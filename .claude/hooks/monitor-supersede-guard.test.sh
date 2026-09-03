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

# Point the incident logger at a throwaway repo root. Without this the suite
# writes synthetic `deny` rows into the operator's real
# .claude/.rule-incidents.jsonl on every run — measured at 4 rows per run — which
# poisons rule-metrics-aggregate.sh's input. Same class commit dd8683701 forbids.
mkdir -p "$WORK/fakeroot/.claude/hooks/lib"
cp .claude/hooks/lib/incidents.sh "$WORK/fakeroot/.claude/hooks/lib/" 2>/dev/null || true
export CLAUDE_PROJECT_DIR="$WORK/fakeroot"

# Each case gets its own ledger so rows cannot leak into one another.
fresh() { LEDGER="$WORK/ledger-$1.jsonl"; : > "$LEDGER"; export SOLEUR_MONITOR_LEDGER="$LEDGER"; }

# run <session> <json-tool_input> [tool_name]  -> echoes hook stdout
run() {
  local sess="$1" ti="$2" tool="${3:-Monitor}"
  jq -nc --arg s "$sess" --arg t "$tool" --argjson ti "$ti" \
    '{session_id:$s, tool_name:$t, tool_input:$ti}' | bash "$HOOK" 2>/dev/null
}
warned() { printf '%s' "$1" | grep -q '"systemMessage"'; }
blocked() { printf '%s' "$1" | grep -q '"permissionDecision"'; }

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
rc=1; warned "$out" || rc=0
verdict "$rc" 'a first monitor on a target is ALLOWED'

# --- 2. second arm on the SAME target is warned ------------------------------
fresh 2
run s1 "$CI" >/dev/null
out=$(run s1 "$CI2")
rc=1; warned "$out" && rc=0
verdict "$rc" 'a second monitor on the SAME pr is REPORTED (the #7753 case)'

# --- 3. a DIFFERENT target is allowed ----------------------------------------
fresh 3
run s1 "$CI" >/dev/null
out=$(run s1 "$OTHER")
rc=1; warned "$out" || rc=0
verdict "$rc" 'a monitor on a DIFFERENT pr is ALLOWED'

# --- 4. a different SESSION is allowed ---------------------------------------
fresh 4
run s1 "$CI" >/dev/null
out=$(run s2 "$CI2")
rc=1; warned "$out" || rc=0
verdict "$rc" 'another session watching the same pr is ALLOWED (ledger is session-scoped)'

# --- 5. TaskStop clears the notice --------------------------------------------
fresh 5
run s1 "$CI" >/dev/null
run s1 '{"task_id":"abc"}' TaskStop >/dev/null
out=$(run s1 "$CI2")
rc=1; warned "$out" || rc=0
verdict "$rc" 'after TaskStop the same target is silent again'

# --- 6. an expired arm is no longer reported --------------------------------------
fresh 6
run s1 '{"command":"gh pr checks 7753","description":"short","timeout_ms":1000}' >/dev/null
sleep 2
out=$(run s1 "$CI2")
rc=1; warned "$out" || rc=0
verdict "$rc" 'an arm past its own timeout is no longer reported'

# --- 7. the RETIRED override marker is inert ---------------------------------
# The hatch existed to escape a false deny. With no deny there is nothing to
# escape, so the marker must carry no special meaning — otherwise it survives as
# a magic string that silently suppresses a notice.
fresh 7
run s1 "$CI" >/dev/null
out=$(run s1 '{"command":"gh pr checks 7753 # gate-override: monitor-supersede","description":"x","timeout_ms":600000}')
rc=1; warned "$out" && rc=0
verdict "$rc" 'the retired override marker no longer suppresses the notice'

# --- 8. no extractable signature => never reported ----------------------------
fresh 8
run s1 '{"command":"tail -f nothing-identifiable","description":"a"}' >/dev/null
out=$(run s1 '{"command":"tail -f also-nothing","description":"b"}')
rc=1; warned "$out" || rc=0
verdict "$rc" 'commands with no extractable target are never reported'

# --- 9. path signature collides ----------------------------------------------
fresh 9
run s1 '{"command":"grep X /var/tmp/soleur/run.log","description":"p1","timeout_ms":600000}' >/dev/null
out=$(run s1 '{"command":"tail /var/tmp/soleur/run.log","description":"p2","timeout_ms":600000}')
rc=1; warned "$out" && rc=0
verdict "$rc" 'two monitors on the same absolute log path collide'

# --- 10. workflow signature collides -----------------------------------------
fresh 10
run s1 '{"command":"gh run list --workflow ci.yml","description":"w1","timeout_ms":600000}' >/dev/null
out=$(run s1 '{"command":"gh run list --workflow ci.yml --json x","description":"w2","timeout_ms":600000}')
rc=1; warned "$out" && rc=0
verdict "$rc" 'two monitors on the same workflow collide'

# --- 11. malformed stdin fails OPEN ------------------------------------------
fresh 11
out=$(printf 'not json' | bash "$HOOK" 2>/dev/null)
rc=1; warned "$out" || rc=0
verdict "$rc" 'malformed stdin fails OPEN and silent'

# --- 12. a non-Monitor tool is ignored ---------------------------------------
fresh 12
run s1 "$CI" >/dev/null
out=$(run s1 "$CI2" Bash)
rc=1; warned "$out" || rc=0
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
rc=1; warned "$out" || rc=0
verdict "$rc" "ship Phase 7's merge->release->ci sequence is ALLOWED end to end (different targets never collide)"

# --- 14/15. RECENCY, honestly named ------------------------------------------
# This was an early-vs-late split gated on 50% of the prior window, justified as
# "still live". That premise is unobservable — see the hook header. What remains
# is recency: an arm inside its own declared window MIGHT still be running, so it
# is worth mentioning; one past its window cannot be, so it is not.
fresh 14
run s1 '{"command":"gh pr checks 7753","description":"prior","timeout_ms":4000}' >/dev/null
out=$(run s1 '{"command":"gh pr checks 7753 --json state","description":"immediate re-arm","timeout_ms":4000}')
rc=1; warned "$out" && rc=0
verdict "$rc" 'a re-arm INSIDE the prior window is REPORTED'

fresh 15
run s1 '{"command":"gh pr checks 7753","description":"aging prior","timeout_ms":3000}' >/dev/null
sleep 4   # past the whole 3s window, not a fraction of it
out=$(run s1 '{"command":"gh pr checks 7753 --json state","description":"late re-arm","timeout_ms":3000}')
rc=1; warned "$out" || rc=0
verdict "$rc" 'a re-arm after the prior window EXPIRES is silent'

# --- 16. A MALFORMED LEDGER LINE MUST NOT DISABLE THE GATE --------------------
# `jq -rs` is all-or-nothing: one unparseable line failed the whole slurp, the
# `|| PRIOR=""` swallowed it, and an empty PRIOR reads as "no prior arm" — so a
# single torn record turned the gate off permanently and silently. Measured
# before the fix: this case was ALLOWED.
fresh 16
run s1 "$CI" >/dev/null
printf 'CORRUPT NOT JSON\n' >> "$LEDGER"
out=$(run s1 "$CI2")
rc=1; warned "$out" && rc=0
verdict "$rc" 'a malformed ledger line does NOT disable the gate (unparseable lines are skipped, not fatal)'

# --- 17. A NEWLINE IN description MUST NOT KILL THE DENY ----------------------
# PRIOR became multi-line, `cut -f1` yielded two lines, and the arithmetic on a
# newline-bearing string was fatal under `set -u` — the hook exited 0 having
# printed nothing, so the tool proceeded. Measured before the fix:
# `line 145: line2: unbound variable`, NOT denied.
fresh 17
run s1 '{"command":"gh pr checks 7753","description":"line1\nline2","timeout_ms":600000}' >/dev/null
out=$(run s1 "$CI2")
rc=1; warned "$out" && rc=0
verdict "$rc" 'a newline in a prior description does NOT crash the deny path'

# --- 18. TELEMETRY LANDS AS A READABLE ROW ------------------------------------
# emit_incident takes <rule_id> <event_type> <prefix>. Transposed, every firing
# landed as rule_id="deny" and was invisible to rule-metrics-aggregate.sh, which
# keys its counters on rule_id. Assert the ROW the hook actually wrote, not the
# call's source text: a grep for the literal passes just as well when the helper's
# signature changes underneath it.
fresh 18
INC="$CLAUDE_PROJECT_DIR/.claude/.rule-incidents.jsonl"
: > "$INC" 2>/dev/null || true
run s1 "$CI" >/dev/null
run s1 "$CI2" >/dev/null
rc=1
if [ -r "$INC" ]; then
  jq -e 'select(.rule_id == "monitor-supersede" and .event_type == "warn")' "$INC" >/dev/null 2>&1 && rc=0
fi
verdict "$rc" 'the firing writes a row keyed rule_id=monitor-supersede, event_type=warn'

# --- 19. A LEDGER POISONED BY AN OLDER HOOK VERSION ---------------------------
# Case 17 only reaches the WRITE-time sanitiser: with `tr -d '\n\t'` in place a
# newline can no longer enter the ledger through this hook, so reverting the
# READ-time guard leaves 17 green (measured — the mutation survived). The
# read-time guard exists for a record written by a PRE-FIX hook or edited by
# hand, which the suite cannot produce through the new code path. So inject one
# directly. Without the guard this aborts under `set -u` before the deny.
fresh 19
now=$(date +%s)
# `\\n` in the source: printf emits a literal backslash-n, i.e. VALID JSON whose
# decoded .desc carries a real newline. A raw newline would be invalid JSON and
# would exercise case 16 instead of the read-time guard this case exists for.
printf '{"event":"arm","session":"s1","sig":"pr:7753","desc":"line1\\nline2","ts":%s,"window":600}\n' "$now" >> "$LEDGER"
out=$(run s1 "$CI2")
rc=1; warned "$out" && rc=0
verdict "$rc" 'a ledger record containing a raw newline (written by an older hook) still denies, rather than aborting'

# --- 20. THE INVARIANT: this hook never blocks -------------------------------
# The whole redesign rests on this. Drive every colliding shape through the hook
# and assert not one of them emits a permissionDecision at all — so a future edit
# that reintroduces a deny fails here rather than in someone's ship run.
fresh 20
rc=0
run s1 "$CI" >/dev/null
for probe in "$CI2" \
  '{"command":"gh pr checks 7753 # gate-override: monitor-supersede","description":"o","timeout_ms":600000}' \
  '{"command":"grep X /var/tmp/soleur/run.log","description":"p","timeout_ms":600000}'; do
  blocked "$(run s1 "$probe")" && rc=1
done
verdict "$rc" 'no input shape produces a permissionDecision — the hook cannot block'

printf '\n'
EXPECTED_CASES=20
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
