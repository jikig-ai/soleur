#!/usr/bin/env bash
# Follow-through verification for #8302 (ADR-225).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       — the transition instrument is alive and produced a reading
#   1 = FAIL       — the instrument went dark (present but yielding nothing)
#   * = TRANSIENT  — could not run at all; retry next sweep
#
# WHAT THIS ASSERTS, AND WHY IT IS NOT A DECISION.
# The obvious thing to enrol here would be "decide whether to promote the gate to
# blocking". That has no pass/fail encoding -- a decision is not a measurement,
# and the sweeper closes a tracker on PASS, so encoding one would either
# auto-close on a decision nobody made or never close at all.
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
# Baseline recorded 2026-09-18 at adoption, against 10,260 invocation records:
#   undeclared=427  sessions=1334  pairs=8800  unclassified=6023
# The delta is printed for the operator; it is NOT a pass condition, because a
# count moving up or down is evidence to read rather than a threshold to trip.
set -uo pipefail

BASELINE_UNDECLARED=427
BASELINE_PAIRS=8800
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

now_undeclared=$(sed -n 's/.*undeclared=\([0-9]*\).*/\1/p' <<<"$OUT")
now_pairs=$(sed -n 's/.*pairs=\([0-9]*\).*/\1/p' <<<"$OUT")

if [[ -z "$now_undeclared" || -z "$now_pairs" ]]; then
  echo "FAIL: could not parse a reading out of the classifier summary." >&2
  echo "$OUT" >&2
  exit 1
fi

echo "PASS: transition instrument alive."
echo "  baseline ($BASELINE_DATE): undeclared=$BASELINE_UNDECLARED pairs=$BASELINE_PAIRS"
echo "  now:                        undeclared=$now_undeclared pairs=$now_pairs"
echo "  delta:                      undeclared $((now_undeclared - BASELINE_UNDECLARED)), pairs $((now_pairs - BASELINE_PAIRS))"
echo "  (the delta is evidence to read, not a threshold — see ADR-225 Consequences)"
exit 0
