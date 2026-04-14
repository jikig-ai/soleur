#!/usr/bin/env bash
set -euo pipefail

# Read-only deploy state reporter for #2185 webhook observability.
# Invoked by /hooks/deploy-status (adnanh/webhook) -- see hooks.json.tmpl.
# Returns the JSON written by ci-deploy.sh write_state, or a sentinel
# {"exit_code":-2,"reason":"no_prior_deploy"} when no deploy has been recorded.
STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"exit_code":-2,"reason":"no_prior_deploy"}'
else
  cat "$STATE_FILE"
fi
