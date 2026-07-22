#!/usr/bin/env bash
# Follow-through verification for #5689 item 1 (producer investigation).
#
# #5689 item 2 (immediate re-sync after backfill) shipped in PR #5696 (arm-1 of
# cron-workspace-sync-health, merged 2026-06-29). Item 1 was deferred and
# soak-gated: "if the skip(needs-reauth)/transient count stays non-zero after a
# one-week post-merge soak, investigate the write-path that mints
# repo_status='ready' rows with NULL github_installation_id. Close only if the
# soak shows zero residual."
#
# The residual signal is observable WITHOUT prod-DB access: arm-1 emits a Sentry
# event (feature:workspace-sync-health op:ready-null-installation) for EVERY
# ready+NULL-install workspace it cannot reconcile, on every daily fire. So:
#   - zero such events in the trailing soak window  → backstop fully drained,
#     no stuck producers → PASS (sweeper auto-closes #5689).
#   - any such events in the window                 → at least one workspace is
#     still ready+NULL-install (solo needs-reauth/transient OR a team workspace)
#     → FAIL (sweeper leaves #5689 open + comments the count). A human then
#     investigates the producer, or — if it is team-only, which is out of item-1
#     scope — closes #5689 manually with that rationale. Keeping it OPEN-and-loud
#     in the non-zero case is the correct outcome; only the clean (zero) case
#     auto-closes.
#
# This deliberately reuses the SENTRY_AUTH_TOKEN the sweeper already exports
# (scheduled-followthrough-sweeper.yml) — no new secret, no migration, no
# prod-DB credential added to the sweeper's blast radius.
#
# Exit codes (sweeper contract):
#   0 = PASS      (zero residual events → close #5689)
#   1 = FAIL      (residual events present → leave open, comment count)
#   * = TRANSIENT (network/HTTP/region-discovery error → leave open, retry next day)
#
# Required env: SENTRY_AUTH_TOKEN

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="${SENTRY_ORG:-jikigai}"
PROJECT="${SENTRY_PROJECT:-web-platform}"
# Trailing window covering the one-week soak. The sweeper fires daily once the
# directive's earliest (2026-07-06) passes; 7d at run time spans the soak week
# (merge 2026-06-29 → ~2026-07-06).
STATS_PERIOD="${SYNC_HEALTH_STATS_PERIOD:-7d}"

# Region discovery: the org lives on a non-US Sentry cluster (EU/DE). Resolve the
# regionUrl from the control-silo endpoint rather than hardcoding the host.
region_json=$(curl -sS --max-time 30 \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  "https://sentry.io/api/0/organizations/${ORG}/" 2>/dev/null || echo "")
api_host=$(printf '%s' "$region_json" | jq -r '.links.regionUrl // empty' 2>/dev/null | sed 's#^https://##; s#/$##')
[[ -z "$api_host" ]] && api_host="sentry.io"

# Project-scoped issues matching the arm-1 skip tags, active in the soak window.
# feature/op are emitted as Sentry tags by reportSilentFallback (observability.ts).
QUERY="feature:workspace-sync-health op:ready-null-installation"
url="https://${api_host}/api/0/projects/${ORG}/${PROJECT}/issues/"

http_code=$(curl -sS -o /tmp/sh5689.json -w '%{http_code}' --max-time 45 \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  --get "$url" \
  --data-urlencode "query=${QUERY}" \
  --data-urlencode "statsPeriod=${STATS_PERIOD}" \
  --data-urlencode "limit=25" 2>/dev/null || echo "000")

if [[ "$http_code" != "200" ]]; then
  echo "TRANSIENT: Sentry issues API returned HTTP ${http_code} (host=${api_host}, org=${ORG}, project=${PROJECT})"
  exit 2
fi

if ! jq -e 'type=="array"' /tmp/sh5689.json >/dev/null 2>&1; then
  echo "TRANSIENT: unexpected Sentry response shape (not a JSON array)"
  exit 2
fi

issue_count=$(jq 'length' /tmp/sh5689.json)
event_total=$(jq '[.[] | (.count | tonumber? // 0)] | add // 0' /tmp/sh5689.json)

echo "Soak window: ${STATS_PERIOD} | host: ${api_host} | query: ${QUERY}"
echo "Matching Sentry issues: ${issue_count} | total events in window: ${event_total}"

if [[ "$issue_count" -eq 0 ]]; then
  echo "PASS: zero ready+NULL-install skip events in the soak window — backstop drained, no stuck producers. Close #5689."
  exit 0
fi

# Non-zero: surface the per-issue breakdown so the investigator (or the
# team-only-manual-close case) has the forensic trail.
echo "FAIL: ${issue_count} stuck-workspace issue(s) still firing op:ready-null-installation:"
jq -r '.[] | "  - \(.shortId // .id): seen \(.count) | lastSeen \(.lastSeen) | \(.title)"' /tmp/sh5689.json 2>/dev/null | head -25
echo ""
echo "Action: investigate the write-path minting repo_status='ready' + NULL github_installation_id rows"
echo "        (per #5689 item 1). If the residual is TEAM workspaces only (out of"
echo "        item-1 solo scope), close #5689 manually with that rationale."
exit 1
