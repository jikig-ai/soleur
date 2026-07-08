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

if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"exit_code":-2,"reason":"no_prior_flip"}'
elif output=$(jq -c . "$STATE_FILE" 2>/dev/null); then
  printf '%s\n' "$output"
else
  echo '{"exit_code":-3,"reason":"corrupt_state"}'
fi
