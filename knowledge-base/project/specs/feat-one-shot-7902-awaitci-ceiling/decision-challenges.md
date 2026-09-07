# Decision Challenges — feat-one-shot-7902-awaitci-ceiling

Recorded headless during `/soleur:plan` (no interactive gate available). `ship` renders these
into the PR body and files them as an `action-required` issue.

## DC-1 — The plan chose option 2, where issue #7902 leaned toward option 3

**Stated direction.** Issue #7902 presented three options and said it was not pre-judging them,
but framed the choice as *"Option 3 removes the class; option 1 defers it."* The one-shot brief
repeated that framing. The natural reading is a lean toward option 3 (`workflow_run`).

**What the plan does instead.** It ships option 2 (shard the long-pole `test-scripts` job and
declare a CI duration budget), leaves the `await-ci` gate and its 3000s ceiling untouched, and
keeps option 3 deferred on #5806 — updated with eight newly-discovered scoping findings and
re-armed with a post-shard criterion.

**Why the reversal.** The plan's own provisional call was option 3. Two independent measurements
and a CTO review overturned it:

1. **The framing that option 3 "removes the class" is true of the ceiling but not of the cost.**
   Option 3 stops the deploy from *noticing* a 57-minute CI; every PR and merge keeps paying it.
2. **Option 3 has a fail-open mode worse than the current outage.** Under `workflow_run`,
   `github.sha` is the default-branch tip, so the deploy job's `EXPECTED_SHA` and the image's
   `BUILD_SHA` would match each other while both being the un-CI'd SHA — the #3409 gate would
   certify the exact wrong tree it was built to catch. A second, independent hazard: because each
   CI completion fires its own release run, an out-of-order pair can roll production *backwards*
   with a green pipeline.
3. **The cause is concentrated, not diffuse.** `test-scripts` is 89.6% of CI wall clock at p50 and
   99.8% of the critical path; one step inside it is 98.3% of the job. K=3 sharding projects wall
   p50 35.7 → 13.2 min and p90 53.2 → 33.4 min, putting the distribution well under the existing
   ceiling — with no change to the deploy topology at all.
4. **Option 1 is not the cheap fallback it appears to be.** `DRIFT_SUSTAINED_THRESHOLD_MIN=195`
   currently equals its B9-computed bound exactly — zero margin — so raising `CEILING_S` forces a
   permanent loosening of the production drift alerter.

**Residual the plan does not hide.** Sharding makes the failure rare, not impossible: under severe
runner starvation the projected wall max stays ~53 min against a 50-minute ceiling, because a
different job becomes the tail through dispatch queueing. Removing the cliff entirely remains
option 3, which is why #5806 stays open rather than being closed.

**What would change the answer.** If post-shard p100 on main still exceeds 60% of `CEILING_S`, the
re-armed #5806 criterion fires and option 3 (or a bounded ceiling raise, threshold first) is
revisited.
