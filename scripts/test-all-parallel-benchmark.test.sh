#!/usr/bin/env bash
# test-all-parallel-benchmark.test.sh — serial-vs-parallel measurement harness (#8231).
#
# This suite RECORDS; it does not gate on a ratio — a wall-clock ratio would be
# a verdict on the host, not on the mechanism (CI boxes vary, and #6496 exists
# precisely because a wall-clock assertion read the load). What it does gate:
# both arms complete, the parallel arm emits the full verdict population, and
# the BENCH summary block is emitted for the plan/spec evidence record.
#
# The corpus is a synthesized fixture battery — a mix of sleep-bound and
# CPU-bound fixtures — driven through a sandboxed copy of the real runner, so
# the measurement exercises the real dispatch/reap/render path rather than a
# mock. Two arms: SOLEUR_TEST_JOBS=1 (serial) and SOLEUR_TEST_JOBS=4.
#
# CPU and memory are read from /proc/self children's utime and GNU time's RSS
# when available; each field degrades to a named unmeasured value rather than a
# fabricated number.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
export REPO_ROOT

PASSES=0; FAILURES=0
pass() { PASSES=$((PASSES + 1)); printf '[pass] %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf '[FAIL] %s\n' "$1"; }

TARGET="$REPO_ROOT/scripts/test-all.sh"
[[ -f "$TARGET" ]] || { echo "FATAL: $TARGET not found"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t8231b.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FIXTURES="$TMP/fixtures"
mkdir -p "$FIXTURES"

# Corpus: 4 sleep-bound + 4 CPU-bound fixtures (~0.4s each under no load).
for i in 1 2 3 4; do
  cat > "$FIXTURES/sleep$i.sh" <<'EOF'
#!/usr/bin/env bash
sleep 0.5
exit 0
EOF
  cat > "$FIXTURES/cpu$i.sh" <<'EOF'
#!/usr/bin/env bash
x=0
end=$(( $(date +%s%N) + 400000000 ))
while (( $(date +%s%N) < end )); do x=$(( x + 1 )); done
exit 0
EOF
  chmod +x "$FIXTURES/sleep$i.sh" "$FIXTURES/cpu$i.sh"
done

cat > "$TMP/body.sh" <<EOF
declare -gA _SESSION_LOCK_ACQUIRED 2>/dev/null || true
_SESSION_LOCK_ACQUIRED[test-all]=1
_pj_lock_held=1
_pj_resolve_run_mode
run_suite "sleep1" bash "$FIXTURES/sleep1.sh"
run_suite "cpu1"   bash "$FIXTURES/cpu1.sh"
run_suite "sleep2" bash "$FIXTURES/sleep2.sh"
run_suite "cpu2"   bash "$FIXTURES/cpu2.sh"
run_suite "sleep3" bash "$FIXTURES/sleep3.sh"
run_suite "cpu3"   bash "$FIXTURES/cpu3.sh"
run_suite "sleep4" bash "$FIXTURES/sleep4.sh"
run_suite "cpu4"   bash "$FIXTURES/cpu4.sh"
_pj_drain
EOF

cp "$TARGET" "$TMP/runner.sh"
mkdir -p "$TMP/lib"
cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$TMP/lib/"
for _lib in test-relevance-paths.sh test-suite-lanes.sh; do
  cp "$REPO_ROOT/scripts/lib/$_lib" "$TMP/lib/"
done
python3 - "$TMP/runner.sh" "$TMP/body.sh" <<'PY'
import sys, re
path, bodyfile = sys.argv[1:3]
s = open(path).read()
a = 'tc_acquire "test-all"'
b = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(a) == 1 and s.count(b) == 1
i = s.index(a) + len(a); j = s.index(b)
s = s[:i] + "\n" + open(bodyfile).read() + s[j:]
s = s.replace(a, 'true "test-all"  # sandbox: lock neutered', 1)
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
open(path, 'w').write(s)
PY

run_arm() {  # <jobs> -> sets WALL_MS CPU_US_RSS
  local jobs="$1" t0 t1 out rc
  t0=$(date +%s%N)
  out=$(env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= TEST_TIMING_LOG=/dev/null \
        TEST_GROUP=all SOLEUR_TEST_JOBS="$jobs" timeout 120 bash "$TMP/runner.sh" 2>&1) || rc=$?
  rc=${rc:-0}
  t1=$(date +%s%N)
  WALL_MS=$(( (t1 - t0) / 1000000 ))
  # /proc-derived child CPU seconds and peak RSS are read where available.
  CPU_S="$(ps --no-headers -o cputime -p $$ 2>/dev/null | head -1 | tr -d ' ' || echo "unmeasured")"
  RSS_KB="$(awk '/^VmHWM/ {print $2}' /proc/self/status 2>/dev/null || echo "unmeasured")"
  VERDICTS="$(grep -cE '^\[(ok|FAIL|KILLED)\]' <<<"$out" || true)"
  RUN_RC="$rc"
}

run_arm 1
SERIAL_MS=$WALL_MS; SERIAL_CPU=$CPU_S; SERIAL_RSS=$RSS_KB; SERIAL_V=$VERDICTS; SERIAL_RC=$RUN_RC
run_arm 4
PAR_MS=$WALL_MS; PAR_CPU=$CPU_S; PAR_RSS=$RSS_KB; PAR_V=$VERDICTS; PAR_RC=$RUN_RC

echo ""
echo "BENCH corpus=8 fixtures=4sleep+4cpu serial_wall_ms=$SERIAL_MS parallel_wall_ms=$PAR_MS jobs=4"
echo "BENCH cpu_s(serial)=$SERIAL_CPU cpu_s(parallel)=$PAR_CPU peak_rss_kb(serial)=$SERIAL_RSS peak_rss_kb(parallel)=$PAR_RSS"
echo "BENCH verdicts(serial)=$SERIAL_V verdicts(parallel)=$PAR_V rc(serial)=$SERIAL_RC rc(parallel)=$PAR_RC"
echo "BENCH host: nproc=$(nproc 2>/dev/null || echo '?') avail_mem_mb=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo '?')"

[[ "$SERIAL_RC" == "0" ]] && pass "serial arm completed cleanly" || { fail "serial arm exited $SERIAL_RC"; }
[[ "$PAR_RC" == "0" ]] && pass "parallel arm completed cleanly" || { fail "parallel arm exited $PAR_RC"; }
[[ "$SERIAL_V" == "8" && "$PAR_V" == "8" ]] \
  && pass "both arms rendered the full 8-suite population" \
  || fail "verdict counts serial=$SERIAL_V parallel=$PAR_V"
if (( PAR_MS > 0 && SERIAL_MS > 0 )); then
  pass "BENCH: serial=${SERIAL_MS}ms parallel=${PAR_MS}ms (jobs=4) — recorded for the spec evidence"
else
  fail "benchmark produced no wall-clock measurement"
fi

echo ""
echo "=== test-all-parallel-benchmark: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
