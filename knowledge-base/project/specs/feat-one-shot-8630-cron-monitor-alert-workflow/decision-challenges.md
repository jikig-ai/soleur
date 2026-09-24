# Decision challenges: feat-one-shot-8630-cron-monitor-alert-workflow

These are decisions taken during `soleur:plan` (headless, one-shot) that are judgment calls rather
than one-right-answer fixes. They are recorded under ADR-084. `ship` renders them into the PR body
and files them as an `action-required` issue.

---

## DC-1: The two #8495 watchdogs are routed, with a 14-day exit

**Date:** 2026-09-24
**Classification:** Taste

**Context.** `scheduled-inngest-health` and `scheduled-zot-restart-loop` miss most check-ins
because GitHub cron does not start them (#8495). Routing them costs about two known-noise emails a
day. The CTO devex review flagged that this can teach the operator to filter the new alert.

**Decision.** Route them anyway.

- Their failures are real, and they give the first live proof that the route works (AC16).
- If #8495 is still open 14 days after the first observed fire, a follow-up PR moves both into
  `cron_monitor_alert_unrouted`, citing #8495.

**Alternative.** Exclude them from day one. That hides a real degradation of the Inngest-down
watchdog.

## DC-2: New cron monitors need two PRs (create, then route)

**Date:** 2026-09-24
**Classification:** Taste

**Context.** A monitor created in the same PR has no detector id at plan time. Guard 2 therefore
refuses to project it, which keeps `main` from going red after a complete apply (the #8050 class).
The advisor consult and the CTO review both suggested ways to keep create and route in one PR:
project unknown ids as `pending`, re-project from post-apply state, or check `detectorIds` live
against live.

**Decision.** Use the two-PR rule now. Record the live-to-live check in the ADR-031 amendment as
the way to revisit it if pending-route PRs pile up. There were 19 monitor-block commits in the prior
90 days.

**Cost.** Adding a cron monitor takes one extra small PR plus one CI-artifact round trip for
`alert-reference.json`.

## DC-3: No daily re-page for persistent failures

**Date:** 2026-09-24
**Classification:** Taste

**Decision.** The workflow uses lifecycle triggers only (`first_seen`, `reappeared`, `regression`).
It does not use `event_frequency_count`.

- A persistent failure sends one email.
- The next reminder is Sentry's own broken-monitor email at 14 days.
- Monitors that are already red when the change is applied get no email. Instead they are listed
  once in the #8630 comment.

This departs from the #8505 shape, which re-pages daily.

## DC-4: Review cuts that were not applied

**Date:** 2026-09-24
**Classification:** Taste

These cuts were proposed in review and not applied:

- **DHH: drop the Class A `::warning::`.** Kept. The simplicity and CTO reviews both kept it, and it
  is the only signal outside the job summary for a pending route.
- **Simplicity: drop the `#N` rule on unrouted entries.** Kept. DHH and the CTO devex review both
  kept it, because it ties every pending route to a tracking issue.
- **Simplicity: drop AC17, the post-merge dispatch of the drift workflow.** Kept.
  `wg-after-merging-a-pr-that-adds-or-modifies` requires a post-merge run of a modified workflow.
