# Tasks: fix cron step-boundary verdicts (#8726)

Plan: `knowledge-base/project/plans/2026-09-24-fix-cron-step-boundary-tagged-results-plan.md`

## Phase 1: Harness and failing tests (RED)

- [ ] 1.1 Create `apps/web-platform/test/helpers/inngest-step-harness.ts`
  - [ ] 1.1.1 `rebuildAsStepError(stepId, err)` using `serializeError` + `StepError` imported from `"inngest"`
  - [ ] 1.1.2 `runLikeInngest(invoke, { maxAttempts, memo? })`: shared memo (caller may pass a `Map` to read or seed it), outputs memoized as `JSON.parse(JSON.stringify(v ?? null))`, one new step per invocation, interruption only after the memo write via a never-settling promise, attempt + 1 on a non-final step failure, rebuilt `StepError` memoized on the final attempt
  - [ ] 1.1.4 `HarnessError` for the invocation cap, a duplicate step ID within one invocation, and an unserializable output
  - [ ] 1.1.3 Docstring states the guessed behaviour (attempt reset to 0 after a successful step)
- [ ] 1.2 Create `apps/web-platform/test/helpers/inngest-step-harness.test.ts`: one assertion per Guard 1 row (1–6) on fixed facts, the must-PASS row, and the permanent negative control (a naive inline driver misses what the harness sees)
- [ ] 1.3 Add S1 as `it.each(ROWS)` over the 8 `ROWS` crons in `cron-cohort-dedup.test.ts` (replacing scenario 11) and one case in `cron-community-monitor-heartbeat.test.ts`; assert `outcome` first
- [ ] 1.4 Add S2 (lease clears on the retry), S3 (genuine setup failure on the final attempt; no memoized output contains the installation token) and S4 (`isFinalAttempt` / `deferDeployOnFinalAttempt` unit tests)
- [ ] 1.5 Drift-guard scenarios on the harness: S5 (runtime-built JWT-shaped suppression warning), S5b (PEM in the `GET /app` error, replacing the old setup), S6 / S6b / S7 with a seeded `drift-check` memo (S7: `createProbeOctokit` rejects so only `resend-body` trips; positive anchors first)
- [ ] 1.6 Run S1, S5, S5b against the unfixed code and record the first failing assertion of each (not a `HarnessError`)

## Phase 2: Deploy deferral (GREEN)

- [ ] 2.1 `_cron-shared.ts`: add `isFinalAttempt` and make `finalizeOutputAwareHeartbeat` call it; add generic `WorkspaceSetupVerdict<W>`, `deferDeployOnFinalAttempt<W>` (ctx keys required), `throwIfDeployDeferred<W>(verdict, cronName)`; update the `DeployInProgressError` and `finalizeOutputAwareHeartbeat` comments
- [ ] 2.2 The 9 crons (`cron-seo-aeo-audit`, `cron-community-monitor`, `cron-growth-audit`, `cron-growth-execution`, `cron-architecture-diagram-sync`, `cron-campaign-calendar`, `cron-competitive-analysis`, `cron-content-generator`, `cron-roadmap-review`)
  - [ ] 2.2.1 Wrap the `"setup-workspace"` step callback in `deferDeployOnFinalAttempt(..., { attempt, maxAttempts })`
  - [ ] 2.2.2 Delete both `instanceof DeployInProgressError` lines and the now-unused `DeployInProgressError` import
  - [ ] 2.2.3 Add `throwIfDeployDeferred(verdict, "<cron>")` after the setup try/catch and before the body's try/finally; read `verdict.workspace`
  - [ ] 2.2.4 Rewrite the "#5728 G1" comments and the `retryEligible: false` comment in all 9 to state the real mechanism
- [ ] 2.3 Delete the scenarios that inject `DeployInProgressError` where nothing produces one: the inner-body scenario in `cron-community-monitor-heartbeat.test.ts` and scenario 11 in `cron-cohort-dedup.test.ts`; refresh the stale comment in `cron-community-monitor-dedup.test.ts`
- [ ] 2.4 `cron-producer-output-wiring.test.ts`: replace the `toContain("instanceof DeployInProgressError")` assertion with the Guard 2 token census (directory walk, comments stripped via `test/helpers/strip-comments.ts`, no `DeployInProgressError` token outside `_cron-shared.ts` and `_cron-claude-eval-substrate.ts`, name floor)

## Phase 3: Drift guard (GREEN)

- [ ] 3.1 `drift-check` returns `{ result, leakDetected }`: live `LeakDetectedError` caught inside the callback, `assertNoLeak("drift-result", JSON.stringify(result))` before returning, other errors rethrown as `redactedError(err)`; outer catch builds `failureDetail` from the redacted message and loses its dead `instanceof` branch
- [ ] 3.2 `issue-handling` and `notify-ops-email` return `{ leakDetected }` from a callback-local variable, returned after the outer try/catch; the `issue_write_403` report reads the local; keep `op: "notify-ops-email"` verbatim
- [ ] 3.2.1 Every leak arm reports `reportSilentFallback(null, { feature: "cron-github-app-drift-guard", op: "leak-tripwire", extra: { step } })` inside its step, with no matched text
- [ ] 3.3 Handler folds the three returned values into `leakDetected`; no step callback assigns a handler-scope variable

## Phase 4: Docs and verification

- [ ] 4.1 ADR-078 `## Amendment 2026-09-24 (#8726)`: mechanism, corrected retry sentence, visible outcomes of a deferral, the accepted doomed replay, ADR-042 precedent, rejected alternatives one line each
- [ ] 4.2 ADR-126: reword named residual 1 in place (drain-timeout hazard; no renumbering); fix accepted negative 2's "still rethrows bare"
- [ ] 4.2.1 Principles register: add the step-boundary verdict row at the next free AP number (AP-028 on `origin/main` today; re-check before merge)
- [ ] 4.2.2 Read the live alert-workflow binding of the 10 cron monitors (read-only Sentry API) and record which page anyone in the PR
- [ ] 4.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 4.4 `cd apps/web-platform && ./node_modules/.bin/vitest run` on the seven suites listed in AC10
- [ ] 4.5 `bash plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 4.6 Check every Acceptance Criterion (AC1–AC11) in the plan
