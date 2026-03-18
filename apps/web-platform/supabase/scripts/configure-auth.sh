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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../templates/magic-link.html"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: Email template not found at $TEMPLATE_FILE" >&2
  exit 1
fi

MAGIC_LINK_TEMPLATE=$(cat "$TEMPLATE_FILE")

echo "Configuring Supabase Auth for project $PROJECT_REF..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH \
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
      "smtp_admin_email": "noreply@soleur.ai",
      "smtp_host": "smtp.resend.com",
      "smtp_port": "465",
      "smtp_user": "resend",
      "smtp_pass": $smtp_pass,
      "smtp_sender_name": "Soleur",
      "mailer_subjects_magic_link": "Sign in to Soleur",
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
