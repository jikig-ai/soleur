#!/usr/bin/env bash
# Follow-through soak gate for #6122 Phase 5 (registry migration GHCR → self-hosted zot).
#
# After the operator provisions (1.8) + backfills (1.9) zot and the pull-site flip goes
# live, the fleet must run zot-primary for a soak window with ZERO GHCR fallbacks before
# GHCR push/egress can be retired (tasks 5.3-5.5) and ADR-093 flips adopting → accepted
# (5.6). This script is that gate. It PASSES (closes the tracker) only when, over the
# window from just-after cutover to now, Sentry shows:
#   (a) ZERO ghcr-fallback events for EITHER image, on the rolling-deploy path
#       (ci-deploy.sh registry_pull_event, tag registry:"ghcr-fallback") AND the
#       fresh-boot path (cloud-init soleur-boot-emit, tag stage:"inngest_ghcr_fallback");
#   (b) a MIN_SAMPLE of zot-served pulls PER image (registry:"zot" image:"web" /
#       image:"inngest") — so a vacuous "zero fallbacks because nothing deployed" cannot
#       close the tracker. Proof the flip was actually exercised.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero fallbacks AND sufficient zot sample; sweeper closes the tracker)
#   1 = FAIL       (>=1 ghcr-fallback OR insufficient zot sample — leave open: a real
#                   fallback is a regression to investigate; an insufficient sample means
#                   keep soaking, do NOT retire GHCR yet)
#   * = TRANSIENT  (Sentry API unreachable / auth / parse failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wire as secrets.SENTRY_IAC_AUTH_TOKEN in the sweeper).
# Directive for the tracking issue body (pin START to the cutover UTC, earliest to >=7d):
#   <!-- soleur:followthrough script=scripts/followthroughs/zot-soak-6122.sh earliest=<UTC+7d> secrets=SENTRY_AUTH_TOKEN -->

set -uo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"

ORG="jikigai-eu"
API="https://sentry.io/api/0"
MIN_SAMPLE="${ZOT_SOAK_MIN_SAMPLE:-3}"   # min zot-served pulls per image to prove exercise

# Absolute window start — PIN THIS to just after the cutover flip (the same UTC the
# operator records in the revert runbook). Placeholder until pinned; the earliest= gate in
# the issue directive still defers the first real check to >=7 days after cutover.
START="${ZOT_SOAK_START:-<POST_CUTOVER_UTC>}"
END=$(date -u +%Y-%m-%dT%H:%M:%S)

# sentry_count <query> → echoes the event count for the window, or "TRANSIENT" on error.
sentry_count() {
  local q enc url resp status body n
  q="$1"
  enc=$(printf '%s' "$q" | jq -sRr @uri)
  url="${API}/organizations/${ORG}/events/?query=${enc}&start=${START}&end=${END}&per_page=100&field=title&field=timestamp"
  resp=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" -H "Accept: application/json" "$url" 2>/dev/null)
  status=$(printf '%s' "$resp" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
  body=$(printf '%s' "$resp" | sed '$d')
  if [[ "$status" != "200" ]]; then echo "TRANSIENT"; return; fi
  n=$(printf '%s' "$body" | jq -r '.data | length // 0' 2>/dev/null)
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "TRANSIENT"
}

# --- (a) ghcr-fallback events (rolling deploy + fresh boot), per image. Zero required. ---
FB_ROLLING=$(sentry_count 'feature:supply-chain op:image-pull registry:"ghcr-fallback"')
FB_FRESHBOOT=$(sentry_count 'stage:"inngest_ghcr_fallback"')
# --- (b) zot-served sample per image. >= MIN_SAMPLE required (proof of exercise). ---
ZOT_WEB=$(sentry_count 'feature:supply-chain op:image-pull registry:"zot" image:"web"')
ZOT_INNGEST=$(sentry_count 'feature:supply-chain op:image-pull registry:"zot" image:"inngest"')

for v in "$FB_ROLLING" "$FB_FRESHBOOT" "$ZOT_WEB" "$ZOT_INNGEST"; do
  if [[ "$v" == "TRANSIENT" ]]; then
    echo "TRANSIENT: Sentry query failed (window $START..$END) — retry next sweep." >&2
    exit 2
  fi
done

FALLBACKS=$(( FB_ROLLING + FB_FRESHBOOT ))
if [[ "$FALLBACKS" -gt 0 ]]; then
  echo "FAIL: $FALLBACKS ghcr-fallback event(s) since $START (rolling=$FB_ROLLING freshboot=$FB_FRESHBOOT) — a host could not pull from zot. Investigate before retiring GHCR (do NOT proceed to 5.3-5.5)."
  exit 1
fi

if [[ "$ZOT_WEB" -lt "$MIN_SAMPLE" || "$ZOT_INNGEST" -lt "$MIN_SAMPLE" ]]; then
  echo "FAIL(insufficient-sample): zot-served pulls web=$ZOT_WEB inngest=$ZOT_INNGEST (need >=$MIN_SAMPLE each) — zero fallbacks so far, but keep soaking until each image has been served by zot enough times to be conclusive."
  exit 1
fi

echo "PASS: 0 ghcr-fallbacks and zot served web=$ZOT_WEB inngest=$ZOT_INNGEST (>=$MIN_SAMPLE each) since $START — zot-primary soak holds. Safe to retire GHCR (5.3-5.5) and flip ADR-093 accepted (5.6)."
exit 0
