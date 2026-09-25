# Decision Challenges: feat-one-shot-8803-spawn-onfailure-deadletter

These were persisted from the `plan` Step 4.5 advisor consult and from the `plan-review` consolidation. This was a headless run, so none of them was auto-applied. `ship` Phase 6 renders this file into the PR body and files an `action-required` issue.

Plan: `knowledge-base/project/plans/2026-09-25-fix-spawn-onfailure-deadletter-and-429-label-plan.md`
Panel: dhh-rails-reviewer · kieran-rails-reviewer · code-simplicity-reviewer · cto (devex, named) · cmo (copy, named) · scoped advisor consult
Date: 2026-09-25

---

## UC-1: Replace `onFailure` with one listener on both lifecycle events (User-Challenge)

**Your direction:** add an `onFailure` handler to `agent-on-spawn-requested`. The #8803 follow-through probe passes once `main` declares `onFailure:`.

**The challenge (DHH reviewer):** instead, use ONE function triggered by both `inngest/function.failed` and `inngest/function.cancelled` under the same `if` filter, and take `lifecycle` from the event name.
- Both paths would get `retries: 3`, `idempotency` and the grace sleep. The SDK's `onFailure` step is hard-coded to one attempt.
- It is one registration instead of two.
- It needs the #8803 probe rewritten, since that probe greps for `onFailure:`.

**Cost of the challenge:** it drops the mechanism you named. It rewrites a second follow-through probe. The `onFailure` single attempt is already harmless, because the conditional UPDATE makes a duplicate or missed retry a no-op, and the catch pages.

**Default kept:** your direction. The plan ships `onFailure` plus a `function.cancelled` listener.

**Reverse it by:** telling the work phase "use a single two-trigger listener". The plan's settle helper is shared, so this only swaps the entry points.

---

## T-1: Founder copy for `leader_internal_error` (Taste)

**Plan copy:** "Something went wrong on our side and this run stopped. CTO has been notified." Retry is not offered.

**CMO suggestion:** "Something went wrong" is the stock phrase the brand voice avoids, and the line does not say what the founder should do next. The CMO proposed "A fault on our side stopped this run. CTO has been notified." with one of two endings:
- "You can ask for it again." Use this only if re-asking is safe after a crash, timeout or cancel.
- "No action needed from you." Use this otherwise.

Retry is dead for already-sent messages (#8840), so re-asking is not a working affordance today.

**Default kept:** the plan copy. The contract test requires the literal "CTO has been notified", and any of the alternatives satisfies it.

**Reverse it by:** choosing the copy. It is a one-string change in `components/dashboard/failure-reason-copy.ts`.

---

## T-2: `retryEligible: false` for `leader_internal_error` (Taste, recorded)

The CTO found that the Today card's Retry re-POSTs the send route, and the route answers 409 `not_a_draft` for any message that has already been sent (#8840). So a Retry button would do nothing. The plan ships `false`, consistent with every other "CTO has been notified" row. If #8840 later makes Retry work, revisit this row.

---

## Recorded, not applied

- **Gating `mark-acknowledged` / `persist-failure` with `.is("failure_reason", null)`** (advisor): rejected. The late `mark-acknowledged` carries `reversal_handles`, and gating it would lose the founder's Undo. See the plan's Risks section.
- **Trimming the Guard Contract matrices to one line each** (DHH): rejected. `scripts/lint-guard-contract.py` and deepen-plan Phase 4.11 require at least 3 rows per guard, plus harness rows.
