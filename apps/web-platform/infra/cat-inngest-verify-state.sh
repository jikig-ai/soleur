#!/usr/bin/env bash
set -euo pipefail

# Read-only inngest wiped-volume-verify state reporter for the
# /hooks/inngest-verify-status GET hook (#5450). Invoked by adnanh/webhook —
# see hooks.json.tmpl. Returns the JSON written by inngest-wiped-volume-verify.sh,
# or sentinels. It CANNOT reuse /hooks/deploy-status (cat-deploy-state.sh), which
# reads only the ci-deploy.state slot written by ci-deploy.sh — the destructive
# verify is a distinct async op with its own terminal exit_code (P1a).
#   {"exit_code":-2,"reason":"no_prior_verify"} — no state file exists
#   {"exit_code":-3,"reason":"corrupt_state"}   — state file unparseable

STATE_FILE="${INNGEST_VERIFY_STATE:-/var/lock/inngest-wiped-volume-verify.state}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"exit_code":-2,"reason":"no_prior_verify"}'
elif output=$(jq -c . "$STATE_FILE" 2>/dev/null); then
  printf '%s\n' "$output"
else
  echo '{"exit_code":-3,"reason":"corrupt_state"}'
fi
