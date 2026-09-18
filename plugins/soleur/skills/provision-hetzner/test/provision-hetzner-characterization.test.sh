#!/usr/bin/env bash
# Characterization suite for provision-hetzner.sh (#8287 Phase 1).
#
# This is the SAFETY NET for the Phase 4 library refactor: it pins today's
# observable `--dry-run` behaviour byte-for-byte so the refactor can be proven
# behaviour-preserving rather than asserted to be.
#
# Three things this suite exists to pin, each of which the refactor could
# silently change:
#   1. the `--dry-run` stdout, byte-for-byte;
#   2. that a SUCCESSFUL `--dry-run` still emits the teardown block (the EXIT
#      trap fires after `exit 0`) — the "duplicate teardown" the plan names;
#   3. that `--help` and bad-argument exits print NO teardown, while DPA-gate
#      exits (rc 3) DO.
#
# Runs with cwd OUTSIDE the repository (the DPA gate reads a path relative to
# cwd), against a synthesized fixture register.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SUITE_DIR}/../scripts/provision-hetzner.sh"
FIXTURE_KB="${SUITE_DIR}/fixture/knowledge-base"

# ONE counter per outcome: the self-test, the anti-vacuity floor and the verdict
# all read these two names (review P1-5 — a shadow `fails` beside `FAIL_COUNT`
# let a dropped increment print [FAIL] and exit 0).
PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }

# Instrument self-test (ADR-193): drive both helpers once each and refuse to
# continue unless both counters moved. A battery whose helpers are neutered
# reports a clean run, so this must run BEFORE any real assertion. Reported via
# printf + exit, never via the helpers under test.
_st_p=$PASS_COUNT; _st_f=$FAIL_COUNT
pass "instrument self-test: pass() reached" >/dev/null
fail "instrument self-test: fail() reached (expected, not a real failure)" 2>/dev/null
if [[ "$PASS_COUNT" -ne $((_st_p + 1)) || "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: pass/fail helpers did not both move (pass %s->%s, fail %s->%s)\n' \
    "$_st_p" "$PASS_COUNT" "$_st_f" "$FAIL_COUNT" >&2
  exit 2
fi
# Unwind the accounting the self-test perturbed; count the self-test itself once.
PASS_COUNT=1; FAIL_COUNT=0
echo "  [ok] instrument self-test: both helpers dispatch"

[[ -f "$SCRIPT" ]] || { printf 'HARNESS: script not found at %s\n' "$SCRIPT" >&2; exit 2; }
[[ -d "$FIXTURE_KB" ]] || { printf 'HARNESS: fixture register not found at %s\n' "$FIXTURE_KB" >&2; exit 2; }

SB="$(mktemp -d -t hetzner-char.XXXXXXXX)" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/run" || { printf 'HARNESS: mkdir failed\n' >&2; exit 2; }
cp -r "$FIXTURE_KB" "$SB/run/" || { printf 'HARNESS: fixture copy failed\n' >&2; exit 2; }

# `hcloud` only has to EXIST for the pre-check; --dry-run never invokes it.
# Exit 64 on any invocation so an accidental network call is loud, not silent.
printf '#!/usr/bin/env bash\necho "STUB hcloud invoked: $*" >&2\nexit 64\n' > "$SB/bin/hcloud"
chmod +x "$SB/bin/hcloud"

run_script() {
  # Always from $SB/run — OUTSIDE the repository (task 1.8).
  ( cd "$SB/run" && PATH="$SB/bin:$PATH" bash "$SCRIPT" "$@" 2>&1 )
}

echo "== provision-hetzner characterization =="

# --- 1. Golden --dry-run stdout, byte-for-byte -------------------------------
GOLDEN="${SUITE_DIR}/fixture/provision-hetzner-dry-run.golden"
actual="$(run_script fixture-tenant --dry-run)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "--dry-run exits 0"
else
  fail "--dry-run exits 0 (got $rc)"
fi

if [[ -f "$GOLDEN" ]]; then
  if diff -u "$GOLDEN" <(printf '%s\n' "$actual") > "$SB/diff.txt" 2>&1; then
    pass "--dry-run stdout is byte-identical to the golden"
  else
    fail "--dry-run stdout DIFFERS from the golden:"
    sed -n '1,40p' "$SB/diff.txt" >&2
  fi
else
  fail "golden file missing at $GOLDEN"
fi

# --- 2. A successful --dry-run STILL emits the teardown block ----------------
# The EXIT trap fires after `exit 0`, so the dry-run prints its own guidance
# AND the trap's teardown. Pinning this stops the refactor from "tidying" it.
if grep -qF '=== Teardown commands (resources created during this run) ===' <<<"$actual"; then
  pass "successful --dry-run emits the teardown block (EXIT trap after exit 0)"
else
  fail "successful --dry-run no longer emits the teardown block"
fi
if grep -qF '(no resources were created)' <<<"$actual"; then
  pass "teardown block reports no resources created on a dry run"
else
  fail "teardown block lost its empty-resources arm"
fi

# --- 3. --help and bad arguments print NO teardown --------------------------
help_out="$(run_script --help)"; help_rc=$?
if [[ "$help_rc" -eq 1 ]]; then
  pass "--help exits 1"
else
  fail "--help exits 1 (got $help_rc)"
fi
if grep -qF 'Teardown commands' <<<"$help_out"; then
  fail "--help printed a teardown block (it must not)"
else
  pass "--help prints no teardown block"
fi

bad_out="$(run_script --nope)"; bad_rc=$?
if [[ "$bad_rc" -eq 1 ]]; then
  pass "unknown flag exits 1"
else
  fail "unknown flag exits 1 (got $bad_rc)"
fi
if grep -qF 'Teardown commands' <<<"$bad_out"; then
  fail "unknown flag printed a teardown block (it must not)"
else
  pass "unknown flag prints no teardown block"
fi

noslug_out="$(run_script)"; noslug_rc=$?
if [[ "$noslug_rc" -eq 1 ]]; then
  pass "missing slug exits 1"
else
  fail "missing slug exits 1 (got $noslug_rc)"
fi
if grep -qF 'Teardown commands' <<<"$noslug_out"; then
  fail "missing slug printed a teardown block (it must not)"
else
  pass "missing slug prints no teardown block"
fi

# --- 4. DPA-gate exits (rc 3) DO print teardown ------------------------------
# Bidirectional by construction: the fixture carries a `terminated` row that
# must NOT pass the gate, and an absent slug that also must not. Asserting only
# the passing direction would not detect a gate that accepts everything.
for blocked in fixture-revoked absent-slug; do
  gate_out="$(run_script "$blocked" --dry-run)"; gate_rc=$?
  if [[ "$gate_rc" -eq 3 ]]; then
    pass "DPA gate blocks '$blocked' with rc 3"
  else
    fail "DPA gate blocks '$blocked' with rc 3 (got $gate_rc)"
  fi
  if grep -qF 'Teardown commands' <<<"$gate_out"; then
    pass "DPA-gate exit for '$blocked' prints the teardown block"
  else
    fail "DPA-gate exit for '$blocked' lost its teardown block"
  fi
done

# The in-progress row must pass — a gate that accepted only `dpa-signed` would
# be a silent narrowing, and the one-row fixture could not see it.
inflight_out="$(run_script fixture-inflight --dry-run)"; inflight_rc=$?
if [[ "$inflight_rc" -eq 0 ]]; then
  pass "DPA gate admits a 'provisioning-in-progress' row"
else
  fail "DPA gate admits a 'provisioning-in-progress' row (got $inflight_rc)"
fi
if grep -qF "tenant-fixture-inflight-prd" <<<"$inflight_out"; then
  pass "slug is interpolated into the sub-project name"
else
  fail "slug is not interpolated into the sub-project name"
fi

# --- 5. No live-repo write (task 1.8) ---------------------------------------
if [[ -e "$SB/run/knowledge-base/legal/tenant-dpa-register.md" ]]; then
  pass "suite read its own fixture register, not the live one"
else
  fail "fixture register missing from the sandbox"
fi

# --- Anti-vacuity floor -----------------------------------------------------
# Reads and appends to the SAME two counters the verdict below reads.
ASSERT_TOTAL=$((PASS_COUNT + FAIL_COUNT))
FLOOR=16
if [[ "$ASSERT_TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: %s assertions ran, expected at least %s\n' "$ASSERT_TOTAL" "$FLOOR" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo "Total: $((PASS_COUNT + FAIL_COUNT)) assertions, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
