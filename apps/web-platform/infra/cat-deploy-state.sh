#!/usr/bin/env bash
set -euo pipefail

# Read-only deploy state reporter for #2185 webhook observability.
# Invoked by /hooks/deploy-status (adnanh/webhook) -- see hooks.json.tmpl.
# Returns the JSON written by ci-deploy.sh write_state, MERGED with a
# `services.inngest_heartbeat` field reading live `systemctl is-active`
# state (#4116 — discoverability_test for the new plan-skill observability
# gate). Sentinels:
#   {"exit_code":-2,"reason":"no_prior_deploy"} -- no state file exists
#   {"exit_code":-3,"reason":"corrupt_state"}   -- state file unparseable
# Exit-code protocol defined in ci-deploy.sh header (#2205).

# Best-effort: systemctl may be unavailable in non-systemd contexts (local
# tests, containers). Default to "unknown" so the field shape is stable
# without coupling the script's contract to systemd availability.
heartbeat_status() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active inngest-heartbeat.service 2>/dev/null || true
  else
    echo "unknown"
  fi
}
HEARTBEAT_STATUS="$(heartbeat_status)"
HEARTBEAT_STATUS="${HEARTBEAT_STATUS:-unknown}"

STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"
if [[ ! -f "$STATE_FILE" ]]; then
  jq -nc --arg hb "$HEARTBEAT_STATUS" \
    '{exit_code: -2, reason: "no_prior_deploy", services: {inngest_heartbeat: $hb}}'
elif ! jq -c --arg hb "$HEARTBEAT_STATUS" \
       '. + {services: ((.services // {}) + {inngest_heartbeat: $hb})}' \
       "$STATE_FILE" 2>/dev/null; then
  # Transient: ci-deploy.sh's mv may be observed mid-write. Workflow's -3 case
  # should treat this as retryable, not fatal.
  jq -nc --arg hb "$HEARTBEAT_STATUS" \
    '{exit_code: -3, reason: "corrupt_state", services: {inngest_heartbeat: $hb}}'
fi
