#!/usr/bin/env bash
# Follow-through readback for #10445 (hosted agent Bash outage: apply-seccomp unshare(CLONE_NEWUSER) EPERM).
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. It reads the deploy-state the host publishes on /hooks/deploy-status and
# prints the faithful sandbox canary's verdict and the deployed tag. The faithful canary was GREEN for the whole outage
# (its replay ends in `-- true` and never runs the SDK's command-side wrapper), so a green here is NOT proof that a
# hosted Bash call works. It is the discoverable readback of the canary the incident record cites (the PIR
# knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md); the
# fix itself is pinned pre-merge by test/sandbox-wrapped-command-runtime.test.ts and the docker suite's wrapped-command
# arms, and watched at runtime by the `agent_sandbox_bash_denial` Better Stack alert (betterstack-logs-alerts.tf).
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (deploy-status reports sandbox_canary.verdict=pass; prints sandbox_canary=pass and the tag)
#   1 = FAIL       (sandbox_canary.verdict=sandbox_broken; prints sandbox_canary=fail)
#   * = TRANSIENT  (endpoint unreachable / non-JSON / no verdict yet; retry next sweep)
#
# Required env (declared in the tracker's followthrough directive): WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID,
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

# (#9597, S2) The three credentials ride curl's stdin as `header = "..."` config lines, values checked first (the why and the
# process-substitution rule: the comment above `_bs_refuse` in scripts/betterstack-query.sh). The signature must be exactly 64
# lowercase hex (python3 missing or an empty key leaves SIGNATURE empty, and an unsigned request must never be sent). A refusal
# is TRANSIENT (exit 2, never 1: exit 1 is the FAIL verdict that flags a tracker), sends no request and prints one value-free
# marker.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_refuse() { echo "TRANSIENT: $1 is unusable; no request was sent" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=sandbox-readback-10445 reason=token_shape" >&2; exit 2; }
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
if ! printf '%s' "$BODY" | jq -e '.sandbox_canary' >/dev/null 2>&1; then
  echo "TRANSIENT: deploy-status body missing .sandbox_canary (non-JSON or old host)" >&2
  exit 2
fi

VERDICT="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.verdict // "unknown"')"
TAG="$(printf '%s' "$BODY" | jq -r '.tag // "unknown"')"
case "$VERDICT" in
  pass)
    echo "sandbox_canary=pass tag=$TAG"
    exit 0
    ;;
  sandbox_broken)
    echo "sandbox_canary=fail tag=$TAG" >&2
    exit 1
    ;;
  *)
    echo "TRANSIENT: sandbox_canary.verdict='$VERDICT' (no verdict yet)" >&2
    exit 2
    ;;
esac
