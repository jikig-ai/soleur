#!/usr/bin/env bash
# probe-github-app-mint.sh — prove the GITHUB_APP_* pair in env mints a live App JWT.
#
# The MU1 integration leg (scheduled-integration-suites.yml) mints a GitHub App
# installation token before cloning the fixture repo; a credential that is parseable
# but unregistered surfaces only as GitHub's opaque 401 "A JSON web token could not be
# decoded" minutes into vitest (#9995). This probe signs the same JWT shape (RS256,
# iss=GITHUB_APP_ID) and calls GET /app — a 200 means the pair mints; anything else
# fails fast with a named error BEFORE suite time is spent.
#
# Prints exactly one verdict line on success:
#   GITHUB_APP_MINT status=200 slug=<app-slug> fp=<sha256(env-form PEM)[:8]>
# and a ::error:: line on failure. The key and the JWT are NEVER printed: the PEM is
# written only to a mktemp file under umask 077 for the openssl calls, and the Bearer
# token reaches curl on its STDIN config via scripts/lib/bearer-curl.sh (ADR-280) —
# never on any argument list. `gh api` is deliberately not used: it sends
# `Authorization: token`, never `Bearer` (workflow-jwt-mint-silent-failure-traps.md).
#
# Env contract (the same names the mu1 test reads):
#   GITHUB_APP_ID          numeric app id
#   GITHUB_APP_PRIVATE_KEY PEM; the Doppler literal `\n` escape variant is expanded
# Run under `doppler run -p soleur -c dev_scheduled -- bash scripts/probe-github-app-mint.sh`.
# Exit 0 = mints; 1 = cannot mint (missing env, unparseable PEM, non-200, transport).
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GITHUB_APP_ID:+x}${GITHUB_APP_PRIVATE_KEY:+x}${DOPPLER_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

umask 077

fail() { printf '::error::%s\n' "$1" >&2; exit 1; }

[[ -n "${GITHUB_APP_ID:-}" ]] \
  || fail "GITHUB_APP_ID is not set; run under doppler run -p soleur -c dev_scheduled"
[[ "$GITHUB_APP_ID" =~ ^[0-9]+$ ]] \
  || fail "GITHUB_APP_ID is not numeric"
[[ -n "${GITHUB_APP_PRIVATE_KEY:-}" ]] \
  || fail "GITHUB_APP_PRIVATE_KEY is not set; run under doppler run -p soleur -c dev_scheduled"

command -v openssl >/dev/null 2>&1 || fail "openssl is required (JWT RS256 sign)"

# fp of the ENV-FORM value — the same field the mint code logs as pemFingerprint on
# failure (apps/web-platform/server/github-app.ts generateInstallationToken), so a CI
# 401 can be matched to a config entry without ever printing it.
FP="$(printf '%s' "$GITHUB_APP_PRIVATE_KEY" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-8)"

# PEM to a private tmp file for openssl. `\n` is the Doppler escape variant the
# runtime's getPrivateKey() also expands.
PEM_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
PEMF="$(mktemp "$PEM_DIR/ghapp-mint-pem.XXXXXXXX")" || fail "mktemp failed"
trap 'rm -f "${PEMF:-}"' EXIT
printf '%s' "$GITHUB_APP_PRIVATE_KEY" \
  | awk '{gsub(/\\n/, "\n"); printf "%s\n", $0}' > "$PEMF"

# Pre-flight the PEM before signing (#4384 mint chain): a corrupted value fails with a
# named error here instead of an opaque downstream 401.
if ! openssl rsa -check -in "$PEMF" -noout >/dev/null 2>&1 \
   && ! openssl pkey -check -in "$PEMF" -noout >/dev/null 2>&1; then
  fail "GITHUB_APP_PRIVATE_KEY is not a parseable RSA private key (fp=$FP)"
fi

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '=\n'; }

NOW="$(date +%s)"
HDR="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)"
PLD="$(printf '{"iat":%d,"exp":%d,"iss":%s}' "$((NOW - 60))" "$((NOW + 600))" "$GITHUB_APP_ID" | b64url)"
SIG="$(printf '%s' "$HDR.$PLD" | openssl dgst -sha256 -sign "$PEMF" 2>/dev/null | b64url)"
[[ -n "$SIG" ]] || fail "openssl could not sign with GITHUB_APP_PRIVATE_KEY (fp=$FP)"
JWT="$HDR.$PLD.$SIG"

# The Bearer token reaches curl on its stdin config channel only (ADR-280).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/bearer-curl.sh"
# shellcheck source=/dev/null
source "$LIB" || fail "could not load scripts/lib/bearer-curl.sh from this checkout"

RESP="$(bc_curl probe-github-app-mint \
  'Authorization:Bearer :JWT' -- \
  -s --max-time 15 -w '\n%{http_code}' \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  -H 'User-Agent: soleur-mint-probe' \
  "https://api.github.com/app")"
CURL_RC=$?
CODE="${RESP##*$'\n'}"
BODY="${RESP%$'\n'*}"

if [[ "$CURL_RC" -ne 0 || "$CODE" != 200 ]]; then
  fail "GITHUB_APP_* cannot mint a valid JWT for app $GITHUB_APP_ID (status=${CODE:-none} curl_rc=$CURL_RC fp=$FP)"
fi

# slug: jq when present, sed otherwise (operator macOS hosts may lack jq).
SLUG="$(printf '%s' "$BODY" | jq -er '.slug' 2>/dev/null \
  || printf '%s' "$BODY" | sed -n 's/.*"slug"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
SLUG="$(printf '%s' "$SLUG" | tr -cd 'a-z0-9-')"

printf 'GITHUB_APP_MINT status=200 slug=%s fp=%s\n' "${SLUG:-unknown}" "$FP"
