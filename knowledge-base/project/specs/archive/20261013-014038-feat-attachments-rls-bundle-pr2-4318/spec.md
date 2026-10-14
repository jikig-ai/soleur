---
feature: attachments-rls-bundle-pr2-4318
brainstorm: knowledge-base/project/brainstorms/2026-05-25-attachments-workspace-shared-pr2-bundle-brainstorm.md
issue: "#4318"
parent_issue: "#4233"
predecessor_prs:
  - "#4345 / mig 067 (PR-1 session invalidation)"
  - "#3883 / mig 045 (PR-D attachments tenant RLS)"
  - "#4289 (controllership disclosure)"
lane: cross-domain
brand_survival_threshold: single-user incident
status: ready-for-plan
---

# Spec — PR-2 attachments workspace-shared (Storage layer)

## Problem Statement

The `chat-attachments` Supabase Storage bucket is **user-folder-keyed** (mig 045:54-60): predicate `(storage.foldername(name))[1] = auth.uid()::text` allows only the uploader to read their own attachment objects. Once `TEAM_WORKSPACE_INVITE_ENABLED` flips ON (load-bearing-prereqed by merged PR-1 #4345 / mig 067), workspaces become multi-user — but workspace co-members cannot read each others' attachments. The DB-layer cascade is already workspace-aware (mig 059:416-447 widened `is_message_owner` to use `messages.workspace_id` via `is_workspace_member()`); only the Storage bucket layer's folder predicate remains user-keyed.

Closing this gap requires (a) widening the bucket policy to allow workspace co-membership, and (b) extending the account-delete cascade to pseudonymise the departed-member's uploader identity on shared-workspace attachment rows the controller retains. Without (b), shipping (a) opens a lingering-uploader-PII window on first member-removal in a multi-user workspace.

## Goals

1. **Workspace co-members can read each others' attachments on shared conversations** post-mig-068 + post-flag-flip.
2. **Bucket policy stays defense-in-depth**: no `WITH CHECK (true)` regression, no fail-open on malformed paths (UUID-cast regex guard).
3. **Departed-member uploader identity is pseudonymised** on shared-workspace `message_attachments` rows in the same cascade step shape as PR #4351 (`member_<hex12>` pseudonym).
4. **No silent data loss** post-cutover: `dsar-export.ts` + `account-delete.ts` Storage list operations enumerate by workspace, not by user prefix.
5. **Article 30 PA-2 register matches as-shipped behavior**: §(c), §(d), §(g)(10) reflect workspace-shared semantics + new TOMs.
6. **Tenant-isolation tests prove BOTH directions**: workspace co-member positive control AND cross-workspace dual-shape deny, using real-shaped UUIDs.

## Non-Goals

- **NOT adding `workspace_id` column to `message_attachments`.** Mig 059 cascade already workspace-aware; column would be redundant.
- **NOT renaming Storage objects from `{userId}/...` to `{workspaceId}/...`.** Avoids Art. 30 processing-op logging burden; predicate-only change suffices (CLO sub-option (a)).
- **NOT adding UX changes (uploader attribution in attachment cards).** Filed as follow-up; gates `TEAM_WORKSPACE_INVITE_ENABLED` flag flip, not PR-2 merge.
- **NOT adding new disclosure modal.** PR #4289 (2026-05-22) already shipped co-member visibility disclosure.
- **NOT flipping `TEAM_WORKSPACE_INVITE_ENABLED` in this PR.** Flag flip happens separately after UX follow-up lands and orphan-path audit passes.
- **NOT touching `presign/route.ts:91` path mint** (stays `{userId}/{conversationId}/{uuid}.{ext}`) — sub-option (a) keeps paths user-keyed physically.

## Functional Requirements

- **FR1**: Mig 068 replaces the `chat-attachments` bucket FOR ALL policy predicate with `(storage.foldername(name))[1] = auth.uid()::text OR ((storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$' AND is_workspace_member(((storage.foldername(name))[1])::uuid, auth.uid()))`.
- **FR2**: `account-delete.ts` inserts a sibling cascade step between 3.92 (`anonymise_workspace_member_attestations`) and 3.93 (`anonymise_workspace_members`) that pseudonymises `message_attachments.uploader_user_id` (or equivalent column) to `member_<hex12>` for rows where the message's `conversation.user_id ≠ departing user`.
- **FR3**: `dsar-export.ts` Storage list enumeration (around line 1198) and `account-delete.ts` Storage list (around line 175) read workspace-scoped paths, not `chat-attachments/{userId}/`.
- **FR4**: Article 30 register `PA-2` is amended: §(c) adds "workspace co-members whose PII is incidentally contained in attachments uploaded by other co-members"; §(d) flips "per-user_id isolation" → "per-workspace_id isolation via `is_workspace_member()` at both `message_attachments` row layer (via mig 059) and `storage.objects` folder layer (via this PR's mig 068)"; §(g)(10) rewrites Storage TOM; §(g) adds pre-merge orphan-path audit as documented TOM.
- **FR5**: Tenant-isolation test `attachment-pipeline.tenant-isolation.test.ts` (or sibling file) adds: (a) positive control — User B in shared workspace downloads User A's attachment, (b) dual-shape deny — cross-workspace download returns either `{data:null,error:<RLS-deny>}` OR `{data:[],error:null}`, both blocked.
- **FR6**: Pre-merge orphan-path audit query (documented in `migration-checklist.md` or equivalent) returns zero rows: `SELECT COUNT(*) FROM storage.objects WHERE bucket_id='chat-attachments' AND (storage.foldername(name))[1] !~ '^[0-9a-f-]{36}$'` (or workspace-membership-resolvable equivalent). Non-zero blocks merge.

## Technical Requirements

- **TR1**: Mig 068 down.sql restores the mig 045 predicate verbatim (idempotent DROP-then-CREATE preamble per established pattern).
- **TR2**: `is_workspace_member(uuid, uuid)` qualified as `public.is_workspace_member(...)` in the bucket policy (storage policies run with `search_path` scoped to `storage`).
- **TR3**: UUID-cast regex MUST run BEFORE the `::uuid` cast (Postgres evaluates left-to-right with short-circuit on AND); otherwise malformed paths throw `invalid input syntax for type uuid` and fail-open.
- **TR4**: Account-delete cascade step pseudonymisation uses the same `member_<hex12>` shape as PR #4351 author-redaction. Reuse existing pseudonym minter if present.
- **TR5**: Migration-shape lint (`apps/web-platform/test/supabase-migrations/068-*.test.ts`) asserts: (a) bucket policy contains both predicate clauses; (b) UUID regex appears BEFORE `::uuid` cast; (c) down.sql restores exact mig 045 predicate; (d) no `WITH CHECK` clause introduced.
- **TR6**: Single PR + post-merge ack-gated `supabase db push` per `hr-menu-option-ack-not-prod-write-auth` and PR-1 / PR-D precedent.
- **TR7**: `tsc --noEmit` clean. Full vitest suite green. `bash scripts/test-all.sh` green.
- **TR8**: `/soleur:gdpr-gate` advisory pass on cumulative diff (canonical regex match: `attachments|storage.objects|workspace_member`).
- **TR9**: Test fixtures use real-shaped UUIDs (`crypto.randomUUID()`), not `__ALICE__`-style sentinels, per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`.

## Open Questions (deferred to plan Phase 0)

1. Prd `chat-attachments` object count (size the orphan-path audit; Supabase MCP query against prd).
2. `current_workspace` JWT claim availability for presign route (verify mig 060 hook output reaches `app/api/attachments/presign/route.ts:91` without round-trip).
3. Workspace-deletion cascade to Storage objects (likely orphan gap — investigate; if cheap, include in PR-2).
4. DSAR Art. 15 coverage of cross-uploader attachments in shared conversations (over-include default; confirm with CLO).
5. Final orphan-path audit query shape (pinned at plan time).

## Acceptance Criteria (Hardened scope)

- **AC1**: Mig 068 lints green (TR5).
- **AC2**: Cross-workspace download in tenant-isolation suite returns dual-shape deny (FR5).
- **AC3**: Workspace co-member positive download succeeds in tenant-isolation suite (FR5).
- **AC4**: Pre-merge orphan-path audit query returns 0 rows in dev + prd (FR6).
- **AC5**: `account-delete.ts` cascade step pseudonymises uploader on shared-workspace attachment rows; verified by integration test (departed member's `uploader_user_id` no longer appears in shared-workspace `message_attachments` post-delete).
- **AC6**: `dsar-export.ts` + `account-delete.ts` Storage list operations enumerate workspace-scoped paths and return non-empty when expected (FR3).
- **AC7**: Article 30 PA-2 register reflects workspace-shared semantics + new TOMs (FR4).
- **AC8**: Full vitest suite + tsc + `bash scripts/test-all.sh` green (TR7).
- **AC9**: `/soleur:gdpr-gate` advisory pass (TR8).
- **AC10**: PR body includes `Closes #4318` on its own body line; UX follow-up issue filed and linked.
- **AC11**: 5-agent `/soleur:review` at single-user-incident threshold including `user-impact-reviewer` passes.
- **AC12**: Squash-merge. Apply mig 068 via `web-platform-release.yml#migrate` (dev → prd ack-gated per `hr-menu-option-ack-not-prod-write-auth`).
- **AC13**: `gh issue close 4318 -r completed -c "Closed by PR #N (mig 068 + storage bucket workspace-co-member predicate)..."` AFTER prd migration succeeds.
- **AC14**: UX follow-up issue tracks: "attachment cards must show uploader avatar + name BEFORE TEAM_WORKSPACE_INVITE_ENABLED flips ON."

## Out of Scope for PR-2 (deferred)

- Storage object rename to workspace-keyed paths (sub-option (b)): defer to future Enterprise-tier scoping; requires Art. 30 processing-op logging.
- UX uploader attribution in attachment cards: separate PR, gates flag flip.
- `soleur:rls-cascade-to-direct` skill: filed as productize candidate follow-up.
- `TEAM_WORKSPACE_INVITE_ENABLED` flag flip: separate operator action post-PR-2 + UX follow-up.
