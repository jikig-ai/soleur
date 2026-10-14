# Learning: total_count is a point-in-time snapshot, not proof the page was truncated

## Problem

#9533b: `actions-queue-health.sh` UNKNOWNed on most Oct-5 runs with
`in-progress runs truncated (7 of 8 > MAX_IP_RUNS=100)`. The guard's
predicate was `total_count > page_length` — but `total_count` and the page
rows are computed against different snapshots inside the ONE API response:
a run completing mid-request (or replica lag) shows a count higher than
the page it accompanies, with zero truncation. During Actions-capacity
churn (runs finishing rapidly) the probe kept UNKNOWNing on a count/page
disagreement that wasn't a truncation, and the probe-unavailable filing
step that exists to surface exactly that state could never file (the
`gh --jq --arg` defect — separately fixed).

The deeper framing: a guard's predicate must measure the property it
names. "Might be truncated" ≠ "page is full AND more exist". The narrow
predicate `IP_RUN_COUNT >= MAX_IP_RUNS && IP_TOTAL > IP_RUN_COUNT` is the
minimal shape that is still true of every genuine truncation and false of
the snapshot race. Partial pages are complete evidence — judge them.

## Solution

- Guard narrowed to the full-page conjunct; tests pin all three arms:
  genuine truncation (knob-scaled `MAX_IP_RUNS=1`, 1 row, total 2 →
  UNKNOWN), the 7-of-8 race (→ judged HEALTHY), and the exact-fill
  boundary (`total == page` → judged).
- Same class hardened while in the file: a non-numeric `total_count`/
  `QUEUED_RUNS` errors `[ -gt ]` to false and reads as "not truncated"/
  "queue empty" — both fail-quiet — so all three API counts now UNKNOWN
  on a non-integer. And `MAX_IP_RUNS` clamps to the API's 100-row page
  ceiling so a large knob can't make the full-page conjunct unsatisfiable.
