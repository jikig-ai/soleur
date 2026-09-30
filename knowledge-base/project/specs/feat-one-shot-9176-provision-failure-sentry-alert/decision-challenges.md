# Decision challenges — feat-one-shot-9176-provision-failure-sentry-alert

These are decisions the planning phase made beyond the literal scope of #9176. They are recorded
under ADR-084 so they can be audited outside this session, and `ship` renders them into the PR
body.

---

## DC-1 — The new rule also pages `bootstrap_done_degraded`

**Date:** 2026-09-30
**Classification:** Taste. It widens the issue's four listed events by one stage. Reversing it
means deleting one list member.
**Status:** open. The default holds unless the operator objects.

### What the issue asked

Page on non-pull provision-unit failures: `provision_attempt_failed`, an isolation-check FATAL, a
bootstrap failure, and `provision-fsm-busy`. All four reach Sentry as one stage,
`provision_attempt_failed`, with `why=<stage>` in the `detail` tag.

### What the plan adds

`bootstrap_done_degraded` (Sentry, warning) is the bootstrap that exits 0 while the host serves
SQLite-only. Nothing pages it today, for these reasons:

- The unit writes no latch, so it retries only on the next boot.
- ADR-257 grants nothing the authority to reboot the host.
- The degraded state therefore persists indefinitely.
- The #8562 delivery probe already reads this state as `FAIL reason=degraded`, never as a PASS.

It is the same failure class as the issue, "the host did not reach the durable shape". It costs
one member in the rule's `stage in` list.

### How to reverse

Remove `bootstrap_done_degraded` from the rule's `stage` value in `issue-alerts.tf` and from
`alert-reference.json`. Then add it to `EXEMPT_WARNING_STAGES` in
`sentry-inngest-provision-failure-alert-op-contract.test.ts`.
