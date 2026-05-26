---
date: 2026-05-22
topic: Multi-tenant RLS + session-invalidation hardening (5 #4233 deferrals → 2 PRs after premise re-verification)
related_issues:
  - "#4233 (parent — identity-rbac-reviewer agent, merged via #4288 today)"
  - "#4304 kb_chunks RLS — STALE PREMISE (table does not exist)"
  - "#4305 kb_files RLS — STALE PREMISE (table does not exist)"
  - "#4306 runtime_cost_state RLS — STALE PREMISE (no such table; cost columns are on public.users)"
  - "#4307 session invalidation on workspace_member delete/role change (R4) — REAL, p2-medium"
  - "#4318 attachments RLS cascade — PARTIAL (row RLS already workspace-aware via 059; storage-bucket folder predicate is the residual gap)"
brand_survival_threshold: single-user incident
lane: cross-domain
domains_assessed:
  - Product (CPO)
  - Legal (CLO)
  - Engineering (CTO)
---

# Brainstorm: Close 5 #4233 known-gap deferrals (re-scoped to 2 PRs)

## What We're Building

Original framing: ship a single sweep migration closing 4 workspace-keyed RLS gaps (`kb_chunks`, `kb_files`, `runtime_cost_state`, `attachments`) + one session-invalidation primitive (#4307). Premise re-verification at Phase 1.0.5 collapsed the bundle to **two PRs and three paper-closes**:

- **PR-1 (real, blocks `TEAM_WORKSPACE_INVITE_ENABLED=ON`):** Session invalidation on workspace-member removal/role change. Extends `workspace_member_removals` (migration 062) with a `revoked_after` column read by middleware on every authenticated request. Closes #4307.
- **PR-2 (real, residual #4318 gap):** Migrate `chat-attachments` storage bucket folder predicate from `auth.uid()::text` to workspace-keyed (`is_workspace_member`-routed via `messages.workspace_id` lookup). The `message_attachments` row RLS is already workspace-aware via migration 059's widened `is_message_owner` (ADR-038) — this PR closes the storage-bucket layer that migration 045 still gates per-user.
- **Paper-closes:** #4304, #4305, #4306, #4318 (original framing). Append premise-reverification comments to each; defer close decisions to operator after review.

## Why This Approach

Three premise findings drove the re-scope (Phase 1.0.5 re-verification per `hr-write-boundary-sentinel-sweep-all-write-sites` and prior-art repo-research):

1. **`kb_chunks` and `kb_files` do not exist as tables.** Zero migrations create them; zero TS/SQL references. The actual KB surface is `kb_share_links` (already swept by migration 059) and `kb_sync_history` (JSONB column on `public.users`). The embeddings worktree `feat-adr-embeddings-kb-retrieval-4206` has migrations only through 052; if it introduces `kb_files`/`kb_chunks`, the right place to land RLS is *the same migration that creates the table*, not a follow-on sweep. #4304/#4305 belong in #4206's scope.
2. **`runtime_cost_state` is not a table.** Migration 046 adds columns (`runtime_paused_at`, `runtime_cost_cap_cents`) on `public.users`. They inherit `users` RLS (per-user). The G7 `workspace_id` from migration 059 was added to `audit_byok_use`, NOT to these columns. Issue body's claim of "RLS predicate missing" applies to a table that doesn't exist; the columns are correctly per-user-scoped today.
3. **#4318 row RLS is already workspace-aware** — migration 059:416-447 widened `is_message_owner` to dispatch via `messages.workspace_id → is_workspace_member` (ADR-038). The **residual** gap is one layer below: `chat-attachments` storage bucket's `(storage.foldername(name))[1] = auth.uid()::text` predicate at migration 045:54-60 is still per-user, not workspace-aware. Workspace co-members cannot read each others' attachments via `.storage.download()` because of this — which breaks the ADR-038 promise the moment the invite UI flips ON.

CTO, CLO, and CPO independently converged on **#4307 = ship first** (only p2; only one with active blast radius post-flag-flip). The triad split on whether to bundle the storage-bucket fix:

- **CTO**: bundle the RLS work into one migration ("059b") was the right answer when 4 tables were in scope; with the bundle collapsed to one storage-policy change, single-PR is preferable.
- **CPO**: separate PR for storage-bucket fix — different review surface (storage RLS vs middleware/auth), different rollback shape, no shared invariant with #4307.
- **CLO**: ship them as two PRs but **co-edit Art. 30 PA-2 in PR-2** (attachments storage TOM amendment) AND ship #4307's Art. 30(1)(g) addition to PA-19/PA-20 in PR-1.

Resolved: two PRs. PR-1 first (statutory clock per CLO §3), PR-2 follows.

## User-Brand Impact

Brand-survival threshold: `single-user incident`.

| Vector | Failure mode | Founder-visible signal |
|---|---|---|
| **(a) Stale-JWT post-removal (#4307)** | Removed/demoted workspace member retains JWT-backed access for ~1h until natural expiry. Active the moment `TEAM_WORKSPACE_INVITE_ENABLED` flips ON in prd. | "I removed the contractor 5 minutes ago and they screenshotted my private thread." Demo-killing; trust-killing; statutory (Art. 6 lawful-basis termination at removal; Art. 32 TOM failure on entitlement-change confidentiality). |
| **(b) Cross-tenant storage read (#4318 residual)** | Workspace co-member B downloads co-member A's attachment file directly via `.storage.download()` — bucket folder predicate gates on `auth.uid()` not workspace membership. Row-RLS on `message_attachments` is workspace-aware (via 059) so the metadata is shared correctly, but the binary content predicate is below the row layer. | "Why can I see Alice's onboarding PDF but only my own messages reference it?" Confidentiality breach class; Art. 5(1)(f) integrity; Art. 33 72h clock at controller awareness. |
| **(c) Silent migration regression (highest-probability post-launch)** | Storage RLS change denies founder's own download (`tenant-jwt-rpc-grant-mismatch-vitest-blind` precedent). `attachment-display.tsx` swallows fetch errors → permanent skeleton loader. Founder can't distinguish RLS denial from LLM-not-using-context. | "I attached my brand guide and the agent is ignoring it." Trust erodes per turn. Mitigation: positive-control assertions per learning `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`. |

**Latent-vs-active threshold is load-bearing for prioritization.** #4307 stale-JWT and #4318 storage read are both **latent today** because (i) invite UI flag is OFF (no removed members exist), (ii) every workspace currently has exactly one member (no co-member to cross-read). Both become active the same moment: when the first multi-member workspace ships. Therefore PR-1 must land before flag-flip; PR-2 must land before (or in the same release as) PR-1's user-visible exposure.

## Key Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| 1 | **Two PRs, not one bundle.** PR-1 = #4307 session invalidation. PR-2 = #4318 storage-bucket folder predicate. | Different review surfaces (auth/middleware vs storage RLS); different rollback shapes; no shared invariant. | CPO §2, CTO §1 (post-scope-collapse), CLO §1 |
| 2 | **PR-1 sequencing: blocks `TEAM_WORKSPACE_INVITE_ENABLED=ON` flag flip in prd.** Workflow gate asserts #4307 closed before the flag set-role skill writes to Doppler. | Re-evaluation criterion quoted from #4307 verbatim. Art. 6/32 statutory framing per CLO §2. | CLO §3 (binding) |
| 3 | **#4307 mechanism = revocation table extension off `workspace_member_removals` (mig 062), NOT JWKS rotation or shorter TTL.** Add `revoked_after timestamptz` column; consult in middleware/`tenantFor` on every authenticated request; cache lookup with a short TTL to bound DB load. | JWKS = nuke-from-orbit (CTO §2); TTL = doesn't close gap, only narrows; trigger writes to existing WORM ledger (CTO §2). Per-user revocation is the product-correct shape (CPO §4). | CTO §2, CPO §4 |
| 4 | **#4307 in-product UX: one-time disclosure modal at first invite-send AND first invite-accept; persistent member indicator in chat surface when workspace > 1 member.** | ADR-038 widens semantic: workspace co-members can read each others' messages + attachments. Not implicit in "team workspace" mental model — requires transparency surface. | CPO §3 |
| 5 | **#4318 PR-2 scope = `chat-attachments` storage bucket folder predicate ONLY.** Migration changes `(storage.foldername(name))[1] = auth.uid()::text` to a workspace-membership lookup via the existing message_attachments → messages.workspace_id chain. Backwards-compat orphan-path audit query MUST run pre-merge (precedent: 2026-05-16 PR-D brainstorm Open Question #2). | Row RLS already workspace-aware (mig 059, ADR-038). Storage bucket is the only residual layer. | CTO §3, repo-research §3 |
| 6 | **NOT migrating to Option B (direct workspace_id column on `attachments`).** The cascade via `is_message_owner` is workspace-aware today; adding a denormalized column buys ~1 join hop on a hot table, costs migration + backfill + NOT NULL flip. | CTO §3; #4318 issue-body framing of the choice was correct but the row-RLS layer is already done. | CTO §3 |
| 7 | **Paper-close #4304, #4305, #4306 with premise-reverification comment, BUT do not auto-close.** Operator reviews and closes. #4304/#4305 fold into #4206 scope (RLS lands in same migration as table creation). #4306 closes as wrong-granularity (cost columns inherit users RLS). | Premise findings 1+2; identity-rbac-reviewer R1 accepts "table doesn't exist → no gap." | Premise re-verification + operator decision |
| 8 | **#4318 stays OPEN until PR-2 ships.** Original framing of "Option A vs Option B" gets a comment noting Option A is already shipped (mig 059) and the residual storage-bucket layer is the actual scope of PR-2. | Issue keeps a referent so identity-rbac-reviewer's info-finding can close cleanly when PR-2 lands. | CTO §3; identity-rbac-reviewer audit shape |
| 9 | **PR-1 Art. 30 amendment: PA-19 / PA-20 §(g) addition documenting revocation-lookup TOM.** PR-2 Art. 30 amendment: PA-2 §(c) categories + §(g) TOMs to cover storage-bucket workspace-keying. | CLO §1, §4 (gdpr-gate pre-emption). | CLO §1, §4 |
| 10 | **No `is_jti_denied`/`denied_jti` primitive exists in code today.** Learnings researcher's pointer was incorrect; repo grep returned zero hits. #4307's mechanism is therefore NEW (extend 062), not extension. | Repo-research §4. | Repo-research |
| 11 | **Migration number for PR-1 / PR-2 = 064+.** Migration 063 collision: both main (workspace_member_actions) and worktree `feat-byok-delegations-4232` (byok_delegations) hold the 063 slot. Serialize against the in-flight 063. | Repo-research §5. | Repo-research |
| 12 | **AC pattern for both PRs: positive control + service-role re-read poison check per `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`.** Same payload as deny test, expect success in owner's workspace; assert service-role sees row absent after deny. | Highest-likelihood failure mode (CTO §5; learning #4). | CTO §5, learnings |

## Open Questions

1. **PR-2 storage-bucket predicate shape.** The migration needs a SQL predicate that joins from `storage.objects.name` (folder path) back to `message_attachments → messages.workspace_id → is_workspace_member`. Today's path layout (`(storage.foldername(name))[1] = auth.uid()::text`) embeds `user_id`, not `message_id`. Two sub-options: (a) keep user_id in path but require requesting user to be a workspace co-member of the file's owner (lookup via `workspace_members` join); (b) re-layout the bucket to embed `workspace_id` in the path prefix and backfill. **Decision deferred to PR-2 plan Phase 0.** Sub-option (a) avoids re-layout (no orphan-path remediation) at the cost of a slightly heavier predicate.
2. **#4307 cache TTL on revocation lookup.** Per-request DB hit is the safe shape but adds latency. Cached lookup with N-second TTL trades freshness for load. CPO constraint: "removal must be effective within seconds for the removed user, invisible to everyone else." 5-10s cache window meets this. **Decision deferred to PR-1 plan Phase 0** (ADR-worthy).
3. **Storage path orphan audit (PR-2 pre-merge).** Pre-merge SQL query: count `message_attachments` rows whose storage path's first folder segment ≠ a current workspace-member's `user_id`. If non-zero, migrate-or-quarantine before flipping bucket policy. Mirrors 2026-05-16 PR-D Open Question #2.
4. **`feat-adr-embeddings-kb-retrieval-4206` coordination.** When/if that worktree introduces `kb_files`/`kb_chunks`, the RLS predicate MUST land in the same migration that creates the tables. File a cross-link comment on #4206 noting this constraint and pointing at the 059 sweep pattern.
5. **identity-rbac-reviewer checklist update.** After PR-1+PR-2 ship, the R4 (session invalidation) finding can be demoted from info to enforced/high (per #4233 spec FR2.4). The R1 cascade-documentation finding for attachments can close. File a follow-up to update the agent body when both PRs merge.

## Domain Assessments

**Assessed:** Engineering (CTO), Legal (CLO), Product (CPO)

### Engineering (CTO)

**Summary:** Original 4-table sweep was mechanically aligned with migration 059's pattern, but premise-reverification collapsed scope to one storage-bucket policy change + one revocation primitive. CTO's pre-collapse recommendation (single migration 064 for the 4 RLS gaps) becomes inapplicable; post-collapse recommendation is two PRs with different review surfaces. #4307 mechanism: extend `workspace_member_removals` ledger (mig 062) with `revoked_after` column, middleware lookup. #4318 storage-bucket layer is the real residual gap (row RLS already workspace-aware via mig 059). Highest-likelihood failure: deny tests passing for the wrong reason on storage RLS — mitigation per learning `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`. ADR worth filing for #4307 mechanism choice.

### Legal (CLO)

**Summary:** Cross-tenant storage read = Art. 5(1)(f) integrity breach class with Art. 33 72h clock. Stale-JWT post-removal = Art. 6 (lawful basis termination) AND Art. 32 (entitlement-change TOM failure). PR-1 sequencing relative to `TEAM_WORKSPACE_INVITE_ENABLED` flag flip is BINDING (criterion quoted verbatim from #4307 body). Art. 30 register has PA-2 (attachments storage) and PA-19/PA-20 (workspace_member_removals/actions) — both need §(g) TOM amendments co-edited in the same PRs as the migrations. gdpr-gate fires at plan-time when migration deltas are concrete; pre-empt by declaring PA amendments + cross-tenant deny tests + write-boundary sentinel sweep in the plan. Highest compliance defect to flag: shipping RLS without Art. 30 PA amendment ("tightened the lock but never wrote the door into the building register").

### Product (CPO)

**Summary:** #4307 is the only p2 and the only one with active blast radius post-flag-flip — ship now. Other 4 paper-close per stale premises. ADR-038 widens "workspace co-members can read each others' messages + attachments" — this is NOT implicit in the "team workspace" mental model; requires transparency surface (modal at first invite send + first invite accept, persistent indicator when > 1 member). #4307 mechanism: per-user revocation table, NOT JWKS (panic button), NOT TTL (constant friction). Highest-likelihood founder-facing failure: removed member's stale JWT triggers Sentry alert during first multi-member demo. Roadmap: no current milestone home — create "MU4 hardening — pre-invite-flag-flip" sub-section with #4307 as the only blocker for flag flip. #4304/#4305/#4306/#4318 belong in "Team-Workspace RLS sweep" track, re-eval = Enterprise scoping OR first multi-member incident.

## Capability Gaps

None blocking. All primitives required for both PRs exist:

- `workspace_member_removals` table + `remove_workspace_member` RPC for #4307 mechanism (migration 062, evidence: `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql`).
- Middleware `await supabase.auth.getUser()` site for revocation lookup injection (evidence: `apps/web-platform/middleware.ts:121-123`).
- Workspace-resolver consuming `app_metadata.current_organization_id` claim from custom-access-token hook (evidence: `apps/web-platform/server/workspace-resolver.ts:7,28,36,46`; `apps/web-platform/supabase/migrations/060_current_organization_jwt_hook.sql:32-41`).
- `is_workspace_member` SECURITY DEFINER helper for #4318 storage policy predicate (evidence: migration 053).
- Tenant-isolation test harness pattern (evidence: `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts` for storage, `apps/web-platform/test/server/cc-dispatcher.tenant-isolation.test.ts` for vitest synthetic JWT shape).
- `reportSilentFallback` helper for storage-deny mirror-to-Sentry (precedent: 2026-05-16 PR-D Key Decision #9).

## Productize Candidate (Phase 2.5)

Two recurring patterns surfaced:

1. **Premise re-verification before bundle scoping.** This brainstorm collapsed a 5-issue bundle to 2-PR scope at Phase 1.0.5 because three issue bodies described tables/columns/primitives that don't exist. Pattern: when an issue body cites table names or columns or named primitives, the brainstorm grep at Phase 1.0.5 must verify each exists in main BEFORE Phase 0.5 leader spawn. Already partially captured in `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`; extend with bundle-rescope precedent. **Candidate: `/soleur:compound` after PR-1 merges to capture the bundle-rescope pattern.**
2. **Session-revocation lookup-on-removal-ledger pattern.** If a third Soleur subsystem ever needs "revoke X on Y event," the `workspace_member_removals + revoked_after + middleware lookup` triple is a reusable shape. **Candidate: file as future skill `soleur:revocation-lookup-from-ledger` after PR-1 merges.** Do NOT pivot this brainstorm.

## Session Errors

1. **Learnings researcher cited `is_jti_denied`/`denied_jti` as existing primitive (migs 047-050); repo-research grep returned zero hits.** The learning `2026-05-18-supabase-custom-access-token-hook-discriminator.md` may describe a planned or reverted feature. Discrepancy noted; CTO's recommendation (extend 062, not jti deny-list) is the correct path. Compound-time follow-up: re-read that learning and correct or annotate it.
2. **Stale issue bodies on #4304/#4305/#4306.** Three #4233 deferral issues describe tables/columns that don't exist in main. Likely artifact of #4233 brainstorm referencing planned tables (from `feat-adr-embeddings-kb-retrieval-4206`) as if shipped. Premise-reverification at Phase 1.0.5 caught this; without the grep, the bundle would have proposed a sweep migration against ghost tables. Reinforces `2026-05-21-brainstorm-premise-verification-call-site-granularity-and-adr-mutability.md`.

## Resume Prompt

```
/soleur:plan #4307 — Session invalidation on workspace_member removal via revocation-lookup extension off workspace_member_removals (mig 062). Brainstorm: knowledge-base/project/brainstorms/2026-05-22-rls-known-gaps-4233-bundle-brainstorm.md. Spec: knowledge-base/project/specs/feat-rls-known-gaps-4233-bundle/spec.md. Branch: feat-rls-known-gaps-4233-bundle. Worktree: .worktrees/feat-rls-known-gaps-4233-bundle. Draft PR: #4345. Brand-survival threshold: single-user incident. Scope: PR-1 only this session.
```
