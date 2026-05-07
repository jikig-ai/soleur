#!/usr/bin/env bash
# Seed three dev-only test users (R3 / feat-dev-signin-bypass) into the
# dev Supabase project for the multi-account QA panel rendered on /login.
#
# Usage (operator, separate terminal — never via the `! ` Claude Code
# shell prefix; passwords are read from Doppler env, not arguments):
#
#   doppler run -p soleur -c dev -- bash apps/web-platform/scripts/seed-dev-users.sh
#
# Idempotent: re-runs upsert each user's password to whatever is in
# DEV_USER_{1,2,3}_PASSWORD at the moment, so credential rotation is
# just `doppler secrets set DEV_USER_<N>_PASSWORD=...` then re-run.
#
# Triple-defense before any Supabase write:
#   1. DOPPLER_CONFIG === "dev"          (Doppler injects automatically)
#   2. JWT `ref` claim from SUPABASE_SERVICE_ROLE_KEY matches the host
#      prefix in NEXT_PUBLIC_SUPABASE_URL                (URL ↔ key bind)
#   3. NEXT_PUBLIC_SUPABASE_URL is the canonical 20-char shape
#      (per validate-url.ts CANONICAL_HOSTNAME)
#
# Modeled on seed-qa-user.sh; reuses the same admin-API call shape.

set -euo pipefail

# --- Pre-flight ----------------------------------------------------------

if [[ "${DOPPLER_CONFIG:-}" != "dev" ]]; then
  echo "::error::Refusing to run: DOPPLER_CONFIG=\"${DOPPLER_CONFIG:-<unset>}\" — must be \"dev\""
  echo "::error::Re-run via: doppler run -p soleur -c dev -- bash $0"
  exit 1
fi

: "${NEXT_PUBLIC_SUPABASE_URL:?NEXT_PUBLIC_SUPABASE_URL not set (use doppler run)}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY not set (use doppler run)}"

# Strip CR/LF defensively (mirrors verify-required-secrets.sh).
SRK="${SUPABASE_SERVICE_ROLE_KEY//$'\r'/}"
SRK="${SRK//$'\n'/}"
SB_URL="${NEXT_PUBLIC_SUPABASE_URL//$'\r'/}"
SB_URL="${SB_URL//$'\n'/}"

# Canonical-shape check on URL.
SUPABASE_URL_RE='^https://[a-z0-9]{20}\.supabase\.co$'
if [[ ! "$SB_URL" =~ $SUPABASE_URL_RE ]]; then
  echo "::error::NEXT_PUBLIC_SUPABASE_URL=\"$SB_URL\" is not the canonical 20-char ref shape"
  echo "::error::Custom-domain (api.soleur.ai) is allowed in prd but the dev Supabase"
  echo "::error::project's URL must point directly at the 20-char ref."
  exit 1
fi

# Decode JWT payload of SUPABASE_SERVICE_ROLE_KEY and assert ref matches URL host prefix.
if [[ "$(printf '%s' "$SRK" | tr -cd '.' | wc -c)" -ne 2 ]]; then
  echo "::error::SUPABASE_SERVICE_ROLE_KEY is not a 3-segment JWT"
  exit 1
fi
payload=$(printf '%s' "$SRK" | cut -d. -f2)
pad=$(( (4 - ${#payload} % 4) % 4 ))
if [[ $pad -gt 0 ]]; then
  padded="$payload$(printf '=%.0s' $(seq 1 $pad))"
else
  padded="$payload"
fi
json=$(printf '%s' "$padded" | tr '_-' '/+' | base64 -d 2>/dev/null) || {
  echo "::error::SUPABASE_SERVICE_ROLE_KEY payload is not valid base64url"
  exit 1
}
ref=$(printf '%s' "$json" | jq -r '.ref // ""')
role=$(printf '%s' "$json" | jq -r '.role // ""')

if [[ "$role" != "service_role" ]]; then
  echo "::error::SUPABASE_SERVICE_ROLE_KEY role=\"$role\", expected \"service_role\""
  exit 1
fi
url_host="${SB_URL#https://}"
url_ref="${url_host%%.*}"
if [[ "$ref" != "$url_ref" ]]; then
  echo "::error::JWT ref=\"$ref\" does not match URL canonical ref=\"$url_ref\""
  echo "::error::Refusing to seed — this would write to a different Supabase project"
  echo "::error::than the one NEXT_PUBLIC_SUPABASE_URL points at."
  exit 1
fi

echo "::notice::Pre-flight OK (DOPPLER_CONFIG=dev, ref=$ref matches URL)"

# --- Per-slot seeding ----------------------------------------------------

header_auth="Authorization: Bearer $SRK"
header_api="apikey: $SRK"
header_json="Content-Type: application/json"

# Fetch the current user list once and look up by email locally — cheaper
# and more reliable than the search query API for small lists.
USER_LIST=$(curl -sf "$SB_URL/auth/v1/admin/users?per_page=100" \
  -H "$header_auth" -H "$header_api")

for slot in 1 2 3; do
  pw_var="DEV_USER_${slot}_PASSWORD"
  password="${!pw_var:-}"
  if [[ -z "$password" ]]; then
    echo "::error::$pw_var is not set in Doppler dev — set it via:"
    echo "::error::  doppler secrets set $pw_var=\$(openssl rand -hex 16) -p soleur -c dev"
    exit 1
  fi
  email="dev-${slot}@example.com"

  user_id=$(printf '%s' "$USER_LIST" | jq -r --arg e "$email" \
    '(.users // []) | map(select(.email == $e)) | .[0].id // ""')

  if [[ -z "$user_id" ]]; then
    echo "Creating $email..."
    create_response=$(curl -sf "$SB_URL/auth/v1/admin/users" \
      -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
      -d "$(jq -nc --arg email "$email" --arg password "$password" \
        '{email: $email, password: $password, email_confirm: true}')")
    user_id=$(printf '%s' "$create_response" | jq -r '.id // ""')
    if [[ -z "$user_id" ]]; then
      echo "::error::Create failed for $email — response: $create_response"
      exit 1
    fi
    echo "  Created: $user_id"
  else
    echo "Refreshing password for $email ($user_id)..."
    curl -sf "$SB_URL/auth/v1/admin/users/$user_id" \
      -X PUT -H "$header_auth" -H "$header_api" -H "$header_json" \
      -d "$(jq -nc --arg password "$password" '{password: $password, email_confirm: true}')" \
      > /dev/null
    echo "  Updated."
  fi
done

echo ""
echo "::notice::All three dev users provisioned. Panel will appear on /login when"
echo "::notice::FLAG_DEV_SIGNIN=1 is set in Doppler dev and the dev server is running."
