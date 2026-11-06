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
case "$-" in
  *x*)
    if [ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
set +x
unset BASH_XTRACEFD  # belt and braces: `set +x` above already stops tracing
set -uo pipefail

# Destination and package are constants, not env-overridable: a settable destination is a way to
# send the bearer to another host, and nothing needs one (the tests stub curl on PATH).
REGISTRY="https://registry.npmjs.org"
PACKAGE="@soleur/opencode"
# The values the npm-side trusted-publisher entry must carry, derived from the run
# itself so a rename or transfer cannot leave this guidance printing stale values.
# Both are allowlisted before use: they are printed into a command an owner may paste.
# A value that fails its allowlist falls back to the default AND says so (a silent fallback would
# print a trust-entry value that does not match the workflow that ran).
REPO="${GITHUB_REPOSITORY:-}"; fell_back=""
[[ "$REPO" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { [[ -z "$REPO" ]] || fell_back="repository"; REPO="jikig-ai/soleur"; }
WORKFLOW="${GITHUB_WORKFLOW_REF:-}"; WORKFLOW="${WORKFLOW%%@*}"; WORKFLOW="${WORKFLOW##*/}"
[[ "$WORKFLOW" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}\.ya?ml$ ]] || { [[ -z "$WORKFLOW" ]] || fell_back="${fell_back:+$fell_back and }workflow"; WORKFLOW="npm-publish.yml"; }
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

if ! [[ "$ACTIONS_ID_TOKEN_REQUEST_URL" =~ ^https://[^[:space:][:cntrl:]]+$ ]]; then
  verdict id-token-fetch-failed
  say detail "the id-token request URL is not a plain https URL; the request token was not sent"
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
    # A registry that echoes a bearer back must not get it printed: the runner masks the
    # exact full value only, so a fragment would pass unmasked. Drop the message if any
    # 16-character window of either bearer appears in it once squeezed to token characters
    # (the squeeze rejoins a fragment split by separators, spaces, newlines or control bytes
    # and is a superset of the raw text, so no separate raw check is needed).
    # A copy squeezed to token characters also catches a bearer split by separators or newlines,
    # and any 24+ character token-shaped run in the RAW message is dropped (a re-encoded bearer, a
    # long URL): a real error sentence has none. The message is capped first so this stays cheap.
    if [[ -n "$msg" ]]; then
      msg="${msg:0:4096}"
      sq="$(printf '%s' "$msg" | LC_ALL=C tr -cd 'A-Za-z0-9._~+/=-')"
      bearers="$idtok $ACTIONS_ID_TOKEN_REQUEST_TOKEN"
      if [[ "$msg" =~ [A-Za-z0-9._~+/=-]{24} ]]; then
        msg=""
      else
        for ((i = 0; i + 16 <= ${#bearers}; i++)); do
          w="${bearers:i:16}"; [[ "$w" == *" "* ]] && continue
          if [[ "$sq" == *"$w"* ]]; then msg=""; break; fi
        done
      fi
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
    fixcmd="npm trust github ${PACKAGE} --file ${WORKFLOW} --repo ${REPO} --allow-publish"
    # say() caps at 200 bytes; a truncated command could name a different repo if pasted.
    if (( ${#fixcmd} <= 190 )); then say fix "$fixcmd"; else say detail "fix command omitted: it would exceed the 200-byte line cap; use the repository, workflow and environment values above"; fi
    [[ -z "$fell_back" ]] || say detail "the ${fell_back} value from the run (GITHUB_REPOSITORY / GITHUB_WORKFLOW_REF) was not usable; the value above is the default, not derived from this run"
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
