---
title: The deploy gate is bounded by measuring its own gated quantity, not by arithmetic over declared CI budgets
status: accepted
date: 2026-09-07
---

# ADR-212: The deploy gate is bounded by measuring its own gated quantity

- **Deciders:** Jean (operator), CTO agent (binding ruling on three forks), review panel
  (code-simplicity-reviewer, architecture-strategist, performance-oracle)
- **Relates to:** #7902 (this change),
  [ADR-072](./ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md) (the gate this bounds; amended
  by the same PR), #5806 (deploy off `workflow_run` — still open, re-armed),
  [ADR-133](./ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md),
  [ADR-181](./ADR-181-local-gate-declines-are-counted-verdicts.md)

## Context

`web-platform-release.yml`'s `await-ci` job fail-closes the prod deploy when CI's `test`
aggregator check-run has not concluded within a wall-clock ceiling. On 2026-09-07 every deploy
was blocked: two consecutive runs died at 3005s and 3002s against a 3000s ceiling, on different
SHAs, while their CI runs were healthy. A production outage fix sat merged-but-undeployed.

CI's duration and the gate's ceiling were coupled by nothing, and the only signal that CI had
outgrown the gate was a blocked production deploy.

## Decision

**1. The gated metric is time-to-`test`, not run wall clock.**

`await-ci` polls the `test` check-run and exits 0 the moment it concludes success, so jobs
outside `test`'s `needs` closure cannot delay it. Every sizing statement about this gate must be
expressed in that quantity. ADR-072's item 4 sized the ceiling in run wall-clock terms — a
quantity the gate does not measure — and that mis-framing is a root cause of this incident, not a
footnote.

**2. Time-to-`test` decomposes into `concurrency queue + critical-path execution`, and the queue
is usually the larger term.**

Measured 2026-09-07 across consecutive `main` push runs: real job dispatch is ~1 second, and
every job in a run starts within ~15s of the others. The 6–21 minute gaps between run creation
and job start are `ci.yml`'s **own** `concurrency` group —
`group: ${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: false` — serialising
each `main` push behind its predecessor's `test` job. Four consecutive runs started their first
job **+1 second** after the previous run's `test` completed; the two runs created after the group
had drained started in ~1 second.

An earlier revision of this ADR recorded these figures as "runner dispatch delay … tracked
separately as runner-pool contention." That was wrong, and it is corrected here rather than
quietly dropped: attributing a self-inflicted, one-line-fixable serialisation to an external pool
is exactly the mis-framing Decision 1 exists to correct, one layer out.

**3. Arithmetic over declared CI job ceilings was CONSIDERED AND REJECTED.**

The rejected design asserted `max(test's needs-closure timeout-minutes) + test's own <=
CEILING_S / 60`, enforced by a CI guard. It is recorded here because it is the obvious idea and
will otherwise be re-proposed:

- Declared job ceilings bound **execution only**. The queue term of Decision 2 is absent from the
  arithmetic by construction, so the guard is green on configurations the gate provably cannot
  absorb: under back-to-back merges — the normal case, 12 runs in 9 hours — the real quantity is
  `previous run's time-to-test + own critical path`.
- **No headroom factor repairs it.** Applying the repo's own 1.2x convention still yields a green
  verdict on that same failure. A multiplier rescales a term that is present; it cannot conjure a
  term that is absent.
- It would not have caught #7902. Before that PR no closure job declared `timeout-minutes` at
  all, and CI grew slower for months under no declared ceilings. The arithmetic only moves when a
  human edits an integer.

**4. The bound is enforced by measuring the gated quantity itself.**

`await-ci` already computes `elapsed` every iteration. It now emits an `::error::`-free
`::warning::` at `0.7 * CEILING_S` (a value DERIVED from `CEILING_S`, never restated, so the two
cannot drift). That measures time-to-`test` **including the queue**, on every release, and
catches the creep class that produced #7902 months before it becomes a fail-closed deploy.

> **RELOCATED 2026-09-09 — see [ADR-215](./ADR-215-the-deploy-fires-on-cis-completion-event-and-the-verdict-never-crosses-as-a-value.md) (#5806).**
> `await-ci` is deleted; the deploy now fires on CI's `workflow_run: completed` event, so
> `CEILING_S` no longer exists and nothing can be derived from it. **The detector is relocated,
> not deleted** — dropping it would have regressed this decision and undone what #7902 shipped
> two days earlier.
>
> Declaring a fresh `CI_BUDGET_S` and warning at 0.7x it was rejected: that is an unowned
> number, which is exactly what Decision 3 of this ADR rejected arithmetic for. The reference
> now derives from a constant that is **already owned and already CI-asserted** —
> `DRIFT_SUSTAINED_THRESHOLD_MIN`, which check B9 asserts stays >= the declared critical path.
> CI's allowed share is that budget minus the ceilings downstream of it:
> `CI_BUDGET_MIN = 207 - (30 + 15 + 90) = 72`, and the warning fires at `0.7 x` it — the same
> factor chosen here.
>
> **The measured quantity changed with it, and the change is an improvement.** This decision
> measured time-to-`test` *including the queue*, which was correct while the queue was inside
> the gated quantity. Since #7931 part 1 gave every `main` push its own concurrency group there
> IS no queue term, so the detector now measures CI's own duration from the completion event —
> the same creep, without a term belonging to a different commit.
>
> One thing this decision did not have to distinguish, and its successor does:
> `CI_BUDGET_MIN` (72, what the budget ALLOWS CI) and `CI_DECLARED_PATH` (70, what CI declares
> for ITSELF) are different quantities. An earlier revision of the #5806 work used them
> interchangeably. `70 <= 72` is the headroom statement that makes the budget hold, and it is
> now asserted at runtime rather than assumed.

**5. Job ceilings exist to bound a HUNG job, and a silent bound must never fire before a loud
one.**

`timeout-minutes` is retained on `test`'s closure for that narrow purpose only, and explicitly
not as a bound on the gate. Sizing rule: GitHub's `timeout-minutes` produces **no annotation** on
a kill, so it is the last resort and must sit strictly above whatever else can stop the job first.

> **Corrected 2026-09-08 (#7902 QA round 2).** An earlier revision of this paragraph named that
> "every loud bound on its path — the per-suite budgets declared in `scripts/test-all.sh` and
> `await-ci`'s own `CEILING_S`", and called the 2,500,000 ms budget a *fail-safe*. Both halves are
> wrong, and `ci.yml`'s own comment had already been corrected to say so:
>
> - The per-suite budget is **advisory**. `scripts/test-all.sh` states it verbatim — *"A budget
>   NEVER changes a suite's status or the runner's exit code."* It reports; it cannot fire, so it
>   is not a bound of any kind, loud or otherwise.
> - `CEILING_S` bounds a job in a **different workflow**. It does not bound a CI leg, so
>   `timeout-minutes` is in fact the *only* bound on that leg.
>
> The sizing CONCLUSION is unchanged and still right — `test-scripts` carries 60 min so that a
> healthy slow run cannot be killed silently — but the reason is that the leg's own declared
> budget describes a legitimately long run, not that it is a bound the timeout must clear. This
> ADR outlives the workflow comment, so leaving the retracted version here would hand the next
> reader the erratum.

## Consequences

- CI creeping toward the ceiling is now visible on every release, in the release log, measured in
  the quantity that matters — rather than inferred from job ceilings nobody edits.
- The warning is advisory by design. It cannot block a deploy; `await-ci`'s existing fail-closed
  `::error::` at `CEILING_S` remains the only blocking bound.
- **Named residual, correctly attributed this time:** the concurrency queue is the dominant term
  and this ADR does not remove it. The candidate fix is a one-line key change
  (`github.event_name == 'pull_request' && github.ref || github.sha`), which raises peak runner
  concurrency and would break the deliberate "let prior runs finish so the audit trail stays
  intact" property `ci.yml` documents. That is a decision about that property and is tracked as a
  follow-up, not folded into a production unblock.

  > **Superseded 2026-09-09 (ADR-215, #7931 part 1).** Two claims in the bullet above are wrong,
  > and both are corrected where the key actually changed (`ci.yml`'s dispatch note):
  >
  > 1. **"the concurrency queue is the dominant term" — not across the population.** Measured over
  >    29 consecutive `main` push runs, the group is occupied at creation on **7 (24%)**, costing a
  >    median 393s / max 1245s. On the other 22 the first job starts a median of **4s** after
  >    creation, and the window's WORST time-to-`test` (4156s) came from a run whose group was
  >    empty. The queue is real, bounded and intermittent; runner availability is the larger term
  >    overall (needs-less start spread med 292s, max 1708s).
  > 2. **"would break the ... audit trail" — it does not.** Per-SHA grouping gives each `main` push
  >    its OWN group, and `cancel-in-progress` stays `${{ github.event_name == 'pull_request' }}`.
  >    Nothing is cancelled on `main` under either key; prior runs still run to completion. The
  >    audit trail is byte-identically intact, so the property this bullet treated as a blocking
  >    trade-off was never in tension with the fix.
  >
  > What survives is the real cost: the key raises **peak runner concurrency**, on the pool the
  > measurement identifies as the binding constraint for 76% of runs. That is the declared risk of
  > #7931 part 1, with a rollback trigger, not an audit-trail concern.
- Balance across the `test-scripts` matrix legs is a positional accident of registration order,
  not an owned fact — it swung 15.09 → 20.70 → 15.09 minutes during this PR's own review purely
  from adding and removing two files. Tracked in the same follow-up.
