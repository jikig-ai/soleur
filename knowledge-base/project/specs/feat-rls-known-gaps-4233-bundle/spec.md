---
feature: rls-known-gaps-4233-bundle
status: brainstormed
created: 2026-05-22
brand_survival_threshold: single-user incident
lane: cross-domain
parent_issues:
  - "#4307 (real, p2-medium — PR-1 scope)"
  - "#4318 (real residual at storage-bucket layer — PR-2 scope)"
paper_close_issues:
  - "#4304 kb_chunks RLS (stale premise: table does not exist)"
  - "#4305 kb_files RLS (stale premise: table does not exist)"
  - "#4306 runtime_cost_state RLS (stale premise: not a table; columns on public.users)"
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-22-rls-known-gaps-4233-bundle-brainstorm.md
domain_review:
  cpo: signed-off
  clo: signed-off
  cto: signed-off
---

# feat: rls-known-gaps-4233-bundle

## Problem Statement

PR #4288 (identity-rbac-reviewer agent, merged 2026-05-22) introduced an `info`-severity review surface that lights up on every identity-touching PR until the 5 carried-forward #4233 known gaps close. Three of those issues describe substrates that do not exist in main; closing them requires no engineering work. The remaining two — session invalidation on workspace-member removal (#4307) and the `chat-attachments` storage-bucket folder predicate (the real residual of #4318) — are latent today because `TEAM_WORKSPACE_INVITE_ENABLED` is OFF in prd, but go active the moment the invite UI ships. PR-1 must land before the flag flip; PR-2 should land in the same release or shortly after.

## Goals

- **G1.** Ship per-user session invalidation on `workspace_member` row delete or role change such that effect is observable within seconds of removal (CPO §4 constraint).
- **G2.** Migrate `chat-attachments` storage bucket folder predicate from `auth.uid()::text` to a workspace-membership-aware lookup so workspace co-members can read each others' attachments per ADR-038, and ONLY workspace co-members can.
- **G3.** Co-edit `knowledge-base/legal/article-30-register.md` PA amendments in the same PR as each migration so Art. 30(1) record-keeping stays in sync with TOM changes (CLO §1).
- **G4.** Wire a workflow gate that blocks `TEAM_WORKSPACE_INVITE_ENABLED` from flipping ON in prd until #4307 is closed (CLO §3 binding).
- **G5.** Update identity-rbac-reviewer agent body to demote R4 (session invalidation) from info → enforced/high and close the R1 cascade-documentation note for attachments after both PRs ship.

## Non-Goals

- **NG1.** No JWKS rotation, no shorter JWT TTL, no separate session-deny-list table. Mechanism is per-user revocation lookup against `workspace_member_removals` (mig 062) extended with `revoked_after`.
- **NG2.** No Option B (`workspace_id` direct column on `attachments`). The cascade via `is_message_owner` is workspace-aware as of mig 059 / ADR-038.
- **NG3.** No new `kb_files` / `kb_chunks` / `runtime_cost_state` table RLS work. Those issues' premises are stale; RLS for `kb_files` / `kb_chunks` (if those tables ever ship) belongs in the migration that creates them (likely `feat-adr-embeddings-kb-retrieval-4206` scope).
- **NG4.** No in-product transparency UI in this bundle. The disclosure modal at first invite-send / first invite-accept (CPO §3) is a follow-up product surface tracked separately.
- **NG5.** No bucket re-layout. Storage path prefix stays `user_id`-based; the policy predicate adds a workspace-membership check via the message_attachments → messages.workspace_id chain (Open Q #1, sub-option (a)).
- **NG6.** No third PR for #4304/#4305/#4306. Those are paper-closes; this spec only delivers PR-1 + PR-2.

## Functional Requirements

### PR-1 — Session invalidation (#4307)

- **FR1.1.** Migration 064 adds `revoked_after timestamptz` to `public.workspace_member_removals` (one row already exists per removal; populate `revoked_after = removed_at` for all existing rows).
- **FR1.2.** `public.remove_workspace_member` RPC (mig 062) updated to set `revoked_after = now()` on the new row in the same SECURITY DEFINER body.
- **FR1.3.** New SECURITY DEFINER function `public.is_member_revoked(p_user_id uuid, p_workspace_id uuid, p_jwt_iat timestamptz) RETURNS boolean` returns TRUE iff a `workspace_member_removals` row exists for the user/workspace pair with `revoked_after > p_jwt_iat`. Pinned `search_path = public, pg_temp`; REVOKE all from PUBLIC/anon/authenticated/service_role; GRANT EXECUTE to `authenticated`.
- **FR1.4.** Middleware extension at `apps/web-platform/middleware.ts:121-123` calls `is_member_revoked` after `getUser()` resolution and before workspace-scoped route handling. On TRUE: clear session cookie, redirect to `/membership-revoked`. Cached lookup with 5-10s TTL (Open Q #2 resolves exact value during plan Phase 0).
- **FR1.5.** Role-change path: `update_workspace_member_role` (or equivalent) RPC inserts a `workspace_member_removals` row with `revocation_reason = 'role-changed'` so demotions invalidate the prior JWT's role claim.
- **FR1.6.** `membership-revoked-screen.tsx` (`apps/web-platform/components/dashboard/membership-revoked-screen.tsx:10-19`) updated to reflect "your access was revoked just now" vs the current "until the access token refreshes" copy.

### PR-2 — Storage bucket workspace-keyed predicate (#4318 residual)

- **FR2.1.** Migration 065 replaces the `chat-attachments` bucket SELECT policy at mig 045:54-60. New predicate: a SECURITY DEFINER helper `public.can_read_attachment_path(p_path text)` that derives the owning `user_id` from `(storage.foldername(p_path))[1]::uuid`, looks up the `workspace_id` of any `message_attachment` with that storage_path, and returns TRUE iff `auth.uid()` is a workspace member of that workspace.
- **FR2.2.** Storage bucket INSERT/UPDATE/DELETE policies (per 2026-05-16 PR-D Key Decision #4) retain `auth.uid() = (storage.foldername(name))[1]::uuid` (write-side stays per-user; only the reader semantic widens to workspace co-members).
- **FR2.3.** Pre-merge orphan-path audit SQL: count `message_attachments` rows where the storage path's first folder segment is NOT a current workspace member's `user_id`. Surface in PR body; non-zero blocks merge until quarantine plan documented.
- **FR2.4.** `attachment-display.tsx` permanent-skeleton fix (precedent: 2026-05-16 PR-D Key Decision #10). `.catch(() => {})` becomes `.catch((err) => { reportSilentFallback(err, {tag: 'storage-rls-deny'}); setLoadFailed(true); })` with retry affordance.

### Shared

- **FR3.1.** Each PR ships its Art. 30 amendment co-edit:
    - PR-1: amend `knowledge-base/legal/article-30-register.md` PA-19 §(g) TOMs to document revocation-lookup. Add line to PA-20 (`workspace_member_actions`) if role-change path writes there.
    - PR-2: amend PA-2 §(c) categories to include "binary attachment content" if not already covered, and §(g) TOMs to document workspace-keyed bucket SELECT policy.
- **FR3.2.** Workflow gate (G4) implementation: `plugins/soleur/skills/admin-ip-refresh` precedent — the flag-set skill MUST query `gh issue view 4307 --json state` and refuse if not CLOSED.

## Technical Requirements

- **TR1.** Migration number 064 for PR-1, 065 for PR-2. Migration 063 is taken by both main (`workspace_member_actions`) and worktree `feat-byok-delegations-4232` — serialize against the in-flight 063.
- **TR2.** Both migrations use the migration 059 sweep pattern: ALTER + backfill + GET DIAGNOSTICS rc + RAISE NOTICE audit per `2026-03-20-gdpr-remediation-migration-discriminator-strategy.md`.
- **TR3.** Per `cq-pg-security-definer-search-path-pin-pg-temp`, all new SECURITY DEFINER helpers (`is_member_revoked`, `can_read_attachment_path`) pin `SET search_path = public, pg_temp`.
- **TR4.** Per `hr-write-boundary-sentinel-sweep-all-write-sites`, PR-1 enumerates the FULL output of `git grep -nE "workspace_members.*(DELETE|UPDATE)" apps/web-platform/` and confirms every site reaches the revocation-writing path.
- **TR5.** Per learning `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`: each new deny test ships with a positive control (same payload, owner's own workspace, expect success) AND a service-role re-read confirming row absence on deny.
- **TR6.** Per learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`: integration tests run with `TENANT_INTEGRATION_TEST=1` against a real Supabase project (CI tenant-isolation job from PR-D / #3869 item 6).
- **TR7.** Per `cq-silent-fallback-must-mirror-to-sentry`: FR2.4's `.catch` mirror calls `reportSilentFallback` with `setUser({id: userId})` so the breadcrumb is attributable.
- **TR8.** Storage path orphan audit (FR2.3) runs as a one-shot SQL block in the PR-2 description, NOT as a migration step. Result documented in PR body before requesting review.
- **TR9.** identity-rbac-reviewer agent body update (G5) ships in the same PR as PR-2 (after both PR-1 and PR-2's substrate is in main). One PR-3 for the agent-body update + paper-close housekeeping.

## Acceptance Criteria

- **AC1 (PR-1).** Removing a workspace member via `remove_workspace_member` RPC → that user's next authenticated request within ≤10s sees a 302 to `/membership-revoked` and a cleared session cookie. Integration test exercises the cache-stale window.
- **AC2 (PR-1).** Demoting a workspace member from owner to member via the role-change path → that user's next authenticated request within ≤10s reflects the new role (cannot exercise owner-only RPCs).
- **AC3 (PR-1).** Service-role writers (cost-writer, account-delete, dsar-export) are NOT affected by the new middleware revocation lookup (they bypass middleware by design).
- **AC4 (PR-1).** Art. 30 PA-19/PA-20 §(g) amendments present in the same commit set; CLO line-edit visible in PR diff.
- **AC5 (PR-2).** Workspace co-member B can `.storage.download()` co-member A's attachment via the public attachment URL or signed-URL minter. Workspace non-member C cannot.
- **AC6 (PR-2).** Pre-merge orphan-path audit SQL run, result pasted in PR body. Non-zero count blocks merge until quarantine plan documented.
- **AC7 (PR-2).** `attachment-display.tsx` permanent-skeleton bug fixed — failed downloads surface "preview unavailable, click to retry" affordance.
- **AC8 (PR-2).** Art. 30 PA-2 §(c) + §(g) amendments present in the same commit set; CLO line-edit visible in PR diff.
- **AC9 (PR-3 / housekeeping).** identity-rbac-reviewer agent body updated: R4 demoted info → enforced; R1 cascade note for attachments removed. Paper-closes #4304/#4305/#4306 in same PR (with reverification comment already appended by brainstorm).
- **AC10 (workflow gate).** `TEAM_WORKSPACE_INVITE_ENABLED` flag-set skill queries #4307 state; if not CLOSED, refuses. Test asserts refusal.

## Open Questions

1. Storage-bucket predicate shape — sub-option (a) keep `user_id` path + add workspace-membership check, or (b) re-layout bucket with `workspace_id` prefix + backfill. Defer to PR-2 plan Phase 0. Default = (a) per Key Decision #5.
2. Revocation-lookup cache TTL value. Default = 5s (CPO constraint "effective within seconds"). Plan-Phase-0 spike measures p99 DB round-trip; if cache absent path stays <50ms, drop the cache entirely.
3. Role-change path: does an existing RPC update `workspace_members.role` or do we add `update_workspace_member_role`? Confirm at plan Phase 0.
4. `feat-adr-embeddings-kb-retrieval-4206` coordination: file cross-link issue/comment noting that any `kb_files`/`kb_chunks` tables must ship workspace-keyed RLS in the same migration that creates them.

## Sequencing

1. **PR-1 (this session → plan):** #4307 session invalidation. Lands first per CLO §3 binding (blocks flag flip).
2. **PR-2 (next session):** #4318 storage-bucket. Lands in same release as PR-1 or before invite UI flips ON.
3. **PR-3 (housekeeping):** identity-rbac-reviewer agent body update + paper-close #4304/#4305/#4306. Lands after PR-1 + PR-2.

## Out of Scope (with file pointers)

- New `kb_files`/`kb_chunks` tables: see worktree `feat-adr-embeddings-kb-retrieval-4206`.
- `runtime_cost_state` per-workspace authenticated read view: file follow-up if/when first user-facing cost panel ships (re-evaluation criterion from #4306 already specifies "first feature that authenticates a user-facing read against `runtime_cost_state`").
- Direct `workspace_id` column on `attachments` (Option B from #4318): NOT NEEDED; cascade via mig 059 is sufficient.
- Disclosure modal at first invite (CPO §3): follow-up product surface, file under MU4 hardening when invite UI scope opens.
