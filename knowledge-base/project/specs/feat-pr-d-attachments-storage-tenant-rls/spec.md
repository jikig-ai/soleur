---
feature: pr-d-attachments-storage-tenant-rls
lane: cross-domain
brand_survival_threshold: single-user incident
related_issues:
  - "#3244 (umbrella)"
  - "#3869 (PR-C deferrals tracker; items 4-5 are PR-D scope; item 6 is pre-PR prerequisite)"
predecessor_prs:
  - "#3240 (PR-A)"
  - "#3395 (PR-B)"
  - "#3854 (PR-C, merged abcb3765)"
brainstorm: knowledge-base/project/brainstorms/2026-05-16-pr-d-attachments-storage-tenant-rls-brainstorm.md
branch: feat-pr-d-attachments-storage-tenant-rls
draft_pr: "#3883"
domains_assessed:
  - Engineering (CTO)
  - Legal (CLO)
  - Product (CPO)
---

# Feature: PR-D — Attachments-Storage Tenant RLS

## Problem Statement

The runtime tenant-isolation umbrella (#3244) migrated 11 server files in PR-C (#3854) from `createServiceClient()` to `getFreshTenantClient(userId)`. The last data-plane site still on service-role is the attachments storage pipeline:

- `cc-dispatcher.ts:1435` calls `persistAndDownloadAttachments({supabase: supabase(), ...})` (web chat path)
- `agent-runner.ts:2305` calls the same helper with a service-role client (CLI agent-runner path; has a stale comment falsely claiming "Migrated in PR-C")

The helper at `apps/web-platform/server/attachment-pipeline.ts` performs three storage-adjacent operations under that service-role client:
- `message_attachments` INSERT (`:115`)
- `chat-attachments` storage `.download()` (`:142`)
- `users.workspace_path` SELECT (`:128`)

Tenant isolation is currently enforced **only** by an application-layer path-prefix check (`storagePath.startsWith(${userId}/${conversationId}/)` + reject `..`) at `attachment-pipeline.ts:83-86`, validated against client-supplied `storagePath` from the WS payload. The motivating incident for this work is the IDOR vector documented in `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md`: a crafted WS payload with `../other-user-id/conv/secret.pdf` could read any user's attachments if the application-layer check were bypassed.

Storage SELECT RLS already exists in migration `019_chat_attachments.sql` (`(storage.foldername(name))[1] = auth.uid()::text`) but is **bypassed today** because the call is service-role. INSERT/UPDATE/DELETE policies on `storage.objects` for the `chat-attachments` bucket and INSERT policy on `message_attachments` are missing entirely. Article 30 register (PA2 — Conversation Data) is currently silent on the `chat-attachments` bucket and `message_attachments` table — a present Art. 30 gap independent of PR-D.

## Goals

- **G1.** Migrate `persistAndDownloadAttachments` callers to `getFreshTenantClient(userId)` at both sites (`cc-dispatcher.ts:1435` and `agent-runner.ts:2305`). Fix stale `agent-runner.ts:2300` comment.
- **G2.** Make existing Storage SELECT RLS load-bearing (not bypassed). The application-layer prefix check at `attachment-pipeline.ts:83-86` becomes documented defense-in-depth.
- **G3.** Add missing Storage write policies: `storage.objects` INSERT/UPDATE/DELETE for `bucket_id='chat-attachments'` scoped by `(storage.foldername(name))[1] = auth.uid()::text`; `public.message_attachments` INSERT scoped by `messages.conversation_id → conversations.user_id = auth.uid()`.
- **G4.** Remove the cc-dispatcher PR-D-pending entry from `.service-role-allowlist` (lines 78-84). 14 → 13 PERMANENT entries.
- **G5.** Add Sentry mirror on silent download failures in `attachment-pipeline.ts` per `cq-silent-fallback-must-mirror-to-sentry`. Use `setUser({id: userId})` for attribution.
- **G6.** Fix `attachment-display.tsx` permanent-skeleton bug: replace `.catch(() => {})` with `reportSilentFallback(err)` + `setLoadFailed(true)` + a "preview unavailable, click to retry" affordance.
- **G7.** Amend PA2 in `knowledge-base/legal/article-30-register.md` to cover `chat-attachments` bucket, `message_attachments` table, TOMs, and retention. Closes a pre-existing Art. 30 gap.
- **G8.** Add cross-tenant Storage SELECT deny test (Founder A attempts to download Founder B's attachment path; expect RLS-deny) and positive control (B downloads B's own file successfully).
- **G9.** Add cross-tenant `message_attachments` INSERT deny test mirroring the PR-C `cc-dispatcher.tenant-isolation.test.ts` shape.

## Non-Goals

- **NG1. Migrate `/api/attachments/presign` and `/api/attachments/url` routes to tenant client.** `createSignedUploadUrl`/`createSignedUrl` mint RLS-bypass tokens by design — moving the minter to tenant client gains zero residency benefit. Routes stay service-role; document in route docstrings.
- **NG2. Migrate `account-delete.ts:152` (storage.remove) and `dsar-export.ts:515` (storage.list).** Admin ops list across all tenants; service-role required by design. Existing allowlist entries remain PERMANENT.
- **NG3. Ship `audit_byok_use` writer + `is_jti_denied` consumer.** Originally bundled with PR-D in the PR-C plan. Split to **PR-E** per CLO + CPO + CTO consensus (different review surface, different rollback shape). PR-E tracking issue filed with CLO advisory "BEFORE 2nd hosted founder or GA exposure."
- **NG4. Architectural ADR on "signed URLs vs tenant-client streaming."** CTO §3 raised the longer-term question but it is out of PR-D scope. File via `/soleur:architecture` post-PR-D if pursued.
- **NG5. New schema column `attachment_download_status`.** CPO §2 considered it as Option (i) for the silent-failure surface; rejected in favor of Sentry-mirror floor (Option (ii)) given 0 beta users.
- **NG6. Productize `soleur:tenant-migrate-call-site` skill.** Captured as Productize Candidate; file as separate skill-creation issue after PR-D merges via `/soleur:compound`.

## Functional Requirements

### FR1: Cross-tenant attachment download is rejected by RLS, not by application code

Given an authenticated tenant client for Founder A and a `storagePath` belonging to Founder B's folder (`{founderB.id}/conv-x/file.pdf`), calling `.storage.from("chat-attachments").download(storagePath)` MUST return `{ data: null, error: <not-found-or-permission> }` due to the Storage SELECT RLS policy in `migration 019_chat_attachments.sql`, NOT due to the application-layer prefix check at `attachment-pipeline.ts:83-86`. The application-layer check remains in place as defense-in-depth.

### FR2: Tenant client can write attachment metadata for its own conversations

Given an authenticated tenant client for Founder A and a `conversation_id` owned by Founder A (`conversations.user_id = founderA.id`), calling `tenantClient.from("message_attachments").insert([...])` MUST succeed. The same call against a conversation owned by Founder B MUST be rejected by the new INSERT RLS policy with PostgreSQL error code `42501` — NOT a FK violation (`23503`), which would mask the policy.

### FR3: Silent download failure is mirrored to Sentry with user attribution

When `persistAndDownloadAttachments` encounters a `.storage.download()` failure for an individual attachment (current path: `attachment-pipeline.ts:139-149` returns `null` via `Promise.allSettled`), the failure MUST be mirrored to Sentry via `reportSilentFallback` with `setUser({id: userId})`. Existing partial-success semantics (per-file failure omits the file from `attachmentContext` instead of failing the whole turn) are preserved.

### FR4: UI surfaces attachment download failure with retry affordance

`apps/web-platform/components/chat/attachment-display.tsx` MUST NOT render a permanent skeleton loader on fetch failure. On `/api/attachments/url` failure (network error, 4xx, or `data.url` missing), the component renders a "preview unavailable" affordance with click-to-retry behavior. The failure is mirrored client-side to Sentry.

### FR5: Cross-tenant deny tests fire under default CI

Tenant-isolation tests for Storage SELECT and `message_attachments` INSERT MUST run under the CI tenant-isolation job (#3869 item 6, shipped as the pre-PR prerequisite). They MUST NOT silent-skip due to missing `TENANT_INTEGRATION_TEST=1` flag in default CI.

### FR6: Allowlist enforcement passes with cc-dispatcher entry removed

`.service-role-allowlist` lines 78-84 (PR-D-pending block + cc-dispatcher.ts entry) MUST be removed. CI allowlist-enforcement script MUST pass with `cc-dispatcher.ts` no longer in the allowlist. Any residual `createServiceClient()` / `supabase()` call inside `cc-dispatcher.ts` MUST carry a `// SERVICE-ROLE: <reason>` annotation matching the pattern from PR-B (per `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`).

## Technical Requirements

### TR1: New migration — storage.objects write policies + message_attachments INSERT

A new migration (next sequence number — current latest is 044, so likely `045_attachments_storage_rls.sql`) MUST add:

```sql
-- storage.objects INSERT/UPDATE/DELETE policies for chat-attachments bucket
CREATE POLICY "Users can write own attachment objects"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
-- NOTE: No explicit WITH CHECK. A future drive-by "explicitness" edit
-- adding WITH CHECK (true) would silently disable tenant isolation on
-- writes per 2026-04-18-rls-for-all-using-applies-to-writes.md.

-- message_attachments INSERT policy
CREATE POLICY "Users can insert own message attachments"
  ON public.message_attachments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.conversations c ON c.id = m.conversation_id
      WHERE m.id = message_attachments.message_id
        AND c.user_id = auth.uid()
    )
  );
```

The exact predicate shape and any pg_temp `search_path` pinning (per `cq-pg-security-definer-search-path-pin-pg-temp`) is plan-time work.

### TR2: Single PR + post-merge ack-gated `supabase db push`

Following PR-B precedent (#3395) and `hr-menu-option-ack-not-prod-write-auth`: the PR ships migration + code together. CI applies migration to staging/test DB pre-test. Production migration via `supabase db push --linked --include-all --password ...` runs **post-merge** with per-command operator ack. NOT a separate migration-only PR.

### TR3: Tenant client call-site swap

`apps/web-platform/server/cc-dispatcher.ts:1435` and `apps/web-platform/server/agent-runner.ts:2305` swap from `supabase: supabase()` to `supabase: await getFreshTenantClient(userId)`. Wrap mint in `try/catch` with `reportSilentFallback` per PR-C cc-dispatcher precedent (`cc-dispatcher.ts:1396-1410`).

The stale `agent-runner.ts:2300` comment ("Migrated in PR-C alongside the rest of the attachment pipeline") MUST be removed/corrected.

### TR4: Sentinel sweep for hidden storage byte-readers

Pre-implementation grep sweep:

```bash
rg -n "storage\s*\.from\(['\"]chat-attachments" apps/web-platform
rg -n "\.from\(['\"]message_attachments['\"]\)" apps/web-platform
rg -n "createSignedUrl|createSignedUploadUrl|\.download\(|\.upload\(" apps/web-platform/{server,app,lib}
```

Each result MUST be either (a) migrated to tenant client, (b) annotated `// SERVICE-ROLE: <reason>` and kept on allowlist, or (c) read-only join (e.g., `api-messages.ts:141` joins via messages — RLS already covers). Per `hr-write-boundary-sentinel-sweep-all-write-sites`.

### TR5: pgTAP cross-tenant deny + positive control tests

Following `cc-dispatcher.tenant-isolation.test.ts` shape (lines 33-44, 62-110, 121-134):

- **Deny tests**: Founder A's tenant client attempts to download Founder B's actual seeded file path. Use real-shaped UUID paths (not malformed) per CTO §5 — `foldername()` returns NULL on bad input, producing false RLS-deny signals.
- **Positive control**: Founder B's tenant client successfully downloads Founder B's own file. Without this, deny tests pass for the wrong reason if the seed/fixture is broken.
- **Service-role re-read** after attempted writes per `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md` — successful HTTP response can hide RLS-filtered no-op.
- Use `randomUUID()` for UUID columns per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`.

### TR6: PA2 amendment in Article 30 register

`knowledge-base/legal/article-30-register.md` PA2 (Conversation Data) row MUST be amended to add:

- **(c) Categories**: `message_attachments` rows (filename, content-type, size, storage_path) and user-uploaded file content in the private `chat-attachments` bucket (image/PDF — content may incidentally contain personal data and Art. 9 data).
- **(g) TOMs**: per-user folder prefix `${userId}/${conversationId}/`; Supabase Storage RLS policy `(storage.foldername(name))[1] = auth.uid()::text` (load-bearing post-PR-D); defense-in-depth path-prefix validation in `attachment-pipeline.ts`; content-type allowlist; filename sanitisation; uploads via service-role presigned URL only.
- **(f) Retention**: Storage objects cascade-delete with `message_attachments` row (FK ON DELETE CASCADE on `message_id`), cascades from `messages`, cascades from conversation/account deletion.

NOT a new PA12 — attachments are sub-objects of a conversation (same lawful basis Art. 6(1)(b), same controller, same retention cascade).

### TR7: Backwards-compat orphan-path audit query (pre-merge gate)

Plan Phase 0 MUST run against staging DB:

```sql
SELECT count(*)
FROM message_attachments ma
JOIN messages m ON m.id = ma.message_id
WHERE (storage.foldername(ma.storage_path))[1] != m.user_id::text;
```

Non-zero result blocks merge until quarantine/migration plan agreed. CLO advisory carried forward to PR description.

### TR8: storage.foldername edge-case SQL spike

Plan Phase 0 MUST run on staging DB to verify behavior:

```sql
SELECT
  storage.foldername(''),
  storage.foldername('/x'),
  storage.foldername('a/'),
  storage.foldername('a/b/c');
```

If `foldername('a/')` does not return `{'a'}` (or returns NULL), the existing SELECT policy in migration 019 has a latent bypass that PR-D MUST close (e.g., by adding a `name LIKE auth.uid()::text || '/%'` check as a belt-and-suspenders predicate).

### TR9: Pre-PR for CI tenant-isolation job (#3869 item 6)

A separate small pre-PR MUST land before PR-D:

- New GitHub Actions workflow job exporting `TENANT_INTEGRATION_TEST=1`
- Doppler-gated dev-Supabase secrets: `SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`
- Re-enable `describe.skipIf(!INTEGRATION_ENABLED)` clauses to fire under the new job
- Closes #3869 item 6

Without this, all 11 PR-C tenant-isolation tests AND new PR-D Storage deny tests silent-skip.

### TR10: Multi-agent review at Phase 6 + user-impact-reviewer

Per PR-C plan structure (Phase 6: multi-agent review). PR-D plan MUST include user-impact-reviewer sign-off per `Brand-survival threshold: single-user incident`. preflight Check 6 fires on `apps/web-platform/server/**` and on the new `0NN_attachments_storage_rls.sql` migration; gdpr-gate auto-invokes per `hr-gdpr-gate-on-regulated-data-surfaces`.

## Acceptance Criteria

- [ ] Pre-PR for CI tenant-isolation job merged and green (closes #3869 item 6)
- [ ] `.service-role-allowlist` count drops 14 → 13 PERMANENT entries; cc-dispatcher PR-D-pending block removed
- [ ] Migration `0NN_attachments_storage_rls.sql` deployed to prod via post-merge ack-gated `supabase db push`
- [ ] Cross-tenant Storage SELECT deny test fires under CI and asserts `data === null`
- [ ] Cross-tenant `message_attachments` INSERT deny test fires under CI and asserts `42501` (NOT `23503`)
- [ ] Positive control: same-tenant download + INSERT both succeed
- [ ] Backwards-compat orphan-path query result = 0 (or quarantine plan agreed in PR body)
- [ ] `storage.foldername` SQL spike result documented in PR body; belt-and-suspenders predicate added if needed
- [ ] PA2 amendment in `article-30-register.md` lands in this PR (NOT deferred)
- [ ] `attachment-display.tsx` permanent-skeleton bug fixed; retry affordance present
- [ ] Sentry mirror on `attachment-pipeline.ts` silent download failures with `setUser({id})`
- [ ] Stale `agent-runner.ts:2300` comment fixed
- [ ] PR-E tracking issue filed (audit_byok_use + is_jti_denied) referencing umbrella #3244 + CLO advisory
- [ ] user-impact-reviewer agent sign-off in review thread

## References

- **Brainstorm**: `knowledge-base/project/brainstorms/2026-05-16-pr-d-attachments-storage-tenant-rls-brainstorm.md`
- **Umbrella**: #3244 — Command Center server-side agentic runtime
- **PR-C plan**: `knowledge-base/project/plans/2026-05-15-feat-pr-c-sibling-query-migration-plan.md`
- **PR-C deferrals tracker**: #3869
- **Existing migration**: `apps/web-platform/supabase/migrations/019_chat_attachments.sql`
- **Article 30 register**: `knowledge-base/legal/article-30-register.md` (PA2 at lines 54-67)
- **Motivating IDOR**: `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md`
- **Test trap (UUID payload)**: `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
- **GRANT-mismatch vitest blind**: `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`
- **RLS FOR ALL semantics**: `knowledge-base/project/learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md`
