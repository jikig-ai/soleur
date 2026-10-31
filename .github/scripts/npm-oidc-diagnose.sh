#!/usr/bin/env bash
# Failure-only diagnostic for the npm OIDC trusted-publishing binding.
#
# WHY. npm swallows every OIDC exchange failure at verbose log level and then
# dies ENEEDAUTH (or E404), so a missing trusted-publisher entry is invisible at
# the default loglevel. This script replays the exact exchange `npm publish`
# makes and prints ONE classified verdict plus the values the npm-side entry must
# carry. Runbook: knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md
#
# Contract: always exits 0 (it runs after a failure and must not mask or add
# one); prints exactly one NPM_OIDC_VERDICT= line; never prints a bearer.
#   id-token-missing                         runner gave no id-token request env
#   id-token-fetch-failed                    the Actions id-token could not be obtained or
#                                            did not have a usable shape
#   exchange-ok                              exchange accepted; the failure is elsewhere
#   trusted-publisher-missing-or-mismatched  401/403/404 from the exchange
#   registry-error                           any other status, or no answer, or this script
#                                            could not run its check (no jq, bad registry)
# The workflow itself prints `NPM_OIDC_VERDICT=not-exercised` on its already-published
# early exit; this script never emits that one. This script is exercised by
# plugins/soleur/test/npm-publish-oidc.test.sh (not .github/scripts/test/): it shares the
# workflow-wiring guard's suite on purpose.
#
# Both bearers travel ONLY on curl's stdin config channel, never argv. A 2xx
# exchange body is never read or printed: by then the registry has minted a
# short-lived publish credential. curl still writes that body to a temp file
# (mode 0700 directory), which the EXIT trap removes; a SIGKILL would leave it on
# the ephemeral runner.
set +x
unset BASH_XTRACEFD
set -uo pipefail

REGISTRY="${OIDC_DIAG_REGISTRY:-https://registry.npmjs.org}"
PACKAGE="${OIDC_DIAG_PACKAGE:-@soleur/opencode}"
# The values the npm-side trusted-publisher entry must carry, derived from the run
# itself so a rename or transfer cannot leave this guidance printing stale values.
REPO="${GITHUB_REPOSITORY:-jikig-ai/soleur}"
WORKFLOW="${GITHUB_WORKFLOW_REF:-}"; WORKFLOW="${WORKFLOW%%@*}"; WORKFLOW="${WORKFLOW##*/}"
case "$WORKFLOW" in *.yml|*.yaml) ;; *) WORKFLOW="npm-publish.yml" ;; esac
RUNBOOK="knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md"
TOKPAT='^[A-Za-z0-9._~+/=-]+$'

# Every printed value goes through say(): a `key=` prefix (so no registry-controlled
# byte can start a line with `::`); CR/LF/TAB become spaces, other C0 controls and
# DEL are deleted, U+2028/U+2029 and C1 controls become spaces; 200 bytes.
clean() { printf '%s' "$1" | LC_ALL=C tr '\r\n\t' '   ' | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed 's/\xe2\x80[\xa8\xa9]/ /g' | LC_ALL=C sed 's/\xc2[\x80-\x9f]/ /g' | LC_ALL=C cut -c1-200; }
say() { printf '%s=%s\n' "$1" "$(clean "$2")"; }
verdict() { printf 'NPM_OIDC_VERDICT=%s\n' "$1"; }
annotate() { printf '::error title=npm trusted publisher::%s\n' "$1"; }
RUNBOOK_NOTE="Runbook: $RUNBOOK"

if ! [[ "$REGISTRY" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  verdict registry-error
  say detail "OIDC_DIAG_REGISTRY must be https://<host>[:port]; nothing was sent"
  annotate "The registry override is not an https host; nothing was sent. $RUNBOOK_NOTE"
  exit 0
fi

if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  verdict id-token-missing
  say detail "ACTIONS_ID_TOKEN_REQUEST_URL/TOKEN not set: the job lacks id-token: write"
  annotate "The job has no OIDC id-token; check jobs.publish.permissions id-token: write."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  verdict registry-error
  say detail "jq not found on the runner; the id-token response cannot be parsed"
  annotate "The diagnostic could not run (no jq). $RUNBOOK_NOTE"
  exit 0
fi

if ! [[ "$ACTIONS_ID_TOKEN_REQUEST_URL" == https://* ]]; then
  verdict id-token-fetch-failed
  say detail "the id-token request URL is not https; the request token was not sent"
  annotate "The Actions id-token could not be fetched. $RUNBOOK_NOTE"
  exit 0
fi

tmp="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/npm-oidc-diag.XXXXXX")" || {
  verdict id-token-fetch-failed
  say detail "could not create a temp dir"
  annotate "The Actions id-token could not be fetched. $RUNBOOK_NOTE"
  exit 0
}
# Remove exactly the two files this script writes, then the (now empty) directory.
trap 'rm -f -- "$tmp/idtoken.json" "$tmp/exchange.json"; rmdir -- "$tmp"' EXIT

host="${REGISTRY#*://}"; host="${host%%/*}"

if ! [[ "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" =~ $TOKPAT ]]; then
  verdict id-token-fetch-failed
  say detail "the id-token request token has an unexpected shape; not sent"
  annotate "The Actions id-token could not be fetched. $RUNBOOK_NOTE"
  exit 0
fi

rc=0
code="$(printf 'header = "Authorization: Bearer %s"\n' "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" | curl --disable --noproxy '*' --proto '=https' -sS --connect-timeout 10 --max-time 20 -G -K - --data-urlencode "audience=npm:${host}" -o "$tmp/idtoken.json" -w '%{http_code}' "$ACTIONS_ID_TOKEN_REQUEST_URL" 2>/dev/null)" || rc=$?
[[ "$code" =~ ^[0-9]{3}$ ]] || code=000
idtok=""
if [[ "$rc" -eq 0 && "$code" == 2* ]]; then
  idtok="$(jq -r '.value // empty' "$tmp/idtoken.json" 2>/dev/null)" || idtok=""
fi
if [[ -z "$idtok" ]] || ! [[ "$idtok" =~ $TOKPAT ]]; then
  verdict id-token-fetch-failed
  say status "$code"
  annotate "The Actions id-token could not be fetched. $RUNBOOK_NOTE"
  exit 0
fi
printf '::add-mask::%s\n' "$idtok"

esc="${PACKAGE//\//%2f}"
xrc=0
xcode="$(printf 'header = "Authorization: Bearer %s"\n' "$idtok" | curl --disable --noproxy '*' --proto '=https' -sS --connect-timeout 10 --max-time 20 -X POST -K - -o "$tmp/exchange.json" -w '%{http_code}' "$REGISTRY/-/npm/v1/oidc/token/exchange/package/$esc" 2>/dev/null)" || xrc=$?
[[ "$xcode" =~ ^[0-9]{3}$ ]] || xcode=000

case "$xcode" in
  2??) outcome=exchange-ok ;;
  401|403|404) outcome=trusted-publisher-missing-or-mismatched ;;
  *) outcome=registry-error ;;
esac

verdict "$outcome"
say status "$xcode"
case "$outcome" in
  exchange-ok)
    say detail "the OIDC exchange works; the publish failure is elsewhere (audience, version conflict, provenance, registry); read the npm error above this step"
    annotate "The OIDC exchange succeeded, so the trusted-publisher entry exists; read the npm publish error above."
    ;;
  trusted-publisher-missing-or-mismatched)
    msg="$(jq -r 'if (.message|type)=="string" then .message else empty end' "$tmp/exchange.json" 2>/dev/null)" || msg=""
    # A registry that echoes a bearer back must not get it printed: the runner masks
    # the exact id-token value only, so a truncated fragment would pass unmasked.
    if [[ -n "$msg" ]] && { [[ "$msg" == *"${idtok:16:24}"* ]] || [[ "$msg" == *"$ACTIONS_ID_TOKEN_REQUEST_TOKEN"* ]]; }; then
      msg=""
    fi
    if [[ -n "$msg" ]]; then
      say message "$msg"
    else
      say body_bytes "$(wc -c < "$tmp/exchange.json" | tr -d ' ')"
    fi
    say detail "exchange rejected; most likely no matching trusted publisher for ${PACKAGE} (a bad bearer also yields 401)"
    say repository "$REPO"
    say workflow "$WORKFLOW"
    say environment "(none)"
    say fix "npm trust github ${PACKAGE} --file ${WORKFLOW} --repo ${REPO} --allow-publish"
    say runbook "$RUNBOOK"
    annotate "No matching npm trusted publisher; configure repository, workflow and environment as printed in the run log. $RUNBOOK_NOTE"
    ;;
  registry-error)
    say curl_rc "$xrc"
    say detail "the registry did not give a usable answer; not a trust verdict; retry the run"
    annotate "The npm registry returned an unclassified status; see the status line in the run log. $RUNBOOK_NOTE"
    ;;
esac
exit 0
