# Learning: a bound sized from one contended sample was 1.12x, not the 1.35x its comment claimed

## Problem

PR #10478 gave `web-host-provisioner-parity-mutation.test.sh` a 540 s per-suite bound and wrote
"1.35x the 401 s worst case" beside it. The 401 s was ONE contended sample from a local `taskset`
experiment. The two cold re-gate dispatches that then passed the Item I gate (#7432, tracker #9217)
measured the same suite at 481 s and 424 s, so 540 s was 1.12x the worst observed run, not 1.35x. Three
more heavy suites sat at 0.85-0.89 of their own bounds in the same runs (zot-pull 475/540, repush
468/540, boot-unlock 766/900), and `run-registered-suites.test.sh` ran 281 s against the 360 s default
with no entry at all. Slowness was a shared run-level factor (total suite-seconds ranged 4474 to 6242
across five runs), so one slower runner reds several suites in the same run, and the soak's revert
trigger would have counted each as a width failure when they were bound defects.

## Solution

Widen the five bounds by about 1.5x the worst observed figures (parity, repush, zot-pull 540 -> 720,
boot-unlock 900 -> 1200, a new 540 entry for the runner's own suite), and rewrite the comment to say
what the number is: a judgement over five off-peak runs, not a measured ceiling. A wider bound can only
turn a bound-kill into a pass, so no re-dispatch is needed. The change touches `apps/web-platform/infra/`
and so arms the nested runner, which is why it lands as its own PR before the soak starts.

## Key Insight

A threshold written down as "Nx the worst case" is a claim about the sample, and the sample is whatever
you had when you wrote it. Count the samples behind the word "worst" and say the span they cover (here:
five runs, all off-peak, Friday to Sunday). The next measurement taken for a different purpose (the
re-gates) is the cheapest falsifier, so re-read the comment against it before the bound is relied on.
Second, a bound is only a bound where nothing smaller sits above it: infra-validation's legs carry
`timeout-minutes: 15` (900 s), so a 1200 s per-suite bound cannot fire there and a hang in that context
still reads as a leg timeout. Say which context a widened bound actually governs.

## Session Errors

1. **The first pass at the boot-unlock comment promised more than the bound delivers.** It said the
   wider bound renders a slow day as the suite's own RED, which is true in the monitor's 60-minute
   step and false in infra-validation's 15-minute legs. Caught at review by reading the leg
   `timeout-minutes` against the new number. **Prevention:** when widening a per-suite bound, grep
   every CI context that runs the map for its enclosing timeout before writing the comment.
2. **A tense error in a comment about a sibling PR.** "PR #10459 removed the infra step's pin" would
   have been false at this PR's merge, because this PR lands first. Reworded to the present tense.
   **Prevention:** a comment citing an unmerged PR describes it in the present tense or not at all.

## Tags

category: workflow-issues
module: apps/web-platform/infra/run-registered-suites.sh
