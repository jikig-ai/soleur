#!/usr/bin/env bash
# Guard 3 — the operator-stage approval hook (plugins/soleur/hooks/operator-stage-approval.sh, ADR-264).
#
# PROPERTY: the hook never lets a staged `--apply` command reach execution without a
# human decision, never mints a receipt for anything but ONE simple command, never
# mints under bypass mode or on a deferring invocation, never executes the script it
# fingerprints, and never breaks a call that is not a candidate.
#
# ASSEMBLY (what the hook sees): the tool (Bash, Monitor, Write, Edit, Read), every
# spelling of the script path (absolute, `cd <dir> && bash relative`, a path with a
# space, a symlink, a renamed copy carrying the v2 header, a legacy v1 copy), the
# modes (interactive, headless, bypass, dontAsk, auto, unknown, disabled by the web
# variable, resume with and without the marker), and the other hooks that may fire on
# the same call (prod-write-defer-gate rule 4, grep-rewrite).
#
# ANCHOR: the envelope keys are asserted against the payload shapes measured and
# committed in .claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md and
# UPDATED-INPUT-PAYLOAD-SHAPE.md (hookEventName rides in the SAME object as the
# decision; updatedInput REPLACES tool_input, so the whole object is copied).
#
# HARNESS: the hook's trace file must show the SUT ran for every row; a must-PASS
# non-canonical input (a path with a space) is driven; a row removes jq from PATH.
# Every mutation row is proven to LAND (md5 against the pristine hook) before it is
# asked to drive the suite red.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SUITE_DIR}/.." && pwd)"
HOOK_SRC="${PLUGIN_ROOT}/hooks/operator-stage-approval.sh"
LIB="${PLUGIN_ROOT}/scripts/lib/operator-script.sh"
TEMPLATE="${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }

for bin in jq perl md5sum python3 timeout; do
  command -v "$bin" >/dev/null 2>&1 || { printf 'HARNESS: %s is required\n' "$bin" >&2; exit 2; }
done
[[ -r "$HOOK_SRC" && -r "$LIB" && -r "$TEMPLATE" ]] || { printf 'HARNESS: hook, library or template missing\n' >&2; exit 2; }
JQ_DIR="$(dirname "$(command -v jq)")"

SB="$(mktemp -d -t operator-stage-approval-hook.XXXXXXXX)" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
mkdir -p "$SB/hooks" "$SB/scripts/lib" "$SB/mut" || { printf 'HARNESS: mkdir failed\n' >&2; exit 2; }

# shellcheck source=./lib/operator-stub-world.sh
source "${SUITE_DIR}/lib/operator-stub-world.sh"

md5_of() { md5sum "$1" | cut -d' ' -f1; }

# The hook is driven from a COPY laid out like the plugin (hooks/ beside scripts/lib/), so a
# mutation row can edit the copy without touching the repo.
cp "$HOOK_SRC" "$SB/hooks/operator-stage-approval.sh"
cp "$LIB" "$SB/scripts/lib/operator-script.sh"
HOOK="$SB/hooks/operator-stage-approval.sh"

# --- fixture scripts, generated from the template ------------------------------------------------
# A v2 script with ONE write stage whose apply makes a mutating vendor call (so the end-to-end row
# observes the write) and one read stage.
mkdir -p "$SB/fx" "$SB/fx/with space"
sed "s#__SOLEUR_OP_LIB_BAKED__#${LIB}#" "$TEMPLATE" \
  | perl -0777 -pe 's{  # \.\.\. the write goes here \(stdin for a secret, never argv\) \.\.\.}{  doppler secrets set DEMO_KEY -p demo -c prd </dev/null >/dev/null}' > "$SB/fx/bootstrap.sh"
cp "$SB/fx/bootstrap.sh" "$SB/fx/with space/bootstrap.sh"
cp "$SB/fx/bootstrap.sh" "$SB/fx/renamed-copy.sh"
ln -s "$SB/fx/bootstrap.sh" "$SB/fx/linked.sh"
sed '2s/ v2$/ v1/' "$SB/fx/bootstrap.sh" > "$SB/fx/legacy-v1.sh"
# A script whose body proves whether the hook ever EXECUTES it: it touches a canary file.
{ printf '#!/usr/bin/env bash\n# SOLEUR-GENERATED-OPERATOR-SCRIPT v2\n'
  printf 'touch "%s/canary-executed"\n' "$SB"
  printf '# SOLEUR-STAGE demo|write|If it fails nothing user-facing changes.|Delete the demo key.\n'
} > "$SB/fx/canary.sh"

# --- driver ---------------------------------------------------------------------------------------
HOOK_OUT=""; HOOK_RC=0
TRACE="$SB/trace.log"
# hook_run <json> [ENV=VAL ...]  — default env: interactive CLI, no resume marker.
hook_run() {
  local json="$1"; shift
  : > "$TRACE"
  HOOK_OUT="$(printf '%s' "$json" | env -u SOLEUR_RESUME_APPROVED_DIGEST -u SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK \
    "XDG_STATE_HOME=$XDG_STATE_HOME" "SOLEUR_OPERATOR_STAGE_APPROVAL_TRACE=$TRACE" "CLAUDE_CODE_ENTRYPOINT=cli" "$@" bash "$HOOK" 2>/dev/null)"; HOOK_RC=$?
}
# bash_json <command> [permission_mode] [cwd]
bash_json() {
  local mode="${2-default}"
  jq -nc --arg c "$1" --arg m "$mode" --arg cwd "${3:-/}" \
    '{tool_name:"Bash",tool_input:{command:$c,description:"run it",timeout:45000,run_in_background:false},permission_mode:$m,session_id:"s-1",cwd:$cwd,hook_event_name:"PreToolUse"}'
}
path_json() { # <tool> <path>
  jq -nc --arg t "$1" --arg p "$2" '{tool_name:$t,tool_input:{file_path:$p,content:"x"},permission_mode:"default",session_id:"s-1",cwd:"/",hook_event_name:"PreToolUse"}'
}
fresh_world() { stub_world_init "$SB/world-$1" >/dev/null 2>&1 || return 1; }
records() { ls -A "$XDG_STATE_HOME/soleur/approvals" 2>/dev/null | grep -vc '\.consumed$' || true; }

# A plan digest for a fixture script, taken from the SCRIPT (the way an agent gets it).
plan_digest() { # <script> <stage> — needs the stub world exported
  env "PATH=${STUB_ROOT%/stub}/bin:$PATH" "SOLEUR_OP_LIB=$LIB" "ENV_FILE=${STUB_ROOT%/stub}/.env" "SOLEUR_BOOTSTRAP_LEDGER=${STUB_ROOT%/stub}/ledger.jsonl" \
    "STUB_REAL_JQ=$STUB_REAL_JQ" bash "$1" --stage "$2" </dev/null 2>&1 | sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=[0-9]* digest=\([0-9a-f]*\)$/\1/p'
}

decision() { jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$HOOK_OUT" 2>/dev/null; }
newcmd() { jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$HOOK_OUT" 2>/dev/null; }

expect() { # <label> <condition-rc> — pass/fail by an already-evaluated test
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1 (out: $(printf '%s' "$HOOK_OUT" | cut -c1-200); trace: $(tail -n 1 "$TRACE" 2>/dev/null))"; fi
}
ran() { grep -q '^ran ' "$TRACE" 2>/dev/null; }   # the SUT ran for this row

# =============================================================================
echo "== hook: interactive mint (ask + updatedInput) =="
fresh_world a || exit 2
D="$(plan_digest "$SB/fx/bootstrap.sh" provision)"
[[ -n "$D" ]] || { fail "harness: no plan digest from the fixture script"; D="$(printf '%064d' 0)"; }
CMD="bash $SB/fx/bootstrap.sh --stage provision --apply --plan-digest $D"
hook_run "$(bash_json "$CMD")"
ran; expect "the SUT ran (trace file)" $?
[[ "$(decision)" == "ask" ]]; expect "interactive: the decision is ask (never allow)" $?
jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' <<<"$HOOK_OUT" >/dev/null 2>&1; expect "envelope: hookEventName rides in the same object as the decision" $?
N="$(newcmd)"
[[ "$N" == SOLEUR_APPROVAL_NONCE=[0-9a-f]*" bash $SB/fx/bootstrap.sh --stage provision --apply --plan-digest $D" ]]; expect "the rewritten command is the original with the nonce prefixed immediately before bash" $?
jq -e '.hookSpecificOutput.updatedInput | (.description == "run it" and .timeout == 45000 and .run_in_background == false)' <<<"$HOOK_OUT" >/dev/null 2>&1; expect "updatedInput carries the WHOLE tool_input (it replaces, it does not merge)" $?
jq -e '.hookSpecificOutput.permissionDecisionReason | (contains("If it fails: A billable resource") and contains("To undo: Delete the resource"))' <<<"$HOOK_OUT" >/dev/null 2>&1; expect "the ask reason carries the stage's plain-language impact and rollback (read statically)" $?
[[ "$(records)" -eq 1 ]]; expect "exactly one record was minted" $?
NONCE="${N#SOLEUR_APPROVAL_NONCE=}"; NONCE="${NONCE%% *}"
[[ -f "$XDG_STATE_HOME/soleur/approvals/$(printf '%s' "$NONCE" | sha256sum | cut -d' ' -f1)" ]]; expect "the record is named sha256(nonce): a listing never reveals a live nonce" $?
[[ "$(stat -c '%a' "$XDG_STATE_HOME/soleur/approvals")" == "700" ]]; expect "the receipt directory is mode 0700" $?
! grep -rqF "$NONCE" "$XDG_STATE_HOME/soleur/approvals/"; expect "the nonce itself is stored nowhere in the receipt directory" $?

echo "== hook: end to end (hook -> script) =="
# The rewritten command is shell-parsed by bash -c, exactly as the harness runs it.
OUT="$(env "PATH=${STUB_ROOT%/stub}/bin:$PATH" "SOLEUR_OP_LIB=$LIB" "ENV_FILE=${STUB_ROOT%/stub}/.env" "SOLEUR_BOOTSTRAP_LEDGER=${STUB_ROOT%/stub}/ledger.jsonl" "STUB_REAL_JQ=$STUB_REAL_JQ" timeout 30 bash -c "$N" </dev/null 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_STAGE_OK stage=provision changed=1 approval=harness-receipt' <<<"$OUT" && [[ "$(stub_calls mutating)" -eq 1 ]]
expect "the script accepted the receipt the hook minted and performed the write (rc ${rc})" $?
fresh_world a2 || exit 2
D2="$(plan_digest "$SB/fx/with space/bootstrap.sh" provision)"
CMD2="bash \"$SB/fx/with space/bootstrap.sh\" --stage provision --apply --plan-digest $D2"
hook_run "$(bash_json "$CMD2")"
N2="$(newcmd)"
[[ "$(decision)" == "ask" && -n "$N2" ]]; expect "a QUOTED path containing a space is recognised (must-PASS non-canonical input)" $?
OUT="$(env "PATH=${STUB_ROOT%/stub}/bin:$PATH" "SOLEUR_OP_LIB=$LIB" "ENV_FILE=${STUB_ROOT%/stub}/.env" "SOLEUR_BOOTSTRAP_LEDGER=${STUB_ROOT%/stub}/ledger.jsonl" "STUB_REAL_JQ=$STUB_REAL_JQ" timeout 30 bash -c "$N2" </dev/null 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && grep -qF 'approval=harness-receipt' <<<"$OUT"
expect "round trip with a quoted, spaced path: the hook's parsed argv equals the script's shell-parsed argv (rc ${rc})" $?
# cd form: the nonce goes before bash, not before cd (R3)
fresh_world a3 || exit 2
D3="$(plan_digest "$SB/fx/bootstrap.sh" provision)"
hook_run "$(bash_json "cd $SB/fx && bash bootstrap.sh --stage provision --apply --plan-digest $D3")"
N3="$(newcmd)"
[[ "$N3" == "cd $SB/fx && SOLEUR_APPROVAL_NONCE="*" bash bootstrap.sh --stage provision --apply --plan-digest $D3" ]]; expect "cd <dir> && bash <relative>: the nonce is injected before bash, not before cd" $?
OUT="$(env "PATH=${STUB_ROOT%/stub}/bin:$PATH" "SOLEUR_OP_LIB=$LIB" "ENV_FILE=${STUB_ROOT%/stub}/.env" "SOLEUR_BOOTSTRAP_LEDGER=${STUB_ROOT%/stub}/ledger.jsonl" "STUB_REAL_JQ=$STUB_REAL_JQ" timeout 30 bash -c "$N3" </dev/null 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && grep -qF 'approval=harness-receipt' <<<"$OUT"; expect "the cd form round-trips to a successful write (rc ${rc})" $?

echo "== hook: recognition is by CONTENT, never by name =="
fresh_world b || exit 2
D="$(plan_digest "$SB/fx/bootstrap.sh" provision)"
hook_run "$(bash_json "bash $SB/fx/renamed-copy.sh --stage provision --apply --plan-digest $D")"
[[ "$(decision)" == "ask" && "$(records)" -eq 1 ]]; expect "a RENAMED copy carrying the v2 header is recognised and minted for" $?
fresh_world b2 || exit 2
hook_run "$(bash_json "bash $SB/fx/legacy-v1.sh --stage provision --apply --plan-digest $D")"
[[ -z "$HOOK_OUT" && "$(records)" -eq 0 ]]; expect "a legacy v1-header copy gets NO receipt (the hook passes it through)" $?
ran; expect "the SUT ran for the v1 row" $?
fresh_world b3 || exit 2
hook_run "$(bash_json "bash $SB/fx/linked.sh --stage provision --apply --plan-digest $D")"
[[ "$(decision)" == "ask" ]]; expect "a symlinked script path is resolved and recognised" $?
fresh_world b4 || exit 2
hook_run "$(bash_json "bash $SB/fx/canary.sh --stage demo --apply --plan-digest $D")"
[[ ! -e "$SB/canary-executed" ]]; expect "the hook NEVER executes the script it fingerprints (canary file absent)" $?
[[ "$(decision)" == "ask" ]]; expect "the canary script (v2 header) is still recognised statically, from its stage lines" $?

echo "== hook: modes =="
fresh_world c || exit 2
hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=sdk-cli
[[ "$(decision)" == "defer" && "$(records)" -eq 0 && -z "$(newcmd)" ]]; expect "headless (sdk-cli): defer, and NOTHING minted on the deferring invocation" $?
hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=
[[ "$(decision)" == "defer" && "$(records)" -eq 0 ]]; expect "an undeterminable mode (empty entrypoint) emits defer, never allow" $?
hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=something-new
[[ "$(decision)" == "defer" && "$(records)" -eq 0 ]]; expect "an unknown entrypoint value emits defer" $?
# the resume marker is the binding digest of THIS command
BINDING="$(bash -c 'source "$1"; shift; soleur_approval_binding_digest "$(soleur_approval_realpath "$1")" "$2" "${@:3}"' _ "$LIB" "$SB/fx/bootstrap.sh" provision --stage provision --apply --plan-digest "$D")"
hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=sdk-cli "SOLEUR_RESUME_APPROVED_DIGEST=$BINDING"
[[ "$(decision)" == "allow" && "$(records)" -eq 1 && -n "$(newcmd)" ]]; expect "headless resume with the human-set marker equal to this command's digest: allow + rewritten command + one record" $?
fresh_world c2 || exit 2
hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=sdk-cli "SOLEUR_RESUME_APPROVED_DIGEST=$(printf '%064d' 0)"
[[ "$(decision)" == "defer" && "$(records)" -eq 0 ]]; expect "a resume marker for a DIFFERENT digest mints nothing" $?
hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=sdk-cli "SOLEUR_RESUME_APPROVED_DIGEST="
[[ "$(decision)" == "defer" && "$(records)" -eq 0 ]]; expect "an empty resume marker mints nothing" $?
for m in bypassPermissions dontAsk auto ""; do
  fresh_world "c-$m" || exit 2
  hook_run "$(bash_json "$CMD" "$m")"
  [[ "$(decision)" == "deny" && "$(records)" -eq 0 && -z "$(newcmd)" ]]; expect "permission mode '${m:-<empty>}': deny, and never mint" $?
done
for m in default acceptEdits plan; do
  fresh_world "m-$m" || exit 2
  hook_run "$(bash_json "$CMD" "$m")"
  [[ "$(decision)" == "ask" ]]; expect "permission mode '${m}': ask" $?
done
fresh_world c3 || exit 2
hook_run "$(bash_json "$CMD")" SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK=1
[[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 && "$(records)" -eq 0 ]]; expect "the web runtime opt-out (variable = 1) makes the hook a no-op for a candidate" $?
hook_run "$(bash_json "$CMD")" SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK=0
[[ "$(decision)" == "ask" ]]; expect "the opt-out only honours the exact value 1" $?

echo "== hook: input that must be refused or ignored =="
fresh_world d || exit 2
hook_run "$(bash_json "SOLEUR_APPROVAL_NONCE=0123456789abcdef0123456789abcdef $CMD")"
[[ "$(decision)" == "deny" && "$(records)" -eq 0 ]]; expect "a command that already carries the nonce variable is denied (never stripped, never honoured)" $?
hook_run "$(bash_json "ls $XDG_STATE_HOME/soleur/approvals")"
[[ "$(decision)" == "deny" ]]; expect "a Bash command touching the receipt directory is denied" $?
hook_run "$(bash_json "cat ~/.local/state/soleur/approvals/x")"
[[ "$(decision)" == "deny" ]]; expect "the receipt-directory fragment is denied even with another XDG root" $?
for t in Write Edit Read; do
  hook_run "$(path_json "$t" "$XDG_STATE_HOME/soleur/approvals/forged")"
  [[ "$(decision)" == "deny" ]]; expect "$t of a path inside the receipt directory is denied" $?
done
hook_run "$(path_json Write "$XDG_STATE_HOME/soleur/approvals/../approvals/forged")"
[[ "$(decision)" == "deny" ]]; expect "a traversal spelling of the receipt directory is canonicalized and denied" $?
mkdir -p "$SB/elsewhere"; ln -sfn "$XDG_STATE_HOME/soleur/approvals" "$SB/elsewhere/via-link"
hook_run "$(path_json Write "$SB/elsewhere/via-link/forged")"
[[ "$(decision)" == "deny" ]]; expect "a symlinked spelling of the receipt directory is canonicalized and denied" $?
hook_run "$(path_json Read "$SB/fx/bootstrap.sh")"
[[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 ]]; expect "a Read of an unrelated file is ignored" $?
for compound in "$CMD | cat" "$CMD; echo done" "$CMD && echo done" "echo \$($CMD)" "$CMD > /tmp/out" "true || $CMD" "FOO=1 $CMD"; do
  fresh_world "d-cmp" || exit 2
  hook_run "$(bash_json "$compound")"
  [[ "$(decision)" == "deny" && "$(records)" -eq 0 && -z "$(newcmd)" ]]; expect "a compound/odd form is denied with the accepted form and mints nothing: ${compound:0:30}..." $?
done
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("ONE simple command")' <<<"$HOOK_OUT" >/dev/null 2>&1; expect "the compound-command denial names the accepted form" $?
hook_run "$(bash_json "bash $SB/fx/bootstrap.sh --stage provision --apply --plan-digest $D --yes")"
[[ "$(decision)" == "deny" && "$(records)" -eq 0 ]]; expect "an unknown flag (--yes) is denied, not minted for" $?
hook_run "$(bash_json "bash $SB/fx/bootstrap.sh --stage nonexistent --apply --plan-digest $D")"
[[ "$(decision)" == "deny" ]]; expect "an undeclared stage is denied" $?
hook_run "$(bash_json "bash $SB/fx/bootstrap.sh --stage provision --apply --plan-digest notahexdigest")"
[[ "$(decision)" == "deny" ]]; expect "a malformed plan digest is denied" $?
hook_run "$(bash_json "bash $SB/fx/bootstrap.sh --stage account --apply --plan-digest $D")"
[[ -z "$HOOK_OUT" && "$(records)" -eq 0 ]]; expect "--apply on a READ stage mints nothing (nothing to approve)" $?
hook_run "$(bash_json "bash $SB/fx/bootstrap.sh --list")"
[[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 ]]; ran; expect "--list returns no decision (not a candidate)" $?
hook_run "$(bash_json "bash \"$SB/fx/with space/bootstrap.sh\" --list")"
[[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 ]]; expect "--list with a spaced path returns no decision" $?
hook_run "$(bash_json "ls -la")"
[[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 ]]; ran; expect "an unrelated Bash call: no output, exit 0, and the SUT ran" $?
hook_run "$(bash_json "bash /x/flip.sh --apply")"
[[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 ]]; expect "a prod-write-defer-gate rule 4 script (flip.sh --apply) is not this hook's: pass-through" $?
hook_run "$(bash_json "bash /x/flip.sh --apply && $CMD")"
[[ "$(decision)" == "deny" && "$(records)" -eq 0 ]]; expect "a command matching this hook AND rule 4 resolves to the strongest verdict (deny > ask > defer): denied, nothing minted" $?
hook_run "$(jq -nc '{tool_name:"Monitor",tool_input:{command:"tail -f /var/log/x"},permission_mode:"default",session_id:"s",cwd:"/"}')"
[[ -z "$HOOK_OUT" ]]; expect "a Monitor call that is not a candidate is ignored" $?

echo "== hook: jq absent =="
mkdir -p "$SB/nojq"
# a PATH with every tool EXCEPT jq: symlink the ones the hook and the shell need
for t in bash cat grep sed head cut tr date mv chmod mkdir id stat od readlink printenv dirname basename env rm sha256sum timeout ls; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$SB/nojq/$t"
done
: > "$TRACE"
HOOK_OUT="$(printf '%s' "$(bash_json "ls -la")" | env -u SOLEUR_RESUME_APPROVED_DIGEST "PATH=$SB/nojq" "XDG_STATE_HOME=$XDG_STATE_HOME" "SOLEUR_OPERATOR_STAGE_APPROVAL_TRACE=$TRACE" CLAUDE_CODE_ENTRYPOINT=cli "$SB/nojq/bash" "$HOOK" 2>/dev/null)"; HOOK_RC=$?
[[ -z "$HOOK_OUT" && "$HOOK_RC" -eq 0 ]]; expect "no jq + a NON-candidate: returns at once with no output (a missing jq cannot brick unrelated calls)" $?
HOOK_OUT="$(printf '%s' "$(bash_json "$CMD")" | env -u SOLEUR_RESUME_APPROVED_DIGEST "PATH=$SB/nojq" "XDG_STATE_HOME=$XDG_STATE_HOME" "SOLEUR_OPERATOR_STAGE_APPROVAL_TRACE=$TRACE" CLAUDE_CODE_ENTRYPOINT=cli "$SB/nojq/bash" "$HOOK" 2>/dev/null)"; HOOK_RC=$?
grep -q '"permissionDecision":"deny"' <<<"$HOOK_OUT" && [[ "$HOOK_RC" -eq 0 ]]; expect "no jq + a CANDIDATE: a fixed deny envelope (fails closed only for candidates)" $?

echo "== hook: mutation rows =="
mutate_hook() { # <label> <dst> ; perl program on stdin
  local label="$1" dst="$SB/mut/hooks/operator-stage-approval.sh" prog
  prog="$(cat)"
  rm -rf "$SB/mut"; mkdir -p "$SB/mut/hooks" "$SB/mut/scripts/lib"
  cp "$LIB" "$SB/mut/scripts/lib/operator-script.sh"
  cp "$HOOK_SRC" "$dst"
  perl -0777 -pi -e "$prog" "$dst"
  if [[ "$(md5_of "$dst")" == "$(md5_of "$HOOK_SRC")" ]]; then fail "mutation '${label}' did NOT land (md5 identical to the pristine hook)"; return 1; fi
  bash -n "$dst" 2>/dev/null || { fail "mutation '${label}' fails bash -n"; return 1; }
  pass "mutation '${label}' landed (md5 differs from the pristine hook; bash -n clean)"
}
# mrow <label> <test-snippet-name> ; runs the named row against the mutated hook and requires it to FAIL.
HOOK_PRISTINE="$HOOK"
row_headless_no_mint() { # defer must mint nothing
  fresh_world "mr-h-$RANDOM" || return 0
  hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=sdk-cli
  [[ "$(decision)" == "defer" && "$(records)" -eq 0 ]]
}
row_bypass_denied() {
  fresh_world "mr-b-$RANDOM" || return 0
  hook_run "$(bash_json "$CMD" bypassPermissions)"
  [[ "$(decision)" == "deny" && "$(records)" -eq 0 ]]
}
row_undetermined_defer() {
  fresh_world "mr-u-$RANDOM" || return 0
  hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=
  [[ "$(decision)" == "defer" ]]
}
row_renamed_minted_v1_not() {
  fresh_world "mr-r-$RANDOM" || return 0
  hook_run "$(bash_json "bash $SB/fx/renamed-copy.sh --stage provision --apply --plan-digest $D")"
  local a; a="$(decision)"
  fresh_world "mr-r2-$RANDOM" || return 0
  hook_run "$(bash_json "bash $SB/fx/legacy-v1.sh --stage provision --apply --plan-digest $D")"
  [[ "$a" == "ask" && -z "$HOOK_OUT" ]]
}
row_nonce_denied() {
  fresh_world "mr-n-$RANDOM" || return 0
  hook_run "$(bash_json "SOLEUR_APPROVAL_NONCE=0123456789abcdef0123456789abcdef $CMD")"
  [[ "$(decision)" == "deny" ]]
}
row_compound_no_mint() {
  fresh_world "mr-c-$RANDOM" || return 0
  hook_run "$(bash_json "$CMD | cat")"
  [[ "$(decision)" == "deny" && "$(records)" -eq 0 ]]
}
row_cd_before_bash() {
  fresh_world "mr-cd-$RANDOM" || return 0
  hook_run "$(bash_json "cd $SB/fx && bash bootstrap.sh --stage provision --apply --plan-digest $D")"
  [[ "$(newcmd)" == "cd $SB/fx && SOLEUR_APPROVAL_NONCE="* ]]
}
row_resume_marker_exact() {
  fresh_world "mr-m-$RANDOM" || return 0
  hook_run "$(bash_json "$CMD")" CLAUDE_CODE_ENTRYPOINT=sdk-cli "SOLEUR_RESUME_APPROVED_DIGEST=$(printf '%064d' 0)"
  [[ "$(decision)" == "defer" && "$(records)" -eq 0 ]]
}
row_noncandidate_nojq() {
  : > "$TRACE"
  local o; o="$(printf '%s' "$(bash_json "ls -la")" | env "PATH=$SB/nojq" "XDG_STATE_HOME=$XDG_STATE_HOME" CLAUDE_CODE_ENTRYPOINT=cli "$SB/nojq/bash" "$HOOK" 2>/dev/null)"
  [[ -z "$o" ]]
}
row_never_executes() {
  rm -f "$SB/canary-executed"
  fresh_world "mr-x-$RANDOM" || return 0
  hook_run "$(bash_json "bash $SB/fx/canary.sh --stage demo --apply --plan-digest $D")"
  [[ ! -e "$SB/canary-executed" ]]
}
row_deny_beats_rule4() {
  fresh_world "mr-d-$RANDOM" || return 0
  hook_run "$(bash_json "bash /x/flip.sh --apply && $CMD")"
  [[ "$(decision)" == "deny" && "$(records)" -eq 0 ]]
}
# a mutated hook must make its row FAIL (the row passing on the mutant means the suite does not see the defect)
mutant_row() { # <label> <row-function> ; mutation on stdin
  local label="$1" row="$2"
  mutate_hook "$label" || return 0
  HOOK="$SB/mut/hooks/operator-stage-approval.sh"
  if "$row"; then fail "hook mutant '${label}': the row '${row}' stayed GREEN — the suite does not see it"; else pass "hook mutant '${label}': row '${row}' went RED"; fi
  HOOK="$HOOK_PRISTINE"
}
mutant_row "h1 fingerprint keyed on the basename / v1 accepted" row_renamed_minted_v1_not <<'PERL'
s{head -n 3 "\$1" 2>/dev/null \| grep -aq '\^\# SOLEUR-GENERATED-OPERATOR-SCRIPT v2\$'}{head -n 3 "\$1" 2>/dev/null | grep -aq 'SOLEUR-GENERATED-OPERATOR-SCRIPT v[12]'}
PERL
mutant_row "h2 undeterminable mode emits allow instead of defer" row_undetermined_defer <<'PERL'
s{trace "ran verdict=defer reason=headless-no-marker stage=\$\{STAGE\}"\nemit_envelope defer}{trace "ran verdict=defer reason=headless-no-marker stage=\$\{STAGE\}"\nemit_envelope allow}
PERL
mutant_row "h3 mints on the deferring headless invocation" row_headless_no_mint <<'PERL'
s{(trace "ran verdict=defer reason=headless-no-marker stage=\$\{STAGE\}"\n)}{NONCE="\$(soleur_approval_mint "\$BINDING" "\$SESSION")"\n$1}
PERL
mutant_row "h4 mints under bypass mode" row_bypass_denied <<'PERL'
s{default\|acceptEdits\|plan\) ;;}{default|acceptEdits|plan|bypassPermissions) ;;}
PERL
mutant_row "h5 strips instead of denies an input carrying the nonce" row_nonce_denied <<'PERL'
s{\*SOLEUR_APPROVAL_NONCE\*\)\n    emit_deny "That command carries an approval token[^\n]*\n}{*SOLEUR_APPROVAL_NONCE*)\n    COMMAND="\$(printf '%s' "\$COMMAND" | sed -E 's/SOLEUR_APPROVAL_NONCE=[0-9a-f]+ //')" ;;\n}
PERL
mutant_row "h6 a compound command mints" row_compound_no_mint <<'PERL'
s{if ! tokenize "\$COMMAND"; then}{if ! tokenize "\$\{COMMAND%%|*\}"; then}
PERL
mutant_row "h7 nonce injected before cd instead of before bash" row_cd_before_bash <<'PERL'
s{new="\$\{COMMAND:0:BASH_OFFSET\}SOLEUR_APPROVAL_NONCE=\$\{nonce\} \$\{COMMAND:BASH_OFFSET\}"}{new="SOLEUR_APPROVAL_NONCE=\$\{nonce\} \$\{COMMAND\}"}
PERL
mutant_row "h8 resume marker not compared" row_resume_marker_exact <<'PERL'
s{\[\[ -n "\$\{SOLEUR_RESUME_APPROVED_DIGEST:-\}" && "\$\{SOLEUR_RESUME_APPROVED_DIGEST\}" == "\$BINDING" \]\]}{[[ -n "\${SOLEUR_RESUME_APPROVED_DIGEST:-}" ]]}
PERL
mutant_row "h9 fails closed on a non-candidate when jq is missing" row_noncandidate_nojq <<'PERL'
s{case "\$INPUT" in\n  \*--apply\*\|\*SOLEUR_APPROVAL_NONCE\*\|\*"\$approvals_fragment"\*\) candidate=1 ;;\nesac}{candidate=1}
PERL
mutant_row "h10 a command matching this hook and rule 4 resolves weaker than deny" row_deny_beats_rule4 <<'PERL'
s{      emit_deny "That is a staged Soleur operator-script apply in a form Soleur cannot ask the person about\. Issue it as \$\{ACCEPTED_FORM\}\. Nothing was changed\." "compound-command"\n    fi\n    trace "ran verdict=noop reason=extra-and-no-v2-script"}{      trace "ran verdict=noop reason=weakened"\n      exit 0\n    fi\n    trace "ran verdict=noop reason=extra-and-no-v2-script"}
PERL
mutant_row "h11 executes the script (--list) from the hook" row_never_executes <<'PERL'
s{(REAL="\$\(soleur_approval_realpath "\$SCRIPT_PATH"\)"\n)}{$1bash "\$REAL" --list >/dev/null 2>\&1 </dev/null\n}
PERL

# --- floors: the instrument must be able to see both outcomes (reported directly, ADR-193) -------
ASSERT_TOTAL=$((PASS_COUNT + FAIL_COUNT))
FLOOR=87
if [[ "$ASSERT_TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$ASSERT_TOTAL" "$FLOOR" >&2
  printf 'Total: %s assertions, %s failed\n' "$ASSERT_TOTAL" "$((FAIL_COUNT + 1))"
  exit 1
fi
echo "Total: ${ASSERT_TOTAL} assertions, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
