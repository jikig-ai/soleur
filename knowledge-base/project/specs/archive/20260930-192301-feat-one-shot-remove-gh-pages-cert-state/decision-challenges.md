# Decision challenges — feat-one-shot-remove-gh-pages-cert-state

Headless planning run (one-shot). Recorded for `ship` Phase 6 to render and file per ADR-084.

## 1. Scope is delivered as two PRs, and the handler ships in the first one (Taste, surfaced; operator direction unchanged)

- **Operator's stated direction:** remove the function AND the Sentry monitor (scope "function + monitor").
- **What the plan does:** two PRs. PR A (this branch) deletes the function, tests and wiring, and moves the monitor to the unrouted list. PR B (tracker #9304) deletes the monitor with `[ack-destroy]`, fixes the count ledgers and adds an Art. 30 note.
- **Why the split is not optional:** `apps/web-platform/infra/sentry/README.md` (two-PR rule, #8630) forbids an unroute and a delete in one apply. CTO confirmed no evidence a single PR is safe.
- **The open taste question:** where the handler deletion lives. The CTO, and on plan review the DHH and simplicity seats, preferred putting it in PR B (no temporary `NON_INNGEST_MONITORS` exemption, no throwaway comment rewrite). The plan puts it in PR A because the #6178 soak probe's retired-id (a UUID only measurable after the function leaves the registry) can then ride in PR B instead of forcing a third PR, and the ack-carrying PR stays a single-delete diff.
- **To flip:** move Phase 1-2 tasks into PR B and drop the exemption line; nothing else changes.

## 2. Plan-time issue created for the deferred half

Issue #9304 was filed at plan time (rule `wg-when-deferring-a-capability-create-a`) so the unrouted-map reason can cite a real `(#N)`. It is labelled `type/chore`, `domain/engineering`, `priority/p3-low`, milestone `Post-MVP / Later`.

## 3. Closing #7711

PR A's body carries `Closes #7711` (the `[cert-poll]` issue auto-filed by the deleted routine, labelled `action-required`). Its body instructs firing the reissue routine, which ADR-194 records as hazardous after the cutover. Confirm this closure is wanted; the plan comments on the issue first.
