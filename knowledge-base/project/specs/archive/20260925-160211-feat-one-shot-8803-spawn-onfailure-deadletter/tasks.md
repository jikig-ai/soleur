# Tasks: Settle orphaned agent spawns and label retry-exhausted Anthropic errors (#8803, #8783)

Plan: `knowledge-base/project/plans/2026-09-25-fix-spawn-onfailure-deadletter-and-429-label-plan.md` (deepened 2026-09-25)

## Phase 1: Setup

- [ ] 1.1 Read `decision-challenges.md` in this directory. The defaults stand unless the operator reversed them:
  - `onFailure` forwards to one settle function;
  - the plan copy;
  - `retryEligible: false`;
  - Stop plus a timeout pages.
- [ ] 1.2 Re-read the source:
  - `agent-on-spawn-requested.ts` and `spawn-dead-letter.ts`;
  - `test/helpers/inngest-step-harness.ts`;
  - `cron-gh-pages-cert-reissue.ts` (`cronGhPagesCertReissueOnFailure`, the envelope precedent);
  - `cron-action-required-sla.ts` (the `step.sendEvent` typing precedent);
  - `app/api/dashboard/today/[id]/{cancel,undo}/route.ts`.

## Phase 2: RED tests (cq-write-failing-tests-before)

- [ ] 2.1 Leader-loop suite:
  - [ ] 2.1.1 Rewrite the `it.each([429, 500, 408, 409])` block: 429 → `anthropic_rate_limited`, the others → `anthropic_timeout`, with 4 `create` calls each (T1, T3).
  - [ ] 2.1.2 Extend `vi.mock("@anthropic-ai/sdk")` to export the REAL `APIConnectionError` / `APIConnectionTimeoutError` (`vi.importActual`). The AC10 case throws a real-class `APIConnectionTimeoutError` (T3).
  - [ ] 2.1.3 A post-billing failure → `leader_internal_error` (T5). A plain `TypeError` → `leader_internal_error` (T4). `ByokLeaseError(fetch_failed)` → `byok_lease_unavailable` (T6).
  - [ ] 2.1.4 `runLikeInngest` cases with their own `memo`: a 429 → `anthropic_rate_limited` with a memoized `StepError` `cause`, and `ByokLeaseError(subscription_limit)` → `byok_lease_unavailable` (T2).
- [ ] 2.2 New `test/server/inngest/agent-on-spawn-lifecycle.test.ts`:
  - [ ] 2.2.1 An in-memory service-client fake that APPLIES the `.eq` / `.is(col, null)` filters to a fixture row.
  - [ ] 2.2.2 `onFailure` forwards exactly one `agent.spawn.orphaned` event and makes no DB call (T7).
  - [ ] 2.2.3 The precedence `it.each` (lifecycle × Stop, with `FINISH_TIMEOUT_MS` / `-1` boundaries) and the grace ordering (T8). Missing `ts` and a Stop-read error (T9).
  - [ ] 2.2.4 Terminal rows (T10), zero rows at `attempt = 0` (T11), `settle_failed` once under `runLikeInngest` (T12), both re-read arms (T12b), a foreign `user_id` (T13), envelope validation with a fixed message (T14).
  - [ ] 2.2.5 Card derivation via `deriveTodayCardState` (T22), no ctx `logger` (T23), per-lifecycle messages (T24).
  - [ ] 2.2.6 Registration with the REAL client: T15, and T16 (two triggers, where the cancelled `if` equals `getConfig(...)[1].triggers[0].expression`, plus idempotency and retries).
  - [ ] 2.2.7 No raw `founderId` through the real middleware + `beforeSend` pipeline, or the documented two-test fallback (T20). No replay double-report (T21).
- [ ] 2.3 `function-registry-count.test.ts`: route-entry pin 69 → 70, naming `agentOnSpawnSettle` (T17).
- [ ] 2.4 Contract and copy tests:
  - [ ] 2.4.1 `PINNED_PAGED_REASONS` and `PROMISED_NOTIFICATION` += `leader_internal_error`, with count-free titles. The TF set equals the pin and is non-empty (T18).
  - [ ] 2.4.2 `ALL_REASONS` and the CPO-2 list += it.

## Phase 3: Core implementation

- [ ] 3.1 Taxonomy: `lib/failure-reason.ts` (union + `PAGES_OPERATOR` true) and `failure-reason-copy.ts` (row, `retryEligible: false`).
- [ ] 3.2 Sentry rule:
  - [ ] 3.2.1 `issue-alerts.tf`: seven sorted reasons in the `reason in` list, plus a runbook pointer comment.
  - [ ] 3.2.2 Regenerate `alert-reference.json`, or take the gate's `sentry-alert-reference-expected-<run-id>` artifact.
- [ ] 3.3 Classifier:
  - [ ] 3.3.1 `TRANSIENT_ANTHROPIC_CAUSES`.
  - [ ] 3.3.2 `tagTransientAnthropicError`: 429 → `anthropic_rate_limited`; 408/409/>=500 or `instanceof APIConnectionError` → `anthropic_timeout`; never `name`.
  - [ ] 3.3.3 A cause-only `classifyAnthropicOrLeaseError` whose catch-all is `leader_internal_error`.
  - [ ] 3.3.4 No existing step return shape changes.
- [ ] 3.4 `spawn-dead-letter.ts`:
  - [ ] 3.4.1 An optional `lifecycle` (`failed` | `cancelled` | `timed_out` | `settle_failed`) message suffix plus `extra`, on both paths. The legacy message stays byte-identical.
  - [ ] 3.4.2 A COVERAGE rewrite that names both remaining gaps (#8839), plus a runbook pointer.
- [ ] 3.5 Lifecycle handlers in `agent-on-spawn-requested.ts`:
  - [ ] 3.5.1 `FINISH_TIMEOUT_MS`, with `timeouts.finish` built from it.
  - [ ] 3.5.2 `agentOnSpawnRequestedOnFailure`: one `step.sendEvent("forward-orphan", agent.spawn.orphaned)`, carrying `data.event`, `data.run_id`, `error`, `ts` and `lifecycle: "failed"`.
  - [ ] 3.5.3 `agentOnSpawnSettleHandler`:
    - normalise both payloads;
    - `step.sleep("settle-grace", "2m")` for cancels only, with the single-in-flight-step invariant comment;
    - validate the envelope with a fixed message;
    - call `settleOrphanedSpawn`;
    - one `settle_failed` report in the catch;
    - no ctx `logger`.
  - [ ] 3.5.4 `settleOrphanedSpawn`:
    - a founder-scoped (`id` + `user_id` + `message_id`) Stop read for `cancelled` only;
    - the conditional UPDATE with `.is()` on `failure_reason`, `acknowledged_at` and `undone_at`, plus `.select("id")`;
    - the `attempt > 0` re-read;
    - report only when `wrote`.
  - [ ] 3.5.5 `agentOnSpawnSettle` (`retries: 3`, `idempotency: "event.data.run_id"`, triggers `inngest/function.cancelled` with the literal `==` filter and `agent.spawn.orphaned`).
  - [ ] 3.5.6 `onFailure: agentOnSpawnRequestedOnFailure,` on its own line.
- [ ] 3.6 `app/api/inngest/route.ts`: register `agentOnSpawnSettle` on its own line with a trailing comma.
- [ ] 3.7 Rewrite `scripts/followthroughs/leader-429-label-8758.sh`: PASS when `main` defines `tagTransientAnthropicError` and `TRANSIENT_ANTHROPIC_CAUSES` and lacks `return "anthropic_timeout";`. Keep the xtrace prologue and the stub marker, and no `${VAR:?}`.

## Phase 4: ADRs and docs

- [ ] 4.1 ADR-042: the §I1 2026-09-25 amendment (tag carrier, paging consequence, rejected `maxAttempts`) and a new §I6 (terminal-state invariant).
- [ ] 4.2 New ADR (provisional ADR-251) via `soleur:architecture`: "Inngest functions that must leave a terminal record handle both lifecycle signals". Re-derive the ordinal from freshly fetched `origin/main` first.
- [ ] 4.3 New runbook `knowledge-base/engineering/operations/runbooks/spawn-dead-letter-triage.md`: per-suffix steps, a Sentry `inngest.run_id:<failedRunId>` search, artifact triage (#8845), and the rollout false page. No SSH.

## Phase 5: Verification

- [ ] 5.1 AC4: `grep -Ec '^[[:space:]]*onFailure[[:space:]]*:'` on the handler file prints `1`.
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, plus the touched vitest suites (`./node_modules/.bin/vitest run <paths>`).
- [ ] 5.3 `bash plugins/soleur/test/c4-count-parity.test.sh`, `c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] 5.4 `scripts/lint-followthrough-varq-ban.sh`.
- [ ] 5.5 QA I-1, in scratchpad only, on a local `inngest-cli` v1.19.4 dev server. Prove that:
  - a finish timeout AND an API cancel both emit `inngest/function.cancelled` with `data.event`, `data.run_id` and numeric `ts`;
  - `onFailure` does NOT fire for either;
  - the SDK-generated filter matches.

  Also record whether a hand-sent `inngest/function.cancelled` is accepted. If any expectation fails, STOP and re-plan.
- [ ] 5.6 I-2: `grep -hoE 'leader_internal_error|agentOnSpawnSettle'` over `alert-reference.json` + `route.ts` prints both.

## Phase 6: Post-merge (soleur:postmerge)

- [ ] 6.1 P-1: both follow-through probes print `PASS:` against `main`.
- [ ] 6.2 P-3: `apply-sentry-infra.yml` is green on the merge commit.
- [ ] 6.3 P-4: `gh workflow run cutover-inngest.yml -f op=registry-probe`, whose `function_ids` must include `soleur-runtime-agent-on-spawn-requested-failure` and `soleur-runtime-agent-on-spawn-settle`.
