#!/usr/bin/env bash
# dispatch-web-redeploy/track.sh — same-version redeploy via /hooks/deploy (#8211 PR2).
#
# Rebuilt on the apply-deploy-pipeline-fix.yml "Redeploy to load applied profile"
# mechanism (ADR-237 D6 amendment): the web-platform-release arm is gone from this
# path because same-version redeploys must NOT mint a release — the cutover's flip and
# rollback both need the RUNNING image restarted, not a new version shipped. There is
# no GitHub Actions run on this path at all, so the old databaseId>baseline poll is
# replaced by the deploy-status frame clock: a qualifying frame has
# component=web-platform AND tag==TARGET AND start_ts > PRIOR_START (the status read
# taken before our POST; host-clock comparison, never runner-side created_at).
#
#   1. Resolve TARGET_TAG from the running container: GET https://app.<base>/health
#      (.version is the baked BUILD_VERSION; ci-deploy.sh requires ^v[0-9]+\.[0-9]+\.[0-9]+$,
#      so re-sending the state-file .tag `latest` would be rejected AND re-stamped — the
#      #5955 wedge). Fail closed on a non-semver answer.
#   2. PRIOR_START: read /hooks/deploy-status and take its .start_ts BEFORE dispatching.
#      An unreadable or non-numeric baseline fails CLOSED: 0 would accept every
#      historical frame.
#   3. POST {"command":"deploy web-platform <image> <tag>","peers":"<csv>"} to
#      /hooks/deploy — HMAC X-Signature-256 + CF-Access headers. `peers` fans the swap
#      out to every web host (web-hosts-fanout-parity.test.sh pins the literal); a
#      single-host trigger would leave the fleet MIXED (flag on for the receiving host
#      only).
#   4. Poll /hooks/deploy-status for OUR frame. Terminal set is `ok` ONLY —
#      `ok_peer_fanout_degraded` means a host did not take the swap and the fleet is
#      mixed, so it is a failure verdict here (the seccomp precedent accepts it; the
#      cutover cannot). `lock_contention`/`adr027_prod_already_running` and
#      exit_code<0 (running) are NON-TERMINAL: a flock loser stamps OUR component+tag
#      and persists for the winner's whole swap.
#
# Env (all required; no defaults that would make a missing credential look absent-but-valid):
#   WEBHOOK_DEPLOY_SECRET   HMAC key for both endpoints (caller resolves; never printed)
#   CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET   Cloudflare Access service creds
#   APP_DOMAIN_BASE         default soleur.ai
#   WEB_HOST_PRIVATE_IPS    peers CSV (parity-test-pinned literal; empty = single-host,
#                           which the flip refuses — the fleet must all take the swap)
#   REDEPLOY_POLL_INTERVAL_S  poll interval (default 30)
#   REDEPLOY_TIMEOUT_S        give-up bound (default 4800 ≥ the ADR-078 cron drain 4200)
#   REDEploy_DRY_RUN…        (none — the workflow's proof mode never calls this script)
#
# Exit: 0 confirmed swap (frame ok, start_ts>PRIOR_START, tag==TARGET); 1 terminal
# failure/timeout; 2 usage; 78 xtrace refusal.
set -euo pipefail
export LC_ALL=C
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential (WEBHOOK_DEPLOY_SECRET) and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

APP_DOMAIN_BASE="${APP_DOMAIN_BASE:-soleur.ai}"
PEERS="${WEB_HOST_PRIVATE_IPS:-}"
INTERVAL="${REDEPLOY_POLL_INTERVAL_S:-30}"
TIMEOUT="${REDEPLOY_TIMEOUT_S:-4800}"
STATUS_URL="https://deploy.${APP_DOMAIN_BASE}/hooks/deploy-status"
DEPLOY_URL="https://deploy.${APP_DOMAIN_BASE}/hooks/deploy"
HEALTH_URL="https://app.${APP_DOMAIN_BASE}/health"

_summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY" || true; }

for v in WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
  if [[ -z "${!v:-}" ]]; then
    echo "::error::dispatch-web-redeploy: ${v} is unset — the webhook path cannot authenticate. verdict=redeploy_credential_absent"
    exit 2
  fi
done
for v in INTERVAL TIMEOUT; do
  if [[ ! "${!v}" =~ ^[0-9]+$ ]] || (( ${!v} < 1 )); then
    echo "::error::dispatch-web-redeploy: ${v} must be a positive integer (got '${!v}')."
    exit 2
  fi
done
for b in curl jq openssl; do
  command -v "$b" >/dev/null 2>&1 || { echo "::error::dispatch-web-redeploy: ${b} not on PATH (verdict=redeploy_tool_absent)"; exit 2; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. Target tag from the running container ---------------------------------------
RUNNING_VERSION="$(curl -sf --max-time 15 "$HEALTH_URL" 2>/dev/null | jq -r '.version // ""' 2>/dev/null || echo "")"
TARGET_TAG="v${RUNNING_VERSION}"
if [[ ! "$TARGET_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::dispatch-web-redeploy: cannot resolve a semver tag for the running container from ${HEALTH_URL} (.version='${RUNNING_VERSION}'). The fleet is not reporting a released BUILD_VERSION — the same-version redeploy has nothing safe to re-run. verdict=redeploy_tag_unresolved"
  exit 1
fi
echo "running version ${RUNNING_VERSION} → target tag ${TARGET_TAG} (same-image reload, no release)"

# --- Webhook plumbing (HMAC over body; CF-Access) ------------------------------------
get_status() { # -> http_code; body lands in $TMP/status.json
  local sig
  sig="$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')"
  curl -s --max-time 15 -o "$TMP/status.json" -w '%{http_code}' \
    -X GET -H "X-Signature-256: sha256=${sig}" \
    -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
    -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}" \
    "$STATUS_URL" 2>/dev/null || echo "000"
}

# --- 2. PRIOR_START baseline (fail closed) -------------------------------------------
HTTP="$(get_status)"
if [[ "$HTTP" != "200" ]]; then
  echo "::error::dispatch-web-redeploy: cannot read /hooks/deploy-status (HTTP ${HTTP}) — refusing to assert a redeploy blind. verdict=redeploy_status_unreadable"
  exit 1
fi
PRIOR_START="$(jq -r '.start_ts // 0' "$TMP/status.json" 2>/dev/null || echo 0)"
[[ "$PRIOR_START" =~ ^[0-9]+$ ]] || PRIOR_START=0
if [[ "$PRIOR_START" == "0" ]]; then
  echo "::error::dispatch-web-redeploy: /hooks/deploy-status returned no numeric start_ts — without a baseline the poll cannot tell a new swap from an old one. verdict=redeploy_baseline_unreadable"
  exit 1
fi
echo "baseline start_ts=${PRIOR_START}"

# --- 3. Dispatch --------------------------------------------------------------------
PAYLOAD="$(jq -cn --arg cmd "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform ${TARGET_TAG}" --arg peers "$PEERS" \
           'if $peers == "" then {command:$cmd} else {command:$cmd, peers:$peers} end')"
POST_SIG="$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')"
POST_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
  -X POST -H "Content-Type: application/json" \
  -H "X-Signature-256: sha256=${POST_SIG}" \
  -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
  -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}" \
  -d "$PAYLOAD" "$DEPLOY_URL" 2>/dev/null || echo "000")"
if [[ "$POST_CODE" != "202" ]]; then
  echo "::error::dispatch-web-redeploy: POST /hooks/deploy rejected (HTTP ${POST_CODE}). verdict=redeploy_dispatch_rejected"
  exit 1
fi
echo "redeploy dispatched (HTTP 202, peers='${PEERS:-<none>}'); polling for our ${TARGET_TAG} frame…"

# --- 4. Poll for our frame -----------------------------------------------------------
start=$SECONDS
while :; do
  sleep "$INTERVAL"
  HTTP="$(get_status)"
  if [[ "$HTTP" != "200" ]]; then
    echo "poll: status HTTP ${HTTP}; retrying."
  else
    COMPONENT="$(jq -r '.component // ""' "$TMP/status.json" 2>/dev/null || echo "")"
    FRAME_TAG="$(jq -r '.tag // ""' "$TMP/status.json" 2>/dev/null || echo "")"
    REASON="$(jq -r '.reason // ""' "$TMP/status.json" 2>/dev/null || echo "")"
    EXIT_CODE="$(jq -r '.exit_code // -99' "$TMP/status.json" 2>/dev/null || echo -99)"
    START_TS="$(jq -r '.start_ts // 0' "$TMP/status.json" 2>/dev/null || echo 0)"
    [[ "$START_TS" =~ ^[0-9]+$ ]] || START_TS=0

    if [[ "$COMPONENT" != "web-platform" || "$FRAME_TAG" != "$TARGET_TAG" || ! "$START_TS" -gt "$PRIOR_START" ]]; then
      echo "poll: ignoring frame (component='${COMPONENT}' tag='${FRAME_TAG}' start_ts=${START_TS}); waiting for web-platform ${TARGET_TAG} start_ts>${PRIOR_START}…"
    else
      case "$REASON" in
        lock_contention|adr027_prod_already_running)
          echo "poll: reason=${REASON} (a concurrent deploy holds the lock) — NON-TERMINAL, keep polling for the winner's terminal…"
          ;;
        *)
          if [[ "$EXIT_CODE" =~ ^-?[0-9]+$ ]] && [[ "$EXIT_CODE" -lt 0 ]]; then
            echo "poll: exit_code=${EXIT_CODE} reason=${REASON} (running) — keep polling…"
          elif [[ "$REASON" == "ok" ]]; then
            echo "redeploy terminal: reason=ok exit_code=${EXIT_CODE} — web-platform ${TARGET_TAG} swapped on all peers (start_ts=${START_TS})."
            _summary "- Same-version redeploy confirmed: \`${TARGET_TAG}\` swapped (frame start_ts \`${START_TS}\` > baseline \`${PRIOR_START}\`)."
            exit 0
          elif [[ "$REASON" == "ok_peer_fanout_degraded" ]]; then
            # The receiving host swapped but ≥1 peer did not take it — a MIXED fleet,
            # which the flag flip cannot accept (the seccomp precedent's acceptance of
            # this reason is exactly what the cutover must NOT inherit).
            echo "::error::dispatch-web-redeploy: reason=ok_peer_fanout_degraded — a peer host did not take the swap; the fleet is MIXED. verdict=redeploy_peer_fanout_degraded"
            _summary "- Redeploy DEGRADED: \`ok_peer_fanout_degraded\` — peer host did not swap; fleet mixed."
            exit 1
          else
            echo "::error::dispatch-web-redeploy: terminal reason='${REASON}' exit_code=${EXIT_CODE} for ${TARGET_TAG}. verdict=redeploy_terminal_failure"
            _summary "- Redeploy FAILED: reason \`${REASON}\` exit \`${EXIT_CODE}\`."
            exit 1
          fi
          ;;
      esac
    fi
  fi

  if (( SECONDS - start >= TIMEOUT )); then
    echo "::error::dispatch-web-redeploy: no web-platform frame with tag=${TARGET_TAG} and start_ts>${PRIOR_START} concluded ok within ${TIMEOUT}s. verdict=redeploy_timeout"
    _summary "- Redeploy NOT confirmed within ${TIMEOUT}s (baseline \`${PRIOR_START}\`)."
    exit 1
  fi
done
