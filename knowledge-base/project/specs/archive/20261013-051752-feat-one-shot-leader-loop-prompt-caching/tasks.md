# Tasks: fix leader-loop prompt caching

Plan: `knowledge-base/project/plans/2026-09-24-fix-leader-loop-prompt-caching-plan.md`

## Phase 1: Setup

- [ ] 1.1 Re-verify premises on the rebased branch: the `client.messages.create` call shape in `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`, the per-class tool counts in `LEADER_PROMPTS`, and `@anthropic-ai/sdk` 0.93.x `MessageCreateParamsBase.cache_control`.
- [ ] 1.2 Baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts` (28/28 green at plan time).

## Phase 2: Core Implementation (tests first, per `cq-write-failing-tests-before`)

- [ ] 2.1 Guard 1 tests (Test Scenarios 1-2), written RED against today's code:
  - [ ] 2.1.1 `it.each(Object.keys(LEADER_PROMPTS))`: a `create` call count above 0, a `JSON.stringify` breakpoint count ≤ 4 and === 2, exact `toEqual` on the top-level and system markers, and `params.tools` toEqual the module's tools.
  - [ ] 2.1.2 A 3-call `pr_review_pending` run captured per call with `structuredClone`, asserting `captured[0].messages.length === 1` and every Scenario 1 assertion on every capture.
- [ ] 2.2 Phase 1 request shape: add top-level `cache_control`, keep the system marker, and pass `tools: leaderModule.tools as never`. In the `MODEL_PRICING` comment, name both markers and correct the stale "does not distinguish" claim (SDK 0.93 has `usage.cache_creation.ephemeral_{5m,1h}_input_tokens`). Guard 1 goes GREEN.
- [ ] 2.3 Guard 2 tests (Test Scenarios 3-4), written RED:
  - [ ] 2.3.1 Harness: hoist `getRestApiKeySpy` into the lease mock and `mockReset` it in `beforeEach`; add a `makeStep({ retries: 3, serializeThrow })` variant; synthesize lease errors by `name`/`cause`.
  - [ ] 2.3.2 Cases: 400 → `anthropic_request_rejected` after 1 call; 401/402 → `byok_lease_unavailable` after 1 call; `MissingByokKeyError` after 1 call; 429 and 500 retried.
  - [ ] 2.3.3 `serializeThrow` pins: 429 → `anthropic_timeout` (the residual); `fetch_failed` → `byok_lease_unavailable` after 4 attempts.
  - [ ] 2.3.4 Sentry spy's first argument message starts with `"400 "`; the JSON round-trip of the returned value includes `status`.
- [ ] 2.4 Phase 2 code:
  - [ ] 2.4.1 Widen `classifyAnthropicOrLeaseError`: 401/402/403 → `byok_lease_unavailable`, and every other 4xx except 408/409/429 → `anthropic_request_rejected`.
  - [ ] 2.4.2 Add a pre-billing `try/catch` (from `getRestApiKey` through `create`) inside the lease callback. It returns `{ rejected, status, message, stack }` for deterministic failures and re-throws everything else. Do not use `instanceof Anthropic.APIError`.
  - [ ] 2.4.3 Handler: drop the `as AnthropicTurnResult` cast and narrow with `"rejected" in result`. Route a rejection to `persistFailure` with an `Error` rebuilt from the returned message and stack, plus a new optional `extra` (`status`, `turn`, `model`) that `persistFailure` merges into its `reportSilentFallback` extra.
  - [ ] 2.4.4 Widen the `FailureReason` union: the server file, `components/dashboard/failure-reason-copy.ts` (union, copy row with `retryEligible: false`, docstring), `test/components/dashboard/failure-reason-copy.test.ts` `ALL_REASONS`, and `test/components/dashboard/today-card-state-matrix.test.ts` CPO-2 list. Then run `./node_modules/.bin/tsc --noEmit`.
- [ ] 2.5 Amend ADR-042 (dated). §I1 gets the return-not-throw terminal outcome and cites the `server/inngest/middleware/run-log.ts` precedent (#5674). §I5 gets the marker placement, the TTL-ordering note and the alternatives row. Update the sentinel lines and the Consequences sentinel table (Guard 1 and Guard 2).

## Phase 3: Testing and Verification

- [ ] 3.1 AC3 mutation checks. For each mutation, record the red and the green summary lines for the PR body:
  - [ ] Re-add per-tool markers. Expect RED, including `security.cve_alert` (total 7) and `knowledge.kb_drift` (total 5).
  - [ ] Guard 1 mutation 3: drop the top-level field.
  - [ ] Guard 1 mutation 5: put a marker on `tool_result`.
  - [ ] Guard 2 mutation 1: re-throw the 400.
- [ ] 3.2 AC8: `./node_modules/.bin/vitest run test/server/inngest test/components/dashboard` and `./node_modules/.bin/tsc --noEmit`.
- [ ] 3.3 AC1: `rg -c 'client\.messages\.create\(' apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` prints `1`.
- [ ] 3.4 AC9, **after the final rebase onto `origin/main`** (in ship's pre-merge sync): re-measure `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts`, bump it by 1 with a PLACEMENT / TRUTH / NO SUBSTITUTE comment, and run `bun test plugins/soleur/test/preflight-discoverability-test.test.ts`.
- [ ] 3.5 AC10 scope fence: `git diff --name-only origin/main...HEAD`.
- [ ] 3.6 PR body:
  - the mutation evidence;
  - the corrected worst-case figures: the "≈$0.33" figure is output-only, and the real totals are about $0.58 uncached and $0.42 cached;
  - the #8635 interplay: a double bill now costs less and is still flagged;
  - the known limits: #8629 tag loss, #8719 no alert rule, and the 429-after-retries residual;
  - DC-1 from `decision-challenges.md`.
