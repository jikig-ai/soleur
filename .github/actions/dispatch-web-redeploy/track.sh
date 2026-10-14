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
#   WEB_HOST_PRIVATE_IPS    peers CSV (parity-test-pinned literal). Empty dispatches a
#                           single-host swap (the manual lever); the cutover/apply call
#                           sites always pass the full literal — a one-host redeploy is
#                           caught downstream by the per-host git_data_store= assertion
#                           and by ok_peer_fanout_degraded being terminal.
#   REDEPLOY_POLL_INTERVAL_S  poll interval (default 30)
#   REDEPLOY_TIMEOUT_S        give-up bound (default 4800). Call sites inside bounded
#                           jobs override it per job budget — pin_load=1200, the
#                           cutover redeploy=2400, the finalizer=900.
#   REDEPLOY_DRY_RUN          (none — the workflow's proof mode never calls this script)
#
# Exit: 0 confirmed swap (frame ok, start_ts>PRIOR_START, tag==TARGET); 1 terminal
# failure/timeout; 2 usage; 78 xtrace refusal.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential (WEBHOOK_DEPLOY_SECRET) and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
export LC_ALL=C

# The Cloudflare Access pair and the HMAC signature reach curl on its stdin config through the shared library, never
# on an argument list (ADR-280, tracker #9597). Found by this script's own path (no GITHUB_WORKSPACE is assumed), so the
# library and the script cannot skew. A missing library is a hard failure: there is no argv fallback.
# Pure parameter expansion (no dirname/cd): this must resolve under an empty PATH too.
_here="${BASH_SOURCE[0]}"
if [[ "$_here" == */* ]]; then _here="${_here%/*}"; else _here="."; fi
# shellcheck source=/dev/null
source "${_here}/../../../scripts/lib/bearer-curl.sh" || {
  echo "::error::dispatch-web-redeploy: scripts/lib/bearer-curl.sh could not be loaded — the webhook credentials cannot be sent safely. verdict=redeploy_tool_absent"
  exit 2
}

APP_DOMAIN_BASE="${APP_DOMAIN_BASE:-soleur.ai}"
PEERS="${WEB_HOST_PRIVATE_IPS:-}"
INTERVAL="${REDEPLOY_POLL_INTERVAL_S:-30}"
TIMEOUT="${REDEPLOY_TIMEOUT_S:-4800}"
STATUS_URL="https://deploy.${APP_DOMAIN_BASE}/hooks/deploy-status"
DEPLOY_URL="https://deploy.${APP_DOMAIN_BASE}/hooks/deploy"
HEALTH_URL="https://app.${APP_DOMAIN_BASE}/health"

_summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY" || true; }

# The HMAC key only has to be non-empty (it is never a header value); the Cloudflare Access pair is a header value and
# must also be a plausible token. Either way an unusable credential is the existing credential-absent verdict, no new word.
if [[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]]; then
  echo "::error::dispatch-web-redeploy: WEBHOOK_DEPLOY_SECRET is unset — the webhook path cannot authenticate. verdict=redeploy_credential_absent"
  exit 2
fi
for v in CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
  if ! bc_ok_var "$v"; then
    bc_refuse track.sh "$v" || true
    echo "::error::dispatch-web-redeploy: ${v} is unset or not a usable token — the webhook path cannot authenticate. verdict=redeploy_credential_absent"
    exit 2
  fi
done
for v in INTERVAL TIMEOUT; do
  if [[ ! "${!v}" =~ ^[0-9]+$ ]] || (( ${!v} < 1 )); then
    echo "::error::dispatch-web-redeploy: ${v} must be a positive integer (got '${!v}')."
    exit 2
  fi
done
for b in curl jq python3; do
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
# The GET signature is constant (empty body) — compute once, not per poll iteration.
# The key rides a python3 child's environment only (never an argument list); an empty key reaches the check below.
# shellcheck disable=SC2034 # read by bc_curl / bc_ok_var through indirect expansion
GET_SIG="$(bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET < /dev/null)" || GET_SIG=""
if ! bc_ok_var GET_SIG; then
  bc_refuse track.sh GET_SIG || true
  echo "::error::dispatch-web-redeploy: the status-read signature could not be computed. verdict=redeploy_credential_absent"
  exit 2
fi
get_status() { # -> http_code; body lands in $TMP/status.json
  bc_curl track.sh 'X-Signature-256:sha256=:GET_SIG' 'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
    'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- \
    -s --max-time 15 -o "$TMP/status.json" -w '%{http_code}' -X GET \
    "$STATUS_URL" || echo "000"
}

# The status endpoint is remote-controlled bytes: bound every field before it reaches
# the log (a multi-line reason could smuggle a `::error::`/`::stop-commands::` token at
# line start — the same class _access_clean exists for).
_safe() { printf '%s' "$1" | head -n1 | tr -cd '[:print:] ' | cut -c1-120; }

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
# shellcheck disable=SC2034 # read by bc_curl / bc_ok_var through indirect expansion
POST_SIG="$(printf '%s' "$PAYLOAD" | bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET)" || POST_SIG=""
if ! bc_ok_var POST_SIG; then
  bc_refuse track.sh POST_SIG || true
  echo "::error::dispatch-web-redeploy: the dispatch signature could not be computed — nothing was sent. verdict=redeploy_credential_absent"
  exit 2
fi
POST_CODE="$(bc_curl track.sh 'X-Signature-256:sha256=:POST_SIG' 'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
  'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- \
  -s -o /dev/null -w '%{http_code}' --max-time 30 \
  -X POST -H "Content-Type: application/json" \
  -d "$PAYLOAD" "$DEPLOY_URL" || echo "000")"
if [[ "$POST_CODE" != "202" ]]; then
  echo "::error::dispatch-web-redeploy: POST /hooks/deploy rejected (HTTP ${POST_CODE}). verdict=redeploy_dispatch_rejected"
  exit 1
fi
echo "redeploy dispatched (HTTP 202, peers='${PEERS:-<none>}'); polling for our ${TARGET_TAG} frame…"

# --- 4. Poll for our frame -----------------------------------------------------------
start=$SECONDS
first=1
while :; do
  (( SECONDS - start >= TIMEOUT )) && break
  if [[ "$first" = 1 ]]; then first=0; else sleep "$INTERVAL"; fi
  HTTP="$(get_status)"
  if [[ "$HTTP" != "200" ]]; then
    echo "poll: status HTTP ${HTTP}; retrying."
  else
    COMPONENT="$(_safe "$(jq -r '.component // ""' "$TMP/status.json" 2>/dev/null || echo "")")"
    FRAME_TAG="$(_safe "$(jq -r '.tag // ""' "$TMP/status.json" 2>/dev/null || echo "")")"
    REASON="$(_safe "$(jq -r '.reason // ""' "$TMP/status.json" 2>/dev/null || echo "")")"
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
done
echo "::error::dispatch-web-redeploy: no web-platform frame with tag=${TARGET_TAG} and start_ts>${PRIOR_START} concluded ok within ${TIMEOUT}s. verdict=redeploy_timeout"
_summary "- Redeploy NOT confirmed within ${TIMEOUT}s (baseline \`${PRIOR_START}\`)."
exit 1
