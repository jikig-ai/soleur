# Decision challenges — feat-one-shot-6939-cutover-missed-tick-defang

These are review findings from plan review that the headless planning run did not apply on its
own, because they are taste or user-challenge decisions (ADR-084). `ship` renders this file into
the PR body and files it as an `action-required` issue.

---

## DC-1 — Delete the opt-in ON arm entirely instead of gating it

**Date:** 2026-09-25
**Classification:** User-Challenge (it challenges the issue's stated direction)
**Source:** DHH plan-review, P1-1

**The issue's direction (the default):** #6939 names its preferred first step as putting the
per-bucket output behind a `workflow_dispatch` input that defaults to off. The plan follows that.
With the input on, it prints non-command `candidate` lines under an UNVERIFIED header.

**The challenge:** delete the block and ship no input. Most of the test surface exists for the ON
arm: window validation, the error and warning arms, the header and footer, and several fixture
cases. The candidates are unmapped UUIDs, and the operator has to do the runbook's schedule check
anyway.

**Why the plan kept the default:** for a cron whose period equals `CRON_PERIOD` (the hourly crons
at the 3600 s default), an empty bucket in the gap really is a miss. The ON arm keeps that signal
without printing anything that looks like a command. Deleting the block would also break the suite's
bucketing census and ADR-106's content anchor. The CTO judged keeping it "justified, but only just".

**Operator decision needed:** keep the gate (as planned), or delete the ON arm.

---

## DC-2 — Re-prioritise #6940 now that it owns the #6939 proper fix

**Date:** 2026-09-25
**Classification:** Taste (priority and milestone)
**Source:** architecture-strategist plan-review, P1-1

**What happens:** #6939 (p1, milestone "Phase 4: Validate + Scale") closes. Its proper fix (naming
candidates, deciding which ticks were due) moves to #6940 as a new separate item. #6940 is a chore in
"Post-MVP / Later".

**The challenge:** move #6940, or just its new item, to Phase 4 / p1, so the remaining work keeps
the priority it had.

**What the plan did instead:** it re-keyed the re-check condition so it can actually fire. The item
is due before the next production op=verify dispatch against a newly cut-over dedicated host,
whatever `missed_tick_candidates` is set to. After this PR, the harmful output is gone. What remains
is recall and precision for an accepted ADR-100 residual, which by itself does not look like p1.

**Operator decision needed:** leave #6940 as it is, or raise its priority or milestone.
