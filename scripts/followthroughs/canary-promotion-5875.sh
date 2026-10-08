#!/usr/bin/env bash
# Follow-through verification for #5875 (faithful sandbox canary dark→blocking soak).
#
# PR2 dark-launched the faithful sandbox canary NON-BLOCKING (ADR-079): it replays
# the SDK-captured bwrap argv inside the canary container each deploy and records a
# verdict. Promotion to a BLOCKING gate (PR3) is soak-gated: the canary must return
# 5 consecutive green verdicts spanning ≥3 days of real deploys, with the window
# pinned strictly after PR2's deploy.
#
# The soak signal is accumulated on the host in the deploy-state (ci-deploy.sh
# write_sandbox_canary_state: `consecutive_pass` increments on each `pass`, resets
# on a faithful `sandbox_broken`, HOLDS on a dark-launch `canary_infra_error`;
# `first_pass_at` self-pins the window to the first green after this deploy). So
# this script is a single stateless GET of /hooks/deploy-status (no issue ledger,
# no Sentry query) — hr-no-dashboard-eyeball-pull-data-yourself compliant.
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (≥5 consecutive green verdicts over ≥3 days — canary ready to
#                   promote to blocking in PR3; sweeper closes the soak issue #5889)
#   1 = FAIL       (the faithful canary returned `sandbox_broken` — it disagreed
#                   with the legacy PASS gate; investigate before promoting)
#   * = TRANSIENT  (endpoint unreachable / non-JSON / soak not yet complete; retry)
#
# Required env (declared in the #5875 followthrough directive; wired in
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
_refuse() { echo "TRANSIENT: $1 is unusable; no request was sent" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=canary-promotion-5875 reason=token_shape" >&2; exit 2; }
_bearer_ok "$CF_ACCESS_CLIENT_ID" || _refuse "the Cloudflare Access client id"
_bearer_ok "$CF_ACCESS_CLIENT_SECRET" || _refuse "the Cloudflare Access client secret"

# /hooks/deploy-status is a GET whose HMAC is computed over an EMPTY body
# (mirrors the deploy-inngest-image.yml status poll), plus CF-Access headers.
SIGNATURE="$(printf '' | HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null)" || SIGNATURE=""
[[ "$SIGNATURE" =~ ^[0-9a-f]{64}$ ]] || _refuse "the request signature (python3 missing or the webhook key empty)"

RESP="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\nHTTP_STATUS:%{http_code}' \
  -X GET \
  "$STATUS_URL" \
  --config - < <(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' "$SIGNATURE" "$CF_ACCESS_CLIENT_ID" "$CF_ACCESS_CLIENT_SECRET") 2>/dev/null)"

HTTP_STATUS="$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')"
BODY="$(printf '%s' "$RESP" | sed '$d')"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: /hooks/deploy-status returned HTTP $HTTP_STATUS" >&2
  exit 2
fi
if ! printf '%s' "$BODY" | jq -e '.sandbox_canary' >/dev/null 2>&1; then
  echo "TRANSIENT: deploy-status body missing .sandbox_canary (non-JSON or old host)" >&2
  exit 2
fi

VERDICT="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.verdict // "unknown"')"
CONSEC="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.consecutive_pass // 0')"
FIRST="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.first_pass_at // 0')"
CHECKED="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.checked_at // 0')"
SDK="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.sdk_version // ""')"

for n in "$CONSEC" "$FIRST" "$CHECKED"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: non-numeric soak field ('$n')" >&2; exit 2; }
done

if [[ "$VERDICT" == "sandbox_broken" ]]; then
  echo "FAIL: faithful canary verdict=sandbox_broken (sdk=$SDK) — it disagreed with the legacy PASS gate. Investigate the seccomp/apparmor profile before promoting the canary to blocking (do NOT promote)." >&2
  exit 1
fi

SPAN=$((CHECKED - FIRST))
if [[ "$CONSEC" -ge "$REQUIRED_GREENS" && "$FIRST" -gt 0 && "$SPAN" -ge "$MIN_SPAN_SECS" ]]; then
  echo "PASS: $CONSEC consecutive green canary verdicts over $((SPAN / 86400))d (≥${REQUIRED_GREENS} / ≥3d) since first_pass_at=$FIRST (sdk=$SDK) — canary proven; promote to blocking in PR3."
  exit 0
fi

echo "TRANSIENT: soak not complete — verdict=$VERDICT consecutive_pass=$CONSEC (need ≥${REQUIRED_GREENS}) span=$((SPAN / 86400))d (need ≥3d). Retry next sweep." >&2
exit 2
