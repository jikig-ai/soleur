# Decision Challenges — feat-one-shot-8231-parallel-test-all

Persisted by `plan-review` running headless (invoked with a plan-file-path argument inside a Task
subagent). `ship` Phase 6 renders these into the PR body and files an `action-required` issue.

---

## UC-1 — the cheapest fix for the stated pain may be #8045, not #8231

**Class:** User-Challenge. The operator selected #8231 explicitly and was shown that #7454 Item 1
blocks it, so re-scoping to a different issue is never-Mechanical under ADR-084 and is surfaced
rather than applied.

**The operator's stated direction (the default):** implement #8231 — give the local battery a safe
parallel execution mode, ordered diagnose → fix → parallelize.

**What review found.** `dhh-rails-reviewer` argued from the plan's own arithmetic. The speedup
ceiling is `total ÷ longest_relevant_suite`: ~3.2× when the heavy batteries are relevant, and an
unmeasured figure when they decline. Forty-five minutes at 3.2× is fourteen; twenty-seven at 3.2× is
eight. The payer is `lefthook.yml:332`, a pre-commit hook, and the comment three lines above that
`run:` already records the measured outcome of the current latency: **3,861 s before any suite
started, and four `--no-verify` bypasses on PR #8082's sibling PR #7866.** A three-fold speedup on
an unusable-latency hook produces a slightly faster unusable-latency hook; the bypass rate does not
move. The change that reaches that pain is **#8045** — scoping the hook's glob to what the commit
touches — which this plan places in Non-Goals.

**How the plan responds without overruling you.** It does not re-scope. It adds **Phase 0.4a**, a
go/no-go that computes the ratio before anything is built and **stops the work if the ceiling is
below 2×**, naming #8045 as the alternative. So the decision is deferred to a measurement rather
than to either party's intuition, and the measurement is one serial run the plan was already doing.

**How to overrule.** If you want #8231 implemented regardless of what 0.4a measures, say so and the
gate becomes advisory. If you would rather spend the budget on #8045 first, say that instead — the
plan's Phase 0 output is exactly the evidence that decision needs, and nothing after Phase 0 has
been built yet.

---

## UC-2 — the #7376 diagnosis may belong in its own PR

**Class:** User-Challenge (lower confidence than UC-1). You directed the ordering explicitly, so
this is recorded rather than acted on.

**The operator's stated direction:** "Diagnose first, then parallelize" — chosen after being shown
that #7454 Item 1 blocks this work on an undiagnosed interference bug.

**What review found.** `dhh-rails-reviewer` argued that the diagnosis subject and the deliverable
share no mechanism: the new scheduler uses `wait -n -p` instead of `xargs`, an in-process rc instead
of the `.meta` sideband, per-suite capture files instead of a shared log dir — the plan says so
itself when it explains why "#7554's class cannot arise at this layer". On that reading Phase 1 is
not diagnosing the thing being extended. It also observed that the flake does not reproduce on this
16-core host at all (it is a 4-core phenomenon), so Phase 1 opens by manufacturing someone else's
hardware in a cgroup and running the infra battery seven times inside it — and that Phase 4.3's
condition (e) then makes the scheduler hostage to whether that manufactured flake appeared.

**How the plan responds.** Condition (e) was **weakened, not removed**: an all-UNKNOWN diagnosis no
longer blocks shipping the scheduler opt-in, only the default flip. The counter-argument to a full
cut is in the plan's own collision inventory: C4 records that a nested `test-all.sh` spawn can block
up to 3,600 s on the parent's own lock and then *proceed without it*, and that this is a live
candidate cause of #7376 — so the two are not as independent as the mechanism comparison suggests.
Phase 0.5 measures exactly that population, before Phase 1 runs.

**How to overrule.** Saying "split the diagnosis into its own PR against #7376" re-scopes this branch
to Phases 0, 3, 4 and 5, drops condition (e) entirely, and leaves #7432's `JOBS: 1` removal blocked
where it already is. Nothing in the current plan is harder to split later than it is now.
