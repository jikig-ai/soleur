#!/usr/bin/env bash
# test-all-enumerate-toolchain.test.sh — a broken bun must not silence this runner (#8231).
#
# WHAT IS UNDER TEST. `scripts/test-all.sh` › the Version Check block. `command -v bun` is too
# weak for the claim its own comment makes: a version-manager SHIM resolves on PATH while being
# unable to run. An unpinned `mise` shim prints `No version is set for shim: bun` and exits
# non-zero; under `set -euo pipefail` the bare `actual=$(bun --version)` was an ABORT, and it
# sits above every registration emit. So the failure was not a missing warning — it was EVERY
# invocation of the runner exiting rc 1 having emitted nothing.
#
# WHY THAT MATTERS. Two consumers fail closed on the record stream and go red for a cause
# neither can name: `scripts/battery-tag-authorship.test.sh` › the `--enumerate-commands`
# root-set guard (rc AND count), and `plugins/soleur/test/scripts-shard-totality.test.sh` ›
# `enumerate_leg()` (count only). `scripts/lint-orphan-test-suites.sh` › the
# `--print-suite-globs` derivation is the same fail-closed shape on the sibling stream.
# Failing closed on a count is the RIGHT design; the producer must not hand them a zero for an
# environment reason.
#
# SCOPE. This pins ONE tool. `tr`, `dirname`, `mktemp` and `mkdir` can still abort the prologue
# with the same rc-1/zero-record signature, and the `dirname` sites do it silently. Do not read
# a green run here as "the enumerate prologue is toolchain-independent".
#
# THE ARMS, and what each exists to stop:
#   R1/R2  the defect itself, on both enumerate modes.
#   R3     must-PASS control: a genuinely bun-FREE host still works. Without it, a runner that
#          refuses everything scores full marks.
#   R4     must-PASS control: a matching bun is silent. R4b is the "does not cry wolf" row.
#   R5     must-PASS control: the mismatch WARNING still fires. Without it the cheapest way to
#          go green is to DELETE the version check, which would revert the capability.
#   R6     asserts the value that must NEVER appear (zero records), not only the value expected.
#   R7     the degraded path must be REPORTED, not silently swallowed.
#   R8     every enumerate group, by rc AND by record COUNT, against a working-bun twin. The
#          count rows are load-bearing: without them a "fix" making `want_bun()` require a
#          runnable bun empties the bun group (435 -> 428) while every rc row stays green —
#          this PR's own defect class surviving this PR's own assertions.
#   R9     PARITY across arms. The registration set must not be a function of bun's state.
#   R10    a NON-enumerate invocation. The abort killed every mode, so pinning only the
#          enumerate projection leaves the others free to regress.
#   R11    a HANG. `|| actual=""` bounds the STATUS, not the TIME.
#   R12    CRLF output. Without normalising the command's output a MATCHING bun warns.
#
# AUTHORING CONSTRAINTS (work/SKILL.md; each cost a debug cycle somewhere):
#   - Never `producer | grep -q` under `set -o pipefail`: an early match closes the pipe, the
#     producer takes SIGPIPE (141), pipefail promotes it, and NEGATIVE assertions fail OPEN.
#   - A deliberately-nonzero command inside `$( … )` aborts under `set -e` before fail() can
#     print — capture rc on its own line.
#   - `cases` is incremented at the CALL SITE, never inside a verdict helper, never in `$( )`.
#
# ADR-193. This file is in `scripts/guard-vacuity-floor.test.sh`'s derived population
# (`COVERED_DIRS='^(scripts/|plugins/soleur/test/)'`). D1 — the floor `exit 1`s directly, never
# through this suite's own fail(). D2 — `cases` moves at the call site. D3 — conservation is
# present. D4 — it runs BEFORE the floor.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only). No `repo-write-boundary-sandbox`
# marker: that marker's population is suites that RELOCATE the runner, and this one invokes it
# in place from REPO_ROOT.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
BUN_VERSION_FILE="$REPO_ROOT/.bun-version"

# Resolved ONCE, before any fixture PATH exists: every invocation below puts a fixture directory
# first on PATH, and `env` would otherwise let that directory supply the interpreter of the
# script under test.
BASH_BIN="$(command -v bash)"

pass_n=0
fails=0
cases=0

# Kept in lockstep with MIN_CASES at the bottom; the derivation check there proves it.
MIN_CASES_EXPECTED=35

# P1b guard (#7708). Every fixture root is asserted before anything is written under it or
# removed with it. Two repo-global ratchets police this and a new suite trips BOTH unless it is
# exact — neither references a file this diff touches, so no file-selected suite set can see
# them: `fixture-relative-assert.test.sh` counts operands that are not provably absolute, and
# `fixture-dir-operand-assert.test.sh` asserts every tracked copy is BYTE-IDENTICAL to canonical.
#
# BYTE-IDENTICAL to `plugins/soleur/test/test-helpers.sh` › `assert_fixture_dir()`. Do not
# reword it here alone — an earlier revision "improved" the empty-operand message and that one
# line is what the equality ratchet calls drift. Copied rather than sourced, matching
# `scripts/check-tom4-rls-posture.test.sh` › `assert_fixture_dir()`, the suite-side precedent.
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

TESTROOT="$(mktemp -d -t test-all-enum-toolchain.XXXXXXXX)"
assert_fixture_dir "$TESTROOT"
FAILLOG="$TESTROOT/failures.log"
: > "$FAILLOG"
# INT/TERM/HUP as well as EXIT: an EXIT-only trap does not fire on Ctrl-C, and this suite runs
# inside the local gate, so interruption is ordinary. What would persist is several directories
# of mode-0755 files named `bun`.
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT INT TERM HUP

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
# Drives BOTH verdict helpers once and refuses to continue unless both counters moved AND fail()
# actually WROTE THE LOG. The log is half the exit gate, so a fail() that counts without writing
# is invisible to a counter-only self-test.
#
# Snapshot-restore, matching `scripts/prod-version-drift-check.test.sh` and
# `plugins/soleur/test/pr-fanout-ledger.test.sh`. FAILLOG is pointed at a scratch file for the
# duration so the deliberate failure never reaches the real log OR the log STREAM: work/SKILL.md
# prescribes "a reap leaves ZERO [FAIL] lines" as a triage discriminator, and a suite printing
# one on every green run retires that leg.
# ---------------------------------------------------------------------------
_self_pass_before=$pass_n
_self_fail_before=$fails
_real_faillog="$FAILLOG"
FAILLOG="$TESTROOT/selftest.log"
: > "$FAILLOG"
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
_self_logged=$(wc -l < "$FAILLOG" | tr -d ' ')
FAILLOG="$_real_faillog"
if (( pass_n != _self_pass_before + 1 )) || (( fails != _self_fail_before + 1 )); then
  printf '\n[FATAL] instrument self-test: pass() moved %d, fail() moved %d; both must move exactly 1.\n' \
    "$((pass_n - _self_pass_before))" "$((fails - _self_fail_before))" >&2
  exit 1
fi
if (( _self_logged != 1 )); then
  printf '\n[FATAL] instrument self-test: fail() wrote %d line(s) to the failure log, expected 1.\n' "$_self_logged" >&2
  printf '        The exit gate reads that log. A fail() that counts without writing it lets\n' >&2
  printf '        this suite print failures and still exit 0.\n' >&2
  exit 1
fi
pass_n=$_self_pass_before
fails=$_self_fail_before
cases=0

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A `bun` that resolves and CANNOT RUN — the mise no-pinned-version shape, reproduced from the
# measured stderr so the fixture cannot drift into a friendlier failure than the real one.
make_broken_bun() {
  local dir="$1"
  # Guarded at the WRITING WINDOW: inside this function `$dir` is a parameter, so it is not
  # provably absolute here, and the redirect below is the site the P1b ratchet counts.
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  cat > "$dir/bun" <<'SHIM'
#!/usr/bin/env bash
echo "mise ERROR No version is set for shim: bun" >&2
echo "Set a global default version with one of the following:" >&2
exit 1
SHIM
  chmod +x "$dir/bun"
}

# A `bun` that works. The version is read from a SIBLING FILE rather than interpolated into the
# shim body: `.bun-version` is a one-token data file that a dependency bump touches and a
# reviewer skims, and interpolating it into a script that is then chmod +x'd and executed makes
# it an input to a generated executable. Removing the channel beats validating it.
make_working_bun() {
  local dir="$1" version="$2"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  cat > "$dir/bun" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  cat "$(dirname "$0")/version.txt"
  exit 0
fi
exit 0
SHIM
  chmod +x "$dir/bun"
  printf '%s\n' "$version" > "$dir/version.txt"
}

# A `bun` that blocks.
make_hanging_bun() {
  local dir="$1"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 600' > "$dir/bun"
  chmod +x "$dir/bun"
}

# A `bun` that emits CRLF. Real shims do.
make_crlf_bun() {
  local dir="$1" version="$2"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  cat > "$dir/bun" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf '%s\r\n' "$(cat "$(dirname "$0")/version.txt")"
  exit 0
fi
exit 0
SHIM
  chmod +x "$dir/bun"
  printf '%s\n' "$version" > "$dir/version.txt"
}

# The base PATH every fixture PATH is built on.
#
# Hardcoding `/usr/bin:/bin` makes this suite fail for a toolchain-LOCATION reason on a Homebrew
# or Nix host — and every arm would report it as a version-check abort, the misattribution class
# this file exists to end. Start from `getconf PATH`, then append the caller's entries with
# every bun-bearing directory removed (appending the caller's PATH raw would defeat R3).
_base_path="$(getconf PATH 2>/dev/null || printf '/usr/bin:/bin')"
while IFS= read -r -d ':' _d || [[ -n "${_d:-}" ]]; do
  [[ -n "${_d:-}" ]] || continue
  [[ -x "$_d/bun" ]] && continue
  case ":$_base_path:" in *":$_d:"*) continue ;; esac
  _base_path="$_base_path:$_d"
done < <(printf '%s:' "${PATH:-}")

# `env -i` with an explicit allowlist rather than a hand-maintained `-u` list: the list drifts as
# the runner grows branches, and an inherited value it misses reds every arm with a confidently
# wrong message. Measured: an inherited non-absolute INCIDENTS_REPO_ROOT makes the runner exit 1
# before the version check, and every arm then reports "the version check aborted the runner" —
# false, and it points the operator at the code this file pins.
run_enumerate() {
  local tag="$1" path_val="$2"; shift 2
  local out="$TESTROOT/$tag.out" err="$TESTROOT/$tag.err"
  local rc=0
  ( cd "$REPO_ROOT" && env -i \
      PATH="$path_val" \
      HOME="${HOME:-/nonexistent}" \
      TERM="${TERM:-dumb}" \
      "$BASH_BIN" "$RUNNER" "$@" ) > "$out" 2> "$err" || rc=$?
  printf '%s' "$rc" > "$TESTROOT/$tag.rc"
}

records_of() { grep -c '^SUITE_REGISTRATION' "$TESTROOT/$1.out" 2>/dev/null || true; }
commands_of() { grep -c '^SUITE_COMMAND' "$TESTROOT/$1.out" 2>/dev/null || true; }
rc_of() { cat "$TESTROOT/$1.rc"; }

BROKEN_BIN="$TESTROOT/broken-bin"; make_broken_bun "$BROKEN_BIN"
MATCH_BIN="$TESTROOT/match-bin";   make_working_bun "$MATCH_BIN" "$EXPECTED_BUN"
DRIFT_BIN="$TESTROOT/drift-bin";   make_working_bun "$DRIFT_BIN" "0.0.1-not-the-pinned-version"
HANG_BIN="$TESTROOT/hang-bin";     make_hanging_bun "$HANG_BIN"
CRLF_BIN="$TESTROOT/crlf-bin";     make_crlf_bun "$CRLF_BIN" "$EXPECTED_BUN"
EMPTY_BIN="$TESTROOT/empty-bin";   assert_fixture_dir "$EMPTY_BIN"; mkdir -p "$EMPTY_BIN"

BROKEN_PATH="$BROKEN_BIN:$_base_path"
MATCH_PATH="$MATCH_BIN:$_base_path"
DRIFT_PATH="$DRIFT_BIN:$_base_path"
HANG_PATH="$HANG_BIN:$_base_path"
CRLF_PATH="$CRLF_BIN:$_base_path"
ABSENT_PATH="$EMPTY_BIN:$_base_path"

# Fixture precondition self-checks. A fixture that does not instantiate the condition its arm is
# named for proves nothing. These abort rather than fail(): a broken fixture is a harness bug,
# not a product verdict.
for _tool in git python3 sed awk; do
  if ! PATH="$_base_path" command -v "$_tool" >/dev/null 2>&1; then
    echo "ERROR: fixture precondition failed — '$_tool' does not resolve under the derived base PATH, so every arm would fail for a toolchain-location reason and report it as a version-check abort" >&2
    exit 1
  fi
done
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

# The enumerate groups, DERIVED from the runner's own TEST_GROUP validation arm rather than
# restated, so a group added there cannot escape R8 silently. `all` is excluded: R1/R3/R4/R5
# already drive it.
ENUM_GROUPS=()
while IFS= read -r _g; do
  [[ -n "$_g" && "$_g" != "all" ]] && ENUM_GROUPS+=("$_g")
done < <(sed -n 's/^[[:space:]]*\(all|[a-z|-]*\))[[:space:]]*;;.*$/\1/p' "$RUNNER" | head -1 | tr '|' '\n')
# CARDINALITY IS NOT VALIDITY. An earlier revision of this block checked only the count, and
# passed on garbage: `GROUPS` is a bash SPECIAL ARRAY holding the current user's group ids, so
# `GROUPS=()` does not clear it and `+=` appended to `1000 998` (`id -G`). The count check said
# "2 groups, fine" and R8 then drove `--enumerate 1000`. Assert the derived names are names the
# runner actually accepts.
if (( ${#ENUM_GROUPS[@]} < 2 )); then
  echo "ERROR: fixture precondition failed — derived only ${#ENUM_GROUPS[@]} enumerate group(s) from the runner's TEST_GROUP case arm; the derivation has drifted" >&2
  exit 1
fi
for _g in "${ENUM_GROUPS[@]}"; do
  if [[ ! "$_g" =~ ^[a-z-]+$ ]]; then
    echo "ERROR: fixture precondition failed — derived enumerate group '$_g' is not a lowercase name; the derivation is reading something other than the runner's TEST_GROUP case arm" >&2
    exit 1
  fi
  if ! grep -qE "^[[:space:]]*all\|.*\b${_g}\b.*\)[[:space:]]*;;" "$RUNNER"; then
    echo "ERROR: fixture precondition failed — derived group '$_g' does not appear in the runner's TEST_GROUP case arm" >&2
    exit 1
  fi
done

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
  fail "R1b --enumerate all emitted ZERO SUITE_REGISTRATION records under a broken bun shim"
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
_r4warn="$(grep -cF "expected $EXPECTED_BUN" "$TESTROOT/r4.err" 2>/dev/null || true)"
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
# Anchored on the runner's own emitted text, not a bare token: r1.err also carries the fixture
# shim's stderr and any contention banner, and both mention bun.
_r7warn="$(grep -cE "^WARNING: 'bun --version' produced no version" "$TESTROOT/r1.err" 2>/dev/null || true)"
if (( _r7warn >= 1 )); then
  pass "R7 a resolvable-but-unrunnable bun produces the runner's own diagnostic on stderr"
else
  fail "R7 a broken bun shim was skipped SILENTLY; a degraded toolchain that reports nothing is the fail-quiet class the consumers exist to prevent"
fi

echo "== R8: every enumerate group survives a broken shim, by rc AND by count =="
for _g in "${ENUM_GROUPS[@]}"; do
  run_enumerate "r8_$_g" "$BROKEN_PATH" --enumerate "$_g"
  cases=$((cases + 1))
  if [[ "$(rc_of "r8_$_g")" == "0" ]]; then
    pass "R8[$_g] --enumerate $_g exits 0 under a broken bun shim"
  else
    fail "R8[$_g] --enumerate $_g exited $(rc_of "r8_$_g") under a broken bun shim"
  fi
  run_enumerate "r8w_$_g" "$MATCH_PATH" --enumerate "$_g"
  cases=$((cases + 1))
  _bn="$(records_of "r8_$_g")"; _wn="$(records_of "r8w_$_g")"
  if (( _bn == _wn )); then
    pass "R8[$_g] emits the same $_bn record(s) under a broken bun as under a working one"
  else
    fail "R8[$_g] emitted $_bn record(s) under a broken bun vs $_wn under a working one; bun's state is deciding the registration SET"
  fi
done

echo "== R9: the registration set is not a function of bun's state =="
for _tag in r1 r3 r5; do
  cases=$((cases + 1))
  _a="$(records_of "$_tag")"; _b="$(records_of r4)"
  if (( _a == _b )); then
    pass "R9[$_tag] emits the same $_a record(s) as the working-bun arm"
  else
    fail "R9[$_tag] emitted $_a record(s) against the working-bun arm's $_b; a toolchain state is changing which suites are registered"
  fi
done

echo "== R10: the defect was not enumerate-specific; a non-enumerate path must reach past the check =="
# The probe must TRAVERSE the version check, which is what makes choosing it delicate. An earlier
# revision used `--capacity`; `scripts/test-all.sh` › the `--capacity` handler returns ABOVE the
# `# --- Version Check ---` block, so the arm never reached the code it named and a guard scoped
# to `_ENUMERATE` alone passed it 32/32 — a fixture that cannot contain the thing it looks for.
#
# An invalid TEST_GROUP is validated by `scripts/test-all.sh` › the `TEST_GROUP` case arm, which
# sits BELOW the Version Check and exits 2 with a distinctive message. Reaching that message is
# proof the prologue ran to completion; the pre-fix abort dies inside the Version Check and never
# prints it. Fast, runs no suite.
run_enumerate r10 "$BROKEN_PATH" __not_a_real_group__
cases=$((cases + 1))
if [[ "$(rc_of r10)" == "2" ]]; then
  pass "R10a a non-enumerate invocation reaches TEST_GROUP validation (rc 2) under a broken bun shim"
else
  fail "R10a a non-enumerate invocation exited $(rc_of r10), not 2, under a broken bun shim; the prologue aborted before reaching group validation"
fi
cases=$((cases + 1))
_r10msg="$(grep -cF 'TEST_GROUP must be one of' "$TESTROOT/r10.err" 2>/dev/null || true)"
if (( _r10msg >= 1 )); then
  pass "R10b it printed the group-validation error, proving it executed the whole prologue"
else
  fail "R10b the group-validation error never printed; the runner died in the prologue, so the guard covers only the enumerate path while the abort kills every mode"
fi

echo "== R11: a bun that HANGS must not block the runner =="
_t0=$(date +%s)
run_enumerate r11 "$HANG_PATH" --enumerate all
_elapsed=$(( $(date +%s) - _t0 ))
cases=$((cases + 1))
if [[ "$(rc_of r11)" == "0" ]]; then
  pass "R11a --enumerate all exits 0 under a bun that blocks"
else
  fail "R11a --enumerate all exited $(rc_of r11) under a hanging bun"
fi
cases=$((cases + 1))
if (( _elapsed < 120 )); then
  pass "R11b the hanging bun was bounded (${_elapsed}s); the || arm bounds the status, only a timeout bounds the time"
else
  fail "R11b the runner took ${_elapsed}s under a hanging bun — the version read is unbounded"
fi
cases=$((cases + 1))
_r11n="$(records_of r11)"
if (( _r11n >= 1 )); then
  pass "R11c a hanging bun does not empty the enumerate stream ($_r11n records)"
else
  fail "R11c a hanging bun emptied the enumerate stream"
fi

echo "== R12: a CRLF-emitting bun must not produce a self-contradicting warning =="
run_enumerate r12 "$CRLF_PATH" --enumerate all
cases=$((cases + 1))
_r12warn="$(grep -cF "expected $EXPECTED_BUN" "$TESTROOT/r12.err" 2>/dev/null || true)"
if (( _r12warn == 0 )); then
  pass "R12 a bun emitting CRLF around the pinned version is treated as matching"
else
  fail "R12 a CRLF-emitting bun produced a mismatch warning against its own byte-identical version; the command's output is not whitespace-normalised"
fi

# ---------------------------------------------------------------------------
# ADR-193 D3 — accounting conservation. Runs BEFORE the floor (D4).
# ---------------------------------------------------------------------------
if (( pass_n + fails != cases )); then
  printf '\n[FATAL] accounting: %d passed + %d failed != %d assertions.\n' "$pass_n" "$fails" "$cases" >&2
  if (( pass_n + fails < cases )); then
    printf '        Fewer verdicts than assertions: a call site incremented `cases` without\n' >&2
    printf '        recording a verdict, or a verdict helper was stubbed to a no-op.\n' >&2
  else
    printf '        More verdicts than assertions: a verdict was recorded at a call site with no\n' >&2
    printf '        cases increment before it.\n' >&2
  fi
  echo "=== test-all-enumerate-toolchain: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# ADR-193 D1/H2 — the anti-vacuity floor.
#
# `exit 1` DIRECTLY, never through this suite's own fail(). DERIVED BY RUNNING THE AS-WRITTEN
# FILE: 22 fixed rows plus 2 per derived group. Zero slack is deliberate — floor slack is attack
# budget, because every assertion above the floor can be undispatched without the floor looking.
# ---------------------------------------------------------------------------
# The derived half is checked FIRST and separately, so the floor's own bound can stay a literal.
_expected_cases=$(( 25 + 2 * ${#ENUM_GROUPS[@]} ))
if (( MIN_CASES_EXPECTED != _expected_cases )); then
  printf '\n[FATAL] floor derivation: 25 fixed + 2 x %d group(s) = %d, but the literal floor is %d.\n' \
    "${#ENUM_GROUPS[@]}" "$_expected_cases" "$MIN_CASES_EXPECTED" >&2
  printf '        A group was added to or removed from the runner. Update the literal below.\n' >&2
  exit 1
fi

# THE BOUND STAYS A LITERAL, adjacent to this `if`. `scripts/guard-vacuity-floor.test.sh` ›
# build_mutant() constructs its mutant by walking back from the floor's `if` over simple
# assignments and re-running the block with the counters zeroed; a COMPUTED bound referencing an
# array the mutant does not carry drops this suite into its unconstructible set. Measured: with
# the bound written as `$(( 23 + 2 * ${#ENUM_GROUPS[@]} ))` that guard reported 22/1, naming this
# file as "a floor enforced THROUGH the machinery it guards". The derivation check above keeps
# the literal honest without putting an expansion next to the `if`.
MIN_CASES=35
if (( cases < MIN_CASES )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_CASES" >&2
  echo "=== test-all-enumerate-toolchain: $pass_n passed, $fails failed ($cases assertions) ==="
  exit 1
fi

echo "=== test-all-enumerate-toolchain: $pass_n passed, $fails failed ($cases assertions) ==="
# DUAL-SOURCE. The counter alone is silenced by redirecting an increment; the append-only log
# alone is silenced by dropping the write from fail() — measured, that one edit printed ten
# [FAIL] lines, reported "10 passed, 10 failed" and exited 0, which run_suite reads as green.
# Either source going quiet must still fail the suite.
if (( fails != 0 )) || [[ -s "$FAILLOG" ]]; then
  exit 1
fi
