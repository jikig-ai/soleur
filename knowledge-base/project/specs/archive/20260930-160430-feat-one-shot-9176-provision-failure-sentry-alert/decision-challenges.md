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
`alert-reference.json`. T3 in `sentry-inngest-provision-failure-alert-op-contract.test.ts` then
fails (it requires every literal warning stage to be paged), so the same edit adds an explicit
exemption list to that test.

---

## DC-2 — Give `bootstrap_done_degraded` its own alert rule (needs a second production write)

**Date:** 2026-09-30
**Classification:** User-Challenge. The technical fix is clear; the blocker is the scope of the
operator's authorization, which covered ONE new Sentry alert rule for this PR.
**Status:** open. This PR ships one rule; the split needs the operator's go-ahead.

### The gap (review, 4 agents converged)

`frequency_minutes = 120` throttles per rule per issue group, and both stages share one rule and
the one shared group. `provision_attempt_failed` repeats while the unit retries, so a throttled
failure pages again later. `bootstrap_done_degraded` is emitted once per boot and never again. The
common sequence (one attempt fails and pages, the next attempt ends degraded within 2 h) therefore
suppresses the degraded page, and the SQLite-only host stays silent until its next boot. A forged
`provision_attempt_failed` event from the semi-public DSN can do the same.

### What this PR does instead

The rule comment and the runbook state the gap and tell the operator, after ANY page from this
rule, to confirm `bootstrap-done` (not `bootstrap-done-DEGRADED`) for the same `iid`. The #8562
delivery probe also reads the state as `FAIL reason=degraded` while it is open.

### The fix, if authorized

Move `bootstrap_done_degraded` into a second rule (e.g. `inngest-provision-degraded`) with its own
unused `frequency_minutes`, keep `inngest-provision-failure` on `provision_attempt_failed`, and
make T3 check the union of the two rules. About 40 lines; merging it auto-creates one more Sentry
rule via `apply-sentry-infra.yml`.
