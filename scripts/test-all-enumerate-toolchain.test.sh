#!/usr/bin/env bash
# test-all-enumerate-toolchain.test.sh — `--enumerate` must not depend on a working bun (#8231).
#
# WHAT IS UNDER TEST. One property, stated as the runner's own Version Check comment states it:
#
#   "Gated on bun being installed so the script runs cleanly in a bun-free environment"
#
# `command -v bun` is the gate that comment relies on, and it is TOO WEAK for the claim. It is
# satisfied by a SHIM that resolves but cannot run — a `mise` shim with no version pinned prints
#
#   mise ERROR No version is set for shim: bun
#
# to stderr and exits non-zero. The runner is `set -euo pipefail` (line 2), so the bare
# `actual=$(bun --version)` was an ABORT, not a skipped check. That abort sits ABOVE every
# registration emit, so the failure mode is not "the version check was skipped" — it is
# `--enumerate` returning ZERO records at rc 1, on a host where nothing about the battery is
# actually wrong.
#
# WHY THAT MATTERS MORE THAN A MISSING WARNING. Three registered consumers fail CLOSED on the
# enumerate stream's rc AND its record count, which is correct of them and is what converts this
# into a red suite with no nameable cause:
#
#   scripts/battery-tag-authorship.test.sh:224-260   — refuses to classify against an empty root
#                                                      set; measured exit 1 on this host.
#   plugins/soleur/test/scripts-shard-totality.test.sh
#   plugins/soleur/test/fullsuite-merge-gate.test.ts
#
# The same shape guards `--print-suite-globs` at scripts/lint-orphan-test-suites.sh:229-232. A
# consumer that fails closed on a count is the RIGHT design; it is the producer that must not
# hand it a zero for an environment reason.
#
# ANTI-VACUITY NOTE. R3 is the must-PASS control that stops this suite from being satisfied by a
# runner that refuses everything, and R5 is the must-PASS row that stops the fix from being
# "delete the version check" — the WARNING capability has to survive, or the guard is a
# regression wearing a fix's clothes. R6 asserts the value that must NEVER appear (zero records),
# rather than only asserting the value expected.
#
# AUTHORING CONSTRAINTS (work/SKILL.md; each cost a debug cycle somewhere):
#   - Never `producer | grep -q` under `set -o pipefail`: an early match closes the pipe, the
#     producer takes SIGPIPE (141), pipefail promotes it, and every NEGATIVE assertion fails
#     OPEN. Grep a FILE, or `grep -c` on a herestring.
#   - A deliberately-nonzero command inside `$( … )` aborts under `set -e` before fail() can
#     print — suffix `|| true` INSIDE the substitution, or capture rc on its own line.
#   - `cases` is incremented at the CALL SITE, never inside pass()/fail() and never inside
#     `$( … )` (a subshell increment is discarded).
#
# ADR-193 COMPLIANCE. This file lives under `scripts/`, which scripts/guard-vacuity-floor.test.sh
# declares in its DERIVED population (`COVERED_DIRS='^(scripts/|plugins/soleur/test/)'`), so it is
# enrolled the moment it lands. D1 — the floor `exit 1`s directly, never through this suite's own
# fail(). D2 — `cases` moves at the call site. D3 — an accounting-conservation check is present.
# D4 — it runs BEFORE the floor.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): fake `bun` shims written into
# TESTROOT, and nothing written outside it.
#
# repo-write-boundary-sandbox: not-needed every arm drives `--enumerate`, which emits registrations instead of executing any suite, so no suite body ever runs to write anything (#8231)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
BUN_VERSION_FILE="$REPO_ROOT/.bun-version"

pass_n=0
fails=0
cases=0

TESTROOT="$(mktemp -d -t test-all-enum-toolchain.XXXXXXXX)"
FAILLOG="$TESTROOT/failures.log"
: > "$FAILLOG"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

# Every failure is ALSO appended to a file, and the exit decision at the bottom reads THAT, not
# the counter: silencing an append-only record means DELETING EVIDENCE, not moving a number.
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; printf '%s\n' "$1" >> "$FAILLOG"; }

for _required in "$RUNNER" "$BUN_VERSION_FILE"; do
  if [[ ! -f "$_required" ]]; then
    echo "ERROR: $_required does not exist" >&2
    exit 1
  fi
done

EXPECTED_BUN="$(tr -d '[:space:]' < "$BUN_VERSION_FILE")"
if [[ -z "$EXPECTED_BUN" ]]; then
  echo "ERROR: .bun-version is empty — every arm below depends on the runner reading a version from it" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Instrument self-test (ADR-193 H1).
#
# Drive BOTH verdict helpers once each and refuse to continue unless both counters moved. A suite
# whose only gate is a failure counter can report 0 failures having asserted nothing; a suite
# whose pass() is a no-op reports a green it never earned. Neither is detectable from the summary
# line, so it is checked here rather than inferred.
# ---------------------------------------------------------------------------
_self_pass_before=$pass_n
_self_fail_before=$fails
pass "instrument self-test: pass() is live"
fail "instrument self-test: fail() is live (this [FAIL] line is EXPECTED and is retracted below)"
if (( pass_n != _self_pass_before + 1 )) || (( fails != _self_fail_before + 1 )); then
  printf '\n[FATAL] instrument self-test: pass() moved %d, fail() moved %d; both must move exactly 1.\n' \
    "$((pass_n - _self_pass_before))" "$((fails - _self_fail_before))" >&2
  exit 1
fi
# Retract the deliberate failure from BOTH the counter and the append-only record, so the
# self-test cannot leave the suite permanently red. The retraction is narrow on purpose: it
# removes exactly the one line it wrote, by exact match, rather than truncating the log.
fails=$((fails - 1))
grep -vxF "instrument self-test: fail() is live (this [FAIL] line is EXPECTED and is retracted below)" \
  "$FAILLOG" > "$FAILLOG.tmp" || true
mv "$FAILLOG.tmp" "$FAILLOG"
if [[ -s "$FAILLOG" ]]; then
  printf '\n[FATAL] instrument self-test: retraction left residue in the failure log.\n' >&2
  exit 1
fi
pass_n=$((pass_n - 1))
cases=0

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A `bun` that resolves on PATH and CANNOT RUN — the mise no-pinned-version shape, reproduced
# byte-for-byte from the measured stderr so the fixture cannot drift into a friendlier failure
# than the real one.
make_broken_bun() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/bun" <<'SHIM'
#!/usr/bin/env bash
echo "mise ERROR No version is set for shim: bun" >&2
echo "Set a global default version with one of the following:" >&2
echo "mise use -g bun@1.3.14" >&2
exit 1
SHIM
  chmod +x "$dir/bun"
}

# A `bun` that works and reports the version it is told to report.
make_working_bun() {
  local dir="$1" version="$2"
  mkdir -p "$dir"
  cat > "$dir/bun" <<SHIM
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  echo "$version"
  exit 0
fi
exit 0
SHIM
  chmod +x "$dir/bun"
}

# Clear every variable the runner branches on, so an inherited value cannot decide an arm.
# `CI` in particular changes tc_acquire's path; `SOLEUR_SUBAGENT` reaches the exit-4 refusal.
RUN_CLEAN=(env
  -u CI
  -u SOLEUR_SUBAGENT
  -u SOLEUR_ALLOW_FULL_GATE
  -u SOLEUR_TEST_FORCE_ALL
  -u SOLEUR_INCIDENT_SKIP
  -u TEST_GROUP
  -u SCRIPTS_SHARD
  -u TEST_TIMING_LOG
)

# Run the runner from REPO_ROOT with a given PATH, capturing stdout, stderr and rc separately.
# rc is captured on its OWN line immediately after the command whose status matters — never
# through a pipe, which would take the pipe's status and destroy the evidence in one stroke.
run_enumerate() {
  local tag="$1" path_val="$2"; shift 2
  local out="$TESTROOT/$tag.out" err="$TESTROOT/$tag.err"
  local rc=0
  ( cd "$REPO_ROOT" && "${RUN_CLEAN[@]}" PATH="$path_val" bash "$RUNNER" "$@" ) \
    > "$out" 2> "$err" || rc=$?
  printf '%s' "$rc" > "$TESTROOT/$tag.rc"
}

records_of() { grep -c '^SUITE_REGISTRATION' "$TESTROOT/$1.out" 2>/dev/null || true; }
commands_of() { grep -c '^SUITE_COMMAND' "$TESTROOT/$1.out" 2>/dev/null || true; }
rc_of() { cat "$TESTROOT/$1.rc"; }

BROKEN_BIN="$TESTROOT/broken-bin"; make_broken_bun "$BROKEN_BIN"
MATCH_BIN="$TESTROOT/match-bin";   make_working_bun "$MATCH_BIN" "$EXPECTED_BUN"
DRIFT_BIN="$TESTROOT/drift-bin";   make_working_bun "$DRIFT_BIN" "0.0.1-not-the-pinned-version"
EMPTY_BIN="$TESTROOT/empty-bin";   mkdir -p "$EMPTY_BIN"

BROKEN_PATH="$BROKEN_BIN:/usr/bin:/bin"
MATCH_PATH="$MATCH_BIN:/usr/bin:/bin"
DRIFT_PATH="$DRIFT_BIN:/usr/bin:/bin"
ABSENT_PATH="$EMPTY_BIN:/usr/bin:/bin"

# Fixture precondition self-checks. If a fixture does not instantiate the condition its arm is
# named for, the arm proves nothing — and a vacuous green here is exactly the failure this suite
# exists to make impossible elsewhere. These abort rather than fail(): a broken fixture is a
# harness bug, not a product verdict.
if PATH="$ABSENT_PATH" command -v bun >/dev/null 2>&1; then
  echo "ERROR: fixture precondition failed — bun is still resolvable under the bun-free PATH, so R3 would not test a bun-free environment" >&2
  exit 1
fi
if ! PATH="$BROKEN_PATH" command -v bun >/dev/null 2>&1; then
  echo "ERROR: fixture precondition failed — the broken shim is not resolvable, so R1 would test a bun-free environment rather than a broken-shim one" >&2
  exit 1
fi
if PATH="$BROKEN_PATH" bun --version >/dev/null 2>&1; then
  echo "ERROR: fixture precondition failed — the broken shim SUCCEEDED; it must exit non-zero or R1 is vacuous" >&2
  exit 1
fi
if [[ "$(PATH="$MATCH_PATH" bun --version 2>/dev/null)" != "$EXPECTED_BUN" ]]; then
  echo "ERROR: fixture precondition failed — the matching shim does not report $EXPECTED_BUN" >&2
  exit 1
fi

echo "== R1: a broken bun shim must not empty the enumerate stream =="
run_enumerate r1 "$BROKEN_PATH" --enumerate all
cases=$((cases + 1))
if [[ "$(rc_of r1)" == "0" ]]; then
  pass "R1a --enumerate all exits 0 under a resolvable-but-unrunnable bun"
else
  fail "R1a --enumerate all exited $(rc_of r1) under a broken bun shim; the version check aborted the runner above every registration emit"
fi
cases=$((cases + 1))
_r1n="$(records_of r1)"
if (( _r1n >= 1 )); then
  pass "R1b --enumerate all emitted $_r1n SUITE_REGISTRATION record(s) under a broken bun shim"
else
  fail "R1b --enumerate all emitted ZERO SUITE_REGISTRATION records under a broken bun shim; every consumer that fails closed on count goes red for an environment reason"
fi

echo "== R2: the same holds for --enumerate-commands =="
run_enumerate r2 "$BROKEN_PATH" --enumerate-commands all
cases=$((cases + 1))
if [[ "$(rc_of r2)" == "0" ]]; then
  pass "R2a --enumerate-commands all exits 0 under a broken bun shim"
else
  fail "R2a --enumerate-commands all exited $(rc_of r2) under a broken bun shim"
fi
cases=$((cases + 1))
_r2n="$(commands_of r2)"
if (( _r2n >= 1 )); then
  pass "R2b --enumerate-commands all emitted $_r2n SUITE_COMMAND record(s) under a broken bun shim"
else
  fail "R2b --enumerate-commands all emitted ZERO SUITE_COMMAND records under a broken bun shim"
fi

echo "== R3 (must-PASS control): the documented bun-free environment still works =="
run_enumerate r3 "$ABSENT_PATH" --enumerate all
cases=$((cases + 1))
if [[ "$(rc_of r3)" == "0" ]]; then
  pass "R3a --enumerate all exits 0 with no bun on PATH at all"
else
  fail "R3a --enumerate all exited $(rc_of r3) with no bun on PATH; the guard broke the bun-free path its own comment promises"
fi
cases=$((cases + 1))
_r3n="$(records_of r3)"
if (( _r3n >= 1 )); then
  pass "R3b --enumerate all emitted $_r3n record(s) with no bun on PATH"
else
  fail "R3b --enumerate all emitted ZERO records with no bun on PATH"
fi

echo "== R4 (must-PASS): a matching bun is unchanged and silent =="
run_enumerate r4 "$MATCH_PATH" --enumerate all
cases=$((cases + 1))
if [[ "$(rc_of r4)" == "0" ]]; then
  pass "R4a --enumerate all exits 0 with a matching bun"
else
  fail "R4a --enumerate all exited $(rc_of r4) with a matching bun"
fi
cases=$((cases + 1))
_r4warn="$(grep -cF 'expected ' "$TESTROOT/r4.err" 2>/dev/null || true)"
if (( _r4warn == 0 )); then
  pass "R4b no version-mismatch warning is emitted when the installed bun matches .bun-version"
else
  fail "R4b a version-mismatch warning fired on a MATCHING bun ($_r4warn line(s)); the check now cries wolf"
fi

echo "== R5 (must-PASS): the mismatch WARNING capability survives the fix =="
run_enumerate r5 "$DRIFT_PATH" --enumerate all
cases=$((cases + 1))
if [[ "$(rc_of r5)" == "0" ]]; then
  pass "R5a a version MISMATCH warns without failing the run"
else
  fail "R5a --enumerate all exited $(rc_of r5) on a version mismatch; the check must warn, never abort"
fi
cases=$((cases + 1))
_r5warn="$(grep -cF "expected $EXPECTED_BUN" "$TESTROOT/r5.err" 2>/dev/null || true)"
if (( _r5warn >= 1 )); then
  pass "R5b the mismatch warning still names the expected version $EXPECTED_BUN"
else
  fail "R5b NO mismatch warning was emitted for a bun reporting a wrong version; the fix deleted the capability instead of guarding it"
fi
cases=$((cases + 1))
_r5n="$(records_of r5)"
if (( _r5n >= 1 )); then
  pass "R5c a warning does not cost the enumerate stream its records ($_r5n)"
else
  fail "R5c the mismatch warning emptied the enumerate stream"
fi

echo "== R6: the value that must NEVER appear, across every toolchain state =="
for _tag in r1 r3 r4 r5; do
  cases=$((cases + 1))
  _n="$(records_of "$_tag")"
  if (( _n > 0 )); then
    pass "R6[$_tag] record count is non-zero ($_n) — a zero here is indistinguishable from an empty battery"
  else
    fail "R6[$_tag] record count is ZERO; a consumer failing closed on count cannot tell this from a battery with no suites"
  fi
done

echo "== R7: the broken shim is REPORTED, not silently swallowed =="
cases=$((cases + 1))
_r7warn="$(grep -ciE 'bun.*(not|fail|unusable|skipping)' "$TESTROOT/r1.err" 2>/dev/null || true)"
if (( _r7warn >= 1 )); then
  pass "R7 a resolvable-but-unrunnable bun produces a diagnostic on stderr rather than a silent skip"
else
  fail "R7 a broken bun shim was skipped SILENTLY; a degraded toolchain that reports nothing is the fallback class cq-silent-fallback-must-mirror-to-sentry exists to forbid"
fi

echo "== R8: every enumerate group survives a broken shim =="
for _g in scripts bun webplat infra; do
  run_enumerate "r8_$_g" "$BROKEN_PATH" --enumerate "$_g"
  cases=$((cases + 1))
  if [[ "$(rc_of "r8_$_g")" == "0" ]]; then
    pass "R8[$_g] --enumerate $_g exits 0 under a broken bun shim"
  else
    fail "R8[$_g] --enumerate $_g exited $(rc_of "r8_$_g") under a broken bun shim"
  fi
done

# ---------------------------------------------------------------------------
# ADR-193 D3 — accounting conservation. Runs BEFORE the floor (D4).
# ---------------------------------------------------------------------------
if (( pass_n + fails != cases )); then
  printf '\n[FATAL] accounting: %d passed + %d failed != %d assertions.\n' "$pass_n" "$fails" "$cases" >&2
  printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it, or a\n' >&2
  printf '  verdict helper was stubbed. This is a harness bug, not a product failure.\n' >&2
  echo "=== test-all-enumerate-toolchain: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# ADR-193 D1/H2 — the anti-vacuity floor.
#
# `exit 1` DIRECTLY, never through this suite's own fail(): a floor routed through the verdict
# helper cannot witness a broken verdict helper. Deleting every fixture so zero arms run fails
# here on `0 passed, 0 failed`.
#
# DERIVED BY RUNNING THE AS-WRITTEN FILE, never estimated from prose. Zero slack is deliberate:
# floor slack is attack budget, because every assertion above the floor can be undispatched
# without the floor looking.
# ---------------------------------------------------------------------------
MIN_CASES=20
if (( cases < MIN_CASES )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_CASES" >&2
  echo "=== test-all-enumerate-toolchain: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

echo "=== test-all-enumerate-toolchain: $pass_n passed, $fails failed ($cases assertions) ==="
# Reads the append-only record, never the counter. See fail() above.
[[ ! -s "$FAILLOG" ]] || exit 1
