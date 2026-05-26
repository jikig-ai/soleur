#!/usr/bin/env bash
# Create a new runtime feature flag in Flagsmith + wire it into the codebase.
#
# Contract: SKILL.md in the parent directory.
# Usage: bash create.sh <kebab-name> [--description "..."] [--dev-on] [--prd-on] [--dry-run]

set -euo pipefail

readonly FLAGSMITH_PROJECT_ID=39082
readonly FLAGSMITH_ENV_DEV_ID=90722
readonly FLAGSMITH_ENV_PRD_ID=90721
readonly FLAGSMITH_API="https://api.flagsmith.com/api/v1"
readonly SERVER_TS="apps/web-platform/lib/feature-flags/server.ts"
readonly ENV_EXAMPLE="apps/web-platform/.env.example"

DRY_RUN=0
DEV_ON=0
PRD_ON=0
DESCRIPTION=""
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN=1; shift ;;
    --dev-on)      DEV_ON=1; shift ;;
    --prd-on)      PRD_ON=1; shift ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --*)           echo "unknown flag: $1" >&2; exit 1 ;;
    *)             NAME="$1"; shift ;;
  esac
done

[[ -z "$NAME" ]] && { echo "Usage: create.sh <kebab-name> [--description ...] [--dev-on] [--prd-on] [--dry-run]" >&2; exit 1; }
[[ ! "$NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && { echo "name must be lowercase kebab-case (got: $NAME)" >&2; exit 1; }

[[ ! -f "$SERVER_TS" ]] && { echo "missing $SERVER_TS (run from repo root)" >&2; exit 2; }
[[ ! -f "$ENV_EXAMPLE" ]] && { echo "missing $ENV_EXAMPLE" >&2; exit 2; }

ENV_VAR="FLAG_$(echo "$NAME" | tr 'a-z-' 'A-Z_')"

# Pre-check: flag name not already registered.
if grep -qE "[\"']${NAME}[\"']" "$SERVER_TS"; then
  echo "'$NAME' already appears in $SERVER_TS" >&2; exit 1
fi
if grep -qE "^${ENV_VAR}=" "$ENV_EXAMPLE"; then
  echo "$ENV_VAR already in $ENV_EXAMPLE" >&2; exit 1
fi

TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain 2>/dev/null || true)
[[ -z "$TOKEN" ]] && { echo "FLAGSMITH_MANAGEMENT_API_KEY not in Doppler soleur/cli_ops" >&2; exit 2; }

fs_api() { curl -sS -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" "$@"; }

# Pre-check: not already a feature in Flagsmith.
EXISTING=$(fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/?q=${NAME}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(f['name'] for f in d.get('results', []) if f['name'] == '$NAME'))")
if [[ -n "$EXISTING" ]]; then
  echo "feature '$NAME' already exists in Flagsmith — use flag-set-role to toggle" >&2; exit 1
fi

PRD_DOPPLER_VAL=$([[ $PRD_ON -eq 1 ]] && echo 1 || echo 0)

# --- propose ---------------------------------------------------------------
echo "→ Proposed mutations:"
echo "  1. Flagsmith: create feature '$NAME' (default_enabled=false)"
[[ $DEV_ON -eq 1 ]] && echo "     + segment override role-dev=ON in BOTH envs"
[[ $PRD_ON -eq 1 ]] && echo "     + segment override role-prd=ON in BOTH envs"
echo "  2. $SERVER_TS: add \"$NAME\": \"$ENV_VAR\" to RUNTIME_FLAGS"
echo "  3. $ENV_EXAMPLE: add $ENV_VAR=$PRD_DOPPLER_VAL"
echo "  4. Doppler: $ENV_VAR=$PRD_DOPPLER_VAL in soleur/dev AND soleur/prd"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run — exiting 0)"
  exit 0
fi

read -p "Proceed? Type 'yes': " ACK
[[ "$ACK" == "yes" ]] || { echo "aborted" >&2; exit 0; }

# --- audit append (WORM) ---------------------------------------------------
ACTOR=$(doppler secrets get OPERATOR_EMAIL -p soleur -c cli_ops --plain 2>/dev/null | tr '[:upper:]' '[:lower:]')
[[ -z "$ACTOR" ]] && { echo "FATAL: OPERATOR_EMAIL not in Doppler soleur/cli_ops" >&2; exit 4; }

DB_URL=$(doppler secrets get DATABASE_URL_POOLER -p soleur -c dev --plain 2>/dev/null)
[[ -z "$DB_URL" ]] && { echo "FATAL: DATABASE_URL_POOLER not in Doppler soleur/dev" >&2; exit 4; }

AUDIT_ID=$(psql "${DB_URL/6543/5432}" -tAc "SELECT public.audit_flag_flip('$NAME', 'dev', 'global', 'create', NULL, NULL, '$ACTOR');" 2>&1) \
  || { echo "FATAL: audit append failed: $AUDIT_ID" >&2; exit 4; }
echo "  audit_id=$AUDIT_ID"

# --- create feature --------------------------------------------------------
echo "→ Creating Flagsmith feature '$NAME'…"
RESP=$(fs_api -X POST "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/" \
  -d "$(python3 -c "
import json, sys
print(json.dumps({
    'name': '$NAME',
    'description': '''$DESCRIPTION''' or None,
    'default_enabled': False,
    'project': $FLAGSMITH_PROJECT_ID,
}))
")")
FEATURE_ID=$(echo "$RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))')
[[ -z "$FEATURE_ID" ]] && { echo "Flagsmith feature create failed: $RESP" >&2; exit 3; }
echo "  feature_id=$FEATURE_ID"

# --- segment overrides (if requested) --------------------------------------
apply_override() {
  local env_id="$1" segment_id="$2"
  local body
  body=$(printf '{"feature_states_to_create":[{"feature_segment":{"segment":%d},"enabled":true,"feature_state_value":{"type":"unicode","string_value":null,"integer_value":null,"boolean_value":null}}],"feature_states_to_update":[],"segment_ids_to_delete_overrides":[],"publish_immediately":true}' "$segment_id")
  fs_api -X POST "${FLAGSMITH_API}/environments/${env_id}/features/${FEATURE_ID}/versions/" -d "$body" >/dev/null
}

resolve_segment() {
  fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); [print(s['id']) for s in d.get('results', []) if s['name']=='$1']"
}

if [[ $DEV_ON -eq 1 ]]; then
  SEG=$(resolve_segment "role-dev")
  echo "→ Applying role-dev=ON in dev env…"; apply_override "$FLAGSMITH_ENV_DEV_ID" "$SEG"
  echo "→ Applying role-dev=ON in prd env…"; apply_override "$FLAGSMITH_ENV_PRD_ID" "$SEG"
fi
if [[ $PRD_ON -eq 1 ]]; then
  SEG=$(resolve_segment "role-prd")
  echo "→ Applying role-prd=ON in dev env…"; apply_override "$FLAGSMITH_ENV_DEV_ID" "$SEG"
  echo "→ Applying role-prd=ON in prd env…"; apply_override "$FLAGSMITH_ENV_PRD_ID" "$SEG"
fi

# --- edit server.ts ---------------------------------------------------------
echo "→ Editing $SERVER_TS…"
python3 <<PY || exit 4
import re, sys
p = "$SERVER_TS"
with open(p) as f: src = f.read()
new_line = '  "$NAME": "$ENV_VAR",\n'
m = re.search(r'(const RUNTIME_FLAGS = \{)([^}]*)(\}[ \t]*as const;)', src, re.DOTALL)
if not m:
    print('RUNTIME_FLAGS block not found in', p, file=sys.stderr); sys.exit(1)
body = m.group(2).rstrip()
if not body.endswith(','): body += ','
body += '\n' + new_line
src = src[:m.start(2)] + body + src[m.end(2):]
with open(p, 'w') as f: f.write(src)
print('  added entry to RUNTIME_FLAGS')
PY

# --- edit .env.example -----------------------------------------------------
echo "→ Editing $ENV_EXAMPLE…"
python3 <<PY || exit 4
p = "$ENV_EXAMPLE"
with open(p) as f: lines = f.readlines()
# Insert after the existing FLAG_KB_CHAT_SIDEBAR line.
out = []
inserted = False
for line in lines:
    out.append(line)
    if not inserted and line.startswith('FLAG_KB_CHAT_SIDEBAR='):
        out.append('$ENV_VAR=$PRD_DOPPLER_VAL\n')
        inserted = True
if not inserted:
    out.append('$ENV_VAR=$PRD_DOPPLER_VAL\n')
with open(p, 'w') as f: f.writelines(out)
print('  added $ENV_VAR=$PRD_DOPPLER_VAL')
PY

# --- mirror Doppler --------------------------------------------------------
echo "→ Doppler dev: $ENV_VAR=$PRD_DOPPLER_VAL…"
printf '%s' "$PRD_DOPPLER_VAL" | doppler secrets set "$ENV_VAR" -p soleur -c dev --silent || exit 5
echo "→ Doppler prd: $ENV_VAR=$PRD_DOPPLER_VAL…"
printf '%s' "$PRD_DOPPLER_VAL" | doppler secrets set "$ENV_VAR" -p soleur -c prd --silent || exit 5

echo
echo "✓ Done. Next: review the diff in $SERVER_TS + $ENV_EXAMPLE, then commit:"
echo "    git add $SERVER_TS $ENV_EXAMPLE && git commit -m 'feat(flags): add $NAME runtime flag'"
exit 0
