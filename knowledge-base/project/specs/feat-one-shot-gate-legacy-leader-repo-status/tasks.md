# Tasks — Gate the legacy `startAgentSession` leader dispatch path on `repo_status`

Plan: `knowledge-base/project/plans/2026-06-16-feat-gate-legacy-leader-dispatch-on-repo-status-plan.md`
Issue: #5399 (AC10 follow-up to #5395). Branch: `feat-one-shot-gate-legacy-leader-repo-status`.

## Phase 0 — Preconditions (read-before-edit)

- [ ] 0.1 Read `apps/web-platform/server/agent-runner.ts:859-920` (startAgentSession open,
      supersede-abort, `registerSession`) and pin the exact line of `registerSession`. The Option A
      gate MUST sit BEFORE it (Risk + Sharp Edge: dangling-session).
- [ ] 0.2 Read `apps/web-platform/server/agent-runner.ts:2455-2514` (outer catch) — confirm the
      generic `else` mirrors to Sentry AND marks the conversation failed (the two behaviors the
      gate must avoid).
- [ ] 0.3 Confirm imports: is `getCurrentRepoStatus` already in the `./current-repo-url` import
      line (alongside `getCurrentRepoUrl`)? Extend, do not duplicate. Confirm `evaluateRepoReadiness`
      import path is `./repo-readiness`.
- [ ] 0.4 `git diff origin/main --stat -- apps/web-platform/server/repo-readiness.ts
      apps/web-platform/server/current-repo-url.ts` is empty before starting (baseline for AC6).
- [ ] 0.5 Read `apps/web-platform/test/agent-runner-reprovision.test.ts` to lift the hoisted-mock
      harness (mocks `@sentry/nextjs`, `../server/ws-handler`, `../server/current-repo-url`).

## Phase 1 — RED (failing wiring test)

- [ ] 1.1 Create `apps/web-platform/test/agent-runner-repo-readiness-gate.test.ts` with cases 1-4
      from the plan (cloning / error / ready / not_connected). Assert: `sendToClient` shape,
      `query` (SDK) NOT called on block, `captureException` NOT called on block, conversation NOT
      marked failed on block.
- [ ] 1.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run
      test/agent-runner-repo-readiness-gate.test.ts` — cases 1/2 FAIL on origin/main (no gate yet).

## Phase 2 — GREEN (implement the gate, Option A)

- [ ] 2.1 Add the gate to `startAgentSession` BEFORE `registerSession`/`resolveKeyOwnerThenLease`:
      `getCurrentRepoStatus(userId)` → `evaluateRepoReadiness(...)` → on `!ok`: `log.info`
      breadcrumb (op=repo-readiness-gate), `sendToClient` honest message + optional errorCode,
      early `return` (no throw).
- [ ] 2.2 Extend/add imports (`getCurrentRepoStatus`, `evaluateRepoReadiness`). Do NOT import
      `RepoNotReadyError` under Option A (unused → lint/tsc noise).
- [ ] 2.3 Re-run the wiring test — all 4 cases PASS.
- [ ] 2.4 (Only if Option A's pre-`registerSession` ordering proves infeasible) pivot to Option B:
      throw `RepoNotReadyError` after `workspacePath` resolves; add `else if (err instanceof
      RepoNotReadyError)` in the outer catch ABOVE the generic `else`, reading `err.errorCode`
      directly, skipping Sentry + the failed-status write. Document the pivot in the PR body.

## Phase 3 — Verify (full AC sweep)

- [ ] 3.1 AC7: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] 3.2 AC8: `cd apps/web-platform && ./node_modules/.bin/vitest run
      test/agent-runner-repo-readiness-gate.test.ts test/repo-readiness.test.ts` passes.
- [ ] 3.3 AC6: `git diff origin/main --stat -- apps/web-platform/server/repo-readiness.ts
      apps/web-platform/server/current-repo-url.ts` is empty (primitives reused, not modified).
- [ ] 3.4 AC9: `git grep -n "startAgentSession(" apps/web-platform/server` confirms ws-handler
      `pendingLeader` + the three `sendUserMessage` call sites all route through the gated function.
- [ ] 3.5 Run the full web-platform suite (`./node_modules/.bin/vitest run`) as the exit gate to
      catch any orphan suite that imports the dispatch path.

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Closes #5399`. Note the Option A vs B choice + the registerSession
      ordering. Reference the source gate (#5395).
- [ ] 4.2 No post-merge operator steps (container restart is automatic on merge to main touching
      `apps/web-platform/**`).
