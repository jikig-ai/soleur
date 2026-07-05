#!/usr/bin/env bash
# Shared off-host web-2 acceptance verify (spec-flow P1-3, AC10c). EXTRACTED so
# the web_2_recreate dispatch job REUSES this poll rather than re-deriving a copy
# of the warm_standby verify. It triggers the host-side deploy fan-out to web-2
# via web-1's PUBLIC /hooks/deploy (the only off-host-reachable trigger; web-2
# :9000 is private-net-deny), then proves web-2 accepted OFF-HOST via web-1's
# /hooks/deploy-status `reason` — NO SSH, no private-IP curl. web-2 binding :9000
# (fresh cloud-init completed past the webhook-enable step) is EXACTLY what flips
# reason from ok_peer_fanout_degraded → ok under the single-peer invariant.
#
# Invariants preserved from warm_standby (do NOT weaken):
#   - ROSTER_COUNT==1 single-peer guard: reason==ok ⟹ web-2 accepted holds ONLY
#     with exactly one peer besides web-1. A future web-3 trips LOUDLY here.
#   - staleness gate: only a completion whose start_ts ADVANCED past the
#     pre-trigger baseline counts as this dispatch's deploy.
#   - terminal exit 1 on timeout (NO green-on-timeout) + on any degraded/failed
#     reason. Fails LOUD per the recovery contract (re-dispatch is idempotent).
#
# Inputs (env, all REQUIRED unless noted):
#   WEBHOOK_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET
#   WEB_HOST_PRIVATE_IPS          e.g. "10.0.1.10,10.0.1.11" (parity w/ var.web_hosts)
#   DEPLOY_STATUS_URL             default https://deploy.soleur.ai/hooks/deploy-status
#   DEPLOY_URL                    default https://deploy.soleur.ai/hooks/deploy
#   STATUS_POLL_MAX_ATTEMPTS      default 60
#   STATUS_POLL_INTERVAL_S        default 15
#   SETTLE_SECONDS                default 30 (fresh web-2 private-iface + :9000 bind)
set -euo pipefail

: "${WEBHOOK_SECRET:?WEBHOOK_SECRET required}"
: "${CF_ACCESS_CLIENT_ID:?CF_ACCESS_CLIENT_ID required}"
: "${CF_ACCESS_CLIENT_SECRET:?CF_ACCESS_CLIENT_SECRET required}"
: "${WEB_HOST_PRIVATE_IPS:?WEB_HOST_PRIVATE_IPS required}"
DEPLOY_STATUS_URL="${DEPLOY_STATUS_URL:-https://deploy.soleur.ai/hooks/deploy-status}"
DEPLOY_URL="${DEPLOY_URL:-https://deploy.soleur.ai/hooks/deploy}"
STATUS_POLL_MAX_ATTEMPTS="${STATUS_POLL_MAX_ATTEMPTS:-60}"
STATUS_POLL_INTERVAL_S="${STATUS_POLL_INTERVAL_S:-15}"
SETTLE_SECONDS="${SETTLE_SECONDS:-30}"

# Single-peer invariant (explicit, before trusting `reason`).
ROSTER_COUNT=$(printf '%s' "$WEB_HOST_PRIVATE_IPS" | tr ',' '\n' | grep -cE '10\.0\.1\.[0-9]+')
if [[ "$ROSTER_COUNT" -ne 2 ]]; then
  echo "::error::web-2 verify assumes exactly one peer besides web-1 (reason==ok ⟹ web-2 accepted), but WEB_HOST_PRIVATE_IPS enumerates ${ROSTER_COUNT} hosts. With >1 peer, reason=ok no longer uniquely proves web-2 accepted — teach this verify to read per-peer state before adding web-3."
  exit 1
fi

_empty_sig() { printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //'; }
_get_status() {
  local sig; sig=$(_empty_sig)
  curl -s --max-time 10 -o /tmp/ds-body -w '%{http_code}' -X GET \
    -H "X-Signature-256: sha256=$sig" \
    -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
    -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
    "$DEPLOY_STATUS_URL" || echo "000"
}

# 1. Baseline: read the current deployed tag + start_ts; don't POST into an
#    in-flight swap (exit_code==-1). Full-anchor tag validation.
CURRENT_TAG=""; PRE_START_TS=0
for i in $(seq 1 12); do
  HTTP_CODE=$(_get_status); BODY=$(cat /tmp/ds-body 2>/dev/null || echo "")
  if [[ -z "$BODY" ]] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
    echo "baseline $i/12: HTTP $HTTP_CODE non-JSON/empty — retrying"; sleep 10; continue
  fi
  EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
  if [[ "$EXIT_CODE" == "-1" ]]; then
    echo "baseline $i/12: web-1 deploy in flight (exit_code=-1) — waiting"; sleep 10; continue
  fi
  CURRENT_TAG=$(echo "$BODY" | jq -r '.tag // ""')
  PRE_START_TS=$(echo "$BODY" | jq -r '.start_ts // 0')
  break
done
if [[ ! "$CURRENT_TAG" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
  echo "::error::could not read a valid current deployed tag from web-1 deploy-status (got '${CURRENT_TAG}'). Cannot redeploy the current version — aborting (recreate already landed; re-dispatch is idempotent)."
  exit 1
fi
[[ "$PRE_START_TS" =~ ^[0-9]+$ ]] || PRE_START_TS=0
echo "current deployed tag = ${CURRENT_TAG}; pre-trigger start_ts baseline = ${PRE_START_TS}"
# Bounded settle for the fresh web-2 private interface / :9000 bind.
sleep "$SETTLE_SECONDS"

# 2. Trigger the fan-out (re-swaps web-1 at the current tag first, then web-2).
#    Tag-downgrade race guard: re-read and adopt the freshest tag before POSTing.
curl -s --max-time 10 -o /tmp/ds-body -w '%{http_code}' -X GET \
  -H "X-Signature-256: sha256=$(_empty_sig)" \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  "$DEPLOY_STATUS_URL" >/dev/null 2>&1 || true
DEPLOY_TAG="$CURRENT_TAG"
RE_BODY=$(cat /tmp/ds-body 2>/dev/null || echo "")
if [[ -n "$RE_BODY" ]] && echo "$RE_BODY" | jq -e . >/dev/null 2>&1; then
  FRESH_TAG=$(echo "$RE_BODY" | jq -r '.tag // ""')
  if [[ "$FRESH_TAG" =~ ^v[0-9][A-Za-z0-9._-]*$ ]] && [[ "$FRESH_TAG" != "$CURRENT_TAG" ]]; then
    echo "tag advanced '${CURRENT_TAG}' -> '${FRESH_TAG}' between baseline and trigger; deploying the freshest to avoid a downgrade re-swap of web-1."
    DEPLOY_TAG="$FRESH_TAG"
  fi
fi
PAYLOAD=$(printf '{"command":"deploy web-platform ghcr.io/jikig-ai/soleur-web-platform %s","peers":"%s"}' "$DEPLOY_TAG" "$WEB_HOST_PRIVATE_IPS")
TRIG_SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
  -H "Content-Type: application/json" \
  -H "X-Signature-256: sha256=$TRIG_SIG" \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  -d "$PAYLOAD" "$DEPLOY_URL")
if [[ "$HTTP_CODE" != "202" ]]; then
  echo "::error::deploy webhook rejected the web-2 fan-out (HTTP $HTTP_CODE). web-2 recreated but NOT deployed — ingress-safe (web-2 weight 0). Recovery: idempotent re-dispatch."
  exit 1
fi
echo "deploy fan-out accepted (HTTP 202) for ${DEPLOY_TAG}; verifying web-2 acceptance off-host…"

# 3. Verify poll: staleness-gated, single-peer reason==ok proof, terminal exit 1.
for i in $(seq 1 "$STATUS_POLL_MAX_ATTEMPTS"); do
  HTTP_CODE=$(_get_status); BODY=$(cat /tmp/ds-body 2>/dev/null || echo "")
  if [[ -z "$BODY" ]] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
    echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: HTTP $HTTP_CODE non-JSON/empty (endpoint not ready)"
    sleep "$STATUS_POLL_INTERVAL_S"; continue
  fi
  EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
  REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
  TAG=$(echo "$BODY" | jq -r '.tag // ""')
  START_TS=$(echo "$BODY" | jq -r '.start_ts // 0'); [[ "$START_TS" =~ ^[0-9]+$ ]] || START_TS=0
  if [[ "$START_TS" -le "$PRE_START_TS" ]]; then
    echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: still pre-trigger state (start_ts=$START_TS <= baseline=$PRE_START_TS)"
    sleep "$STATUS_POLL_INTERVAL_S"; continue
  fi
  case "$EXIT_CODE" in
    0)
      if [[ "$TAG" != "$DEPLOY_TAG" ]]; then
        echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: fresh deploy for '$TAG' (want '$DEPLOY_TAG') — waiting"
        sleep "$STATUS_POLL_INTERVAL_S"; continue
      fi
      if [[ "$REASON" == "ok" ]]; then
        echo "web-2 ACCEPTED the deploy (reason=ok, tag=$DEPLOY_TAG). web-2 :9000 bound — verified off-host (no SSH)."
        exit 0
      fi
      if [[ "$REASON" == *"_peer_fanout_degraded" ]]; then
        echo "::error::web-2 did NOT accept the deploy (reason=$REASON) — the fan-out to web-2 :9000 was not accepted (unbound listener / fresh boot still failing). Recreate landed but web-2 undeployed. Recovery: idempotent re-dispatch. RED."
        echo "$BODY" | jq .; exit 1
      fi
      echo "::error::fresh deploy completed with an unexpected reason (reason=$REASON, tag=$TAG). RED."
      echo "$BODY" | jq .; exit 1
      ;;
    -1) echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: re-swap in flight (reason=$REASON, start_ts=$START_TS)" ;;
    -3) echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: corrupt state read (reason=$REASON), retrying" ;;
    *)
      echo "::error::deploy fan-out failed (exit=$EXIT_CODE, reason=$REASON, tag=$TAG). Recreate landed, web-2 undeployed. Recovery: idempotent re-dispatch."
      echo "$BODY" | jq .; exit 1
      ;;
  esac
  sleep "$STATUS_POLL_INTERVAL_S"
done
echo "::error::web-2 fan-out did not report a fresh completion within $((STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S))s. web-2 recreate landed but the :9000 bind is unverified. Recovery: idempotent re-dispatch. Failing loudly per the recovery contract."
exit 1
