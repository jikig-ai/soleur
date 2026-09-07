# Decision Challenges — feat-one-shot-7902-awaitci-ceiling

Recorded headless during `/soleur:plan` + `/soleur:deepen-plan` (no interactive gate available).
`ship` renders these into the PR body and files them as an `action-required` issue.

## DC-1 — The plan ships option 2 + a bounded option 1, where issue #7902 leaned toward option 3

**Stated direction.** Issue #7902 presented three options and said it was not pre-judging them, but
framed the choice as *"Option 3 removes the class; option 1 defers it."* The natural reading is a
lean toward option 3 (`workflow_run`), with option 1 (raise the ceiling) discouraged.

**What the plan does instead.** It **raises the ceiling by a bounded amount** (3000s → 3600s, with
the drift threshold moved first) *and* **shards the long-pole `test-scripts` job**. It leaves the
release job graph otherwise untouched and keeps option 3 deferred on #5806 — updated with fourteen
scoping findings it did not previously carry and re-armed with a new criterion.

**Why option 3 was rejected.** The plan's own provisional call was option 3. Measurement and review
overturned it:

1. **A fail-open worse than the current outage.** The deploy job's `EXPECTED_SHA: ${{ github.sha }}`
   — the #3409 "right semver, wrong source tree" gate — resolves under `workflow_run` to the
   default-branch tip, the same value the image's `BUILD_SHA` would take. The two would **match each
   other while both being the un-CI'd SHA**, so the gate would certify exactly the tree it exists to
   catch. Today's failure is a blocked deploy; that one is an unverified deploy reporting success.
2. **It silently disarms `live-verify`**, a *blocking* dark-launch gate whose `if:` ends
   `github.event_name == 'push'`, taking its Sentry emission and a soak's denominator with it.
3. **A CI re-run would ship a release**, since `types: [completed]` fires on `gh run rerun` and the
   release workflow has no already-released-this-SHA short-circuit.
4. **It leaves CI at ~56 minutes**, which every PR and merge keeps paying. It stops the deploy
   *noticing* the problem rather than removing it.

**Why option 1 was nonetheless bundled, against the issue's framing.** A first revision of this plan
shipped sharding alone and explicitly declined the raise, arguing it would spend prod drift-alert
sensitivity. Review established the real cost: the drift threshold moves 195 → 207 — **12 minutes**
— against a probe whose own header records measured delivery intervals of 61–243 minutes. Twelve
minutes is inside that probe's granularity. Set against leaving production blocked on a fix that
cannot be tested before merge, the trade was inverted. The raise is three integers, verifiable by
inspection, and covers today's entire measured distribution (max 56.1 min).

The pairing is the point: the raise is the deterministic unblock, and the shard is what stops the
raised ceiling from becoming the next incident — the pattern this repo has already lived twice.

**Residual the plan does not hide.** `test` waits on the maximum runner-dispatch draw across its
legs, and sharding turns one draw for `test-scripts` into K (the run already takes a max over four
draws, so the marginal change is 4 → 6). Measured dispatch is p50 1.4 / p90 12.4 / max 21.0 min. The
raised ceiling is what absorbs it.

**What would change the answer.** If post-shard time-to-`test` p100 on main exceeds 60% of
`CEILING_S`, the re-armed #5806 criterion fires and option 3 is revisited — with the fourteen
findings now recorded, so it would be scoped correctly from the start.

## DC-2 — Two plan-time measurement corrections worth the operator's attention

Both were caught by review after the plan had already been written and committed, and both changed
the plan's conclusions. Recorded because they are the kind of error that is invisible once fixed.

1. **The plan measured the wrong quantity.** `await-ci` gates on the `test` **check-run**, whose
   closure is three jobs — not on `ci.yml`'s run wall clock. The two measure equal to within 0.1 min
   in 22 of 22 runs today, but only *because* `test-scripts` is the tail. The plan's original
   "honest residual" argued that `critical-css-gate` (49.1 min) and `lockfile-sync` (40.5 min) would
   become the new tail; **neither is in `test`'s closure**, so neither can delay the gate. The
   residual was wrong in the favourable direction, and the corrected metric is what AC25 and the
   re-armed #5806 criterion are now keyed to.
2. **The partition design was unimplementable as first written.** It specified "a deterministic
   total function over the suite path", but roughly 198 scripts-group suites are hand-registered
   imperative `run_suite` statements and ~24 name no path at all. The partition now keys on the
   `run_suite` label and runs round-robin at that chokepoint — which also made totality and
   determinism structural rather than asserted, deleting an entire guard from the plan.

## Correction (2026-09-07, post-review)

DC-1's "Residual the plan does not hide" paragraph attributes the 1.4 / 12.4 / 21.0 minute
figures to runner dispatch across matrix legs. That is wrong. Re-derived from the API, real
dispatch is ~1 second and is per-RUN; those gaps are `ci.yml`'s own `concurrency` group
serialising each main push behind its predecessor's `test` job. Sharding therefore does not
multiply a dispatch draw, and the raised ceiling is not what absorbs it — the queue is a separate
term, now recorded in ADR-208 and filed as a follow-up.

DC-1's measured distribution ("max 56.1 min") is also superseded: re-measured over 25 runs, the
gated metric is p50 35.2 / p90 54.0 / p100 57.4 min.
