#!/usr/bin/env bash
# Follow-through verification for #8302 (ADR-225). OPERATOR-RUN, NOT SWEEPER-ENROLLED.
#
# Exit semantics (the sweep-followthroughs.sh contract, kept so the script reads
# the same way as its siblings):
#   0 = PASS       — the transition instrument is alive and produced a reading
#   1 = FAIL       — the instrument went dark (present but yielding nothing)
#   * = TRANSIENT  — could not run at all; retry
#
# WHY THIS IS NOT ENROLLED IN THE SWEEPER. The sweeper runs on a hosted runner
# against a fresh checkout. `.claude/.skill-invocations.jsonl` is gitignored and
# machine-local -- it exists only where sessions ran -- so on that runner every
# root is empty, the classifier prints NULL READING, and this probe exits 1 on
# EVERY sweep. Measured at review in a synthetic fresh checkout: FAIL, rc=1. That
# is the #6042 locality error (a CI schedule for the aggregator saw zero
# incidents on every run and was removed) reproduced one row down, and ADR-225's
# own Alternatives table cites #6042 as the reason not to restore that schedule.
# A probe that cannot PASS where it runs is not a soak; it is a daily false alarm
# that trains the operator to ignore FAIL. So: no `soleur:followthrough`
# directive on #8302. Run this by hand on the operator machine:
#
#     bash scripts/followthroughs/workflow-fsm-transition-baseline-8302.sh
#
# WHAT THIS ASSERTS, AND WHY IT IS NOT A DECISION.
# The obvious thing to encode here would be "decide whether to promote the gate to
# blocking". That has no pass/fail encoding -- a decision is not a measurement.
#
# What IS falsifiable is whether the instrument still works. The failure mode
# this whole change exists to prevent is a mechanism that reports success while
# reaching nothing: #8302 found the aggregator reading 68% of its corpus and
# calling it the whole, and found this very classifier printing a clean
# "undeclared=0" while discarding all 10,260 records behind a wrong field name.
# Both were silent. So the soak condition is: does the classifier still produce a
# non-null reading?
#
# A dark instrument is a FAIL even though nothing is "broken" in the ordinary
# sense -- that asymmetry is the point. Silence must not read as an all-clear.
#
# Baseline recorded 2026-09-18 at adoption, under the NODE-ONLY walk (sub-skill
# hops collapsed to the lifecycle transition they enclose; see the classifier
# header), against 10,268 invocation records spanning 2026-05-04..2026-09-18:
#   undeclared=604  sessions=1259  pairs=4922  nonnode=3936
# The earlier raw-adjacency reading (427 of 8,800) is superseded: it could not
# see plan -> deepen-plan -> ship as a review skip. The delta is printed for the
# operator; it is NOT a pass condition, because a count moving up or down is
# evidence to read rather than a threshold to trip.
set -uo pipefail

BASELINE_UNDECLARED=604
BASELINE_PAIRS=4922
BASELINE_DATE=2026-09-18

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFIER="$REPO_ROOT/scripts/classify-workflow-transitions.sh"

if [[ ! -x "$CLASSIFIER" ]]; then
  echo "TRANSIENT: classifier not executable at $CLASSIFIER" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "TRANSIENT: jq unavailable" >&2; exit 2; }

OUT=$(cd "$REPO_ROOT" && bash "$CLASSIFIER" --summary 2>&1)
RC=$?

if [[ "$RC" -ne 0 ]]; then
  # The classifier fails hard on an unparseable log or a missing edge set. That
  # is a real regression in the instrument, not a transient.
  echo "FAIL: classifier exited $RC" >&2
  echo "$OUT" >&2
  exit 1
fi

if [[ "$OUT" == *"NULL READING"* ]]; then
  echo "FAIL: the instrument is DARK — no invocation records reachable from any root." >&2
  echo "      This is the silent-success shape #8302 exists to prevent: an empty reading" >&2
  echo "      is indistinguishable from a clean one unless something says so." >&2
  echo "$OUT" >&2
  exit 1
fi

# Anchored at line start and on the summary line's own shape: a leading-greedy
# `.*undeclared=` binds to the LAST occurrence, and OUT is 2>&1-merged.
now_undeclared=$(sed -n 's/^undeclared=\([0-9][0-9]*\) .*/\1/p' <<<"$OUT" | head -1)
now_pairs=$(sed -n 's/^undeclared=[0-9]* sessions=[0-9]* pairs=\([0-9][0-9]*\) .*/\1/p' <<<"$OUT" | head -1)

if [[ -z "$now_undeclared" || -z "$now_pairs" ]]; then
  echo "FAIL: could not parse a reading out of the classifier summary." >&2
  echo "$OUT" >&2
  exit 1
fi
# A reading with records but ZERO pairs (every session a single invocation) is
# a corpus the instrument cannot say anything about -- not alive, not dark.
if [[ "$now_pairs" -eq 0 ]]; then
  echo "FAIL: records were read but no lifecycle pair formed (pairs=0); the instrument has nothing to classify." >&2
  echo "$OUT" >&2
  exit 1
fi

echo "PASS: transition instrument alive."
echo "  baseline ($BASELINE_DATE): undeclared=$BASELINE_UNDECLARED pairs=$BASELINE_PAIRS"
echo "  now:                        undeclared=$now_undeclared pairs=$now_pairs"
echo "  delta:                      undeclared $((now_undeclared - BASELINE_UNDECLARED)), pairs $((now_pairs - BASELINE_PAIRS))"
echo "  (the delta is evidence to read, not a threshold — see ADR-225 Consequences)"
exit 0
