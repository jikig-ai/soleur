# Tasks: fix cron step-boundary verdicts (#8726)

Plan: `knowledge-base/project/plans/2026-09-24-fix-cron-step-boundary-tagged-results-plan.md`

## Phase 1: Harness and failing tests (RED)

- [ ] 1.1 Create `apps/web-platform/test/helpers/inngest-step-harness.ts`
  - [ ] 1.1.1 `rebuildAsStepError(stepId, err)` using `serializeError` + `StepError` imported from `"inngest"`
  - [ ] 1.1.2 `runLikeInngest(invoke, { maxAttempts, memo? })`: shared memo, JSON round-trip, one new step per invocation, never-settling interruption, attempt + 1 on a non-final step failure, rebuilt `StepError` memoized on the final attempt, invocation cap, loud failure on a duplicate step ID, optional caller-owned memo `Map`
  - [ ] 1.1.3 Docstring states the guessed behaviour (attempt reset to 0 after a successful step)
- [ ] 1.2 Create `apps/web-platform/test/helpers/inngest-step-harness.test.ts` with one assertion per Guard 1 row (1–4) plus the must-PASS row, compared against `new StepError(...)`
- [ ] 1.3 Add S1 over the 8 `ROWS` crons in `cron-cohort-dedup.test.ts` (replacing scenario 11) and in `cron-community-monitor-heartbeat.test.ts`
- [ ] 1.4 Add S2 (lease clears on the retry) and S3 (genuine setup failure on the final attempt)
- [ ] 1.5 Move the drift-guard leak scenarios onto the harness: S5 (JWT-shaped suppression warning), S6, S6b (leak then 403 on the leak-issue write), S7 (rewritten: `issue-handling` fails for a non-leak reason so only `resend-body` trips)
- [ ] 1.6 Run the new scenarios against the unfixed code and record that S1, S5, S6, S7 fail for the stated reason

## Phase 2: Deploy deferral (GREEN)

- [ ] 2.1 `_cron-shared.ts`: add `EphemeralWorkspace`, `WorkspaceSetupVerdict`, `deferDeployOnFinalAttempt` (ctx keys required; predicate copied from `finalizeOutputAwareHeartbeat`, with its one divergence from the SDK documented), `throwIfDeployDeferred(verdict, cronName)`; update the `DeployInProgressError` and `finalizeOutputAwareHeartbeat` comments
- [ ] 2.2 The 9 crons (`cron-seo-aeo-audit`, `cron-community-monitor`, `cron-growth-audit`, `cron-growth-execution`, `cron-architecture-diagram-sync`, `cron-campaign-calendar`, `cron-competitive-analysis`, `cron-content-generator`, `cron-roadmap-review`)
  - [ ] 2.2.1 Wrap the `"setup-workspace"` step callback in `deferDeployOnFinalAttempt(..., { attempt, maxAttempts })`
  - [ ] 2.2.2 Delete both `instanceof DeployInProgressError` lines and the now-unused `DeployInProgressError` import
  - [ ] 2.2.3 Add `throwIfDeployDeferred(verdict, "<cron>")` after the setup try/catch; read `verdict.workspace`
  - [ ] 2.2.4 Rewrite the "#5728 G1" and `retryEligible` comments to state the real mechanism
- [ ] 2.3 Delete the scenarios that inject `DeployInProgressError` where nothing produces one: the inner-body scenario in `cron-community-monitor-heartbeat.test.ts` and scenario 11 in `cron-cohort-dedup.test.ts`; refresh the stale comment in `cron-community-monitor-dedup.test.ts`
- [ ] 2.4 `cron-producer-output-wiring.test.ts`: replace the `toContain("instanceof DeployInProgressError")` assertion with the Guard 2 token census (directory walk, comments stripped via `test/helpers/strip-comments.ts`, no `DeployInProgressError` token outside `_cron-shared.ts` and `_cron-claude-eval-substrate.ts`, name floor)

## Phase 3: Drift guard (GREEN)

- [ ] 3.1 `drift-check` returns `{ result, leakDetected }` (live `LeakDetectedError` caught inside the callback); remove the dead `instanceof` branch in the outer catch
- [ ] 3.2 `issue-handling` and `notify-ops-email` return `{ leakDetected }` from a callback-local variable, returned after the outer try/catch
- [ ] 3.3 Handler folds the three returned values into `leakDetected`; no step callback assigns a handler-scope variable

## Phase 4: Docs and verification

- [ ] 4.1 ADR-078 amendment (one paragraph; rejected alternatives one line each)
- [ ] 4.2 ADR-126: mark named residual 1 dissolved; fix the "still rethrows bare" sentence
- [ ] 4.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 4.4 `cd apps/web-platform && ./node_modules/.bin/vitest run` on the six suites listed in AC10
- [ ] 4.5 `bash plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 4.6 Check every Acceptance Criterion (AC1–AC10) in the plan
