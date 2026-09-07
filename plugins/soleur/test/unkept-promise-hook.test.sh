#!/usr/bin/env bash
# Guard suite for plugins/soleur/hooks/unkept-promise-hook.sh
#
# TWO DIRECTIONS, DELIBERATELY.
#
# A suite whose fixtures all assert must-BLOCK cannot see the predicate becoming
# too aggressive, and over-firing is the failure that gets a gate routed around
# (this repo's own reasoning about gates that cannot pass). Every must-PASS row
# below is therefore load-bearing, not padding: the must-PASS set is the only
# thing that separates "discriminates" from "blocks every turn".
#
# The fixtures are drawn from REAL closing sentences in the 2026-09-07 session
# -- both the three that should have been blocked and the ones that were correct
# handoffs -- so the fixture set models the producer rather than what reads well.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
HOOK="$REPO_ROOT/plugins/soleur/hooks/unkept-promise-hook.sh"
WORK="$(mktemp -d -t unkept-promise.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

# ISOLATE THE HOOK'S STAND-DOWN STATE PER RUN.
#
# The hook keeps a per-session counter under $TMPDIR. With a shared TMPDIR those
# files survive between suite runs, so fixed session ids accumulate firings and
# stand down permanently -- the suite then passes or fails depending on how many
# times it has been run before. Measured: two consecutive runs of the identical
# tree gave 23/0 and then 3 failures. Three runs of an UNCHANGED tree giving
# different results is a harness defect, never a re-run to repeat.
# BOTH variables, because the hook prefers XDG_RUNTIME_DIR over TMPDIR. An
# earlier revision of this suite redirected only TMPDIR; the hook's hostile-/tmp
# hardening then made XDG_RUNTIME_DIR the effective base, state leaked through
# the real per-user runtime dir, and three runs of an UNCHANGED tree gave
# 27/0, 27/0, then 18/9. Whatever the hook may read as its base, the suite must
# redirect.
export TMPDIR="$WORK"
export XDG_RUNTIME_DIR="$WORK"

PASS=0; FAIL=0
FAILURES=()   # append-only: a conservation check on counters alone is silenced
              # by redirecting an increment; printed verdicts are not.

pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); echo "  FAIL: $1"; }

# Each case gets its OWN session id so the stand-down counter from one case
# cannot silence the next -- a shared id would make later must-BLOCK rows pass
# for the wrong reason.
# The id is DERIVED from the message, not from a counter: an incrementing
# variable inside run_hook() lives in a $( ) subshell and never advances in the
# parent, so every case would share one session, the stand-down would trip after
# two blocks, and every later must-BLOCK row would pass for the wrong reason.
# That is exactly what the first draft of this harness did.
run_hook() { # <message> -> echoes "BLOCK" or "ALLOW"
  local msg="$1" out sid
  sid=$(printf '%s' "$msg" | md5sum | cut -c1-12)
  out=$(jq -n --arg m "$msg" --arg s "case$sid" \
        '{last_assistant_message:$m, session_id:$s}' | bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    echo "BLOCK"
  else
    echo "ALLOW"
  fi
}

expect() { # <want> <label> <message>
  local want="$1" label="$2" msg="$3" got
  got=$(run_hook "$msg")
  [ "$got" = "$want" ] && pass "$label" || fail "$label (want $want, got $got)"
}

echo "=== instrument self-test (both counters must move) ==="
_p0=$PASS; _f0=$FAIL
pass "self-check: pass() increments"
fail "self-check: fail() increments (EXPECTED, not a defect)"
[ "$PASS" -gt "$_p0" ] && [ "$FAIL" -gt "$_f0" ] \
  || { printf '[FATAL] assertion helpers do not both move their counters\n' >&2; exit 2; }
PASS=$((PASS - 1)); FAIL=$((FAIL - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'

echo "=== must BLOCK: real closings from the 2026-09-07 session ==="
expect BLOCK "verbatim instance 1: 'Implementing the drafted wording verbatim now'" \
  "The ruling is comprehensive and every citation checks out. Implementing the drafted wording verbatim now, plus the audits determination and the register entry."
expect BLOCK "verbatim instance 2: 'I'll run those rather than describe them'" \
  "Remaining on #7891: emit the review trailer, then ship. I'll run those rather than describe them."
expect BLOCK "verbatim instance 3: 'I'll probe them rather than reason about them, then build'" \
  "Both are empirical. I'll probe them rather than reason about them, then build."
expect BLOCK "'let me' + imminent" \
  "That settles the design question. Let me now write the plan and open the PR."
expect BLOCK "bare gerund announcement" \
  "All four load-bearing claims verified against the records. Running the full battery now."
expect BLOCK "'I will' + next" \
  "The determination holds on the replaced ground. I will implement the wording next."

echo "=== must PASS: correct handoffs that must NOT be blocked ==="
expect ALLOW "conditional on the operator ('say the word')" \
  "My recommendation is to ship the corrected core and file the rest. Say the word and I'll run it."
expect ALLOW "explicit operator gate sentinel" \
  "Capture the last-used timestamp before rotating. <promise>OPERATOR-GATE: waiting on the Sentry credential entry</promise>"
expect ALLOW "explicit DONE sentinel" \
  "Merged, verified on main, worktree cleaned. <promise>DONE</promise>"
expect ALLOW "trailing question is a genuine stop" \
  "Ship it in the plugin, or keep it in this repo's .claude/hooks?"
expect ALLOW "conditional 'if you'" \
  "Blocking is more effective and carries a real wedge risk. If you'd rather I warn first, I'll change it."
expect ALLOW "past tense -- work already done" \
  "Committed and pushed. lint-legal-registers: 7 assertions, 0 failed. The register entry that was missing is now indexed."
expect ALLOW "waiting on a background agent, not on itself" \
  "Three agents are still running. I'll report what they find rather than assume it is clean."
expect ALLOW "prose about a FUTURE session, not this turn" \
  "The follow-up this earns is widening the rule from issue state to credential liveness, which is not in this PR."
expect ALLOW "operator's action, not mine" \
  "Your action is unchanged: rotate the token in prd_terraform once the timestamp is captured."

echo "=== fail-open: infrastructure problems must never wedge a turn ==="
out=$(printf '' | bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && [ -z "$out" ] && pass "empty stdin -> allow (rc=0, no decision)" \
  || fail "empty stdin must allow, got rc=$rc out='$out'"
out=$(printf 'not json at all' | bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && [ -z "$out" ] && pass "malformed stdin -> allow" \
  || fail "malformed stdin must allow, got rc=$rc"
out=$(jq -n '{session_id:"x"}' | bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && [ -z "$out" ] && pass "missing last_assistant_message -> allow" \
  || fail "missing field must allow, got rc=$rc"

echo "=== independence from the UNPROVEN tool_calls field ==="
# The hook must behave identically whether or not `.tool_calls` is present --
# it is documented but unused anywhere in this repo, and a predicate depending
# on an absent field silently never fires.
a=$(jq -n --arg m "Let me now write the plan." --arg s "tc-a" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null || true); a=${a:-none}
b=$(jq -n --arg m "Let me now write the plan." --arg s "tc-b" '{last_assistant_message:$m,session_id:$s,tool_calls:[{tool_name:"Bash"}]}' | bash "$HOOK" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null || true); b=${b:-none}
[ "$a" = "$b" ] && [ "$a" = "block" ] && pass "verdict identical with and without tool_calls present" \
  || fail "tool_calls presence changed the verdict ($a vs $b) -- hook must not depend on it"

echo "=== hostile /tmp: the state dir must be refused, not followed ==="
# The counter must persist between turns, so the path is necessarily
# predictable. On a shared machine that is a real primitive: `mkdir -p` succeeds
# THROUGH a symlink (measured), turning the counter write into a file-clobber at
# an attacker-chosen path, and a pre-seeded counter silently disables the guard.
_atk=$(mktemp -d); _victim=$(mktemp -d)
ln -s "$_victim" "$_atk/soleur-unkept-promise"
_out=$(jq -n '{last_assistant_message:"Let me now do it.",session_id:"atk"}' \
       | XDG_RUNTIME_DIR= TMPDIR="$_atk" bash "$HOOK" 2>/dev/null); _rc=$?
[ "$_rc" = "0" ] && pass "symlinked state dir -> fails open (rc=0)" \
  || fail "symlinked state dir must fail open, got rc=$_rc"
[ "$(ls -A "$_victim" | wc -l)" = "0" ] \
  && pass "symlinked state dir -> NOTHING written to the symlink target" \
  || fail "wrote into the symlink target -- file-clobber primitive is live"
rm -rf "$_atk" "$_victim"

# A pre-seeded counter owned by ANOTHER user would disable the guard. We cannot
# create a foreign-owned file in an unprivileged test, so pin the two mechanical
# properties that make that unreachable: the dir is created 0700, and the hook
# refuses a state dir it does not own.
_perm=$(mktemp -d)
jq -n '{last_assistant_message:"Let me now do it.",session_id:"perm"}' \
  | XDG_RUNTIME_DIR= TMPDIR="$_perm" bash "$HOOK" >/dev/null 2>&1
_mode=$(stat -c '%a' "$_perm/soleur-unkept-promise" 2>/dev/null || echo "missing")
[ "$_mode" = "700" ] && pass "state dir created mode 0700 (no other-user writes)" \
  || fail "state dir mode is $_mode, want 700"
grep -q '\-O "\$STATE_DIR"' "$HOOK" \
  && pass "hook refuses a state dir it does not own (-O check present)" \
  || fail "no ownership check on the state dir"
rm -rf "$_perm"

echo "=== stand-down after repeated firing (false-positive bound) ==="
S="standdown"
r1=$(jq -n --arg m "Let me now do it." --arg s "$S" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null || true); r1=${r1:-none}
r2=$(jq -n --arg m "Let me now do it." --arg s "$S" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null || true); r2=${r2:-none}
r3=$(jq -n --arg m "Let me now do it." --arg s "$S" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null || true); r3=${r3:-none}
[ "$r1" = "block" ] && [ "$r2" = "block" ] && [ "$r3" = "none" ] \
  && pass "blocks twice then stands down (never fights the operator indefinitely)" \
  || fail "stand-down sequence wrong: $r1/$r2/$r3 (want block/block/none)"

echo "=== the escape hatch CLEARS the counter (a declared stop is not penalised) ==="
S2="clears"
jq -n --arg m "Let me now do it." --arg s "$S2" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" >/dev/null 2>&1
jq -n --arg m "<promise>DONE</promise>" --arg s "$S2" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" >/dev/null 2>&1
r=$(jq -n --arg m "Let me now do it." --arg s "$S2" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null || true); r=${r:-none}
[ "$r" = "block" ] && pass "a declared stop resets the counter" \
  || fail "counter not reset by the escape hatch (got $r)"

echo "=== the block payload is actionable ==="
body=$(jq -n --arg m "Let me now do it." --arg s "payload" '{last_assistant_message:$m,session_id:$s}' | bash "$HOOK" 2>/dev/null)
printf '%s' "$body" | jq -e '.reason | test("OPERATOR-GATE")' >/dev/null 2>&1 \
  && pass "block reason names the escape hatch" || fail "block reason does not name the escape hatch"
printf '%s' "$body" | jq -e '.reason | test("in THIS turn")' >/dev/null 2>&1 \
  && pass "block reason states the required action" || fail "block reason does not state the action"

# --- assertion floor: emitted DIRECTLY, never through the helpers it backstops
# Derived from a MEASURED green run (23), never from expectation -- an
# aspirational floor fails a correct suite and gets lowered until it is inert.
MIN_ASSERTIONS=27
echo ""
echo "=== $PASS passed, $FAIL failed ==="
if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILURES[@]}" >&2
fi
if [ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] assertion floor: ran %s, expected >= %s -- assertions were removed or silenced\n' \
    "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
# Conservation: the printed FAILURES ledger is append-only, so silencing the
# counter alone cannot produce a green run.
if [ "${#FAILURES[@]}" -ne "$FAIL" ]; then
  printf '[FATAL] conservation: %s FAIL(s) counted but %s recorded\n' "$FAIL" "${#FAILURES[@]}" >&2
  exit 1
fi
[ "$FAIL" -eq 0 ] || exit 1
exit 0
