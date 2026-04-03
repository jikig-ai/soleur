#!/usr/bin/env bash
set -euo pipefail

# Configure Supabase Auth: Site URL, redirect URLs, SMTP via Resend, and branded email template.
#
# Required environment variables:
#   SUPABASE_ACCESS_TOKEN -- from https://supabase.com/dashboard/account/tokens
#   PROJECT_REF           -- from project URL: supabase.com/dashboard/project/<ref>
#   RESEND_API_KEY        -- from Resend dashboard (starts with re_)

SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:?Missing SUPABASE_ACCESS_TOKEN}"
PROJECT_REF="${PROJECT_REF:?Missing PROJECT_REF}"
RESEND_API_KEY="${RESEND_API_KEY:?Missing RESEND_API_KEY}"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../templates/magic-link.html"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: Email template not found at $TEMPLATE_FILE" >&2
  exit 1
fi

MAGIC_LINK_TEMPLATE=$(cat "$TEMPLATE_FILE")

echo "Configuring Supabase Auth for project $PROJECT_REF..."

RESPONSE=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X PATCH \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg template "$MAGIC_LINK_TEMPLATE" \
    --arg smtp_pass "$RESEND_API_KEY" \
    '{
      "site_url": "https://app.soleur.ai",
      "uri_allow_list": "http://localhost:3000/**,https://app.soleur.ai/**",
      "external_email_enabled": true,
      "mailer_otp_length": 6,
      "mailer_otp_exp": 600,
      "smtp_admin_email": "noreply@soleur.ai",
      "smtp_host": "smtp.resend.com",
      "smtp_port": "465",
      "smtp_user": "resend",
      "smtp_pass": $smtp_pass,
      "smtp_sender_name": "Soleur",
      "mailer_subjects_magic_link": "Your Soleur verification code",
      "mailer_templates_magic_link_content": $template
    }'
  )")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "Supabase auth config updated successfully (HTTP $HTTP_CODE)."
else
  echo "ERROR: Supabase API returned HTTP $HTTP_CODE" >&2
  echo "$BODY" >&2
  exit 1
fi

# --- OAuth Provider Configuration ---
#
# Optional environment variables (providers are enabled only when both
# client ID and secret are set):
#   GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
#   APPLE_CLIENT_ID / APPLE_CLIENT_SECRET
#   GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET
#   AZURE_CLIENT_ID / AZURE_CLIENT_SECRET  (Microsoft)

configure_provider() {
  local provider_name="$1"
  local client_id="$2"
  local client_secret="$3"
  local extra_json="${4:-}"

  echo "Enabling $provider_name OAuth provider..."

  local payload
  payload=$(jq -n \
    --arg prov "$provider_name" \
    --arg id "$client_id" \
    --arg secret "$client_secret" \
    --argjson extra "${extra_json:-{}}" \
    '{
      ("external_" + $prov + "_enabled"): true,
      ("external_" + $prov + "_client_id"): $id,
      ("external_" + $prov + "_secret"): $secret
    } + $extra'
  )

  local resp
  resp=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X PATCH \
    "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload")

  local code
  code=$(echo "$resp" | tail -1)
  local body
  body=$(echo "$resp" | sed '$d')

  if [[ "$code" -ge 200 && "$code" -lt 300 ]]; then
    echo "$provider_name OAuth enabled (HTTP $code)."
  else
    echo "WARNING: $provider_name OAuth config failed (HTTP $code)" >&2
    echo "$body" >&2
  fi
}

if [[ -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  configure_provider "google" "$GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_SECRET"
fi

if [[ -n "${APPLE_CLIENT_ID:-}" && -n "${APPLE_CLIENT_SECRET:-}" ]]; then
  configure_provider "apple" "$APPLE_CLIENT_ID" "$APPLE_CLIENT_SECRET"
fi

if [[ -n "${GITHUB_CLIENT_ID:-}" && -n "${GITHUB_CLIENT_SECRET:-}" ]]; then
  configure_provider "github" "$GITHUB_CLIENT_ID" "$GITHUB_CLIENT_SECRET"
fi

if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
  configure_provider "azure" "$AZURE_CLIENT_ID" "$AZURE_CLIENT_SECRET" \
    '{"external_azure_url": "https://login.microsoftonline.com/common"}'
fi

echo "Auth configuration complete."
