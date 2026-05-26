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

## Phase 1 — Manifest schema bump

- [ ] 1.1 Bump `MANIFEST_SCHEMA_VERSION` from `"1.1.0"` to `"1.2.0"` in `dsar-export.ts`
- [ ] 1.2 Add `redacted?: boolean`, `redaction_reason?: string`, `uploader_pseudonym?: string` to `ManifestFileEntry`
- [ ] 1.3 Update `dsar-export-oversize.sh` companion version

## Phase 2 — Lift pseudonym salt to shared scope

- [ ] 2.1 Create `pseudonymSalt = randomBytes(32)` in `runExport` (or `buildArchiveToDisk`)
- [ ] 2.2 Pass salt as parameter to `exportSqlTable`
- [ ] 2.3 Pass salt as parameter to co-uploader enumeration (via `buildArchiveToDisk`)

## Phase 3 — Co-uploader enumeration (#4445)

- [ ] 3.1 Implement co-uploader 3-step query chain in `dsar-export.ts`:
  - [ ] 3.1.1 Query `workspace_members` + `conversations` for participated conv IDs where user is co-member
  - [ ] 3.1.2 Query `messages.in('conversation_id', convBatch)` for non-subject messages
  - [ ] 3.1.3 Query `message_attachments.in('message_id', coUploaderMsgIds)` for attachment metadata
- [ ] 3.2 Create `ManifestFileEntry` entries with `included: false`, `redacted: true`, `redaction_reason: "art-15-co-uploader"`, `uploader_pseudonym`
- [ ] 3.3 Wire co-uploader entries into `buildArchiveToDisk` manifest (in `files[]`, not `excluded_files[]`)
- [ ] 3.4 Add observability log line (`op: "co-uploader-enumerate"`)

## Phase 4 — Account-delete Storage cleanup (#4444)

- [ ] 4.1 Insert step 3.9015 in `account-delete.ts` between 3.901 and 3.905
- [ ] 4.2 Implement query chain: conversations owned by user -> co-member messages -> message_attachments.storage_path
- [ ] 4.3 Remove Storage objects via `service.storage.from('chat-attachments').remove(paths)`
- [ ] 4.4 Wrap in try/catch with `reportSilentFallback` (non-fatal)

## Phase 5 — PA-2 Article 30 amendment

- [ ] 5.1 Amend PA-2 (g) TOM (12) in `knowledge-base/legal/article-30-register.md`
- [ ] 5.2 Grep-validate amendment prose against `account-delete.ts`

## Phase 6 — Tests

- [ ] 6.1 Create `dsar-co-uploader.integration.test.ts` — shared-workspace co-uploader DSAR test
- [ ] 6.2 Add single-user workspace test (zero co-uploader entries)
- [ ] 6.3 Update `dsar-worker-per-row-where.test.ts` for new `.in()` chain patterns
- [ ] 6.4 Add account-delete step 3.9015 test (success + failure paths)

## Phase 7 — Final verification

- [ ] 7.1 Run vitest for all affected test files
- [ ] 7.2 Run `dsar-allowlist-completeness.test.ts`
- [ ] 7.3 Run `dsar-worker-per-row-where.test.ts`
