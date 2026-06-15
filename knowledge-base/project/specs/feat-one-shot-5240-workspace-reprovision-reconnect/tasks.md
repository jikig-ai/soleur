---
title: Tasks — deterministic workspace re-provision on reconnect
issue: 5340
epic: 5240
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-15-feat-workspace-reprovision-on-reconnect-plan.md
created: 2026-06-15
---

# Tasks — workspace re-provision on reconnect (#5340, refs #5240)

> Spec lacks a `spec.md` (entered via one-shot → plan, no brainstorm). `lane:`
> defaulted to `cross-domain`. Plan is the source of truth.

## Phase 0 — Preconditions
- [ ] 0.1 Confirm `agent-runner.ts` does NOT import/call `ensureWorkspaceRepoCloned` (`grep -n` → zero).
- [ ] 0.2 Confirm `resolveInstallationId` + `getCurrentRepoUrl` imported/resolvable in `startAgentSession` scope.
- [ ] 0.3 Confirm `setBashAutonomous` closure-cell + setter + deps-wiring pattern in `cc-dispatcher.ts` (template for the new sink).
- [ ] 0.4 Confirm `__setGraftForTests` seam at `ensure-workspace-repo.ts:30`.
- [ ] 0.5 Baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/ensure-workspace-repo.test.ts && ./node_modules/.bin/tsc --noEmit`.

## Phase 1 — Widen `ensureWorkspaceRepoCloned` return type (contract first)
- [ ] 1.1 RED: extend `test/ensure-workspace-repo.test.ts` — catch → `"failed"`, benign exits → `"ok"`.
- [ ] 1.2 Add `export type ReprovisionOutcome = "failed" | "ok"`; return `"ok"` at `:74/:78/:88/:97`, `"failed"` at `:108`.
- [ ] 1.3 GREEN + `tsc --noEmit`.

## Phase 2 — Leader path recovery (standalone-valuable)
- [ ] 2.1 RED: `test/agent-runner-reprovision.test.ts` — recovery runs before `patchWorkspacePermissions`/`syncPull` when `.git` absent; resolutions NOT run when `.git` present.
- [ ] 2.2 Import `ensureWorkspaceRepoCloned`; inside a `.git`-absent gate, lazily resolve `resolveInstallationId` + `getCurrentRepoUrl`, then call recovery before `:1027`/`:1037`. No bespoke honest-message emit.
- [ ] 2.3 GREEN. Verify pass-through and recovery cases.

## Phase 3 — Thread reprovision result out of the cc factory
- [ ] 3.1 RED: `test/cc-dispatcher-reprovision-honest-message.test.ts` — threading + routing (cc path), INCLUDING a warm-query reconnect case.
- [ ] 3.2 Add `setReprovisionResult?` to `QueryFactoryArgs` (`:1029`) AND the forward (`:2512-2516`); add dispatcher cell + setter + deps-wiring (mirror `setBashAutonomous` `:2332`/`:2893`). **COLD-vs-WARM (deepen finding):** `realSdkQueryFactory` runs only on cold turns — do the re-provision + result publish via the per-dispatch fire-and-forget re-resolve in `dispatchSoleurGo` (mirror `setBashAutonomous` warm resolve at `:2348`), so warm reconnects are covered. Keep idempotent (`.git`-absent-gated). The `:1469` factory call may stay as the cold-path self-heal.
- [ ] 3.3 GREEN for threading assertions (cold + warm).

## Phase 4 — Honest post-recovery-failure message (cc path)
- [ ] 4.1 Add `WORKSPACE_RECLAIMED_MESSAGE` to `cc-workflow-end-messages.ts` (copywriter copy; NOT a new status).
- [ ] 4.2 In `onWorkflowEnded` final `else` branch (`:2787-2792`): `worktree_enter_failed` + `"failed"` → `{ type:"error", message: WORKSPACE_RECLAIMED_MESSAGE }`; else generic. Inline comment cites the placement learning.
- [ ] 4.3 GREEN for routing (incl. negative: `"ok"` never yields reclaimed message).

## Phase 5 — Full suite + typecheck
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` (full) + `./node_modules/.bin/tsc --noEmit`.

## Ship
- [ ] S.1 PR body uses `Closes #5340` and `Refs #5240` (NOT `Closes #5240`).
- [ ] S.2 Review (incl. `user-impact-reviewer` — single-user-incident threshold).
- [ ] S.3 `/soleur:ship` post-merge verification (no operator steps).
