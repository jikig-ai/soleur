#!/usr/bin/env bash
# Shared off-host web-2 acceptance verify (spec-flow P1-3, AC10c). EXTRACTED so
# the web_2_recreate dispatch job AND the warm_standby dispatch job REUSE this poll
# rather than each re-deriving a copy (#6040 — the two-divergent-copies drift
# hazard). It triggers the host-side deploy fan-out to web-2 via web-1's PUBLIC
# /hooks/deploy (the only off-host-reachable trigger; web-2 :9000 is private-net-
# deny), then proves web-2 accepted OFF-HOST via web-1's /hooks/deploy-status
# `reason` — NO SSH, no private-IP curl. web-2 binding :9000 (fresh cloud-init
# completed past the webhook-enable step) is EXACTLY what flips reason from
# ok_peer_fanout_degraded → ok under the single-peer invariant.
#
# #6051 — bounded fresh-boot degraded-retry. A fresh `terraform apply -replace`
# boot of web-2 takes ~10 min (apt + docker + multi-image pull + webhook-enable);
# at fan-out time web-2's :9000 is still unbound, so the single fan-out degrades.
# Instead of aborting RED on the FIRST ok_peer_fanout_degraded (the #6051 bug),
# wait out the remaining fresh-boot window (FRESH_BOOT_WINDOW_S) then re-POST the
# fan-out EXACTLY once (DEGRADED_RETRY_MAX). This bounds web-1 (the sole live
# origin) to at most 2 swap cycles total (initial + 1 retry) — NOT a short-cadence
# loop. A booted warm-standby web-2 returns reason==ok on the FIRST fan-out, so the
# retry branch never fires there (the defaults preserve warm_standby semantics).
#
# Invariants preserved (do NOT weaken):
#   - ROSTER_COUNT==2 single-peer guard: reason==ok ⟹ web-2 accepted holds ONLY
#     with exactly one peer besides web-1. A future web-3 trips LOUDLY here.
#   - staleness gate: only a completion whose start_ts ADVANCED past the ORIGINAL
#     pre-trigger baseline counts as this dispatch's deploy. The baseline is NEVER
#     advanced on a re-trigger (a late-arriving `ok` from an earlier in-flight cycle
#     must still be accepted; advancing would filter it as pre-trigger + add clock skew).
#   - terminal exit 1 on timeout (NO green-on-timeout) + on any genuinely-failed
#     reason / non-202 (re)trigger / unexpected reason. Fails LOUD per the recovery
#     contract (re-dispatch is idempotent). lock_contention is the sole retryable exit_code=1.
#
# Inputs (env, all REQUIRED unless noted):
#   WEBHOOK_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET
#   WEB_HOST_PRIVATE_IPS          e.g. "10.0.1.10,10.0.1.11" (parity w/ var.web_hosts)
#   DEPLOY_STATUS_URL             default https://deploy.soleur.ai/hooks/deploy-status
#   DEPLOY_URL                    default https://deploy.soleur.ai/hooks/deploy
#   STATUS_POLL_MAX_ATTEMPTS      default 60   (recreate job raises to 120 — see AC5b)
#   STATUS_POLL_INTERVAL_S        default 15
#   SETTLE_SECONDS                default 30 (fresh web-2 private-iface + :9000 bind)
#   DEGRADED_RETRY_MAX            default 1   (exactly one re-POST after the boot window)
#   FRESH_BOOT_WINDOW_S           default 600 (wait this long from verify start before the single re-POST)
#   OP_CONTEXT                    default recreate  {recreate|warm-standby} — recovery-message wording
#   HEALTH_URL                    default https://app.soleur.ai/health — web-1's PUBLIC
#                                 /health. #6353: the tag the fan-out re-swaps web-1 at is
#                                 resolved from its `.version` (the actually-running
#                                 container's BUILD_VERSION), NEVER the shared deploy-status
#                                 `.tag` slot (which independent writers pollute with `latest`).
#   GITHUB_OUTPUT                 optional — deployed_tag=<tag> emitted when set (summary step consumer)
# Test seams (unset in prod → real curl / POST / wall-clock — see the sibling .test.sh):
#   DS_BODY_FILE                  status body path (default /tmp/ds-body)
#   DEPLOY_STATUS_SOURCE_CMD      overrides the GET (writes $DS_BODY_FILE, echoes HTTP code)
#   DEPLOY_POST_SINK              records each fan-out POST payload (one line per POST)
#   DEPLOY_POST_CODE_CMD          overrides the per-POST HTTP code (default DEPLOY_POST_CODE / 202)
#   HEALTH_SOURCE_CMD             overrides the /health fetch (echoes the bare `.version` string)
set -euo pipefail

# This script and the pure resolver it calls (resolve-web1-known-good-tag.sh) live in
# the same directory; resolve it from BASH_SOURCE so a caller's CWD never matters.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${WEBHOOK_SECRET:?WEBHOOK_SECRET required}"
: "${CF_ACCESS_CLIENT_ID:?CF_ACCESS_CLIENT_ID required}"
: "${CF_ACCESS_CLIENT_SECRET:?CF_ACCESS_CLIENT_SECRET required}"
: "${WEB_HOST_PRIVATE_IPS:?WEB_HOST_PRIVATE_IPS required}"
DEPLOY_STATUS_URL="${DEPLOY_STATUS_URL:-https://deploy.soleur.ai/hooks/deploy-status}"
DEPLOY_URL="${DEPLOY_URL:-https://deploy.soleur.ai/hooks/deploy}"
HEALTH_URL="${HEALTH_URL:-https://app.soleur.ai/health}"
HEALTH_SOURCE_CMD="${HEALTH_SOURCE_CMD:-}"
STATUS_POLL_MAX_ATTEMPTS="${STATUS_POLL_MAX_ATTEMPTS:-60}"
STATUS_POLL_INTERVAL_S="${STATUS_POLL_INTERVAL_S:-15}"
SETTLE_SECONDS="${SETTLE_SECONDS:-30}"
DEGRADED_RETRY_MAX="${DEGRADED_RETRY_MAX:-1}"
FRESH_BOOT_WINDOW_S="${FRESH_BOOT_WINDOW_S:-600}"
OP_CONTEXT="${OP_CONTEXT:-recreate}"
DS_BODY_FILE="${DS_BODY_FILE:-/tmp/ds-body}"
DEPLOY_STATUS_SOURCE_CMD="${DEPLOY_STATUS_SOURCE_CMD:-}"
DEPLOY_POST_SINK="${DEPLOY_POST_SINK:-}"
DEPLOY_POST_CODE_CMD="${DEPLOY_POST_CODE_CMD:-}"
DEPLOY_POST_CODE="${DEPLOY_POST_CODE:-202}"

# Single-peer invariant (explicit, before trusting `reason`). `grep -c` exits 1 on
# a zero count, which under `set -e`+`pipefail` would abort the assignment BEFORE
# the tailored error below — `|| true` lets ROSTER_COUNT=0 reach the fail-loud guard.
ROSTER_COUNT=$(printf '%s' "$WEB_HOST_PRIVATE_IPS" | tr ',' '\n' | grep -cE '10\.0\.1\.[0-9]+' || true)
if [[ "$ROSTER_COUNT" -ne 2 ]]; then
  echo "::error::web-2 verify assumes exactly one peer besides web-1 (reason==ok ⟹ web-2 accepted), but WEB_HOST_PRIVATE_IPS enumerates ${ROSTER_COUNT} hosts. With >1 peer, reason=ok no longer uniquely proves web-2 accepted — teach this verify to read per-peer state before adding web-3."
  exit 1
fi

# OP_CONTEXT-selected recovery message (the intentional per-context divergence #6040
# flagged: warm_standby's attach vs the recreate's -replace). Trailing period included.
_recovery_msg() {
  if [[ "$OP_CONTEXT" == "warm-standby" ]]; then
    printf '%s' "Attach landed (billing flips) but web-2 is undeployed — ingress-safe (web-2 weight 0). Recovery: idempotent re-dispatch."
  else
    printf '%s' "Recreate landed but web-2 is undeployed — ingress-safe (web-2 weight 0). Recovery: idempotent re-dispatch."
  fi
}

_empty_sig() { printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //'; }

_get_status() {
  if [[ -n "$DEPLOY_STATUS_SOURCE_CMD" ]]; then
    # Test seam: the injected command writes the next fixture body to $DS_BODY_FILE
    # and prints the HTTP code. Prod path (unset) uses the real curl GET below.
    bash -c "$DEPLOY_STATUS_SOURCE_CMD"
    return
  fi
  local sig; sig=$(_empty_sig)
  curl -s --max-time 10 -o "$DS_BODY_FILE" -w '%{http_code}' -X GET \
    -H "X-Signature-256: sha256=$sig" \
    -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
    -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
    "$DEPLOY_STATUS_URL" || echo "000"
}

# Resolve web-1's known-good re-swap tag from its PUBLIC /health `.version` (the
# actually-running container's baked BUILD_VERSION) — NOT the shared deploy-status
# `.tag` slot (#6353). That slot is a single last-write-wins object stamped by
# multiple independent writers (a web-platform deploy, an inngest `restart … latest`,
# a git-lock sweep); when a non-web writer owns it the verify would re-POST
# `deploy web-platform <image> latest`, which ci-deploy.sh rejects as tag_malformed —
# aborting EVERY web-host recreate. /health is immune (it never reads the shared slot).
# Same invariant ADR-079 amendment #5955 + the recreate pin-gate (#6147) already adopted
# for the two sibling readers; the pure resolver resolve-web1-known-good-tag.sh applies
# the strict `^v[0-9]+\.[0-9]+\.[0-9]+$` guard (reused unchanged — single source of the
# guard, do NOT fork the regex).
#
# HOST-TARGETING INVARIANT (load-bearing): app.<domain>/health MUST resolve to web-1,
# not a partially-recreated web-2. Holds today by construction — cloudflare_record.app
# (apps/web-platform/infra/dns.tf) is a SINGLE proxied A record pinned to web-1, NOT a
# round-robin LB, and web-2 rides at ingress weight 0. REVISIT TRIGGER: if the multi-host
# DNS rewire (#5274) or the #6178 inngest cutover makes `app` canary-weighted so web-2 can
# answer, this resolver MUST switch to a web-1-pinned health path (or re-add a host check).
# This very PR unblocks the #6178 cutover that eventually changes that — revisit then.
#
# stdout = the resolved `vX.Y.Z` tag ONLY; ALL diagnostics go to >&2. Called as
# DEPLOY_TAG="$(_resolve_known_good_tag)", any stray stdout is captured INTO DEPLOY_TAG
# and would pollute the fan-out payload. On /health unreachable or a non-semver version:
# loud ::error:: + terminal exit 1 — NEVER a silent fallback to the `.tag` seed.
_resolve_known_good_tag() {
  local version tag
  if [[ -n "$HEALTH_SOURCE_CMD" ]]; then
    # Test seam: the injected command echoes the /health `.version` string directly
    # (a bare semver / "dev" / "" — no JSON body, no HTTP code). `|| true` keeps a
    # seam that exits non-zero from aborting under set -e before the resolver runs.
    version=$(bash -c "$HEALTH_SOURCE_CMD" || true)
  else
    # web-1 here is the LIVE prod origin already serving — a one-line bounded retry
    # (NOT the pin step's 12× fresh-boot loop) covers transient CF-tunnel blips.
    # `|| true` mirrors _get_status's `|| echo "000"`: a curl transport failure must
    # surface as an empty version the resolver rejects LOUD, not a set -e abort here.
    version=$(curl -sf --max-time 15 --retry 3 --retry-connrefused "$HEALTH_URL" 2>/dev/null | jq -r '.version // ""' 2>/dev/null || true)
  fi
  # The pure resolver strict-validates + prepends `v`, emitting its OWN ::error:: to
  # >&2 and exit 1 on rejection. Capture its stdout (the tag); on failure add the
  # OP_CONTEXT recovery remediation and abort LOUD. NEVER fall back to `.tag`.
  if ! tag=$(bash "$SCRIPT_DIR/resolve-web1-known-good-tag.sh" "$version"); then
    # Strip C0 control chars from the untrusted /health value before echoing it into
    # the runner log — mirrors resolve-web1-known-good-tag.sh:55. An embedded newline
    # in a spoofed .version would otherwise inject a line-start `::workflow-command::`
    # annotation (the resolver already sanitizes its OWN diagnostic; this wrapper must
    # too, since it is reached on exactly the malformed-version path).
    local safe_version; safe_version=$(printf '%s' "$version" | tr -d '\000-\037')
    echo "::error::deploy fan-out cannot resolve web-1's known-good re-swap tag from ${HEALTH_URL} (/health .version='${safe_version}'). $(_recovery_msg)" >&2
    exit 1
  fi
  printf '%s' "$tag"
}

# POST the fan-out payload; echo the HTTP code. Test seam records the payload to a
# sink and returns a scripted code so the assertion path is network-free.
_post_fanout() {
  local payload="$1"
  if [[ -n "$DEPLOY_POST_SINK" ]]; then
    printf '%s\n' "$payload" >> "$DEPLOY_POST_SINK"
    if [[ -n "$DEPLOY_POST_CODE_CMD" ]]; then bash -c "$DEPLOY_POST_CODE_CMD"; else printf '%s' "$DEPLOY_POST_CODE"; fi
    return
  fi
  local sig; sig=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
  # `|| echo "000"` mirrors _get_status: a curl transport failure (timeout/DNS/
  # connection) surfaces as a non-202 "000" through the loud non-202 handler in
  # _trigger_fanout rather than aborting under `set -e` before the recovery message.
  curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
    -H "Content-Type: application/json" \
    -H "X-Signature-256: sha256=$sig" \
    -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
    -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
    -d "$payload" "$DEPLOY_URL" || echo "000"
}

# Emit the tag actually POSTed so the warm_standby `Warm-standby summary` step can
# read steps.verify.outputs.deployed_tag (the shared script replaces the removed
# inline `trigger` step's identical emit). Last write wins → the final tag deployed.
_emit_deployed_tag() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "deployed_tag=${DEPLOY_TAG}" >> "$GITHUB_OUTPUT"
  return 0
}

# Re-callable fan-out trigger (the INITIAL POST and each bounded retry share this).
# Re-RESOLVES the re-swap tag from web-1's /health `.version` (#6353) and REASSIGNS the
# outer DEPLOY_TAG so the verify poll's TAG==DEPLOY_TAG match tracks a tag that advanced
# during a long fresh-boot wait — else a genuine reason==ok at the NEW tag would never
# match and a HEALTHY web-2 would RED on budget exhaustion (spec-flow P1). /health is the
# UNIFORM tag source (baseline seed AND here), so the `.tag` slot is NEVER a tag source
# (architecture P1-A): the former `.tag` re-read used a looser regex than the deploy
# contract, so a v-prefixed non-strict pollutant (e.g. `v1.2.3-rc1`) could be adopted →
# POSTed → tag_malformed — the same #6353 wedge through a third seam. /health `.version`
# is web-1's running version (never a downgrade), so the downgrade-safety intent is kept.
# Asserts HTTP 202 and is TERMINAL exit 1 on non-202 (AC3f). Does NOT touch PRE_START_TS
# (the staleness baseline stays the ORIGINAL for the whole run).
_trigger_fanout() {
  DEPLOY_TAG="$(_resolve_known_good_tag)"
  local payload code
  payload=$(printf '{"command":"deploy web-platform ghcr.io/jikig-ai/soleur-web-platform %s","peers":"%s"}' "$DEPLOY_TAG" "$WEB_HOST_PRIVATE_IPS")
  code=$(_post_fanout "$payload")
  if [[ "$code" != "202" ]]; then
    echo "::error::deploy webhook rejected the web-2 fan-out (HTTP $code). $(_recovery_msg)"
    exit 1
  fi
  _emit_deployed_tag
  echo "deploy fan-out accepted (HTTP 202) for ${DEPLOY_TAG}; verifying web-2 acceptance off-host…"
}

# 1. Baseline: read start_ts (staleness baseline) + exit_code (don't POST into an
#    in-flight swap, exit_code==-1). The `.tag` field is NO LONGER read here (#6353):
#    it is the shared last-write-wins slot's last-ATTEMPT tag, which independent writers
#    (an inngest `restart … latest`, a git-lock sweep) pollute with `latest` — the wedge
#    that aborted every recreate. The re-swap tag is resolved from /health below instead.
PRE_START_TS=0
for i in $(seq 1 12); do
  HTTP_CODE=$(_get_status); BODY=$(cat "$DS_BODY_FILE" 2>/dev/null || echo "")
  if [[ -z "$BODY" ]] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
    echo "baseline $i/12: HTTP $HTTP_CODE non-JSON/empty — retrying"; sleep 10; continue
  fi
  EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
  if [[ "$EXIT_CODE" == "-1" ]]; then
    echo "baseline $i/12: web-1 deploy in flight (exit_code=-1) — waiting"; sleep 10; continue
  fi
  PRE_START_TS=$(echo "$BODY" | jq -r '.start_ts // 0')
  break
done
[[ "$PRE_START_TS" =~ ^[0-9]+$ ]] || PRE_START_TS=0
# Resolve the re-swap tag from web-1's /health `.version` — the actually-running image,
# immune to deploy-status writer contention. A non-semver / unreachable /health aborts
# LOUD inside _resolve_known_good_tag (no silent fallback to the polluted `.tag`).
DEPLOY_TAG="$(_resolve_known_good_tag)"
echo "pre-trigger start_ts baseline = ${PRE_START_TS}; re-swap tag (resolved from web-1 /health) = ${DEPLOY_TAG}"
# Bounded settle for the fresh web-2 private interface / :9000 bind.
sleep "$SETTLE_SECONDS"

# 2. Trigger the fan-out (re-swaps web-1 at the /health-resolved tag first, then web-2).
#    The re-swap tag re-resolution (uniform /health source) lives in _trigger_fanout.
_trigger_fanout

# 3. Verify poll: staleness-gated, single-peer reason==ok proof, bounded fresh-boot
#    degraded-retry, terminal exit 1 (no green-on-timeout). One overall poll budget
#    (no fresh budget per retry).
START_EPOCH=$(date +%s)
retrigger_count=0
declare -A retried   # start_ts values we have ALREADY re-POSTed against — marked ONLY when the retry fires (P0)
for i in $(seq 1 "$STATUS_POLL_MAX_ATTEMPTS"); do
  HTTP_CODE=$(_get_status); BODY=$(cat "$DS_BODY_FILE" 2>/dev/null || echo "")
  if [[ -z "$BODY" ]] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
    echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: HTTP $HTTP_CODE non-JSON/empty (endpoint not ready)"
    sleep "$STATUS_POLL_INTERVAL_S"; continue
  fi
  EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
  REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
  TAG=$(echo "$BODY" | jq -r '.tag // ""')
  START_TS=$(echo "$BODY" | jq -r '.start_ts // 0'); [[ "$START_TS" =~ ^[0-9]+$ ]] || START_TS=0
  elapsed=$(( $(date +%s) - START_EPOCH ))
  if [[ "$START_TS" -le "$PRE_START_TS" ]]; then
    echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: still pre-trigger state (start_ts=$START_TS <= baseline=$PRE_START_TS, elapsed=${elapsed}s)"
    sleep "$STATUS_POLL_INTERVAL_S"; continue
  fi
  case "$EXIT_CODE" in
    0)
      if [[ "$TAG" != "$DEPLOY_TAG" ]]; then
        echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: fresh deploy for '$TAG' (want '$DEPLOY_TAG', elapsed=${elapsed}s) — waiting"
        sleep "$STATUS_POLL_INTERVAL_S"; continue
      fi
      if [[ "$REASON" == "ok" ]]; then
        echo "web-2 ACCEPTED the deploy (reason=ok, tag=$DEPLOY_TAG, elapsed=${elapsed}s). web-2 :9000 bound — verified off-host (no SSH)."
        exit 0
      fi
      if [[ "$REASON" == *"_peer_fanout_degraded" ]]; then
        # START_TS==0 is the corrupt parse-fallback; never let it collide in the
        # `retried` map (P2). The staleness gate above already filters it whenever
        # PRE_START_TS>=0, but guard explicitly for defense.
        if [[ "$START_TS" -eq 0 ]]; then
          echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: degraded with start_ts=0 (corrupt fallback) — skipping"
          sleep "$STATUS_POLL_INTERVAL_S"; continue
        fi
        if [[ -n "${retried[$START_TS]:-}" ]]; then
          # Already re-POSTed against THIS completion — wait for the NEW cycle's fresh completion.
          echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: awaiting post-retry completion (already re-fanned start_ts=$START_TS, elapsed=${elapsed}s)"
          sleep "$STATUS_POLL_INTERVAL_S"; continue
        fi
        if [[ "$retrigger_count" -ge "$DEGRADED_RETRY_MAX" ]]; then
          echo "::error::web-2 still degraded after the single re-POST (reason=$REASON, retrigger=$retrigger_count/$DEGRADED_RETRY_MAX, elapsed=${elapsed}s). $(_recovery_msg) RED."
          echo "$BODY" | jq .; exit 1
        fi
        if [[ "$elapsed" -lt "$FRESH_BOOT_WINDOW_S" ]]; then
          # P0 (spec-flow + architecture converged): re-evaluate elapsed EVERY poll;
          # do NOT mark this start_ts consumed here, or a static fresh-boot degraded
          # state (same start_ts on every poll) would be seen once and never retried.
          echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: web-2 not yet bound (reason=$REASON, elapsed=${elapsed}s < ${FRESH_BOOT_WINDOW_S}s) — waiting out the fresh-boot window before the single re-POST"
          sleep "$STATUS_POLL_INTERVAL_S"; continue
        fi
        echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: fresh-boot window elapsed (${elapsed}s >= ${FRESH_BOOT_WINDOW_S}s) — re-POSTing the fan-out once (retrigger $((retrigger_count + 1))/$DEGRADED_RETRY_MAX)"
        _trigger_fanout
        retried[$START_TS]=1; retrigger_count=$((retrigger_count + 1))
        sleep "$STATUS_POLL_INTERVAL_S"; continue
      fi
      echo "::error::fresh deploy completed with an unexpected reason (reason=$REASON, tag=$TAG, elapsed=${elapsed}s). RED."
      echo "$BODY" | jq .; exit 1
      ;;
    -1) echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: re-swap in flight (reason=$REASON, start_ts=$START_TS, elapsed=${elapsed}s)" ;;
    -3) echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: corrupt state read (reason=$REASON, elapsed=${elapsed}s), retrying" ;;
    1)
      # lock_contention is RETRYABLE, not terminal: a re-POST may briefly overlap an
      # in-flight swap and lose flock -n (ci-deploy.sh:846-849 → final_write_state 1
      # "lock_contention"). Any OTHER exit_code=1 reason is a genuine deploy failure.
      if [[ "$REASON" == "lock_contention" ]]; then
        echo "verify $i/$STATUS_POLL_MAX_ATTEMPTS: deploy lock held by an in-flight swap (reason=lock_contention, elapsed=${elapsed}s) — retrying"
      else
        echo "::error::deploy fan-out failed (exit=1, reason=$REASON, tag=$TAG, elapsed=${elapsed}s). $(_recovery_msg)"
        echo "$BODY" | jq .; exit 1
      fi
      ;;
    *)
      echo "::error::deploy fan-out failed (exit=$EXIT_CODE, reason=$REASON, tag=$TAG, elapsed=${elapsed}s). $(_recovery_msg)"
      echo "$BODY" | jq .; exit 1
      ;;
  esac
  sleep "$STATUS_POLL_INTERVAL_S"
done
echo "::error::web-2 fan-out did not report a fresh completion within $((STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S))s (retrigger=$retrigger_count/$DEGRADED_RETRY_MAX). $(_recovery_msg) Failing loudly per the recovery contract."
exit 1
