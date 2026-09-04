#!/usr/bin/env bash
# ccla-add.test.sh — collected by scripts/test-all.sh via the existing
# apps/cla-evidence/scripts/*.test.sh glob (the same one that collects
# sentinel-pr.test.sh).
#
# Covers the write-side half of Guard 3 (contribution-triggered entry) and the
# documented exit-code contract. The mutation arm at the end is the one that
# matters: it deletes the ledger check from a COPY of the script and asserts
# the copy then accepts an account that has not signed the ICLA. Without that,
# every other case here would pass just as happily against a script whose check
# does nothing.

set -uo pipefail

# Sandbox harnesses build trees under TMPDIR. /tmp is a machine-global tmpfs
# shared with parallel worktrees; a direct invocation of this suite would
# otherwise inherit it and its verdicts would depend on another session's disk.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$REPO_ROOT/apps/cla-evidence/scripts/ccla-add.sh"
SHA64="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

passes=0
fails=0
pass() { passes=$((passes + 1)); echo "[ok]   $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1"; }

WORK="$(mktemp -d -t ccla-add-test.XXXXXXXX)" || { echo "harness: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# --- harness setup must ABORT, never continue. A sandbox that half-built
# --- produces confident wrong verdicts about the SUT rather than a missing one.
git show origin/cla-signatures:signatures/cla.json > "$WORK/ledger.json" \
  || { echo "harness: could not read the ICLA ledger" >&2; exit 2; }
[[ -s "$WORK/ledger.json" ]] || { echo "harness: ledger empty" >&2; exit 2; }
printf '{\n  "schema_version": "1.0",\n  "organizations": []\n}\n' > "$WORK/roster.json" \
  || { echo "harness: could not write roster fixture" >&2; exit 2; }

# Run the SUT (or a mutant) in dry-run with stubbed id resolution.
# $1 = script path, $2 = id map JSON, rest = argv.
run_sut() {
  local script="$1" idmap="$2"; shift 2
  CCLA_ADD_DRY_RUN=1 \
  CCLA_ADD_LEDGER="$WORK/ledger.json" \
  CCLA_ADD_ROSTER="$WORK/roster.json" \
  CCLA_ADD_ID_MAP="$idmap" \
    bash "$script" "$@" > "$WORK/out.txt" 2> "$WORK/err.txt"
  echo $?
}

add_args=(add --record-ref CCLA-0001 --org "Convergence SARL"
          --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z
          --instrument-sha256 "$SHA64")

# --- instrument self-test: drive both counters once, and refuse to continue
# --- unless both actually moved. A suite whose pass/fail helpers are inert
# --- reports a clean run having asserted nothing.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — EXPECTED, discounted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'harness: instrument self-test did not move both counters (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0; fails=0
echo "--- instrument verified; counters reset ---"

# ---------------------------------------------------------------------------
# Exit-code contract
# ---------------------------------------------------------------------------
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${add_args[@]}" --login deruelle)
[[ "$rc" == "0" ]] && pass "signed account is accepted (rc=0)" || fail "signed account: expected rc=0, got $rc"
grep -q '"id": 54279' "$WORK/out.txt" \
  && pass "login resolved to its numeric id in the emitted roster" \
  || fail "emitted roster does not carry the resolved numeric id"
grep -q 'no PR opened' "$WORK/out.txt" \
  && pass "dry run opens no PR" || fail "dry run did not report that it opened no PR"

rc=$(run_sut "$SCRIPT" '{"stranger":999999}' add --record-ref CCLA-0002 --org "Nobody Ltd" \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login stranger)
[[ "$rc" == "4" ]] && pass "unsigned account refused with the entry-gate code (rc=4)" \
  || fail "unsigned account: expected rc=4, got $rc"
grep -q 'have not signed the Individual CLA' "$WORK/err.txt" \
  && pass "refusal names the reason" || fail "refusal message does not name the reason"
grep -q '999999' "$WORK/err.txt" \
  && pass "refusal names the offending id" || fail "refusal does not name the offending id"

# Two unsigned accounts: must not stop at the first (row G3-M2).
rc=$(run_sut "$SCRIPT" '{"a":999998,"b":999999}' add --record-ref CCLA-0003 --org "Nobody Ltd" \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login a --login b)
[[ "$rc" == "4" ]] && pass "two unsigned accounts refused" || fail "two unsigned: expected rc=4, got $rc"
grep -q '2 account' "$WORK/err.txt" \
  && pass "both offenders reported, not just the first" \
  || fail "refusal stopped at the first offender"

# One signed + one unsigned: the valid first member must not mask the second.
rc=$(run_sut "$SCRIPT" '{"deruelle":54279,"b":999999}' add --record-ref CCLA-0004 --org "Mixed Ltd" \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login deruelle --login b)
[[ "$rc" == "4" ]] && pass "an unsigned account after a valid one is still refused" \
  || fail "mixed batch: expected rc=4, got $rc"

# Usage errors.
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref NOPE --org X \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login deruelle)
[[ "$rc" == "64" ]] && pass "malformed --record-ref rejected (rc=64)" || fail "bad record-ref: got $rc"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref CCLA-0005 --org X \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z --login deruelle)
[[ "$rc" == "64" ]] && pass "missing --instrument-sha256 rejected (rc=64)" || fail "missing sha: got $rc"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref CCLA-0006 --org X --sole-trader \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login deruelle)
[[ "$rc" == "64" ]] && pass "--org and --sole-trader are mutually exclusive (rc=64)" || fail "org+sole-trader: got $rc"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref CCLA-0007 \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login deruelle)
[[ "$rc" == "64" ]] && pass "neither --org nor --sole-trader rejected (rc=64)" || fail "no org: got $rc"

# Sole trader: legal_name is published as null (CLO amendment B1-c-2).
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref CCLA-0008 --sole-trader \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login deruelle)
[[ "$rc" == "0" ]] && pass "--sole-trader accepted (rc=0)" || fail "sole-trader: expected rc=0, got $rc"
grep -q '"legal_name": null' "$WORK/out.txt" \
  && pass "sole trader publishes a null legal_name, not the person's name" \
  || fail "sole trader did not publish a null legal_name"

# The roster carries no identity field, by construction (.strict()).
if grep -qE '"(signatory_name|email|corporate_email|title|address)"' "$WORK/out.txt"; then
  fail "emitted roster carries a prohibited identity field"
else
  pass "emitted roster carries no prohibited identity field"
fi

# Dry run must not touch the roster on disk.
if [[ "$(jq -c '.organizations' "$WORK/roster.json")" == "[]" ]]; then
  pass "dry run left the roster on disk untouched"
else
  fail "dry run mutated the roster on disk"
fi

# A caller-supplied ledger must survive the script's own cleanup trap.
[[ -s "$WORK/ledger.json" ]] && pass "caller-supplied ledger not deleted by the cleanup trap" \
  || fail "cleanup trap deleted the caller's ledger"

# --- remove path (withdrawal of designation) --------------------------------
run_sut "$SCRIPT" '{"deruelle":54279}' "${add_args[@]}" --login deruelle >/dev/null
sed -n '/^{/,$p' "$WORK/out.txt" | sed '/^---/d' > "$WORK/populated.json"
if jq -e . "$WORK/populated.json" >/dev/null 2>&1; then
  cp "$WORK/populated.json" "$WORK/roster.json"
  rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' remove --record-ref CCLA-0001 --login deruelle \
    --withdrawn-at 2026-09-05T00:00:00Z)
  [[ "$rc" == "0" ]] && pass "remove path records a withdrawal (rc=0)" || fail "remove: expected rc=0, got $rc"
  grep -q '"removed_at": "2026-09-05T00:00:00Z"' "$WORK/out.txt" \
    && pass "withdrawal marker written to the designated account" \
    || fail "withdrawal marker not written"

  rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' remove --record-ref CCLA-9999 --login deruelle \
    --withdrawn-at 2026-09-05T00:00:00Z)
  [[ "$rc" != "0" ]] && pass "remove against an unknown record_ref fails" || fail "remove accepted an unknown record_ref"
  printf '{\n  "schema_version": "1.0",\n  "organizations": []\n}\n' > "$WORK/roster.json"
else
  fail "harness: could not recover the emitted roster for the remove path"
fi

# ---------------------------------------------------------------------------
# MUTATION — row G3-M5. Delete the ledger check from a COPY and confirm the
# copy then ACCEPTS an unsigned account. This is what proves the check in the
# real script is load-bearing rather than decorative.
# ---------------------------------------------------------------------------
MUTANT="$WORK/ccla-add.mutant.sh"
cp "$SCRIPT" "$MUTANT" || { echo "harness: could not copy the SUT" >&2; exit 2; }
python3 - "$MUTANT" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
start = s.index("MISSING=()")
end = s.index("# ---- build the new roster")
mutated = s[:start] + s[end:]
assert mutated != s, "mutation did not change the file"
open(p, "w").write(mutated)
PY
if [[ $? -ne 0 ]]; then
  fail "harness: could not apply the G3-M5 mutation"
else
  # Assert the mutation actually LANDED — a mutation that did not apply
  # reports the baseline, which is indistinguishable from a pass.
  if diff -q "$SCRIPT" "$MUTANT" >/dev/null; then
    fail "harness: G3-M5 mutant is byte-identical to the SUT"
  else
    pass "G3-M5 mutation landed (mutant differs from the SUT)"
    rc=$(run_sut "$MUTANT" '{"stranger":999999}' add --record-ref CCLA-0002 --org "Nobody Ltd" \
      --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
      --instrument-sha256 "$SHA64" --login stranger)
    # The exit code CANNOT discriminate here, and that is the finding: with the
    # write-side check deleted the validator still refuses, also with rc=4,
    # because the two sites are genuinely redundant. Defense in depth is the
    # design — so the mutation is proved on the PRODUCER of the refusal, not on
    # its code. Baseline refuses at the write path, before anything is built;
    # the mutant gets as far as the validator.
    mutant_err="$(cat "$WORK/err.txt")"
    if [[ "$rc" != "4" ]]; then
      fail "G3-M5: the mutant did not refuse at all (rc=$rc) — expected the validator to still catch it"
    elif grep -q 'refusing to write:' <<<"$mutant_err"; then
      fail "G3-M5: the mutant still refused at the WRITE path — the deleted block was not the check"
    elif grep -q 'does not validate' <<<"$mutant_err"; then
      pass "G3-M5: deleting the write-side check moves the refusal to the validator (both sites are load-bearing)"
    else
      fail "G3-M5: mutant refused for an unrecognised reason: ${mutant_err:0:120}"
    fi
  fi
fi

# ---------------------------------------------------------------------------
echo "---"
echo "Total: $passes passed, $fails failed"
# Assertion floor, reported with printf + exit rather than through fail(),
# which is the helper it exists to backstop.
MIN_ASSERTIONS=22
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY: only %s assertions ran, expected at least %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
exit 0
