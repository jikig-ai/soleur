#!/usr/bin/env bash
# Follow-through readback for #10445 (hosted agent Bash outage: apply-seccomp unshare(CLONE_NEWUSER) EPERM).
#
# WHAT EXIT 0 MEANS: the fix PR's merge commit is an ANCESTOR of the tag the host reports as deployed, AND the faithful
# sandbox canary's verdict is `pass`. WHAT IT DOES NOT MEAN: that a hosted Bash call works. The canary was GREEN for the
# whole outage (its replay ends in `-- true` and never runs the SDK's command-side wrapper), so a green verdict alone is
# no evidence; it is only a regression tripwire once the fix is known to be deployed. The fix is pinned pre-merge by
# test/sandbox-wrapped-command-runtime.test.ts and the docker suite's wrapped-command arms, watched at runtime by the
# `agent_sandbox_bash_denial` Better Stack alert, and the first real hosted Bash call is recorded in the PIR
# (knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md) by the
# post-merge verification before its status flips.
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (fix deployed AND sandbox_canary.verdict=pass)
#   1 = FAIL       (fix deployed AND sandbox_canary.verdict=sandbox_broken)
#   * = TRANSIENT  (PR not merged, fix not yet in the deployed tag, endpoint unreachable, non-JSON, no verdict yet)
#
# Required env (declared in the tracker's followthrough directive): WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID,
# CF_ACCESS_CLIENT_SECRET, GH_TOKEN.
# #7797: refuse to run under xtrace while a live credential is bound. `$-` is tested FIRST and the
# bindings ONLY with `${VAR:+x}` (expands to a literal `x`): a `-n "$VAR"` test would itself print
# the value under `-x` before the refusal fires. HMAC_KEY is the signing key's per-command name.
case "$-" in
  *x*)
    if [ -n "${WEBHOOK_DEPLOY_SECRET:+x}" ] || [ -n "${CF_ACCESS_CLIENT_ID:+x}" ] || [ -n "${CF_ACCESS_CLIENT_SECRET:+x}" ] || [ -n "${GH_TOKEN:+x}" ] || [ -n "${HMAC_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

set -uo pipefail

FIX_PR=10451
REPO=jikig-ai/soleur

if [[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]]; then echo "TRANSIENT: WEBHOOK_DEPLOY_SECRET not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_ID:-}" ]]; then echo "TRANSIENT: CF_ACCESS_CLIENT_ID not set" >&2; exit 2; fi
if [[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then echo "TRANSIENT: CF_ACCESS_CLIENT_SECRET not set" >&2; exit 2; fi
if [[ -z "${GH_TOKEN:-}" ]]; then echo "TRANSIENT: GH_TOKEN not set" >&2; exit 2; fi

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

# Output from the remote JSON is reduced to a safe alphabet before it is ever printed: the sweeper posts this script's
# stdout into a tracker comment, and a newline or `::` workflow command must not ride along.
VERDICT="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.verdict // "unknown"' | tr -cd 'A-Za-z0-9._-')"
TAG="$(printf '%s' "$BODY" | jq -r '.tag // ""' | tr -cd 'A-Za-z0-9._-')"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "TRANSIENT: deploy-status tag '$TAG' is not a release tag" >&2; exit 2; }

# The fix is deployed only when the PR's merge commit is contained in the deployed release tag. `compare base...head`
# reports head's position relative to base: `behind` or `identical` means the merge commit is an ancestor of the tag.
MERGE_SHA="$(gh pr view "$FIX_PR" --repo "$REPO" --json mergeCommit --jq '.mergeCommit.oid // ""' 2>/dev/null | tr -cd '0-9a-f')"
[[ "$MERGE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "TRANSIENT: PR #$FIX_PR has no merge commit yet (not merged, or gh unavailable)" >&2; exit 2; }
CMP="$(gh api "repos/$REPO/compare/web-$TAG...$MERGE_SHA" --jq .status 2>/dev/null | tr -cd 'a-z')"
case "$CMP" in
  behind|identical) : ;;
  ahead|diverged) echo "TRANSIENT: deployed tag $TAG does not contain the fix yet (compare=$CMP)" >&2; exit 2 ;;
  *) echo "TRANSIENT: could not compare web-$TAG with the merge commit (gh api returned '$CMP')" >&2; exit 2 ;;
esac

case "$VERDICT" in
  pass)
    echo "fix_deployed=yes tag=$TAG sandbox_canary=pass"
    exit 0
    ;;
  sandbox_broken)
    echo "fix_deployed=yes tag=$TAG sandbox_canary=fail" >&2
    exit 1
    ;;
  *)
    echo "TRANSIENT: sandbox_canary.verdict='$VERDICT' (no verdict yet)" >&2
    exit 2
    ;;
esac
