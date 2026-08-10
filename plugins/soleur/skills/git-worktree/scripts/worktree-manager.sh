#!/usr/bin/env bash

# Git Worktree Manager
# Handles creating, listing, switching, and cleaning up Git worktrees
# KISS principle: Simple, interactive, opinionated
#
# BARE REPO NOTE (rewritten for #7394 — the three claims here were all stale, and
# one was inverted in a way that hid the defect for months):
#
# This repo uses core.bare=true in the SHARED config with extensions.worktreeConfig
# DISABLED. That is the state git itself produces, and it is the state this script
# now enforces. The extension is NOT set, so `core.bare` is NOT resolved per-worktree.
#
# The retired claim was: "the per-worktree config (.git/config.worktree) holds
# core.bare=true ONLY for the bare root; linked worktrees inherit core.bare=false by
# default." Measured on git 2.53.0, the inheritance direction is the OPPOSITE. With
# extensions.worktreeConfig ON, a linked worktree that does not set `bare = false` in
# its OWN config.worktree inherits `true` from the shared config and is treated as
# BARE — and `git worktree add` writes no config.worktree at all, so every worktree
# starts out in exactly that state. Believing the inverted version is why the round-6
# guard's author saw no risk in skipping the surgery on a `.git` DIRECTORY: on this
# repo's bare-repo-in-`.git` layout that skip made the whole function dead code.
#
# On-disk files at the bare root are never updated by git -- they become stale after
# every merge. The IS_BARE flag (computed at init) guards all working-tree-dependent
# operations. If this script crashes with "must be run in a work tree", the on-disk
# copy is stale. Run from a worktree instead, or use: worktree-manager.sh sync-bare

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resolve this script's own directory so callers inside worktrees can reference it
# without knowing where plugins/ lives relative to their CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source session-state helpers (locks + leases + headless visibility). The
# live copy lives in the worktree filesystem; SCRIPT_DIR resolves to
# plugins/soleur/skills/git-worktree/scripts/, so 5 levels up is the worktree
# root. When invoked from a worktree that predates this file (legacy state),
# the file is missing and we degrade to no-op stubs so the script keeps
# running — old worktrees lose lock/lease protection but don't crash.
_SS_LIB="$SCRIPT_DIR/../../../../../.claude/hooks/lib/session-state.sh"
# Read at the reap decision point so the skip REASON is mode-accurate: with the
# stub in place every worktree reads "leased", and reporting that as an observed
# active lease would assert something the gate cannot know.
_SS_LIB_MISSING=false
if [[ -f "$_SS_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_SS_LIB"
else
  # Loud one-shot warn so an operator (or CI log scrape) sees that lease
  # protection is OFF in this worktree. Silent stubs would mask the
  # 2026-04-21 regression class the lease layer was added to prevent.
  _SS_LIB_MISSING=true
  # stdout, not stderr: stderr is invisible under `claude --bg`, which is the
  # mode cleanup-merged actually runs in (see the note at the reap loop).
  echo "SOLEUR_WORKTREE_LEASE_LIB_MISSING path=$_SS_LIB reason=fail-closed-no-reap"
  echo "[warn] session-state.sh missing at $_SS_LIB — lease/lock protection disabled in this worktree." >&2
  echo "[warn] cleanup-merged will REFUSE to reap any worktree (fail-closed): with no lease" >&2
  echo "[warn] library there is no way to tell a live session from an abandoned one." >&2
  echo "[warn] Restore it with: git checkout origin/main -- .claude/hooks/lib/session-state.sh" >&2
  acquire_lock() { return 0; }
  release_lock() { return 0; }
  acquire_lease() { return 0; }
  release_lease() { return 0; }
  # FAIL CLOSED (#5454). This used to `return 1` — "no lease is active" — which
  # told cleanup-merged that EVERY worktree was free to reap at the exact moment
  # we had just admitted we cannot measure whether one is in use. That is a
  # fail-open default on a destructive, unrecoverable operation (it deletes the
  # worktree, the local branch, AND the remote branch, and closes the PR).
  #
  # Returning 0 inverts the default: with no lease library, every worktree reads
  # as held and nothing is reaped. The cost is that cleanup silently stops doing
  # anything in a legacy worktree — which the loud warnings above surface, and
  # which is trivially recoverable by hand. The old cost was losing live work.
  is_lease_active() { return 0; }
  sweep_orphan_leases() { return 0; }
  _register_lease_release_trap() { return 0; }
  headless_or_stderr() { echo "[$1] $2" >&2; }
fi

# Auto-confirm flag (--yes skips all interactive prompts)
YES_FLAG=false

# When true, `create` also fast-forwards the local <from> ref (legacy behavior).
# Default false: new worktrees base on refs/remotes/origin/<from> directly so
# `create` no longer fails when a sibling worktree holds <from> checked out (#3741).
UPDATE_LOCAL_MAIN=false

# Get repo root and detect bare repo (single subprocess for both)
# IS_BARE: true when the parent/root repo is bare (affects fetch strategy, file sync)
# IS_IN_WORKTREE: true when running from inside a worktree (has a working tree)
# Must also detect when running from a worktree whose parent repo is bare,
# since git rev-parse --is-bare-repository returns false inside worktrees.
IS_BARE=false
IS_IN_WORKTREE=false
if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  IS_IN_WORKTREE=true
fi
# Concierge repo-readiness gate: fail LOUD when there is no git repository at
# all. In the Soleur web (Concierge) env the workspace is /workspaces/<id>; a
# connected repo is cloned in the background (or self-healed at session start),
# so a session that opens during the clone window — or after a clone failure —
# lands in a repo-less dir. Without this guard the `else` branch below dies
# silently on `git rev-parse --show-toplevel` under `set -e`, giving the
# calling skill (go/one-shot) no clear signal; the agent then improvises dozens
# of varied exploration commands (which evade the narrow cd-&&-pwd-loop runtime
# detector from #5313) until the session hangs. Emit a distinct, machine-
# detectable marker + non-zero exit so the skill stops with an honest, no-wait
# message instead. Runs before the bare/worktree branch so every subcommand
# (create, cleanup-merged, list, …) fails the same clear way in a repo-less env.
if [[ "$IS_IN_WORKTREE" != "true" \
      && "$(git rev-parse --is-bare-repository 2>/dev/null)" != "true" ]]; then
  echo -e "${RED}Error: No git repository in this workspace.${NC}" >&2
  echo "NO_GIT_REPOSITORY: cannot run a worktree operation — the workspace has no git checkout. If your repository is still being set up, try again in a moment; if it keeps failing, reconnect your repository." >&2
  exit 3
fi
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  IS_BARE=true
  _git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null)
  if [[ "$_git_dir" == */.git ]]; then
    GIT_ROOT="${_git_dir%/.git}"
  else
    GIT_ROOT="$_git_dir"
  fi
else
  GIT_ROOT=$(git rev-parse --show-toplevel)
  # Check if we're in a worktree of a bare repo
  _common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  # #5934 round-3: under the Concierge char-device config mask (and, benignly, at the
  # toplevel of ANY normal clone) git returns the RELATIVE string ".git" for
  # --git-common-dir. Left relative, the `*/.git` strip below cannot match (no slash) and
  # GIT_ROOT collapses to the relative ".git" — which makes WORKTREE_DIR ".git/.worktrees"
  # and detonates verify_worktree_created's absolute-vs-relative --show-toplevel compare
  # ("Worktree path mismatch"). Resolve to ABSOLUTE here, BEFORE the strip, so the strip
  # yields the true absolute workspace ROOT (sibling .worktrees) rather than a path buried
  # inside .git.
  if [[ -n "$_common_dir" && "$_common_dir" != /* ]]; then
    _common_dir="$(cd "$_common_dir" 2>/dev/null && pwd)" || _common_dir=""
  fi
  if [[ -n "$_common_dir" ]] && git -C "$_common_dir" rev-parse --is-bare-repository 2>/dev/null | grep -q true; then
    IS_BARE=true
    # GIT_ROOT should point to the bare repo, not the worktree
    if [[ "$_common_dir" == */.git ]]; then
      GIT_ROOT="${_common_dir%/.git}"
    else
      GIT_ROOT="$_common_dir"
    fi
  fi
fi
# #5934 round-3 defense-in-depth: GIT_ROOT MUST be absolute before it feeds WORKTREE_DIR
# (and every other consumer: ensure_bare_config, copy_env_files, verify_worktree_created).
# Any branch above can hand back a RELATIVE root (mask-degraded --show-toplevel /
# --git-common-dir) or an EMPTY one; a relative WORKTREE_DIR then mismatches git's absolute
# --show-toplevel in verify. Normalize a relative root against $PWD (create runs from the
# workspace root); if it resolves empty, fall back to $PWD when that IS a real checkout. A
# no-op for an already-absolute root (the common, healthy case).
ensure_git_root_absolute() {
  if [[ -n "$GIT_ROOT" && "$GIT_ROOT" != /* ]]; then
    GIT_ROOT="$(cd "$GIT_ROOT" 2>/dev/null && pwd)" || GIT_ROOT=""
  fi
  if [[ -z "$GIT_ROOT" && -d "$PWD/.git" ]]; then
    GIT_ROOT="$PWD"
  fi
}
# NOTE (#7394): the `ensure_git_root_absolute` CALL and the `WORKTREE_DIR` assignment
# used to sit here. They now run further down, immediately after the detection-time
# self-heal (`_selfheal_bare_worktree_override`), so they are computed ONCE against
# HEALED state. Order is what matters, not position: on a poisoned worktree the
# pre-heal `GIT_ROOT` resolves to `<common-dir>/worktrees/<name>`, so assigning
# `WORKTREE_DIR` before the heal yields `<root>/.git/worktrees/<name>/.worktrees` and
# every subsequent `create` lands inside the admin dir. The self-heal has to live
# below because it writes through `atomic_git_config`, which is not defined until
# later in this file — bash defines functions as execution reaches them.

# Exit with error if running at the bare repo root (no working tree available).
# Allows execution from worktrees of bare repos (IS_BARE=true but IS_IN_WORKTREE=true).
require_working_tree() {
  if [[ "$IS_BARE" == "true" && "$IS_IN_WORKTREE" != "true" ]]; then
    echo -e "${RED}Error: Cannot run from bare repo root (no working tree available).${NC}"
    echo -e "${YELLOW}Run from an existing worktree, or use: git worktree add .worktrees/<name> -b <branch> main${NC}"
    exit 1
  fi
}

# Map GNU `rm` strerror text -> a stable errno label for the diagnostic sentinel.
# (GNU rm prints "rm: cannot remove '<f>': <strerror>"; we match the strerror.)
_rm_errno() {
  case "$1" in
    *"Device or resource busy"*) echo "EBUSY" ;;
    *"Operation not permitted"*) echo "EPERM" ;;
    *"Permission denied"*)       echo "EACCES" ;;
    *"Read-only file system"*)   echo "EROFS" ;;
    *)                           echo "OTHER" ;;
  esac
}

# classify_lock_node <path> — prints "<type> <is_mp>" for <path> to stdout, where
# <type> is symlink/chardevice/mount/dir/regular/other, and returns 0; or returns
# 1 with no output if <path> is absent. Single source of truth for the type-precedence
# check (symlink FIRST because -e/-f/-d all dereference symlinks; char-device
# BEFORE mountpoint BEFORE dir BEFORE regular — a bound /dev/null is BOTH -c and
# a mountpoint, and a mountpoint is also a dir) shared by BOTH
# sweep_stale_git_locks and _config_lock_wedged (#6186 — the two used to run
# independent, disagreeing checks: a bind-mounted REGULAR config.lock passes
# _config_lock_wedged's own `-f` test as "regular"/not-wedged, while the sweep's
# mountpoint check classified the SAME node "mount"/non-regular-lock).
#
# Output contract: ONE line, two space-separated fields — `<type> <is_mp>` where
# <is_mp> is "true"/"false" — so a caller needing the mountpoint flag (the
# sweep's `mount=` attribute) doesn't recompute `stat -c%m`. The flag is part of
# STDOUT, deliberately NOT a global: every call site is a command substitution
# (`ftype=$(classify_lock_node …)`), which runs the function in a SUBSHELL, so a
# global assignment here is discarded on subshell exit and the parent reads it
# unset — fatal under this script's `set -u`. Callers split with `read -r`.
# GNU-only stat, consistent with the rest of this file.
classify_lock_node() {
  local path="$1" rp is_mp=false
  if [[ -L "$path" ]]; then
    echo "symlink $is_mp"
    return 0
  fi
  [[ -e "$path" ]] || return 1
  # `stat -c%m` prints the file's mount root; == its own realpath iff the path
  # IS a mountpoint. (Do NOT use bare `findmnt -T`: it exits 0 + prints the
  # containing-fs SOURCE for every existing path and never yields "none".)
  rp=$(realpath -- "$path" 2>/dev/null) || rp=""
  if [[ -n "$rp" && "$(stat -c%m -- "$rp" 2>/dev/null)" == "$rp" ]]; then
    is_mp=true
  fi
  if [[ -c "$path" ]]; then
    echo "chardevice $is_mp"
  elif [[ "$is_mp" == true ]]; then
    echo "mount $is_mp"
  elif [[ -d "$path" ]]; then
    echo "dir $is_mp"
  elif [[ -f "$path" ]]; then
    echo "regular $is_mp"
  else
    echo "other $is_mp"
  fi
  return 0
}

# Instrument + self-heal the stale git config-write locks that wedge worktree
# creation (e.g., the 2026-07-01 seccomp outage killed git under `unshare` EPERM,
# leaving `.git/config.lock` on the mounted volume; every later `git config` write
# then fails EEXIST — "could not lock config file …: File exists" — forever).
#
# The Concierge agent-sandbox is a BLIND surface (no interactive ls/stat/findmnt,
# and asking the operator is a hard-rule violation), so this sweep IS the only
# diagnostic instrument. For EVERY present lock it emits one grep-able
# SOLEUR_GIT_LOCK_DIAG line on STDOUT (the stream the orchestrating agent greps —
# stderr is invisible under `claude --bg`, mirroring the SOLEUR_FEATURE_PUSH_FAILED
# precedent below) carrying type/owner/perms/mtime/age/mount. It then:
#   - auto-removes ONLY a stale REGULAR lock (a config.lock is created by git via
#     open(O_CREAT|O_EXCL) — always a regular file), age-guarded so an in-flight
#     sub-second writer is never clobbered; clock-skew guard preserves future-dated;
#   - on a non-regular lock (dir/symlink/mount) OR a regular lock whose rm fails
#     (EBUSY/EPERM/EACCES/EROFS), emits a loud SOLEUR_GIT_LOCK_UNREMOVABLE line with
#     the errno/reason and does NOT proceed — it never marches into the doomed
#     `git config` write. Removal of non-regular locks is deferred to the targeted
#     fix this probe informs (auto-`rm -rf` on a blind surface is out of scope).
#
# Returns non-zero iff a config-write lock remained present-and-unremovable, so
# ensure_bare_config can short-circuit before the EEXIST write. GNU-only stat
# (Linux containers + CI ubuntu + dev; mirrors the existing GNU `stat -c%s`).
# Idempotent; safe for parallel sessions — the age-guard, not a flock, is the
# safety mechanism. Every capture is set -e-safe (`|| default` / `if !`) so an
# abort never pre-empts the loud sentinel on the exact case it exists for.
sweep_stale_git_locks() {
  local git_dir="$1"
  local threshold="${2:-60}"   # seconds
  [[ -d "$git_dir" ]] || return 0
  local now lock path mtime age swept=0 unremovable=0
  local ftype owner perms mount rm_err rm_rc rdev whiteout is_mp classify_out
  now=$(date +%s)
  # Scope: ONLY the config-write locks (`config.lock`, `config.worktree.lock`) —
  # the confirmed EEXIST wedge that blocks ensure_bare_config's writes below.
  # Deliberately NOT index.lock / HEAD.lock: on a NON-bare git_dir those are the
  # LIVE working-tree locks a concurrent >60s commit/checkout/rebase legitimately
  # holds (removing one mid-op tears that tenant's index), and they never block a
  # `git config` write, so they add live-clobber risk with zero wedge-fix value.
  # Also NOT the per-worktree lock dirs (.git/worktrees/*/index.lock) — a
  # different failure class (a wedged checkout/rebase) with a larger blast radius.
  for lock in config.lock config.worktree.lock; do
    path="$git_dir/$lock"
    # Node classification is unified in classify_lock_node() (#6186, shared with
    # _config_lock_wedged) so both detectors agree on every node type. It emits
    # "<type> <is_mp>" on one line; split both fields out of the SAME call so the
    # mountpoint flag survives the command substitution's subshell.
    if ! classify_out=$(classify_lock_node "$path"); then
      continue   # missing: nothing present to diagnose
    fi
    read -r ftype is_mp <<<"$classify_out"

    owner=$(stat -c '%u:%g' -- "$path" 2>/dev/null) || owner=unknown
    perms=$(stat -c '%a' -- "$path" 2>/dev/null) || perms=unknown
    mtime=$(stat -c '%Y' -- "$path" 2>/dev/null) || mtime=unknown
    age=unknown
    # Numeric guard: a non-numeric mtime flowing into $(( )) aborts under set -e.
    if [[ "$mtime" =~ ^[0-9]+$ ]]; then age=$(( now - mtime )); fi
    # rdev — GNU stat hex major:minor of a device node; the #5934 substrate
    # discriminator (kernel-grounded, ADR-081): `1:3` ⇒ a bound /dev/null (Phase-2
    # must umount before rm); `0:0` ⇒ an overlay whiteout; other non-zero ⇒ a real
    # mknod device (`rm` clears it). `none` for every non-device type.
    rdev=none
    if [[ "$ftype" == "chardevice" ]]; then
      rdev=$(stat -c '%t:%T' -- "$path" 2>/dev/null) || rdev=unknown
    fi
    mount=none
    if [[ "$ftype" == "mount" ]]; then
      if command -v findmnt >/dev/null 2>&1; then
        mount=$(findmnt -n -o SOURCE -T "$path" 2>/dev/null) || mount=unknown
      else
        mount=findmnt-unavailable
      fi
    elif [[ "$ftype" == "chardevice" && "$is_mp" == true ]]; then
      mount=mountpoint   # bound device node → Phase-2 sweep umounts before rm
    fi
    # Overlay-whiteout alternate form: a ZERO-SIZE REGULAR file bearing the
    # trusted.overlay.whiteout xattr is semantically a whiteout, not an ordinary
    # stale lock — so it must NOT be auto-rm'd as one below. Probe with getfattr when
    # available. NOTE: reading a `trusted.*` xattr needs CAP_SYS_ADMIN, so on the
    # unprivileged blind sandbox this reliably reports `no` (unprobeable); the probe
    # earns its keep under the privileged Phase-2 sweep and in root-run forensics.
    whiteout=no
    if [[ "$ftype" == "regular" ]] && command -v getfattr >/dev/null 2>&1; then
      if getfattr -n trusted.overlay.whiteout --only-values -- "$path" >/dev/null 2>&1; then
        whiteout=yes
      fi
    fi
    # Plain, color-free, STDOUT — color would break the agent's grep.
    echo "SOLEUR_GIT_LOCK_DIAG file=$lock type=$ftype owner=$owner perms=$perms mtime=$mtime age=$age mount=$mount rdev=$rdev whiteout=$whiteout"

    if [[ "$ftype" == "regular" && "$whiteout" != "yes" ]]; then
      # In-flight-writer safety applies ONLY to a regular lock (a real git writer
      # holds a regular config.lock for single-digit ms): remove it only once stale
      # (age >= threshold); fresh AND future-dated (clock skew) are left untouched —
      # the DIAG line above already surfaced them. Arithmetic nested in `if` so a
      # false `(( ))` never trips set -e (mirrors cleanup_merged_worktrees).
      if [[ "$age" =~ ^[0-9]+$ ]] && (( age >= threshold )); then
        rm_err=""; rm_rc=0
        # 2>&1 >/dev/null order is load-bearing: capture stderr, discard stdout.
        # LC_ALL=C pins strerror to English so _rm_errno maps the label reliably
        # under a non-C operator/CI locale (else every failure degrades to OTHER).
        rm_err=$(LC_ALL=C rm -f -- "$path" 2>&1 >/dev/null) || rm_rc=$?
        if (( rm_rc == 0 )); then
          swept=$(( swept + 1 ))   # assignment form, NOT (( swept++ )) — old value 0 -> rc 1 -> set -e abort
        else
          unremovable=1
          echo "SOLEUR_GIT_LOCK_UNREMOVABLE file=$lock type=regular errno=$(_rm_errno "$rm_err") reason=rm-failed hint=\"git config write will fail EEXIST — targeted fix needed\""
        fi
      fi
    elif [[ "$whiteout" == "yes" ]]; then
      # A zero-size REGULAR file carrying trusted.overlay.whiteout is a whiteout, not
      # a real in-flight lock: never auto-rm it on the blind surface (its removal is
      # the privileged Phase-2 sweep's job). Flagged unremovable so ensure_bare_config
      # routes around it, exactly like a non-regular lock. (rdev is `none` for this
      # regular-xattr whiteout form; the type stays `regular` for grep continuity.)
      unremovable=1
      echo "SOLEUR_GIT_LOCK_UNREMOVABLE file=$lock type=regular rdev=$rdev whiteout=yes errno=none reason=overlay-whiteout-regular hint=\"regular-file overlay whiteout — targeted fix required; not auto-removed\""
    else
      # chardevice / dir / symlink / mount / other: a config.lock is created by git
      # via open(O_CREAT|O_EXCL) — ALWAYS a regular file. A non-regular lock is NEVER
      # a legitimate in-flight writer and ALWAYS blocks the git config write (EEXIST)
      # regardless of age, so flag it unremovable UNCONDITIONALLY (no staleness gate
      # — that gate exists only for the regular in-flight-writer case above). Never
      # auto-removed on a blind surface; the DIAG line above carries the forensic
      # detail (type + rdev) to design/scope the privileged Phase-2 substrate fix.
      unremovable=1
      echo "SOLEUR_GIT_LOCK_UNREMOVABLE file=$lock type=$ftype rdev=$rdev errno=none reason=non-regular-lock hint=\"observed non-regular config lock — targeted fix required; not auto-removed\""
    fi
  done
  # Report progress BEFORE the return so a partial sweep (one lock removed, the
  # other stuck) still surfaces its count.
  if (( swept > 0 )); then
    echo -e "${YELLOW}Swept $swept stale git lock file(s) from $git_dir${NC}"
  fi
  (( unremovable == 0 ))   # non-zero iff a config-write lock remained unremovable
}

# _config_lock_wedged <file> — rc 0 (WEDGED) iff "<file>.lock" is PRESENT and
# NON-REGULAR (symlink / dir / mountpoint / character-device / other). This is the
# masked-lock signature the sweep flags reason=non-regular-lock: a genuine git config
# lock is ALWAYS a regular file (git creates it via open(O_CREAT|O_EXCL)), so a
# non-regular lock is never a legitimate in-flight writer and blocks every native
# `git config` write with EEXIST. An ABSENT or REGULAR lock is NOT wedged (rc 1):
# git's native writer either succeeds or legitimately blocks on a real concurrent
# writer. Delegates to classify_lock_node() (#6186) — the SAME precedence
# sweep_stale_git_locks uses — so a bind-mounted REGULAR lock (a mountpoint that
# also passes a bare `-f` test) is classified `mount`, not `regular`, in BOTH
# detectors; before this unification a duplicated `-f`-only check here read that
# node as regular/not-wedged while the sweep flagged it non-regular-lock.
_config_lock_wedged() {
  local lock="$1.lock" classify_out ftype
  classify_out=$(classify_lock_node "$lock") || return 1  # absent -> not wedged
  read -r ftype _ <<<"$classify_out"                      # field 2 (is_mp) unused here
  [[ "$ftype" == "regular" ]] && return 1                 # regular -> real/handled, not the wedge
  return 0                                                # symlink/chardevice/mount/dir/other -> wedged
}

# _config_target_masked <path> — rc 0 (MASKED) iff the RENAME TARGET itself is a
# character-device OR a mountpoint — the #5934 substrate signature. This is the direct
# cause of the verbatim live wedge:
#   mv: cannot move '.git/config.soleur-tmp.N' to '.git/config': Device or resource busy
# where `.git/config` (the target of atomic_git_config's same-dir rename), not merely its
# lock, is a bind-mounted / masked node. Reuses the EXACT `[[ -c ]]` + `stat -c%m`-self
# mountpoint idiom already proven in sweep_stale_git_locks (:187-193): `-c` (which
# dereferences a symlink, so a symlink→/dev/null is caught too) OR realpath is its own
# mount root. A regular file is NEVER masked (`-c` false; `stat -c%m` yields the containing
# fs root, not the file's own path), so this cannot over-trigger on a legitimate config —
# the load-bearing guarantee for the T22 regression (masked LOCK + regular config routes
# around, no false positive). GNU-only stat, consistent with the sweep.
_config_target_masked() {
  local t="$1" rp
  [[ -c "$t" ]] && return 0
  rp=$(realpath -- "$t" 2>/dev/null) || rp=""
  [[ -n "$rp" && "$(stat -c%m -- "$rp" 2>/dev/null)" == "$rp" ]] && return 0
  return 1
}

# atomic_git_config <file> <git-config-args…> — apply a `git config --file <file>`
# mutation without depending on <file>'s native "<file>.lock" when that lock is
# wedged (the #5912 Concierge char-device). The targeted fix for the config.lock
# worktree-creation wedge; composes read-first idempotence with a gated lockless
# writer, and is the sole config-mutation entry point for ensure_bare_config below.
#
# Call-site classes (#7394 added the last two): the shared-config normalization in
# ensure_bare_config; the create-time `core.bare = false` seed into a NEW worktree's
# own `config.worktree`; and the detection-time self-heal that writes the same key
# into an ALREADY-POISONED worktree's `config.worktree`. The latter two target a
# per-worktree admin dir rather than the shared config, so their failure mode is a
# single unusable worktree, never a repo-wide wedge.
#
#   FR2 read-first — a `key value` set whose value already matches, or an `--unset`
#     of an already-absent key, returns 0 with NO write. Reads never acquire
#     "<file>.lock", so this fast path works even while the lock is wedged.
#   FR3 gated writer — CLEAN/absent lock: native `git config` (preserves git's flock
#     serialization for healthy concurrent writers; a real regular lock surfaces its
#     own EEXIST here, the correct back-off). WEDGED (non-regular) lock: redirect
#     git's own INI writer to a same-directory temp copy and atomic-rename over the
#     target. git creates "<temp>.lock" — a clean path distinct from the masked
#     "<file>.lock" — so the write never touches the wedge.
#   TR1/TR2 — cp -p original -> same-dir temp (preserves mode/owner; plain cp
#     perm-drifts), git edits the temp, `mv -f` atomically replaces the target
#     (same-dir rename is atomic; a cross-fs /tmp temp would be a non-atomic
#     copy+unlink).
#   TR3 symlink guard — when <file> is itself a symlink, resolve to its target so the
#     rename preserves the indirection instead of clobbering the link with a regular
#     file.
#
# Parallel-session safety: last-rename-wins can drop a concurrent edit. For SAME-key
# writes every writer converges to the same idempotent value (a lost update is
# redundant, not corrupting). For DISTINCT-key writes by two concurrent lockless
# sessions the result is only EVENTUALLY consistent — an interleave can momentarily
# drop one key, self-healed on the next ensure_bare_config run. Native writers cannot
# race here: under a wedge they EEXIST on the masked lock, so only Soleur's own
# lockless sessions contend. Acceptable under this script's existing age-guard-not-flock
# posture (see sweep_stale_git_locks). GNU-only tooling (cp -p / realpath / mv),
# consistent with the sweep. Returns non-zero (with a loud headless_or_stderr line) on
# any write failure so ensure_bare_config can fail loud instead of proceeding
# half-applied. Self-contained return status (never relies on the caller's `if !`
# context to disarm set -e), so a future bare call site stays safe.
atomic_git_config() {
  local file="$1"; shift

  # --- FR2: read-first idempotence (reads never acquire "<file>.lock") ---
  if [[ "${1:-}" == "--unset" || "${1:-}" == "--unset-all" ]]; then
    # Skip ONLY when the key is truly ABSENT (git config --get rc 1). A multi-valued
    # key exits rc 2 ("multiple values") — do NOT swallow that as "absent" or the
    # unset silently no-ops (fail-open); fall through so the writer surfaces git's
    # loud --unset-all-required error. Reads never take the lock.
    #
    # `--unset-all` shares BOTH halves of that contract (#7394): the rc-1 absent skip
    # is equally correct for it, and the rc-2 multi-valued fall-through is what
    # `--unset-all` is FOR, so falling through there does the right thing rather than
    # surfacing an error. Matching only the literal `--unset` was a latent wedge —
    # `--unset-all` fell through to the native writer, and git exits **5** for
    # `--unset-all` on an absent key, so the first caller to use it (the defensive
    # extensions.worktreeConfig removal below) would have failed `create`,
    # `create-for-feature` and `cleanup-merged` on every already-healthy repo.
    local _grc=0
    git config --file "$file" --get "${2:-}" >/dev/null 2>&1 || _grc=$?
    (( _grc == 1 )) && return 0
  elif [[ "$#" -eq 2 && "$1" != --* ]]; then
    local _cur
    _cur=$(git config --file "$file" --get "$1" 2>/dev/null || true)
    [[ "$_cur" == "$2" ]] && return 0
  fi

  # --- D2: masked-TARGET pre-check (BEFORE any write, covering BOTH branches below) ---
  # The #5934 LIVE wedge: `.git/config` — the write TARGET itself, not just its lock — is a
  # char-device/bind-mount masked node, so EVERY write path fails (the native writer's own
  # rename over the target EBUSYs, and so does the lockless same-dir rename at the mv below).
  # Detect it here, AFTER the FR2 read-first fast path (an already-satisfied set/unset still
  # short-circuits with no write, correct even under the mask) but BEFORE the native-vs-
  # lockless decision, so a masked target NEVER reaches a doomed write. Checking "$file"
  # (whose `-c` test dereferences a symlink) covers a symlinked-to-masked config too. Fail
  # loud with the VISIBLE stdout sentinel (a bare echo, NOT headless_or_stderr — the latter's
  # per-PID logfile sink is invisible to the git-lock-marker telemetry scanner; #5934 D1).
  if _config_target_masked "$file"; then
    echo "SOLEUR_GIT_CONFIG_TARGET_MASKED file=$(basename -- "$file") reason=target-bind-mount branch=target-masked-precheck hint=\"config write TARGET is a char-device/bind-mount; rename would EBUSY — host-side pre-seed needed, see #6191,#5934\""
    headless_or_stderr error "atomic_git_config: config TARGET $file is masked (char-device/mountpoint); refusing the doomed write (see SOLEUR_GIT_CONFIG_TARGET_MASKED)."
    return 1
  fi

  # --- FR3: clean/absent lock -> native writer (keeps flock serialization) ---
  # Capture rc explicitly so the function is correct regardless of call context
  # (a bare `atomic_git_config …` call site must not abort at the git line under set -e).
  if ! _config_lock_wedged "$file"; then
    local _nrc=0
    git config --file "$file" "$@" || _nrc=$?
    return "$_nrc"
  fi

  # --- FR3 wedged + TR1/TR2/TR3: lockless temp-copy + same-dir atomic rename ---
  # TR3: resolve a symlinked config to its target so the rename preserves the link.
  local target="$file"
  if [[ -L "$file" ]]; then
    if ! target=$(realpath -- "$file" 2>/dev/null) || [[ -z "$target" ]]; then
      headless_or_stderr error "atomic_git_config: cannot resolve symlinked config $file; refusing lockless write."
      return 1
    fi
  fi
  local dir base tmp
  dir=$(dirname -- "$target")
  base=$(basename -- "$target")
  tmp="$dir/$base.soleur-tmp.$$"   # same-dir temp -> atomic rename; distinct .lock path
  # Seed the temp with current content (or empty when the target is absent),
  # preserving mode/owner via cp -p (TR2).
  if [[ -f "$target" ]]; then
    if ! cp -p -- "$target" "$tmp"; then
      rm -f -- "$tmp" 2>/dev/null || true   # cp can fail mid-copy leaving a partial temp
      headless_or_stderr error "atomic_git_config: cp -p failed for $target."
      return 1
    fi
  elif ! : > "$tmp" 2>/dev/null; then
    headless_or_stderr error "atomic_git_config: cannot create temp $tmp."
    return 1
  fi
  # Edit the temp copy with git's own INI writer (creates a clean "$tmp.lock").
  if ! git config --file "$tmp" "$@"; then
    rm -f -- "$tmp" "$tmp.lock" 2>/dev/null || true
    # Failing to write even the temp copy means git could not create the temp's OWN
    # clean lock ("$tmp.lock") — the strongest in-surface signal that the sandbox
    # masks *.lock as a GLOB, not just literal config.lock (the spec's BLOCKING
    # ASSUMPTION). Emit a DISTINCT stdout sentinel so the next blind-surface session
    # can tell glob-masking apart from the now-fixed single-path wedge (feeds #5934).
    echo "SOLEUR_GIT_LOCK_TEMP_WEDGED file=$base.soleur-tmp type=temp-write-failed reason=lockless-temp-unwritable hint=\"clean temp lock could not be created — sandbox may mask *.lock as a glob; see #5934\""
    headless_or_stderr error "atomic_git_config: git config write to temp failed for $target (temp lock unwritable — possible glob masking)."
    return 1
  fi
  # Defensive re-check on the RESOLVED target immediately before the rename (D2). Guard A
  # above already refuses a masked "$file"; this covers a symlink whose resolved target is
  # masked and any TOCTOU between the two points — so we never attempt the EBUSY-doomed mv.
  if _config_target_masked "$target"; then
    rm -f -- "$tmp" "$tmp.lock" 2>/dev/null || true
    echo "SOLEUR_GIT_CONFIG_TARGET_MASKED file=$base reason=target-bind-mount branch=target-masked-precheck hint=\"resolved rename target is masked; not attempting mv — host-side pre-seed needed, see #6191,#5934\""
    headless_or_stderr error "atomic_git_config: resolved config TARGET $target is masked; refusing the doomed rename."
    return 1
  fi
  # Atomic same-dir rename over the target; never touches the masked "<file>.lock".
  if ! mv -f -- "$tmp" "$target"; then
    rm -f -- "$tmp" "$tmp.lock" 2>/dev/null || true
    # A same-dir rename of a temp we just created failing is overwhelmingly the masked-target
    # EBUSY (the verbatim #5934 error). Emit the VISIBLE stdout sentinel (D1a) so the outcome
    # reaches the telemetry scanner regardless of headless_or_stderr's logfile sink.
    echo "SOLEUR_GIT_CONFIG_TARGET_MASKED file=$base reason=rename-failed branch=target-masked-precheck hint=\"same-dir atomic rename failed (likely EBUSY on a masked target); see #6191,#5934\""
    headless_or_stderr error "atomic_git_config: atomic rename failed for $target."
    return 1
  fi
  rm -f -- "$tmp.lock" 2>/dev/null || true   # defensive: git normally consumes it
  return 0
}

# _selfheal_bare_worktree_override — recover THIS worktree when it is being reported as
# bare (#7394, Phase 5).
#
# The create-path normalization above cannot help a worktree that ALREADY exists: the
# operator's worktrees were created while the poisoning pair was live, so every one of
# them is wedged until something writes `bare = false` into its own config.worktree.
# This runs at detection time, so the CURRENT worktree becomes usable immediately rather
# than waiting for the next session-start `cleanup-merged` (which is an AGENTS.md gate,
# not a hook, and the learnings corpus records it being skipped).
#
# Fires ONLY on a three-way conjunction, so it can never touch a genuine bare root or a
# normal clone:
#   (1) `.git` at the CWD (or nearest ancestor) is a FILE containing `gitdir: <path>` —
#       the on-disk signature of a LINKED worktree, which a bare root never has;
#   (2) that gitdir resolves under `<git-common-dir>/worktrees/` — it is a worktree of
#       THIS repo, not an unrelated gitfile;
#   (3) git nevertheless reports `--is-bare-repository` = true — i.e. it is wedged.
# A healthy worktree fails (3); a bare root fails (1); a normal clone fails (1) and (3).
#
# BLAST RADIUS IS EXACTLY ONE WORKTREE. The write targets this worktree's own
# config.worktree and the SHARED config is never touched — a shared-config write here
# would silently re-shape every sibling worktree from a code path that runs on every
# single invocation of this script.
_selfheal_bare_worktree_override() {
  # (1) a linked worktree's `.git` is a FILE, never a directory.
  local dotgit="" probe="$PWD"
  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -e "$probe/.git" ]]; then dotgit="$probe/.git"; break; fi
    probe="$(dirname -- "$probe")"
  done
  [[ -n "$dotgit" && -f "$dotgit" ]] || return 0
  grep -q '^gitdir: ' "$dotgit" 2>/dev/null || return 0

  # (2) the gitdir must live under <git-common-dir>/worktrees/.
  local wt_gitdir common_dir
  wt_gitdir="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$wt_gitdir" && -n "$common_dir" ]] || return 0
  if [[ "$common_dir" != /* ]]; then
    common_dir="$(cd "$common_dir" 2>/dev/null && pwd)" || return 0
  fi
  [[ "$wt_gitdir" == "$common_dir/worktrees/"* ]] || return 0

  # (3) …and git still calls it bare. A healthy worktree exits here.
  [[ "$(git rev-parse --is-bare-repository 2>/dev/null || true)" == "true" ]] || return 0

  local wt_name gitver
  wt_name="$(basename -- "$wt_gitdir")"
  gitver="$(git --version 2>/dev/null | awk '{print $3}')"

  if atomic_git_config "$wt_gitdir/config.worktree" core.bare false; then
    echo "SOLEUR_GIT_BARE_SELFHEAL worktree=$wt_name git_dir=$wt_gitdir git_version=$gitver branch=ok"
    # Re-derive every global the poisoned state computed wrongly. GIT_ROOT was resolved
    # from the bare branch at init and points at <common>/worktrees/<name>.
    IS_IN_WORKTREE=false
    if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
      IS_IN_WORKTREE=true
    fi
    IS_BARE=false
    if [[ "$common_dir" == */.git ]]; then
      GIT_ROOT="${common_dir%/.git}"
    else
      GIT_ROOT="$common_dir"
    fi
    if [[ "$(git -C "$common_dir" rev-parse --is-bare-repository 2>/dev/null || true)" == "true" ]]; then
      IS_BARE=true
    fi
    return 0
  fi

  # [R5] Fail LOUD and ACTIONABLE. Deliberately NOT the bare "Run from an existing
  # worktree" text: the caller IS in an existing worktree, so that message sends the
  # operator to do the thing they already did.
  echo "SOLEUR_GIT_BARE_SELFHEAL worktree=$wt_name git_dir=$wt_gitdir git_version=$gitver branch=failed"
  echo -e "${RED}Error: this worktree is being reported as bare, and the fix could not be written.${NC}" >&2
  echo -e "${YELLOW}Could not write: $wt_gitdir/config.worktree${NC}" >&2
  echo -e "${YELLOW}Likely causes: no write permission on that directory, wrong ownership, a read-only mount, or the disk being full.${NC}" >&2
  echo -e "${YELLOW}Next step: run  ls -ld '$wt_gitdir'  and make it writable by you (e.g. chmod u+w), then re-run this command.${NC}" >&2
  return 1
}
if ! _selfheal_bare_worktree_override; then
  exit 1
fi
# Relocated from the detection block above (#7394): both run ONCE, here, on healed state.
ensure_git_root_absolute
WORKTREE_DIR="$GIT_ROOT/.worktrees"

# Normalize a bare repo's SHARED config so per-worktree core.bare resolution is never
# engaged (#7394 — polarity reversed; the previous header described the opposite fix).
#
# What it now guarantees on a repo whose shared config has core.bare=true:
#   1. extensions.worktreeConfig is ABSENT — this is the key that makes git resolve
#      core.bare per-worktree, and it is the half of the pair that wedges worktrees.
#   2. core.bare stays IN the shared config — removing it (the issue's hand workaround)
#      makes the bare ROOT report as a normal working tree (fact 7).
#   3. stale core.worktree is removed — orthogonal, retained from the previous behaviour.
#
# The old header claimed it "fixes TWO broken states … core.bare must ONLY exist in
# .git/config.worktree". That prescription is what created the wedge; see the file header.
# Called before AND after git worktree add. Safe for parallel sessions: every operation is
# idempotent, and on an already-healthy repo it performs ZERO writes.
ensure_bare_config() {
  local git_dir="$GIT_ROOT/.git"
  # Only relevant for bare repos (git dir IS the repo root)
  if [[ ! -d "$git_dir" ]]; then
    git_dir="$GIT_ROOT"
  fi
  # Mask-robust root fallback (#5934 D3 follow-up). Under the Concierge char-device config
  # mask, GIT_ROOT can resolve two ways, BOTH of which misdirect git_dir: it may resolve
  # EMPTY (`--show-toplevel` returns nothing → git_dir collapses to "", shared_config becomes
  # "/config"); or, because `--is-bare-repository` DEGRADES to a false "true" at init, the top
  # of this script recomputes GIT_ROOT from `--absolute-git-dir`/`--git-common-dir` to the
  # RELATIVE string ".git" (non-empty → git_dir collapses to ".git", which has NO slash, so the
  # line-532 `*/.git` non-bare skip cannot match → the bare surgery misfires and wedges,
  # telemetry branch=target-masked-precheck/bare-fail). The predecessor D3 fix (merged
  # 2026-07-07) gated this fallback on `-z "$GIT_ROOT"`, so it caught only the EMPTY case and
  # MISSED the relative-".git" case. The mask-proof invariant: a corrupted GIT_ROOT is ALWAYS
  # non-absolute (empty or a relative ".git"), while a LEGITIMATE GIT_ROOT — bare or non-bare —
  # is always an absolute path. create_worktree runs from the workspace root, so recover git_dir
  # from the ABSOLUTE $PWD/.git whenever GIT_ROOT is non-absolute (a pure filesystem fact that
  # does NOT read the masked config), so the line-532 `*/.git` skip fires for BOTH the empty and
  # the relative-".git" cases. Gating on `$GIT_ROOT != /*` (not unconditional) preserves the
  # genuine-bare path: a real bare repo carries an ABSOLUTE GIT_ROOT → fallback stays inert →
  # its surgery still runs even if the invoking CWD happens to be an unrelated non-bare checkout.
  # Genuine bare repos also have no `.git` subdir and linked worktrees carry `.git` as a FILE
  # (both `-d` false), so the fallback also stays inert there when GIT_ROOT is legitimately set.
  if [[ "$GIT_ROOT" != /* && -d "$PWD/.git" ]]; then
    git_dir="$PWD/.git"
  fi

  # Self-heal: sweep BEFORE the config writes below for its diagnostics + stale
  # REGULAR-lock removal (the 2026-07-01 outage class). Runs on EVERY repo (bare or
  # normal) — it writes NO config, only removes stale regular locks and emits the
  # blind-surface SOLEUR_GIT_LOCK_* forensic — so it stays ABOVE the non-bare guard
  # below. A NON-REGULAR (masked) lock is NO LONGER fatal here — atomic_git_config
  # routes every write below around it via a lockless temp-copy+rename (#5912). So we
  # intentionally ignore the sweep's non-zero return: the per-write gate in
  # atomic_git_config makes the correct native-vs-lockless choice, and a genuinely
  # stuck REGULAR lock (a real in-flight writer) still surfaces as a native `git config`
  # EEXIST failure from atomic_git_config's clean-lock branch. `|| true` disarms set -e.
  sweep_stale_git_locks "$git_dir" || true

  # NON-BARE GUARD (#6184 → #5934, hardened round 6). Everything BELOW is a BARE-repo
  # accommodation: on a bare repo `git worktree add` corrupts the shared config (see
  # header), and setting extensions.worktreeConfig=true steers those writes off it. A
  # NORMAL working clone (the Concierge workspace layout, core.bare=false) needs NONE of
  # it — `git worktree add` writes only to `.git/worktrees/<id>/`. Worse, enabling
  # worktreeConfig FORCES git to read `.git/config.worktree`, which in the agent sandbox
  # is an unreadable /dev/null char device → `fatal: … Permission denied` on EVERY git
  # command. So: proceed with the surgery ONLY when the repo is DEFINITIVELY bare;
  # default to SKIP.
  #
  # ROUND-6 root cause (#5934, operator-CONFIRMED non-bare workspace): the round-5 guard
  # trusted `git rev-parse --is-bare-repository`, but under the char-device config mask that
  # command DEGRADES — it (and `--show-toplevel`, → GIT_ROOT="") must read the masked
  # `.git/config`, and can report a false "true" — so the guard fell through to the surgery
  # on a NON-bare clone and wedged the config write at the give-up below. Round 6's fix was
  # to detect non-bare by a PURE FILESYSTEM fact that never reads the masked config —
  # `git_dir` is a `.git` DIRECTORY — and SKIP there.
  #
  # ROUND-7 (#7394): that filesystem fact is not the discriminator it was taken for. There
  # is a THIRD surface round 6 did not enumerate — a BARE repo STORED IN a `.git`
  # subdirectory (the operator's own CLI clone, ADR-099 row 3): `<root>/.git` is a real
  # DIRECTORY *and* `core.bare = true`. The shape test matches it, so everything below was
  # DEAD CODE on that layout and nothing ever broke the config pair that wedges worktrees.
  # `[[ -d <root>/.git ]]` cannot tell row 2 (normal clone) from row 3's root, because both
  # are a `.git` directory — the distinguishing fact is the CONTENT of the config, not the
  # SHAPE of the gitdir.
  #
  # So: decide on `core.bare` read out of the shared config FILE, and STILL DEFAULT TO SKIP.
  # Reading the file directly (rather than `git rev-parse`) is what preserves the round-6
  # mask protection: under the char-device mask this read degrades to EMPTY with a non-zero
  # rc, which is not the literal `true` required to fall through, so a masked repo takes the
  # SAME skip branch it took before. Every other outcome — absent, `false`, a non-zero rc —
  # also skips. Only an unambiguous `true` proceeds to git's authoritative check below.
  #
  # NOT gated on `core.repositoryformatversion` (fact 2): a bare repo created before the
  # extension era carries version 0, so requiring 1 would re-introduce a shape test that
  # misses exactly the repos most likely to be poisoned.
  local _shared_bare="" _shared_bare_rc=0
  _shared_bare="$(git config --file "$git_dir/config" --get --type=bool core.bare 2>/dev/null)" || _shared_bare_rc=$?
  if [[ "$_shared_bare" != "true" ]]; then
    # Effectively NON-BARE (or unreadable) → the bare surgery is unneeded and native
    # `git worktree add` (writing only to .git/worktrees/<id>/, never the masked .git/config)
    # proceeds. If the config family IS masked, emit a BENIGN diagnostic (mirrored, NOT
    # paged) so telemetry shows the graceful-degrade path fired — branch=non-bare-skip.
    if _config_target_masked "$git_dir/config" || _config_target_masked "$git_dir/config.worktree"; then
      echo "SOLEUR_GIT_CONFIG_MASK_SKIP file=config reason=non-bare-skip branch=non-bare-skip hint=\"masked .git/config on a non-bare clone; bare surgery skipped — native worktree add writes only .git/worktrees/<id>/\""
    fi
    return 0
  fi
  unset _shared_bare_rc
  # git_dir is NOT a `.git` directory → a genuine bare repo (gitdir IS the root) or an
  # indeterminate resolution. Consult git's authoritative check ONLY now; a non-"true"
  # verdict (normal clone / indeterminate / wedged) still skips safely.
  local _bare_status
  _bare_status="$(git -C "${GIT_ROOT:-.}" rev-parse --is-bare-repository 2>/dev/null || true)"
  if [[ "$_bare_status" != "true" ]]; then
    return 0
  fi
  # GENUINELY bare AND its config is masked → the shared-config write is REQUIRED (prevents
  # core.bare bleeding into worktrees) but IMPOSSIBLE in-sandbox. Fail LOUD + VISIBLE naming
  # the host-seed remedy — never ship a core.bare-bleeding worktree. This is the RARE
  # fallback (the operator's live wedge is the non-bare-skip above); the durable fix is
  # host-side (pre-seed .git/config before the bwrap mask, #6191/#5934).
  if _config_target_masked "$git_dir/config"; then
    echo "SOLEUR_GIT_CONFIG_TARGET_MASKED file=config reason=bare-under-mask branch=bare-fail remedy=host-pre-seed-.git/config-before-bwrap-mask see=#6191,#5934"
    echo "worktree wedge: bare repo config write impossible under masked .git/config in $git_dir (host-side pre-seed required; see #6191,#5934)"
    headless_or_stderr error "worktree wedge: bare repo + masked .git/config in $git_dir — host-side pre-seed required (see #6191,#5934)."
    return 1
  fi

  local shared_config="$git_dir/config"
  local fixed=false

  # REVERSED POLARITY (#7394). The old code did the opposite of all three steps below: it
  # ENABLED extensions.worktreeConfig (plus repositoryformatversion 1) and then UNSET
  # core.bare from the shared config, on the theory that core.bare belongs per-worktree only.
  # Measured on git 2.53.0, that theory is inverted at both ends:
  #
  #   - The extension is the half that WEDGES. With it on, git resolves core.bare
  #     per-worktree; a linked worktree that does not set `bare = false` in its OWN
  #     config.worktree inherits `true` from the shared config and is treated as BARE.
  #     `git worktree add` writes NO config.worktree at all (fact 4), so EVERY worktree
  #     created after the extension is enabled starts out poisoned.
  #   - Unsetting shared core.bare is not a safe end state either (fact 7): it makes the
  #     bare ROOT report as a normal working tree. That is the issue's hand workaround, and
  #     it is retired here rather than codified.
  #
  # So the durable state is the one git itself produces: core.bare in the shared config,
  # extension OFF, per-worktree resolution never engaged. Both writes below are REMOVALS of
  # a state we no longer create, which is why an already-healthy repo performs zero writes.
  local _ext_present=""
  _ext_present="$(git config --file "$shared_config" --get extensions.worktreeConfig 2>/dev/null || true)"
  if [[ -n "$_ext_present" ]]; then
    echo -e "${BLUE}Fixing bare repo config: removing extensions.worktreeConfig from shared config...${NC}"
    # --unset-all, not --unset: the key is multi-valued-capable and a repo poisoned twice
    # would rc-2 a plain --unset. Safe on an absent key only because of the FR2 fast path
    # extended for this call site (see atomic_git_config) — a native --unset-all on an
    # absent key exits 5.
    if ! atomic_git_config "$shared_config" --unset-all extensions.worktreeConfig; then
      echo "worktree wedge: could not break the bare-config pair in $git_dir (see errors above)"
      headless_or_stderr error "worktree wedge: could not break the bare-config pair in $git_dir (see errors above)."
      return 1
    fi
    fixed=true
  fi

  # Remove stale core.worktree from shared config (leftover from worktree operations).
  # Retained unchanged from the previous behaviour — it is orthogonal to the polarity.
  if git config --file "$shared_config" core.worktree &>/dev/null; then
    echo -e "${BLUE}Fixing bare repo config: removing stale core.worktree from shared config...${NC}"
    if ! atomic_git_config "$shared_config" --unset core.worktree; then
      echo "worktree wedge: could not break the bare-config pair in $git_dir (see errors above)"
      headless_or_stderr error "worktree wedge: could not unset core.worktree in $shared_config (see errors above)."
      return 1
    fi
    fixed=true
  fi

  # core.bare is deliberately LEFT IN the shared config, and `.git/config.worktree` is
  # deliberately left on disk untouched: with the extension absent that file is inert, and
  # deleting it would be a destructive write with no benefit. The old fourth write block
  # (setting core.bare=true into the bare root's own config.worktree) is REMOVED — under the
  # reversed polarity nothing reads config.worktree, so it was permanently inert.

  local _branch="clean"; [[ "$fixed" == "true" ]] && _branch="healed"
  # Bare stdout echo (D1a) so the outcome reaches the git-lock-marker telemetry scanner —
  # headless_or_stderr's per-PID logfile sink is invisible to it (#5934).
  echo "SOLEUR_GIT_BARE_POISON git_dir=$git_dir extension=$([[ -n "$_ext_present" ]] && echo present || echo absent) shared_bare=true wt_override=$([[ -f "$git_dir/config.worktree" ]] && echo present || echo absent) git_version=$(git --version 2>/dev/null | awk '{print $3}') branch=$_branch"

  if [[ "$fixed" == "true" ]]; then
    echo -e "${GREEN}Fixed: shared config keeps core.bare, per-worktree resolution disabled${NC}"
  fi
}

# seed_worktree_bare_false <worktree-path> — pin `core.bare = false` into a NEWLY
# created worktree's OWN config.worktree (#7394, Phase 4).
#
# Defense in depth, not the primary fix: with extensions.worktreeConfig absent (the
# reversed polarity above) nothing reads config.worktree, so this write is inert on a
# healthy repo. It exists so that a worktree created here stays correct even if some
# OTHER tool re-enables the extension later — the recorded re-evaluation trigger for
# ADR-173 is exactly "a new setter of extensions.worktreeConfig appears in the toolchain".
#
# This is a CREATE, not a repair: per fact 4, `git worktree add` writes NO
# config.worktree at all, so there is no existing-and-empty file to heal.
#
# The admin dir is resolved from git itself (`rev-parse --absolute-git-dir` inside the
# new worktree), never by string-joining a guessed worktree name onto
# `<root>/.git/worktrees/` — git derives that directory name from the worktree's BASENAME
# with its own collision suffixing, so a guessed join silently targets the wrong
# directory (or a nonexistent one) whenever two worktrees share a basename.
#
# Non-fatal by design: failing to write a defense-in-depth pin must not fail `create` on
# a repo that is already in the durable state. Returns non-zero and emits the marker so
# the outcome is still visible in telemetry.
seed_worktree_bare_false() {
  local worktree_path="$1"
  local wt_gitdir
  wt_gitdir="$(git -C "$worktree_path" rev-parse --absolute-git-dir 2>/dev/null || true)"
  if [[ -z "$wt_gitdir" || ! -d "$wt_gitdir" ]]; then
    echo "SOLEUR_GIT_BARE_SELFHEAL worktree=$(basename -- "$worktree_path") reason=gitdir-unresolved git_version=$(git --version 2>/dev/null | awk '{print $3}') branch=seed-failed"
    headless_or_stderr warn "seed_worktree_bare_false: could not resolve the git dir for $worktree_path; skipping the core.bare=false pin."
    return 1
  fi
  if ! atomic_git_config "$wt_gitdir/config.worktree" core.bare false; then
    echo "SOLEUR_GIT_BARE_SELFHEAL worktree=$(basename -- "$worktree_path") reason=seed-write-failed git_version=$(git --version 2>/dev/null | awk '{print $3}') branch=seed-failed"
    headless_or_stderr warn "seed_worktree_bare_false: could not write core.bare=false into $wt_gitdir/config.worktree."
    return 1
  fi
  return 0
}

# Verify a worktree was properly created and registered.
# Checks: (1) rev-parse --show-toplevel matches expected path,
#          (2) worktree appears in git worktree list.
# On registration failure, attempts targeted git worktree repair before giving up.
# Usage: verify_worktree_created "$worktree_path" "$branch_name" "$from_branch"
verify_worktree_created() {
  local worktree_path="$1"
  local branch_name="$2"
  # $from_branch is used only in diagnostic hint messages below, but kept as a
  # parameter because all callers already have it in scope and the hint aids
  # debugging when worktree creation fails.
  local from_branch="$3"

  # Check 0: Fast-fail if directory was not created at all
  if [[ ! -d "$worktree_path" ]]; then
    # Bare stdout marker (D1a) so this failure reaches the git-lock-marker telemetry scanner
    # — verify_worktree_created was SILENT to every sink before #5934 round-3, so the round-2
    # relative-GIT_ROOT path-mismatch could only be diagnosed from an operator paste.
    echo "SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=dir-not-created branch=$branch_name expected=$worktree_path"
    echo -e "${RED}Error: Worktree directory not created at $worktree_path${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    exit 1
  fi

  # Check 1: Verify the directory is a valid git worktree
  local actual_toplevel
  if ! actual_toplevel=$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null); then
    echo "SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=not-a-worktree branch=$branch_name expected=$worktree_path"
    echo -e "${RED}Error: Worktree creation failed — $worktree_path is not a valid git worktree${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi
  if [[ "$actual_toplevel" != "$worktree_path" ]]; then
    # The #5934 round-2 LIVE failure: a RELATIVE GIT_ROOT (".git") made WORKTREE_DIR relative,
    # so the expected path is a relative string while git reports the same location ABSOLUTE.
    # Emit both so the relative-vs-absolute mismatch is self-diagnosable from telemetry.
    echo "SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=path-mismatch branch=$branch_name expected=$worktree_path actual=$actual_toplevel"
    echo -e "${RED}Error: Worktree path mismatch — expected $worktree_path, got $actual_toplevel${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi

  # Check 2: Verify worktree is registered in git's worktree list (#1932)
  if ! git worktree list --porcelain | grep -qxF "worktree $worktree_path"; then
    echo -e "${YELLOW}Warning: Worktree not in git worktree list — attempting repair...${NC}"
    git worktree repair "$worktree_path" 2>/dev/null || true
    if ! git worktree list --porcelain | grep -qxF "worktree $worktree_path"; then
      echo "SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=unregistered branch=$branch_name expected=$worktree_path"
      echo -e "${RED}Error: Worktree directory exists but is not registered after repair${NC}"
      git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
      exit 1
    fi
    echo -e "${GREEN}Repair successful — worktree now registered${NC}"
  fi

  # Check 3: Verify the branch was actually created
  if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo "SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=branch-missing branch=$branch_name expected=$worktree_path"
    echo -e "${RED}Error: Branch $branch_name was not created despite successful worktree add${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi
}

# Ensure the worktree has a git identity, RESPECTING an already-present host-seeded
# owner identity (#6184).
#
# IDENTITY AUTHORITY IS INVERTED BETWEEN THE TWO NON-BARE/BARE SURFACES (ADR-099):
#   - Non-bare Concierge agent workspace (where this runs in production): the host seeds
#     the shared config with the per-workspace OWNER as the LOCAL identity
#     (workspace.ts), while the sandbox image bakes a `github-actions[bot]` --GLOBAL
#     (Dockerfile). So in-sandbox: LOCAL = owner (authoritative), GLOBAL = bot.
#   - Bare CLI dev repo: the bare repo may carry a bot LOCAL and the operator's --GLOBAL
#     is the real human.
# The prior logic FORCED global over local — correct only for the bare dev repo, but on
# Concierge it clobbered the correct OWNER with the bot GLOBAL via a raw per-worktree
# `--local` config write. That write locked the shared config → O_CREAT|O_EXCL on
# the masked config.lock (ADR-081) → EEXIST → RC=255 wedge; and had it "succeeded" it
# would have misattributed the operator's commits to `github-actions[bot]`.
#
# Fix (bot-aware, #6184 F1/F2): the discriminator is BOT-SHAPE, not presence — because
# authority is inverted (ADR-099) and neither "always force global" (old — wrong on
# non-bare Concierge) nor "always respect local" (wrong on the bare CLI dev repo, which
# frequently carries a poisoned bot LOCAL — the #2815 CLA-reject bug) is correct alone.
#   - present NON-bot local → authoritative; return WITHOUT writing (the common Concierge
#     owner path; also a human dev-local). No lock, no wedge, correct attribution.
#   - bot-shaped or absent local → correct it from a present, NON-bot --global, routed
#     through atomic_git_config against the resolved common-dir config so a masked
#     config.lock cannot wedge it. A bot-shaped --global is NEVER written (that is the
#     silent misattribution the plan rejects): a present owner-local is left intact, a
#     fully-absent local refuses loudly (reason=bot-global-refused).
# `user.*` is not an RCE-relevant config key. Never re-add a raw `git config` write here
# (see SKILL.md Sharp Edges).
# A git identity is BOT-shaped iff its name OR email carries a `[bot]` marker
# (github-actions[bot], dependabot[bot], …) — the unambiguous CI-bot signature that the
# GitHub Actions default committer and `actions/checkout` inject. Used by
# ensure_worktree_identity as the authority discriminator; see its header (#6184 F1/F2).
_identity_is_bot() {
  [[ "${1:-}" == *'[bot]'* || "${2:-}" == *'[bot]'* ]]
}

ensure_worktree_identity() {
  local worktree_path="$1"

  # Read BOTH identities up front. On a linked worktree `--local` targets the shared
  # common-dir config (on Concierge, the host-seeded owner). --global is the operator's
  # identity locally, but the sandbox IMAGE bakes a `github-actions[bot]` --global.
  local local_email local_name global_email global_name
  local_email=$(git -C "$worktree_path" config --local --get user.email 2>/dev/null || true)
  local_name=$(git -C "$worktree_path" config --local --get user.name 2>/dev/null || true)
  global_email=$(git config --global --get user.email 2>/dev/null || true)
  global_name=$(git config --global --get user.name 2>/dev/null || true)

  # PRIMARY: a present, non-empty, NON-bot local identity is authoritative — the
  # host-seeded owner on Concierge, or a human dev-local on any clone. Respect it with
  # ZERO config work (the common Concierge path — no lock, no wedge, correct attribution).
  # The bot-shape guard is load-bearing (#6184 F1): a bare CLI dev root FREQUENTLY carries
  # an inherited `github-actions[bot]` LOCAL that every worktree inherits (learning
  # 2026-04-24-fake-git-author-bare-repo-bot-override; PR #2815 CLA reject) — respecting
  # THAT would re-open the exact bug ensure_worktree_identity was born to fix. Neither
  # blanket rule works (ADR-099 "authority is inverted, never blanket-force"); bot-shape is
  # the discriminator that is correct on both surfaces.
  if [[ -n "$local_email" && -n "$local_name" ]] && ! _identity_is_bot "$local_email" "$local_name"; then
    return 0
  fi

  # Reached iff local is NOT authoritative (absent, partial, or bot-shaped). We can only
  # correct it FROM a present, non-bot --global.
  local have_global=0 global_is_bot=0
  [[ -n "$global_email" && -n "$global_name" ]] && have_global=1
  if (( have_global )) && _identity_is_bot "$global_email" "$global_name"; then global_is_bot=1; fi

  if (( ! have_global )); then
    # Nothing to set from. If local is bot-shaped and uncorrectable, warn (the commit will
    # be bot-authored and bounce at the CLA gate, wg-cla-signed-author-before-merge).
    if [[ -n "$local_email$local_name" ]] && _identity_is_bot "$local_email" "$local_name"; then
      headless_or_stderr warn "ensure_worktree_identity: $worktree_path has a bot-shaped local identity and no human --global to override it; commits may fail the CLA author gate."
    fi
    return 0   # the user owns their git config; nothing to assert
  fi

  if (( global_is_bot )); then
    # The only --global is the sandbox bot. NEVER write it — that is the Layer-A silent
    # misattribution the plan rejects, reached via the local-absent/​bot-local trigger.
    # A present (owner) local, even partial, is left intact; a fully-absent local means
    # host-seeding failed/raced (#6184 F2) → refuse LOUDLY rather than author as the bot.
    if [[ -n "$local_email" || -n "$local_name" ]]; then
      return 0
    fi
    echo "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=bot-global-refused file=config"
    return 1
  fi

  # A human --global is available → set/override the worktree identity from it.
  # DIAG-class precondition marker (NOT a wedge; excluded from WEDGE_RE): device/path
  # forensic only, never the identity values. It signals the DEGRADED/fallback path (a
  # human dev repo, or a Concierge owner-seed that went missing) — NOT the normal
  # Concierge path, which early-returns above with no marker.
  if [[ -n "$local_email" || -n "$local_name" ]]; then
    echo "SOLEUR_GIT_LOCK_IDENTITY_DIAG source=ensure_worktree_identity reason=identity-drift-override-bot-local"
  else
    echo "SOLEUR_GIT_LOCK_IDENTITY_DIAG source=ensure_worktree_identity reason=identity-drift-set-from-global"
  fi

  # Resolve the SHARED (common-dir) config as an ABSOLUTE path. --path-format=absolute is
  # load-bearing: a bare `--git-common-dir` can return a RELATIVE `.git`
  # (learning 2026-03-18-git-common-dir-vs-show-toplevel-semantics; --path-format needs
  # git ≥ 2.31, universally present in 2026). On empty/failure,
  # emit the wedge sentinel + return 1 — do NOT fall back to $GIT_ROOT/.git/config (wrong
  # on the bare layout, where $GIT_ROOT has no .git/ subdir).
  local common_dir common_config
  common_dir=$(git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$common_dir" ]]; then
    echo "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=common-dir-unresolved file=config"
    return 1
  fi
  common_config="$common_dir/config"

  # set -e DISCIPLINE (MANDATORY shape): `if !`-wrapping this function at the call site
  # DISARMS errexit for the whole function body, so a bare `atomic_git_config …` failure
  # would silently fall through to the success `return 0` (vacuous success — worse than
  # the wedge). Each write is therefore its OWN explicit `if !` guard. The call-site wrap
  # matters (a) to give a contextual red error + exit 1 instead of a bare abort, and
  # (b) precisely BECAUSE it disarms errexit, forcing these per-write checks — NOT because
  # "an echo wouldn't print" (an echo before `return 1` always flushes).
  if ! atomic_git_config "$common_config" user.email "$global_email" \
     || ! atomic_git_config "$common_config" user.name "$global_name"; then
    echo "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=native-eexist file=config"
    return 1
  fi
  echo -e "${GREEN}Set worktree git identity from global: $global_name <$global_email>${NC}"
  return 0
}

# Ensure .worktrees is in .gitignore
ensure_gitignore() {
  if ! grep -q "^\.worktrees$" "$GIT_ROOT/.gitignore" 2>/dev/null; then
    echo ".worktrees" >> "$GIT_ROOT/.gitignore"
  fi
}

# Fetch from origin without mutating the local <branch> ref, then echo the
# best ref to use as the worktree base. Safe to run while the local <branch>
# is checked out in another worktree — only refs/remotes/origin/<branch> (if
# tracked) and FETCH_HEAD are updated. Default base path for `create` since #3741.
#
# Precedence:
#   1. refs/remotes/origin/<branch>  — normal clone with standard fetch refspec
#   2. FETCH_HEAD                    — bare clones without remotes.origin.fetch
#                                      get FETCH_HEAD written by `git fetch origin <b>`
#   3. <branch>                      — offline fallback to local ref
fetch_origin_branch_base() {
  local branch="$1"
  # All progress/warning output goes to stderr — only the chosen ref name is
  # written to stdout so callers can capture it via $(...).
  echo -e "${BLUE}Fetching latest origin/$branch...${NC}" >&2
  if ! git fetch origin "$branch" 2>/dev/null; then
    echo -e "${YELLOW}Warning: Could not fetch origin/$branch -- using cached ref${NC}" >&2
  fi
  if git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null 2>&1; then
    echo "origin/$branch"
  elif git rev-parse --verify --quiet FETCH_HEAD >/dev/null 2>&1; then
    echo "FETCH_HEAD"
  else
    echo "$branch"
  fi
}

# Acquire the session lease for a worktree, with the diagnostics a destructive
# path requires. Used by create_worktree() and create_for_feature() at four
# sites; extracted so the protocol (sweep -> acquire -> VERIFY -> trap) cannot
# drift between them, and so a fix lands once instead of four times.
#
#   $1  branch name — this IS the lease key
#   $2  call-site tag for telemetry: create | create-reentry | feature | feature-reentry
#   $3  "trap"   — this process created the worktree; register the release trap
#       "notrap" — re-entry into a worktree this process did NOT create
#
# Why $3 exists: the trap makes the CALLING process release_lease's in-process
# owner. On a re-entry that is wrong — a SIGINT during re-entry would delete the
# lease the INCUMBENT session depends on, leaving it unleased and reapable. The
# trap belongs to the process whose exit actually ends the work.
#
# Returns 0 only when a lease file demonstrably exists on disk.
_acquire_worktree_lease() {
  local branch_name="$1" site="$2" mode="${3:-trap}"

  # Guarded: _session_state_init_dirs inside the sweep is unguarded, and a full
  # or read-only state dir would otherwise abort the caller under `set -e` —
  # blast radius being the whole create. Mirrors the guarded sibling call in
  # cleanup_merged_worktrees.
  sweep_orphan_leases \
    || headless_or_stderr warn "lease sweep failed before acquiring $branch_name"

  # With no lease library the reaper fails CLOSED (is_lease_active() stub returns
  # 0 => refuse to reap anything), so an absent lease file is not an exposure and
  # the load-time SOLEUR_WORKTREE_LEASE_LIB_MISSING sentinel already said so.
  # Verifying here would emit a second, misleading failure marker.
  if [[ "$_SS_LIB_MISSING" == "true" ]]; then
    return 0
  fi

  local acquired=true
  acquire_lease "$branch_name" "${SOLEUR_SKILL_NAME:-unknown}" "${SOLEUR_EXPECTED_DURATION_MIN:-240}" \
    || acquired=false

  if [[ "$acquired" != "true" ]]; then
    # Most common real cause: a branch name the lease layer cannot key on
    # (_validate_worktree_name rejects anything outside [A-Za-z0-9._-], so any
    # slash-bearing name lands here and runs UNLEASED).
    echo "SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED branch=$branch_name site=$site reason=rc-nonzero"
    headless_or_stderr warn "could not acquire lease for $branch_name — this worktree is REAPABLE"
    return 1
  fi

  # rc=0 is NOT proof the artifact exists. Assert the FILE, because that is what
  # is_lease_active reads. Covers a failed rename, a divergent state root, and
  # SOLEUR_DISABLE_SESSION_STATE=1 (which returns success while writing nothing
  # AND leaves is_lease_active returning "not active" — i.e. fail-open).
  local lease_path=""
  lease_path="$(_lease_file "$branch_name" 2>/dev/null || true)"
  if [[ -z "$lease_path" || ! -f "$lease_path" ]]; then
    echo "SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED branch=$branch_name site=$site reason=file-absent"
    headless_or_stderr warn "acquire_lease reported success but no lease file exists for $branch_name — this worktree is REAPABLE"
    return 1
  fi

  if [[ "$mode" == "trap" ]]; then
    # Multi-signal trap so an interrupted session (SIGINT/SIGTERM/SIGHUP) still
    # releases. NOT EXIT — see _register_lease_release_trap in session-state.sh.
    _register_lease_release_trap "$branch_name"
  fi
  return 0
}

# Resolve the base ref to use for `git worktree add` based on whether the
# operator passed --update-local-main. Sets globals BASE_REF and TRACK_FLAG.
# Used by create_worktree() and create_for_feature() — both call sites need
# identical behavior so the helper keeps the load-bearing --no-track comment
# (see fetch_origin_branch_base) and the --update-local-main branch in one place.
resolve_base_ref() {
  local from="$1"
  if [[ "$UPDATE_LOCAL_MAIN" == "true" ]]; then
    update_branch_ref "$from"
    BASE_REF="$from"
    TRACK_FLAG=""
  else
    BASE_REF="$(fetch_origin_branch_base "$from")"
    # --no-track is load-bearing: without it, branch.<new>.merge would be set
    # to refs/heads/<from>, breaking bare `git push` from inside the worktree.
    # Pre-fix behavior left upstream UNSET; this preserves that exactly.
    TRACK_FLAG="--no-track"
  fi
}

# Update a branch ref to latest remote, handling bare vs non-bare repos.
# In bare repos: uses fetch with refspec (no working tree needed).
# In non-bare repos: uses checkout + pull.
# Kept for `--update-local-main` opt-in path and for cleanup_merged_worktrees
# (post-cleanup main advancement).
update_branch_ref() {
  local branch="$1"
  echo -e "${BLUE}Updating $branch...${NC}"
  if [[ "$IS_BARE" == "true" && "$IS_IN_WORKTREE" != "true" ]]; then
    # Bare repo root: no working tree, so use fetch with refspec
    if git fetch origin "$branch:$branch" 2>/dev/null; then
      echo -e "${GREEN}Updated $branch to latest (via fetch)${NC}"
    elif git fetch origin "$branch" 2>/dev/null; then
      # Fast-forward failed but fetch succeeded -- force-update local ref to match remote.
      # Safe because direct commits to main are prohibited (hook-enforced).
      if git update-ref "refs/heads/$branch" "origin/$branch"; then
        echo -e "${YELLOW}Warning: Could not fast-forward local $branch -- force-updated to origin/$branch${NC}"
      else
        echo -e "${RED}Error: could not force-update refs/heads/$branch${NC}"
      fi
    fi
  else
    git checkout "$branch"
    git pull origin "$branch" || true
  fi
}

# Copy .env files from main repo to worktree
copy_env_files() {
  local worktree_path="$1"

  echo -e "${BLUE}Copying environment files...${NC}"

  # Find all .env* files in root (excluding .env.example which should be in git)
  local env_files=()
  for f in "$GIT_ROOT"/.env*; do
    if [[ -f "$f" ]]; then
      local basename=$(basename "$f")
      # Skip .env.example (that's typically committed to git)
      if [[ "$basename" != ".env.example" ]]; then
        env_files+=("$basename")
      fi
    fi
  done

  if [[ ${#env_files[@]} -eq 0 ]]; then
    echo -e "  ${YELLOW}ℹ️  No .env files found in main repository${NC}"
    return
  fi

  local copied=0
  for env_file in "${env_files[@]}"; do
    local source="$GIT_ROOT/$env_file"
    local dest="$worktree_path/$env_file"

    if [[ -f "$dest" ]]; then
      echo -e "  ${YELLOW}⚠️  $env_file already exists, backing up to ${env_file}.backup${NC}"
      cp "$dest" "${dest}.backup"
    fi

    cp "$source" "$dest"
    echo -e "  ${GREEN}✓ Copied $env_file${NC}"
    copied=$((copied + 1))
  done

  echo -e "  ${GREEN}✓ Copied $copied environment file(s)${NC}"
}

# Install dependencies in a newly created worktree
install_deps() {
  local worktree_path="$1"

  # --- Root-level dependency install ---
  if [[ -f "$worktree_path/package.json" ]] && [[ ! -d "$worktree_path/node_modules" ]]; then
    if ! command -v bun &>/dev/null; then
      echo -e "  ${YELLOW}Warning: bun not found -- install root dependencies manually${NC}" >&2
    else
      echo -e "${BLUE}Installing dependencies...${NC}"
      local install_output
      if install_output=$(bun install --frozen-lockfile --cwd "$worktree_path" 2>&1); then
        echo -e "  ${GREEN}Dependencies installed${NC}"
      else
        echo -e "  ${YELLOW}Warning: bun install failed -- run manually in the worktree${NC}" >&2
        echo "  $install_output" >&2
      fi
    fi
  fi

  # --- Subdirectory dependency install ---
  # Scan apps/*/ for package.json files and install per-directory.
  # Follows the same null-glob-safe pattern as copy_env_files().
  local app_dir
  for app_dir in "$worktree_path"/apps/*/; do
    [[ -d "$app_dir" ]] || continue
    [[ -f "$app_dir/package.json" ]] || continue
    [[ -d "$app_dir/node_modules" ]] && continue

    local app_name
    app_name=$(basename "$app_dir")

    local -a install_cmd=()
    if [[ -f "$app_dir/bun.lockb" ]] || [[ -f "$app_dir/bun.lock" ]]; then
      if command -v bun &>/dev/null; then
        install_cmd=(bun install --frozen-lockfile --cwd "$app_dir")
      else
        echo -e "  ${YELLOW}Warning: $app_name has bun lockfile but bun not found -- skip${NC}" >&2
        continue
      fi
    elif [[ -f "$app_dir/package-lock.json" ]]; then
      if command -v npm &>/dev/null; then
        install_cmd=(npm ci --prefix "$app_dir")
      else
        echo -e "  ${YELLOW}Warning: $app_name has package-lock.json but npm not found -- skip${NC}" >&2
        continue
      fi
    elif [[ -f "$app_dir/yarn.lock" ]]; then
      if command -v yarn &>/dev/null; then
        install_cmd=(yarn install --frozen-lockfile --cwd "$app_dir")
      else
        echo -e "  ${YELLOW}Warning: $app_name has yarn.lock but yarn not found -- skip${NC}" >&2
        continue
      fi
    else
      echo -e "  ${YELLOW}Warning: $app_name has package.json but no lockfile -- skip${NC}" >&2
      continue
    fi

    echo -e "${BLUE}Installing dependencies for $app_name...${NC}"
    local app_install_output
    if app_install_output=$("${install_cmd[@]}" 2>&1); then
      echo -e "  ${GREEN}$app_name dependencies installed${NC}"
    else
      echo -e "  ${YELLOW}Warning: $app_name install failed -- run manually${NC}" >&2
      echo "  $app_install_output" >&2
    fi
  done
}

# Auto-heal a stale, EMPTY orphan branch left behind by a prior aborted
# create/one-shot run, so a fresh create of the same branch proceeds cleanly
# instead of stranding the operator with a hand-cleanup step (the failure a
# prior aborted 2026-07-05 run hit: it had pushed `feat-one-shot-<name>-*` with
# zero commits and no PR, and the next attempt had to be rescued by a manual
# `git push origin --delete`).
#
# STRICTLY SCOPED — the auto-delete only ever fires when ALL hold:
#   1. the branch name EXACTLY equals the one this run is about to create
#      (so we only touch our own aborted-attempt namespace, never a sibling's);
#   2. it is provably EMPTY — 0 commits ahead of its base (origin/<from>);
#   3. no LIVE (open/merged) PR is attached (a parallel session may have opened a
#      draft before committing — that collision is left untouched, never healed).
# Real work (commits) or a live PR is left untouched and logged for the operator's
# run log (these warnings are informational only — no automated caller gate
# consumes heal's output; one-shot's Step 0a.5 collision gate is issue-ref-based
# and runs BEFORE create). Fully fail-open: any probe/network/auth failure warns
# and returns 0 — healing must NEVER block worktree creation. Runs identically
# from the CLI and the web (Concierge) surface, since both call this script's
# `create`/`feature` path — that is the CLI/web parity guarantee.
heal_stale_branch() {
  local branch="$1"
  local from_branch="${2:-main}"
  [[ -n "$branch" ]] || return 0

  # A branch checked out in ANY worktree is ACTIVE, not a stale orphan — never
  # heal it (guards both the remote delete and the local prune below in one place;
  # a checked-out branch is exactly the thing we must not touch).
  if git worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/$branch"; then
    return 0
  fi

  local remote_ref="refs/remotes/origin/$branch"

  # Base to measure "empty" against: the freshly-fetched origin/<from>, else the
  # local <from>. If neither resolves we cannot judge emptiness — bail rather than
  # risk deleting a branch that only LOOKS empty against a missing base. This
  # deliberately does NOT reuse fetch_origin_branch_base(): that helper falls back
  # to FETCH_HEAD / the literal branch name (never bails), which would be an unsafe
  # emptiness baseline here — heal must bail, not measure against a wrong base.
  git fetch origin "$from_branch" >/dev/null 2>&1 || true
  local base_ref
  if git rev-parse --verify --quiet "refs/remotes/origin/$from_branch" >/dev/null 2>&1; then
    base_ref="refs/remotes/origin/$from_branch"
  elif git rev-parse --verify --quiet "refs/heads/$from_branch" >/dev/null 2>&1; then
    base_ref="refs/heads/$from_branch"
  else
    return 0
  fi

  # --- Remote orphan ---
  # Resolve the remote tip via a direct ls-remote query (a SHA), NOT a cached
  # refs/remotes/origin/<branch> tracking ref — bare clones created without the
  # standard `+refs/heads/*:refs/remotes/origin/*` fetch refspec never populate
  # those tracking refs, so relying on them silently skips the heal. The fetch
  # brings the tip's objects local so rev-list can measure it.
  git fetch origin "$branch" >/dev/null 2>&1 || true
  # Full `refs/heads/<branch>` (not the bare name) so ls-remote's tail-at-slash
  # matching can't false-match a suffix branch (e.g. `sub/<branch>`). The trailing
  # `|| remote_sha=""` keeps a non-zero ls-remote (offline) set -e-safe.
  local remote_sha
  remote_sha="$(git ls-remote --heads origin "refs/heads/$branch" 2>/dev/null | awk 'NR==1{print $1}')" || remote_sha=""
  if [[ -n "$remote_sha" ]]; then
    local ahead
    ahead="$(git rev-list --count "$base_ref..$remote_sha" 2>/dev/null || echo unknown)"
    if [[ "$ahead" == "0" ]]; then
      # Empty vs base. Refuse to delete if a LIVE PR exists. The PR probe has THREE
      # outcomes — and the error case must fail SAFE (asymmetry matters: unlike the
      # emptiness probe, a wrong "no PR" answer deletes a parallel session's draft):
      #   gh ABSENT          → policy: exact-name + empty is sufficient evidence of
      #                        a prior aborted run → allow delete.
      #   gh present, OK      → trust the count (0 = no live PR → delete).
      #   gh present, ERRORED → unknown (auth/rate-limit/network) → do NOT delete;
      #                        a transient gh outage must not yank a live PR's branch.
      local pr_check="absent" live_pr="0"
      if command -v gh >/dev/null 2>&1; then
        if live_pr="$(gh pr list --head "$branch" --state all \
             --json state --jq '[.[] | select(.state=="OPEN" or .state=="MERGED")] | length' 2>/dev/null)" \
           && [[ -n "$live_pr" ]]; then
          pr_check="ok"
        else
          pr_check="error"; live_pr=""
        fi
      fi
      if [[ "$pr_check" == "error" ]]; then
        headless_or_stderr warn "remote branch origin/$branch is empty but gh could not confirm PR state — NOT auto-deleting (fail-safe); logged for the operator's run log"
      elif [[ "$live_pr" == "0" ]]; then
        if git push origin --delete "$branch" >/dev/null 2>&1; then
          headless_or_stderr warn "auto-healed stale empty remote branch origin/$branch (0 commits ahead of $from_branch, no live PR) — left by a prior aborted run"
        else
          headless_or_stderr warn "stale empty remote branch origin/$branch detected but delete failed (offline / no push auth) — continuing; a fresh push will fast-forward it"
        fi
      else
        headless_or_stderr warn "remote branch origin/$branch is empty but has a live PR — NOT auto-deleting; logged for the operator's run log"
      fi
    else
      headless_or_stderr warn "remote branch origin/$branch has $ahead commit(s) ahead of $from_branch — NOT auto-deleting (real work); logged for the operator's run log"
    fi
  else
    # Not on remote (already deleted, or never pushed). Prune any stale tracking ref.
    git update-ref -d "$remote_ref" 2>/dev/null || true
  fi

  # --- Local orphan ref (would block `git worktree add -b <branch>`) ---
  # The not-checked-out condition is already guaranteed by the early return at the
  # top, so only the emptiness gate remains. `git branch -D` skips git's merge
  # check, but `lahead == 0` (0 commits ahead of base) is the correct substitute:
  # a ref with unique unpushed commits reads lahead > 0 and is kept.
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    local lahead
    lahead="$(git rev-list --count "$base_ref..refs/heads/$branch" 2>/dev/null || echo unknown)"
    if [[ "$lahead" == "0" ]]; then
      if git branch -D "$branch" >/dev/null 2>&1; then
        headless_or_stderr warn "auto-healed stale empty local branch $branch (0 commits ahead of $from_branch) — would have blocked worktree add"
      fi
    fi
  fi

  return 0
}

# Create a new worktree
create_worktree() {
  if ! ensure_bare_config; then
    echo -e "${RED}Cannot create worktree — wedged on an unremovable git lock (see SOLEUR_GIT_LOCK_UNREMOVABLE above).${NC}" >&2
    exit 1
  fi
  local branch_name="$1"
  local from_branch="${2:-main}"

  if [[ -z "$branch_name" ]]; then
    echo -e "${RED}Error: Branch name required${NC}"
    exit 1
  fi

  local worktree_path="$WORKTREE_DIR/$branch_name"

  # Check if worktree already exists
  if [[ -d "$worktree_path" ]]; then
    echo -e "${YELLOW}Worktree already exists at: $worktree_path${NC}"
    local response="n"
    if [[ "$YES_FLAG" == "true" ]]; then
      response="y"
    else
      echo -e "Switch to it instead? (y/n)"
      read -r response
    fi
    if [[ "$response" == "y" ]]; then
      # Re-entry is a working session too. `--yes create` sets response=y, so
      # this is the path a RESUMED one-shot/work run takes — and without a
      # lease here that session is reapable for its whole duration. The lease
      # belongs to "worked in", not to "created".
      #
      # Deliberately INSIDE the y-branch: on `n` the caller does not enter the
      # worktree and must not lease it. Hoisting this above the branch would
      # stamp a >=4h lease on a worktree nobody entered, permanently blocking
      # cleanup for it.
      #
      # `notrap`: this process did not create the worktree and may be a
      # co-tenant of a live session. acquire_lease is last-writer-wins with no
      # ownership check, so re-acquiring rewrites pid/started_at — arming the
      # release trap here would make THIS process release_lease's in-process
      # owner, and a SIGINT would then delete the INCUMBENT's protection.
      _acquire_worktree_lease "$branch_name" create-reentry notrap || true
      switch_worktree "$branch_name"
    fi
    return
  fi

  echo -e "${BLUE}Creating worktree: $branch_name${NC}"
  echo "  From: $from_branch"
  echo "  Path: $worktree_path"
  echo ""
  local response
  if [[ "$YES_FLAG" == "true" ]]; then
    response="y"
  else
    echo "Proceed? (y/n)"
    read -r response
  fi

  if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    return
  fi

  # Auto-heal a stale empty orphan branch from a prior aborted run before we
  # try to (re)create the branch of the same name — see heal_stale_branch().
  heal_stale_branch "$branch_name" "$from_branch"

  # Create worktree
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  # Base on origin/<from> by default (avoids local-ref lock contention, #3741);
  # --update-local-main opt-in keeps the legacy behavior.
  local BASE_REF TRACK_FLAG
  resolve_base_ref "$from_branch"

  # Lease BEFORE the worktree exists, not after it is furnished.
  #
  # The lease is keyed by BRANCH NAME and needs nothing on disk, so nothing
  # forces it later — and everything after `git worktree add` is a reap window.
  # A branch freshly cut from origin/main is 0 commits ahead, so it appears in
  # `git branch --merged main`; the 10-minute recent-commit grace reads
  # origin/main's tip (hours old); the tree is clean because node_modules and
  # .env are gitignored. So during verify + config + identity + env copy +
  # install_deps (a full `bun install` per workspace — minutes) EVERY reap guard
  # falls through and only the lease can save it.
  #
  # Measured 2026-08-09: a `--yes create` worktree checked out all 13,354 files
  # and was destroyed before verify_worktree_created ran. Acquiring after
  # install_deps — which is where parity with create_for_feature originally put
  # it — would not have prevented that. Parity of FORM is not parity of COVER.
  _acquire_worktree_lease "$branch_name" create trap || true

  echo -e "${BLUE}Creating worktree from $BASE_REF...${NC}"
  # shellcheck disable=SC2086 # intentional unquoted $TRACK_FLAG: empty string must elide
  git worktree add $TRACK_FLAG -b "$branch_name" "$worktree_path" "$BASE_REF"

  # Verify BEFORE fixing config — most honest check of worktree health
  verify_worktree_created "$worktree_path" "$branch_name" "$BASE_REF"

  # `git worktree add` can leave the shared config carrying the pair that wedges every
  # worktree (extensions.worktreeConfig + core.bare) — normalize it (#7394). The previous
  # comment here described the retired polarity ("writes core.bare=false to shared config").
  if ! ensure_bare_config; then
    echo -e "${RED}Worktree created but shared-config repair is wedged on an unremovable git lock (see SOLEUR_GIT_LOCK_UNREMOVABLE above).${NC}" >&2
    exit 1
  fi

  # Defense in depth (#7394): pin core.bare=false in the NEW worktree's OWN
  # config.worktree so it stays correct even if per-worktree resolution is re-enabled
  # later by another tool. Inert while the extension is absent, so non-fatal by design.
  seed_worktree_bare_false "$worktree_path" || true

  # Respect a host-seeded owner identity; only set from --global when local is absent
  # (#6184). Wrapped in `if !` so a genuine identity wedge fails LOUD with context +
  # exit 1 instead of a bare set -e abort (see ensure_worktree_identity's set -e note).
  if ! ensure_worktree_identity "$worktree_path"; then
    echo -e "${RED}Cannot create worktree — git identity could not be set (see SOLEUR_GIT_LOCK_IDENTITY_WEDGED above).${NC}" >&2
    exit 1
  fi

  # Copy environment files
  copy_env_files "$worktree_path"

  # Install dependencies
  install_deps "$worktree_path"

  echo -e "${GREEN}✓ Worktree created successfully!${NC}"
  # Say so on `create` too. Until #5454 only create_for_feature printed this,
  # so the operator-visible evidence read "only `feature` leases" — which was
  # true, and was the bug.
  echo -e "${BLUE}Worktree leased; release on session exit.${NC}"
  echo ""
  echo "To switch to this worktree:"
  echo -e "${BLUE}cd $worktree_path${NC}"
  echo ""
}

# Create a worktree for a feature with spec directory
# Simplified version: no prompts, just creates everything
create_for_feature() {
  if ! ensure_bare_config; then
    echo -e "${RED}Cannot create worktree — wedged on an unremovable git lock (see SOLEUR_GIT_LOCK_UNREMOVABLE above).${NC}" >&2
    exit 1
  fi
  local name="$1"
  local from_branch="${2:-main}"

  if [[ -z "$name" ]]; then
    echo -e "${RED}Error: Feature name required${NC}"
    echo "Usage: worktree-manager.sh feature <name> [from-branch]"
    exit 1
  fi

  local branch_name="feat-$name"
  local worktree_path="$WORKTREE_DIR/$branch_name"
  local spec_dir="$worktree_path/knowledge-base/project/specs/$branch_name"

  # Check if worktree already exists
  if [[ -d "$worktree_path" ]]; then
    echo -e "${YELLOW}Worktree already exists: $worktree_path${NC}"
    echo -e "${BLUE}Spec directory: $spec_dir${NC}"
    # Same re-entry hole as create_worktree's early return: a resumed session
    # lands here and, without this, holds no lease for its whole run. There is
    # no y/n arm on this path — reaching here always means the caller proceeds
    # with the existing worktree — so acquire unconditionally.
    # `notrap` for the same reason as create_worktree's re-entry arm: this
    # process may be a co-tenant, and arming the release trap here would let a
    # SIGINT delete a live incumbent's lease. Before PR #7373 this arm registered
    # no trap at all, so adding one would have been a NEW deletion path on a
    # previously-safe surface.
    _acquire_worktree_lease "$branch_name" feature-reentry notrap || true
    return 0
  fi

  echo -e "${BLUE}Creating feature: $name${NC}"
  echo "  Branch: $branch_name"
  echo "  Worktree: $worktree_path"
  echo "  Spec dir: $spec_dir"
  echo ""

  # Auto-heal a stale empty orphan branch from a prior aborted run before we
  # try to (re)create the branch of the same name — see heal_stale_branch().
  heal_stale_branch "$branch_name" "$from_branch"

  # Ensure directories exist
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  # Base on origin/<from> by default (avoids local-ref lock contention, #3741).
  # --update-local-main opt-in keeps the legacy behavior for operators who want
  # the local <from> ref fast-forwarded.
  local base_ref
  local track_flag=""
  if [[ "$UPDATE_LOCAL_MAIN" == "true" ]]; then
    update_branch_ref "$from_branch"
    base_ref="$from_branch"
  else
    base_ref="$(fetch_origin_branch_base "$from_branch")"
    # --no-track is load-bearing: without it, branch.<new>.merge would be set
    # to refs/heads/<from>, breaking bare `git push` from inside the worktree.
    track_flag="--no-track"
  fi

  # Lease BEFORE the worktree exists — same reasoning as create_worktree, and
  # the same reap window (verify + config + identity + env copy + install_deps)
  # applies here. This placement is what parity should have meant.
  _acquire_worktree_lease "$branch_name" feature trap || true

  echo -e "${BLUE}Creating worktree from $base_ref...${NC}"
  # shellcheck disable=SC2086 # intentional unquoted $track_flag: empty string must elide
  git worktree add $track_flag -b "$branch_name" "$worktree_path" "$base_ref"

  # Verify BEFORE fixing config — most honest check of worktree health
  verify_worktree_created "$worktree_path" "$branch_name" "$base_ref"

  # `git worktree add` can leave the shared config carrying the pair that wedges every
  # worktree (extensions.worktreeConfig + core.bare) — normalize it (#7394). The previous
  # comment here described the retired polarity ("writes core.bare=false to shared config").
  if ! ensure_bare_config; then
    echo -e "${RED}Worktree created but shared-config repair is wedged on an unremovable git lock (see SOLEUR_GIT_LOCK_UNREMOVABLE above).${NC}" >&2
    exit 1
  fi

  # Defense in depth (#7394): pin core.bare=false in the NEW worktree's OWN
  # config.worktree so it stays correct even if per-worktree resolution is re-enabled
  # later by another tool. Inert while the extension is absent, so non-fatal by design.
  seed_worktree_bare_false "$worktree_path" || true

  # Respect a host-seeded owner identity; only set from --global when local is absent
  # (#6184). Wrapped in `if !` so a genuine identity wedge fails LOUD with context +
  # exit 1 instead of a bare set -e abort (see ensure_worktree_identity's set -e note).
  if ! ensure_worktree_identity "$worktree_path"; then
    echo -e "${RED}Cannot create worktree — git identity could not be set (see SOLEUR_GIT_LOCK_IDENTITY_WEDGED above).${NC}" >&2
    exit 1
  fi

  # Create spec directory inside the worktree so it's tracked on the feature branch
  if [[ -d "$worktree_path/knowledge-base" ]]; then
    mkdir -p "$spec_dir"
    echo -e "${GREEN}Created spec directory: $spec_dir${NC}"
  fi

  # Copy environment files
  copy_env_files "$worktree_path"

  # Install dependencies
  install_deps "$worktree_path"

  # Lease acquisition moved ABOVE `git worktree add` (see the note there) — the
  # window between creating the worktree and finishing install_deps was the one
  # in which a reap was actually observed.

  # Push -u immediately so the branch has a remote anchor before the operator
  # writes any local commits. Per plan AC line 158, verify the remote ref
  # exists via `git ls-remote` after push so a silent push-failure does NOT
  # leave a local-only branch that a later `cleanup-merged` could reap.
  local push_ok=true
  if ! git -C "$worktree_path" push -u origin "$branch_name" 2>/dev/null; then
    push_ok=false
  elif [[ -z "$(git -C "$worktree_path" ls-remote --heads origin "$branch_name" 2>/dev/null)" ]]; then
    push_ok=false
  fi
  if [[ "$push_ok" == "false" ]]; then
    # Emit BOTH the human warn and a structured marker on stdout — the
    # marker is grep-able by orchestrating agents so push failure surfaces
    # under `claude --bg` where warn-to-log-file is otherwise invisible.
    echo "SOLEUR_FEATURE_PUSH_FAILED branch=$branch_name"
    headless_or_stderr warn "git push -u origin $branch_name failed; branch is local-only and may be reaped after the lease expires. Run \`git push -u origin $branch_name\` once network is available."
  fi

  echo ""
  echo -e "${GREEN}Feature setup complete!${NC}"
  echo -e "${BLUE}Worktree leased; release on session exit.${NC}"
  echo ""
  echo "Next steps:"
  echo -e "  1. ${BLUE}cd $worktree_path${NC}"
  echo -e "  2. Create spec: ${BLUE}knowledge-base/project/specs/$branch_name/spec.md${NC}"
  echo -e "  3. Open draft PR: ${BLUE}bash $SCRIPT_DIR/worktree-manager.sh draft-pr${NC}"
  echo ""
}

# List all worktrees
list_worktrees() {
  echo -e "${BLUE}Available worktrees:${NC}"
  echo ""

  if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo -e "${YELLOW}No worktrees found${NC}"
    return
  fi

  local count=0
  for worktree_path in "$WORKTREE_DIR"/*; do
    if [[ -d "$worktree_path" && -e "$worktree_path/.git" ]]; then
      count=$((count + 1))
      local worktree_name=$(basename "$worktree_path")
      local branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

      if [[ "$PWD" == "$worktree_path" ]]; then
        echo -e "${GREEN}✓ $worktree_name${NC} (current) → branch: $branch"
      else
        echo -e "  $worktree_name → branch: $branch"
      fi
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}No worktrees found${NC}"
  else
    echo ""
    echo -e "${BLUE}Total: $count worktree(s)${NC}"
  fi

  echo ""
  if [[ "$IS_BARE" == "true" ]]; then
    echo -e "${YELLOW}Bare root (no working tree):${NC}"
    echo "  Path: $GIT_ROOT"
  else
    echo -e "${BLUE}Main repository:${NC}"
    local main_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo "  Branch: $main_branch"
    echo "  Path: $GIT_ROOT"
  fi
}

# Switch to a worktree
switch_worktree() {
  local worktree_name="$1"

  if [[ -z "$worktree_name" ]]; then
    if [[ "$YES_FLAG" == "true" ]]; then
      echo -e "${RED}Error: --yes requires a worktree name argument${NC}"
      exit 1
    fi
    list_worktrees
    echo -e "${BLUE}Switch to which worktree? (enter name)${NC}"
    read -r worktree_name
  fi

  local worktree_path="$WORKTREE_DIR/$worktree_name"

  if [[ ! -d "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree not found: $worktree_name${NC}"
    echo ""
    list_worktrees
    exit 1
  fi

  # Entering a worktree IS working in it. `switch|go` was the last entry point
  # that took an existing worktree and leased nothing — the same hole the two
  # early-return arms had, one function over. A session that switches in and
  # works for hours was reapable for all of them.
  #
  # `notrap` for the same reason as the early-return arms: switch by definition
  # enters a worktree this process did not create, so it may be a co-tenant of a
  # live session. Arming the release trap here would make THIS short-lived CLI
  # release_lease's in-process owner, and a signal would delete the incumbent's
  # protection.
  #
  # Keyed on the DIRECTORY name, which is what cleanup_merged_worktrees looks up
  # (`is_lease_active "$(basename "$worktree_path")"`). For everything create or
  # feature made, that equals the branch name.
  #
  # Non-fatal: switching is a navigation verb and must not fail because the lease
  # layer is unavailable. The marker inside the helper is what makes an
  # unprotected switch visible instead of silent.
  _acquire_worktree_lease "$worktree_name" switch notrap || true

  echo -e "${GREEN}Switching to worktree: $worktree_name${NC}"
  cd "$worktree_path"
  echo -e "${BLUE}Now in: $(pwd)${NC}"
}

# Copy env files to an existing worktree (or current directory if in a worktree)
copy_env_to_worktree() {
  local worktree_name="$1"
  local worktree_path

  if [[ -z "$worktree_name" ]]; then
    # Check if we're currently in a worktree
    local current_dir=$(pwd)
    if [[ "$current_dir" == "$WORKTREE_DIR"/* ]]; then
      worktree_path="$current_dir"
      worktree_name=$(basename "$worktree_path")
      echo -e "${BLUE}Detected current worktree: $worktree_name${NC}"
    else
      echo -e "${YELLOW}Usage: worktree-manager.sh copy-env [worktree-name]${NC}"
      echo "Or run from within a worktree to copy to current directory"
      list_worktrees
      return 1
    fi
  else
    worktree_path="$WORKTREE_DIR/$worktree_name"

    if [[ ! -d "$worktree_path" ]]; then
      echo -e "${RED}Error: Worktree not found: $worktree_name${NC}"
      list_worktrees
      return 1
    fi
  fi

  copy_env_files "$worktree_path"
  echo ""
}

# Clean up completed worktrees
cleanup_worktrees() {
  if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo -e "${YELLOW}No worktrees to clean up${NC}"
    return
  fi

  echo -e "${BLUE}Checking for completed worktrees...${NC}"
  echo ""

  local found=0
  local to_remove=()

  for worktree_path in "$WORKTREE_DIR"/*; do
    if [[ -d "$worktree_path" && -e "$worktree_path/.git" ]]; then
      local worktree_name=$(basename "$worktree_path")

      # Skip if current worktree
      if [[ "$PWD" == "$worktree_path" ]]; then
        echo -e "${YELLOW}(skip) $worktree_name - currently active${NC}"
        continue
      fi

      found=$((found + 1))
      to_remove+=("$worktree_path")
      echo -e "${YELLOW}• $worktree_name${NC}"
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo -e "${GREEN}No inactive worktrees to clean up${NC}"
    return
  fi

  echo ""
  local response
  if [[ "$YES_FLAG" == "true" ]]; then
    response="y"
  else
    echo -e "Remove $found worktree(s)? (y/n)"
    read -r response
  fi

  if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    return
  fi

  echo -e "${BLUE}Cleaning up worktrees...${NC}"
  for worktree_path in "${to_remove[@]}"; do
    local worktree_name=$(basename "$worktree_path")
    git worktree remove "$worktree_path" --force 2>/dev/null || true
    echo -e "${GREEN}✓ Removed: $worktree_name${NC}"
  done

  # Clean up empty directory if nothing left
  if [[ -z "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
    rmdir "$WORKTREE_DIR" 2>/dev/null || true
  fi

  echo -e "${GREEN}Cleanup complete!${NC}"
}

# Archive KB artifact files matching a slug from a flat directory
# Usage: archive_kb_files <dir> <slug> <label> <verbose>
archive_kb_files() {
  local dir="$1"
  local slug="$2"
  local label="$3"
  local verbose="$4"
  [[ -d "$dir" ]] || return 0
  local archive_dir="$dir/archive"
  mkdir -p "$archive_dir"
  for f in "$dir"/*"$slug"*; do
    [[ -f "$f" && "$f" != */archive/* ]] || continue
    local fname ts
    fname=$(basename "$f")
    ts="$(date +%Y-%m-%d-%H%M%S)"
    if ! mv "$f" "$archive_dir/$ts-$fname" 2>/dev/null; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not archive $label $fname${NC}"
    fi
  done
}

# Clean up orphan directories in .worktrees/ that aren't registered as git worktrees.
# These can be left behind by interrupted worktree creation, manual deletion of .git files,
# or other edge cases where the directory exists but git doesn't know about it.
cleanup_orphan_worktree_dirs() {
  local verbose="${1:-false}"
  [[ ! -d "$WORKTREE_DIR" ]] && return 0

  # Build set of registered worktree paths. FAIL CLOSED: this list is the ONLY
  # thing standing between a live worktree and `rm -rf`. `git worktree list` can
  # fail wholesale under the sandbox's masked-config wedge (the same condition
  # sweep_stale_git_locks exists for), and a swallowed failure yields an EMPTY
  # registry — under which every directory reads as unregistered and the reaper
  # deletes the entire tree. Refuse to reap rather than reap everything.
  local -A registered_paths
  local wt_list
  # Capture stdout ONLY (`2>/dev/null`, not `2>&1`): the parsed value is an
  # allowlist that decides what survives `rm -rf`, so folding git's stderr into
  # it would let a diagnostic line be parsed as registry content. Errors are
  # signalled by the exit status, which is what the fail-closed branch reads.
  if ! wt_list=$(git worktree list --porcelain 2>/dev/null); then
    echo "SOLEUR_ORPHAN_REGISTRY_UNAVAILABLE reason=git-worktree-list-failed errno=OTHER hint=\"refusing to reap; every dir would read as unregistered — see git-worktree SKILL.md §Sharp Edges\""
    headless_or_stderr warn "cleanup_orphan_worktree_dirs: 'git worktree list' failed; skipping orphan reap (fail-closed)"
    return 0
  fi
  while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
      registered_paths["${line#worktree }"]=1
    fi
  done <<<"$wt_list"

  local orphans_cleaned=0
  local -a orphans_failed=()
  local -a orphans_failed_errno=()
  for dir in "$WORKTREE_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue
    # Normalize path (remove trailing slash). Load-bearing beyond cosmetics: it
    # is what makes `rm -rf -- "$dir"` unlink a SYMLINK rather than descend into
    # its target and delete out-of-tree content.
    dir="${dir%/}"
    # A symlink into the tree is never ours to reap — unlink-only is the safe
    # behaviour the trailing-slash strip happens to give us, but pin it
    # explicitly rather than relying on that side effect.
    if [[ -L "$dir" ]]; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) orphan $(basename "$dir") - symlink, not reaping${NC}"
      continue
    fi
    # A BARE repository has no `.git` entry at all — it IS the git directory —
    # so every `.git`-based test reads it as "definitely orphaned" and reaps it,
    # taking its refs and objects with it (verified: a bare repo parked here is
    # destroyed by the `-e` test alone). Detect the bare layout positively and
    # never reap it. This repo is itself bare, so a parked bare clone under
    # .worktrees/ is a plausible thing for an operator or tool to create.
    if [[ -f "$dir/HEAD" && -d "$dir/objects" && -d "$dir/refs" ]]; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) orphan $(basename "$dir") - bare repository, not reaping${NC}"
      continue
    fi
    if [[ -z "${registered_paths[$dir]:-}" ]]; then
      # Not a registered worktree — reap only when there is NO `.git` entry of
      # any kind. `-e`, not `-f`: a linked worktree has a `.git` FILE, but a
      # nested full `git clone` has a `.git` DIRECTORY, and `-f` reads that as
      # "definitely orphaned" and destroys the clone (with any uncommitted work
      # in it). The honest-reporting fix below would then faithfully announce
      # the destruction, which is worse, not better.
      if [[ ! -e "$dir/.git" ]]; then
        # #7102 — the exit status is the whole point: a `rm -rf` that fails
        # (root-owned Supabase bind-mount residue is the recurring cause) used
        # to increment the counter anyway, so the summary announced removals
        # for directories still on disk. Redirection order is load-bearing:
        # `2>&1 >/dev/null` sends stderr to the capture and THEN stdout to
        # /dev/null, so rm_err holds only the error text. LC_ALL=C pins
        # strerror to English so _rm_errno maps the label reliably.
        # --one-file-system is defence-in-depth against a CROSS-DEVICE mount
        # appearing under a worktree: the flag skips any directory whose st_dev
        # differs from the command-line argument's. It does NOT protect against
        # a same-device bind mount, which shares st_dev and is descended into
        # normally — so do not read this as a general bind-mount guard. No such
        # mount exists under .worktrees/ today (`findmnt -T` shows one plain
        # ext4 device); the flag is cheap insurance, not a fix for an observed
        # case. GNU-only, like this script's existing `stat -c` / strerror
        # mapping — a BSD `rm` would reject it.
        local rm_err
        if rm_err=$(LC_ALL=C rm -rf --one-file-system -- "$dir" 2>&1 >/dev/null); then
          # Assignment form, never `(( orphans_cleaned++ ))` — that returns 1
          # at the old value 0 and aborts the caller under `set -e`.
          orphans_cleaned=$((orphans_cleaned + 1))
          [[ "$verbose" == "true" ]] && echo -e "${BLUE}Removed orphan directory: $(basename "$dir")${NC}"
        else
          orphans_failed+=("$dir")
          orphans_failed_errno+=("$(_rm_errno "$rm_err")")
        fi
      else
        [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) orphan $(basename "$dir") - has a .git entry (linked worktree or nested clone), not reaping${NC}"
      fi
    fi
  done

  if [[ $orphans_cleaned -gt 0 ]]; then
    [[ "$verbose" == "true" ]] && echo -e "${GREEN}Cleaned $orphans_cleaned orphan directory(ies)${NC}"
  fi

  # Unconditional — unlike the success summary. The default verbose=false path
  # is the one session-start, work Phase 0 and ship Phase 7 Step 4 actually run,
  # and a failure nobody is told about repeats silently on every later run.
  if [[ ${#orphans_failed[@]} -gt 0 ]]; then
    # ONE aggregate marker per invocation, never one per directory. The marker
    # extractor keeps the FIRST N markers per tool_response and stops at the
    # cap. Note the creation path cannot actually be starved here — it is a
    # separate invocation — and the markers that DO co-occur (ensure_bare_config
    # inside cleanup_merged_worktrees) are emitted before this reaper runs, so
    # first-N ordering already protects them. Aggregate anyway: an unbounded
    # per-directory producer is a log-volume and marker-length problem in its
    # own right, and the budget is a shared resource worth not spending. Every
    # failure is still named individually on stderr below.
    #
    # The names are sanitized because this loop is the ONLY one that handles
    # arbitrarily-named, UNREGISTERED directories: git refnames forbid control
    # characters, so the creation path cannot produce them, but any process can
    # `mkdir` a directory whose name embeds a newline. Interpolated raw into a
    # line-oriented sink, `$'x\nworktree wedge: forged'` emits a SECOND line
    # that matches the wedge pattern and forges a false platform-integrity page.
    # Collapse CR/LF/TAB and the quote/space characters that would also break
    # the key=value shape, and emit the basename only — the full path adds a
    # user-derived branch name to an off-box sink for no diagnostic gain.
    local failed_dir failed_names=""
    for failed_dir in "${orphans_failed[@]}"; do
      # Positive ALLOWLIST, not a denylist: a denylist of the characters that
      # broke the line format ("\n\r\t and space) still admits \v, \f, ESC and
      # U+2028/U+2029, the last of which splits lines in JSON log viewers even
      # though bash's own `.split("\n")` does not (cq-regex-unicode-separators).
      # Closed sets are the only ones that stay closed as sinks change.
      local safe_name="${failed_dir##*/}"
      safe_name="${safe_name//[^A-Za-z0-9._-]/_}"
      failed_names+="${failed_names:+,}${safe_name:0:64}"
    done
    # `cleaned=` is carried here, not only in the verbose-gated success summary,
    # so the success counter is OBSERVABLE on the default verbose=false path —
    # the one session-start, work Phase 0 and ship Phase 7 actually run. Without
    # it the counter has no reader at that verbosity, so a miscount there is
    # both undetectable and untestable, and only becomes visible later when
    # someone makes the summary unconditional. `${x[0]:-OTHER}` because a
    # desynced errno array must degrade to a label, never abort under `set -u`.
    echo "SOLEUR_ORPHAN_UNREMOVABLE count=${#orphans_failed[@]} cleaned=${orphans_cleaned} errno=${orphans_failed_errno[0]:-OTHER} names=$failed_names reason=rm-partial hint=\"partially-deleted orphans survive; see git-worktree SKILL.md §Sharp Edges\""

    echo -e "${YELLOW}Could not remove ${#orphans_failed[@]} orphan directory(ies):${NC}" >&2
    # Index over the array itself rather than a hand-maintained counter: the
    # errno read is then symmetric with the `:-OTHER` guard above, and a
    # desynced pair degrades to a label instead of aborting under `set -u`
    # (an unset array element is fatal regardless of `set -e`).
    local idx
    for idx in "${!orphans_failed[@]}"; do
      echo -e "${YELLOW}  - ${orphans_failed[idx]} (${orphans_failed_errno[idx]:-OTHER})${NC}" >&2
    done
    echo -e "${YELLOW}  Remediation: git-worktree SKILL.md §Sharp Edges${NC}" >&2
  fi

  # #7102 defect 3 — the function used to END on `[[ … ]] && echo`, so a
  # SUCCESSFUL clean at the default verbose=false returned 1. Both call sites
  # are bare inside cleanup_merged_worktrees under `set -e`, so that aborted
  # the caller mid-flight and silently skipped the tmp reapers after it.
  #
  # Belt-and-braces: the failure-summary block above already ends the function
  # on a zero-returning construct, so deleting this line does NOT currently
  # reintroduce the bug (measured — the suite stays green). It is here so the
  # invariant survives a future edit that appends another `[[ … ]] && echo`
  # tail. What the suite actually pins is the CONTRACT (rc=0 on every path),
  # not the presence of this statement.
  return 0
}

# Clean up worktrees for merged branches (detects [gone] and merged-to-main)
cleanup_merged_worktrees() {
  # Serialize concurrent cleanup-merged invocations across sibling sessions.
  # 5s is the operator-perception threshold; longer waits in headless mode
  # are invisible. Skip (don't fail) when contended — the holder will
  # finish the work and the next session-start cycle picks up any residue.
  if ! acquire_lock cleanup-merged 5; then
    headless_or_stderr warn "cleanup-merged lock contended; skipping"
    return 0
  fi
  # RETURN trap fires on any function-level return without clobbering EXIT.
  trap 'release_lock cleanup-merged' RETURN

  # Fix bare repo config if broken (defense-in-depth on every session start).
  # Guard the non-zero return so a wedged config lock does NOT abort the unrelated
  # session-start maintenance below (orphan-dir cleanup, tmp reclamation, runaway-
  # process kill). The loud SOLEUR_GIT_LOCK_UNREMOVABLE sentinel already printed.
  if ! ensure_bare_config; then
    headless_or_stderr warn "cleanup-merged: ensure_bare_config wedged on an unremovable git lock (see SOLEUR_GIT_LOCK_UNREMOVABLE above); continuing with remaining maintenance."
  fi

  # Expire genuinely abandoned leases BEFORE the reap loop consults them.
  # Previously the sweep ran only in the `create` subcommand, so a host that
  # runs cleanup-merged on a schedule but creates no worktrees never executed
  # the 24h backstop at all — leaving is_lease_active as the sole gate. It is
  # safe to run here precisely because the sweep now only deletes a dead-pid
  # lease once it is PAST its own window (session-state.sh), so this cannot
  # remove protection from a live session.
  #
  # GUARDED, for the reason stated ~40 lines above about the config-lock call:
  # this runs under `set -euo pipefail` and cleanup_merged_worktrees is invoked
  # bare, so ANY non-zero return here aborts everything after it — fetch-prune,
  # the whole reap loop, orphan-dir cleanup, tmp reclamation, runaway-kill.
  #
  # The sweep returns non-zero with no corrupt file involved: `_lease_read_field`
  # returns 1 both for a missing field and for a file that has vanished, and a
  # sibling releasing its lease between our glob and our read is an ordinary
  # race. This change makes that path HOT — a dead recorded pid is now the
  # common case, so those reads run for nearly every lease on every session
  # start. Failure direction is safe (nothing reaped), which is exactly what
  # makes it a SILENT disable rather than a visible break.
  sweep_orphan_leases || headless_or_stderr warn "cleanup-merged: lease sweep returned non-zero (concurrent release or truncated lease file); continuing — the reap loop re-checks each lease itself."

  # Determine output mode: verbose if TTY, quiet otherwise
  local verbose=false
  [[ -t 1 ]] && verbose=true

  # Fetch to update remote tracking info — guarded by a separate lock so an
  # interactive `git fetch` and our background cleanup don't collide on the
  # ref-update path. flock semantics are inode-bound, so acquiring a second
  # distinct lock name does not deadlock with cleanup-merged above.
  local fetch_error
  acquire_lock fetch-prune 30 || headless_or_stderr warn "fetch-prune lock contended; proceeding without"
  if ! fetch_error=$(git fetch --prune 2>&1); then
    release_lock fetch-prune
    [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not fetch from remote: $fetch_error${NC}"
    return 0
  fi
  release_lock fetch-prune

  # Find stale branches using three complementary detection methods:
  # 1. [gone] tracking: remote branch was deleted (e.g., GitHub auto-delete after PR merge)
  # 2. Merged to main: branch is fully merged but remote still exists (e.g., auto-delete disabled)
  # 3. GH-merged: squash-merged branches in the GitHub auto-delete propagation window
  local gone_branches
  gone_branches=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads 2>/dev/null | grep '\[gone\]' | cut -d' ' -f1 || true)

  local merged_branches
  # git branch uses: * = current, + = checked out in another worktree
  # Strip all prefix markers and whitespace, then exclude main/master and current branch
  merged_branches=$(git branch --merged main 2>/dev/null \
    | sed 's/^[*+[:space:]]*//' \
    | grep -v -E '^(main|master)$' \
    || true)

  # Squash-merged branches produce a new commit on main with a different SHA, so
  # they appear in neither [gone] nor --merged main during the auto-delete propagation
  # window. Query GitHub directly as the authoritative source of truth.
  local gh_merged_branches=""
  local _wt_branch
  while IFS= read -r _line; do
    if [[ "$_line" == "branch refs/heads/"* ]]; then
      _wt_branch="${_line#branch refs/heads/}"
      [[ "$_wt_branch" == "main" || "$_wt_branch" == "master" ]] && continue
      if printf '%s\n' "$gone_branches" "$merged_branches" | grep -qxF "$_wt_branch"; then continue; fi
      local _merged_count
      _merged_count=$(gh pr list --head "$_wt_branch" --state merged --limit 1 --json number --jq 'length' 2>/dev/null || echo "0")
      [[ "$_merged_count" == "1" ]] && gh_merged_branches+="${_wt_branch}"$'\n'
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  # Combine all three lists, deduplicate
  local all_stale_branches
  all_stale_branches=$(printf '%s\n%s\n%s' "$gone_branches" "$merged_branches" "$gh_merged_branches" | sort -u | sed '/^$/d' || true)

  if [[ -z "$all_stale_branches" ]]; then
    [[ "$verbose" == "true" ]] && echo -e "${GREEN}No merged branches to clean up${NC}"
    # Still check for orphan directories below
    cleanup_orphan_worktree_dirs "$verbose"
    return 0
  fi

  # Build a map of branch -> actual worktree path using git's porcelain output.
  # This is essential because branch names use slashes (feat/fix-x) but worktree
  # directories use hyphens (feat-fix-x), so we cannot construct paths from branch names.
  local -A branch_to_worktree
  local current_wt_path="" current_wt_branch=""
  while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
      current_wt_path="${line#worktree }"
    elif [[ "$line" == "branch refs/heads/"* ]]; then
      current_wt_branch="${line#branch refs/heads/}"
      branch_to_worktree["$current_wt_branch"]="$current_wt_path"
    elif [[ -z "$line" ]]; then
      current_wt_path=""
      current_wt_branch=""
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  local cleaned=()

  for branch in $all_stale_branches; do
    local worktree_path="${branch_to_worktree[$branch]:-}"
    local safe_branch
    safe_branch=$(echo "$branch" | tr '/' '-')
    # Skip if active worktree
    if [[ -n "$worktree_path" && "$PWD" == "$worktree_path"* ]]; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) $branch - currently active${NC}"
      continue
    fi

    # Skip if a sibling session holds an active lease on this worktree
    # (hostname matches and within the lease window — PID liveness is NOT
    # required; requiring it is what reaped two live worktrees on 2026-08-06).
    if [[ -n "$worktree_path" ]] && is_lease_active "$(basename "$worktree_path")"; then
      # Mode-accurate, and unconditional. Two reasons this is not `verbose`-gated
      # prose: `verbose` is `[[ -t 1 ]]`, so under `claude --bg` — the mode the
      # 2026-08-06 reaps ran in — it printed NOTHING; and when the lease library
      # is missing the stub returns 0 for every worktree, so "active lease" would
      # ASSERT an observation the gate had just admitted it cannot make.
      # NOT a SOLEUR_* sentinel. Skipping a leased worktree is the NORMAL, correct
      # outcome — mirroring it to telemetry would page on the happy path. The
      # anomalous state (no lease library, so this reads "leased" for everything)
      # has its own sentinel, emitted once at load rather than once per branch.
      if [[ "$_SS_LIB_MISSING" == "true" ]]; then
        echo "(skip) $branch - lease library missing, refusing to reap (fail-closed)"
      else
        echo "(skip) $branch - active lease"
      fi
      continue
    fi

    # Skip if worktree HEAD was committed to in the last 10 minutes — a
    # foreground operator working without a lease (e.g., pre-skill manual
    # session) still gets a grace window. Clock-skew guard: negative
    # delta = future-dated commit; treat as fresh.
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
      local last_commit_age
      last_commit_age=$(git -C "$worktree_path" log -1 --format=%ct HEAD 2>/dev/null || true)
      if [[ -n "$last_commit_age" ]]; then
        local _now=$(date +%s)
        local _delta=$(( _now - last_commit_age ))
        if (( _delta < 0 || _delta < 600 )); then
          [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) $branch - recent commit (<10min) or clock-skew${NC}"
          continue
        fi
      fi
    fi

    # Skip if worktree has uncommitted changes (safety check)
    # Always print this warning since uncommitted changes need user attention
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
      local status
      status=$(git -C "$worktree_path" status --porcelain 2>/dev/null)
      if [[ -n "$status" ]]; then
        echo -e "${YELLOW}(skip) $branch - has uncommitted changes${NC}"
        continue
      fi
    fi

    # Archive spec directory. Backward-compat for legacy pre-#2815 worktrees that
    # created specs at the bare root. New layout commits the spec inside the
    # worktree (git history is the canonical archive); the [[ -d ]] guard silently
    # skips when the bare-root dir does not exist.
    local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$safe_branch"
    if [[ -d "$spec_dir" ]]; then
      local archive_dir archive_name archive_path
      archive_dir="$(dirname "$spec_dir")/archive"
      archive_name="$(date +%Y-%m-%d-%H%M%S)-$safe_branch"
      archive_path="$archive_dir/$archive_name"

      mkdir -p "$archive_dir"
      if ! mv "$spec_dir" "$archive_path" 2>/dev/null; then
        [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not archive spec for $branch${NC}"
      fi
    fi

    # Extract feature slug by stripping all known branch prefixes
    local feature_slug="$safe_branch"
    feature_slug="${feature_slug#feat-}"
    feature_slug="${feature_slug#fix-}"
    feature_slug="${feature_slug#feature-}"

    # Archive brainstorms and plans matching the feature slug
    archive_kb_files "$GIT_ROOT/knowledge-base/project/brainstorms" "$feature_slug" "brainstorm" "$verbose"
    archive_kb_files "$GIT_ROOT/knowledge-base/project/plans" "$feature_slug" "plan" "$verbose"

    # Remove worktree if exists (use actual path from git, not constructed path)
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
      if ! git worktree remove "$worktree_path" 2>/dev/null; then
        # Retry with --force for edge cases (e.g., untracked files from interrupted archival)
        if ! git worktree remove "$worktree_path" --force 2>/dev/null; then
          [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not remove worktree for $branch${NC}"
          continue
        fi
      fi
    fi

    # Delete remote branch if it still exists (prevents stale remote refs from accumulating)
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      if git push origin --delete "$branch" 2>/dev/null; then
        [[ "$verbose" == "true" ]] && echo -e "${BLUE}Deleted remote branch: $branch${NC}"
      fi
    fi

    # Delete local branch
    if ! git branch -D "$branch" 2>/dev/null; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not delete branch $branch${NC}"
    fi

    cleaned+=("$branch")
  done

  # Output summary
  if [[ ${#cleaned[@]} -gt 0 ]]; then
    echo -e "${GREEN}Cleaned ${#cleaned[@]} merged worktree(s): ${cleaned[*]}${NC}"

    # After cleanup, update main checkout so next worktree branches from latest
    # Skip entirely for bare repos -- there is no working tree to update
    if [[ "$IS_BARE" == "true" ]]; then
      # Bare repos have no working tree -- use fetch with refspec to update the
      # local main ref directly (plain "fetch origin main" only updates FETCH_HEAD
      # and origin/main, leaving local main stale for new worktree creation)
      if git fetch origin main:main 2>/dev/null; then
        echo -e "${GREEN}Updated main to latest${NC}"
      elif git fetch origin main 2>/dev/null; then
        # Fast-forward failed but fetch succeeded -- force-update local ref to match remote.
        # Safe because direct commits to main are prohibited (hook-enforced).
        if git update-ref "refs/heads/main" "origin/main"; then
          echo -e "${YELLOW}Warning: Could not fast-forward local main -- force-updated to origin/main${NC}"
        else
          echo -e "${RED}Error: could not force-update refs/heads/main${NC}"
        fi
      fi
      # Auto-sync stale on-disk files so the next session reads current versions
      sync_bare_files
    else
      # Auto-reset stale index/working tree on main checkout.
      # Direct commits to main are prohibited (hook-enforced), so staged or
      # unstaged changes are always stale debris from index drift (e.g., fetch
      # moved HEAD but index was never updated). Reset to HEAD before pulling.
      if ! git -C "$GIT_ROOT" diff --quiet HEAD 2>/dev/null || ! git -C "$GIT_ROOT" diff --cached --quiet 2>/dev/null; then
        local stale_count
        stale_count=$(git -C "$GIT_ROOT" diff --cached --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "0")
        echo -e "${YELLOW}Resetting stale main checkout ($stale_count staged files)${NC}"
        git -C "$GIT_ROOT" reset --hard HEAD >/dev/null 2>&1
      fi
      local current_branch
      current_branch=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
        git -C "$GIT_ROOT" checkout main 2>/dev/null || git -C "$GIT_ROOT" checkout master 2>/dev/null || true
      fi
      local pull_output
      if pull_output=$(git -C "$GIT_ROOT" pull --ff-only origin main 2>&1); then
        echo -e "${GREEN}Updated main to latest${NC}"
      else
        echo -e "${YELLOW}Warning: Could not pull latest main: $pull_output${NC}"
      fi
    fi
  fi

  # Clean up orphan directories in .worktrees/ that aren't registered as git worktrees
  cleanup_orphan_worktree_dirs "$verbose"

  # Always clean up stale Claude tmp files (RAM-backed, can be huge)
  cleanup_claude_tmp

  # Reap stale Bash-sandbox temp the harness orphans directly under /tmp. No
  # settings.json/env lever exists to relocate or auto-clean it (verified against
  # Claude Code docs 2026-07-11), so this session-start sweep is the only lever.
  cleanup_stale_sandbox_tmp

  # Kill runaway processes that waste CPU (e.g., stuck gst-plugin-scanner)
  cleanup_runaway_processes

  return 0
}

# Clean up stale Claude Code temp files to reclaim RAM.
# Claude stores task output in /tmp/claude-<uid>/<project>/<session>/tasks/.
# These files sit on tmpfs (RAM-backed). Runaway task outputs can consume tens
# of GB and starve the system. This function identifies session directories that
# no longer correspond to a running Claude process and removes their task output.
cleanup_claude_tmp() {
  local uid
  uid=$(id -u)
  local claude_tmp="/tmp/claude-$uid"

  if [[ ! -d "$claude_tmp" ]]; then
    return 0
  fi

  # Collect session IDs from running Claude processes (--resume <id> or conversation ID)
  local active_sessions=()
  while IFS= read -r pid; do
    # Read /proc/<pid>/cmdline -- args are NUL-separated
    local cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
    # Extract --resume argument (session ID)
    local session_id
    session_id=$(echo "$cmdline" | grep -oP '(?<=--resume )[0-9a-f-]+' || true)
    if [[ -n "$session_id" ]]; then
      active_sessions+=("$session_id")
    fi
  done < <(pgrep -u "$uid" -x claude 2>/dev/null || true)

  local total_freed=0
  local files_removed=0

  # Walk each project directory
  for project_dir in "$claude_tmp"/*/; do
    [[ -d "$project_dir" ]] || continue

    for session_dir in "$project_dir"/*/; do
      [[ -d "$session_dir" ]] || continue
      local session_id
      session_id=$(basename "$session_dir")

      # Skip active sessions
      local is_active=false
      for active in "${active_sessions[@]+"${active_sessions[@]}"}"; do
        if [[ "$active" == "$session_id" ]]; then
          is_active=true
          break
        fi
      done
      if [[ "$is_active" == "true" ]]; then
        continue
      fi

      # Remove task output files from stale sessions
      local tasks_dir="$session_dir/tasks"
      if [[ -d "$tasks_dir" ]]; then
        for output_file in "$tasks_dir"/*.output; do
          [[ -f "$output_file" ]] || continue
          # Skip symlinks (they point to subagent logs and are tiny)
          [[ -L "$output_file" ]] && continue
          local size_kb
          size_kb=$(stat -c%s "$output_file" 2>/dev/null || echo 0)
          size_kb=$((size_kb / 1024))
          # Only remove files > 1 MB to avoid removing small, harmless files
          if [[ $size_kb -gt 1024 ]]; then
            local size_mb=$((size_kb / 1024))
            rm -f "$output_file"
            total_freed=$((total_freed + size_mb))
            files_removed=$((files_removed + 1))
          fi
        done
      fi

      # If the session directory is now empty (or only has empty subdirs), remove it
      if [[ -z "$(find "$session_dir" -type f 2>/dev/null | head -1)" ]]; then
        rm -rf "$session_dir" 2>/dev/null || true
      fi
    done

    # Remove project dir if empty
    if [[ -z "$(ls -A "$project_dir" 2>/dev/null)" ]]; then
      rmdir "$project_dir" 2>/dev/null || true
    fi
  done

  if [[ $files_removed -gt 0 ]]; then
    echo -e "${GREEN}Cleaned $files_removed stale Claude task output(s), freed ~${total_freed} MB${NC}"
  fi
}

# Reap stale Claude Code Bash-sandbox temp to reclaim tmpfs (RAM-backed /tmp).
# Beyond cleanup_claude_tmp (which reaps /tmp/claude-<uid> task output), the Bash
# sandbox leaves per-invocation artifacts DIRECTLY under /tmp that the harness does
# not garbage-collect and that no settings.json/env option can relocate or auto-clean
# (verified against Claude Code sandbox/application-data docs 2026-07-11: only
# `cleanupPeriodDays` exists and it covers ~/.claude/projects/, not /tmp). On a small
# tmpfs these starve the machine mid-run — the 2026-07-11 disk-full that interrupted a
# planning subagent had ~10k dirs / ~23k dirents in /tmp. Two safely-reapable classes:
#   - empty temp-dir shells left by mkdtemp callers      -> the dirent driver (~8.5k)
#   - stale sandbox copies (child repo/apps/plugins/NOTICE or <id>/ssr) + creds copies
#                                                        -> the space driver (~170M)
# Reap is AGE-gated so a live in-flight sandbox (seconds-to-minutes old) is never
# touched, SIGNATURE-gated so a random non-empty tmp dir another tool owns is spared,
# and uses find -delete / rmdir (never rm -rf) to stay inside the repo rm-guardrail.
# node-compile-cache is deliberately spared (a reusable Node V8 cache, not a leak).
# Thresholds and the tmp root are env-overridable for unit testing.
cleanup_stale_sandbox_tmp() {
  local uid tmp_root empty_age stale_age
  uid=$(id -u)
  tmp_root="${SOLEUR_SANDBOX_TMP_ROOT:-/tmp}"
  # Empty shells cannot hold live data; a short floor still spares a just-created
  # dir about to be written. Non-empty copies get a full-day floor (a sandbox
  # invocation lives seconds, so 24h is unambiguously orphaned).
  empty_age="${SOLEUR_SANDBOX_EMPTY_MAX_AGE_MIN:-60}"
  stale_age="${SOLEUR_SANDBOX_STALE_MAX_AGE_MIN:-1440}"
  [[ -d "$tmp_root" ]] || return 0

  local removed_empty=0 removed_stale=0 d

  # 1) Empty temp-pattern dirs (the dirent driver). `-empty -type d` = empty dirs.
  while IFS= read -r d; do
    if rmdir "$d" 2>/dev/null; then
      removed_empty=$((removed_empty + 1))
    fi
  done < <(find "$tmp_root" -mindepth 1 -maxdepth 1 -type d -empty -uid "$uid" \
             -mmin +"$empty_age" -regextype posix-extended \
             -regex "$tmp_root/[A-Za-z0-9_-]{15,}" 2>/dev/null)

  # 2) Non-empty sandbox artifacts older than the stale floor, matched by signature.
  while IFS= read -r d; do
    case "$(basename "$d")" in
      claude-creds-copy*) : ;;                       # harness credential copy
      *)
        # Only reap dirs bearing a known sandbox signature; never a random
        # non-empty tmp dir some other tool owns.
        [[ -d "$d/ssr" || -d "$d/repo" || -d "$d/apps" || -d "$d/plugins" || -e "$d/NOTICE" ]] || continue
        ;;
    esac
    if find "$d" -delete 2>/dev/null; then
      removed_stale=$((removed_stale + 1))
    fi
  done < <(find "$tmp_root" -mindepth 1 -maxdepth 1 -type d -uid "$uid" \
             -mmin +"$stale_age" -regextype posix-extended \
             -regex "$tmp_root/[A-Za-z0-9_-]{15,}" 2>/dev/null)

  if [[ $removed_empty -gt 0 || $removed_stale -gt 0 ]]; then
    echo -e "${GREEN}Reaped ${removed_empty} empty + ${removed_stale} stale sandbox temp dir(s) from ${tmp_root}${NC}"
  fi
}

# Kill runaway processes that waste CPU/memory during development sessions.
# Known offenders:
#   - gst-plugin-scanner: GStreamer media scanner spawned by GNOME's localsearch-3
#     (Tracker file indexer). Gets stuck in infinite CPU loops scanning dev repos.
#     Safe to kill -- GNOME re-indexes on next login if needed.
# Only targets processes owned by the current user and running longer than the
# CPU time threshold (avoids killing short-lived legitimate scans).
cleanup_runaway_processes() {
  local killed=0

  # gst-plugin-scanner: kill instances using >5 min of CPU time
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pid cputime
    pid=$(echo "$line" | awk '{print $1}')
    cputime=$(echo "$line" | awk '{print $2}')
    # cputime format: [DD-]HH:MM:SS or MM:SS -- extract minutes
    local minutes=0
    if [[ "$cputime" == *-* ]]; then
      # DD-HH:MM:SS format (days of CPU time -- definitely stuck)
      minutes=9999
    elif [[ "$cputime" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
      # HH:MM:SS
      minutes=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
    elif [[ "$cputime" =~ ^([0-9]+):([0-9]+)$ ]]; then
      # MM:SS
      minutes=${BASH_REMATCH[1]}
    fi

    if [[ $minutes -ge 5 ]]; then
      kill "$pid" 2>/dev/null && killed=$((killed + 1))
    fi
  done < <(ps -u "$(id -u)" -o pid=,cputime=,comm= 2>/dev/null | grep 'gst-plugin-scan' || true)

  # If we killed any gst-plugin-scanner, also stop localsearch to prevent respawn
  if [[ $killed -gt 0 ]]; then
    # Stop and mask the localsearch service so it doesn't respawn immediately
    systemctl --user stop localsearch-3.service 2>/dev/null || true
    systemctl --user mask localsearch-3.service 2>/dev/null || true
    echo -e "${GREEN}Killed $killed runaway gst-plugin-scanner process(es), masked localsearch-3${NC}"
  fi
}

# Create a draft PR for the current branch
# Idempotent: skips if a PR already exists
# All push/PR failures warn but do not block (returns 0)
create_draft_pr() {
  require_working_tree

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)

  # Guard: refuse to run on main/master
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo -e "${RED}Error: Cannot create draft PR on $branch${NC}"
    return 1
  fi

  # Check if PR already exists (idempotent)
  local existing_pr
  if ! existing_pr=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>&1); then
    echo -e "${YELLOW}Warning: Could not check for existing PR: $existing_pr${NC}"
    existing_pr=""
  fi

  if [[ -n "$existing_pr" ]]; then
    echo -e "${GREEN}Draft PR #$existing_pr already exists for $branch${NC}"
    return 0
  fi

  # Create empty initial commit
  git commit --allow-empty -m "chore: initialize $branch"

  # Push branch to remote (warn on failure, do not block)
  local push_error
  if ! push_error=$(git push -u origin "$branch" 2>&1); then
    echo -e "${YELLOW}Warning: Push failed. Work is committed locally.${NC}"
    echo "  $push_error"
    return 0
  fi

  # Create draft PR (warn on failure, do not block)
  local pr_body="Draft PR created automatically. Content will be added as work progresses."
  local pr_url
  if ! pr_url=$(gh pr create --draft --title "WIP: $branch" --body "$pr_body" 2>&1); then
    echo -e "${YELLOW}Warning: Draft PR creation failed. Branch is pushed to remote.${NC}"
    echo "  $pr_url"
    return 0
  fi

  echo -e "${GREEN}Draft PR created: $pr_url${NC}"
}

# Sync critical on-disk files from git HEAD in a bare repo.
# Bare repos have no working tree, so on-disk files become stale after merges.
# This extracts the latest versions from git and overwrites the stale copies.
sync_bare_files() {
  if [[ "$IS_BARE" != "true" ]]; then
    echo -e "${YELLOW}Not a bare repo -- sync-bare-files is only needed for bare repo roots${NC}"
    return 0
  fi

  echo -e "${BLUE}Syncing on-disk files from git HEAD...${NC}"

  # Full mirror, not a whitelist. The bare root carries a legacy populated working
  # tree that DRIFTS from HEAD in two ways the old archive-a-whitelist approach left
  # unfixed: (1) any tree outside the hardcoded list stayed stale forever -- .github
  # workflows deleted in the Inngest migration (#4483) and knowledge-base content
  # (brand-guide drift, learning 2026-05-21) both misled later analysis; (2) deleted
  # files were only pruned under .claude/hooks/, so every other tree accumulated
  # tracked-deletions. checkout-index from a throwaway index materializes EVERY
  # tracked file from HEAD (content refresh, additive -- never touches untracked
  # node_modules/.env/.mcp.json/.worktrees/_site/.playwright-mcp); a history-scoped
  # prune then removes tracked-deleted leftovers. Result: on-disk == HEAD exactly.
  local tmp_index
  tmp_index=$(mktemp)
  if ! GIT_INDEX_FILE="$tmp_index" git read-tree HEAD 2>/dev/null \
    || ! GIT_INDEX_FILE="$tmp_index" git --work-tree="$GIT_ROOT" checkout-index -a -f 2>/dev/null; then
    echo -e "${RED}Error: checkout-index from HEAD failed${NC}"
    rm -f "$tmp_index"
    return 1
  fi
  rm -f "$tmp_index"

  # Prune stale tracked-deleted files: paths git EVER tracked (the history
  # discriminator -- NOT a raw disk scan) that are absent from HEAD but still on disk.
  # The history gate is the safety boundary: untracked runtime artifacts were never
  # tracked, so they never enter the candidate set and are never removed. rmdir -p
  # cleans directories emptied by the removal (stops at the first non-empty parent).
  local stale_count=0 rel
  while IFS= read -r rel; do
    [[ -n "$rel" && -e "$GIT_ROOT/$rel" ]] || continue
    if rm -f "$GIT_ROOT/$rel"; then
      stale_count=$((stale_count + 1))
      rmdir -p "$(dirname "$GIT_ROOT/$rel")" 2>/dev/null || true
    fi
  done < <(comm -23 \
    <(git log HEAD --pretty=format: --name-only --diff-filter=AMRC 2>/dev/null | LC_ALL=C sort -u | sed '/^$/d') \
    <(git ls-tree -r --name-only HEAD 2>/dev/null | LC_ALL=C sort -u))
  if [[ "$stale_count" -gt 0 ]]; then
    echo -e "${YELLOW}Removed $stale_count stale tracked-deleted file(s) from bare root${NC}"
  fi

  # Restore execute bits. checkout-index already restores the index mode, but be
  # defensive for the scripts/hooks the plugin loader and SessionStart hooks exec.
  find "$GIT_ROOT/plugins/" -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
  chmod +x "$GIT_ROOT/plugins/soleur/hooks/"*.sh 2>/dev/null || true
  chmod +x "$GIT_ROOT/.claude/hooks/"*.sh 2>/dev/null || true

  echo -e "${GREEN}Synced on-disk files from git HEAD${NC}"
}

# Main command handler
main() {
  local command="${1:-list}"

  case "$command" in
    create)
      create_worktree "${2:-}" "${3:-}"
      ;;
    feature|feat)
      create_for_feature "${2:-}" "${3:-}"
      ;;
    list|ls)
      list_worktrees
      ;;
    switch|go)
      switch_worktree "${2:-}"
      ;;
    copy-env|env)
      copy_env_to_worktree "${2:-}"
      ;;
    cleanup|clean)
      cleanup_worktrees
      ;;
    cleanup-merged)
      cleanup_merged_worktrees
      ;;
    cleanup-tmp)
      cleanup_claude_tmp
      ;;
    cleanup-procs)
      cleanup_runaway_processes
      ;;
    draft-pr)
      create_draft_pr
      ;;
    sync-bare-files|sync-bare|sync)
      sync_bare_files
      ;;
    help)
      show_help
      ;;
    *)
      echo -e "${RED}Unknown command: $command${NC}"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

show_help() {
  cat << EOF
Git Worktree Manager

Usage: worktree-manager.sh [--yes] [--update-local-main] <command> [options]

Global Flags:
  --yes                               Auto-confirm all prompts (for headless/scripted use)
  --update-local-main                 (create only) Also fast-forward the local <from>
                                      ref to origin/<from>. Default: only the remote-
                                      tracking ref is updated; local <from> is never
                                      mutated. Bypasses the local-main lock contention
                                      class of failures (#3741).

Commands:
  create <branch-name> [from-branch]  Create new worktree (copies .env files automatically)
                                      (from-branch defaults to main)
  feature | feat <name> [from-branch] Create worktree for feature with spec directory
                                      (creates feat-<name> branch + knowledge-base/project/specs/feat-<name>/)
  list | ls                           List all worktrees
  switch | go [name]                  Switch to worktree
  copy-env | env [name]               Copy .env files from main repo to worktree
                                      (if name omitted, uses current worktree)
  cleanup | clean                     Clean up inactive worktrees
  cleanup-merged                      Clean up worktrees for merged branches
                                      (detects [gone] + merged-to-main branches,
                                      deletes stale remote branches, removes
                                      orphan directories, cleans Claude tmp
                                      files, kills runaway procs)
                                      NOTE: does NOT durably archive spec dirs
                                      — see ship/SKILL.md Phase 7 Step 4.
  cleanup-tmp                         Remove stale Claude task output files
                                      (reclaims RAM from /tmp/claude-<uid>/)
  cleanup-procs                       Kill runaway processes wasting CPU
                                      (e.g., stuck gst-plugin-scanner)
  draft-pr                            Create empty commit, push, and open draft PR
                                      (idempotent: skips if PR already exists)
  sync-bare | sync-bare-files | sync  Sync stale on-disk files from git HEAD
                                      (bare repos only -- overwrites AGENTS.md,
                                      CLAUDE.md, hooks, settings, plugin manifest,
                                      and this script. Removes stale hooks.)
  help                                Show this help message

Environment Files:
  - Automatically copies .env, .env.local, .env.test, etc. on create
  - Skips .env.example (should be in git)
  - Creates .backup files if destination already exists
  - Use 'copy-env' to refresh env files after main repo changes

Examples:
  worktree-manager.sh feature user-auth        # Creates feat-user-auth branch + spec dir
  worktree-manager.sh create feature-login
  worktree-manager.sh create feature-auth develop
  worktree-manager.sh switch feature-login
  worktree-manager.sh copy-env feature-login
  worktree-manager.sh copy-env                   # copies to current worktree
  worktree-manager.sh cleanup
  worktree-manager.sh list

EOF
}

# Parse global flags from arguments before dispatching
args=()
for arg in "$@"; do
  if [[ "$arg" == "--yes" ]]; then
    YES_FLAG=true
  elif [[ "$arg" == "--update-local-main" ]]; then
    UPDATE_LOCAL_MAIN=true
  else
    args+=("$arg")
  fi
done

# Guard for testability: only run main() when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "${args[@]+"${args[@]}"}"
fi
