#!/usr/bin/env bash
# Tests for run-health-emit.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/run-health-emit.sh"

TMP="$(mktemp -d -t runhealth.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0; fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; return 0; }

# Drive pass and fail once, then restore the counters. A subshell makes a
# later use of those names look lost.
instrument_self_test() {
  local before_p="$passes" before_f="$fails" dp df
  pass "instrument-pass" >/dev/null
  fail "instrument-fail" >/dev/null
  dp=$((passes - before_p))
  df=$((fails - before_f))
  passes=$before_p
  fails=$before_f
  [[ "$dp" -eq 1 && "$df" -eq 1 ]]
}
instrument_self_test || { echo "instrument self-test failed" >&2; exit 1; }

# A producer call is a command-position bash line: optional indent, the script
# name, and a --seal token. A prose sentence that names those words is not a call.
producer_call() {
  local -a files=("$@")
  local f line found
  [[ "${#files[@]}" -eq 0 ]] && return 1
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || return 1
    found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*bash[[:space:]] ]] \
        && [[ "$line" == *run-health-emit.sh* ]] \
        && [[ "$line" =~ (^|[[:space:]])--seal([[:space:]]|$) ]]; then
        found=1
        break
      fi
    done < "$f"
    [[ "$found" -eq 1 ]] || return 1
  done
  return 0
}

# Case 1: creates run_health.json with required fields
RD="$TMP/run1"
printf 'prompt text' > "$TMP/p.md"
bash "$SUT" --run-dir "$RD" --run-id r1 --issue 12573 --branch b --harness opencode --phase 0 --status started --prompt-file "$TMP/p.md"
if [[ -f "$RD/run_health.json" ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); v=d.get('schema_version'); sys.exit(0 if type(v) is int and v==1 and d['run_id']=='r1' and d['issue']=='12573' and len(d['phases'])==1 else 1)" "$RD/run_health.json"; then
  pass "creates run_health.json with schema_version 1"
else
  fail "creates run_health.json with schema_version 1"
fi

# Case 2: idempotent upsert (same phase updates, no duplicate)
bash "$SUT" --run-dir "$RD" --phase 0 --status completed
N=$(python3 -c "import json; print(len(json.load(open('$RD/run_health.json'))['phases']))")
if [[ "$N" == "1" ]]; then pass "idempotent upsert (no duplicate phase)"; else fail "idempotent upsert" "got $N"; fi

# Case 3: prompt snapshot created and not overwritten on retry
if [[ -f "$RD/phase_prompts/0.md" ]] && grep -q "prompt text" "$RD/phase_prompts/0.md"; then
  pass "prompt snapshot created"
else
  fail "prompt snapshot created"
fi

# Case 4: retry creates attempt-2 file, preserves original
printf 'retry prompt' > "$TMP/p2.md"
bash "$SUT" --run-dir "$RD" --phase 0 --status started --prompt-file "$TMP/p2.md"
if [[ -f "$RD/phase_prompts/0.attempt-2.md" ]] && grep -q "retry prompt" "$RD/phase_prompts/0.attempt-2.md" && grep -q "prompt text" "$RD/phase_prompts/0.md"; then
  pass "retry preserves original snapshot"
else
  fail "retry preserves original snapshot"
fi

# Case 5: missing required args exits 0 (non-fatal)
bash "$SUT" --run-dir "$RD" 2>/dev/null; rc=$?
if [[ "$rc" == "0" ]]; then pass "missing args non-fatal"; else fail "missing args non-fatal" "rc=$rc"; fi

# Case 6: phase 8 completed without --seal does not seal
S6="$TMP/run-noseal"
bash "$SUT" --run-dir "$S6" --phase 8 --status completed --prompt-file "$TMP/p.md" 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('sealed') is False and 'completed_at' not in d else 1)" "$S6/run_health.json" 2>/dev/null; then
  pass "phase 8 without --seal does not seal"
else
  fail "phase 8 without --seal does not seal"
fi

# Case 7: --seal with a phase sets the terminal status and a later upsert keeps it
S7="$TMP/run-seal"
bash "$SUT" --run-dir "$S7" --phase exit --status failed --seal 2>/dev/null
bash "$SUT" --run-dir "$S7" --phase later --status completed 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('sealed') is True and d.get('status')=='failed' and d.get('completed_at') else 1)" "$S7/run_health.json" 2>/dev/null; then
  pass "seal stays sealed across a later upsert"
else
  fail "seal stays sealed across a later upsert"
fi

# Case 8: --seal before any phase row, then a phase upsert, stays sealed
S8="$TMP/run-seal-first"
bash "$SUT" --run-dir "$S8" --status failed --seal 2>/dev/null
bash "$SUT" --run-dir "$S8" --phase later --status completed 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('sealed') is True and d.get('status')=='failed' else 1)" "$S8/run_health.json" 2>/dev/null; then
  pass "seal before any phase stays sealed"
else
  fail "seal before any phase stays sealed"
fi

# Case 9: --seal with no --phase leaves phases empty
S9="$TMP/run-seal-nophase"
bash "$SUT" --run-dir "$S9" --status failed --seal 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('sealed') is True and d.get('status')=='failed' and d.get('phases')==[] else 1)" "$S9/run_health.json" 2>/dev/null; then
  pass "seal with no phase leaves phases empty"
else
  fail "seal with no phase leaves phases empty"
fi

# Case 10: goto_count is full lines `verb: goto`; a missing file is 0
printf '%s\n' 'verb: goto' 'the compact marker is verb=goto and does not count' 'verb: goto' > "$TMP/session-state.md"
S10="$TMP/run-goto"
bash "$SUT" --run-dir "$S10" --status completed --seal --session-state "$TMP/session-state.md" 2>/dev/null
S10b="$TMP/run-goto-missing"
bash "$SUT" --run-dir "$S10b" --status completed --seal --session-state "$TMP/no-such-session-state.md" >"$TMP/goto-missing.out" 2>"$TMP/goto-missing.err"; rc=$?
if [[ "$rc" == "0" ]] && grep -q 'run-health-emit:' "$TMP/goto-missing.err" && python3 -c "import json,sys; a=json.load(open(sys.argv[1])); b=json.load(open(sys.argv[2])); sys.exit(0 if a.get('goto_count')==2 and b.get('goto_count')==0 else 1)" "$S10/run_health.json" "$S10b/run_health.json" 2>/dev/null; then
  pass "goto_count counts full verb: goto lines"
else
  fail "goto_count counts full verb: goto lines"
fi

# Case 11: --import-tally stores the PATH stub's stdout
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/pipeline-tally.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'tally: seats=3 ci_cycles=1 fix_rounds=0 agent_rounds=2 ci_wall_s=unmeasured'
EOF
chmod +x "$BIN/pipeline-tally.sh"
S11="$TMP/run-tally"
PATH="$BIN:$PATH" bash "$SUT" --run-dir "$S11" --status completed --seal --import-tally 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'tally: seats=3 ci_cycles=1 fix_rounds=0 agent_rounds=2 ci_wall_s=unmeasured' in d.get('tally_show','') else 1)" "$S11/run_health.json" 2>/dev/null; then
  pass "import-tally stores stub stdout"
else
  fail "import-tally stores stub stdout"
fi

# Case 12: refused phase tokens exit 0, print the prefix, and create nothing
refuse_phase() {
  local token="$1" label="$2" dest err rc
  dest="$TMP/refuse-${label}"
  err="$TMP/refuse-${label}.err"
  bash "$SUT" --run-dir "$dest" --phase "$token" --status started >"$TMP/refuse-${label}.out" 2>"$err"; rc=$?
  if [[ "$rc" == "0" && ! -e "$dest" ]] && grep -q 'run-health-emit:' "$err"; then
    pass "refuses phase ${label}"
  else
    fail "refuses phase ${label}" "rc=$rc exists=$([[ -e "$dest" ]] && echo yes || echo no)"
  fi
}
refuse_phase '../x' 'dotdot-slash'
refuse_phase '..' 'dotdot'
refuse_phase '.' 'dot'
refuse_phase 'a..b' 'embedded-dotdot'
refuse_phase 'a/b' 'slash'

# Case 13: producer skills. Empty list and a prose sentence are not calls.
REPO="$(git -C "$DIR" rev-parse --show-toplevel)"
PROSE="$TMP/prose-skill.md"
printf '%s\n' '**Run health.** After step 0d and on every return path, read the schema and run its `bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh"` lines, including `--seal`.' > "$PROSE"
CALL="$TMP/call-skill.md"
# shellcheck disable=SC2016 # the fixture line is literal text, not this shell's expansion
printf '%s\n' 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" --status completed --seal' > "$CALL"
if producer_call; then
  fail "empty producer array is not a call"
else
  pass "empty producer array is not a call"
fi
if producer_call "$PROSE"; then
  fail "prose sentence is not a producer call"
else
  pass "prose sentence is not a producer call"
fi
if producer_call "$CALL"; then
  pass "bash line with --seal is a producer call"
else
  fail "bash line with --seal is a producer call"
fi
SCHEMA="$REPO/plugins/soleur/skills/one-shot/references/run-health-schema.md"
TFL="$REPO/plugins/soleur/skills/test-fix-loop/SKILL.md"
if producer_call "$TFL" "$SCHEMA" \
  && grep -F 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" --run-dir "$RUN_DIR" --status "$RUN_HEALTH_STATUS" --seal --import-tally' "$TFL" >/dev/null \
  && grep -F 'Set `RUN_HEALTH_STATUS` to `completed` when Result is SUCCESS or the suite already passed, to `budget-capped` on tally STOP, and to `failed` for every other Result.' "$TFL" >/dev/null; then
  pass "producer skills call run-health-emit.sh with --seal"
else
  fail "producer skills call run-health-emit.sh with --seal"
fi
if producer_call "$REPO/plugins/soleur/skills/one-shot/SKILL.md"; then
  fail "one-shot pointer sentence is not a producer call"
else
  pass "one-shot pointer sentence is not a producer call"
fi
# shellcheck disable=SC2016 # the schema sentence is literal text, not this shell's expansion
# A "Do not Append \`run_health_dir:\`" line contains the restore sentence and must not pass.
if grep -F 'SESSION_STATE="knowledge-base/project/specs/<branch>/session-state.md"' "$SCHEMA" >/dev/null \
  && grep -F 'Append `run_health_dir:` again after that rewrite' "$SCHEMA" \
    | grep -Ev '(^|[^[:alnum:]_])([Dd]o not|[Nn]ever|[Dd]on'\''t) Append' >/dev/null \
  && grep -F 'Set `RUN_HEALTH_STATUS` to `completed` only when the completion promise is true, to `budget-capped` on a tally stop, and to `failed` on every other return.' "$SCHEMA" >/dev/null \
  && grep -F 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" --run-dir "$RUN_DIR" --status "$RUN_HEALTH_STATUS" --seal --session-state "$SESSION_STATE" --import-tally' "$SCHEMA" >/dev/null \
  && grep -F -- '- run_health_dir: <RUN_DIR>' "$REPO/plugins/soleur/skills/one-shot/SKILL.md" >/dev/null; then
  pass "schema binds session-state and restores run_health_dir"
else
  fail "schema binds session-state and restores run_health_dir"
fi

# Case 14: existing gitignore covers the artifact paths
if git -C "$REPO" check-ignore -q -- .soleur/runs/example/run_health.json \
  && git -C "$REPO" check-ignore -q -- .soleur/runs/example/phase_prompts/0.md; then
  pass "gitignore covers run_health.json and phase_prompts"
else
  fail "gitignore covers run_health.json and phase_prompts"
fi

# Case 15: --discover prints ok. Do not count the live repo tree; another
# writer in .soleur/runs flips that comparison.
disc="$(bash "$SUT" --discover 2>"$TMP/discover.err")"
rc=$?
if [[ "$rc" == "0" && "$disc" == "ok" ]] && ! grep -q 'discover failed' "$TMP/discover.err"; then
  pass "discover prints ok without a repo run file"
else
  fail "discover prints ok without a repo run file" "rc=$rc out=$disc"
fi

# Case 16: --seal with started does not set sealed
S16="$TMP/run-seal-started"
bash "$SUT" --run-dir "$S16" --phase 0 --status started --seal 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('sealed') is False else 1)" "$S16/run_health.json" 2>/dev/null; then
  pass "seal with started does not seal"
else
  fail "seal with started does not seal"
fi

# Case 17: a default PATH stores the sibling script's own stdout.
# An empty counter root prints UNKNOWN. A host ledger must not be required.
# The stub in case 11 is prepended; this case must not see that stub.
S17root="$TMP/tally-root"
mkdir -p "$S17root"
S17="$TMP/run-tally-real"
expected="$(PATH=/usr/bin:/bin SOLEUR_SESSION_STATE_ROOT="$S17root" bash "$DIR/pipeline-tally.sh" show 2>/dev/null || true)"
PATH=/usr/bin:/bin SOLEUR_SESSION_STATE_ROOT="$S17root" bash "$SUT" --run-dir "$S17" --status failed --seal --import-tally 2>/dev/null
if [[ -n "$expected" ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('tally_show','')==sys.argv[2] else 1)" "$S17/run_health.json" "$expected" 2>/dev/null; then
  pass "import-tally finds the sibling script"
else
  fail "import-tally finds the sibling script" "expected=$(printf %s "$expected" | head -c 80)"
fi

# Case 18: a trailing value flag exits 0. A spin is exit 124 from timeout.
S18err="$TMP/novalue.err"
timeout 2 bash "$SUT" --run-dir "$TMP/novalue" --status >"$TMP/novalue.out" 2>"$S18err"
rc=$?
if [[ "$rc" == "0" ]] && grep -q 'run-health-emit: --status requires a value' "$S18err"; then
  pass "missing flag value exits 0"
else
  fail "missing flag value exits 0" "rc=$rc"
fi

# Case 19: a later seal keeps the terminal status and the first goto_count.
S19="$TMP/run-reseal"
bash "$SUT" --run-dir "$S19" --status budget-capped --seal --session-state "$TMP/session-state.md" 2>/dev/null
bash "$SUT" --run-dir "$S19" --status completed --seal 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('sealed') is True and d.get('status')=='budget-capped' and d.get('completed_at') and d.get('goto_count')==2 else 1)" "$S19/run_health.json" 2>/dev/null; then
  pass "later seal keeps budget-capped"
else
  fail "later seal keeps budget-capped"
fi

# Case 20: a ledger that does not parse is left in place.
S20="$TMP/run-corrupt"
mkdir -p "$S20"
printf 'not-json' > "$S20/run_health.json"
bash "$SUT" --run-dir "$S20" --status completed --seal >"$TMP/corrupt.out" 2>"$TMP/corrupt.err"; rc=$?
if [[ "$rc" == "0" && "$(cat "$S20/run_health.json")" == "not-json" ]] && grep -q 'run-health-emit:' "$TMP/corrupt.err"; then
  pass "unreadable ledger is left in place"
else
  fail "unreadable ledger is left in place" "rc=$rc body=$(cat "$S20/run_health.json" 2>/dev/null)"
fi

# Case 21: a symlink prompt is not followed.
printf 'secret-bytes' > "$TMP/secret.txt"
chmod 600 "$TMP/secret.txt"
ln -s "$TMP/secret.txt" "$TMP/prompt-link"
S21="$TMP/run-link-prompt"
bash "$SUT" --run-dir "$S21" --phase 0 --status started --prompt-file "$TMP/prompt-link" 2>"$TMP/linkp.err"; rc=$?
secret_copied=0
if [[ -d "$S21" ]]; then
  while IFS= read -r -d '' leaked; do
    if grep -q 'secret-bytes' "$leaked"; then secret_copied=1; break; fi
  done < <(find "$S21" -type f -print0)
fi
if [[ "$rc" == "0" && ! -e "$S21/phase_prompts/0.md" && "$secret_copied" == "0" ]]; then
  pass "symlink prompt is not copied"
else
  fail "symlink prompt is not copied" "rc=$rc copied=$secret_copied"
fi

# Case 22: a symlink run-dir is not written through.
mkdir -p "$TMP/link-target"
ln -s "$TMP/link-target" "$TMP/run-link-dir"
bash "$SUT" --run-dir "$TMP/run-link-dir" --phase 0 --status started >"$TMP/linkd.out" 2>"$TMP/linkd.err"; rc=$?
if [[ "$rc" == "0" && ! -e "$TMP/link-target/run_health.json" && ! -e "$TMP/link-target/phase_prompts" ]] && grep -q 'run-health-emit:' "$TMP/linkd.err"; then
  pass "symlink run-dir is refused"
else
  fail "symlink run-dir is refused" "rc=$rc"
fi

# Case 23: a symlink ledger is not replaced.
S23="$TMP/run-link-health"
mkdir -p "$S23"
printf '%s\n' '{"sealed":true,"status":"failed"}' > "$TMP/real-health.json"
ln -s "$TMP/real-health.json" "$S23/run_health.json"
bash "$SUT" --run-dir "$S23" --status completed --seal >"$TMP/linkh.out" 2>"$TMP/linkh.err"; rc=$?
if [[ "$rc" == "0" && -L "$S23/run_health.json" && "$(cat "$TMP/real-health.json")" == '{"sealed":true,"status":"failed"}' ]] && grep -q 'run-health-emit:' "$TMP/linkh.err"; then
  pass "symlink ledger is left in place"
else
  fail "symlink ledger is left in place" "rc=$rc"
fi

# Case 24: new ledger and prompt files are mode 0600.
S24="$TMP/run-mode"
bash "$SUT" --run-dir "$S24" --phase 0 --status started --prompt-file "$TMP/p.md" 2>/dev/null
json_mode="$(stat -c %a "$S24/run_health.json" 2>/dev/null || true)"
prompt_mode="$(stat -c %a "$S24/phase_prompts/0.md" 2>/dev/null || true)"
if [[ "$json_mode" == "600" && "$prompt_mode" == "600" ]]; then
  pass "ledger and prompt are mode 0600"
else
  fail "ledger and prompt are mode 0600" "json=$json_mode prompt=$prompt_mode"
fi

# Case 25: a non-terminal upsert clears ended_at.
S25="$TMP/run-ended"
bash "$SUT" --run-dir "$S25" --phase 0 --status completed 2>/dev/null
bash "$SUT" --run-dir "$S25" --phase 0 --status started 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); p=d['phases'][0]; sys.exit(0 if p.get('status')=='started' and 'ended_at' not in p else 1)" "$S25/run_health.json" 2>/dev/null; then
  pass "non-terminal status clears ended_at"
else
  fail "non-terminal status clears ended_at"
fi

# Case 26: a phase token that is an attempt filename is refused.
refuse_phase '0.attempt-2' 'attempt-name'

# Case 27: a failing tally show is not stored as a silent empty measurement.
BIN2="$TMP/bin-fail"
mkdir -p "$BIN2"
cat > "$BIN2/pipeline-tally.sh" <<'EOF'
#!/usr/bin/env bash
echo 'tally exploded' >&2
exit 1
EOF
chmod +x "$BIN2/pipeline-tally.sh"
S27="$TMP/run-tally-fail"
PATH="$BIN2:/usr/bin:/bin" bash "$SUT" --run-dir "$S27" --status completed --seal --import-tally >"$TMP/tally-fail.out" 2>"$TMP/tally-fail.err"; rc=$?
if [[ "$rc" == "0" ]] && grep -q 'run-health-emit: tally show failed' "$TMP/tally-fail.err" && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('tally_show')=='' else 1)" "$S27/run_health.json" 2>/dev/null; then
  pass "failed tally show is reported"
else
  fail "failed tally show is reported" "rc=$rc"
fi

echo "passes=$passes fails=$fails"
# 36 is every pass() that remains after instrument_self_test restores its
# counters: 6 refuse_phase labels plus 30 other sites. Deleting a site fails.
[[ "$passes" -eq 36 ]]
[[ "$fails" -eq 0 ]]