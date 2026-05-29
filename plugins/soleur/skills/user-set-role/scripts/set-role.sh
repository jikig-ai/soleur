#!/usr/bin/env bash
# Promote/demote a Soleur user's flag-targeting role.
#
# Contract: SKILL.md in the parent directory.
# Usage: bash set-role.sh <email|uuid> <prd|dev> [--dry-run]

set -euo pipefail

# Shared WORM audit-append helper (PostgREST RPC; no DB-CLI binary). See #4581 PR-1.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/audit-flag-flip.sh"

readonly FLAGSMITH_API="https://api.flagsmith.com/api/v1"
readonly FLAGSMITH_ENV_DEV_ID=90722
readonly FLAGSMITH_ENV_PRD_ID=90721

DRY_RUN=0
if [[ "${3:-}" == "--dry-run" ]]; then DRY_RUN=1; fi

IDENT="${1:-}"
TARGET="${2:-}"

usage() {
  echo "Usage: set-role.sh <email|uuid> <prd|dev> [--dry-run]" >&2
  exit 1
}

[[ -z "$IDENT" || -z "$TARGET" ]] && usage
[[ "$TARGET" != "prd" && "$TARGET" != "dev" ]] && { echo "role must be prd|dev (got: $TARGET)" >&2; usage; }

# UUID v4 regex (loose — Supabase auth uses standard v4).
UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

command -v curl >/dev/null || { echo "missing: curl" >&2; exit 2; }
command -v doppler >/dev/null || { echo "missing: doppler" >&2; exit 2; }
command -v python3 >/dev/null || { echo "missing: python3" >&2; exit 2; }

SUPA_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain 2>/dev/null || true)
SUPA_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain 2>/dev/null || true)
FLAGSMITH_TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain 2>/dev/null || true)
[[ -z "$SUPA_URL" || -z "$SUPA_KEY" ]] && { echo "missing Supabase secrets in soleur/prd" >&2; exit 2; }
[[ -z "$FLAGSMITH_TOKEN" ]] && { echo "missing FLAGSMITH_MANAGEMENT_API_KEY in soleur/cli_ops" >&2; exit 2; }

supa() {
  curl -sS -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY" -H "Content-Type: application/json" "$@"
}

fs_api() {
  curl -sS -H "Authorization: Api-Key $FLAGSMITH_TOKEN" -H "Content-Type: application/json" "$@"
}

# --- resolve user ----------------------------------------------------------
if [[ "$IDENT" =~ $UUID_RE ]]; then
  USER_ID="$IDENT"
  echo "→ Using UUID directly: $USER_ID"
else
  echo "→ Resolving email '$IDENT' to UUID via Supabase…"
  # URL-encode the email (`+` → `%2B` etc.) so PostgREST receives it intact.
  EMAIL_ENC=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$IDENT")
  ROWS=$(supa "${SUPA_URL}/rest/v1/users?email=eq.${EMAIL_ENC}&select=id,email,role")
  COUNT=$(echo "$ROWS" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d))')
  [[ "$COUNT" == "0" ]] && { echo "no user with email '$IDENT'" >&2; exit 3; }
  [[ "$COUNT" -gt "1" ]] && { echo "MULTIPLE users with email '$IDENT' — abort." >&2; echo "$ROWS" >&2; exit 3; }
  USER_ID=$(echo "$ROWS" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')
fi

# Read current role.
CUR_ROWS=$(supa "${SUPA_URL}/rest/v1/users?id=eq.${USER_ID}&select=id,email,role")
[[ "$(echo "$CUR_ROWS" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" == "0" ]] && { echo "no users.row for UUID $USER_ID" >&2; exit 3; }
CUR_ROLE=$(echo "$CUR_ROWS" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["role"])')
EMAIL=$(echo "$CUR_ROWS" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["email"])')

echo "  user: $EMAIL ($USER_ID)  current role: $CUR_ROLE  target: $TARGET"

if [[ "$CUR_ROLE" == "$TARGET" ]]; then
  echo "✓ No change — role is already '$TARGET'. Re-applying Flagsmith trait anyway for idempotency."
  if [[ $DRY_RUN -eq 1 ]]; then exit 0; fi
fi

# --- ack ------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run — exiting 0)"
  exit 0
fi

read -p "Proceed? Type 'yes': " ACK
[[ "$ACK" == "yes" ]] || { echo "aborted" >&2; exit 0; }

# --- audit append (WORM) — BEFORE the users.role mutation (append-before-flip) -------
# A failed audit must abort the script before any prod mutation; otherwise a role
# change could land in prd with no WORM accountability row (#4581 review FINDING 1).
ACTOR=$(doppler secrets get OPERATOR_EMAIL -p soleur -c cli_ops --plain 2>/dev/null | tr '[:upper:]' '[:lower:]')
[[ -z "$ACTOR" ]] && { echo "FATAL: OPERATOR_EMAIL not in Doppler soleur/cli_ops" >&2; exit 4; }

# Audit DB target = soleur/dev (preserves the historical dev-DB audit destination);
# distinct from the prd SUPA_URL/SUPA_KEY used for the users.role PATCH below.
# `|| true` normalizes a Doppler auth/network failure to the exit-4 contract (the
# [[ -z ]] guard) instead of letting `set -e` abort at the assignment with exit 1.
AUDIT_URL=$(doppler secrets get SUPABASE_URL -p soleur -c dev --plain 2>/dev/null) || true
AUDIT_SRK=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c dev --plain 2>/dev/null) || true
[[ -z "$AUDIT_URL" || -z "$AUDIT_SRK" ]] && { echo "FATAL: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not in Doppler soleur/dev" >&2; exit 4; }

# NOTE(#4581): AUDIT_ACTION tautology (both branches "on") is a pre-existing bug,
# out of scope for the transport swap; see #4593. Role assignment records "on".
AUDIT_ACTION=$([[ "$CUR_ROLE" == "$TARGET" ]] && echo "on" || echo "on")
AUDIT_ID=$(audit_flag_flip_rpc "$AUDIT_URL" "$AUDIT_SRK" "user-role" "prd" "user:$USER_ID" "$AUDIT_ACTION" null null "$ACTOR") || exit 4
echo "  audit_id=$AUDIT_ID"

# --- update Supabase (AFTER the audit row is committed) -------------------------------
if [[ "$CUR_ROLE" != "$TARGET" ]]; then
  echo "→ Updating Supabase users.role…"
  RESP=$(supa -X PATCH "${SUPA_URL}/rest/v1/users?id=eq.${USER_ID}" \
    -H 'Prefer: return=representation' \
    -d "{\"role\": \"$TARGET\"}")
  echo "$RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, list) or not d:
    print(json.dumps(d), file=sys.stderr); sys.exit(4)
print("  updated:", d[0]["email"], "role →", d[0]["role"])
' || exit 4
fi

# --- update Flagsmith identity trait (both envs) --------------------------
for ENV_PAIR in "dev:$FLAGSMITH_ENV_DEV_ID" "prd:$FLAGSMITH_ENV_PRD_ID"; do
  ENV_NAME=${ENV_PAIR%:*}
  ENV_ID=${ENV_PAIR#*:}
  echo "→ Writing Flagsmith trait role=$TARGET for identity $USER_ID in env=$ENV_NAME ($ENV_ID)…"
  fs_api -X POST "${FLAGSMITH_API}/environments/${ENV_ID}/identities/${USER_ID}/traits/" \
    -d "{\"trait_key\":\"role\",\"trait_value\":\"$TARGET\"}" \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and d.get("trait_key") == "role":
    print("  ✓ wrote:", d)
else:
    print("  ! response:", json.dumps(d), file=sys.stderr); sys.exit(5)
' || exit 5
done

echo
echo "✓ Done. The per-role flag cache TTL is 30s; user's resolved flags update within that window."
exit 0
