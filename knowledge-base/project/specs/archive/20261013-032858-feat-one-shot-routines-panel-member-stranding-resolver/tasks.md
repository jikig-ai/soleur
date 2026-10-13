---
title: "Tasks — routines-panel member stranding resolver (ADR-044 PR-3)"
plan: knowledge-base/project/plans/2026-06-22-fix-routines-panel-member-stranding-resolver-plan.md
branch: feat-one-shot-routines-panel-member-stranding-resolver
lane: single-domain
brand_survival_threshold: single-user incident
---

# Tasks

## Phase 0 — Preconditions (verify at HEAD before coding)

- [ ] 0.1 Re-confirm the three bare-`userId` calls remain in `apps/web-platform/server/cc-reprovision.ts:39-43` (`fetchUserWorkspacePath(userId)`, `resolveInstallationId(userId)`, `getCurrentRepoUrl(userId)`).
- [ ] 0.2 Re-confirm `RepoResolverDivergenceOp` union members in `apps/web-platform/server/repo-resolver-divergence.ts` (`non-member-claim-reset`, `self-heal-failed`, `connected-null-install-at-dispatch`).
- [ ] 0.3 Re-confirm `cc-reprovision.test.ts` mocks all three consumers (`:32-49`) and hoisted spies (`:16-30`).
- [ ] 0.4 Run Open Code-Review Overlap: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/cr.json`, then `jq` for `cc-reprovision.ts` / `repo-resolver-divergence.ts` / `cc-dispatcher.ts`. Record result in PR body.
- [ ] 0.5 Read all three `.c4` files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) and re-confirm "no C4 impact" (Member + GitHub App + workspaces/user_session_state already modeled).

## Phase 1 — RED (write failing tests)

- [ ] 1.1 Add to `apps/web-platform/test/cc-reprovision.test.ts`: two new `vi.mock`s — `@/lib/supabase/tenant` (`getFreshTenantClient`) and `@/server/workspace-resolver` (`resolveActiveWorkspace`) — plus hoisted spies.
- [ ] 1.2 AC3(a) solo-owner: claim===userId → one resolve, no membership probe; path/install/repo all key `userId`; no breadcrumb.
- [ ] 1.3 AC3(b) member-of-team: team claim, membership confirmed → path/install/repo all key TEAM id (single id, no split).
- [ ] 1.4 AC3(c) non-member reset: team claim, probe null → path/install/repo all key `userId`; breadcrumb op=`reprovision-non-member-claim-reset` fires (mirror `repo-resolver-divergence.test.ts:19-42`, assert no repoUrl/installationId in `extra`).
- [ ] 1.5 AC3(d) membership-probe db-error: `resolveActiveWorkspace` → `{ok:false}` → reprovision SKIPPED, returns `"ok"`, NO clone attempted, error mirrored.
- [ ] 1.6 Add a case to `apps/web-platform/test/server/repo-resolver-divergence.test.ts` for the new op (dedup key `op:userId:activeClaimWorkspaceId`; no repoUrl/install leak).
- [ ] 1.7 Confirm all new tests FAIL against current `cc-reprovision.ts` (RED).

## Phase 2 — GREEN (implement)

- [ ] 2.1 Add `"reprovision-non-member-claim-reset"` to `RepoResolverDivergenceOp` union in `repo-resolver-divergence.ts` (+ JSDoc op list if present).
- [ ] 2.2 Refactor `reprovisionWorkspaceOnDispatch` (`cc-reprovision.ts`): import `getFreshTenantClient` (`@/lib/supabase/tenant`), `resolveActiveWorkspace` (`./workspace-resolver`), `reportRepoResolverDivergence` (`./repo-resolver-divergence`). One `getFreshTenantClient(userId)` + one `resolveActiveWorkspace(userId, tenant)`; `{ok:false}` → return `"ok"` (skip); thread `activeWorkspaceId` into `fetchUserWorkspacePath(userId, id)`, `resolveInstallationId(userId, id)`, `getCurrentRepoUrl(userId, id)`; emit breadcrumb on `resetFromClaim`. Leave `resolveEffectiveInstallationId({userId, installationId, repoUrl})` unchanged (no workspace re-resolve).
- [ ] 2.3 All Phase 1 tests GREEN.

## Phase 3 — Refactor + ADR

- [ ] 3.1 Amend `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` with the PR-3 reprovision-path closure entry (single-resolve-then-thread on warm+cold per-dispatch reprovision; new breadcrumb op; db-error→skip rationale).
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run` full suite green.

## Phase 4 — Ship

- [ ] 4.1 PR body: `Ref`/`Closes` per the post-merge AC9 disposition; record the Phase 0.4 overlap result; note CPO sign-off (single-user-incident threshold) and that `user-impact-reviewer` runs at review.
- [ ] 4.2 Multi-agent review (security / user-impact / pattern / architecture) per single-user-incident threshold.
