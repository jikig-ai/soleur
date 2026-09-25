---
title: "fix(inngest): settle orphaned agent spawns via onFailure + function.cancelled, and label retry-exhausted Anthropic errors by positive match"
type: fix
date: 2026-09-25
slug: fix-spawn-onfailure-deadletter-and-429-label
branch: feat-one-shot-8803-spawn-onfailure-deadletter
issue: 8803
closes: [8803, 8783]
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-09-25.

**Agents:**
- observability-coverage-reviewer
- architecture-strategist
- security-sentinel
- test-design-reviewer
- spec-flow-analyzer
- a verify-the-negative + self-audit pass (Sonnet)

This followed the plan-review panel (DHH, Kieran, code-simplicity, CTO, CMO) and the scoped advisor consult.

### Key improvements

1. **`onFailure` forwards; one settle function does the work.** The SDK pins `-failure` to one retry with no idempotency, so `onFailure` now sends `agent.spawn.orphaned` to `agent-on-spawn-settle`. That function has `retries: 3`, `idempotency: event.data.run_id` and two triggers (the forward and `inngest/function.cancelled`). It keeps the operator's `onFailure`, which the #8803 probe needs.
2. **A Stop can no longer hide a hang.** Stop only sets `cancellation_requested_at`, and there is no `cancelOn`. So `timed_out` + Stop now pages `leader_internal_error`. `cancelled_by_operator` is kept only for a pre-timeout cancel with Stop.
3. **Founder-scoped, validated settle.** Every query adds `user_id` + `message_id`. The envelope is validated first (event name, UUID ids, known class) with a fixed error message, so a forged or foreign envelope writes nothing and leaks no raw id.
4. **Connection errors are classified by `instanceof APIConnectionError`.** SDK 0.93 sets `name === "Error"`, verified at runtime. The suite mock exports the real classes.
5. **Operator triage.** Every failure mode cites its observability layer. `settle_failed` gets its own Sentry issue. A registry-presence postmerge check (P-4) and a no-SSH runbook are added.
6. **Tests assert behaviour, not calls.** An in-memory fake applies the `.eq`/`.is` filters. There is a precedence `it.each` with `>=` boundary fixtures, a card-derivation test (T22), real-serializer cases for 429 and `subscription_limit`, and a real-pipeline PII test (T20).

### New considerations discovered

- Reversal handles exist only in memory until `mark-acknowledged`, so orphaned runs can leave un-undoable GitHub artifacts (#8845, pre-existing).
- A `persist-failure` UPDATE failure inside `persistFailure` returns normally, so no lifecycle event fires. The card stays on "Working" (named in COVERAGE, and on #8839).
- The fleet-wide rule "a terminal record needs both lifecycle signals" gets its own ADR (provisional ADR-251). `cron-gh-pages-cert-reissue` handles only `onFailure`, a known gap named there.

## Overview

This branch has no spec.md, so it has no valid `lane:`. It defaults to `cross-domain` (TR2 fail-closed).

Two open review findings on the leader loop in `agent-on-spawn-requested` share one root: a spawn whose failure the handler cannot classify, or never sees, ends in the wrong terminal state. Issue 8803 covers runs that never reach `persistFailure` at all (a step that throws past its retries, the ten-minute finish timeout, a cancellation), so the Today card stays on "Working" and no dead-letter page fires. Issue 8783 covers a retry-exhausted Anthropic 429 that reaches the handler without its HTTP status and is mislabelled `anthropic_timeout`. This plan settles both in one failure-taxonomy design and one PR.

## Research Insights

### Premise Validation

- #8803 is OPEN; #8783 is OPEN. PR #8794, which filed #8803, is MERGED. #8764 (move suites onto the shared step harness) is OPEN, and #8783's follow-through probe `scripts/followthroughs/leader-429-label-8758.sh` only waits on it. This plan does not need #8764 (see Alternatives), so #8783 closes here and #8764 stays open, unaffected.
- Every cited path exists on this branch: `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` (`classifyAnthropicOrLeaseError`, `classifyLiveRejection`, `persistFailure`, `agentOnSpawnRequested`), `lib/failure-reason.ts`, `components/dashboard/failure-reason-copy.ts`, `server/spawn-dead-letter.ts`, `infra/sentry/issue-alerts.tf` (`sentry_alert.spawn_agent_dead_letter`), `test/sentry-spawn-dead-letter-alert-op-contract.test.ts` (`PINNED_PAGED_REASONS`), `infra/sentry/alert-reference.json`, `scripts/followthroughs/spawn-onfailure-deadletter-8794.sh`.
- The follow-through script PASSes on `grep -Eq '^[[:space:]]*onFailure[[:space:]]*:'` against `main`'s copy of the handler file. So the `onFailure:` key must sit at the start of its own line in the `createFunction` options object, in that file, not in a helper module.
- ADR corpus: ADR-042 (`knowledge-base/engineering/architecture/decisions/ADR-042-anthropic-sdk-inside-inngest-leader-loop.md`) governs the step's two terminal outcomes. Its 2026-09-24 amendment already records that a string `cause` survives the step round-trip (the carrier `ByokLeaseError` relies on). No ADR rejects an `onFailure` handler or a `function.cancelled` listener.

### Inngest lifecycle semantics (verified, SDK 3.54.2, self-hosted server v1.19.4)

- **Cancellation does NOT fire `onFailure`.** The failure-handlers doc sends cancelled runs to the `inngest/function.cancelled` system event instead (https://www.inngest.com/docs/features/inngest-functions/error-retries/failure-handlers).
- **`timeouts.finish` and `timeouts.start` are cancellations.** "Runs that are cancelled due to a timeout trigger an `inngest/function.cancelled` event" (https://www.inngest.com/docs/features/inngest-functions/cancellation/cancel-on-timeouts). So two of the three #8803 cases (timeout, cancellation) need a `function.cancelled` listener. Only the retry-exhausted throw reaches `onFailure`.
- **`function.cancelled` payload** (https://www.inngest.com/docs/reference/system-events/inngest-function-cancelled): `data.event` is the original triggering event, `data.error.message` is `"function cancelled"`, `data.function_id` is `<app-id>-<function-id>`, plus `data.run_id`. The SDK's `CancelledEventPayload` type (`node_modules/inngest/types.d.ts`) omits `event`/`error`, so the listener must read them through a narrowed local type, not the SDK type. Neither field tells a timeout apart from an API cancel.
- **Listener trigger form** (https://www.inngest.com/docs/examples/cleanup-after-function-cancellation): `{ event: "inngest/function.cancelled", if: "event.data.function_id == '<app-id>-<fn-id>'" }`. The app id is `soleur-runtime` (`server/inngest/client.ts`, `new Inngest({ id: "soleur-runtime" })`), so the filter value is `soleur-runtime-agent-on-spawn-requested`.
- **`onFailure` envelope:** the SDK registers `onFailure` as a separate function, `<id>-failure` (`InngestFunction.failureSuffix`), triggered by `inngest/function.failed`. Its `event` is `{ data: { function_id, run_id, error, event: <original> } }`, not the original event. The in-repo precedent, `cronGhPagesCertReissueOnFailure` in `server/inngest/functions/cron-gh-pages-cert-reissue.ts`, documents this and reads `event.data.event` / `event.data.run_id`.
- **What survives a step boundary:** `StepError` (`node_modules/inngest/components/StepError.js`) keeps `message`, `stack` and a deserialized `cause`. A string `cause` round-trips through `serializeError`, which returns it as-is under `allowUnknown`. `status` is dropped, and the repo's own measurement finds a custom `name` rewritten to `"Error"` (learning below). `ctx.maxAttempts` is typed optional (`BaseContext.maxAttempts?`), so code cannot count on a final-attempt signal.

### Relevant files

- `server/inngest/functions/agent-on-spawn-requested.ts`: steps with no try/catch are `read-action-send-created-at`, `turn-N-precheck-cost-ceiling`, `turn-N-cancel-check`, `turn-N-progress-write` and `turn-N-tool-i` (`createGitHubAppClient` sits outside `executeTool`'s try). Synchronous code outside steps, such as `leaderModule.userPromptTemplate`, can also throw. `classifyAnthropicOrLeaseError` ends in an unconditional `return "anthropic_timeout"`, and its only reachable production arms are the lease `cause` strings and the `/timeout/i` message regex.
- `server/byok-lease.ts` `ByokLeaseError.cause`: `fetch_failed | decrypt_failed | escape | subscription_limit`. `subscription_limit` is not mapped by `classifyAnthropicOrLeaseError` today, although it has no producer yet (`mapByokLeaseCauseToErrorCode` comment).
- `server/spawn-dead-letter.ts`: `reportSpawnDeadLetter` never throws, and pages by `PAGES_OPERATOR[reason]`. `PAGED_DEAD_LETTER_REASONS` is derived, never re-typed. Its COVERAGE comment names #8803 and must be rewritten.
- `components/dashboard/today-card-state-matrix.ts`: row 6 renders "Working — turn N of MAX" while `current_turn` is set and both `failure_reason` and `acknowledged_at` are null. A `failure_reason` wins over every later state (rows 1-2). Row 5 renders a Stop in progress while `cancellation_requested_at` is set and both are null.
- `server/inngest/middleware/sentry-correlation.ts`: the untagged function-final capture (`transformOutput`, no `step`) stays. It attaches `inngest.event_data` as a scope extra. `server/sentry-scrub.ts` `scrubRecursive` hashes a nested `founderId` to `founderIdHash` fleet-wide, which covers the failure/cancel envelopes' nested `event.data.founderId`.
- `test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts`: `makeRetryingStep` rebuilds the escaping error with only `message`, `stack` and `cause`, which is the StepError model. The `it.each([429, 500, 408, 409])` block "%i is transient: thrown, retried 3 times, then anthropic_timeout" pins the #8783 residual. `test/helpers/inngest-step-harness.ts` (`runLikeInngest`) rebuilds errors with the REAL `serializeError` + `StepError`.
- `app/api/inngest/route.ts`: the served function array. A new function needs an import and an array entry. `test/server/inngest/function-registry-count.test.ts` parses that array and pins its length (`expect(routeEntries.length).toBe(69)`).
- `supabase/migrations/064_action_sends_acknowledgment.sql`: `failure_reason text`, with no CHECK constraint. A new value needs no migration.
- `infra/sentry/README.md` "Adding or editing a rule" gives the regeneration triplet for `alert-reference.json` (`terraform plan -out` → `terraform show -json` → `jq -S --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq`). `.github/workflows/apply-sentry-infra.yml` applies `infra/sentry/` on push to main (ADR-031). No local apply.

### Institutional learnings applied

- `knowledge-base/project/learnings/integration-issues/2026-09-24-a-thrown-error-loses-its-status-at-the-inngest-step-boundary-so-return-the-verdict.md`: never route a post-step decision on `status`/`name`. The string `cause` survives. That session's carrier was superseded twice, so "measure what survives the boundary (`serializeError` + `new StepError`) before designing a carrier". This plan's carrier is the string `cause`, proven by a harness test that uses the real serializer.
- `knowledge-base/project/learnings/integration-issues/2026-09-24-changing-a-step-return-shape-strands-in-flight-runs-and-a-boundary-redaction-blinds-the-detector.md`: changing a memoized step's RETURN shape strands in-flight runs. This plan changes only what a step THROWS, never what it returns.
- `knowledge-base/project/learnings/security-issues/2026-09-25-a-no-raw-id-claim-tested-at-the-call-args-missed-three-sinks-on-the-same-event.md`: a "no raw founder id in the event" claim must be tested over the whole event (`captureMessage` + `addBreadcrumb` + scope extras + `err.message`), not one call's args.
- `knowledge-base/project/learnings/2026-07-18-gh-pages-cert-reissue-restore-failloud-and-onfailure-paging.md`: an `onFailure` handler must fail loud and page through a tagged reporter, never `logger.info`.
- `knowledge-base/project/learnings/2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity.md`: when widening `FailureReason`, audit if-ladders as well as `Record` maps. `classifyAnthropicOrLeaseError` is such an if-ladder.

### Property List (Phase 0.6b)

1. P1: every `agent.spawn.requested` run that ends without the handler returning, whether it failed past retries, timed out or was cancelled at the Inngest level, leaves `action_sends.failure_reason` set, so the Today card leaves "Working".
2. P2: each such run emits a tagged dead-letter, and a run that is not a founder Stop pages the operator through `sentry_alert.spawn_agent_dead_letter`.
3. P3: a run whose terminal state is already recorded is never overwritten or re-reported by the lifecycle path.
4. P4: a retry-exhausted Anthropic 429 reaches the founder as `anthropic_rate_limited`, not `anthropic_timeout`.
5. P5: an in-step failure the classifier cannot positively identify is labelled a paged internal error, not a silent `anthropic_timeout`. Real Anthropic transients (408/409/5xx/connection) keep `anthropic_timeout` and still page no one.
6. P6: the paging policy for the six existing paged reasons and `LEADER_CLASSES_DISABLED` does not change.

### Cut List (Phase 0.6b)

- **Issue #8783's `maxAttempts` + final-attempt `TurnRejection`** → buys P4 → a string `cause` tag set on the live error inside the step buys P4 on every attempt with no attempt arithmetic. `ctx.maxAttempts` is optional in 3.54.2, and that design needed the #8764 harness migration. Cut.
- **Issue #8783's move of the leader-loop retry tests onto `runLikeInngest`** → bought per-request attempt modelling, needed only by the cut `maxAttempts` design. `makeRetryingStep` already models the StepError round-trip. One new `runLikeInngest` case proves the tag with the real serializer. The wholesale migration stays with #8764.
- **A try/catch + `persistFailure` around each unwrapped step** (`read-action-send-created-at`, `precheck`, `cancel-check`, `progress-write`, `tool-i`) → buys P1/P2 for those steps → the `onFailure` handler covers every one of them, and synchronous throws too, at one chokepoint. Cut. Per-step labels would add reasons, and #8803 asks for one.
- **A separate unpaged reason for Inngest-level cancellation** → would buy only a label distinction. The cancel payload cannot tell a timeout (a defect) from an operator cancel, so a label claiming either would be a guess. Cut. The run's `lifecycle` extra records `cancelled`.

### CLAUDE.md / AGENTS.md conventions in play

`cq-union-widening-grep-three-patterns`, `hr-type-widening-cross-consumer-grep`, `cq-silent-fallback-must-mirror-to-sentry`, `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`, `cq-cite-content-anchor-not-line-number`, `hr-observability-as-plan-quality-gate`, `hr-all-infrastructure-provisioning-servers` (the Sentry rule reaches prod only through `apply-sentry-infra.yml`), `wg-use-closes-n-in-pr-body-not-title-to`.

### Functional overlap

`soleur:engineering:discovery:functional-discovery` queried 3/3 registries and found no overlap (the official Inngest plugin is general guidance). Nothing installed. Community discovery was skipped: the TypeScript stack is covered.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| #8803: "Cancellation may not trigger `onFailure` at all." | Confirmed from Inngest docs: it never does. A `timeouts.finish` expiry is ALSO a cancellation, so `onFailure` covers only one of the three cases. | Two lifecycle signals, one settle function. `onFailure` forwards `agent.spawn.orphaned`, and `agent-on-spawn-settle` handles both that event and `inngest/function.cancelled`. |
| #8803: the fix touches "8 files". | Also touched: `app/api/inngest/route.ts` (registering the new settle function), `test/components/dashboard/failure-reason-copy.test.ts` (`ALL_REASONS`), `test/components/dashboard/today-card-state-matrix.test.ts` (CPO-2 list), the contract test's second pin `PROMISED_NOTIFICATION` (four becomes five), `server/spawn-dead-letter.ts` (an optional `lifecycle` message suffix and the COVERAGE comment), `test/server/inngest/function-registry-count.test.ts` (route-entry pin 69 → 70), `scripts/followthroughs/leader-429-label-8758.sh` (the sweeper would reopen a closed #8783 while its probe waits on #8764), ADR-042. | Listed in Files to Edit. |
| #8783: fix via `maxAttempts` and a final-attempt `TurnRejection`, after moving the suite onto `runLikeInngest` (#8764). | `ctx.maxAttempts` is optional in SDK 3.54.2. `makeRetryingStep` already models the StepError round-trip (message, stack, cause). A string `cause` survives the real serializer. | A string `cause` tag set on the live error inside the step. One `runLikeInngest` case proves it with the real serializer. #8764 is not a dependency. |
| #8783 open question: do 500/408/409 on the final attempt need their own labels? | They are Anthropic-side transients. The `anthropic_timeout` copy ("Retry usually works", Retry enabled) is the right founder action for them. | They keep `anthropic_timeout`, now through a positive tag rather than the catch-all. No new label, and no paging change for them. |
| `classifyAnthropicOrLeaseError` "falls through to `anthropic_timeout`" (#8803 item 4). | True. Its production-reachable arms are only the lease causes and a `/timeout/i` message regex. Every other in-step error, including a post-billing cost-write failure, reads as an Anthropic timeout and pages no one. | The catch-all becomes `leader_internal_error` (paged). `anthropic_timeout` needs a positive match. |

## Hypotheses

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

This gate fired on the keyword `timeout`. In this plan that word names the Inngest `timeouts.finish` run cutoff and the Anthropic SDK's own client-side connection timeout, which are both CLASSIFIED here, not diagnosed. No connectivity symptom is under investigation, and no host, firewall, DNS, TLS or SSH path is changed.

| Layer | Status |
|---|---|
| L3 firewall allow-list | not applicable: no inbound/outbound rule or egress IP is involved. The web-1 → Anthropic and web-1 → Supabase/Sentry egress paths are unchanged |
| L3 DNS / routing | not applicable: no hostname or route changes |
| L7 TLS / proxy | not applicable: the existing HTTPS clients (Anthropic SDK, supabase-js, @sentry/nextjs) are unchanged |
| L7 application | in scope. This is the whole plan: how an Anthropic transient (including `APIConnectionTimeoutError`) is LABELLED after retries, and how a run the platform timed out is settled |

## Problem Statement

The leader loop (`agentOnSpawnRequestedHandler`) routes every failure it catches through `persistFailure`. That call writes `action_sends.failure_reason` and sends a tagged dead-letter (`reportSpawnDeadLetter`), which `sentry_alert.spawn_agent_dead_letter` turns into an operator email for paged reasons. Three kinds of run end without ever reaching it:

1. **Retry-exhausted throws the handler does not catch.** Five step names have no try/catch: `read-action-send-created-at`, `turn-N-precheck-cost-ceiling`, `turn-N-cancel-check`, `turn-N-progress-write` and `turn-N-tool-i`. A synchronous throw outside any step lands here too. The run fails and Inngest would call `onFailure`, but none is declared.
2. **The `timeouts: { finish: "10m" }` cutoff.** Inngest cancels the run.
3. **An Inngest-level cancellation** from the API, the dashboard or a bulk cancel.

In all three, the founder's Today card keeps rendering "Working — turn N of 8" (`deriveTodayCardState` row 6) indefinitely, with no failure copy and no Retry, and the operator gets no email. The only Sentry trace is the untagged final-error capture from `sentry-correlation.ts`, and no alert rule routes it.

Separately (#8783), a transient Anthropic error is rethrown from `turn-N-claude` and retried 3 times. It then reaches the handler as a `StepError` without `status`, so `classifyAnthropicOrLeaseError` cannot see a 429 and returns `anthropic_timeout`. The founder reads "Anthropic API timeout. Retry usually works." with Retry enabled, instead of "Anthropic rate-limited. Try again in a minute." with Retry disabled. The same catch-all also labels OUR defects (for example a post-billing `persistTurnCostAwaitable` failure) as an Anthropic timeout, so they never page.

## Proposed Solution

One taxonomy, two halves.

**Half 1: lifecycle terminal state (#8803).** A run that the handler did not finish is settled by ONE function with retries, reached from both Inngest lifecycle signals:

- **`onFailure: agentOnSpawnRequestedOnFailure`** on `agentOnSpawnRequested` covers retry-exhausted failures. It does no settling itself. Its whole body is `await step.sendEvent("forward-orphan", { name: "agent.spawn.orphaned", data: { event: <original event>, run_id: <failed run_id>, error: <{name, message}>, ts: <failure event ts>, lifecycle: "failed" } })`.
  - Why forward rather than settle in place: the SDK hard-codes the `-failure` function to `retries: { attempts: 1 }` (`InngestFunction.getConfig`), with no idempotency. A settle step there would get a single retry, and a brief DB blip would leave the card stuck. Forwarding moves the DB work into the function that has retries and idempotency (deepen, architecture review).
  - It keeps the `onFailure:` key you asked for, on its own line, written plainly because the whole options object is already cast `as unknown as Parameters<…>[0]`. That line is the predicate the #8803 follow-through probe greps on `main`.
- **A new function `agentOnSpawnSettle`** (id `agent-on-spawn-settle`, `retries: 3`, `idempotency: "event.data.run_id"`) has TWO triggers:
  - `{ event: "inngest/function.cancelled", if: "event.data.function_id == 'soleur-runtime-agent-on-spawn-requested'" }` covers the timeout and API/dashboard/bulk cancels. The `if` is a literal `==` string, so it never matches the SDK's own `…-agent-on-spawn-requested-failure` id.
  - `{ event: "agent.spawn.orphaned" }` is the `onFailure` forward.
  - Both payloads carry `data.event` (the original event) and `data.run_id` (the orphaned run), so one handler and one idempotency key serve both. `lifecycle` is `"failed"` for the forward, and for the cancel it is `"timed_out"` or `"cancelled"`: see `timed_out` below.

**A grace sleep for cancels only.** Inngest does not abort a step request that is already running on web-1 when it cancels a run. That request's DB write can still land after the cancel event, for example `mark-acknowledged` or `persistFailure`'s `persist-failure`, both unconditional UPDATEs. So for a cancel the handler first runs `await step.sleep("settle-grace", "2m")`, with an inline comment naming the invariant it relies on: in async mode at most ONE step request is in flight per run, and every `action_sends` writer in the loop is a single UPDATE. A forwarded `failed` event skips the sleep, because the run has already ended and the loop has no parallel steps. (Residual, pre-existing: `persistFailure` reports BEFORE its `persist-failure` step. A cancel landing in that gap means the step never runs, so the settle writes `leader_internal_error` and pages a second time. It is recorded in Risks next to #8841.)

**Envelope validation, as the step's first statements.** It rejects the envelope with a FIXED message (no value echoed) unless all of these hold:

- `data.event.name === "agent.spawn.requested"`;
- `actionSendId`, `founderId` and `messageId` match a UUID pattern;
- `actionClass` is a known `ActionClass`. Otherwise it is carried as `"unknown"`, so a forged class cannot mint unbounded Sentry issues through the message, which is the grouping key.

A fixed message matters because PostgREST's `invalid input syntax for type uuid: "<value>"` would copy a raw id into `extra.err.message`, and the scrubber hashes keys, not free text (security review).

Then the handler runs one memoized step, `settle-orphaned-spawn`, which receives the handler's `attempt` and returns `{ wrote: boolean, reason }`. Every query is scoped to the founder: `.eq("id", actionSendId).eq("user_id", founderId).eq("message_id", messageId)`. A forged or mismatched envelope then matches zero rows and reports nothing. (`action_sends.user_id` is the event's `founderId`, per `writeActionSend`'s insert.)

1. **Reason.** `lifecycle === "cancelled"` (a cancel before the finish timeout) with `cancellation_requested_at` set gives `cancelled_by_operator`, unpaged: the founder asked to stop and the run was stopped. EVERY other case gives `leader_internal_error` (paged), including these two:
   - `timed_out` + Stop. Stop only sets `cancellation_requested_at` (`app/api/dashboard/today/[id]/cancel/route.ts`); there is no `cancelOn`, so a Stop never cancels an Inngest run itself. The likely story is a hung turn, a founder clicking Stop, and `turn-N-cancel-check` never getting to run. That is a hang, so it must page, and the "Stopped. The current turn finished…" copy would be false.
   - `failed` + Stop. A crash is a defect whatever the founder asked.

   The Stop read happens only when `lifecycle === "cancelled"`. A read ERROR falls back to `leader_internal_error` (paged), because the page is the safe side. The founder's Stop is still honoured in substance, since the run is stopped either way.
2. **Write.** A conditional UPDATE `.update({ failure_reason }).eq("id", …).eq("user_id", …).eq("message_id", …).is("failure_reason", null).is("acknowledged_at", null).is("undone_at", null).select("id")`. **Whether to report is decided by the rows this UPDATE returned.** Zero rows covers every no-op in one arm: the body already recorded a terminal state, a concurrent terminal write won, the row is gone (for example after an account-deletion cascade), or the envelope does not belong to that founder.
   - `.is("undone_at", null)` is defence in depth only. Undo requires `reversal_handles`, which only `mark-acknowledged` writes, and that step also sets `acknowledged_at`, so an undone row is already excluded by the `acknowledged_at` filter.
   - **A committed write whose page was lost to a retry.** If the UPDATE commits but the step then fails and is retried, the retry sees zero rows. So on zero rows with `attempt > 0`, the step re-reads the row under the same founder scope. If `failure_reason === reason`, it returns `wrote: true`. The residual is a rare double page when `persistFailure` had written the same reason, which beats silence.

After the step, when `wrote` is true, it calls:

```
reportSpawnDeadLetter({
  reason, actionClass, err, lifecycle,
  extra: { founderId, messageId, sourceRef, actionSendId, failedRunId, elapsedMs },
})
```

- **`lifecycle` goes into the Sentry MESSAGE and into `extra`; it is not a new tag.** The message becomes `agent-on-spawn deadlettered: leader_internal_error [<class>] (<lifecycle>)`, where `lifecycle` is one of `failed`, `cancelled`, `timed_out` or `settle_failed`. The reason is grouping: Sentry groups these events by message, and the alert re-fires per issue at most once every 1442 minutes. With a shared message, a crash email would silence a timeout storm in the same class for a day. `settle_failed` is kept distinct for the same reason, so a settle-step failure never hides behind a real crash's issue. The in-body `persistFailure` path passes no lifecycle, so its message, and every existing Sentry issue, is unchanged. The alert rule filters on tags only, so it is untouched.
- **`timed_out`** is an OPERATOR hint for a cancel whose `elapsedMs >= FINISH_TIMEOUT_MS`. `FINISH_TIMEOUT_MS = 10 * 60_000` is the single source: `timeouts.finish` is built from it, so the two cannot drift. `elapsedMs` = lifecycle event `ts` − original event `ts`. It is measured from when the event was QUEUED, not when the run started, which skews toward `timed_out`; that is acceptable for a hint. A manual cancel can only land before the timeout expires, so reaching the threshold effectively means a timeout. When either `ts` is absent, `elapsedMs` is `null` and `lifecycle` stays `cancelled`. QA I-1 checks that `ts` is present. The founder-facing reason is decided by the rule in step 1, not by the hint.
- `failedRunId` is the ORPHANED run's `data.run_id`, never the ctx `runId`, which belongs to the settle function's own run (the `cronGhPagesCertReissueOnFailure` warning).
- `leader_internal_error` pages; `cancelled_by_operator` is a warning.

The report sits AFTER the step, so a replay does not duplicate it: the step is memoized, and the report runs only in the final invocation. T21 proves this with `runLikeInngest`. (`persistFailure`'s own report is outside any step and duplicates on replay. That is pre-existing, tracked in #8841, and deliberately not copied here.)

If the step throws past its retries (a DB outage, or envelope validation failing), the handler catches it and sends ONE `reportSpawnDeadLetter({ reason: "leader_internal_error", lifecycle: "settle_failed", … })`. That pages, because the card may be stuck. The handler never throws. NONE of the three new handlers (`agentOnSpawnRequestedOnFailure`, `agentOnSpawnSettle`'s handler, `settleOrphanedSpawn`) touches the ctx `logger`: the Inngest ctx logger is not pino and would log the raw founder id (the `persistFailure` note). AC17 pins this with a source grep.

**Founder-visible latency.** A timed-out run shows "Working" for up to about 12 minutes: the 10-minute finish timeout plus the 2-minute grace. A retry-exhausted failure settles within seconds of the run failing.

**A known residual, not fixed here (#8845).** A run that dies AFTER a `turn-N-tool-i` step created a GitHub artifact settles to the failure card WITHOUT Undo, because reversal handles are written only at `mark-acknowledged`. That is equally true of `persistFailure` today. The runbook tells the operator to read the orphaned run's tool-step outputs and tell the founder or reverse the artifact.

`leader_internal_error` is threaded through every surface #8803 names:

- the `FailureReason` union;
- `PAGES_OPERATOR` (`true`);
- `FAILURE_REASON_COPY`: copy "Something went wrong on our side and this run stopped. CTO has been notified.", `retryEligible: false`. It matches every other "CTO has been notified" row, and the Retry button is dead for already-sent messages anyway (the send route answers 409 `not_a_draft`, pre-existing, tracked in #8840);
- the TF `reason in` list, which becomes the seven sorted paged reasons;
- `PINNED_PAGED_REASONS` (six become seven) and `PROMISED_NOTIFICATION` (four become five, since the new copy promises a notification);
- the regenerated `alert-reference.json`.

**Half 2: positive-match classification (#8783, #8803 item 4).** Inside `turn-N-claude`'s pre-billing catch, a live error that `classifyLiveRejection` leaves retryable (it returns `null`) is classified once more while its `status`/`name` are still readable:

- `status === 429` → rethrow tagged `cause: "anthropic_rate_limited"`;
- `status` 408/409 or `>= 500`, or `err instanceof APIConnectionError` (a named import from `@anthropic-ai/sdk`; `APIConnectionTimeoutError` extends it) → rethrow tagged `cause: "anthropic_timeout"`. **Not `name`:** in SDK 0.93.0 both connection classes have `name === "Error"` and `status === undefined`. This was verified at runtime: `new APIConnectionTimeoutError().name` is `"Error"`. So a `name` arm never fires in production, and with the `/timeout/i` regex gone, every network blip would page. Not `constructor.name` either, since Next.js minifies server code. The existing code's `name === "APIConnectionTimeoutError"` arm and its "AC10 anthropic_timeout" test (which hand-sets `err.name`) are therefore dead in production today. The leader-loop suite's `vi.mock("@anthropic-ai/sdk")` must export the REAL `APIConnectionError` / `APIConnectionTimeoutError` classes via `vi.importActual`. The AC10 test must throw `new APIConnectionTimeoutError()` built from the real class, never a hand-named `Error`;
- anything else (e.g. a `ByokLeaseError` from `getRestApiKey`, whose own string `cause` must survive) → rethrow unchanged.

The tag vocabulary IS the `FailureReason` value, so the classifier needs no translation table. The tagged error is a fresh `Error` that keeps the SDK's `message` and `stack` and carries the tag as a string own-property `cause`, the carrier ADR-042's 2026-09-24 amendment already relies on for `ByokLeaseError`. It is still THROWN, so Inngest still retries it 3 times (ADR-042 §I1 unchanged). Only the label of the final failure changes.

`classifyAnthropicOrLeaseError` becomes positive-match only:

| Match (in order) | Reason |
|---|---|
| `cause` ∈ {`fetch_failed`, `decrypt_failed`, `escape`, `subscription_limit`} | `byok_lease_unavailable` (adds the previously unmapped `subscription_limit`) |
| `cause` ∈ `TRANSIENT_ANTHROPIC_CAUSES` (`anthropic_rate_limited`, `anthropic_timeout`) | that `cause` value itself |
| anything else | `leader_internal_error` (paged) |

The classifier is cause-only. The old `name === "ByokLeaseError"` / `MissingByokKeyError` arms are deleted: a StepError rewrites `name`, so they could only ever fire in-process. Every `ByokLeaseError` carries one of its four typed causes, and `MissingByokKeyError` never crosses the boundary, because `classifyLiveRejection` RETURNS it as a `TurnRejection`. A future lease error class that carries no cause would land in `leader_internal_error` and page, which is the right signal for an unmapped class.

The `status === 429` in-process arm, the connection-`name` arms and the `/timeout/i` message regex go away. The in-step tag supersedes all three, and the regex was the arm that turned an arbitrary "statement timeout" from our own database into an "Anthropic API timeout".

## Technical Approach

### Implementation Phases

#### Phase 0: RED tests first (`cq-write-failing-tests-before`)

- 0.1 Leader-loop suite: rewrite the `it.each([429, 500, 408, 409])` block to expect `429 → anthropic_rate_limited` and `500/408/409 → anthropic_timeout`, still with 4 `create` calls and no memoized `turn-1-claude`. Update "an error after billing is never read as a rejection…" to expect `leader_internal_error`. Add a case where an unclassified in-step error (a plain `TypeError` from `create`) → `leader_internal_error`, and one for a `ByokLeaseError(subscription_limit)` after retries → `byok_lease_unavailable`.
- 0.2 `runLikeInngest` cases (`test/helpers/inngest-step-harness.ts`, REAL `serializeError` + `StepError`), each passing its own `memo`:
  - a 429 from `create` on every attempt → `anthropic_rate_limited`, and `memo.get("turn-1-claude")` is `{ ok: false }` with a `StepError` whose `cause === "anthropic_rate_limited"`;
  - a `ByokLeaseError("subscription_limit")` from `getRestApiKey` on every attempt → `byok_lease_unavailable`, with the memoized `StepError`'s `cause === "subscription_limit"`. The classifier is now cause-only, so only the real serializer proves the lease path survives.

  A fresh tagged `Error` also passes in-process, and `makeRetryingStep` copies `cause` by hand, so these memo assertions are what prove the boundary.
- 0.3 Lifecycle tests, in a new `test/server/inngest/agent-on-spawn-lifecycle.test.ts`. They call `agentOnSpawnRequestedOnFailure` and `agentOnSpawnSettleHandler` directly with synthesized envelopes, using the real `reportSpawnDeadLetter` → mocked Sentry (the pattern `spawn-dead-letter.test.ts` uses).
  - The service client is a small IN-MEMORY fake over one fixture row. It APPLIES the recorded `.eq`/`.is(col, null)` filters, so an UPDATE returns the rows that really match. Tests then assert behaviour (rows written, captures sent), not call arguments, and dropping a filter reddens a behavioural assertion.
  - The scenarios are T7–T14 and T22–T24 in Test Scenarios.
- 0.4 Registration tests, in the same file. They import the REAL `inngest` client with the `NEXT_PHASE` hoist `model-tiers.test.ts` uses, because the leader-loop suite mocks `createFunction` and has no `inngest.id`. They read each function's `opts` / `getConfig`, and assert:
  - `agentOnSpawnRequested`'s options carry `onFailure === agentOnSpawnRequestedOnFailure`, and its `getConfig` yields the ids `agent-on-spawn-requested` and `agent-on-spawn-requested-failure`;
  - `agentOnSpawnSettle` has exactly two triggers. The cancelled trigger's `if` equals the SDK-generated failure-trigger expression `agentOnSpawnRequested.getConfig(...)[1].triggers[0].expression` (exact string equality, which also rules out matching the `-failure` id). The other trigger is `agent.spawn.orphaned`;
  - `agentOnSpawnSettle`'s options carry `idempotency: "event.data.run_id"` and `retries: 3`;
  - `agentOnSpawnRequested`'s `timeouts.finish` is built from `FINISH_TIMEOUT_MS`;
  - `app/api/inngest/route.ts` registers `agentOnSpawnSettle`, and `test/server/inngest/function-registry-count.test.ts`'s route-entry pin moves 69 → 70, with a comment line naming `agentOnSpawnSettle`. The entry must sit on its own line with a trailing comma, to match `extractRouteArrayEntries`'s `^\s+(\w+),$`.
- 0.5 Contract/copy tests:
  - `PINNED_PAGED_REASONS` += `leader_internal_error`. `PROMISED_NOTIFICATION` += `leader_internal_error`. Drop the counts from the test titles ("six", "four"), so the next paged reason does not churn them. The TF-set assertion becomes "equals `PINNED_PAGED_REASONS` and is non-empty";
  - `ALL_REASONS` += it, and the CPO-2 list in `today-card-state-matrix.test.ts` += it;
  - `spawn-dead-letter.test.ts`: a `leader_internal_error` report is `error`-level. `spawnDeadLetterMessage` yields a DISTINCT message for each `lifecycle` value, and the unchanged no-lifecycle form for the in-body path. The existing message assertions stay byte-identical.

#### Phase 1: taxonomy surfaces

- `lib/failure-reason.ts`:
  - union += `"leader_internal_error"`, commented "the leader loop ended without the handler recording a terminal state (retry-exhausted throw, finish timeout, Inngest-level cancel), or an in-step error no arm positively classifies";
  - `PAGES_OPERATOR.leader_internal_error = true`, with a one-line why.
- `components/dashboard/failure-reason-copy.ts`: add the row (`retryEligible: false`). Extend the `retryEligible` docstring list with "leader_internal_error → CTO investigates".
- `infra/sentry/issue-alerts.tf`: the `reason` `in` value becomes the seven sorted names, `acknowledgment_persist_failed,anthropic_request_rejected,leader_class_disabled,leader_internal_error,leader_refused,leader_response_truncated,leader_tool_invalid`.
- `infra/sentry/alert-reference.json`: regenerate per `infra/sentry/README.md` "Adding or editing a rule". The regeneration needs a `terraform plan` against the Sentry root (it reads `SENTRY_AUTH_TOKEN`). If the work session cannot authenticate, edit the single projected leaf by hand so the file matches the `jq` projection byte-for-byte. `scripts/sentry-alert-reference-gate.sh` (run by `apply-sentry-infra.yml` on the PR) prints the expected file on mismatch, and that printout is authoritative. Take the gate's artifact, never hand-guess twice.

#### Phase 2: classifier and in-step tag

- `agent-on-spawn-requested.ts`:
  - export `TRANSIENT_ANTHROPIC_CAUSES = ["anthropic_rate_limited", "anthropic_timeout"] as const satisfies readonly FailureReason[]`;
  - add a `tagTransientAnthropicError(err: unknown): unknown` beside `classifyLiveRejection`, and call it at the `if (rejected === null) throw err;` site as `throw tagTransientAnthropicError(err);`;
  - rewrite `classifyAnthropicOrLeaseError` per the table above;
  - leave the `TurnRejection` shape and every memoized return value unchanged (in-flight-run safety).

#### Phase 3: lifecycle handlers

- In `agent-on-spawn-requested.ts`, which must hold the `onFailure:` key for the follow-through probe:
  - `FINISH_TIMEOUT_MS = 10 * 60_000`. `timeouts: { finish: \`${FINISH_TIMEOUT_MS / 60_000}m\` }` is built from it, so it is the single source.
  - `agentOnSpawnRequestedOnFailure({ event, step })`, exported: one `step.sendEvent("forward-orphan", …)` of `agent.spawn.orphaned` carrying `{ event: event.data.event, run_id: event.data.run_id, error: { name, message }, ts: event.ts, lifecycle: "failed" }`. It reads `event.data.*` as `cronGhPagesCertReissueOnFailure` does, and never the ctx `runId`, which is the failure function's own run. `step.sendEvent` is not on the shared `HandlerArgs` step type, so it gets its own args type (precedent: `cron-action-required-sla.ts`).
  - `agentOnSpawnSettleHandler({ event, step, attempt })`, exported, with its own args type whose `step` declares `run` AND `sleep`. It normalises both payloads to `{ original, runId, error, lifecycle, elapsedMs }` and sleeps `settle-grace` only for a cancel. It then calls `settleOrphanedSpawn(step, …, attempt)`, which takes a `run`-only step, so both `HandlerArgs.step` and `HarnessStep` satisfy it.
  - `agentOnSpawnSettle = inngest.createFunction({ id: "agent-on-spawn-settle", retries: 3, idempotency: "event.data.run_id" }, [{ event: "inngest/function.cancelled", if: "event.data.function_id == 'soleur-runtime-agent-on-spawn-requested'" }, { event: "agent.spawn.orphaned" }], agentOnSpawnSettleHandler)`, exported.
  - add `onFailure: agentOnSpawnRequestedOnFailure,` on its own line in `agentOnSpawnRequested`'s already-cast options object.
- Local narrowed types for the three envelopes (`inngest/function.failed`, `inngest/function.cancelled` and `agent.spawn.orphaned`). The SDK's `CancelledEventPayload` omits `event`/`error`, and `ts` is optional. Field reads are guarded.
- `app/api/inngest/route.ts`: import and register `agentOnSpawnSettle` beside `agentOnSpawnRequested`. The `-failure` function is registered by the SDK itself.
- `server/spawn-dead-letter.ts`:
  - `reportSpawnDeadLetter` and `spawnDeadLetterMessage` take an optional `lifecycle?: "failed" | "cancelled" | "timed_out" | "settle_failed"`. When present, it is appended to the message as ` (<lifecycle>)`, on both the main path and the "report failed" fallback, and copied into `extra`. Without it, the message is byte-identical to today. Tags do not change, and `reportSpawnPersistFailed` is unchanged.
  - Rewrite the COVERAGE paragraph. Name every terminal path: `persistFailure`, and the lifecycle settle. Name the TWO remaining gaps honestly: a run Inngest loses entirely (#8839), and a `persist-failure` UPDATE that fails inside `persistFailure`, which returns normally so no lifecycle event fires. `reportSpawnPersistFailed` reports that one, but the card stays on "Working"; it is also noted on #8839.
- `scripts/followthroughs/leader-429-label-8758.sh` (#8783's probe): REWRITE its PASS condition. Today it PASSes only when #8764 closes. `scripts/sweep-followthroughs.sh` `closed_precheck` re-runs the probe of a follow-through issue closed by anyone other than the sweeper, and REOPENS it on FAIL. So `Closes #8783` would be reopened by the sweeper while #8764 stays open. The new probe mirrors `spawn-onfailure-deadletter-8794.sh`: it reads the handler file on `main` via `gh api … contents/…?ref=main`. It PASSes when the file defines `tagTransientAnthropicError` AND `TRANSIENT_ANTHROPIC_CAUSES` AND no longer contains the literal `return "anthropic_timeout";`, the old catch-all. It FAILs otherwise, and reports TRANSIENT on an empty read. It keeps the xtrace-refusal prologue and the `soleur:followthrough-stub v1` marker, and uses no `${VAR:?}` (`scripts/lint-followthrough-varq-ban.sh`).

#### Phase 4: ADRs and docs

- **ADR-042** (the leader loop):
  - an "Amended 2026-09-25" paragraph under §I1: a thrown transient carries its `FailureReason` as a string `cause` set on the live error (429 → `anthropic_rate_limited`; 408/409/5xx/`instanceof APIConnectionError` → `anthropic_timeout`). An untagged thrown error is `leader_internal_error` (paged), which newly pages a post-billing cost-write failure and an uncaused lease-infra error; both are defects on our side. Also record that the `maxAttempts` final-attempt `TurnRejection` design from #8783 was rejected because `ctx.maxAttempts` is optional in SDK 3.54.2.
  - a new **§I6 — terminal state**: every leader-loop run ends in a terminal `action_sends` state. The body records it through `persistFailure`, and a run the body did not finish is settled by `agent-on-spawn-settle`, reached from the `onFailure` forward and from the `inngest/function.cancelled` listener. Link the new fleet ADR below.
- **New ADR (provisional ADR-251; re-verify the ordinal against `origin/main` at ship):** "Inngest functions that must leave a terminal record handle both lifecycle signals". Its rule: `onFailure` never sees a cancel or a timeout, so a function that owes a user-visible terminal record needs BOTH entry points. Do the settling in ONE function with retries and idempotency: `onFailure` forwards to it, because the SDK pins `-failure` to a single retry. Name `cronGhPagesCertReissueOnFailure` as a pre-existing function that handles only `onFailure`, and do not change it here. Sibling of ADR-030. Write it via `soleur:architecture`.
- **New runbook** `knowledge-base/engineering/operations/runbooks/spawn-dead-letter-triage.md` (short, no SSH). It maps each message suffix (none / `(failed)` / `(cancelled)` / `(timed_out)` / `(settle_failed)`) to a next step:
  - read the issue with `scripts/sentry-issue.sh`;
  - for `(failed)`, search Sentry for `inngest.run_id:<extra.failedRunId>` to find the failed run's own final-error capture (layer 1). A cancel has no such capture. Pino carries no per-run line for the leader loop, so do NOT send the operator to Better Stack for run lines;
  - for any lifecycle, check the orphaned run's `turn-N-tool-i` outputs for GitHub artifacts that were created but cannot be undone (#8845), and tell the founder;
  - a `leader_internal_error` in the first ~30 minutes after a deploy whose `extra.err.message` is an Anthropic error is the known rollout false page;
  - `(settle_failed)` means the card may still show "Working". This PR has no automated re-drive; the backstop for it is #8839. Record the `actionSendId` on #8839.

  The TF rule's comment and the `server/spawn-dead-letter.ts` header both point to it.

### Files to Edit

- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`
- `apps/web-platform/lib/failure-reason.ts`
- `apps/web-platform/components/dashboard/failure-reason-copy.ts`
- `apps/web-platform/server/spawn-dead-letter.ts` (optional `lifecycle` message suffix + COVERAGE comment + runbook pointer)
- `apps/web-platform/app/api/inngest/route.ts`
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (69 → 70)
- `scripts/followthroughs/leader-429-label-8758.sh` (PASS on the fix, not on #8764)
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json` (regenerated)
- `apps/web-platform/test/sentry-spawn-dead-letter-alert-op-contract.test.ts`
- `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts`
- `apps/web-platform/test/server/spawn-dead-letter.test.ts`
- `apps/web-platform/test/components/dashboard/failure-reason-copy.test.ts`
- `apps/web-platform/test/components/dashboard/today-card-state-matrix.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-042-anthropic-sdk-inside-inngest-leader-loop.md`

### Files to Create

- `apps/web-platform/test/server/inngest/agent-on-spawn-lifecycle.test.ts`
- `knowledge-base/engineering/operations/runbooks/spawn-dead-letter-triage.md`
- `knowledge-base/engineering/architecture/decisions/ADR-251-inngest-terminal-record-handles-both-lifecycle-signals.md` (provisional ordinal)

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| #8783's `maxAttempts` + final-attempt `TurnRejection` for a live 429 | `ctx.maxAttempts` is optional (`BaseContext.maxAttempts?`, SDK 3.54.2). Absent, the final attempt is unknowable and the mislabel persists. It needs per-request attempt modelling (#8764's migration). It covers only 429, where the tag covers the whole transient family at the same site. |
| Encode the status in the error MESSAGE and regex it after the boundary | The message survives, but a regex over free text also matches unrelated text. The 2026-09-24 session superseded exactly this carrier. A string `cause` is a dedicated field. |
| try/catch + `persistFailure` around each unwrapped step | Five sites plus every synchronous throw, each needing a label. `onFailure` is one chokepoint that also covers future steps. Per-step labels are not asked for. |
| A single two-trigger listener on `inngest/function.failed` + `inngest/function.cancelled` with NO `onFailure` (DHH plan-review) | This drops the `onFailure` mechanism the operator named and the #8803 probe keys on. The adopted design gets the same benefit (one settle function with `retries: 3`, idempotency and the grace sleep) by having `onFailure` FORWARD `agent.spawn.orphaned` to that function (architecture review). |
| Settle in place inside `onFailure` | The SDK pins the `-failure` function to `retries: { attempts: 1 }` with no idempotency, so a brief DB blip leaves the card stuck. That is why `onFailure` forwards instead. |
| Only `onFailure` (the issue's step 1) | Leaves the finish timeout and every cancellation stuck on "Working". Inngest documents both as `function.cancelled`, which `onFailure` never sees. |
| A distinct unpaged reason for Inngest-level cancellation | The payload's `error.message` is `"function cancelled"` for both a timeout (a hang, our defect) and an operator cancel. Any label claiming one of them would be a guess. Paging an operator for a cancel they made is cheap. Missing a hang is not. |
| A client-side "stale Working" fallback in `deriveTodayCardState` | It covers even a run Inngest loses entirely, but it changes the UI state matrix (Product/UX gate, wireframe) and would guess at liveness. Deferred and tracked (Non-Goals). |

## Non-Goals / Deferred

- **Rows already stuck on "Working" in production, and runs Inngest loses entirely** (server state loss, so no lifecycle event fires). This PR fixes the terminal state going forward. A backstop needs either a sweep cron or a client-side staleness rule, and both are product/data decisions. Tracked in the issue filed at plan time (see `## Deferral Tracking`).
- Items 2-4 of the operator's follow-up list (preflight Check 10 YAML escape decoding, ship Phase 7 Monitor `CLAUDE_PLUGIN_ROOT`, the `guardrails.sh` issues/N/labels false positive) are separate PRs.
- #8764 (the general suite migration onto the step harness) is untouched and stays open.

## Deferral Tracking

- #8839: a backstop for spawns stuck on "Working" that no Inngest lifecycle event settles (historical rows, and runs Inngest loses entirely). Milestone Post-MVP / Later.

Pre-existing defects found while planning (`wg-when-an-audit-identifies-pre-existing`). Both are filed, and neither is folded in, per the operator's scope instruction:

- #8840: the Today card's Retry button is dead for every retry-eligible reason. The send route returns 409 `not_a_draft` for an already-archived message. This is why `leader_internal_error` ships `retryEligible: false`.
- #8845: a spawn that fails after a tool step leaves GitHub artifacts with no Undo, because reversal handles are written only at `mark-acknowledged`. The runbook covers operator triage.
- #8841: `persistFailure` reports the dead-letter outside any `step.run`, so a replay re-reports it. The new settle helper does not copy the pattern.

## Open Code-Review Overlap

2 open scope-outs touch these files. Both are this plan's targets:

- #8803 (no `onFailure`; runs past retries/timeout/cancel never dead-letter). **Fold in**: `Closes #8803`.
- #8783 (retry-exhausted 429 labelled `anthropic_timeout`). **Fold in**: `Closes #8783`.

No other open `code-review` issue body names `agent-on-spawn-requested.ts`, `failure-reason.ts`, `failure-reason-copy.ts`, `issue-alerts.tf`, `spawn-dead-letter.ts` or the leader-loop suite.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Today card (`components/dashboard/today-card.tsx`, via `deriveTodayCardState`) still stuck on "Working — turn N of 8" after a spawn died. Or a real Anthropic outage mislabelled "Something went wrong on our side" (a wrong tag arm). Or a founder Stop overwritten with an internal-error card (a wrong precedence in `settleOrphanedSpawn`).
- **Also user-visible, pre-existing and not fixed here:** a run that dies after creating a GitHub artifact settles to a failure card with no Undo (#8845). A timed-out run shows "Working" for up to about 12 minutes before it settles.
- **If this leaks, the user's data is exposed via:** the new lifecycle envelopes carry the original event, including the raw `founderId`, in two places. It appears in the Sentry scope extra `inngest.event_data` that `sentry-correlation.ts` attaches, and in whatever the handler passes to `reportSpawnDeadLetter`. `server/sentry-scrub.ts` `scrubRecursive` hashes nested `founderId` fleet-wide, and `reportSpawnDeadLetter` pseudonymizes `founderId` to `userIdHash`. The tests search the WHOLE event for the raw id, not one call's arguments.
- **Brand-survival threshold:** `aggregate pattern`. A stuck card or a mislabel costs trust across founders over time. It exposes no founder data and loses no money beyond an already-bounded spawn.

## Observability

```yaml
liveness_signal:
  what: "sentry_alert.spawn_agent_dead_letter email on a tagged event feature=spawn-agent op=agent-on-spawn-requested reason=leader_internal_error (layer 2: reportSilentFallback message path -> Sentry, plus its pino line)"
  cadence: "per dead-letter: first-seen, reappeared and regression triggers, plus the 1h event-frequency trigger, throttled by frequency_minutes 1442 per Sentry issue; each (reason, class, lifecycle) message is its own issue"
  alert_target: "operator email (issue_owners, ActiveMembers fallthrough)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (sentry_alert.spawn_agent_dead_letter), applied by .github/workflows/apply-sentry-infra.yml"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (reportSpawnDeadLetter -> reportSilentFallback message path, layer 2) plus the pino line to Better Stack"
  fail_loud: "Sentry message 'agent-on-spawn deadlettered: leader_internal_error [<actionClass>] (failed|cancelled|timed_out|settle_failed)' at error level; extra.failedRunId, extra.elapsedMs, extra.err"

failure_modes:
  - mode: "a step throws past its retries or a synchronous throw ends the run (retry-exhausted failure)"
    detection: "layer 1: sentry-correlation final-error capture on the failed run (tag inngest.run_id). Layer 2: onFailure forwards agent.spawn.orphaned, agent-on-spawn-settle writes leader_internal_error and emits the '(failed)' dead-letter"
    alert_route: "operator email via sentry_alert.spawn_agent_dead_letter"
  - mode: "the timeouts.finish 10m cutoff, or a cancel from the Inngest API or dashboard"
    detection: "layer 2: agent-on-spawn-settle on inngest/function.cancelled (if-filtered to soleur-runtime-agent-on-spawn-requested) emits the '(timed_out)' or '(cancelled)' dead-letter after the 2m grace"
    alert_route: "operator email via sentry_alert.spawn_agent_dead_letter"
  - mode: "the settle step's own DB read or write fails past its retries, or the envelope fails validation"
    detection: "layer 2: catch in agentOnSpawnSettleHandler -> one '(settle_failed)' leader_internal_error dead-letter, its own Sentry issue"
    alert_route: "operator email via sentry_alert.spawn_agent_dead_letter"
  - mode: "an in-step error no arm positively classifies (e.g. a post-billing cost-write failure)"
    detection: "layer 2: classifyAnthropicOrLeaseError catch-all -> persistFailure(leader_internal_error) dead-letter with no lifecycle suffix"
    alert_route: "operator email via sentry_alert.spawn_agent_dead_letter"
  - mode: "the -failure function or agent-on-spawn-settle never registers on the prd Inngest server (no re-sync, or v1.19.4 differs from the dev CLI)"
    detection: "pre-merge: registration tests (T15-T17) and QA I-1 on a pinned v1.19.4 dev server. Post-merge: P-4 reads function_ids through cutover-inngest.yml op=registry-probe (workflow run log; deploy webhook, no SSH). Sync errors surface in layer 3 (Vector -> Better Stack, inngest-server WARN+)"
    alert_route: "workflow run log for P-4 (postmerge fails loud); CI red on the PR for T15-T17"
  - mode: "the #8803 onFailure key regresses on main before #8803 has a recorded PASS"
    detection: "scripts/followthroughs/spawn-onfailure-deadletter-8794.sh run by scheduled-followthrough-sweeper.yml (workflow run log)"
    alert_route: "the sweeper comments on or reopens #8803"
  - mode: "a retry-exhausted Anthropic 429 (the founder's rate limit)"
    detection: "layer 2: anthropic_rate_limited dead-letter at warning level (by design, unpaged)"
    alert_route: "none (founder-actionable; the Today card shows 'Try again in a minute')"

logs:
  where: "pino (server/logger.ts) -> Better Stack, one line per dead-letter from reportSilentFallback / warnSilentFallback; Sentry event with extra.err (name, message, stack)"
  retention: "Better Stack source retention for the web-platform source; Sentry event retention per the org plan"

discoverability_test:
  command: "grep -hoE 'leader_internal_error|agentOnSpawnSettle' apps/web-platform/infra/sentry/alert-reference.json apps/web-platform/app/api/inngest/route.ts"
  expected_output: "leader_internal_error, agentOnSpawnSettle"
```

The affected surface (`*agent-on-spawn*`, plan Phase 2.9.2) is an Inngest function body on web-1. Every detection above is emitted FROM the function or its lifecycle handler, not from a host probe. A single event tells the causes apart through three things: the message suffix (none / `(failed)` / `(cancelled)` / `(timed_out)` / `(settle_failed)`), `extra.elapsedMs` and `extra.err.name/message`. It distinguishes the three #8803 causes, the in-body catch-all and a settle-step failure. Triage steps live in `knowledge-base/engineering/operations/runbooks/spawn-dead-letter-triage.md`, which uses no SSH.

## Encryption Posture

This plan adds no store and no connection. It writes one more value into an existing column (`action_sends.failure_reason`, Supabase prd) and sends one more tagged event over the existing web-platform → Sentry SDK channel. The `inngest/function.cancelled` delivery rides the existing, ledgered web ↔ inngest-host private-network connection (`scripts/encryption-posture-ledger.json`, whose plaintext exception is tracked there). This PR neither adds nor changes it.

```yaml
at_rest:
  - store: supabase.prd (action_sends.failure_reason, existing column)
    mechanism: provider-managed:supabase-postgres-aes256
    evidence: "scripts/encryption-posture-ledger.json store supabase.prd — Supabase encrypts Postgres data at rest with AES-256 (https://supabase.com/docs/guides/security, retrieved_on 2026-07-24)"
    defends_against: "physical-media compromise of the managed Postgres storage"
    does_not_defend: "a leaked service-role key, an RLS bypass, or any query over a legitimate connection; the key is provider-managed"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:named SOC 2 attestation formalization pending; tracked #6911"
in_transit:
  - connection: "web-platform server -> Supabase Postgres/PostgREST (the settle step's read and conditional UPDATE)"
    enforced_at: "apps/web-platform/lib/supabase/service.ts (getServiceClient)"
    tls: "https (Supabase REST) / TLS 1.2+"
    cert_verification: on
    does_not_defend: "a leaked service-role key; TLS protects the channel, not the credential"
    disclosed_as: "docs/legal/data-protection-disclosure.md:TLS for data in transit"
  - connection: "web-platform server -> Sentry ingest (the dead-letter event)"
    enforced_at: "apps/web-platform/sentry.server.config.ts (SENTRY_DSN, https)"
    tls: "https / TLS 1.2+"
    cert_verification: on
    does_not_defend: "a leaked DSN (write-only ingest), or PII placed in the event body itself; the scrubber (server/sentry-scrub.ts) and message-path reporting are what keep the raw founder id out"
    disclosed_as: not-publicly-claimed
```

## Architecture Decision (ADR/C4)

### ADR

Both ADR changes are written via `soleur:architecture` (Phase 4):

- **Amend ADR-042** (an extension, not a reversal):
  - the §I1 2026-09-25 amendment covers the string-`cause` tag on thrown transients, the paged catch-all and its consequence, and the rejected `maxAttempts` design;
  - a new **§I6 — terminal state** records that every leader-loop run ends terminal, through `persistFailure` or `agent-on-spawn-settle`.

  The terminal-state invariant sits in its own §I6 because §I1 is the per-turn step layout (architecture review).
- **New ADR (provisional ADR-251):** "Inngest functions that must leave a terminal record handle both lifecycle signals". The rule applies across the Inngest fleet, not to the Anthropic-SDK leader loop alone, so it does not belong inside ADR-042 (architecture + CTO reviews). It is a sibling of ADR-030. `cronGhPagesCertReissueOnFailure` handles only `onFailure`; the ADR names it as a known pre-existing gap and does not change it here. The ordinal is PROVISIONAL: `ls knowledge-base/engineering/architecture/decisions | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1` against freshly fetched `origin/main` and every pushed branch gave ADR-250 on 2026-09-25. `soleur:ship`'s ADR-Ordinal Collision Gate re-verifies it; a renumber must sweep this plan and `tasks.md`.

### C4 views

No C4 change. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors:** `founder` (who reads the Today card) and the operator (who receives the email, the same `founder` actor, "Founder / Operator") are already modeled. No new actor.
- **External systems:** `sentry` (`webapp -> sentry`, "Exceptions + debounced warns via the @sentry/nextjs SDK") and `anthropic` are already modeled. No new vendor.
- **Containers/stores:** `inngest` ("Inngest Server"), `supabase` (`api -> supabase`), `dashboard`, `api`. The new `agent-on-spawn-settle` function and the SDK's `-failure` function are functions inside the existing webapp serve endpoint (`app/api/inngest/route.ts`), over the existing `api -> inngest` and Inngest → serve-URL paths. No new container or store.
- **Relationships:** no access relationship changes. The same service-role write to `action_sends` and the same Sentry emit are used.
- **Cardinalities:** `c4-count-parity` counts cron monitors and CI emitters. The new function is not a `cron-*` file and adds no Sentry cron monitor. The work phase must still run `plugins/soleur/test/c4-count-parity.test.sh` green, along with `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

### Sequencing

The ADR amendment ships in this PR, in Phase 4.

## Guard Contract

### Guard 1 — paged-reason contract (emitter ↔ rule ↔ copy)

**Property.** The set of reasons whose dead-letter is error-level equals the set the Sentry rule's `reason in` filter matches, equals the pinned set, and every founder-copy row that promises a notification is in that set.

**Assembly.** There are two chokepoints, and they are named separately because either can drift alone. (a) The code side: `PAGES_OPERATOR` (`lib/failure-reason.ts`), from which `PAGED_DEAD_LETTER_REASONS` (`server/spawn-dead-letter.ts`) and the `reportSilentFallback`/`warnSilentFallback` choice in `reportSpawnDeadLetter` are both derived. (b) The rule side: the `reason` `in` string in `sentry_alert.spawn_agent_dead_letter` (`infra/sentry/issue-alerts.tf`), projected into `infra/sentry/alert-reference.json` and compared against the PR plan by `scripts/sentry-alert-reference-gate.sh` and against live Sentry by `scheduled-sentry-alert-drift.yml`. The copy side (`FAILURE_REASON_COPY` rows containing "CTO has been notified") is checked against (a).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `leader_internal_error` from the TF `in` string only | RED (`filters reason with in over exactly the paged set`) |
| 2 | Flip `PAGES_OPERATOR.leader_internal_error` to `false` | RED (pinned-set test AND the copy-promise test, since the copy promises a notification) |
| 3 | Add a second new `true` reason after `leader_internal_error` in `PAGES_OPERATOR`, without touching TF or the pin | RED (pinned-set test) |
| 4 | Remove "CTO has been notified" from the new copy row | RED (`PROMISED_NOTIFICATION` equality) |
| 5 | Leave `alert-reference.json` un-regenerated after the TF edit | RED (`scripts/sentry-alert-reference-gate.sh` via `apply-sentry-infra.yml`) |

**Harness rows.** RED on a suite edit: make the TF value extraction return `""`. The suite must fail on the empty set rather than compare two empty sets, so the assertion is "TF set equals `PINNED_PAGED_REASONS` AND is non-empty". Must-PASS: reorder the TF `in` list (same set, different order), which PASSes because the test sorts.

**Anchor.** `PINNED_PAGED_REASONS` is a stored value one diff can edit together with `PAGES_OPERATOR`. The value outside the commit is the operator's settled paging policy (six existing reasons unchanged). The pin exists so any change to it shows up as a reviewed diff line, and the test title's count ("seven") moves with it.

### Guard 2 — lifecycle routing (every bypass path reaches the settle helper)

**Property.** Every Inngest terminal path of `agent-on-spawn-requested` that bypasses the handler's own return, whether `inngest/function.failed` or `inngest/function.cancelled`, is routed to `settleOrphanedSpawn`, which writes a terminal state only on a row that has none.

**Assembly.** There are three chokepoints, all required. The `onFailure` key in `agentOnSpawnRequested`'s options. `agentOnSpawnSettle`'s two triggers: the `agent.spawn.orphaned` forward, and the `inngest/function.cancelled` trigger's literal `if` filter, whose expected value is the SDK-generated failure-trigger expression of `agentOnSpawnRequested` (T16). And the served array in `app/api/inngest/route.ts`: a settle function that is not served never runs. Inside the helper, the chokepoint is the conditional UPDATE's `.is("failure_reason", null).is("acknowledged_at", null).is("undone_at", null)` filters.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `onFailure:` line | RED (T15 options identity test; AC4's grep at work time) |
| 2 | Rename `agentOnSpawnRequested`'s `id` without updating the settle function's literal `if` (or misspell the literal) | RED (T16: expected value is the SDK-generated failure-trigger expression) |
| 3 | Remove `agentOnSpawnSettle` from the route array, or drop its `agent.spawn.orphaned` trigger after a compliant cancelled trigger | RED (T16/T17) |
| 4 | Drop the `.is("acknowledged_at", null)` filter from the UPDATE, after a compliant `.is("failure_reason", null)` | RED (the test asserts BOTH filter calls on the update chain) |
| 5 | REORDER: move `reportSpawnDeadLetter` before the step (report even when the UPDATE returned zero rows) | RED (the T10 terminal-row case asserts zero dead-letter captures) |
| 6 | Precedence: write `leader_internal_error` for `lifecycle: "cancelled"` with `cancellation_requested_at` set, and then (the second member) write `cancelled_by_operator` for `lifecycle: "failed"` with it set | RED (cancelled + Stop expects `cancelled_by_operator`; failed + Stop expects `leader_internal_error`) |
| 7 | REORDER: move the settle handler's `step.sleep("settle-grace", …)` after `settle-orphaned-spawn`, or delete it | RED (the T8 cancel rows record step ops in order and asserts `settle-grace` precedes `settle-orphaned-spawn`) |
| 8 | `onFailure` settles in place instead of forwarding `agent.spawn.orphaned` (loses retries and idempotency) | RED (T7: the handler must send exactly one event and make no DB call) |
| 9 | Drop `.eq("user_id", founderId)` from the UPDATE, after a compliant `.eq("id", …)` | RED (T13: a foreign row is written by the in-memory fake) |

**Harness rows.** RED on a suite edit: replace the mocked update chain with one that ignores `.is()` calls. The filter assertion in row 4 must read the recorded call args, not the resulting row, so it stays RED. Must-PASS: an envelope whose `data` carries extra unknown fields (`events`, `correlation_id`) settles normally.

### Guard 3 — positive-match classification survives the step boundary

**Property.** A transient Anthropic error that exhausts its retries is labelled from a tag set on the live error inside the step, and a thrown error carrying no recognised tag or lease cause is `leader_internal_error`.

**Assembly.** One chokepoint: the `if (rejected === null)` rethrow site in `turn-N-claude`, where `tagTransientAnthropicError` is applied. `classifyAnthropicOrLeaseError` is the single reader. The tag must survive the REAL `serializeError` + `StepError`, which only the `runLikeInngest` case exercises.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `tagTransientAnthropicError` call (rethrow `err` raw) | RED (429 → expects `anthropic_rate_limited`, gets `leader_internal_error`) |
| 2 | Set the tag as an `Error` object instead of a string `cause` | RED (the `runLikeInngest` case asserts the memoized `StepError`'s `cause === "anthropic_rate_limited"`, a string) |
| 3 | Classify connection errors by `name` instead of `instanceof APIConnectionError` | RED (the AC10 case throws a real-class `APIConnectionTimeoutError`, whose `name` is `"Error"`) |
| 4 | A 500 after a compliant 429 in the same `it.each` (the second member) mapped to `anthropic_rate_limited` by a lazy `status >= 400` arm | RED (500 expects `anthropic_timeout`) |
| 5 | Restore the old unconditional `return "anthropic_timeout"` catch-all | RED (plain `TypeError` → expects `leader_internal_error`; post-billing failure → expects `leader_internal_error`) |

**Harness rows.** RED on a suite edit: switch the `runLikeInngest` case to `makeStep` (no boundary). The case's own assertion that the harness reported a rebuilt `StepError` must fail. Must-PASS: a `ByokLeaseError(fetch_failed)` from `getRestApiKey`, which must keep `byok_lease_unavailable`. That proves the tag does not overwrite a lease cause.

## Risks & Mitigations

- **The timeout → `function.cancelled` claim comes from Inngest docs, not from our self-hosted v1.19.4.** Mitigation: QA step I-1 (below) proves it once on a local `inngest-cli dev` pinned to the same server version, using a throwaway `timeouts.finish: "5s"` function and the real listener shape. If the server does NOT emit `function.cancelled` on a timeout, the plan's P1 for timeouts fails. The work phase must then stop and re-plan, not ship `onFailure` alone as if it covered timeouts.
- **Deploy-window false page.** A run mid-retry on `turn-N-claude` at deploy replays a StepError that the OLD code threw untagged. The new catch-all labels it `leader_internal_error` and pages, where the old code said `anthropic_timeout`. That is a one-off during rollout, and the PR body says so.
- **New functions not registered with the Inngest server.** If the app does not re-sync after deploy, the `-failure` and `agent-on-spawn-settle` functions never run, and nothing says so. Mitigation: a unit test asserts that `agentOnSpawnRequested`'s registration config yields both `agent-on-spawn-requested` and `agent-on-spawn-requested-failure`, and that the route serves `agentOnSpawnCancelled`. That is the part the diff controls. Server-side registration rides the existing sync on every `web-platform-release.yml` deploy, the same path every function has used. A before/after `function_count` delta was considered and dropped: any concurrent merge that adds or removes a function flips it, so it measures the fleet, not this change (`cq-ac-must-not-depend-on-concurrent-sessions`).
- **Finish timeouts during an Anthropic 429/5xx storm now page.** Eight turns of SDK retries plus 3 Inngest step retries can exceed 10 minutes. Each such run pages `leader_internal_error` with `lifecycle: cancelled` and a large `elapsedMs`. That is the intended visibility. The Sentry issue is per (reason, class) with a 1442-minute throttle, so a storm yields at most one email per affected class per day.
- **A late in-flight step write after the settle function settles.** The `settle-grace` sleep (2 minutes) outlasts any single `action_sends` UPDATE step, and the conditional UPDATE never overwrites a terminal state. The residual would be a writer that takes longer than 2 minutes, and no such step exists: `turn-N-claude` can run long but never writes `action_sends`.
  - **Deliberately NOT done: gating `mark-acknowledged` and `persist-failure` with `.is("failure_reason", null)`.** The scoped advisor proposed it. It was rejected because, in the residual collision, the late `mark-acknowledged` carries `reversal_handles`. Gating it would drop the handles, so the founder could not Undo an artifact that really landed on GitHub. Ungated, the row keeps both `failure_reason` and `reversal_handles`, and `deriveTodayCardState` row 1 renders the failure WITH Undo. A late `persist-failure` overwriting `leader_internal_error` with its more specific reason is also the better outcome. The grace sleep is the correctness mechanism; the unconditional late writers are the safer failure mode.
- **In-flight memoized shapes.** No step's RETURN shape changes. Only thrown errors and the post-step classifier change (learning: changing-a-step-return-shape-strands-in-flight-runs).

## Acceptance Criteria

### Functional

- [ ] AC1: `lib/failure-reason.ts` declares `leader_internal_error` in `FailureReason`, and `PAGES_OPERATOR.leader_internal_error === true`. The six existing `true` rows are unchanged and all other rows stay `false` (`git diff` of `PAGES_OPERATOR` shows exactly one added line).
- [ ] AC2: `FAILURE_REASON_COPY.leader_internal_error` exists, contains "CTO has been notified", does not contain the raw key, and has `retryEligible: false`.
- [ ] AC3: `sentry_alert.spawn_agent_dead_letter`'s `reason` `in` value is exactly `acknowledgment_persist_failed,anthropic_request_rejected,leader_class_disabled,leader_internal_error,leader_refused,leader_response_truncated,leader_tool_invalid`. `infra/sentry/alert-reference.json` is regenerated, and `scripts/sentry-alert-reference-gate.sh` is green in `apply-sentry-infra.yml`.
- [ ] AC4: `grep -Ec '^[[:space:]]*onFailure[[:space:]]*:' apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` prints `1`. That is the exact predicate `scripts/followthroughs/spawn-onfailure-deadletter-8794.sh` applies to `main`'s copy.
- [ ] AC5: `agentOnSpawnSettle` is exported and served from `app/api/inngest/route.ts`. It is triggered by `inngest/function.cancelled` with `if` equal to the SDK-generated `event.data.function_id == 'soleur-runtime-agent-on-spawn-requested'`, AND by `agent.spawn.orphaned`, which `onFailure` forwards. It is configured with `retries: 3` and `idempotency: "event.data.run_id"`. `function-registry-count.test.ts` pins 70.
- [ ] AC6: `settleOrphanedSpawn` follows the T8 precedence matrix. Every query is scoped by `id` + `user_id` + `message_id`. It reports only on rows the UPDATE returned, plus the `attempt > 0` re-read (T12b). A terminal, undone, missing or foreign row produces zero reports (T10, T13). Envelope validation rejects with a fixed message (T14). A step failure produces exactly one `(settle_failed)` page (T12). It never throws. A settled row renders as the failure card, not "Working" (T22).
- [ ] AC7: A retry-exhausted Anthropic 429 ends as `anthropic_rate_limited`, both through `makeRetryingStep` and through `runLikeInngest` (real serializer). 500/408/409 end as `anthropic_timeout`. `create` is still called 4 times for each (retry behaviour unchanged).
- [ ] AC8: `classifyAnthropicOrLeaseError` has no unconditional `anthropic_timeout` return and no `/timeout/i` regex. An untagged thrown error → `leader_internal_error`. `ByokLeaseError` causes, including `subscription_limit` → `byok_lease_unavailable`.
- [ ] AC9: `scripts/followthroughs/leader-429-label-8758.sh` no longer references #8764 (`grep -c 8764` prints `0`). Its PASS predicate matches the branch's handler file when applied locally (the same `grep` the probe runs, over the working-tree file). It passes `scripts/lint-followthrough-varq-ban.sh`.
- [ ] AC10: ADR-042 carries the §I1 2026-09-25 amendment (the tag carrier, the catch-all paging consequence, the rejected `maxAttempts`) and a new §I6 terminal-state invariant. The new fleet ADR (provisional ADR-251, ordinal re-verified against `origin/main` before merge) exists and is linked from §I6.

### Non-functional

- [ ] AC11: No raw `founderId` appears anywhere in a lifecycle dead-letter's Sentry event. The test searches the whole event after `scrubSentryEvent`, covering `captureMessage` args, breadcrumbs and the `inngest.event_data` scope extra shape (nested `event.data.founderId`).
- [ ] AC12: No step's return shape changes. `git diff` of `agent-on-spawn-requested.ts` shows no change to `TurnRejection` / `AnthropicTurnResult` or to any EXISTING `step.run` callback's return value. The new `settle-orphaned-spawn` step runs in new functions and strands nothing.
- [ ] AC13: `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` are green (the "no C4 impact" claim).
- [ ] AC14: The touched web-platform vitest suites (`cd apps/web-platform && ./node_modules/.bin/vitest run <paths>`) and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` are green. `tsc` is the enumerator for every exhaustive `Record<FailureReason, …>`: `PAGES_OPERATOR` and `FAILURE_REASON_COPY`.

- [ ] AC17: `agentOnSpawnRequestedOnFailure`, `agentOnSpawnSettleHandler` and `settleOrphanedSpawn` never reference the ctx `logger` (T23).
- [ ] AC18: `spawn-dead-letter-triage.md` exists, contains no `ssh` command, and is linked from the TF rule comment and the `server/spawn-dead-letter.ts` header.

### Post-merge (automated, `soleur:postmerge`)

- [ ] AC15: Postmerge P-1: both follow-through probes print `PASS:` against `main`.
- [ ] AC16: Postmerge P-3: `apply-sentry-infra.yml` ran green on the merge commit.
- [ ] AC19: Postmerge P-4: the prd registry lists both `…-failure` and `…-agent-on-spawn-settle`.

### PR body

- [ ] `Closes #8803` and `Closes #8783` in the body, not the title. `Ref #8839 #8840 #8841 #8845`.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** The CTO confirmed the direction and the string-`cause` carrier, and raised five changes, all folded in:

- report on the conditional UPDATE's returned rows, not on the read (TOCTOU);
- a grace `step.sleep` in the cancelled listener before settling (a step still in flight can write after the cancel event);
- Stop → `cancelled_by_operator` only for `lifecycle: cancelled` (a crash is a defect even with a Stop pending);
- `retryEligible: false`, because the send route 409s any retry of an archived message (#8840);
- the registry count pin 69 → 70, plus rewriting #8783's follow-through probe, since the sweeper's `closed_precheck` would otherwise reopen it.

It also asked for `lifecycle` as a Sentry tag (adopted instead as a MESSAGE suffix, per its own later devex review, so each cause gets its own Sentry issue), the failed run's `run_id`, `elapsedMs` to tell a timeout from a manual cancel, no ctx logger in the helper, and a dev proof that timeouts emit `function.cancelled` on v1.19.4. All are folded in (QA I-1). It noted the pre-existing replay double-report in `persistFailure` (filed #8841). It suggested a standalone ADR for the lifecycle pattern; this plan amends ADR-042 instead (see ADR section) and records the reusable rule there.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

Deepen-plan note: the founder can see "Working" for up to about 12 minutes on a timed-out run (the 10-minute finish timeout plus the 2-minute grace) before the failure copy appears. A retry-exhausted failure settles within seconds. The failure card offers no action: Stop, Undo, Retry and Resume are all absent. That is recorded as Taste item T-1 in `decision-challenges.md` (the copy could name a next step).

The only founder-visible change is one new copy row in an existing table (`failure-reason-copy.ts`, a `.ts` file matching none of the UI-surface globs). The Today card also now leaves "Working" for runs that used to hang. There is no new page, component, flow or layout. The copy follows the existing "what happened. who is on it." shape of the other paged rows. No domain leader recommended a copywriter.

## Test Scenarios

### Acceptance (RED first)

- T1: Given `create` rejects with a 429 on every attempt, when the loop runs under `makeRetryingStep({ retries: 3 })`, then the result is `anthropic_rate_limited` and `create` was called 4 times.
- T2: Given the same 429 under `runLikeInngest` (real `serializeError` + `StepError`), then `anthropic_rate_limited`, and the memoized `turn-1-claude` entry is a `StepError` with `cause === "anthropic_rate_limited"`. A second case covers `ByokLeaseError("subscription_limit")` → `byok_lease_unavailable`, with the memoized `cause === "subscription_limit"`.
- T3: Given 500 / 408 / 409 on every attempt, then `anthropic_timeout` for each, and `create` was called 4 times. The AC10 case throws a REAL-class `new APIConnectionTimeoutError()` (from `vi.importActual`), whose `name` is `"Error"`, and still gets `anthropic_timeout`.
- T4: Given `create` rejects with a plain `TypeError`, then `leader_internal_error`, and the dead-letter is `error`-level.
- T5: Given `persistTurnCostAwaitable` rejects on every attempt (post-billing), then `leader_internal_error`.
- T6: Given `getRestApiKey` rejects with `ByokLeaseError(fetch_failed)` under `makeRetryingStep`, then `byok_lease_unavailable`. The tag did not overwrite the lease cause.
- T7: `agentOnSpawnRequestedOnFailure`, given an `inngest/function.failed` envelope whose ctx `runId` DIFFERS from `data.run_id`, sends exactly one `agent.spawn.orphaned` event carrying `data.event`, `run_id === data.run_id` and `lifecycle: "failed"`. It makes no DB call and no report.
- T8: **Precedence matrix.** One `it.each` over lifecycle {`failed` (forwarded), `cancelled` (`elapsedMs = FINISH_TIMEOUT_MS - 1`), `timed_out` (`elapsedMs = FINISH_TIMEOUT_MS`)} × Stop {unset, set}, against the in-memory fake with a non-terminal row. Each row asserts the reason written, the report level and the message suffix:

  | lifecycle | Stop unset | Stop set |
  |---|---|---|
  | failed | `leader_internal_error`, error, `(failed)` | `leader_internal_error`, error, `(failed)` |
  | cancelled | `leader_internal_error`, error, `(cancelled)` | `cancelled_by_operator`, warning, `(cancelled)` |
  | timed_out | `leader_internal_error`, error, `(timed_out)` | `leader_internal_error`, error, `(timed_out)` |

  The two boundary fixtures catch a `>` vs `>=` mutation. For every cancel row, the recorded step ops show `settle-grace` before `settle-orphaned-spawn`; the `failed` rows record no sleep.
- T9: Given a cancel envelope with no `ts` on either event, then `elapsedMs` is `null` and the suffix is `(cancelled)`. Given the Stop read returns `{ data: null, error }`, then `leader_internal_error` is written (paged), which is the stated fail-safe.
- T10: **Terminal rows are never re-settled.** A fixture row for each of `acknowledged_at` set, `failure_reason` set (including `cancelled_by_operator` already written) and `undone_at` + `acknowledged_at` set (the only shape Undo produces). For each, the UPDATE is issued, the fake returns zero rows, the row is unchanged, and zero captures are sent.
- T11: Given zero rows on the FIRST attempt (`attempt = 0`) while the re-read would show `failure_reason === leader_internal_error` (a concurrent `persistFailure` wrote it), then zero captures, and no re-read happens. This makes removing the `attempt > 0` gate red.
- T12: Given the settle step's DB call rejects on every attempt, under `runLikeInngest` with `maxAttempts: 4`, then the handler resolves (never throws) and exactly ONE error-level dead-letter with suffix `(settle_failed)` is sent across all invocations.
- T12b: Given `attempt > 0`, zero rows, and a re-read showing `failure_reason === reason`, then exactly one capture. Given the same with a re-read showing a DIFFERENT reason, then zero captures.
- T13: Given the fixture row's `user_id` differs from the envelope's `founderId` (a forged or mismatched envelope), then the row is unchanged and zero captures are sent.
- T14: **Envelope validation.** Given `data.event.name !== "agent.spawn.requested"`, or a missing or non-UUID `actionSendId` / `founderId` / `messageId`, then no DB call, and exactly one `(settle_failed)` dead-letter whose `extra.err.message` is the FIXED validation message and contains none of the supplied values. Given an unknown `actionClass`, the message carries `[unknown]`.
- T22: **The card leaves "Working".** Feed each settled fixture row (`leader_internal_error` on a row with `current_turn: 3`, and `cancelled_by_operator`) into `deriveTodayCardState`. Expect the failure state with the `leader_internal_error` copy, no Stop, no Retry, and the `Stopped` copy for the Stop row. The assertion is on the card, not the mock.
- T23: **No ctx logger.** A source-level check that `agentOnSpawnRequestedOnFailure`, `agentOnSpawnSettleHandler` and `settleOrphanedSpawn` never reference `logger`.
- T24: `spawnDeadLetterMessage` yields a distinct string per lifecycle (`failed`, `cancelled`, `timed_out`, `settle_failed`), and the byte-identical legacy string when no lifecycle is passed.

### Registration and contract

- T15: `agentOnSpawnRequested`'s options `onFailure` is `agentOnSpawnRequestedOnFailure`, and its `getConfig` yields the ids `agent-on-spawn-requested` and `agent-on-spawn-requested-failure`. `timeouts.finish` is derived from `FINISH_TIMEOUT_MS`. (The source-text `onFailure:` regex is NOT a committed test. AC4 runs it once at work time, and the follow-through probe owns it after merge.)
- T16: `agentOnSpawnSettle` has exactly two triggers. The cancelled trigger's `if` equals `agentOnSpawnRequested.getConfig({ baseUrl, appPrefix: "soleur-runtime" })[1].triggers[0].expression`, the string the SDK itself generates, today `event.data.function_id == 'soleur-runtime-agent-on-spawn-requested'`. The other trigger is `agent.spawn.orphaned`. Options carry `idempotency: "event.data.run_id"` and `retries: 3`.
- T17: The route array contains `agentOnSpawnSettle`, and the registry count is 70.
- T18: The contract suite checks that the paged set equals `PINNED_PAGED_REASONS` (which includes `leader_internal_error`), that the TF `in` set equals it and is non-empty, and that every `PROMISED_NOTIFICATION` member pages. The test titles carry no counts.

### Regression

- T19: The #8783 regression: the old `it.each` expectation (`429 → anthropic_timeout`) is gone. T1/T2 replace it.
- T20: **No raw founder id through the real pipeline.** Run a lifecycle dead-letter end to end with a hostile `founderId` fixture: the real `sentryCorrelationMiddleware` scope, the real `sentry.server.config` `beforeSend` (`scrubSentryEvent`) and a capturing transport, fed the real failure-envelope shape (nested `event.data.founderId` and `data.error.message`/`stack`). The raw id must appear nowhere in the serialized sent event. If wiring the real middleware into a unit test proves impractical, the fallback is two tests. The first asserts that the helper's own `captureMessage` args and breadcrumbs carry no raw id. The second, in the scrubber's suite, asserts `scrubSentryEvent` hashes a nested `inngest.event_data.event.data.founderId`. Record which form shipped.
- T21 (no replay double-report): drive `agentOnSpawnSettleHandler` with a forwarded `failed` payload through `runLikeInngest` (`maxAttempts: 4`), which re-invokes the handler after every new step. Assert exactly ONE dead-letter capture across all invocations. This is the property #8841 shows `persistFailure` lacks. The cancel path's sleep is not modelled by `HarnessStep`, so its replay property is covered by the ordering assertion in T8 and stated here as a known harness gap.

### Integration verification (for `soleur:qa`)

- I-1 (timeout emits `function.cancelled` on our server version): start the pinned `inngest-cli` dev server (same version as `apps/web-platform/infra/inngest.tf`). Register a throwaway function with `timeouts: { finish: "5s" }` that `step.sleep`s 10s, plus a listener built exactly like `agentOnSpawnCancelled`'s trigger but filtered to the throwaway id. Send one event, then assert the listener ran and read `data.event.data` and `data.run_id`. Also send a cancel through the dev server's REST API for a second run, and assert the listener ran again. A throwaway script under the scratchpad; never committed. Also assert that both the cancelled envelope and the original event carry a numeric `ts`, which `elapsedMs` depends on. Give the throwaway function an `onFailure` too, and assert it does NOT fire on the timeout or on the cancel. If v1.19.4 sends `function.failed` on either, the `failed` path would settle with no grace period and with failed-plus-Stop precedence. That breaks the design, so treat it as a stop-and-re-plan gate. Also build the listener's filter from the throwaway function's `getConfig(...)[1].triggers[0].expression`, to prove the SDK's own `onFailure` filter format matches on the server. Finally, send a hand-built `inngest/function.cancelled` event with the event key and record whether the server accepts it. This is informational only: the founder-scoped UPDATE (T13) is the control either way.
- I-2: the discoverability command, `grep -hoE 'leader_internal_error|agentOnSpawnSettle' apps/web-platform/infra/sentry/alert-reference.json apps/web-platform/app/api/inngest/route.ts`, prints both `leader_internal_error` and `agentOnSpawnSettle`.

### Postmerge (for `soleur:postmerge`)

- P-1: `bash scripts/followthroughs/spawn-onfailure-deadletter-8794.sh` and `bash scripts/followthroughs/leader-429-label-8758.sh` both print `PASS:` against `main` (`GH_TOKEN` from the environment).
- P-4: registration reached the prd Inngest server. `gh workflow run cutover-inngest.yml -f op=registry-probe` is the read-only `/hooks/inngest-registry-probe` GET, through the deploy webhook with HMAC + CF Access and no SSH. Its JSON `function_ids` must contain both `soleur-runtime-agent-on-spawn-requested-failure` and `soleur-runtime-agent-on-spawn-settle`. This checks presence by id, so a concurrent merge cannot flip it. If the probe is unavailable, P-4 falls back to the next orphaned run's dead-letter arriving with a lifecycle suffix.
- P-3: `apply-sentry-infra.yml` ran green on the merge commit, and the rule's `reason` filter shows seven values, read back through the same projection the drift probe uses.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled here with `aggregate pattern`.
- `onFailure` must be written as `onFailure: agentOnSpawnRequestedOnFailure,` on its own line. No per-key cast is needed, because the options object is already cast. The shorthand `onFailure,` is a valid key but leaves the #8803 follow-through probe on FAIL forever.
- The failure and cancel envelopes are NOT the original event. Read `event.data.event` and `event.data.run_id`. The ctx `runId` is the handler's own run.
- The SDK's `CancelledEventPayload` type omits `data.event` and `data.error`. Do not "fix" a type error by dropping the read. Narrow locally.
- `makeRetryingStep` copies `cause` by hand, so it cannot prove the tag survives. Only the `runLikeInngest` case (T2) does. Do not delete T2 as redundant.
- Regenerating `alert-reference.json` needs Sentry read credentials. If the session has none, take the expected file from the gate's `sentry-alert-reference-expected-<run-id>` artifact. Never hand-edit it twice.
- `leader-429-label-8758.sh` must be rewritten in THIS PR. Otherwise the sweeper's `closed_precheck` reopens #8783 the day after merge.

## Plan Review Log (2026-09-25)

The panel was DHH, Kieran and code-simplicity (eng), plus the CTO (devex) and the CMO (copy) as a named panel, and a scoped advisor consult. Mechanical findings were applied. Taste and User-Challenge findings are persisted in `knowledge-base/project/specs/feat-one-shot-8803-spawn-onfailure-deadletter/decision-challenges.md`.

Applied:

- **Kieran P0.** Connection errors are classified by `instanceof APIConnectionError`, not `name`, because SDK 0.93.0 sets `name === "Error"` (verified at runtime). The suite mock now exports the real classes.
- **Kieran P1.**
  - A committed-but-retried settle write still pages (re-read on zero rows when `attempt > 0`).
  - The T2 case asserts the memoized `StepError` and its string `cause`.
  - I-1 also proves `onFailure` stays silent on a timeout or cancel.
- **Kieran P2.**
  - Registration tests use the real client and pin the SDK-generated failure-trigger expression.
  - The listener has its own step type with `sleep`.
  - `ts` is optional.
  - The #8783 probe also rejects a surviving `return "anthropic_timeout";`.
- **DHH and simplicity.**
  - The read decides only the Stop check. The UPDATE's returned rows decide reporting, which removes the `row_missing` arm.
  - The envelope-missing case throws inside the step, so the one catch pages once, and `reportSpawnPersistFailed` is not doubled.
  - The tag vocabulary is the `FailureReason` value itself, and the classifier is cause-only (the dead `name` arms are removed).
  - The literal `if` filter replaces the derived constant, and `onFailure` is written plainly inside the already-cast options.
  - The source-text regex test is dropped (AC4 runs the grep once).
  - The ADR amendment is one paragraph.
- **CTO devex.**
  - `lifecycle` (`failed` / `cancelled` / `timed_out`, the last inferred from `elapsedMs >= FINISH_TIMEOUT_MS`) goes into the Sentry message, so each cause is its own issue and email under the 1442-minute throttle.
  - A triage runbook is added.
  - The contract-test titles carry no counts.
- **Standing check.** The before/after `function_count` delta AC was dropped: a concurrent merge flips it (`cq-ac-must-not-depend-on-concurrent-sessions`). It is replaced by a unit test over the registration config.

Not applied (reasons in `decision-challenges.md`):

- replacing `onFailure` with a two-trigger listener (User-Challenge against your stated direction). Deepen-plan later adopted its benefit without dropping `onFailure`: `onFailure` forwards to one settle function;
- the copy rewrite (Taste);
- gating the late writers (loses Undo handles);
- trimming the Guard matrices (required by the guard-contract lint).
