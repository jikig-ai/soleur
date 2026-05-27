#!/usr/bin/env bash
set -euo pipefail

# Read-only infra-config state reporter for /hooks/infra-config-status (#4554).
# Invoked by adnanh/webhook — see hooks.json.tmpl.
# Returns the JSON written by infra-config-apply.sh, or sentinels:
#   {"exit_code":-2,"reason":"no_prior_apply"} — no state file exists
#   {"exit_code":-3,"reason":"corrupt_state"}  — state file unparseable

STATE_FILE="${INFRA_CONFIG_STATE:-/var/lock/infra-config-apply.state}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"exit_code":-2,"reason":"no_prior_apply"}'
elif output=$(jq -c . "$STATE_FILE" 2>/dev/null); then
  printf '%s\n' "$output"
else
  echo '{"exit_code":-3,"reason":"corrupt_state"}'
fi
