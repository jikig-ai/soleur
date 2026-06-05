---
title: "Tasks — migrate authenticateAndResolveKbPath to ADR-044 resolvers"
issue: 4956
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-05-refactor-authenticate-kb-path-adr044-resolver-plan.md
---

# Tasks — `authenticateAndResolveKbPath` → ADR-044 resolvers (#4956)

Derived from the finalized (deepened) plan. Brand-survival threshold: single-user
incident — run the security/integrity/architecture review triad before merge.

## Phase 0 — Preconditions (read-before-write, RED before GREEN)

1.1. Confirm only the two App-Router routes + the CSRF test reference the helper:
   `git grep -n "authenticateAndResolveKbPath" apps/web-platform -- ':!**/test/**' ':!knowledge-base/**'`
   → expect `kb/file/[...path]/route.ts`, `kb/c4/[...path]/route.ts`,
   `infra/sentry/issue-alerts.tf` (comment + IS_IN), `kb-route-helpers.ts`.
1.2. Confirm `kb-sync.tenant-mint` still lives in `app/api/kb/sync/route.ts:62` (the
   surviving live tenant-mint surface that keeps the alert armed).
1.3. Read the three client error branches to lock message parity:
   `components/kb/file-tree.tsx:330-348`, `components/kb/c4-shared.tsx:271` — all use
   `!res.ok` + `body.error` (no numeric-code switch).
1.4. Read the allowlist gate: `apps/web-platform/scripts/service-role-allowlist-gate.sh`
   and `.service-role-allowlist:66` (removal comment listing `kb-route-helpers`).

## Phase 1 — Migrate the helper (Files to Edit #1)

2.1. In `apps/web-platform/server/kb-route-helpers.ts`, replace the
   `getFreshTenantClient` + `users` SELECT + `resolveInstallationId` fallback block
   (lines ~97-140) with the precedent block (plan §Precedent Diff): `createServiceClient()`
   → `resolveActiveWorkspaceKbRoot` → `resolveActiveWorkspaceRepoMeta(... access.activeWorkspaceId)`.
2.2. Build `userData = { workspace_path: access.workspacePath, repo_url: repoMeta.repoUrl,
   github_installation_id: repoMeta.githubInstallationId }`.
2.3. Map resolver-not-ok to the LEGACY message strings (message parity, plan AC10):
   `resolveActiveWorkspaceKbRoot` 503 → "Workspace not ready", 404 → "No repository
   connected"; `resolveActiveWorkspaceRepoMeta` 400/404 → "No repository connected",
   503 → "Workspace not ready".
2.4. Keep the CSRF + auth probe + path/null-byte/markdown/symlink/owner-repo block
   byte-identical. Keep the `KbRouteContext` return shape unchanged.
2.5. Remove now-dead imports: `getFreshTenantClient`, `RuntimeAuthError`, the dynamic
   `resolveInstallationId` import, and the `authenticateAndResolveKbPath.tenant-mint`
   `reportSilentFallback` mirror. Add `createServiceClient` + the two resolver imports.
   Do NOT let resolver imports leak into `workspace-sync.ts` (WS-bundle boundary).

## Phase 2 — Observability contract (Files to Edit #2, #3)

3.1. `apps/web-platform/infra/sentry/issue-alerts.tf` — drop
   `authenticateAndResolveKbPath.tenant-mint,` from the IS_IN value (line ~607); leave
   `kb-sync.tenant-mint`. Update the block comment (lines ~565-569) to state the helper
   now reads via service-role resolvers (no tenant-mint surface).
3.2. `apps/web-platform/test/sentry-kb-tenant-mint-alert-op-contract.test.ts` — remove
   the `authenticateAndResolveKbPath.tenant-mint` entry from `OP_SLUGS` and update the
   comment. The single surviving slug still proves the alert is armed (emit-site +
   filter-block assertions).

## Phase 3 — Allowlist (Files to Edit #4)

4.1. `apps/web-platform/.service-role-allowlist` — RE-ADD the verbatim line
   `apps/web-platform/server/kb-route-helpers.ts` with a one-line justification (#4956
   ADR-044 migration restores a service-role read for the membership-scoped resolvers).
4.2. Update the removal comment at `.service-role-allowlist:66` so it no longer lists
   `kb-route-helpers` among removed files.

## Phase 4 — Tests (Files to Edit #5)

5.1. `apps/web-platform/test/kb-route-helpers.test.ts` — rewrite the
   `authenticateAndResolveKbPath` describe: mock both resolvers; cover happy path
   (populated `KbRouteContext`), CSRF/401/path/markdown/symlink/owner-repo branches,
   resolver-not-ok → message-parity, and member-vs-solo active-id resolution.
5.2. DELETE the `tenant-mint failure (reverted)` describe block (no tenant-mint surface
   remains in this helper).
5.3. Add a c4 active-path test note: `writeC4Diagram` / `renderC4Model(workspacePath)`
   operates on `access.workspacePath` (the active workspace), not `users.workspace_path`.

## Phase 5 — Verification gates (Acceptance Criteria)

6.1. AC1 — `git grep getFreshTenantClient server/kb-route-helpers.ts` = 0.
6.2. AC2 — `git grep authenticateAndResolveKbPath.tenant-mint apps/web-platform`
   (excl. knowledge-base) = 0.
6.3. AC3/AC4 — Sentry IS_IN narrowed; op-contract test green.
6.4. AC5/AC6/AC7 — `kb-route-helpers.test.ts`, `csrf-coverage.test.ts`, and the
   allowlist gate (`test/ci/service-role-allowlist-gate.test.sh`) all green.
6.5. AC8 — `npx tsc --noEmit` clean.
6.6. AC9 — full `apps/web-platform` vitest suite green (`./node_modules/.bin/vitest run`).
6.7. AC10 — message parity confirmed (clients render `body.error`).

## Phase 6 — Review + ship

7.1. Run the single-user-incident review triad (data-integrity-guardian +
   security-sentinel + architecture-strategist) + `user-impact-reviewer`.
7.2. `/soleur:gdpr-gate` advisory pass (credential read-path) — expect "strengthens
   isolation, no new processing activity".
7.3. PR body: `Ref #4956` if the Sentry apply is post-merge; `gh issue close 4956`
   after the prod apply succeeds (or `Closes #4956` if apply-on-merge is confirmed at
   ship time).
