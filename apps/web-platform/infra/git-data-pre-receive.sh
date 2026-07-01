#!/usr/bin/env bash
#
# git-data writer-side CAS fence — `pre-receive` hook (epic #5274 Phase 2, ADR-068 §3).
#
# NOVEL PATTERN — no in-repo precedent for git server-side hooks (Gap 9). This is
# the load-bearing data-integrity invariant of the multi-host /workspaces split:
# the git-data host (the resource server, in Kleppmann's fencing-token model) is
# the ONLY place that can make a stale/GC-paused writer's late push a no-op rather
# than corruption. A generation check *before* the ref write would be TOCTOU; this
# hook does the read-check-write ATOMICALLY under a per-(workspace,worktree) lock,
# inside `pre-receive` so the WHOLE push is rejected before any ref is written.
#
# Mechanism (OQ2 concretization of the plan's recommended form):
#   - The web host holds lease generation N (from acquire_worktree_lease, mig 116)
#     and presents it on every push as TWO push-options:
#         git push --push-option=lease-gen=N --push-option=worktree-id=<id>
#   - The bare repo is per-WORKSPACE ($GIT_DIR); the lock + sidecar are
#     per-(workspace,worktree), so the hook is told which worktree is pushing.
#   - Sidecar `$GIT_DIR/fence/<worktree_id>.gen` holds the monotonic max gen seen.
#   - Under `flock` on `$GIT_DIR/fence/<worktree_id>.lock` (held for the WHOLE push,
#     one read-check-write regardless of how many refs ride the push):
#       * reject (exit 1) if N < stored_max  — a stale writer (strict `<`)
#       * accept if N == stored_max          — idempotent retry of a partial/timed-out
#                                              push (acquire's atomic gen+1 guarantees a
#                                              given gen is held by exactly ONE host, so
#                                              equal never admits a competing writer)
#       * else advance stored_max = max(stored_max, N) and accept.
#
# FAIL-CLOSED CONTRACT (the silent-corruption path this phase exists to prevent):
#   - a push with NO lease-gen OR NO worktree-id push-option is REJECTED (never
#     treated as gen 0 / fall-through — that would be fail-OPEN);
#   - a non-integer lease-gen is REJECTED;
#   - an unparseable / partial `.gen` sidecar is REJECTED;
#   - a worktree-id with path-traversal / unsafe chars is REJECTED (it names a file).
#
# At replicas=1 the fence is LIVE but never rejects: the single host re-acquires
# its own lease with a STABLE gen (mig-116 acquire CASE keeps gen on same-host
# refresh), so gen never climbs and no `gen<max` ever arises. It becomes
# load-bearing at Phase 3's second writer. Not dormant — live-but-non-rejecting.
#
# The sidecar + lock MUST live on the persistent git-data volume, never tmpfs — a
# reboot resetting max to 0 would let a stale gen=5 writer beat a fresh 0. The
# bootstrap mounts $GIT_DATA_ROOT on the block volume; bare repos (and thus
# $GIT_DIR/fence) live under it.
#
# Delivered via the web-platform deploy payload (NOT cloud-init) so this
# safety-critical, most-likely-to-iterate artifact stays pipeline-iterable; a
# fail-closed placeholder ships in cloud-init until this lands (git-data-bootstrap.sh).

set -euo pipefail

reject() {
  # stderr from pre-receive is relayed to the pushing client (the web host),
  # which surfaces it via the worktree_lease Sentry slug.
  echo "remote: git-data fence: $1" >&2
  exit 1
}

# Drain stdin (the <old> <new> <ref> lines). The fence is per-(workspace,worktree)
# — one lease-gen per push — so we do not need per-ref data; draining avoids a
# SIGPIPE on the sender.
cat >/dev/null 2>&1 || true

# --- Parse push-options (git sets GIT_PUSH_OPTION_COUNT + GIT_PUSH_OPTION_<i>) ---
count="${GIT_PUSH_OPTION_COUNT:-0}"
case "$count" in (*[!0-9]*|"") count=0 ;; esac

lease_gen=""
worktree_id=""
i=0
while [ "$i" -lt "$count" ]; do
  opt_var="GIT_PUSH_OPTION_${i}"
  opt="${!opt_var-}"
  case "$opt" in
    lease-gen=*) lease_gen="${opt#lease-gen=}" ;;
    worktree-id=*) worktree_id="${opt#worktree-id=}" ;;
  esac
  i=$((i + 1))
done

# --- Fail-closed validation ---
[ -n "$lease_gen" ] || reject "missing lease-gen push-option (fail-closed)"
[ -n "$worktree_id" ] || reject "missing worktree-id push-option (fail-closed)"

case "$lease_gen" in
  (*[!0-9]*|"") reject "lease-gen is not a non-negative integer: '$lease_gen'" ;;
esac

# worktree-id names a sidecar file — it must be an opaque safe token. The web host
# generates it (never user-supplied free-text), but the fence still validates,
# defense-in-depth (CWE-22 path traversal).
case "$worktree_id" in
  (""|.|..) reject "worktree-id is empty or a dot path: '$worktree_id'" ;;
  (*[!A-Za-z0-9._-]*) reject "worktree-id has unsafe characters: '$worktree_id'" ;;
  (*/*) reject "worktree-id contains a slash: '$worktree_id'" ;;
esac

# --- Locate the per-workspace bare repo's fence dir ---
gd="${GIT_DIR:-$(git rev-parse --git-dir 2>/dev/null || echo .)}"
fence_dir="${gd}/fence"
mkdir -p "$fence_dir"
gen_file="${fence_dir}/${worktree_id}.gen"
lock_file="${fence_dir}/${worktree_id}.lock"

# --- Acquire the per-(workspace,worktree) lock for the WHOLE push ---
# Held until the hook exits (fd 9 closes), so a racing push blocks here rather than
# interleaving its read-check-write with ours. Mirrors `flock` use in infra/*.sh.
exec 9>"$lock_file"
flock 9 || reject "could not acquire fence lock for worktree '$worktree_id'"

# --- Read the stored monotonic max (default 0 when absent: first push / post-cutover) ---
stored_max=0
if [ -f "$gen_file" ]; then
  stored_max="$(cat "$gen_file" 2>/dev/null || echo "")"
  case "$stored_max" in
    (*[!0-9]*|"") reject "fence sidecar unparseable: '$stored_max' (fail-closed)" ;;
  esac
fi

# --- CAS: reject a strictly-stale generation (equal gen is an allowed idempotent retry) ---
if [ "$lease_gen" -lt "$stored_max" ]; then
  reject "stale lease generation ${lease_gen} < stored max ${stored_max} — rejected"
fi

# --- Advance the monotonic max atomically (tmp + mv under the held lock) ---
new_max="$lease_gen"
if [ "$stored_max" -gt "$new_max" ]; then
  new_max="$stored_max"
fi
tmp="$(mktemp "${fence_dir}/.${worktree_id}.gen.XXXXXX")"
printf '%s\n' "$new_max" >"$tmp"
mv -f "$tmp" "$gen_file"

exit 0
