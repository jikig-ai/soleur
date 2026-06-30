---
feature: feat-one-shot-reconcile-on-push-reclone-corrupt-git
lane: single-domain
plan: knowledge-base/project/plans/2026-06-29-fix-reconcile-on-push-reclone-corrupt-git-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — fix(workspace): reconcile-on-push must re-clone a missing/corrupt `.git`

Derived from the finalized + deepened plan. Single-domain server-side bug fix.

## Phase 0 — Preconditions
- [x] 0.1 `git grep -n "workspaceDirExists" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — confirm the only use is the gate at line 309 + the helper at 103-110; `git grep -n "\bfs\." <same file>` to confirm `node:fs` import is removable.
- [x] 0.2 Confirm exports: `isValidGitWorkTree` (`@/server/git-worktree-validity`), `ensureWorkspaceRepoCloned` + `EnsureWorkspaceRepoArgs` (`@/server/ensure-workspace-repo`).
- [x] 0.3 Confirm `Sentry.addBreadcrumb` import precedent (`team-workspace-boot.ts:11`); import `* as Sentry from "@sentry/nextjs"`.

## Phase 1 — Validity-aware readiness gate + re-clone
- [x] 1.1 Write the 5 failing tests FIRST (Phase 2 below) — RED.
- [x] 1.2 Replace the `workspaceDirExists` gate (workspace-reconcile-on-push.ts:305-329) with the `isValidGitWorkTree` gate; VALID → existing `syncWorkspace`; INVALID/ABSENT → `ensureWorkspaceRepoCloned({ userId: ownerId ?? ws.id, workspacePath, installationId, repoUrl: targetRepoUrl })`.
- [x] 1.3 Compute `recovered = outcome === "ok" && isValidGitWorkTree(workspacePath)` (invariant re-probe, not the `"ok"` proxy).
- [x] 1.4 Emit `Sentry.addBreadcrumb` (category `workspace-reconcile-push`, op `corrupt-worktree-reclone`, `data.recovered`) — best-effort context only; do NOT add a captureException (no double-page).
- [x] 1.5 Write audit rows via the existing `writeAuditRow` closure: recovered → `ok:true, recovered:true`; not-recovered → `ok:false, error_class: WORKSPACE_NOT_READY`.
- [x] 1.6 Add imports (`isValidGitWorkTree`, `ensureWorkspaceRepoCloned`, `* as Sentry`); remove `workspaceDirExists` helper + unused `node:fs` import (gated on 0.1).
- [x] 1.7 Update `ReprovisionOutcome` docstring at `ensure-workspace-repo.ts:44-47` — reconcile is now a second consumer that reads the `"ok"` variant (docstring only; no type/behavior change).

## Phase 2 — Tests (extend test/server/inngest/workspace-reconcile-on-push.test.ts)
- [x] 2.1 Add module mocks: `@/server/git-worktree-validity` (isValidGitWorkTree spy), `@/server/ensure-workspace-repo` (ensureWorkspaceRepoCloned spy), `@sentry/nextjs` (addBreadcrumb spy).
- [x] 2.2 Case 1 — VALID `.git` → normal sync, NO reclone (ensure spy not called; no breadcrumb).
- [x] 2.3 Case 2 — invalid OR absent `.git` → reclone; ensure spy called with the 4-arg shape; `recovered:true`; covers the concurrent-racer early-return (probe false→true). syncWorkspace NOT called.
- [x] 2.4 Case 3 — populated-but-broken → ensure returns `"failed"`; audit `WORKSPACE_NOT_READY`; breadcrumb `recovered:false`; not destroyed.
- [x] 2.5 Case 4 — benign `"ok"` that did NOT heal (re-probe stays false) → `recovered:false` (invariant-not-proxy).
- [x] 2.6 Case 5 — owner-less workspace → `userId === ws.id`; audit via `appendKbSyncRowForWorkspaceSpy`.

## Phase 3 — ADR-044 amendment + C4 confirm
- [x] 3.1 Append `## Amendment 2026-06-29` to ADR-044: readiness gates on worktree VALIDITY + re-clone (extension of the 2026-06-19 validity amendment to the reconcile surface).
- [x] 3.2 Read `model.c4`, `views.c4`, `spec.c4`; confirm GitHub clone edge + workspace store + kb_sync_history already modeled → no `.c4` edit (cite the enumeration). If any element description is falsified, fix + run c4-code-syntax/c4-render tests.

## Phase 4 — Verify
- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] 4.2 `./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts`.
- [x] 4.3 `./node_modules/.bin/vitest run test/sentry-workspace-sync-health-alert-op-contract.test.ts` — assert ABSENCE of `skip-not-ready` on the reclone path.

## Notes
- Brand-survival threshold single-user incident → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review-time.
- PR body: `Ref #5591` (NOT `Closes`). Do NOT cite #4826.
