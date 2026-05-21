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
# tests, containers). `systemctl is-active` prints a canonical state word to
# stdout and exits non-zero for inactive/failed; the `|| true` swallows the
# exit so the stdout value reaches HEARTBEAT_STATUS. Empty stdout only on
# missing systemctl (covered by the `else` branch).
heartbeat_status() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active inngest-heartbeat.service 2>/dev/null || true
  else
    echo "unknown"
  fi
}
HEARTBEAT_STATUS="$(heartbeat_status)"

STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"

# Compute the base JSON once, then perform a single jq merge with the
# heartbeat field. ci-deploy.sh's mv may be observed mid-write (corrupt
# JSON); the workflow's -3 case treats that as retryable, not fatal.
if [[ ! -f "$STATE_FILE" ]]; then
  BASE='{"exit_code":-2,"reason":"no_prior_deploy"}'
elif ! BASE="$(jq -c . "$STATE_FILE" 2>/dev/null)"; then
  BASE='{"exit_code":-3,"reason":"corrupt_state"}'
fi

jq -nc --argjson base "$BASE" --arg hb "$HEARTBEAT_STATUS" \
  '$base + {services: (($base.services // {}) + {inngest_heartbeat: $hb})}'
