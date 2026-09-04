#!/usr/bin/env bash
# Idempotent Sentry alert-rule configurator for the auth observability stack.
#
# SCOPE NARROWED TO ONE RULE (#7650 Phase 2, 2026-09-04). This script now
# configures exactly one issue-alert rule:
#
#   1. auth-per-user-loop — >=3 unique-user events in 5m, feature:auth
#
# The other three (auth-exchange-code-burst, auth-callback-no-code-burst,
# auth-signout-burst) were adopted into Terraform as `sentry_alert` resources
# with their real definitions read from live, and their stanzas were deleted
# from here. Terraform now owns their filters outright — their blocks carry
# `ignore_changes = [environment]` only, not the wide list that previously made
# this script their sole executable definition.
#
# WHY THIS SCRIPT STILL EXISTS. `auth-per-user-loop` uses
# `event_unique_user_frequency_count`, which the pinned provider (0.15.7)
# does not offer under `trigger_conditions` — verified against the provider
# schema, upstream jianyuan/terraform-provider-sentry issue 950. Its
# `sentry_issue_alert` block still declares `conditions_v2 = []` /
# `filters_v2 = []` under a wide `ignore_changes`, so Terraform explicitly does
# NOT own its filters and an apply cannot restore them. This script remains the
# only executable definition of that one rule. Do not delete it. See
# knowledge-base/project/learnings/2026-08-19-i-proposed-deleting-a-control-because-terraform-appeared-to-own-it.md
#
# THIS SCRIPT WRITES THROUGH THE DEPRECATED /rules/ ENDPOINT. Measured
# 2026-09-04: before the narrowing it wrote `frequency 60` for all three burst
# rules while live carried 60/61/62, so running it rewrote two live paging
# cadences. That drift vector is removed by the deletion below.
#
# Idempotency: GET /rules/, match by name, PUT if found else POST.
# Region detection: probes /users/me/ on sentry.io and de.sentry.io.
# Action target: prefers Sentry team slug ops|engineering, falls back to
# IssueOwners + ActiveMembers if no team is found.
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT
# Closes #2997. Runbook: knowledge-base/engineering/operations/runbooks/oauth-probe-failure.md

set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"
: "${SENTRY_PROJECT:?SENTRY_PROJECT must be set}"

# --- Region detection (skipped if SENTRY_API_HOST is set) -----------------
# Sentry has US (sentry.io) and EU (de.sentry.io) ingest clusters; the API
# hostname follows the same split. Probe /users/me/ on each candidate and
# pick whichever returns 200.
#
# Escape hatch: tokens minted without member:read scope (e.g. project-scoped
# personal tokens) 403 on /users/me/. Set SENTRY_API_HOST to bypass.
api_host="${SENTRY_API_HOST:-}"
if [[ -z "$api_host" ]]; then
  for candidate in de.sentry.io sentry.io; do
    http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${candidate}/api/0/users/me/")
    if [[ "$http" == "200" ]]; then
      api_host="$candidate"
      break
    fi
  done
fi
if [[ -z "$api_host" ]]; then
  echo "ERROR: Sentry token not valid against either US or EU ingest (set SENTRY_API_HOST to bypass)" >&2
  exit 1
fi
echo "[info] Using Sentry API host: ${api_host}"

# --- Action target resolution -------------------------------------------
# NotifyEmailAction.targetType=Member requires a numeric Sentry user ID, so
# prefer Team (resolves to all team members + their notification preferences).
# Fall back to IssueOwners + ActiveMembers if no ops/engineering team exists.
team_id=""
teams_json=$(curl -s --max-time 10 \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  "https://${api_host}/api/0/organizations/${SENTRY_ORG}/teams/")
if jq -e . <<<"$teams_json" >/dev/null 2>&1; then
  team_id=$(jq -r '[.[] | select(.slug == "ops" or .slug == "engineering")] | .[0].id // empty' <<<"$teams_json")
fi

if [[ -n "$team_id" ]]; then
  email_action=$(jq -n --arg id "$team_id" \
    '[{id:"sentry.mail.actions.NotifyEmailAction", targetType:"Team", targetIdentifier:($id|tonumber), fallthroughType:"ActiveMembers"}]')
  echo "[info] Email action: Team #${team_id}"
else
  # IssueOwners + ActiveMembers means: try the issue's auto-assigned owners
  # first, fall through to all active project members. This pages SOMEONE
  # in any well-formed project, but for a hardened ops paging path the
  # caller should create a Sentry team named ops or engineering and re-run.
  email_action=$(jq -n \
    '[{id:"sentry.mail.actions.NotifyEmailAction", targetType:"IssueOwners", fallthroughType:"ActiveMembers"}]')
  echo "[warn] No 'ops' or 'engineering' Sentry team found — falling back to IssueOwners+ActiveMembers."
  echo "[warn]   For tightly scoped ops paging, create a Sentry team and re-run this script."
fi

# --- upsert_rule <name> <conditions_json> <filters_json> <freq_minutes> ---
upsert_rule() {
  local name="$1" conditions="$2" filters="$3" freq="$4"

  # Match-by-name idempotency: a Sentry user can manually duplicate a rule
  # name in the UI (the API does NOT enforce uniqueness). If we silently
  # picked .[0].id we would update one copy and leave the other(s) drifted
  # — paging on stale config with no signal. Fail-closed when count > 1.
  local rules_json match_count match_ids existing
  rules_json=$(curl -s --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/")
  if ! jq -e . <<<"$rules_json" >/dev/null 2>&1; then
    echo "ERROR: GET /rules/ returned non-JSON for '${name}' lookup" >&2
    echo "$rules_json" >&2
    exit 1
  fi
  match_ids=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<<"$rules_json")
  match_count=$(printf '%s' "$match_ids" | grep -c . || true)
  if (( match_count > 1 )); then
    echo "ERROR: ${match_count} rules named '${name}' found — refusing to mutate (resolve duplicates in Sentry UI)." >&2
    echo "  IDs: $(printf '%s' "$match_ids" | tr '\n' ' ')" >&2
    exit 1
  fi
  existing=$(printf '%s' "$match_ids" | head -n1)

  local payload
  payload=$(jq -n \
    --arg name "$name" \
    --argjson conditions "$conditions" \
    --argjson filters "$filters" \
    --argjson actions "$email_action" \
    --argjson freq "$freq" \
    '{name: $name, actionMatch: "all", filterMatch: "all", conditions: $conditions, filters: $filters, actions: $actions, frequency: $freq}')

  local resp_file
  resp_file=$(mktemp)
  trap 'rm -f "$resp_file"' RETURN

  local http
  if [[ -n "$existing" ]]; then
    http=$(curl -s --max-time 10 -X PUT \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      -o "$resp_file" -w '%{http_code}' \
      "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/${existing}/" \
      -d "$payload")
    if [[ ! "$http" =~ ^2 ]]; then
      echo "ERROR: PUT rule '${name}' -> HTTP ${http}" >&2
      cat "$resp_file" >&2
      exit 1
    fi
    echo "[ok] Updated rule '${name}' (id=${existing})"
  else
    http=$(curl -s --max-time 10 -X POST \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      -o "$resp_file" -w '%{http_code}' \
      "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/" \
      -d "$payload")
    if [[ ! "$http" =~ ^2 ]]; then
      echo "ERROR: POST rule '${name}' -> HTTP ${http}" >&2
      cat "$resp_file" >&2
      exit 1
    fi
    echo "[ok] Created rule '${name}'"
  fi
}

# --- The one remaining rule: per-user broken loop ------------------------
# Unique-user frequency accepts the same intervals; 5m matches the issue
# body directly. Lower frequency cap (30 min) so per-user paging is timely.
upsert_rule "auth-per-user-loop" \
  '[{"id":"sentry.rules.conditions.event_frequency.EventUniqueUserFrequencyCondition","value":3,"interval":"5m"}]' \
  '[{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"}]' \
  30

echo "[done] auth-per-user-loop upserted (the other three are Terraform-owned since #7650)."
