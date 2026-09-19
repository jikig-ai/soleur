#!/usr/bin/env bash
# Tests for pkill-self-match-guard.sh.
#
# ANTI-VACUITY: the verdict below reads an append-only ledger, NOT a counter that
# pass()/fail() both increment — a conservation sum is silenced by one token
# (`fails=$((fails+1))` -> `passes=...`), which is the exact class this repo has
# shipped twice. VERDICTS is appended to by each helper and the floor asserts a
# minimum length, so silencing a helper DELETES evidence rather than moving a number.
set -uo pipefail

# Redirect incident telemetry into a sandbox before any case runs. Required of
# every hook suite by .claude/hooks/incident-sandbox-coverage.test.sh: without
# it these fixtures write into the operator's live .claude/.rule-incidents.jsonl,
# which `compound` Phase 1.5 reads as deviation evidence and
# `rule-metrics-aggregate.sh` keys its counters on. Sourcing the helper (rather
# than setting INCIDENTS_REPO_ROOT per call) is what makes it impossible for an
# individual invocation to forget.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pkill-self-match-guard.sh"
VERDICTS=()
MIN_ASSERTIONS=59

pass() { VERDICTS+=("PASS"); printf '  ok   %s\n' "$1"; }
fail() { VERDICTS+=("FAIL"); printf '  FAIL %s\n' "$1"; }

# $1=name  $2=command-string  $3=deny|allow
run_case() {
  local name="$1" cmd="$2" want="$3" out got
  out="$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null || true)"
  if grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' <<<"$out"; then got=deny; else got=allow; fi
  [[ "$got" == "$want" ]] && pass "$name (=$want)" || fail "$name — wanted $want got $got"
}

echo "--- must DENY: any -f use (the wrapper always carries the pattern) ---"
# The literal incident: a waiter whose own wrapper cmdline carries the pattern.
run_case "waiter loop naming the same script" \
  'until ! pgrep -f "run-registered-suites" >/dev/null; do sleep 5; done; echo done' deny
run_case "pkill after echoing the same name" \
  'echo "killing run-registered-suites"; pkill -f run-registered-suites' deny
# The FALSIFIED narrowing from PR #7888 — must still be caught.
run_case "the ^bash narrowing is still self-matching" \
  'nohup bash apps/x/run-registered-suites.sh & pkill -f "^bash .*run-registered-suites\.sh"' deny
run_case "single-quoted pattern" \
  "tail -f run-registered-suites.log & pkill -f 'run-registered-suites'" deny
run_case "pattern that appears nowhere else is STILL self-matching" \
  'pkill -f some-unrelated-daemon' deny
run_case "bundled flag form -af" 'pgrep -af lonelyprocess' deny

# Devin wire name `exec` reaches the gate (kind map, #8205).
echo "--- Devin wire name ---"
out="$(jq -nc '{tool_name:"exec", tool_input:{command:"pgrep -af lonelyprocess"}}' | bash "$HOOK" 2>/dev/null || true)"
grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' <<<"$out" \
  && pass "Devin exec: -f self-match denied" || fail "Devin exec: -f self-match not denied"

echo "--- must ALLOW: no -f, or not our shape ---"
run_case "pkill without -f matches the NAME only" 'pkill node; echo node' allow
run_case "pgrep without -f"               'pgrep sshd' allow
run_case "not a pkill/pgrep command"      'grep -rn run-registered-suites .' allow
run_case "captured PID, no pattern"       'sleep 5 & pid=$!; kill "$pid"' allow
run_case "sanctioned helper is never blocked" \
  'source plugins/soleur/scripts/lib/proc.sh; kill_mine' allow

# ---------------------------------------------------------------------------
# Read-only spelling (#8330): an args-showing `ps` pipeline whose grep/awk regex
# matches the wrapper line `bash -c <the command>`. The hook SIMULATES the regex
# against that line; it does not look for "the pattern elsewhere". Row ids
# (D1–D19, A1–A23) are the plan's §Test Scenarios names — cite them, not lines.
# ---------------------------------------------------------------------------
NL=$'\n'

echo "--- must DENY: read-only ps | grep/awk pipeline that matches its own wrapper ---"
# D1 — the #8231 incident: bracket trick, un-tricked literal elsewhere in the command.
run_case "D1 bracket trick + literal elsewhere (the incident)" \
  'bash scripts/test-all.sh > /tmp/b.log 2>&1 & until [ "$(ps -eo args | grep -c '"'"'[t]est-all\.sh'"'"')" = 0 ]; do sleep 5; done' deny
# D2 — an unescaped metacharacter matches its own literal; nothing else in the command.
D2='n=$(ps -eo args | grep -c test-all.sh)'
run_case "D2 unescaped dot, alone" "$D2" deny
run_case "D3 bare literal, ps aux" 'ps aux | grep foo-daemon' deny
run_case "D4 ps -ef with -i and trailing wc" 'ps -ef | grep -i NGINX | wc -l' deny
run_case "D5 awk regex literal" "ps -eo args | awk '/test-all.sh/' | wc -l" deny
# D6 — the PR #7888 narrowing: ^ anchors the joined line, .* eats "-c ".
run_case "D6 the ^bash .* narrowing" \
  "bash scripts/test-all.sh & ps -eo args | grep -cE '^bash .*test-all\\.sh'" deny
run_case "D7 second pipeline after a compliant first" \
  'ps -eo comm | grep -c bash; ps -eo args | grep -c "x-y-z"' deny
run_case "D8 -F defeats the bracket trick" "ps -eo args | grep -cF '[t]est-all'" deny
# D9 — the literal lives in a heredoc BODY; the wrapper still carries it.
D9="cat > /tmp/note.md <<'EOF'${NL}waiting on scripts/test-all.sh${NL}EOF${NL}n=\$(ps -eo args | grep -c '[t]est-all\\.sh')"
run_case "D9 literal in a heredoc body re-arms the bracket trick" "$D9" deny
run_case "D10 fail-open pipeline then a self-matching one (per-pipeline fail-open)" \
  'P=x; ps -eo args | grep -c "$P"; ps -eo args | grep -c test-all.sh' deny
run_case "D12 -o pid,cmd is args-showing" 'ps -o pid,cmd | grep -c x-y-z' deny
run_case "D13 BSD x alone" 'ps x | grep -c test-all.sh' deny
run_case "D14 --format args" 'ps --format args -e | grep -c test-all.sh' deny
run_case "D15 awk -v is not grep -v" "ps -eo args | awk -v n=1 '/test-all.sh/' | wc -l" deny
run_case "D16 -C is not a pid restriction" 'ps -o args= -C bash | grep -c x-y-z' deny
run_case "D17 self-matching pipeline FIRST, compliant second" \
  'ps -eo args | grep -c test-all.sh; ps -eo comm | grep -c bash' deny
run_case "D18 fgrep alias is fixed-string" "ps -eo args | fgrep -c '[t]est-all'" deny
# D19 — a `;` boundary inside a quoted string is an ACCEPTED false deny (header names it).
run_case "D19 ; boundary inside quotes (accepted false deny)" \
  'echo "x; ps aux | grep -c '"'"'foo'"'"'"' deny

# D11 — both spellings in one command: the -f arm fires first and is the ONLY
# envelope. Discriminate on the -f reason's opening line — both reasons carry
# "matches the process NAME only" once the `pgrep -a <name>` recipe lands.
D11='pgrep -af x; ps -eo args | grep -c test-all.sh'
out="$(jq -nc --arg c "$D11" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null || true)"
n="$(printf '%s\n' "$out" | jq -s length 2>/dev/null || echo 0)"
[[ "$n" == "1" ]] && pass "D11 both spellings → exactly one envelope" \
  || fail "D11 both spellings — wanted 1 envelope got $n"
r="$(printf '%s\n' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null | head -1)"
[[ "$r" == 'BLOCKED: `pgrep -f`'* ]] && pass "D11 the -f arm's reason wins" \
  || fail "D11 reason did not begin with the -f arm's BLOCKED line: ${r:0:60}"

# Devin wire name reaches the read-only arm too (kind map, #8205).
out="$(jq -nc --arg c "$D2" '{tool_name:"exec", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null || true)"
grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' <<<"$out" \
  && pass "Devin exec: read-only self-match denied" || fail "Devin exec: read-only self-match not denied"

echo "--- must ALLOW: cannot self-match, sanctioned, documentation, or fail-open ---"
run_case "A1 bracket trick + escaped dot, no other mention" \
  "n=\$(ps -eo args | grep -c '[t]est-all\\.sh')" allow
run_case "A2 argv-slot awk with the runner launched in the same command" \
  "bash scripts/test-all.sh & ps -eo args | awk '\$1==\"bash\" && \$2==\"scripts/test-all.sh\"' | wc -l" allow
run_case "A3 name-only ps -eo comm" 'ps -eo comm | grep -c bash' allow
run_case "A4 work/SKILL.md liveness shape with grep -v grep" \
  "ps -ef | grep -E 'test-all' | grep -v grep" allow
run_case "A5 start-anchored without .*" \
  "bash scripts/test-all.sh & ps -eo args | grep -cE '^bash scripts/test-all\\.sh'" allow

# A6 — documentation about the spelling. Fixture synthesized inline with the
# learning paragraph's shape (2026-09-18-every-instrument-i-waited-on-was-
# counting-itself.md): prose, a fenced poller, prose naming the runner. A repo
# doc is NOT read here so a doc edit cannot break a hook test; the two repo
# docs are checked once at ship (plan AC4).
FIX="The poller counted itself for an hour and reported \"still waiting\".${NL}A wait-for-quiet loop written this way never fires:${NL}\`\`\`bash${NL}n=\$(ps -eo args | grep -c '[t]est-all\\.sh')${NL}\`\`\`${NL}The runner was launched as scripts/test-all.sh in the same command."
# Non-vacuity control: the fixture really carries the spelling and the literal.
if [[ "$FIX" == *"ps -eo args | grep -c"* && "$FIX" == *"scripts/test-all.sh"* ]]; then
  pass "A6 control: fixture carries the ps|grep spelling and the runner literal"
else
  fail "A6 control: fixture lost the spelling or the literal"
fi
# Positive control: the SAME text fed without the heredoc wrapper is the D9
# shape and must deny — so A6's allow is provably from strip_heredocs.
run_case "A6 positive control: fixture text WITHOUT the heredoc wrapper" "$FIX" deny
run_case "A6 heredoc writing the doc-shaped fixture" \
  "cat > /dev/null <<'EOF'${NL}${FIX}${NL}EOF" allow

run_case "A7 grepping docs for the shape" \
  "grep -rn 'ps -eo args | grep -c' knowledge-base/" allow
run_case "A8 pattern in a variable (fail-open)" 'P=test-all; ps -eo args | grep -c "$P"' allow
run_case "A9 pattern file (fail-open)" 'ps -ef | grep -c -f pats.txt' allow
run_case "A10 no matcher stage" 'ps -eo args | wc -l' allow
run_case "A11 sanctioned helper" 'source plugins/soleur/scripts/lib/proc.sh; list_runs test-all' allow
run_case "A12 ps inside a quoted argument, no boundary" \
  "grep -n \"ps aux | grep -c 'foo'\" README.md" allow
run_case "A13 invalid regex (fail-open, grep rc 2)" "ps -eo args | grep -c '[unterminated'" allow
# A14 — inner pattern QUOTED so that under mutation M9 (ps anywhere) extraction
# resolves to `foo`, which the model carries, and the row goes RED.
run_case "A14 ps inside an echoed string, not at a boundary" \
  "echo \"ps aux | grep -c 'foo'\"" allow
run_case "A15 literal containing a quote (fail-open)" "ps -eo args | grep -c \"it's-daemon\"" allow
run_case "A16 awk -F is not grep -F" "ps -eo args | awk -F: '/test-all\\.sh/' | wc -l" allow
# A17 — an EXECUTED heredoc is a deliberate fail-open (header names the gap).
run_case "A17 executed heredoc (deliberate fail-open)" \
  "bash <<'EOF'${NL}ps -eo args | grep -c test-all.sh${NL}EOF" allow
run_case "A18 pid-restricted ps cannot list the wrapper" \
  'cmd & pid=$!; ps -o args= -p "$pid" | grep -c test-all.sh' allow
run_case "A19 whole-line match cannot hit the wrapper" \
  "ps -eo args | grep -cx 'bash scripts/test-all.sh'" allow
run_case "A20 long-form invert" 'ps -ef | grep test-all | grep --invert-match grep' allow
run_case "A21 slot-anchored awk regex with an escaped metacharacter" \
  "ps -eo args | awk '\$2 ~ /test-all\\.sh/' | wc -l" allow
run_case "A22 | inside a quoted pattern resolves fail-open" \
  "ps -eo args | grep -cE 'test-all|lint' | wc -l" allow
run_case "A23 egrep alias of the safe bracket spelling" \
  "ps -eo args | egrep -c '[t]est-all\\.sh'" allow

# Telemetry: the read-only arm emits exactly one ledger line under its own rule
# id; the -f arm emits none. A FRESH root per invocation — the suite sandbox
# already holds lines from the deny rows above, so "exactly one" is only
# meaningful against an empty ledger.
echo "--- telemetry: read-only arm emits, -f arm does not ---"
R="$(mktemp -d)"; mkdir -p "$R/.claude"
jq -nc --arg c "$D2" '{tool_name:"Bash", tool_input:{command:$c}}' \
  | INCIDENTS_REPO_ROOT="$R" bash "$HOOK" >/dev/null 2>&1 || true
n="$(grep -c '"rule_id":"pkill-self-match-guard-readonly"' "$R/.claude/.rule-incidents.jsonl" 2>/dev/null || true)"
[[ "$n" == "1" ]] && pass "telemetry: D2 leaves one pkill-self-match-guard-readonly line" \
  || fail "telemetry: D2 wanted 1 ledger line got ${n:-0}"
rm -rf "$R"
R="$(mktemp -d)"; mkdir -p "$R/.claude"
jq -nc --arg c "$D11" '{tool_name:"Bash", tool_input:{command:$c}}' \
  | INCIDENTS_REPO_ROOT="$R" bash "$HOOK" >/dev/null 2>&1 || true
if [[ ! -s "$R/.claude/.rule-incidents.jsonl" ]]; then
  pass "telemetry: D11 (-f arm wins) leaves no ledger line"
else
  fail "telemetry: D11 wrote a ledger line although the -f arm handled it"
fi
rm -rf "$R"

echo "--- positive control: both helpers move the ledger ---"
before=${#VERDICTS[@]}
pass "control: pass() appends"
fail "control: fail() appends (EXPECTED — retracted below)"
after=${#VERDICTS[@]}
if (( after - before == 2 )); then
  unset 'VERDICTS[-1]'                       # retract the deliberate FAIL
  VERDICTS=("${VERDICTS[@]}")
  VERDICTS+=("PASS"); printf '  ok   control retracted; both helpers verified live\n'
else
  VERDICTS+=("FAIL"); printf '  FAIL control: a helper did not append (%d)\n' "$((after-before))"
fi

# --- verdict, read from the append-only ledger ---
total=${#VERDICTS[@]}
fails=0
for v in "${VERDICTS[@]}"; do [[ "$v" == "FAIL" ]] && fails=$((fails+1)); done
printf '\n=== %d verdicts, %d failed ===\n' "$total" "$fails"
if (( total < MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor breached: %d < %d — the suite lost verdicts.\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
