---
plan: knowledge-base/project/plans/2026-05-26-feat-storage-dsar-co-uploader-plan.md
branch: feat-one-shot-4444-4445-storage-dsar-co-uploader
lane: cross-domain
---

# Tasks — PR-2: Storage + DSAR co-uploader (#4444 + #4445)

## Phase 0 — Preconditions

- [ ] 0.1 Verify worktree CWD
- [ ] 0.2 Run `bun install`
- [ ] 0.3 Verify `MANIFEST_SCHEMA_VERSION = "1.1.0"` at `dsar-export.ts:193`
- [ ] 0.4 Verify `ManifestFileEntry` lacks `redacted`/`redaction_reason`/`uploader_pseudonym` fields
- [ ] 0.5 Verify account-delete step numbering (3.901 / 3.905 / 3.91)
- [ ] 0.6 Audit per-row-WHERE lint: confirm it scans only `dsar-export.ts` (line 27 of test); decision: co-uploader queries go in separate file `dsar-export-co-uploader.ts`
- [ ] 0.7 Verify `.neq()` available in installed `@supabase/postgrest-js`

## Phase 1 — Manifest schema bump

- [ ] 1.1 Bump `MANIFEST_SCHEMA_VERSION` from `"1.1.0"` to `"1.2.0"` in `dsar-export.ts`
- [ ] 1.2 Add `redacted?: boolean`, `redaction_reason?: string`, `uploader_pseudonym?: string` to `ManifestFileEntry`
- [ ] 1.3 Update `dsar-export-oversize.sh` line 130 from `"1.1.0"` to `"1.2.0"`

## Phase 2 — Lift pseudonym salt to shared scope

- [ ] 2.1 Create `pseudonymSalt = randomBytes(32)` in `runExport` before `exportSqlTable` call
- [ ] 2.2 Add `pseudonymSalt: Buffer` parameter to `exportSqlTable` signature; remove internal `randomBytes(32)` at line 428
- [ ] 2.3 Add `pseudonymSalt: Buffer` parameter to `buildArchiveToDisk` signature
- [ ] 2.4 Update `exportSqlTable` call at `runExport:1783` to pass salt
- [ ] 2.5 Update `buildArchiveToDisk` call at `runExport:1794` to pass salt
- [ ] 2.6 Update test call sites: `dsar-export-cross-tenant.integration.test.ts`, `dsar-author-redaction.integration.test.ts` — grep for `exportSqlTable(` to find all

## Phase 3 — Co-uploader enumeration (#4445)

- [ ] 3.1 Create `apps/web-platform/server/dsar-export-co-uploader.ts` with `enumerateCoUploaderAttachments` function
- [ ] 3.2 Implement 3-step query chain:
  - [ ] 3.2.1 Query `workspace_members` for workspace IDs, then `conversations.in('workspace_id', ...).neq('user_id', ...)` for participated conv IDs
  - [ ] 3.2.2 Query `messages.in('conversation_id', convBatch)` — filter for non-subject user_id
  - [ ] 3.2.3 Query `message_attachments.in('message_id', coUploaderMsgIds)` for attachment metadata
- [ ] 3.3 Build `CoUploaderManifestEntry` array with `included: false`, `redacted: true`, `redaction_reason: "art-15-co-uploader"`, `uploader_pseudonym`
- [ ] 3.4 Add empty-array guards at each step (mirror `dsar-export.ts:497` pattern)
- [ ] 3.5 Add batching for `.in()` calls with >500 items
- [ ] 3.6 Add observability log line (`op: "co-uploader-enumerate"`)
- [ ] 3.7 In `dsar-export.ts:buildArchiveToDisk`, import and call `enumerateCoUploaderAttachments` after `enumerateChatAttachments`; append entries to `manifest.files[]`
- [ ] 3.8 Add co-uploader redaction disclosure to `manifest.redactions[]`

## Phase 4 — Account-delete Storage cleanup (#4444)

- [ ] 4.1 Insert step 3.9015 in `account-delete.ts` between 3.901 and 3.905
- [ ] 4.2 Implement query chain: conversations owned by user -> co-member messages -> message_attachments.storage_path
- [ ] 4.3 Remove Storage objects via `service.storage.from('chat-attachments').remove(paths)` with batch guard (>1000)
- [ ] 4.4 Wrap in try/catch with `reportSilentFallback` (non-fatal); mirror step 3.5 error-handling shape

## Phase 5 — PA-2 Article 30 amendment

- [ ] 5.1 Amend PA-2 (g) TOM (12) in `knowledge-base/legal/article-30-register.md`
- [ ] 5.2 Grep-validate amendment prose against `account-delete.ts`

## Phase 6 — Tests

- [ ] 6.1 Create `dsar-co-uploader.integration.test.ts` — shared-workspace co-uploader DSAR test (two synthesized users, shared workspace)
- [ ] 6.2 Add single-user workspace test (zero co-uploader entries)
- [ ] 6.3 Assert same pseudonym in messages table redaction and manifest co-uploader entry
- [ ] 6.4 Add account-delete step 3.9015 test (success + failure paths)
- [ ] 6.5 Verify `dsar-worker-per-row-where.test.ts` passes unchanged (co-uploader queries are in separate file)

## Phase 7 — Final verification

- [ ] 7.1 Run vitest for all affected test files
- [ ] 7.2 Run `dsar-allowlist-completeness.test.ts`
- [ ] 7.3 Run `dsar-worker-per-row-where.test.ts`
- [ ] 7.4 Grep for `exportSqlTable(` across test files — confirm all call sites pass the new `pseudonymSalt` parameter
