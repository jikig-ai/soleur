# shellcheck shell=bash
# Shared verdict logic for scripts/supabase-logs-query.sh.
#
# WHY THIS IS A LIB AND NOT INLINE
# ================================
# Guard 2's assembly is "the script's SINGLE result-rendering function" — every
# output path, success and failure, human and --json, routes through it. Putting
# that function here makes the single-chokepoint property mechanically checkable
# (one file, one emitter) and gives it a unit suite that auto-registers via the
# scripts/lib/*.test.sh glob (see the migration spec's §Preconditions).
#
# THE PROPERTY THIS FILE EXISTS TO ENFORCE
# ========================================
# A row count must never be separated from its coverage verdict. The consumer is
# an AGENT transcribing the number into a legal determination; a "0" that was
# printed next to (but not inside) a verdict gets copied without the caveat. So
# `rows=` is emitted ONLY by emit_evidence_block / emit_evidence_json here, and
# never printed anywhere else in the helper.
#
# TOP-LINE TOKEN DISCIPLINE
# =========================
# There are exactly TWO top-line verdict tokens: COVERED and INCONCLUSIVE.
# UNINSTRUMENTED is a REASON attached to INCONCLUSIVE, never a second token to
# scan for — an agent that greps for one token and finds a synonym it did not
# know about reads a caveat as a clean answer.
#
# EXIT-CODE BINDING
# =================
# The verdict must reach `$?`, not only stdout: `if helper; then echo clean; fi`,
# `set -e`, and any agent reading `$?` are all blind to a printed line. Every
# non-zero exit therefore means INCONCLUSIVE, and the CODE carries the class:
#
#   0  COVERED                     the window is covered and the count is trustworthy
#   1  INCONCLUSIVE / transient    a 5xx that SURVIVED narrowing — retry is rational
#   2  INCONCLUSIVE / auth+config  creds, bad ref, stale SQL — retry is NOT rational
#   3  INCONCLUSIVE / data         uninstrumented, partial coverage, retention, cap
#
# NOTE THE DIVERGENCE FROM scripts/betterstack-query.sh: that script uses exit 3
# for MISSING CREDENTIALS. Here exit 3 is the data verdict and missing creds are
# exit 2. Documented rather than silently inherited, because an agent that has
# internalised "3 == no creds" from the sibling would read this helper's headline
# verdict as a configuration problem and go looking for Doppler.

_SUPABASE_LOGS_VERDICT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/scrub-supabase-pat.sh
. "${_SUPABASE_LOGS_VERDICT_DIR}/scrub-supabase-pat.sh"
# shellcheck source=scripts/lib/strip-log-injection.sh
. "${_SUPABASE_LOGS_VERDICT_DIR}/strip-log-injection.sh"

# Every reason token, mapped to its exit class. A reason with no entry here is
# itself a bug, so the fallback is exit 2 (a class for which retry is NOT
# rational) rather than 0 — an unknown reason must never read as success.
verdict_exit_code() {
  case "${1:-}" in
    FULLY_COVERED|TRUNCATED_AUTONARROWED)                         printf '0' ;;
    TRANSIENT_5XX)                                                printf '1' ;;
    CONFIG_ERROR|AUTH_ERROR|DIALECT_ERROR|MALFORMED_RESULT| \
    AGGREGATION_FAILED)                                           printf '2' ;;
    UNKNOWN_SOURCE|UNINSTRUMENTED|PARTIAL_COVERAGE| \
    WINDOW_PREDATES_RETENTION|WINDOW_SIZE_FAILURE| \
    TRUNCATION_UNRESOLVED|ZERO_SOURCE_COVERAGE_UNESTABLISHED)     printf '3' ;;
    *)                                                            printf '2' ;;
  esac
}

# The top-line token is derived from the reason, never set independently — two
# independently-set fields drift, and the drift direction that matters (reason
# says UNINSTRUMENTED, token says COVERED) is the exact false all-clear.
verdict_for_reason() {
  if [[ "$(verdict_exit_code "${1:-}")" == "0" ]]; then
    printf 'COVERED'
  else
    printf 'INCONCLUSIVE'
  fi
}

# Does the observed retained span cover the requested window?
#   FULL    the project has rows at both edges of the window (within tolerance),
#           so a zero for the REQUESTED source is a real zero
#   PARTIAL rows exist but the window has an uncovered head and/or tail
#   NONE    no rows anywhere in the window for ANY source — the window is
#           outside retention and NOTHING can be concluded about it
# Args: cov_lo_epoch cov_hi_epoch req_lo_epoch req_hi_epoch tolerance_sec
# Empty cov_lo/cov_hi means "no rows observed" and yields NONE.
coverage_classify() {
  local lo="${1:-}" hi="${2:-}" req_lo="${3:-}" req_hi="${4:-}" tol="${5:-0}"
  if [[ -z "$lo" || -z "$hi" || "$lo" == "null" || "$hi" == "null" ]]; then
    printf 'NONE'
    return
  fi
  if (( lo <= req_lo + tol && hi >= req_hi - tol )); then
    printf 'FULL'
  else
    printf 'PARTIAL'
  fi
}

# ---------------------------------------------------------------------------
# THE SINGLE RESULT RENDERER. Guard 2's assembly.
#
# Reads the V_* globals set by the caller. Deliberately global-driven rather
# than 15 positional args: an emitter with a long positional signature invites
# a second, shorter "just print the count" helper to appear next to it, which
# is precisely the separation this contract forbids.
#
# Human mode writes the block to STDERR so STDOUT stays pipeable (the log rows
# are the stdout payload), plus ONE `verdict=... reason=...` line on stdout so a
# caller that redirects stdout to a file does not end up with an empty file and
# exit 0. --json writes ONE OBJECT to stdout instead.
# ---------------------------------------------------------------------------

# rows= is never a bare number for a FAILED query. A query that did not return
# is reported as UNAVAILABLE, never as 0 — "0 rows" and "we could not look" are
# the two answers this whole helper exists to keep apart.
_rows_field() {
  if [[ -z "${V_ROWS:-}" ]]; then printf 'UNAVAILABLE'; else printf '%s' "$V_ROWS" | strip_log_injection; fi
}

# Sanitise ONE FIELD VALUE, not the block. strip_log_injection deletes \r and
# \n by design (it exists to stop a crafted upstream string forging a log line),
# so piping the whole multi-line block through it would collapse the block into
# a single line — which is exactly the "count separated from its verdict"
# failure, arrived at from the opposite direction. Per-field is the only correct
# placement: an API-derived project name or error string cannot then forge a
# `verdict=COVERED` line of its own.
_field() {
  local v="${1:-}"
  [[ -z "$v" ]] && v="(unknown)"
  printf '%s' "$v" | strip_log_injection | scrub_pat
}

emit_evidence_block() {
  local reason verdict code
  reason="${V_REASON:-MALFORMED_RESULT}"
  verdict="$(verdict_for_reason "$reason")"
  code="$(verdict_exit_code "$reason")"
  # ONE heredoc: the block cannot be partially emitted, and no caller can
  # interleave a stray line between the count and the verdict.
  {
    cat <<BLOCK
=== supabase-logs-query EVIDENCE BLOCK — these lines are ONE answer, do not quote them apart ===
verdict=${verdict}
reason=${reason}
ref=$(_field "${V_REF:-}")
project=$(_field "${V_PROJECT:-}")
requested_window=$(_field "${V_REQ_START:-}")..$(_field "${V_REQ_END:-}")
covered_window=$(_field "${V_COV_START:-}")..$(_field "${V_COV_END:-}")
rows=$(_rows_field)
sources_requested=$(_field "${V_SOURCES_REQ:-}")
instrumentation_span_days=$(_field "${V_SPAN_DAYS:-}")
instrumentation=$(_field "${V_INSTR_LINE:-}")
in_window_by_source=$(_field "${V_WINDOW_LINE:-}")
monotonicity=$(_field "${V_MONO:-}")
slices=$(_field "${V_SLICES:-none}")
next_action=$(_field "${V_NEXT:-}")
=== end evidence block (exit ${code}) ===
BLOCK
  } | scrub_pat >&2
  # ONE verdict line on STDOUT as well, and the block still owns stderr.
  #
  # Human mode routes the whole block to stderr so stdout stays pipeable, which
  # meant `helper --source X > f` produced an EMPTY f and exit 0 whenever the
  # source was quiet — a reader of f sees a file with nothing wrong in it. The
  # redirect is the common shape (an agent capturing output to read later), and
  # it silently discarded the entire caveat. The line is deliberately the two
  # fields that cannot be misread apart: the top-line token and the reason.
  #
  # Not the whole block: duplicating rows= onto stdout would put a second,
  # quotable copy of the count somewhere the block does not enclose, which is the
  # separation this lib exists to prevent. rows stays stderr-only.
  printf 'verdict=%s reason=%s\n' "$verdict" "$reason" | scrub_pat
}

emit_evidence_json() {
  local reason verdict code
  reason="${V_REASON:-MALFORMED_RESULT}"
  verdict="$(verdict_for_reason "$reason")"
  code="$(verdict_exit_code "$reason")"
  # rows is a NUMBER or JSON null — never 0-for-unavailable. The machine path
  # carries the same distinction as the human one, or "no bare zero" would be
  # true only where a human was reading.
  local rows_json="null"
  [[ -n "${V_ROWS:-}" ]] && rows_json="${V_ROWS}"
  # jq -c escapes control bytes inside strings, so the object cannot carry a raw
  # ESC/CR into a terminal; free-text fields are additionally run through
  # strip_log_injection so a crafted project name or vendor error cannot smuggle
  # a newline into a consumer that splits on them.
  local j_ref j_project j_mono j_slices j_next
  j_ref="$(printf '%s' "${V_REF:-}" | strip_log_injection)"
  j_project="$(printf '%s' "${V_PROJECT:-}" | strip_log_injection)"
  j_mono="$(printf '%s' "${V_MONO:-}" | strip_log_injection)"
  j_slices="$(printf '%s' "${V_SLICES:-none}" | strip_log_injection)"
  j_next="$(printf '%s' "${V_NEXT:-}" | strip_log_injection)"
  jq -nc \
    --arg verdict "$verdict" \
    --arg reason "$reason" \
    --arg ref "$j_ref" \
    --arg project "$j_project" \
    --arg req_start "${V_REQ_START:-}" \
    --arg req_end "${V_REQ_END:-}" \
    --arg cov_start "${V_COV_START:-}" \
    --arg cov_end "${V_COV_END:-}" \
    --arg cov_class "${V_COV_CLASS:-NONE}" \
    --arg mono "$j_mono" \
    --arg slices "$j_slices" \
    --arg next "$j_next" \
    --argjson span "${V_SPAN_DAYS:-0}" \
    --argjson rows "$rows_json" \
    --argjson exit_code "$code" \
    --argjson sources "${V_SOURCES_JSON:-[]}" \
    --argjson sample "${V_SAMPLE_JSON:-[]}" \
    '{
       verdict: $verdict,
       reason: $reason,
       ref: $ref,
       project: $project,
       coverage: {
         requested_start: $req_start,
         requested_end: $req_end,
         covered_start: (if $cov_start == "" then null else $cov_start end),
         covered_end: (if $cov_end == "" then null else $cov_end end),
         classification: $cov_class,
         monotonicity: $mono,
         slices: $slices
       },
       sources: $sources,
       rows: $rows,
       instrumentation_span_days: $span,
       next_action: $next,
       exit_code: $exit_code,
       sample: $sample
     }' | scrub_pat
}

# The ONLY exit path. Renders the block in the requested mode and exits with the
# code bound to the reason, so the verdict is in $? by construction.
emit_and_exit() {
  if [[ "${JSON_MODE:-0}" == "1" ]]; then
    emit_evidence_json
  else
    emit_evidence_block
  fi
  exit "$(verdict_exit_code "${V_REASON:-MALFORMED_RESULT}")"
}
