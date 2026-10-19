#!/usr/bin/env bash
# Follow-through verification for #10548 (deploy-time SDK Bash smoke, dark -> blocking soak; ADR-079 addendum 2026-10-19).
#
# #10453 dark-launched `run_sdk_bash_smoke` NON-BLOCKING: each deploy runs ONE real Bash call through the real Agent SDK, the
# shipped shim and the production sandbox config inside the canary container and records a verdict in its own ledger
# (/mnt/data/ci-deploy-sdk-bash-smoke.json, surfaced on /hooks/deploy-status as `.sdk_bash_smoke`). Promotion to a BLOCKING gate is
# soak-gated by ADR-079: 5 consecutive green verdicts spanning >= 3 days of real deploys, with the coverage field present and
# equal to the shim-and-wrapper tuple (a `replay_only` pass never counts; the writer holds the counter on it).
#
# The soak signal is accumulated on the host (ci-deploy.sh run_sdk_bash_smoke through write_sandbox_canary_state: `consecutive_pass`
# increments on each `pass`, resets on `sdk_bash_smoke_failed`, HOLDS on `smoke_infra_error`; `first_pass_at` self-pins the window
# to the first green). So this script is a single stateless GET of /hooks/deploy-status (no issue ledger, no Sentry query), the
# workspace-isolation-verdict-2640.sh precedent. It reads the smoke's OWN ledger, never the shared deploy frame.
#
# Every path prints ONE stdout line starting `sdk_bash_smoke` (the discoverability probe's expected output, and the sweeper's
# summary), with the verdict values reduced to a safe charset (they come from a remote JSON body).
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (>= 5 consecutive green verdicts over >= 3 days, latest verdict `pass`, coverage sdk_wrapper_shim_prodtuple;
#                   a follow-up PR promotes the smoke to blocking: a code change that adds a red-verdict->rollback path in
#                   run_sdk_bash_smoke AND drops the call-site `|| true`. Enabling the agent-sandbox-unix-deny flag is a separate,
#                   operator-authorized step tracked in #10548)
#   1 = FAIL       (an `sdk_bash_smoke_failed` verdict is recorded: investigate before promoting; do NOT flip. Also: >= 3 consecutive
#                   `smoke_infra_error` verdicts, `consecutive_infra_error` >= 3 -- the probe is blind and has not exercised Bash on the
#                   last 3 deploys; flags the tracker. The host records the same condition as `SDK_BASH_SMOKE_STALE` in journald and
#                   Sentry; nothing emails it)
#   * = TRANSIENT  (endpoint unreachable / non-JSON / field absent / soak not complete / 1-2 `smoke_infra_error` / unknown / a pass whose
#                   coverage is not the shim-and-wrapper tuple / a non-numeric counter; retry next sweep)
#
# Required env (declared in the #10548 followthrough directive): WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET.
#
# RETIREMENT: when #10548 closes (soak green and the smoke promoted) delete this file, its .test.sh, the `sdk-bash-smoke-verdict-10548`
# line in scripts/test-all.sh, the shard-TSV rows and the bearer-sweep manifest row.

# #7797: refuse to run under xtrace while a live credential is bound. `$-` is tested FIRST and the
# bindings ONLY with `${VAR:+x}` (expands to a literal `x`): a `-n "$VAR"` test would itself print
# the value under `-x` before the refusal fires. HMAC_KEY is the signing key's per-command name.
case "$-" in
  *x*)
    if [ -n "${WEBHOOK_DEPLOY_SECRET:+x}" ] || [ -n "${CF_ACCESS_CLIENT_ID:+x}" ] || [ -n "${CF_ACCESS_CLIENT_SECRET:+x}" ] || [ -n "${HMAC_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

set -uo pipefail

# One summary line on stdout for every path (the first token is the discoverability contract).
_say() { printf 'sdk_bash_smoke %s\n' "$1"; }
# Reduce a remote value to a safe one-line charset (no newline, no workflow-command prefix) and cap it.
_safe() { printf '%s' "${1:-}" | LC_ALL=C tr -dc 'A-Za-z0-9_.=: -' | cut -c1-80; }

if [[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]]; then _say "status=TRANSIENT reason=WEBHOOK_DEPLOY_SECRET_not_set"; echo "TRANSIENT: WEBHOOK_DEPLOY_SECRET not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_ID:-}" ]]; then _say "status=TRANSIENT reason=CF_ACCESS_CLIENT_ID_not_set"; echo "TRANSIENT: CF_ACCESS_CLIENT_ID not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then _say "status=TRANSIENT reason=CF_ACCESS_CLIENT_SECRET_not_set"; echo "TRANSIENT: CF_ACCESS_CLIENT_SECRET not set" >&2; exit 2; fi

STATUS_URL="https://deploy.soleur.ai/hooks/deploy-status"
REQUIRED_GREENS=5
MIN_SPAN_SECS=$((3 * 24 * 3600)) # >= 3 days
FULL_COVERAGE="sdk_wrapper_shim_prodtuple"

# (#9597, S2) The three credentials ride curl's stdin as `header = "..."` config lines, values checked first (the why and the
# process-substitution rule: the comment above `_bs_refuse` in scripts/betterstack-query.sh). The signature must be exactly 64
# lowercase hex (python3 missing or an empty key leaves SIGNATURE empty, and an unsigned request must never be sent). A refusal
# is TRANSIENT (exit 2, never 1: exit 1 is the FAIL verdict that flags a tracker), sends no request and prints one value-free
# marker.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_refuse() { _say "status=TRANSIENT reason=credential_shape_refused"; echo "TRANSIENT: $1 is unusable; no request was sent" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=sdk-bash-smoke-verdict-10548 reason=token_shape" >&2; exit 2; }
_bearer_ok "$CF_ACCESS_CLIENT_ID" || _refuse "the Cloudflare Access client id"
_bearer_ok "$CF_ACCESS_CLIENT_SECRET" || _refuse "the Cloudflare Access client secret"

# /hooks/deploy-status is a GET whose HMAC is computed over an EMPTY body
# (mirrors the deploy-inngest-image.yml status poll), plus CF-Access headers.
SIGNATURE="$(printf '' | HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null)" || SIGNATURE=""
[[ "$SIGNATURE" =~ ^[0-9a-f]{64}$ ]] || _refuse "the request signature (python3 missing or the webhook key empty)"

RESP="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\nHTTP_STATUS:%{http_code}' \
  -X GET \
  "$STATUS_URL" \
  --config - < <(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' "$SIGNATURE" "$CF_ACCESS_CLIENT_ID" "$CF_ACCESS_CLIENT_SECRET" 2>/dev/null) 2>/dev/null)"

HTTP_STATUS="$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')"
BODY="$(printf '%s' "$RESP" | sed '$d')"

if [[ "$HTTP_STATUS" != "200" ]]; then
  _say "status=TRANSIENT reason=http_$(_safe "$HTTP_STATUS")"
  echo "TRANSIENT: /hooks/deploy-status returned HTTP $(_safe "$HTTP_STATUS")" >&2
  exit 2
fi
if ! printf '%s' "$BODY" | jq -e '.sdk_bash_smoke' >/dev/null 2>&1; then
  _say "status=TRANSIENT reason=field_absent"
  echo "TRANSIENT: deploy-status body missing .sdk_bash_smoke (non-JSON, an old host script, or a deploy that never reached the smoke)" >&2
  exit 2
fi

VERDICT="$(_safe "$(printf '%s' "$BODY" | jq -r '.sdk_bash_smoke.verdict // "unknown"')")"
REASON="$(_safe "$(printf '%s' "$BODY" | jq -r '.sdk_bash_smoke.reason // ""')")"
COVERAGE="$(_safe "$(printf '%s' "$BODY" | jq -r '.sdk_bash_smoke.coverage // ""')")"
CONSEC="$(printf '%s' "$BODY" | jq -r '.sdk_bash_smoke.consecutive_pass // 0')"
FIRST="$(printf '%s' "$BODY" | jq -r '.sdk_bash_smoke.first_pass_at // 0')"
CHECKED="$(printf '%s' "$BODY" | jq -r '.sdk_bash_smoke.checked_at // 0')"
# Consecutive `smoke_infra_error` verdicts (the host bumps it on an infra error and resets it on any other verdict). It is the ONLY
# signal that the probe itself is dead (e.g. a .dockerignore regression drops sdk-bash-probe.mjs: `probe_absent` every deploy), which
# the soak counters cannot show: they HOLD on an infra error. See the stale-probe rule below.
CIE="$(printf '%s' "$BODY" | jq -r '.sdk_bash_smoke.consecutive_infra_error // 0')"
BLIND_THRESHOLD=3

for n in "$CONSEC" "$FIRST" "$CIE"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { _say "status=TRANSIENT reason=non_numeric_soak_field verdict=$VERDICT"; echo "TRANSIENT: non-numeric soak field" >&2; exit 2; }
done
# Span endpoint is the host's last-observation time (`checked_at`); if absent, fall back to this client's now. Residual (the 2640
# precedent): a ledger frozen AFTER the criteria were met still reports PASS; the promotion PR is human-reviewed and re-reads the
# ledger's freshness.
if [[ "$CHECKED" =~ ^[0-9]+$ ]] && [[ "$CHECKED" -gt 0 ]]; then
  NOW="$CHECKED"
else
  NOW="$(date +%s)"
fi
SPAN=$((NOW - FIRST))
SUMMARY="verdict=$VERDICT coverage=${COVERAGE:-none} consecutive_pass=$CONSEC consecutive_infra_error=$CIE span_days=$((SPAN / 86400)) reason=${REASON:-none}"

case "$VERDICT" in
  sdk_bash_smoke_failed)
    _say "status=FAIL $SUMMARY"
    echo "FAIL: sdk_bash_smoke verdict=$VERDICT (reason=$REASON): a real wrapped Bash call failed in the canary image. Investigate (canary-probe-set.md, SDK Bash smoke section) before promoting the smoke to blocking (do NOT promote)." >&2
    exit 1
    ;;
esac

# The latest verdict must itself be `pass` (`smoke_infra_error` HOLDS counters rather than resetting them, so a stale counter could
# otherwise PASS while the current verdict is an infra flake), and the coverage must be the shim-and-wrapper tuple.
if [[ "$VERDICT" == "pass" && "$COVERAGE" == "$FULL_COVERAGE" && "$CONSEC" -ge "$REQUIRED_GREENS" && "$FIRST" -gt 0 && "$SPAN" -ge "$MIN_SPAN_SECS" ]]; then
  _say "status=PASS $SUMMARY"
  echo "PASS: $CONSEC consecutive green sdk_bash_smoke verdicts over $((SPAN / 86400))d (>= ${REQUIRED_GREENS} / >= 3d) with coverage $COVERAGE since first_pass_at=$FIRST. The smoke is proven; promote it in a follow-up PR (add the red-verdict->rollback path in run_sdk_bash_smoke AND drop the call-site '|| true'). Also review the alert rows against the real failed verdicts (no flap)." >&2
  exit 0
fi

# A dead probe must not stay silent (CTO ruling F3, 2026-10-19): >= 3 consecutive `smoke_infra_error` verdicts mean no deploy has
# actually exercised Bash for 3 deploys running. Exit 1 so the sweeper flags the #10548 tracker; the host side only records it in
# journald and Sentry (`SDK_BASH_SMOKE_STALE`), it does not email.
if [[ "$CIE" -ge "$BLIND_THRESHOLD" ]]; then
  _say "status=FAIL stale=1 $SUMMARY"
  echo "FAIL: sdk_bash_smoke probe is blind: $CIE consecutive smoke_infra_error verdicts (latest reason=$REASON). The deploy smoke has not exercised Bash on the last $CIE deploys: fix the probe (image missing sdk-bash-probe.mjs? docker exec failing?) before relying on the soak (canary-probe-set.md, SDK Bash smoke section)." >&2
  exit 1
fi

_say "status=TRANSIENT $SUMMARY"
echo "TRANSIENT: soak not complete: verdict=$VERDICT coverage=${COVERAGE:-none} consecutive_pass=$CONSEC (need >= ${REQUIRED_GREENS}) span=$((SPAN / 86400))d (need >= 3d, coverage $FULL_COVERAGE). Retry next sweep." >&2
exit 2
