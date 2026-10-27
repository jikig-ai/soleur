#!/usr/bin/env bash
# test-all-parallel-scheduler.test.sh — the parallel scheduler's contract guard (#8231).
#
# What this suite proves about scripts/test-all.sh's --jobs/SOLEUR_TEST_JOBS mode:
#
#   A1  the registered suite population is identical under parallel scheduling —
#       every run_suite registration produces exactly one rendered verdict,
#       so the terminal `=== N/M suites passed ===` denominator matches the
#       serial walk, and nothing is dropped, double-run, or misattributed.
#   A2  the top-level exit contract is preserved: a planted FAIL exits 1, a
#       planted signal-shaped exit renders [KILLED] and exits 3, a clean run
#       exits 0, and a decline keeps its skip semantics.
#   A3  verdict lines print in REGISTRATION order after drain — a late
#       registration finishing first cannot reorder the report.
#   A4  token-intersecting suites never overlap in time (shared-resource
#       serialization), and a `*` suite runs with a drained pool.
#   A5  parallel execution actually happened on this host: at least one pair of
#       independent fixtures' windows overlap (a degenerate-serial pool would
#       pass every other assertion while delivering nothing).
#   A6  the serial fallback arms: lock-not-held falls back to serial with a
#       named banner; --jobs=1 and jobs=0-class requests resolve serial; a
#       malformed value exits 2.
#   A7  the in-flight liveness pair `[run] <label> started/done` and the
#       tmp_delta=unattributed honesty field are emitted in parallel mode.
#
# The sandbox follows the killed-classification convention: copy the runner,
# assert each splice anchor occurs exactly once, neuter the advisory lock and
# preamble, replace the registration window with fixture calls. The scheduler's
# own additions sit INSIDE that window, so the fixture body re-arms them
# explicitly: a faked lock-held marker, then _pj_resolve_run_mode, then the
# fixture run_suite calls, then _pj_drain — the resolution call the real runner
# makes after the lock is preserved verbatim by living in the fixture body.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
export REPO_ROOT

PASSES=0; FAILURES=0
pass() { PASSES=$((PASSES + 1)); printf '[pass] %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf '[FAIL] %s\n' "$1"; }
dump() { sed 's/^/    /' <<<"${1:-}"; }

# macOS lacks `date +%N`; EPOCHREALTIME is bash 5+. Fixtures below write
# nanosecond stamps via `date +%s%N` where GNU coreutils exists — the sandbox
# arms that need it run on linux only (CI + dev hosts here).
TARGET="$REPO_ROOT/scripts/test-all.sh"
[[ -f "$TARGET" ]] || { echo "FATAL: $TARGET not found"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t8231.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FIXTURES="$TMP/fixtures"
mkdir -p "$FIXTURES"

# --- Fixtures ---------------------------------------------------------------
# Timeline writers: each appends S/E nanosecond stamps to a shared log so the
# test can compute window overlap exactly, rather than inferring it.
mk_timeline_fixture() {  # <name> <sleep_s>
  cat > "$FIXTURES/$1.sh" <<EOF
#!/usr/bin/env bash
echo "S $1 \$(date +%s%N)" >> "$FIXTURES/timeline.log"
sleep "$2"
echo "E $1 \$(date +%s%N)" >> "$FIXTURES/timeline.log"
echo "out-$1"
echo "err-$1" >&2
exit 0
EOF
  chmod +x "$FIXTURES/$1.sh"
}
mk_timeline_fixture indA 0.4
mk_timeline_fixture indB 0.4
mk_timeline_fixture indC 0.4
mk_timeline_fixture tokA 0.4
mk_timeline_fixture tokB 0.4
mk_timeline_fixture starS 0.4

cat > "$FIXTURES/fail.sh" <<'EOF'
#!/usr/bin/env bash
echo "this fixture fails on purpose"
exit 1
EOF
cat > "$FIXTURES/selfterm.sh" <<'EOF'
#!/usr/bin/env bash
kill -TERM $$
sleep 5
exit 0
EOF
cat > "$FIXTURES/ok.sh" <<'EOF'
#!/usr/bin/env bash
echo "fixture ok"
exit 0
EOF
chmod +x "$FIXTURES"/*.sh

# --- Sandbox builder --------------------------------------------------------
# $1 = out path, $2 = arm name.
build_sandbox() {
  local out="$1" arm="$2"
  cp "$TARGET" "$out" || return 1
  mkdir -p "$(dirname "$out")/lib" || return 1
  # repo-write-boundary.sh stays a literal cp — the boundary-relocator census
  # keys on that form. The others go through the variable loop so the file list
  # lives in one place.
  cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$(dirname "$out")/lib/" || return 1
  for _lib in test-relevance-paths.sh test-suite-lanes.sh; do
    cp "$REPO_ROOT/scripts/lib/$_lib" "$(dirname "$out")/lib/" || return 1
  done
  python3 - "$out" "$arm" "$FIXTURES" <<'PY'
import sys
path, arm, fixtures = sys.argv[1:4]
s = open(path).read()

def sub_once(hay, old, new, what):
    assert hay.count(old) == 1, f"expected exactly one {what}, found {hay.count(old)}"
    return hay.replace(old, new)

start_anchor = 'tc_acquire "test-all"'
end_anchor = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(start_anchor) == 1, "start anchor not unique"
assert s.count(end_anchor) == 1, "end anchor not unique"
i = s.index(start_anchor) + len(start_anchor)
j = s.index(end_anchor)

# Fixture body: fake the lock-held verdict (the sandbox neutered tc_acquire),
# resolve the run mode, register the arm's fixtures, drain. _pj_resolve_run_mode
# reads SOLEUR_TEST_JOBS from the environment the arm invocation exports.
prelude = '''
declare -gA _SESSION_LOCK_ACQUIRED 2>/dev/null || true
_SESSION_LOCK_ACQUIRED[test-all]=1
_pj_lock_held=1
_pj_resolve_run_mode
lane_declare "tokA" "artifact:fixture-shared" "fixture token pair A"
lane_declare "tokB" "artifact:fixture-shared" "fixture token pair B"
lane_declare "starS" "*" "fixture drain barrier"
'''
calls = {
    "clean":     [("indA","indA.sh"),("indB","indB.sh"),("indC","indC.sh")],
    "mixed":     [("indA","indA.sh"),("bad","fail.sh"),("indC","indC.sh")],
    "killed":    [("selfterm","selfterm.sh"),("indA","indA.sh")],
    "tokens":    [("tokA","tokA.sh"),("tokB","tokB.sh"),("indC","indC.sh")],
    "star":      [("indA","indA.sh"),("starS","starS.sh"),("indB","indB.sh"),("indC","indC.sh")],
    "order":     [("first","indC.sh"),("second","indB.sh"),("third","indA.sh")],
    "one":       [("okfixture","ok.sh")],
}[arm]
body = prelude + "".join(
    f'run_suite "{label}" bash "{fixtures}/{script}"\n' for label, script in calls
) + "_pj_drain\n"
s = s[:i] + body + s[j:]

s = sub_once(s, 'tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 'tc_acquire call')
import re
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)

open(path, 'w').write(s)
print("sandbox built")
PY
}

run_arm() {  # <arm> [jobs-env] — an EMPTY second arg leaves the knob unset (serial arm)
  local arm="$1" jobs="${2-4}"
  local sb="$TMP/runner-${arm}-${jobs}.sh"
  ARM_OUT=""; ARM_RC=-1
  rm -f "$FIXTURES/timeline.log"
  build_sandbox "$sb" "$arm" >/dev/null || { fail "sandbox build failed: $arm"; return 1; }
  ARM_OUT=$(cd "$REPO_ROOT" && env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
            TEST_TIMING_LOG="${TIMING_FILE:-/dev/null}" TEST_GROUP=all \
            ${jobs:+SOLEUR_TEST_JOBS="$jobs"} timeout 120 bash "$sb" 2>&1)
  ARM_RC=$?
  return 0
}

verdict_lines() { grep -oE '^\[(ok|FAIL|KILLED|TRIPWIRE|UNACCOUNTED)\] [^ ]+' <<<"$1" | awk '{print $2}'; }

# --- A1: population parity ---------------------------------------------------
run_arm clean 4 || true
vl="$(verdict_lines "$ARM_OUT")"
if [[ "$vl" == $'indA\nindB\nindC' && "$ARM_RC" == "0" ]]; then
  pass "A1 — every registration renders exactly one verdict; clean parallel run exits 0"
else
  fail "A1 — verdict lines '$vl' or rc=$ARM_RC wrong"; dump "$ARM_OUT"
fi
if grep -qE '^=== 3/3 suites passed ===$' <<<"$ARM_OUT"; then
  pass "A1 — the terminal marker denominator equals the registration count"
else
  fail "A1 — terminal marker wrong"; dump "$ARM_OUT"
fi
if grep -q '\[parallel\] mode engaged' <<<"$ARM_OUT"; then
  pass "A5b — the mode banner announced the engaged width"
else
  fail "A5b — no [parallel] mode-engaged banner"; dump "$ARM_OUT"
fi

# --- A5: parallel actually ran ----------------------------------------------
if python3 - "$FIXTURES/timeline.log" <<'PY'
import sys
wins = {}
for line in open(sys.argv[1]):
    k, label, ns = line.split()
    wins.setdefault(label, {})[k] = int(ns)
labels = sorted(wins)
overlap = any(
    wins[a]['S'] < wins[b]['E'] and wins[b]['S'] < wins[a]['E']
    for i, a in enumerate(labels) for b in labels[i+1:]
    if 'S' in wins[a] and 'E' in wins[a] and 'S' in wins[b] and 'E' in wins[b]
)
sys.exit(0 if overlap else 1)
PY
then
  pass "A5 — at least one independent pair's windows overlap (parallel scheduling engaged)"
else
  fail "A5 — no window overlap: the pool degenerated to serial"
fi

# --- A3: registration-order rendering ---------------------------------------
run_arm order 4 || true
order_out="$(grep -E '^--- (first|second|third) ---$' <<<"$ARM_OUT" | tr -d '-' | tr -d ' ' | paste -sd, -)"
if [[ "$order_out" == "first,second,third" ]]; then
  pass "A3 — verdict blocks print in registration order after drain"
else
  fail "A3 — order was $order_out"; dump "$ARM_OUT"
fi

# --- A2a: a planted FAIL exits 1 ---------------------------------------------
run_arm mixed 4 || true
if [[ "$ARM_RC" == "1" ]]; then
  pass "A2 — a fixture failure exits 1 under parallel mode"
else
  fail "A2 — mixed arm exited $ARM_RC, expected 1"; dump "$ARM_OUT"
fi
if grep -qE '^\[FAIL\] bad ' <<<"$ARM_OUT"; then
  pass "A2 — [FAIL] line survives the scheduler (unmasked)"
else
  fail "A2 — no [FAIL] bad line"; dump "$ARM_OUT"
fi
if grep -qE '^\[ok\] indA ' <<<"$ARM_OUT" && grep -qE '^\[ok\] indC ' <<<"$ARM_OUT"; then
  pass "A2 — the sibling ok verdicts are preserved beside the failure"
else
  fail "A2 — ok siblings missing"; dump "$ARM_OUT"
fi
if grep -qE '^=== 2/3 suites passed ===$' <<<"$ARM_OUT"; then
  pass "A2 — the marker counts the failure correctly"
else
  fail "A2 — marker wrong"; dump "$ARM_OUT"
fi

# --- A2b: signal-shaped exit stays [KILLED] + exit 3 -------------------------
run_arm killed 4 || true
if [[ "$ARM_RC" == "3" ]]; then
  pass "A2 — a signal-shaped fixture exit resolves to exit 3"
else
  fail "A2 — killed arm exited $ARM_RC, expected 3"; dump "$ARM_OUT"
fi
if grep -qE '^\[KILLED\] selfterm ' <<<"$ARM_OUT"; then
  pass "A2 — [KILLED] marker emitted for a 128+15 wait status"
else
  fail "A2 — no [KILLED] selfterm line"; dump "$ARM_OUT"
fi
if grep -qE '^=== 2 suites: 1 passed, 0 failed, 1 killed' <<<"$ARM_OUT"; then
  pass "A2 — the summary names the killed count"
else
  fail "A2 — summary line wrong"; dump "$ARM_OUT"
fi

# --- A4a: shared-token suites never overlap ----------------------------------
run_arm tokens 4 || true
if [[ "$ARM_RC" == "0" ]]; then
  pass "A4 — the token arm completed cleanly"
else
  fail "A4 — token arm exited $ARM_RC"; dump "$ARM_OUT"
fi
if python3 - "$FIXTURES/timeline.log" <<'PY'
import sys
wins = {}
for line in open(sys.argv[1]):
    k, label, ns = line.split()
    wins.setdefault(label, {})[k] = int(ns)
a, b = wins['tokA'], wins['tokB']
overlap = a['S'] < b['E'] and b['S'] < a['E']
sys.exit(1 if overlap else 0)
PY
then
  pass "A4 — tokA and tokB (shared artifact token) never ran concurrently"
else
  fail "A4 — token-intersecting fixtures OVERLAPPED"
fi

# --- A4b: a `*` suite runs with a drained pool -------------------------------
run_arm star 4 || true
if python3 - "$FIXTURES/timeline.log" <<'PY'
import sys
wins = {}
for line in open(sys.argv[1]):
    k, label, ns = line.split()
    wins.setdefault(label, {})[k] = int(ns)
star = wins['starS']
bad = [l for l, w in wins.items() if l != 'starS' and 'S' in w and 'E' in w
       and star['S'] < w['E'] and w['S'] < star['E']]
sys.exit(1 if bad else 0)
PY
then
  pass "A4 — the * barrier suite ran with an empty pool"
else
  fail "A4 — the * suite overlapped another fixture"
fi

# --- A7: liveness + honesty fields -------------------------------------------
TIMING_FILE="$TMP/timing.log"
run_arm clean 4 || true
if grep -qE '^\[run\] indA started' <<<"$ARM_OUT" && grep -qE '^\[run\] indA done' <<<"$ARM_OUT"; then
  pass "A7 — [run] started/done liveness pairs are emitted on stderr"
else
  fail "A7 — no [run] liveness lines"; dump "$ARM_OUT"
fi
if grep -q $'tmp_delta=' "$TIMING_FILE" 2>/dev/null; then
  pass "A7 — timing rows carry the tmp_delta field"
else
  fail "A7 — no tmp_delta fields in $TIMING_FILE"; dump "$(cat "$TIMING_FILE" 2>/dev/null || true)"
fi
unset TIMING_FILE

# --- A6: fallback arms --------------------------------------------------------
run_arm clean "" || true
if [[ "$ARM_RC" == "0" ]] && ! grep -q '\[parallel\] mode engaged' <<<"$ARM_OUT"; then
  pass "A6 — unset SOLEUR_TEST_JOBS runs serial (the measured default), silently"
else
  fail "A6 — unset-knob arm did not run serial"; dump "$ARM_OUT"
fi
run_arm clean 1 || true
if [[ "$ARM_RC" == "0" ]] && ! grep -q '\[parallel\] mode engaged' <<<"$ARM_OUT"; then
  pass "A6 — jobs=1 resolves serial"
else
  fail "A6 — jobs=1 arm went parallel"; dump "$ARM_OUT"
fi

# lock-not-held arm: same sandbox, but no _SESSION_LOCK_ACQUIRED fake.
sb_nolock="$TMP/runner-nolock.sh"
cp "$TARGET" "$sb_nolock"
mkdir -p "$TMP/lib"
cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$TMP/lib/"
for _lib in test-relevance-paths.sh test-suite-lanes.sh; do
  cp "$REPO_ROOT/scripts/lib/$_lib" "$TMP/lib/"
done
python3 - "$sb_nolock" "$FIXTURES" <<'PY'
import sys, re
path, fixtures = sys.argv[1:3]
s = open(path).read()
a = 'tc_acquire "test-all"'
b = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(a) == 1 and s.count(b) == 1
i = s.index(a) + len(a); j = s.index(b)
body = '''
_pj_lock_held=0
_pj_resolve_run_mode
run_suite "okfixture" bash "''' + fixtures + '''/ok.sh"
_pj_drain
'''
s = s[:i] + body + s[j:]
s = s.replace(a, 'true "test-all"  # sandbox: lock neutered', 1)
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
open(path, 'w').write(s)
PY
NL_OUT=$(cd "$REPO_ROOT" && env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
        TEST_TIMING_LOG=/dev/null TEST_GROUP=all SOLEUR_TEST_JOBS=8 \
        timeout 60 bash "$sb_nolock" 2>&1) || true
if grep -q 'serial fallback — reason=lock-not-held' <<<"$NL_OUT"; then
  pass "A6 — lock-not-held falls back to serial with a named banner"
else
  fail "A6 — no lock-not-held fallback banner"; dump "$NL_OUT"
fi
if ! grep -q '\[parallel\] mode engaged' <<<"$NL_OUT"; then
  pass "A6 — the lock-not-held run never went wide"
else
  fail "A6 — lock-not-held run engaged parallel anyway"
fi

# jobs validation: malformed values exit 2. The `|| RC=$?` shape is required —
# a bare `VAR=$(cmd)` under `set -e` aborts on the non-zero before $? is read.
JB_RC=0
JB_OUT=$(cd "$REPO_ROOT" && env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
        TEST_TIMING_LOG=/dev/null TEST_GROUP=all SOLEUR_TEST_JOBS=banana \
        timeout 60 bash "$sb_nolock" 2>&1) || JB_RC=$?
if [[ "$JB_RC" == "2" ]]; then
  pass "A6 — a malformed SOLEUR_TEST_JOBS refuses with exit 2"
else
  fail "A6 — SOLEUR_TEST_JOBS=banana exited $JB_RC, expected 2"; dump "$JB_OUT"
fi
JB2_RC=0
JB2_OUT=$(cd "$REPO_ROOT" && env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
        TEST_TIMING_LOG=/dev/null TEST_GROUP=all SOLEUR_TEST_JOBS=bogus \
        timeout 60 bash scripts/test-all.sh --enumerate 2>&1) || JB2_RC=$?
if [[ "${JB2_RC:-0}" == "2" ]]; then
  pass "A6 — a malformed --jobs/SOLEUR_TEST_JOBS refuses before doing work (exit 2)"
else
  fail "A6 — malformed knob exited ${JB2_RC:-?}, expected 2"; dump "$JB2_OUT"
fi

# --- Done --------------------------------------------------------------------
echo ""
echo "=== test-all-parallel-scheduler: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
