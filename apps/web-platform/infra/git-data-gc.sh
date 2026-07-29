#!/usr/bin/env bash
#
# (#6982, W4/W5) Weekly bounded maintenance for the git-data bare-repo store.
#
# WHY: replicateToGitData force-pushes per-worktree namespaces at every session end, and
# `--force` ORPHANS the old objects with nothing to prune them — on a 10 GB store that grows
# without bound. There is no maintenance escape hatch over SSH by design, so this runs
# host-local as root. UNREACHABLE OBJECTS ONLY: NOT an Art. 17 pathway (that is
# git-data-remove.sh). Bounding is delegated to systemd — only a cgroup caps peak RSS.
set -uo pipefail

REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"
GIT_DATA_ROOT="${GIT_DATA_ROOT:-/mnt/git-data}"
EMIT="${GIT_DATA_EMIT:-/usr/local/bin/git-data-emit}"
LOCK="${GIT_DATA_GC_LOCK:-/var/lock/git-data-gc.lock}"
# Mirrors bootstrap's pack.windowMemory, passed explicitly so a repack does not depend on
# the system config still being right.
WINDOW_MEMORY="${GIT_DATA_GC_WINDOW_MEMORY:-64m}"
PRUNE_EXPIRE="${GIT_DATA_GC_PRUNE_EXPIRE:-2.weeks.ago}"
# B8: per-repo wall-clock bound. Without it ONE pathological repo can consume the unit's whole
# TimeoutStartSec, and every repo after it in glob order is silently never maintained.
REPO_TIMEOUT="${GIT_DATA_GC_REPO_TIMEOUT:-900}"

log() { echo "[git-data-gc] $*"; }

# MOUNT FIRST, and emit on absence rather than exiting 0 quietly. /mnt/git-data exists as
# a plain directory whether or not the volume is attached (`mkdir -p` in runcmd, fstab
# `nofail`, `mount … || true`), so without this guard `df` below silently reports the ROOT
# filesystem's usage and it ships as the store's. And a bare `exit 0` on a missing repo
# root makes a VANISHED STORE indistinguishable off-box from a healthy weekly run: the
# unit succeeds, OnFailure never fires, and nothing is emitted.
if ! mountpoint -q "$GIT_DATA_ROOT" 2>/dev/null; then
  log "FATAL: $GIT_DATA_ROOT is not a mountpoint — the store volume is not attached"
  [[ -x "$EMIT" ]] && "$EMIT" "SOLEUR_GIT_DATA_GC store volume not mounted" gc fatal "" \
    "mount=absent" || true
  exit 1
fi
if [[ ! -d "$REPO_ROOT" ]]; then
  log "FATAL: repo root $REPO_ROOT absent on a mounted volume"
  [[ -x "$EMIT" ]] && "$EMIT" "SOLEUR_GIT_DATA_GC repo root absent" gc fatal "" \
    "repo_root=absent" || true
  exit 1
fi

# flock on a SHARED lock so this never runs concurrently with a cutover fsck window. -n:
# skipping a weekly run is correct; stacking two repacks on a 4 GB box is not.
# B10: both arms EMIT. A bare `exit 0` here is the anti-pattern this file argues against one
# stanza above: a run that never happened is indistinguishable off-host from a clean one, and
# if the lock is permanently wedged the store is never maintained again while every weekly
# unit reports success.
exec 9>"$LOCK" || {
  log "cannot open lock $LOCK"
  [ -x "$EMIT" ] && "$EMIT" "SOLEUR_GIT_DATA_GC lock unopenable" gc warning "" \
    "lock=unopenable" || true
  exit 0
}
if ! flock -n 9; then
  log "another maintenance holder owns $LOCK — skipping this run"
  [ -x "$EMIT" ] && "$EMIT" "SOLEUR_GIT_DATA_GC run skipped (lock held)" gc info "" \
    "lock=held" || true
  exit 0
fi

ERRLOG="$(mktemp -t git-data-gc-err.XXXXXXXX)"

repos=0
failed=0
completed=0
emitted=0

# B8: THE SUMMARY EMITS FROM A TRAP, so a kill still reports. MemoryMax=1G and
# TimeoutStartSec are real outcomes on a 4 GB box, and a SIGKILL/SIGTERM part-way through the
# glob used to destroy the loop AND the emit together: the unit died, OnFailure fired a bare
# "unit failed", and nothing said HOW FAR it got — so every repo after the offender in glob
# order was silently unmaintained, indefinitely, with no signal naming the shortfall.
#
# Emitting `repos=` from the trap makes that shortfall visible: a run killed at repo 12 of 300
# reports 12, and the gap against the previous run is the alarm. `emitted` guards the
# double-fire when TERM is followed by EXIT.
summarize() {
  [ "$emitted" -eq 1 ] && return 0
  emitted=1
  read -r disk_pct inode_pct < <(df --output=pcent,ipcent "$GIT_DATA_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9 \n') || true
  log "maintenance done: repos=${repos} failures=${failed} complete=${completed} disk=${disk_pct:-unknown}% inodes=${inode_pct:-unknown}%"
  # NO per-repo identifiers, ever: a repo name is <workspace_id>.git and workspace_id IS the
  # user id. Only aggregate counts leave this host.
  if [ -x "$EMIT" ]; then
    if [ "$completed" -ne 1 ]; then
      "$EMIT" "SOLEUR_GIT_DATA_GC run did not complete" gc_report warning "$ERRLOG" \
        "repos=${repos}" "failures=${failed}" "complete=no" \
        "disk_pct=${disk_pct:-unknown}" "inode_pct=${inode_pct:-unknown}" || true
    elif [ "$failed" -gt 0 ]; then
      "$EMIT" "SOLEUR_GIT_DATA_GC" gc_report warning "$ERRLOG" \
        "repos=${repos}" "failures=${failed}" "complete=yes" \
        "disk_pct=${disk_pct:-unknown}" "inode_pct=${inode_pct:-unknown}" || true
    else
      "$EMIT" "SOLEUR_GIT_DATA_GC" gc_report info "" \
        "repos=${repos}" "failures=0" "complete=yes" \
        "disk_pct=${disk_pct:-unknown}" "inode_pct=${inode_pct:-unknown}" || true
    fi
  fi
  rm -f "$ERRLOG"
}
trap summarize EXIT
trap 'summarize; exit 143' TERM
trap 'summarize; exit 130' INT
for repo in "$REPO_ROOT"/*.git; do
  [[ -d "$repo" ]] || continue
  repos=$((repos + 1))
  # `-A`, NOT `-a` — a data-loss boundary. `repack -a -d` deletes the redundant packs in the
  # same step, so an object unreachable at scan time dies immediately and `prune --expire`
  # never applies its grace. `-A` keeps them and `--unpack-unreachable=<grace>` explodes the
  # recent ones to loose, leaving the LATER prune as the single thing deciding by age (how
  # `git gc` itself works). It also closes a concurrency window: git-receive-pack takes no
  # lock, so a push can update its ref AFTER repack's scan — under `-a -d` its objects are
  # dropped and the ref points at nothing. Bare repos default core.logAllRefUpdates=false,
  # so there is no reflog net. Grace == PRUNE_EXPIRE by construction.
  # Capture stderr rather than discarding it: on a host with no shell it is the only way to
  # learn WHY a repo failed (e.g. "detected dubious ownership" if safe.directory regressed).
  # It rides the emit's detail arg, which redacts internally.
  timeout -k 30 "$REPO_TIMEOUT" git -C "$repo" reflog expire --expire-unreachable=now --all >/dev/null 2>>"$ERRLOG" || failed=$((failed + 1))
  # --threads: re-passed for the SAME reason as --window-memory (so a repack does not depend
  # on the system config still being right) -- and it matters MORE, not less. The bootstrap
  # calls parallel delta search "the actual OOM path" because it multiplies the window budget
  # by the thread count, so re-passing the lesser control and trusting the config for the
  # greater one had it exactly backwards.
  timeout -k 30 "$REPO_TIMEOUT" git -C "$repo" repack -A -d -q --threads=1 \
    --window-memory="$WINDOW_MEMORY" \
    --unpack-unreachable="$PRUNE_EXPIRE" >/dev/null 2>>"$ERRLOG" || failed=$((failed + 1))
  timeout -k 30 "$REPO_TIMEOUT" git -C "$repo" prune --expire="$PRUNE_EXPIRE" >/dev/null 2>>"$ERRLOG" || failed=$((failed + 1))
done

completed=1

# Exit 0 on partial per-repo failures: OnFailure= is reserved for the unit DYING (OOM
# kill, missing binary), the condition worth paging on.
exit 0
