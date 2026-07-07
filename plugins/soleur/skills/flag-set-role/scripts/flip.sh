#!/usr/bin/env bash
# Flip a Flagsmith per-role segment override + mirror to Doppler on prd flips.
#
# Contract: SKILL.md in the parent directory. ADR-038 v2 §"Fallback semantics"
# documents the env-var mirror invariant this script enforces.
#
# Usage: bash flip.sh <flag> <prd|dev> <on|off> [--confirmed] [--org <orgId>] [--dry-run]
#        bash flip.sh <flag> <prd|dev> on --detach-shared --org <memberId> [--control-org <id>] [--confirmed]
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
# Edge SDK eval endpoint (client-side X-Environment-Key). Mirrors the production
# resolution path: flagsmith-nodejs getIdentityFlags() against edge.api.flagsmith.com
# (apps/web-platform/lib/feature-flags/server.ts DEFAULT_FLAGSMITH_API_URL).
readonly FLAGSMITH_EDGE_API="https://edge.api.flagsmith.com/api/v1"
# Synthetic non-member orgId — default control for the eval-layer control-negative
# assertion. Guaranteed to match no segment, so the flag must eval OFF for it; if it
# evals ON the flag is globally enabled (a real leak). Override with --control-org to
# assert against a specific real sibling org (e.g. the org sharing org-targeted).
readonly DEFAULT_CONTROL_ORG="00000000-0000-0000-0000-000000000000"
# Legacy shared per-org segment (ADR-043 §"Segment Design", pre per-feature scoping).
# `--detach-shared` resolves this BY NAME (never a hard-coded id) and removes the
# feature's override on it, migrating the feature onto its own `<flag>-orgs` segment.
readonly SHARED_SEGMENT_NAME="org-targeted"

# Map known flag-name → Doppler env-var name. Keep in sync with
# apps/web-platform/lib/feature-flags/server.ts RUNTIME_FLAGS.
# Co-editor: soleur:flag-delete (scripts/delete.sh) removes an entry from this
# map on delete by regex-matching `["<name>"]="FLAG_<X>"`. If you reshape this
# declaration (quoting, generated map, multi-line), update delete.sh's removal
# regex in lockstep or a deleted flag will leave a stale entry here.
declare -A FLAG_ENV_VARS=(
  ["kb-chat-sidebar"]="FLAG_KB_CHAT_SIDEBAR"
  ["team-workspace-invite"]="FLAG_TEAM_WORKSPACE_INVITE"
  ["byok-delegations"]="FLAG_BYOK_DELEGATIONS"
  ["c4-visualizer"]="FLAG_C4_VISUALIZER"
  ["debug-mode"]="FLAG_DEBUG_MODE"
  ["c4-edit"]="FLAG_C4_EDIT"
  ["command-palette"]="FLAG_COMMAND_PALETTE"
  ["support"]="FLAG_SUPPORT"
  ["guided-tour"]="FLAG_GUIDED_TOUR"
)

# --- arg parsing ------------------------------------------------------------
DRY_RUN=0
CONFIRMED=0
TARGET_TYPE="role"
TARGET_ORG=""
CONTROL_ORG=""
DETACH_SHARED=0
FLAG=""
ROLE=""
VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=1; shift ;;
    --confirmed)     CONFIRMED=1; shift ;;
    --target)        TARGET_TYPE="$2"; shift 2 ;;
    --org)           TARGET_ORG="$2"; shift 2 ;;
    --control-org)   CONTROL_ORG="$2"; shift 2 ;;
    --detach-shared) DETACH_SHARED=1; shift ;;
    --*)             echo "unknown flag: $1" >&2; exit 2 ;;
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
  echo "       flip.sh <flag> <prd|dev> on --detach-shared --org <memberId> [--control-org <id>] [--confirmed]" >&2
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
  [[ -z "$CONTROL_ORG" ]] && CONTROL_ORG="$DEFAULT_CONTROL_ORG"
  [[ "$CONTROL_ORG" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || { echo "invalid control orgId format (expected UUID): $CONTROL_ORG" >&2; exit 2; }
  [[ "$CONTROL_ORG" == "$TARGET_ORG" ]] \
    && { echo "--control-org must differ from --org (got both = $TARGET_ORG)" >&2; exit 2; }
  # The synthetic default only proves "not globally ON"; pass a real sibling org for a
  # leak check against the shared org-targeted blast radius. [review: user-impact F4]
  [[ "$CONTROL_ORG" == "$DEFAULT_CONTROL_ORG" ]] \
    && echo "⚠ control-negative uses the synthetic default org ($DEFAULT_CONTROL_ORG) — pass --control-org <real-sibling-uuid> for a stronger leak assertion." >&2
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

# audit_append <target> [before_override] [after_override]
# WORM append-before-flip. before/after default to the on/off semantics of $VALUE;
# pass explicit overrides for a mutation that does NOT change enablement (e.g. a
# --detach-shared segment-config change where the feature stays enabled=true).
audit_append() {
  local audit_target="$1" before_override="${2:-}" after_override="${3:-}"
  local actor audit_url audit_srk before_bool after_bool audit_id
  actor=$(doppler secrets get OPERATOR_EMAIL -p soleur -c cli_ops --plain 2>/dev/null | tr '[:upper:]' '[:lower:]')
  [[ -z "$actor" ]] && { echo "FATAL: OPERATOR_EMAIL not in Doppler soleur/cli_ops" >&2; exit 4; }
  # `|| true` normalizes a Doppler auth/network failure to the exit-4 contract.
  audit_url=$(doppler secrets get SUPABASE_URL -p soleur -c dev --plain 2>/dev/null) || true
  audit_srk=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c dev --plain 2>/dev/null) || true
  [[ -z "$audit_url" || -z "$audit_srk" ]] && { echo "FATAL: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not in Doppler soleur/dev" >&2; exit 4; }
  before_bool=$([[ "$VALUE" == "on" ]] && echo "false" || echo "true")
  after_bool=$([[ "$VALUE" == "on" ]] && echo "true" || echo "false")
  [[ -n "$before_override" ]] && before_bool="$before_override"
  [[ -n "$after_override" ]] && after_bool="$after_override"
  # The WORM row is the compliance record — never append a malformed bool.
  case "$before_bool" in true|false) ;; *) echo "FATAL: audit before_bool must be true|false (got: '$before_bool')" >&2; exit 4 ;; esac
  case "$after_bool"  in true|false) ;; *) echo "FATAL: audit after_bool must be true|false (got: '$after_bool')" >&2; exit 4 ;; esac
  audit_id=$(audit_flag_flip_rpc "$audit_url" "$audit_srk" "$FLAG" "$ROLE" "$audit_target" "$VALUE" "$before_bool" "$after_bool" "$actor") || exit 4
  echo "  audit_id=$audit_id"
}

# Idempotently provision a feature's OWN org segment `<flag>-orgs` (ADR-043
# per-feature scoping, 2026-05-29): create the segment with the ALL→ANY/EQUAL-orgId
# envelope (zero conditions initially) if absent, then ensure an ON feature-state
# override for the feature on that segment in BOTH envs. Echoes the segment id on
# stdout (progress to stderr). Idempotent: re-running converges (no churn when the
# override is already ON). The per-org gate is the segment's conditions, added later.
provision_feature_segment() {
  local flag="$1"
  local seg_name="${flag}-orgs"
  local seg_id feat_id env_id cur resp body
  seg_id=$(resolve_segment_id "$seg_name" 2>/dev/null) || seg_id=""
  if [[ -z "$seg_id" ]]; then
    echo "  → creating segment '$seg_name'…" >&2
    # Same rule envelope as org-targeted (flip.sh source-of-truth), zero conditions.
    body=$(python3 -c "
import json
print(json.dumps({
  'name': '${seg_name}',
  'project': ${FLAGSMITH_PROJECT_ID},
  'rules': [{'type':'ALL','rules':[{'type':'ANY','rules':[],'conditions':[]}],'conditions':[]}],
}))")
    resp=$(echo "$body" | fs_api -X POST "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/" -d @-) \
      || { echo "failed to create segment $seg_name" >&2; return 3; }
    seg_id=$(echo "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))') \
      || { echo "segment create response not JSON: $resp" >&2; return 3; }
    [[ -n "$seg_id" ]] || { echo "segment create returned no id: $resp" >&2; return 3; }
    echo "    created $seg_name segment_id=$seg_id" >&2
  else
    echo "  → segment '$seg_name' exists (id=$seg_id)" >&2
  fi
  feat_id=$(resolve_feature_id "$flag") || { echo "feature '$flag' not found in Flagsmith" >&2; return 3; }
  # ON override in BOTH envs (idempotent: only publish when not already ON).
  for env_id in "$FLAGSMITH_ENV_DEV_ID" "$FLAGSMITH_ENV_PRD_ID"; do
    cur=$(read_segment_state "$env_id" "$feat_id" "$seg_id")
    if [[ "$cur" != "true" ]]; then
      echo "  → ON override for '$flag' on '$seg_name' (env $env_id)…" >&2
      flip_segment_in_env "$env_id" "$feat_id" "$seg_id" true >/dev/null
    fi
  done
  printf '%s' "$seg_id"
}

# Verification identity role trait. Deliberately a value that matches NO role
# segment (role-prd/role-dev match role=='prd'/'dev'), so eval-verify isolates the
# PER-ORG segment gate (`<flag>-orgs` / org-targeted match on orgId, role-independent)
# from any role-segment rollout. Without this, a flag carrying a role-<env>=ON override
# would evaluate enabled for EVERY identity and the control-negative assertion would
# fire spuriously. [review: code-reviewer "Important" / user-impact F4]
readonly FLAG_VERIFY_ROLE="__flag-verify__"

# Evaluate <flag> for a transient identity carrying the orgId trait, mirroring the
# production getIdentityFlags() path (edge.api.flagsmith.com /identities/). Echoes
# "true"/"false" ONLY on a 2xx; returns 3 on any transport OR HTTP error so the
# verify FAILS LOUD instead of fail-open. This is the FR8 load-bearing check: a correct
# segment membership is NOT proof the flag is enabled (override missing / one-env-only
# leaves it OFF) — re-verify reads the EVALUATED flag, not the membership set.
# [review P0: do NOT treat an error body's missing flag as "disabled".]
eval_flag_enabled() { # $1=env_key $2=flag $3=orgId
  local env_key="$1" flag="$2" org="$3" body resp code payload
  body=$(python3 -c "
import json
print(json.dumps({
  'identifier': 'org:${org}:${FLAG_VERIFY_ROLE}',
  'traits': [
    {'trait_key':'role','trait_value':'${FLAG_VERIFY_ROLE}'},
    {'trait_key':'orgId','trait_value':'${org}'},
  ],
  'transient': True,
}))")
  resp=$(curl -sS -w '\n%{http_code}' -X POST "${FLAGSMITH_EDGE_API}/identities/" \
    -H "X-Environment-Key: ${env_key}" -H "Content-Type: application/json" \
    -d "$body") || { echo "eval request failed (curl transport) for org $org" >&2; return 3; }
  code=$(printf '%s' "$resp" | tail -n1)
  payload=$(printf '%s' "$resp" | sed '$d')
  [[ "$code" =~ ^2[0-9][0-9]$ ]] \
    || { echo "eval HTTP $code for org $org (treating as UNVERIFIED, not disabled): $payload" >&2; return 3; }
  printf '%s' "$payload" | FS_FLAG="$flag" python3 -c "
import json, os, sys
flag = os.environ['FS_FLAG']
try:
    d = json.load(sys.stdin)
except Exception:
    print('eval response not JSON', file=sys.stderr); sys.exit(3)
for f in d.get('flags', []):
    if f.get('feature', {}).get('name') == flag:
        print(str(bool(f.get('enabled'))).lower()); sys.exit(0)
print('false')  # 2xx + flag absent -> authoritatively not enabled for this identity
"
}

# Poll eval until it matches the expected value (edge propagation is eventual).
# Echoes the final observed value; returns 0 on match within budget, 1 otherwise.
# Cadence overridable for tests (EVAL_POLL_TRIES / EVAL_POLL_SLEEP); live default
# ~24s budget. No sleep after the final attempt.
eval_until() { # $1=env_key $2=flag $3=org $4=expected
  local got i tries="${EVAL_POLL_TRIES:-12}" naptime="${EVAL_POLL_SLEEP:-2}"
  for i in $(seq 1 "$tries"); do
    got=$(eval_flag_enabled "$1" "$2" "$3") || return 3
    [[ "$got" == "$4" ]] && { printf '%s' "$got"; return 0; }
    [[ "$i" -lt "$tries" ]] && sleep "$naptime"
  done
  printf '%s' "$got"; return 1
}

# Detach a feature's override from a SHARED segment (e.g. the legacy `org-targeted`)
# by publishing a new version with `segment_ids_to_delete_overrides:[<shared id>]`
# (empty create/update arrays) in BOTH envs. Idempotent: a no-op for any env where
# no override row exists, and a clean no-op if the shared segment is already gone.
# Echoes the resolved shared segment id (empty if absent). Progress to stderr.
detach_from_shared() { # $1=flag $2=shared_segment_name
  local flag="$1" shared_name="$2"
  local feat_id shared_id env_id existing_fs_id body resp
  feat_id=$(resolve_feature_id "$flag") || { echo "feature '$flag' not found in Flagsmith" >&2; return 3; }
  shared_id=$(resolve_segment_id "$shared_name" 2>/dev/null) || shared_id=""
  if [[ -z "$shared_id" ]]; then
    echo "  → shared segment '$shared_name' not found — nothing to detach (no-op)" >&2
    printf ''; return 0
  fi
  for env_id in "$FLAGSMITH_ENV_DEV_ID" "$FLAGSMITH_ENV_PRD_ID"; do
    existing_fs_id=$(read_feature_segment_id "$env_id" "$feat_id" "$shared_id")
    if [[ -z "$existing_fs_id" ]]; then
      echo "  → no '$flag' override on '$shared_name' in env $env_id (already detached)" >&2
      continue
    fi
    echo "  → detaching '$flag' from '$shared_name' in env $env_id…" >&2
    body=$(printf '{"feature_states_to_create":[],"feature_states_to_update":[],"segment_ids_to_delete_overrides":[%d],"publish_immediately":true}' "$shared_id")
    resp=$(fs_api -X POST "${FLAGSMITH_API}/environments/${env_id}/features/${feat_id}/versions/" -d "$body")
    echo "$resp" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("uuid"):
    print(json.dumps(d), file=sys.stderr); sys.exit(3)
' || { echo "detach POST failed (env $env_id): $resp" >&2; return 3; }
  done
  printf '%s' "$shared_id"
}

# --- detach-from-shared branch (#4617, ADR-043 §"Per-feature segment scoping") ---
# Migrate a feature OFF the legacy shared `org-targeted` segment. The feature must
# already be served by its own `<flag>-orgs` segment (provision via the --org path
# FIRST); this removes its override on the shared segment, then eval-verifies the
# feature STILL resolves enabled=true for the member org (now via <flag>-orgs) and
# enabled=false for a control org (no leak). No Doppler mirror (segment-config change).
if [[ $DETACH_SHARED -eq 1 ]]; then
  [[ "$TARGET_TYPE" != "org" || -z "$TARGET_ORG" ]] \
    && { echo "--detach-shared requires --org <member-uuid> (the org to eval-verify stays enabled after detach)" >&2; exit 2; }
  [[ "$VALUE" != "on" ]] \
    && { echo "--detach-shared requires value 'on' (the feature must remain enabled for the member after detach)" >&2; exit 2; }
  ENV_KEY=$([[ "$ROLE" == "prd" ]] && echo "$FLAGSMITH_ENV_PRD_KEY" || echo "$FLAGSMITH_ENV_DEV_KEY")

  echo "→ Detach '$FLAG' from shared segment '$SHARED_SEGMENT_NAME' (both envs)"
  echo "→ Member to eval-verify stays enabled: $TARGET_ORG (control: $CONTROL_ORG)"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry-run — would detach '$FLAG' from '$SHARED_SEGMENT_NAME' in both envs, then"
    echo "  eval-verify member enabled=true / control enabled=false; exiting 0 without mutation)"
    exit 0
  fi
  if [[ $CONFIRMED -eq 0 ]]; then
    echo
    read -p "Proceed? Type 'yes' to apply: " ACK
    [[ "$ACK" == "yes" ]] || { echo "aborted (ack was '$ACK')" >&2; exit 0; }
  else
    echo "(--confirmed: skipping interactive prompt)"
  fi

  # Append-before-flip: WORM audit precedes the first Flagsmith mutation. Enablement
  # is UNCHANGED (the feature stays ON, now served by <flag>-orgs) → before=after=true.
  audit_append "detach:$SHARED_SEGMENT_NAME" true true

  echo "→ Detaching from '$SHARED_SEGMENT_NAME'…"
  detach_from_shared "$FLAG" "$SHARED_SEGMENT_NAME" >/dev/null || exit 3

  # Eval-layer re-verify (the load-bearing check): the feature must STILL evaluate
  # enabled for the member (served by <flag>-orgs now) and disabled for control.
  echo "→ Eval-verify ($ROLE env): $FLAG for member $TARGET_ORG must STILL be enabled=true…"
  GOT_TARGET=$(eval_until "$ENV_KEY" "$FLAG" "$TARGET_ORG" "true") || {
    echo "EVAL VERIFY FAILED: $FLAG for member $TARGET_ORG expected enabled=true after detach, last observed=$GOT_TARGET" >&2
    echo "  (the detach dropped the member — its <flag>-orgs override is missing/one-env-only, OR the edge endpoint errored. UNVERIFIED — investigate; the member may have LOST the feature.)" >&2
    exit 3
  }
  echo "  ✓ member $TARGET_ORG: enabled=$GOT_TARGET"

  echo "→ Eval-verify ($ROLE env): control org $CONTROL_ORG must settle to enabled=false (no leak)…"
  GOT_CONTROL=$(eval_until "$ENV_KEY" "$FLAG" "$CONTROL_ORG" "false") || {
    echo "EVAL VERIFY FAILED (control leak): $FLAG did not settle to disabled for control org $CONTROL_ORG within the propagation budget (last observed=$GOT_CONTROL) — the flag is reaching a non-targeted org, OR the edge endpoint errored. UNVERIFIED." >&2
    exit 3
  }
  echo "  ✓ control $CONTROL_ORG: enabled=$GOT_CONTROL"

  echo
  echo "✓ Done. '$FLAG' detached from '$SHARED_SEGMENT_NAME' + eval-verified (served by"
  echo "  ${FLAG}-orgs now). Segment changes are immediate; edge eval propagation completes within seconds."
  exit 0
fi

# --- org-targeting branch (ADR-043 per-feature segment scoping) -------------
# When --org is provided, target the feature's OWN segment `<flag>-orgs` (NOT the
# shared org-targeted segment): provision it (segment + ON override both envs), then
# add/remove the org's EQUAL orgId condition, then re-verify by EVALUATING the flag
# for the target org (must be enabled) and a control org (must be disabled). No Doppler
# mirror — per-org segment membership is invisible to the FLAG_* env-var fallback
# (ADR-038/ADR-043: a per-org-only flag falls back OFF on a Flagsmith outage).
if [[ "$TARGET_TYPE" == "org" ]]; then
  SEG_NAME="${FLAG}-orgs"
  echo "→ Per-feature org segment: $SEG_NAME"
  ENV_KEY=$([[ "$ROLE" == "prd" ]] && echo "$FLAGSMITH_ENV_PRD_KEY" || echo "$FLAGSMITH_ENV_DEV_KEY")

  # Read current membership (segment may not exist yet -> empty).
  PRE_SEG_ID=$(resolve_segment_id "$SEG_NAME" 2>/dev/null) || PRE_SEG_ID=""
  CURRENT_ORGS=""
  if [[ -n "$PRE_SEG_ID" ]]; then
    PRE_JSON=$(fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/${PRE_SEG_ID}/") \
      || { echo "failed to read segment $PRE_SEG_ID" >&2; exit 3; }
    CURRENT_ORGS=$(echo "$PRE_JSON" | python3 -c "
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
") || { echo "failed to parse $SEG_NAME rules (unexpected structure)" >&2; exit 3; }
  fi

  # Compute new membership (add on / remove off). No early-exit on 'already present':
  # the override may still be missing, so we always provision + eval-verify.
  NEW_ORGS=$(CURRENT_ORGS="$CURRENT_ORGS" TARGET_ORG="$TARGET_ORG" VALUE="$VALUE" python3 -c "
import os
current = os.environ['CURRENT_ORGS']
target = os.environ['TARGET_ORG']
action = os.environ['VALUE']
orgs = [x for x in current.split(',') if x] if current else []
if action == 'on':
    if target not in orgs: orgs.append(target)
else:
    orgs = [o for o in orgs if o != target]
print(','.join(orgs))
") || exit 3

  echo "→ Current membership of $SEG_NAME:"
  if [[ -z "$CURRENT_ORGS" ]]; then echo "  (empty)"; else echo "$CURRENT_ORGS" | tr ',' '\n' | sed 's/^/  /'; fi
  echo "→ Proposed: $VALUE orgId $TARGET_ORG (control: $CONTROL_ORG)"
  echo "→ New membership:"
  if [[ -z "$NEW_ORGS" ]]; then echo "  (empty — feature OFF for all via $SEG_NAME)"; else echo "$NEW_ORGS" | tr ',' '\n' | sed 's/^/  /'; fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry-run — would provision $SEG_NAME (+ON override both envs), set membership above, then eval-verify; exiting 0 without mutation)"
    exit 0
  fi
  if [[ $CONFIRMED -eq 0 ]]; then
    echo
    read -p "Proceed? Type 'yes' to apply: " ACK
    [[ "$ACK" == "yes" ]] || { echo "aborted (ack was '$ACK')" >&2; exit 0; }
  else
    echo "(--confirmed: skipping interactive prompt)"
  fi

  # Append-before-flip: WORM audit precedes the first Flagsmith mutation (provision).
  audit_append "org:$TARGET_ORG"

  echo "→ Provisioning $SEG_NAME (segment + ON override both envs)…"
  ORG_SEG_ID=$(provision_feature_segment "$FLAG") || exit 3

  # Re-read immediately before the PUT to shrink the read-modify-write window (P1-1),
  # then rebuild the conditions from the fresh read + target delta.
  echo "→ Reading segment rules…"
  SEG_JSON=$(fs_api "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/${ORG_SEG_ID}/") \
    || { echo "failed to read segment $ORG_SEG_ID" >&2; exit 3; }

  # Recompute the delta from the FRESH read (the segment may have just been created
  # empty by provision_feature_segment). One EQUAL orgId condition per org in the ANY
  # rule — NOT a single IN condition (org-targeted source-of-truth, flip.sh history).
  UPDATED_JSON=$(echo "$SEG_JSON" | TARGET_ORG="$TARGET_ORG" VALUE="$VALUE" python3 -c "
import json, os, sys
seg = json.load(sys.stdin)
target = os.environ['TARGET_ORG']
action = os.environ['VALUE']
anyrule = seg['rules'][0]['rules'][0]
orgs = []
for c in anyrule['conditions']:
    if c.get('operator') != 'EQUAL' or c.get('property') != 'orgId':
        print(f\"unexpected condition: operator={c.get('operator')} property={c.get('property')}\", file=sys.stderr)
        sys.exit(3)
    orgs.append(c['value'])
if action == 'on':
    if target not in orgs: orgs.append(target)
else:
    orgs = [o for o in orgs if o != target]
anyrule['conditions'] = [{'operator':'EQUAL','property':'orgId','value':o} for o in orgs]
json.dump(seg, sys.stdout)
") || { echo "failed to build updated $SEG_NAME JSON (unexpected structure)" >&2; exit 3; }

  echo "→ Writing updated $SEG_NAME membership to Flagsmith…"
  RESP=$(echo "$UPDATED_JSON" | fs_api -X PUT "${FLAGSMITH_API}/projects/${FLAGSMITH_PROJECT_ID}/segments/${ORG_SEG_ID}/" -d @-) \
    || { echo "PUT segment failed" >&2; exit 3; }
  echo "$RESP" | python3 -c "
import json, sys
seg = json.load(sys.stdin)
if 'id' not in seg:
    print(json.dumps(seg), file=sys.stderr); sys.exit(3)
print('  updated segment id=' + str(seg['id']))
" || exit 3

  # --- eval-layer re-verify (FR8, the load-bearing fix) ---------------------
  # Membership-set equality is NOT sufficient (override-missing / one-env-only leaves
  # the flag OFF while the org is 'in' the segment). Evaluate the flag for a transient
  # identity carrying the orgId trait (production getIdentityFlags path), asserting:
  #   target org  -> enabled == (VALUE==on)         [the per-org enable actually works]
  #   control org -> enabled == false               [no leak to a non-targeted org]
  EXPECT_TARGET=$([[ "$VALUE" == "on" ]] && echo true || echo false)
  echo "→ Eval-verify ($ROLE env): $FLAG for target $TARGET_ORG must be enabled=$EXPECT_TARGET…"
  GOT_TARGET=$(eval_until "$ENV_KEY" "$FLAG" "$TARGET_ORG" "$EXPECT_TARGET") || {
    echo "EVAL VERIFY FAILED: $FLAG for org $TARGET_ORG expected enabled=$EXPECT_TARGET, last observed=$GOT_TARGET" >&2
    echo "  (membership was written, but the flag does not EVALUATE as expected — missing/one-env override OR the edge endpoint errored; this is UNVERIFIED, investigate before relying on it)" >&2
    exit 3
  }
  echo "  ✓ target $TARGET_ORG: enabled=$GOT_TARGET"

  # Poll until the control SETTLES to disabled — same propagation tolerance as the
  # target check. The edge environment document is eventually consistent: right after a
  # segment+override create, a non-member org can transiently read enabled=true for one
  # refresh window before the segment's orgId condition propagates. A single-shot read
  # here false-positives on that window. A genuine leak never settles to false → the
  # poll exhausts its budget and fails loud (and an HTTP error returns 3 → exit 3).
  echo "→ Eval-verify ($ROLE env): control org $CONTROL_ORG must settle to enabled=false (no leak)…"
  GOT_CONTROL=$(eval_until "$ENV_KEY" "$FLAG" "$CONTROL_ORG" "false") || {
    echo "EVAL VERIFY FAILED (control leak): $FLAG did not settle to disabled for control org $CONTROL_ORG within the propagation budget (last observed=$GOT_CONTROL) — the flag is reaching a non-targeted org, OR the edge endpoint errored. UNVERIFIED." >&2
    exit 3
  }
  echo "  ✓ control $CONTROL_ORG: enabled=$GOT_CONTROL"

  echo
  echo "✓ Done. $SEG_NAME membership updated + flag eval-verified. Segment changes are"
  echo "  immediate; edge eval propagation completes within seconds."
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
