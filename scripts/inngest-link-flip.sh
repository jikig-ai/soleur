#!/usr/bin/env bash
# inngest-link-flip.sh - the orchestration body of .github/workflows/inngest-link-flip.yml (#10136, ADR-292).
#
# Flips the web -> Inngest link between http://10.0.1.40:8288 and https://10.0.1.40:8443 by changing ONE
# Doppler flag (INNGEST_LINK_TLS in soleur/prd) and redeploying the running web image so ci-deploy.sh's
# resolve_inngest_link re-reads it. Nothing here writes Doppler or Terraform state itself: the flag is changed
# only by the Tier-B `inngest_link_flag` job of apply-web-platform-infra.yml (apply_target=inngest-link-flag),
# which this script dispatches and waits for. Every network call is bounded.
#
#   inngest-link-flip.sh flip     pending:<epoch> -> redeploy (canary, then prod) -> verify -> flag 1
#   inngest-link-flip.sh off      flag absent -> redeploy -> verify (the rollback; also run by hand)
#   inngest-link-flip.sh revert   best-effort `off` for the workflow's failure/cancel step; always exits 0
#
# THE LEASE IS THE CONTROL, not this script. `pending:<epoch>` is honoured by the resolver only while
# now <= epoch + 1800 s, after which it resolves to http plus an event. So an aborted run (this script killed,
# the off dispatch blocked on an environment reviewer nobody is there to approve) cannot leave the web tier on
# https against a host that cannot answer: the worst case is 30 minutes. The `revert` path is best effort.
#
# WHAT "VERIFIED" MEANS, stated so it is not over-read. The canary layer (docker inspect shows https, an
# in-container fetch and inngest.send succeed, the CA-withheld negative control fails, the registry is non-empty)
# runs INSIDE ci-deploy.sh before the swap and a failed canary exits non-zero and keeps the old container; so a
# terminal deploy-status of exit_code 0 for our tag is this script's proof of canary + prod swap on the host that
# answers /hooks/deploy-status (web-1). web-2 receives the deploy over the private-net fan-out (`peers`) and its
# own canary/swap result is NOT readable from CI: read the ci-deploy resolver log lines for it from Better Stack
# (runbook inngest-server.md, "Link TLS"). The script therefore ends with an explicit reminder, not a claim.
#
# Environment (all supplied by the workflow; none is echoed):
#   GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID     gh CLI + the audit string
#   WEBHOOK_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET   the deploy webhook (bearer-curl.sh, ADR-280)
# Test seams (never set by the workflow): FLIP_SLEEP (sleep command), FLIP_NOW (date +%s command),
#   FLIP_POLL_MAX (deploy-status attempts), FLIP_WATCH_TIMEOUT_S.

set -euo pipefail

FLIP_LEASE_S=1800
FLIP_PEERS="10.0.1.10,10.0.1.11"
FLIP_APPLY_WORKFLOW="apply-web-platform-infra.yml"
FLIP_DEPLOY_URL="https://deploy.soleur.ai/hooks/deploy"
FLIP_STATUS_URL="https://deploy.soleur.ai/hooks/deploy-status"
FLIP_HANDSHAKE_URL="https://deploy.soleur.ai/hooks/inngest-tls-handshake"
FLIP_HEALTH_URL="https://app.soleur.ai/health"
FLIP_IMAGE="ghcr.io/jikig-ai/soleur-web-platform"
FLIP_SLEEP="${FLIP_SLEEP:-sleep}"
FLIP_NOW="${FLIP_NOW:-date +%s}"
FLIP_POLL_MAX="${FLIP_POLL_MAX:-720}"
FLIP_POLL_INTERVAL_S=5
FLIP_DONE_AT=""
FLIP_WATCH_TIMEOUT_S="${FLIP_WATCH_TIMEOUT_S:-1500}"
# deploy-status is a single slot, so a frame older than the trigger is the PREVIOUS deploy. 60 s clock-skew
# tolerance (the host stamps start_ts with its own clock), as restart-inngest-server.yml does.
FLIP_SKEW_S=60
# ci-deploy-wrapper.sh hard-kills at 4800 s; a status frame still `running` inside that window is live.
FLIP_IN_FLIGHT_CEILING_S=4800

flip_now() { $FLIP_NOW; }
flip_sleep() { $FLIP_SLEEP "$1"; }
# Both go to stderr: GitHub parses workflow commands from either stream, and stdout stays free for results.
flip_log() { printf '%s\n' "$*" >&2; }
flip_err() { printf '::error::%s\n' "$*" >&2; }

flip_load_bearer() {
  # shellcheck source=/dev/null
  source "${FLIP_BEARER_LIB:-${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh}" \
    || { flip_err "scripts/lib/bearer-curl.sh could not be loaded."; return 1; }
}

# flip_webhook <GET|POST> <url> <body-or-empty> <out-file>: prints the HTTP code ("000" on a transport failure or a
# refused credential). The signature and the Cloudflare Access pair ride curl's stdin config, never an argument list.
flip_webhook() {
  local method="$1" url="$2" body="$3" out="$4" code
  # shellcheck disable=SC2034  # read by NAME inside bc_curl
  FLIP_SIG="$(printf '%s' "$body" | bc_hmac_sha256_hex WEBHOOK_SECRET)" || FLIP_SIG=""
  if [[ "$method" == POST ]]; then
    code="$(bc_curl inngest-link-flip 'X-Signature-256:sha256=:FLIP_SIG' 'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
      'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- -s --max-time 30 -o "$out" -w '%{http_code}' \
      -X POST -H 'Content-Type: application/json' -d "$body" "$url")" || code=000
  else
    code="$(bc_curl inngest-link-flip 'X-Signature-256:sha256=:FLIP_SIG' 'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
      'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- -s --max-time 15 -o "$out" -w '%{http_code}' \
      -X GET "$url")" || code=000
  fi
  printf '%s' "$code"
}

# flip_guard_idle: refuse to start while another deploy is running or while another apply holds the Terraform
# mutex. The ci-deploy flock is the real serializer; this only keeps the lease from burning in a queue.
flip_guard_idle() {
  local f="${RUNNER_TEMP:-/tmp}/flip-status.json" code exit_code start now busy st n
  code="$(flip_webhook GET "$FLIP_STATUS_URL" "" "$f")"
  if [[ "$code" == 200 ]] && jq -e . "$f" >/dev/null 2>&1; then
    exit_code="$(jq -r '.exit_code // -99' "$f")"; start="$(jq -r '.start_ts // 0' "$f")"; now="$(flip_now)"
    if [[ "$exit_code" == -1 && "$start" =~ ^[0-9]+$ && $((now - start)) -lt $FLIP_IN_FLIGHT_CEILING_S ]]; then
      flip_err "a deploy is already running (elapsed $((now - start))s); not starting a flip behind it."; return 1
    fi
  else
    flip_err "cannot read /hooks/deploy-status (HTTP ${code}); refusing to flip blind."; return 1
  fi
  busy=0
  for st in in_progress queued; do
    n="$(gh run list --workflow "$FLIP_APPLY_WORKFLOW" --status "$st" --json databaseId -q 'length' 2>/dev/null)" \
      || { flip_err "cannot list ${FLIP_APPLY_WORKFLOW} runs; refusing to flip blind."; return 1; }
    busy=$((busy + ${n:-0}))
  done
  if [[ "$busy" != 0 ]]; then
    flip_err "${FLIP_APPLY_WORKFLOW} has ${busy} run(s) in flight; the flag apply would queue and burn the lease."; return 1
  fi
}

# flip_apply_flag <off|1|pending:epoch>: dispatch the Tier-B job, find OUR run, wait for it. The run is identified by
# its non-skipped `inngest_link_flag` job and a creation time at or after the dispatch (the dispatch API returns no id).
flip_apply_flag() {
  local value="$1" t0 id="" cid created cj
  [[ "$value" =~ ^(off|1|pending:[0-9]{10})$ ]] || { flip_err "refusing a flag value outside {off, 1, pending:<epoch>}."; return 1; }
  t0="$(flip_now)"
  gh workflow run "$FLIP_APPLY_WORKFLOW" --ref main -f apply_target=inngest-link-flag \
    -f "inngest_link_value=${value}" -f "reason=inngest-link-flip run ${GITHUB_RUN_ID:-local}: ${value%%:*}" \
    || { flip_err "could not dispatch the inngest-link-flag job."; return 1; }
  for _ in $(seq 1 120); do
    flip_sleep 5
    while read -r cid created; do
      [[ -n "$cid" ]] || continue
      [[ "$(date -u -d "$created" +%s 2>/dev/null || echo 0)" -ge $((t0 - 10)) ]] || continue
      cj="$(gh run view "$cid" --json jobs -q '[.jobs[] | select(.name == "inngest_link_flag")] | if length == 0 then "none" else .[0].conclusion end' 2>/dev/null || echo none)"
      # none = the jobs are not created yet (queued behind the Terraform mutex); skipped = another apply_target's run.
      [[ "$cj" == none || "$cj" == skipped ]] && continue
      id="$cid"; break
    done < <(gh run list --workflow "$FLIP_APPLY_WORKFLOW" --event workflow_dispatch --limit 20 --json databaseId,createdAt -q '.[] | "\(.databaseId) \(.createdAt)"' 2>/dev/null || true)
    [[ -n "$id" ]] && break
  done
  [[ -n "$id" ]] || { flip_err "the dispatched inngest-link-flag run never appeared (value ${value%%:*})."; return 1; }
  flip_log "flag apply run ${id} (value ${value%%:*})"
  timeout "$FLIP_WATCH_TIMEOUT_S" gh run watch "$id" --exit-status --interval 10 >/dev/null \
    || { flip_err "the inngest-link-flag run ${id} did not finish green (value ${value%%:*})."; return 1; }
}

# flip_redeploy: redeploy the RUNNING version (same image, canary-validated, cron-drained swap through ci-deploy.sh)
# and wait for a terminal frame of our own. Sets FLIP_DONE_AT to the epoch at which the terminal frame was observed. Precedent: apply-deploy-pipeline-fix.yml "Redeploy to load applied profile" (#5875).
flip_redeploy() {
  local f="${RUNNER_TEMP:-/tmp}/flip-deploy.json" ver tag payload code trig exit_code reason ftag start
  ver="$(curl -sf --max-time 15 "$FLIP_HEALTH_URL" 2>/dev/null | jq -r '.version // ""' 2>/dev/null || true)"
  tag="v${ver}"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { flip_err "cannot resolve a released semver from ${FLIP_HEALTH_URL}; not redeploying."; return 1; }
  payload="$(printf '{"command":"deploy web-platform %s %s","peers":"%s"}' "$FLIP_IMAGE" "$tag" "$FLIP_PEERS")"
  trig="$(flip_now)"
  code="$(flip_webhook POST "$FLIP_DEPLOY_URL" "$payload" "$f")"
  [[ "$code" == 202 ]] || { flip_err "the deploy webhook answered HTTP ${code}; nothing was redeployed."; return 1; }
  flip_log "redeploy of ${tag} accepted; polling deploy-status"
  for _ in $(seq 1 "$FLIP_POLL_MAX"); do
    flip_sleep "$FLIP_POLL_INTERVAL_S"
    rm -f "$f"
    code="$(flip_webhook GET "$FLIP_STATUS_URL" "" "$f")"
    [[ "$code" == 200 ]] || continue
    jq -e . "$f" >/dev/null 2>&1 || continue
    exit_code="$(jq -r '.exit_code // -99' "$f")"; reason="$(jq -r '.reason // "unknown"' "$f" | tr -cd 'a-z0-9_-')"
    ftag="$(jq -r '.tag // ""' "$f")"; start="$(jq -r '.start_ts // 0' "$f")"
    [[ "$start" =~ ^[0-9]+$ ]] || start=0
    # A frame that started before our trigger is the previous deploy's, whatever it says.
    (( start >= trig - FLIP_SKEW_S )) || continue
    case "$exit_code" in
      0) if [[ "$ftag" == "$tag" ]]; then flip_log "ci-deploy.sh completed for ${tag} (canary passed, prod swapped on the answering host)"; FLIP_DONE_AT="$(flip_now)"; return 0; fi ;;
      -1|-2|-3) ;;
      *) if [[ "$reason" == lock_contention ]]; then continue; fi
         flip_err "ci-deploy.sh exited ${exit_code} (reason=${reason}, tag=${ftag}): the canary or the swap failed and the old container keeps serving."; return 1 ;;
    esac
  done
  flip_err "ci-deploy.sh reported no terminal frame for ${tag} within $((FLIP_POLL_MAX * FLIP_POLL_INTERVAL_S))s."
  return 1
}

# flip_verify <t0>: the post-swap checks that need no host access. The lease must not have lapsed during the deploy
# (a swap that straddled the expiry may have resolved to http; promoting to `1` would then claim a state we did not see).
flip_verify() {
  local t0="$1" done_at="$2" f="${RUNNER_TEMP:-/tmp}/flip-hs.json" code
  if (( done_at > t0 + FLIP_LEASE_S )); then
    flip_err "the deploy finished $((done_at - t0))s after the lease epoch (lease ${FLIP_LEASE_S}s): the swap may have resolved to http. Not promoting; re-run flip."; return 1
  fi
  code="$(flip_webhook GET "$FLIP_HANDSHAKE_URL" "" "$f")"
  [[ "$code" == 200 ]] || { flip_err "the handshake hook answered HTTP ${code}: the verified-TLS probe (200 with the CA, certificate failure without it) did not pass on web-1."; return 1; }
  flip_log "handshake probe on web-1: HTTP 200 (verified with the CA; the same request without the CA is asserted to fail inside the hook)"
}

flip_cmd_flip() {
  local t0
  flip_load_bearer; flip_guard_idle
  t0="$(flip_now)"
  flip_apply_flag "pending:${t0}"
  flip_redeploy
  flip_verify "$t0" "$FLIP_DONE_AT"
  flip_apply_flag 1
  flip_log "FLIPPED: flag=1. T (last prod swap observed, before the drain) = ${FLIP_DONE_AT}. Take the counter baseline AFTER the old container drains; web-2's swap is proven by its ci-deploy resolver log (Better Stack), not by this run."
}

flip_cmd_off() {
  flip_load_bearer; flip_guard_idle
  flip_apply_flag off
  flip_redeploy
  flip_log "OFF: flag removed and the running version redeployed on the http link. web-2 follows through the fan-out; confirm it from the ci-deploy log."
}

flip_cmd_revert() {
  flip_log "revert: best-effort flag off + redeploy (the 30-minute lease bounds the worst case)"
  flip_load_bearer || return 0
  ( flip_apply_flag off ) || flip_log "::warning::the best-effort off dispatch did not finish green; the lease (${FLIP_LEASE_S}s) bounds the exposure."
  ( flip_redeploy >/dev/null ) || flip_log "::warning::the best-effort redeploy did not complete; run the workflow with action=off."
  return 0
}

main() {
  case "${1:-}" in
    flip) flip_cmd_flip ;;
    off) flip_cmd_off ;;
    revert) flip_cmd_revert ;;
    *) printf 'usage: %s flip|off|revert\n' "${0##*/}" >&2; return 64 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
