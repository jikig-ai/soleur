#!/usr/bin/env bash
# Tests for monitor-supersede-guard.sh.
#
# The load-bearing half is the ALLOW cases. A deny gate that fires on everything
# is indistinguishable from a working one until it blocks legitimate work, so
# every fall-through branch below is a must-PASS row, not decoration.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor-supersede-guard.sh"
PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES + 1)); if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

WORK="$(mktemp -d -t monsup-XXXXXX)" || exit 2
trap 'rm -rf "$WORK"' EXIT

# Each case gets its own ledger so rows cannot leak into one another.
fresh() { LEDGER="$WORK/ledger-$1.jsonl"; : > "$LEDGER"; export SOLEUR_MONITOR_LEDGER="$LEDGER"; }

# run <session> <json-tool_input> [tool_name]  -> echoes hook stdout
run() {
  local sess="$1" ti="$2" tool="${3:-Monitor}"
  jq -nc --arg s "$sess" --arg t "$tool" --argjson ti "$ti" \
    '{session_id:$s, tool_name:$t, tool_input:$ti}' | bash "$HOOK" 2>/dev/null
}
denied() { printf '%s' "$1" | grep -q '"permissionDecision": *"deny"'; }

CI='{"command":"gh pr checks 7753 --json name,state","description":"ci","timeout_ms":600000}'
CI2='{"command":"gh pr checks 7753 --json state","description":"ci again","timeout_ms":600000}'
OTHER='{"command":"gh pr checks 9999 --json state","description":"other pr","timeout_ms":600000}'

# --- POSITIVE CONTROL: the helpers can both move -----------------------------
_p=$PASS; _f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS - _p)) -ne 1 ] || [ $((FAIL - _f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2; exit 1
fi
PASS=$_p; FAIL=$_f

# --- 1. first arm is always allowed ------------------------------------------
fresh 1
out=$(run s1 "$CI")
rc=1; denied "$out" || rc=0
verdict "$rc" 'a first monitor on a target is ALLOWED'

# --- 2. second arm on the SAME target is denied ------------------------------
fresh 2
run s1 "$CI" >/dev/null
out=$(run s1 "$CI2")
rc=1; denied "$out" && rc=0
verdict "$rc" 'a second monitor on the SAME pr is DENIED (the #7753 case)'

# --- 3. a DIFFERENT target is allowed ----------------------------------------
fresh 3
run s1 "$CI" >/dev/null
out=$(run s1 "$OTHER")
rc=1; denied "$out" || rc=0
verdict "$rc" 'a monitor on a DIFFERENT pr is ALLOWED'

# --- 4. a different SESSION is allowed ---------------------------------------
fresh 4
run s1 "$CI" >/dev/null
out=$(run s2 "$CI2")
rc=1; denied "$out" || rc=0
verdict "$rc" 'another session watching the same pr is ALLOWED (ledger is session-scoped)'

# --- 5. TaskStop clears the block --------------------------------------------
fresh 5
run s1 "$CI" >/dev/null
run s1 '{"task_id":"abc"}' TaskStop >/dev/null
out=$(run s1 "$CI2")
rc=1; denied "$out" || rc=0
verdict "$rc" 'after TaskStop the same target is ALLOWED again'

# --- 6. an expired arm no longer blocks --------------------------------------
fresh 6
run s1 '{"command":"gh pr checks 7753","description":"short","timeout_ms":1000}' >/dev/null
sleep 2
out=$(run s1 "$CI2")
rc=1; denied "$out" || rc=0
verdict "$rc" 'an arm past its own timeout no longer blocks'

# --- 7. the override hatch works ---------------------------------------------
fresh 7
run s1 "$CI" >/dev/null
out=$(run s1 '{"command":"gh pr checks 7753 # gate-override: monitor-supersede","description":"x","timeout_ms":600000}')
rc=1; denied "$out" || rc=0
verdict "$rc" 'the override marker suppresses the deny'

# --- 8. no extractable signature => never blocked ----------------------------
fresh 8
run s1 '{"command":"tail -f nothing-identifiable","description":"a"}' >/dev/null
out=$(run s1 '{"command":"tail -f also-nothing","description":"b"}')
rc=1; denied "$out" || rc=0
verdict "$rc" 'commands with no extractable target are never blocked'

# --- 9. path signature collides ----------------------------------------------
fresh 9
run s1 '{"command":"grep X /var/tmp/soleur/run.log","description":"p1","timeout_ms":600000}' >/dev/null
out=$(run s1 '{"command":"tail /var/tmp/soleur/run.log","description":"p2","timeout_ms":600000}')
rc=1; denied "$out" && rc=0
verdict "$rc" 'two monitors on the same absolute log path collide'

# --- 10. workflow signature collides -----------------------------------------
fresh 10
run s1 '{"command":"gh run list --workflow ci.yml","description":"w1","timeout_ms":600000}' >/dev/null
out=$(run s1 '{"command":"gh run list --workflow ci.yml --json x","description":"w2","timeout_ms":600000}')
rc=1; denied "$out" && rc=0
verdict "$rc" 'two monitors on the same workflow collide'

# --- 11. malformed stdin fails OPEN ------------------------------------------
fresh 11
out=$(printf 'not json' | bash "$HOOK" 2>/dev/null)
rc=1; denied "$out" || rc=0
verdict "$rc" 'malformed stdin fails OPEN (a no-op hook is never a false block)'

# --- 12. a non-Monitor tool is ignored ---------------------------------------
fresh 12
run s1 "$CI" >/dev/null
out=$(run s1 "$CI2" Bash)
rc=1; denied "$out" || rc=0
verdict "$rc" 'a Bash call carrying the same text is ignored'

# --- 13. THE PRIMARY FLOW MUST NOT BE BLOCKED ---------------------------------
# ship Phase 7 polls merge, then release workflows, then CI. If this hook denied
# any leg of that, it would break the flow it exists to help. The three legs carry
# different signatures (pr / workflow / workflow), so they must all be ALLOWED.
# Verified against the commands in ship/SKILL.md Phase 7 rather than invented.
fresh 13
run s1 '{"command":"while true; do gh pr view 7753 --json state,mergeStateStatus; sleep 30; done","description":"merge wait","timeout_ms":1800000}' >/dev/null
run s1 '{"command":"while true; do gh run list --workflow web-platform-release.yml --branch main; sleep 30; done","description":"release wait","timeout_ms":1800000}' >/dev/null
out=$(run s1 '{"command":"gh run list --workflow ci.yml --branch main","description":"ci wait","timeout_ms":1800000}')
rc=1; denied "$out" || rc=0
verdict "$rc" "ship Phase 7's merge->release->ci sequence is ALLOWED end to end (different targets never collide)"

# --- 14. A LATE re-arm is allowed; an EARLY one is not ------------------------
# The distinguishing observation, measured 2026-09-03: real layering happens FAST
# (the incident's three monitors were minutes apart on 45-55 minute windows, i.e.
# single-digit percent elapsed), whereas a re-arm LATE in a window is almost always
# replacing a watcher that has already finished — which a hook cannot observe. So
# "still live" is scoped to the early fraction of the prior window, not all of it.
# Without this the author's own next re-arm would have been denied.
fresh 14
run s1 '{"command":"gh pr checks 7753","description":"early prior","timeout_ms":4000}' >/dev/null
out=$(run s1 '{"command":"gh pr checks 7753 --json state","description":"immediate re-arm","timeout_ms":4000}')
rc=1; denied "$out" && rc=0
verdict "$rc" 'an IMMEDIATE re-arm (the layering shape) is still DENIED'

fresh 15
run s1 '{"command":"gh pr checks 7753","description":"aging prior","timeout_ms":4000}' >/dev/null
sleep 3   # >50% of the 4s window
out=$(run s1 '{"command":"gh pr checks 7753 --json state","description":"late re-arm","timeout_ms":4000}')
rc=1; denied "$out" || rc=0
verdict "$rc" 'a re-arm LATE in the prior window is ALLOWED (the watcher has almost certainly finished)'

printf '\n'
EXPECTED_CASES=15
if [ "$CASES" -ne "$EXPECTED_CASES" ]; then
  printf '[FATAL] vacuity floor: %d cases executed, expected exactly %d\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [ $((PASS + FAIL)) -ne "$CASES" ]; then
  printf '[FATAL] accounting: %d verdicts across %d cases\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
if [ "$FAIL" -ne 0 ]; then printf 'FAILED: %d/%d\n' "$FAIL" "$CASES"; exit 1; fi
printf 'OK: %d/%d\n' "$PASS" "$CASES"
