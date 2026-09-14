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
# This deliberately reuses the SENTRY_ACTIONS_RO_TOKEN the sweeper already exports
# (scheduled-followthrough-sweeper.yml; the org-level read-only `actions-read-prd`
# integration, ADR-031) — no new secret, no prod-DB credential added to the sweeper's
# blast radius.
#
# Exit codes (sweeper contract):
#   0 = PASS      (zero residual events → close #5689)
#   1 = FAIL      (residual events present → leave open, comment count)
#   * = TRANSIENT (network/HTTP/region-discovery error → leave open, retry next day)
#
# Required env: SENTRY_ACTIONS_RO_TOKEN

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands AFTER
# expansion, so a credential is printed the moment it is used. The test below
# covers EVERY credential this file references and uses `${VAR:+x}`, which is
# non-emptiness WITHOUT expanding the value -- `${VAR:-}` would print it here.
# Tracing stays available with the credentials unset, so this refuses a leak
# without blocking a debugging session.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SENTRY_ACTIONS_RO_TOKEN). Unset it to trace safely (see #7797).
' >&2
      exit 78
    fi
    ;;
esac

if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN not set" >&2; exit 2; fi

# `jikigai-eu`, not the legacy `jikigai` slug: that org was cancelled vendor-side (article-30
# register PA-8 (d), 2026-05-21) and returns 403/404 for every credential, so this probe
# posted a daily TRANSIENT 404 under the old default. Rule D pin (ADR-202): both values are
# env-settable and ride a credentialed call, so each is adjudicated against its literal.
readonly ORG_PINNED="jikigai-eu"
readonly PROJECT_PINNED="web-platform"
ORG="${SENTRY_ORG:-$ORG_PINNED}"
PROJECT="${SENTRY_PROJECT:-$PROJECT_PINNED}"
if [[ "$ORG" != "$ORG_PINNED" || "$PROJECT" != "$PROJECT_PINNED" ]]; then
  echo "TRANSIENT: refusing an unpinned Sentry destination (org=${ORG} project=${PROJECT}; pinned to ${ORG_PINNED} / ${PROJECT_PINNED})" >&2
  exit 2
fi
# `14d`, not `7d`: the project-issues endpoint accepts only '', '24h' and '14d' for
# statsPeriod (measured 2026-09-11: `7d` -> HTTP 400 "Invalid stats_period"), a defect the
# dead org slug's 404 masked until #7946 moved the probe to `jikigai-eu`. 14d still spans
# the one-week soak; the count is "residual events in the window", so a wider window
# only makes the zero-residual PASS stricter, never looser.
STATS_PERIOD="${SYNC_HEALTH_STATS_PERIOD:-14d}"

# Region discovery: the org lives on a non-US Sentry cluster (EU/DE). Resolve the
# regionUrl from the control-silo endpoint rather than hardcoding the host.
region_json=$(curl --disable --noproxy '*' -sS --max-time 30 \
  -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" \
  "https://sentry.io/api/0/organizations/${ORG}/" 2>/dev/null || echo "")
api_host=$(printf '%s' "$region_json" | jq -r '.links.regionUrl // empty' 2>/dev/null | sed 's#^https://##; s#/$##')
# Rule D (ADR-202): the host read back from the API is PINNED to the one literal it may
# take. A response naming any other host -- or no host (transport failure, `sentry.io`
# would have been the old silent fallback) -- is refused, never followed.
readonly API_HOST_PINNED="de.sentry.io"
if [[ "$api_host" != "$API_HOST_PINNED" ]]; then
  echo "TRANSIENT: regionUrl resolved to '${api_host:-<none>}', pinned to ${API_HOST_PINNED} -- refusing an unpinned destination" >&2
  exit 2
fi

# Project-scoped issues matching the arm-1 skip tags, active in the soak window.
# feature/op are emitted as Sentry tags by reportSilentFallback (observability.ts).
QUERY="feature:workspace-sync-health op:ready-null-installation"
url="https://${api_host}/api/0/projects/${ORG}/${PROJECT}/issues/"

http_code=$(curl --disable --noproxy '*' -sS -o /tmp/sh5689.json -w '%{http_code}' --max-time 45 \
  -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" \
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
