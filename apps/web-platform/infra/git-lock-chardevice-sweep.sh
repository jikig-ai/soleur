#!/usr/bin/env bash
# git-lock-chardevice-sweep.sh — durable substrate remediation for the #5934
# Concierge worktree-creation wedge (companion to the in-session self-heal in
# #5912 / worktree-manager.sh `atomic_git_config`).
#
# ROOT CAUSE (ADR-081): the container filesystem substrate can leave a residual
# CHARACTER-DEVICE inode at a historical `.git/config.lock` on the persistent
# host volume (`/mnt/data/workspaces`, `-v … :/workspaces` per ci-deploy.sh:899).
# git's open(O_CREAT|O_EXCL) EEXISTs against ANY pre-existing inode, so a masked
# config.lock permanently wedges worktree creation with no in-sandbox recourse
# (the blind agent has neither privilege nor a non-`rm`-able path). This sweep is
# the privileged, NON-BLIND removal the wedge needs — it clears any char-device
# config-write lock BEFORE an agent session uses the repo.
#
# WHY host-side + quiescent: the bare repos live on the host bind-mount
# `/mnt/data/workspaces` (NOT the container overlay2 upper — overlay2 does not
# overlay the bind mount, so a Dockerfile-layer sweep would never see the node).
# It runs ONLY in a quiescent window (first-boot / container-entrypoint, before the
# agent runtime starts) — NEVER a periodic timer against a live volume. Ordering
# is the concurrency-safety mechanism: under a future ADR-068 shared-git-data
# topology the volume is not quiescent, so a periodic sweep there would race a live
# writer. Do NOT add a timer. (ADR-068 `/mnt/git-data` is the not-yet-GA multi-host
# future — deliberately NOT swept here; `replicas=1` is still in force.)
#
# SCOPE (idempotent, no-op when clean): ONLY `config.lock` / `config.worktree.lock`
# that are CHARACTER DEVICES (`test -c`), depth-bounded under KNOWN workspace roots.
# NEVER a regular lock (that stays the in-sandbox age-guarded self-heal's job) and
# NEVER index.lock / HEAD.lock / per-worktree locks (different, live-clobber class —
# same scoping rationale as sweep_stale_git_locks in worktree-manager.sh).
#
# rdev-aware removal (ADR-081 discriminators): a PLAIN char-special inode is cleared
# with `rm -f` (root can, unlike the sandboxed agent); a BIND-MOUNTED device node
# (e.g. a bound /dev/null, rdev 1:3) returns EBUSY on unlink — it MUST be `umount`ed
# FIRST, else the sweep silently "succeeds" while the wedge persists.
#
# Observability (no-SSH): one structured SOLEUR_CHARDEV_SWEEP_* marker per node +
# a JSON state file readable via the cat-*-state.sh pattern; a failure to remove a
# detected node is LOUD, never silent (cq-silent-fallback-must-mirror-to-sentry).
#
# Test seams: GIT_LOCK_SWEEP_ROOT, GIT_LOCK_SWEEP_STATE, GIT_LOCK_SWEEP_MAXDEPTH,
# GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS (colon-list of paths to treat as mountpoints,
# so the umount-then-rm branch is testable without CAP_SYS_ADMIN); mock umount/rm
# on PATH. The `BASH_SOURCE == $0` guard means main() does NOT run on source.
set -euo pipefail

readonly LOG_TAG="git-lock-chardevice-sweep"
ROOT="${GIT_LOCK_SWEEP_ROOT:-/mnt/data/workspaces}"
STATE_FILE="${GIT_LOCK_SWEEP_STATE:-/var/lock/git-lock-chardevice-sweep.state}"
# Depth 3 covers a bare repo (`<workspace>/config.lock`) AND a working tree
# (`<workspace>/.git/config.lock`); `-type c` makes the walk a cheap kernel stat
# filter that yields only the (rare) device node. Bounded — NOT an unbounded find.
MAXDEPTH="${GIT_LOCK_SWEEP_MAXDEPTH:-3}"
START_TS=$(date +%s)

# Emit a structured, grep-able, no-SSH marker (STDOUT + host journal via logger).
marker() {
  echo "$1"
  logger -t "$LOG_TAG" "$1" 2>/dev/null || true
}

write_state() {
  local exit_code="$1" removed="$2" failed="$3"
  # jq when available (matches the inngest-wiped-volume-verify state shape); a
  # dependency-free fallback keeps the liveness marker present on a jq-less host.
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --argjson ec "$exit_code" --argjson rm "$removed" --argjson fl "$failed" \
      --argjson st "$START_TS" --argjson et "$(date +%s)" \
      --arg comp "$LOG_TAG" \
      '{exit_code:$ec, removed:$rm, failed:$fl, component:$comp, start_ts:$st, end_ts:$et}' \
      > "$STATE_FILE" 2>/dev/null || true
  else
    printf '{"exit_code":%s,"removed":%s,"failed":%s,"component":"%s","start_ts":%s,"end_ts":%s}\n' \
      "$exit_code" "$removed" "$failed" "$LOG_TAG" "$START_TS" "$(date +%s)" \
      > "$STATE_FILE" 2>/dev/null || true
  fi
}

# is_mountpoint <path> — true iff the path is a mount root (a bind-mounted device
# node). Uses `stat -c%m` == realpath (the findmnt-free idiom from
# worktree-manager.sh). The FORCE_MOUNTPOINTS seam lets a test exercise the
# umount-then-rm branch with a regular-file stand-in (no CAP_SYS_ADMIN needed).
is_mountpoint() {
  local p="$1" rp forced
  if [[ -n "${GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS:-}" ]]; then
    IFS=':' read -ra forced <<< "$GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS"
    local f
    for f in "${forced[@]}"; do [[ "$f" == "$p" ]] && return 0; done
  fi
  rp=$(realpath -- "$p" 2>/dev/null) || return 1
  [[ "$(stat -c%m -- "$rp" 2>/dev/null)" == "$rp" ]]
}

# discover_targets — NUL-separated char-device config-write locks under ROOT,
# depth-bounded. Returns nothing (rc 0) when ROOT is absent or clean.
discover_targets() {
  [[ -d "$ROOT" ]] || return 0
  find "$ROOT" -mindepth 1 -maxdepth "$MAXDEPTH" -type c \
    \( -name config.lock -o -name config.worktree.lock \) -print0 2>/dev/null || true
}

# remediate_node <path> — clear ONE confirmed char-device lock. rdev-aware:
# umount-before-rm for a bind-mounted node, plain rm otherwise. rc 0 on removal,
# rc 1 (LOUD marker) on any failure. Assumes <path> is already a confirmed target
# (discovery owns the -type c / name filter), so it is directly seam-testable.
remediate_node() {
  local path="$1" rdev branch
  rdev=$(stat -c '%t:%T' -- "$path" 2>/dev/null || echo unknown)
  if is_mountpoint "$path"; then
    branch=umount-then-rm
    # `rm`/`unlink` on a bind mount → EBUSY; umount FIRST. Lazy umount (-l) is the
    # fallback for a busy node so a transient open handle does not defeat the sweep.
    if ! umount "$path" 2>/dev/null && ! umount -l "$path" 2>/dev/null; then
      marker "SOLEUR_CHARDEV_SWEEP_FAILED path=$path rdev=$rdev branch=$branch reason=umount-failed"
      return 1
    fi
  else
    branch=rm
  fi
  if ! rm -f -- "$path" 2>/dev/null; then
    marker "SOLEUR_CHARDEV_SWEEP_FAILED path=$path rdev=$rdev branch=$branch reason=rm-failed"
    return 1
  fi
  marker "SOLEUR_CHARDEV_SWEEP_REMOVED path=$path rdev=$rdev branch=$branch"
  return 0
}

main() {
  local removed=0 failed=0 path
  while IFS= read -r -d '' path; do
    if remediate_node "$path"; then removed=$(( removed + 1 )); else failed=$(( failed + 1 )); fi
  done < <(discover_targets)
  write_state "$(( failed == 0 ? 0 : 1 ))" "$removed" "$failed"
  marker "SOLEUR_CHARDEV_SWEEP_DONE root=$ROOT removed=$removed failed=$failed"
  (( failed == 0 ))   # non-zero iff a detected node could not be cleared
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
