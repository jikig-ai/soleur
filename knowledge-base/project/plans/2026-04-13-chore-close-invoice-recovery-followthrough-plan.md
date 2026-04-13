---
title: "chore: close invoice recovery follow-through (#2099, #2100)"
type: chore
date: 2026-04-13
issues: [2099, 2100]
---

# Close Invoice Recovery Follow-Through

PR #2081 (invoice history + failed payment recovery) merged and created two
follow-through items: #2099 (code-review deferred P3 findings) and #2100
(migration 022 production verification). This plan closes both.

## Background

#2099 lists 4 deferred P3 items from the code review of PR #2081. Per AGENTS.md,
deferrals without tracking issues are invisible. Each needs its own GitHub issue
milestoned to "Post-MVP / Later".

#2100 requires verifying that migration `022_invoice_recovery.sql` (adds `'unpaid'`
to the `users.subscription_status` CHECK constraint) is applied to production
Supabase. Per AGENTS.md, committed-but-unapplied migrations are silent deployment
failures.

## Task 1: Create 4 GitHub Issues for Deferred P3 Items (#2099)

Create separate tracking issues for each deferred item. All should reference
#2099 and PR #2081 as source, and be milestoned to "Post-MVP / Later" (number 6).

### Issue A: invoice.paid unconditional activation guard

- **Title:** `fix(billing): guard invoice.paid handler to only restore from past_due/unpaid`
- **Body:** The `invoice.paid` webhook handler unconditionally sets
  `subscription_status = 'active'`. It should check the current status first and
  only restore from `past_due` or `unpaid` — otherwise a paid invoice on an
  already-cancelled subscription could silently reactivate it. Ref #2099, PR #2081.
- **Labels:** `code-review`
- **Milestone:** Post-MVP / Later

### Issue B: Banner dismiss sessionStorage

- **Title:** `fix(billing): use sessionStorage for payment warning banner dismiss`
- **Body:** The past_due warning banner dismiss state should use `sessionStorage`
  (cleared on tab close) instead of component state. Currently, dismissing the
  banner persists only in React state — a page refresh shows it again. Using
  `sessionStorage` gives the user a tab-scoped dismiss without permanently hiding
  a genuine warning. Ref #2099, PR #2081.
- **Labels:** `code-review`
- **Milestone:** Post-MVP / Later

### Issue C: TOCTOU on WS subscription check

- **Title:** `fix(billing): address TOCTOU window in WebSocket subscription cache`
- **Body:** The subscription status is cached on the `ClientSession` at auth time.
  If a Stripe webhook updates the status to `unpaid` between auth and the next
  message, the user can continue chatting until they reconnect. The current
  approach accepts eventual consistency (status changes on webhook events, not
  mid-conversation), but a future enhancement could listen for webhook-triggered
  invalidation events to close the TOCTOU window. Ref #2099, PR #2081. See also
  `knowledge-base/project/learnings/2026-04-13-ws-session-cache-subscription-status.md`.
- **Labels:** `code-review`
- **Milestone:** Post-MVP / Later

### Issue D: Invoice endpoint rate limiting

- **Title:** `fix(billing): add application-level rate limiting to invoice endpoint`
- **Body:** The `/api/billing/invoices` endpoint relies on Cloudflare's default
  rate limiting. Application-level rate limiting (e.g., per-user token bucket)
  would provide defense-in-depth. Currently P3 because Cloudflare covers the
  abuse case. Ref #2099, PR #2081.
- **Labels:** `code-review`
- **Milestone:** Post-MVP / Later

### Close #2099

After all 4 issues are created, close #2099 with a comment listing the 4 new
issue numbers.

## Task 2: Verify Migration 022 Applied to Production (#2100)

### Verification approach

Use the Supabase MCP tool or REST API to verify the CHECK constraint exists.
Priority chain per AGENTS.md:

1. **Supabase MCP** — authenticate and query `information_schema.check_constraints`
2. **Supabase REST API** — use Supabase URL + service role key from Doppler `prd`
   config to query: `SELECT constraint_name FROM information_schema.check_constraints
   WHERE constraint_name = 'users_subscription_status_check'`
3. **Functional test** — attempt to PATCH a test user's `subscription_status` to
   `'unpaid'` via REST API and verify it succeeds (then restore original value)

### If migration is NOT applied

Run it manually via Supabase CLI or dashboard, then re-verify.

### Close #2100

After verification succeeds, close #2100 with a comment documenting the
verification result.

## Task 3: Update Roadmap

Update `knowledge-base/product/roadmap.md`:

- Change roadmap row 3.14 (Invoice history + failed payment handling) status from
  "Not started" to "Done" — PR #2081 shipped this feature.
- Update the Current State section to remove `invoice history (#1079)` from the
  "Remaining" list.

## Acceptance Criteria

- [ ] 4 separate GitHub issues created for deferred P3 items, each milestoned to
  "Post-MVP / Later" with `code-review` label
- [ ] #2099 closed with comment referencing the 4 new issues
- [ ] Migration 022 verified applied to production (CHECK constraint includes
  `'unpaid'`)
- [ ] #2100 closed with verification evidence
- [ ] Roadmap row 3.14 updated to "Done"
- [ ] Current State section updated (remove #1079 from remaining)

## Test Scenarios

- Given #2099 is open, when 4 tracking issues are created and #2099 is closed,
  then `gh issue view 2099 --json state` returns `CLOSED`
- Given migration 022 exists in the repo, when querying production
  `information_schema.check_constraints`, then
  `users_subscription_status_check` constraint is present
- Given a production user row, when setting `subscription_status = 'unpaid'`,
  then the update succeeds (constraint allows the value)
- Given roadmap.md row 3.14 says "Not started", when updated, then it says "Done"

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — issue management and migration verification.

## Implementation Notes

- All 4 `gh issue create` commands can run in parallel
- Migration verification requires Doppler `prd` credentials (Supabase URL + service
  role key)
- The roadmap update must happen in the same commit as any other changes per
  AGENTS.md workflow gates

## References

- PR #2081: feat(billing): invoice history + failed payment recovery
- Issue #2099: review: invoice recovery billing enforcement (PR #2081)
- Issue #2100: follow-through: verify migration 022 applied to production
- Issue #1079: feat: invoice history + failed payment recovery (parent, CLOSED)
- Migration: `apps/web-platform/supabase/migrations/022_invoice_recovery.sql`
- Learning: `knowledge-base/project/learnings/2026-04-13-stripe-status-mapping-check-constraint.md`
- Learning: `knowledge-base/project/learnings/2026-04-13-ws-session-cache-subscription-status.md`
