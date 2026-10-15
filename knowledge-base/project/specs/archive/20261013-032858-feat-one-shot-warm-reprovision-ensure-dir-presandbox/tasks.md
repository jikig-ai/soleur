---
title: "Tasks — unconditionally ensure workspace dir pre-sandbox (Concierge + leader)"
plan: knowledge-base/project/plans/2026-06-15-fix-warm-reprovision-ensure-workspace-dir-presandbox-plan.md
branch: feat-one-shot-warm-reprovision-ensure-dir-presandbox
lane: single-domain
brand_survival_threshold: single-user incident
---

# Tasks

> Plan-quoted line numbers are PRECONDITIONS to verify, not facts. Re-grep at Phase 0.
> Cited test paths: `ls test/<file>` before trusting (vitest silently runs only matched files → false-green).

## Phase 0 — Preconditions (verify before any edit)

- [x] 0.1 `git grep -n "fetchUserWorkspacePath\|buildAgentQueryOptions\|ensureWorkspaceRepoCloned" apps/web-platform/server/cc-dispatcher.ts` — confirm the factory `Promise.all` resolves `workspacePath` (~:1314), `ensureWorkspaceRepoCloned` awaited (~:1450), `buildAgentQueryOptions({ workspacePath })` sandbox site (~:1799).
- [x] 0.2 `git grep -n "fetchUserWorkspacePath\|buildAgentQueryOptions\|ensureWorkspaceRepoCloned" apps/web-platform/server/agent-runner.ts` — confirm leader resolve, awaited `ensureWorkspaceRepoCloned` (~:1064), `buildAgentQueryOptions` (~:1869).
- [x] 0.3 Confirm `ensure-workspace-repo.ts:85` (`installationId === null || !repoUrl` → `return "ok"`) and `:89` (`.git`-present → `return "ok"`) BOTH precede the mkdir at `:163` (the load-bearing gap).
- [x] 0.4 `ls apps/web-platform/test/cc-dispatcher-real-factory.test.ts apps/web-platform/test/agent-runner-reprovision.test.ts apps/web-platform/test/cc-reprovision.test.ts` — confirm seam files exist; confirm `apps/web-platform/test/cc-dispatcher-warm-presandbox-mkdir.test.ts` does NOT exist yet.
- [x] 0.5 Open Code-Review Overlap: `gh issue list --label code-review --state open --json number,title,body` then per-path `jq --arg path` for `cc-dispatcher.ts` / `ensure-workspace-repo.ts` / `cc-reprovision.ts` / `agent-runner.ts` — confirm none, else fold/ack/defer.

## Phase 1 — RED (write failing tests first; `cq-write-failing-tests-before`)

- [x] 1.1 Create `apps/web-platform/test/cc-dispatcher-warm-presandbox-mkdir.test.ts` (vitest, node env). RED test: not-connected fixture (`resolveInstallationId` → null / empty `repoUrl`), real tmpdir as resolved `workspacePath`, `rm -rf` it, stub `buildAgentSandboxConfig`/`sdkQuery` to record `existsSync(workspacePath)` at invocation; assert `true` (RED `false` on `main`). (AC1)
- [x] 1.2 Add `.git`-present-but-root-reclaimed case (skips `:89`) — dir still ensured before sandbox build. (AC2/T2)
- [x] 1.3 Add AC4 assertion: `existsSync(join(workspacePath,".git")) === false` right after the pre-sandbox mkdir on a fresh dir.
- [x] 1.4 Add AC6 fail-soft: `mkdir` rejects → `reportSilentFallback({feature:"cc-dispatcher",op:"ensure-workspace-dir-presandbox",extra:{userId}})` AND turn surfaces retryable/honest envelope (does NOT build a doomed sandbox).
- [x] 1.5 Extend `apps/web-platform/test/agent-runner-reprovision.test.ts` with the leader-path not-connected dir-ensure-before-sandbox assertion. (AC8/T7)
- [x] 1.6 Run the new + extended tests; confirm RED. `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher-warm-presandbox-mkdir.test.ts test/agent-runner-reprovision.test.ts`

## Phase 2 — GREEN (implement the unconditional pre-sandbox mkdir)

- [x] 2.1 `cc-dispatcher.ts realSdkQueryFactory`: import `mkdir` from `node:fs/promises`; add unconditional `await mkdir(workspacePath, { recursive: true })` after the `:1314-1315` resolve, before `buildAgentQueryOptions` at `:1799`. try/catch → `reportSilentFallback` → surface retryable/honest envelope on failure (optional one bounded retry). Doc-comment: dir-existence ⊋ clone-eligibility; do NOT place in `dispatchSoleurGo`.
- [x] 2.2 `agent-runner.ts startAgentSession`: identical unconditional `await mkdir(workspacePath, { recursive: true })` after its `workspacePath` resolve, before `buildAgentQueryOptions` at `:1869`. `feature:"agent-runner"`, same `op`. (AC8 fold-in; scope-out only with rationale + tracking issue.)
- [x] 2.3 Re-run the RED tests → GREEN.

## Phase 3 — Verify (regression + typecheck + suite)

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher-warm-presandbox-mkdir.test.ts test/cc-dispatcher.test.ts test/cc-dispatcher-real-factory.test.ts test/cc-reprovision.test.ts test/ensure-workspace-repo.test.ts test/ensure-workspace-repo-graft-race.test.ts test/agent-runner-reprovision.test.ts` (AC3 cold-path preserved; AC9)
- [x] 3.3 Confirm AC5 honest "workspace reclaimed" path unperturbed (fire-and-forget clone + `reprovisionOutcome` publish untouched).

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Ref #5240` (epic) / `Closes #<bug-issue>` per the auto-close convention; split AC into Pre-merge / Post-merge subsections.
- [ ] 4.2 Post-merge: `web-platform-release.yml` restarts the container on merge (path-filtered `on.push`) — PR merge IS the deploy; verify green via the deploy webhook (read-only). No operator restart step.
