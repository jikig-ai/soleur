---
name: feat-adr-044-workspace-connection
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-16-feat-adr-044-workspace-owned-connection-plan.md
---

# Tasks: ADR-044 Workspace-Owned Connection (PR-1)

## Phase 1 — Unified resolver + thread all consumers (atomic)
- [ ] 1.1 Add `resolveActiveWorkspace(userId, supabase)` → `{ok:true, workspaceId, resetFromClaim?} | {ok:false, reason:"db-error"}` in `workspace-resolver.ts` (TR1 invariant: never an unprobed claim id; no MIN(created_at))
- [ ] 1.2 Add `preResolvedActiveWorkspaceId?` to `resolveActiveWorkspacePath` (`workspace-resolver.ts:397`); plumb through `fetchUserWorkspacePath` (`kb-document-resolver.ts:91`)
- [ ] 1.3 `cc-dispatcher.ts`: resolve once before `Promise.all` (~:1533); thread into 4 consumers + the self-heal block at `:1703`; throw `WorkspaceNotReadyError` on `ok:false`
- [ ] 1.4 Confirm self-heal (`ensureWorkspaceRepoCloned`) runs against unified id before the readiness gate (#5240); handle absent + diverged clone states

## Phase 2 — Personal-workspace coverage (verify-only)
- [ ] 2.1 Run read-only membership-null count; record in PR body
- [ ] 2.2 If count > 0: ship one idempotent residual backfill migration (mirror mig 091 keying); else no migration

## Phase 3 — Not-ready copy
- [ ] 3.1 db-error → transient copy at dispatch boundary (no switcher/reconnect)
- [ ] 3.2 repo-readiness layer: member-solo-no-repo → switcher deep link carrying target team id + RLS-name fallback; owner → reconnect
- [ ] 3.3 Remove member "reconnect repository" advice from `go.md` Step 0.0 + `repo-readiness.ts:30`

## Phase 4 — Observability
- [ ] 4.1 `reportSilentFallback` breadcrumb on non-member-claim-reset + self-heal-failed (synthetic Error; op tag; not on db-error/cloning)

## Phase 5 — Owner-gate
- [ ] 5.1 `is_workspace_owner` check on `disconnect` + `setup` routes (403 non-owner)
- [ ] 5.2 Thread `isOwner` into `project-setup-card.tsx`; read-only member variant

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
