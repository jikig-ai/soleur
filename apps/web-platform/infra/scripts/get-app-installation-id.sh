#!/usr/bin/env bash
# Discover the installation ID for the soleur-ai GitHub App on the jikig-ai org.
#
# Reads GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY from env (operator supplies
# via `doppler run -p soleur -c prd -- bash <this>`), mints an RS256 JWT,
# calls /orgs/jikig-ai/installation, and prints the numeric installation ID
# to stdout. Output is non-sensitive — safe to log.
#
# Invoke:
#   doppler run -p soleur -c prd -- bash apps/web-platform/infra/scripts/get-app-installation-id.sh
#
# Then write to Doppler prd_terraform:
#   doppler secrets set GITHUB_APP_INSTALLATION_ID=<value> -p soleur -c prd_terraform
#
# Idempotent: re-running prints the same numeric ID.
#
# Trap-cleanup: the PEM is written to /dev/shm and unlinked on EXIT.
#
# Why this exists: PR #4144 — TF integrations/github provider now uses
# app_auth { id, installation_id, pem_file } instead of var.github_actions_token
# (a PAT requiring per-operator minting and rotation). See AGENTS.core.md
# hr-github-app-auth-not-pat.

set -euo pipefail

: "${GITHUB_APP_ID:?GITHUB_APP_ID env var required}"
: "${GITHUB_APP_PRIVATE_KEY:?GITHUB_APP_PRIVATE_KEY env var required (PEM contents)}"

# PEM tempfile lives in /dev/shm (tmpfs, never on disk) and is removed on EXIT.
PEM_FILE="$(mktemp -p /dev/shm get-app-installation-id.XXXXXX.pem)"
trap 'rm -f "$PEM_FILE"' EXIT INT TERM HUP

printf '%s\n' "$GITHUB_APP_PRIVATE_KEY" > "$PEM_FILE"

# base64url encode (no trailing newline, +/= -> -_, strip =).
# `base64 -w 0` is coreutils; `tr -d '=\n'` strips both padding and
# trailing newline. See knowledge-base/project/learnings/best-practices/
# 2026-05-05-workflow-jwt-mint-silent-failure-traps.md Trap 2.
b64url() { base64 -w 0 | tr '+/' '-_' | tr -d '=\n'; }

NOW="$(date +%s)"
IAT=$((NOW - 60))    # clock-skew margin
EXP=$((NOW + 540))   # 9 minutes; GitHub max is 10

HEADER='{"alg":"RS256","typ":"JWT"}'
PAYLOAD="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$IAT" "$EXP" "$GITHUB_APP_ID")"

HEADER_B64="$(printf '%s' "$HEADER" | b64url)"
PAYLOAD_B64="$(printf '%s' "$PAYLOAD" | b64url)"
UNSIGNED="${HEADER_B64}.${PAYLOAD_B64}"

SIG_B64="$(printf '%s' "$UNSIGNED" \
  | openssl dgst -sha256 -sign "$PEM_FILE" \
  | b64url)"

JWT="${UNSIGNED}.${SIG_B64}"

# Note: `gh api` sends `Authorization: token <value>` — App-JWT endpoints
# require `Bearer`. We use curl directly. Pass JWT via process substitution
# so it never lands in argv. See JWT-mint-silent-failure-traps.md Trap 1.
RESPONSE="$(mktemp -p /dev/shm get-app-installation-id-response.XXXXXX.json)"
trap 'rm -f "$PEM_FILE" "$RESPONSE"' EXIT INT TERM HUP

HTTP_CODE="$(curl --max-time 10 -sS -w '%{http_code}' \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --header @<(printf 'Authorization: Bearer %s' "$JWT") \
  https://api.github.com/orgs/jikig-ai/installation \
  -o "$RESPONSE")"

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "ERROR: GitHub API returned HTTP $HTTP_CODE" >&2
  cat "$RESPONSE" >&2
  exit 1
fi

jq -er '.id' < "$RESPONSE"
