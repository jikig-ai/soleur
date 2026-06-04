---
feature: feat-one-shot-kb-share-resolver-consolidation-ux
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-04-fix-kb-share-resolver-consolidation-c4-concierge-ux-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — KB share fix + resolver consolidation + C4 Concierge UX

Note: spec.md absent for this branch — `lane` defaulted to `cross-domain` (TR2 fail-closed).
Test runner is **vitest** (NOT bun): `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.

## Phase 0 — Preconditions
- [ ] 0.1 Re-read on `origin/main`: `share/route.ts`, `kb-route-helpers.ts`, `workspace-resolver.ts`, `kb-share.ts`, `upload/route.ts`, `active-repo/route.ts`, `resolve-installation-id.ts` (premise still holds).
- [ ] 0.2 Confirm `workspaces.repo_url` / `workspaces.github_installation_id` exist (migrations 079/080/081) and `github_installation_id` is revoked from `authenticated` grant.
- [ ] 0.3 CPO sign-off recorded (single-user-incident threshold) before /work begins.

## Phase 1 — Workstream A: Observability (ships first / independently verifiable)
- [ ] 1.1 (RED) `test/kb-share.test.ts`: write failing tests asserting each of the 6 validation returns mirrors via `reportSilentFallback` with matching `reason` (invalid-path ×2, symlink-rejected, not-found, not-a-file, too-large). Synthesized fixtures only.
- [ ] 1.2 (GREEN) `server/kb-share.ts`: add `reportSilentFallback(null, { feature:"kb-share", op:"create", message, extra:{ userId, documentPath, reason:<code> } })` to each validation return (lines 203, 212, 225, 232, 245, 253). Match the `kb-share.ts:784` null-err+message shape. Do NOT change HTTP status/body.
- [ ] 1.3 (if A ships strictly before B) inline mirror at `resolveUserKbRoot` `workspace_status !== "ready"` branch (kb-route-helpers.ts:284-295), op `resolveUserKbRoot.workspace-not-ready`; add a test.
- [ ] 1.4 AC-A1/A2 green; `grep -c reportSilentFallback server/kb-share.ts` ≥ 9.

## Phase 2 — Workstream B: Resolver consolidation
- [ ] 2.1 (GREEN) `server/workspace-resolver.ts`: add `resolveActiveWorkspaceRepoMeta(userId, serviceClient)` — active-id via `resolveActiveWorkspaceIdWithMembership`; `workspaces.repo_url` read (mirror active-repo:67-71); installation via `resolveInstallationId(userId, activeWorkspaceId)`. Returns `{ok:false,status:400|404|503}|{ok:true,repoUrl,githubInstallationId}`. Mirror errors.
- [ ] 2.2 (RED→GREEN) `test/server/workspace-resolver-repo-meta.test.ts` (new): solo / shared-member / missing-repo / missing-installation cases. Synthesized mocks.
- [ ] 2.3 `app/api/kb/share/route.ts`: swap `resolveUserKbRoot(user.id)` → `resolveActiveWorkspaceKbRoot(user.id, serviceClient)`; branch 404/503 per `access.status`; pass `access.kbRoot` to `createShare`; use `access.activeWorkspaceId` for the insert workspace_id (drop the second `resolveCurrentWorkspaceId` call — assert equality in a test). Land A's route-level resolver mirror here.
- [ ] 2.4 `app/api/kb/upload/route.ts`: compose `resolveActiveWorkspaceKbRoot` (kbRoot + gate, `syncWorkspace` uses `access.workspacePath`) + `resolveActiveWorkspaceRepoMeta` (owner/repo parsing + GitHub installation). Remove `resolveUserKbRoot` import.
- [ ] 2.5 `server/kb-route-helpers.ts`: remove `resolveUserKbRoot` + `ResolveUserKbRootExtras`/`ResolveUserKbRootResult` types. Keep `authenticateAndResolveKbPath` (scoped OUT — file tracking issue for full ADR-044 consistency).
- [ ] 2.6 Update/clean test refs: `test/kb-share.test.ts` (404/503 cases), `test/kb-upload.test.ts` + `test/kb-upload-route-delegation.test.ts` (solo byte-identical + shared-member), `test/kb-security.test.ts`, `test/kb-route-helpers.test.ts`, `test/sentry-kb-tenant-mint-alert-op-contract.test.ts` (drop `resolveUserKbRoot.tenant-mint` op assertion, keep `authenticateAndResolveKbPath.tenant-mint`), `test/kb-delete.test.ts`, `test/server/kb-route-helpers.tenant-isolation.test.ts`.
- [ ] 2.7 AC-B1: `grep -rn resolveUserKbRoot apps/web-platform --include="*.ts" | grep -v '\.test\.'` → 0. AC-B2: same over `test/` → 0.
- [ ] 2.8 AC-B3: full suite green `cd apps/web-platform && ./node_modules/.bin/vitest run`.

## Phase 3 — Workstream C: C4 Concierge UX
- [ ] 3.1 `components/kb/kb-chat-context.tsx`: add embedded-Concierge signal(s) (e.g. `embeddedConciergeOpen` + `revealEmbeddedConcierge`/collapse), optional for test-mock back-compat.
- [ ] 3.2 `app/(dashboard)/dashboard/kb/[...path]/page.tsx`: on C4 branch keep `setSuppressSidebar(true)` for side-panel mount; wire embedded-Concierge reveal; stop using `suppressSidebar` to hide the trigger.
- [ ] 3.3 `components/kb/kb-chat-trigger.tsx`: when embedded Concierge present, trigger reveals it (call context reveal) instead of `return null`; md path unchanged.
- [ ] 3.4 `components/kb/c4-workspace.tsx`: read reveal/collapse from context; remove floating "Open Concierge" pill (66-78); wire chevron (148) + `KbChatContent.onClose` (165) to context collapse. Keep Concierge/Code tabs.
- [ ] 3.5 (RED→GREEN) `test/c4-workspace.test.tsx`: C4-C1 single `[data-kb-chat]`; C4-C2 no "Open Concierge"; C4-C3 trigger reveals; C4-C4 X/chevron collapse + thread persists; C4-C5 md no-regression. Mock `next/navigation` incl. `useSearchParams`.
- [ ] 3.6 Wireframe AC-C6: `c4-concierge-header-consistency.pen` committed (DONE this cycle); refine fidelity via ux-design-lead if available.

## Phase 4 — Validation + review
- [ ] 4.1 Local repro BEFORE+AFTER (qa local-auth `authenticated` Playwright project OR MCP bot-signin recipe): Generate link on a fresh md doc AND c4-model.md; capture `/api/kb/share` POST status+body. Done = token minted for BOTH.
- [ ] 4.2 security-sentinel R1–R6 PASS (workspace boundary, IDOR, membership scoping). user-impact-reviewer at review.
- [ ] 4.3 If A ships separately: confirm the instrumented Sentry signal identifies the failing branch before claiming B fixed it.
- [ ] 4.4 File tracking issue: migrate `authenticateAndResolveKbPath` to ADR-044 resolver (deferred scope-out).

## Phase 5 — Ship
- [ ] 5.1 `/soleur:ship`; PR body notes the upload shared-member behavior change + the scoped-out `authenticateAndResolveKbPath` tracking issue.
