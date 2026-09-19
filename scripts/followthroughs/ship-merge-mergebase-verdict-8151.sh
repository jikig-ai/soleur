#!/usr/bin/env bash
# AC-PM1 probe for #8091 (shipped in PR #8151): the hosted event-ship-merge
# function deepens its depth-1 PR checkout via `git fetch --unshallow` and proves
# `git merge-base origin/main HEAD` before proceeding. This probe watches Better
# Stack for the run-time evidence and for the defect signature.
#
# PASS marker (function logger.info row, `mergeBaseOk` field):
#   "ship-merge workspace has origin/main...HEAD merge-base"
# FAIL markers (the defect class reappearing post-deploy):
#   "no merge-base origin/main HEAD after unshallow"   (thrown by checkout-pr)
#   "git fetch --unshallow origin failed"              (unshallow itself failed)
#
# WEBHOOK-ECHO EXCLUSION (#6475 shape): every `remote()` hit for these strings so
# far has been a `"caller":"api"` event-receipt row that embeds an issue/PR body
# verbatim — the plan, this tracker's own body, and #8370 all quote the markers.
# The runtime lines are produced by the inngest function's logger, whose decoded
# .message does NOT carry the `"caller":"api"` + `"deliveryId"` receipt shape, so
# rows matching that shape are excluded before counting.
#
# Exit semantics (per scripts/sweep-followthroughs.sh):
#   0 = PASS       (>=1 PASS marker row AND zero non-echo FAIL rows in window)
#   1 = FAIL       (>=1 non-echo FAIL marker row — the defect is still live)
#   2 = TRANSIENT  (creds unset, query fault, or no qualifying rows yet —
#                   no event-ship-merge run has reached the merge-base step)
#
# Required env (via sweeper `secrets=` clause): BETTERSTACK_QUERY_HOST,
#   BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD.
# Test seam: ACPM1_BQ overrides the betterstack-query.sh path.
#
# RETIREMENT: when the tracker closes, delete this file and its .test.sh, drop
# the run_suite line in scripts/test-all.sh, and remove the directive from the
# issue body. Nothing else references it.

set -uo pipefail

# Refuse to run under xtrace with a live credential bound (#7797): the sweeper
# publishes probe stdout into a public issue comment.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BQ="${ACPM1_BQ:-$SCRIPT_DIR/../betterstack-query.sh}"

WINDOW="${ACPM1_WINDOW:-7d}"
if ! [[ "$WINDOW" =~ ^[0-9]+[hmd]$ ]]; then
  echo "TRANSIENT: invalid ACPM1_WINDOW '$WINDOW' (expected Nh/Nm/Nd)" >&2
  exit 2
fi

if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2
  exit 2
fi

# Explicit empty-check, never `:?` -- that aborts with status 1 (= FAIL) under
# the sweeper's non-interactive shell, so unprovisioned creds would page instead
# of retry.
if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  echo "TRANSIENT: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not all set -- cannot query Better Stack; inconclusive" >&2
  exit 2
fi

readonly PASS_MARKER='ship-merge workspace has origin/main'
readonly FAIL_MARKER_A='no merge-base origin/main HEAD after unshallow'
readonly FAIL_MARKER_B='git fetch --unshallow origin failed'
readonly ECHO_MARKER='"caller":"api"'   # webhook event-receipt shape (#6475)

# fetch_rows <grep_term> — raw JSONEachRow rows matching <grep_term> in the
# window; non-zero on query failure (caller -> TRANSIENT). Mode-2 --grep UNIONs
# the hot window with the s3 archive, so a multi-day window is not truncated.
fetch_rows() {
  local term="$1" out rc
  out="$("$BQ" --since "$WINDOW" --grep "$term" --limit 1000 2>/dev/null)"; rc=$?
  [[ "$rc" -ne 0 ]] && return 1
  printf '%s' "$out"
  return 0
}

# non_echo_count <marker> — print the count of rows matching <marker> whose
# DECODED message is not a webhook event-receipt echo; return 2 on query failure
# (checked via $? by the caller — a subshell return cannot be compared as a
# value). Decoding .raw (double-encoded JSON) is required: a substring grep on
# the escaped line cannot see the caller field's value reliably, and a receipt
# row must never count as runtime evidence.
non_echo_count() {
  local marker="$1" rows
  rows="$(fetch_rows "$marker")" || return 2
  printf '%s\n' "$rows" | jq -r 'try (.raw | fromjson | .message) // empty' 2>/dev/null \
    | grep -F "$marker" | grep -vF "$ECHO_MARKER" | grep -c . || true
}

fail_a="$(non_echo_count "$FAIL_MARKER_A")" || { echo "TRANSIENT: Better Stack query failed (fail-marker-a)" >&2; exit 2; }
fail_b="$(non_echo_count "$FAIL_MARKER_B")" || { echo "TRANSIENT: Better Stack query failed (fail-marker-b)" >&2; exit 2; }

if (( fail_a > 0 || fail_b > 0 )); then
  echo "FAIL: ${fail_a} merge-base-still-unavailable + ${fail_b} unshallow-failure row(s) in ${WINDOW} -- the #8091 defect persists post-deploy."
  echo "Inspect: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since ${WINDOW} --grep 'merge-base' | jq -r '.raw | fromjson | .message'"
  exit 1
fi

pass_n="$(non_echo_count "$PASS_MARKER")" || { echo "TRANSIENT: Better Stack query failed (pass marker)" >&2; exit 2; }

if (( pass_n > 0 )); then
  echo "PASS: ${pass_n} event-ship-merge run(s) reached the verified merge-base in ${WINDOW} -- AC-PM1 satisfied (the run proceeds to Phase 5.5, where ship-pir-action-items-gate emits its verdict)."
  exit 0
fi

echo "TRANSIENT: no event-ship-merge run reached the merge-base step in ${WINDOW} yet -- a qualifying run has not occurred."
exit 2
