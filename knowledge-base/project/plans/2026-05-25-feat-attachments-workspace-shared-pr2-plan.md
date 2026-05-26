---
date: 2026-05-25
feature: attachments-rls-bundle-pr2-4318
brainstorm: knowledge-base/project/brainstorms/2026-05-25-attachments-workspace-shared-pr2-bundle-brainstorm.md
spec: knowledge-base/project/specs/feat-attachments-rls-bundle-pr2-4318/spec.md
issue: "#4318"
parent_issue: "#4233"
pr: "#4417 (draft)"
branch: feat-attachments-rls-bundle-pr2-4318
worktree: .worktrees/feat-attachments-rls-bundle-pr2-4318/
predecessor_prs:
  - "#4345 / mig 067 (PR-1 session invalidation)"
  - "#3883 / mig 045 (PR-D attachments tenant RLS)"
  - "#4289 (controllership disclosure)"
  - "#4351 (DSAR Art. 15(4) author-only redaction)"
brand_survival_threshold: single-user incident
lane: cross-domain
requires_cpo_signoff: true
status: ready-for-review
---

# Plan — PR-2 attachments workspace-shared (Storage layer)

## Overview

Switch the `chat-attachments` Supabase Storage bucket from **user-folder-keyed** to **workspace-co-member-readable** so that, once `TEAM_WORKSPACE_INVITE_ENABLED` flips ON, User B can download attachments uploaded by User A on shared conversations — without leaking cross-workspace, without widening writes to other users' folders, and without leaving a lingering uploader-PII window on member removal.

Deliverables in this PR:
1. **Migration 068** — split the mig 045 `FOR ALL` policy into separate `SELECT` (widened) and `INSERT/UPDATE/DELETE` (kept narrow). The widened SELECT derives `workspace_id` from the path's conversation segment via a SECURITY DEFINER helper and calls `is_workspace_member(workspace_id, auth.uid())`.
2. **API-layer co-membership widening** — `presign/route.ts` conversation-ownership check and `url/route.ts` SSRF guard both widen from owner-only to workspace-co-member.
3. **Account-delete cascade addition** — pseudonymise `messages.user_id` (NOT `message_attachments.uploader_user_id` — see Reconciliation R-2) for messages with attachments in shared-workspace conversations the controller retains.
4. **Workspace-member-removal cascade** — apply the same pseudonymisation step in `removeWorkspaceMember` flow (NOT in spec; see Reconciliation R-5).
5. **DSAR + account-delete Storage list operations** — enumerate workspace-scoped paths, not `chat-attachments/{userId}/`.
6. **Article 30 PA-2 amendment** — §(c), §(d), §(g)(10) rewrites; new §(g) pre-merge orphan-path audit TOM; lawful-basis annotation in mig 068 header.
7. **Tenant-isolation tests + migration-shape lint** — real-shaped UUIDs; positive control + dual-shape deny; predicate-clause + write-narrowing assertions.

Ships behind `TEAM_WORKSPACE_INVITE_ENABLED` (currently OFF in prd). Zero behaviour change in prd until flag flip. UX uploader-attribution work is filed as a separate issue that gates the flag flip.

## Research Reconciliation — Spec vs. Codebase

The brainstorm and spec each contain claims that did not survive Phase 1 verification. **All ten are load-bearing for correctness.** Each row below is the plan's authoritative response.

| # | Source claim | Codebase reality | Plan response |
|---|---|---|---|
| **R-1** | Brainstorm Decision 3 / spec FR1: predicate `is_workspace_member(((foldername)[1])::uuid, auth.uid())`. | `(storage.foldername(name))[1]` is the path's **first segment**. Current path shape is `{userId}/{conversationId}/{uuid}.{ext}` (kept under Decision 4). So `(foldername)[1] = userId`, not `workspace_id`. `is_workspace_member(p_workspace_id, p_user_id)` would be called with `(uploaderUserId, currentUser)` — type-correct but semantically wrong; returns `false` almost always → **fails closed, feature dead**. | **Corrected predicate** uses `(foldername)[2]` (conversationId) joined via a new SECURITY DEFINER helper `public.is_attachment_path_workspace_member(p_user_id uuid, p_conversation_id uuid) RETURNS boolean` that resolves `conversations.workspace_id` and calls `public.is_workspace_member(workspace_id, p_user_id)`. See Implementation Phase 2. |
| **R-2** | Brainstorm Decision 6 / spec FR2: pseudonymise `message_attachments.uploader_user_id` to `member_<hex12>`. | Verified via `apps/web-platform/supabase/migrations/019_chat_attachments.sql:20-28` — `message_attachments` schema is `(id, message_id, storage_path, filename, content_type, size_bytes, created_at)`. **No uploader column exists.** Author identity is reachable only transitively via `message_id → messages.user_id`. | **FR2 retargeted** to pseudonymise `messages.user_id` (the message that owns the attachment) where `EXISTS (SELECT 1 FROM message_attachments WHERE message_id = m.id)` AND `conversations.workspace_id IN (departing-user's shared workspaces)` AND `conversations.user_id ≠ departing user`. See Phase 4. |
| **R-3** | Brainstorm Decision 4: "No `WITH CHECK` added (preserve mig 045 lines 54-60 invariant per `2026-04-18-rls-for-all-using-applies-to-writes.md`)." | Mig 045 is `FOR ALL USING (...)` with NO `WITH CHECK`. Per the cited learning, `FOR ALL USING` governs **both reads and writes**. Widening USING widens write-eligibility — co-members would gain ability to write into other users' folders, contradicting the brainstorm's Decision 4 intent. The cited learning is about avoiding `WITH CHECK (true)` (the regression); it does NOT prohibit a constraining `WITH CHECK`. | **Split the policy.** Replace the single `FOR ALL` with two policies: (a) SELECT widened to allow co-member reads via the helper from R-1; (b) `INSERT, UPDATE, DELETE` kept narrow to `(foldername)[1] = auth.uid()::text`. This matches mig 045's intent (own-folder writes) while widening reads. See Phase 2. |
| **R-4** | Brainstorm + spec: silent-failure inventory enumerates `account-delete.ts:175` and `dsar-export.ts:1198`. | **FOUR** additional silent-failure surfaces exist beyond the brainstorm's two: (i) `app/api/attachments/presign/route.ts:76-83` `.eq("user_id", user.id)` conv-ownership check; (ii) `app/api/attachments/url/route.ts:24` `startsWith(\`${user.id}/\`)` SSRF guard; (iii) `apps/web-platform/server/attachment-pipeline.ts:91,149` uses `pathPrefix = \`${userId}/${conversationId}/\`` validation but the actual download uses tenant-JWT supabase — RLS now widens but no API-layer fallback if a future caller bypasses RLS; (iv) `apps/web-platform/server/agent-runner.ts:569` reads `message_attachments` joined to `messages` using `createServiceClient()` (RLS-bypassed) — no API-layer co-membership check exists between service-role and attachment bytes (architecture P0-3 + user-impact F5 + Kieran P1-10 convergence). | **Add FR7 (presign widening), FR8 (url-route widening), FR10 (service-role surfaces inventory).** Both routes (i)(ii) inline a `service.from("conversations").select("workspace_id, user_id").eq("id", conversationId).single()` lookup + `is_workspace_member` check (NO new shared TS helper file — DHH/CS/A converge on inline; do not create `attachment-co-membership.ts`). Routes (iii)(iv) get a per-call-site assertion derived from the same SQL helper as the storage policy. All four sites `reportSilentFallback` on cutover-related denies. See Phase 3 + Phase 3.5. |
| **R-5** | Spec FR2: cascade addition lives only in `account-delete.ts`. | A **distinct code path** exists: `app/api/workspace/remove-member/route.ts` → `apps/web-platform/server/workspace-membership.ts:238-298` calls `service.rpc("remove_workspace_member", ...)` (mig 067 `:117-206`). The PG RPC is an **atomic SECURITY DEFINER body** that INSERTs `workspace_member_removals` then DELETEs from `workspace_members` in one transaction — **TS-side cannot insert a "before DELETE" hook**. Currently no pseudonymisation of `messages.user_id` happens on member removal — same lingering-uploader-PII window the brainstorm flagged. | **Add FR9 (workspace-member-removal cascade) — TWO RPCs, not one.** Mig 068 (a) creates a private internal helper `_anonymise_authored_messages_internal(p_user_id uuid, p_workspace_id uuid)` (workspace-scoped; called by both public RPCs); (b) creates `public.anonymise_departed_user_across_workspaces(p_user_id uuid)` for account-delete (iterates the user's workspaces and calls the internal helper for each); (c) **AMENDS `public.remove_workspace_member`** to call the internal helper INSIDE its atomic body BEFORE the workspace_members DELETE — this is the only way to keep the membership row visible to the pseudonymisation predicate (architecture P0-1). See Phase 4. |
| **R-6** | Brainstorm/spec: cascade insertion "between 3.92 (`anonymise_workspace_member_attestations`) and 3.93 (`anonymise_workspace_members`)". | Actual numbering in `apps/web-platform/server/account-delete.ts` is: 3.90 attestations → 3.905 removals → 3.91 members → 3.92 org-membership → 3.93 member-actions. Brainstorm/spec numbering is wrong by one step. | **Insert between 3.90 (`anonymise_workspace_member_attestations`) and 3.905 (`anonymise_workspace_member_removals`)**, numbered **3.901**. Rationale: must run before 3.91 (`anonymise_workspace_members` DELETEs membership rows; if the membership row goes first, `is_workspace_member` queries inside the new RPC return false and the pseudonymisation skips). |
| **R-7** | Brainstorm Decision 6: reuse pseudonym shape `member_<hex12>` "consistent with PR #4351". | `pseudonymiseUserId` in `apps/web-platform/server/dsar-export.ts:175-180` is **per-bundle salt-scoped** (`randomBytes(32)` held in closure, never persisted, used for one DSAR export and discarded). PR #4351 is DSAR export-side redaction, NOT in-place DB pseudonymisation. Reusing the function as-is would produce different pseudonyms on every cascade invocation (different salt each time), breaking referential integrity if multiple removals happen across time. | **Mint pseudonym at SQL layer** inside the new RPC using `encode(gen_random_bytes(6), 'hex')` → `'member_' || <hex12>`. Per-row random hex; collision-safe at the row scope (we're writing the pseudonym INTO the row, not joining on it). Document salt-lifecycle decision: pseudonym is row-local, never joined cross-row. |
| **R-8** | Spec TR2: "`is_workspace_member(uuid, uuid)` qualified as `public.is_workspace_member(...)`". | Re-verified at `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:139-140`: mig 053:139 REVOKEs from `PUBLIC, anon, authenticated, service_role` (**all four**, per `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` — explicit role-list defeats default-privileges); mig 053:140 GRANTs EXECUTE back to `authenticated` only. Mig 063 re-GRANTs `service_role` (per `063_post_workspace_rpc_repair.sql:114`). The new helper `is_attachment_path_workspace_member` is called from the storage policy (under `authenticated` JWT role); the new cascade RPC is called from `account-delete.ts` (under `service_role`) AND from inside `remove_workspace_member` (which is itself `SECURITY DEFINER` invoked under `authenticated`). Two different GRANT matrices. | **Mig 068 grants — helper:** `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ... TO authenticated`. **Mig 068 grants — cascade RPC:** `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ... TO service_role` (account-delete) PLUS the inner call from `remove_workspace_member` works through SECURITY DEFINER chain (the caller's grant matters, not the callee's). Verify with `has_function_privilege` probes in Phase 6 ack-prompt. Mirrors `2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` + `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`. |
| **R-9** | Brainstorm + repo-research: "No existing storage.objects policy in-repo invokes a SECURITY DEFINER helper — first-of-kind precedent." | Confirmed via grep on `storage.foldername` and `storage.objects` — mig 019, 042, 045 all use raw `(storage.foldername(name))[1] = auth.uid()::text`. No precedent invokes a helper. | **Phase 0.4 spike (load-bearing):** apply mig 068 to a local Supabase instance (via `supabase db reset`); insert two fixture conversations across workspaces W1/W2; insert one storage.object per workspace; execute `SELECT name FROM storage.objects WHERE bucket_id='chat-attachments'` under tenant JWTs for User A (member of W1) and User B (member of W2). Expected: A sees W1's object only; B sees W2's only. If the SECURITY DEFINER helper does not resolve from storage policy context, the plan aborts and switches to inline SQL in the policy body (no helper). |
| **R-10** | Brainstorm OQ#3: workspace-deletion may orphan Storage objects. | Verified FK chain via mig 053/059: `workspaces.id` referenced by `workspace_members.workspace_id ON DELETE RESTRICT`, `conversations.workspace_id ON DELETE RESTRICT`, `messages.workspace_id ON DELETE RESTRICT`. **Workspace cannot be deleted today.** Even hypothetically, `storage.objects` has no FK to `message_attachments` → physical deletion of message_attachments rows orphans Storage objects (separate system). | **OQ#3 resolution: confirm as gap, file follow-up — do NOT include in PR-2.** Workspace deletion is a non-flow today (RESTRICT chain). Storage cleanup on workspace deletion belongs to a future Enterprise-tier issue. File as **blocking-pre-flag-flip** issue (per gdpr-gate AC-NEW) so the gap is not silently inherited at flag flip. |

## User-Brand Impact

(Carried forward from brainstorm. CPO sign-off required at plan time per `requires_cpo_signoff: true` in frontmatter.)

**If this lands broken, the user experiences:** an attachment uploaded by a co-member in a shared conversation either (a) fails to load with a permanent skeleton placeholder (silent-deny → `.catch(() => {})` swallow), or (b) is accessible to a user in a different workspace altogether (cross-workspace leak — Art. 33 notification surface).

**If this leaks, the user's data is exposed via:** the `chat-attachments` bucket SELECT predicate evaluating in a way that the path's conversation segment resolves to a workspace the requesting user is not a member of — most likely via a malformed UUID fail-open, a missing JOIN filter, or a `SECURITY DEFINER` helper that resolves to the function owner's privileges and ignores the caller's tenancy.

**Brand-survival threshold:** `single-user incident`.

**Sign-off lifecycle staging:**
- Brainstorm phase: CTO + CLO + CPO all assessed in parallel (carried forward).
- Plan phase: **CPO sign-off required** before `/work`. Confirm CPO has reviewed the brainstorm `## Domain Assessments` section AND this Reconciliation table (especially R-1, R-3, R-5).
- Review phase: `user-impact-reviewer` mandatory in the 5-agent panel.
- Ship phase: preflight Check 6 verifies this section is present and threshold valid.

## Research Insights

### Verified file:line references

- **Mig 045 bucket predicate** (TR1 down.sql restore target): `apps/web-platform/supabase/migrations/045_attachments_storage_rls.sql:54-60` — `CREATE POLICY "Users can write own attachment objects" ON storage.objects FOR ALL USING (bucket_id = 'chat-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);` (no `WITH CHECK`).
- **Mig 045 helper** (`is_message_owner` original): `045:87-109` — `SECURITY DEFINER`, `search_path = public, pg_temp`, plpgsql (not sql, to defeat planner inlining). GRANT EXECUTE to `authenticated`; REVOKE from PUBLIC/anon/service_role at `045:111-112`.
- **Mig 059 workspace widening**: `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql:416-447` — `is_message_owner` now checks `is_workspace_member(m.workspace_id, p_user_id)`. **Caveat (load-bearing):** the comment at line 444 says "all 045-era callers inherit transparently" but this applies to `message_attachments` table policies, NOT the `storage.objects` policy (which uses the path directly, no helper call). This is exactly the residual gap PR-2 closes.
- **`is_workspace_member` helper**: `053:115-140`. Signature `(p_workspace_id uuid, p_user_id uuid) RETURNS boolean`. `SECURITY DEFINER`, `search_path` pinned. GRANT EXECUTE to `authenticated` (053:140) + `service_role` (063:114).
- **Mig 060 JWT claim**: claim path is `claims.app_metadata.current_organization_id` (NOT `current_workspace_id`). **Plan does not depend on this claim** for the storage policy — the policy derives workspace from the path's conversation segment, not the JWT. JWT claim remains unused in PR-2.
- **`message_attachments` schema**: `apps/web-platform/supabase/migrations/019_chat_attachments.sql:20-28`. No uploader column. `message_id` is `ON DELETE CASCADE`. See R-2.
- **Account-delete cascade structure**: `apps/web-platform/server/account-delete.ts:400-591`. Actual step numbering: 3.90 / 3.905 / 3.91 / 3.92 / 3.93. See R-6.
- **Pseudonym minter (DSAR-scope only)**: `apps/web-platform/server/dsar-export.ts:175-180`. See R-7.
- **Tenant-isolation test fixture**: `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` exists; pattern is two-distinct-user (not shared-workspace); imports `randomUUID` from `node:crypto`. Will extend.
- **`__ALICE__` sentinel**: `apps/web-platform/test/dsar-author-redaction.integration.test.ts:80-84` — present, but used only in `createSharedWorkspaceMembers(service, 3)` (line 93) which substitutes real UUIDs at runtime. Confirms a reusable shared-workspace fixture pattern exists.
- **Article 30 PA-2**: `knowledge-base/legal/article-30-register.md:54-68`. PA-2 already covers workspace co-member co-visibility at line 67; PR-2 amends §(c), §(d), §(g)(10) and adds new §(g) TOM.
- **Migration-shape lint precedent**: `apps/web-platform/test/supabase-migrations/067-workspace-member-revocation-lookup.test.ts` — reuse exact structure.
- **Mig 068 is next free slot.** Last 5: 064, 064 (twin), 065, 066, 067.
- **Test runner**: `vitest` (NOT `bun test` — `apps/web-platform/bunfig.toml` `pathIgnorePatterns = ["**"]` blocks bun discovery per #1469).

### Relevant learnings (top 10, all verified to exist)

| Learning | Why it applies |
|---|---|
| `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md` | Test fixtures must use `crypto.randomUUID()`, not sentinels. Drives TR9 + AC-NEW test-sentinel lint. |
| `security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md` | R-3: `FOR ALL USING` governs writes. Drives the policy split. |
| `security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md` | API-layer prefix/contentType validation in `agent-runner.ts` and `attachment-pipeline.ts` must NOT be removed when widening the bucket predicate. |
| `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md` | `hr-write-boundary-sentinel-sweep-all-write-sites` — enumerate every `storage.from("chat-attachments")` callsite post-cutover. |
| `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md` | The cascade step MUST ship in this PR, not as a follow-up. |
| `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md` | Cascade insertion at 3.901 must verify no FK + WORM-trigger deadlock on `messages` UPDATE. |
| `2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md` | PA-2 amendment prose must be `grep`-validated against the actual mig 068 body. |
| `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` | Prd migration apply requires explicit confirmation with full SQL text, not a menu-ack. |
| `2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` | GRANT/REVOKE matrix on `is_workspace_member` — verify EXECUTE for `authenticated` survives. |
| `2026-05-10-plan-time-reviewer-orthogonality-for-security-sensitive-plans.md` | At single-user-incident threshold, 5-agent panel with union-of-cuts + intersection-of-P1-hardening. |

## Phase 0 — Preconditions and Open Questions

Resolve before writing any code in Phase 2+.

### 0.1 — Verify worktree and branch (mechanical)

- `git rev-parse --abbrev-ref HEAD` inside the worktree returns `feat-attachments-rls-bundle-pr2-4318`.
- Run `bun install` (or repo-canonical install) so `vitest` is available.

### 0.2 — Resolve brainstorm Open Questions

| OQ | Resolution path |
|---|---|
| **OQ1** — prd `chat-attachments` object count | Query via Supabase MCP against prd: `SELECT COUNT(*) FROM storage.objects WHERE bucket_id = 'chat-attachments';` AND `SELECT COUNT(*) FROM storage.objects WHERE bucket_id = 'chat-attachments' AND (storage.foldername(name))[2] !~ '^[0-9a-f-]{36}$';` (segment-2 conversation-id-shape audit per Kieran P1-5 — non-zero rows go invisible post-mig-068). Record actual counts in Phase 0 worklog. Expected: small (jikigai-only, no multi-user workspaces in prd). |
| **OQ2** — `current_workspace` JWT claim availability | **Resolved by plan design.** Plan does NOT use the JWT claim for storage policy; policy derives workspace from path's `(foldername)[2]` (conversationId) via `conversations.workspace_id`. JWT claim avoidance also dodges the per-presign round-trip latency concern. Record "not needed" in worklog. |
| **OQ3** — Workspace-deletion cascade to Storage objects | **Resolved as confirmed gap.** Workspace can't be deleted today (RESTRICT chain — see R-10). Even hypothetically, `storage.objects` has no FK cascade. **Do NOT include in PR-2.** File pre-flag-flip blocking issue `chore: storage-object lifecycle on workspace deletion (blocks TEAM_WORKSPACE_INVITE_ENABLED flag flip)` with label `compliance/blocker` and link to this PR AND link from the Flagsmith flag description (per architecture P0-4). |
| **OQ4** — DSAR Art. 15 coverage of cross-uploader attachments | **Resolved via gdpr-gate DL-04 finding.** Default-include co-member uploads in shared conversations, REDACT bytes, manifest shape `{filename, size, uploader_pseudonym, redacted: true, redaction_reason: "art-15-co-uploader"}`. Bumps DSAR manifest schema 1.1.0 → 1.2.0 (**forward-compatible:** absence of `redacted` field means "not redacted" per architecture P1-4; document in manifest schema comment). Verified against PR #4351 author-only redaction precedent. CLO sign-off captured in Phase 0 worklog. |
| **OQ5** — Orphan-path audit query shape | **Pinned:** `SELECT COUNT(*) FROM storage.objects WHERE bucket_id = 'chat-attachments' AND ((storage.foldername(name))[1] IS NULL OR (storage.foldername(name))[1] !~ '^[0-9a-f-]{36}$' OR (storage.foldername(name))[2] IS NULL OR (storage.foldername(name))[2] !~ '^[0-9a-f-]{36}$');`. Non-zero blocks merge per FR6 + AC4. |

### 0.2b — Critical pre-Phase-2 data integrity probes (added by review panel)

These MUST all pass before Phase 2 begins. Any non-zero result reshapes the plan.

| Probe | SQL | Required result | Source |
|---|---|---|---|
| **PROBE-A** — `messages.workspace_id` NULL backfill complete | `SELECT COUNT(*) FROM public.messages WHERE workspace_id IS NULL;` against prd | `0` | user-impact F10 — otherwise the cascade RPC's `p_workspace_id IS NULL` branch pseudonymises pre-mig-059 cross-workspace messages over-broadly (irreversible). If non-zero, mig 068 RPC's `WHERE` clause MUST add `AND m.workspace_id IS NOT NULL`. |
| **PROBE-B** — Segment-2 conversation-id-shape | `SELECT COUNT(*) FROM storage.objects WHERE bucket_id='chat-attachments' AND ((storage.foldername(name))[2] IS NULL OR (storage.foldername(name))[2] !~ '^[0-9a-f-]{36}$');` | `0` | Kieran P1-5 — non-zero rows become invisible post-mig-068 (segment-2 regex deny). |
| **PROBE-C** — Migration slot collision | `ls apps/web-platform/supabase/migrations/068_*.sql` | empty (no collisions) | Kieran P0-4 — race-collision if another PR landed a 068. |
| **PROBE-D** — `messages` WORM trigger | `grep -rn "CREATE TRIGGER.*messages\|tg_messages_worm" apps/web-platform/supabase/migrations/` | empty OR carve-out pattern documented | R-Risk-3 / Kieran P1-8. If trigger exists, RPC UPDATE body MUST encode `to_jsonb minus column equality` carve-out per `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md`. |

### 0.3 — Resolve Reconciliation R-9 (load-bearing spike)

Apply the mig 068 DRAFT against a local Supabase instance and prove the SECURITY DEFINER helper resolves from storage policy context:

1. `cd apps/web-platform && supabase db reset`
2. Apply DRAFT mig 068 (initial helper + split policy).
3. Insert fixture: 2 workspaces (W1, W2), 2 users (Alice ∈ W1, Bob ∈ W2), 1 conversation per workspace, 1 storage.object per workspace under `{userId}/{convId}/test.png`.
4. Mint two tenant JWTs (Alice's, Bob's) using the local Supabase test signing key.
5. Run `SELECT name FROM storage.objects WHERE bucket_id = 'chat-attachments';` under each JWT.
6. **Expected:** Alice sees W1's object only; Bob sees W2's only. Workspace co-member fixture (Alice + Carol both in W1): both see W1's object.
7. **If helper does not resolve from storage context:** abort plan, switch to inline SQL in the policy body (lift the helper logic into the policy). Document the empirical learning at `knowledge-base/project/learnings/2026-05-25-storage-policies-cannot-invoke-security-definer.md`.

### 0.4 — Verify `messages` WORM-trigger compatibility (R-6 follow-up)

Per `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md`, check whether `messages` carries a WORM `BEFORE UPDATE` trigger. If yes, the new RPC's UPDATE of `messages.user_id` must:
- Use the `to_jsonb minus column equality` carve-out pattern, OR
- Be allowlisted on a specific column-set the WORM trigger accepts.

Command: `grep -rn "CREATE TRIGGER.*messages\|WORM.*messages\|tg_messages_worm" apps/web-platform/supabase/migrations/`. If a trigger exists, design the carve-out into the RPC body before Phase 4.

### 0.5 — Run the storage.foldername edge-case spike

Per PR-D plan's spike framework. Test against local Supabase:
- `(storage.foldername(''))[1]` → expected `NULL`
- `(storage.foldername('a'))[1]` → expected `NULL` or `''` (path has no `/`)
- `(storage.foldername('a/'))[1]` → expected `'a'`
- `(storage.foldername('a/../b'))[1]` → expected `'a'` (no path normalisation)
- `(storage.foldername('a/b/c.png'))[2]` → expected `'b'`

Document exact behaviour. The mig 068 predicate's regex `~ '^[0-9a-f-]{36}$'` MUST short-circuit before the `::uuid` cast on NULL inputs. Postgres `NULL ~ '...'` returns `NULL`, which `AND` short-circuits to false (deny) — verify empirically.

### 0.6 — CPO sign-off acknowledgement

Brand-survival = `single-user incident`. Before Phase 2, the operator (or CPO via brainstorm carry-forward) confirms:
- This plan's Reconciliation section has been read end-to-end.
- R-1 (predicate semantics), R-3 (write widening hole), R-5 (member-removal flow gap) are accepted.
- The OQ#3 deferral with blocking-pre-flag-flip issue is acceptable.

## Implementation Phases

**Phase ordering note (review-applied):** Legal-prose amendment lives at **Phase 6.5** (after the SQL is final), per DHH P0-4 + code-simplicity P0-4 convergence — drafting prose against unfinalised SQL invites drift; let the SQL settle, then grep-validate the prose against the actual body per `2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md`.

### Phase 2 — Migration 068 (storage RLS predicate widening + policy split)

Files to create:
- `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.sql`
- `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.down.sql`

#### Migration body shape

The entire body MUST be wrapped in `BEGIN; ... COMMIT;` (per user-impact F8 — mid-apply DROP-then-CREATE window otherwise leaves the bucket default-denied). The repo's `web-platform-release.yml#migrate` runs `psql -1` which already enforces single-transaction; the migration body itself states the boundary explicitly for documentation + standalone `psql` correctness.

```sql
BEGIN;

-- LAWFUL_BASIS: Art. 6(1)(b) workspace collaboration contract +
--               Art. 6(1)(f) shared-asset retention legitimate interest.
-- See knowledge-base/legal/article-30-register.md PA-2.

-- 1. New helper: derive workspace_id from a conversation-id path segment
--    and check membership. SECURITY DEFINER so it can read conversations.
--    plpgsql (not sql) to defeat planner inlining per mig 045 precedent.
--    Param order matches established convention (id-first, user-second)
--    per Kieran P0-3 — mirrors is_workspace_member(workspace_id, user_id)
--    and is_message_owner(message_id, user_id).
CREATE OR REPLACE FUNCTION public.is_attachment_path_workspace_member(
  p_conversation_id uuid,
  p_user_id         uuid
) RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_workspace_id uuid;
BEGIN
  IF p_conversation_id IS NULL OR p_user_id IS NULL THEN
    RETURN false;
  END IF;
  SELECT workspace_id INTO v_workspace_id
    FROM public.conversations
    WHERE id = p_conversation_id;
  IF v_workspace_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN public.is_workspace_member(v_workspace_id, p_user_id);
END;
$$;

-- REVOKE list mirrors mig 045 precedent (all four roles) to defeat
-- ALTER DEFAULT PRIVILEGES per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md
REVOKE ALL ON FUNCTION public.is_attachment_path_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_attachment_path_workspace_member(uuid, uuid)
  TO authenticated;

-- 2. Drop the mig 045 FOR ALL policy and replace with split SELECT + write.
DROP POLICY IF EXISTS "Users can write own attachment objects" ON storage.objects;

-- 2a. SELECT: widened to allow workspace co-member reads.
CREATE POLICY "Users read own + co-member attachment objects"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'chat-attachments'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR (
        (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
        AND public.is_attachment_path_workspace_member(
          ((storage.foldername(name))[2])::uuid,
          auth.uid()
        )
      )
    )
  );

-- 2b. INSERT/UPDATE/DELETE: kept narrow to own-folder (mig 045 invariant).
CREATE POLICY "Users write own attachment objects only"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Users update own attachment objects only"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
CREATE POLICY "Users delete own attachment objects only"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

COMMENT ON POLICY "Users read own + co-member attachment objects" ON storage.objects IS
  'Read-path widened per #4318 / mig 068. Co-member visibility derived from '
  'conversations.workspace_id via is_attachment_path_workspace_member(). '
  'Writes are governed by the sibling FOR INSERT/UPDATE/DELETE policies — '
  'do NOT collapse back to FOR ALL without re-reading '
  'security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md.';

-- (Phase 4 RPC definitions follow here — see Phase 4 section.)

COMMIT;
```

The down.sql wraps in `BEGIN; ... COMMIT;`, drops the four new policies, drops the helper + two cascade RPCs, restores mig 067's `remove_workspace_member` body verbatim, and recreates the mig 045 `FOR ALL USING` policy.

### Phase 3 — API-layer co-membership widening (presign + url routes)

**Per DHH P0-2 + code-simplicity P0-1 + architecture P1-1 convergence: DO NOT create `attachment-co-membership.ts`. Inline the conversation lookup at each route.**

Files to edit:
- `apps/web-platform/app/api/attachments/presign/route.ts:76-83` (conv-ownership check)
- `apps/web-platform/app/api/attachments/url/route.ts:14-30` (SSRF guard)

**Presign route (lines 76-83) replacement shape (inline, ~7 lines):**

```ts
// Verify conversation read-eligibility (own OR workspace co-member)
const { data: conversation } = await service
  .from("conversations")
  .select("id, user_id, workspace_id")
  .eq("id", conversationId)
  .single();
if (!conversation) {
  return NextResponse.json({ error: "conversation_not_found" }, { status: 404 });
}
if (conversation.user_id !== user.id) {
  const { data: memberRow } = await service.rpc("is_workspace_member", {
    p_workspace_id: conversation.workspace_id,
    p_user_id: user.id,
  });
  if (!memberRow) {
    reportSilentFallback({ at: "presign-route", reason: "workspace_cutover_deny",
      userId: user.id, conversationId });
    return NextResponse.json({ error: "not_a_workspace_member" }, { status: 403 });
  }
}
```

**Url-route (line 24) replacement shape (inline, ~10 lines):** parse `storagePath` segments (`userId/conversationId/file`), early-accept own folder, else look up conversation by segment 2 and check `is_workspace_member`. Same `reportSilentFallback` shape.

Error code taxonomy: `404 conversation_not_found` | `403 not_a_workspace_member` | (legacy `403 unauthorized` for non-shared-conv malicious-path attempts).

### Phase 3.5 — Service-role surface inventory + assert (added by review panel)

Per architecture P0-3 + user-impact F5 + Kieran P1-10 + `hr-write-boundary-sentinel-sweep-all-write-sites`:

1. Run the sentinel sweep: `rg -n "storage\.from\(['\"]chat-attachments['\"]\)" apps/web-platform/`. Pin EVERY callsite in the Phase 3.5 worklog.
2. For every server-side callsite that USES `createServiceClient()` (RLS-bypassed) AND reads bytes (`.download(...)` / `.createSignedUrl(...)`), insert an explicit conversation-membership assertion derived from the requester's user context BEFORE the byte fetch. Known sites:
   - `apps/web-platform/server/attachment-pipeline.ts:149` (`.download(att.storagePath)`) — assert requester is the message owner or workspace co-member.
   - `apps/web-platform/server/agent-runner.ts:569` if/when it transitions to byte fetch (currently metadata-only; document the assertion site for the future).
   - `apps/web-platform/server/dsar-export.ts:1198+` Storage download seam — re-assert post-enumeration that each path's `(foldername)[2]` resolves to a conversation the DSAR requester participated in (architecture P1-5 final-defense layer).
3. AC: `rg "storage\.from\(['\"]chat-attachments['\"]\).*\.\(download\|createSignedUrl\)" apps/web-platform/server/` shows each match preceded (within 30 lines) by an explicit `assertReaderMayAccessAttachment(...)` call or equivalent inline check.

### Phase 4 — Cascade pseudonymisation (two public RPCs + shared internal + amended `remove_workspace_member`)

**Per architecture P0-1 + P0-2: SPLIT into two public RPCs sharing a private internal helper. The member-removal RPC MUST live inside `remove_workspace_member`'s atomic body (it can't be sequenced from TS).**

The mig 068 migration body adds these three SQL definitions (between sections 2 and the `COMMIT;` from Phase 2):

```sql
-- 3. Private internal helper. Performs the actual pseudonymisation
--    UPDATE; both public RPCs call this. Per-row pseudonym minted at
--    SQL layer via gen_random_bytes (NOT the DSAR TS minter — see R-7).
--    PROBE-A asserts messages.workspace_id IS NOT NULL across prd, so
--    no NULL-workspace_id fallback is needed; if PROBE-A is ever
--    non-zero post-deploy, this helper MUST add the NULL filter.
CREATE OR REPLACE FUNCTION public._anonymise_authored_messages_internal(
  p_departing_user uuid,
  p_workspace_id   uuid  -- single workspace; loops at the public-RPC layer
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated integer := 0;
  -- WORM-carveout pattern per 2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md
  -- only encoded here if PROBE-D found a WORM trigger on messages.
BEGIN
  IF p_departing_user IS NULL OR p_workspace_id IS NULL THEN
    RETURN 0;
  END IF;
  UPDATE public.messages AS m
     SET user_id = ('member_' || encode(gen_random_bytes(6), 'hex'))::uuid
     -- ↑ If users.id is uuid and messages.user_id is also uuid, the cast
     --   above is invalid. PRE-PHASE-4 verify column type and either:
     --   (a) widen messages.user_id to text in a sibling migration, OR
     --   (b) mint a deterministic-shaped uuid via uuid_generate_v5 on
     --       the (workspace, departing-user, message-id) tuple.
     --   The (b) path keeps types but loses the human-readable prefix.
   WHERE m.user_id      = p_departing_user
     AND m.workspace_id = p_workspace_id
     AND EXISTS (SELECT 1 FROM public.message_attachments ma
                  WHERE ma.message_id = m.id)
     AND EXISTS (SELECT 1 FROM public.conversations c
                  WHERE c.id = m.conversation_id
                    AND c.user_id <> p_departing_user);
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;
REVOKE ALL ON FUNCTION public._anonymise_authored_messages_internal(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
-- No public GRANT; only invoked from sibling SECURITY DEFINER RPCs.

-- 4. Public RPC for full account-delete: iterates the user's shared
--    workspaces and calls the internal helper for each. Emits Art. 17
--    erasure audit row per workspace touched.
CREATE OR REPLACE FUNCTION public.anonymise_departed_user_across_workspaces(
  p_departing_user uuid
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_total   integer := 0;
  v_one     integer;
  r         record;
BEGIN
  FOR r IN
    SELECT DISTINCT m.workspace_id
      FROM public.messages m
     WHERE m.user_id = p_departing_user
       AND m.workspace_id IS NOT NULL
  LOOP
    v_one := public._anonymise_authored_messages_internal(p_departing_user, r.workspace_id);
    v_total := v_total + v_one;
  END LOOP;
  RETURN v_total;
END;
$$;
REVOKE ALL ON FUNCTION public.anonymise_departed_user_across_workspaces(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.anonymise_departed_user_across_workspaces(uuid)
  TO service_role;

-- 5. AMEND public.remove_workspace_member (mig 067) to call the internal
--    helper inside its atomic body, BEFORE the DELETE FROM workspace_members.
--    This is the ONLY way to keep the membership row visible to the
--    pseudonymisation predicate (architecture P0-1). The mig 068 body
--    re-CREATEs the function with the helper call inserted between the
--    workspace_member_removals INSERT and the workspace_members DELETE.
--    The full re-CREATE body is required (Postgres has no "ALTER FUNCTION
--    BODY" — must redeclare).
CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid;
  v_org_id         uuid;
  v_rows           integer;
  v_anon_count     integer;  -- NEW (mig 068)
BEGIN
  -- (mig 067 body lines 117-169 verbatim — owner check, self-removal block,
  --  org-id resolve.)

  -- NEW (mig 068): pseudonymise authored messages in shared convs BEFORE
  -- the membership row is deleted, so is_workspace_member still returns
  -- true for the predicate. Per architecture P0-1.
  v_anon_count := public._anonymise_authored_messages_internal(p_user_id, p_workspace_id);
  -- Optional: emit a structured raise notice for ops visibility.

  -- (mig 067 body lines 170-183 verbatim — INSERT workspace_member_removals
  --  + DELETE workspace_members + return rows.)

  -- (mig 067 body lines 184-203 verbatim — session-state cleanup.)
  RETURN v_rows;
END;
$$;
-- GRANTs unchanged from mig 067:204-206.
```

**File edits (TS layer):**

- `apps/web-platform/server/account-delete.ts` — insert step **3.901** between 3.90 (`anonymise_workspace_member_attestations`) and 3.905 (`anonymise_workspace_member_removals`). Call `service.rpc("anonymise_departed_user_across_workspaces", { p_departing_user: userId })`. Match existing step shape: try/catch + structured log + abort-on-failure semantics. **Runtime ordering guard (architecture P1-3):** assert `(SELECT COUNT(*) FROM workspace_members WHERE user_id = $1) > 0` BEFORE invoking RPC; structured Sentry warning if zero (cascade-order regression detector).
- `apps/web-platform/server/workspace-membership.ts:238-298` — **no TS change required** for the cascade itself; the amended `remove_workspace_member` PG RPC now handles it atomically. Document this in the function's existing JSDoc block (the "Steps 1..3" comment around line 232) so future readers see that step 0 (pseudonymise) now lives inside the RPC.

### Phase 5 — Storage list widening (silent-failure inventory closeout)

Files to edit:
- `apps/web-platform/server/account-delete.ts:160-193` — `chat-attachments/{userId}/` list operation. **Decision (gdpr-gate Art. 17 framing):** on full account-delete, KEEP the user's own-uploaded objects in shared workspaces (controller retains per Art. 17 legitimate-interest carve-out); DELETE only objects in conversations owned by the departing user. Update the list operation to enumerate via `message_attachments` + `conversations.user_id = departing_user` join, not via `{userId}/` prefix.
- `apps/web-platform/server/dsar-export.ts:1193-1253` — `enumerateChatAttachments`. Widen to enumerate via `message_attachments` joined to conversations the requester participated in. Co-uploader files: include with byte redaction per gdpr-gate FR-NEW (manifest schema 1.1.0 → 1.2.0 with `redacted: true, redaction_reason: "art-15-co-uploader"`).
- `apps/web-platform/server/dsar-export.ts:175-180` — reuse `pseudonymiseUserId` for co-uploader identity in DSAR manifest (per-bundle salt-scoped is correct for DSAR's lifetime).
- **Architecture P1-5 final-defense layer**: post-enumeration in `dsar-export.ts`, BEFORE each `service.storage.from("chat-attachments").download(...)` call, re-assert `(foldername)[2]` (conversationId) resolves to a conversation the DSAR requester actually participated in (defense-in-depth against a join bug leaking unrelated bytes). Inline check; ~5 lines.

**Manifest schema 1.2.0 forward-compatibility (architecture P1-4):** new fields `redacted: bool, redaction_reason: string, uploader_pseudonym: string` are purely additive; 1.1.0 readers ignore unknown fields. Absence of `redacted` = "not redacted". Document this invariant inline in the manifest schema comment.

### Phase 6 — Tests + migration-shape lint

Files to create:
- `apps/web-platform/test/supabase-migrations/068-attachments-workspace-shared.test.ts` — mig-shape lint. Adopt structure from `067-workspace-member-revocation-lookup.test.ts`. Assertions:
  - (a) `068.sql` contains both policy clauses (`Users read own + co-member`, `Users write own attachment objects only` + UPDATE + DELETE siblings).
  - (b) UUID regex `~ '^[0-9a-f-]{36}$'` appears BEFORE the `::uuid` cast in the SELECT policy body.
  - (c) `068.down.sql` restores the mig 045 single `FOR ALL USING` policy verbatim (file-equality check on the canonical mig 045 snippet).
  - (d) NO `WITH CHECK (true)` anywhere in the migration body (anti-regression).
  - (e) `GRANT EXECUTE ... TO authenticated` present for the new helper + new RPC.
  - (f) `REVOKE ALL ... FROM PUBLIC, anon, service_role` present.

Files to extend:
- `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` — add (a) workspace co-member positive control (Bob in W reads Alice's attachment in shared conv X), (b) cross-workspace dual-shape deny (Bob in W1 reads Carol's attachment in W2: returns either `{data:null,error:<RLS-deny>}` or `{data:[],error:null}`), (c) NULL-foldername deny (root-level object), (d) corrupt UUID fail-closed (path with non-UUID first/second segment).
- `apps/web-platform/test/server/account-delete.integration.test.ts` (or sibling) — full-delete pseudonymisation test: User A authors a message with attachment in W's shared conv X (owned by B); A account-deletes; `SELECT user_id FROM messages WHERE id = X.message_id` returns a `member_<hex12>` pseudonym, and B's authored messages in the same conv remain untouched.
- `apps/web-platform/test/server/workspace-membership.integration.test.ts` — workspace-removal pseudonymisation test: same setup as above, but A is removed from W (not full delete); same pseudonymisation outcome on A's authored shared-conv messages; A's solo-workspace messages untouched.

All test fixtures use `crypto.randomUUID()` per TR9.

**Test files (extend existing siblings — code-simplicity P1-5):**
- Extend `apps/web-platform/test/server/account-delete.integration.test.ts` with a `describe("attachment cascade", ...)` block.
- Extend `apps/web-platform/test/server/workspace-membership.integration.test.ts` with a `describe("attachment cascade on member removal", ...)` block.

### Phase 6.5 — Article 30 PA-2 amendment + lawful-basis cross-validation (moved from Phase 1)

After the mig 068 SQL body is final and tests are green, edit `knowledge-base/legal/article-30-register.md` PA-2:

- **§(c)** append the co-member language from gdpr-gate Recommendation §4.
- **§(d)** replace per-user_id language with the dual-layer (mig 059 row + mig 068 storage) language.
- **§(g)(10)** rewrite TOM with new predicate + path-physical-stability framing + path-segment-userId Art. 17 disposition note.
- **§(g) new TOM** — pre-merge orphan-path audit (OQ5 query as documented TOM).

Lockstep:
- `docs/legal/data-protection-disclosure.md` (canonical)
- `plugins/soleur/docs/pages/legal/*` (Eleventy mirror — re-publish via existing build step)

**PA-2-vs-mig-068-body drift check (architecture-flagged operationalisation of `2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md`):** `grep -E 'is_attachment_path_workspace_member|conversations\.workspace_id|\(foldername\)\[2\]' apps/web-platform/supabase/migrations/068_*.sql` returns at least one match per technical claim made in PA-2 §(g)(10). AC10 enforces.

### Phase 7 — Apply

**Plan-vs-workflow reality (corrected from initial plan draft):** `.github/workflows/web-platform-release.yml#migrate` uses `doppler run -c prd -- bash run-migrations.sh` — there is **no dev-stage migration**; the release workflow applies mig 068 directly to prd on push to main with no separate operator ack between merge and apply. The plan's earlier "auto-apply to dev, ack-gated prd" framing did NOT match the workflow shape. Recorded here for downstream readers; the underlying gap (no dev rehearsal stage in the release pipeline) is filed as a separate follow-up against `web-platform-release.yml`.

- Single PR. Squash-merge.
- On merge: mig 068 auto-applies to prd via `web-platform-release.yml#migrate`.
- Post-apply verification runs automatically via `web-platform-release.yml#verify-migrations` (executes `run-verify.sh`). A `supabase/verify/068_*.sql` sentinel file (Phase 7.5) asserts the four new policies are present and the four new functions exist.
- Post-apply, run the orphan-path audit (OQ5 query) on prd. Non-zero opens a `compliance/critical` follow-up (does not retroactively block the merge but blocks `gh issue close 4318`).

## Files to Edit

| File | Why | Phase |
|---|---|---|
| `apps/web-platform/app/api/attachments/presign/route.ts` (lines 76-83) | R-4: inline conv-ownership widening; `reportSilentFallback` on cutover-deny | 3 |
| `apps/web-platform/app/api/attachments/url/route.ts` (lines 14-30) | R-4: inline SSRF guard widening | 3 |
| `apps/web-platform/server/attachment-pipeline.ts` (line 149 + surrounding) | R-4 / Phase 3.5: assert reader-may-access at service-role download seam | 3.5 |
| `apps/web-platform/server/agent-runner.ts` (line 569 area) | R-4 / Phase 3.5: document/insert byte-fetch assertion site | 3.5 |
| `apps/web-platform/server/account-delete.ts` (3.90↔3.905 boundary; lines 160-193 list op) | R-5 + R-6: insert step 3.901 with runtime ordering guard; widen Storage list enumeration | 4, 5 |
| `apps/web-platform/server/workspace-membership.ts:238-298` | JSDoc update only (RPC handles cascade atomically — no TS change required for cascade) | 4 |
| `apps/web-platform/server/dsar-export.ts` (lines 175-180, 1193-1253, manifest schema) | Phase 5: workspace-scoped enumeration; manifest 1.1.0 → 1.2.0 (forward-compatible); pre-download seam re-assertion | 5 |
| `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` | Add workspace co-member fixtures + dual-shape deny | 6 |
| `apps/web-platform/test/server/account-delete.integration.test.ts` (sibling extension) | Full-delete cascade pseudonymisation (`describe("attachment cascade")` block) | 6 |
| `apps/web-platform/test/server/workspace-membership.integration.test.ts` (sibling extension) | Member-removal cascade pseudonymisation block | 6 |
| `knowledge-base/legal/article-30-register.md` | PA-2 §(c)/§(d)/§(g)(10) amendments + new §(g) TOM | 6.5 |
| `docs/legal/data-protection-disclosure.md` | Canonical disclosure lockstep with PA-2 | 6.5 |
| `plugins/soleur/docs/pages/legal/*` (Eleventy mirror) | Re-publish mirror; no drift vs canonical | 6.5 |

## Files to Create

| File | Why | Phase |
|---|---|---|
| `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.sql` | Mig 068 (helper + split policy + 2 cascade RPCs + amended `remove_workspace_member`) | 2, 4 |
| `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.down.sql` | Idempotent restore of mig 045 predicate + mig 067 RPC + helper/RPC drops | 2 |
| `apps/web-platform/test/supabase-migrations/068-attachments-workspace-shared.test.ts` | Migration-shape lint | 6 |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200`:

- **#4355** (`fix(supabase): mig 065 063-workspace_member_actions workspace_id RESTRICT → SET NULL`) — mentions `account-delete.ts`. **Disposition: acknowledge.** Different concern (mig 065 cascade SET NULL for workspace_member_actions). PR-2 does not touch the workspace_member_actions cascade ordering; the two changes can land independently. No fold-in needed.

No matches on `dsar-export.ts`, `chat-attachments`, `attachments/presign`, or `url/route`.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO) — carried forward from brainstorm Phase 2.5.

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** narrow scope to Storage bucket layer + cascade; mig 059 already covered DB cascade. Plan refinement: R-1/R-3/R-4 widen scope to (a) corrected predicate via new helper, (b) policy split for write narrowing, (c) two additional API routes. CTO sign-off implicitly carried but recommend a quick CTO re-read of the Reconciliation section before Phase 2 begins.

### Legal (CLO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** controllership settled in PR #4289; no new disclosure modal. PR-2 owns the cascade for departed-member uploader pseudonymisation. PA-2 §(c)/§(d)/§(g)(10) edits + new TOM (orphan audit) + lawful-basis annotation on mig 068. **Additional from gdpr-gate (this plan):** R-10 → file blocking-pre-flag-flip issue for workspace-deletion orphan path with label `compliance/blocker`.

### Product (CPO)
**Status:** reviewed (brainstorm carry-forward) — **plan-time sign-off required per `requires_cpo_signoff: true`**
**Assessment:** zero multi-user workspaces in prd; PR-2 is structural prep for Phase 4 recruitment. UX uploader-attribution work filed as follow-up gating flag flip. **Plan-time CPO confirmation:** Reconciliation R-1/R-3/R-5 accepted; OQ#3 deferral with blocking-pre-flag-flip issue accepted.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — plan does not introduce new user-facing surfaces (no `components/**/*.tsx`, no `app/**/page.tsx`). UX work for attachment cards is a separate follow-up issue gating the flag flip. mechanical-escalation check: 0 new component files in `Files to Create`.
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

## GDPR / Compliance Gate

Advisory pass run inline (full output preserved at `/tmp/gdpr-gate-pr2-4318.txt` for the session; key findings folded in below). **Disclaimer:** advisory only; engage CLO + `legal-compliance-auditor` for binding review.

**Critical:** none (no Art. 9 schema-shape match; user-content controllership carve-out per PR #4289 applies to attachment content).

**Important findings folded into FR/AC:**
- **FR-NEW1 (lawful-basis annotation):** mig 068 SQL preamble carries `-- LAWFUL_BASIS: Art. 6(1)(b) + 6(1)(f)` header. → AC-NEW1.
- **FR-NEW2 (DSAR co-uploader bytes redaction):** Phase 5 manifest schema bump + redaction. → AC-NEW2.
- **FR-NEW3 (cascade scope guard):** RPC `WHERE` clause restricts to `conversations.user_id ≠ departing_user`. Test asserts co-member messages in departing-user-owned conv are untouched. → AC-NEW3.
- **FR-NEW4 (silent-fallback parity):** presign + url routes call `reportSilentFallback` on cutover-deny. → AC-NEW4.
- **AC-NEW5 (NULL-foldername fuzz):** mig-068 lint test fixture covers root-level object.
- **AC-NEW6 (sentinel lint):** new test files contain `crypto.randomUUID()`; no `__[A-Z]+__` literals (grep gate).
- **AC-NEW7 (path-segment user_id Art. 17 disposition):** PA-2 §(g)(10) documents the technical-identifier-only framing for path-encoded `{userId}` segment.
- **AC-NEW8 (OQ#3 deferral with tracking):** blocking-pre-flag-flip issue filed, labelled `compliance/blocker`, linked to this PR.
- **AC-NEW9 (CCPA disclosure check):** CLO confirms PR #4289 language covers CCPA §1798.140 "sharing" for workspace co-members; if gap, file ToS/AUP amendment as blocking-pre-flag-flip.

## Observability

```yaml
liveness_signal:
  what: Mig 068 RLS deny + cutover-deny audit log entries
  cadence: Per-request (storage policy eval + presign + url route)
  alert_target: Sentry (via reportSilentFallback) + Better Stack logs
  configured_in: cq-silent-fallback-must-mirror-to-sentry + apps/web-platform/server/attachment-co-membership.ts

error_reporting:
  destination: Sentry (workspace-cutover-deny tag) + structured log "anonymise_authored_messages_in_shared_conversations failed"
  fail_loud: yes (RPC failure aborts cascade per existing account-delete pattern; presign/url returns 403 with structured response, not silent skeleton)

failure_modes:
  - mode: SECURITY DEFINER helper resolves false-positive (cross-workspace read leak)
    detection: Tenant-isolation test cross-workspace dual-shape deny + monthly sentry query "RLS leak on chat-attachments"
    alert_route: Sentry P0 (single-user incident threshold)
  - mode: Helper resolves false-negative (legitimate co-member read denied)
    detection: reportSilentFallback at presign/url + Sentry tag "workspace_cutover_deny"
    alert_route: Sentry P1 (user-impact-reviewer scope)
  - mode: Cascade RPC partial failure (some messages pseudonymised, others not)
    detection: Integration test asserts COUNT(*) of pseudonymised rows matches expected; account-delete logs include "anonymise_authored_messages_in_shared_conversations" with returned count
    alert_route: Sentry P0 (Art. 17 erasure incomplete)
  - mode: Orphan-path post-deploy regression (new uploads land at non-UUID-shaped paths)
    detection: Daily cron variant of OQ5 query on prd (file as follow-up runbook addition, NOT blocking PR-2)
    alert_route: Sentry P2 + ops weekly review

logs:
  where: Better Stack via existing pino transport + Supabase Postgres logs for RPC failure
  retention: per existing retention policy (no new retention requirement)

discoverability_test:
  command: |
    curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/health
  expected_output: "200"
```

NO `ssh` in the discoverability command — single `curl` probe against the live origin's `/api/health` endpoint runs end-to-end through TLS + Cloudflare + Hetzner + Next.js + Supabase pooler. Structural verification (mig-shape lint, OQ5 orphan-path audit, function/policy presence) is encoded in `apps/web-platform/supabase/verify/068_attachments_workspace_shared.sql` which runs automatically via `web-platform-release.yml#verify-migrations` after every prd apply — no operator step.

## Acceptance Criteria

(Paper-AC trim applied per DHH P0-3 + code-simplicity P1-3: dropped AC11 baseline tsc/vitest/test-all, AC15 generic sentinel-grep folded into AC2/AC3 fixture spec.)

### Pre-merge (PR)

- **AC1**: Mig-shape lint test (`068-*.test.ts`) green: (a) both split policies present with correct USING / WITH CHECK shapes; (b) UUID regex `~ '^[0-9a-f-]{36}$'` precedes `::uuid` cast in the SELECT policy; (c) `068.down.sql` restores mig 045 single-`FOR ALL` policy and mig 067 `remove_workspace_member` body verbatim; (d) NO `WITH CHECK (true)` anywhere in mig 068 body; (e) `GRANT EXECUTE ... TO authenticated` for the helper AND `GRANT EXECUTE ... TO service_role` for `anonymise_departed_user_across_workspaces`; (f) REVOKE list includes all four roles `(PUBLIC, anon, authenticated, service_role)`; (g) mig 068 body wraps `BEGIN; ... COMMIT;`.
- **AC2**: Cross-workspace download in tenant-isolation test returns dual-shape deny `{data:null,error:<RLS-deny>}` OR `{data:[],error:null}`. Fixtures use `crypto.randomUUID()`, no `__[A-Za-z]+__` sentinels (case-insensitive; Kieran P1-11).
- **AC3**: Workspace co-member positive download succeeds in tenant-isolation test.
- **AC4**: PROBE-A (`messages.workspace_id IS NULL`) returns 0 on dev + prd. PROBE-B (segment-2 conversation-id shape) returns 0 on dev + prd. PROBE-C (slot collision) returns empty. PROBE-D documented.
- **AC5**: `account-delete.ts` step 3.901 invokes `anonymise_departed_user_across_workspaces` and integration test asserts: (a) departing user's user_id no longer appears on shared-conv messages with attachments, (b) co-member messages in same conv untouched, (c) departing user's solo-conv messages untouched, (d) **RPC executes atomically — failure mid-iteration leaves zero rows pseudonymised** (user-impact F4 atomicity assertion), (e) runtime ordering guard fires structured Sentry warning if `workspace_members` count = 0 at invocation time (architecture P1-3).
- **AC6**: Amended `public.remove_workspace_member` (mig 068 re-CREATE of mig 067 body) pseudonymises authored-with-attachments messages BEFORE deleting the membership row; integration test asserts pseudonymisation on workspace-removal flow with single-workspace scope.
- **AC7**: `dsar-export.ts` enumerates workspace-scoped paths; co-uploader manifest entries carry `redacted: true, redaction_reason: "art-15-co-uploader"`; manifest schema 1.2.0 (forward-compatible — comment documents the invariant); pre-download seam re-asserts conversation participation (architecture P1-5).
- **AC8**: `account-delete.ts` Storage list operation enumerates via `message_attachments` ⨝ `conversations.user_id = departing_user` join; retains shared-workspace objects under controller's Art. 17 carve-out.
- **AC9**: `presign/route.ts` + `url/route.ts` use inline conversation lookup + `is_workspace_member` check (no shared TS helper file); both call `reportSilentFallback({ at, reason: "workspace_cutover_deny", userId, conversationId })` on cutover-related denies; distinguished error codes (`404 conversation_not_found`, `403 not_a_workspace_member`); UI surface contract test asserts the deny renders a NON-skeleton state (user-impact F2/F3 recovery).
- **AC10**: `grep -E 'is_attachment_path_workspace_member|conversations\.workspace_id|\(foldername\)\[2\]' apps/web-platform/supabase/migrations/068_*.sql` returns ≥1 match per technical claim in PA-2 §(g)(10); canonical (`docs/legal/data-protection-disclosure.md`) and Eleventy mirror diff-clean against PA-2 prose.
- **AC11**: 5-agent `/soleur:review` panel at single-user-incident threshold (DHH + Kieran + code-simplicity + architecture-strategist + `user-impact-reviewer` + `spec-flow-analyzer`) passes per `2026-05-10-plan-time-reviewer-orthogonality-for-security-sensitive-plans.md` (union-of-cuts + intersection-of-P1-hardening).
- **AC12**: PR body uses **`Ref #4318`** (not `Closes`) per Kieran P1-7 — issue is closed post-merge by AC15 after AC14 passes. OQ#3 follow-up issue filed with label `compliance/blocker`, linked from PR body AND from the Flagsmith `TEAM_WORKSPACE_INVITE_ENABLED` description (architecture P0-4). UX uploader-attribution follow-up issue filed and linked.
- **AC13**: Sentinel sweep complete: `rg -n "storage\.from\(['\"]chat-attachments['\"]\)" apps/web-platform/server/` produces a worklog; every read-byte callsite under service-role is preceded by an explicit reader-may-access assertion (Phase 3.5).

### Post-merge (operator)

- **AC14**: Mig 068 auto-applied to dev via `web-platform-release.yml#migrate` on push to main; verified via Supabase MCP `SELECT polname FROM pg_policy WHERE polrelid = 'storage.objects'::regclass` returns four new policy names + `SELECT proname FROM pg_proc WHERE proname IN ('is_attachment_path_workspace_member','_anonymise_authored_messages_internal','anonymise_departed_user_across_workspaces','remove_workspace_member')` returns four rows.
- **AC15**: Mig 068 applied to prd via explicit ack-gated invocation: operator confirms with full SQL text including `BEGIN; ... COMMIT;` boundaries quoted in the ack prompt per `hr-menu-option-ack-not-prod-write-auth` (NOT menu-letter). Ack prompt also surfaces `has_function_privilege('authenticated', 'public.is_attachment_path_workspace_member(uuid,uuid)', 'EXECUTE')`, `has_function_privilege('service_role', 'public.anonymise_departed_user_across_workspaces(uuid)', 'EXECUTE')` verifications.
- **AC16**: Post-prd-apply, OQ5 orphan-path audit + PROBE-A + PROBE-B all return 0 rows on prd via Supabase MCP; non-zero blocks AC17.
- **AC17**: `gh issue close 4318 -r completed -c "Closed by PR #N (mig 068 — split storage RLS + cascade RPCs + amended remove_workspace_member). Predicate corrected per R-1; FR2 retargeted to messages.user_id per R-2; policy split per R-3; presign/url + service-role surfaces widened per R-4; member-removal cascade folded INTO remove_workspace_member per architecture P0-1."` AFTER prd apply succeeds AND AC16 passes.
- **AC18**: CLO confirms PR #4289 disclosure language covers CCPA §1798.140 "sharing" for workspace co-members; if gap, file ToS/AUP amendment as blocking-pre-flag-flip issue (does NOT block PR-2 merge — code-simplicity P1-6).

## Risks

- **R-Risk-1 (highest):** SECURITY DEFINER helper does not resolve from storage policy context (R-9 spike fails). Phase 0.4 detects; mitigation is to inline the helper logic into the storage policy body (lose the abstraction, keep semantics). If the inline form also fails, the only remaining option is to denormalise `workspace_id` onto a join key the storage policy can read directly — but this contradicts the brainstorm's "no schema widening" stance and would force a re-brainstorm.
- **R-Risk-2:** Performance: per-storage-eval JOIN to `conversations`. Mitigated by (a) `conversations.id` is PK (single-row index lookup), (b) `is_workspace_member` is a SECURITY DEFINER plpgsql function with planner-inlining defeated (same shape as mig 059's `is_message_owner`), (c) Storage downloads are infrequent vs message reads. Measure in Phase 0.4 spike via `EXPLAIN ANALYZE`; record budget in plan worklog.
- **R-Risk-3:** WORM trigger on `messages` (Phase 0.4 check). If present, RPC UPDATE must use to_jsonb-minus-column-equality carve-out per `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md`. Mitigation already designed in Phase 0.4; aborts plan to redesign if carve-out is impractical.
- **R-Risk-4:** Mig 068 applied to dev but lockstep with `apply-deploy-pipeline-fix.yml`-style auto-apply forgets the prd ack. Mitigated by `hr-menu-option-ack-not-prod-write-auth` — full SQL quoted in ack prompt.
- **R-Risk-5:** PostgREST schema cache lag post-mig-068 — new RPC `anonymise_authored_messages_in_shared_conversations` invisible to tenant clients until `NOTIFY pgrst, 'reload schema'`. Mitigated by post-deploy `gh workflow run web-platform-release.yml --field action=schema-reload` per `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`.

## Sharp Edges

(Trimmed per DHH P1-3 + code-simplicity P1-4 — Reconciliation-paraphrases removed. Reconciliation table R-1..R-10 is authoritative for those traps.)

- Mig 068 introduces the FIRST in-repo `storage.objects` policy invoking a SECURITY DEFINER helper. The R-9 Phase 0.3 spike is load-bearing — do not skip.
- The `remove_workspace_member` RPC body in mig 067 is replicated VERBATIM inside the mig 068 re-CREATE block (Postgres has no `ALTER FUNCTION BODY`). When /work writes the mig 068 body, re-read mig 067 lines 117-206 and reproduce exactly; any drift between the two CREATEs is silent.
- The pseudonym cast `('member_' || encode(gen_random_bytes(6), 'hex'))::uuid` may not be valid if `messages.user_id` is `uuid` typed. Phase 4 includes a column-type verification gate; if `uuid`, the design switches to `uuid_generate_v5` on a deterministic tuple (loses the human-readable prefix). Do not ship the literal `'member_<hex12>'::uuid` cast without verifying.
- `_anonymise_authored_messages_internal` has NO public GRANT. Calling it directly from TS will return permission-denied. Always go through the two public RPCs.
- PROBE-A (`messages.workspace_id IS NULL` count) MUST be 0 in prd. If non-zero, the `_anonymise_authored_messages_internal` body needs `AND m.workspace_id IS NOT NULL` filter; otherwise irreversible over-pseudonymisation on cross-workspace legacy messages.
- Mig 068 = de-facto flag flip for storage RLS semantics (the SECURITY DEFINER predicate evaluates regardless of `TEAM_WORKSPACE_INVITE_ENABLED`). If invite-issuance has not yet shipped, no co-members exist and the new clause is dormant — but the predicate IS live the moment mig 068 applies. Document in the flag's description.

## Alternatives Considered

| Approach | Why rejected |
|---|---|
| **Minimal-correct (brainstorm option)** — patch only the bucket predicate as drafted; defer cascade, API routes, member-removal | Brainstorm Decision 1 rejected (operator + triad). Reconciliation confirms: R-1 predicate broken, R-2 column doesn't exist, R-4/R-5 silent-failure surfaces. "Minimal" would have shipped 5 known critical bugs. |
| **Defer entirely** — wait until first multi-user workspace lands | Brainstorm Decision 1 rejected. Storage layer is the only residual gap; flag-flip readiness requires this. |
| **Path rename to `{workspaceId}/{convId}/{file}` (sub-option (b))** | Brainstorm Decision 4 rejected. Renaming = processing operation on file content = Art. 30 logging burden + cross-region replication risk. Deferred to future Enterprise-tier scope. |
| **JWT `current_workspace_id` claim** | Claim is `current_organization_id` (not workspace); org ⊃ workspaces; doesn't map. Path-derivation via `(foldername)[2]` is the canonical alternative. |
| **`users_share_workspace(a, b)` helper** (broader sharing) | Too broad — would let any user in any shared workspace read another user's uploads from any other workspace they share. Conversation-derived workspace check is tighter. |
| **Keep `FOR ALL USING`, accept the write-widening hole** | Contradicts brainstorm Decision 4 intent and `2026-04-18-rls-for-all-using-applies-to-writes.md`. Policy split is cheap (~20 lines SQL) and audit-clear. |
| **Add `uploader_user_id` column to `message_attachments` + backfill** | Wider schema migration than scoped. Pseudonymising `messages.user_id` (which already exists) reaches the same Art. 17 outcome. |
| **Single polymorphic RPC with `p_workspace_id DEFAULT NULL`** (initial plan draft) | Architecture P0-2 rejected. Hides two distinct contracts (caller authorisation, membership-row state assumption, audit-log emission). Split into two public RPCs sharing a private internal helper. |
| **Shared TS helper `attachment-co-membership.ts`** (initial plan draft) | DHH P0-2 + code-simplicity P0-1 + architecture P1-1 convergence: parallel-universe abstraction. Inline the conversation lookup (5-7 lines per route). |
| **TS-side sequence `pseudonymise → call remove_workspace_member`** (initial plan draft) | Architecture P0-1 rejected. `remove_workspace_member` is atomic; the DELETE lives inside the RPC body — no TS-side seam exists "before DELETE". Fold pseudonymisation INTO the RPC body via mig 068 re-CREATE. |
| **3-reviewer panel (DHH cut)** | DHH P1-4 rejected. Single-user-incident threshold mandates 5+ panel per `2026-05-10-plan-time-reviewer-orthogonality-for-security-sensitive-plans.md`. Multi-panel is non-negotiable at this floor. |

---

**Plan author:** Claude (Opus 4.7 / 1M context)
**Date:** 2026-05-25
**Plan-review status:** APPLIED — 5-panel review (DHH + Kieran + code-simplicity + architecture-strategist + user-impact-reviewer) ran 2026-05-25; convergent cuts (TS helper, paper ACs, Phase 1 reorder) and load-bearing additions (RPC split, `remove_workspace_member` amend, service-role surface sweep, PROBE-A..D, transaction boundary, GRANT/REVOKE matrix correction) applied. Open spec-flow-analyzer panel was run as journey-walk; findings folded into Phase 3.5 + R-4 + AC9. CPO sign-off required before `/work` per `requires_cpo_signoff: true`.
