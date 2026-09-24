# Decision challenges: feat-one-shot-8630-cron-monitor-alert-workflow

These are decisions taken during `soleur:plan` (headless, one-shot) that are judgment calls rather
than one-right-answer fixes. They are recorded under ADR-084. `ship` renders them into the PR body
and files them as an `action-required` issue.

---

## DC-1: The two #8495 watchdogs are routed, and stay routed until #8495 lands

**Date:** 2026-09-24 (revised at deepen-plan)
**Classification:** Taste

**Context.** `scheduled-inngest-health` and `scheduled-zot-restart-loop` miss most check-ins,
because GitHub cron does not start them (#8495). Routing them sends about two known-noise emails a
day. Two reviews pulled in opposite directions:

- **CTO devex:** the noise could teach the operator to filter the new alert. It proposed moving the
  pair to `unrouted` after 14 days.
- **Observability:** the pair are the only continuous proof that the route fires. It argued against
  un-routing them.

**Decision.** Route them, with no automatic exit. They stop firing once #8495 fixes their cadence.
The operator can move them to `cron_monitor_alert_unrouted` (citing #8495) if the noise proves
worse than the canary value.

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

## DC-5: No scheduled check that the route actually fires

**Date:** 2026-09-24
**Classification:** Taste

**Context.** The observability review noted that every automated probe checks configuration. None
checks firing. If Sentry changed the detector-to-workflow dispatch on its side, every gate would
stay green while no email is sent. That is the failure shape of the 2026-09-23 learning.

**Decision.** The mitigations are:

- AC16 proves one live fire after merge.
- While #8495 is open, its watchdogs fire daily. That is visible in the workflow's group history.

A daily check is **not** added in this PR. The proposed check would require every regressed cron
issue to have a matching group-history entry in `scheduled-sentry-alert-drift.yml`. It is recorded
here, and as an accepted residual in the plan's `failure_modes`.

**Revisit** if a real cron failure is ever found to have sent no email.
