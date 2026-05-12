#!/usr/bin/env bash
# log-rotation.sh — sourced helper for .claude/.*.jsonl rotation.
#
# Single source of truth for rotating telemetry sinks under .claude/. Called
# at write time from each emitter (incidents.sh::emit_incident,
# skill-invocation-logger.sh, agent-token-tee.sh) so growth is bounded on
# every operator's machine — not only when the weekly aggregator runs.
#
# Source from a hook via:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/log-rotation.sh"
#
# Strategy: copy-then-truncate-in-place (NOT atomic-rename). Mirrors the
# pattern at scripts/rule-metrics-aggregate.sh:291-295. The rationale is
# concurrency-correctness: writers identify the file by PATH and use `>>$file`
# (open for append). flock advisories are inode-bound. A `mv $active →
# $archive.tmp; : > $active` inside the flock would let a writer that opens
# `>>$file` between the mv and its own flock acquire end up locking a DIFFERENT
# inode (the freshly-created post-truncate file) than the rotator's open fd.
# Two writers, two inodes, two flocks — torn writes return.
#
# Copy-then-truncate keeps the same inode throughout; readers/writers always
# converge on the same inode and the lock semantics hold.
#
# Public API:
#   rotate_if_needed <jsonl-path> [size-bytes] [age-days]
#
# The caller MUST pass a canonicalized absolute path (cd -P / pwd -P resolved)
# so flock targets the same inode as concurrent writers on the same logical
# file. All three production callers (incidents.sh, skill-invocation-logger.sh,
# agent-token-tee.sh) canonicalize their repo-root via `cd -P + pwd -P` —
# follow that pattern in any new caller. `stat` and the cat redirect both use
# `-L`/path-following semantics so a symlinked sink rotates on the target's
# size/mtime rather than the link's metadata.
#
# Defaults:
#   size-bytes = $LOG_ROTATION_SIZE_BYTES (or 5 MB)
#   age-days   = $LOG_ROTATION_AGE_DAYS   (or 30)
#   timeout    = $LOG_ROTATION_FLOCK_TIMEOUT_S (or 5)
#
# Kill-switch: LOG_ROTATION_DISABLE=1 short-circuits before any work.
# Test override: LOG_ROTATION_UNIQ_SUFFIX overrides the collision suffix.
#
# Exit codes:
#   0 — no-op (below threshold, missing file, kill-switch, lock-acquire
#       timeout) OR a successful rotation. Existing fire-and-forget callers
#       using `|| true` swallow this either way.
#   1 — archive-write failure (disk-full, permission-denied). The active file
#       is preserved intact (truncate gated on cat success), the partial
#       archive is removed, and ONE stderr warning is emitted per process
#       (rate-limited via /tmp/log-rotation-warned-$$ — mirrors the pattern
#       at incidents.sh:130-138).
#
# Sentinel-aware callers (issue #3509) branch on the non-zero return to emit
# a `rotation_fail` drop sentinel before falling through to the data write:
#   if ! rotate_if_needed "$file"; then
#     _emit_drop_sentinel "$file" "$HOOK_EVENT_LITERAL" rotation_fail
#   fi

# Source session-state.sh (idempotent guard inside it). Used for
# headless_or_stderr — routes warns to a log file under `claude --bg` and to
# stderr foreground. Fallback to plain stderr echo when missing (legacy
# worktrees).
# shellcheck source=session-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/session-state.sh" 2>/dev/null || true
if ! declare -f headless_or_stderr >/dev/null; then
  headless_or_stderr() { echo "[$1] $2" >&2; }
fi

LOG_ROTATION_SIZE_BYTES_DEFAULT=$((5 * 1024 * 1024))   # 5 MB
LOG_ROTATION_AGE_DAYS_DEFAULT=30
LOG_ROTATION_FLOCK_TIMEOUT_S_DEFAULT=5

rotate_if_needed() {
  [[ "${LOG_ROTATION_DISABLE:-}" == "1" ]] && return 0

  local active="${1:-}"
  [[ -z "$active" ]] && return 0
  [[ -f "$active" ]] || return 0
  [[ -s "$active" ]] || return 0   # empty — no rotation regardless of mtime

  local size_threshold="${2:-${LOG_ROTATION_SIZE_BYTES:-$LOG_ROTATION_SIZE_BYTES_DEFAULT}}"
  local age_threshold_days="${3:-${LOG_ROTATION_AGE_DAYS:-$LOG_ROTATION_AGE_DAYS_DEFAULT}}"
  local timeout_s="${LOG_ROTATION_FLOCK_TIMEOUT_S:-$LOG_ROTATION_FLOCK_TIMEOUT_S_DEFAULT}"

  # Pre-check (cheap, no lock): >99% of calls exit here.
  # `stat -L` dereferences symlinks so a relocated sink (operator-symlinked to
  # tmpfs / larger volume) rotates on the target's size/mtime, not the link's.
  local size mtime now age_seconds age_threshold_seconds
  read -r size mtime < <(stat -L -c "%s %Y" "$active" 2>/dev/null) || return 0
  now=$(date -u +%s 2>/dev/null) || return 0
  age_seconds=$(( now - mtime ))
  age_threshold_seconds=$(( age_threshold_days * 86400 ))
  if (( size <= size_threshold )) && (( age_seconds <= age_threshold_seconds )); then
    return 0
  fi

  # Compute archive path BEFORE entering flock subshell. Subshell variable
  # reassignments do not propagate back (precedent at
  # rule-metrics-aggregate.sh:288 — same hazard). An already-rotated `.gz`
  # or a lingering uncompressed file from a mid-run crash both count as
  # "already exists"; we append a uniquify suffix rather than clobbering.
  local dir base ts archive suffix
  dir=$(dirname "$active")
  base=$(basename "$active" .jsonl)
  ts=$(date -u +%Y-%m 2>/dev/null) || return 0
  archive="$dir/${base}-${ts}.jsonl"
  if [[ -f "${archive}.gz" || -f "$archive" ]]; then
    suffix="${LOG_ROTATION_UNIQ_SUFFIX:-$(date -u +%H%M%S%N)}"
    archive="$dir/${base}-${ts}-${suffix}.jsonl"
  fi

  # Acquire flock + re-check + copy-then-truncate. flock fd 9 against $active
  # — same inode the writers use for their own flock. -w timeout matches the
  # agent-token-tee.sh / aggregator precedent. On timeout: skip this round;
  # the next call will rotate. We use exit-code 10 as a 1-bit signal channel
  # ("rotated successfully") since subshell variable reassignments cannot
  # propagate to the outer scope.
  # The subshell exits 0 (no-op) or 10 (rotated). The non-zero exit-10 is a
  # signal channel — caller-side `set -e` would otherwise treat it as an
  # error, so we capture via `|| rotated=$?` (conditional context — set -e
  # does not trigger on the LHS).
  local rotated=0
  # SC2094 disable: the flock-against-self pattern (`9>>"$active"`) opens fd 9
  # against the file the body reads via `cat "$active"`. This is intentional —
  # flock advisories are inode-bound, so the writer's flock and the rotator's
  # flock must target the same inode for them to interlock. Same pattern as
  # scripts/rule-metrics-aggregate.sh:291-295.
  # shellcheck disable=SC2094
  (
    if ! flock -w "$timeout_s" -x 9; then
      exit 0
    fi
    # Re-check inside lock (TOCTOU defense — a peer writer may have rotated
    # between our pre-check and our acquire). `stat -L` parity with the
    # outer pre-check.
    local s2 m2 now2 age2
    read -r s2 m2 < <(stat -L -c "%s %Y" "$active" 2>/dev/null) || exit 0
    now2=$(date -u +%s 2>/dev/null) || exit 0
    age2=$(( now2 - m2 ))
    if (( s2 <= size_threshold )) && (( age2 <= age_threshold_seconds )); then
      exit 0
    fi
    # Copy first, truncate only on success. Preserves data on disk-full / OOM:
    # if cat fails, $active stays intact and the next call retries. We exit 11
    # to signal "rotation attempted but archive write failed" so the outer
    # scope can emit a one-shot warn AND clean up any partial archive bytes.
    if cat "$active" >> "$archive" 2>/dev/null; then
      : > "$active"
      exit 10
    fi
    exit 11
  ) 9>>"$active" 2>/dev/null || rotated=$?

  case "$rotated" in
    10)
      # gzip outside the lock — concurrent writers don't wait on compression.
      # Failure leaves the .jsonl archive intact, readable by aggregators.
      gzip -f "$archive" 2>/dev/null || true
      ;;
    11)
      # Archive write failed mid-copy. Clean up the partial archive so the
      # next attempt starts clean (otherwise the collision-suffix branch fires
      # and orphans the partial forever). Then warn ONCE per process via the
      # marker pattern at incidents.sh:130-138, and signal the failure to
      # sentinel-aware callers via a non-zero return (issue #3509).
      rm -f "$archive" 2>/dev/null || true
      local _log_rotation_warned_marker="/tmp/log-rotation-warned-$$"
      if [[ ! -f "$_log_rotation_warned_marker" ]]; then
        SOLEUR_HOOK_NAME="log-rotation" headless_or_stderr warn "failed to archive $active (disk full? permissions?)"
        : > "$_log_rotation_warned_marker" 2>/dev/null || true
      fi
      return 1
      ;;
  esac
  return 0
}
