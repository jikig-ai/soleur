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
# Defaults:
#   size-bytes = $LOG_ROTATION_SIZE_BYTES (or 5 MB)
#   age-days   = $LOG_ROTATION_AGE_DAYS   (or 30)
#   timeout    = $LOG_ROTATION_FLOCK_TIMEOUT_S (or 5)
#
# Kill-switch: LOG_ROTATION_DISABLE=1 short-circuits before any work.
# Test override: LOG_ROTATION_UNIQ_SUFFIX overrides the collision suffix.
#
# Exit code: always 0 (fire-and-forget — never blocks the calling hook).

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
  local size mtime now age_seconds age_threshold_seconds
  read -r size mtime < <(stat -c "%s %Y" "$active" 2>/dev/null) || return 0
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
    # between our pre-check and our acquire).
    local s2 m2 now2 age2
    read -r s2 m2 < <(stat -c "%s %Y" "$active" 2>/dev/null) || exit 0
    now2=$(date -u +%s 2>/dev/null) || exit 0
    age2=$(( now2 - m2 ))
    if (( s2 <= size_threshold )) && (( age2 <= age_threshold_seconds )); then
      exit 0
    fi
    # Copy first, truncate only on success. Preserves data on disk-full / OOM:
    # if cat fails, $active stays intact and the next call retries.
    if cat "$active" >> "$archive" 2>/dev/null; then
      : > "$active"
      exit 10
    fi
    exit 0
  ) 9>>"$active" 2>/dev/null || rotated=$?

  # gzip outside the lock — concurrent writers don't wait on compression.
  # Failure leaves the .jsonl archive intact, readable by aggregators.
  if [[ "$rotated" == "10" ]]; then
    gzip -f "$archive" 2>/dev/null || true
  fi
  return 0
}
