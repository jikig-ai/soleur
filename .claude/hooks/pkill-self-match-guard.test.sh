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
MIN_ASSERTIONS=126

pass() { VERDICTS+=("PASS"); printf '  ok   %s\n' "$1"; }
fail() { VERDICTS+=("FAIL"); printf '  FAIL %s\n' "$1"; }
# $1=observed $2=wanted $3=name — the one comparison the telemetry rows route
# through, so its reject path can be driven by the control below.
expect_eq() { if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (got $1 wanted $2)"; fi; }

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
# docs were probed once at work time (plan AC4, /var/tmp/soleur-8330-docprobe.sh):
#   review/SKILL.md bullet "A process count that greps its own pattern…" and the
#   learning section "### The instruments that were counting themselves" (its one
#   -f line filtered), each wrapped as `cat > /dev/null <<'EOF' … EOF` → empty
#   stdout. Note the learning's poller sits in inline backticks, so it is allowed
#   by the boundary rule regardless of the heredoc; the fenced shape that
#   exercises strip_heredocs is THIS fixture and its positive control.
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
# A22 (review round 1): the quote-aware pipeline splitter keeps `|` inside a
# quoted pattern in the stage, so the ERE alternation is simulated — and it
# self-matches. Was a fail-open allow before the splitter existed.
run_case "D54 (was A22) | inside a quoted ERE alternation self-matches" \
  "ps -eo args | grep -cE 'test-all|lint' | wc -l" deny
run_case "A23 egrep alias of the safe bracket spelling" \
  "ps -eo args | egrep -c '[t]est-all\\.sh'" allow

# ---------------------------------------------------------------------------
# Review round 1 (PR #8354): rows for the branches the first battery sampled
# once or never — quote-aware splitting, keyword/prefix boundaries, output-mode
# grep flags, projection awk, value-taking ps options, matcher aliases.
# ---------------------------------------------------------------------------
echo "--- must DENY: review round 1 ---"
# The classic pid-extract poller: a projection awk after a live grep is a
# pass-through, not a filter (the first cut read any no-regex awk as "filtered").
run_case "D20 projection awk after a live grep" "ps aux | grep foo-daemon | awk '{print \$2}'" deny
run_case "D20b pid-extract-then-kill" "ps -eo pid,args | grep test-all.sh | awk '{print \$1}' | xargs -r kill" deny
# Pipeline terminators — each must END the walk so the next command's `grep -v grep` cannot rescue.
run_case "D21 ; terminates the pipeline" 'ps -eo args | grep -c test-all.sh; cat log | grep -v grep' deny
run_case "D22 & terminates the pipeline" 'ps -eo args | grep -c test-all.sh & cat log | grep -v grep' deny
run_case "D23 newline terminates the pipeline" "ps -eo args | grep -c test-all.sh${NL}cat log | grep -v grep" deny
run_case "D24 ) terminates the pipeline" '(ps -eo args | grep -c test-all.sh) | grep -v grep' deny
# The hook's own one-off remedy, applied after a -c: a count cannot be filtered.
run_case "D25 grep -c then grep -v grep still counts the wrapper" 'ps -eo args | grep -c test-all.sh | grep -v grep' deny
run_case "D56 -c then tr then grep -v" 'ps -eo args | grep -c test-all.sh | tr a-z A-Z | grep -v GREP' deny
# Keyword / brace / backtick / prefix boundaries.
run_case "D26 while-led poller" 'while ps -eo args | grep -q test-all.sh; do sleep 5; done' deny
run_case "D27 until-!-led poller" 'until ! ps -eo args | grep -q test-all.sh; do sleep 5; done' deny
run_case "D28 if-led check" 'if ps aux | grep -q foo-daemon; then echo busy; fi' deny
run_case "D29 env-assignment prefix" 'LC_ALL=C ps -eo args | grep -c test-all.sh' deny
run_case "D30 brace group" '{ ps aux | grep -c foo-daemon; }' deny
run_case "D31 backtick substitution" 'n=`ps aux | grep -c foo-daemon`' deny
run_case "D32 timeout prefix" 'timeout 5 ps aux | grep -c foo-daemon' deny
# Redirects and pipe spellings before the stage.
run_case "D33 2>&1 before the pipe" 'ps -eo args 2>&1 | grep -c test-all.sh' deny
run_case "D34 |& pipe" 'ps -eo args |& grep -c test-all.sh' deny
run_case "D35 newline right after the pipe" "ps -eo args |${NL}  grep -c test-all.sh" deny
# Matcher aliases and prefixes.
run_case "D36 command grep" 'ps -eo args | command grep -c test-all.sh' deny
run_case "D37 backslash-grep" 'ps -eo args | \grep -c test-all.sh' deny
run_case "D38 rg" 'ps -eo args | rg -c test-all.sh' deny
run_case "D39 absolute-path grep" 'ps -eo args | /usr/bin/grep -c test-all.sh' deny
run_case "D40 ERE group inside quotes" "ps -eo args | grep -cE '(test-all|zzqq)'" deny
run_case "D41 awk regex with && in the program" "ps -eo args | awk '/test-all.sh/ && \$1==\"bash\"' | wc -l" deny
# ps format spellings.
run_case "D42 args:width" 'ps -eo pid,args:200 | grep -c test-all.sh' deny
run_case "D43 quoted format list" "ps -eo 'pid,args' | grep -c test-all.sh" deny
run_case "D44 --format=args attached" 'ps -e --format=args | grep -c test-all.sh' deny
run_case "D45 -eo command" 'ps -eo command | grep -c test-all.sh' deny
run_case "D46 -O cmd" 'ps -eO cmd | grep -c test-all.sh' deny
run_case "D47 dashed BSD -ax" 'ps -ax | grep -c test-all.sh' deny
run_case "D48 bare BSD u" 'ps u | grep -c test-all.sh' deny
run_case "D14b -eo args= (the = suffix, no bare-token rescue)" 'ps -eo args= | grep -c test-all.sh' deny
# grep pattern spellings.
run_case "D49 -- then a dash-led pattern" 'ps -eo args | grep -c -- -foo' deny
run_case "D50 --regexp=" 'ps -eo args | grep -c --regexp=test-all.sh' deny
run_case "D51 --fixed-strings defeats the bracket trick" "ps -eo args | grep --fixed-strings -c '[t]est-all'" deny
run_case "D52 attached -e pattern" 'ps -eo args | grep -c -etest-all.sh' deny
run_case "D57 -vw non-matching word does not filter" "ps -eo args | grep test-all | grep -vw '[g]re'" deny
# --ppid is NOT a pid restriction: the wrapper is a child of \$PPID.
run_case "D53 --ppid lists the wrapper" 'ps -o args= --ppid $$ | grep -c x-y-z' deny

# D55 — the read-only envelope itself: exactly one, its own reason, and the
# offending pipeline + matching stage named (mirrors D11 for the -f arm).
out="$(jq -nc --arg c "$D2" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null || true)"
n="$(printf '%s\n' "$out" | jq -s length 2>/dev/null || echo 0)"
[[ "$n" == "1" ]] && pass "D55 read-only deny → exactly one envelope" || fail "D55 wanted 1 envelope got $n"
r="$(printf '%s\n' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
[[ "$r" == 'BLOCKED: `ps '* ]] && pass "D55 reason is the read-only arm's" || fail "D55 reason opener: ${r:0:40}"
grep -qF 'Offending pipeline: ps -eo args | grep -c test-all.sh' <<<"$r" \
  && pass "D55 reason names the offending pipeline" || fail "D55 reason lacks the offending pipeline"
grep -qF "Matching stage:     grep 'test-all.sh' (-G)" <<<"$r" \
  && pass "D55 reason names the matching stage + flavour" || fail "D55 reason lacks the matching stage"

echo "--- must ALLOW: review round 1 ---"
run_case "A24 grep -v grep BEFORE a projection awk" "ps aux | grep foo-daemon | grep -v grep | awk '{print \$2}'" allow
run_case "A25 -C value is not a BSD bundle (comm-only)" 'ps -C bash -o comm | grep -c bash' allow
run_case "A25b -u value is not a BSD bundle (comm-only)" 'ps -u jean -o comm | grep -c sshd' allow
run_case "A26 a non-matching positive stage filters the wrapper" "ps -eo args | grep -i nginx | grep -c '^/usr/sbin/'" allow
run_case "A27 awk string with a / is not a regex position" "ps -eo args | awk '\$2==\"apps/web/scripts/test-all.sh\"' | wc -l" allow
run_case "A2b single-condition argv-slot awk (reaches the no-regex branch)" \
  "bash scripts/test-all.sh & ps -eo args | awk '\$2==\"scripts/test-all.sh\"' | wc -l" allow
run_case "A28 bundled -vi" "ps -ef | grep -E test-all | grep -vi grep" allow
run_case "A29 -m takes an argument" "ps -eo args | grep -c -m 1 '[t]est-all\\.sh'" allow
run_case "A30 bundled -f is a pattern file (fail-open)" 'ps -ef | grep -cf pats.txt' allow
run_case "A31 --perl-regexp (fail-open)" 'ps -eo args | grep --perl-regexp -c test-all' allow
run_case "A32 empty literal (fail-open)" "ps -eo args | grep -c ''" allow
run_case "A33 --line-regexp cannot hit the wrapper" "ps -eo args | grep -c --line-regexp 'bash scripts/test-all.sh'" allow
run_case "A34 abbreviated --invert" 'ps -ef | grep test-all | grep --invert grep' allow
run_case "A35 -q pid restriction" 'ps -o args -q "$pid" | grep -c test-all.sh' allow
run_case "A36 --pid restriction" 'ps -o args --pid "$pid" | grep -c test-all.sh' allow
run_case "A40 awk is ERE (interval)" "ps -eo args | awk '/test-al{2}/' | wc -l" allow
run_case "A41 egrep is ERE in a -v stage" "ps -ef | grep test-all | egrep -v 'x{0}[g]rep'" allow
run_case "A42 sed matcher ends the walk (accepted gap)" "ps -eo args | sed -n '/test-all.sh/p'" allow

# A39 — lib absent: the arm skips itself with a stderr WARN (fail-open), the -f
# arm still denies. Run a copy of the hook from a dir with no lib/incidents.sh.
LIBLESS="$(mktemp -d)"; mkdir -p "$LIBLESS/lib"
cp "$HOOK" "$LIBLESS/hook.sh"; cp "$(dirname "$HOOK")/lib/hook-tool-kind.sh" "$LIBLESS/lib/"
err="$(jq -nc --arg c "$D2" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$LIBLESS/hook.sh" 2>&1 >/dev/null || true)"
out="$(jq -nc --arg c "$D2" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$LIBLESS/hook.sh" 2>/dev/null || true)"
if [[ -z "$out" && "$err" == *"read-only self-match arm skipped"* ]]; then
  pass "A39 lib absent → arm skipped with a WARN (fail-open)"
else
  fail "A39 lib absent: out=[${out:0:40}] err=[${err:0:60}]"
fi
out="$(jq -nc '{tool_name:"Bash", tool_input:{command:"pgrep -af lonelyprocess"}}' | bash "$LIBLESS/hook.sh" 2>/dev/null || true)"
grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' <<<"$out" \
  && pass "A39 lib absent → -f arm still denies" || fail "A39 lib absent: -f arm did not deny"
rm -rf "$LIBLESS"

# Telemetry: the read-only arm emits exactly one ledger line under its own rule
# id; the -f arm emits none. Asserted as a DELTA against the sandbox ledger the
# sourced lib guarantees (SOLEUR_TEST_INCIDENT_ROOT) — never a per-call
# INCIDENTS_REPO_ROOT override: an empty override resolves to the OPERATOR'S
# real ledger (review round 1, data-integrity; the 2026-09-03 class).
echo "--- telemetry: read-only arm emits, -f arm does not ---"
LEDGER="$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl"
ledger_lines() { if [[ -f "$LEDGER" ]]; then wc -l < "$LEDGER"; else echo 0; fi; }
ledger_ro() { if [[ -f "$LEDGER" ]]; then grep -c '"rule_id":"pkill-self-match-guard-readonly"' "$LEDGER" || true; else echo 0; fi; }
[[ -n "${SOLEUR_TEST_INCIDENT_ROOT:-}" ]] || { printf '[FATAL] telemetry: SOLEUR_TEST_INCIDENT_ROOT unset — sandbox lib not sourced\n' >&2; exit 1; }
b_all=$(ledger_lines); b_ro=$(ledger_ro)
jq -nc --arg c "$D2" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" >/dev/null 2>&1 || true
a_all=$(ledger_lines); a_ro=$(ledger_ro)
expect_eq "$((a_ro - b_ro))/$((a_all - b_all))" "1/1" "telemetry: D2 adds exactly one pkill-self-match-guard-readonly line (readonly/all delta)"
b_all=$(ledger_lines)
jq -nc --arg c "$D11" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" >/dev/null 2>&1 || true
a_all=$(ledger_lines)
expect_eq "$((a_all - b_all))" "0" "telemetry: D11 (-f arm wins) adds no ledger line"
b_all=$(ledger_lines)
jq -nc --arg c "n=\$(ps -eo args | grep -c '[t]est-all\\.sh')" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" >/dev/null 2>&1 || true
a_all=$(ledger_lines)
expect_eq "$((a_all - b_all))" "0" "telemetry: an allowed pipeline (A1) adds no ledger line"

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
# expect_eq owns a verdict: prove it can still REJECT (a `[[ 1 == 1 ]]` mutant
# in its comparison would leave every telemetry row green).
before=${#VERDICTS[@]}
expect_eq 1 2 "control: expect_eq rejects a mismatch (EXPECTED — retracted below)"
if (( ${#VERDICTS[@]} - before == 1 )) && [[ "${VERDICTS[-1]}" == "FAIL" ]]; then
  unset 'VERDICTS[-1]'; VERDICTS=("${VERDICTS[@]}")
  VERDICTS+=("PASS"); printf '  ok   control retracted; expect_eq verified able to reject\n'
else
  VERDICTS+=("FAIL"); printf '  FAIL control: expect_eq did not reject a mismatch\n'
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
