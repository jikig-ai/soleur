#!/usr/bin/env bash
# Follow-through verification for #6400 (post-deploy soak of the GHCR pull-site
# recovery fix).
#
# The fix moves GHCR credential recovery from §1A's login-outcome gate to the
# pull site: on a `docker pull` auth-denial, ci-deploy.sh re-fetches the prd
# cred, relogins, and retries the pull once. A recovered pull emits a distinct
# `op:image-pull-recovery` (level info) breadcrumb; only an UNRECOVERED denial
# emits `op:image-pull pull_result:auth_denied` (level error, WEB-PLATFORM-59).
#
# This script asserts ZERO unrecovered `op:image-pull pull_result:auth_denied`
# error events fleet-wide over the soak window. Because the directive's
# `earliest=<deploy+3d>` gates the first sweep to ≥3 days after the deploy, the
# rolling `statsPeriod=3d` window starts AFTER the deploy timestamp and naturally
# excludes the pre-deploy incident events recorded in phase0-evidence.md. A
# recovered denial (info breadcrumb) is NOT counted — the recovery working is the
# success condition, not a failure.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero unrecovered auth_denied events; sweeper closes #6400)
#   1 = FAIL       (>=1 unrecovered auth_denied event; sweeper comments, leaves open)
#   * = TRANSIENT  (Sentry API unreachable / auth failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wired in scheduled-followthrough-sweeper.yml
#   as secrets.SENTRY_IAC_AUTH_TOKEN).

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"

# Unrecovered GHCR pull denial: op:image-pull (NOT op:image-pull-recovery) with
# pull_result:auth_denied at level:error. The recovered-success breadcrumb carries
# op:image-pull-recovery (level info) and is intentionally excluded.
QUERY='op:"image-pull" pull_result:"auth_denied" level:error'

QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)

URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=3d&per_page=25&field=title&field=timestamp&field=host_id&field=recovery_stage"

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  -H "Accept: application/json" \
  "$URL")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

EVENT_COUNT=$(printf '%s' "$BODY" | jq -r '.data | length // 0' 2>/dev/null)

if ! [[ "$EVENT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse event count from response" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

if [[ "$EVENT_COUNT" -eq 0 ]]; then
  echo "PASS: 0 unrecovered GHCR pull auth_denied error events in 3d soak window (#6400 fix holds)"
  exit 0
fi

echo "FAIL: $EVENT_COUNT unrecovered GHCR pull auth_denied error event(s) in 3d window — #6400 recovery may have regressed"
printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) @ \(.timestamp) host_id=\(.host_id // "-") recovery_stage=\(.recovery_stage // "-")"' | head -25
exit 1
