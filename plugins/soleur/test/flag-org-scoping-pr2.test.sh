#!/usr/bin/env bash
# Tests for #4581 PR-2 — per-feature-segment org scoping (gaps 1+2+3):
#   1. create.sh --flagsmith-only (gap 1): create the Flagsmith feature only,
#      skipping the server.ts/.env.example/Doppler mutations + the "already
#      code-wired" exit-1 precheck.
#   2. provision_feature_segment <flag> (gap 2): idempotent create of <flag>-orgs
#      segment + ON feature-state override in BOTH envs.
#   3. flip.sh --org reshape (gaps 2/3): target <flag>-orgs (NOT the shared
#      org-targeted segment) + evaluation-layer re-verify (positive target +
#      control-negative) + empty-membership eval=false.
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
CREATE="$REPO_ROOT/plugins/soleur/skills/flag-create/scripts/create.sh"
FLIP="$REPO_ROOT/plugins/soleur/skills/flag-set-role/scripts/flip.sh"
fail=0

# Shared stub for `doppler`: `secrets get` returns canned values; `secrets set`
# is recorded to $DOPPLER_SET_LOG so a test can assert no mirror write happened.
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

# --- Section 1: create.sh --flagsmith-only ---------------------------------
# curl stub: audit RPC -> uuid+200; feature lookup -> not-found; feature POST -> id.
# Every invocation is logged to $CURL_LOG (URL only) for create-happened assertion.
make_create_curl_stub() { # $1=dir
  cat > "$1/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
echo "$url" >> "${CURL_LOG:-/dev/null}"
if [[ "$url" == *"/rpc/audit_flag_flip"* ]]; then
  printf '%s\n%s' '"11111111-1111-1111-1111-111111111111"' '200'; exit 0
fi
if [[ "$url" == *"/features/?q="* ]]; then echo '{"results":[]}'; exit 0; fi
if [[ "$url" == *"/features/"* ]];   then echo '{"id":12345}';   exit 0; fi
echo '{}'; exit 0
STUB
  chmod +x "$1/curl"
}

S1_STUB="$(mktemp -d)"; trap 'rm -rf "$S1_STUB"' EXIT
make_doppler_stub "$S1_STUB"
make_create_curl_stub "$S1_STUB"

run_create() { # runs create.sh in an EMPTY dir (no server.ts/.env.example).
  local rundir; rundir="$(mktemp -d)"
  ( cd "$rundir" \
    && echo yes | PATH="$S1_STUB:$PATH" \
         CURL_LOG="$CURL_LOG" DOPPLER_SET_LOG="$DOPPLER_SET_LOG" \
         bash "$CREATE" "$@" )
}

# 1a. NEGATIVE CONTROL: without --flagsmith-only, an empty dir (no server.ts)
#     must fail (missing file / precheck) — proves the flag is the lever.
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"
if run_create byok-delegations >/dev/null 2>&1; then
  echo "pr2: FAIL — create.sh without --flagsmith-only should fail in a dir lacking server.ts" >&2; fail=1
fi

# 1b. --flagsmith-only from an empty dir -> exit 0 (no server.ts/.env needed).
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"
if run_create byok-delegations --flagsmith-only >/dev/null 2>&1; then
  : # ok
else
  echo "pr2: FAIL — create.sh --flagsmith-only should exit 0 without touching server.ts" >&2; fail=1
fi

# 1c. --flagsmith-only must NOT mirror Doppler (no `secrets set`).
if grep -q '^set:' "$DOPPLER_SET_LOG" 2>/dev/null; then
  echo "pr2: FAIL — --flagsmith-only wrote Doppler ($(cat "$DOPPLER_SET_LOG"))" >&2; fail=1
fi

# 1d. --flagsmith-only DID create the Flagsmith feature (POST /features/).
if ! grep -q '/features/$' "$CURL_LOG" 2>/dev/null; then
  echo "pr2: FAIL — --flagsmith-only did not POST the Flagsmith feature (curl log: $(cat "$CURL_LOG"))" >&2; fail=1
fi

# --- Section 2+3: flip.sh --org reshape (provision <flag>-orgs + eval-verify) ---
# Stateless Flagsmith stub covering every endpoint the reshaped org path hits.
# Eval (/identities/) returns enabled per EVAL_TARGET_ENABLED / EVAL_CONTROL_ENABLED,
# keyed on which org UUID appears in the request body — so a test can simulate a
# control-org leak and assert the script fails loud.
TARGET_ORG_FULL="70a70ab0-0000-0000-0000-000000000001"
CONTROL_ORG_FULL="1a8045bf-0000-0000-0000-000000000002"
FLAG_NAME="byok-delegations"

make_flip_curl_stub() { # $1=dir
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
    printf '%s\n%s' '"11111111-1111-1111-1111-111111111111"' '200'; exit 0 ;;
  *"/identities/"*)
    # edge eval: emits body + '\n<http_code>' (matches curl -w). enabled keyed on
    # which org is in the body + the test's knobs; EVAL_HTTP_CODE simulates errors.
    en="false"
    if [[ "$data" == *"$TARGET_ORG_FULL"* ]];  then en="${EVAL_TARGET_ENABLED:-false}"; fi
    if [[ "$data" == *"$CONTROL_ORG_FULL"* ]]; then en="${EVAL_CONTROL_ENABLED:-false}"; fi
    printf '{"flags":[{"feature":{"name":"%s"},"enabled":%s}],"traits":[]}\n%s' "$FLAG_NAME" "$en" "${EVAL_HTTP_CODE:-200}"
    exit 0 ;;
  *"/features/?q="*)
    printf '{"results":[{"id":777,"name":"%s"}]}' "$FLAG_NAME"; exit 0 ;;
  *"/segments/")
    if [[ "$method" == "POST" ]]; then echo '{"id":888,"name":"created"}'
    else echo '{"results":[]}'; fi   # list: <flag>-orgs absent -> provision creates it
    exit 0 ;;
  *"/segments/"*[0-9]"/"|*"/segments/"*[0-9])
    if [[ "$method" == "PUT" ]]; then echo '{"id":888}'
    else echo '{"id":888,"rules":[{"type":"ALL","rules":[{"type":"ANY","rules":[],"conditions":[]}],"conditions":[]}]}'; fi
    exit 0 ;;
  *"/featurestates/"*) echo '[]'; exit 0 ;;          # read_segment_state -> missing
  *"/versions/"*)
    if [[ "$method" == "POST" ]]; then echo '{"uuid":"v-uuid"}'
    else echo '{"results":[{"uuid":"v-uuid","is_live":true}]}'; fi
    exit 0 ;;
  *"/feature-segments/"*) echo '{"results":[]}'; exit 0 ;;  # no existing override row
  *) echo '{}'; exit 0 ;;
esac
STUB
  chmod +x "$1/curl"
}

S2_STUB="$(mktemp -d)"
make_doppler_stub "$S2_STUB"
make_flip_curl_stub "$S2_STUB"
OLD_TRAP_DIR="$S1_STUB"
trap 'rm -rf "$S1_STUB" "$S2_STUB"' EXIT

run_flip() { # env knobs come from caller; runs from repo root (FLAG_ENV_VARS resolution)
  # EVAL_POLL_SLEEP=0 / fewer tries keeps the no-match (silent-leak) paths fast.
  ( cd "$REPO_ROOT" \
    && PATH="$S2_STUB:$PATH" CURL_LOG="$CURL_LOG" DOPPLER_SET_LOG="$DOPPLER_SET_LOG" \
       TARGET_ORG_FULL="$TARGET_ORG_FULL" CONTROL_ORG_FULL="$CONTROL_ORG_FULL" FLAG_NAME="$FLAG_NAME" \
       EVAL_POLL_SLEEP=0 EVAL_POLL_TRIES=2 \
       bash "$FLIP" "$@" )
}

# 2a. Source-level: org branch must target the per-feature <flag>-orgs segment
#     and provision it — NOT the shared org-targeted segment.
if ! grep -q 'provision_feature_segment' "$FLIP"; then
  echo "pr2: FAIL — flip.sh lacks provision_feature_segment" >&2; fail=1
fi
if grep -q 'resolve_segment_id "org-targeted"' "$FLIP"; then
  echo "pr2: FAIL — flip.sh --org still resolves the shared org-targeted segment" >&2; fail=1
fi
if ! grep -qE '\$\{?FLAG\}?-orgs|\$FLAG-orgs' "$FLIP"; then
  echo "pr2: FAIL — flip.sh does not reference the <flag>-orgs per-feature segment" >&2; fail=1
fi
# eval-layer re-verify against the edge identities endpoint (per ADR-043 identity model)
if ! grep -q 'edge.api.flagsmith.com' "$FLIP"; then
  echo "pr2: FAIL — flip.sh eval-verify must hit the edge identities endpoint" >&2; fail=1
fi

# 2b. POSITIVE: on --org <target>, eval true for target / false for control -> exit 0,
#     and the eval (/identities/) + segment POST (provision) actually happened.
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false \
     run_flip "$FLAG_NAME" prd on --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  grep -q 'POST https://edge.api.flagsmith.com/api/v1/identities/' "$CURL_LOG" \
    || { echo "pr2: FAIL — eval-verify did not POST the edge identities endpoint" >&2; fail=1; }
  grep -q 'POST .*/segments/$' "$CURL_LOG" \
    || { echo "pr2: FAIL — provision did not POST a per-feature segment" >&2; fail=1; }
else
  echo "pr2: FAIL — on --org with target-enabled/control-disabled should exit 0" >&2; fail=1
fi

# 2c. CONTROL-LEAK (gate-present test): if the flag also evaluates enabled for the
#     control org, the script MUST fail loud (the FR8 control-negative assertion).
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=true \
     run_flip "$FLAG_NAME" prd on --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "pr2: FAIL — control-org leak (eval true for control) must fail loud, not exit 0" >&2; fail=1
fi

# 2d. POSITIVE off-case + empty-membership semantics: off --org <target> with the
#     flag evaluating OFF for the target -> exit 0 (eval=false is the expected state).
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"
if ! EVAL_TARGET_ENABLED=false EVAL_CONTROL_ENABLED=false \
       run_flip "$FLAG_NAME" prd off --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
       >/dev/null 2>&1; then
  echo "pr2: FAIL — off --org with eval=false target should exit 0" >&2; fail=1
fi

# 2e. SILENT-LEAK guard (gate-present): on --org but the flag does NOT actually
#     evaluate enabled for the target (override missing / one-env-only) -> fail loud.
#     Membership-set equality alone would pass here; eval-verify must catch it.
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=false EVAL_CONTROL_ENABLED=false \
     run_flip "$FLAG_NAME" prd on --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "pr2: FAIL — on --org with target NOT enabled must fail loud (silent-leak guard)" >&2; fail=1
fi

# 2f. FAIL-OPEN guard: an edge eval HTTP error must NOT be read as "disabled" and pass
#     the verify — the gate must fail loud (exit non-zero). Without the HTTP-2xx check,
#     curl -sS exits 0 on a 5xx and the parser's flag-absent fall-through returns
#     "false", silently passing the control-negative + off assertions.
CURL_LOG="$(mktemp)"; DOPPLER_SET_LOG="$(mktemp)"
if EVAL_TARGET_ENABLED=true EVAL_CONTROL_ENABLED=false EVAL_HTTP_CODE=500 \
     run_flip "$FLAG_NAME" prd on --org "$TARGET_ORG_FULL" --control-org "$CONTROL_ORG_FULL" --confirmed \
     >/dev/null 2>&1; then
  echo "pr2: FAIL — edge eval HTTP 500 must fail loud (no fail-open), not exit 0" >&2; fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "flag-org-scoping-pr2: ok"
