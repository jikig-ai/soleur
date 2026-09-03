#!/usr/bin/env bash
# Drift guard: every hook suite whose hook can emit an incident must redirect
# that telemetry into a sandbox, by sourcing lib/test-incident-sandbox.sh.
#
# WHY A GUARD AND NOT JUST THE FIX. Measured 2026-09-03: 12 suites wrote 396
# rows into the operator's live `.claude/.rule-incidents.jsonl` in a single
# sweep — 316 from iac-plan-write-guard.test.sh alone. That file is what
# `compound` Phase 1.5 reads as deviation evidence and what
# `rule-metrics-aggregate.sh` keys its counters on, so the fixtures were being
# scored as real rule violations.
#
# WHY THE CHECK IS "SOURCES THE HELPER" AND NOT "MENTIONS INCIDENTS_REPO_ROOT".
# Every one of those 12 suites already mentioned the variable. They set it
# inline on SOME hook invocations and missed others, and partial isolation is
# indistinguishable from full isolation to a grep for the NAME — which is
# precisely how the gap survived review. Sourcing the helper is *sufficient*:
# it exports before any case runs, so an individual call site cannot forget it.
# The check is therefore precise, not a proxy.
#
# ZERO, not a baseline. A grandfathered allowlist would assert nothing on day
# one; the tree was taken to zero deliberately, so zero is enforceable.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES+1)); if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

# --- POSITIVE CONTROL --------------------------------------------------------
_p=$PASS; _f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS-_p)) -ne 1 ] || [ $((FAIL-_f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2; exit 1
fi
PASS=$_p; FAIL=$_f

# --- 1. EVERY hook suite sources the sandbox --------------------------------
# No filename pairing. An earlier revision derived the population as
# `*.test.sh` whose sibling `*.sh` emits — and `security_reminder_hook` is a
# `.py`, so it fell outside the population, kept writing the real ledger, AND
# was invisible to this guard, which used the same enumeration. A population
# derived by naming convention silently excludes whatever does not follow it.
# Requiring it of every suite costs nothing (the helper is inert for a suite
# that never emits) and has no such blind spot.
missing=""; population=0
for t in "$HERE"/*.test.sh; do
  [ "$(basename "$t")" = "incident-sandbox-coverage.test.sh" ] && continue
  population=$((population+1))
  grep -q 'test-incident-sandbox\.sh' "$t" 2>/dev/null || missing="${missing} $(basename "$t")"
done
rc=1; [ -z "$missing" ] && rc=0
verdict "$rc" "every hook suite sources the sandbox helper${missing:+ (missing:$missing)}"

# --- 2. the population is non-empty ------------------------------------------
# Without this, deleting the enumeration above leaves case 1 vacuously green.
rc=1; [ "$population" -ge 40 ] && rc=0
verdict "$rc" "the enumeration found a real population ($population suites, floor 40)"

# --- 3. the helper actually redirects ----------------------------------------
REAL="$HERE/../.rule-incidents.jsonl"
[ -f "$REAL" ] || : > "$REAL" 2>/dev/null || true
before=$(wc -l < "$REAL" 2>/dev/null || echo 0)
( # shellcheck source=/dev/null
  . "$HERE/lib/test-incident-sandbox.sh"
  # shellcheck source=/dev/null
  . "$HERE/lib/incidents.sh" 2>/dev/null || exit 0
  emit_incident sandbox-probe warn "probe" "cmd" ) >/dev/null 2>&1
after=$(wc -l < "$REAL" 2>/dev/null || echo 0)
rc=1; [ "$before" = "$after" ] && rc=0
verdict "$rc" "an emit under the helper leaves the real ledger untouched ($before -> $after)"

# --- 4. NON-VACUITY: without the helper, the same emit DOES land -------------
# Case 3 alone would pass if emit_incident were simply broken. This proves the
# probe can write, so case 3 is measuring redirection and not silence.
SB=$(mktemp -d -t sbctl-XXXXXX)
mkdir -p "$SB/.claude"
( INCIDENTS_REPO_ROOT="$SB" ; export INCIDENTS_REPO_ROOT
  # shellcheck source=/dev/null
  . "$HERE/lib/incidents.sh" 2>/dev/null || exit 0
  emit_incident sandbox-probe warn "probe" "cmd" ) >/dev/null 2>&1
n=$(wc -l < "$SB/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)
rm -rf "$SB"
rc=1; [ "$n" -ge 1 ] && rc=0
verdict "$rc" "the same emit DOES write when pointed at a sandbox (case 3 is not vacuous)"

printf '\n'
MIN_CASES=4
if [ "$CASES" -lt "$MIN_CASES" ]; then
  printf '[FATAL] vacuity floor: %d cases executed, expected at least %d\n' "$CASES" "$MIN_CASES" >&2; exit 1
fi
if [ $((PASS+FAIL)) -ne "$CASES" ]; then
  printf '[FATAL] accounting: PASS+FAIL=%d but CASES=%d\n' "$((PASS+FAIL))" "$CASES" >&2; exit 1
fi
if [ "$FAIL" -gt 0 ]; then printf 'FAILED: %d/%d\n' "$FAIL" "$CASES"; exit 1; fi
printf 'OK: %d/%d\n' "$PASS" "$CASES"
