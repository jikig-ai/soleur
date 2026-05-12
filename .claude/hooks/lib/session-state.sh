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

_lease_file() {
  _session_state_init_dirs
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
  lease_file=$(_lease_file "$worktree")
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
  return 0
}

release_lease() {
  local worktree="$1"
  _session_state_disabled && return 0
  local lease_file
  lease_file=$(_lease_file "$worktree")
  [[ -f "$lease_file" ]] || return 0

  # Guard: only release if same pid + hostname + started_at (Flohr rule).
  local lease_pid lease_host
  lease_pid=$(_lease_read_field "$lease_file" pid)
  lease_host=$(_lease_read_field "$lease_file" hostname)
  if [[ "$lease_pid" == "$$" ]] && [[ "$lease_host" == "$HOSTNAME" ]]; then
    rm -f "$lease_file"
  fi
  return 0
}

# Returns 0 (active) iff PID alive, hostname matches, and age < max(expected,4h).
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
  kill -0 "$lease_pid" 2>/dev/null || return 1

  # Age cap: max(expected*60, 4h floor)
  local floor=14400
  local cap=$(( lease_expected * 60 ))
  (( cap < floor )) && cap=$floor

  if [[ -n "$lease_started" ]]; then
    local started_epoch now_epoch age
    started_epoch=$(date -d "$lease_started" +%s 2>/dev/null || echo "")
    now_epoch=$(date +%s)
    if [[ -n "$started_epoch" ]]; then
      age=$(( now_epoch - started_epoch ))
      # Clock-skew guard: negative age (future start) treated as fresh.
      (( age < 0 )) && return 0
      (( age < cap )) && return 0
      return 1
    fi
  fi
  # Missing started_at — fall back to PID-alive truth.
  return 0
}

# Sweep orphan leases: PID dead OR mtime > 24h.
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
    lease_pid=$(_lease_read_field "$f" pid)
    if [[ -n "$lease_pid" ]] && ! kill -0 "$lease_pid" 2>/dev/null; then
      # Dead PID — but only sweep if same hostname (don't reap remote-host
      # leases that share the LEASE_DIR via shared filesystem).
      local lease_host
      lease_host=$(_lease_read_field "$f" hostname)
      if [[ "$lease_host" == "$HOSTNAME" ]]; then
        rm -f "$f"
      fi
    fi
  done
  shopt -u nullglob
  return 0
}

# Multi-signal trap helper. Body is unset-variable safe via local set +u.
_register_lease_release_trap() {
  local worktree="$1"
  # shellcheck disable=SC2064
  trap "_lease_release_safe '$worktree'" EXIT INT TERM HUP
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
