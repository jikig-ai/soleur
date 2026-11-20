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

# A producer call is one line that runs bash on run-health-emit.sh and passes --seal.
# A sentence that only names the tokens is not a call. An empty list is not a call.
producer_call() {
  local -a files=("$@")
  local f line found
  [[ "${#files[@]}" -eq 0 ]] && return 1
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || return 1
    found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == *bash* && "$line" == *run-health-emit.sh* && "$line" == *--seal* ]]; then
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
if [[ -f "$RD/run_health.json" ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('schema_version')==1 and d['run_id']=='r1' and d['issue']=='12573' and len(d['phases'])==1 else 1)" "$RD/run_health.json"; then
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
bash "$SUT" --run-dir "$S10b" --status completed --seal --session-state "$TMP/no-such-session-state.md" 2>/dev/null; rc=$?
if [[ "$rc" == "0" ]] && python3 -c "import json,sys; a=json.load(open(sys.argv[1])); b=json.load(open(sys.argv[2])); sys.exit(0 if a.get('goto_count')==2 and b.get('goto_count')==0 else 1)" "$S10/run_health.json" "$S10b/run_health.json" 2>/dev/null; then
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

# Case 13: producer skills. Empty list and a prose sentence are not calls.
REPO="$(git -C "$DIR" rev-parse --show-toplevel)"
PROSE="$TMP/prose-skill.md"
printf '%s\n' 'This sentence names run-health-emit.sh and --seal but does not run them.' > "$PROSE"
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
if producer_call \
  "$REPO/plugins/soleur/skills/one-shot/SKILL.md" \
  "$REPO/plugins/soleur/skills/test-fix-loop/SKILL.md"; then
  pass "producer skills call run-health-emit.sh with --seal"
else
  fail "producer skills call run-health-emit.sh with --seal"
fi

# Case 14: existing gitignore covers the artifact paths
if git -C "$REPO" check-ignore -q -- .soleur/runs/example/run_health.json \
  && git -C "$REPO" check-ignore -q -- .soleur/runs/example/phase_prompts/0.md; then
  pass "gitignore covers run_health.json and phase_prompts"
else
  fail "gitignore covers run_health.json and phase_prompts"
fi

# Case 15: --discover prints ok and does not write under the repo
before="$(find "$REPO/.soleur/runs" -type f 2>/dev/null | wc -l | tr -d ' ')"
disc="$(bash "$SUT" --discover 2>"$TMP/discover.err")"
rc=$?
after="$(find "$REPO/.soleur/runs" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$rc" == "0" && "$disc" == *ok* && "$before" == "$after" ]]; then
  pass "discover prints ok without a repo run file"
else
  fail "discover prints ok without a repo run file" "rc=$rc before=$before after=$after out=$disc"
fi

# Case 16: --seal with started does not set sealed
S16="$TMP/run-seal-started"
bash "$SUT" --run-dir "$S16" --phase 0 --status started --seal 2>/dev/null
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('sealed') is False else 1)" "$S16/run_health.json" 2>/dev/null; then
  pass "seal with started does not seal"
else
  fail "seal with started does not seal"
fi

echo "passes=$passes fails=$fails"
[[ "$fails" -eq 0 ]]