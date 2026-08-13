#!/usr/bin/env bash
# Run all .github/scripts/ fixture tests sequentially. EVERY suite runs; the exit code is
# decided once, after the loop. Run from repo root via `bash .github/scripts/test/run-all.sh`.
#
# CONTRACT (#6454): the `test-*.sh` glob below feeds `guard-script-fixture-tests`,
# which is a REQUIRED check, runs on `merge_group`, and has NO path filter — so it
# gates every PR in the repo. Suites here must therefore be BASH-ONLY: no terraform,
# no cloud-init, no apt. A suite needing external tooling would either red every PR
# (the tool is absent on that bare runner) or put a package-mirror dependency on the
# merge-queue critical path for docs-only PRs.
#
# That is why `fixtures-validate-infra-templates.sh` sits in this directory but is
# deliberately NOT named `test-*`: it needs terraform + cloud-init, so it runs from
# the `deploy-script-tests` job in infra-validation.yml, which installs both. Do not
# rename it back into this glob.
#
# EXIT CONTRACT (#7429, ADR-187) — this is a NESTED runner. scripts/test-all.sh registers it
# via `run_suite`, so whatever rc leaves this file is what `run_suite` classifies:
#
#   0       every suite passed
#   1       at least one suite FAILED an assertion, or the MIN_SUITES floor fired
#   128+N   nothing failed, and at least one suite died signal-shaped (rc 128+N carrying a
#           decodable signal name) — `run_suite` then renders `[KILLED]` and test-all.sh
#           exits 3
#
# The body used to be `if ! bash "$t"; then FAIL=1; fi` — a BOOLEAN test, which collapsed 143
# (SIGTERM) and 1 (one failed assertion) into the same flat 1. A terminated fixture suite then
# rendered `[FAIL]` at the top level: the most alarming available reading, and a false one.
# ADR-177 is the taxonomy; ADR-187 adds that a nested runner signals UNRESOLVED by exit SHAPE,
# and only from an rc it DIRECTLY OBSERVED. This runner invokes each suite as `bash "$t"` with
# nothing in between, so the child's rc IS the observation — it never has to infer one, and it
# must never synthesize one from a wall-clock guess or a log scrape.
#
# The value 3 is deliberately never emitted from this file: 3 is a
# TOP-LEVEL contract owned by scripts/test-all.sh (ADR-177 §Consequences), and a nested runner
# emitting it would be indistinguishable from a suite that legitimately returned 3.
#
# PRECEDENCE IS FIXED, AND FAILURE DOMINATES: floor > failed > killed > ok. The MIN_SUITES
# floor is evaluated FIRST and stays dominant — a run that is both short and signal-shaped is
# reported as a short run, because the floor says the SET was wrong while the shape says only
# that one member died.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
FAIL=0
RAN=0
KILLED=0
# One "<basename>|<rc>" record per signal-shaped suite. An array, not a single slot, because
# the loop must not stop at the first kill and the SELECTION RULE below needs the whole set.
KILLED_RECORD=()

# INLINED VERBATIM from scripts/test-all.sh, byte-for-byte, and pinned as such by
# test-run-all-signal-propagation.sh — the three copies of this classifier cannot drift
# silently. It is NOT sourced from a shared lib: ADR-177 §A3 makes this fatal to SHARE, but not for the reason first recorded: the binding
# constraint is that run-registered-suites.test.sh drives a python SINGLE-FILE mutator over the
# copy, so the two rows that mutate the classifier BODY (drop-rc128-guard, drop-name-guard)
# could not be applied at all if it lived elsewhere. (The original reason — "a sourced lib
# would be absent from the copy" — does not follow: the runner cd's to $ROOT first, so a
# $ROOT-anchored source resolves fine. Corrected in ADR-187 at review; this copy is the
# propagation of that correction.)
# The independent argument for THIS file is stronger still — `guard-script-fixture-tests` runs this file on a
# bare runner with nothing but `actions/checkout`. Do not "improve" one copy.
suite_exit_class() {
  local rc="${1-}" name
  [[ "$rc" =~ ^[0-9]+$ ]] || { printf 'failed\n'; return 0; }   # fail CLOSED on a malformed rc
  (( rc == 0 )) && { printf 'ok\n'; return 0; }
  # `<= 192` is a legibility bound and is NOT load-bearing: the call passes
  # `kill -l $(( rc - 128 ))`, so for every rc in 193..255 the operand is 65..127,
  # which kill -l rejects — the `-n "$name"` guard already excludes it. Mutating
  # this to `rc > 128` leaves every table row byte-identical, so no test pins it.
  # It is kept to state the intended domain, not because a row proves it.
  if (( rc > 128 && rc <= 192 )); then
    name=$(kill -l $(( rc - 128 )) 2>/dev/null) || name=""
    [[ -n "$name" ]] && { printf 'killed\n'; return 0; }
  fi
  printf 'failed\n'
}

# Minimum-suite floor (#7068). Without it the glob is silently de-existable: delete or rename
# a suite out of `test-*.sh` and this script prints "ALL FIXTURE TESTS PASS" over a smaller
# set, with nothing anywhere asserting the membership. That is the same silent-and-green shape
# the suites here exist to catch, applied to their own runner -- and
# test-infra-suite-registration.sh already carries this exact discipline for ITS input while
# this runner carried none for its own.
#
# A FLOOR, not equality: the count is developer-incremented, so `-eq` would turn every added
# suite into a spurious failure. Derived from a green run (11 suites, 2026-08-13; was 10 until
# test-run-all-signal-propagation.sh landed with #7429). Raise it when suites are added; lower
# it deliberately, with a reason.
MIN_SUITES=11

for t in "$DIR"/test-*.sh; do
  [[ -e "$t" ]] || continue
  RAN=$((RAN + 1))
  echo "=== $(basename "$t") ==="
  # CAPTURE the rc, never `if ! bash "$t"`. The boolean form discards WHICH non-zero came
  # back, which is precisely the bit that separates a terminated suite from a failed one.
  rc=0
  bash "$t" || rc=$?
  case "$(suite_exit_class "$rc")" in
    ok) ;;
    killed)
      KILLED=$((KILLED + 1))
      KILLED_RECORD+=("$(basename "$t")|$rc")
      # Deliberately NOT test-all.sh's `[KILLED]` byte-shape: that line carries a trailing
      # `, <N>ms)` field and main-health-monitor.yml anchors on it exactly, precisely so a
      # nested runner's stdout cannot forge the top-level marker. This line is for the human
      # reading this runner's own log; the top-level marker is minted by run_suite from the rc
      # this file exits with.
      echo "[KILLED] $(basename "$t") (exit=$rc, signal-shaped 128+$(( rc - 128 )) = SIG$(kill -l $(( rc - 128 )) 2>/dev/null)) — UNRESOLVED, not a failure: this runner did not measure what terminated it, and exit $rc is also what a suite calling exit($rc) reports." >&2
      ;;
    failed) FAIL=1 ;;
    # Fail CLOSED, and say so out loud. An unrecognized class must never fall through as a
    # pass -- that is the same false green the rc capture exists to remove.
    *) echo "WARNING: suite_exit_class returned unrecognized class for rc=$rc; counting as FAILED." >&2
       FAIL=1 ;;
  esac
  echo ""
done

if (( RAN < MIN_SUITES )); then
  echo "::error::run-all: ran only $RAN fixture suite(s), expected >= $MIN_SUITES."
  echo "         A suite was deleted or renamed out of the test-*.sh glob. If that was"
  echo "         deliberate, lower MIN_SUITES in the same commit and say why."
  FAIL=1
fi

# Precedence, in order. The floor is folded into FAIL above and is therefore evaluated BEFORE
# the killed arm -- it stays dominant.
if (( FAIL != 0 )); then
  echo "ONE OR MORE FIXTURE TESTS FAILED"
  exit 1
fi

if (( KILLED > 0 )); then
  # SELECTION RULE (deterministic, and stated so two runs of the same failure cannot report
  # different numbers): the signal-shaped rc of the LEXICOGRAPHICALLY-FIRST killed suite
  # basename, byte-ordered. `LC_ALL=C` is a prefix on `sort` alone -- pinning it here rather
  # than in the environment keeps the fixture suites running under the ambient locale.
  # Read in the current shell via `< <(...)`, never `$(...)` around the counter, so nothing
  # that must escape the loop is computed in a subshell.
  KILLED_RC=""
  KILLED_NAME=""
  while IFS='|' read -r _kname _krc; do
    if [[ -z "$KILLED_RC" ]]; then
      KILLED_NAME="$_kname"
      KILLED_RC="$_krc"
    fi
  done < <(printf '%s\n' "${KILLED_RECORD[@]}" | LC_ALL=C sort)
  if [[ ! "$KILLED_RC" =~ ^[0-9]+$ ]]; then
    # Fail CLOSED: KILLED>0 with no usable rc means the record went missing, which is a bug in
    # this file, not a passing run.
    echo "::error::run-all: $KILLED suite(s) classified killed but no rc was recoverable — treating as failure."
    echo "ONE OR MORE FIXTURE TESTS FAILED"
    exit 1
  fi
  echo "$KILLED FIXTURE SUITE(S) TERMINATED SIGNAL-SHAPED, NONE FAILED — exiting $KILLED_RC (from $KILLED_NAME)"
  exit "$KILLED_RC"
fi

echo "ALL FIXTURE TESTS PASS"
