# Tasks: Bulk archive for /dashboard/inbox (#9284)

## Phase 1: Shared eligibility module (RED-first)

- [ ] 1.1 Write `test/lib/inbox-archive-eligibility.test.ts` — predicate truth table, enum-exhaustive: email `new|acknowledged|archived` × statutory null/set; inbox `action_required|attention|info` × acted_at null/set × status. Assert reason codes `statutory | needs_action | already_acknowledged | already_archived | ok`.
- [ ] 1.2 Create `lib/inbox-archive-eligibility.ts` — `keyOf({kind,id})` helper (the `kind:id` format contract) + `archiveEligibility(row) → reason code`. Pure module, no server imports (client+server shared — `inbox-severity.ts` precedent).
- [ ] 1.3 GREEN phase-1 tests.

## Phase 2: DB statutory pin (migration 145)

- [ ] 2.1 Write `test/migration-145-email-triage-statutory-archive-guard.test.ts` — up-file contains the `CREATE OR REPLACE`, the statutory clause, `ERRCODE='P0001'`, `is_email_triage_workspace_owner`, `SET search_path = public, pg_temp`; down-file restores the mig-111 body verbatim (NOT 102 — different authz pin).
- [ ] 2.2 Create `supabase/migrations/145_email_triage_statutory_archive_guard.sql`: copy mig-111's `set_email_triage_status` body verbatim; insert after the `status <> 'new'` check and before `SET LOCAL`: `IF p_status = 'archived' AND v_row.statutory_class IS NOT NULL THEN RAISE EXCEPTION 'set_email_triage_status: statutory rows are never archived' USING ERRCODE='P0001';` Refresh the `COMMENT ON FUNCTION` to document the pin; keep the REVOKE/GRANT block.
- [ ] 2.3 Create `145_email_triage_statutory_archive_guard.down.sql` restoring the mig-111 body (workspace-owner pin) verbatim.
- [ ] 2.4 Re-check ordinal 145 against freshly-fetched `origin/main` immediately before merge (ordinal drift is live — duplicate 141 exists).

## Phase 3: Bulk archive endpoint

- [ ] 3.1 Write `test/inbox-bulk-archive-handler.test.ts` — the full Test Scenarios list from the plan: 401; 400 on >200 items / bad UUID / bad kind; dedupe; statutory email → `guarded`+`statutory` with **no RPC invoked**; un-acted `action_required` → `guarded`+`needs_action`; acknowledged email → `guarded`+`already_acknowledged`; foreign id → `not_found`; mixed batch → per-item outcomes; soft-deadline flush returns remaining ids as `error`.
- [ ] 3.2 Create `server/inbox-bulk-archive-handler.ts` — parse `{items:[{kind,id}]}`; `.in("id", ids)` chunked ≤100 per table on the user-context client; classify via `archiveEligibility`; never dispatch RPC for pre-classified ids; map 42501→`not_found`, P0001→`conflict`, else `error`; ~60s soft deadline in the loop; `reportSilentFallback` (feature `inbox`, op `bulk-archive`, ids only).
- [ ] 3.3 Create `app/api/inbox/bulk-archive/route.ts` — thin, `force-dynamic`, `POST = withUserRateLimit(inboxBulkArchiveHandler, { perMinute: 60, feature: "inbox.bulk-archive" })`.
- [ ] 3.4 Add `server/inbox-bulk-archive-handler.ts` to `SERVER_MODULES` in `test/inbox-no-service-client.test.ts`.
- [ ] 3.5 GREEN phase-3 tests.

## Phase 4: Selection UI

- [ ] 4.1 Create `hooks/use-row-selection.ts` — `Set<kind:id>` state, toggle, select-all-per-section, clear, prune-on-data-update effect.
- [ ] 4.2 `components/inbox/inbox-surface.tsx`: sibling-checkbox wrapper at the `Row` dispatch site (`flex` wrapper, `flex-1 min-w-0` on the row), per-section Select-all strips (indeterminate via ref callback, disabled when section has zero archivable), bulk bar ("N selected" / Clear / gold "Archive N selected"), Escape-clears gated on dialog-open, result `role="status"` line above the list (split copy per outcome class; focus target), `useSWRConfig().mutate` on `swrKeys.inbox("active")` + `swrKeys.inbox("archived")`, residual selection keeps non-archived ids.
- [ ] 4.3 Confirm dialog: `ResponsiveModal` + `usePendingAction`, `onClose={pending ? undefined : onCancel}` (`typed-confirm-modal.tsx` pattern), copy "Archive N items? They'll stay in the Archived tab — nothing is deleted.", Cancel ghost / Archive gold.
- [ ] 4.4 Extend `test/inbox-surface.test.tsx`: per-row checkbox render, disabled-with-reason on the three ineligible classes, per-section select-all + indeterminate + disabled-when-empty, bar show/hide, Clear, result-line copy per outcome class, selection pruning on data change, no checkboxes on Archived tab.
- [ ] 4.5 (separate commit) `e.target === e.currentTarget` keydown gate on both row components — opportunistic fix for the pre-existing "Space on inner button navigates" bug; regression rows in the row component tests.

## Phase 5: Verification

- [ ] 5.1 `npx vitest run` touched suites + full web-platform suite green; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.2 Browser QA on `/dashboard/inbox` per repo's browser workflow — select-all + bulk archive + confirm + result line screenshots.
- [ ] 5.3 AC walk: all 10 Acceptance Criteria verified against the final tree.
