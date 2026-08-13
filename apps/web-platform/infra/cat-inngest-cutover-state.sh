#!/usr/bin/env bash
set -euo pipefail

# Read-only on-host state reader for the inngest cutover flip (#6178, ADR-100).
#
# DEBUG AID ONLY — this is explicitly NOT the operator gate. The dedicated host is
# deny-all-public; the operator confirms the flip result off-box via Better Stack (the
# on-host Vector -> Better Stack journald shipper carries the `inngest-cutover-flip`
# JSON log line, P0-2). This reader exists solely for on-host debugging and mirrors
# cat-inngest-verify-state.sh. It returns the JSON slot written by
# inngest-cutover-flip.sh, or a sentinel:
#   {"exit_code":-2,"reason":"no_prior_flip"} — no state file exists yet
#   {"exit_code":-3,"reason":"corrupt_state"}  — state file unparseable

STATE_FILE="${INNGEST_CUTOVER_STATE:-/var/lock/inngest-cutover-flip.state}"
# (#7228 P0-5) The monotonic re-flush latch, surfaced ALONGSIDE the slot rather than instead of
# it, because the two answer different questions and only one of them is trustworthy:
#   * the slot answers "what did the last poll do?" — LAST-WRITE-WINS, so a `rolled-back` poll
#     overwrites a `done` record. It is a debug aid, not a guarantee.
#   * the latch answers "has a FLUSHALL EVER been performed?" — append-only, on the durable
#     volume, erasable by no branch. It is what actually decides whether a re-arm may flush.
# Reading the slot alone would show `rolled-back` on a host whose catastrophe guard is armed,
# which is the exact confusion that let the erasure bug hide.
LATCH_FILE="${INNGEST_CUTOVER_LATCH:-/mnt/data/inngest-cutover/flip-done.latch}"

if [[ -e "$LATCH_FILE" ]]; then
  latch_json="$(jq -nc --arg r "$(tail -n 1 "$LATCH_FILE" 2>/dev/null || printf '')" \
    '{flush_latched:true, latch_record:$r}')"
else
  latch_json='{"flush_latched":false,"latch_record":""}'
fi

if [[ ! -f "$STATE_FILE" ]]; then
  slot_json='{"exit_code":-2,"reason":"no_prior_flip"}'
elif slot_json=$(jq -c . "$STATE_FILE" 2>/dev/null); then
  :
else
  slot_json='{"exit_code":-3,"reason":"corrupt_state"}'
fi

jq -nc --argjson slot "$slot_json" --argjson latch "$latch_json" '$slot + $latch'
