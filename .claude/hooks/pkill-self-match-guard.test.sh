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
MIN_ASSERTIONS=11

pass() { VERDICTS+=("PASS"); printf '  ok   %s\n' "$1"; }
fail() { VERDICTS+=("FAIL"); printf '  FAIL %s\n' "$1"; }

# $1=name  $2=command-string  $3=deny|allow
run_case() {
  local name="$1" cmd="$2" want="$3" out got
  out="$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then got=deny; else got=allow; fi
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

echo "--- must ALLOW: no -f, or not our shape ---"
run_case "pkill without -f matches the NAME only" 'pkill node; echo node' allow
run_case "pgrep without -f"               'pgrep sshd' allow
run_case "not a pkill/pgrep command"      'grep -rn run-registered-suites .' allow
run_case "captured PID, no pattern"       'sleep 5 & pid=$!; kill "$pid"' allow
run_case "sanctioned helper is never blocked" \
  'source plugins/soleur/scripts/lib/proc.sh; kill_mine' allow

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
