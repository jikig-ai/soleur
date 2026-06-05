---
title: "Tasks — fix: C4 + KB write path resolves the ACTIVE workspace"
plan: knowledge-base/project/plans/2026-06-05-fix-c4-kb-write-active-workspace-resolution-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — C4 + KB write-path active-workspace cutover (ADR-044)

> Spec lacks a `lane:` source (no prior spec.md) — defaulted to `cross-domain` (TR2 fail-closed).
> Implement strictly RED → GREEN → REFACTOR. The fix is **entirely inside
> `authenticateAndResolveKbPath`** — no route files change.

## Phase 0 — Preconditions (verify, do not rebuild)

- [ ] 0.1 Re-read `apps/web-platform/server/workspace-resolver.ts` resolver signatures
  (`resolveActiveWorkspaceKbRoot` ~L350, `resolveActiveWorkspaceRepoMeta` ~L473) for drift.
- [ ] 0.2 Re-read the canonical composition precedent: `apps/web-platform/app/api/kb/upload/route.ts:60-107`.
- [ ] 0.3 Confirm `authenticateAndResolveKbPath` `ctx` consumers (c4 PUT route L40-48; kb/file
  PATCH/DELETE) read only stable `ctx` fields → ctx shape is unchanged across the cutover.
- [ ] 0.4 Confirm the RPC (`migration 079`) needs a tenant client (`auth.uid()`) and that
  `resolveActiveWorkspaceRepoMeta` self-mints tenant inside `resolveInstallationId`
  (`resolve-installation-id.ts:35`). → pass service-role to the resolver; RPC step self-mints.
- [ ] 0.5 Read `apps/web-platform/.service-role-allowlist` format.
- [ ] 0.6 FALSIFY the deny-list hypothesis: trace whether any revocation path relies on the helper's
  tenant-mint `denied_jti` → 403 for kb/c4 or kb/file. If load-bearing, retain a minimal mint probe.
- [ ] 0.7 Re-run the `gh issue list --label code-review` overlap query against the final file list;
  confirm #2246 dispositions (Open Code-Review Overlap section) still hold.

## Phase 1 — RED: failing tests

- [ ] 1.1 `apps/web-platform/test/kb-route-helpers.test.ts` — member (active ≠ solo) resolves the
  ACTIVE workspace's owner/repo/workspacePath/installationId, NOT the solo `users` row. FAILS today.
- [ ] 1.2 Same file — solo caller (active == solo) no-regression case.
- [ ] 1.3 Same file — non-member stale claim self-heals to solo (resolver guarantee inherited).
- [ ] 1.4 Same file — status mapping: `access.status` 404/503; `repoMeta.status` 400/404/503 →
  correct client-visible messages.
- [ ] 1.5 NEW `apps/web-platform/test/c4-write-active-workspace-parity.test.ts` — PUT-route resolution
  and concierge resolution yield identical active-workspace owner/repo/workspacePath/installationId.
  (Place under `test/` to match vitest `include:` glob.)

## Phase 2 — GREEN: cut the helper over

- [ ] 2.1 In `apps/web-platform/server/kb-route-helpers.ts`, import `createServiceClient`,
  `resolveActiveWorkspaceKbRoot`, `resolveActiveWorkspaceRepoMeta`.
- [ ] 2.2 Replace the tenant `from("users").select(...)` block + owner/repo parse with the upload
  route composition: `access = resolveActiveWorkspaceKbRoot(user.id, serviceClient)`;
  `repoMeta = resolveActiveWorkspaceRepoMeta(user.id, serviceClient, access.activeWorkspaceId)`;
  assemble `userData` from `access.workspacePath` + `repoMeta.repoUrl` + `repoMeta.githubInstallationId`.
- [ ] 2.3 Use `access.kbRoot` directly (do NOT recompute). Keep path/null-byte/markdown/
  `isPathInWorkspace`/symlink guards unchanged — they now run against the ACTIVE kbRoot.
- [ ] 2.4 Parse owner/repo from `repoMeta.repoUrl` via `.replace(/\.git$/,"").split("/")`.
- [ ] 2.5 Map `access.status` / `repoMeta.status` to the existing `err()` responses (preserve 404/503/400 contract).
- [ ] 2.6 Per Phase 0.6 decision: remove dead tenant-mint try/catch if confirmed unused, OR retain a
  minimal mint probe for the deny-list. Rely on the resolvers' internal `reportSilentFallback` for Sentry mirroring.
- [ ] 2.7 Run `./node_modules/.bin/vitest run apps/web-platform/test/kb-route-helpers.test.ts` until Phase 1 passes.

## Phase 3 — Parity lock + sibling regression

- [ ] 3.1 Finish `c4-write-active-workspace-parity.test.ts` (concierge parity).
- [ ] 3.2 Extend `apps/web-platform/test/kb-delete.test.ts` — PATCH/DELETE targets active workspace for a member.
- [ ] 3.3 Confirm `apps/web-platform/test/kb-security.test.ts` symlink/traversal guards fire against active kbRoot.
- [ ] 3.4 Extend `apps/web-platform/test/server/kb-route-helpers.tenant-isolation.test.ts` — member
  cannot resolve a non-member workspace; helper never reads a workspace id from body/query.

## Phase 4 — REFACTOR + docs + allowlist

- [ ] 4.1 Update `authenticateAndResolveKbPath` + `KbRouteContext` doc-comments (active-workspace, ADR-044, cite upload precedent).
- [ ] 4.2 Add/verify `.service-role-allowlist` entry for the new `createServiceClient()` call-site.
- [ ] 4.3 Opportunistic: if trivial, extract shared owner/repo parse to `server/github-app.ts` (`Refs #2246`); else leave.
- [ ] 4.4 Update #2246 item #13 with a re-evaluation note.

## Phase 5 — Full suite + typecheck

- [ ] 5.1 `tsc --noEmit` clean.
- [ ] 5.2 `./node_modules/.bin/vitest run` web-platform suite green (CSRF coverage, tenant-isolation,
  kb-delete, kb-security, kb-route-helpers, parity).
- [ ] 5.3 security-sentinel review on the diff; fold findings or scope out with rationale.

## Post-merge (operator)

- [ ] P.1 Prod round-trip (AC11): as the confirmed-live member (active `754ee124`/jikig-ai/soleur),
  edit `model.c4`, Save, confirm commit lands in the ACTIVE repo via `gh api /repos/jikig-ai/soleur/commits`
  and that `Elvalio/SAE_for_Soleur` (solo) gets NO new commit. Automation: `gh` CLI — bake into ship verification.
