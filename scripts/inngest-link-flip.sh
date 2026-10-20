#!/usr/bin/env bash
# inngest-link-flip.sh - the orchestration body of .github/workflows/inngest-link-flip.yml (#10136, ADR-294).
#
# Flips the web -> Inngest link between http://10.0.1.40:8288 and https://10.0.1.40:8443 by changing ONE
# Doppler flag (INNGEST_LINK_TLS in soleur/prd) and redeploying the running web image so ci-deploy.sh's
# resolve_inngest_link re-reads it. Nothing here writes Doppler or Terraform state itself: the flag is changed
# only by the Tier-B `inngest_link_flag` job of apply-web-platform-infra.yml (apply_target=inngest-link-flag),
# which this script dispatches and waits for. That job writes the SOURCE KEY INNGEST_LINK_TLS in soleur/prd_terraform first
# (what every untargeted plan reads; prd_terraform does NOT inherit a post-branch Terraform-written prd key, measured
# 2026-10-19) and also hands the value to its plan as an explicit environment variable. Every network call is bounded.
#
#   inngest-link-flip.sh flip     pending:<epoch> -> redeploy (canary, then prod) -> verify -> flag 1
#   inngest-link-flip.sh off      flag absent -> redeploy -> verify (the rollback; also run by hand; idempotent: a flag
#                                 that is already absent still gets the redeploy)
#   inngest-link-flip.sh revert   best-effort `off` for the workflow's failure/cancel step; always exits 0
#
# Every subcommand ends with one verdict line (FLIPPED / OFF / REVERTED / REVERT-INCOMPLETE) and appends t=, flag_run=
# and verdict= to $GITHUB_OUTPUT plus a block to $GITHUB_STEP_SUMMARY (verdict: flipped|off|reverted|revert_incomplete|
# failed|refused; `refused` = a guard stopped the run before anything was written).
#
# WHAT THE LEASE BOUNDS, stated so it is not over-read. `pending:<epoch>` is honoured by the deploy-time resolver
# (ci-deploy.sh resolve_inngest_link) only while now <= epoch + 1800 s, after which a NEW deploy resolves http plus
# an event. It bounds how long a stuck `pending` can make NEW deploys resolve https; it does NOT touch a RUNNING
# container, whose INNGEST_BASE_URL is fixed at `docker run`. So a run that dies after the pending redeploy leaves
# the fleet dialling https until something redeploys it: the `revert` step (best effort; it fires only once the first
# flag write was attempted), an `off` run, or any later deploy after the lease lapsed.
# The lease epoch is written INTO the flag before the apply that publishes it, so it cannot be taken after the apply
# returns; the apply's own duration is therefore spent out of the lease. flip_verify keeps FLIP_LEASE_MARGIN_S of it back
# for web-2, whose deploy (and its resolver read) starts only after web-1 finishes, and prints how long the apply took.
#
# WHAT "VERIFIED" MEANS. The canary layer (docker inspect shows https, an in-container fetch and inngest.send succeed,
# the CA-withheld negative control fails, the registry is non-empty) runs INSIDE ci-deploy.sh before the swap, and a
# failed canary exits non-zero and keeps the old container. The redeploy is driven through
# .github/actions/dispatch-web-redeploy/track.sh, which polls web-1's /hooks/deploy-status for our own frame and fails
# closed on `ok_peer_fanout_degraded` and on every non-`ok` terminal reason (it keeps polling through a non-terminal
# lock_contention). Its `ok` proves web-1 canary + prod swap AND that web-2 ACCEPTED the fan-out trigger (HTTP 202).
# It does NOT prove web-2's own canary or swap: web-1's single status frame carries no per-host result for web-2 (the
# peer's status is only readable over the private net). Likewise no deploy-status field and no hook reports the
# scheme the running containers resolved (the handshake hook is independent of the link env). The verdict line says so
# and prints the Better Stack query that closes the gap: the ci-deploy `class=resolved` row of EACH host.
#
# CRON-QUIET WINDOW. A deploy waits in the cron drain (ci-deploy.sh CRON_DRAIN_TIMEOUT, up to 4200 s) while a claude cron
# child is in flight. /hooks/deploy-status exposes only the LAST drain's outcome (cat-deploy-state.sh cron_drain_json:
# cron_drain_wait_secs, cron_drain_timed_out), not a live in-flight signal, so flip_guard_idle cannot refuse on it: flip
# only in a cron-quiet window. A drain longer than the lease margin fails the flip closed (flip_verify) and the revert runs.
#
# Environment (all supplied by the workflow; none is echoed):
#   GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY   gh CLI, the audit string, the
#                                           `started`/`t`/`flag_run`/`verdict` outputs, the summary block
#   WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET   the deploy webhook (bearer-curl.sh, ADR-280);
#                                           the names track.sh reads
#   WEB_HOST_PRIVATE_IPS   the fan-out roster, a parity-pinned literal in the workflow (web-hosts-fanout-parity.test.sh);
#                          required: an empty value would redeploy web-1 alone and leave the fleet MIXED
# Test seams (never set by the workflow): FLIP_SLEEP (sleep command), FLIP_NOW (date +%s command), FLIP_TRACK (the
#   redeploy driver, default track.sh), FLIP_WATCH_TIMEOUT_S.


set -euo pipefail

# BUDGET TABLE (seconds). The ONE place the flip's deadlines are stated; inngest-link-flip-workflow.test.sh (A40-A42) pins the
# workflow's timeout-minutes to it. Every number below is either the pipeline's own invariant or a sum of the others.
#   FLIP_LEASE_S                the resolver's lease (ci-deploy.sh resolve_inngest_link); the next line is pinned by A17
FLIP_LEASE_S=1800
#   FLIP_LEASE_MARGIN_S         lease kept back for web-2: its deploy, and so its resolver read of `now`, starts only after
#                               web-1's whole deploy (fan_out_to_peers runs at the end) and does its own pull/verify first
FLIP_LEASE_MARGIN_S=600
#   FLIP_IN_FLIGHT_CEILING_S    ci-deploy-wrapper.sh hard-kills ci-deploy.sh at 4800 s (cron drain 4200 s + swap overhead);
#                               a status frame still `running` inside it is live. The redeploy budget below equals it: giving
#                               up earlier abandons a deploy that is still running and will swap after the revert.
FLIP_IN_FLIGHT_CEILING_S=4800
FLIP_REDEPLOY_TIMEOUT_S=4800
#   flag apply = waiting for the dispatched run to APPEAR (polls x interval; it queues behind the shared Terraform mutex)
#                + gh run watch
FLIP_APPEAR_POLLS=120
FLIP_APPEAR_POLL_S=5
FLIP_WATCH_TIMEOUT_S="${FLIP_WATCH_TIMEOUT_S:-1500}"
FLIP_GUARD_S=120
FLIP_HANDSHAKE_S=60
FLIP_APPLY_BUDGET_S=$((FLIP_APPEAR_POLLS * FLIP_APPEAR_POLL_S + FLIP_WATCH_TIMEOUT_S))
#   flip step   = guards + pending apply + redeploy + handshake + the `1` apply
FLIP_STEP_BUDGET_S=$((FLIP_GUARD_S + 2 * FLIP_APPLY_BUDGET_S + FLIP_REDEPLOY_TIMEOUT_S + FLIP_HANDSHAKE_S))
#   revert step = off apply + redeploy. On a CANCELLED run GitHub force-terminates a cancelled() step 5 minutes after the
#   cancel request (docs.github.com "Workflow cancellation reference"), whatever timeout-minutes says: `action=off` is the
#   real rollback for that case, which is why it is idempotent.
FLIP_REVERT_BUDGET_S=$((FLIP_APPLY_BUDGET_S + FLIP_REDEPLOY_TIMEOUT_S))
#   job         = a flip that fails at its last stage plus the revert that follows it, plus slack for checkout and runner
#                 start so the job ceiling never fires before the revert step's own timeout does
FLIP_JOB_SLACK_S=900
# shellcheck disable=SC2034  # read by the workflow test, which sources this file (A40-A42)
FLIP_JOB_BUDGET_S=$((FLIP_STEP_BUDGET_S + FLIP_REVERT_BUDGET_S + FLIP_JOB_SLACK_S))

FLIP_APPLY_WORKFLOW="apply-web-platform-infra.yml"
FLIP_STATUS_URL="https://deploy.soleur.ai/hooks/deploy-status"
FLIP_HANDSHAKE_URL="https://deploy.soleur.ai/hooks/inngest-tls-handshake"
FLIP_SLEEP="${FLIP_SLEEP:-sleep}"
FLIP_NOW="${FLIP_NOW:-date +%s}"
FLIP_TRACK="${FLIP_TRACK:-${GITHUB_WORKSPACE:-.}/.github/actions/dispatch-web-redeploy/track.sh}"
FLIP_DONE_AT=""
FLIP_APPLIED_AT=""
FLIP_LAST_FLAG_RUN=""
FLIP_FLAG_RUNS=""
FLIP_T0=""
FLIP_ACTION=""
# refused = a guard stopped the run before anything was written; failed = a write was attempted (or the off command passed
# its guards) and the run did not finish; the success verdicts are set only by the last line of a subcommand.
FLIP_VERDICT="refused"
FLIP_NOT_VERIFIED="NOT VERIFIED by this run: web-2's own canary and swap, and the scheme the running containers resolved (no deploy-status field or hook carries either)."

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
# mutex. The ci-deploy flock is the real serializer; this only keeps the lease from burning in a queue. (It cannot see a
# cron in flight: see the CRON-QUIET WINDOW paragraph of the header.)
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
# The job is idempotent for `off` (an already-absent flag is green, result=already_absent) and fails for a value that did
# not land (a zero-change plan), so a green run here means the flag now holds what was asked.
flip_apply_flag() {
  local value="$1" t0 id="" cid created cj
  [[ "$value" =~ ^(off|1|pending:[0-9]{10})$ ]] || { flip_err "refusing a flag value outside {off, 1, pending:<epoch>}."; return 1; }
  t0="$(flip_now)"
  gh workflow run "$FLIP_APPLY_WORKFLOW" --ref main -f apply_target=inngest-link-flag \
    -f "inngest_link_value=${value}" -f "reason=inngest-link-flip run ${GITHUB_RUN_ID:-local}: ${value%%:*}" \
    || { flip_err "could not dispatch the inngest-link-flag job."; return 1; }
  for _ in $(seq 1 "$FLIP_APPEAR_POLLS"); do
    flip_sleep "$FLIP_APPEAR_POLL_S"
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
  FLIP_LAST_FLAG_RUN="$id"; FLIP_FLAG_RUNS="${FLIP_FLAG_RUNS}${value%%:*}=${id} "
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
  FLIP_VERDICT=failed
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf 'started=true\n' >> "$GITHUB_OUTPUT"; fi
}

# flip_hs_body <file>: the handshake hook's response body, reduced to what the hook can legitimately say (fixed tokens and
# numeric curl exit codes: inngest-registry-probe.sh tls_handshake), capped, with every other character - CR/LF, ':' (so no
# `::error::` workflow command can be smuggled in), quotes - deleted.
flip_hs_body() {
  [[ -f "$1" ]] || return 0
  tr -cd 'A-Za-z0-9_= .-' < "$1" 2>/dev/null | head -c 300 || true
}

# flip_verify <t0> <done_at>: the post-swap checks that need no host access.
#  1. The redeploy must have finished at least FLIP_LEASE_MARGIN_S before the lease ran out: web-2 resolves AFTER web-1, so a
#     web-1 finish inside the margin can leave web-2 on http (lease_expired) while the flag is promoted to `1`. The same bound
#     refuses a long cron drain (finish time, not resolve time, is what is measured: a refusal there is a spurious but safe
#     rollback cycle, and the cron-quiet window of the header avoids it).
#  2. The handshake hook must answer 200 AND its body must say result=pass (a 200 from a mis-routed hook is not a pass); on
#     either failure the body is printed so the cause (verified_rc=60 CA rejected, 28/7 unreachable, unverified=ACCEPTED
#     listener accepts an unverified client) is readable without the host.
flip_verify() {
  local t0="$1" done_at="$2" f="${RUNNER_TEMP:-/tmp}/flip-hs.json" code body
  if (( done_at > t0 + FLIP_LEASE_S - FLIP_LEASE_MARGIN_S )); then
    flip_err "the deploy finished $((done_at - t0))s after the lease epoch (lease ${FLIP_LEASE_S}s, of which ${FLIP_LEASE_MARGIN_S}s are kept for web-2, which resolves after web-1; the pending apply returned at +$(( ${FLIP_APPLIED_AT:-$t0} - t0 ))s): web-2 may have resolved to http. Not promoting; re-run flip."; return 1
  fi
  code="$(flip_webhook GET "$FLIP_HANDSHAKE_URL" "" "$f")"
  body="$(flip_hs_body "$f")"
  [[ "$code" == 200 ]] || { flip_err "the handshake hook answered HTTP ${code}: the verified-TLS probe (200 with the CA, certificate failure without it) did not pass on web-1. body: ${body:-<empty>}"; return 1; }
  if [[ ! "$body" =~ ^inngest-tls-handshake([[:space:]][a-z_]+=[A-Za-z0-9]+)+$ || "$body" != *" result=pass"* ]]; then
    flip_err "the handshake hook answered HTTP 200 but its body is not a pass (want 'inngest-tls-handshake ... result=pass'). body: ${body:-<empty>}"; return 1
  fi
  flip_log "handshake probe on web-1: HTTP 200, ${body} (verified with the CA; the same request without the CA is asserted to fail inside the hook)"
}

# flip_resolved_query <since-epoch>: the command that reads the ci-deploy `resolved` row of EVERY web host from Better Stack
# (journald tag ci-deploy via Vector Source 4, info level, so it is in Better Stack but not Sentry and not the deploy run log).
# host_name is Vector's (web-1 soleur-web-platform, web-2 soleur-web-2; it can be stale on a web-1 row, #6616, so the OS
# `host` is printed beside it). --since takes ISO-8601 UTC (scripts/betterstack-query.sh); raw is double-encoded, hence the
# double fromjson?.
flip_resolved_query() {
  local since
  since="$(date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s' "doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since ${since} --grep 'class=resolved' | jq -R -r 'fromjson? | .raw? | fromjson? | select(.SYSLOG_IDENTIFIER == \"ci-deploy\") | \"\\(.host_name) \\(.host) \\(.message)\"'"
}

# flip_read_line <state=... scheme=...>: the sentence that closes the web-2 gap.
flip_read_line() {
  printf 'TO CLOSE THE GAP read the ci-deploy resolved row of EACH host (expect one row from soleur-web-platform = web-1 AND one from soleur-web-2, each with %s): %s' "$1" "$(flip_resolved_query "${FLIP_T0:-0}")"
}

# flip_emit_results: t=, flag_run= and verdict= to $GITHUB_OUTPUT and a block to $GITHUB_STEP_SUMMARY. Never fails.
flip_emit_results() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      [[ -z "$FLIP_DONE_AT" ]] || printf 't=%s\n' "$FLIP_DONE_AT"
      [[ -z "$FLIP_LAST_FLAG_RUN" ]] || printf 'flag_run=%s\n' "$FLIP_LAST_FLAG_RUN"
      printf 'verdict=%s\n' "$FLIP_VERDICT"
    } >> "$GITHUB_OUTPUT" 2>/dev/null || true
  fi
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      printf '### inngest-link-flip %s\n\n' "${FLIP_ACTION:-?}"
      printf '| field | value |\n|---|---|\n| verdict | %s |\n' "$FLIP_VERDICT"
      printf '| T (last prod swap observed, before the drain) | %s |\n' "${FLIP_DONE_AT:-n/a}"
      printf '| flag apply runs | %s |\n\n' "${FLIP_FLAG_RUNS:-none}"
      printf '%s\n' "$FLIP_NOT_VERIFIED"
    } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
  fi
  return 0
}

flip_exit_hook() {
  local rc=$?
  trap - EXIT
  flip_emit_results
  exit "$rc"
}

flip_cmd_flip() {
  local t0
  flip_load_bearer; flip_require_peers; flip_guard_idle
  t0="$(flip_now)"; FLIP_T0="$t0"
  flip_mark_started
  flip_apply_flag "pending:${t0}"
  FLIP_APPLIED_AT="$(flip_now)"
  flip_dispatch_redeploy
  flip_verify "$t0" "$FLIP_DONE_AT"
  flip_apply_flag 1
  FLIP_VERDICT=flipped
  flip_log "FLIPPED: flag=1 applied and the fleet redeploy confirmed by track.sh (web-1 swapped, web-2 accepted the trigger). T (last prod swap observed, before the drain) = ${FLIP_DONE_AT}. ${FLIP_NOT_VERIFIED} $(flip_read_line 'state=https_pending scheme=https'). The counter baseline is taken AFTER the old container drains."
}

# `off` is the release valve for a fail-closed fleet, so it takes NO idle guard: deploy contention is handled by
# track.sh (lock_contention is non-terminal) and by the Tier-B job's own concurrency group. It is idempotent: an
# already-absent flag is a green apply job, and the redeploy follows either way.
flip_cmd_off() {
  flip_load_bearer; flip_require_peers
  FLIP_VERDICT=failed; FLIP_T0="$(flip_now)"
  flip_apply_flag off
  flip_dispatch_redeploy
  FLIP_VERDICT=off
  flip_log "OFF: the flag-absent apply job finished green (its plan held exactly one delete, or the flag was already absent) and the fleet redeploy was confirmed by track.sh (web-1 swapped, web-2 accepted the trigger). ${FLIP_NOT_VERIFIED} $(flip_read_line 'state=http_default scheme=http')."
}

flip_cmd_revert() {
  local off_ok=0 redeploy_ok=0
  FLIP_VERDICT=revert_incomplete; FLIP_T0="$(flip_now)"
  flip_log "revert: best-effort flag off + redeploy (the lease does not touch a running container, so this is what moves the fleet back)"
  if flip_load_bearer && flip_require_peers; then
    if flip_apply_flag off; then off_ok=1
    else flip_log "::warning::the best-effort off dispatch did not finish green; run the workflow with action=off (idempotent). A running https container stays on https until a redeploy."; fi
    if flip_dispatch_redeploy; then redeploy_ok=1
    else flip_log "::warning::the best-effort redeploy did not complete; run the workflow with action=off (idempotent: it redeploys even when the flag is already gone)."; fi
  fi
  if [[ "$off_ok" == 1 && "$redeploy_ok" == 1 ]]; then
    FLIP_VERDICT=reverted
    flip_log "REVERTED: the flag-absent apply finished green and the fleet redeploy was confirmed by track.sh. ${FLIP_NOT_VERIFIED} $(flip_read_line 'state=http_default scheme=http')."
  else
    flip_log "REVERT-INCOMPLETE: flag off applied=${off_ok}, fleet redeployed=${redeploy_ok} (1 = yes). The fleet may still be dialling https: run the workflow with action=off (idempotent). ${FLIP_NOT_VERIFIED} $(flip_read_line 'state=http_default scheme=http')."
  fi
  return 0
}

main() {
  FLIP_ACTION="${1:-}"
  case "${1:-}" in
    flip) trap flip_exit_hook EXIT; flip_cmd_flip ;;
    off) trap flip_exit_hook EXIT; flip_cmd_off ;;
    revert) trap flip_exit_hook EXIT; flip_cmd_revert ;;
    *) printf 'usage: %s flip|off|revert\n' "${0##*/}" >&2; return 64 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
