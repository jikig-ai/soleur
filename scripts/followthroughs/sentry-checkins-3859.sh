#!/usr/bin/env bash
# Follow-through verification for #3859 (AC15 of #3849).
#
# Verifies that each of the 8 Sentry cron monitors created by the 2026-05-15
# rotation has either accumulated check-ins OR has a low-frequency schedule
# (monthly) that may still have zero. Returns:
#   0 = PASS (close-criteria met → sweeper auto-closes #3859)
#   1 = FAIL (criteria not met → sweeper leaves open, comments)
#   * = TRANSIENT (e.g. network error → sweeper leaves open, retries next day)
#
# Required env: SENTRY_AUTH_TOKEN
#
# Close criteria (from #3859 body):
#   - Every slug returns 200 on the checkins API
#   - At least 6/8 monitors have ≥1 checkin recorded (allowing 2 for
#     low-frequency / once-a-month schedules that may have no fire yet)

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="jikigai"
API="https://sentry.io/api/0"
SLUGS=(
  scheduled-terraform-drift
  scheduled-oauth-probe
  scheduled-github-app-drift-guard
  scheduled-daily-triage
  scheduled-realtime-probe
  scheduled-skill-freshness
  scheduled-content-vendor-drift
  scheduled-community-monitor
)

have_count=0
total_count=0
errors=0

for slug in "${SLUGS[@]}"; do
  total_count=$((total_count + 1))
  http_code=$(curl -sS -o /tmp/ck.json -w '%{http_code}' \
    --max-time 30 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "${API}/organizations/${ORG}/monitors/${slug}/checkins/?limit=5" || echo "000")

  if [[ "$http_code" != "200" ]]; then
    echo "FAIL: ${slug} — HTTP ${http_code}"
    errors=$((errors + 1))
    continue
  fi

  n=$(jq 'if type=="array" then length else 0 end' /tmp/ck.json 2>/dev/null || echo 0)
  if [[ "$n" -gt 0 ]]; then
    have_count=$((have_count + 1))
    echo "ok:   ${slug} — ${n} check-in(s)"
  else
    echo "warn: ${slug} — 0 check-ins (acceptable for low-frequency monitors)"
  fi
done

echo ""
echo "Summary: ${have_count}/${total_count} monitors with ≥1 check-in; ${errors} HTTP errors"

# TRANSIENT: network/HTTP errors → leave open, retry next day
if [[ "$errors" -gt 0 ]]; then
  echo "exit: TRANSIENT (HTTP errors)"
  exit 2
fi

# PASS: ≥6/8 (close-criteria met, monthly-schedule slack accepted)
if [[ "$have_count" -ge 6 ]]; then
  echo "exit: PASS"
  exit 0
fi

# FAIL: <6/8 monitors have any check-ins after the earliest gate
echo "exit: FAIL (only ${have_count} of 8 have check-ins; threshold is 6)"
exit 1
