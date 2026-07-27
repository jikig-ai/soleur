#!/usr/bin/env bash
#
# (#6982, W4/W5) Weekly bounded maintenance for the git-data bare-repo store.
#
# WHY: replicateToGitData force-pushes per-worktree namespaces at every session end, and
# `--force` ORPHANS the objects the old ref pointed at with nothing to prune them — on a
# 10 GB store (the Hetzner floor, not a capacity estimate) that grows without bound. The
# transport wrapper allows exactly two verbs and all three keys are command=/no-pty, so
# there is no maintenance escape hatch over SSH BY DESIGN; widening that allowlist for a
# scheduled job would be the wrong trade. So maintenance runs host-local as root.
#
# UNREACHABLE OBJECTS ONLY. This is NOT an Art. 17 erasure pathway and must never be
# described as one — erasure is git-data-remove.sh. A reachable object is a user's
# committed work and is never touched here.
#
# Bounding is delegated to systemd (git-data-gc.service): only a cgroup caps peak RSS.
set -uo pipefail

REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"
GIT_DATA_ROOT="${GIT_DATA_ROOT:-/mnt/git-data}"
EMIT="${GIT_DATA_EMIT:-/usr/local/bin/git-data-emit}"
LOCK="${GIT_DATA_GC_LOCK:-/var/lock/git-data-gc.lock}"
# Mirrors bootstrap's pack.windowMemory, passed explicitly so a repack does not depend on
# the system config still being right.
WINDOW_MEMORY="${GIT_DATA_GC_WINDOW_MEMORY:-64m}"
PRUNE_EXPIRE="${GIT_DATA_GC_PRUNE_EXPIRE:-2.weeks.ago}"

log() { echo "[git-data-gc] $*"; }

[[ -d "$REPO_ROOT" ]] || { log "repo root $REPO_ROOT absent — nothing to do"; exit 0; }

# flock on a SHARED lock so this never runs concurrently with a cutover fsck window. -n:
# skipping a weekly run is correct; stacking two repacks on a 4 GB box is not.
exec 9>"$LOCK" || { log "cannot open lock $LOCK"; exit 0; }
if ! flock -n 9; then
  log "another maintenance holder owns $LOCK — skipping this run"
  exit 0
fi

repos=0
failed=0
for repo in "$REPO_ROOT"/*.git; do
  [[ -d "$repo" ]] || continue
  repos=$((repos + 1))
  # Order is load-bearing: expire the reflog FIRST so force-pushed objects stop being
  # reachable-via-reflog, then repack, then prune. Prune first would collect nothing.
  git -C "$repo" reflog expire --expire-unreachable=now --all >/dev/null 2>&1 || failed=$((failed + 1))
  git -C "$repo" repack -adq --window-memory="$WINDOW_MEMORY" >/dev/null 2>&1 || failed=$((failed + 1))
  git -C "$repo" prune --expire="$PRUNE_EXPIRE" >/dev/null 2>&1 || failed=$((failed + 1))
done

disk_pct="$(df --output=pcent "$GIT_DATA_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')"
log "maintenance done: repos=${repos} failures=${failed} disk=${disk_pct:-unknown}%"

# Disk state rides THIS run and the boot-completion emit; there is deliberately no
# 15-minute poller (an earlier design polled the LUKS mount, empty by construction until
# the cutover, while the filesystem that actually fills went unwatched).
#
# NO per-repo identifiers, ever: a repo name is <workspace_id>.git and workspace_id IS the
# user id. Only aggregate counts leave this host.
if [[ -x "$EMIT" ]]; then
  if [[ "$failed" -gt 0 ]]; then
    "$EMIT" "SOLEUR_GIT_DATA_GC" gc warning "" \
      "repos=${repos}" "failures=${failed}" "disk_pct=${disk_pct:-unknown}" || true
  else
    "$EMIT" "SOLEUR_GIT_DATA_GC" gc info "" \
      "repos=${repos}" "failures=0" "disk_pct=${disk_pct:-unknown}" || true
  fi
fi

# Exit 0 on partial per-repo failures: OnFailure= is reserved for the unit DYING (OOM
# kill, missing binary), the condition worth paging on.
exit 0
