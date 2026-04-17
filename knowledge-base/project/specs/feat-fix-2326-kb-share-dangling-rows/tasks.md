# Tasks — fix(kb): bind KB share links to content hash

Derived from: `knowledge-base/project/plans/2026-04-17-fix-kb-share-dangling-rows-plan.md`
Issue: #2326 · Branch: `feat-fix-2326-kb-share-dangling-rows`

## 1. Setup

- 1.1 Verify worktree state: `git status --short` clean, branch `feat-fix-2326-kb-share-dangling-rows` checked out.
- 1.2 Run prod `kb_share_links` row-count audit (REST probe under Doppler `prd`). Record count in PR body.
  - 1.2.1 If 0 rows → proceed with migration as written.
  - 1.2.2 If 1-10 rows → proceed as written; document pre-state in PR.
  - 1.2.3 If >10 rows → PAUSE; switch to soft-legacy migration path; file backfill follow-up.
- 1.3 Confirm app-level test runner works: `cd apps/web-platform && ./node_modules/.bin/vitest run --reporter=verbose test/kb-share-allowed-paths.test.ts`.

## 2. Core Implementation (RED → GREEN)

### 2.1 Phase 1 — Migration

- 2.1.1 Write `apps/web-platform/supabase/migrations/026_kb_share_links_content_sha256.sql` with: add column, defensive revoke, set NOT NULL, add check constraint, add index.
- 2.1.2 Lint migration with `supabase db lint` if available locally.

### 2.2 Phase 2 — Hash helper (TDD)

- 2.2.1 RED: write `apps/web-platform/test/kb-content-hash.test.ts` with failing assertions for `hashBytes`, `hashStream`, stream/buffer parity, empty-buffer known-hash.
- 2.2.2 GREEN: write `apps/web-platform/server/kb-content-hash.ts` exporting `hashBytes` and `hashStream`.
- 2.2.3 Verify tests green: `./node_modules/.bin/vitest run test/kb-content-hash.test.ts`.

### 2.3 Phase 3 — Creation endpoint (TDD)

- 2.3.1 RED: write `apps/web-platform/test/kb-share-content-hash.test.ts` covering:
  - Hash persisted in insert payload.
  - Same content → existing token returned (no second insert).
  - Different content for same path → stale row revoked AND new token issued.
  - Symlink swap rejected by O_NOFOLLOW.
- 2.3.2 RED: extend `apps/web-platform/test/kb-share-allowed-paths.test.ts` to assert `content_sha256` present in insert payload.
- 2.3.3 GREEN: edit `apps/web-platform/app/api/kb/share/route.ts` — open with O_NOFOLLOW, fstat-validate, `hashStream(createReadStream)`, existing-share-with-hash-check, revoke-and-reissue on mismatch.
- 2.3.4 Verify tests green.

### 2.4 Phase 4 — View endpoint + kb-reader extraction (TDD)

- 2.4.1 RED: write `apps/web-platform/test/shared-token-content-hash.test.ts` covering all eight view scenarios in the plan (markdown match/mismatch, binary match/mismatch, frontmatter-only edit, deletion, null hash, rate-limit precedence).
- 2.4.2 GREEN: add `readContentRaw` to `apps/web-platform/server/kb-reader.ts`; refactor `readContent` to call it.
- 2.4.3 GREEN: edit `apps/web-platform/app/api/shared/[token]/route.ts` — select `content_sha256`, verify on both branches, 410 with `code: content-changed` on mismatch, 410 with `code: legacy-null-hash` on null hash.
- 2.4.4 Optional: add `ETag` emission to `buildBinaryResponse` in `apps/web-platform/server/kb-binary-response.ts` and handle `If-None-Match` short-circuit.
- 2.4.5 Verify server tests green.

### 2.5 Phase 4b — UI error variant (TDD)

- 2.5.1 RED: write `apps/web-platform/test/shared-token-content-changed-ui.test.tsx` covering content-changed copy, legacy-null-hash copy, and 410-without-body fallback.
- 2.5.2 GREEN: edit `apps/web-platform/app/shared/[token]/page.tsx` — extend `PageError` union, read JSON body in the 410 branch, add `ErrorMessage` for `content-changed`.
- 2.5.3 Verify UI tests green.

## 3. Integration & QA

- 3.1 Run full app-level suite: `cd apps/web-platform && ./node_modules/.bin/vitest run`.
- 3.2 `npm run build` under Doppler in `apps/web-platform/` to catch Next route-file validator errors.
- 3.3 Manual QA against `./scripts/dev.sh` (Doppler-wrapped dev server):
  - 3.3.1 Scenario 1 — delete → re-upload → 410. Screenshot.
  - 3.3.2 Scenario 2 — rename → recreate → 410. Screenshot.
  - 3.3.3 Scenario 3 — frontmatter-only edit → 410. Screenshot.
  - 3.3.4 Scenario 4 — legitimate re-share after edit → new token works. Screenshot.
- 3.4 Verify no hash values appear in any log line (grep diff for `content_sha256` and review context).

## 4. Ship

- 4.1 `/soleur:compound` to capture learnings.
- 4.2 `/soleur:ship` with labels `priority/p1-high`, `type/security`, `domain/engineering`.
- 4.3 PR body: include pre-apply row count, all four QA screenshots, `Closes #2326`.
- 4.4 Post-merge: verify migration applied on prod via the Supabase runbook REST probe.
- 4.5 Post-merge: proceed to #2316 (stream binary responses) as the next Phase-3 review finding.
