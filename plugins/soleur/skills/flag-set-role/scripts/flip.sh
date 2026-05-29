#!/usr/bin/env bash
# Flip a Flagsmith per-role segment override + mirror to Doppler on prd flips.
#
# Contract: SKILL.md in the parent directory. ADR-038 v2 §"Fallback semantics"
# documents the env-var mirror invariant this script enforces.
#
# Usage: bash flip.sh <flag> <prd|dev> <on|off> [--confirmed] [--org <orgId>] [--dry-run]
#
# Exit codes:
#   0 — success / dry-run clean
#   1 — fallback-fidelity rule violated
#   2 — prerequisite missing
#   3 — Flagsmith API error
#   4 — Doppler write failed (partial state — operator must reconcile)

set -euo pipefail

# Shared WORM audit-append helper (PostgREST RPC; no DB-CLI binary). See #4581 PR-1.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/audit-flag-flip.sh"

# --- constants (project-level, captured 2026-05-22) -------------------------
# Note: Flagsmith Admin API is inconsistent — some endpoints want the numeric
# env_id (e.g. /environments/{int_id}/features/{int_id}/versions/), others
# want the env api_key string (e.g. /environments/{api_key}/featurestates/).
# Both forms documented here so the helpers can pick the right one.
readonly FLAGSMITH_PROJECT_ID=39082
readonly FLAGSMITH_ENV_DEV_ID=90722
readonly FLAGSMITH_ENV_PRD_ID=90721
readonly FLAGSMITH_ENV_DEV_KEY="PRHE5c9eWXYuRDFFPtbFxj"
readonly FLAGSMITH_ENV_PRD_KEY="QMEpRRzFx8kpEcY7nZmhJd"
readonly FLAGSMITH_API="https://api.flagsmith.com/api/v1"

# Map known flag-name → Doppler env-var name. Keep in sync with
# apps/web-platform/lib/feature-flags/server.ts RUNTIME_FLAGS.
declare -A FLAG_ENV_VARS=(
  ["kb-chat-sidebar"]="FLAG_KB_CHAT_SIDEBAR"
  ["team-workspace-invite"]="FLAG_TEAM_WORKSPACE_INVITE"
  ["byok-delegations"]="FLAG_BYOK_DELEGATIONS"
)

# --- arg parsing ------------------------------------------------------------
DRY_RUN=0
CONFIRMED=0
TARGET_TYPE="role"
TARGET_ORG=""
FLAG=""
ROLE=""
VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN=1; shift ;;
    --confirmed)   CONFIRMED=1; shift ;;
    --target)      TARGET_TYPE="$2"; shift 2 ;;
    --org)         TARGET_ORG="$2"; shift 2 ;;
    --*)           echo "unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$FLAG" ]]; then FLAG="$1"
      elif [[ -z "$ROLE" ]]; then ROLE="$1"
      elif [[ -z "$VALUE" ]]; then VALUE="$1"
      fi
      shift ;;
  esac
done

usage() {
  echo "Usage: flip.sh <flag> <prd|dev> <on|off> [--confirmed] [--org <orgId>] [--dry-run]" >&2
  echo "Known flags: ${!FLAG_ENV_VARS[*]}" >&2
  exit 2
}

# Infer TARGET_TYPE=org when --org is provided (no need for explicit --target org).
[[ -n "$TARGET_ORG" ]] && TARGET_TYPE="org"

[[ -z "$FLAG" || -z "$ROLE" || -z "$VALUE" ]] && usage
[[ -z "${FLAG_ENV_VARS[$FLAG]:-}" ]] && { echo "unknown flag: $FLAG" >&2; usage; }
[[ "$ROLE" != "prd" && "$ROLE" != "dev" ]] && { echo "role must be prd|dev (got: $ROLE)" >&2; usage; }
[[ "$VALUE" != "on" && "$VALUE" != "off" ]] && { echo "value must be on|off (got: $VALUE)" >&2; usage; }
[[ "$TARGET_TYPE" != "role" && "$TARGET_TYPE" != "org" ]] && { echo "target must be role|org (got: $TARGET_TYPE)" >&2; usage; }
[[ "$TARGET_TYPE" == "org" && -z "$TARGET_ORG" ]] && { echo "--target org requires --org <orgId>" >&2; usage; }

if [[ "$TARGET_TYPE" == "org" ]]; then
  [[ "$TARGET_ORG" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || { echo "invalid orgId format (expected UUID): $TARGET_ORG" >&2; exit 2; }
fi

ENV_VAR="${FLAG_ENV_VARS[$FLAG]}"
PROPOSED_ENABLED=$([[ "$VALUE" == "on" ]] && echo true || echo false)
SEGMENT_NAME="role-$ROLE"

# --- prerequisites ----------------------------------------------------------
command -v curl >/dev/null || { echo "missing: curl" >&2; exit 2; }
command -v doppler >/dev/null || { echo "missing: doppler" >&2; exit 2; }
command -v python3 >/dev/null || { echo "missing: python3" >&2; exit 2; }

TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain 2>/dev/null || true)
[[ -z "$TOKEN" ]] && { echo "FLAGSMITH_MANAGEMENT_API_KEY not in Doppler soleur/cli_ops" >&2; exit 2; }

# --- helpers ----------------------------------------------------------------
fs_api() {
  curl -sS -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" "$@"
}

resolve_feature_id() {
  local name="$1"
  fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/features/?q=${name}" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
for f in d.get('results', []):
    if f['name'] == '$name':
        print(f['id'])
        sys.exit(0)
print('not-found', file=sys.stderr)
sys.exit(3)
"
}

resolve_segment_id() {
  local name="$1"
  fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
for s in d.get('results', []):
    if s['name'] == '$name':
        print(s['id'])
        sys.exit(0)
print('not-found', file=sys.stderr)
sys.exit(3)
"
}

# Find the feature_segment row id for (env, feature, segment), if any.
# Uses numeric env_id (the /features/feature-segments/ endpoint accepts int).
read_feature_segment_id() {
  local env_id="$1" feature_id="$2" segment_id="$3"
  fs_api "${FLAGSMITH_API}/features/feature-segments/?environment=${env_id}&feature=${feature_id}" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
for fs in d.get('results', []):
    if fs.get('segment') == int('$segment_id'):
        print(fs['id']); sys.exit(0)
print('')
"
}

# Get the live (published, is_live) version uuid for (env, feature).
get_live_version_uuid() {
  local env_id="$1" feature_id="$2"
  fs_api "${FLAGSMITH_API}/environments/${env_id}/features/${feature_id}/versions/" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
for v in d.get('results', []):
    if v.get('is_live'):
        print(v['uuid']); sys.exit(0)
sys.exit(3)
"
}

# Read enablement of (env, feature, segment). Outputs "true"/"false"/"missing".
# Uses the version-scoped featurestates endpoint which returns env-default +
# segment overrides in one call.
read_segment_state() {
  local env_id="$1" feature_id="$2" segment_id="$3"
  local live_uuid
  live_uuid=$(get_live_version_uuid "$env_id" "$feature_id") || { echo "missing"; return; }
  fs_api "${FLAGSMITH_API}/environments/${env_id}/features/${feature_id}/versions/${live_uuid}/featurestates/" \
    | python3 -c "
import json, sys
target = int('$segment_id')
d = json.load(sys.stdin)
for fs in d:
    seg = fs.get('feature_segment')
    seg_id_val = None
    if isinstance(seg, dict):
        seg_id_val = seg.get('segment')
    if seg_id_val == target:
        print(str(fs['enabled']).lower()); sys.exit(0)
print('missing')
"
}

# Push a new version with the override change. Detects create-vs-update via
# whether a feature_segment row already exists.
flip_segment_in_env() {
  local env_id="$1" feature_id="$2" segment_id="$3" enabled="$4"

  local existing_fs_id
  existing_fs_id=$(read_feature_segment_id "$env_id" "$feature_id" "$segment_id")

  local body
  if [[ -z "$existing_fs_id" ]]; then
    # First-time override: feature_states_to_create.
    body=$(printf '{"feature_states_to_create":[{"feature_segment":{"segment":%d},"enabled":%s,"feature_state_value":{"type":"unicode","string_value":null,"integer_value":null,"boolean_value":null}}],"feature_states_to_update":[],"segment_ids_to_delete_overrides":[],"publish_immediately":true}' "$segment_id" "$enabled")
  else
    # Existing override: feature_states_to_update referencing the fs_id.
    body=$(printf '{"feature_states_to_create":[],"feature_states_to_update":[{"feature_segment":{"id":%d},"enabled":%s,"feature_state_value":{"type":"unicode","string_value":null,"integer_value":null,"boolean_value":null}}],"segment_ids_to_delete_overrides":[],"publish_immediately":true}' "$existing_fs_id" "$enabled")
  fi

  local resp
  resp=$(fs_api -X POST "${FLAGSMITH_API}/environments/${env_id}/features/${feature_id}/versions/" -d "$body")
  echo "$resp" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("uuid"):
    print(json.dumps(d), file=sys.stderr)
    sys.exit(3)
print("ok:", d["uuid"])
' || exit 3
}

doppler_mirror() {
  local config="$1" value="$2"
  # Write via stdin so the value never appears in process listing.
  printf '%s' "$value" | doppler secrets set "${ENV_VAR}" -p soleur -c "$config" --silent || return 4
}

gate_or_confirm() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry-run — exiting 0 without mutation)"
    exit 0
  fi
  if [[ $CONFIRMED -eq 0 ]]; then
    echo
    read -p "Proceed? Type 'yes' to apply: " ACK
    [[ "$ACK" == "yes" ]] || { echo "aborted (ack was '$ACK')" >&2; exit 0; }
  else
    echo "(--confirmed: skipping interactive prompt)"
  fi
}

audit_append() {
  local audit_target="$1"
  local actor audit_url audit_srk before_bool after_bool audit_id
  actor=$(doppler secrets get OPERATOR_EMAIL -p soleur -c cli_ops --plain 2>/dev/null | tr '[:upper:]' '[:lower:]')
  [[ -z "$actor" ]] && { echo "FATAL: OPERATOR_EMAIL not in Doppler soleur/cli_ops" >&2; exit 4; }
  # `|| true` normalizes a Doppler auth/network failure to the exit-4 contract.
  audit_url=$(doppler secrets get SUPABASE_URL -p soleur -c dev --plain 2>/dev/null) || true
  audit_srk=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c dev --plain 2>/dev/null) || true
  [[ -z "$audit_url" || -z "$audit_srk" ]] && { echo "FATAL: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not in Doppler soleur/dev" >&2; exit 4; }
  before_bool=$([[ "$VALUE" == "on" ]] && echo "false" || echo "true")
  after_bool=$([[ "$VALUE" == "on" ]] && echo "true" || echo "false")
  audit_id=$(audit_flag_flip_rpc "$audit_url" "$audit_srk" "$FLAG" "$ROLE" "$audit_target" "$VALUE" "$before_bool" "$after_bool" "$actor") || exit 4
  echo "  audit_id=$audit_id"
}

# --- org-targeting branch --------------------------------------------------
# When --org is provided, modify the org-targeted segment's rule definition
# directly (add/remove EQUAL orgId conditions in the ANY rule), then exit. No Doppler
# mirror — org segment membership is not reflected in env vars (ADR-038
# fallback mirrors prd-segment override state, not segment rule definitions).
if [[ "$TARGET_TYPE" == "org" ]]; then
  echo "→ Resolving org-targeted segment…"
  ORG_SEG_ID=$(resolve_segment_id "org-targeted") || { echo "segment 'org-targeted' not found in Flagsmith" >&2; exit 3; }
  echo "  org-targeted segment_id=$ORG_SEG_ID"

  echo "→ Reading segment rules…"
  SEG_JSON=$(fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/${ORG_SEG_ID}/") \
    || { echo "failed to read segment $ORG_SEG_ID" >&2; exit 3; }

  # The org-targeted segment uses ANY(EQUAL orgId <uuid>, EQUAL orgId <uuid>, ...)
  # — one condition per org, not a single IN condition with comma-separated values.
  PARSED=$(echo "$SEG_JSON" | python3 -c "
import json, sys
seg = json.load(sys.stdin)
conditions = seg['rules'][0]['rules'][0]['conditions']
orgs = []
for c in conditions:
    if c.get('operator') != 'EQUAL' or c.get('property') != 'orgId':
        print(f\"unexpected condition: operator={c.get('operator')} property={c.get('property')}\", file=sys.stderr)
        sys.exit(3)
    orgs.append(c['value'])
print(','.join(orgs) if orgs else '')
") || { echo "failed to parse segment rules (unexpected structure)" >&2; exit 3; }

  CURRENT_ORGS="$PARSED"

  RESULT=$(CURRENT_ORGS="$CURRENT_ORGS" TARGET_ORG="$TARGET_ORG" VALUE="$VALUE" python3 -c "
import os, sys
current = os.environ['CURRENT_ORGS']
target = os.environ['TARGET_ORG']
action = os.environ['VALUE']
orgs = [x for x in current.split(',') if x] if current else []

if action == 'on':
    if target in orgs:
        print('IDEMPOTENT:already present')
    else:
        orgs.append(target)
        print(','.join(orgs))
else:
    if target not in orgs:
        print('IDEMPOTENT:not present')
    else:
        orgs.remove(target)
        print(','.join(orgs))
") || exit 3

  if [[ "$RESULT" == "IDEMPOTENT:already present" ]]; then
    echo "  orgId $TARGET_ORG is already in the org-targeted segment — no change needed."
    exit 0
  fi
  if [[ "$RESULT" == "IDEMPOTENT:not present" ]]; then
    echo "  orgId $TARGET_ORG is not in the org-targeted segment — no change needed."
    exit 0
  fi

  NEW_ORGS="$RESULT"

  echo "→ Current membership:"
  if [[ -z "$CURRENT_ORGS" ]]; then
    echo "  (empty)"
  else
    echo "$CURRENT_ORGS" | tr ',' '\n' | sed 's/^/  /'
  fi
  echo "→ Proposed: $VALUE orgId $TARGET_ORG"
  echo "→ New membership:"
  echo "$NEW_ORGS" | tr ',' '\n' | sed 's/^/  /'

  gate_or_confirm
  audit_append "org:$TARGET_ORG"

  echo "→ Writing updated segment to Flagsmith…"
  UPDATED_JSON=$(echo "$SEG_JSON" | NEW_ORGS="$NEW_ORGS" python3 -c "
import json, os, sys
seg = json.load(sys.stdin)
new_orgs = os.environ['NEW_ORGS']
orgs = [x for x in new_orgs.split(',') if x] if new_orgs else []
seg['rules'][0]['rules'][0]['conditions'] = [
    {'operator': 'EQUAL', 'property': 'orgId', 'value': o} for o in orgs
]
json.dump(seg, sys.stdout)
") || { echo "failed to build updated segment JSON" >&2; exit 3; }

  RESP=$(echo "$UPDATED_JSON" | fs_api -X PUT "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/${ORG_SEG_ID}/" -d @-) \
    || { echo "PUT segment failed" >&2; exit 3; }

  echo "$RESP" | python3 -c "
import json, sys
seg = json.load(sys.stdin)
if 'id' not in seg:
    print(json.dumps(seg), file=sys.stderr)
    sys.exit(3)
print('  updated segment id=' + str(seg['id']))
" || exit 3

  echo "→ Re-verifying…"
  VERIFY_VALUE=$(fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/${ORG_SEG_ID}/" \
    | python3 -c "
import json, sys
seg = json.load(sys.stdin)
conditions = seg['rules'][0]['rules'][0]['conditions']
orgs = sorted(c['value'] for c in conditions if c.get('property') == 'orgId')
print(','.join(orgs))
") || { echo "re-verification read failed" >&2; exit 3; }

  EXPECT_ORGS=$(echo "$NEW_ORGS" | tr ',' '\n' | sort | paste -sd,)
  if [[ "$VERIFY_VALUE" != "$EXPECT_ORGS" ]]; then
    echo "VERIFICATION FAILED: expected [$EXPECT_ORGS] but got [$VERIFY_VALUE]" >&2
    exit 3
  fi
  echo "  ✓ verified: orgId $TARGET_ORG is $([[ "$VALUE" == "on" ]] && echo 'present' || echo 'absent') in org-targeted segment."

  echo
  echo "✓ Done. Segment rule change is immediate — no cache TTL applies to segment definitions."
  exit 0
fi

# --- resolve ---------------------------------------------------------------
echo "→ Resolving feature '$FLAG' + segment '$SEGMENT_NAME' in Flagsmith…"
FEATURE_ID=$(resolve_feature_id "$FLAG") || { echo "feature '$FLAG' not found in Flagsmith" >&2; exit 3; }
SEG_PRD=$(resolve_segment_id "role-prd") || exit 3
SEG_DEV=$(resolve_segment_id "role-dev") || exit 3
SEG_TARGET=$([[ "$ROLE" == "prd" ]] && echo "$SEG_PRD" || echo "$SEG_DEV")

echo "  feature_id=$FEATURE_ID  role-prd=$SEG_PRD  role-dev=$SEG_DEV"

# --- read current state (both envs, both segments) -------------------------
echo "→ Current state:"
CUR_DEV_PRD=$(read_segment_state "$FLAGSMITH_ENV_DEV_ID" "$FEATURE_ID" "$SEG_PRD")
CUR_DEV_DEV=$(read_segment_state "$FLAGSMITH_ENV_DEV_ID" "$FEATURE_ID" "$SEG_DEV")
CUR_PRD_PRD=$(read_segment_state "$FLAGSMITH_ENV_PRD_ID" "$FEATURE_ID" "$SEG_PRD")
CUR_PRD_DEV=$(read_segment_state "$FLAGSMITH_ENV_PRD_ID" "$FEATURE_ID" "$SEG_DEV")
printf '  %-12s %-12s %-12s\n' "env" "role-prd" "role-dev"
printf '  %-12s %-12s %-12s\n' "dev"  "$CUR_DEV_PRD" "$CUR_DEV_DEV"
printf '  %-12s %-12s %-12s\n' "prd"  "$CUR_PRD_PRD" "$CUR_PRD_DEV"

# --- fallback-fidelity rule -------------------------------------------------
if [[ "$ROLE" == "dev" && "$VALUE" == "off" ]]; then
  if [[ "$CUR_DEV_PRD" == "true" || "$CUR_PRD_PRD" == "true" ]]; then
    echo >&2
    echo "REJECTED: cannot set dev off while prd on — env-var fallback cannot represent" >&2
    echo "this state (see ADR-038 v2 §Fallback semantics). Flip prd off first." >&2
    exit 1
  fi
fi

# --- proposed delta --------------------------------------------------------
echo "→ Proposed: $FLAG / role=$ROLE → $VALUE (in BOTH dev and prd envs)"
if [[ "$ROLE" == "prd" ]]; then
  echo "  + Doppler mirror: FLAG_${FLAG^^}=${VALUE}  in soleur/dev AND soleur/prd"
  echo "    (replacing $(doppler secrets get $ENV_VAR -p soleur -c prd --plain 2>/dev/null || echo unset) / $(doppler secrets get $ENV_VAR -p soleur -c dev --plain 2>/dev/null || echo unset))"
fi

gate_or_confirm

# --- audit append (WORM) ---------------------------------------------------
audit_append "role:$ROLE"

# --- write Flagsmith (both envs) -------------------------------------------
echo "→ Writing Flagsmith dev env…"
flip_segment_in_env "$FLAGSMITH_ENV_DEV_ID" "$FEATURE_ID" "$SEG_TARGET" "$PROPOSED_ENABLED"
echo "→ Writing Flagsmith prd env…"
flip_segment_in_env "$FLAGSMITH_ENV_PRD_ID" "$FEATURE_ID" "$SEG_TARGET" "$PROPOSED_ENABLED"

# --- mirror Doppler (only on prd flips) -------------------------------------
if [[ "$ROLE" == "prd" ]]; then
  DOPPLER_VAL=$([[ "$VALUE" == "on" ]] && echo 1 || echo 0)
  echo "→ Doppler: setting ${ENV_VAR}=${DOPPLER_VAL} in soleur/dev…"
  doppler_mirror dev "$DOPPLER_VAL" || { echo "Doppler dev write FAILED" >&2; exit 4; }
  echo "→ Doppler: setting ${ENV_VAR}=${DOPPLER_VAL} in soleur/prd…"
  doppler_mirror prd "$DOPPLER_VAL" || { echo "Doppler prd write FAILED (dev already updated — manual fix needed)" >&2; exit 4; }
fi

echo
echo "✓ Done. Cache TTL is 30s per role — propagation per replica completes within 30s."
exit 0
