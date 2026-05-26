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
# exit so the stdout value reaches the caller. Empty stdout only on
# missing systemctl (covered by the `else` branch).
service_status() {
  local unit="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active "$unit" 2>/dev/null || true
  else
    echo "unknown"
  fi
}

# Tail of recent journal entries for a unit. Read-only; returns at most 100
# lines (capped to ~8000 chars total). Strips control bytes so the JSON
# `vector_journal_tail` field round-trips cleanly. Empty on missing
# journalctl OR non-existent unit. Used for no-SSH RCA of vector.service
# startup failures (TR9 PR-5).
#
# Tail bumped from 10 → 100 lines because the original cap was eclipsed
# by high-volume per-request error logs (e.g., Vector's sink retries
# flooded the 10-line window). The 8000-char cap keeps the JSON payload
# small enough for the webhook response while letting diagnostic content
# (envelope_debug sink output, init errors) rise above per-request noise.
service_journal_tail() {
  local unit="$1"
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u "$unit" --no-pager --output=cat -n 100 2>/dev/null \
      | tr -d '\r' | tr '\n' '|' | tr -dc '[:print:]|' | tail -c 8000 \
      || true
  fi
}

# Per-cron last-fire timestamps written by postSentryHeartbeat (#4131).
# Glob is best-effort; empty dir or missing path produces "{}".
inngest_crons_json() {
  local dir="/var/lib/inngest/cron-fires"
  if [[ ! -d "$dir" ]]; then echo "{}"; return; fi
  local result="{}"
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    local slug last_ok
    slug=$(jq -r '.slug // empty' "$f" 2>/dev/null) || continue
    last_ok=$(jq -r '.last_ok_at // empty' "$f" 2>/dev/null) || continue
    [[ -n "$slug" && -n "$last_ok" ]] || continue
    result=$(echo "$result" | jq --arg s "$slug" --arg t "$last_ok" '. + {($s): {last_ok_at: $t}}')
  done
  echo "$result"
}

HEARTBEAT_STATUS="$(service_status inngest-heartbeat.service)"
INNGEST_SERVER_STATUS="$(service_status inngest-server.service)"
VECTOR_STATUS="$(service_status vector.service)"
VECTOR_JOURNAL_TAIL="$(service_journal_tail vector.service)"
INNGEST_CRONS="$(inngest_crons_json)"

STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"

# Compute the base JSON once, then perform a single jq merge with the
# heartbeat field. ci-deploy.sh's mv may be observed mid-write (corrupt
# JSON); the workflow's -3 case treats that as retryable, not fatal.
if [[ ! -f "$STATE_FILE" ]]; then
  BASE='{"exit_code":-2,"reason":"no_prior_deploy"}'
elif ! BASE="$(jq -c . "$STATE_FILE" 2>/dev/null)"; then
  BASE='{"exit_code":-3,"reason":"corrupt_state"}'
fi

jq -nc \
  --argjson base "$BASE" \
  --arg hb "$HEARTBEAT_STATUS" \
  --arg is "$INNGEST_SERVER_STATUS" \
  --arg vs "$VECTOR_STATUS" \
  --arg vj "$VECTOR_JOURNAL_TAIL" \
  --argjson ic "$INNGEST_CRONS" \
  '$base + {services: (($base.services // {}) + {
    inngest_heartbeat: $hb,
    inngest_server: $is,
    vector: $vs,
    vector_journal_tail: $vj,
    inngest_crons: $ic
  })}'
