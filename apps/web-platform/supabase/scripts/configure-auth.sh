#!/usr/bin/env bash
set -euo pipefail

# Refuse to run under xtrace (#7797): -x prints a command after expansion, so a credential would be
# printed the moment it is used. `${VAR:+x}` tests non-emptiness without expanding the value; every
# credential this file binds is covered. Tracing stays available with them unset.
case "$-" in
  *x*)
    if [ -n "${APPLE_CLIENT_SECRET:+x}${AZURE_CLIENT_SECRET:+x}${GITHUB_CLIENT_SECRET:+x}${GOOGLE_CLIENT_SECRET:+x}${RESEND_API_KEY:+x}${SUPABASE_ACCESS_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# Configure Supabase Auth: Site URL, redirect URLs, SMTP via Resend, and branded email template.
#
# Required environment variables:
#   SUPABASE_ACCESS_TOKEN -- from https://supabase.com/dashboard/account/tokens
#   PROJECT_REF           -- from project URL: supabase.com/dashboard/project/<ref>
#   RESEND_API_KEY        -- from Resend dashboard (starts with re_)

SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:?Missing SUPABASE_ACCESS_TOKEN}"
PROJECT_REF="${PROJECT_REF:?Missing PROJECT_REF}"
RESEND_API_KEY="${RESEND_API_KEY:?Missing RESEND_API_KEY}"

# Destination pin: the Management API bearer travels to .../projects/$PROJECT_REF/..., and
# PROJECT_REF is env-derived, so an override must not steer the account-level token at a project the
# operator did not intend. Refuse anything but the two live Supabase projects (prd and dev are
# distinct projects, hr-dev-prd-distinct-supabase-projects; this script is run against both).
case "$PROJECT_REF" in
  ifsccnjhymdmidffkzhl|mlwiodleouzwniehynfz) ;;
  *) echo "ERROR: refusing PROJECT_REF (expected the live prd or dev Supabase project ref)" >&2; exit 1 ;;
esac

# One wrapper owns the transport flags, the token-shape guard and the bearer header, so the
# account-level token travels on curl's stdin config channel and never on its argument list
# (/proc/<pid>/cmdline, ps, a traced parent). A newline in the token would inject a curl config
# directive and an empty one would send the request unauthenticated, so it is refused before curl
# runs; the value is never echoed. Supabase access tokens (sbp_ + hex) are inside the allowlist.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
if ! _bearer_ok "$SUPABASE_ACCESS_TOKEN"; then
  echo "ERROR: SUPABASE_ACCESS_TOKEN has an unexpected shape" >&2
  exit 1
fi
mgmt_curl() {
  _bearer_ok "${SUPABASE_ACCESS_TOKEN:-}" || { echo "mgmt_curl: SUPABASE_ACCESS_TOKEN unusable" >&2; return 1; }
  curl --disable --noproxy '*' "$@" --config - \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$SUPABASE_ACCESS_TOKEN")
}

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../templates/magic-link.html"
CONFIRMATION_TEMPLATE_FILE="$SCRIPT_DIR/../templates/confirmation.html"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: Email template not found at $TEMPLATE_FILE" >&2
  exit 1
fi

if [[ ! -f "$CONFIRMATION_TEMPLATE_FILE" ]]; then
  echo "ERROR: Email template not found at $CONFIRMATION_TEMPLATE_FILE" >&2
  exit 1
fi

MAGIC_LINK_TEMPLATE=$(cat "$TEMPLATE_FILE")
CONFIRMATION_TEMPLATE=$(cat "$CONFIRMATION_TEMPLATE_FILE")

echo "Configuring Supabase Auth for project $PROJECT_REF..."

RESPONSE=$(mgmt_curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X PATCH \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg template "$MAGIC_LINK_TEMPLATE" \
    --arg confirmation "$CONFIRMATION_TEMPLATE" \
    --arg smtp_pass "$RESEND_API_KEY" \
    '{
      "site_url": "https://app.soleur.ai",
      "uri_allow_list": "http://localhost:3000/**,https://app.soleur.ai/**",
      "external_email_enabled": true,
      "mailer_otp_length": 6,
      "mailer_otp_exp": 600,
      # Auth rate-limit ceilings. DEFENSE RELAXATION (per
      # 2026-05-05-defense-relaxation-must-name-new-ceiling): raised from the
      # over-aggressive values that locked legitimate users out of their own
      # product (the "login blocked easily" symptom). Measured prd actuals at
      # change time (Management API GET 2026-06-15):
      #   rate_limit_email_sent: 2  -> 100  (project-wide OTP email sends /hr)
      #   rate_limit_verify:      30 -> 150 (token verifications /hr, per-IP)
      # The old email_sent=2/hr meant the WHOLE project could send only two
      # sign-in codes per hour — a handful of users, or one user across a few
      # retry/multi-tab cycles, exhausted it and locked everyone out. The
      # ceiling these values no longer bound is spam-email cost (Resend
      # volume); 100/hr stays well within the current Resend tier. The
      # per-user 60s OTP send window is a SEPARATE knob (not set here) and is
      # intentionally left at default — the client cooldown already matches it
      # and relaxing it would re-open the invited-user double-send class
      # (#4638). NOTE: jq strips these "#" comment lines from the JSON body.
      "rate_limit_email_sent": 100,
      "rate_limit_verify": 150,
      "smtp_admin_email": "noreply@soleur.ai",
      "smtp_host": "smtp.resend.com",
      "smtp_port": "465",
      "smtp_user": "resend",
      "smtp_pass": $smtp_pass,
      "smtp_sender_name": "Soleur",
      "mailer_subjects_magic_link": "Your Soleur verification code",
      "mailer_templates_magic_link_content": $template,
      "mailer_subjects_confirmation": "Confirm your Soleur account",
      "mailer_templates_confirmation_content": $confirmation
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
  resp=$(mgmt_curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" -X PATCH \
    "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
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
