# Tasks: T&C Subscription Cancellation and EU Withdrawal Policy

**Issue:** #893
**Plan:** [2026-03-20-chore-tc-cancellation-withdrawal-policy-plan.md](../../plans/2026-03-20-chore-tc-cancellation-withdrawal-policy-plan.md)

## Phase 1: Source File Update

- [ ] 1.1 Insert new Section 5 "Subscriptions, Cancellation, and Refunds" in `docs/legal/terms-and-conditions.md` after line 78
  - [ ] 1.1.1 Write preamble (billing cadence, auto-renewal — one sentence)
  - [ ] 1.1.2 Write 5.1 Cancellation
  - [ ] 1.1.3 Write 5.2 Account Deletion with Active Subscription
  - [ ] 1.1.4 Write 5.3 EU Right of Withdrawal (Art. 16(m) waiver + model withdrawal form reference)
  - [ ] 1.1.5 Write 5.4 Refunds (discretionary, single source of truth)
- [ ] 1.2 Renumber sections 5-16 → 6-17 (all `## N.` and `### N.X` headings)
- [ ] 1.3 Update all internal cross-references (6 locations — see plan table)
- [ ] 1.4 Add subscription deletion reference in Section 14.1b (formerly 13.1b) to Section 5.2
- [ ] 1.5 Update survival clause in Section 14.3 (formerly 13.3) — include new 5.4
- [ ] 1.6 Update "Last Updated" date line

## Phase 2: Eleventy Copy Sync

- [ ] 2.1 Replicate all Phase 1 changes to `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
- [ ] 2.2 Adjust link format: `.md` relative → `/pages/legal/*.html` absolute
- [ ] 2.3 Verify both files have identical section structure and content

## Phase 3: Verification

- [ ] 3.1 Verify section count is 17 (was 16) in both files
- [ ] 3.2 Exhaustive grep for `Section [0-9]` in both files — verify every reference resolves correctly
- [ ] 3.3 Verify no broken internal links
