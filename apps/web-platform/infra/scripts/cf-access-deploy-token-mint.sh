#!/usr/bin/env bash
# cf-access-deploy-token-mint.sh: mint the deploy webhook's Cloudflare Access service token on the
# Soleur account and write the pair to every holder (#12931, ADR-329, ADR-241 D10).
# Runbook: knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md, Phase 3 step 1.
#
# Usage:
#   cf-access-deploy-token-mint.sh           dry run: prove every read and list the holders; mints nothing
#   cf-access-deploy-token-mint.sh --apply   mint, write, verify
#
# Credentials, read from Doppler by this script and never taken from argv:
#   soleur/prd_terraform CF_API_TOKEN_ACCESS_MINT (or its staged _NEXT; both present refuses). This is
#     the only Cloudflare token it reads: CF_API_TOKEN must never be exported where this runs (CTO F8).
#   soleur-infra-app/prd GITHUB_INFRA_APP_ID, GITHUB_INFRA_APP_PRIVATE_KEY: the infra GitHub App, for an
#     installation token limited to secrets:write on this repository (hr-github-app-auth-not-pat).
#
# HOLDERS, written in this order, each name on stdin:
#   1. soleur-infra-privileged/prd and soleur/prd_terraform, always;
#   2. every other config of apps/web-platform/infra/doppler-config-inventory.txt that holds the pair
#      (a config holding one of the two names refuses: that is a decision, not a write);
#   3. the GitHub repository secrets CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET.
#
# VERIFICATION. A Doppler write is read back and compared by sha256. A GitHub secret cannot be read
# back, so its proof is weaker and named as such: its updated_at must move (verify=updated_at). The
# value is proven only by a real deploy-status call through Access (runbook Phase 3 step 5).
#
# PARTIAL FAILURE. The client secret exists only in this process, so the first failed write stops the
# run and prints `verdict=partial token_id=<uuid> written=<...> failed=<...> not_attempted=<...>`.
# Recovery: delete that token in Cloudflare and re-run (this script refuses while a token of the name
# exists), which rewrites every holder.
#
# Prints holder names, the token UUID and verdicts; never a client id, a secret or a credential.
# Exit: 0 ok or dry run, 1 refused or partial, 2 usage, 78 xtrace.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
umask 077

readonly P="cf-access-deploy-token-mint"
readonly ACCOUNT_ID="66d4f93f7397f196544e9fe84c3557c2"
readonly TOKEN_NAME="github-actions-deploy"
readonly TOKEN_DURATION="8760h"
readonly CF_TOKENS_URL="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/service_tokens"
readonly GH_API="https://api.github.com"
readonly GH_REPO_FULL="jikig-ai/soleur"
readonly GH_REPO_NAME="soleur"
readonly GH_INSTALLATION_ID="166065653"
readonly GH_HOLDER="github:${GH_REPO_FULL}"
readonly PROJ="soleur"
readonly TFC="prd_terraform"
readonly PRIV_HOLDER="soleur-infra-privileged/prd"
readonly APP_PROJECT="soleur-infra-app"
readonly NAMES=(CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET)
readonly UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

MINT_TOKEN="" JWT="" INSTALL_TOKEN="" MINTED_ID="" MINTED_SECRET="" PEM_FILE=""
HTTP_RC=0 HTTP_CODE="" HTTP_BODY=""
HOLDERS=()
TOKEN_UUID=""

refuse() { # <reason> <message> [<extra fields>]
  printf '%s verdict=refuse reason=%s%s\n' "$P" "$1" "${3:+ $3}"
  printf '::error title=%s::%s\n' "$P" "$2"
  exit 1
}
csv() { local IFS=,; printf '%s' "$*"; }

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || refuse setup "cannot resolve the script directory"
# shellcheck source=/dev/null
source "$SELF/../../../../scripts/lib/bearer-curl.sh" || refuse setup "cannot load scripts/lib/bearer-curl.sh"

cleanup() {
  if [[ -n "$INSTALL_TOKEN" ]]; then
    bc_curl cf-access-deploy-token-mint 'Authorization:Bearer :INSTALL_TOKEN' -- -sS --max-time 10 -X DELETE \
      -H 'Accept: application/vnd.github+json' -o /dev/null "$GH_API/installation/token" >/dev/null || true
  fi
  if [[ -n "$PEM_FILE" ]]; then rm -f -- "$PEM_FILE"; fi
  MINT_TOKEN="" JWT="" INSTALL_TOKEN="" MINTED_ID="" MINTED_SECRET="" HTTP_BODY=""
}

# http <token-variable-name> <method> <url> [<json body>]: sets HTTP_RC, HTTP_CODE, HTTP_BODY.
http() {
  local out rc=0
  local -a data=()
  if [[ -n "${4:-}" ]]; then data=(-H 'Content-Type: application/json' -d "$4"); fi
  out="$(bc_curl cf-access-deploy-token-mint "Authorization:Bearer :$1" -- -sS --max-time 30 -X "$2" \
    -H 'Accept: application/json' ${data[@]+"${data[@]}"} -w '\n%{http_code}' "$3")" || rc=$?
  HTTP_RC="$rc"
  HTTP_CODE="${out##*$'\n'}"
  HTTP_BODY="${out%$'\n'*}"
}
http_ok() { [[ "$HTTP_RC" -eq 0 && "$HTTP_CODE" =~ ^20[01]$ ]]; }

# names_of <project> <config>: secret names, one per line. rc 1 on an unreadable or reshaped listing.
names_of() {
  local raw
  raw="$(doppler secrets --only-names --json -p "$1" -c "$2" 2>/dev/null)" || return 1
  jq -r 'if type == "object" and (keys | all(test("^[A-Z0-9_]+$"))) then keys[] else error("shape") end' <<<"$raw" 2>/dev/null
}
in_names() { grep -qxF -- "$1" <<<"$2"; }
# plain_get <project> <config> <name>: the value, byte-exact (drops the CLI's one trailing newline).
plain_get() {
  doppler secrets get "$3" -p "$1" -c "$2" --plain 2>/dev/null | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}'
}

discover_holders() {
  local inv="$SELF/../doppler-config-inventory.txt" cfgs c names n_held
  [[ -r "$inv" ]] || refuse holders-unreadable "the Doppler config inventory is not readable; nothing was minted."
  cfgs="$(grep -E '^[a-z0-9_]+$' "$inv" | LC_ALL=C sort -u)"
  [[ -n "$cfgs" ]] || refuse holders-unreadable "the Doppler config inventory lists no config; nothing was minted."
  names_of "${PRIV_HOLDER%%/*}" "${PRIV_HOLDER#*/}" >/dev/null \
    || refuse holders-unreadable "the names listing of ${PRIV_HOLDER} is unreadable; nothing was minted." "holder=${PRIV_HOLDER}"
  HOLDERS=("$PRIV_HOLDER" "$PROJ/$TFC")
  while IFS= read -r c; do
    names="$(names_of "$PROJ" "$c")" \
      || refuse holders-unreadable "the names listing of ${PROJ}/${c} is unreadable, so a holder there cannot be ruled out; nothing was minted." "holder=${PROJ}/${c}"
    [[ "$c" != "$TFC" ]] || { TF_NAMES="$names"; continue; }
    n_held=0
    in_names "${NAMES[0]}" "$names" && n_held=$((n_held + 1))
    in_names "${NAMES[1]}" "$names" && n_held=$((n_held + 1))
    case "$n_held" in
      0) ;;
      2) HOLDERS+=("$PROJ/$c") ;;
      *) refuse holder-half-pair "${PROJ}/${c} holds only one of the two names. Decide that config by hand first; nothing was minted." "holder=${PROJ}/${c}" ;;
    esac
  done <<<"$cfgs"
  [[ -n "${TF_NAMES:-}" ]] || refuse holders-unreadable "${PROJ}/${TFC} is not in the inventory or lists no names; nothing was minted."
}

read_mint_token() {
  local k=CF_API_TOKEN_ACCESS_MINT key
  if in_names "$k" "$TF_NAMES" && in_names "${k}_NEXT" "$TF_NAMES"; then
    refuse mint-token-ambiguous "both ${k} and ${k}_NEXT exist in ${PROJ}/${TFC}; delete the stale one. Nothing was minted."
  elif in_names "$k" "$TF_NAMES"; then key="$k"
  elif in_names "${k}_NEXT" "$TF_NAMES"; then key="${k}_NEXT"
  else refuse mint-token-missing "${k} is not in ${PROJ}/${TFC}; mint it first (runbook Phase 3 step 1). Nothing was minted."
  fi
  # shellcheck disable=SC2034 # read by NAME through bc_curl
  MINT_TOKEN="$(plain_get "$PROJ" "$TFC" "$key")" || MINT_TOKEN=""
  bc_ok_var MINT_TOKEN || refuse mint-token-missing "${key} is unreadable or malformed; nothing was minted."
}

check_no_existing_token() {
  local verdict
  http MINT_TOKEN GET "${CF_TOKENS_URL}?per_page=100"
  http_ok || refuse token-list-unreadable "the mint token could not list service tokens (http=${HTTP_CODE:0:3} e=${HTTP_RC}); nothing was minted."
  verdict="$(jq -r --arg n "$TOKEN_NAME" '
    if (.success != true) or ((.result | type) != "array") then "unreadable"
    elif (.result_info.total_count // (.result | length)) > (.result | length) then "truncated"
    else ([.result[] | select(.name == $n) | .id] | if length > 0 then "exists " + (.[0] | tostring) else "none" end) end' <<<"$HTTP_BODY" 2>/dev/null)" || verdict=unreadable
  case "$verdict" in
    none) ;;
    truncated) refuse token-list-truncated "the service-token list did not fit one page, so an existing ${TOKEN_NAME} cannot be ruled out; nothing was minted." ;;
    "exists "*)
      local id="${verdict#exists }"
      [[ "$id" =~ $UUID_RE ]] || id=unknown
      refuse token-exists "a service token named ${TOKEN_NAME} already exists. Its secret cannot be read again: delete it in Cloudflare to re-mint. Nothing was minted." "id=$id" ;;
    *) refuse token-list-unreadable "the service-token list is not readable; nothing was minted." ;;
  esac
}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '=\n'; }
build_app_jwt() {
  local app_id pem now header payload unsigned sig
  # The key file goes on the per-user tmpfs where there is one.
  if [[ "${XDG_RUNTIME_DIR:-}" == /* && -d "${XDG_RUNTIME_DIR:-}" ]]; then export TMPDIR="$XDG_RUNTIME_DIR"; fi
  app_id="$(plain_get "$APP_PROJECT" prd GITHUB_INFRA_APP_ID)" || app_id=""
  pem="$(plain_get "$APP_PROJECT" prd GITHUB_INFRA_APP_PRIVATE_KEY)" || pem=""
  [[ "$app_id" =~ ^[0-9]+$ && -n "$pem" ]] \
    || refuse github-app-unreadable "the infra GitHub App credentials are not readable from ${APP_PROJECT}/prd; nothing was minted."
  PEM_FILE="$(mktemp -t cf-mint-app.XXXXXXXX)" || refuse github-app-unreadable "cannot create a private key file; nothing was minted."
  [[ "$PEM_FILE" == /* ]] || refuse github-app-unreadable "the private key file path is not absolute (TMPDIR is relative); nothing was minted."
  printf '%s\n' "$pem" >"$PEM_FILE"
  pem=""
  openssl pkey -in "$PEM_FILE" -noout >/dev/null 2>&1 \
    || refuse github-app-unreadable "GITHUB_INFRA_APP_PRIVATE_KEY is not a valid key; nothing was minted."
  now="$(date +%s)"
  header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(jq -nc --argjson iss "$app_id" --argjson iat "$((now - 60))" --argjson exp "$((now + 540))" '{iss:$iss,iat:$iat,exp:$exp}' | b64url)"
  unsigned="${header}.${payload}"
  sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$PEM_FILE" -binary 2>/dev/null | b64url)"
  rm -f -- "$PEM_FILE"; PEM_FILE=""
  [[ -n "$sig" && -n "$payload" ]] || refuse github-app-unreadable "signing the App JWT failed; nothing was minted."
  # shellcheck disable=SC2034 # read by NAME through bc_curl
  JWT="${unsigned}.${sig}"
}

# Dry run only: reads the installation's grant; mints no token.
check_app_grant() {
  http JWT GET "$GH_API/app/installations/$GH_INSTALLATION_ID"
  http_ok && jq -e '.permissions.secrets == "write"' <<<"$HTTP_BODY" >/dev/null 2>&1 \
    || refuse github-app-unreadable "the infra GitHub App installation does not show secrets:write (http=${HTTP_CODE:0:3} e=${HTTP_RC})."
}

mint_install_token() {
  local body t
  body="$(jq -nc --arg r "$GH_REPO_NAME" '{repositories:[$r],permissions:{secrets:"write"}}')"
  http JWT POST "$GH_API/app/installations/$GH_INSTALLATION_ID/access_tokens" "$body"
  http_ok || refuse github-app-unreadable "the installation-token exchange failed (http=${HTTP_CODE:0:3} e=${HTTP_RC}); nothing was minted."
  t="$(jq -r '.token // empty' <<<"$HTTP_BODY" 2>/dev/null)"
  [[ -n "$t" ]] || refuse github-app-unreadable "the installation-token exchange returned no token; nothing was minted."
  INSTALL_TOKEN="$t"; t=""
  bc_ok_var INSTALL_TOKEN || refuse github-app-unreadable "the installation token is malformed; nothing was minted."
  jq -e --arg r "$GH_REPO_NAME" '(.permissions | del(.metadata)) == {secrets:"write"}
      and ((.permissions.metadata // "read") == "read")
      and .repository_selection == "selected" and ([.repositories[]?.name] == [$r])' <<<"$HTTP_BODY" >/dev/null 2>&1 \
    || refuse github-token-scope "the installation token is not limited to secrets:write on ${GH_REPO_NAME}; it was revoked and nothing was minted."
}

gh_updated_at() { # <name>: the secret's updatedAt, empty when absent; rc 1 on an unreadable list
  local raw
  raw="$(GH_TOKEN="$INSTALL_TOKEN" gh secret list --repo "$GH_REPO_FULL" --app actions --json name,updatedAt 2>/dev/null)" || return 1
  jq -er --arg n "$1" 'if type == "array" then ([.[] | select(.name == $n) | .updatedAt][0] // "") else error("shape") end' <<<"$raw" 2>/dev/null
}

mint_service_token() {
  local body
  body="$(jq -nc --arg n "$TOKEN_NAME" --arg d "$TOKEN_DURATION" '{name:$n,duration:$d}')"
  http MINT_TOKEN POST "$CF_TOKENS_URL" "$body"
  http_ok || refuse mint-failed "the service-token create failed (http=${HTTP_CODE:0:3} e=${HTTP_RC}). Check the dashboard for a ${TOKEN_NAME} token before re-running; nothing was written."
  TOKEN_UUID="$(jq -r 'if .success == true then (.result.id // "") else "" end | tostring' <<<"$HTTP_BODY" 2>/dev/null)" || TOKEN_UUID=""
  [[ "$TOKEN_UUID" =~ $UUID_RE ]] || {
    TOKEN_UUID=""
    refuse mint-response-invalid "the create answered without a usable token id. A token may exist: read the dashboard for ${TOKEN_NAME}. Nothing was written."
  }
  MINTED_ID="$(jq -r '.result.client_id // empty' <<<"$HTTP_BODY" 2>/dev/null)" || MINTED_ID=""
  MINTED_SECRET="$(jq -r '.result.client_secret // empty' <<<"$HTTP_BODY" 2>/dev/null)" || MINTED_SECRET=""
  local minted_name
  minted_name="$(jq -r '.result.name // empty' <<<"$HTTP_BODY" 2>/dev/null)" || minted_name=""
  HTTP_BODY=""
  if ! bc_ok_var MINTED_ID || ! bc_ok_var MINTED_SECRET || [[ "$minted_name" != "$TOKEN_NAME" ]]; then
    refuse mint-response-invalid "the create answered without a usable client id or secret. Delete token ${TOKEN_UUID} in Cloudflare and re-run. Nothing was written." "token_id=$TOKEN_UUID"
  fi
}

value_of() { case "$1" in CF_ACCESS_CLIENT_ID) printf '%s' "$MINTED_ID" ;; *) printf '%s' "$MINTED_SECRET" ;; esac; }

WRITE_CAUSE=""
write_doppler() { # <project/config> <name>
  local p="${1%%/*}" c="${1#*/}" want got
  WRITE_CAUSE=write-refused
  # 2>&1 too: Doppler prints the config table (#7133). --no-interactive: no confirmation prompt.
  value_of "$2" | doppler secrets set "$2" --silent --no-interactive -p "$p" -c "$c" >/dev/null 2>&1 || return 1
  want="$(value_of "$2" | sha256sum | cut -d' ' -f1)"
  got="$(set -o pipefail; plain_get "$p" "$c" "$2" | sha256sum | cut -d' ' -f1)" || { WRITE_CAUSE=readback-failed; return 1; }
  [[ "$want" == "$got" ]] || { WRITE_CAUSE=digest-mismatch; return 1; }
  printf '%s wrote holder=%s name=%s verify=digest\n' "$P" "$1" "$2"
}
write_github() { # <name>
  local before after
  WRITE_CAUSE=readback-failed
  before="$(gh_updated_at "$1")" || return 1
  WRITE_CAUSE=write-refused
  value_of "$1" | GH_TOKEN="$INSTALL_TOKEN" gh secret set "$1" --repo "$GH_REPO_FULL" --app actions >/dev/null 2>&1 || return 1
  WRITE_CAUSE=readback-failed
  after="$(gh_updated_at "$1")" || return 1
  [[ -n "$after" && "$after" != "$before" ]] || { WRITE_CAUSE=updated-at-unchanged; return 1; }
  printf '%s wrote holder=%s name=%s verify=updated_at\n' "$P" "$GH_HOLDER" "$1"
}

write_all() {
  local i t h n rc
  local -a targets=() written=()
  for h in "${HOLDERS[@]}"; do for n in "${NAMES[@]}"; do targets+=("$h:$n"); done; done
  for n in "${NAMES[@]}"; do targets+=("$GH_HOLDER:$n"); done
  for ((i = 0; i < ${#targets[@]}; i++)); do
    t="${targets[$i]}"; n="${t##*:}"; h="${t%:*}"
    rc=0
    if [[ "$h" == "$GH_HOLDER" ]]; then write_github "$n" || rc=1; else write_doppler "$h" "$n" || rc=1; fi
    if [[ "$rc" -ne 0 ]]; then
      printf '%s verdict=partial token_id=%s written=%s failed=%s not_attempted=%s cause=%s\n' "$P" "$TOKEN_UUID" \
        "$(csv ${written[@]+"${written[@]}"})" "$t" "$(csv "${targets[@]:i+1}")" "$WRITE_CAUSE"
      printf '::error title=%s::the write to %s failed (%s). The holders in written= hold the new pair. Recovery: delete token %s in Cloudflare and re-run, which rewrites every holder.\n' \
        "$P" "$t" "$WRITE_CAUSE" "$TOKEN_UUID"
      exit 1
    fi
    written+=("$t")
  done
  printf '%s verdict=ok token_id=%s written=%s\n' "$P" "$TOKEN_UUID" "${#written[@]}"
}

main() {
  local mode=dry h
  case "$#:${1:-}" in
    0:) ;;
    1:--apply) mode=apply ;;
    *) printf 'usage: %s [--apply]\n' "${0##*/}" >&2; exit 2 ;;
  esac
  local c
  for c in doppler gh jq openssl curl sha256sum; do
    command -v "$c" >/dev/null 2>&1 || refuse missing-tool "$c is required; nothing was minted."
  done
  trap cleanup EXIT
  discover_holders
  read_mint_token
  check_no_existing_token
  build_app_jwt
  if [[ "$mode" == dry ]]; then
    check_app_grant
    for h in "${HOLDERS[@]}" "$GH_HOLDER"; do printf '%s would-write holder=%s names=%s\n' "$P" "$h" "$(csv "${NAMES[@]}")"; done
    printf '%s verdict=dry-run holders=%s\n' "$P" "$((${#HOLDERS[@]} + 1))"
    return 0
  fi
  # Every credential and write path is proven BEFORE the mint: a token minted and then unwritable is
  # a secret that exists nowhere.
  mint_install_token
  gh_updated_at "${NAMES[0]}" >/dev/null \
    || refuse github-secrets-unreadable "the GitHub repository secret list is not readable with the installation token; nothing was minted."
  mint_service_token
  write_all
}

main "$@"
