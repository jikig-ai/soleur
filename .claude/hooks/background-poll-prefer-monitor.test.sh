#!/usr/bin/env bash
# Fixture-based tests for background-poll-prefer-monitor.sh.
#
# Coverage:
#   DENY (backgrounded remote poll loop):
#     (a) run_in_background + while-loop + `gh pr view`
#     (b) run_in_background + until-loop + `gh pr checks`
#     (c) run_in_background + `gh run watch` (self-looping idiom, no explicit loop)
#     (d) run_in_background + `gh pr checks --watch`
#     (e) run_in_background + while-loop + curl (generic remote read)
#   ALLOW (must NOT false-fire):
#     (f) foreground while+gh poll (run_in_background absent/false) — Monitor is
#         advisory here but the BANNED tool is run_in_background, so allow.
#     (g) run_in_background single-shot wait-then-check (no loop): sleep && gh pr view
#     (h) run_in_background background build (npm run build)
#     (i) run_in_background local-only while-loop (no remote-read token)
#     (j) run_in_background write fan-out loop (gh issue create) — not a read/poll
#     (k) override-marker present
#     (l) non-Bash tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/background-poll-prefer-monitor.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

assert_decision() {
  local label="$1" want="$2" payload="$3"
  TOTAL=$((TOTAL + 1))
  local out decision
  out="$(echo "$payload" | bash "$HOOK" 2>/dev/null)"
  decision="$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<missing>"' 2>/dev/null || echo "<jq-fail>")"
  if [[ "$decision" == "$want" ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $label → $decision"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  want: $want"
    echo "  got:  $decision"
    echo "  raw:  $out"
  fi
}

# Bash payload with run_in_background flag (true/false) and a command.
mk_bg() {
  local bg="$1" cmd="$2"
  jq -nc --argjson b "$bg" --arg c "$cmd" \
    '{tool_name: "Bash", tool_input: {command: $c, run_in_background: $b}}'
}
# Bash payload with NO run_in_background field at all.
mk_fg() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}'
}

# --- DENY cases ------------------------------------------------------------

assert_decision "(a) bg + while + gh pr view denies" "deny" \
  "$(mk_bg true 'while true; do gh pr view 4595 --json state; sleep 60; done')"

assert_decision "(b) bg + until + gh pr checks denies" "deny" \
  "$(mk_bg true 'until gh pr checks 4595 | grep -q pass; do sleep 30; done')"

assert_decision "(c) bg + gh run watch (no explicit loop) denies" "deny" \
  "$(mk_bg true 'RUN_ID=123; gh run watch "$RUN_ID"')"

assert_decision "(d) bg + gh pr checks --watch denies" "deny" \
  "$(mk_bg true 'gh pr checks 4595 --watch')"

assert_decision "(e) bg + while + curl denies" "deny" \
  "$(mk_bg true 'while :; do curl -s https://api.example.com/status; sleep 45; done')"

# --- ALLOW cases (no false positives) -------------------------------------

assert_decision "(f) FOREGROUND while+gh poll allows (flag absent)" "allow" \
  "$(mk_fg 'while true; do gh pr view 4595 --json state; sleep 60; done')"

assert_decision "(f2) explicit run_in_background:false while+gh allows" "allow" \
  "$(mk_bg false 'while true; do gh pr view 4595 --json state; sleep 60; done')"

assert_decision "(g) bg single-shot wait-then-check (no loop) allows" "allow" \
  "$(mk_bg true 'sleep 15 && gh pr view 4595 --json state')"

assert_decision "(h) bg background build allows" "allow" \
  "$(mk_bg true 'npm run build')"

assert_decision "(i) bg local-only while-loop allows (no remote read)" "allow" \
  "$(mk_bg true 'while read f; do convert "$f" out/"$f"; done < list.txt')"

assert_decision "(j) bg write fan-out loop (gh issue create) allows" "allow" \
  "$(mk_bg true 'for n in 1 2 3; do gh issue create --title "t$n" --body x; done')"

assert_decision "(k) override-marker allows" "allow" \
  "$(mk_bg true 'while true; do gh pr view 4595; sleep 60; done
# gate-override: background-poll-prefer-monitor')"

assert_decision "(l) non-Bash tool allows" "allow" \
  "$(jq -nc '{tool_name: "Write", tool_input: {file_path: "x.md", content: "while gh run watch; do :; done"}}')"

# --- Fail-open on malformed / empty stdin (P3 regression guard) ------------
# jq exits 5 on invalid JSON; under set -euo pipefail the hook must NOT abort
# before emitting allow JSON (header invariant: "exit 0 always / fail-open").
assert_decision "(m) malformed JSON stdin allows (fail-open)" "allow" 'not json{'
assert_decision "(n) empty stdin allows (fail-open)" "allow" ''

# Exit-code guard: the hook must exit 0 even on malformed input.
TOTAL=$((TOTAL + 1))
if echo 'not json{' | bash "$HOOK" >/dev/null 2>&1; then
  PASS=$((PASS + 1)); echo "PASS: (o) malformed stdin exits 0"
else
  FAIL=$((FAIL + 1)); echo "FAIL: (o) malformed stdin exit code was $?"
fi

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
