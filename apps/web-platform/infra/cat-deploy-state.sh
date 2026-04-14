#!/usr/bin/env bash
set -euo pipefail

# Read-only deploy state reporter for #2185 webhook observability.
# Invoked by /hooks/deploy-status (adnanh/webhook) -- see hooks.json.tmpl.
# Returns the JSON written by ci-deploy.sh write_state, or a sentinel:
#   {"exit_code":-2,"reason":"no_prior_deploy"} -- no state file exists
#   {"exit_code":-3,"reason":"corrupt_state"}   -- state file unparseable
# Exit-code protocol defined in ci-deploy.sh header (#2205).
STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"exit_code":-2,"reason":"no_prior_deploy"}'
elif ! jq -c . "$STATE_FILE" 2>/dev/null; then
  # Transient: ci-deploy.sh's mv may be observed mid-write. Workflow's -3 case
  # should treat this as retryable, not fatal.
  echo '{"exit_code":-3,"reason":"corrupt_state"}'
fi
