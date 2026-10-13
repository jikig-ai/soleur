---
feature: feat-one-shot-concierge-clone-self-heal-order
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-08-fix-concierge-clone-consumes-self-healed-installation-plan.md
status: pending
---

# Tasks — Workspace clone must consume the self-healed installation

Derived from the finalized plan. Pure ordering fix in `cc-dispatcher.ts` + regression coverage. No new files, no infra.

## Phase 1 — Tests first (RED)

- [ ] 1.1 In `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`, hoist the `ensureWorkspaceRepoCloned` mock (currently inline anonymous `vi.fn` at ~:152) to a named top-level `const mockEnsureWorkspaceRepoCloned`, matching the sibling `mock*` consts; reference it in the `vi.mock("@/server/ensure-workspace-repo", …)` factory; clear it in `beforeEach`.
- [ ] 1.2 Extend the existing `installation self-heal` describe block (~:702) — mismatch case: assert `mockEnsureWorkspaceRepoCloned` called with `installationId: OWNER` (AC1, RED against `main`).
- [ ] 1.3 Deny case: assert clone called with `installationId: STORED` when `findRepoOwnerInstallationForUser` → `{ null, "not-member" }` (AC2).
- [ ] 1.4 Already-correct case: assert clone called with stored install, no owner probe (AC3).
- [ ] 1.5 Probe-throw case: assert clone still called (with STORED) and dispatch proceeds when `getInstallationAccount` rejects (AC4).
- [ ] 1.6 Lockstep assertion: clone + mint receive the SAME install id per branch (AC5).
- [ ] 1.7 Token-substring negative assertion on moved observability payloads — no `ghs_`/`gho_`/`ghp_` (AC6).
- [ ] 1.8 Run the new tests → confirm AC1 fails (clone currently gets STORED), others as expected.

## Phase 2 — Fix (GREEN)

- [ ] 2.1 In `apps/web-platform/server/cc-dispatcher.ts`, cut the `connectedOwner`/`connectedRepo` parse (~:1354-1368) AND the self-heal block (~:1394-1459) as one contiguous unit.
- [ ] 2.2 Paste both immediately after the `Promise.all` destructure + ack-posture setup, BEFORE the `ensureWorkspaceRepoCloned` call.
- [ ] 2.3 Change the clone arg from `installationId` to `effectiveInstallationId`; update the clone-call comment to note it now consumes the self-healed install.
- [ ] 2.4 Leave the GH_TOKEN mint (~:1461-1475) and C4 write block (~:1477+) in place; do NOT move the `autonomous_posture` send / ack-posture registration.
- [ ] 2.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — confirm `effectiveInstallationId`/`connectedOwner`/`connectedRepo` are in scope at every later read site (mint, C4).
- [ ] 2.6 Re-run Phase 1 tests → all green.

## Phase 3 — Verify & regression

- [ ] 3.1 Read `apps/web-platform/test/cc-dispatcher-self-heal-observability.test.ts`; if it asserts clone-vs-self-heal ordering, update for the new order (self-heal now precedes clone); else leave unchanged (AC7).
- [ ] 3.2 Full suite: `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher-real-factory.test.ts test/cc-dispatcher-self-heal-observability.test.ts test/ensure-workspace-repo.test.ts test/cc-dispatcher-gh-403-directive.test.ts test/github-app-mint-observability.test.ts` → green (AC8).
- [ ] 3.3 `tsc --noEmit` clean (AC8).
- [ ] 3.4 PR body: `Ref` the screenshot cascade; note the entitlement-gate invariant (clone consumes already-gated `effectiveInstallationId`, no new promotion path).
