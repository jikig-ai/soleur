#!/usr/bin/env bash
# Seed the dedicated synthetic PROD principal for the live-verification harness
# (#5452, FR1/FR2/TR5). The harness (apps/web-platform/scripts/live-verify/run.ts)
# signs in as this user against the DEPLOYED app to catch the realtime/
# server-commit-timing bug class mock e2e structurally cannot (#5391/#5421/#5436).
#
# Usage (agent-run LOCALLY, ONE-TIME — NEVER wired into CI; keeps prod
# service-role out of GitHub Actions, security P0-1):
#
#   doppler run -p soleur -c prd -- bash apps/web-platform/scripts/seed-live-verify-user.sh
#
# Idempotent: re-runs upsert the password to LIVE_VERIFY_USER_PASSWORD (set by
# Terraform random_password → doppler_secret, infra/live-verify.tf) and reset the
# full middleware ladder to canonical state, so rotation is just
# `terraform apply -replace=random_password.live_verify_user` then re-run.
#
# Ladder (per CTO ruling 2026-06-17, ADR live-verify): the synthetic user must
# clear EVERY middleware gate the real rail sits behind, AND `createConversation`
# (server/ws-handler.ts) aborts if `workspaces.repo_url` is null — so this seeds:
#   - auth user (email_confirm:true) → handle_new_user trigger (mig 053, ADR-038)
#     auto-provisions a solo workspace whose id == user.id + owner membership
#   - public.users ladder: tc_accepted_version (= lib/legal/tc-version.ts),
#     workspace_status=ready, repo_status=ready, workspace_path
#   - workspaces row: repo_status=ready AND repo_url=<synthetic sentinel> (the
#     seed-qa-user.sh gap; getCurrentRepoUrl reads workspaces.repo_url, not
#     users.repo_url — server/current-repo-url.ts:58-62)
#   - user_session_state row: current_workspace_id=<solo workspace> +
#     current_organization_id (#5501). createConversation resolves
#     conversations.workspace_id via the fail-loud resolveUserWorkspaceBinding,
#     which THROWS on an absent binding (agent-session-registry.ts:316) — without
#     this row a chat send never persists a conversation and the harness emits
#     CANT-RUN:forURL. handle_new_user (mig 053) does not seed this row.
#   - a dummy (decrypt-poisoned) anthropic api_keys row (has-key gate)
#   - DELIBERATELY NO scope_grants row: with zero grants the agent's Send route
#     403s before write-action-send.ts, so the harness can never create a WORM
#     action_sends row (I-action-send-free, by construction).
#
# Triple-defense before any Supabase write (mirrors seed-dev-users.sh, but PRD):
#   1. DOPPLER_CONFIG === "prd"                          (Doppler injects)
#   2. SUPABASE_SERVICE_ROLE_KEY JWT role === service_role + ref derived from JWT
#   3. NEXT_PUBLIC_SUPABASE_URL is in PROD_ALLOWED_HOSTS (api.soleur.ai) OR the
#      canonical 20-char ref shape; on the canonical shape we cross-check the
#      JWT ref against the URL host (validate-url.ts / validate-anon-key.ts
#      custom-domain handling: trust the JWT ref when the host is the custom
#      domain, since it carries no 20-char label).
#
# Secret discipline (AC8): no `set -x`; the password is only ever interpolated
# into a jq-built request body passed straight to curl -d — never echoed, never
# logged. No response body that could carry a token is printed.

set -euo pipefail

case "$-" in
  *x*)
    if [ -n "${LIVE_VERIFY_USER_PASSWORD:+x}${NEXT_PUBLIC_SUPABASE_ANON_KEY:+x}${SUPABASE_SERVICE_ROLE_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# --- Pre-flight ----------------------------------------------------------

if [[ "${DOPPLER_CONFIG:-}" != "prd" ]]; then
  echo "::error::Refusing to run: DOPPLER_CONFIG=\"${DOPPLER_CONFIG:-<unset>}\" — must be \"prd\""
  echo "::error::Re-run via: doppler run -p soleur -c prd -- bash $0"
  exit 1
fi

: "${NEXT_PUBLIC_SUPABASE_URL:?NEXT_PUBLIC_SUPABASE_URL not set (use doppler run)}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY not set (use doppler run)}"
: "${NEXT_PUBLIC_SUPABASE_ANON_KEY:?NEXT_PUBLIC_SUPABASE_ANON_KEY not set (use doppler run)}"
: "${LIVE_VERIFY_USER_PASSWORD:?LIVE_VERIFY_USER_PASSWORD not set — run terraform apply for infra/live-verify.tf first}"

# Strip CR/LF defensively (mirrors verify-required-secrets.sh).
SRK="${SUPABASE_SERVICE_ROLE_KEY//$'\r'/}"
SRK="${SRK//$'\n'/}"
SB_URL="${NEXT_PUBLIC_SUPABASE_URL//$'\r'/}"
SB_URL="${SB_URL//$'\n'/}"
ANON="${NEXT_PUBLIC_SUPABASE_ANON_KEY//$'\r'/}"
ANON="${ANON//$'\n'/}"

# Allowed prod hosts (mirror lib/supabase/validate-url.ts PROD_ALLOWED_HOSTS).
CANONICAL_RE='^https://[a-z0-9]{20}\.supabase\.co$'
url_host="${SB_URL#https://}"
url_host="${url_host%%/*}"

is_custom_domain=0
if [[ "$url_host" == "api.soleur.ai" ]]; then
  is_custom_domain=1
elif [[ ! "$SB_URL" =~ $CANONICAL_RE ]]; then
  echo "::error::NEXT_PUBLIC_SUPABASE_URL=\"$SB_URL\" is neither the prod custom domain"
  echo "::error::(api.soleur.ai) nor the canonical 20-char ref shape — refusing to seed."
  exit 1
fi

# Decode the service-role JWT payload and assert role + derive ref.
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
if [[ -z "$ref" ]]; then
  echo "::error::SUPABASE_SERVICE_ROLE_KEY carries no ref claim — cannot bind project"
  exit 1
fi

# On the canonical 20-char URL, the host first-label IS the ref — cross-check.
# On the custom domain (api.soleur.ai) the host carries no 20-char label, so we
# trust the JWT ref as the source of truth (mirrors validate-anon-key.ts).
if [[ "$is_custom_domain" -eq 0 ]]; then
  url_ref="${url_host%%.*}"
  if [[ "$ref" != "$url_ref" ]]; then
    echo "::error::JWT ref=\"$ref\" does not match URL canonical ref=\"$url_ref\""
    echo "::error::Refusing to seed — this would write to a different Supabase project."
    exit 1
  fi
fi

echo "::notice::Pre-flight OK (DOPPLER_CONFIG=prd, service_role, ref=$ref, host=$url_host)"

# --- Seed ----------------------------------------------------------------

header_auth="Authorization: Bearer $SRK"
header_api="apikey: $SRK"
header_json="Content-Type: application/json"

# DERIVED from lib/legal/tc-version.ts, never restated. A hand-kept literal
# with a "keep this in sync" comment is the drift shape this repo documents
# repeatedly, and it drifted here: the principal sat at 2.3.0 against a gate
# requiring 2.5.1, so `live-verify` redirected to /accept-terms and timed out
# on a page that could never contain the composer (#7969). The literal was
# CORRECT at the time — what broke was that nothing re-derived it after the
# bump. Extraction failure is fatal: a silently-empty version would PATCH the
# gate column to "" and re-break the harness in the same way.
_seed_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TC_SRC="$_seed_dir/../lib/legal/tc-version.ts"
[[ -f "$TC_SRC" ]] || { echo "::error::tc-version.ts not found at $TC_SRC"; exit 1; }
TC_VERSION="$(sed -n 's/^export const TC_VERSION = "\([^"]*\)";$/\1/p' "$TC_SRC")"
TC_DOCUMENT_SHA="$(sed -n 's/^  "\([0-9a-f]\{64\}\)";$/\1/p' "$TC_SRC" | head -1)"
[[ "$TC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "::error::derived TC_VERSION '\''$TC_VERSION'\'' is not a semver — the extraction is broken"; exit 1; }
[[ "$TC_DOCUMENT_SHA" =~ ^[0-9a-f]{64}$ ]] \
  || { echo "::error::derived TC_DOCUMENT_SHA is not a sha256 — the extraction is broken"; exit 1; }

EMAIL="live-verify@soleur.ai"
# Synthetic, non-resolvable sentinel repo URL. Never cloned/fetched — the app
# only stores the string into conversations.repo_url for Command Center scoping
# (CTO ruling Q3). A real repo would add a GitHub dependency + leak surface for
# zero benefit.
SENTINEL_REPO_URL="https://github.com/soleur-synthetic/verify-harness-sentinel"

find_user_by_email() {
  local email="$1"
  curl --disable --noproxy '*' -sf "$SB_URL/auth/v1/admin/users?email=$(jq -rn --arg v "$email" '$v|@uri')&per_page=1" \
    -H "$header_auth" -H "$header_api" \
    | jq -r --arg e "$email" '(.users // []) | map(select(.email == $e)) | .[0].id // ""'
}

user_id=$(find_user_by_email "$EMAIL")

if [[ -z "$user_id" ]]; then
  echo "Creating $EMAIL..."
  create_response=$(curl --disable --noproxy '*' -sf "$SB_URL/auth/v1/admin/users" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -d "$(jq -nc --arg email "$EMAIL" --arg password "$LIVE_VERIFY_USER_PASSWORD" \
      '{email: $email, password: $password, email_confirm: true}')")
  user_id=$(printf '%s' "$create_response" | jq -r '.id // ""')
  if [[ -z "$user_id" ]]; then
    # Do NOT echo create_response — it can carry tokens/identity payloads.
    echo "::error::Create failed for $EMAIL (admin API returned no id)"
    exit 1
  fi
  echo "  Created."
else
  echo "Refreshing password for $EMAIL..."
  curl --disable --noproxy '*' -sf "$SB_URL/auth/v1/admin/users/$user_id" \
    -X PUT -H "$header_auth" -H "$header_api" -H "$header_json" \
    -d "$(jq -nc --arg password "$LIVE_VERIFY_USER_PASSWORD" \
      '{password: $password, email_confirm: true}')" \
    > /dev/null
  echo "  Updated."
fi

# public.users ladder — clears /setup-key + workspace middleware gates.
# NOTE: tc_accepted_version is deliberately NOT set here. Consent goes through
# public.accept_terms below, the same RPC /api/accept-terms calls, because that
# is what also writes the public.tc_acceptances ledger row. PATCHing the column
# directly records consent with no audit row — measured in prod on the synthetic
# principal: tc_accepted_version set since 2026-06-17, ledger EMPTY (#7969).
echo "  Provisioning public.users row..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/users?id=eq.$user_id" \
  -X PATCH -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: return=minimal" \
  -d "$(jq -nc \
    --arg wp "/workspaces/$user_id" \
    '{workspace_status: "ready", repo_status: "ready", workspace_path: $wp}')" \
  > /dev/null

# Consent via the RPC the application uses. Idempotent in SQL: the users UPDATE
# is a no-op when the version already matches, and the ledger INSERT is
# ON CONFLICT (user_id, version) DO NOTHING.
echo "  Recording T&C acceptance (v$TC_VERSION) via public.accept_terms..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/rpc/accept_terms" \
  -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
  -d "$(jq -nc --arg uid "$user_id" --arg v "$TC_VERSION" --arg sha "$TC_DOCUMENT_SHA" \
    '{p_user_id: $uid, p_version: $v, p_doc_sha: $sha}')" \
  > /dev/null

# Resolve the solo workspace (handle_new_user trigger sets id == user.id; the
# owner membership row is the authoritative lookup).
workspace_id=$(curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/workspace_members?user_id=eq.$user_id&role=eq.owner&select=workspace_id&limit=1" \
  -H "$header_auth" -H "$header_api" \
  | jq -r '.[0].workspace_id // ""')
if [[ -z "$workspace_id" ]]; then
  echo "::error::No owned workspace membership for $user_id (handle_new_user trigger did not fire?)"
  exit 1
fi

# Mirror repo readiness AND set repo_url on the WORKSPACE row. getCurrentRepoUrl
# (server/current-repo-url.ts) reads workspaces.repo_url; without it,
# createConversation aborts "No connected repository" and the rail check can
# never materialize a conversation (CTO ruling Q3 — the seed-qa-user.sh gap).
echo "  Provisioning workspaces row (repo_url sentinel + repo_status=ready)..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/workspaces?id=eq.$workspace_id" \
  -X PATCH -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: return=minimal" \
  -d "$(jq -nc --arg url "$SENTINEL_REPO_URL" \
    '{repo_status: "ready", repo_url: $url}')" \
  > /dev/null

# Active-workspace binding (#5501). The deployed createConversation
# (server/ws-handler.ts:851) resolves conversations.workspace_id via the
# fail-loud resolveUserWorkspaceBinding (server/agent-session-registry.ts:288),
# which reads user_session_state.current_workspace_id and THROWS when no row
# exists (:316-326) — aborting the INSERT before any conversation persists, so
# the harness can never navigate and emits CANT-RUN:forURL. handle_new_user
# (mig 053) does NOT seed user_session_state, so we must bind it here.
#
# Write the row DIRECTLY via the table endpoint (NOT the set_current_workspace_id
# RPC at mig 079:256: it derives the writer from auth.uid() and RAISEs 28000
# under a service-role caller, mig 079:267). The body mirrors the RPC's own write
# verbatim (INSERT … ON CONFLICT (user_id) DO UPDATE, mig 079:293-298). Service
# role bypasses the SELECT-only RLS (mig 060:41-43); the table has no
# insert/update trigger and no table-level REVOKE FROM service_role.
echo "  Resolving organization_id for the active-workspace binding..."
org_id=$(curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/workspaces?id=eq.$workspace_id&select=organization_id" \
  -H "$header_auth" -H "$header_api" \
  | jq -r '.[0].organization_id // ""')
if [[ -z "$org_id" ]]; then
  echo "::error::No organization_id on workspace $workspace_id (handle_new_user trigger did not provision an org?)"
  exit 1
fi

# POST upsert (NOT a bare PATCH: no row exists yet, so ?user_id=eq.X matches 0
# rows and silently no-ops, leaving the binding absent and the harness broken).
echo "  Binding active workspace (user_session_state upsert)..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/user_session_state?on_conflict=user_id" \
  -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: resolution=merge-duplicates,return=minimal" \
  -d "$(jq -nc \
    --arg uid "$user_id" \
    --arg wid "$workspace_id" \
    --arg oid "$org_id" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{user_id: $uid, current_workspace_id: $wid, current_organization_id: $oid, updated_at: $ts}')" \
  > /dev/null

# Dummy decrypt-poisoned anthropic api_keys row (has-key gate). iv/auth_tag are
# NOT NULL (mig 004); GCM verification can never succeed on these, so any real
# dispatch fails decryption — the row only drives the "key on file" UI state.
existing_key=$(curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/api_keys?user_id=eq.$user_id&provider=eq.anthropic&select=id" \
  -H "$header_auth" -H "$header_api" \
  | jq -r '.[0].id // ""')
if [[ -z "$existing_key" ]]; then
  curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/api_keys" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -H "Prefer: return=minimal" \
    -d "$(jq -nc --arg uid "$user_id" \
      '{user_id: $uid, provider: "anthropic", encrypted_key: "live-verify-dummy-not-real", iv: "bGl2ZS12ZXJpZnktaXY=", auth_tag: "bGl2ZS12ZXJpZnktdGFn", is_valid: true}')" \
    > /dev/null
  echo "  Inserted dummy anthropic api_keys row."
else
  echo "  api_keys row already present."
fi

echo ""
echo "::notice::Synthetic prod principal provisioned (tc=$TC_VERSION, workspace=ready,"
echo "::notice::repo_url sentinel set, dummy anthropic key, NO scope_grants)."
echo "::notice::Set these Doppler prd values for the harness allowlist code-gate:"
echo "::notice::  doppler secrets set LIVE_VERIFY_EXPECTED_UID=$user_id -p soleur -c prd"
echo "::notice::  doppler secrets set LIVE_VERIFY_EXPECTED_REF=$ref -p soleur -c prd"
echo "LIVE_VERIFY_EXPECTED_UID=$user_id"
echo "LIVE_VERIFY_EXPECTED_REF=$ref"
