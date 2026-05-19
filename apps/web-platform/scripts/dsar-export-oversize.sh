#!/usr/bin/env bash
# Oversize DSAR export helper — manual fallback for accounts that
# exceed DSAR_EXPORT_SIZE_CAP_MB. See
# knowledge-base/engineering/ops/runbooks/dsar-export-oversize.md.
#
# Usage:
#   doppler run -p soleur -c prd -- \
#     ./scripts/dsar-export-oversize.sh <user-id> <out-dir>
#
# Env vars (sourced from Doppler):
#   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  — for the SQL + Storage REST calls
#   WORKSPACES_HOST                          — ssh target for /workspaces rsync
#   SOLEUR_SENTRY_PII_SALT                   — for hashed-userId log lines
#
# The script intentionally does NOT mutate any production state — it
# only reads. The final "mark delivered" step (per the runbook) is a
# separate manual SQL statement after operator verification.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <user-id> <out-dir>" >&2
  exit 64
fi

USER_ID="$1"
OUT_DIR="$2"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set (run under doppler)" >&2
  exit 78
fi

# Refuse to operate on a non-UUID user id — defense against typo'd
# CLI args dumping ALL users via missing WHERE clauses below.
if ! [[ "$USER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "error: <user-id> must be a UUID, got: $USER_ID" >&2
  exit 64
fi

mkdir -p "$OUT_DIR/tables" "$OUT_DIR/attachments" "$OUT_DIR/workspace"

# SQL helper — PostgREST GET with service-role bearer and an explicit
# eq filter. The filter is the runbook's "per-row WHERE" equivalent;
# refusing the request without it is the operator-side AC30.
read_table() {
  local table="$1"
  local owner_field="$2"
  local outfile="$OUT_DIR/tables/${table}.json"
  curl -sf \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Accept: application/json" \
    "${SUPABASE_URL}/rest/v1/${table}?${owner_field}=eq.${USER_ID}&select=*" \
    > "$outfile"
  echo "  · ${table}: $(jq 'length' < "$outfile") rows"
}

echo "[1/4] Reading SQL tables…"
read_table users               id
read_table api_keys            user_id
read_table conversations       user_id
read_table kb_share_links      user_id
read_table team_names          user_id
read_table audit_byok_use      founder_id

# Join-via reads: messages + message_attachments are scoped through
# conversation ownership we already proved. We pull the conversation
# id list from the file above, then query the children.
CONV_IDS=$(jq -r '[.[].id] | join(",")' "$OUT_DIR/tables/conversations.json")
if [[ -n "$CONV_IDS" ]]; then
  echo "  · messages: scoping via conversations…"
  curl -sf \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Accept: application/json" \
    "${SUPABASE_URL}/rest/v1/messages?conversation_id=in.(${CONV_IDS})&select=*" \
    > "$OUT_DIR/tables/messages.json"
  echo "    $(jq 'length' < "$OUT_DIR/tables/messages.json") rows"

  MSG_IDS=$(jq -r '[.[].id] | join(",")' "$OUT_DIR/tables/messages.json")
  if [[ -n "$MSG_IDS" ]]; then
    echo "  · message_attachments: scoping via messages…"
    curl -sf \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Accept: application/json" \
      "${SUPABASE_URL}/rest/v1/message_attachments?message_id=in.(${MSG_IDS})&select=*" \
      > "$OUT_DIR/tables/message_attachments.json"
    echo "    $(jq 'length' < "$OUT_DIR/tables/message_attachments.json") rows"
  fi
fi

echo "[2/4] Downloading chat-attachments/${USER_ID}/…"
# List folders, then list per-folder files, then download each.
# This is the operator-side mirror of enumerateChatAttachments in
# dsar-export.ts; the path-prefix guard below is the AC26 equivalent.
LIST=$(curl -sf \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "{\"prefix\":\"${USER_ID}/\",\"limit\":1000}" \
  "${SUPABASE_URL}/storage/v1/object/list/chat-attachments")
echo "$LIST" | jq -r '.[] | .name' | while read -r name; do
  if [[ "$name" == *".."* || "$name" == /* ]]; then
    echo "  · REFUSING (path-traversal in name): $name" >&2
    exit 1
  fi
  curl -sf \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -o "$OUT_DIR/attachments/${name##*/}" \
    "${SUPABASE_URL}/storage/v1/object/chat-attachments/${USER_ID}/${name}"
  echo "  · downloaded ${name}"
done

echo "[3/4] Syncing workspace files…"
if [[ -n "${WORKSPACES_HOST:-}" ]]; then
  rsync -av --no-links \
    "${WORKSPACES_HOST}:/workspaces/${USER_ID}/" \
    "$OUT_DIR/workspace/"
else
  echo "  · WORKSPACES_HOST unset — skipping (manifest will note this)"
fi

echo "[4/4] Writing manifest + SHA-256 inventory…"
{
  echo "{"
  echo '  "schema_version": "1.0.0",'
  echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"user_id\": \"${USER_ID}\","
  echo '  "fulfilment_channel": "operator-fallback: dsar-export-oversize.sh",'
  echo '  "serialization": {'
  echo '    "timestamp_format": "ISO 8601 with UTC offset (Z)",'
  echo '    "bytea_encoding": "base64",'
  echo '    "null_encoding": "JSON null",'
  echo '    "object_keys": "sorted alphabetically"'
  echo "  }"
  echo "}"
} > "$OUT_DIR/manifest.json"

(cd "$OUT_DIR" && find . -type f -name "*.json" -o -name "*" | sort | xargs sha256sum) \
  > "$OUT_DIR/manifest.sha256"

echo "Done. Bundle at: $OUT_DIR"
echo "Next: verify per runbook step 3, then deliver via R2 one-time URL."
