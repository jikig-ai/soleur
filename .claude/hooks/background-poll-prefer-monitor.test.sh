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
#     (p) run_in_background + for+seq loop + sleep + gh run/pr view (the
#         2026-06-02 escape: a bounded for-poll the while|until signature missed)
#   ALLOW (must NOT false-fire):
#     (f) foreground while+gh poll (run_in_background absent/false) — Monitor is
#         advisory here but the BANNED tool is run_in_background, so allow.
#     (g) run_in_background single-shot wait-then-check (no loop): sleep && gh pr view
#     (h) run_in_background background build (npm run build)
#     (i) run_in_background local-only while-loop (no remote-read token)
#     (j) run_in_background write fan-out loop (gh issue create) — not a read/poll
#     (j2) run_in_background for-loop remote READ but NO sleep — batch fetch, not a poll
#     (k) override-marker present
#     (l) non-Bash tool

set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

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
  # Normalise "the hook emitted nothing" to a readable sentinel. Empty stdout is
  # a pass-through (the tool proceeds, no decision asserted) and is distinct
  # from an explicit allow — a distinction #7164 made load-bearing.
  if [[ -z "${out//[[:space:]]/}" ]]; then
    decision="<none>"
  else
    decision="$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<missing>"' 2>/dev/null || echo "<jq-fail>")"
  fi
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

# (p) Regression for the 2026-06-02 escape: a bounded `for i in $(seq …)` poll
# that sleeps between iterations and reads remote state (gh run/pr view). The
# while|until-only signature missed it because `for` was excluded outright.
assert_decision "(p) bg + for+seq + sleep + gh run/pr view denies" "deny" \
  "$(mk_bg true 'for i in $(seq 1 40); do gh run view "$RID" --json status; gh pr view 4850 --json state; sleep 45; done')"

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

assert_decision "(j2) bg for-loop remote READ but NO sleep allows (batch fetch)" "allow" \
  "$(mk_bg true 'for n in 1 2 3; do gh pr view "$n" --json state >> out.txt; done')"

assert_decision "(k) override-marker allows" "allow" \
  "$(mk_bg true 'while true; do gh pr view 4595; sleep 60; done
# gate-override: background-poll-prefer-monitor')"

assert_decision "(l) non-Bash tool allows" "allow" \
  "$(jq -nc '{tool_name: "Write", tool_input: {file_path: "x.md", content: "while gh run watch; do :; done"}}')"

# --- Fail-open on malformed / empty stdin (P3 regression guard) ------------
# EXPECTATION REFRESHED for #7164 (ADR-157), and deliberately TIGHTENED.
#
# The fail-open contract is unchanged and still asserted by (o) below: the hook
# exits 0 and never blocks the session on unparseable input.
#
# What changed is that it no longer emits an explicit {"permissionDecision":
# "allow"}. It records a hook-input fault and passes through silently instead.
# That is strictly better here, for a reason specific to this hook being a
# NON-RESPONDER: it fires on the same tool call as guardrails.sh, which emits
# `ask` on the very same unparseable payload. A non-responder shouting an
# explicit `allow` into that round is at best redundant and at worst overrides
# the prompt, depending on Claude Code's multi-hook precedence — an upstream
# invariant this repo cannot verify, which is exactly what ADR-156 refuses to
# depend on. Emitting nothing removes the question.
assert_decision "(m) malformed JSON stdin: no decision emitted (fault recorded, tool not blocked)" "<none>" 'not json{'
assert_decision "(n) empty stdin: no decision emitted (fault recorded, tool not blocked)" "<none>" ''

# …and the fault is genuinely RECORDED, not silently dropped. Asserting only
# "no output" would pass equally well against a hook that disarmed and said
# nothing, which is defect 2 of #7164.
TOTAL=$((TOTAL + 1))
# ADR-129 rule (c): one owning trap for the tempdir. The suite runs under
# `set -euo pipefail`, so a failure between allocation and the rm below would
# otherwise leak it into /tmp — a machine-global tmpfs shared with sibling
# worktrees.
_bpm_root="$(mktemp -d)"
trap 'rm -rf "$_bpm_root"' EXIT
printf 'not json{' | INCIDENTS_REPO_ROOT="$_bpm_root" bash "$HOOK" >/dev/null 2>&1 || true
if [[ -f "$_bpm_root/.claude/.rule-incidents.jsonl" ]] \
   && grep -q 'hook-input-' "$_bpm_root/.claude/.rule-incidents.jsonl" 2>/dev/null; then
  PASS=$((PASS + 1)); echo "PASS: (m2) malformed stdin records a hook-input fault"
else
  FAIL=$((FAIL + 1)); echo "FAIL: (m2) malformed stdin disarmed the hook with no record"
fi
rm -rf "$_bpm_root"

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
