# Tasks: OAuth T&C Consent Residual Audit Bundle

Derived from: `knowledge-base/project/plans/2026-05-15-feat-oauth-tc-consent-residual-audit-plan.md`
Spec: `knowledge-base/project/specs/feat-oauth-tc-consent-3205/spec.md`
Branch: `feat-oauth-tc-consent-3205` · Worktree: `.worktrees/feat-oauth-tc-consent-3205/` · PR: #3853 · Issue: #3205

ATDD discipline: each Phase 1-8 task lists the test FIRST (RED), then the implementation, then the GREEN verification.

## Phase 0: Preconditions

- [ ] 0.1 Verify worktree on `feat-oauth-tc-consent-3205`, HEAD ≥ `a63aa714`.
- [ ] 0.2 `ls apps/web-platform/supabase/migrations/ | sort | tail -n 5` — confirm `044` is still free; bump if claimed.
- [ ] 0.3 `doppler secrets get SUPABASE_PROJECT_REF -p soleur -c dev --plain` and `-c prd` — record both refs in `migration-checklist.md`.
- [ ] 0.4 `sha256sum docs/legal/terms-and-conditions.md plugins/soleur/docs/pages/legal/terms-and-conditions.md` — both byte-identical; record canonical SHA for Phase 3.
- [ ] 0.5 Grep `reportSilentFallback` in `app/api/accept-terms/route.ts` — confirm import path `@/server/observability`.
- [ ] 0.6 Read `apps/web-platform/lib/types.ts` discriminated union (around line 201-230) — confirm the 7 inbound message types named in AC6.

## Phase 1: Migration `044_add_tc_acceptances_ledger.sql` (ATDD)

- [ ] 1.1 RED: Write `apps/web-platform/test/migration-044-tc-acceptances.test.ts` — three grep-based asserts: (a) every caller-facing `CREATE OR REPLACE FUNCTION` followed by `REVOKE ALL ... FROM PUBLIC, anon, authenticated`, (b) trigger function REVOKEs from `PUBLIC, anon, authenticated, service_role`, (c) trigger function does NOT contain `SECURITY DEFINER` (must be INVOKER).
- [ ] 1.2 Write migration: table DDL (`tc_acceptances` with `UNIQUE(user_id, version)`, `retention_until` 7y default, `ON DELETE RESTRICT` on `user_id`), header citing precedent 043 + learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`, comment block on offboarding-runbook ordering.
- [ ] 1.3 WORM trigger function `tc_acceptances_no_mutate` (INVOKER, anonymise-bypass only, four-role REVOKE).
- [ ] 1.4 RPC `accept_terms(p_user_id uuid, p_version text, p_doc_sha text)` — `SECURITY DEFINER`, `SET search_path = public, pg_temp`, body uses server-side `now()`, `INSERT ... ON CONFLICT (user_id, version) DO NOTHING`. Three-role REVOKE + service-role GRANT.
- [ ] 1.5 RPC `anonymise_tc_acceptances(p_user_id uuid) RETURNS int` — single GUC SET-site, idempotent.
- [ ] 1.6 No `pg_cron` schedule in v1 (deferred per AC21).
- [ ] 1.7 GREEN: `bash apps/web-platform/scripts/run-migrations.sh --target dev`; test 1.1 passes.
- [ ] 1.8 prd application deferred to `/soleur:ship` post-merge (AC22).

## Phase 2: Route handler delegates to RPC (ATDD)

- [ ] 2.1 RED: Write `apps/web-platform/test/api-accept-terms-ledger.test.ts` — assert `.rpc("accept_terms", { p_user_id, p_version, p_doc_sha })` is called exactly once; assert no `.update("users")` or `.insert("tc_acceptances")` direct calls; assert no short-circuit on already-current version.
- [ ] 2.2 Edit `apps/web-platform/app/api/accept-terms/route.ts` — remove early-return idempotency (current lines 40-50); always call RPC; preserve `validateOrigin`+`rejectCsrf`; on RPC error mirror to Sentry via `reportSilentFallback`, return 500.
- [ ] 2.3 Import `TC_DOCUMENT_SHA` from `@/lib/legal/tc-version`.
- [ ] 2.4 GREEN: test 2.1 passes.

## Phase 3: `TC_DOCUMENT_SHA` literal in `tc-version.ts`

- [ ] 3.1 Compute SHA-256 of canonical T&C doc (Phase 0.4 captured the value).
- [ ] 3.2 Edit `apps/web-platform/lib/legal/tc-version.ts`: add `export const TC_DOCUMENT_SHA = "<64-hex>";` with the doc-comment about CI guardrail.
- [ ] 3.3 No package.json, .gitignore, or new-file edits in this phase (per plan-review-applied simplification).

## Phase 4: Middleware fail-closed (ATDD)

- [ ] 4.1 RED: Write `apps/web-platform/test/middleware.fail-closed.test.ts` — `test.each(TC_EXEMPT_PATHS)` asserts NextResponse.next() on DB error for each exempt path; separate test asserts `/dashboard` redirects to `/accept-terms?error=db_unavailable`.
- [ ] 4.2 Edit `apps/web-platform/middleware.ts` lines 126-142 — replace fail-open with Sentry mirror + redirect for non-exempt paths. Import `TC_EXEMPT_PATHS` from `@/lib/routes` if not already in scope.
- [ ] 4.3 GREEN: test 4.1 passes.

## Phase 5: WebSocket mid-session re-check (ATDD)

- [ ] 5.1 RED: Write `apps/web-platform/test/ws-handler.tc-mid-session.test.ts` — `test.each` over 5 gated types asserts `ws.close(TC_NOT_ACCEPTED)`; `test.each` over 2 exempt types asserts close NOT invoked; cache test asserts mock `.select` count == 1 after two consecutive gated messages within 30s.
- [ ] 5.2 Edit `apps/web-platform/server/ws-handler.ts`:
  - [ ] 5.2.a Add `TC_RECHECK_MESSAGE_TYPES` set near top of file.
  - [ ] 5.2.b Add `tcVersionAtHandshake: string | null` + `tcRecheckCacheUntil: number | null` to `ClientSession`.
  - [ ] 5.2.c At session registration (~line 1875), set both new fields.
  - [ ] 5.2.d Insert re-check guard at top of inbound `switch (msg.type)` block.
- [ ] 5.3 GREEN: test 5.1 passes.

## Phase 6: CI guardrail for T&C SHA drift

- [ ] 6.1 Write `apps/web-platform/scripts/check-tc-document-sha.sh` — bash + sha256sum; recompute canonical + mirror SHAs; grep `TC_DOCUMENT_SHA` literal; fail on mismatch unless `TC_VERSION` was bumped in the PR diff.
- [ ] 6.2 Add `tc-document-sha-guard` job to `.github/workflows/ci.yml` (mirror sibling `lint-bot-statuses` shape).
- [ ] 6.3 Manual verify on this PR: (a) confirm doc unchanged + literal correct → CI green; (b) test by temporarily editing the doc → CI fails; revert.

## Phase 7: Copy regression test

- [ ] 7.1 Write `apps/web-platform/test/accept-terms-copy-regression.test.tsx` per plan AC8.
- [ ] 7.2 Confirm GREEN (current copy already passes).

## Phase 8: End-to-end test (ATDD)

- [ ] 8.1 RED: Write `apps/web-platform/test/e2e-oauth-tc-consent.test.ts` — mock chain per plan AC9; assert RPC called once with `(p_user_id, TC_VERSION, TC_DOCUMENT_SHA)`; do NOT claim atomicity (P0-2).
- [ ] 8.2 GREEN: test passes.

## Phase 9: Legal docs

- [ ] 9.1 Edit `knowledge-base/legal/article-30-register.md` — append "Processing Activity — Consent Records" (number = current entry count + 1).
- [ ] 9.2 Create `knowledge-base/legal/tc-version-bump-policy.md` — 3-tier rubric (material / clarifying / cosmetic).
- [ ] ~~9.3 Learning addendum~~ — CUT (per plan-review).

## Phase 10: PR-ready + deferred tracking

- [ ] 10.1 Run `/soleur:gdpr-gate`; commit report to `knowledge-base/legal/gdpr-gate-report-2026-05-15-feat-oauth-tc-consent-3205.md`.
- [ ] 10.2 `gh issue create` deferred-tracking for `pg_cron` retention sweep (AC21).
- [ ] 10.3 Run all tests (`npm test` or `bun run test` per `package.json scripts.test`); confirm all phase-RED tests now GREEN and no existing test regressed (AC19).
- [ ] 10.4 Update PR #3853 body: append summary, declare `Closes #3205`.
- [ ] 10.5 `gh pr ready 3853`.
- [ ] 10.6 Spawn review: `user-impact-reviewer` (mandatory AC20) + `data-integrity-guardian` (recommended).
- [ ] 10.7 CPO/CLO sign-off captured via PR comments on FR1 schema, Phase 9.2 rubric, 7-year retention default.

## Post-merge (operator, via `/soleur:ship`)

- [ ] AC22 Migration applied to prd Supabase (with ack per `hr-menu-option-ack-not-prod-write-auth`).
- [ ] AC23 prd spot-check via `mcp__plugin_supabase_supabase__execute_sql`: insert + SELECT + WORM-on-UPDATE + anonymise.
- [ ] `gh issue close 3205` once verification complete.
