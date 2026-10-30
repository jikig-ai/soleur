#!/usr/bin/env bash
# Follow-through verification for the skip-persistence probe's coverage gaps (deferred from the
# #11070 review; ADR-188 amendment 2026-10-25, "Known limits").
#
# The gaps: (A) SKIP_MARKERS covers T5, S1 and T17 only, so the rehearsal suite's S2 arm_skip
# case-arm sites print `SKIP (loud): S2(...` lines that match no marker; (B) the suite's roster
# guard counts only `^[[:space:]]*arm_skip`, so a new case-arm site is not seen; (C) push runs the
# infra workflow skips as duplicates of a green PR run are never observed.
#
# This probe closes the issue only when gap (A) is demonstrably fixed: a S2 prefix is an ELEMENT of
# the SKIP_MARKERS array in the carrier probe. It anchors on the array element form, not a bare
# token, so a comment that merely names the prefix cannot close the tracker. Until then it is NOT
# YET, which leaves the issue open; the fix PR does (A), (B) and (C) together by contract and
# re-measures the skip rate over 20 runs first (a CTO ruling: the marker vocabulary does not change
# in the same PR as the verdict arithmetic).
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS         the S2 prefix is a SKIP_MARKERS element
#   2 = NOT YET      it is not
#   3 = CANNOT ESTABLISH  the carrier probe could not be read
# Required secrets: none (reads one repository file).
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

CARRIER="scripts/followthroughs/t5-skip-persistence-bound-7510.sh"
if [[ ! -r "$CARRIER" ]]; then
  echo "CANNOT ESTABLISH: ${CARRIER} is not readable from $(pwd)" >&2
  exit 3
fi

# An array ELEMENT: the line is a single-quoted string starting with the marker prefix.
if grep -qE "^[[:space:]]*'SKIP \(loud\): S2" "$CARRIER"; then
  echo "PASS: SKIP_MARKERS in ${CARRIER} carries an S2 prefix; the vocabulary gap (A) is closed"
  exit 0
fi

echo "NOT YET: SKIP_MARKERS in ${CARRIER} has no S2 prefix; the coverage gaps (A), (B) and (C) are still open"
exit 2
