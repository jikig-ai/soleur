---
date: 2026-05-25
topic: PR-2 of #4233 known-gaps bundle — attachments workspace-shared (Storage layer only)
related_issues:
  - "#4233 (parent bundle)"
  - "#4318 (residual gap — workspace-keyed RLS on attachments)"
predecessor_prs:
  - "#4345 / mig 067 (PR-1: workspace-member session invalidation, merged 33293aae 2026-05-25)"
  - "#3883 / mig 045 (PR-D umbrella #3244: attachments-storage tenant RLS, merged 2026-05-16)"
  - "#4289 (DPD §2.1b(a) controllership team-workspace carve-out, merged 2026-05-22)"
  - "#4351 (DSAR Art. 15(4) author-only redaction, merged 2026-05-25)"
brand_survival_threshold: single-user incident
lane: cross-domain
domains_assessed:
  - Engineering (CTO)
  - Legal (CLO)
  - Product (CPO)
---

# Brainstorm: PR-2 — attachments workspace-shared (Storage layer)

## What We're Building

Switch the `chat-attachments` Supabase Storage bucket from **user-folder-keyed** to **workspace-co-member-readable** so that, once `TEAM_WORKSPACE_INVITE_ENABLED` flips ON, User B can download attachments uploaded by User A on shared conversations.

Concrete delta: a single migration (068) replacing the bucket policy predicate `(storage.foldername(name))[1] = auth.uid()::text` with a dual predicate `... OR is_workspace_member(((foldername)[1])::uuid, auth.uid())`, plus a sibling cascade step in `account-delete.ts` to pseudonymise uploader identity on shared-workspace attachment rows when a member leaves.

**Scope narrowing surfaced during brainstorm:** the original framing assumed PR-2 needed `workspace_id` column on `message_attachments` + RLS sweep + Storage object rename. CTO verification of mig 059 lines 416-447 showed the DB-layer cascade is **already workspace-aware** (mig 059 widened `is_message_owner` to use `messages.workspace_id` via `is_workspace_member()`; all 045-era callers including `message_attachments` SELECT + INSERT policies inherit the new semantic transparently per the migration's COMMENT). Storage object rename is avoidable per CLO sub-option (a) — keep paths user-keyed physically, change predicate only — which dodges an Art. 30-logged processing operation on file content.

## User-Brand Impact

Brand-survival threshold: `single-user incident` (carry-forward from PR-1 / #4307).

| Vector | Failure mode | Founder-visible signal |
|---|---|---|
| **(a) Trust breach / cross-workspace leak** | Mig 068 predicate widens too far (e.g., wrong UUID-cast regex; `(foldername)[1]` returns non-UUID and predicate fails-open). User in workspace X reads attachment from workspace Y. | One incident = Art. 33 notification surface + brand-survival event. |
| **(b) Legitimate-read denial (silent)** | Post-cutover bucket policy denies a workspace co-member's read; UI's `.catch(() => {})` swallows error → permanent skeleton loader (per PR-D learning). Founder sees "attachment ignored by agent." | Trust erodes per turn; indistinguishable from LLM-not-using-context. |
| **(c) Lingering uploader-PII after member removal** | Departed member's `user_id` remains on `message_attachments.uploader_user_id` (or equivalent column) in shared-workspace conversations the controller retains. CLO load-bearing concern. | Art. 17 erasure incomplete; legal exposure on first member-removal in multi-user workspace. |

## Why This Approach

**Hardened scope** (operator-confirmed at brainstorm Phase 2 AskUserQuestion) over Minimal-correct and Defer-entirely because:

1. **Storage layer is the ONLY residual gap.** Mig 059 already shipped workspace-keyed `is_message_owner` (lines 416-447, ADR-038). PR-D #3883 already shipped bucket SELECT/INSERT/UPDATE/DELETE policies (mig 045). PR-1 #4345 already shipped session invalidation. The bucket folder predicate is what's left.
2. **No backfill pressure.** Zero multi-user workspaces in prd (TEAM_WORKSPACE_INVITE_ENABLED is OFF). Orphan-path audit query is the gate, not a multi-step backfill job.
3. **CLO load-bearing legal step requires PR-2 ownership.** The departed-member uploader pseudonymisation cascade addition (between `account-delete.ts` steps 3.92 and 3.93) **must ship in this PR**, not a follow-up — otherwise shipping the workspace-shared bucket creates the lingering-uploader-PII window immediately on first member-removal post flag flip.
4. **Storage object rename avoided (CLO sub-option (a)).** Renaming objects = processing operation on file content = Art. 30 logging burden + cross-region replication risk. Predicate-only change keeps paths physically `{userId}/{conversationId}/{uuid}.{ext}` and resolves user-folder → workspace-membership at policy evaluation.
5. **No new disclosure surface needed.** PR #4289 (2026-05-22) shipped DPD §2.1b(a) + ToS §3b + AUP §5.5 + Privacy Policy §4.11 covering co-member visibility three days before this PR.
6. **Ships behind invite flag** (currently OFF). Zero behavior change in prd until flag flip; UX follow-up (uploader attribution in attachment cards) is the gate for flag flip, not for PR-2 merge.

## Key Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| 1 | **Scope = Hardened.** All deliverables below ship in PR-2 as one PR. | Operator + triad consensus | Phase 2 AskUserQuestion |
| 2 | **Single PR + post-merge ack-gated `supabase db push`** per `hr-menu-option-ack-not-prod-write-auth` and PR-D / PR-1 precedent. | Established Soleur pattern | CTO §5 |
| 3 | **Mig 068**: replace `chat-attachments` bucket FOR ALL policy predicate `(foldername)[1] = auth.uid()::text` with dual predicate `(foldername)[1] = auth.uid()::text OR is_workspace_member(((foldername)[1])::uuid, auth.uid())`. Add UUID-cast regex guard `(foldername)[1] ~ '^[0-9a-f-]{36}$'` before the cast to prevent fail-open on malformed inputs. | CTO §1; CLO sub-option (a) | Triad |
| 4 | **Keep Storage paths user-keyed physically** (`{userId}/...`). No object rename. No `WITH CHECK` added (preserve mig 045 lines 54-60 invariant per `2026-04-18-rls-for-all-using-applies-to-writes.md`). | Avoid Art. 30 processing-op + drive-by RLS regression | CLO §5; CTO §1 |
| 5 | **NO `workspace_id` column added to `message_attachments`.** Mig 059 cascade already workspace-aware. | Verified: mig 059:416-447 + COMMENT confirms 045-era callers inherit transparently | CTO §0 (state of play) |
| 6 | **`account-delete.ts` sibling cascade step** between 3.92 (`anonymise_workspace_member_attestations`) and 3.93 (`anonymise_workspace_members`): pseudonymise uploader identity on `message_attachments` rows where the message's `conversation.user_id ≠ departing user` (shared-workspace conversations the controller retains). Pseudonym shape `member_<hex12>` consistent with PR #4351. | CLO load-bearing — without this, lingering uploader-PII window on first member-removal post flag flip | CLO §2 |
| 7 | **`dsar-export.ts` + `account-delete.ts` Storage list updates**: change `chat-attachments/{userId}/` enumeration to workspace-scoped enumeration to avoid silent empty-list data-loss bug post-cutover. | CTO §4 (silent-failure surface) | CTO |
| 8 | **Article 30 PA-2 amendment**: §(c) add co-member data subjects; §(d) flip "per-user_id isolation" → "per-workspace_id isolation"; §(g)(10) rewrite Storage TOM with new predicate; add §(g) pre-merge orphan-path audit query as documented TOM (mirrors PR-D OQ#2). | CLO §3 | CLO |
| 9 | **Tenant-isolation tests**: real-shaped UUIDs in victim workspace folders (NOT `__ALICE__` style sentinels — `dsar-author-redaction.integration.test.ts:81` uses unreal sentinels and would not trigger the workspace-member check); dual-shape deny assertions (`{ data: null, error: <RLS-deny> }` AND `{ data: [], error: null }` for cross-tenant list); positive control (User B downloads User A's attachment in shared workspace). | CTO §3 per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md` | CTO |
| 10 | **UX follow-up filed (NOT in PR-2)**: attachment cards must show uploader avatar + name BEFORE `TEAM_WORKSPACE_INVITE_ENABLED` flips ON. Tracking issue links to PR-2's PR body + flag-flip runbook so the gate isn't forgotten. | CPO §2 | CPO |
| 11 | **Productize candidate** (Phase 2.5): `soleur:rls-cascade-to-direct` skill — pattern repeats (attachments here, likely message_reactions, conversation_shares next). File as P3-low follow-up; do NOT pivot this brainstorm. | CPO §5 | CPO |

## Open Questions

1. **Object count in prd `chat-attachments` bucket** (CTO blocking Q1). Needed via Supabase MCP query against prd `storage.objects WHERE bucket_id='chat-attachments'` to size the orphan-path audit. Likely small (0 multi-user workspaces; jikigai-only org). **Decision deferred to plan Phase 0.**
2. **`current_workspace` JWT claim availability for presign route** (CTO blocking Q2). Mig 060 wired the `current_organization_id` claim into the JWT via Custom Access Token Hook. Verify `app/api/attachments/presign/route.ts:91` can read it without a per-upload round-trip to `workspace_members`. If not, latency-budget check needed. **Decision deferred to plan Phase 0.**
3. **Workspace-deletion cascade reaches Storage objects?** (CPO §3c). `conversations.workspace_id` FK → `workspaces(id) ON DELETE RESTRICT` (per mig 053/059). When a workspace is deleted, do Storage objects get reaped, or do they orphan in the `chat-attachments` bucket? **Likely gap.** Options: (a) confirm existing cascade chain reaches Storage; (b) add to PR-2 scope; (c) file as separate cleanup issue. **Provisional: investigate at plan Phase 0; if gap is real and cheap to close in PR-2, include; else file follow-up.**
4. **DSAR Art. 15 coverage of cross-uploader attachments in shared conversations** (CPO §4). When User A asks for DSAR export, do attachments uploaded by OTHER members in conversations A participated in appear in A's bundle? Default-include with uploader identity redacted (per Art. 15 over-include preference); confirm with CLO at plan time. **Decision deferred.**
5. **Orphan-path audit query shape** (CLO §5 pre-merge gate). Query: `SELECT COUNT(*) FROM storage.objects WHERE bucket_id='chat-attachments' AND (storage.foldername(name))[1] NOT IN (SELECT user_id::text FROM workspace_members WHERE workspace_id IN (SELECT workspace_id FROM ...))`. Exact shape pinned at plan time; non-zero blocks merge.

## Domain Assessments

**Assessed:** Engineering (CTO), Legal (CLO), Product (CPO)

### Engineering (CTO)

**Summary:** Major scope narrowing: mig 059 already widened `is_message_owner` to workspace-keyed; only residual gap is the Storage bucket folder predicate (mig 045:54-60) + path mint (`presign/route.ts:91`) + SSRF guard (`url/route.ts:24`). Recommend sub-option (B) dual-predicate disjunction for zero-downtime cutover; keep paths physically user-keyed. Two blocking questions: prd object count + `current_workspace` JWT claim availability. Silent-failure inventory: `account-delete.ts:175` and `dsar-export.ts:1198` list `chat-attachments/<userId>/` — both silently return empty post-cutover unless updated in this PR.

### Legal (CLO)

**Summary:** Controller/processor split already settled (PR #4289 / DPD §2.1b(a) + ToS §3b + AUP §5.5). No new disclosure modal needed — co-member visibility was disclosed 2026-05-22. Load-bearing legal step PR-2 must own: `account-delete.ts` sibling cascade between 3.92/3.93 to pseudonymise uploader identity on shared-workspace `message_attachments` rows on member removal (otherwise lingering uploader-PII window opens immediately on first removal post flag flip). PA-2 amendment scope concrete: §(c)/§(d)/§(g)(10) deltas + add §(g) pre-merge orphan-path audit as TOM. Recommend sub-option (a) — predicate-only change, no object rename — on legal-risk grounds.

### Product (CPO)

**Summary:** Zero multi-user workspaces in prd → PR-2 is structural prep for Phase 4 recruitment, not present-user need. Can ship behind `TEAM_WORKSPACE_INVITE_ENABLED` (OFF). UX gate for flag flip = author attribution in attachment cards (uploader avatar + name); UX work is acceptable as follow-up before flag flip, NOT before PR-2 merge. Permission edge case flagged: workspace-deletion cascade likely orphans Storage objects (Open Question #3). Brand-survival floor add: shape-test that `attachment-display.tsx` renders non-skeleton fallback on uploader profile fetch failure (PR-D precedent). Productize candidate: `soleur:rls-cascade-to-direct` skill, P3-low follow-up.

## Capability Gaps

None blocking. The Hardened scope is fully executable with current primitives:

- `is_workspace_member(workspace_id, user_id)` SECURITY DEFINER helper exists (verified via mig 059 reference). Usable in `storage.objects` bucket policy with explicit `public.` schema qualification.
- Mig 060's Custom Access Token Hook injects `current_organization_id` into JWT (Open Question 2 verifies this is reachable from the presign route without round-trip).
- `account-delete.ts` cascade pattern is established (steps 3.91-3.93 inserted by PR #4351 and mig 062); sibling-step insertion follows the same shape.
- Tenant-isolation test fixture in `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` provides canonical workspace-A vs workspace-B synthetic JWT shape (verified).
- `reportSilentFallback` + `cq-silent-fallback-must-mirror-to-sentry` already standard for `attachment-display.tsx` fallback.

## Productize Candidate (Phase 2.5)

Pattern repeating across PR-D (#3883), PR-1 (#4345), this PR-2: extend WORM ledger or RLS predicate → swap cascade → tenant-client migration → tenant-isolation tests → Article 30 amendment → account-delete cascade addition. Capture as future skill `soleur:rls-cascade-to-direct` (one-table or one-predicate scope). **Trigger: after PR-2 merges, run `/soleur:compound` to capture the pattern, file as separate skill-creation issue.** Do NOT pivot this brainstorm.

## Pitfalls Surfaced

1. **Original PR-2 framing (from 2026-05-22 bundle brainstorm) was wrong** about workspace_id column being needed on `message_attachments`. Mig 059 (which landed before the bundle brainstorm was written) already covered the DB-layer cascade. The bundle brainstorm's "PR-2 chat-attachments storage-bucket workspace-keyed predicate" line WAS accurate about the bucket layer; the AskUserQuestion option labels in THIS brainstorm initially conflated bucket + table layers. Triad caught it during scope-shaping.
2. **#4318's "Option A vs Option B" enumeration is partially obsolete.** Option B's "add workspace_id + sweep RLS" was author's mental model from before mig 059; today, only the Storage layer needs the predicate widening. Close #4318 with PR-2's narrowed-scope explanation.
3. **`dsar-author-redaction.integration.test.ts:81` uses unreal UUID sentinels** (`__ALICE__` style). Per learning `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`, these would NOT trigger workspace-member check failures. PR-2's tenant-isolation tests MUST use real-shaped UUIDs.
4. **Storage path mint stays `{userId}/{conversationId}/{uuid}.{ext}`** in this PR. Future-PR option to re-layout to `{workspaceId}/{conversationId}/{uuid}.{ext}` is deferred under sub-option (b); requires Art. 30 processing-op logging.

## Sources

- **Predecessor brainstorm (bundle umbrella)**: `knowledge-base/project/brainstorms/2026-05-22-rls-known-gaps-4233-bundle-brainstorm.md`
- **Predecessor brainstorm (PR-D / mig 045)**: `knowledge-base/project/brainstorms/2026-05-16-pr-d-attachments-storage-tenant-rls-brainstorm.md`
- **Existing migrations**: `apps/web-platform/supabase/migrations/045_attachments_storage_rls.sql` (lines 54-60 bucket predicate, 87-109 helper); `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql` (lines 416-447 — `is_message_owner` already workspace-aware)
- **Article 30 PA-2 (edit target)**: `knowledge-base/legal/article-30-register.md`
- **Controllership posture (already-settled)**: `knowledge-base/legal/compliance-posture.md`, `knowledge-base/legal/data-processing-agreement-template.md`, `docs/legal/data-protection-disclosure.md` §2.1b(a) / §2.3(u) / §4.2
- **IDOR motivating learning**: `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md`
- **Test-payload trap**: `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
- **GRANT-mismatch vitest blind**: `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`
- **RLS FOR ALL semantics**: `knowledge-base/project/learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md`
- **Author-redaction precedent**: PR #4351 (mig + DSAR Art. 15(4))
- **Controllership disclosure precedent**: PR #4289 (DPD §2.1b(a) + ToS §3b + AUP §5.5 + Privacy Policy §4.11)
- **Call sites**: `app/api/attachments/presign/route.ts:91` (path mint); `app/api/attachments/url/route.ts:24` (SSRF guard); `server/attachment-pipeline.ts:149` (download); `server/account-delete.ts:175` (user-prefix list); `server/dsar-export.ts:1198` (user-prefix list); `test/server/attachment-pipeline.tenant-isolation.test.ts` (test fixture)
