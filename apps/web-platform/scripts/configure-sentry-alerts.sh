#!/usr/bin/env bash
# Idempotent Sentry alert-rule configurator for the auth observability stack.
#
# Configures three issue-alert rules that page ops via email on user-facing
# auth regressions detected through the existing `feature:auth` Sentry tag:
#
#   1. auth-exchange-code-burst    — >=5 events in 15m, op:exchangeCodeForSession
#   2. auth-callback-no-code-burst — >=3 events in 15m, op:callback_no_code
#   3. auth-per-user-loop          — >=3 unique-user events in 5m, feature:auth
#
# Idempotency: GET /rules/, match by name, PUT if found else POST.
# Region detection: probes /users/me/ on sentry.io and de.sentry.io.
# Action target: prefers Sentry team slug ops|engineering, falls back to
# IssueOwners + ActiveMembers if no team is found.
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT
# Closes #2997. Runbook: knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md

set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"
: "${SENTRY_PROJECT:?SENTRY_PROJECT must be set}"

# --- Region detection ----------------------------------------------------
# Sentry has US (sentry.io) and EU (de.sentry.io) ingest clusters; the API
# hostname follows the same split. Probe /users/me/ on each candidate and
# pick whichever returns 200.
api_host=""
for candidate in sentry.io de.sentry.io; do
  http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${candidate}/api/0/users/me/")
  if [[ "$http" == "200" ]]; then
    api_host="$candidate"
    break
  fi
done
if [[ -z "$api_host" ]]; then
  echo "ERROR: Sentry token not valid against either US or EU ingest" >&2
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

# --- Rule 1: exchangeCodeForSession burst -------------------------------
# >=5 events in 15m. Issue body said 10m; Sentry intervals are
# {1m,5m,15m,1h,1d,1w,30d} — 10m is rejected. 15m is the next-larger
# accepted value (conservative on paging).
upsert_rule "auth-exchange-code-burst" \
  '[{"id":"sentry.rules.conditions.event_frequency.EventFrequencyCondition","value":5,"interval":"15m"}]' \
  '[{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"},{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"op","match":"eq","value":"exchangeCodeForSession"}]' \
  60

# --- Rule 2: callback_no_code burst (likely uri_allow_list drift) -------
upsert_rule "auth-callback-no-code-burst" \
  '[{"id":"sentry.rules.conditions.event_frequency.EventFrequencyCondition","value":3,"interval":"15m"}]' \
  '[{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"},{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"op","match":"eq","value":"callback_no_code"}]' \
  60

# --- Rule 3: per-user broken loop ---------------------------------------
# Unique-user frequency accepts the same intervals; 5m matches the issue
# body directly. Lower frequency cap (30 min) so per-user paging is timely.
upsert_rule "auth-per-user-loop" \
  '[{"id":"sentry.rules.conditions.event_frequency.EventUniqueUserFrequencyCondition","value":3,"interval":"5m"}]' \
  '[{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"}]' \
  30

echo "[done] All three Sentry alert rules upserted."
