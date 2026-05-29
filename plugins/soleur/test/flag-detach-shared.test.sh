#!/usr/bin/env bash
# Tests for #4617 — flip.sh --detach-shared (migrate a feature off the legacy
# shared `org-targeted` segment onto its own `<flag>-orgs` segment, ADR-043
# §"Per-feature segment scoping").
#
# The detach verb publishes a new feature version with
# `segment_ids_to_delete_overrides:[<org-targeted id>]` (empty create/update
# arrays) in BOTH envs, appends a WORM audit row append-before-flip, then
# eval-verifies the feature STILL resolves enabled=true for a member org (now
# served by `<flag>-orgs`) and enabled=false for a control org (no leak).
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
FLIP="$REPO_ROOT/plugins/soleur/skills/flag-set-role/scripts/flip.sh"
fail=0

TARGET_ORG_FULL="70a70ab0-0000-0000-0000-000000000001"   # member org (must stay enabled)
CONTROL_ORG_FULL="1a8045bf-0000-0000-0000-000000000002"   # sibling/control (must be off)
FLAG_NAME="team-workspace-invite"
ORG_TARGETED_ID=1130454

make_doppler_stub() { # $1=dir
  cat > "$1/doppler" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "secrets" && "${2:-}" == "get" ]]; then
  case "${3:-}" in
    FLAGSMITH_MANAGEMENT_API_KEY) echo "fake-mgmt-key" ;;
    OPERATOR_EMAIL)               echo "op@jikigai.com" ;;
    SUPABASE_URL)                 echo "https://x.supabase.co" ;;
    SUPABASE_SERVICE_ROLE_KEY)    echo "srk" ;;
    *)                            echo "" ;;
  esac
  exit 0
fi
if [[ "${1:-}" == "secrets" && "${2:-}" == "set" ]]; then
  echo "set:${3:-}" >> "${DOPPLER_SET_LOG:-/dev/null}"
  exit 0
fi
exit 0
STUB
  chmod +x "$1/doppler"
}

# Stateless Flagsmith stub for the detach path. Records POST bodies to $BODY_LOG
# and every (method url) to $CURL_LOG. Knobs:
#   FS_OVERRIDE_PRESENT  1 (default) → feature has an override row on org-targeted;
#                        0 → no override (idempotent no-op path).
#   FS_SHARED_ABSENT     1 → /segments/ list omits org-targeted (segment already gone).
#   EVAL_TARGET_ENABLED  member eval result (default true — stays enabled post-detach).
#   EVAL_CONTROL_ENABLED control eval result (default false — no leak).
#   EVAL_HTTP_CODE       edge eval HTTP status (default 200).
#   AUDIT_HTTP_CODE      audit RPC HTTP status (default 200; 500 → append-before-flip abort).
make_detach_curl_stub() { # $1=dir
  cat > "$1/curl" <<'STUB'
#!/usr/bin/env bash
url=""; method="GET"; data=""; prev=""
for a in "$@"; do
  case "$prev" in -X) method="$a" ;; -d) data="$a" ;; esac
  case "$a" in http*) url="$a" ;; esac
  prev="$a"
done
echo "$method $url" >> "${CURL_LOG:-/dev/null}"
case "$url" in
  *"/rpc/audit_flag_flip"*)
    printf '%s\n%s' '"11111111-1111-1111-1111-111111111111"' "${AUDIT_HTTP_CODE:-200}"; exit 0 ;;
  *"/identities/"*)
    en="false"
    if [[ "$data" == *"$TARGET_ORG_FULL"* ]];  then en="${EVAL_TARGET_ENABLED:-true}"; fi
    if [[ "$data" == *"$CONTROL_ORG_FULL"* ]]; then en="${EVAL_CONTROL_ENABLED:-false}"; fi
    printf '{"flags":[{"feature":{"name":"%s"},"enabled":%s}],"traits":[]}\n%s' "$FLAG_NAME" "$en" "${EVAL_HTTP_CODE:-200}"
    exit 0 ;;
  *"/features/?q="*)
    printf '{"results":[{"id":777,"name":"%s"}]}' "$FLAG_NAME"; exit 0 ;;
  *"/feature-segments/"*)
    if [[ "${FS_OVERRIDE_PRESENT:-1}" == "1" ]]; then
      printf '{"results":[{"id":555,"segment":%s}]}' "$ORG_TARGETED_ID"
    else
      echo '{"results":[]}'
    fi
    exit 0 ;;
  *"/segments/")
    if [[ "${FS_SHARED_ABSENT:-0}" == "1" ]]; then echo '{"results":[]}'
    else printf '{"results":[{"id":%s,"name":"org-targeted"}]}' "$ORG_TARGETED_ID"; fi
    exit 0 ;;
  *"/versions/"*)
    if [[ "$method" == "POST" ]]; then
      echo "$data" >> "${BODY_LOG:-/dev/null}"
      echo '{"uuid":"v-uuid"}'
    else
      echo '{"results":[{"uuid":"v-uuid","is_live":true}]}'
    fi
    exit 0 ;;
  *) echo '{}'; exit 0 ;;
esac
STUB
  chmod +x "$1/curl"
}

STUB_DIR="$(mktemp -d)"; trap 'rm -rf "$STUB_DIR"' EXIT
make_doppler_stub "$STUB_DIR"
make_detach_curl_stub "$STUB_DIR"

run_detach() { # caller sets env knobs; runs from repo root (FLAG_ENV_VARS resolution)
  ( cd "$REPO_ROOT" \
    && PATH="$STUB_DIR:$PATH" CURL_LOG="$CURL_LOG" DOPPLER_SET_LOG="$DOPPLER_SET_LOG" BODY_LOG="$BODY_LOG" \
       TARGET_ORG_FULL="$TARGET_ORG_FULL" CONTROL_ORG_FULL="$CONTROL_ORG_FULL" \
       FLAG_NAME="$FLAG_NAME" ORG_TARGETED_ID="$ORG_TARGETED_ID" \
       EVAL_POLL_SLEEP=0 EVAL_POLL_TRIES=2 \
       bash "$FLIP" "$@" )
}

# --- 1. source-level: the verb exists and resolves the shared segment by name ---
if ! grep -q 'detach-shared' "$FLIP"; then
  echo "detach: FAIL — flip.sh lacks the --detach-shared verb" >&2; fail=1
fi
if ! grep -q 'org-targeted' "$FLIP"; then
  echo "detach: FAIL — flip.sh detach path must reference the shared 'org-targeted' segment (resolved by name)" >&2; fail=1
fi

# --- 2. POSITIVE: detach with member-stays-enabled / control-off → exit 0 -------
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  # 2a. version-POST body shape: delete-override carries org-targeted id; create/update empty.
  grep -q "\"segment_ids_to_delete_overrides\":\[${ORG_TARGETED_ID}\]" "$BODY_LOG" \
    || { echo "detach: FAIL — version body missing segment_ids_to_delete_overrides:[$ORG_TARGETED_ID] (body: $(cat "$BODY_LOG"))" >&2; fail=1; }
  grep -q '"feature_states_to_create":\[\]' "$BODY_LOG" \
    || { echo "detach: FAIL — version body must have empty feature_states_to_create" >&2; fail=1; }
  grep -q '"feature_states_to_update":\[\]' "$BODY_LOG" \
    || { echo "detach: FAIL — version body must have empty feature_states_to_update" >&2; fail=1; }
  # 2b. ran in BOTH envs (dev 90722 + prd 90721 version POSTs).
  grep -q 'POST .*/environments/90722/features/.*/versions/' "$CURL_LOG" \
    || { echo "detach: FAIL — no detach version POST against dev env 90722" >&2; fail=1; }
  grep -q 'POST .*/environments/90721/features/.*/versions/' "$CURL_LOG" \
    || { echo "detach: FAIL — no detach version POST against prd env 90721" >&2; fail=1; }
  # 2c. append-before-flip: audit RPC POSTed BEFORE the first version POST.
  audit_line=$(grep -n '/rpc/audit_flag_flip' "$CURL_LOG" | head -1 | cut -d: -f1)
  ver_line=$(grep -nE 'POST .*/versions/' "$CURL_LOG" | head -1 | cut -d: -f1)
  if [[ -z "$audit_line" ]]; then
    echo "detach: FAIL — no WORM audit RPC call recorded" >&2; fail=1
  elif [[ -n "$ver_line" && "$audit_line" -ge "$ver_line" ]]; then
    echo "detach: FAIL — audit RPC ($audit_line) must precede the first version POST ($ver_line)" >&2; fail=1
  fi
  # 2d. eval-verify hit the edge identities endpoint.
  grep -q 'POST https://edge.api.flagsmith.com/api/v1/identities/' "$CURL_LOG" \
    || { echo "detach: FAIL — eval-verify did not POST the edge identities endpoint" >&2; fail=1; }
  # 2e. no Doppler mirror for a detach (segment-config change, not a role flip).
  if grep -q '^set:' "$DOPPLER_SET_LOG" 2>/dev/null; then
    echo "detach: FAIL — detach must not mirror Doppler ($(cat "$DOPPLER_SET_LOG"))" >&2; fail=1
  fi
else
  echo "detach: FAIL — positive detach (member on / control off) should exit 0" >&2; fail=1
fi

# --- 3. CONTROL-LEAK (gate-present): control evals enabled → fail loud ----------
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=true \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "detach: FAIL — control-org leak (eval true for control) must fail loud, not exit 0" >&2; fail=1
fi

# --- 4. MEMBER-DROPPED (gate-present): member no longer enabled → fail loud -----
# The whole point of detach is the member STAYS enabled via <flag>-orgs. If the
# detach drops it (override never migrated), the eval-verify must catch it.
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=false EVAL_CONTROL_ENABLED=false \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "detach: FAIL — member org dropped (eval false) must fail loud (post-detach member must stay enabled)" >&2; fail=1
fi

# --- 5. DRY-RUN: writes nothing (no version POST, no audit RPC), exit 0 ----------
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --dry-run \
     >/dev/null 2>&1; then
  if grep -qE 'POST .*/versions/' "$CURL_LOG"; then
    echo "detach: FAIL — --dry-run must not POST any version" >&2; fail=1
  fi
  if grep -q '/rpc/audit_flag_flip' "$CURL_LOG"; then
    echo "detach: FAIL — --dry-run must not append a WORM audit row" >&2; fail=1
  fi
else
  echo "detach: FAIL — --dry-run should exit 0" >&2; fail=1
fi

# --- 6. IDEMPOTENT: no override present → no version POST, still eval-verifies → 0 -
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if FS_OVERRIDE_PRESENT=0 EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  if grep -qE 'POST .*/versions/' "$CURL_LOG"; then
    echo "detach: FAIL — idempotent re-run (no override) must not POST a version" >&2; fail=1
  fi
else
  echo "detach: FAIL — idempotent re-run (no override present) should exit 0" >&2; fail=1
fi

# --- 7. FAIL-OPEN guard: edge eval HTTP error must not pass the verify ----------
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false EVAL_HTTP_CODE=500 \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "detach: FAIL — edge eval HTTP 500 must fail loud (no fail-open), not exit 0" >&2; fail=1
fi

# --- 8. requires --org (the member to eval-verify) ------------------------------
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if run_detach "$FLAG_NAME" prd on --detach-shared --confirmed >/dev/null 2>&1; then
  echo "detach: FAIL — --detach-shared without --org must exit non-zero (need a member to eval-verify)" >&2; fail=1
fi

# --- 9. SHARED SEGMENT ALREADY GONE: clean no-op (no version POST), still verifies → 0 -
# Distinct from test 6 (segment exists, no override row): here org-targeted itself
# is absent, so detach_from_shared early-returns before touching any env.
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if FS_SHARED_ABSENT=1 EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  if grep -qE 'POST .*/versions/' "$CURL_LOG"; then
    echo "detach: FAIL — org-targeted absent must not POST a version (clean no-op)" >&2; fail=1
  fi
  grep -q 'POST https://edge.api.flagsmith.com/api/v1/identities/' "$CURL_LOG" \
    || { echo "detach: FAIL — eval-verify must still run when org-targeted is already gone" >&2; fail=1; }
else
  echo "detach: FAIL — clean no-op (org-targeted absent) should exit 0" >&2; fail=1
fi

# --- 10. AUDIT-FAILURE ABORT (append-before-flip): audit RPC non-2xx → exit 4, no mutation -
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if AUDIT_HTTP_CODE=500 EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false \
     run_detach "$FLAG_NAME" prd on --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "detach: FAIL — audit RPC failure must abort (non-zero exit), not proceed" >&2; fail=1
else
  if grep -qE 'POST .*/versions/' "$CURL_LOG"; then
    echo "detach: FAIL — audit failure must abort BEFORE any version POST (append-before-flip)" >&2; fail=1
  fi
fi

# --- 11. value must be 'on' (off rejected: detach asserts the member stays enabled) ---
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"
if run_detach "$FLAG_NAME" prd off --detach-shared --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "detach: FAIL — --detach-shared with value 'off' must exit non-zero" >&2; fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "flag-detach-shared: ok"
