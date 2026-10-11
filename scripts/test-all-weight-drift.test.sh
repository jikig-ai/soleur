#!/usr/bin/env bash
# test-all-weight-drift — suite for the #9814 local weight-drift detector.
#
# Property: a local affected run reports each ran suite's local-vs-committed
# weight drift as an advisory WEIGHT_DRIFT line — warn-only, never a gate.
# local > 2*committed AND local > WEIGHT_DRIFT_FLOOR_MS (10000, value-pinned in
# scripts/lib/test-weight-drift.sh mirroring LOCAL_FAST_CAP_MS) emits
#   WEIGHT_DRIFT <label> committed=<ms> local=<ms>
# a floor-class anchor row adds basis=floor; a ran suite with no committed row
# in any scripts/suite-durations*.tsv emits committed=unmeasured (visible,
# never silently skipped); a log whose ran rows all show elapsed_ms=0 emits
# WEIGHT_DRIFT_UNAVAILABLE once — the check measured nothing and says so.
#
# WHAT THIS SUITE PROVES.
#   Part A  the runner wiring is present and ordered (lib source, default arm,
#           epilogue emit AFTER the `=== N/N suites passed ===` marker,
#           registration, ALWAYS_ON + AFFECTED block).
#   Part B  the comparator predicate — every term and every row class driven
#           through synthetic timing-log/manifest fixtures (the predicate
#           itself runs red and green in every invocation).
#   Part C  the wiring behaviourally — a spliced sandbox of the real runner on
#           a fixture git repo: the default arm creates the timing log, the
#           epilogue emits, the exit code and terminal marker are unchanged,
#           CI/read-only-dir/caller-set arms behave per contract, and the
#           Guard-2 mutation matrix reds when each site is removed.
#
# WHAT IT DOES NOT CLAIM. Local wall-clock is load-dependent — this suite pins
# the predicate and the wiring, not any real host's ratios.
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
LIB="$REPO_ROOT/scripts/lib/test-weight-drift.sh"
INDEX="$REPO_ROOT/scripts/lib/test-affected-paths.sh"

TMP=$(mktemp -d) || exit 2
# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires the verbatim body).
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
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
assert_fixture_dir "$TMP"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Instrument self-check: stubbed fail() must itself redden.
_before_fails=$FAIL; fail "self-test (expected; discounted below)"
if (( FAIL == _before_fails + 1 )); then FAIL=$((FAIL - 1)); pass "instrument: fail() increments the counter"
else fail "instrument: fail() did not increment"; fi

echo "=== test-all-weight-drift ==="
echo ""
echo "--- Part A: structural contract (wiring sites present, ordered) ---"

# A1 — the comparator lib is sourced opportunistically beside the scratch-root include.
if grep -qE 'lib/test-weight-drift\.sh' "$TARGET" \
   && grep -nE '_WD_LIB=.*lib/test-weight-drift\.sh' "$TARGET" | grep -q 'dirname "${BASH_SOURCE\[0\]}"'; then
  pass "A1 — runner sources lib/test-weight-drift.sh via BASH_SOURCE-anchored path"
else
  fail "A1 — lib source line missing or not BASH_SOURCE-anchored"
fi

# A2 — the TEST_TIMING_LOG default arm: anchored markers around the block, all
# four predicate conjuncts (CI unset, var unset, affected-shaped, writability probe).
_da=$(sed -n '/# wd-default-arm-begin/,/# wd-default-arm-end/p' "$TARGET")
if [[ -n "$_da" ]]; then
  pass "A2 — default arm present (anchor markers)"
else
  fail "A2 — default arm anchors missing"
fi
if grep -qF '"${CI:-}"' <<<"$_da" && grep -qF '"${TEST_TIMING_LOG:-}"' <<<"$_da"; then
  pass "A2 — arm refuses to fire under CI or over a caller-set path"
else
  fail "A2 — arm missing -z CI / -z TEST_TIMING_LOG conjuncts"
fi
if grep -qF 'TEST_GROUP' <<<"$_da" && grep -qF '_AFFECTED' <<<"$_da"; then
  pass "A2 — arm covers both affected selectors (TEST_GROUP and _AFFECTED)"
else
  fail "A2 — arm does not cover both affected selectors"
fi
if grep -qF 'mkdir -p' <<<"$_da" && grep -qF -- '-w ' <<<"$_da"; then
  pass "A2 — writability probe guards the export (>> under set -e aborts without it)"
else
  fail "A2 — no mkdir/writability probe before exporting TEST_TIMING_LOG"
fi

# A3 — the epilogue emit sits AFTER the `=== N/N suites passed ===` marker: the
# marker must stay the last ===-shaped line, but WEIGHT_DRIFT is not ===-shaped,
# so the emit belongs in the post-marker NOTE region.
_marker_line=$(grep -n 'suites passed ==="' "$TARGET" | tail -1 | cut -d: -f1)
_emit_line=$(grep -n 'weight_drift_report' "$TARGET" | grep -v '_WD_LIB\|declare -F' | head -1 | cut -d: -f1)
if [[ -n "$_marker_line" && -n "$_emit_line" && "$_emit_line" -gt "$_marker_line" ]]; then
  pass "A3 — epilogue emit is post-marker (emit=$_emit_line > marker=$_marker_line)"
else
  fail "A3 — epilogue emit missing or precedes the terminal marker (emit=${_emit_line:-none} marker=${_marker_line:-none})"
fi

# A4 — the suite is registered explicitly (scripts/*.test.sh is not auto-globbed).
if grep -qE '^[[:space:]]*run_suite "scripts/test-all-weight-drift" bash scripts/test-all-weight-drift\.test\.sh' "$TARGET"; then
  pass "A4 — run_suite registration present"
else
  fail "A4 — no run_suite registration for scripts/test-all-weight-drift"
fi

# A5 — classification: ALWAYS_ON_SUITES entry + declared AFFECTED_*_PATHS block.
if grep -qE '^\s*"scripts/test-all-weight-drift"' "$INDEX"; then
  pass "A5 — ALWAYS_ON_SUITES entry present"
else
  fail "A5 — ALWAYS_ON_SUITES entry missing"
fi
if grep -q 'AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS=(' "$INDEX" \
   && sed -n '/AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS=(/,/^)/p' "$INDEX" \
      | grep -qF 'glob:scripts/*.tsv'; then
  pass "A5 — AFFECTED block declared with glob: scripts/*.tsv edge"
else
  fail "A5 — AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS block missing or lacks glob: scripts/*.tsv edge"
fi

# A6 — the floor constant is value-pinned in the lib (a value pin cannot
# self-mutate under sed; mirrors LOCAL_FAST_CAP_MS's pinning convention).
if grep -qE '^WEIGHT_DRIFT_FLOOR_MS=10000' "$LIB"; then
  pass "A6 — WEIGHT_DRIFT_FLOOR_MS pinned to 10000 in the lib"
else
  fail "A6 — WEIGHT_DRIFT_FLOOR_MS missing or drifted from 10000"
fi

echo ""
echo "--- Part B: the comparator predicate against fixtures ---"

if [[ -f "$LIB" ]]; then
  # shellcheck source=scripts/lib/test-weight-drift.sh
  source "$LIB"
fi

# run_report <out-prefix> <log> <manifest...> — captures stdout and stderr
# separately so the dual-emit contract is asserted, never assumed.
REPORT_OUT=""; REPORT_ERR=""; REPORT_RC=-1
run_report() {
  local log="$1"; shift
  REPORT_OUT=$(weight_drift_report "$log" "$@" 2>"$TMP/.rerr")
  REPORT_RC=$?
  REPORT_ERR=$(cat "$TMP/.rerr")
  return 0
}

FXB="$TMP/fx-b"; mkdir -p "$FXB"

# B1 — drift: local 30000 > 2*5000 AND > 10000 → one exact line.
printf 'scripts/x\t30000\n' > "$FXB/log-b1.tsv"
printf 'scripts/x\t5000\tmeasured\n' > "$FXB/dur-b1.tsv"
run_report "$FXB/log-b1.tsv" "$FXB/dur-b1.tsv"
if [[ "$REPORT_OUT" == *"WEIGHT_DRIFT scripts/x committed=5000 local=30000"* ]]; then
  pass "B1 — drifted row emits WEIGHT_DRIFT committed=5000 local=30000"
else
  fail "B1 — no drift line"; echo "$REPORT_OUT" | sed 's/^/    /'
fi
if [[ "$REPORT_ERR" == *"WEIGHT_DRIFT scripts/x committed=5000 local=30000"* ]]; then
  pass "B1 — dual-emit: line reaches stderr (an agent's stdout capture is not the only sink)"
else
  fail "B1 — drift line missing on stderr"
fi
if [[ "$REPORT_RC" == 0 ]]; then
  pass "B1 — report exits 0 on emit (warn-only)"
else
  fail "B1 — report exited $REPORT_RC on emit"
fi

# B2 — within tolerance, three sub-arms, each must emit NOTHING:
#   (a) ratio < 2x               committed=5000 local=9000
#   (b) >2x but under the floor  committed=4000 local=8100
#   (c) exactly 2x               committed=5000 local=10000 (strict >)
: > "$FXB/log-b2.tsv"
printf 'a/under-2x\t9000\nb/over-2x-under-floor\t8100\nc/exactly-2x\t10000\n' >> "$FXB/log-b2.tsv"
printf 'a/under-2x\t5000\tmeasured\nb/over-2x-under-floor\t4000\tmeasured\nc/exactly-2x\t5000\tmeasured\n' > "$FXB/dur-b2.tsv"
run_report "$FXB/log-b2.tsv" "$FXB/dur-b2.tsv"
if ! grep -q 'WEIGHT_DRIFT' <<<"$REPORT_OUT"; then
  pass "B2 — within-tolerance rows emit nothing (ratio <2x; >2x but <10s; exactly-2x strict)"
else
  fail "B2 — tolerance arm emitted"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B3 — two drifted rows emit TWO lines (stops-at-first is itself the defect).
printf 'd/one\t30000\nd/two\t25000\n' > "$FXB/log-b3.tsv"
printf 'd/one\t5000\tmeasured\nd/two\t6000\tmeasured\n' > "$FXB/dur-b3.tsv"
run_report "$FXB/log-b3.tsv" "$FXB/dur-b3.tsv"
if [[ "$(grep -c '^WEIGHT_DRIFT ' <<<"$REPORT_OUT")" == 2 ]]; then
  pass "B3 — two drifted rows emit two lines"
else
  fail "B3 — expected 2 drift lines"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B4 — skip=*/comment/short rows are invisible: a log of only declines emits nothing.
printf 'e/declined\t0\tskip=affected\ne/ceiling\t0\tskip=runtime-ceiling\n# a comment\nshort\n' > "$FXB/log-b4.tsv"
printf 'e/declined\t5000\tmeasured\ne/ceiling\t5000\tmeasured\n' > "$FXB/dur-b4.tsv"
run_report "$FXB/log-b4.tsv" "$FXB/dur-b4.tsv"
if ! grep -q 'WEIGHT_DRIFT' <<<"$REPORT_OUT"; then
  pass "B4 — skip=*/comment/short rows emit nothing"
else
  fail "B4 — decline-class rows emitted"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B5 — ran-but-rowless label reports committed=unmeasured (never silently skipped).
printf 'f/new-suite\t12000\n' > "$FXB/log-b5.tsv"
printf 'other/label\t5000\tmeasured\n' > "$FXB/dur-b5.tsv"
run_report "$FXB/log-b5.tsv" "$FXB/dur-b5.tsv"
if [[ "$REPORT_OUT" == *"WEIGHT_DRIFT f/new-suite committed=unmeasured local=12000"* ]]; then
  pass "B5 — ran-but-rowless label emits committed=unmeasured"
else
  fail "B5 — unmeasured arm silent"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B6 — a floor-class anchor row emits with basis=floor (the anchor is weaker
# than a measured row, so the line names it).
printf 'g/floored\t20000\n' > "$FXB/log-b6.tsv"
printf 'g/floored\t3000\tfloor\n' > "$FXB/dur-b6.tsv"
run_report "$FXB/log-b6.tsv" "$FXB/dur-b6.tsv"
if [[ "$REPORT_OUT" == *"WEIGHT_DRIFT g/floored committed=3000 basis=floor local=20000"* ]]; then
  pass "B6 — floor-class anchor emits with basis=floor"
else
  fail "B6 — floor row emitted without basis=floor"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B7 — FAIL/KILLED/TRIPWIRE rows still count as ran — they consumed wall-clock.
printf 'h/failed\t30000\tFAIL\nh/killed\t30000\tKILLED\nh/tripped\t30000\tTRIPWIRE\n' > "$FXB/log-b7.tsv"
printf 'h/failed\t5000\tmeasured\nh/killed\t5000\tmeasured\nh/tripped\t5000\tmeasured\n' > "$FXB/dur-b7.tsv"
run_report "$FXB/log-b7.tsv" "$FXB/dur-b7.tsv"
if [[ "$(grep -c '^WEIGHT_DRIFT ' <<<"$REPORT_OUT")" == 3 ]]; then
  pass "B7 — FAIL/KILLED/TRIPWIRE rows are still compared"
else
  fail "B7 — non-ok ran rows filtered out"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B8 — ran rows exist but every elapsed_ms is 0 → WEIGHT_DRIFT_UNAVAILABLE once
# (bash-3.2 host shape: EPOCHREALTIME unset → 0 silently). __run_boundary_*
# probe markers and torn non-numeric rows ride the same log and must NOT be
# counted into rows= (review P3 — an all-decline run's two probe rows would
# otherwise report rows=2 "measured nothing" for a run that measured no suites).
printf 'i/one\t0\n__run_boundary_start__\t0\tbytes_tmp=12\tbytes_tmpdir=34\ni/two\t0\tFAIL\ntorn\tgarbage\n__run_boundary_end__\t0\tbytes_tmp=12\tbytes_tmpdir=34\n' > "$FXB/log-b8.tsv"
printf 'i/one\t5000\tmeasured\ni/two\t5000\tmeasured\n' > "$FXB/dur-b8.tsv"
run_report "$FXB/log-b8.tsv" "$FXB/dur-b8.tsv"
if [[ "$(grep -c 'WEIGHT_DRIFT_UNAVAILABLE' <<<"$REPORT_OUT")" == 1 ]] \
   && grep -q 'WEIGHT_DRIFT_UNAVAILABLE rows=2 reason=elapsed-zero' <<<"$REPORT_OUT"; then
  pass "B8 — all-zero elapsed emits WEIGHT_DRIFT_UNAVAILABLE rows=2 once (probes/torn rows not counted)"
else
  fail "B8 — elapsed-zero vacuity unnamed or rows= inflated"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B9 — an emitted report ends with the timing-log trailer (the warning is
# inspectable, not a dead end); a clean report emits no trailer.
run_report "$FXB/log-b1.tsv" "$FXB/dur-b1.tsv"
if grep -qF "WEIGHT_DRIFT_LOG $FXB/log-b1.tsv" <<<"$REPORT_OUT"; then
  pass "B9 — drift report carries the timing-log trailer"
else
  fail "B9 — no timing-log trailer on a drifted report"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B10 — the report NEVER exits non-zero: missing log, zero manifests, garbage
# rows — every degenerate input still returns 0.
weight_drift_report "$FXB/does-not-exist.tsv" >/dev/null 2>&1; _rc1=$?
weight_drift_report "$FXB/log-b1.tsv" "$FXB/no-such-manifest.tsv" >/dev/null 2>&1; _rc2=$?
weight_drift_report "$FXB/log-b1.tsv" >/dev/null 2>&1; _rc3=$?
if (( _rc1 == 0 && _rc2 == 0 && _rc3 == 0 )); then
  pass "B10 — report returns 0 on missing log, missing manifest, zero manifests"
else
  fail "B10 — non-zero exit on degenerate input ($_rc1 $_rc2 $_rc3)"
fi
# Zero readable manifests → every ran row still reports unmeasured (never silent).
run_report "$FXB/log-b1.tsv" "$FXB/no-such-manifest.tsv"
if [[ "$REPORT_OUT" == *"WEIGHT_DRIFT scripts/x committed=unmeasured local=30000"* ]]; then
  pass "B10 — zero readable manifests → ran rows emit unmeasured"
else
  fail "B10 — manifest-less run skipped the row"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

# B11 — row grammar edge cases: tmp_delta trailing field parses; a label in a
# SECOND manifest resolves (the suite-durations*.tsv glob join); duplicate
# labels take the last row.
printf 'j/tmp\t30000\ttmp_delta=4\nj/heavy\t25000\nj/dup\t22000\n' > "$FXB/log-b11.tsv"
printf 'j/heavy\t5000\tmeasured\nj/dup\t9000\tmeasured\nj/dup\t5000\tmeasured\n' > "$FXB/dur-b11a.tsv"
printf 'j/tmp\t5000\tmeasured\n' > "$FXB/dur-b11b.tsv"
run_report "$FXB/log-b11.tsv" "$FXB/dur-b11a.tsv" "$FXB/dur-b11b.tsv"
if [[ "$(grep -c '^WEIGHT_DRIFT ' <<<"$REPORT_OUT")" == 3 ]] \
   && grep -q 'WEIGHT_DRIFT j/tmp committed=5000 local=30000' <<<"$REPORT_OUT" \
   && grep -q 'WEIGHT_DRIFT j/heavy committed=5000 local=25000' <<<"$REPORT_OUT" \
   && grep -q 'WEIGHT_DRIFT j/dup committed=5000 local=22000' <<<"$REPORT_OUT"; then
  pass "B11 — tmp_delta field parsed, second-manifest join, last-row-wins"
else
  fail "B11 — grammar edge arm wrong"; echo "$REPORT_OUT" | sed 's/^/    /'
fi

echo ""
echo "--- Part C: the wiring against a sandboxed runner ---"

# Fixture repo: base commit pins origin/main; a dirty scripts/wd-stub.sh forms
# the HEAD diff that selects the wd-stub registration (stem match, the same
# heuristic shape test-all-group-affected.test.sh drives).
FXC="$TMP/fixture-repo"; assert_fixture_dir "$FXC"
mkdir -p "$FXC/scripts"
(
  cd "$FXC" || exit 1
  git init -q
  git config user.email fixture@test && git config user.name fixture
  git config commit.gpgsign false
  # Two stubs, both inert on disk — TEST_TIMING_LOG is deliberately NOT
  # exported by the default arm (review P1: an exported var leaks the parent's
  # log into every nested runner a suite spawns). The drifted row therefore
  # arrives via a spliced in-runner line in build_sandbox, and wd-unmeasured's
  # REAL run_suite-written row is what pins the writer->file->awk chain end
  # to end (review P2 — a stub-injected row would never exercise it).
  printf 'exit 0\n' > scripts/wd-stub.test.sh
  printf 'exit 0\n' > scripts/wd-unmeasured.test.sh
  # wd-env-probe prints a marker iff it can SEE TEST_TIMING_LOG — a suite
  # process observes the variable only when the runner exported it, so this
  # marker is the export-leak tripwire (review P1).
  cat > scripts/wd-env-probe.test.sh <<'EOF'
if [[ -n "${TEST_TIMING_LOG:-}" ]]; then echo "WD_ENV_LEAKED"; fi
exit 0
EOF
  git add -A && git commit -qm base
  git update-ref refs/remotes/origin/main HEAD
  # Dirty the suite files — the registration argv paths land in the diff, so
  # every selection heuristic reaches all three stubs.
  printf '# touched\n' >> scripts/wd-stub.test.sh
  printf '# touched\n' >> scripts/wd-unmeasured.test.sh
  printf '# touched\n' >> scripts/wd-env-probe.test.sh
)

# Sandbox copy of the real runner: fixture registration spliced between the
# lock and the epilogue anchors (identical window to test-all-group-affected),
# tc_acquire/tc_preamble neutered, per-mutation text deletions between the
# weight-drift anchor markers.
SB="$TMP/sandbox"; assert_fixture_dir "$SB"; mkdir -p "$SB/lib"
cat > "$SB/suite-durations.tsv" <<'EOF'
wd-stub	5000	measured
EOF

build_sandbox() {
  local out="$1" mutation="${2:-none}" inject="${3:-1}"
  cp "$TARGET" "$out" || return 1
  cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$SB/lib/" || return 1
  cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$SB/lib/" || return 1
  [[ -f "$LIB" ]] && cp "$LIB" "$SB/lib/test-weight-drift.sh"
  python3 - "$out" "$mutation" "$inject" <<'PY'
import sys, re
path, mutation, inject = sys.argv[1], sys.argv[2], sys.argv[3]
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

# Trailing newline is load-bearing: without it the anchor text at s[j:] glues
# onto the argv (measured: scripts/wd-stub.test.shtc_epilogue declined).
calls = '''run_suite "wd-stub" bash scripts/wd-stub.test.sh
run_suite "wd-unmeasured" bash scripts/wd-unmeasured.test.sh
run_suite "wd-env-probe" bash scripts/wd-env-probe.test.sh
'''
if inject == "1":
    # The drifted row is written IN-RUNNER (in-shell TEST_TIMING_LOG — the
    # suite process cannot see it since the default arm deliberately does not
    # export). wd-unmeasured needs no injection: its own real row is the
    # committed=unmeasured fixture.
    calls += 'printf \'wd-stub\\t30000\\n\' >> "${TEST_TIMING_LOG:-/dev/null}"\n'
s = s[:i] + "\n" + calls + s[j:]

s = sub_once(s, 'tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 'tc_acquire call')
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
s = sub_once(s, 'if [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0',
             'TC_SIBLING_RUN_COUNT_PID=$$\nif [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0',
             'sibling refusal opener')

def delete_span(hay, begin, end, what):
    bi = hay.find(begin)
    assert bi >= 0, f"mutation could not locate {what} begin anchor"
    ei = hay.find(end, bi)
    assert ei >= 0, f"mutation could not locate {what} end anchor"
    return hay[:bi] + hay[ei + len(end):]

if mutation == "no_default_arm":
    s = delete_span(s, '# wd-default-arm-begin', '# wd-default-arm-end', 'default arm')
elif mutation == "no_emit":
    s = delete_span(s, '# wd-epilogue-emit-begin', '# wd-epilogue-emit-end', 'epilogue emit')
elif mutation == "no_probe":
    s = sub_once(s, 'if mkdir -p "$_durable_log_dir" 2>/dev/null && [[ -w "$_durable_log_dir" ]]; then',
                 'if true; then', 'writability guard')
elif mutation == "ci_arm_off":
    s = sub_once(s, 'if [[ -z "${TEST_TIMING_LOG:-}" ]] && [[ -z "${CI:-}" ]] \\\n',
                 'if [[ -z "${TEST_TIMING_LOG:-}" ]] \\\n', 'CI conjunct in default arm')
elif mutation == "caller_wins_off":
    s = sub_once(s, 'if [[ -z "${TEST_TIMING_LOG:-}" ]] && [[ -z "${CI:-}" ]] \\\n',
                 'if [[ -z "${CI:-}" ]] \\\n', 'caller-set conjunct in default arm')
elif mutation == "export_leak":
    s = sub_once(s, '    TEST_TIMING_LOG="$_durable_log_dir/suite-timings.tsv"',
                 '    export TEST_TIMING_LOG="$_durable_log_dir/suite-timings.tsv"', 'in-shell assignment')
elif mutation != "none":
    raise AssertionError(f"unknown mutation {mutation}")

open(path, 'w').write(s)
print("sandbox built")
PY
}

# Run one arm inside the fixture repo. Env is scrubbed per arm (the env-leak
# class that reddens suites only under an exported TEST_GROUP/TEST_TIMING_LOG).
run_arm() {
  local name="$1" mutation="${2:-none}" extra_env="${3:-}" timing="${4:-}" inject="${5:-1}"
  local sb="$SB/runner-${name}-${mutation}.sh"
  ARM_OUT=""; ARM_RC=-1
  build_sandbox "$sb" "$mutation" "$inject" >/dev/null || { fail "sandbox build failed: $name/$mutation"; return 1; }
  ARM_OUT=$(cd "$FXC" && env -u TEST_GROUP -u TEST_TIMING_LOG -u CI -u GITHUB_EVENT_NAME \
            SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= SOLEUR_TEST_FORCE_ALL= \
            SOLEUR_TEST_ALL_LOG_DIR="$TMP/durable" $extra_env \
            TEST_TIMING_LOG="$timing" timeout 180 bash "$sb" 2>&1)
  ARM_RC=$?
  return 0
}

# run_arm_unset exercises the truly-UNSET TEST_TIMING_LOG — the arm the
# default arm's -z conjunct was written for. TEST_GROUP=affected rides the
# base env (the two affected selectors are covered: these arms use the
# TEST_GROUP spelling; _AFFECTED==1 is armed by every no-CI no-flag run too).
run_arm_unset() {
  local name="$1" mutation="${2:-none}" extra_env="${3:-}" inject="${4:-1}"
  local sb="$SB/runner-${name}-${mutation}.sh"
  ARM_OUT=""; ARM_RC=-1
  build_sandbox "$sb" "$mutation" "$inject" >/dev/null || { fail "sandbox build failed: $name/$mutation"; return 1; }
  ARM_OUT=$(cd "$FXC" && env -u TEST_GROUP -u TEST_TIMING_LOG -u CI -u GITHUB_EVENT_NAME \
            SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= SOLEUR_TEST_FORCE_ALL= \
            SOLEUR_TEST_ALL_LOG_DIR="$TMP/durable" TEST_GROUP=affected $extra_env \
            timeout 180 bash "$sb" 2>&1)
  ARM_RC=$?
  return 0
}

dump() { sed 's/^/    /' <<<"$1"; }

# C1 — the default arm: a local affected run with no TEST_TIMING_LOG and no CI
# creates the log at the default path and the epilogue emits the drift line
# for the injected 30000ms row; the exit code and terminal marker are unchanged.
rm -rf "$TMP/durable"
run_arm_unset c1 none || true
C1_OUT="$ARM_OUT"; C1_RC="$ARM_RC"
_timing_file=$(find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | head -1)
if [[ -n "$_timing_file" && -f "$_timing_file" ]]; then
  pass "C1 — default arm created the timing log at \$_durable_log_dir/suite-timings.tsv"
else
  fail "C1 — no default-path timing log"; dump "$C1_OUT"
fi
if grep -qF 'WEIGHT_DRIFT wd-stub committed=5000 local=30000' <<<"$C1_OUT"; then
  pass "C1 — epilogue emitted the drift line for the injected row"
else
  fail "C1 — no WEIGHT_DRIFT line in run output"; dump "$C1_OUT"
fi
if grep -qE 'WEIGHT_DRIFT wd-unmeasured committed=unmeasured local=[0-9]+' <<<"$C1_OUT"; then
  pass "C1 — wd-unmeasured's REAL run_suite row emits committed=unmeasured (writer->file->awk pinned)"
else
  fail "C1 — real runner-written row did not reach the comparator"; dump "$C1_OUT"
fi
if [[ "$C1_RC" == 0 ]]; then
  pass "C1 — exit code unchanged by an emitting run (rc=0)"
else
  fail "C1 — exited $C1_RC, expected 0"; dump "$C1_OUT"
fi
_last_eq=$(grep -nE '^===' <<<"$C1_OUT" | tail -1)
if [[ "$_last_eq" == *"suites passed ===" ]]; then
  pass "C1 — the terminal marker remains the last ===-shaped line"
else
  fail "C1 — terminal marker displaced"; dump "$C1_OUT"
fi

# C2 — no drift line when no row is over the predicate: build the sandbox
# WITHOUT the injected row so only real sub-10000ms rows land; the unmeasured
# stub still reports (unmeasured is unconditional — that is the point of it).
rm -rf "$TMP/durable"
run_arm_unset c2 none "" 0 || true
if ! grep -q 'WEIGHT_DRIFT wd-stub' <<<"$ARM_OUT" \
   && grep -qE 'WEIGHT_DRIFT wd-unmeasured committed=unmeasured local=[0-9]+' <<<"$ARM_OUT" \
   && [[ "$ARM_RC" == 0 ]]; then
  pass "C2 — within-tolerance run: only the unmeasured line, no drift line, rc=0"
else
  fail "C2 — quiet run emitted a drift line or failed (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# C3 — CI=1: no auto-default of TEST_TIMING_LOG (the arm requires -z CI).
rm -rf "$TMP/durable"
run_arm_unset c3 none "CI=1" || true
if ! find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q . \
   && ! grep -q 'WEIGHT_DRIFT' <<<"$ARM_OUT"; then
  pass "C3 — CI run never auto-defaults the timing log"
else
  fail "C3 — auto-default fired under CI"; dump "$ARM_OUT"
fi

# C4 — caller-set TEST_TIMING_LOG on a local run: the comparator still emits
# (the emit gate is on the variable, not the mode) and the caller's path wins.
rm -rf "$TMP/durable"
CALLER_LOG="$TMP/caller-set.tsv"; : > "$CALLER_LOG"
run_arm c4 none "TEST_GROUP=affected" "$CALLER_LOG" || true
if [[ -s "$CALLER_LOG" ]] \
   && grep -qF 'WEIGHT_DRIFT wd-stub committed=5000 local=30000' <<<"$ARM_OUT" \
   && grep -qE 'WEIGHT_DRIFT wd-unmeasured committed=unmeasured local=[0-9]+' <<<"$ARM_OUT"; then
  pass "C4 — caller-set path receives rows and emits drift + unmeasured lines"
else
  fail "C4 — caller-set path not honored or no emit"; dump "$ARM_OUT"
fi
if ! find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q .; then
  pass "C4 — caller-set path is not clobbered by the default"
else
  fail "C4 — default arm overrode the caller-set path"
fi

# C6 — enumerate/print paths are side-effect-free: the arm declines BEFORE the
# mkdir, so --enumerate creates no timing log and no durable run dir.
rm -rf "$TMP/durable"
_sb="$SB/runner-c6-none.sh"
build_sandbox "$_sb" none 0 >/dev/null || fail "sandbox build failed: c6"
C6_OUT=$(cd "$FXC" && env -u TEST_GROUP -u TEST_TIMING_LOG -u CI \
         SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= SOLEUR_TEST_FORCE_ALL= \
         SOLEUR_TEST_ALL_LOG_DIR="$TMP/durable" timeout 120 bash "$_sb" --enumerate 2>&1)
C6_RC=$?
if [[ "$C6_RC" == 0 ]] && ! find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q .; then
  pass "C6 — --enumerate declines the arm: no timing log, side-effect-free"
else
  fail "C6 — enumerate path armed the default or errored (rc=$C6_RC)"; dump "$C6_OUT"
fi

# C7 — a named TEST_GROUP is not affected-shaped: _AFFECTED==1 is armed-but-inert
# for named groups, and the arm must not fire on TEST_GROUP=scripts either.
rm -rf "$TMP/durable"
_sb="$SB/runner-c7-none.sh"
build_sandbox "$_sb" none 0 >/dev/null || fail "sandbox build failed: c7"
C7_OUT=$(cd "$FXC" && env -u TEST_GROUP -u TEST_TIMING_LOG -u CI \
         SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= SOLEUR_TEST_FORCE_ALL= \
         SOLEUR_TEST_ALL_LOG_DIR="$TMP/durable" TEST_GROUP=scripts \
         timeout 180 bash "$_sb" 2>&1)
C7_RC=$?
if ! find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q .; then
  pass "C7 — named group (TEST_GROUP=scripts) is not affected-shaped: no timing log"
else
  fail "C7 — default arm fired on a named group"; dump "$C7_OUT"
fi

# C5 — read-only durable dir: the probe declines the default, the run still
# completes green with no timing log (>> under set -e would abort without it).
RO_DIR="$TMP/readonly"; assert_fixture_dir "$RO_DIR"; mkdir -p "$RO_DIR"; chmod 0555 "$RO_DIR"
_sb="$SB/runner-c5-none.sh"
build_sandbox "$_sb" none >/dev/null || fail "sandbox build failed: c5"
C5_OUT=$(cd "$FXC" && env -u TEST_GROUP -u TEST_TIMING_LOG -u CI \
         SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= SOLEUR_TEST_FORCE_ALL= \
         SOLEUR_TEST_ALL_LOG_DIR="$RO_DIR" TEST_GROUP=affected timeout 180 bash "$_sb" 2>&1)
C5_RC=$?
chmod 0755 "$RO_DIR"
if [[ "$C5_RC" == 0 ]] && grep -q 'suites passed ===' <<<"$C5_OUT" \
   && ! find "$RO_DIR" -name 'suite-timings.tsv' 2>/dev/null | grep -q .; then
  pass "C5 — unwritable durable dir: probe declines, run completes green, no log"
else
  fail "C5 — read-only-dir run aborted or logged anyway (rc=$C5_RC)"; dump "$C5_OUT"
fi

# --- Guard-2 mutation matrix ------------------------------------------------

# M1: default arm deleted → no timing log is created.
rm -rf "$TMP/durable"
run_arm_unset m1 no_default_arm || true
if ! find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q .; then
  pass "M1 — without the default arm, no timing log exists"
else
  fail "M1 — timing log appeared despite deleted arm"
fi

# M2: writability probe removed → the unwritable target makes >> abort the run
# mid-suite (no terminal marker, non-zero rc) — the probe is load-bearing.
chmod 0555 "$RO_DIR"
_sb="$SB/runner-m2-no_probe.sh"
build_sandbox "$_sb" no_probe >/dev/null || fail "sandbox build failed: m2"
M2_OUT=$(cd "$FXC" && env -u TEST_GROUP -u TEST_TIMING_LOG -u CI \
         SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= SOLEUR_TEST_FORCE_ALL= \
         SOLEUR_TEST_ALL_LOG_DIR="$RO_DIR" TEST_GROUP=affected timeout 180 bash "$_sb" 2>&1)
M2_RC=$?
chmod 0755 "$RO_DIR"
if [[ "$M2_RC" != 0 ]] || ! grep -q 'suites passed ===' <<<"$M2_OUT"; then
  pass "M2 — removed probe turns the unwritable path into a mid-run abort (probe is load-bearing)"
else
  fail "M2 — run survived without the probe (probe is decorative)"
fi

# M3: epilogue call deleted → timing log exists but zero WEIGHT_DRIFT lines.
rm -rf "$TMP/durable"
run_arm_unset m3 no_emit || true
if find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q . \
   && ! grep -q '^WEIGHT_DRIFT ' <<<"$ARM_OUT"; then
  pass "M3 — deleted emit site: log exists, zero WEIGHT_DRIFT lines"
else
  fail "M3 — emit-deleted run still emitted (or log missing)"; dump "$ARM_OUT"
fi

# M4: -z CI dropped from the default arm → the arm fires under CI.
rm -rf "$TMP/durable"
run_arm_unset m4 ci_arm_off "CI=1" || true
if find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q .; then
  pass "M4 — without the CI conjunct the arm fires under CI (conjunct is load-bearing)"
else
  fail "M4 — CI conjunct removal changed nothing (arm already fires under CI)"
fi

# M5: -z TEST_TIMING_LOG dropped → the default clobbers the caller-set path.
rm -rf "$TMP/durable"
CALLER_LOG2="$TMP/caller-m5.tsv"; : > "$CALLER_LOG2"
run_arm m5 caller_wins_off "TEST_GROUP=affected" "$CALLER_LOG2" || true
if find "$TMP/durable" -name 'suite-timings.tsv' 2>/dev/null | grep -q . \
   && [[ ! -s "$CALLER_LOG2" ]]; then
  pass "M5 — without the caller-set conjunct the default clobbers the caller path"
else
  fail "M5 — caller-set conjunct removal changed nothing"
fi

# C8 + M6: the in-shell assignment never reaches a suite process. Green run
# emits no WD_ENV_LEAKED; re-adding `export` makes the probe's marker appear
# (the export was the whole P1 — a leak into nested runner children).
rm -rf "$TMP/durable"
run_arm_unset c8 none || true
if ! grep -q 'WD_ENV_LEAKED' <<<"$ARM_OUT"; then
  pass "C8 — suite children cannot see the in-shell TEST_TIMING_LOG"
else
  fail "C8 — TEST_TIMING_LOG leaked into a suite process"; dump "$ARM_OUT"
fi
run_arm_unset m6 export_leak || true
if grep -q 'WD_ENV_LEAKED' <<<"$ARM_OUT"; then
  pass "M6 — re-added export leaks the var into suite children (in-shell pin is load-bearing)"
else
  fail "M6 — export re-addition did not leak (probe blind)"
fi

echo ""
echo "test-all-weight-drift: $PASS passed, $FAIL failed"

# Conservation + anti-vacuity floor (sibling-suite shape — a count assertion
# cannot see a deleted body, so the floor counts assertion RESULTS).
MIN_ASSERTIONS=40
_total=$((PASS + FAIL))
if (( _total < MIN_ASSERTIONS )); then
  echo "[FATAL] anti-vacuity floor: only $_total assertion(s) ran, expected >= $MIN_ASSERTIONS" >&2
  exit 2
fi
if (( FAIL > 0 )); then
  exit 1
fi
echo "test-all-weight-drift: ALL PASS"
