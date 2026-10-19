#!/usr/bin/env bash
# Follow-through readback for #10445 (hosted agent Bash outage: apply-seccomp unshare(CLONE_NEWUSER) EPERM).
#
# NOTIFY-ONLY PROBE (followthrough-convention.md, "registered sub-vocabulary"): this script NEVER exits 0 and NEVER exits 1.
# Exit 0 would make the sweeper CLOSE tracker #10456, and a green faithful canary is not proof that a hosted Bash call works:
# the canary was GREEN for the whole outage (its replay ends in `-- true` and never runs the SDK's command-side wrapper). The
# tracker's real close condition is the first real hosted Bash call recorded in the PIR
# (knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md) and the docs
# PR that flips its status, both done by a human/agent AFTER this probe reports ACTION REQUIRED. The operator ends the tracker
# by closing it AND removing its `follow-through` label.
#
# Exit semantics (registered sub-vocabulary of the TRANSIENT bucket):
#   2 = NOT YET            (PR unmerged, deployed tag predates the fix, a deploy is in flight/failed, canary not re-run since
#                           the deploy started, no verdict yet)
#   3 = CANNOT ESTABLISH   (credentials/endpoint/gh unavailable or malformed answer: the probe could not measure)
#   5 = ACTION REQUIRED    (fix deployed by a successful deploy AND the canary ran since: record the first hosted Bash call in
#                           the PIR and open the status flip PR; or the canary says sandbox_broken after the deploy: REGRESSION)
# The never-0/never-1 invariant is asserted by sandbox-readback-10445.test.sh on every row.
#
# RETIREMENT: when #10456 is closed, delete this file, its .test.sh, and the `sandbox-readback-10445` line in scripts/test-all.sh.
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

if [[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]]; then echo "CANNOT ESTABLISH: WEBHOOK_DEPLOY_SECRET not set" >&2; exit 3; fi
if [[ -z "${CF_ACCESS_CLIENT_ID:-}" ]]; then echo "CANNOT ESTABLISH: CF_ACCESS_CLIENT_ID not set" >&2; exit 3; fi
if [[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then echo "CANNOT ESTABLISH: CF_ACCESS_CLIENT_SECRET not set" >&2; exit 3; fi
if [[ -z "${GH_TOKEN:-}" ]]; then echo "CANNOT ESTABLISH: GH_TOKEN not set" >&2; exit 3; fi

STATUS_URL="https://deploy.soleur.ai/hooks/deploy-status"

# (#9597, S2) The three credentials ride curl's stdin as `header = "..."` config lines, values checked first (the why and the
# process-substitution rule: the comment above `_bs_refuse` in scripts/betterstack-query.sh). The signature must be exactly 64
# lowercase hex (python3 missing or an empty key leaves SIGNATURE empty, and an unsigned request must never be sent). A refusal
# is CANNOT ESTABLISH (exit 3, never 0 or 1), sends no request and prints one value-free
# marker.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_refuse() { echo "CANNOT ESTABLISH: $1 is unusable; no request was sent" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=sandbox-readback-10445 reason=token_shape" >&2; exit 3; }
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
  echo "CANNOT ESTABLISH: /hooks/deploy-status returned HTTP $HTTP_STATUS" >&2
  exit 3
fi
if ! printf '%s' "$BODY" | jq -e '.sandbox_canary' >/dev/null 2>&1; then
  echo "CANNOT ESTABLISH: deploy-status body missing .sandbox_canary (non-JSON or old host)" >&2
  exit 3
fi

# Output from the remote JSON is reduced to a safe alphabet before it is ever printed: the sweeper posts this script's
# stdout into a tracker comment, and a newline or `::` workflow command must not ride along.
VERDICT="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.verdict // "unknown"' | tr -cd 'A-Za-z0-9._-')"
TAG="$(printf '%s' "$BODY" | jq -r '.tag // ""' | tr -cd 'A-Za-z0-9._-')"
# `.tag`/`.exit_code`/`.component`/`.start_ts` are ONE shared deploy frame that EVERY component's deploy overwrites (ci-deploy.sh
# write_state): it is the last deploy ATTEMPT of any component, written with exit_code=-1 the moment a deploy starts and again on
# failure. The `sandbox_canary` ledger is a separate durable file that keeps the PREVIOUS deploy's verdict until a web-platform
# deploy's canary overwrites it. Two cases follow:
#   * the frame is a web-platform deploy: require it to have SUCCEEDED, the canary to have run since it started, and its release
#     tag to contain the fix PR's merge commit;
#   * the frame is another component's later deploy (it overwrote the web-platform frame): the tag says nothing about the web
#     image, so fall back on the durable ledger alone - the canary must have been checked after the PR merged.
# Either way exit 5 is only a notification to go verify by hand; the hosted Bash call is the real proof.
EXIT_CODE="$(printf '%s' "$BODY" | jq -r '.exit_code // "none"' | tr -cd '0-9-')"
COMPONENT="$(printf '%s' "$BODY" | jq -r '.component // ""' | tr -cd 'A-Za-z0-9._-')"
START_TS="$(printf '%s' "$BODY" | jq -r '.start_ts // ""' | tr -cd '0-9')"
CHECKED_AT="$(printf '%s' "$BODY" | jq -r '.sandbox_canary.checked_at // ""' | tr -cd '0-9')"
[[ "$CHECKED_AT" =~ ^[0-9]+$ ]] || { echo "NOT YET: deploy-status carries no numeric sandbox_canary.checked_at (no canary run recorded)" >&2; exit 2; }

# gh failing is CANNOT ESTABLISH (exit 3); an unmerged PR is a clean answer and NOT YET (exit 2).
PR_JSON="$(gh pr view "$FIX_PR" --repo "$REPO" --json mergeCommit,mergedAt --jq '[(.mergeCommit.oid // ""), (.mergedAt // "")] | @tsv' 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: gh pr view $FIX_PR failed" >&2; exit 3; }
MERGE_SHA="$(printf '%s' "$PR_JSON" | cut -f1 | tr -cd '0-9a-f')"
MERGED_AT="$(printf '%s' "$PR_JSON" | cut -f2 | tr -cd '0-9TZ:-')"
[[ "$MERGE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "NOT YET: PR #$FIX_PR has no merge commit yet (not merged)" >&2; exit 2; }
MERGED_EPOCH="$(date -u -d "$MERGED_AT" +%s 2>/dev/null)" || MERGED_EPOCH=""
[[ "$MERGED_EPOCH" =~ ^[0-9]+$ ]] || { echo "CANNOT ESTABLISH: PR #$FIX_PR mergedAt '$MERGED_AT' is not a timestamp" >&2; exit 3; }
(( CHECKED_AT >= MERGED_EPOCH )) || { echo "NOT YET: the sandbox canary verdict predates the fix PR's merge (checked_at=$CHECKED_AT < merged=$MERGED_EPOCH)" >&2; exit 2; }

DEPLOYED=likely
if [[ "$COMPONENT" == "web-platform" ]]; then
  [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "CANNOT ESTABLISH: deploy-status tag '$TAG' is not a release tag" >&2; exit 3; }
  [[ "$START_TS" =~ ^[0-9]+$ ]] || { echo "NOT YET: deploy-status carries no numeric start_ts" >&2; exit 2; }
  [[ "$EXIT_CODE" == "0" ]] || { echo "NOT YET: last deploy exit_code=$EXIT_CODE (in flight, failed or rolled back)" >&2; exit 2; }
  (( CHECKED_AT >= START_TS )) || { echo "NOT YET: the sandbox canary verdict predates the last deploy (checked_at=$CHECKED_AT < start_ts=$START_TS)" >&2; exit 2; }
  # `compare base...head` reports head's position relative to base: `behind` or `identical` means the merge commit is an
  # ancestor of the tag.
  CMP="$(gh api "repos/$REPO/compare/web-$TAG...$MERGE_SHA" --jq .status 2>/dev/null | tr -cd 'a-z')"
  case "$CMP" in
    behind|identical) : ;;
    ahead|diverged) echo "NOT YET: deployed tag $TAG does not contain the fix yet (compare=$CMP)" >&2; exit 2 ;;
    *) echo "CANNOT ESTABLISH: could not compare web-$TAG with the merge commit (gh api returned '$CMP')" >&2; exit 3 ;;
  esac
  DEPLOYED=yes
fi

case "$VERDICT" in
  pass)
    echo "ACTION REQUIRED: fix_deployed=$DEPLOYED tag=$TAG sandbox_canary=pass. A green canary is NOT proof that hosted Bash works: make a real hosted Bash call, record it in the PIR, open the docs-only PR that sets status: resolved, then close this tracker and remove its follow-through label."
    exit 5
    ;;
  sandbox_broken)
    echo "ACTION REQUIRED: REGRESSION fix_deployed=$DEPLOYED tag=$TAG sandbox_canary=fail" >&2
    exit 5
    ;;
  *)
    echo "NOT YET: sandbox_canary.verdict='$VERDICT' (no verdict yet)" >&2
    exit 2
    ;;
esac
