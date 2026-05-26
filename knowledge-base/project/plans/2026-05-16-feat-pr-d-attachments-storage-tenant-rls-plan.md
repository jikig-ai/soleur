---
feature: pr-d-attachments-storage-tenant-rls
date: 2026-05-16
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_issues:
  - "#3244 (umbrella)"
  - "#3869 (PR-C deferrals tracker; items 4-5 closed by PR-D; item 6 is pre-PR prerequisite)"
  - "#3887 (PR-E tracking: audit_byok_use + is_jti_denied)"
  - "#3739 (acknowledged overlap: reportSilentFallbackWithUser helper; absorbs PR-D's 12th site mechanically)"
predecessor_prs:
  - "#3240 (PR-A)"
  - "#3395 (PR-B)"
  - "#3854 (PR-C, merged abcb3765 on 2026-05-16)"
brainstorm: knowledge-base/project/brainstorms/2026-05-16-pr-d-attachments-storage-tenant-rls-brainstorm.md
spec: knowledge-base/project/specs/feat-pr-d-attachments-storage-tenant-rls/spec.md
branch: feat-pr-d-attachments-storage-tenant-rls
draft_pr: "#3883"
domains_assessed:
  - Engineering (CTO) — carry-forward from brainstorm
  - Legal (CLO) — carry-forward from brainstorm
  - Product (CPO) — carry-forward from brainstorm
---

# Plan: PR-D — Attachments-Storage Tenant RLS

## Overview

Final slice of runtime tenant-isolation umbrella #3244. Migrates `persistAndDownloadAttachments` (2 callers) from service-role to tenant client, adds missing Storage write policies, fixes a permanent-skeleton UI silent-failure bug, amends Article 30 register PA2 (closing a pre-existing Art. 30 gap), and shrinks `.service-role-allowlist` from 14 → 13 PERMANENT entries.

**Scope:** Hardened (compliance-complete) per brainstorm decision §1.
**Sequencing:** Pre-PR for CI tenant-isolation job (closes #3869 item 6) → PR-D ships everything else atomically + post-merge ack-gated `supabase db push` (PR-B precedent + learning `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`).
**Test gating:** All new cross-tenant deny tests use `describe.skipIf(!INTEGRATION_ENABLED)` — they silent-skip in default CI today; the pre-PR ships the workflow that fires them.

After PR-D merges, every data path in the runtime is tenant-scoped or has a structural reason to stay service-role.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident` (carry-forward from PR-C umbrella per brainstorm Phase 0.1).

**If this lands broken, the user experiences:** Founder A retrieves Founder B's attachment bytes (image, PDF, voice memo) — the LLM context contains another founder's PII (incorporation docs, brand guides, financials). Or: the founder's own attachment becomes unloadable mid-conversation (permanent skeleton loader, no error toast) due to RLS misconfiguration.

**If this leaks, the user's data is exposed via:** Cross-tenant `storage.objects` read through a tenant client whose JWT predicate (`(storage.foldername(name))[1] = auth.uid()::text`) evaluates NULL/empty → false-deny mask. OR: `message_attachments` row leakage exposing sibling tenants' filenames/MIME/sizes if INSERT policy is mis-scoped. OR: signed-URL TTL leakage via Sentry breadcrumbs.

**Threshold rationale:** Cross-tenant attachment read is the 3rd of 3 PR-C umbrella vectors. The first two were closed by PR-C (message INSERT + sibling-query GET); this closes the structural risk PR-D is named for.

**CPO sign-off required at plan time.** Brainstorm CPO assessment §1 covers the three vectors (trust breach, broader exposure, silent failure). Confirm CPO has reviewed the brainstorm before `/work` begins. `user-impact-reviewer` agent invoked at PR-review time per `Brand-survival threshold: single-user incident`.

## Research Reconciliation — Spec vs. Codebase

| Spec/Brainstorm claim | Codebase reality (verified at plan time) | Plan response |
|---|---|---|
| Brainstorm framing: "PA1/PA2 TOM row, attachment-storage residency claim" exists | CLO read article-30-register.md end-to-end: **no such row**. PA1 line 50 has generic RLS-per-user TOM; PA2 (Conversation Data) never names `chat-attachments` or `message_attachments` | PR-D includes TR6 PA2 amendment (closing existing gap, not just amending for the new code) |
| cc-dispatcher.ts:1421 is the call site | Actual at HEAD: setup ~1429, `await persistAndDownloadAttachments(...)` at :1435. PR-C plan §Tracked Deferrals cited `:1395` — drift continues | Phase 0.2 re-enumerates at /work HEAD; spec FR1 line refs are advisory |
| Single caller | TWO callers: `cc-dispatcher.ts:1435` AND `agent-runner.ts:2305`. Latter has stale "Migrated in PR-C" comment at :2300 (false) | Phase 3 migrates both; Phase 3.3 fixes stale comment |
| Migration-first split (initial intuition) | PR-B precedent (#3395) = single PR + post-merge ack-gated `supabase db push` per `hr-menu-option-ack-not-prod-write-auth`. Counter-evidence: `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md` | Brainstorm Decision #12: single PR. This plan follows |
| Migration command: `npx supabase db push` | **Runbook EXPLICITLY forbids npx supabase**. Canonical: `doppler run -p soleur -c dev -- bash scripts/run-migrations.sh` per `knowledge-base/engineering/ops/runbooks/supabase-migrations.md:171` | Phase 0.3, Phase 1.4, Phase 8 use the correct command |
| Existing test file for attachment-pipeline | `apps/web-platform/test/cc-attachment-pipeline.test.ts` (363 lines, unit-level, mocks `fs/promises` + supabase chain) | EXTEND with Sentry-mirror behavior tests (Phase 4.4); do NOT duplicate. Cross-tenant integration tests go in NEW `test/server/attachment-pipeline.tenant-isolation.test.ts` |
| Use `Sentry.setUser({id: userId})` for attribution | Canonical pattern (`reportSilentFallback` at `apps/web-platform/server/observability.ts`): pass `extra: { userId, ... }`; helper pseudonymizes via SHA-HMAC + `SENTRY_USERID_PEPPER` to `userIdHash`. Direct `Sentry.setUser` ships raw userId | Phase 4 uses `extra: { userId, ... }`, NOT `Sentry.setUser`. Per-user-per-attachment cardinality → `mirrorWithDebounce` (NOT raw `reportSilentFallback`) per `2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md` |
| Client-side: similar pattern in attachment-display.tsx | Client `ClientExtra` type brands `userId/user_id/email` as `never` — compile-time PII protection. Cannot put userId in client extras | Phase 5 client-side mirror uses `reportSilentFallback(err, { feature, op })` — NO user attribution from client. Canonical example: `message-bubble.tsx:254` |
| Storage SELECT RLS: `(storage.foldername(name))[1] = auth.uid()::text` is sufficient | Framework-docs verified: `foldername('')` → `{}` → NULL → fail-closed ✓; `foldername('a/')` → `{'a'}` → predicate passes but filename is empty (need API-layer non-empty check); `foldername('/x')` → `{''}` → fail-closed; `foldername('a/../b')` → `{'a','..'}` → bucket-scoped, no escape | Phase 0.4 SQL spike confirms on prod Postgres version. If `'a/'` case is exploitable, Phase 1.2 adds belt-and-suspenders `name LIKE auth.uid()::text || '/%'` predicate |
| Signed URL bypasses RLS by design | Confirmed: minting via tenant client goes through RLS at mint time; consumed URL bypasses RLS forever. NG1 stands | No change |
| #3660 is a PR-D predecessor | #3660 belongs to chat-RAIL/transcript-hardening track (parent #3603) — DIFFERENT "PR-D". Naming collision | Plan body explicitly disambiguates; brainstorm Pitfalls §1 captured |

## Open Code-Review Overlap

Two open code-review issues touch files PR-D will modify:

- **#3739** (review: extract `reportSilentFallbackWithUser` helper) — DIRECT pattern overlap. The 11 existing sites in `app/**/route.ts` use a 4-line wrap (`Sentry.withIsolationScope` + `setUser({id: hashUserIdValue(userId)})` + `reportSilentFallback`). PR-D Phase 4 adds a 12th site in `server/attachment-pipeline.ts` using the same shape (or `mirrorWithDebounce` variant). **Disposition: Acknowledge.** Use the inline pattern in PR-D's new site; #3739's mechanical sweep absorbs it as 12 instead of 11. Folding helper extraction in would add 12 more file edits (observability.ts + 11 route.ts) and dilute review focus — PR-D scope is already Hardened.
- **#3243** (arch: decompose cc-dispatcher.ts into focused modules, ref #3235) — PR-D edits one line at `cc-dispatcher.ts:1435` (call-site swap). **Disposition: Acknowledge.** Decomposition is an independent refactor; PR-D's tiny edit does not block it.

No matches for: `attachment-pipeline.ts`, `attachment-display.tsx`, `agent-runner.ts:2305`, `.service-role-allowlist`, `message_attachments`, `chat-attachments`, `019_chat_attachments`, `article-30-register.md`.

## Files to Edit

| File | Phase | Change |
|---|---|---|
| `apps/web-platform/server/cc-dispatcher.ts` | 3.1 | Swap `supabase: supabase()` → `supabase: await getFreshTenantClient(userId)` at :1435 call. Wrap mint in try/catch with `reportSilentFallback` per PR-C cc-dispatcher precedent (lines 1396-1410). |
| `apps/web-platform/server/agent-runner.ts` | 3.2, 3.3 | Same swap at :2305. Fix stale comment at :2300 (currently falsely claims "Migrated in PR-C"). |
| `apps/web-platform/server/attachment-pipeline.ts` | 4.1, 4.2 | Add `mirrorWithDebounce(err, ctx, userId, "attachment_download_failed")` at :139-149 silent-failure branch. **Preserve** the `"Failed to download attachment"` message string in `ctx.message` per `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`. Sentry pseudonymizes userId via SENTRY_USERID_PEPPER → userIdHash. Partial-success semantics unchanged (per-file failure omits from `attachmentContext`). |
| `apps/web-platform/components/chat/attachment-display.tsx` | 5.1, 5.2, 5.3 | Replace `.catch(() => {})` with `.catch((err) => { reportSilentFallback(err, { feature: "attachments", op: "url-fetch" }); setLoadFailed(true); })`. Add `loadFailed` state. Render "Preview unavailable" + "Retry" button (resets `loadFailed` + re-fetches) in place of the permanent skeleton when `loadFailed === true`. Use the `message-bubble.tsx:254` precedent for the client-side `reportSilentFallback` shape; **NO userId in extras** (ClientExtra brands it `never`). |
| `apps/web-platform/.service-role-allowlist` | 6.1 | Remove lines 78-84 (PR-D-pending comment block + `apps/web-platform/server/cc-dispatcher.ts` entry). Single atomic commit per PR-C Phase 4 precedent. |
| `apps/web-platform/test/cc-attachment-pipeline.test.ts` | 4.4 | Add unit-test cases covering the new Sentry mirror behavior: simulate `.storage.download()` returning `{data:null, error: <RLS-deny>}` and assert `mirrorWithDebounce` is called with `feature: "attachment-pipeline"`, `op: "storage.download"`, `errorClass: "attachment_download_failed"`, `extra.userId: <user-id>`, `message: "Failed to download attachment"`. |
| `knowledge-base/legal/article-30-register.md` | 7.1 | Amend PA2 (Conversation Data) row. Add to (c) Categories: `message_attachments` rows + `chat-attachments` bucket content (image/PDF; may incidentally contain Art. 9 data). Add to (g) TOMs: per-user folder prefix, Storage RLS policy `(storage.foldername(name))[1] = auth.uid()::text` (load-bearing post-PR-D), defense-in-depth path-prefix check in `attachment-pipeline.ts`, content-type allowlist, filename sanitisation, uploads via service-role presigned URL only. Add to (f) Retention: FK ON DELETE CASCADE on `message_id` → messages → conversation/account deletion. |

## Files to Create

| File | Phase | Purpose |
|---|---|---|
| `apps/web-platform/supabase/migrations/045_attachments_storage_rls.sql` | 1.1-1.3 | NEW migration. `storage.objects` FOR ALL policy (INSERT/UPDATE/DELETE) scoped to `bucket_id='chat-attachments'` with `(storage.foldername(name))[1] = auth.uid()::text`. `message_attachments` INSERT policy joining `messages.conversation_id → conversations.user_id = auth.uid()`. Migration comment explaining `FOR ALL USING` (no explicit `WITH CHECK`) semantics per `2026-04-18-rls-for-all-using-applies-to-writes.md` to prevent future drive-by `WITH CHECK (true)` regression. Belt-and-suspenders predicate added if Phase 0.4 SQL spike surfaces `foldername('a/')` exploit. |
| `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` | 2.1-2.5 | NEW integration test file mirroring `cc-dispatcher.tenant-isolation.test.ts` shape. Two synthetic founders (`tenant-isolation-<16hex>@soleur.test`). Cross-tenant Storage SELECT deny test (Founder A `.storage.from("chat-attachments").download(<userB-path>)` → `expect(data).toBeNull()`). Same-tenant positive control. Cross-tenant `message_attachments` INSERT deny test (asserts `42501`, NOT `23503`). Use `randomUUID()` for all UUID columns per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`. Gated by `describe.skipIf(!INTEGRATION_ENABLED)` (`TENANT_INTEGRATION_TEST=1`). Cleanup via `afterAll` per `assertSynthetic` guard. |

## Pre-PR (separate branch, prerequisite)

**Not part of this PR-D plan.** Filed as a separate small infra PR from `main` before `/work` begins on PR-D.

Scope:
- New GitHub Actions workflow job (or extension to existing) exporting `TENANT_INTEGRATION_TEST=1`
- Doppler dev-Supabase secret wiring: `SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET` (per `cc-dispatcher.tenant-isolation.test.ts:33-50` requirements)
- Causes the 11 existing PR-C tenant-isolation tests to fire (currently silent-skipping in default CI)
- Closes #3869 item 6

The pre-PR is small (workflow YAML + Doppler config), infra-only, no code-domain review needed. Merge fast.

## Implementation Phases

### Phase 0 — Prerequisites & Sanity (no code changes)

- **0.1 Pre-PR merged.** Verify `gh issue view 3869 --json comments` shows item 6 closed AND the new CI tenant-isolation workflow is on `main`. Without this, PR-D's new tests silent-skip and the validation chain is broken.
- **0.2 Re-enumerate line refs.** At `/work` HEAD, run:
  ```bash
  grep -n "persistAndDownloadAttachments\|Migrated in PR-C" apps/web-platform/server/{cc-dispatcher,agent-runner,attachment-pipeline}.ts
  ```
  Update spec/plan line refs if drifted (this plan was written at commit `ce43e1f8`; HEAD may have moved).
- **0.3 Apply Phase 0 migrations locally** before any test work:
  ```bash
  cd apps/web-platform
  doppler run -p soleur -c dev -- bash scripts/run-migrations.sh
  ```
  Verify migrations 001-044 apply cleanly. Records baseline before Phase 1 adds 045.
- **0.4 SQL spike — `storage.foldername()` edge cases.** Connect to dev Supabase and run:
  ```sql
  SELECT
    storage.foldername('')        AS empty,
    storage.foldername('/x')      AS leading_slash,
    storage.foldername('a/')      AS trailing_slash,
    storage.foldername('a/b/c')   AS typical,
    storage.foldername('a/../b')  AS traversal;
  ```
  Expected per framework-docs research:
  - `empty` → `{}` → `[1]` NULL → predicate fails (good)
  - `leading_slash` → `{''}` → `[1] = ''` → predicate fails for any UUID (good)
  - `trailing_slash` → `{'a'}` → `[1] = 'a'` → predicate passes if 'a' = uid; **but filename is empty** — exploitable only if Storage API accepts empty filenames (unlikely; verify)
  - `typical` → `{'a','b'}` → `[1] = 'a'` (good)
  - `traversal` → `{'a','..'}` → `[1] = 'a'` → bucket-scoped, no escape
  
  Capture results in PR body. If `trailing_slash` is exploitable, Phase 1.2 adds a belt-and-suspenders `name LIKE auth.uid()::text || '/%'` check.
- **0.5 Backwards-compat orphan-path audit** (CLO requirement). Run against dev Supabase:
  ```sql
  SELECT count(*) AS orphan_count
  FROM message_attachments ma
  JOIN messages m ON m.id = ma.message_id
  WHERE (storage.foldername(ma.storage_path))[1] != m.user_id::text;
  ```
  If `orphan_count > 0`, document quarantine plan in PR body before proceeding. Block Phase 1 until decision agreed.
- **0.6 Sentinel sweep — hidden Storage byte-readers.** Run:
  ```bash
  rg -n "storage\.from\(['\"]chat-attachments" apps/web-platform
  rg -n "\.from\(['\"]message_attachments['\"]\)" apps/web-platform
  rg -n "createSignedUrl|createSignedUploadUrl|\.download\(|\.upload\(|\.move\(|\.copy\(|\.getPublicUrl\(" apps/web-platform/{server,app,lib}
  ```
  Expected matches (verified at plan time per Kieran P1-1):
  - `server/attachment-pipeline.ts:115, :141, :142` (PR-D migrates the download; INSERT covered by message_attachments INSERT policy)
  - `server/cc-dispatcher.ts:1435` (PR-D migrates)
  - `server/agent-runner.ts:2305` (PR-D migrates)
  - `app/api/attachments/presign/route.ts:94` (PERMANENT per NG1)
  - `app/api/attachments/url/route.ts:29` (PERMANENT per NG1)
  - `server/account-delete.ts:152` (PERMANENT per NG2)
  - `server/dsar-export.ts:515` (PERMANENT per NG2; list call)
  - `server/dsar-export.ts:602` (PERMANENT per NG2; download call — added per Kieran P1-1 verifier sweep)
  - `server/api-messages.ts:141` (read-only join through messages; RLS already covers, no change)
  
  Any UNEXPECTED match is a hidden byte-reader and must be classified (migrate / `// SERVICE-ROLE:` annotate / scope-out) before Phase 1. The expanded grep (`.move/.copy/.getPublicUrl`) catches future drive-by uses of mutation/public-URL verbs that earlier sweeps would miss.
- **0.4b GRANT presence check** (Kieran P3-2). Verify Postgres `authenticated` role has table-level grants the new policies depend on:
  ```sql
  SELECT
    has_table_privilege('authenticated', 'storage.objects', 'INSERT') AS storage_insert,
    has_table_privilege('authenticated', 'storage.objects', 'UPDATE') AS storage_update,
    has_table_privilege('authenticated', 'storage.objects', 'DELETE') AS storage_delete,
    has_table_privilege('authenticated', 'public.message_attachments', 'INSERT') AS ma_insert;
  ```
  All four MUST return `true`. If any returns `false`, the new policies are no-ops (RLS evaluates only after GRANT passes) — add corresponding `GRANT` statement to migration 045.
- **0.7 Acceptance check.** All 0.1-0.6 outputs captured in PR body. CPO sign-off confirmed (per `requires_cpo_signoff: true`). Block /work until done.

### Phase 1 — Migration (`045_attachments_storage_rls.sql`)

- **1.1 Create migration file.**
  ```sql
  -- 045_attachments_storage_rls.sql
  -- PR-D scope: close cross-tenant attachment read vector by adding the
  -- INSERT/UPDATE/DELETE Storage policies that migration 019 left out.
  -- Companion SELECT policy in 019 was load-bearing-but-bypassed before
  -- this PR; PR-D's call-site changes make it load-bearing.
  --
  -- Refs: #3244 (umbrella), #3854 (PR-C), #3869 items 4-5.

  -- 1. storage.objects INSERT/UPDATE/DELETE for chat-attachments bucket
  --
  -- FOR ALL with USING, NO WITH CHECK. Per 2026-04-18 learning: USING
  -- applies to writes when no WITH CHECK is specified. Adding
  -- WITH CHECK (true) here would silently disable tenant isolation on writes.
  CREATE POLICY "Users can write own attachment objects"
    ON storage.objects FOR ALL
    USING (
      bucket_id = 'chat-attachments'
      AND (storage.foldername(name))[1] = auth.uid()::text
    );

  -- 2. message_attachments INSERT for tenant client
  --
  -- Joins through messages → conversations → conversations.user_id.
  -- DELETE handled by FK ON DELETE CASCADE from messages; no explicit
  -- DELETE policy needed (provisional decision per brainstorm Open
  -- Question §3; follow-up issue if un-attach UX is requested).
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
- **1.2 Belt-and-suspenders predicate (CONDITIONAL).** If Phase 0.4 SQL spike showed `foldername('a/')` is exploitable, add to each policy USING/WITH CHECK:
  ```sql
  AND name LIKE auth.uid()::text || '/%'
  ```
  This ensures filename is non-empty (the path has content AFTER the user's folder prefix).
- **1.3 Migration comments.** Document the `FOR ALL USING` no-`WITH CHECK` decision inline. Cross-reference the 2026-04-18 learning by file basename. Document the FK-cascade rationale for skipping explicit DELETE policy.
- **1.4 Apply migration locally:**
  ```bash
  cd apps/web-platform
  doppler run -p soleur -c dev -- bash scripts/run-migrations.sh
  ```
  Verify migration 045 applies without error. Check policy presence:
  ```sql
  SELECT polname, polcmd FROM pg_policy WHERE polrelid IN (
    'storage.objects'::regclass, 'public.message_attachments'::regclass
  ) AND polname LIKE '%attachment%';
  ```
  Expect 3 policies (1 new on storage.objects, 1 new on message_attachments, 1 existing on storage.objects from migration 019).

### Phase 2 — Tenant-Isolation Integration Tests (NEW file)

These tests verify the RLS contract directly via tenant JWT; they do NOT depend on application code. They should pass as soon as Phase 1 migration is applied, regardless of Phase 3-6 state.

- **2.1 Create test file.** `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts`. Mirror `cc-dispatcher.tenant-isolation.test.ts` lines 1-50 for env gating, synthetic email pattern, `assertSynthetic`, `requireEnv`, `mintFounderJwt` import.
- **2.2 Cross-tenant Storage SELECT deny test.**
  ```typescript
  // Seed via service-role: Founder B uploads a file to her own folder
  const victimPath = `${userB.id}/${convB}/${randomUUID()}.png`;
  await service.storage.from("chat-attachments").upload(victimPath, fixture);
  // Attempt via Founder A's tenant client
  const { data, error } = await aClient.storage
    .from("chat-attachments")
    .download(victimPath);
  // RLS-deny shape: data === null (NOT an error from the API)
  expect(data).toBeNull();
  ```
  Per CTO §5: use real-shaped UUID path under victim folder (NOT malformed). `foldername` returns NULL on malformed input — false RLS-deny signal.
- **2.3 Same-tenant positive control.**
  ```typescript
  // Founder B downloads her own file successfully
  const { data: ownData } = await bClient.storage
    .from("chat-attachments")
    .download(victimPath);
  expect(ownData).not.toBeNull();
  ```
  Without this, deny tests pass for the wrong reason if seed/fixture is broken.
- **2.4 Cross-tenant `message_attachments` INSERT deny test.**
  ```typescript
  // Seed: Founder B has a message
  const messageB = randomUUID();
  await service.from("messages").insert({ id: messageB, conversation_id: convB, role: "user", content: "ok" });
  // Attempt: Founder A inserts a message_attachments row claiming messageB
  const { error: insertErr } = await aClient.from("message_attachments").insert({
    id: randomUUID(),
    message_id: messageB,
    storage_path: `${userA.id}/${convA}/spoof.png`,
    filename: "spoof.png",
    content_type: "image/png",
    size_bytes: 1,
  });
  // Assert RLS deny (42501), NOT FK violation (23503)
  expect(insertErr?.code).toBe("42501");
  ```
  Per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`: if `messageB` did not exist, the test would pass via FK-fail before RLS evaluates. Seeding messageB first ensures RLS is the load-bearing gate.
- **2.5 Cleanup.** `afterAll` removes synthetic users via `service.auth.admin.deleteUser` (cascades to conversations + messages + message_attachments via FKs). **Storage bytes do NOT cascade with FK** — `afterAll` MUST also call `service.storage.from("chat-attachments").remove([victimPath, ...])` for every seeded object. Mirror the remove pattern at `account-delete.ts:152`. Per gdpr-gate Phase 2.7 TS-05 finding.
- **2.6 Local test run.** `bun test apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` with `TENANT_INTEGRATION_TEST=1` and Supabase env vars set. All assertions pass.

### Phase 3 — Code migration (tenant client swap)

- **3.1 cc-dispatcher.ts:1435 swap.** **REUSE the existing `tenant` mint from `persistUserMessage` block at `cc-dispatcher.ts:1396-1410`** (Kieran P2-2: same userId in same turn; single RTT). Do NOT mint a second tenant client. Adapt:
  ```typescript
  let attachmentTenant: Awaited<ReturnType<typeof getFreshTenantClient>>;
  try {
    attachmentTenant = await getFreshTenantClient(userId);
  } catch (mintErr) {
    reportSilentFallback(mintErr, {
      feature: "cc-dispatcher",
      op: "tenant-mint.persistAndDownloadAttachments",
      extra: { userId, conversationId },
    });
    throw mintErr;
  }
  // ... existing if (attachments && attachments.length > 0) block ...
  const { attachmentContext } = await persistAndDownloadAttachments({
    supabase: attachmentTenant,
    userId,
    conversationId,
    messageId,
    attachments,
  });
  ```
  Reuse `tenant` from the block at :1396-1410 (already in scope); pass it as `supabase: tenant` to `persistAndDownloadAttachments`. Kieran P2-2 frozen at plan time — do not mint a second client.
- **3.2 agent-runner.ts:2305 swap.** Same shape. Use existing local helper or mint fresh per call site.
- **3.3 Fix stale comment at agent-runner.ts:2300.** Current text falsely claims "SERVICE-ROLE: persistAndDownloadAttachments uses service-role for attachment-storage writes (signed URL plumbing). Migrated in PR-C alongside the rest of the attachment pipeline (spec §2.1.4)." Replace with:
  ```typescript
  // PR-D #3244 §2: tenant-client persistAndDownloadAttachments. Storage
  // RLS in migration 019 (SELECT) + 045 (INSERT/UPDATE/DELETE) is now
  // load-bearing; the application-layer path-prefix check at
  // attachment-pipeline.ts:83-86 is defense-in-depth.
  ```
- **3.4 Type check passes.** `bun run tsc -p apps/web-platform` returns clean.
- **3.5 Existing unit tests still pass.** `bun test apps/web-platform/test/cc-attachment-pipeline.test.ts` — the mocked Supabase chain in the test still satisfies the new tenant-client interface (both return `SupabaseClient`).

### Phase 4 — Sentry mirror on silent download failure

- **4.1 Add mirrorWithDebounce import to attachment-pipeline.ts.**
  ```typescript
  import { mirrorWithDebounce } from "@/server/observability";
  ```
- **4.2 Replace silent fallback at :139-149.**
  ```typescript
  const results = await Promise.allSettled(
    attachments.map(async (att) => {
      const { data: fileData, error: dlErr } = await supabase.storage
        .from("chat-attachments")
        .download(att.storagePath);

      if (dlErr || !fileData) {
        // PRESERVE the existing pino message string for operator-dashboard
        // continuity per 2026-05-13 helper-migration learning.
        log.error({ err: dlErr, storagePath: att.storagePath }, "Failed to download attachment");
        // Mirror to Sentry with debounce (per-(userId, errorClass) 5-min
        // TTL) — attachment download failures are per-(user, attachment)
        // high-cardinality post-PR-D (RLS denial on orphan paths, expired
        // signed URLs, storage outages). Raw reportSilentFallback would
        // flood Sentry quota.
        mirrorWithDebounce(
          dlErr,
          {
            feature: "attachment-pipeline",
            op: "storage.download",
            extra: { userId, conversationId, storagePath: att.storagePath, messageId },
            message: "Failed to download attachment",
          },
          userId,
          "attachment_download_failed",
        );
        return null;
      }
      // ... existing file-write logic ...
    })
  );
  ```
  Partial-success semantics unchanged: per-file failure still returns `null` and is omitted from `attachmentContext`.
- **4.3 No double-mirror check.** Verify cc-dispatcher's outer dispatch catch does NOT also mirror per-attachment failures. The attachment helper's failures are file-level (don't bubble); the outer catch handles aggregate failures. Confirmed at plan time via cc-dispatcher.ts:1430 comment ("no inner try/catch — that would double-mirror and bypass the dispatch debounce").
- **4.4 Message-string regression guard.** Per DHH review (mock theater cut) + 2026-05-13 helper-migration learning: add ONE assertion to existing `test/cc-attachment-pipeline.test.ts` that on download-failure, the pino `log.error` call still carries the literal `"Failed to download attachment"` message string. This is the operator-dashboard regression guard; broader mirror-call-shape coverage lives in the Phase 2 integration tests (RLS contract end-to-end). Do NOT add `vi.mock("@/server/observability")` mock theater — testing the mock provides no real signal.

### Phase 5 — UI permanent-skeleton fix

- **5.1 Edit `apps/web-platform/components/chat/attachment-display.tsx`.** Add state:
  ```typescript
  const [loadFailed, setLoadFailed] = useState(false);
  ```
- **5.2 Replace `.catch(() => {})`** at the existing fetch site:
  ```typescript
  .then((data) => {
    if (data?.url) {
      cache.set(att.storagePath, { url: data.url, expiresAt: Date.now() + 50 * 60_000 });
      setUrl(data.url);
    } else {
      // Server returned 200 but no URL — treat as load failure
      reportSilentFallback(null, {
        feature: "attachments",
        op: "url-fetch",
        message: "Attachment URL response missing url field",
      });
      setLoadFailed(true);
    }
  })
  .catch((err) => {
    reportSilentFallback(err, {
      feature: "attachments",
      op: "url-fetch",
      message: "Attachment URL fetch failed",
    });
    setLoadFailed(true);
  });
  ```
  Use `reportSilentFallback` from `@/lib/client-observability` (NOT `@/server/observability`). NO `userId` in extras — client `ClientExtra` brands it `never`. Canonical example: `message-bubble.tsx:254`.
- **5.3 Render fallback affordance** when `loadFailed === true`:
  ```typescript
  if (loadFailed) {
    return (
      <div className="rounded-lg border border-soleur-border-error bg-soleur-bg-surface-2 p-3 text-sm">
        <p className="text-soleur-text-secondary">Preview unavailable.</p>
        <button
          type="button"
          onClick={() => { setLoadFailed(false); cache.delete(att.storagePath); /* triggers re-fetch via existing useEffect */ }}
          className="mt-1 text-soleur-text-accent underline"
        >
          Retry
        </button>
      </div>
    );
  }
  ```
  Microcopy: "Preview unavailable." + "Retry". Minimal, no brand-voice concern (skip copywriter per Phase 2.5 ADVISORY decision).
- **5.4 Smoke test via Playwright.** At /work Phase 6 (browser test), navigate to a conversation with an attachment, simulate `/api/attachments/url` returning 4xx, assert "Preview unavailable" + "Retry" button render. Click Retry, assert re-fetch attempt.
- **5.5 Type check.** `bun run tsc` clean.

### Phase 6 — Allowlist shrink (single atomic commit)

Per PR-C Phase 4 precedent + brainstorm Decision #8.

**Internal phase order is load-bearing per Kieran P2-4: sweep BEFORE commit, not after.** The naive 6.1→6.2→6.3→6.4 order can break the build (allowlist removed + residual unannotated `supabase()` survives in cc-dispatcher = CI fails post-commit). Correct order: 6.1 (remove block in working tree) → 6.4 (sweep cc-dispatcher for residuals) → 6.3 (run allowlist-check locally) → 6.2 (commit).

- **6.1 Remove lines 78-84** from `apps/web-platform/.service-role-allowlist`. The block:
  ```
  # PERMANENT (pending PR-D attachments review) — server/cc-dispatcher.ts:1421
  # passes service-role into persistAndDownloadAttachments({supabase: supabase()})
  # for attachments-storage I/O. Tenant migration of attachments depends on
  # storage RLS work scheduled for PR-D (tracked in plan §"Tracked Deferrals").
  # The 3 tenant data sites (BYOK lease wrap + 2 messages.insert) migrated
  # in PR-C §2.11.
  apps/web-platform/server/cc-dispatcher.ts
  ```
- **6.2 Single atomic commit:** `git commit -m "feat(runtime): shrink allowlist 14 → 13 (PR-D §6)"`. Separate from Phase 1-5 commits so security-owner CODEOWNERS review focuses on this single change.
- **6.3 Verify allowlist enforcement passes.** Run the CI allowlist-check script locally; confirm cc-dispatcher.ts is no longer required to be on the allowlist.
- **6.4 Sentinel sweep on cc-dispatcher.ts.** Any residual `createServiceClient()` or `supabase()` (the cached service-role helper) MUST carry `// SERVICE-ROLE: <reason>` annotation per `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`. Phase 0.6 sweep results determine this.

### Phase 7 — Article 30 PA2 amendment

- **7.1 Edit `knowledge-base/legal/article-30-register.md`.** Locate PA2 (Conversation Data) row at lines ~54-67. Amend:

  **(c) Categories of personal data** — append:
  > Additionally: `message_attachments` rows (filename, content-type, size, storage_path) and user-uploaded file content in the private `chat-attachments` Storage bucket (image: PNG/JPEG/GIF/WebP; PDF up to 24 MB — content may incidentally contain personal data and Art. 9 special-category data the user chooses to upload).
  
  **(g) TOMs** — append:
  > Attachment-storage isolation: per-user folder prefix `${userId}/${conversationId}/` enforced via Storage RLS policy `(storage.foldername(name))[1] = auth.uid()::text` (migration 019 SELECT, migration 045 INSERT/UPDATE/DELETE — load-bearing post-PR-D #3244); defense-in-depth application-layer path-prefix validation in `apps/web-platform/server/attachment-pipeline.ts:83-86`; content-type allowlist via `ALLOWED_ATTACHMENT_TYPES`; filename sanitisation (strip C0/DEL + U+2028/U+2029 + path separators; cap 255); uploads via service-role presigned URL (`createSignedUploadUrl`) with conversation-ownership verification at presign route.
  
  **(f) Retention** — append:
  > Storage objects cascade-delete with `message_attachments` row (FK ON DELETE CASCADE on `message_id`), which cascades from `messages` (FK ON DELETE CASCADE on `conversation_id`), which cascades from conversation/account deletion via Art. 17 erasure cascade.

- **7.2 NOT a new PA12.** Attachments are sub-objects of a conversation: same lawful basis Art. 6(1)(b), same controller, same retention cascade. Adding a new PA would over-fragment the register.

### Phase 8 — Post-merge ack-gated `supabase db push` (operator)

**Per `hr-menu-option-ack-not-prod-write-auth` and `2026-05-15-operator-only-step-canonical-list.md`.** Cannot be automated — explicit ack required per command.

- **8.1 After PR-D merges to main**, operator runs from `apps/web-platform`:
  ```bash
  doppler run -p soleur -c prd -- bash scripts/run-migrations.sh
  ```
  Per-command ack required (this is the canonical post-merge migration apply per the supabase-migrations runbook).
- **8.2 Verify migration 045 applied:** REST probe via Supabase MCP `list_migrations` (or psql `SELECT * FROM supabase_migrations.schema_migrations WHERE version = '045';`).
- **8.3 Verify policies present** in prod:
  ```sql
  SELECT polname FROM pg_policy WHERE polrelid IN (
    'storage.objects'::regclass, 'public.message_attachments'::regclass
  ) AND polname LIKE '%attachment%';
  ```
  Expect 3 policies.
- **8.4 Read-only prod verification** (Kieran P1-2 fix — do NOT create synthetic users in prod; conflicts with `hr-dev-prd-distinct-supabase-projects` and risks DSAR/billing/support visibility from `tenant-isolation-*@soleur.test` accounts). Two checks:
  1. **Policy presence + shape via `pg_policy`** (same as 8.3, with shape assertion):
     ```sql
     SELECT polname, polcmd, polqual IS NOT NULL AS has_using, polcheck IS NULL AS no_with_check
     FROM pg_policy
     WHERE polrelid = 'storage.objects'::regclass
       AND polname = 'Users can write own attachment objects';
     ```
     Expect 1 row with `polcmd='*'` (FOR ALL), `has_using=true`, `no_with_check=true`. The `no_with_check=true` assertion locks in the no-WITH-CHECK decision against future drive-by regression.
  2. **Dry-run RLS predicate eval via `set role authenticated; set request.jwt.claims = ...`** with a synthetic-uuid `sub` claim — verify SELECT against a non-existent path returns 0 rows (RLS-deny) without creating any prod data:
     ```sql
     BEGIN;
     SET LOCAL ROLE authenticated;
     SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}';
     SELECT count(*) FROM storage.objects
     WHERE bucket_id = 'chat-attachments'
       AND (storage.foldername(name))[1] = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
     -- Expect 0
     ROLLBACK;
     ```
     Confirms the RLS predicate evaluates correctly under tenant-JWT shape WITHOUT creating any prod auth.users or Storage objects. Integration suite stays dev-only (per AC25).
- **8.5 Close #3869 items 4-5.** Edit body to mark items resolved.

### Phase 9 — File PR-E confirmation + AUP follow-up + compound (post-merge)

- **9.1 Confirm PR-E tracking issue #3887** has correct labels (`domain/engineering`, `priority/p3-low`, `type/feature`, `deferred-scope-out`). Add a comment confirming PR-D merged and PR-E is unblocked. CLO advisory carried forward.
- **9.2 File AUP follow-up issue** (gdpr-gate Art. 9 §1). Inline `gh issue create --title "legal: Acceptable Use Policy review for chat-attachments Art. 9 incidental upload warning (post-PR-D)" --label "domain/legal,priority/p3-low,type/improvement" --body "Follow-up from PR-D gdpr-gate finding. Confirm AUP/ToS warns users not to upload Art. 9 special-category data..."`. Not an AC per DHH review — execute inline at this phase.
- **9.3 Compound + ship.** Run `/soleur:compound` to capture learnings; `/soleur:ship` Phase 5.5 preflight.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** Pre-PR for CI tenant-isolation job merged on main (closes #3869 item 6); workflow exports `TENANT_INTEGRATION_TEST=1` with Doppler dev-Supabase secrets wired.
- [ ] **AC2.** Migration `apps/web-platform/supabase/migrations/045_attachments_storage_rls.sql` exists; applies cleanly via `doppler run -p soleur -c dev -- bash scripts/run-migrations.sh`; adds 2 policies (`storage.objects FOR ALL` + `message_attachments FOR INSERT`).
- [ ] **AC3.** Migration comment explains the no-`WITH CHECK` decision with reference to `2026-04-18-rls-for-all-using-applies-to-writes.md`.
- [ ] **AC4.** Phase 0.4 SQL spike output is in PR body. If `foldername('a/')` is exploitable, belt-and-suspenders predicate `name LIKE auth.uid()::text || '/%'` is added to both policies.
- [ ] **AC5.** Phase 0.5 orphan-path audit query output = 0 OR quarantine plan agreed in PR body.
- [ ] **AC6.** `cc-dispatcher.ts:1435` and `agent-runner.ts:2305` use `getFreshTenantClient(userId)`. Mint wrapped in try/catch + `reportSilentFallback` per PR-C precedent.
- [ ] **AC7.** Stale `agent-runner.ts:2300` comment replaced (no longer claims "Migrated in PR-C").
- [ ] **AC8.** Phase 0.6 sentinel sweep output in PR body. Any UNEXPECTED `.storage.from("chat-attachments")` / `message_attachments` write site is classified.
- [ ] **AC9.** `attachment-pipeline.ts:139-149` calls `mirrorWithDebounce(err, ctx, userId, "attachment_download_failed")` with `ctx.message === "Failed to download attachment"` (preserve operator-dashboard message string).
- [ ] **AC10.** Unit test `test/cc-attachment-pipeline.test.ts` asserts `mirrorWithDebounce` called with exact `feature`, `op`, `errorClass`, `extra.userId`, `message` values.
- [ ] **AC11.** New file `test/server/attachment-pipeline.tenant-isolation.test.ts` exists. Cross-tenant Storage SELECT deny test asserts `expect(data).toBeNull()`. Cross-tenant `message_attachments` INSERT deny test asserts `expect(insertErr?.code).toBe("42501")` (NOT `"23503"`). Same-tenant positive control included. Uses `randomUUID()` for UUID columns **including `message_id` — seeding messageB first ensures FK passes so RLS (not FK violation) is the load-bearing gate** (Kieran P2-3). Gated by `describe.skipIf(!INTEGRATION_ENABLED)`. **Policy-shape test:** also assert `pg_policy.polcheck IS NULL` and `polqual IS NOT NULL` for the new storage.objects policy — codifies the no-WITH-CHECK decision against future drive-by regression per Kieran P3-1.
- [ ] **AC12.** Tests fire under CI (NOT silent-skipping) once AC1 pre-PR merged.
- [ ] **AC13.** `attachment-display.tsx` renders "Preview unavailable" + "Retry" affordance on fetch failure. `.catch(() => {})` replaced with `reportSilentFallback` + `setLoadFailed(true)`. NO `userId` in client extras (`ClientExtra` brands it `never`).
- [ ] **AC14.** `.service-role-allowlist` lines 78-84 removed (PR-D-pending block + cc-dispatcher.ts entry). 14 → 13 PERMANENT entries.
- [ ] **AC15.** Allowlist shrink lands as a single dedicated commit (separate from Phase 1-5 commits) per PR-C precedent.
- [ ] **AC16.** `knowledge-base/legal/article-30-register.md` PA2 amendment present: (c) Categories adds chat-attachments + message_attachments + Art. 9 incidental; (g) TOMs adds Storage RLS + path-prefix + content-type allowlist + filename sanitisation; (f) Retention adds FK cascade chain.
- [ ] **AC17.** PR description includes brand-survival-threshold matrix from `## User-Brand Impact` and the three vectors from brainstorm.
- [ ] **AC18.** Multi-agent review runs at **PR-ready-for-review** (not draft): architecture-strategist + security-sentinel + data-integrity-guardian + **user-impact-reviewer** (mandatory per `single-user incident` threshold). Verification rule (Kieran P2-1): every P1 finding blocks merge until resolved inline OR scoped-out with explicit rationale in PR body referencing the finding ID; P2/P3 findings documented in PR body but do not block.
- [ ] **AC19.** Type check passes: `bun run tsc -p apps/web-platform`.
- [ ] **AC20.** Local TENANT_INTEGRATION_TEST=1 test run against **dev Supabase**: all assertions pass.
- [ ] **AC20a.** DSAR smoke test against dev: operator triggers synthetic DSAR export for a test user with ≥1 attachment; verify all attachment bytes returned (Kieran P3-3 — promoted from post-merge AC25a per gdpr-gate DL-04 finding; catching NG2 regression in dev before prod migration apply).
- [ ] **AC21.** `gdpr-gate` skill invoked against the migration delta (Phase 7); output in PR body or linked file.
- [ ] **AC22.** PR title uses `Ref #3244 / Closes #3869` (NOT auto-close `Closes #3244` — umbrella stays open until PR-E lands).

### Post-merge (operator)

- [ ] **AC23.** `doppler run -p soleur -c prd -- bash scripts/run-migrations.sh` executed; migration 045 applied to prod with per-command ack.
- [ ] **AC24.** Prod policy presence verified via `pg_policy` query.
- [ ] **AC25.** Prod RLS verified via read-only checks (Kieran P1-2 — NO synthetic-user creation in prod):
  (a) `pg_policy` policy-shape assertion (`polcmd='*'` FOR ALL, `polqual IS NOT NULL`, `polcheck IS NULL`) per Phase 8.4 step 1.
  (b) Dry-run RLS predicate eval inside `BEGIN; SET LOCAL ROLE authenticated; SET LOCAL "request.jwt.claims"; SELECT count(*) ...; ROLLBACK;` per Phase 8.4 step 2.
  Full integration suite (with synthetic auth.users + Storage objects) stays DEV-only per AC20 + `hr-dev-prd-distinct-supabase-projects`.
- [ ] **AC26.** `gh issue edit 3869 --body-file -` updates body to mark items 4-5 as resolved.
- [ ] **AC27.** Comment posted on #3887 (PR-E tracking) confirming PR-D merged.
<!-- AC28 + AC29 removed per DHH + Simplicity review consensus.
     AC28 (stale-comment sweep) was speculative beyond Phase 3.3's known site;
     AC29 (AUP follow-up issue) is filed inline at Phase 9.2, not gated as an AC. -->


## Test Scenarios

| Scenario | Test file | Assertion shape |
|---|---|---|
| Cross-tenant Storage SELECT deny | `test/server/attachment-pipeline.tenant-isolation.test.ts` | `expect(data).toBeNull()` (RLS returns null, not error) |
| Same-tenant Storage SELECT success | same file | `expect(data).not.toBeNull()` (positive control) |
| Cross-tenant message_attachments INSERT deny | same file | `expect(err?.code).toBe("42501")` (RLS, NOT 23503 FK violation) |
| Same-tenant message_attachments INSERT success | same file | `expect(err).toBeNull()` |
| mirrorWithDebounce called on download failure | `test/cc-attachment-pipeline.test.ts` | Vitest mock of `@/server/observability` |
| Partial-success preserved | `test/cc-attachment-pipeline.test.ts` (extend existing) | One attachment fails, others succeed; `attachmentContext` includes survivors |
| UI permanent-skeleton replaced | Playwright e2e at /work Phase 6 | Click retry button; verify re-fetch attempt |

## Risks

| Risk | Mitigation |
|---|---|
| **R1. `storage.foldername()` edge case undiscovered.** `foldername('a/')` returning `{'a'}` could be exploitable if Storage API accepts empty filenames. | Phase 0.4 SQL spike + API-layer non-empty filename probe before Phase 1 freezes. Belt-and-suspenders `name LIKE auth.uid()::text || '/%'` predicate available if needed. |
| **R2. Orphan paths in prod.** Pre-PR-D attachments uploaded under a path that doesn't start with `{userId}/` (early prototype, dev-seed leaked, support upload). | Phase 0.5 audit query blocks Phase 1 until orphan_count = 0 or quarantine plan agreed. |
| **R3. Migration mandates without wired call sites.** Allowlist shrink lands but a residual `supabase()` call survives in cc-dispatcher.ts unannotated. CI allowlist-check then fails. | Phase 6.4 sentinel sweep on cc-dispatcher.ts AFTER Phase 3 swap; any residual gets `// SERVICE-ROLE:` annotation. |
| **R4. Test silent-skip.** New tests in `test/server/*.tenant-isolation.test.ts` skip in CI because pre-PR (#3869 item 6) didn't merge yet. | AC1 hard-blocks PR-D until pre-PR is on main. |
| **R5. Sentry quota burn from RLS rejections.** Post-PR-D, an orphan-path attachment triggers per-(user, attachment) Sentry events. | `mirrorWithDebounce(..., userId, "attachment_download_failed")` coalesces per-(user, errorClass) at 5-min TTL. |
| **R6. Double-mirror in cc-dispatcher dispatch catch.** Outer dispatch catch ALSO routes through `mirrorWithDebounce`; risk of duplicate emit. | Phase 4.3 verifies cc-dispatcher catch path doesn't double-mirror the per-attachment failures (already handled at file level). |
| **R7. agent-runner.ts:2305 sibling drift.** Plan was written at HEAD `ce43e1f8`; mid-flight commits could shift line numbers. | Phase 0.2 re-enumerates line refs; spec line refs are advisory. |
| **R8. Pre-PR scope creep.** The "small" pre-PR balloons into a CI redesign. | Pre-PR scope frozen: workflow YAML + Doppler secrets only. Anything else → separate issue. |
| **R9. Article 30 amendment regresses gdpr-gate.** New PA2 language fails gdpr-gate's RLS-coverage matrix or cross-tenant attestation. | Phase 7 includes `gdpr-gate` invocation before PR ready-for-review. |
| **R10. CPO sign-off missed.** Plan ships to `/work` without explicit CPO confirmation despite `requires_cpo_signoff: true`. | Phase 0.7 hard-gates `/work` on CPO ack (operator confirms via comment on draft PR #3883 or in this thread). |

## Hypotheses

N/A — this is a tenant-isolation migration, not a debugging plan. The CTO + CLO + CPO assessments in the brainstorm constitute the "hypothesis space"; this plan implements the consensus approach.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO) — carry-forward from brainstorm `## Domain Assessments`. No fresh assessment.

### Engineering (CTO) — carry-forward

**Status:** reviewed (brainstorm Phase 0.5)
**Assessment:** Storage SELECT RLS already exists; gap is INSERT/UPDATE/DELETE on `storage.objects` + INSERT on `message_attachments`. Single PR + post-merge ack-gated `db push` per PR-B precedent. Keep API routes PERMANENT (signed URLs bypass RLS by design). Use real-shaped UUID paths in deny tests, NOT malformed.

### Legal (CLO) — carry-forward

**Status:** reviewed (brainstorm Phase 0.5)
**Assessment:** Brainstorm's framing claim of pre-existing PA1/PA2 attachment row is false; PA2 amendment in PR-D closes a present Art. 30 gap. Tenant DPA register empty — no impact. Backwards-compat orphan-path audit MUST run pre-merge (AC5). gdpr-gate fires at Phase 7 with concrete migration delta.

### Product (CPO) — carry-forward

**Status:** reviewed (brainstorm Phase 0.5)
**Assessment:** 0 beta users — blast radius bounded; ship-day risk is structural prep for Phase 4 recruitment. No banner/disclosure. UI permanent-skeleton bug is highest-probability post-launch defect — fix inline (Phase 5). Productize candidate: `soleur:tenant-migrate-call-site` skill captured for post-merge `/compound`.

### Product/UX Gate

**Tier:** advisory
**Decision:** skipped — user-confirmed; brainstorm CPO §2 already assessed
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (minor affordance addition; brainstorm CPO assessment sufficient), copywriter (not recommended by any domain leader; microcopy is two short literals)
**Pencil available:** N/A

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled per brainstorm carry-forward.
- The two callers of `persistAndDownloadAttachments` are NOT the only Storage I/O sites — Phase 0.6 sentinel sweep is mandatory; presign/url routes + account-delete + dsar-export stay PERMANENT (NG1/NG2).
- Test deny payloads MUST use real-shaped UUID paths (NOT malformed) — `foldername()` returns NULL on bad input, producing false RLS-deny signals per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`.
- Migration `045` is committed FIRST in the PR sequence (Phase 1 before Phase 3 code swap), so a partial cherry-pick or revert leaves prod in a defensible state (policies exist, no client uses them = zero functional change). DO NOT reorder Phase 1 after Phase 3.
- Use the canonical migration command `doppler run -p soleur -c <env> -- bash scripts/run-migrations.sh`. The runbook EXPLICITLY forbids `npx supabase db push`.
- `ClientExtra` brands `userId/user_id/email` as `never` — client-side Sentry mirror in `attachment-display.tsx` MUST NOT pass userId in extras. Compile-time guard.
- `mirrorWithDebounce` is correct for per-(user, attachment) high-cardinality storage failures; raw `reportSilentFallback` would flood Sentry quota post-PR-D when orphan-path RLS rejections fire on every conversation.
- PR-E (audit_byok_use + is_jti_denied) MUST land before 2nd hosted founder or GA exposure per CLO advisory carried forward in #3887.
- `#3660` is a DIFFERENT "PR-D" (chat-RAIL transcript-hardening track, parent #3603). Do not conflate.
- Allowlist shrink in Phase 6 lands as a SEPARATE atomic commit so security-owner CODEOWNERS review focuses on that single change.

## References

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-16-pr-d-attachments-storage-tenant-rls-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/feat-pr-d-attachments-storage-tenant-rls/spec.md`
- **PR-C plan (precedent):** `knowledge-base/project/plans/2026-05-15-feat-pr-c-sibling-query-migration-plan.md`
- **Supabase migrations runbook:** `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
- **Existing migration:** `apps/web-platform/supabase/migrations/019_chat_attachments.sql`
- **Article 30 register:** `knowledge-base/legal/article-30-register.md` (PA2 lines 54-67)
- **Canonical test shape:** `apps/web-platform/test/server/cc-dispatcher.tenant-isolation.test.ts:33-50, 121-134`
- **Existing unit test (extend):** `apps/web-platform/test/cc-attachment-pipeline.test.ts`
- **Client observability helper:** `apps/web-platform/lib/client-observability.ts`
- **Server observability helper:** `apps/web-platform/server/observability.ts` (mirrorWithDebounce + reportSilentFallback)
- **Canonical client mirror precedent:** `apps/web-platform/components/chat/message-bubble.tsx:254`

### Learnings cited

- `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md` — motivating IDOR
- `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md` — test-payload trap
- `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md` — GRANT mismatch via vitest mocks
- `knowledge-base/project/learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md` — FOR ALL USING semantics
- `knowledge-base/project/learnings/2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md` — atomic migration+code
- `knowledge-base/project/learnings/2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` — phase ordering when contract changes
- `knowledge-base/project/learnings/2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md` — `mirrorWithDebounce` vs `reportSilentFallback` choice
- `knowledge-base/project/learnings/2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md` — preserve message string
- `knowledge-base/project/learnings/2026-05-15-operator-only-step-canonical-list.md` — post-merge db push framing
- `knowledge-base/project/learnings/2026-05-06-cap-coupling-between-adjacent-prs.md` — counter-evidence to splitting
- `knowledge-base/project/learnings/2026-05-16-brainstorm-verify-register-citations-and-adjacent-silent-failures.md` — this session's learning
