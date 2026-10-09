#!/usr/bin/env bash
# Follow-through verification for #2640 (cross-workspace isolation canary dark→blocking soak).
#
# The #2640 change dark-launched the workspace-isolation canary probe NON-BLOCKING
# (the ADR-079 faithful-canary arc extended): `run_workspace_isolation_probe` runs the
# direct tier of test/sandbox-isolation.test.ts inside the canary container each deploy
# and records a classified verdict. Promotion to a BLOCKING gate is soak-gated: the probe
# must return 5 consecutive green verdicts spanning ≥3 days of real deploys.
#
# The soak signal is accumulated on the host in the deploy-state (ci-deploy.sh
# write_workspace_isolation_state: `consecutive_pass` increments on each `pass`, resets
# on `workspace_isolation_failed` / `workspace_isolation_timeout`, HOLDS on
# `canary_infra_error`; `first_pass_at` self-pins the window to the first green). So this
# script is a single stateless GET of /hooks/deploy-status (no issue ledger, no Sentry
# query) — hr-no-dashboard-eyeball-pull-data-yourself compliant.
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (≥5 consecutive green verdicts over ≥3 days — the probe is proven;
#                   a follow-up PR flips the call site from report-only to blocking)
#   1 = FAIL       (a `workspace_isolation_failed` or `workspace_isolation_timeout`
#                   verdict is recorded — investigate before promoting; do NOT flip)
#   * = TRANSIENT  (endpoint unreachable / non-JSON / field absent / soak not yet
#                   complete / `canary_infra_error`; retry next sweep)
#
# Required env (declared in the #2640 followthrough directive; wired in
# scheduled-followthrough-sweeper.yml): WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID,
# CF_ACCESS_CLIENT_SECRET.

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

if [[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]]; then echo "TRANSIENT: WEBHOOK_DEPLOY_SECRET not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_ID:-}" ]]; then echo "TRANSIENT: CF_ACCESS_CLIENT_ID not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then echo "TRANSIENT: CF_ACCESS_CLIENT_SECRET not set" >&2; exit 2; fi

STATUS_URL="https://deploy.soleur.ai/hooks/deploy-status"
REQUIRED_GREENS=5
MIN_SPAN_SECS=$((3 * 24 * 3600)) # ≥3 days

# (#9597, S2) The three credentials ride curl's stdin as `header = "..."` config lines, values checked first (the why and the
# process-substitution rule: the comment above `_bs_refuse` in scripts/betterstack-query.sh). The signature must be exactly 64
# lowercase hex (python3 missing or an empty key leaves SIGNATURE empty, and an unsigned request must never be sent). A refusal
# is TRANSIENT (exit 2, never 1: exit 1 is the FAIL verdict that flags a tracker), sends no request and prints one value-free
# marker.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_refuse() { echo "TRANSIENT: $1 is unusable; no request was sent" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=workspace-isolation-verdict-2640 reason=token_shape" >&2; exit 2; }
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
  echo "TRANSIENT: /hooks/deploy-status returned HTTP $HTTP_STATUS" >&2
  exit 2
fi
if ! printf '%s' "$BODY" | jq -e '.workspace_isolation' >/dev/null 2>&1; then
  echo "TRANSIENT: deploy-status body missing .workspace_isolation (non-JSON, old host, or a pre-tooling deploy)" >&2
  exit 2
fi

VERDICT="$(printf '%s' "$BODY" | jq -r '.workspace_isolation.verdict // "unknown"')"
REASON="$(printf '%s' "$BODY" | jq -r '.workspace_isolation.reason // ""')"
CONSEC="$(printf '%s' "$BODY" | jq -r '.workspace_isolation.consecutive_pass // 0')"
FIRST="$(printf '%s' "$BODY" | jq -r '.workspace_isolation.first_pass_at // 0')"
CHECKED="$(printf '%s' "$BODY" | jq -r '.workspace_isolation.checked_at // 0')"

for n in "$CONSEC" "$FIRST"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: non-numeric soak field ('$n')" >&2; exit 2; }
done
# Span endpoint is the host's last-observation time (`checked_at` — the "now" the
# soak was measured against); if the field is absent, fall back to this client's
# now. Either way a dark probe cannot keep accruing window: checked_at freezes
# when the writer stops running.
if [[ "$CHECKED" =~ ^[0-9]+$ ]] && [[ "$CHECKED" -gt 0 ]]; then
  NOW="$CHECKED"
else
  NOW="$(date +%s)"
fi

case "$VERDICT" in
  workspace_isolation_failed|workspace_isolation_timeout)
    echo "FAIL: workspace-isolation verdict=$VERDICT (reason=$REASON) — the direct-tier suite found a real isolation break or hung inside the canary. Investigate the failure (and the /sys mask interaction) before promoting the probe to blocking (do NOT promote)." >&2
    exit 1
    ;;
esac

SPAN=$((NOW - FIRST))
if [[ "$CONSEC" -ge "$REQUIRED_GREENS" && "$FIRST" -gt 0 && "$SPAN" -ge "$MIN_SPAN_SECS" ]]; then
  echo "PASS: $CONSEC consecutive green workspace-isolation verdicts over $((SPAN / 86400))d (≥${REQUIRED_GREENS} / ≥3d) since first_pass_at=$FIRST (reason=$REASON) — probe proven; flip the report-only call site to blocking in a follow-up PR."
  exit 0
fi

echo "TRANSIENT: soak not complete — verdict=$VERDICT consecutive_pass=$CONSEC (need ≥${REQUIRED_GREENS}) span=$((SPAN / 86400))d (need ≥3d). Retry next sweep." >&2
exit 2
