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
# WHAT THE LEASE BOUNDS, stated so it is not over-read. `pending:<epoch>` is honoured by the deploy-time resolver
# (ci-deploy.sh resolve_inngest_link) only while now <= epoch + 1800 s, after which a NEW deploy resolves http plus
# an event. It bounds how long a stuck `pending` can make NEW deploys resolve https; it does NOT touch a RUNNING
# container, whose INNGEST_BASE_URL is fixed at `docker run`. So a run that dies after the pending redeploy leaves
# the fleet dialling https until something redeploys it: the `revert` step (best effort; it fires only once the first
# flag write was attempted), an `off` run, or any later deploy after the lease lapsed.
#
# WHAT "VERIFIED" MEANS. The canary layer (docker inspect shows https, an in-container fetch and inngest.send succeed,
# the CA-withheld negative control fails, the registry is non-empty) runs INSIDE ci-deploy.sh before the swap, and a
# failed canary exits non-zero and keeps the old container. The redeploy is driven through
# .github/actions/dispatch-web-redeploy/track.sh, which polls web-1's /hooks/deploy-status for our own frame and fails
# closed on `ok_peer_fanout_degraded` and on every non-`ok` terminal reason (it keeps polling through a non-terminal
# lock_contention). Its `ok` proves web-1 canary + prod swap AND that web-2 ACCEPTED the fan-out trigger (HTTP 202).
# It does NOT prove web-2's own canary or swap: web-1's single status frame carries no per-host result for web-2 (the
# peer's status is only readable over the private net). Likewise no deploy-status field and no hook reports the
# scheme the running containers resolved (the handshake hook is independent of the link env). The final line of
# every subcommand says so; read the `resolved` event (state=, scheme=) of both hosts' ci-deploy log in Better Stack.
#
# Environment (all supplied by the workflow; none is echoed):
#   GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_OUTPUT     gh CLI, the audit string, the `started` output
#   WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET   the deploy webhook (bearer-curl.sh, ADR-280);
#                                           the names track.sh reads
#   WEB_HOST_PRIVATE_IPS   the fan-out roster, a parity-pinned literal in the workflow (web-hosts-fanout-parity.test.sh);
#                          required: an empty value would redeploy web-1 alone and leave the fleet MIXED
# Test seams (never set by the workflow): FLIP_SLEEP (sleep command), FLIP_NOW (date +%s command), FLIP_TRACK (the
#   redeploy driver, default track.sh), FLIP_WATCH_TIMEOUT_S.

set -euo pipefail

FLIP_LEASE_S=1800
FLIP_APPLY_WORKFLOW="apply-web-platform-infra.yml"
FLIP_STATUS_URL="https://deploy.soleur.ai/hooks/deploy-status"
FLIP_HANDSHAKE_URL="https://deploy.soleur.ai/hooks/inngest-tls-handshake"
FLIP_SLEEP="${FLIP_SLEEP:-sleep}"
FLIP_NOW="${FLIP_NOW:-date +%s}"
# track.sh gives up after this many seconds (verdict=redeploy_timeout). The git-data cutover's redeploy uses the same 2400.
FLIP_REDEPLOY_TIMEOUT_S=2400
FLIP_TRACK="${FLIP_TRACK:-${GITHUB_WORKSPACE:-.}/.github/actions/dispatch-web-redeploy/track.sh}"
FLIP_DONE_AT=""
FLIP_WATCH_TIMEOUT_S="${FLIP_WATCH_TIMEOUT_S:-1500}"
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
  FLIP_SIG="$(printf '%s' "$body" | bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET)" || FLIP_SIG=""
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

# flip_dispatch_redeploy: redeploy the RUNNING version (same image, canary-validated, cron-drained swap through
# ci-deploy.sh) by delegating to the shared driver, track.sh. It resolves the running tag, reads the PRIOR_START baseline,
# POSTs with the full peer roster and polls for OUR frame, and it exits non-zero on `ok_peer_fanout_degraded` (a MIXED
# fleet), on every non-`ok` terminal reason and on a timeout; it keeps polling through lock_contention. This function does
# not interpret the frame itself, so it cannot accept a frame track.sh refuses. Sets FLIP_DONE_AT from the shell clock.
flip_dispatch_redeploy() {
  WEB_HOST_PRIVATE_IPS="${WEB_HOST_PRIVATE_IPS:-}" REDEPLOY_TIMEOUT_S="$FLIP_REDEPLOY_TIMEOUT_S" bash "$FLIP_TRACK" \
    || { flip_err "the fleet redeploy (track.sh) did not confirm a clean swap on every host; the verdict is in its output above."; return 1; }
  FLIP_DONE_AT="$(flip_now)"
}

# flip_require_peers: an empty roster makes track.sh redeploy web-1 alone (its manual lever), which for this flip is the
# MIXED fleet it exists to prevent. Refuse before anything is dispatched.
flip_require_peers() {
  [[ "${WEB_HOST_PRIVATE_IPS:-}" =~ ^[0-9.]+(,[0-9.]+)*$ ]] \
    || { flip_err "WEB_HOST_PRIVATE_IPS is unset or malformed; a single-host redeploy would leave the fleet mixed. Nothing was dispatched."; return 1; }
}

# flip_mark_started: tell the workflow the first flag write is about to be attempted. The revert step is gated on this
# output, so a typo-guard or idle-guard refusal (nothing written) never dispatches an off apply or a redeploy.
flip_mark_started() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf 'started=true\n' >> "$GITHUB_OUTPUT"; fi
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
  flip_load_bearer; flip_require_peers; flip_guard_idle
  t0="$(flip_now)"
  flip_mark_started
  flip_apply_flag "pending:${t0}"
  flip_dispatch_redeploy
  flip_verify "$t0" "$FLIP_DONE_AT"
  flip_apply_flag 1
  flip_log "FLIPPED: flag=1 applied and the fleet redeploy confirmed by track.sh (web-1 swapped, web-2 accepted the trigger). T (last prod swap observed, before the drain) = ${FLIP_DONE_AT}. NOT VERIFIED by this run: web-2's own canary and swap, and the scheme the running containers resolved (no deploy-status field or hook carries either); read the ci-deploy 'resolved' event (state=, scheme=) of BOTH hosts in Better Stack before taking the counter baseline, which is taken AFTER the old container drains."
}

# `off` is the release valve for a fail-closed fleet, so it takes NO idle guard: deploy contention is handled by
# track.sh (lock_contention is non-terminal) and by the Tier-B job's own concurrency group.
flip_cmd_off() {
  flip_load_bearer; flip_require_peers
  flip_apply_flag off
  flip_dispatch_redeploy
  flip_log "OFF: the flag-absent apply job finished green (its plan held exactly one delete) and the fleet redeploy was confirmed by track.sh (web-1 swapped, web-2 accepted the trigger). NOT VERIFIED by this run: web-2's own canary and swap, and the scheme the running containers resolved (no deploy-status field or hook carries either); confirm with the ci-deploy 'resolved' event (state=http) of BOTH hosts in Better Stack."
}

flip_cmd_revert() {
  flip_log "revert: best-effort flag off + redeploy (the lease does not touch a running container, so this is what moves the fleet back)"
  flip_load_bearer || return 0
  flip_require_peers || return 0
  ( flip_apply_flag off ) || flip_log "::warning::the best-effort off dispatch did not finish green; run the workflow with action=off. A running https container stays on https until a redeploy."
  ( flip_dispatch_redeploy ) || flip_log "::warning::the best-effort redeploy did not complete; run the workflow with action=off."
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
