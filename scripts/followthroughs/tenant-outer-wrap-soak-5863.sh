#!/usr/bin/env bash
# Follow-through verification for #5863 (outer-wrap canary report-only → promote soak).
#
# The #5863 arm ships the outer-wrap canary NON-BLOCKING (report-only): each
# deploy replays the self-authored mount-table fixture inside the canary
# container, runs the shared isolation payload in it, and records a verdict
# to its own durable ledger (ci-deploy.sh SANDBOX_OUTER_WRAP_CANARY_STATE_FILE —
# separate from the inner arm so the two soak windows never alias). Promotion
# to gating is soak-gated per wg-dark-launch-deploy-gates: the report-only
# verdict must stay green across real deploys, with the window pinned strictly
# AFTER the #5863 deploy (first_pass_at self-pins on the first green).
#
# The soak signal is accumulated on the host in deploy-state
# (write_sandbox_canary_state's consecutive_pass/first_pass_at counters, same
# shape as the inner canary's), surfaced on /hooks/deploy-status as
# .outer_wrap_canary — a single stateless GET, no issue ledger, no Sentry
# query (hr-no-dashboard-eyeball-pull-data-yourself).
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (≥5 consecutive green verdicts over ≥3 days — promote the
#                   outer-wrap arm to gating in a follow-up; sweeper closes the soak issue)
#   1 = FAIL       (the outer-wrap replay returned sandbox_broken — the file-cap
#                   mountns regressed or a sibling mount was realized;
#                   investigate before promoting)
#   * = TRANSIENT  (endpoint unreachable / non-JSON / soak not yet complete; retry)
#
# Required env (wired in scheduled-followthrough-sweeper.yml):
#   WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET.
#
# RETIREMENT: when the tracker closes (soak green) or the arm is promoted to
# gating, delete this file and its mention in the #5863 tracker body; no other
# suite pins it.

set -uo pipefail

# Refuse xtrace with a live credential bound (#7797) — the webhook secret is a
# real credential; tracing would echo it into whatever captures the log.
case "$-" in
  *x*)
    if [ -n "${WEBHOOK_DEPLOY_SECRET:+x}${CF_ACCESS_CLIENT_ID:+x}${CF_ACCESS_CLIENT_SECRET:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (WEBHOOK_DEPLOY_SECRET/CF_ACCESS_*). Unset them to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

if [[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]]; then echo "TRANSIENT: WEBHOOK_DEPLOY_SECRET not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_ID:-}" ]]; then echo "TRANSIENT: CF_ACCESS_CLIENT_ID not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then echo "TRANSIENT: CF_ACCESS_CLIENT_SECRET not set" >&2; exit 2; fi

STATUS_URL="https://deploy.soleur.ai/hooks/deploy-status"
REQUIRED_GREENS=5
MIN_SPAN_SECS=$((3 * 24 * 3600)) # ≥3 days

# /hooks/deploy-status is a GET whose HMAC is computed over an EMPTY body
# (mirrors canary-promotion-5875.sh), plus CF-Access headers.
SIGNATURE="$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')"

# Credential headers ride a process-substituted --config, not argv (a `-H`
# arg is world-readable in /proc/<pid>/cmdline) — and the curl is
# transport-confined (`--disable` aborts ~/.curlrc, `--noproxy '*'` blocks
# proxy redirection).
RESP="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\nHTTP_STATUS:%{http_code}' \
  -X GET \
  --config - \
  "$STATUS_URL" < <(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' \
    "$SIGNATURE" "$CF_ACCESS_CLIENT_ID" "$CF_ACCESS_CLIENT_SECRET") 2>/dev/null)"

HTTP_STATUS="$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')"
BODY="$(printf '%s' "$RESP" | sed '$d')"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: /hooks/deploy-status returned HTTP $HTTP_STATUS" >&2
  exit 2
fi
if ! printf '%s' "$BODY" | jq -e '.outer_wrap_canary' >/dev/null 2>&1; then
  echo "TRANSIENT: deploy-status body missing .outer_wrap_canary (non-JSON or a host image that predates the #5863 deploy)" >&2
  exit 2
fi

VERDICT="$(printf '%s' "$BODY" | jq -r '.outer_wrap_canary.verdict // "unknown"')"
REASON="$(printf '%s' "$BODY" | jq -r '.outer_wrap_canary.reason // ""')"
CONSEC="$(printf '%s' "$BODY" | jq -r '.outer_wrap_canary.consecutive_pass // 0')"
FIRST="$(printf '%s' "$BODY" | jq -r '.outer_wrap_canary.first_pass_at // 0')"
CHECKED="$(printf '%s' "$BODY" | jq -r '.outer_wrap_canary.checked_at // 0')"

for n in "$CONSEC" "$FIRST" "$CHECKED"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: non-numeric soak field ('$n')" >&2; exit 2; }
done

if [[ "$VERDICT" == "sandbox_broken" ]]; then
  echo "FAIL: outer-wrap canary verdict=sandbox_broken reason=$REASON — the file-cap mountns regressed or the realized isolation probe failed. Investigate server/agent-outer-wrap.ts + Dockerfile setcap/cloud-init --cap-add posture before promoting (do NOT promote)." >&2
  exit 1
fi

# PASS is bound to the LATEST observation, not just the historical counters:
# canary_infra_error holds (not resets) consecutive_pass, so a stale counter
# could otherwise PASS while the current verdict is an infra flake or an
# "unknown" sentinel. And a checked_at that has not advanced means the canary
# has not actually run recently — the ledger is stale, not proven.
NOW=$(date +%s)
STALE_SECS=$((7 * 24 * 3600))
if [[ $((NOW - CHECKED)) -gt "$STALE_SECS" ]]; then
  echo "TRANSIENT: canary ledger stale — checked_at=$CHECKED is >${STALE_SECS}s old (last run has not reported recently). Retry next sweep." >&2
  exit 2
fi

SPAN=$((CHECKED - FIRST))
if [[ "$VERDICT" == "pass" && "$CONSEC" -ge "$REQUIRED_GREENS" && "$FIRST" -gt 0 && "$SPAN" -ge "$MIN_SPAN_SECS" ]]; then
  echo "PASS: $CONSEC consecutive green outer-wrap canary verdicts over $((SPAN / 86400))d (≥${REQUIRED_GREENS} / ≥3d) since first_pass_at=$FIRST — soak proven; promote the arm to gating."
  exit 0
fi

echo "TRANSIENT: soak not complete — verdict=$VERDICT consecutive_pass=$CONSEC (need ≥${REQUIRED_GREENS}) span=$((SPAN / 86400))d (need ≥3d). Retry next sweep." >&2
exit 2
