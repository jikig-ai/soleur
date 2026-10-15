---
date: 2026-05-16
topic: PR-D — attachments-storage tenant RLS (final slice of runtime umbrella #3244)
related_issues:
  - "#3244 (umbrella)"
  - "#3869 items 4-5 (PR-D scope tracker)"
predecessor_prs:
  - "#3240 (PR-A)"
  - "#3395 (PR-B)"
  - "#3854 (PR-C, merged abcb3765 on 2026-05-16)"
brand_survival_threshold: single-user incident
lane: cross-domain
domains_assessed:
  - Engineering (CTO)
  - Legal (CLO)
  - Product (CPO)
---

# Brainstorm: PR-D — attachments-storage tenant RLS

## What We're Building

The last data-plane site in the runtime that still uses `createServiceClient()` is the attachments storage pipeline. PR-D migrates the **two** callers of `persistAndDownloadAttachments` (`cc-dispatcher.ts:1435` and `agent-runner.ts:2305`) to `getFreshTenantClient(userId)`, lands the **missing** Storage write policies that the existing SELECT RLS in `migration 019_chat_attachments.sql` leaves uncovered, and closes the cross-tenant attachment read vector — the 3rd of 3 brand-survival vectors from the umbrella.

After PR-D merges, every data path in the runtime is either tenant-scoped or has a structural reason to stay service-role (`account-delete`, `dsar-export`, presigned-URL minters).

## User-Brand Impact

Brand-survival threshold: `single-user incident` (carry-forward from PR-C umbrella).

| Vector | Failure mode | Founder-visible signal |
|---|---|---|
| **(a) Trust breach / cross-tenant read** | Tenant client + missing Storage RLS lets founder B's `.storage.download()` retrieve founder A's image/PDF. App-level prefix check at `attachment-pipeline.ts:83-86` becomes useless once the storage layer trusts the JWT. | LLM context contains another founder's PII (incorporation docs, brand guides, financials). Single incident = Art. 33 notification surface + brand-survival event. |
| **(b) Broader exposure: metadata + signed-URL leakage** | `message_attachments` row reads via tenant client without join-scoped RLS → filename/MIME/size of sibling tenants visible. Signed URLs with overly permissive TTL could leak via Sentry breadcrumbs. | Less acute than (a) but same disclosure class. |
| **(c) Silent failure post-migration (HIGHEST probability)** | New Storage SELECT policy denies `download()` for the founder's *own* path due to JWT/claims mismatch (PR-B/PR-C precedent: `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`). `Promise.allSettled` swallows the error → `log.error` only → attachment silently dropped from `attachmentContext`. UI `attachment-display.tsx` swallows fetch errors with `.catch(() => {})` and renders **permanent skeleton loader** indefinitely. | "I attached my brand guide and the agent is ignoring it." Founder cannot distinguish RLS denial from LLM-not-using-context. Trust erodes per turn. |

## Why This Approach

**Hardened (compliance-complete)** scope was selected over Minimal-correct and Strict-minimum because:

1. **PA2 Article-30 amendment is an existing Art. 30 gap, not caused by PR-D.** Article 30 register currently has zero coverage of the `chat-attachments` bucket or `message_attachments` table (CLO §2 verified — claim in original framing about a pre-existing PA1/PA2 attachment row is false). Leaving it stale ships a known compliance defect.
2. **Storage.objects INSERT/UPDATE/DELETE policies close the bucket cleanly** even though the presign route stays service-role (CTO §1). Cheap to add, prevents future drive-by `WITH CHECK (true)` regressions per `2026-04-18-rls-for-all-using-applies-to-writes.md`.
3. **UI permanent-skeleton bug is the highest-probability post-launch defect.** Fix-in-PR is cheap; deferring it to a follow-up means a founder hits the silent failure first.
4. **#3869 item 6 (CI tenant-isolation job) blocking is non-negotiable.** Without it, all 11 PR-C tenant-isolation tests AND the new PR-D Storage deny tests silent-skip in default CI. Per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`, a test that doesn't fire is worse than no test (false confidence).

Approach selected: **Pre-PR for CI job + single PR-D**. The CI workflow + Doppler secret wiring is infrastructure-orthogonal to the domain work; review focus stays on the domain in PR-D. PR-B precedent (single PR + post-merge ack-gated `supabase db push` per `hr-menu-option-ack-not-prod-write-auth`) applies to PR-D.

## Key Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| 1 | **Scope = Hardened (compliance-complete).** | All 13 items below ship in PR-D. | Operator + triad |
| 2 | **Two PRs**: pre-PR (CI tenant-isolation workflow + Doppler dev-Supabase secret wiring, closes #3869 item 6) → PR-D (everything else). | CI job is orthogonal to domain; pre-PR small + fast. | CTO §6, learnings #9 |
| 3 | **Migrate `persistAndDownloadAttachments` callers** at `cc-dispatcher.ts:1435` AND `agent-runner.ts:2305` (2 sites, not 1 — original framing missed the sibling). Fix stale "Migrated in PR-C" comment at `agent-runner.ts:2300`. | Sibling-call discovery via grep sweep | Premise validation; CTO §4 |
| 4 | **Add storage.objects INSERT/UPDATE/DELETE policies** scoped to `bucket_id='chat-attachments'` with predicate `(storage.foldername(name))[1] = auth.uid()::text` (`FOR ALL USING`). Comment WHY no explicit `WITH CHECK` to prevent future drive-by regression. | Close bucket cleanly, defend against drive-by edits | CTO §1, learning `2026-04-18-rls-for-all-using-applies-to-writes.md` |
| 5 | **Add INSERT policy on `message_attachments`** with predicate that joins `messages.conversation_id → conversations.user_id = auth.uid()`, mirroring SELECT policy shape from migration 019. | Tenant client INSERT requires WITH CHECK | CTO §1 |
| 6 | **Keep `/api/attachments/presign` and `/api/attachments/url` on service-role**, document why in route docstrings. | `createSignedUploadUrl`/`createSignedUrl` mint RLS-bypass tokens by design — moving the minter to tenant client gains zero residency benefit | CTO §3 |
| 7 | **Keep `account-delete.ts` and `dsar-export.ts` on service-role** (per existing allowlist). PR-D does NOT touch them. | Admin ops list across all tenants; documented exceptions | Repo-research, learnings #2 |
| 8 | **Remove the cc-dispatcher PR-D-pending entry** from `.service-role-allowlist` (lines 78-84). | Allowlist shrink is the deliverable signal | Operator framing |
| 9 | **Sentry mirror on silent download failures** per `cq-silent-fallback-must-mirror-to-sentry`. Add `setUser({id: userId})` so the breadcrumb is attributable. NOT a new schema column. | YAGNI floor for silent-failure signal; new column is over-engineered for 0 beta users | CPO §2 |
| 10 | **Fix `attachment-display.tsx` permanent-skeleton bug** — `.catch(() => {})` becomes `.catch((err) => { reportSilentFallback(err); setLoadFailed(true); })` with a "preview unavailable, click to retry" affordance. | Highest-probability post-launch defect; cheap inline fix | Repo-research §7, CPO §2 |
| 11 | **Amend PA2 in `article-30-register.md`** (not new PA12) to cover `chat-attachments` bucket, `message_attachments` table, TOMs (RLS policy, IDOR check, content-type allowlist, filename sanitisation), and retention (FK ON DELETE CASCADE). | Closes existing Art. 30 gap; attachments are sub-objects of a conversation | CLO §2 |
| 12 | **Single PR + post-merge ack-gated `supabase db push`** per `hr-menu-option-ack-not-prod-write-auth` and PR-B precedent. NOT separate migration vs code PRs. | Established Soleur pattern; reverses earlier "split if needed" intuition based on repo evidence | Repo-research §1 |
| 13 | **Split PR-E for `audit_byok_use` writer + `is_jti_denied` consumer.** File tracking issue referencing umbrella #3244 + CLO advisory ("BEFORE 2nd hosted founder or GA exposure"). | Different review surface; different rollback shape (WORM ledger vs Storage RLS); zero-beta-user state makes "runtime hardening milestone" narrative low-stakes | All three leaders, repo-research §4 |

## Open Questions

1. **`storage.foldername()` edge-case behavior** (CTO §6). Need 3-line SQL spike at plan-time: what does `foldername('a/')`, `foldername('/x')`, `foldername('')` return? Affects whether existing SELECT policy has a latent bypass. **Decision deferred to plan Phase 0**.
2. **Backwards-compat orphan-path audit query** (CLO §5). Pre-merge query: count rows where `(storage.foldername(storage_path))[1] != m.user_id::text`. If non-zero, decide migrate-or-quarantine before flipping the client. **Decision deferred to plan Phase 0**.
3. **`message_attachments` DELETE policy.** FK `ON DELETE CASCADE` on `message_id` handles the parent-driven path. Need explicit policy if tenant should ever directly DELETE a row (e.g., un-attach UX). **Provisional decision: skip, document, file follow-up if un-attach UX is requested.**
4. **PR-E scope confirmation.** Original PR-D scope from PR-C plan §Tracked Deferrals was THREE items (audit_byok_use, is_jti_denied, attachments). This brainstorm reframes PR-D as attachments-only. Tracking issue must be filed for PR-E carrying CLO's "BEFORE 2nd hosted founder or GA exposure" advisory.
5. **Stale `agent-runner.ts:2300` comment grep sweep.** Per learning `2026-05-12-cite-prior-prs-by-actual-file-scope-not-umbrella-narrative.md`, run `git log -S "Migrated in PR-" --` to find ALL such stale comments. May need a separate cleanup PR if more are found.

## Domain Assessments

**Assessed:** Engineering (CTO), Legal (CLO), Product (CPO)

### Engineering (CTO)

**Summary:** Storage SELECT RLS already exists; gap is INSERT/UPDATE/DELETE on `storage.objects` + INSERT on `message_attachments`. Migration-first ordering is mandatory (or single-PR with post-merge ack-gated `db push`). Keep API routes PERMANENT (signed URLs bypass RLS by design). Test trap mirror: use real-shaped UUID paths under victim folder, not malformed paths (`foldername` returns NULL on bad input → false RLS-deny signal).

### Legal (CLO)

**Summary:** Brainstorm's framing claim of pre-existing PA1/PA2 attachment row is false — Article 30 is silent on the `chat-attachments` bucket today, which is a current Art. 30 gap independent of PR-D. Amend PA2 (not new PA12) in this PR. Tenant DPA register empty — no impact. Backwards-compat orphan-path audit query MUST run pre-merge; non-zero blocks. gdpr-gate fires at plan-time when migration delta is concrete.

### Product (CPO)

**Summary:** 0 beta users — blast radius bounded; ship-day risk is structural prep for Phase 4 recruitment, not customer-incident. No banner/disclosure surface (empty external cohort per `2026-05-12-brainstorm-re-audit-inherited-transparency-surfaces.md`). UI permanent-skeleton bug is highest-probability post-launch defect. Productize candidate: `soleur:tenant-migrate-call-site` skill after PR-D merges. Split PR-E correct (different review surface, different rollback shape).

## Capability Gaps

None blocking. The Hardened scope is fully executable with current primitives:
- `getFreshTenantClient(userId)` returns full `SupabaseClient` with `.storage` surface (verified: `apps/web-platform/lib/supabase/tenant.ts:236-275`).
- Existing tenant-isolation test fixture in `apps/web-platform/test/server/cc-dispatcher.tenant-isolation.test.ts` provides the canonical Founder-A vs Founder-B synthetic JWT shape (verified: lines 33-44, 62-110, 121-134).
- `reportSilentFallback` helper exists; `setUser({id})` is standard `@sentry/nextjs` API.
- pgTAP fixture cost for Storage RLS tests (CTO §6 risk) needs scoping at plan-time but no new tooling required.

## Productize Candidate (Phase 2.5)

Recurring pattern across PR-A/B/C/D: call-site enumeration → tenant-client swap → auth-probe insertion → RPC GRANT cross-check → vitest mock-DRY → allowlist-shrink commit → CI grep gate. Capture as future skill `soleur:tenant-migrate-call-site` (one-site or one-file scope). **Trigger: after PR-D merges, run `/soleur:compound` to capture the pattern, file as separate skill-creation issue.** Do NOT pivot this brainstorm.

## Pitfalls Surfaced

1. **`#3660` is a different "PR-D".** That issue is `feat(chat): rail-level cohort indicator on conversations-rail (PR-D, deferred from PR-B)` — belongs to the chat-RAIL/transcript-hardening track (parent #3603), NOT the runtime tenant-isolation track. Naming collision; ignore for this brainstorm.
2. **Stale `agent-runner.ts:2300` comment** falsely claims "Migrated in PR-C alongside the rest of the attachment pipeline". Wrong — the migration was deferred to PR-D. Fix included in scope item #3.
3. **Line-ref drift**: original framing cited `cc-dispatcher.ts:1421`; current state at HEAD is the call setup ~1429 and the `await persistAndDownloadAttachments(...)` line at :1435. Minor; plan must re-enumerate at /work HEAD per the R1 pattern from PR-C plan.
4. **PR-B precedent ≠ split**: brainstorm initially leaned toward "migration first, code second" sequencing; repo-research §1 confirmed PR-B used **single PR + post-merge ack-gated `db push`**. Reconciled in Decision #12.

## Sources

- **Predecessor brainstorm**: `knowledge-base/project/brainstorms/2026-05-15-pr-c-sibling-query-migration-brainstorm.md`
- **Predecessor plan**: `knowledge-base/project/plans/2026-05-15-feat-pr-c-sibling-query-migration-plan.md` §Tracked Deferrals
- **IDOR motivating learning**: `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md`
- **Test-payload trap**: `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
- **GRANT-mismatch vitest blind**: `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`
- **RLS FOR ALL semantics**: `knowledge-base/project/learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md`
- **Transparency surface re-audit**: `knowledge-base/project/learnings/2026-05-12-brainstorm-re-audit-inherited-transparency-surfaces.md`
- **Migration mandates need wired call sites**: `knowledge-base/project/learnings/2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`
- **Existing Storage SELECT RLS**: `apps/web-platform/supabase/migrations/019_chat_attachments.sql`
- **Article 30 register PA2**: `knowledge-base/legal/article-30-register.md` (lines 54-67, current silent on chat-attachments)
