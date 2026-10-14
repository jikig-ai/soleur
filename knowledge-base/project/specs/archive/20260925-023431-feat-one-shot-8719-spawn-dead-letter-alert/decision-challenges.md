# Decision challenges — feat-one-shot-8719-spawn-dead-letter-alert

Decisions taken headlessly during planning that the operator may want to revisit. Recorded per
ADR-084 so they are auditable outside the pipeline session. `ship` renders this into the PR body.

---

## DC-1 — The paged set is six reasons, not the issue's three

**Date:** 2026-09-25
**Classification:** Taste (headless default taken)
**Status:** open for review

#8719 names three reasons to page on: `anthropic_request_rejected`, `leader_response_truncated`,
`leader_tool_invalid`. The plan pages three more:

- `leader_refused` and `leader_class_disabled` — the founder's Today-card copy
  (`apps/web-platform/components/dashboard/failure-reason-copy.ts`) already says "CTO has been
  notified" for both. Leaving them quiet keeps that sentence false.
- `acknowledgment_persist_failed` — fires in the leader loop after the GitHub side effect landed;
  our database write failed, so the founder sees a failure for work that exists.

Found by the plan-time CTO review. A new contract-test check ties the policy to the copy: any reason
whose copy says "CTO has been notified" must page.

**Why it could be wrong:** `leader_response_truncated` is marked retry-eligible ("Retry usually
works"), so a low background rate would email once a day per class. It stays paged because the
issue names it.

**Cost to flip:** one `PAGES_OPERATOR` value in `apps/web-platform/lib/failure-reason.ts` plus the rule's `reason` `in` value in
`apps/web-platform/infra/sentry/issue-alerts.tf`. For `leader_refused` or `leader_class_disabled`,
the founder copy must change in the same diff, or the contract test fails.

## DC-2 — The `LEADER_CLASSES_DISABLED` kill switch pages

**Date:** 2026-09-25
**Classification:** Taste (headless default taken)
**Status:** open for review

`leader_class_disabled` covers two arms: a class deliberately disabled through
`LEADER_CLASSES_DISABLED`, and a class with no leader module (a defect). Both page, because the
copy promises it and because splitting the arms would need a new failure reason. While a class is
disabled on purpose, the reason re-pages at most once a day while founders keep clicking it. The
email tells the two arms apart: `extra.err.message` reads "disabled via LEADER_CLASSES_DISABLED" for
the kill switch and "no leader module for class X" for the defect; the rule's comment block says so.

**Alternative:** split the missing-module arm into its own reason, and change the kill-switch copy
so it no longer says "CTO has been notified". That is a product copy change, so it stays out of this
PR.
