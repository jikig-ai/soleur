# Learning: the fix for the gated thing changed the environment the gate measures

## Problem

Item I of the grep -q series (#7432, tracker #9217) removed the infra-step `JOBS: 1` pin of the main health
monitor, gated on dry-run dispatches at `-P 4`. Dispatches 38942396026 and 38942417986 both ended with one
suite, `web-host-provisioner-parity-mutation.test.sh`, killed at the runner's 360 s default per-suite bound
(rc=124, elapsed 360-361 s, every visible row ok). A third dispatch, 38965464152, passed 179 of 179 in 1433 s.

The suite takes 171 s alone on four pinned cores and 401 s beside three other heavy suites, so the default
bound (calibrated at about 1.75x the heaviest solo suite) has no headroom for contention. The fix is a
per-suite entry in `_SUITE_BOUNDS`, but that file lives under `apps/web-platform/infra/`. A branch whose
three-dot diff touches that directory arms `_infra_in_diff` in `scripts/test-all.sh`, so the monitor's tests
step runs the nested infra runner first and the standalone infra step then runs on a warm workspace. A
dispatch from the fixed branch would have measured a different environment than the scheduled monitor on
`main`, where the nested runner is skipped.

## Solution

Land the 540 s bound as its own small PR to `main`, then rebase the gated change onto it so its diff touches no
armed path, and re-run the two concurrent dispatches from that sha. Bound sizing came from a measurement, not
a judgement: `taskset -c 0-3` alone (171 s) against four concurrent heavy suites (401 s), then 1.35x the worst
case, which is the ci-deploy precedent in the same map.

## Key Insight

A gate dispatch is evidence about the diff it runs from, not only about the code under test. Before editing
anything to make a gated change pass, ask which paths in the fix arm the runner's relevance and selection
logic, because a fix that touches an armed path changes the measurement. Separate the fix from the gated
change when the fix sits on an armed path.

## Session Errors

1. **The measurement instrument parsed an API error body as data.** `analyze.py` raised `IndexError` because a
   transient `Server Error` body from `gh api` leaked into `legs.tsv`. Recovery: the leg fetch now retries,
   validates the JSON, aborts on failure, and `analyze.py` asserts every leg row is well formed and every run
   has exactly four legs. **Prevention:** a fetch loop writes raw output to a file and validates it before it
   becomes a data row.
2. **Probe suite slips on first run.** The strict fake `gh` counted 15 arguments where the probe sends 14, one
   fixture had only 11 clean runs before the bad one, and one expectation asserted the wrong output
   substring. Recovery: each fixed against the probe's real argv and output. **Prevention:** none beyond the
   strict stub that surfaced them on the first run.
3. **A conditional CTO ruling was applied to the wrong branch.** Dispatch 3 was launched under the
   "dispatch 2 clean" branch of the ruling while dispatch 2 had actually repeated the timeout, so it earned no
   gate credit. Recovery: a final ruling on the combined data. **Prevention:** read the condition of a
   conditional ruling against the result before launching what it prescribes.
4. **Edited the bound in the gated branch before checking the arming.** Caught before any dispatch by tracing
   `_infra_in_diff`; the edit was parked as a patch and applied in a separate worktree. **Prevention:** the
   Key Insight above.

## Triage

| item | recurring? | disposition |
|---|---|---|
| 1 | yes, a fetch loop that treats any output as data | fixed inline in the instrument |
| 2 | one-off | note only |
| 3 | one-off | note only |
| 4 | recurring, covered by the Key Insight | no new rule |

## Tags

category: workflow-issues
module: apps/web-platform/infra/run-registered-suites.sh
