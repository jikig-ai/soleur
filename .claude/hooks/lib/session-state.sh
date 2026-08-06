#!/usr/bin/env bash
# Soleur session state: cross-session locks + leases + headless visibility.
#
# Designed for N parallel CC sessions (foreground or `claude --bg`). Pays the
# 2026-04-21 concurrency bill so worktree reaping, fetch races, and merge-main
# collisions become safe side-effects.
#
# Plan: knowledge-base/project/plans/2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md
# Canonical flock idiom: .claude/hooks/agent-token-tee.sh:160-170

# Guard against double-source within a single shell.
if [[ "${_SOLEUR_SESSION_STATE_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_SESSION_STATE_LOADED=1

# Kill switch (matches SOLEUR_DISABLE_* idiom). When set to 1, every function
# in this module short-circuits to a no-op so operators can disable the lock
# layer in emergencies without surgery.
_session_state_disabled() {
  [[ "${SOLEUR_DISABLE_SESSION_STATE:-}" == "1" ]]
}

# Path resolution. Tests override via SOLEUR_SESSION_STATE_ROOT; production
# anchors to git-common-dir so all worktrees of one repo share state.
_session_state_root() {
  if [[ -n "${SOLEUR_SESSION_STATE_ROOT:-}" ]]; then
    printf '%s\n' "$SOLEUR_SESSION_STATE_ROOT"
    return 0
  fi
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null) || {
    printf '/tmp/soleur-session-state-orphan\n'
    return 0
  }
  # Canonicalize per existing idiom.
  ( cd -P "$common" 2>/dev/null && printf '%s/soleur-session-state\n' "$(pwd -P)" )
}

# Initialize state dirs (idempotent). Called at module load and on demand.
_session_state_init_dirs() {
  local root
  root=$(_session_state_root)
  LOCK_DIR="$root/locks"
  LEASE_DIR="$root/leases"
  LOG_DIR="$root/logs"
  mkdir -p "$LOCK_DIR" "$LEASE_DIR" "$LOG_DIR" 2>/dev/null || true
}

# Hard-fail predicate. flock from util-linux is required. macOS polyfill
# deferred per plan §Risks #1.
_session_state_require_flock() {
  if ! command -v flock >/dev/null 2>&1; then
    echo "session-state: flock(1) not found. Soleur requires util-linux flock for cross-session locking." >&2
    echo "  macOS: brew install util-linux && add \$(brew --prefix util-linux)/sbin to PATH" >&2
    return 99
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Locks
# ---------------------------------------------------------------------------
#
# Lock state is stashed in module-level associative-style vars. Because flock
# fd 9 must remain open for the lifetime of the critical section, we open it
# inline and stash the FD on a per-name basis so release_lock can close it.
# Bash does not let us programmatically open a numbered FD other than 9 in a
# portable way, so we serialize lock acquisitions in-process and hold fd 9
# for the duration. Callers that need nested locks open them in the natural
# (acquire-A, acquire-B, release-B, release-A) order.

# Per-name FD tracking. bash auto-assigns FDs via `exec {fd}>>file` which
# lets us hold multiple advisory locks (different files) at once. flock
# semantics are inode-bound, so cross-shell mutual exclusion is still
# correct against the same lock_file.
declare -gA _SESSION_LOCK_FDS 2>/dev/null || true
declare -gA _SESSION_LOCK_FILES 2>/dev/null || true
# Stash the started_at this shell wrote into each lease so `release_lease`
# can verify "I'm the recorded owner" before deleting. Closes the PID-reuse
# window where a new shell inheriting our pid would otherwise release.
declare -gA _LEASE_ACQUIRED_STARTED_AT 2>/dev/null || true

_acquire_lock_impl() {
  local name="$1"
  local timeout_s="${2:-30}"
  local mode="${3:-x}"  # x | s

  _session_state_disabled && return 0

  _session_state_require_flock || return 99
  _session_state_init_dirs

  # Idempotent: already held by this shell.
  if [[ -n "${_SESSION_LOCK_FDS[$name]:-}" ]]; then
    return 0
  fi

  local lock_file="$LOCK_DIR/$name.lock"
  local fd
  exec {fd}>>"$lock_file" || return 99

  local flag="-x"
  [[ "$mode" == "s" ]] && flag="-s"

  if ! flock -w "$timeout_s" "$flag" "$fd"; then
    eval "exec ${fd}>&-" 2>/dev/null || true
    return 99
  fi

  _SESSION_LOCK_FDS[$name]="$fd"
  _SESSION_LOCK_FILES[$name]="$lock_file"
  return 0
}

acquire_lock() {
  _acquire_lock_impl "$1" "${2:-30}" "x"
}

acquire_lock_shared() {
  _acquire_lock_impl "$1" "${2:-30}" "s"
}

release_lock() {
  local name="$1"
  _session_state_disabled && return 0
  local fd="${_SESSION_LOCK_FDS[$name]:-}"
  [[ -z "$fd" ]] && return 0
  eval "exec ${fd}>&-" 2>/dev/null || true
  unset "_SESSION_LOCK_FDS[$name]"
  unset "_SESSION_LOCK_FILES[$name]"
  return 0
}

# with_lock <name> <timeout_s> -- <command> [args...]
#
# CLI-friendly wrapper for SKILL.md callers. Each `bash session-state.sh
# acquire_lock` invocation is a separate process whose fd 9 closes on exit,
# so the standalone acquire/release pattern doesn't serialize anything when
# invoked separately. This wrapper acquires the lock and runs the command
# in the same shell so the lock outlives the critical section.
#
# Returns the command's exit code on success, 99 on lock-acquire timeout.
with_lock() {
  local name="$1"; shift
  local timeout_s="$1"; shift
  if [[ "$1" == "--" ]]; then shift; fi
  if ! acquire_lock "$name" "$timeout_s"; then
    headless_or_stderr warn "lock '$name' contended after ${timeout_s}s; aborting"
    return 99
  fi
  local rc=0
  "$@" || rc=$?
  release_lock "$name"
  return "$rc"
}

# ---------------------------------------------------------------------------
# Leases (durable, key=value, atomic-write)
# ---------------------------------------------------------------------------

# Validate that a worktree name is safe for filesystem-path interpolation.
# Rejects `..`, slashes, and any character outside [A-Za-z0-9._-]. Required
# because the CLI shim at the bottom of this file accepts arbitrary worktree
# names from operator/agent input; in-shell callers pass `$(basename "$PWD")`
# which is also safe but worth defense-in-depth.
_validate_worktree_name() {
  local n="$1"
  [[ "$n" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$n" == "." || "$n" == ".." ]] && return 1
  return 0
}

_lease_file() {
  _session_state_init_dirs
  if ! _validate_worktree_name "$1"; then
    headless_or_stderr warn "invalid worktree name for lease: $1"
    return 1
  fi
  printf '%s/%s.lease\n' "$LEASE_DIR" "$1"
}

_lease_read_field() {
  local lease_file="$1"
  local key="$2"
  [[ -f "$lease_file" ]] || return 1
  # Simple key=value extractor. Values do not contain `=`.
  grep "^${key}=" "$lease_file" 2>/dev/null | head -1 | cut -d= -f2-
}

acquire_lease() {
  local worktree="$1"
  local skill="${2:-unknown}"
  local expected_duration_min="${3:-240}"

  _session_state_disabled && return 0
  _session_state_init_dirs

  local lease_file
  lease_file=$(_lease_file "$worktree") || return 1
  # Sanitize skill/duration on write so `_lease_read_field` (grep+cut) sees
  # safe values. `=` and newline would corrupt the key=value parser; today
  # only `=` is plausible (operator-supplied SOLEUR_SKILL_NAME), but the
  # guard is cheap defense-in-depth and matches the documented invariant.
  skill=$(printf '%s' "$skill" | tr -d '=\n')
  if ! [[ "$expected_duration_min" =~ ^[0-9]+$ ]]; then
    expected_duration_min=240
  fi

  local tmp
  tmp=$(mktemp "${lease_file}.XXXXXX") || return 1

  local started_at
  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat > "$tmp" <<EOF
pid=$$
ppid=$PPID
skill=$skill
started_at=$started_at
expected_duration_min=$expected_duration_min
hostname=$HOSTNAME
EOF
  # Atomic rename on same filesystem.
  mv "$tmp" "$lease_file"
  _LEASE_ACQUIRED_STARTED_AT[$worktree]="$started_at"
  return 0
}

release_lease() {
  local worktree="$1"
  _session_state_disabled && return 0
  local lease_file
  lease_file=$(_lease_file "$worktree") || return 0
  [[ -f "$lease_file" ]] || return 0

  # Flohr rule: only release the lease if THIS shell is the recorded owner.
  # Compares pid + hostname + started_at — the started_at field protects
  # against PID-reuse after a crash (new shell inherits the dead shell's
  # numeric pid; without started_at it would release someone else's lease).
  local lease_pid lease_host lease_started
  lease_pid=$(_lease_read_field "$lease_file" pid)
  lease_host=$(_lease_read_field "$lease_file" hostname)
  lease_started=$(_lease_read_field "$lease_file" started_at)
  # Same host is a hard requirement: a shared LEASE_DIR can carry other machines'
  # leases and this process cannot reason about their liveness at all.
  [[ "$lease_host" == "$HOSTNAME" ]] || return 0
  [[ -n "$lease_started" ]] || return 0

  # TWO owners can release, and the second one is why this function used to do
  # NOTHING. Measured before this change: the DOCUMENTED call —
  #   bash .claude/hooks/lib/session-state.sh release_lease "$(basename "$PWD")"
  # which both one-shot and work tell you to run at the end — returned rc=0 and
  # deleted no file, because a fresh process has a different `$$` and an empty
  # `_LEASE_ACQUIRED_STARTED_AT`, so the in-process conjunction could never
  # match. It reported success while leaking the lease. That is not a stricter
  # guard; it is an unreachable one.
  #
  #   in-process  — pid == $$ AND the started_at we recorded at acquire time.
  #                 This is the trap path, and started_at still guards PID reuse.
  #   post-exit   — the recorded pid is DEAD. The session that held it is gone,
  #                 so releasing is correct and is what the CLI call needs.
  #
  # A lease held by a DIFFERENT, still-LIVE process on this host matches neither
  # arm and is refused — which is the property the original guard was reaching
  # for and is the only one worth keeping.
  local owner=""
  if [[ "$lease_pid" == "$$" ]] \
     && [[ -n "${_LEASE_ACQUIRED_STARTED_AT[$worktree]:-}" ]] \
     && [[ "$lease_started" == "${_LEASE_ACQUIRED_STARTED_AT[$worktree]}" ]]; then
    owner="in-process"
  elif [[ -n "$lease_pid" ]] && ! kill -0 "$lease_pid" 2>/dev/null; then
    owner="post-exit"
  fi

  if [[ -n "$owner" ]]; then
    rm -f "$lease_file"
    unset "_LEASE_ACQUIRED_STARTED_AT[$worktree]"
  fi
  return 0
}

# Returns 0 (active) iff hostname matches and age is inside the window computed
# by _lease_window_seconds (declared duration, clamped to [4h, 24h]). PID
# liveness is deliberately NOT required — see the note in is_lease_active.
# How long a lease is honoured, in seconds, from a raw expected_duration_min
# field. ONE definition, because is_lease_active and sweep_orphan_leases must
# agree exactly — and when this logic was duplicated they did not:
#
#   * FLOOR 4h  — a short declared duration should not make a lease reapable
#                 while the session is plainly still working.
#   * CEILING 24h — the field is operator-supplied via SOLEUR_EXPECTED_DURATION_MIN
#                 and validated only as "digits". Unbounded, a typo (240000 for
#                 240) silently disables cleanup-merged for MONTHS: the lease
#                 reads ACTIVE forever and, in the cleanup path, nothing else
#                 reaps it. Pinning the ceiling to the same 24h as the mtime
#                 sweep is what makes "the 24h sweep is the backstop" TRUE
#                 rather than merely claimed. Measured before the clamp: a
#                 20-day-old lease with expected_duration_min=525600 read ACTIVE.
#   * NON-NUMERIC -> 240 (the documented default), never bare arithmetic. Under
#                 `set -u`, `$(( abc * 60 ))` treats `abc` as an unset variable
#                 name and ERRORS; is_lease_active is called from inside an `if`,
#                 so `set -e` is suspended and that error was read as "no active
#                 lease" — i.e. a fresh lease with one corrupt field became
#                 REAPABLE. Fail closed on corrupt input, never open.
_lease_window_seconds() {  # $1 raw expected_duration_min
  local mins="${1:-}"
  [[ "$mins" =~ ^[0-9]+$ ]] || mins=240
  # `10#` forces base 10. WITHOUT it this fails OPEN, which is the whole class
  # this function exists to close: `^[0-9]+$` ACCEPTS a leading zero, bash reads
  # a leading-zero token as OCTAL, and 8/9 are not octal digits — so `08`/`09`/
  # `090` pass validation and then ERROR in the arithmetic. `cap` is never
  # assigned, the function prints nothing, and both callers read an empty window:
  # `(( age < "" ))` is false (INACTIVE -> reapable) and `(( age >= "" ))` is
  # true (the sweep deletes it). Measured on a 0-second-old lease: INACTIVE and
  # SWEPT in the same pass — #7278's exact signature through a different door.
  # `0700` does not error and is worse for being quiet: octal 448 min, not 700.
  # T12 missed this because `abc` is REJECTED by the regex; the escaping input
  # is one the regex ACCEPTS. Pinned by T12's `090` case.
  local cap=$(( 10#$mins * 60 ))
  (( cap < 14400 )) && cap=14400
  (( cap > 86400 )) && cap=86400
  printf '%s\n' "$cap"
}

is_lease_active() {
  local worktree="$1"
  _session_state_disabled && return 1
  local lease_file
  lease_file=$(_lease_file "$worktree")
  [[ -f "$lease_file" ]] || return 1

  local lease_pid lease_host lease_started lease_expected
  lease_pid=$(_lease_read_field "$lease_file" pid)
  lease_host=$(_lease_read_field "$lease_file" hostname)
  lease_started=$(_lease_read_field "$lease_file" started_at)
  lease_expected=$(_lease_read_field "$lease_file" expected_duration_min)

  [[ -n "$lease_pid" ]] || return 1
  [[ "$lease_host" == "$HOSTNAME" ]] || return 1

  # NO `kill -0 "$lease_pid" || return 1` HERE — that line reaped two live
  # worktrees on 2026-08-06 (#7278), and it could never have worked.
  #
  # `acquire_lease` records `pid=$$`, and every DOCUMENTED entry point is a
  # short-lived process:
  #
  #     bash .claude/hooks/lib/session-state.sh acquire_lease <worktree>
  #     bash .../worktree-manager.sh --yes create <branch>
  #
  # so `$$` is a bash that exits within milliseconds of writing the file.
  # A pid-liveness gate therefore reported INACTIVE for every CLI-acquired
  # lease the instant it was taken — the file existed, carried its full
  # remaining duration, and protected nothing. cleanup-merged then removed
  # the worktree, deleted the branch locally AND on origin, and closed the PR.
  #
  # A lease is a TIME-BOXED RESERVATION; the age cap below is the authority.
  # PID liveness is only an optimisation for releasing early, and a session
  # that finishes cleanly calls `release_lease` (which still verifies pid +
  # hostname + started_at before releasing). The cost of this change is that
  # a CRASHED session holds its worktree until the window closes, bounded by
  # max(expected_duration, 4h) here and by the 24h mtime sweep below. That is
  # the correct direction to fail: a worktree kept slightly too long is
  # recoverable, a worktree reaped mid-run is not.
  #
  # The bound is the window computed by _lease_window_seconds, which is CLAMPED
  # to 24h. Do not restate it as "and the 24h mtime sweep backstops this" without
  # checking: an earlier draft of this comment said exactly that and it was FALSE
  # in the path that matters — sweep_orphan_leases was reachable only from the
  # `create` subcommand, never from cleanup_merged_worktrees. That is now also
  # wired (worktree-manager.sh calls the sweep at the top of cleanup), but the
  # clamp is what makes the bound hold regardless.
  #
  # Pinned by T9/T9b (a dead acquirer stays active + unswept inside the
  # window) and T10 (an expired lease is still inactive, so this is not an
  # immortality bug) in session-state.test.sh.

  # Age cap: see _lease_window_seconds. Computed there, not inline, because
  # sweep_orphan_leases needs the IDENTICAL number and two copies already
  # drifted once (one validated the field, one did not — the unvalidated copy
  # fail-OPENED under `set -u`, which on this path means "reap it").
  local cap
  cap=$(_lease_window_seconds "$lease_expected")

  # Anchor started_at to the strict ISO-8601-Z format we always write
  # ourselves (date -u +%Y-%m-%dT%H:%M:%SZ). A malformed or natural-language
  # value (e.g., "next year") fed to `date -d` would otherwise resolve to a
  # future epoch — combined with the clock-skew "fresh" branch below that
  # turns into a forever-active lease and a permanent reap block.
  if [[ ! "$lease_started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    # Malformed or missing — treat as inactive; let sweep_orphan_leases
    # reap by mtime instead of forever-blocking cleanup-merged.
    return 1
  fi
  local started_epoch now_epoch age
  started_epoch=$(date -d "$lease_started" +%s 2>/dev/null || echo "")
  now_epoch=$(date +%s)
  if [[ -z "$started_epoch" ]]; then
    return 1
  fi
  age=$(( now_epoch - started_epoch ))
  # Negative age = clock skew or future-stamped lease. Treat as inactive
  # (not forever-fresh) to avoid the DoS vector.
  if (( age < 0 )); then
    return 1
  fi
  (( age < cap )) && return 0
  return 1
}

# Sweep orphan leases. Deletes on: mtime > 24h, OR (pid dead AND same host AND
# past its own window). The pid-dead arm is deliberately NOT sufficient on its
# own — see is_lease_active for why a dead pid is not orphan evidence here.
sweep_orphan_leases() {
  _session_state_disabled && return 0
  _session_state_init_dirs

  local now_epoch
  now_epoch=$(date +%s)
  local f mtime age lease_pid
  shopt -s nullglob
  for f in "$LEASE_DIR"/*.lease; do
    mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    age=$(( now_epoch - mtime ))
    if (( age > 86400 )); then
      rm -f "$f"
      continue
    fi
    lease_pid=$(_lease_read_field "$f" pid) || true
    if [[ -n "$lease_pid" ]] && ! kill -0 "$lease_pid" 2>/dev/null; then
      # Dead PID — but only sweep if same hostname (don't reap remote-host
      # leases that share the LEASE_DIR via shared filesystem).
      local lease_host
      lease_host=$(_lease_read_field "$f" hostname) || true
      if [[ "$lease_host" == "$HOSTNAME" ]]; then
        # ...AND only once the lease is past its own window. A dead pid alone
        # is NOT orphan evidence: `acquire_lease` records `pid=$$`, which for
        # every documented CLI entry point belongs to a process that exits
        # immediately (see the long note in is_lease_active). Sweeping on a
        # dead pid alone deleted the lease file BEFORE worktree-manager
        # consulted is_lease_active — so the downstream check found no file
        # and the reap proceeded. That is #7278, twice, on 2026-08-06.
        #
        # is_lease_active is the single source of truth for "still held";
        # the 24h mtime cap above remains the backstop for a truly abandoned
        # file. Pinned by T9b.
        # `|| true` on every field read: `_lease_read_field` returns 1 for a
        # missing field AND for a file that has vanished since the glob, and a
        # sibling releasing its lease mid-sweep is an ordinary race, not an
        # error. Bare assignments here abort the caller under `set -e` — and the
        # caller is cleanup-merged, so the blast radius is every maintenance
        # step after it. An empty value is handled below; a dead caller is not.
        local lease_started lease_expected lease_cap started_epoch lease_age
        lease_started=$(_lease_read_field "$f" started_at) || true
        lease_expected=$(_lease_read_field "$f" expected_duration_min) || true
        # Same window as is_lease_active, from the same function — these two
        # MUST agree, and when the arithmetic was duplicated here they did not.
        lease_cap=$(_lease_window_seconds "$lease_expected")
        started_epoch=""
        if [[ "$lease_started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
          started_epoch=$(date -d "$lease_started" +%s 2>/dev/null || echo "")
        fi
        if [[ -z "$started_epoch" ]]; then
          # Unparseable started_at: fall back to mtime, which the 24h cap
          # above already governs. Leave it for that cap rather than guessing.
          continue
        fi
        lease_age=$(( now_epoch - started_epoch ))
        if (( lease_age >= lease_cap )); then
          rm -f "$f"
        fi
      fi
    fi
  done
  shopt -u nullglob
  return 0
}

# Multi-signal trap helper. Body is unset-variable safe via local set +u.
_register_lease_release_trap() {
  local worktree="$1"
  # NOT `EXIT` — that is what made the lease layer unreachable in production.
  #
  # `create_worktree` acquires the lease and registers this trap IN THE SAME
  # PROCESS, and that process exits normally on success. With EXIT armed, the
  # trap fired on that success and deleted the lease before `create` had even
  # printed its path. Measured: the leases directory is EMPTY the instant
  # `worktree-manager.sh --yes create` returns. So a worktree made the
  # DOCUMENTED way (what one-shot and work both invoke) carried no lease at all,
  # and `is_lease_active` returned at its `[[ -f "$lease_file" ]]` guard — every
  # protection below that line was dead code for the path that matters.
  #
  # Normal process exit is not session end. That is this change's whole thesis,
  # applied to the write side: the CLI process is short-lived BY DESIGN, and the
  # session it acquired for outlives it by hours.
  #
  # The abnormal signals stay: those do mean the holder died, and releasing then
  # is correct. Clean release is the caller's explicit `release_lease` (now
  # reachable post-exit — see the owner arms there), plus the window as backstop.
  # shellcheck disable=SC2064
  trap "_lease_release_safe '$worktree'" INT TERM HUP
}

_lease_release_safe() {
  # Unset-var safe — traps fire in odd scopes.
  set +u
  local worktree="${1:-}"
  [[ -n "$worktree" ]] || return 0
  release_lease "$worktree" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Headless visibility helper (sub-PR 2 will reuse this).
# ---------------------------------------------------------------------------
# If fd 2 is not a TTY AND CLAUDECODE is set (we are running under `claude --bg`
# or another headless harness), append a single timestamped line to
# $LOG_DIR/$PPID.log. Otherwise echo to stderr. POSIX-atomic append for lines
# < 4KB.
headless_or_stderr() {
  local level="${1:-warn}"
  local msg="${2:-}"
  _session_state_disabled && { echo "[$level] $msg" >&2; return 0; }

  local hook="${SOLEUR_HOOK_NAME:-$(basename "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" .sh)}"

  if [[ ! -t 2 ]] && [[ -n "${CLAUDECODE:-}" ]]; then
    _session_state_init_dirs
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '[%s] [%s] [%s] %s\n' "$ts" "$level" "$hook" "$msg" >> "$LOG_DIR/${PPID}.log"
  else
    echo "[$level] $msg" >&2
  fi
  return 0
}

# Initialize state dirs once at source-time so consumers can rely on LOG_DIR
# and friends being readable.
_session_state_init_dirs

# Allow `bash session-state.sh <fn> <args>` as a CLI shim (used by SKILL.md
# Phase Exit hooks and ad-hoc operator invocations).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"
  shift || true
  case "$fn" in
    acquire_lock|release_lock|acquire_lock_shared|acquire_lease|release_lease|is_lease_active|sweep_orphan_leases|headless_or_stderr|with_lock)
      "$fn" "$@"
      ;;
    "")
      echo "usage: $0 <function> [args...]" >&2
      exit 2
      ;;
    *)
      echo "session-state: unknown function: $fn" >&2
      exit 2
      ;;
  esac
fi
