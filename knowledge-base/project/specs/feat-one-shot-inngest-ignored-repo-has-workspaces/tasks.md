---
title: "Tasks — fix ignored-repo-has-workspaces Sentry noise"
branch: feat-one-shot-inngest-ignored-repo-has-workspaces
lane: single-domain
plan: knowledge-base/project/plans/2026-06-01-fix-reconcile-ignored-repo-has-workspaces-sentry-noise-plan.md
---

# Tasks — stop `ignored-repo-has-workspaces` Sentry warning flood

Derived from the finalized plan. Implement in order; the test contract change (Phase 2) is written first (RED) per `cq-write-failing-tests-before`, then the code change (Phase 1) turns it GREEN.

## Phase 1 — Code change

- [ ] 1.1 In `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`, replace the `warnSilentFallback(new Error("ignored repo has connected workspaces"), {...})` call (lines ~222-230, inside the `if (isIgnoredReconcileRepo(targetRepoUrl))` guard at the post-resolution / `rows.length > 0` site) with a `logger.info({...}, "...")` carrying `feature`, `op: "ignored-repo-has-workspaces"`, `installationId`, `deliveryId`, `targetRepoUrl`, `workspaceCount: rows.length`.
- [ ] 1.2 Rewrite the explanatory comment (lines ~217-221) to state this is the expected dogfooding steady state, reconciled normally, with the info-log as the on-demand audit trail (not a Sentry page). See plan Phase 1 pseudocode.
- [ ] 1.3 `grep -n "warnSilentFallback" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — confirm the import (line ~22) is STILL needed by the deadletter path (line ~132). Do NOT remove the import (`cq-ref-removal-sweep-cleanup-closures`).

## Phase 2 — Test contract (write the assertion change here; pairs with 1.1)

- [ ] 2.1 In `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts`, update the test "RECONCILES an ignored repo that HAS a connected workspace, and warns once" (lines ~350-385): keep `expect(result).toEqual({ ok: true, synced: 1 })` and the `syncWorkspaceSpy` / `APPENDS` assertions.
- [ ] 2.2 Change the warn assertion to `expect(warnSilentFallbackSpy).not.toHaveBeenCalled()` and add `expect(reportSilentFallbackSpy).not.toHaveBeenCalled()`.
- [ ] 2.3 Add `expect(loggerInfoSpy).toHaveBeenCalledWith(expect.objectContaining({ op: "ignored-repo-has-workspaces", workspaceCount: 1 }), expect.any(String))`. `loggerInfoSpy` already exists (test lines 99-108) and is reset in `beforeEach` (line 176) — no new mock infra needed.
- [ ] 2.4 Update the test title + leading comment from "warns once" to "logs at info, does not page (regression: dogfood KB freeze + #4706 over-warn)".

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` → green.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/webhooks/webhook-push-dispatch.test.ts` → green (sibling referencing the slug; confirm unaffected).
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run` → full package green.
- [ ] 3.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.

## Phase 4 — Ship / post-merge (per plan AC8)

- [ ] 4.1 Standard open-code-review overlap query before push (`gh issue list --label code-review --state open` against the two edited paths).
- [ ] 4.2 Post-merge: confirm via Sentry API that `op:ignored-repo-has-workspaces` receives no new events after deploy (read-only query in `/soleur:ship` post-merge verification; container restart is automatic via `web-platform-release.yml`).
