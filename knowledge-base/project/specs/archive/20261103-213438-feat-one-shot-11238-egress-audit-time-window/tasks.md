# Tasks: egress audit view time-window selector (#11238)

Plan: `knowledge-base/project/plans/2026-11-03-feat-egress-audit-time-window-selector-plan.md`
Branch: `feat-one-shot-11238-egress-audit-time-window`. PR text: `Ref #11238` / `Ref #9601` only, no closing keyword.

## Phase 0: Tests first (RED)

- [ ] 0.1 Create `apps/web-platform/test/supabase-migrations/183-egress-audit-window-summary.test.ts` (shape pins that differ from 177; exact tenant-predicate count; CASE keys equal `TIME_WINDOWS`; Guard 1 parity with extractor floor)
- [ ] 0.2 Extend `test/egress-audit-rpc-denial-prefix.test.ts` to iterate migrations 177 and 183
- [ ] 0.3 Extend `test/egress-audit-summary-helpers.test.ts` (`parseTimeWindow`, `WINDOW_LABEL`, default)
- [ ] 0.4 Extend `test/egress-audit-read-loader.test.ts` (four named args; card probe unchanged with no `p_window`; PGRST202 skew; 22023 is a paged `rpc_error`)
- [ ] 0.5 Extend `test/egress-audit-page-wiring.test.ts` (`?window=` parsing, independence from `decision`)
- [ ] 0.6 Extend `test/egress-audit-view.test.tsx` (window-aware strings; byte-identical retention and visibility copy under all windows; Guard 2 sweep; banned words)
- [ ] 0.7 Extend `test/rls-fuzz/egress-audit-rollup.integration.test.ts` (window inclusion, probe, order oracle, cross-tenant, grants, live parity incl. cross-tenant fixture) - local DSN only

## Phase 1: Migration 183

- [ ] 1.1 Re-verify ordinal against `origin/main` (expect 182 highest; confirm 182 appears in the listing)
- [ ] 1.2 `supabase/migrations/183_egress_audit_window_summary.sql` (`get_egress_audit_window_summary`, 4 params, no defaults, CASE map, 22023 after authz, LAWFUL_BASIS header line, REVOKE/GRANT, COMMENT)
- [ ] 1.3 `183_egress_audit_window_summary.down.sql` (drops only the new function)
- [ ] 1.4 `supabase/verify/183_egress_audit_window_summary.sql` (ten posture rows for the new signature)

## Phase 2: Client-safe helpers

- [ ] 2.1 `lib/egress-audit/summary.ts`: `TimeWindow`, `TIME_WINDOWS`, `DEFAULT_TIME_WINDOW`, `parseTimeWindow`, `WINDOW_LABEL`, `windowPhrase` (never name a variable `window`)

## Phase 3: Loader and page

- [ ] 3.1 `server/egress-audit-read.ts`: `loadEgressAudit(supabase, userId, filter, timeWindow)` calls the new function; card path untouched
- [ ] 3.2 `page.tsx`: parse `(await searchParams).window`, pass to loader and view

## Phase 4: View

- [ ] 4.1 `components/settings/egress-audit-view.tsx`: `hrefFor(filter, timeWindow)` canonical URLs; `WindowChips` (NavLink, aria-label "Time window"); window-aware strings; shorter-window empty state with Refresh + `Show 30 days`
- [ ] 4.2 Confirm Banner, web-off notice body and summary line are byte-identical under all windows

## Phase 5: Harness registration

- [ ] 5.1 `test/rls-fuzz/rpc-cases.ts`: `ATTACK_SQL.get_egress_audit_window_summary`
- [ ] 5.2 `test/rls-fuzz/targets.ts`: extend rollup note
- [ ] 5.3 Run `test/migration-rpc-grants.test.ts`

## Phase 6: Docs

- [ ] 6.1 ADR-288 amendment 2026-11-03 via `soleur:architecture` (retirement path, back-pointer on the 2026-10-26 amendment)
- [ ] 6.2 `model.c4` (three places), run `bash scripts/regenerate-c4-model.sh`, run the three C4 tests
- [ ] 6.3 Runbook `egress-audit-enable.md` (both functions, PGRST202 skew, rollback order)
- [ ] 6.4 `dsar-export-allowlist.ts` comment, `test/feature-map.md`

## Phase 7: Legal re-check and validation

- [ ] 7.1 Run `soleur:legal:clo` on the implemented strings
- [ ] 7.2 Targeted vitest, `tsc --noEmit`, C4 tests; live suites against the LOCAL database only after applying 183 locally
- [ ] 7.3 Before each commit: grep the diff for the enablement issue number (must be absent) and for closing keywords (must be absent)
- [ ] 7.4 Re-verify migration ordinal after each sync with `origin/main`
