---
name: feat-adr-044-workspace-connection
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-16-feat-adr-044-workspace-owned-connection-plan.md
---

# Tasks: ADR-044 Workspace-Owned Connection (PR-1)

## Phase 1 — Unified resolver + thread all consumers (atomic)
- [x] 1.1 **Refactor** `resolveActiveWorkspaceIdWithMembership` (`workspace-resolver.ts:344`) → `resolveActiveWorkspace` returning `{ok:true, workspaceId, resetFromClaim?} | {ok:false, reason:"db-error"}` (make silent solo-rewrite explicit; TR1: never an unprobed/sibling id, no MIN(created_at)). Collapse callers (`resolveActiveWorkspacePath:401`, `resolveActiveWorkspaceKbRoot:415`); no silent caller remains
- [x] 1.2 Add `preResolvedActiveWorkspaceId?` to `resolveActiveWorkspacePath:397`; plumb through `fetchUserWorkspacePath` (`kb-document-resolver.ts:91`)
- [x] 1.3 `cc-dispatcher.ts`: resolve once before `Promise.all` (~:1533); thread into 4 consumers + the self-heal block at `:1703` (replace the raw `resolveCurrentWorkspaceId`); throw `WorkspaceNotReadyError` on `ok:false`
- [x] 1.4 Confirm self-heal runs against unified id before the readiness gate (#5240); absent + diverged clone states; reset case → clone dir is `/workspaces/<userId>`

## Phase 2 — Personal-workspace coverage (verify-only)
- [x] 2.1 Run read-only membership-null count; record in PR body
- [x] 2.2 If count > 0: idempotent residual backfill — parent org/workspace rows first (FK ON DELETE RESTRICT), then `workspace_members ... on conflict (workspace_id, user_id) do nothing` (mirror mig 053:228-259 / 091:169-171); else no migration

## Phase 3 — Not-ready copy (dispatch boundary)
- [x] 3.1 Assemble copy in `cc-dispatcher.ts` catch (NOT repo-readiness.ts — pure predicate, no role/team access): db-error → transient (no switcher/reconnect); member-solo-no-repo → switcher deep link carrying `resetFromClaim`/target team id + RLS-name fallback; owner → reconnect
- [x] 3.2 Remove member "reconnect repository" advice from `go.md` Step 0.0; leave `repo-readiness.ts` pure

## Phase 4 — Observability
- [x] 4.1 `reportSilentFallback` breadcrumb on non-member-claim-reset + self-heal-failed (synthetic Error); **dedupe by `(userId, resetFromClaim)` fingerprint**; `extra` = `{activeClaimWorkspaceId, resolvedWorkspaceId}` only; not on db-error/cloning

## Phase 5 — Owner-gate
- [x] 5.1 `is_workspace_owner(p_workspace_id=mutation-target=user.id, p_user_id)` on `disconnect` + `setup` (403 non-owner); document no-op-for-solo in PR-1, load-bearing in PR-2
- [x] 5.2 Thread `isOwner` (`workspaceIdentity.isOwner`) into `project-setup-card.tsx`; read-only member variant (load-bearing FR3 in PR-1)

## Phase 6 — ADR/C4 (plan deliverable)
- [ ] 6.1 Amend ADR-044 (always-enforce-workspace, `status: adopting`, alternatives row)
- [ ] 6.2 Update C4 Container + Component views via `/soleur:architecture` (c4-edit flag)

## Phase 7 — Tests
- [ ] 7.1 Resolver unit tests (4 outcomes incl TR1 db-error-not-claim-id)
- [ ] 7.2 Threading test: all consumers + `:1703` same id; no raw `resolveCurrentWorkspaceId` on dispatch path
- [ ] 7.3 Copy tests (db-error transient; member switcher deep link; owner reconnect)
- [ ] 7.4 Route 403 non-owner; breadcrumb branch-correctness
- [ ] 7.5 `tsc --noEmit` + vitest green

## Post-merge
- [ ] Backfill verified (membership-null = 0); breadcrumb queryable; `Ref #5437`; fast-follow filed for Sentry alert routing
