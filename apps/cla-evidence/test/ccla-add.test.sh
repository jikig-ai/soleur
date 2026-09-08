#!/usr/bin/env bash
# ccla-add.test.sh — registered EXPLICITLY in scripts/test-all.sh under
# `want_webplat`, not by a glob. It lives in apps/cla-evidence/test/ rather than
# beside the script it tests because apps/cla-evidence/scripts/ is a SUITE_GLOBS
# entry, and matching both that glob and an explicit registration is the
# double-coverage `lint-orphan-test-suites.sh` refuses. The shard is not a
# preference: this suite needs apps/web-platform/node_modules/.bin/tsx, which
# the `test-scripts` job does not install.
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
# The ledger lives on an orphan branch the upstream CLA action maintains, NOT in
# this checkout's history. `actions/checkout` is single-branch by default, so
# `origin/cla-signatures` is simply ABSENT in any job that has not asked for it
# — measured: `fatal: invalid object name 'origin/cla-signatures'`, the whole
# suite dead in 8 ms on CI run 34123093118.
#
# This is the SAME defect that was fixed in the vitest sibling
# (apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts) earlier in
# this PR, and it survived here because that suite ran in a job which happened
# to have the ref while this one did not run in CI at all. Fixing the symptom in
# one of two suites that share a dependency leaves the other armed.
#
# One shallow fetch of exactly this ref, then re-try. A genuine unavailability
# still ABORTS — "could not read the reference set" must never degrade to an
# empty ledger, which would pass every account.
if ! git show origin/cla-signatures:signatures/cla.json > "$WORK/ledger.json" 2>/dev/null; then
  # --no-tags is load-bearing, not tidiness: `git fetch` auto-follows tags, and the gate runner samples the repo's refs as a read-only boundary — a plain fetch wrote 157 tags and tripped [FATAL] A SUITE WROTE TO THE LIVE REPOSITORY on CI run 34123093118.
  # Measured: plain fetch creates tags, --no-tags creates none and still fetches the ref.
  git fetch --no-tags --depth=1 -q origin \
    '+refs/heads/cla-signatures:refs/remotes/origin/cla-signatures' 2>/dev/null
  git show origin/cla-signatures:signatures/cla.json > "$WORK/ledger.json" 2>/dev/null \
    || { echo "harness: could not read the ICLA ledger at origin/cla-signatures, even after a" >&2
         echo "         shallow fetch. That branch is maintained by the upstream CLA action;" >&2
         echo "         without it the reference set is unavailable and no verdict is possible." >&2
         exit 2; }
fi
[[ -s "$WORK/ledger.json" ]] || { echo "harness: ledger empty" >&2; exit 2; }
# The SUT resolves the roster validator through this binary. Without it EVERY
# invocation dies at ccla-add.sh's own operator-fault exit 2, and the suite
# reports ~23 assertion failures that all look like defects in the script —
# measured on CI run 34117976566, where this ran in the `test-scripts` shard,
# which installs no npm dependencies. Named here so the next occurrence says
# WHY in one line instead of as a wall of rc=2. Fail loud, never skip: the
# repo's convention for a missing dependency (see inspect.test.sh and jq).
[[ -x apps/web-platform/node_modules/.bin/tsx ]] || {
  echo "harness: apps/web-platform/node_modules/.bin/tsx is missing — this suite needs the" >&2
  echo "         web-platform toolchain and must run in the TEST_GROUP=webplat shard." >&2
  echo "         Locally: npm ci --prefix apps/web-platform" >&2
  exit 2
}
# Keep the REAL timestamps for the pre-notice arm below, then SYNTHESIZE the
# working fixture by rewriting `created_at` past the coverage-map notice epoch.
# The ids stay real because the id-keyed arms depend on them; only the temporal
# dimension is controlled, which is the one under test here
# (cq-test-fixtures-synthesized-only).
cp "$WORK/ledger.json" "$WORK/ledger-real-timestamps.json"
jq '.signedContributors |= map(.created_at = "2026-10-01T00:00:00Z")' \
  "$WORK/ledger-real-timestamps.json" > "$WORK/ledger.json" \
  || { echo "harness: could not synthesize the post-notice ledger" >&2; exit 2; }
jq -e '.signedContributors | length > 0 and all(.created_at == "2026-10-01T00:00:00Z")' \
  "$WORK/ledger.json" >/dev/null \
  || { echo "harness: synthesized ledger did not take" >&2; exit 2; }
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
grep -q 'no PR opened' "$WORK/err.txt" \
  && pass "dry run opens no PR" || fail "dry run did not report that it opened no PR"
# stdout is the emitted roster ALONE — a caller must be able to pipe it to jq
# without first stripping banners with sed.
jq -e . "$WORK/out.txt" >/dev/null 2>&1 \
  && pass "dry-run stdout is parseable JSON, diagnostics kept on stderr" \
  || fail "dry-run stdout is not parseable JSON — a diagnostic is interleaved with the roster"

# --- V4: the LOOSENING probe. The script's own security rationale is that the
# --- ledger is keyed on numeric id and never on login, "because a login can be
# --- renamed and reused, an id cannot". Every other fixture makes login, ledger
# --- name and id agree, so `select(.id == $id)` -> `select(.name == $l)` passed
# --- the whole suite. The tightening direction cannot see it either — the TS
# --- validator catches that case downstream and still returns 4. Only a renamed
# --- account whose ID IS SIGNED discriminates: it must be ACCEPTED.
rc=$(run_sut "$SCRIPT" '{"newhandle":54279}' add --record-ref CCLA-0007 --org "Renamed Ltd" \
  --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
  --instrument-sha256 "$SHA64" --login newhandle)
[[ "$rc" == "0" ]] && pass "renamed account whose id has signed is ACCEPTED (ledger is id-keyed)" \
  || fail "renamed-but-signed account rejected — the ledger lookup is keyed on login, not id (rc=$rc)"

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

# --- AP-025 / #7797: the xtrace self-refusal. This script binds a live
# --- credential (`gh auth`), and under `-x` bash echoes every expanded word.
# --- Asserted on BOTH the exit code and the refusal text, and paired with a
# --- must-PASS: a script that refused unconditionally would satisfy the
# --- negative arm alone while being completely broken.
out_x=$(bash -x "$SCRIPT" add --record-ref CCLA-0001 2>&1); rc=$?
[[ "$rc" == "78" ]] && pass "refuses to run under xtrace with the documented code (rc=78)" \
  || fail "xtrace refusal: expected rc=78, got $rc"
grep -q 'refusing to run under xtrace' <<<"$out_x" \
  && pass "the xtrace refusal names the hazard" || fail "xtrace refusal message missing"
# must-PASS: WITHOUT -x the same argv reaches the ordinary usage path, not 78.
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref CCLA-0001; true)
[[ "$rc" != "78" ]] && pass "without xtrace the refusal does NOT fire (it is state-gated, not unconditional)" \
  || fail "the script refuses even without -x — the guard is unconditional"

# --- The TEMPORAL half of contribution-triggered entry, on the write path.
# --- Membership is not the property the Art. 13 claim rests on; WHEN the
# --- signature was made is. Both accounts in the real ledger signed before the
# --- coverage-map notice existed, so the real timestamps are the fixture here.
rc=$(CCLA_ADD_DRY_RUN=1 CCLA_ADD_LEDGER="$WORK/ledger-real-timestamps.json" \
     CCLA_ADD_ROSTER="$WORK/roster.json" CCLA_ADD_ID_MAP='{"deruelle":54279}' \
     bash "$SCRIPT" "${add_args[@]}" --login deruelle > "$WORK/out.txt" 2> "$WORK/err.txt"; echo $?)
[[ "$rc" == "4" ]] && pass "an account that signed BEFORE the notice existed is refused on the write path" \
  || fail "pre-notice signer accepted by the write path (rc=$rc)"
grep -q 'coverage-map notice existed' "$WORK/err.txt" \
  && pass "the refusal names the TEMPORAL ground, not a missing signature" \
  || fail "pre-notice refusal does not name the notice epoch"
! grep -q 'have no Individual CLA signature' "$WORK/err.txt" \
  && pass "a pre-notice signer is NOT misreported as never having signed" \
  || fail "pre-notice signer misreported as unsigned"

# --- V12: rc=3 is a DOCUMENTED exit code in this script's header and appears
# --- nowhere in the suite. A mutation hardcoding the validator's passthrough to
# --- 2 ships green without it. Seed a roster the schema refuses.
printf '{\n  "schema_version": "2.0",\n  "organizations": []\n}\n' > "$WORK/roster.json"
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${add_args[@]}" --login deruelle)
[[ "$rc" == "3" ]] && pass "schema-invalid roster refused with the documented code (rc=3)" \
  || fail "schema-invalid roster: expected rc=3, got $rc"
grep -q 'roster record invalid' "$WORK/err.txt" \
  && pass "rc=3 refusal names schema validation, not the entry gate" \
  || fail "rc=3 refusal does not name schema validation"
printf '{\n  "schema_version": "1.0",\n  "organizations": []\n}\n' > "$WORK/roster.json"

# --- An UNPARSEABLE ledger must be reported as an unusable reference set, never
# --- as a finding about a person. "Could not measure" and "measured bad" are
# --- different verdicts and the second one sends the operator to ask a
# --- contributor to re-sign for no reason.
printf '<!DOCTYPE html><html>gateway error</html>' > "$WORK/garbage-ledger.json"
rc=$(CCLA_ADD_DRY_RUN=1 CCLA_ADD_LEDGER="$WORK/garbage-ledger.json" \
     CCLA_ADD_ROSTER="$WORK/roster.json" CCLA_ADD_ID_MAP='{"deruelle":54279}' \
     bash "$SCRIPT" "${add_args[@]}" --login deruelle > "$WORK/out.txt" 2> "$WORK/err.txt"; echo $?)
[[ "$rc" == "2" ]] && pass "unparseable ledger refused as an operator fault (rc=2)" \
  || fail "unparseable ledger: expected rc=2, got $rc"
grep -q 'UNUSABLE' "$WORK/err.txt" && ! grep -q 'have not signed' "$WORK/err.txt" \
  && pass "unparseable ledger is NOT reported as an unsigned contributor" \
  || fail "unparseable ledger reported as a finding about a person"

# A caller-supplied ledger must survive the script's own cleanup trap.
[[ -s "$WORK/ledger.json" ]] && pass "caller-supplied ledger not deleted by the cleanup trap" \
  || fail "cleanup trap deleted the caller's ledger"

# --- remove path (withdrawal of designation) --------------------------------
# --- V5: TWO representatives, not one. At cardinality 1 "stamped the designated
# --- account" and "stamped EVERY account" are the same observation, so
# --- `map(if .login == $login then .removed_at = $at else . end)` ->
# --- `map(.removed_at = $at)` passed the whole suite — silently withdrawing
# --- designation from every representative of the organisation, in a legal
# --- record.
run_sut "$SCRIPT" '{"deruelle":54279,"colleague":92384917}' "${add_args[@]}" \
  --login deruelle --login colleague >/dev/null
cp "$WORK/out.txt" "$WORK/populated.json"
if jq -e . "$WORK/populated.json" >/dev/null 2>&1; then
  cp "$WORK/populated.json" "$WORK/roster.json"
  rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' remove --record-ref CCLA-0001 --login deruelle \
    --withdrawn-at 2026-09-05T00:00:00Z)
  [[ "$rc" == "0" ]] && pass "remove path records a withdrawal (rc=0)" || fail "remove: expected rc=0, got $rc"
  jq -e --arg l deruelle '[.organizations[].representatives[] | select(.login == $l)]
        | length == 1 and .[0].removed_at == "2026-09-05T00:00:00Z"' "$WORK/out.txt" >/dev/null \
    && pass "withdrawal marker written to the designated account" \
    || fail "withdrawal marker not written"
  jq -e --arg l colleague '[.organizations[].representatives[] | select(.login == $l)]
        | length == 1 and .[0].removed_at == null' "$WORK/out.txt" >/dev/null \
    && pass "the OTHER representative of the same organisation is untouched" \
    || fail "withdrawal stamped a representative it was not asked to withdraw"
  # Capture the withdrawn roster HERE, while out.txt still holds it. The probes
  # below deliberately fail, and a failed run leaves out.txt empty — reading it
  # afterwards seeds every later arm with an unparseable roster and reports the
  # harness's own ordering bug as a defect in the SUT.
  cp "$WORK/out.txt" "$WORK/withdrawn.json"

  rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' remove --record-ref CCLA-9999 --login deruelle \
    --withdrawn-at 2026-09-05T00:00:00Z)
  [[ "$rc" != "0" ]] && pass "remove against an unknown record_ref fails" || fail "remove accepted an unknown record_ref"

  # A recorded withdrawal date is the legally operative one. Re-running `remove`
  # must NOT move it forward — the record of when a designation ended is the
  # thing this file exists to hold.
  cp "$WORK/withdrawn.json" "$WORK/roster.json"
  rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' remove --record-ref CCLA-0001 --login deruelle \
    --withdrawn-at 2026-09-30T00:00:00Z)
  [[ "$rc" == "2" ]] && pass "re-withdrawing an already-withdrawn account is refused (rc=2, not jq's own code)" \
    || fail "re-withdrawal accepted — the operative withdrawal date was rewritten"
  grep -q 'already withdrawn' "$WORK/err.txt" \
    && pass "re-withdrawal refusal names the date already on file" \
    || fail "re-withdrawal refusal does not say what is already recorded"

  # A live designation of the same id must not be appended a second time under a
  # different record_ref: two live rows make "who vouches for this contributor"
  # unanswerable from the record. A WITHDRAWN row must not block it — that is
  # how a person moves between employers.
  cp "$WORK/populated.json" "$WORK/roster.json"
  rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref CCLA-0055 --org "Second Employer SAS" \
    --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
    --instrument-sha256 "$SHA64" --login deruelle)
  [[ "$rc" == "2" ]] && pass "a second LIVE designation of the same id is refused (rc=2, not jq's own code)" \
    || fail "the same id was designated live under two organisations"
  cp "$WORK/withdrawn.json" "$WORK/roster.json"
  rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' add --record-ref CCLA-0055 --org "Second Employer SAS" \
    --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z \
    --instrument-sha256 "$SHA64" --login deruelle)
  [[ "$rc" == "0" ]] && pass "re-designation after a withdrawal is ACCEPTED (changing employer)" \
    || fail "a withdrawn designation blocked a legitimate re-designation (rc=$rc)"
  printf '{\n  "schema_version": "1.0",\n  "organizations": []\n}\n' > "$WORK/roster.json"
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


# ===========================================================================
# #7909 — `--instrument-file`: the instrument hash is COMPUTED, not typed.
#
# Guard 1 in the plan's `## Guard Contract`. Fixtures are synthesized
# (cq-test-fixtures-synthesized-only), and every one has its SHAPE asserted
# before use: a fixture that did not build the way it claims produces a
# confident verdict about the SUT that the HARNESS caused. Shape failures
# ABORT (exit 2) rather than fail(), because a half-built sandbox is not a
# finding about the script.
# ===========================================================================
printf 'executed corporate CLA instrument -- synthetic fixture A\n' > "$WORK/instrument.bin"
printf 'a different synthetic instrument, deliberately of another length entirely\n' > "$WORK/instrument2.bin"
: > "$WORK/empty.bin"
printf 'unreadable fixture\n' > "$WORK/unreadable.bin"
chmod 000 "$WORK/unreadable.bin"
mkdir -p "$WORK/adir"
ln -sf "$WORK/instrument.bin" "$WORK/link-outside.bin"
ln -sf "$REPO_ROOT/README.md" "$WORK/link-inside.bin"
printf 'org-named fixture\n' > "$WORK/Convergence SARL executed CCLA.pdf"
# GNU sha256sum PREFIXES its output line with a backslash when the filename
# contains a backslash or a newline, which shifts the awk fields and yields a
# hash that is not 64 hex. `sha256sum < "$f"` reads stdin and prints no
# filename, so it is immune. Without this fixture the argv-vs-stdin mutant
# passes every other arm here.
printf 'backslash-basename fixture\n' > "$WORK/back\\slash.bin"

ifs_abort() { printf 'harness: instrument fixture shape assertion failed: %s\n' "$1" >&2; exit 2; }
[[ -s "$WORK/instrument.bin" && -s "$WORK/instrument2.bin" ]] || ifs_abort "primary fixtures not both non-empty"
[[ "$(wc -c < "$WORK/instrument.bin")" -ne "$(wc -c < "$WORK/instrument2.bin")" ]] \
  || ifs_abort "the two fixtures must differ in LENGTH, not only in bytes"
[[ -f "$WORK/empty.bin" && ! -s "$WORK/empty.bin" ]] || ifs_abort "empty fixture is not a zero-byte regular file"
# A root EUID defeats the -r check, which would make the unreadable arm pass
# for a reason that has nothing to do with the SUT. Abort loudly instead.
[[ ! -r "$WORK/unreadable.bin" ]] || ifs_abort "chmod 000 fixture is still readable (running as root?)"
[[ -d "$WORK/adir" ]] || ifs_abort "directory fixture is not a directory"
[[ -L "$WORK/link-outside.bin" && -f "$WORK/link-outside.bin" ]] || ifs_abort "outside symlink fixture is not a symlink to a file"
[[ -L "$WORK/link-inside.bin" ]] || ifs_abort "inside symlink fixture is not a symlink"
[[ "$(realpath -e "$WORK/link-inside.bin")" == "$(realpath -e "$REPO_ROOT")"/* ]] \
  || ifs_abort "the inside-repo symlink does not resolve inside the repo root"
[[ -f "$WORK/back\\slash.bin" ]] || ifs_abort "backslash-basename fixture missing"
[[ "$WORK" != "$(realpath -e "$REPO_ROOT")"/* ]] || ifs_abort "the sandbox is inside the repo; the custody arms would be inverted"

# Shared head for the instrument arms. `add_args` at the top of this file is
# NOT mutated — it carries --instrument-sha256, and these arms need to control
# that dimension themselves.
if_head=(add --org "Instrument Ltd"
         --signed-at 2026-09-04T00:00:00Z --authorized-from 2026-09-04T00:00:00Z)

# --- FR1 + the AGREEMENT arm, in its non-vacuous form -----------------------
# Two identical FAILURES also emit two empty files and `cmp` passes, so rc==0
# on BOTH arms and parseability are preconditions, not decoration. (The form
# #7909 sketches -- `--instrument-sha256 $(sha256sum X)` -- expands to three
# argv words and exits 64; written that way the arm would assert nothing.)
if_digest=$(sha256sum < "$WORK/instrument.bin" | awk '{print $1}')
rc_file=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0100 \
  --instrument-file "$WORK/instrument.bin" --login deruelle)
cp "$WORK/out.txt" "$WORK/if-a.json"; cp "$WORK/err.txt" "$WORK/if-a.err"
rc_sha=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0100 \
  --instrument-sha256 "$if_digest" --login deruelle)
cp "$WORK/out.txt" "$WORK/if-b.json"; cp "$WORK/err.txt" "$WORK/if-b.err"
if [[ "$rc_file" == "0" && "$rc_sha" == "0" ]]; then
  pass "both instrument flags succeed (rc=0/rc=0) — the agreement arm is comparing two SUCCESSES"
else
  fail "agreement precondition: --instrument-file rc=$rc_file, --instrument-sha256 rc=$rc_sha (expected 0/0)"
fi
jq -e . "$WORK/if-a.json" >/dev/null 2>&1 \
  && pass "--instrument-file emits parseable JSON on stdout" \
  || fail "--instrument-file stdout is not parseable JSON"
cmp -s "$WORK/if-a.json" "$WORK/if-b.json" \
  && pass "--instrument-file and --instrument-sha256 emit a BYTE-IDENTICAL roster (FR1)" \
  || fail "the two instrument flags emit different rosters"
jq -e --arg d "$if_digest" '.organizations[0].executed_instrument_sha256 == $d' "$WORK/if-a.json" >/dev/null \
  && pass "the recorded hash equals sha256sum of the file's bytes (FR1, value arm)" \
  || fail "recorded executed_instrument_sha256 is not the fixture's digest"

# --- FR7: diagnostics on stderr, and the transcripts DIFFER -----------------
# A stderr line is what makes the operator's selection reviewable: the resolved
# path, the byte size and the mtime. `--instrument-file` closes TRANSCRIPTION
# error; it cannot close SELECTION error (hashing the wrong file perfectly), and
# a re-export differs in both size and mtime.
grep -q 'instrument file:' "$WORK/if-a.err" \
  && pass "--instrument-file echoes a diagnostic to stderr (FR7)" \
  || fail "no instrument diagnostic on stderr"
grep -q "$if_digest" "$WORK/if-a.err" \
  && pass "the stderr diagnostic carries the computed hash" \
  || fail "stderr diagnostic does not carry the computed hash"
grep -qE 'bytes=[0-9]+' "$WORK/if-a.err" \
  && pass "the stderr diagnostic carries the byte size (selection-error provenance)" \
  || fail "stderr diagnostic does not carry the byte size"
grep -q 'mtime=' "$WORK/if-a.err" \
  && pass "the stderr diagnostic carries the mtime (selection-error provenance)" \
  || fail "stderr diagnostic does not carry the mtime"
cmp -s "$WORK/if-a.err" "$WORK/if-b.err" \
  && fail "the two flags emit identical stderr — the instrument diagnostic is missing" \
  || pass "stderr transcripts DIFFER while stdout is identical (diagnostics stay off stdout)"

# FR7b: the PASTE-SAFE half. The runbook tells the operator to put provenance in
# the pull request; the diagnostic above cannot be that line, because the
# resolved path may itself BE a legal name and a PR body is public and
# permanent. So the script emits a second line carrying everything that makes
# provenance reviewable and nothing that identifies anyone -- and the absence of
# the path is the assertion, not a property of the line's wording.
_prov="$(grep '^provenance:' "$WORK/if-a.err" || true)"
[[ -n "$_prov" ]] \
  && pass "a paste-safe 'provenance:' line is emitted (the runbook promises one)" \
  || fail "no 'provenance:' line on stderr — the runbook tells the operator to paste one"
grep -q "$if_digest" <<<"$_prov" \
  && pass "the provenance line carries the computed hash" \
  || fail "the provenance line does not carry the computed hash"
grep -qE 'bytes=[0-9]+' <<<"$_prov" && grep -q 'mtime=' <<<"$_prov" \
  && pass "the provenance line carries size and mtime (a re-export differs in both)" \
  || fail "the provenance line is missing size or mtime — pasting it would prove nothing"
grep -qF "$WORK" <<<"$_prov" \
  && fail "the provenance line carries the resolved path — pasting it into a public PR is the leak this line exists to avoid" \
  || pass "the provenance line carries NO path (paste-safe)"

# --- FR2/FR3/FR4/FR5/FR6: the refusal arms, each with its OWN message -------
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0101 \
  --instrument-file "$WORK/instrument.bin" --instrument-sha256 "$SHA64" --login deruelle)
[[ "$rc" == "64" ]] && pass "both instrument flags together are refused (rc=64, FR2)" \
  || fail "both flags: expected rc=64, got $rc"
grep -q 'mutually exclusive' "$WORK/err.txt" \
  && pass "the both-flags refusal names the mutual exclusion" \
  || fail "both-flags refusal does not name the mutual exclusion"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0102 --login deruelle)
[[ "$rc" == "64" ]] && pass "neither instrument flag is refused (rc=64, FR3)" \
  || fail "neither flag: expected rc=64, got $rc"
grep -q -- '--instrument-file' "$WORK/err.txt" \
  && pass "the neither-flag refusal names BOTH flags, not only the older one" \
  || fail "neither-flag refusal does not mention --instrument-file"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0103 \
  --instrument-file "relative/instrument.bin" --login deruelle)
[[ "$rc" == "64" ]] && pass "a relative --instrument-file is refused (rc=64, FR4)" \
  || fail "relative path: expected rc=64, got $rc"
grep -q 'absolute path' "$WORK/err.txt" \
  && pass "the relative-path refusal says an absolute path is required" \
  || fail "relative-path refusal does not name the absolute-path requirement"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0104 \
  --instrument-file "$WORK/does-not-exist.bin" --login deruelle)
[[ "$rc" == "64" ]] && pass "a missing --instrument-file is refused (rc=64, FR5)" \
  || fail "missing file: expected rc=64, got $rc"
grep -q 'no such instrument file' "$WORK/err.txt" \
  && pass "the missing-file refusal names non-existence" \
  || fail "missing-file refusal does not name non-existence"

# `-f` ALONE reports a directory as "no such file" — the measured-bad-for-
# could-not-measure collapse this script exists to refuse. The `-e`/`-f` split
# is what makes these two messages distinct.
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0105 \
  --instrument-file "$WORK/adir" --login deruelle)
[[ "$rc" == "64" ]] && pass "a directory --instrument-file is refused (rc=64, FR5)" \
  || fail "directory: expected rc=64, got $rc"
grep -q 'not a regular file' "$WORK/err.txt" \
  && ! grep -q 'no such instrument file' "$WORK/err.txt" \
  && pass "a directory says 'not a regular file', NOT 'no such file' (the -e/-f split)" \
  || fail "the directory refusal collapses into the missing-file message"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0106 \
  --instrument-file "$WORK/empty.bin" --login deruelle)
[[ "$rc" == "64" ]] && pass "an empty --instrument-file is refused (rc=64, FR5)" \
  || fail "empty file: expected rc=64, got $rc"
grep -q 'evidences nothing' "$WORK/err.txt" \
  && pass "the empty-file refusal says an empty file evidences nothing" \
  || fail "empty-file refusal does not say why an empty file is refused"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0107 \
  --instrument-file "$WORK/unreadable.bin" --login deruelle)
[[ "$rc" == "64" ]] && pass "an unreadable --instrument-file is refused (rc=64, FR5)" \
  || fail "unreadable file: expected rc=64, got $rc"
grep -q 'not readable' "$WORK/err.txt" \
  && pass "the unreadable-file refusal names permission, not absence" \
  || fail "unreadable-file refusal does not name readability"

# FR6 — custody. A symlink OUTSIDE the repo is the supported shape; one whose
# TARGET resolves inside the repo is refused with rc=2, because the instrument
# is held off-repo on the encrypted operator drive (P10). This is a typo
# catcher, not a boundary: a bind mount, a hardlink or a sibling worktree
# defeats any path comparison.
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0108 \
  --instrument-file "$WORK/link-outside.bin" --login deruelle)
[[ "$rc" == "0" ]] && pass "a symlink to a file OUTSIDE the repo is accepted (rc=0)" \
  || fail "outside symlink: expected rc=0, got $rc"

rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0109 \
  --instrument-file "$WORK/link-inside.bin" --login deruelle)
[[ "$rc" == "2" ]] && pass "a symlink RESOLVING inside the repo is refused on custody grounds (rc=2, FR6)" \
  || fail "inside symlink: expected rc=2, got $rc"
grep -q 'off-repo' "$WORK/err.txt" \
  && pass "the custody refusal names off-repo custody" \
  || fail "custody refusal does not name off-repo custody"

# --- the sha256sum argv-vs-stdin hazard -------------------------------------
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0110 \
  --instrument-file "$WORK/back\\slash.bin" --login deruelle)
back_digest=$(sha256sum < "$WORK/back\\slash.bin" | awk '{print $1}')
if [[ "$rc" == "0" ]] && jq -e --arg d "$back_digest" \
     '.organizations[0].executed_instrument_sha256 == $d' "$WORK/out.txt" >/dev/null 2>&1; then
  pass "a backslash in the basename still yields the right hash (sha256sum reads STDIN, not argv)"
else
  fail "backslash basename: rc=$rc and/or the recorded hash is wrong — sha256sum is being passed the path as argv"
fi

# --- FR8: the resolved path reaches no published artifact -------------------
# The instrument's filename plausibly carries a legal name, which is exactly
# what --sole-trader exists to keep off-repo. The RUNTIME paths (the commit
# heredoc, the PR body) are unreachable under this suite's unconditional
# CCLA_ADD_DRY_RUN=1, so this is asserted at SOURCE level over the two spans —
# each with a KNOWN-POSITIVE control first, because an awk range that matched
# nothing would satisfy the absence grep vacuously.
# The start anchor deliberately STOPS before the heredoc operator, and this
# comment deliberately does not quote it either.
#
# `guard-vacuity-floor.test.sh` finds this suite's assertion floor by scanning
# for an `if` line, having first excluded every line it scores as heredoc BODY.
# Its heredoc scanner is textual and state-machine-based: any line carrying the
# redirect operator followed by a tag OPENS a region, and only a line holding
# that bare tag closes it. So a pattern -- or a comment -- that merely NAMES the
# tag used by the commit message below opens a region that never closes, every
# line to EOF is scored as body, this file drops out of the floor-bearing set,
# and its floor silently stops being mutation-tested while the suite stays
# green. Measured twice: once from the awk pattern, then again from the comment
# written to explain the first one. Anchor on `^git commit --quiet --file`
# instead, and describe the hazard without spelling it.
# Two literal identifiers is a claim about NAMES, and the script owns the names.
# Aliasing the value into a third variable -- `PROVENANCE_NOTE=$RESOLVED_INSTRUMENT`
# -- puts the path in the PR body with every arm green. So derive the forbidden
# set instead: seed it with the two the argument arrives in, then close it under
# assignment until it stops growing. Any variable assigned from a tainted one is
# tainted, however it is spelled.
fr8_taint_re() {
  local file="$1" re='INSTRUMENT_FILE|RESOLVED_INSTRUMENT' line lhs rhs added round
  for round in 1 2 3 4 5 6 7 8; do
    added=""
    while IFS= read -r line; do
      lhs="${line%%=*}"; lhs="${lhs##*[[:space:]]}"
      [[ "$lhs" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      rhs="${line#*=}"
      grep -qE "$re" <<<"$rhs" || continue
      grep -qE "(^|\|)${lhs}(\||\$)" <<<"$re" && continue
      re="$re|$lhs"; added=1
    done <<<"$(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$file")"
    [[ -n "$added" ]] || break
  done
  printf '%s' "$re"
}

# INSTRUMENT SELF-TEST for the extractor, before anything relies on it. A
# fixpoint that silently found nothing would make all three absence checks below
# pass for the wrong reason, and the alias is exactly what they exist to catch.
fr8_probe="$WORK/fr8-taint-probe.sh"
printf '%s\n' 'PROVENANCE_NOTE="$RESOLVED_INSTRUMENT"' 'SECOND_HOP="$PROVENANCE_NOTE"' > "$fr8_probe"
fr8_probe_re="$(fr8_taint_re "$fr8_probe")"
grep -qE '(^|\|)PROVENANCE_NOTE(\||$)' <<<"$fr8_probe_re" \
  && pass "FR8 instrument: the taint fixpoint follows a one-hop alias" \
  || fail "FR8 instrument: the taint fixpoint missed a one-hop alias — every FR8 absence check below is vacuous"
grep -qE '(^|\|)SECOND_HOP(\||$)' <<<"$fr8_probe_re" \
  && pass "FR8 instrument: the taint fixpoint follows a two-hop alias (it iterates, it does not scan once)" \
  || fail "FR8 instrument: the taint fixpoint stopped after one hop"

FR8_TAINT="$(fr8_taint_re "$SCRIPT")"

if_commit_span=$(awk '/^git commit --quiet --file/,/^COMMITEOF$/' "$SCRIPT")
if_prbody_span=$(awk '/^if ! gh pr create --repo/,/^Ref #3210\."; then$/' "$SCRIPT")
# The THIRD publishing site, and the one no span covered: the branch name is
# pushed to a public remote and becomes the PR's head ref, so it is as published
# as the body. Appending a basename here leaked the path with 96/96 green.
if_branch_span=$(grep -E '^BRANCH=' "$SCRIPT")
grep -q 'RECORD_REF' <<<"$if_commit_span" \
  && pass "FR8 control: the commit-heredoc span was actually extracted (it carries RECORD_REF)" \
  || fail "FR8 control: the commit-heredoc awk range extracted nothing — the absence check below would be vacuous"
grep -q 'LOGINS' <<<"$if_prbody_span" \
  && pass "FR8 control: the PR-body span was actually extracted (it carries LOGINS)" \
  || fail "FR8 control: the PR-body awk range extracted nothing — the absence check below would be vacuous"
grep -q 'RECORD_REF' <<<"$if_branch_span" \
  && pass "FR8 control: the branch-name span was actually extracted (it carries RECORD_REF)" \
  || fail "FR8 control: the branch-name grep matched nothing — the absence check below would be vacuous"
if grep -qE "$FR8_TAINT" <<<"$if_commit_span"; then
  fail "FR8: the instrument path reaches the commit message"
else
  pass "FR8: the instrument path reaches no commit message"
fi
if grep -qE "$FR8_TAINT" <<<"$if_prbody_span"; then
  fail "FR8: the instrument path reaches the PR body"
else
  pass "FR8: the instrument path reaches no PR body"
fi
if grep -qE "$FR8_TAINT" <<<"$if_branch_span"; then
  fail "FR8: the instrument path reaches the pushed branch name"
else
  pass "FR8: the instrument path reaches no pushed branch name"
fi

# --- the organisation-named fixture leaks nothing (Guard 1 H4, must-PASS) ---
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0111 \
  --instrument-file "$WORK/Convergence SARL executed CCLA.pdf" --login deruelle)
if [[ "$rc" == "0" ]] && ! grep -q 'Convergence SARL executed' "$WORK/out.txt"; then
  pass "an organisation-named instrument basename never reaches the roster or stdout"
else
  fail "organisation-named fixture: rc=$rc, or the basename leaked into stdout"
fi

# --- NFR3: the resolved path never joins the cleanup array ------------------
[[ -s "$WORK/instrument.bin" ]] \
  && pass "the caller's instrument file survives the script's cleanup trap (NFR3)" \
  || fail "the cleanup trap deleted the caller's instrument file"

# --- FR10: usage() documents the new flag -----------------------------------
if_usage=$(bash "$SCRIPT" 2>&1 || true)
grep -q -- '--instrument-file' <<<"$if_usage" \
  && pass "usage() documents --instrument-file (FR10)" \
  || fail "usage() does not document --instrument-file"


# ===========================================================================
# Guard 1 MUTATION MATRIX — rows 1-9.
#
# Every row copies the SUT, edits the copy, and ASSERTS THE MUTATION LANDED
# before asserting its effect: a mutation that did not apply reports the
# BASELINE, which is byte-for-byte indistinguishable from a pass.
#
# Rows 8 and 9 are additions to the plan's matrix, from the deepen-plan
# test-design pass: no listed row covered the sha256sum argv-vs-stdin hazard
# the design devotes a paragraph to, and none covered mutual exclusion.
# ===========================================================================
G1MUT="$WORK/ccla-add.g1.sh"
g1_begin() { cp "$SCRIPT" "$G1MUT" || { echo "harness: could not copy the SUT" >&2; exit 2; }; }
g1_landed() {
  if diff -q "$SCRIPT" "$G1MUT" >/dev/null; then
    fail "$1: the mutation did NOT land (mutant is byte-identical to the SUT) — its verdict below would be the baseline"
    return 1
  fi
  pass "$1: mutation landed"
  return 0
}

# --- Row 1: replace the computed digest with a constant ---------------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'INSTRUMENT_SHA="$(sha256sum < "$RESOLVED_INSTRUMENT" | awk'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, 'INSTRUMENT_SHA="$(printf %s\\\\n ' + 'd' * 64 + ' | awk')
open(p, "w").write(s)
PY
if g1_landed "G1-M1 (constant digest)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0120 \
    --instrument-file "$WORK/instrument.bin" --login deruelle)
  if [[ "$rc" == "0" ]] && jq -e --arg d "$if_digest" \
       '.organizations[0].executed_instrument_sha256 == $d' "$WORK/out.txt" >/dev/null 2>&1; then
    fail "G1-M1: a constant digest still produced the file's real hash — the value arm cannot see it"
  else
    pass "G1-M1: replacing the computed digest with a constant is caught by the value arm"
  fi
fi

# --- Row 2: delete the -s non-empty check -----------------------------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
m = re.search(r'    \[\[ -s "\$RESOLVED_INSTRUMENT" \]\] \\\n      \|\| die [^\n]*\n', s)
assert m, "the -s check was not found in its expected shape"
s = s[:m.start()] + s[m.end():]
open(p, "w").write(s)
PY
if g1_landed "G1-M2 (no -s empty check)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0121 \
    --instrument-file "$WORK/empty.bin" --login deruelle)
  [[ "$rc" == "64" ]] \
    && fail "G1-M2: the empty file was still refused with 64 — the -s check is not what refuses it" \
    || pass "G1-M2: deleting the -s check lets a zero-byte instrument through (rc=$rc) — the arm is load-bearing"
fi

# --- Row 3: collapse the -e / -f split back to -f alone ---------------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
m = re.search(r'    \[\[ -e "\$INSTRUMENT_FILE" \]\] \\\n      \|\| die "no such instrument file[^\n]*\n', s)
assert m, "the -e check was not found in its expected shape"
s = s[:m.start()] + s[m.end():]
old = 'die "not a regular file: $INSTRUMENT_FILE'
assert s.count(old) == 1
s = s.replace(old, 'die "no such instrument file: $INSTRUMENT_FILE')
open(p, "w").write(s)
PY
if g1_landed "G1-M3 (collapsed -e/-f)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0122 \
    --instrument-file "$WORK/adir" --login deruelle)
  if grep -q 'no such instrument file' "$WORK/err.txt"; then
    pass "G1-M3: collapsing the split makes a DIRECTORY report as 'no such file' — the arm catches it"
  else
    fail "G1-M3: the collapsed mutant still distinguished a directory — the two messages are not what the arm reads"
  fi
fi

# --- Row 4: the guard's OWN DISPATCH — make the compute block unreachable ---
g1_begin
python3 - "$G1MUT" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  if [[ -n "$INSTRUMENT_FILE" ]]; then\n'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, '  if false; then\n')
open(p, "w").write(s)
PY
if g1_landed "G1-M4 (compute block unreachable)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0123 \
    --instrument-file "$WORK/instrument.bin" --login deruelle)
  [[ "$rc" == "0" ]] \
    && fail "G1-M4: an unreachable compute block still produced a roster — the happy-path arm is vacuous" \
    || pass "G1-M4: an unreachable compute block is caught at the 64-hex chokepoint (rc=$rc)"
fi

# --- Row 5: accept a relative path (drop the /* check) ----------------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
m = re.search(r'    \[\[ "\$INSTRUMENT_FILE" = /\* \]\] \\\n      \|\| die "--instrument-file must be an absolute path[^\n]*\n', s)
assert m, "the absolute-path check was not found in its expected shape"
s = s[:m.start()] + s[m.end():]
open(p, "w").write(s)
PY
if g1_landed "G1-M5 (relative paths accepted)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0124 \
    --instrument-file "relative/instrument.bin" --login deruelle)
  grep -q 'absolute path' "$WORK/err.txt" \
    && fail "G1-M5: the mutant still named the absolute-path requirement — the check was not removed" \
    || pass "G1-M5: dropping the /* check loses the absolute-path refusal (rc=$rc) — the arm is load-bearing"
fi

# --- Row 6: custody compared WITHOUT realpath -------------------------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '    case "$RESOLVED_INSTRUMENT" in\n'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, '    case "$INSTRUMENT_FILE" in\n')
open(p, "w").write(s)
PY
if g1_landed "G1-M6 (custody without realpath)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0125 \
    --instrument-file "$WORK/link-inside.bin" --login deruelle)
  [[ "$rc" == "2" ]] \
    && fail "G1-M6: the unresolved comparison still refused the symlink — realpath is not what catches it" \
    || pass "G1-M6: comparing the ARGUMENT instead of the resolved path lets a symlink into the repo through (rc=$rc)"
fi

# --- Row 7: interpolate the resolved path into the PR body ------------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'Accounts: ${LOGINS[*]}'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, 'Accounts: ${LOGINS[*]} (instrument: ${RESOLVED_INSTRUMENT})')
open(p, "w").write(s)
PY
if g1_landed "G1-M7 (path interpolated into the PR body)"; then
  g1_span=$(awk '/^if ! gh pr create --repo/,/^Ref #3210\."; then$/' "$G1MUT")
  grep -q 'LOGINS' <<<"$g1_span" \
    && pass "G1-M7 control: the mutant's PR-body span was extracted" \
    || fail "G1-M7 control: the mutant's PR-body span is empty — the row below is vacuous"
  grep -qE 'INSTRUMENT_FILE|RESOLVED_INSTRUMENT' <<<"$g1_span" \
    && pass "G1-M7: a path interpolated into the PR body IS caught by the source-level span assertion" \
    || fail "G1-M7: the span assertion did not see the interpolated path — FR8 is vacuous"
fi

# --- Row 8: sha256sum given the path as ARGV instead of on stdin ------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'sha256sum < "$RESOLVED_INSTRUMENT"'
assert s.count(old) == 1, s.count(old)
s = s.replace(old, 'sha256sum "$RESOLVED_INSTRUMENT"')
open(p, "w").write(s)
PY
if g1_landed "G1-M8 (sha256sum argv, not stdin)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0126 \
    --instrument-file "$WORK/back\\slash.bin" --login deruelle)
  [[ "$rc" == "0" ]] \
    && fail "G1-M8: the argv form still produced a valid hash for a backslash basename — the fixture does not discriminate" \
    || pass "G1-M8: the argv form is caught on a backslash basename (rc=$rc) — the stdin form is load-bearing"
  # ...and the mutant must still be FINE on an ordinary basename, or the row
  # would redden for a reason that has nothing to do with the hazard.
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0127 \
    --instrument-file "$WORK/instrument.bin" --login deruelle)
  [[ "$rc" == "0" ]] \
    && pass "G1-M8 control: the argv form is harmless on an ordinary basename — the row isolates the backslash hazard" \
    || fail "G1-M8 control: the argv mutant failed on an ordinary basename too (rc=$rc) — the row proves nothing specific"
fi

# --- Row 9: remove the mutual exclusion -------------------------------------
g1_begin
python3 - "$G1MUT" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
m = re.search(r'  if \[\[ -n "\$INSTRUMENT_FILE" && -n "\$INSTRUMENT_SHA" \]\]; then\n.*?\n  fi\n', s, re.S)
assert m, "the mutual-exclusion block was not found in its expected shape"
s = s[:m.start()] + s[m.end():]
open(p, "w").write(s)
PY
if g1_landed "G1-M9 (no mutual exclusion)"; then
  rc=$(run_sut "$G1MUT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0128 \
    --instrument-file "$WORK/instrument.bin" --instrument-sha256 "$SHA64" --login deruelle)
  [[ "$rc" == "64" ]] \
    && fail "G1-M9: both flags were still refused — the mutual-exclusion block is not what refuses them" \
    || pass "G1-M9: removing mutual exclusion silently lets one flag win (rc=$rc) — the arm is load-bearing"
fi

# --- H3 (must-PASS, non-canonical): a SECOND fixture, different bytes AND ----
# --- length. A one-fixture guard cannot distinguish "hashes this file" from
# --- "emits a constant that happens to equal this file's hash".
if_digest2=$(sha256sum < "$WORK/instrument2.bin" | awk '{print $1}')
rc=$(run_sut "$SCRIPT" '{"deruelle":54279}' "${if_head[@]}" --record-ref CCLA-0129 \
  --instrument-file "$WORK/instrument2.bin" --login deruelle)
if [[ "$rc" == "0" ]] && jq -e --arg d "$if_digest2" \
     '.organizations[0].executed_instrument_sha256 == $d' "$WORK/out.txt" >/dev/null 2>&1; then
  pass "H3 must-PASS: a second fixture of different bytes AND length hashes correctly too"
else
  fail "H3: the second fixture did not hash correctly (rc=$rc)"
fi
[[ "$if_digest" != "$if_digest2" ]] \
  && pass "H3 control: the two fixtures have DIFFERENT digests, so the arm above discriminates" \
  || fail "H3 control: both fixtures hash identically — the must-PASS proves nothing"

# ---------------------------------------------------------------------------
echo "---"
echo "Total: $passes passed, $fails failed"
# Assertion floor, reported with printf + exit rather than through fail(),
# which is the helper it exists to backstop.
# TIGHT, not a lower bound with slack. At 22 against 23 actual assertions, one
# assertion could be deleted and the run stayed green and silent — the floor
# only fires when TWO go. `guard-vacuity-floor.test.sh` verifies that floors
# FIRE, never that they are tight, so nothing else catches the slack.
MIN_ASSERTIONS=104
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY: only %s assertions ran, expected at least %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
exit 0
