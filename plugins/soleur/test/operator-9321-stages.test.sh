#!/usr/bin/env bash
# The re-cut #9321 bootstrap, driven stage by stage against STUBBED vendors (ADR-264).
#
# knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh gives the two
# App-token release jobs a Doppler credential that reads only the two soleur-infra App values: copy
# the values into the soleur-infra-app container, prove the copy is the live App with a real RS256
# JWT, mint the read-only service token scoped to that container, store it as the infra-privileged
# environment secret DOPPLER_TOKEN_INFRA_APP, and verify with names only.
#
# NOTHING HERE TOUCHES A REAL VENDOR. doppler, gh, curl, openssl and jq are PATH shims over files
# (lib/operator-stub-world.sh) that log every call, classify it read or mutating by verb, and
# validate argv the way the vendor would. SOLEUR_OP_LIB is forced to the worktree library (the
# baked path points at the primary checkout, which gains the staged gate only after merge), stdin
# is closed, and the approvals come from the REAL approval hook minting a receipt for the exact
# command, exactly as the harness does (hook -> rewritten command -> script).
#
# Safety properties each pinned by a named row below (every one existed in the pre-ADR-264 script and
# must survive): no xtrace (exit 78); no secret on stdout and no hash of one; the token is scoped
# (read access, soleur-infra-app/prd) and stored ONLY with `gh secret set --env infra-privileged`;
# "already satisfied" is derived from VENDOR state; an interrupted mint is a recovery operation in the
# next plan; an INCONCLUSIVE read is never a pass and never produces a plan digest; repository- and
# organisation-level secret absence is checked; re-run is safe and is the rotation path (new before
# old); READY is derived from vendor state, never from the sequence of stages run.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SUITE_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_ROOT}/../.." && pwd)"
LIB="${PLUGIN_ROOT}/scripts/lib/operator-script.sh"
HOOK="${PLUGIN_ROOT}/hooks/operator-stage-approval.sh"
S="${REPO_ROOT}/knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }
check() { # <label> <rc-of-condition>
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1 (last out: $(printf '%s' "${OUT:-}" | tr '\n' ' ' | cut -c1-260))"; fi
}

for bin in jq timeout sha256sum python3; do command -v "$bin" >/dev/null 2>&1 || { printf 'HARNESS: %s is required\n' "$bin" >&2; exit 2; }; done
[[ -r "$S" && -r "$LIB" && -r "$HOOK" ]] || { printf 'HARNESS: script, library or hook missing\n' >&2; exit 2; }

SB="$(mktemp -d -t operator-9321-stages.XXXXXXXX)" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT

# shellcheck source=./lib/operator-stub-world.sh
source "${SUITE_DIR}/lib/operator-stub-world.sh"

OUT=""; RC=0
ALL_OUT="$SB/all-output.log"; : > "$ALL_OUT"
world() { # <name>
  ROOT="$SB/w-$1"; rm -rf "$ROOT"
  stub_world_init "$ROOT" >/dev/null 2>&1 || { printf 'HARNESS: stub world failed\n' >&2; exit 2; }
  : > "$ROOT/ledger.jsonl"
  CHILD_ENV=("PATH=${ROOT}/bin:${PATH}" "SOLEUR_OP_LIB=$LIB" "ENV_FILE=${ROOT}/.env" "SOLEUR_BOOTSTRAP_LEDGER=${ROOT}/ledger.jsonl"
             "STUB_ROOT=$STUB_ROOT" "STUB_LOG=$STUB_LOG" "STUB_SNAP=$STUB_SNAP" "STUB_REAL_JQ=$STUB_REAL_JQ" "XDG_STATE_HOME=$XDG_STATE_HOME")
}
run() { # <args...> — one invocation, stdin closed
  OUT="$(env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" timeout 60 bash "$S" "$@" </dev/null 2>&1)"; RC=$?
  printf '%s\n' "$OUT" >> "$ALL_OUT"
}
digest() { sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=[0-9]* digest=\([0-9a-f]*\)$/\1/p' <<<"$OUT"; }
ops() { sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=\([0-9]*\) digest=.*$/\1/p' <<<"$OUT"; }
mut() { stub_calls mutating; }
# approve <stage> [--rotate-token]: plan, then the REAL hook mints a receipt for the exact apply command,
# then the rewritten command runs (as the harness would run it). Leaves OUT/RC of the apply.
approve() {
  local stage="$1"; shift
  run --stage "$stage" "$@"
  local d; d="$(digest)"
  [[ -n "$d" ]] || { OUT="approve(): no plan digest for ${stage}: ${OUT}"; RC=99; return; }
  local cmd="bash $S --stage $stage --apply --plan-digest $d $*" in newc
  in="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},permission_mode:"default",session_id:"s",cwd:"/",hook_event_name:"PreToolUse"}')"
  newc="$(printf '%s' "$in" | env "XDG_STATE_HOME=$XDG_STATE_HOME" CLAUDE_CODE_ENTRYPOINT=cli bash "$HOOK" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
  [[ -n "$newc" ]] || { OUT="approve(): the hook minted nothing for: ${cmd}"; RC=98; return; }
  OUT="$(env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" timeout 60 bash -c "$newc" </dev/null 2>&1)"; RC=$?
  printf '%s\n' "$OUT" >> "$ALL_OUT"
}
T=$'\t'
calls_matching() { grep -cE "$1" "$STUB_LOG" || true; }
call_index() { grep -nE "$1" "$STUB_LOG" | head -1 | cut -d: -f1; }

# =============================================================================
echo "== --list and the read stages =="
world list
run --list
[[ "$RC" -eq 0 && "$(grep -c '^SOLEUR_BOOTSTRAP_STAGE_DECL ' <<<"$OUT")" -eq 5 ]] && grep -qx 'SOLEUR_BOOTSTRAP_STAGE_DECL stage=mint-and-store-token class=write' <<<"$OUT" && [[ "$(grep -c . <<<"$OUT")" -eq 5 ]]
check "--list prints exactly five STAGE_DECL lines, the last is mint-and-store-token class=write (no library, no credentials)" $?
[[ "$(awk 'END{print NR}' <<<"$OUT")" -eq 5 && "$(mut)" -eq 0 && "$(grep -c . "$STUB_LOG")" -eq 0 ]]
check "--list makes no vendor call at all" $?
run --stage preflight
[[ "$RC" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_STAGE_OK stage=preflight changed=0' <<<"$OUT" && [[ "$(mut)" -eq 0 ]]
check "preflight: exits 0 with STAGE_OK and no mutating call" $?
run
[[ "$RC" -eq 64 ]] && grep -qF 'SOLEUR_BOOTSTRAP_STAGE_REQUIRED' <<<"$OUT"
check "no --stage: exit 64 STAGE_REQUIRED (there is no run-all mode)" $?
run --stage nonexistent
[[ "$RC" -eq 64 ]] && grep -qF 'SOLEUR_BOOTSTRAP_UNKNOWN_STAGE stage=nonexistent' <<<"$OUT"
check "an undeclared stage: exit 64 UNKNOWN_STAGE" $?
run --stage preflight --yes
[[ "$RC" -ne 0 && "$(mut)" -eq 0 ]]
check "there is no --yes flag (rejected, nothing run)" $?

echo "== plan: names and booleans only, no mutating call =="
for st in copy-app-values mint-and-store-token; do
  world "plan-$st"
  if [[ "$st" == "mint-and-store-token" ]]; then cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; fi
  run --stage "$st"
  [[ "$RC" -eq 0 && "$(mut)" -eq 0 && "$(ops)" -ge 1 ]] && grep -qF "SOLEUR_BOOTSTRAP_IMPACT stage=${st} text=" <<<"$OUT" && grep -qF "SOLEUR_BOOTSTRAP_ROLLBACK stage=${st} text=" <<<"$OUT" && grep -qF 'SOLEUR_BOOTSTRAP_APPLY_COMMAND' <<<"$OUT"
  check "plan of ${st}: PLAN + IMPACT + ROLLBACK + the exact apply command, zero mutating calls" $?
done
world plan-mint-deps
run --stage mint-and-store-token
[[ "$RC" -eq 1 && "$(mut)" -eq 0 && -z "$(digest)" ]] && grep -qF 'SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=mint-and-store-token need=copy-app-values' <<<"$OUT"
check "mint plan with the copies absent: PRECONDITION_FAILED need=copy-app-values and NO digest (R10)" $?
cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; echo 401 > "$STUB_ROOT/app-code"
run --stage mint-and-store-token
[[ "$RC" -eq 1 && -z "$(digest)" ]] && grep -qF 'need=prove-live-app' <<<"$OUT"
check "mint plan while GitHub rejects the copied key: PRECONDITION_FAILED need=prove-live-app, no digest" $?
world plan-inconclusive
cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; : > "$STUB_ROOT/doppler/tokens-unreadable"
run --stage mint-and-store-token
[[ "$RC" -eq 1 && -z "$(digest)" ]] && grep -qF 'PRECONDITION_FAILED' <<<"$OUT"
check "an UNREADABLE token list is INCONCLUSIVE: no plan, no digest (never 'none')" $?
world plan-src-unreadable
rm -f "$STUB_ROOT/doppler/val/soleur-infra-privileged/GITHUB_INFRA_APP_PRIVATE_KEY"
run --stage copy-app-values
[[ "$RC" -eq 1 && -z "$(digest)" ]] && grep -qF 'PRECONDITION_FAILED stage=copy-app-values need=preflight' <<<"$OUT"
check "an unreadable SOURCE value: copy plan refuses with no digest" $?

echo "== apply without a receipt =="
world norcpt
run --stage copy-app-values; D="$(digest)"
run --stage copy-app-values --apply --plan-digest "$D"
[[ "$RC" -eq 75 && "$(mut)" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED stage=copy-app-values' <<<"$OUT"
check "--apply with no receipt: exit 75 APPROVAL_REQUIRED and ZERO mutating calls" $?
run --stage copy-app-values --apply
[[ "$RC" -eq 64 && "$(mut)" -eq 0 ]] && grep -qF 'PLAN_DIGEST_REQUIRED' <<<"$OUT"
check "--apply without --plan-digest: exit 64, nothing written" $?
env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" SOLEUR_APPROVAL_NONCE=0123456789abcdef0123456789abcdef SOLEUR_BOOTSTRAP_YES=1 CI=1 timeout 60 bash "$S" --stage copy-app-values --apply --plan-digest "$D" </dev/null > "$SB/forged.out" 2>&1; RC=$?
[[ "$RC" -eq 75 && "$(mut)" -eq 0 ]]; check "a forged nonce plus every env 'yes' is still exit 75, zero writes" $?

echo "== the full approved sequence, one stage at a time =="
world full
approve copy-app-values
[[ "$RC" -eq 0 && "$(calls_matching "^doppler${T}mutating${T}secrets set")" -eq 2 ]] && grep -qF 'STAGE_OK stage=copy-app-values changed=1 approval=harness-receipt' <<<"$OUT"
check "copy-app-values: the approved apply wrote both values (approval=harness-receipt)" $?
run --stage prove-live-app
[[ "$RC" -eq 0 ]] && grep -qF 'PASS: a JWT from the copy gets 200 from GET /app with slug=soleur-infra id=424242' <<<"$OUT"
check "prove-live-app: a real RS256 JWT flow against GET /app (stubbed GitHub) says 200 with the expected slug and id" $?
[[ "$(calls_matching "^curl${T}read${T}.*api\.github\.com/app")" -ge 1 && "$(calls_matching "^openssl${T}read${T}dgst -sha256 -binary -sign")" -ge 1 ]]
check "the JWT was signed with openssl dgst -sha256 and sent to https://api.github.com/app" $?
approve mint-and-store-token
[[ "$RC" -eq 0 ]] && grep -qF 'STAGE_OK stage=mint-and-store-token changed=1 approval=harness-receipt' <<<"$OUT"
check "mint-and-store-token: the approved apply minted, verified and stored the token" $?
run --stage verify
[[ "$RC" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_READY_FOR_PR2 repo=jikig-ai/soleur secret=DOPPLER_TOKEN_INFRA_APP environment=infra-privileged project=soleur-infra-app org_secret_list=clear' <<<"$OUT"
check "verify: READY_FOR_PR2 is printed, names only" $?
# the token was minted scoped and stored only at ENVIRONMENT level
grep -qE '^doppler	mutating	configs tokens create release-app-mint -p soleur-infra-app -c prd --access read --plain$' "$STUB_LOG"
check "the token was minted READ-ONLY, on soleur-infra-app/prd, named release-app-mint" $?
[[ "$(calls_matching "^gh${T}mutating${T}secret set")" -eq 1 ]] && grep -qE '^gh	mutating	secret set DOPPLER_TOKEN_INFRA_APP --env infra-privileged -R jikig-ai/soleur$' "$STUB_LOG"
check "the only store is gh secret set DOPPLER_TOKEN_INFRA_APP --env infra-privileged (never repository level)" $?
[[ -f "$STUB_ROOT/gh/env-secrets-infra-privileged" && ! -e "$STUB_ROOT/gh/env-secrets-REPO" ]]
check "the secret landed on the environment, not on the repository" $?
grep -qE 'tokens create.*soleur-infra-privileged' "$STUB_LOG" && fail "a token was minted on the source project" || pass "no token was ever minted on soleur-infra-privileged"

echo "== re-run is safe: a satisfied stage changes nothing and needs no approval =="
: > "$STUB_LOG"
for st in copy-app-values mint-and-store-token; do
  run --stage "$st"
  [[ "$RC" -eq 0 && "$(ops)" -eq 0 && "$(mut)" -eq 0 ]] && grep -qF "SOLEUR_BOOTSTRAP_STAGE_OK stage=${st} changed=0" <<<"$OUT"
  check "re-plan of ${st}: operations=0, STAGE_OK changed=0, no write" $?
  run --stage "$st" --apply --plan-digest "$(digest)"
  [[ "$RC" -eq 0 && "$(mut)" -eq 0 ]]; check "re-apply of ${st} with no receipt: exit 0, changed=0, no approval asked" $?
done

echo "== rotation: --rotate-token mints and stores first, revokes the old token after (new before old) =="
approve mint-and-store-token --rotate-token
[[ "$RC" -eq 0 ]] && grep -qF 'approval=harness-receipt' <<<"$OUT"
check "rotation apply succeeded with its own receipt (the receipt binds --rotate-token)" $?
MINT_I="$(call_index 'tokens create')"; STORE_I="$(call_index 'secret set DOPPLER_TOKEN_INFRA_APP')"; REVOKE_I="$(call_index 'tokens revoke')"
[[ -n "$MINT_I" && -n "$STORE_I" && -n "$REVOKE_I" && "$MINT_I" -lt "$STORE_I" && "$STORE_I" -lt "$REVOKE_I" ]]
check "order in the call log: mint < store < revoke (the old token is revoked only AFTER the new one is stored)" $?
[[ "$(wc -l < "$STUB_ROOT/doppler/tokens/soleur-infra-app")" -eq 1 ]]; check "exactly one token remains after the rotation" $?

echo "== plan drift: the state moved between the plan and the apply =="
world drift
approve copy-app-values >/dev/null 2>&1
run --stage mint-and-store-token; D="$(digest)"
cmd="bash $S --stage mint-and-store-token --apply --plan-digest $D"
in="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},permission_mode:"default",session_id:"s",cwd:"/",hook_event_name:"PreToolUse"}')"
newc="$(printf '%s' "$in" | env "XDG_STATE_HOME=$XDG_STATE_HOME" CLAUDE_CODE_ENTRYPOINT=cli bash "$HOOK" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
# an unrelated token appears at the vendor after the plan was shown and the human approved
mkdir -p "$STUB_ROOT/doppler/tokens"; printf 'slug99|release-app-mint\n' >> "$STUB_ROOT/doppler/tokens/soleur-infra-app"; : > "$STUB_LOG"
OUT="$(env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" timeout 60 bash -c "$newc" </dev/null 2>&1)"; RC=$?
[[ "$RC" -eq 75 && "$(mut)" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_PLAN_DRIFT stage=mint-and-store-token' <<<"$OUT"
check "a vendor change after the approval: PLAN_DRIFT, exit 75, zero writes" $?
ls "$XDG_STATE_HOME/soleur/approvals" | grep -qv '\.consumed$' && fail "the receipt is still live after plan drift" || pass "the receipt was burned on plan drift"

echo "== failure paths keep their safety =="
world vfail
cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; echo 'SOME_OTHER_SECRET' > "$STUB_ROOT/doppler/download-extra"
approve mint-and-store-token
[[ "$RC" -ne 0 && "$RC" -ne 75 && "$(calls_matching "^gh${T}mutating${T}secret set")" -eq 0 && "$(calls_matching "^doppler${T}mutating${T}configs tokens revoke")" -eq 1 ]]
check "a minted token that does not verify (reach too wide) is revoked and NEVER stored" $?
world sfail
cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; : > "$STUB_ROOT/gh/secret-set-fails"
approve mint-and-store-token
[[ "$RC" -ne 0 && "$RC" -ne 75 && "$(calls_matching "^doppler${T}mutating${T}configs tokens revoke")" -eq 1 ]]
check "a failed store revokes the new token (no orphan live credential)" $?
[[ ! -s "$STUB_ROOT/doppler/tokens/soleur-infra-app" ]]; check "no token is left live after the failed store" $?
world interrupted
cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; printf 'TOKEN_MINT_ATTEMPTED=2026-10-01T00:00:00Z\n' > "$ROOT/.env"
run --stage mint-and-store-token
grep -qF 'op=recover-interrupted-mint' <<<"$OUT" && [[ "$(ops)" -ge 3 ]]
check "an interrupted-mint marker appears as a recovery operation in the next plan" $?

echo "== vendor-derived 'already satisfied' =="
world lostenv
approve copy-app-values >/dev/null 2>&1; approve mint-and-store-token >/dev/null 2>&1
rm -f "$ROOT/.env"
run --stage mint-and-store-token
[[ "$(ops)" -ge 3 ]] && grep -qF 'op=revoke-token' <<<"$OUT"
check "with the local record lost, one live token is NOT assumed to be the stored one: the plan rotates (mint, store, revoke)" $?
world marker-only
cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"
printf 'TOKEN_SLUG=slug1\nTOKEN_STORED=slug1\n' > "$ROOT/.env"
run --stage mint-and-store-token
[[ "$(ops)" -ge 2 ]] && grep -qF 'op=mint-read-token' <<<"$OUT"; check "local markers with NO token at the vendor never read as satisfied" $?

echo "== INCONCLUSIVE is never a pass =="
world org
: > "$STUB_ROOT/gh/org-unreadable"
run --stage preflight
[[ "$RC" -eq 0 ]] && grep -qF 'INCONCLUSIVE: the organisation-level secret list is not readable' <<<"$OUT"
check "preflight: an unreadable organisation list is reported INCONCLUSIVE (not 'absent')" $?
echo '{"secrets":[{"name":"DOPPLER_TOKEN_INFRA_APP"}]}' > "$STUB_ROOT/gh/repo-secrets.json"; rm -f "$STUB_ROOT/gh/org-unreadable"
run --stage preflight
[[ "$RC" -eq 1 ]] && grep -qF 'FAIL: no repository-level secret named DOPPLER_TOKEN_INFRA_APP' <<<"$OUT"
check "preflight: a same-named REPOSITORY-level secret fails (it would be branch-reachable)" $?
rm -f "$STUB_ROOT/gh/repo-secrets.json"; echo '{"secrets":[{"name":"DOPPLER_TOKEN_INFRA_APP"}]}' > "$STUB_ROOT/gh/org-secrets.json"
run --stage preflight
[[ "$RC" -eq 1 ]] && grep -qF 'FAIL: no organisation-level secret named DOPPLER_TOKEN_INFRA_APP' <<<"$OUT"
check "preflight: a same-named ORGANISATION-level secret fails" $?
world ready-fresh
run --stage verify
[[ "$RC" -eq 1 ]] && ! grep -qF 'SOLEUR_BOOTSTRAP_READY_FOR_PR2' <<<"$OUT"
check "READY is derived from vendor state: verify on a fresh world fails and prints no READY marker" $?
world ready-org
approve copy-app-values >/dev/null 2>&1; approve mint-and-store-token >/dev/null 2>&1
: > "$STUB_ROOT/gh/org-unreadable"
run --stage verify
[[ "$RC" -eq 0 ]] && grep -qF 'org_secret_list=INCONCLUSIVE' <<<"$OUT"
check "READY carries org_secret_list=INCONCLUSIVE when the organisation list is unreadable" $?

echo "== no secret on stdout, no hash of one, no xtrace =="
SECRET_HASH="$(printf '%s' "$STUB_PEM_SENTINEL" | sha256sum | cut -d' ' -f1)"
ID_HASH="$(printf '%s' "$STUB_APP_ID_VALUE" | sha256sum | cut -d' ' -f1)"
! grep -qF "$STUB_PEM_SENTINEL" "$ALL_OUT" "$SB"/w-*/ledger.jsonl; check "the private-key value never appeared on any stage's stdout or in any ledger" $?
! grep -qF 'STUBTOKEN-VALUE' "$ALL_OUT" "$SB"/w-*/ledger.jsonl "$SB"/w-*/.env 2>/dev/null; check "the minted token value never appeared on stdout, in a ledger or in the recorded .env" $?
! grep -qiE "$SECRET_HASH|$ID_HASH" "$ALL_OUT" "$SB"/w-*/ledger.jsonl; check "no hash of a secret value is printed or logged" $?
! grep -qE 'SOLEUR_APPROVAL_NONCE=[0-9a-f]{32}' "$ALL_OUT" "$SB"/w-*/ledger.jsonl; check "no approval nonce reached stdout or a ledger" $?
world xtrace
OUT="$(env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" timeout 30 bash -x "$S" --stage preflight </dev/null 2>&1)"; RC=$?
[[ "$RC" -eq 78 && "$(grep -c . "$STUB_LOG")" -eq 0 ]] && grep -qF 'refusing to run under xtrace' <<<"$OUT"
check "under bash -x: exit 78 before any vendor call (no xtrace while holding a credential)" $?
OUT="$(env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" timeout 30 bash -c 'set -x; bash "$0" --stage preflight' "$S" </dev/null 2>&1)"
! grep -qF "$STUB_PEM_SENTINEL" <<<"$OUT"; check "an exported xtrace in the parent shell does not leak the key either" $?

echo "== the environment-secret census (G7d) still accepts the re-cut script =="
census_out="$(cd "$REPO_ROOT" && bash tests/scripts/test-infra-privileged-tier-census.sh 2>&1)"; census_rc=$?
if [[ "$census_rc" -eq 0 ]] && grep -qE 'G7d' <<<"$census_out"; then pass "tests/scripts/test-infra-privileged-tier-census.sh is green (G7d reads this script line by line)"; else fail "the infra-privileged census failed (rc ${census_rc}): $(grep -E 'FAIL|G7d' <<<"$census_out" | head -3 | tr '\n' ' ')"; fi
grep -qE '^GH_ENVIRONMENT="infra-privileged"$' "$S"; check "GH_ENVIRONMENT=\"infra-privileged\" stays pinned on its own line, top-level" $?
! grep -vE '^[[:space:]]*#' "$S" | grep -qE 'soleur_op_gh_secret_set|gh variable set'; check "no other store path exists in the script (no soleur_op_gh_secret_set, no gh variable set)" $?

echo "== mutation rows: each safety property goes RED when its line is broken =="
S_PRISTINE="$S"
md5_of() { md5sum "$1" | cut -d' ' -f1; }
# prop_* <script> — returns 0 when the property HOLDS for that script.
prop_no_write_without_receipt() { S="$1"; world pm1; run --stage copy-app-values; local d; d="$(digest)"; run --stage copy-app-values --apply --plan-digest "$d"; [[ "$RC" -eq 75 && "$(mut)" -eq 0 ]]; }
prop_env_level_store() { S="$1"; world pm2; approve copy-app-values >/dev/null 2>&1; approve mint-and-store-token >/dev/null 2>&1; grep -qE "^gh${T}mutating${T}secret set DOPPLER_TOKEN_INFRA_APP --env infra-privileged -R jikig-ai/soleur$" "$STUB_LOG"; }
prop_new_before_old() {
  S="$1"; world pm3; approve copy-app-values >/dev/null 2>&1; approve mint-and-store-token >/dev/null 2>&1
  approve mint-and-store-token --rotate-token >/dev/null 2>&1
  local st rv; st="$(call_index 'secret set DOPPLER_TOKEN_INFRA_APP' )"; rv="$(call_index 'tokens revoke')"
  # the SECOND store and the first revoke after it: the first revoke of the run must follow a store of the rotation
  local n_store_before_revoke; n_store_before_revoke="$(awk -v r="$rv" 'NR < r && /secret set DOPPLER_TOKEN_INFRA_APP/' "$STUB_LOG" | grep -c . || true)"
  [[ -n "$rv" && "$n_store_before_revoke" -ge 2 ]]
}
prop_no_token_on_stdout() { S="$1"; world pm4; approve copy-app-values >/dev/null 2>&1; approve mint-and-store-token >/dev/null 2>&1; ! grep -qF 'STUBTOKEN-VALUE' <<<"$OUT"; }
prop_xtrace_refused() { S="$1"; world pm5; local o rc; o="$(env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" timeout 30 bash -x "$1" --stage preflight </dev/null 2>&1)"; rc=$?; [[ "$rc" -eq 78 ]]; }
prop_ready_from_vendor_state() { S="$1"; world pm6; run --stage verify; ! grep -qF 'SOLEUR_BOOTSTRAP_READY_FOR_PR2' <<<"$OUT"; }
prop_unreadable_is_inconclusive() { S="$1"; world pm7; cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; : > "$STUB_ROOT/doppler/tokens-unreadable"; run --stage mint-and-store-token; [[ -z "$(digest)" ]]; }
prop_revoke_new_on_failed_store() { S="$1"; world pm8; cp "$STUB_ROOT/doppler/val/soleur-infra-privileged/"* "$STUB_ROOT/doppler/val/soleur-infra-app/"; : > "$STUB_ROOT/gh/secret-set-fails"; approve mint-and-store-token >/dev/null 2>&1; [[ ! -s "$STUB_ROOT/doppler/tokens/soleur-infra-app" ]]; }
mutant9321() { # <label> <property-function> ; perl on stdin
  local label="$1" prop="$2" dst prog rc
  dst="$SB/m9321-${label// /-}.sh"
  prog="$(cat)"
  cp "$S_PRISTINE" "$dst"; perl -0777 -pi -e "$prog" "$dst"
  if [[ "$(md5_of "$dst")" == "$(md5_of "$S_PRISTINE")" ]] || ! bash -n "$dst" 2>/dev/null; then fail "9321 mutation '${label}' did NOT land or does not parse"; return 0; fi
  pass "9321 mutation '${label}' landed (md5 differs from the real script; bash -n clean)"
  "$prop" "$dst"; rc=$?; S="$S_PRISTINE"
  if [[ "$rc" -eq 0 ]]; then fail "9321 mutant '${label}': property ${prop} stayed GREEN — no row sees the defect"; else pass "9321 mutant '${label}': property ${prop} went RED"; fi
}
for prop in prop_no_write_without_receipt prop_env_level_store prop_new_before_old prop_no_token_on_stdout prop_xtrace_refused prop_ready_from_vendor_state prop_unreadable_is_inconclusive prop_revoke_new_on_failed_store; do
  "$prop" "$S_PRISTINE" && pass "control: ${prop} holds on the real script" || fail "control: ${prop} does NOT hold on the real script (the mutation rows below would be meaningless)"
done
S="$S_PRISTINE"
mutant9321 "gate removed" prop_no_write_without_receipt <<'PERL'
s{\n        soleur_op_stage_gate [^\n]*\n}{\n}
PERL
mutant9321 "store at repository level" prop_env_level_store <<'PERL'
s{gh secret set "\$ENV_SECRET" --env "\$GH_ENVIRONMENT" -R "\$REPO"}{gh secret set "\$ENV_SECRET" -R "\$REPO"}
PERL
mutant9321 "old token revoked before the new one is stored" prop_new_before_old <<'PERL'
s{(  before="\$TP_SLUGS"\n)}{$1  for s in \$TP_PREV; do revoke_confirmed "\$s" \|\| return 1; done\n}
PERL
mutant9321 "the minted token is printed" prop_no_token_on_stdout <<'PERL'
s{(  \[\[ -n "\$tokval" \]\] \|\| \{ soleur_op_red "  minting failed)}{  printf 'minted=%s\\n' "\$tokval"\n$1}
PERL
mutant9321 "xtrace refusal removed" prop_xtrace_refused <<'PERL'
s{case "\$-" in\n  \*x\*\)\n    printf '\[FATAL\][^\n]*\n    exit 78\n    ;;\nesac}{:}
PERL
mutant9321 "READY printed without checking vendor state" prop_ready_from_vendor_state <<'PERL'
s{(read_verify\(\) \{\n  local names all name org="clear"\n)}{$1  printf 'SOLEUR_BOOTSTRAP_READY_FOR_PR2 repo=x\\n'\n}
PERL
mutant9321 "an unreadable token list read as none" prop_unreadable_is_inconclusive <<'PERL'
s{TP_SLUGS="\$\(token_slugs\)" \|\| return 1}{TP_SLUGS="\$(token_slugs)" \|\| true}
PERL
mutant9321 "a failed store leaves the new token live" prop_revoke_new_on_failed_store <<'PERL'
s{(      soleur_op_red "  storing \$\{ENV_SECRET\} failed; the new token was revoked)}{      :\n$1}; s{(  if ! printf '%s' "\$tokval" \| gh secret set[^\n]*\n    unset tokval\n    if )revoke_confirmed "\$new_slug"}{$1false}
PERL

# --- floor (reported directly: ADR-193) --------------------------------------------------------------
ASSERT_TOTAL=$((PASS_COUNT + FAIL_COUNT))
FLOOR=77
if [[ "$ASSERT_TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$ASSERT_TOTAL" "$FLOOR" >&2
  printf 'Total: %s assertions, %s failed\n' "$ASSERT_TOTAL" "$((FAIL_COUNT + 1))"
  exit 1
fi
echo "Total: ${ASSERT_TOTAL} assertions, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
