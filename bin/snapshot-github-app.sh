#!/usr/bin/env bash
# Snapshot the live GitHub App's identity + permissions + events via `GET /app`.
#
# Operator-only. CI uses the inline JWT-mint in
# `.github/workflows/scheduled-github-app-drift-guard.yml` (mirror at lines
# 127-158, shifted from 119-150 by the #4115 manifest-diff insertion)
# instead of shelling out to this script — keeping CI free of any
# external script reduces the runner's bash surface area. This script exists
# so future re-snapshots (when GitHub adds a permission, when permissions
# change) don't depend on operator memory of the JWT-mint dance.
#
# Inputs:
#   $APP_ID         (env) — positive integer, the App's database id.
#   /tmp/app.pem    (disk) — the App's RS256 private key, mode 0600.
#                            Caller fetches via:
#                              doppler secrets get GITHUB_APP_PRIVATE_KEY --plain \
#                                -p soleur -c prd | base64 -d > /tmp/app.pem
#                              chmod 600 /tmp/app.pem
#                            Caller shreds via `shred -u /tmp/app.pem` after.
#
# Output: pretty-printed JSON on stdout. Exit 0 on success; non-zero on any
# precondition / JWT-mint / curl / jq failure.
#
# Ref #4115.

set -euo pipefail

KEY_FILE="${KEY_FILE:-/tmp/app.pem}"

if [[ -z "${APP_ID:-}" ]]; then
  echo "snapshot-github-app: APP_ID env var is not set" >&2
  exit 2
fi
if ! [[ "$APP_ID" =~ ^[1-9][0-9]+$ ]]; then
  echo "snapshot-github-app: APP_ID is not a positive integer: $APP_ID" >&2
  exit 2
fi
if [[ ! -r "$KEY_FILE" ]]; then
  echo "snapshot-github-app: $KEY_FILE is missing or unreadable" >&2
  exit 2
fi
if ! openssl rsa -in "$KEY_FILE" -check -noout >/dev/null 2>&1; then
  echo "snapshot-github-app: $KEY_FILE is not a valid RSA PEM" >&2
  exit 2
fi

b64url() {
  base64 -w 0 | tr '+/' '-_' | tr -d '=\n'
}

mint_jwt() {
  # Mirror of scheduled-github-app-drift-guard.yml:123-150 mint_jwt.
  # 10-min cap is GitHub's hard ceiling; 540s forward + 60s backdate.
  set -o pipefail
  local backdate_s=60
  local lifetime_s=540
  local now header payload unsigned signature
  now=$(date +%s)
  header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
  payload=$(jq -nc \
    --argjson iss "$APP_ID" \
    --argjson iat "$((now - backdate_s))" \
    --argjson exp "$((now + lifetime_s))" \
    '{iss: $iss, iat: $iat, exp: $exp}' | b64url)
  unsigned="${header}.${payload}"
  signature=$(printf '%s' "$unsigned" | \
    openssl dgst -sha256 -sign "$KEY_FILE" -binary | b64url)
  printf '%s.%s\n' "$unsigned" "$signature"
}

JWT=$(mint_jwt)
if [[ -z "$JWT" ]]; then
  echo "snapshot-github-app: mint_jwt produced empty output" >&2
  exit 3
fi

# `gh api /app` sends `Authorization: token`; App-JWT requires `Bearer`.
# Use curl with --header @<(printf ...) so the JWT never appears in argv
# (mirror of drift-guard:224).
curl -sS --fail --max-time 15 \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --header @<(printf 'Authorization: Bearer %s' "$JWT") \
  https://api.github.com/app | jq .
