#!/usr/bin/env bash
# Follow-through soak for epic #6027 — GA LB pool health + serving evidence (AC4/AC11).
#
# After the ga-monitor-fix / ga-pool-update arms apply, asserts over the soak window
# [DEPLOY_TS, DEPLOY_TS+7d] — DEPLOY_TS derived from the tracker's `earliest` env
# (post-deploy-incident-soak.sh pattern):
#   (a) CF pool-health API reports every origin healthy:true,
#   (b) https://app.soleur.ai/health serves 200,
#   (c) zero new Better Stack incidents in the window.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS       (all origins healthy + edge 200 + zero incidents in-window)
#   1 = FAIL       (any probe red — leave the tracker open, investigate)
#   * = TRANSIENT  (API/auth/parse failure — CANNOT ESTABLISH; retry next sweep)
#
# Required env: CF_API_TOKEN, CF_ACCOUNT_ID, DEPLOY_TS_EPOCH (window start; the
#   directive's earliest= pins the first real check), optional BETTERSTACK_API_TOKEN
#   for the incident-window leg (absent => TRANSIENT, never a silent skip).
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${CF_API_TOKEN:+x}${BETTERSTACK_API_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi ;;
esac

_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

for v in CF_API_TOKEN CF_ACCOUNT_ID DEPLOY_TS_EPOCH; do
  if [ -z "${!v:-}" ]; then printf '[TRANSIENT] %s unset — cannot establish verdict\n' "$v" >&2; exit 3; fi
done
_bearer_ok "$CF_API_TOKEN" || { printf '[TRANSIENT] CF_API_TOKEN fails shape guard\n' >&2; exit 3; }
_bearer_ok "$BETTERSTACK_API_TOKEN" || { printf '[TRANSIENT] BETTERSTACK_API_TOKEN unset/bad shape — incident leg cannot be established\n' >&2; exit 3; }
case "$DEPLOY_TS_EPOCH" in ''|*[!0-9]*) printf '[TRANSIENT] DEPLOY_TS_EPOCH not epoch digits\n' >&2; exit 3 ;; esac

fail=0
CF="https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}"

# (a) pool health — every origin across every PoP must read healthy:true.
POOL_ID=$(curl -sf --max-time 10 "${CF}/load_balancers/pools" -H "Authorization: Bearer ${CF_API_TOKEN}" \
  | jq -r '.result[] | select(.name=="web-1") | .id') || POOL_ID=""
[ -n "$POOL_ID" ] || { printf '[TRANSIENT] web-1 pool id unresolvable\n' >&2; exit 3; }
UNHEALTHY=$(curl -sf --max-time 10 "${CF}/load_balancers/pools/${POOL_ID}/health" -H "Authorization: Bearer ${CF_API_TOKEN}" \
  | jq '[.result.pop_health[].origins[][] | select(.healthy != true)] | length') || UNHEALTHY=""
case "$UNHEALTHY" in
  ''|*[!0-9]*) printf '[TRANSIENT] pool-health unreadable\n' >&2; exit 3 ;;
esac
if [ "$UNHEALTHY" -gt 0 ]; then
  printf '[FAIL] %s origin(s) unhealthy in pool %s\n' "$UNHEALTHY" "$POOL_ID" >&2; fail=1
fi

# (b) edge serving.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://app.soleur.ai/health || echo 000)
[ "$CODE" = "200" ] || { printf '[FAIL] app.soleur.ai/health -> %s\n' "$CODE" >&2; fail=1; }

# (c) incident window [DEPLOY_TS_EPOCH, +7d].
END=$((DEPLOY_TS_EPOCH + 604800))
INCIDENTS=$(curl -sf --max-time 10 \
  -H "Authorization: Bearer ${BETTERSTACK_API_TOKEN}" \
  "https://uptime.betterstack.com/api/v2/incidents?from=${DEPLOY_TS_EPOCH}&to=${END}" \
  | jq '(.data // []) | length' 2>/dev/null) || INCIDENTS=""
case "$INCIDENTS" in
  ''|*[!0-9]*) printf '[TRANSIENT] Better Stack incident query unreadable\n' >&2; exit 3 ;;
esac
if [ "$INCIDENTS" -gt 0 ]; then
  printf '[FAIL] %s Better Stack incident(s) in soak window\n' "$INCIDENTS" >&2; fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf '[PASS] pool %s all origins healthy; edge 200; %d incidents in window\n' "$POOL_ID" "$INCIDENTS"
fi
exit "$fail"
