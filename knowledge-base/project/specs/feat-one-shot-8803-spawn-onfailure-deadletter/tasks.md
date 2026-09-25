# Tasks: Settle orphaned agent spawns and label retry-exhausted Anthropic errors (#8803, #8783)

Plan: `knowledge-base/project/plans/2026-09-25-fix-spawn-onfailure-deadletter-and-429-label-plan.md`

## Phase 1: Setup

- [ ] 1.1 Read `decision-challenges.md` in this directory. The defaults stand unless the operator reversed them: keep `onFailure`, keep the plan copy, and set `retryEligible: false`.
- [ ] 1.2 Re-read `agent-on-spawn-requested.ts`, `spawn-dead-letter.ts`, `test/helpers/inngest-step-harness.ts` and `cron-gh-pages-cert-reissue.ts` (`cronGhPagesCertReissueOnFailure`), the onFailure envelope precedent.

## Phase 2: RED tests (cq-write-failing-tests-before)

- [ ] 2.1 Leader-loop suite:
  - [ ] 2.1.1 Rewrite the `it.each([429, 500, 408, 409])` block: 429 → `anthropic_rate_limited`, the others → `anthropic_timeout`, with 4 `create` calls each (T1, T3).
  - [ ] 2.1.2 A post-billing failure → `leader_internal_error` (T5). A plain `TypeError` → `leader_internal_error` (T4). `ByokLeaseError(fetch_failed | subscription_limit)` → `byok_lease_unavailable` (T6).
  - [ ] 2.1.3 A `runLikeInngest` case with its own `memo`: a 429 on every attempt → `anthropic_rate_limited`. Assert the memoized `StepError` has `cause === "anthropic_rate_limited"` and `invocations > 4` (T2).
  - [ ] 2.1.4 Extend `vi.mock("@anthropic-ai/sdk")` to export the REAL `APIConnectionError` / `APIConnectionTimeoutError` classes (`vi.importActual`). Rewrite the "AC10 anthropic_timeout" case to throw a real-class `APIConnectionTimeoutError`, whose `name` is `"Error"` at runtime.
- [ ] 2.2 New `test/server/inngest/agent-on-spawn-lifecycle.test.ts`:
  - [ ] 2.2.1 Settle scenarios: T7-T14, including T12b (a committed write whose step was retried still pages once).
  - [ ] 2.2.2 Registration (REAL client via the `NEXT_PHASE` hoist): T15, T16. The listener's `if` equals `agentOnSpawnRequested.getConfig(...)[1].triggers[0].expression`, and `FINISH_TIMEOUT_MS` agrees with `timeouts.finish`.
  - [ ] 2.2.3 No raw `founderId` anywhere in the event after `scrubSentryEvent` (T20).
  - [ ] 2.2.4 No replay double-report under `runLikeInngest` (T21).
- [ ] 2.3 `function-registry-count.test.ts`: route-entry pin 69 → 70 (T17).
- [ ] 2.4 Contract and copy tests: `PINNED_PAGED_REASONS` and `PROMISED_NOTIFICATION` += `leader_internal_error`, count-free titles, and the TF set equals the pin and is non-empty (T18). Also `ALL_REASONS` and the CPO-2 list.
- [ ] 2.5 `spawn-dead-letter.test.ts`: `leader_internal_error` is error-level, each lifecycle gets a distinct message, and the no-lifecycle message is byte-identical.

## Phase 3: Core implementation

- [ ] 3.1 Taxonomy: `lib/failure-reason.ts` (union + `PAGES_OPERATOR` true) and `failure-reason-copy.ts` (row, `retryEligible: false`).
- [ ] 3.2 Sentry rule:
  - [ ] 3.2.1 `issue-alerts.tf`: seven sorted reasons in the `reason in` list, plus a runbook pointer comment.
  - [ ] 3.2.2 Regenerate `alert-reference.json` per `infra/sentry/README.md`, or take the gate's `sentry-alert-reference-expected-<run-id>` artifact.
- [ ] 3.3 Classifier:
  - [ ] 3.3.1 `TRANSIENT_ANTHROPIC_CAUSES`.
  - [ ] 3.3.2 `tagTransientAnthropicError` at the `rejected === null` rethrow. It tags 429 as `anthropic_rate_limited`, and 408/409/>=500 or `instanceof APIConnectionError` as `anthropic_timeout`. Never match by `name`.
  - [ ] 3.3.3 A cause-only `classifyAnthropicOrLeaseError` whose catch-all is `leader_internal_error`.
  - [ ] 3.3.4 No step return shape changes.
- [ ] 3.4 `spawn-dead-letter.ts`:
  - [ ] 3.4.1 An optional `lifecycle` message suffix (plus `extra`), on the main path and the report-failed fallback.
  - [ ] 3.4.2 A COVERAGE comment rewrite and a runbook pointer.
- [ ] 3.5 Lifecycle handlers in `agent-on-spawn-requested.ts`:
  - [ ] 3.5.1 `settleOrphanedSpawn`: a Stop read only for `cancelled`, then the conditional UPDATE with `.is()` on `failure_reason`, `acknowledged_at` and `undone_at` plus `.select("id")`. Report only when `wrote`. On zero rows with `attempt > 0`, re-read, and if `failure_reason === reason`, set `wrote`. The catch sends one paged report. No ctx logger.
  - [ ] 3.5.2 `agentOnSpawnRequestedOnFailure`: read `event.data.event` and `event.data.run_id`.
  - [ ] 3.5.3 `agentOnSpawnCancelledHandler`: `step.sleep("settle-grace", "2m")` with a single-in-flight-step invariant comment, then settle.
  - [ ] 3.5.4 `agentOnSpawnCancelled` (`retries: 3`, `idempotency: "event.data.run_id"`, the literal `==` filter).
  - [ ] 3.5.5 `onFailure: agentOnSpawnRequestedOnFailure,` on its own line, and `FINISH_TIMEOUT_MS`.
- [ ] 3.6 `app/api/inngest/route.ts`: register `agentOnSpawnCancelled` on its own line with a trailing comma.
- [ ] 3.7 Rewrite `scripts/followthroughs/leader-429-label-8758.sh`: PASS when `main`'s handler defines `tagTransientAnthropicError` and `TRANSIENT_ANTHROPIC_CAUSES` and no longer contains `return "anthropic_timeout";`. Keep the xtrace prologue and the stub marker, and no `${VAR:?}`.

## Phase 4: Docs

- [ ] 4.1 ADR-042: one "Amended 2026-09-25" paragraph under §I1 (the tag carrier and paging consequence, the rejected `maxAttempts`, and the two-entry-point terminal invariant).
- [ ] 4.2 New runbook `knowledge-base/engineering/operations/runbooks/spawn-dead-letter-triage.md`.

## Phase 5: Verification

- [ ] 5.1 AC4: `grep -Ec '^[[:space:]]*onFailure[[:space:]]*:'` on the handler file prints `1`.
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, plus the touched vitest suites (`./node_modules/.bin/vitest run <paths>`).
- [ ] 5.3 `bash plugins/soleur/test/c4-count-parity.test.sh`, `c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] 5.4 `scripts/lint-followthrough-varq-ban.sh`.
- [ ] 5.5 QA I-1: in scratchpad only, prove on a local `inngest-cli` v1.19.4 dev server that a finish timeout AND an API cancel emit `inngest/function.cancelled`, carrying `data.event`, `data.run_id` and numeric `ts`. Also give the throwaway function an `onFailure` and assert it does NOT fire on the timeout or the cancel. If either expectation fails, STOP and re-plan.
- [ ] 5.6 I-2: `grep -o leader_internal_error apps/web-platform/infra/sentry/alert-reference.json`.

## Phase 6: Post-merge (soleur:postmerge)

- [ ] 6.1 P-1: both follow-through probes print `PASS:` against `main`.
- [ ] 6.2 P-3: `apply-sentry-infra.yml` is green on the merge commit.
