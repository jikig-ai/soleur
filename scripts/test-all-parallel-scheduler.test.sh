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
#       serialization), and a `*` suite runs alone: it is PARKED by the pooled
#       scheduler and launches at the drain, after every non-`*` suite (#12231).
#   A5  parallel execution actually happened on this host: at least one pair of
#       independent fixtures' windows overlap (a degenerate-serial pool would
#       pass every other assertion while delivering nothing).
#   A6  the serial fallback arms: lock-not-held falls back to serial with a
#       named banner; --jobs=1 and jobs=0-class requests resolve serial; a
#       malformed value exits 2.
#   A7  the in-flight liveness pair `[run] <label> started/done` and the
#       tmp_delta=unattributed honesty field are emitted in parallel mode.
#   A8  (#12013) a red is visible at reap: the live `done` line carries the suite's
#       wall time, a non-zero rc is marked provisional (a signal-shaped one
#       unresolved), the authoritative [FAIL] verdict is unchanged and still
#       printed once, after the live line; and the pool width is a runner-only
#       carrier that no suite the runner spawns inherits.
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
MIN_PASSES_FLOOR=80   # the full green count; raise it in the same edit that adds an arm
pass() { PASSES=$((PASSES + 1)); printf '[pass] %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf '[FAIL] %s\n' "$1"; }
dump() { sed 's/^/    /' <<<"${1:-}"; }

# macOS lacks `date +%N`; EPOCHREALTIME is bash 5+. Fixtures below write
# nanosecond stamps via `date +%s%N` where GNU coreutils exists — the sandbox
# arms that need it run on linux only (CI + dev hosts here).
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"  # overridable: point at a mutant to prove the rows red
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
mk_timeline_fixture slowL 1.2
mk_timeline_fixture starT 0.4
mk_timeline_fixture starM 0.4

cat > "$FIXTURES/fail.sh" <<'EOF'
#!/usr/bin/env bash
echo "this fixture fails on purpose"
exit 1
EOF
cat > "$FIXTURES/sigred.sh" <<'EOF'
#!/usr/bin/env bash
# Interrupt the RUNNER (TERM to the pid the sandbox exported), then exit 1: a red reaped by an interrupted run.
kill -TERM "${SIGRED_TARGET:?}"
sleep 0.3
exit 1
EOF
cat > "$FIXTURES/selfterm.sh" <<'EOF'
#!/usr/bin/env bash
kill -TERM $$
sleep 5
exit 0
EOF
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$FIXTURES"
cat > "$FIXTURES/envprobe.sh" <<'EOF'
#!/usr/bin/env bash
# Records whether SOLEUR_TEST_JOBS is in this process's environment (#12013).
if [ -n "${SOLEUR_TEST_JOBS+x}" ]; then own=set; else own=absent; fi
if [ -n "${SOLEUR_PJ_PROVISIONAL_FILE+x}" ]; then pj=set; else pj=absent; fi
if [ -n "${SOLEUR_PJ_FIFO+x}" ]; then ff=set; else ff=absent; fi
printf '%s\n%s\n%s\n' "$own" "$pj" "$ff" > "${PROBE_OUT:?PROBE_OUT is not set}"
exit 0
EOF
cat > "$FIXTURES/ok.sh" <<'EOF'
#!/usr/bin/env bash
echo "fixture ok"
exit 0
EOF
chmod +x "$FIXTURES"/*.sh

# Release-file fixtures (#12013 backfill arms). The ORDER of two suites is decided by files, never by
# sleeps: <waitfor> is polled (at most <maxtenths> tenths of a second, so a scheduler that never lets the
# releasing suite start still terminates), <writeat> says when this suite creates its own release file.
mk_rel_fixture() {  # <name> <sleep_s> <waitfor|-> <writeat:start|end|none> [maxtenths]
  local name="$1" slp="$2" wf="$3" wa="$4" mt="${5:-20}"
  assert_fixture_dir "$FIXTURES"
  cat > "$FIXTURES/$name.sh" <<EOF
#!/usr/bin/env bash
echo "S $name \$(date +%s%N)" >> "$FIXTURES/timeline.log"
[ "$wa" = start ] && : > "$FIXTURES/rel.$name"
if [ "$wf" != "-" ]; then
  for _i in \$(seq 1 $mt); do [ -e "$FIXTURES/$wf" ] && break; sleep 0.1; done
fi
sleep "$slp"
[ "$wa" = end ] && : > "$FIXTURES/rel.$name"
echo "E $name \$(date +%s%N)" >> "$FIXTURES/timeline.log"
exit 0
EOF
  chmod +x "$FIXTURES/$name.sh"
}
mk_timeline_fixture indD 0.4
mk_timeline_fixture indE 0.4
mk_rel_fixture holdT  0.05 rel.indA2 none 20   # holds token T until indA2 has STARTED (or 2 s elapse)
mk_rel_fixture headT  0.2  -        none
mk_rel_fixture headY  0.3  -        none
mk_rel_fixture xU     0.3  -        none
mk_rel_fixture indA2  0.4  -        start      # independent that releases holdT/holdQ when it starts
mk_rel_fixture holdQ  0.05 rel.indA2 none 20   # barrier arm: holds T; released by indA2 starting
mk_rel_fixture holdD  0.3  -        none       # holds T for 0.3 s without waiting on anyone (drain-order and torn star arms)
mk_rel_fixture holdX  0.05 rel.indA2 none 20   # accumulation arm: live holder of X
mk_rel_fixture holdY  0.05 rel.indA2 none 20   # accumulation arm: live holder of Y
mk_rel_fixture qA     0.3  -        none
mk_rel_fixture qB     0.3  -        none
mk_rel_fixture s1     0.3  -        none
mk_rel_fixture qC     0.3  -        none
mk_exit_fixture() {  # <rc> — a suite that exits with exactly <rc>
  assert_fixture_dir "$FIXTURES"
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$FIXTURES/exit$1.sh"
  chmod +x "$FIXTURES/exit$1.sh"
}
for _erc in 128 130 137 160 255; do mk_exit_fixture "$_erc"; done

# tl_check "S:a<E:b" "E:x>=S:y" ... - every clause must hold over $FIXTURES/timeline.log (ns stamps).
# A missing label is a FAILED clause, never a skipped one. Self-tested below.
tl_check() {  # [--log <file>] <clause>...
  local log="$FIXTURES/timeline.log"
  if [[ "${1:-}" == --log ]]; then log="$2"; shift 2; fi
  python3 - "$log" "$@" <<'PY'
import sys, re
log, clauses = sys.argv[1], sys.argv[2:]
w = {}
for line in open(log):
    k, label, ns = line.split()
    w.setdefault(label, {})[k] = int(ns)
bad = 0
for c in clauses:
    m = re.fullmatch(r'([SE]):(\w+)(<|>=)([SE]):(\w+)', c)
    assert m, "bad clause " + c
    a = w.get(m.group(2), {}).get(m.group(1)); b = w.get(m.group(5), {}).get(m.group(4))
    if a is None or b is None:
        print("MISSING stamp for", c); bad += 1; continue
    ok = (a < b) if m.group(3) == '<' else (a >= b)
    if not ok:
        print("FAILED", c, a - b); bad += 1
sys.exit(1 if bad else 0)
PY
}
started_order() { grep -oE '^\[run\] [^ ]+ started' <<<"$1" | awk '{print $2}' | tr '\n' ' '; }
# run_pos <label> <started|done> - line number of the runner's own `[run]` line in ARM_OUT (empty when absent).
# These lines are written by the runner process itself, so their order is the order of its launch and reap events.
run_pos() { grep -nE "^\[run\] $1 $2" <<<"$ARM_OUT" | head -1 | cut -d: -f1 || true; }

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
lane_declare "starT" "*" "fixture second drain barrier"
lane_declare "starM" "* artifact:bfM" "fixture multi-token drain barrier"
lane_declare "holdD" "artifact:bfT" "backfill fixture: holds T for a fixed 0.3 s"
lane_declare "holdT" "artifact:bfT" "backfill fixture: holds T"
lane_declare "holdQ" "artifact:bfT" "backfill fixture: holds T (barrier arm)"
lane_declare "headT" "artifact:bfT" "backfill fixture: queued head blocked on T"
lane_declare "headY" "artifact:bfT artifact:bfU" "backfill fixture: head on T and U"
lane_declare "xU" "artifact:bfU" "backfill fixture: shares only U with headY"
lane_declare "holdX" "artifact:bfX" "backfill fixture: live holder of X"
lane_declare "holdY" "artifact:bfY" "backfill fixture: live holder of Y"
lane_declare "qA" "artifact:bfX artifact:bfW" "backfill fixture: first queued, blocked by live X, owns W"
lane_declare "s1" "artifact:bfX" "backfill fixture: skips on X alone (whole-set dedupe arm)"
lane_declare "qB" "artifact:bfY" "backfill fixture: second queued, blocked by live Y"
lane_declare "qC" "artifact:bfW" "backfill fixture: conflicts ONLY with the queued qA (W), not with anything live"
'''
calls = {
    "clean":     [("indA","indA.sh"),("indB","indB.sh"),("indC","indC.sh")],
    "mixed":     [("indA","indA.sh"),("bad","fail.sh"),("indC","indC.sh")],
    "killed":    [("selfterm","selfterm.sh"),("indA","indA.sh")],
    "tokens":    [("tokA","tokA.sh"),("tokB","tokB.sh"),("indC","indC.sh")],
    "star":      [("indA","indA.sh"),("starS","starS.sh"),("slowL","slowL.sh"),("indB","indB.sh")],
    "starblk":   [("holdT","holdT.sh"),("headT","headT.sh"),("starS","starS.sh"),("indA","indA2.sh")],
    "twostars":  [("indA","indA.sh"),("starS","starS.sh"),("starT","starT.sh"),("indB","indB.sh")],
    "dstar":     [("indA","indA.sh"),("dstar","nonexistent-derived-star.sh"),("indB","indB.sh")],
    "drainord":  [("holdD","holdD.sh"),("starS","starS.sh"),("headT","headT.sh")],
    "starfirst": [("starS","starS.sh")] + [(f"ok{i}","ok.sh") for i in range(10)],
    "starlast":  [("indA","indA.sh"),("indB","indB.sh"),("starS","starS.sh")],
    "starsig":   [("starS","starS.sh"),("sigred","sigred.sh"),("indA","indA.sh")],
    "starm":     [("holdQ","holdQ.sh"),("starM","starM.sh"),("indA","indA2.sh")],
    "starorn":   [("holdD","holdD.sh"),("starS","starS.sh")],
    "order":     [("first","indC.sh"),("second","indB.sh"),("third","indA.sh")],
    "one":       [("okfixture","ok.sh")],
    "envprobe":  [("envprobe","envprobe.sh")],
    "livered":   [("slowL","slowL.sh"),("bad","fail.sh")],
    "sigred":    [("sigred","sigred.sh"),("indA","indA.sh")],
    "rcs":       [("bad","fail.sh"),("r128","exit128.sh"),("r255","exit255.sh"),("r160","exit160.sh"),("r130","exit130.sh"),("r137","exit137.sh")],
    "couple":    [],
    "bf7":       [("holdX","holdX.sh"),("s1","s1.sh"),("qA","qA.sh"),("qC","qC.sh"),("indA","indA2.sh")],
    "bf6":       [("holdX","holdX.sh"),("holdY","holdY.sh"),("qA","qA.sh"),("qB","qB.sh"),("qC","qC.sh"),("indA","indA2.sh")],
    "bf1":       [("holdT","holdT.sh"),("headT","headT.sh"),("indA","indA2.sh"),("indB","indB.sh"),("indC","indC.sh")],
    "bf5":       [("holdT","holdT.sh"),("headT","headT.sh"),("indA","indA2.sh"),("indB","indB.sh"),("indC","indC.sh"),("indD","indD.sh"),("indE","indE.sh")],
    "bf2":       [("holdT","holdT.sh"),("headY","headY.sh"),("xU","xU.sh"),("indA","indA2.sh")],
    "bf3":       [("holdQ","holdQ.sh"),("starS","starS.sh"),("indA","indA2.sh")],
    "torn":      [("holdT","holdT.sh"),("headT","headT.sh")],
    "many":      [("starS","starS.sh")] + [(f"ok{i}","ok.sh") for i in range(60)],
}[arm]
extra = {
    # The runner's own pid, so the sigred fixture really interrupts the RUNNER (not its worker wrapper).
    "sigred": '''
export SIGRED_TARGET=$$
''',
    # Drive the sidecar writer for a spread of rcs and print the runner's own class for each.
    "couple": '''
for _rc in 1 2 127 128 129 130 137 143 160 192 193 255; do
  _provisional_append "rc$_rc" "$_rc"; echo "CLASS $_rc $(suite_exit_class "$_rc")"
done
''',
    # Simulate the torn reap of _pj_reap: wait -n returns with an EMPTY -p variable once (the job
    # left the table first). `rp` is the caller's local; bash scoping lets the shadowing function clear it.
    "torn": '''
_tear_once=1
wait() { builtin wait "$@"; local _r=$?; if (( _tear_once == 1 )); then _tear_once=0; rp=""; fi; return $_r; }
''',
    # Count lane_tokens_conflict calls (a clock-free cost check on the fill pass).
    "many": '''
eval "$(declare -f lane_tokens_conflict | sed '1s/lane_tokens_conflict/_ltc_orig/')"
lane_tokens_conflict() { printf x >> "''' + fixtures + '''/conflict.count"; _ltc_orig "$@"; }
''',
}
extra["starsig"] = extra["sigred"]   # star arms reuse the interrupt and torn-reap shims
extra["starorn"] = extra["torn"]
extra = extra.get(arm, "")
body = prelude + extra + "".join(
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

# Stamp each output line with the wall clock (ns) it ARRIVED at, tab-separated, so a test can tell a line
# printed while a suite was still running from one replayed after it finished.
ts_filter() { local l; while IFS= read -r l; do printf '%s\t%s\n' "$(date +%s%N)" "$l"; done; }

run_arm() {  # <arm> [jobs-env] — an EMPTY second arg leaves the knob unset (serial arm)
  local arm="$1" jobs="${2-4}"
  local sb="$TMP/runner-${arm}-${jobs}.sh"
  ARM_OUT=""; ARM_RC=-1
  rm -f "$FIXTURES/timeline.log"
  build_sandbox "$sb" "$arm" >/dev/null || { fail "sandbox build failed: $arm"; return 1; }
  if ARM_OUT=$(cd "$REPO_ROOT" && env -u CI -u SOLEUR_PJ_FIFO SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= \
            ${ARM_FIFO:+SOLEUR_PJ_FIFO="$ARM_FIFO"} TEST_TIMING_LOG="${TIMING_FILE:-/dev/null}" TEST_GROUP=all \
            ${jobs:+SOLEUR_TEST_JOBS="$jobs"} timeout 120 bash "$sb" 2>&1 | { if [[ "${ARM_TS:-}" == 1 ]]; then ts_filter; else cat; fi; }); then
    ARM_RC=0
  else
    ARM_RC=$?
  fi
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
order_out="$(grep -E '^--- (first|second|third) ---$' <<<"$ARM_OUT" | tr -d '-' | tr -d ' ' | paste -sd, -)" || true
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

# --- A4b: a `*` suite runs alone, at the drain (#12231) ------------------------
# indA, starS, slowL, indB: the `*` is parked by the scheduler, so it starts only after BOTH later suites
# (slowL holds a 1.2 s window, so a premature launch overlaps it for at least 0.8 s) have ended.
TIMING_FILE="$TMP/timing.star"; : > "$TIMING_FILE"
run_arm star 4 || true
STAR_VERDICTS="$(verdict_lines "$ARM_OUT" | tr '\n' ' ')"; STAR_RC="$ARM_RC"
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
  pass "A4 - the * suite ran alone (its window overlaps no other fixture)"
else
  fail "A4 - the * suite overlapped another fixture"
fi
if tl_check "S:starS>=E:indB" "S:starS>=E:slowL" "S:starS>=E:indA"; then
  pass "A4 - star-last: the * suite started only after the suites registered both before and after it had ended"
else
  fail "A4 - star-last: the * started while an independent was still running (a parked * must launch at the drain)"; dump "$(cat "$FIXTURES/timeline.log")"
fi
if [[ "$STAR_RC" == "0" && "$STAR_VERDICTS" == "indA starS slowL indB " ]] && grep -qE '^=== 4/4 suites passed ===$' <<<"$ARM_OUT"; then
  pass "A4 - a parked * leaves the verdict lines, exit code and terminal marker in registration order"
else
  fail "A4 - star arm verdicts '$STAR_VERDICTS' rc=$STAR_RC"; dump "$ARM_OUT"
fi
STAR_TIMING_ORDER="$(cut -f1 "$TIMING_FILE" | tr '\n' ' ')"
if [[ "$STAR_TIMING_ORDER" == "indA starS slowL indB " ]]; then
  pass "A4 - TEST_TIMING_LOG rows keep registration order under a parked *"
else
  fail "A4 - timing rows '$STAR_TIMING_ORDER'"; dump "$(cat "$TIMING_FILE")"
fi
if grep -E '^starS	' "$TIMING_FILE" | grep -qE 'tmp_delta=-?[0-9]+$'; then
  pass "A4 - the parked * launched solo, so its tmp_delta is a number (not unattributed)"
else
  fail "A4 - starS tmp_delta is not numeric: $(grep -E '^starS' "$TIMING_FILE" | tr '\t' '>')"
fi
unset TIMING_FILE

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

# --- A8: a red is visible at reap (#12013) ------------------------------------
# The live `[run] <label> done` line is the only signal an operator polling the log sees before
# the drain replays the verdicts in registration order. It must say how long the suite took, and
# must not read as the final word on a non-zero rc. The authoritative text — `[FAIL] bad (Nms)` —
# is untouched and still appears exactly once, after the live line.
run_arm mixed 4 || true
if grep -qE '^\[run\] bad done \(rc=1, [0-9]+ms\) — provisional' <<<"$ARM_OUT"; then
  pass "A8 — a red suite's live line carries its rc, wall time and a provisional marker"
else
  fail "A8 — no provisional live line for the failing suite"; dump "$ARM_OUT"
fi
if grep -qE '^\[run\] indA done \(rc=0, [0-9]+ms\)$' <<<"$ARM_OUT"; then
  pass "A8 — a passing suite's live line carries its wall time and no marker"
else
  fail "A8 — passing live line wrong"; dump "$ARM_OUT"
fi
n_fail="$(grep -cE '^\[FAIL\] ' <<<"$ARM_OUT" || true)"
if [[ "$n_fail" == "1" ]]; then
  pass "A8 — exactly one [FAIL] verdict line (the live line did not add a second)"
else
  fail "A8 — expected exactly one ^[FAIL] line, got $n_fail"; dump "$ARM_OUT"
fi
live_ln="$(grep -nE '^\[run\] bad done ' <<<"$ARM_OUT" | head -1 | cut -d: -f1 || true)"
verd_ln="$(grep -nE '^\[FAIL\] bad ' <<<"$ARM_OUT" | head -1 | cut -d: -f1 || true)"
if [[ -n "$live_ln" && -n "$verd_ln" ]] && (( live_ln < verd_ln )); then
  pass "A8 — the live line precedes the drain verdict"
else
  fail "A8 — live line ($live_ln) does not precede the verdict ($verd_ln)"; dump "$ARM_OUT"
fi
# A line merely PRINTED before another proves nothing against a replay in reap order, so compare the clock:
# the red's live line must arrive before the slow suite (registered first) has finished running.
ARM_TS=1 run_arm livered 4 || true
bad_ts="$(grep -E $'\t\\[run\\] bad done ' <<<"$ARM_OUT" | head -1 | cut -f1 || true)"
slow_end="$(awk '$1=="E" && $2=="slowL" {print $3; exit}' "$FIXTURES/timeline.log" 2>/dev/null)"
if [[ "$bad_ts" =~ ^[0-9]+$ && "$slow_end" =~ ^[0-9]+$ ]] && (( bad_ts < slow_end )); then
  pass "A8 — the red's live line arrived while a slower suite was still running (not replayed after it)"
else
  fail "A8 — live line stamp '$bad_ts' is not before the slow suite's end '$slow_end'"; dump "$ARM_OUT"
fi
run_arm killed 4 || true
if grep -qE '^\[run\] selfterm done \(rc=143, [0-9]+ms\) — signal-shaped, unresolved' <<<"$ARM_OUT"; then
  pass "A8 — a signal-shaped rc is labelled unresolved, not provisional-failed (ADR-177)"
else
  fail "A8 — signal-shaped live line wrong"; dump "$ARM_OUT"
fi
# The pool width is consumed by the runner and demoted from the environment, like TEST_GROUP
# (#11939): a suite that itself runs a nested test-all.sh must not inherit a pool request.
PROBE_FILE="$TMP/envprobe.reading"; rm -f "$PROBE_FILE"
export PROBE_OUT="$PROBE_FILE"; run_arm envprobe 4 || true; unset PROBE_OUT
if [[ "$(sed -n 1p "$PROBE_FILE" 2>/dev/null)" == "absent" ]]; then
  pass "A8 — SOLEUR_TEST_JOBS is not in the environment of a suite the runner spawns"
else
  fail "A8 — the pool width leaked into a spawned suite: $(cat "$PROBE_FILE" 2>/dev/null || echo '<no reading>')"; dump "$ARM_OUT"
fi
if grep -q '\[parallel\] mode engaged' <<<"$ARM_OUT"; then
  pass "A8 — the demotion did not disarm the pool (mode still engaged)"
else
  fail "A8 — the pool did not engage on the probe arm"; dump "$ARM_OUT"
fi

# Static pins for A8: one writer for the live line, one demotion, and no reintroduced raw print.
n_helper="$(grep -c '^_pj_fmt_done "\?\$' <(sed 's/^[[:space:]]*//' "$TARGET") || true)"
n_raw="$(grep -c "printf '\[run\] %s done (rc=%s)" "$TARGET" || true)"
n_def="$(grep -c '^_pj_fmt_done() {' "$TARGET" || true)"
n_dem="$(grep -c '^export -n SOLEUR_TEST_JOBS$' "$TARGET" || true)"
if [[ "$n_def" == "1" && "$n_helper" == "3" && "$n_raw" == "0" ]]; then
  pass "A8 — the live done line has one definition and exactly three call sites, no raw print survives"
else
  fail "A8 — helper defs=$n_def call-sites=$n_helper raw-prints=$n_raw (want 1/3/0)"
fi
if [[ "$n_dem" == "1" ]]; then
  pass "A8 — SOLEUR_TEST_JOBS is demoted from the environment exactly once"
else
  fail "A8 — expected one 'export -n SOLEUR_TEST_JOBS', found $n_dem"
fi

# --- A9: the provisional-red sidecar (#12013) --------------------------------------
# affected-tests.sh hands the runner SOLEUR_PJ_PROVISIONAL_FILE; the runner appends one
# `label<TAB>rc<TAB>epoch` line per red at exactly two sites (the pool reap line, the serial tail), only for
# the runner's own `failed` class (suite_exit_class), and demotes the variable from the environment of every suite it spawns. The gate reads the file
# only when its budget kills the run (plugins/soleur/scripts/affected-tests.test.sh F4).
SC="$TMP/provisional.sidecar"
sidecar_run() {  # <arm> <jobs> — fresh empty sidecar, run, leave the file for inspection
  assert_fixture_dir "$TMP"
  : > "$SC"; export SOLEUR_PJ_PROVISIONAL_FILE="$SC"; run_arm "$1" "$2" || true; unset SOLEUR_PJ_PROVISIONAL_FILE
}
t_a="$(date +%s)"
sidecar_run mixed 4
t_b="$(date +%s)"
if [[ "$(wc -l < "$SC")" == "1" ]] && awk -F'\t' -v a="$t_a" -v b="$t_b" 'NR==1 && $1=="bad" && $2==1 && $3>=a && $3<=b+1 {ok=1} END {exit !ok}' "$SC"; then
  pass "A9 — pool: a planted red is recorded once as 'bad<TAB>1<TAB>epoch' (the reap site)"
else
  fail "A9 — pool sidecar wrong: $(tr '\t\n' '>|' < "$SC")"; dump "$ARM_OUT"
fi
sidecar_run mixed ""
if [[ "$(wc -l < "$SC")" == "1" ]] && awk -F'\t' '$1=="bad" && $2==1 && $3 ~ /^[0-9]+$/ {ok=1} END {exit !ok}' "$SC"; then
  pass "A9 — serial: the same red is recorded once (the run_suite tail site; no double count with the verdict)"
else
  fail "A9 — serial sidecar wrong: $(tr '\t\n' '>|' < "$SC")"; dump "$ARM_OUT"
fi
sidecar_run clean 4
if [[ ! -s "$SC" && "$ARM_RC" == "0" ]]; then
  pass "A9 — control: an all-green pool run writes nothing"
else
  fail "A9 — clean run wrote '$(tr '\t\n' '>|' < "$SC")' (rc=$ARM_RC)"
fi
sidecar_run killed 4
if [[ ! -s "$SC" ]]; then
  pass "A9 — a signal-shaped rc (143) is never recorded as a red (ADR-177: unresolved, not failed)"
else
  fail "A9 — signal-shaped rc was recorded: $(tr '\t\n' '>|' < "$SC")"; dump "$ARM_OUT"
fi
# Measured 2026-11-05: with the runner genuinely interrupted, the drain TERMs the worker, which exits as a NAMED
# signal (the `killed` class, never recorded), so deleting the `_pj_sig == 1` line in _provisional_append survives
# this arm. The line is kept as defense in depth; this arm pins the OBSERVABLE (nothing recorded, run non-zero).
sidecar_run sigred 4
if [[ ! -s "$SC" && "$ARM_RC" != "0" ]] && grep -q 'sigred done' <<<"$ARM_OUT"; then
  pass "A9 — a red reaped after the RUNNER was interrupted (TERM to its pid) is not recorded, and the run is non-zero"
else
  fail "A9 — interrupted-run arm wrong (rc=$ARM_RC, sidecar: $(tr '\t\n' '>|' < "$SC"))"; dump "$ARM_OUT"
fi
# The writer records exactly the runner's `failed` class (suite_exit_class): 1, 128, 193..255 and an unnamed
# signal (160 -> kill -l 32 has no name) are reds the drain prints [FAIL] for; a NAMED signal (130, 137) is not.
# rc 160 = 128 + 32, and `kill -l 32` has no name on glibc but may on another host: derive the expectation.
if [[ -z "$(kill -l 32 2>/dev/null)" ]]; then RC_WANT="bad r128 r160 r255 "; else RC_WANT="bad r128 r255 "; fi
sidecar_run rcs 4
RC_LABELS="$(cut -f1 "$SC" | sort | tr '\n' ' ')"
if [[ "$RC_LABELS" == "$RC_WANT" ]]; then
  pass "A9 — pool: rc 1, 128, 255 (and an unnamed signal) are recorded; named signals 130 and 137 are not"
else
  fail "A9 — pool recorded labels '$RC_LABELS' (want '$RC_WANT')"; dump "$ARM_OUT"
fi
if grep -qE '^\[run\] r255 done \(rc=255, [0-9]+ms\) — provisional' <<<"$ARM_OUT" \
   && grep -qE '^\[run\] r130 done \(rc=130, [0-9]+ms\) — signal-shaped' <<<"$ARM_OUT"; then
  pass "A9 — the live done line uses the same classifier: 255 is provisional, a named signal (130) is signal-shaped"
else
  fail "A9 — live done-line note disagrees with suite_exit_class"; dump "$ARM_OUT"
fi
sidecar_run rcs ""
RC_LABELS="$(cut -f1 "$SC" | sort | tr '\n' ' ')"
if [[ "$RC_LABELS" == "$RC_WANT" ]]; then
  pass "A9 — serial tail: the same rc classes are recorded at the other append site"
else
  fail "A9 — serial recorded labels '$RC_LABELS' (want '$RC_WANT')"; dump "$ARM_OUT"
fi
# Coupling: for every rc the sidecar holds a line exactly when suite_exit_class says `failed`.
sidecar_run couple 4
couple_bad=0; couple_n=0
while read -r _tag _rc _cls; do
  [[ "$_tag" == CLASS ]] || continue
  couple_n=$((couple_n + 1))
  _col="$(cut -f2 "$SC")"; _has=0; grep -qx "$_rc" <<<"$_col" && _has=1
  { [[ "$_cls" == failed ]] && (( _has == 1 )); } || { [[ "$_cls" != failed ]] && (( _has == 0 )); } || couple_bad=$((couple_bad + 1))
done <<<"$ARM_OUT"
if (( couple_n == 12 )) && (( couple_bad == 0 )); then
  pass "A9 — the sidecar and suite_exit_class cannot disagree: 12 rcs, a line exactly for the failed class"
else
  fail "A9 — coupling broke: n=$couple_n disagreements=$couple_bad"; dump "$ARM_OUT"; dump "$(cat "$SC")"
fi
rm -f "$SC"; export SOLEUR_PJ_PROVISIONAL_FILE="$SC"; run_arm mixed 4 || true; unset SOLEUR_PJ_PROVISIONAL_FILE
if [[ ! -e "$SC" ]]; then
  pass "A9 — a named-but-absent sidecar is never created by the runner (the gate owns the file)"
else
  fail "A9 — the runner created the sidecar itself"
fi
# nested-runner isolation: no suite the runner spawns sees the variable.
assert_fixture_dir "$TMP"
PROBE_FILE="$TMP/envprobe.sidecar"; rm -f "$PROBE_FILE"; : > "$SC"
export PROBE_OUT="$PROBE_FILE" SOLEUR_PJ_PROVISIONAL_FILE="$SC"; run_arm envprobe 4 || true; unset PROBE_OUT SOLEUR_PJ_PROVISIONAL_FILE
if [[ "$(sed -n 2p "$PROBE_FILE" 2>/dev/null)" == "absent" && "$(sed -n 1p "$PROBE_FILE" 2>/dev/null)" == "absent" ]]; then
  pass "A9 — SOLEUR_PJ_PROVISIONAL_FILE is not in the environment of a suite the runner spawns (a nested runner cannot append)"
else
  fail "A9 — the sidecar path leaked into a spawned suite: $(tr '\n' '|' < "$PROBE_FILE" 2>/dev/null || echo '<no reading>')"; dump "$ARM_OUT"
fi
n_pdem="$(grep -c '^export -n SOLEUR_PJ_PROVISIONAL_FILE$' "$TARGET" || true)"
n_pdef="$(grep -c '^_provisional_append() {' "$TARGET" || true)"
# every non-comment mention of the writer (definition + 2 calls) and of the variable (the demotion + the
# one read inside the writer): a third caller or a raw writer written in any other shape changes a count
n_pcall="$(sed -e 's/^[[:space:]]*#.*$//' "$TARGET" | grep -c '_provisional_append' || true)"
n_pvar="$(sed -e 's/^[[:space:]]*#.*$//' "$TARGET" | grep -c 'SOLEUR_PJ_PROVISIONAL_FILE' || true)"
if [[ "$n_pdem" == "1" && "$n_pdef" == "1" && "$n_pcall" == "3" && "$n_pvar" == "2" ]]; then
  pass "A9 — one demotion, one definition, exactly two append sites (reap line + serial tail), two code mentions of the variable"
else
  fail "A9 — demotions=$n_pdem defs=$n_pdef writer-mentions=$n_pcall var-mentions=$n_pvar (want 1/1/3/2)"
fi

# --- A10: conservative backfill (#12013) -----------------------------------------------
# A candidate may launch iff a slot is free, it conflicts with no LIVE suite, and it conflicts with nothing
# still queued AHEAD of it. `*` conflicts with everything, so it runs alone: the scheduler PARKS it and launches it
# at the drain, after every non-`*` suite (#12231), so a queued `*` holds nothing back. SOLEUR_PJ_FIFO=1 restores the
# strict FIFO the runner had before (the A/B control of the measurement). Order of suites that share a token
# is registration order in both modes; only INDEPENDENT suites may jump a blocked head.

# Instrument self-test: the timeline checker must pass a real backfill timeline and FAIL an instantaneous,
# sequential one (so an overlap clause cannot pass vacuously when the fixtures degenerate), and fail on a
# missing label rather than skip it.
GOOD_TL="$TMP/tl.good"; BAD_TL="$TMP/tl.bad"
printf 'S holdT 100\nS indA2 110\nE holdT 200\nE indA2 210\n' > "$GOOD_TL"
printf 'S holdT 100\nE holdT 100\nS indA2 101\nE indA2 101\n' > "$BAD_TL"
if tl_check --log "$GOOD_TL" "S:indA2<E:holdT" >/dev/null && ! tl_check --log "$BAD_TL" "S:indA2<E:holdT" >/dev/null \
   && ! tl_check --log "$GOOD_TL" "S:nope<E:holdT" >/dev/null; then
  pass "A10 — instrument: the timeline checker passes a backfill timeline, fails a sequential one and a missing label"
else
  fail "A10 — the timeline checker is not discriminating"
fi
# A star-last clause over a timeline that lacks the star's label must FAIL, never skip.
if ! tl_check --log "$GOOD_TL" "S:starS>=E:holdT" >/dev/null && ! tl_check --log "$BAD_TL" "S:starS>=E:indA2" >/dev/null; then
  pass "A10 - instrument: a star-last clause over a timeline with no star stamp fails (0 checked is not green)"
else
  fail "A10 - the timeline checker passed a star clause that has no star stamp"
fi

# Canonical shape: a blocked head with independent suites behind it.
run_arm bf1 4 || true
BF1_ORDER="$(verdict_lines "$ARM_OUT" | tr '\n' ' ')"
if [[ "$ARM_RC" == "0" && "$BF1_ORDER" == "holdT headT indA indB indC " ]]; then
  pass "A10 — backfill run exits 0 and the verdicts stay in registration order"
else
  fail "A10 — bf1 rc=$ARM_RC order='$BF1_ORDER'"; dump "$ARM_OUT"
fi
if tl_check "S:indA2<E:holdT" "S:indB<E:holdT" "S:indC<E:holdT" "S:headT>=E:holdT"; then
  pass "A10 — independent suites ran beside the live token holder; the token-blocked head waited for it"
else
  fail "A10 — backfill timeline wrong (independents must overlap holdT, headT must follow it)"; dump "$(cat "$FIXTURES/timeline.log")"
fi
# Solo attribution: backfill overlaps a suite with a LATER launch, so the first one must stop claiming sole
# ownership of the machine-global tmp delta. The timing row carries the label and the tmp_delta field.
assert_fixture_dir "$TMP"
TIMING_FILE="$TMP/timing.bf1"; : > "$TIMING_FILE"
run_arm bf1 4 || true
unset TIMING_FILE
BF1_HOLD_ROW="$(grep -E '(^|[[:space:]])holdT([[:space:]]|$)' "$TMP/timing.bf1" || true)"
if grep -q 'tmp_delta=unattributed' <<<"$BF1_HOLD_ROW"; then
  pass "A10 — solo attribution: the suite overlapped by a backfilled launch reports tmp_delta=unattributed"
else
  fail "A10 — holdT's timing row lacks tmp_delta=unattributed: $(grep -E 'holdT' "$TMP/timing.bf1" | head -2 | tr '\t' '>')"
fi
# frozen from the strict-FIFO algorithm on main (recorded 2026-11-05; see the SOLEUR_PJ_FIFO arm below):
FIFO_FROZEN_ORDER="holdT headT indA indB indC "
# The star fixture's strict-FIFO launch order, recorded by running the FIFO arm against the UNMODIFIED merge-base runner
# in the commit that introduced it (#12231) - the independent anchor for this stored value:
FIFO_STAR_FROZEN_ORDER="indA starS slowL indB "

# Second blocked member after a compliant first: headY holds {T,U} behind the live T; xU shares only U.
# xU conflicts with nothing LIVE, only with the queued headY, so it must wait for headY.
run_arm bf2 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:xU>=E:headY" "S:indA2<E:holdT" "S:headY>=E:holdT"; then
  pass "A10 — a suite sharing a token with an earlier QUEUED suite never jumps it (order among conflicting suites)"
else
  fail "A10 — order among conflicting suites violated"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# Parked `*` (#12231): a queued `*` suite no longer blocks later token-free suites. indA2 (registered AFTER the star)
# starts while holdQ is live; the star starts only after both have ended.
run_arm bf3 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:indA2<E:holdQ" "S:starS>=E:holdQ" "S:starS>=E:indA2"; then
  pass "A10 - a parked * does not block later token-free suites; it launches after both the holder and the independent ended"
else
  fail "A10 - parked-star arm wrong: a queued * must not hold back a later independent"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# A token-blocked non-star ahead of the star, then an independent after it: the star must not enter the skipped set.
run_arm starblk 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:indA2<E:holdT" "S:headT>=E:holdT" "S:starS>=E:headT" "S:starS>=E:indA2"; then
  pass "A10 - blocked-head star: the independent behind the star does not wait for it; the star waits for the blocked head"
else
  fail "A10 - blocked-head star arm wrong"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# Two override stars: neither overlaps the other or anything, and registration order among stars holds.
run_arm twostars 4 || true
TWO_VERDICTS="$(verdict_lines "$ARM_OUT" | tr '\n' ' ')"
TWO_RUN="$(started_order "$ARM_OUT")"
if [[ "$ARM_RC" == "0" && "$TWO_VERDICTS" == "indA starS starT indB " && "$TWO_RUN" == "indA indB starS starT " ]] \
   && tl_check "S:starS>=E:indB" "S:starT>=E:starS"; then
  pass "A10 - two stars run one after the other at the drain, in registration order, never beside anything"
else
  fail "A10 - two-stars arm wrong (rc=$ARM_RC launch order '$TWO_RUN' verdicts '$TWO_VERDICTS')"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# A DERIVED `*` (unreadable suite source, no override) is parked like an override one: it starts after indB is done.
run_arm dstar 4 || true
DS_B="$(run_pos indB done)"; DS_S="$(run_pos dstar started)"
if [[ -n "$DS_B" && -n "$DS_S" ]] && (( DS_B < DS_S )) && grep -qE '^\[FAIL\] dstar ' <<<"$ARM_OUT" && [[ "$ARM_RC" != "0" ]]; then
  pass "A10 - a derived * (unreadable source) is parked until the drain, then runs and its failure is a [FAIL]"
else
  fail "A10 - derived-star arm wrong (indB done at '$DS_B', dstar started at '$DS_S', rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# Drain order: the token-blocked head launches before the parked star, whatever the registration order.
run_arm drainord 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:headT>=E:holdD" "S:starS>=E:headT"; then
  pass "A10 - drain order: a token-blocked non-* launches before the parked * (the release comes after the pass)"
else
  fail "A10 - the * was released before a queued non-* suite"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# A star registered FIRST, with nothing to stamp: the ten suites behind it must all finish before it starts.
run_arm starfirst 4 || true
SF_LAST="$(run_pos ok9 done)"; SF_STAR="$(run_pos starS started)"
if [[ "$ARM_RC" == "0" && -n "$SF_LAST" && -n "$SF_STAR" ]] && (( SF_LAST < SF_STAR )); then
  pass "A10 - star-first: a * registered first starts only after every later suite has finished (not on the empty pool)"
else
  fail "A10 - star-first arm wrong (ok9 done at '$SF_LAST', starS started at '$SF_STAR', rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# Must-PASS (non-canonical): a star registered LAST keeps registration-order verdicts and runs alone after the others.
run_arm starlast 4 || true
if [[ "$ARM_RC" == "0" && "$(verdict_lines "$ARM_OUT" | tr '\n' ' ')" == "indA indB starS " ]] && tl_check "S:starS>=E:indA" "S:starS>=E:indB"; then
  pass "A10 - a * registered last runs alone after the others and the verdicts keep registration order"
else
  fail "A10 - star-last-registered arm wrong"; dump "$ARM_OUT"
fi

# Multi-token set containing `*`: parked like any `*` (the match is word-bounded, not equality with a lone `*`).
run_arm starm 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:indA2<E:holdQ" "S:starM>=E:holdQ" "S:starM>=E:indA2"; then
  pass "A10 - a multi-token set containing * is parked like a lone *"
else
  fail "A10 - multi-token star arm wrong"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# Signal while parked: the star is registered FIRST and parked; the interrupt arrives before the drain, so it never starts.
run_arm starsig 4 || true
if [[ "$ARM_RC" != "0" ]] && ! grep -qE '^\[run\] starS started' <<<"$ARM_OUT" && grep -qE '^\[UNACCOUNTED\] starS ' <<<"$ARM_OUT"; then
  pass "A10 - an interrupt while the * is parked leaves it unlaunched and UNACCOUNTED (nothing launches after the signal)"
else
  fail "A10 - signal-while-parked arm wrong (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# Several queued blockers: qC conflicts ONLY with the queued qA (token W), while qB (a different token) was skipped
# between them. The skipped set must ACCUMULATE; an implementation that remembers only the latest skipped suite
# (or looks one entry ahead) lets qC jump qA.
run_arm bf6 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:qC>=E:qA" "S:qA>=E:holdX" "S:qB>=E:holdY" "S:indA2<E:holdX"; then
  pass "A10 — the queued-ahead set accumulates: a suite sharing a token with an earlier queued suite waits for it behind other skips"
else
  fail "A10 — queued-ahead set did not accumulate"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# Whole-set dedupe: s1 skips on X alone; qA then skips on the SET {X, W}. The union must still gain W, or qC (which
# conflicts only with the queued qA, through W) jumps it. A dedupe keyed on the first token only drops W.
run_arm bf7 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:qC>=E:qA" "S:qA>=E:holdX" "S:s1>=E:holdX" "S:indA2<E:holdX"; then
  pass "A10 — de-duplicated skip set never drops a word of a multi-token set (qC still waits for qA)"
else
  fail "A10 — whole-set dedupe arm wrong"; dump "$(cat "$FIXTURES/timeline.log")"
fi

# (No starvation arm: _pj_submit blocks while the pool is saturated, so the queue never holds an independent suite
# beside a token-ready head when a slot frees - "head tried last" is observationally equivalent at the launcher.
# Measured with an order-preserving head-last mutant on 2026-11-05: it survives, and is equivalent for that reason.
# The head-first rule is pinned by the order-among-conflicting and barrier arms above, which a head-last
# reordering of the queue does fail.)

# Torn reap: wait -n comes back with an empty -p variable once. The torn branch never calls _pj_fill, so a
# queued suite is launched by the drain's own fill and must still be reaped (not left UNACCOUNTED).
run_arm torn 4 || true
if [[ "$ARM_RC" == "0" ]] && ! grep -q 'UNACCOUNTED' <<<"$ARM_OUT" && [[ "$(verdict_lines "$ARM_OUT" | tr '\n' ' ')" == "holdT headT " ]]; then
  pass "A10 — a torn reap does not strand a queued suite (drain fills until empty)"
else
  fail "A10 — torn-reap drain left a suite unaccounted (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# Torn reap with a parked star: the tear hits the last non-star, and the drain's own fill must still release the star.
run_arm starorn 4 || true
if [[ "$ARM_RC" == "0" ]] && ! grep -q 'UNACCOUNTED' <<<"$ARM_OUT" && [[ "$(verdict_lines "$ARM_OUT" | tr '\n' ' ')" == "holdD starS " ]] && tl_check "S:starS>=E:holdD"; then
  pass "A10 - a torn reap of the last non-* still releases the parked * (released from _pj_fill, not only the normal reap)"
else
  fail "A10 - torn-reap star arm wrong (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# The knob: SOLEUR_PJ_FIFO=1 reproduces strict FIFO exactly - independents wait behind the blocked head, and the
# launch order equals the frozen order recorded from main.
ARM_FIFO=1 run_arm bf1 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:indA2>=E:holdT" "S:indB>=S:headT"; then
  pass "A10 — SOLEUR_PJ_FIFO=1 restores strict FIFO (independents idle behind the blocked head)"
else
  fail "A10 — FIFO knob did not reproduce strict FIFO"; dump "$(cat "$FIXTURES/timeline.log")"
fi
if [[ "$(started_order "$ARM_OUT")" == "$FIFO_FROZEN_ORDER" ]]; then
  pass "A10 — the knob's launch order equals the frozen order recorded from main"
else
  fail "A10 — FIFO launch order '$(started_order "$ARM_OUT")' != frozen '$FIFO_FROZEN_ORDER'"
fi
FIFO_VERDICTS="$(verdict_lines "$ARM_OUT" | tr '\n' ' ')"; FIFO_RC="$ARM_RC"
# 0 is backfill, not FIFO (the knob is 1-only), and an OUTER exported value never reaches the sandbox arms
ARM_FIFO=0 run_arm bf1 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:indA2<E:holdT"; then
  pass "A10 — SOLEUR_PJ_FIFO=0 is backfill (only the value 1 selects strict FIFO)"
else
  fail "A10 — FIFO=0 did not backfill"; dump "$(cat "$FIXTURES/timeline.log")"
fi
export SOLEUR_PJ_FIFO=1; run_arm bf1 4 || true; unset SOLEUR_PJ_FIFO
if [[ "$ARM_RC" == "0" ]] && tl_check "S:indA2<E:holdT"; then
  pass "A10 — hermetic: an outer SOLEUR_PJ_FIFO=1 in the test's environment does not reach the sandboxed runner"
else
  fail "A10 — an inherited SOLEUR_PJ_FIFO leaked into a backfill arm"; dump "$(cat "$FIXTURES/timeline.log")"
fi
ARM_FIFO=yes run_arm bf1 4 || true
if [[ "$ARM_RC" == "0" ]] && tl_check "S:indA2<E:holdT"; then
  pass "A10 — any value other than 1 (yes) is backfill: the knob is 1-only"
else
  fail "A10 — SOLEUR_PJ_FIFO=yes selected FIFO"; dump "$(cat "$FIXTURES/timeline.log")"
fi
PROBE_FILE="$TMP/envprobe.fifo"; rm -f "$PROBE_FILE"
export PROBE_OUT="$PROBE_FILE"; ARM_FIFO=1 run_arm envprobe 4 || true; unset PROBE_OUT
if [[ "$(sed -n 3p "$PROBE_FILE" 2>/dev/null)" == "absent" ]] && grep -q '\[run\] envprobe started' <<<"$ARM_OUT"; then
  pass "A10 — SOLEUR_PJ_FIFO is demoted from the environment of a suite the runner spawns"
else
  fail "A10 — SOLEUR_PJ_FIFO leaked into a spawned suite: $(tr '\n' '|' < "$PROBE_FILE" 2>/dev/null || echo '<no reading>')"
fi
n_fdem="$(grep -c '^export -n SOLEUR_PJ_FIFO$' "$TARGET" || true)"
if [[ "$n_fdem" == "1" ]]; then pass "A10 — exactly one 'export -n SOLEUR_PJ_FIFO'"; else fail "A10 — found $n_fdem 'export -n SOLEUR_PJ_FIFO' (want 1)"; fi
if [[ "$FIFO_VERDICTS" == "$BF1_ORDER" && "$FIFO_RC" == "0" ]]; then
  pass "A10 — replay parity: backfill and strict FIFO print identical verdicts in identical order, same exit"
else
  fail "A10 — verdict replay differs between backfill ('$BF1_ORDER') and FIFO ('$FIFO_VERDICTS')"
fi
# Strict FIFO is unchanged by the park: on the star fixture the knob launches in registration order, the star alone in
# its turn, and prints the same verdicts and exit code as the parked backfill run above.
ARM_FIFO=1 run_arm star 4 || true
if [[ "$(started_order "$ARM_OUT")" == "$FIFO_STAR_FROZEN_ORDER" && "$(verdict_lines "$ARM_OUT" | tr '\n' ' ')" == "$STAR_VERDICTS" && "$ARM_RC" == "$STAR_RC" ]] \
   && tl_check "S:starS>=E:indA" "S:slowL>=E:starS" "S:indB>=E:starS"; then
  pass "A10 - SOLEUR_PJ_FIFO=1 keeps strict FIFO on the star fixture (frozen launch order) with the same verdicts and exit as backfill"
else
  fail "A10 - FIFO star control wrong (launch '$(started_order "$ARM_OUT")', want '$FIFO_STAR_FROZEN_ORDER')"; dump "$(cat "$FIXTURES/timeline.log")"
fi
# A second, non-canonical shape (5 independents) must also backfill and replay in order.
run_arm bf5 4 || true
if [[ "$ARM_RC" == "0" && "$(verdict_lines "$ARM_OUT" | tr '\n' ' ')" == "holdT headT indA indB indC indD indE " ]] \
   && tl_check "S:indA2<E:holdT" "S:indB<E:holdT" "S:headT>=E:holdT"; then
  pass "A10 — a differently shaped queue (5 independents behind the head) backfills and replays in order"
else
  fail "A10 — non-canonical backfill shape wrong (rc=$ARM_RC)"; dump "$(cat "$FIXTURES/timeline.log")"
fi
# Cost, without a clock: lane_tokens_conflict calls while 60 suites queue behind a parked `*` suite.
rm -f "$FIXTURES/conflict.count"
run_arm many 4 || true
CC="$(wc -c < "$FIXTURES/conflict.count" 2>/dev/null || echo 0)"
MANY_LAST="$(run_pos ok59 done)"; MANY_STAR="$(run_pos starS started)"
if [[ "$ARM_RC" == "0" ]] && (( CC > 0 )) && (( CC <= 200 )); then
  pass "A10 - the fill pass stays bounded: $CC lane_tokens_conflict calls for 61 suites (ceiling 200; a parked * adds none per queued suite)"
else
  fail "A10 - conflict-call count $CC outside (0, 200] or rc=$ARM_RC"
fi
if [[ -n "$MANY_LAST" && -n "$MANY_STAR" ]] && (( MANY_LAST < MANY_STAR )); then
  pass "A10 - 60 suites registered behind a * all finish before the * starts"
else
  fail "A10 - many arm: ok59 done at '$MANY_LAST', starS started at '$MANY_STAR'"; dump "$ARM_OUT"
fi

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
# Dispatch floor, reported directly (never through fail()): deleting a block of arms lowers PASSES.
(( PASSES < MIN_PASSES_FLOOR )) && { printf '[FATAL] only %s assertions passed, expected at least %s\n' "$PASSES" "$MIN_PASSES_FLOOR"; exit 1; }
echo ""
echo "=== test-all-parallel-scheduler: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
