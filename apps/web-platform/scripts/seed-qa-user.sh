#!/usr/bin/env bash
# Seed a fully provisioned QA test user for local Playwright testing.
# Usage: doppler run -p soleur -c dev -- bash scripts/seed-qa-user.sh [--port PORT]
#
# Creates/updates qa-test@example.com with:
#   - Password auth (qa-test-local-2026)
#   - Accepted terms (current TC_VERSION)
#   - Ready workspace + ready repo status
#   - A dummy API key entry
#   - A conversation with sample messages
#
# Outputs the conversation URL ready for Playwright navigation.
set -euo pipefail

# Refuse to seed anything but the dev Supabase project. The env var names are
# identical in the prd Doppler config, so without this gate a stray `-c prd`
# would create a live prod account with a publicly committed password.
# (First gate of the seed-dev-users.sh pre-flight.)
if [[ "${DOPPLER_CONFIG:-}" != "dev" ]]; then
  echo "ERROR: Refusing to run: DOPPLER_CONFIG=\"${DOPPLER_CONFIG:-<unset>}\" — must be \"dev\"" >&2
  echo "Re-run via: doppler run -p soleur -c dev -- bash $0" >&2
  exit 1
fi

QA_EMAIL="qa-test@example.com"
QA_PASSWORD="qa-test-local-2026"
# TC_VERSION must match lib/legal/tc-version.ts
TC_VERSION="2.4.0"
# Must match the migration-053 backfill sentinel (also used by
# server/agent-runner.ts and server/cc-dispatcher.ts message writes).
TEMPLATE_ID="default_legacy"
PORT="${1:-3000}"
if [[ "${1:-}" == "--port" ]]; then PORT="${2:-3000}"; fi

: "${NEXT_PUBLIC_SUPABASE_URL:?Set NEXT_PUBLIC_SUPABASE_URL (use doppler run)}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Set SUPABASE_SERVICE_ROLE_KEY (use doppler run)}"
: "${NEXT_PUBLIC_SUPABASE_ANON_KEY:?Set NEXT_PUBLIC_SUPABASE_ANON_KEY (use doppler run)}"

SB_URL="$NEXT_PUBLIC_SUPABASE_URL"
SRK="$SUPABASE_SERVICE_ROLE_KEY"
ANON="$NEXT_PUBLIC_SUPABASE_ANON_KEY"

header_auth="Authorization: Bearer $SRK"
header_api="apikey: $SRK"
header_json="Content-Type: application/json"

echo "=== Seeding QA user: $QA_EMAIL ==="

# 1. Find or create the QA user
USER_ID=$(curl -sf "$SB_URL/auth/v1/admin/users" \
  -H "$header_auth" -H "$header_api" | \
  python3 -c "
import sys, json
users = json.load(sys.stdin).get('users', [])
match = [u for u in users if u.get('email') == '$QA_EMAIL']
print(match[0]['id'] if match else '')
")

if [[ -z "$USER_ID" ]]; then
  echo "Creating user..."
  USER_ID=$(curl -sf "$SB_URL/auth/v1/admin/users" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -d "{\"email\":\"$QA_EMAIL\",\"password\":\"$QA_PASSWORD\",\"email_confirm\":true}" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  echo "Created user: $USER_ID"
else
  echo "Found existing user: $USER_ID"
  # Ensure password is set
  curl -sf "$SB_URL/auth/v1/admin/users/$USER_ID" \
    -X PUT -H "$header_auth" -H "$header_api" -H "$header_json" \
    -d "{\"password\":\"$QA_PASSWORD\"}" > /dev/null
fi

# 2. Provision user row (tc_accepted, workspace, repo)
echo "Provisioning user row..."
curl -sf "$SB_URL/rest/v1/users?id=eq.$USER_ID" \
  -X PATCH -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: return=minimal" \
  -d "{
    \"tc_accepted_version\": \"$TC_VERSION\",
    \"tc_accepted_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"workspace_status\": \"ready\",
    \"repo_status\": \"ready\",
    \"workspace_path\": \"/workspaces/$USER_ID\"
  }" > /dev/null
echo "  tc_accepted_version=$TC_VERSION, workspace=ready, repo=ready"

# 3. Ensure a dummy API key exists
EXISTING_KEY=$(curl -sf "$SB_URL/rest/v1/api_keys?user_id=eq.$USER_ID&provider=eq.anthropic&select=id" \
  -H "$header_auth" -H "$header_api" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")

if [[ -z "$EXISTING_KEY" ]]; then
  echo "Creating dummy API key..."
  # iv/auth_tag are NOT NULL (migration 004). The values are decrypt-poisoned
  # by design: GCM verification can never succeed on them, so the row drives
  # the "key on file" UI state but any real agent dispatch fails decryption.
  curl -sf "$SB_URL/rest/v1/api_keys" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -H "Prefer: return=minimal" \
    -d "{
      \"user_id\": \"$USER_ID\",
      \"provider\": \"anthropic\",
      \"encrypted_key\": \"qa-dummy-key-not-real\",
      \"iv\": \"cWEtZHVtbXktaXY=\",
      \"auth_tag\": \"cWEtZHVtbXktdGFn\",
      \"is_valid\": true
    }" > /dev/null
  echo "  Created dummy anthropic key"
else
  echo "  API key already exists: $EXISTING_KEY"
fi

# 4. Create a conversation with sample messages (idempotent: reuses the
# existing seeded conversation on re-runs instead of accumulating duplicates)
# The signup trigger provisions a personal workspace whose id equals the
# user id (migration 053 handle_new_user, ADR-038). conversations.workspace_id
# and messages.workspace_id are NOT NULL since migration 059;
# messages.template_id is NOT NULL since migration 053.
WORKSPACE_ID=$(curl -sf "$SB_URL/rest/v1/workspace_members?user_id=eq.$USER_ID&role=eq.owner&select=workspace_id&limit=1" \
  -H "$header_auth" -H "$header_api" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['workspace_id'] if d else '')")
if [[ -z "$WORKSPACE_ID" ]]; then
  echo "ERROR: no owned workspace membership for QA user $USER_ID" >&2
  exit 1
fi

# Mirror repo readiness to the workspace row: post-ADR-044 (migrations
# 079/080/081) the KB/sync read path gates on workspaces.repo_status, not
# users.repo_status — without this the seeded user is split-brain.
curl -sf "$SB_URL/rest/v1/workspaces?id=eq.$WORKSPACE_ID" \
  -X PATCH -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: return=minimal" \
  -d "{\"repo_status\": \"ready\"}" > /dev/null

CONV_ID=$(curl -sf "$SB_URL/rest/v1/conversations?user_id=eq.$USER_ID&select=id&order=created_at.asc&limit=1" \
  -H "$header_auth" -H "$header_api" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
if [[ -n "$CONV_ID" ]]; then
  echo "  Conversation already exists: $CONV_ID"
else
  echo "Creating conversation with sample messages..."
  CONV_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  curl -sf "$SB_URL/rest/v1/conversations" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -H "Prefer: return=minimal" \
    -d "{\"id\":\"$CONV_ID\",\"user_id\":\"$USER_ID\",\"workspace_id\":\"$WORKSPACE_ID\"}" > /dev/null

  curl -sf "$SB_URL/rest/v1/messages" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -H "Prefer: return=minimal" \
    -d "[
      {\"conversation_id\":\"$CONV_ID\",\"workspace_id\":\"$WORKSPACE_ID\",\"template_id\":\"$TEMPLATE_ID\",\"role\":\"user\",\"leader_id\":null,\"content\":\"What is the current state of our marketing strategy?\"},
      {\"conversation_id\":\"$CONV_ID\",\"workspace_id\":\"$WORKSPACE_ID\",\"template_id\":\"$TEMPLATE_ID\",\"role\":\"assistant\",\"content\":\"Based on my analysis of the knowledge base, here are the key findings:\\n\\n## Marketing Strategy Summary\\n\\n1. **Brand positioning** is well-defined\\n2. **SEO audit** identified 12 opportunities\\n3. **Content calendar** has 3 drafts pending\\n\\nI recommend prioritizing the programmatic SEO pages.\",\"leader_id\":\"cmo\"},
      {\"conversation_id\":\"$CONV_ID\",\"workspace_id\":\"$WORKSPACE_ID\",\"template_id\":\"$TEMPLATE_ID\",\"role\":\"user\",\"leader_id\":null,\"content\":\"Check our financial projections too.\"},
      {\"conversation_id\":\"$CONV_ID\",\"workspace_id\":\"$WORKSPACE_ID\",\"template_id\":\"$TEMPLATE_ID\",\"role\":\"assistant\",\"content\":\"Here are the Q2 2026 projections:\\n\\n| Metric | Projected | Actual |\\n|--------|-----------|--------|\\n| MRR | \$12,500 | \$11,800 |\\n| New customers | 15 | 12 |\\n\\nThe pipeline has 8 qualified leads.\",\"leader_id\":\"cfo\"}
    ]" > /dev/null

  echo "  Created conversation: $CONV_ID"
fi

# 5. Sign in and get session token for Playwright cookie injection
echo ""
echo "=== QA User Ready ==="
echo "Email:    $QA_EMAIL"
echo "Password: $QA_PASSWORD"
echo "User ID:  $USER_ID"
echo ""
echo "Chat URL: http://localhost:$PORT/dashboard/chat/$CONV_ID"
echo ""

# Output session cookie value for Playwright
SESSION=$(curl -sf "$SB_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "$header_json" \
  -d "{\"email\":\"$QA_EMAIL\",\"password\":\"$QA_PASSWORD\"}")

echo "Session cookie (set as 'sb-*-auth-token'):"
rm -f /tmp/qa-session.json
(umask 077; echo "$SESSION" > /tmp/qa-session.json)
echo "  Written to /tmp/qa-session.json"
echo ""
echo "Playwright cookie injection:"
echo "  await context.addCookies([{"
echo "    name: 'sb-$(echo "$SB_URL" | sed 's|https://||' | sed 's|\.supabase\.co||')-auth-token',"
echo "    value: <contents of /tmp/qa-session.json>,"
echo "    domain: 'localhost', path: '/', sameSite: 'Lax'"
echo "  }]);"
