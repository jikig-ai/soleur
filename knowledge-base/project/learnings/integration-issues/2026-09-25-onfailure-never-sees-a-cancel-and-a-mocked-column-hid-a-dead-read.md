---
title: "onFailure never sees a cancel or a timeout, and a mocked column hid a read that failed every spawn"
date: 2026-09-25
category: integration-issues
module: apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts
tags: [inngest, lifecycle, onFailure, function-cancelled, supabase, mocks, schema-contract, step-boundary]
issues: [8803, 8783, 8839]
pr: 8837
---

# Learning: onFailure never sees a cancel or a timeout, and a mocked column hid a read that failed every spawn

## Problem

Leader-loop runs (`agent-on-spawn-requested`) that the handler never finished left the founder's Today
card on "Working" with no page (#8803). A retry-exhausted Anthropic 429 was labelled `anthropic_timeout`
because `status` is stripped at the Inngest step boundary (#8783).

## Solution

- **Two lifecycle signals, one settle function.** Measured on a local `inngest-cli 1.19.4` with SDK
  3.54.2: `onFailure` fires only for a failure past retries. The `timeouts.finish` cutoff and a
  `DELETE /v1/runs/<id>` cancel emit only `inngest/function.cancelled`, with `data.event`,
  `data.run_id`, `data.function_id` and no `data.error`. The server rejects a hand-sent
  `inngest/function.cancelled` with 400. So `onFailure` forwards `agent.spawn.orphaned`, and a new
  `agent-on-spawn-settle` function (retries 3, idempotency on `event.data.run_id`) handles both events.
  It does not settle inside `onFailure`, because the SDK pins the `-failure` function to one retry
  with no idempotency. ADR-251 records the fleet rule.
- **A tag that survives the step boundary.** Inside the step, a retryable live error is rethrown as a
  fresh Error with a string own-property `cause` (`anthropic_rate_limited` / `anthropic_timeout`). The
  handler's classifier is cause-only, and anything it does not recognise becomes `leader_internal_error`
  (paged). Connection errors are matched with `instanceof APIConnectionError`, because the SDK sets
  `name === "Error"` on them.
- **Review found a P1 older than the PR.** `action_sends.created_at` never existed; the table has
  `clicked_at` (migration 051). Every spawn had failed at `read-action-send-created-at` since
  2026-09-03, and the dashboard cost route returned 0 cents. Every suite mocks Supabase, and a mock
  answers for any column. The data-integrity seat found it with a live zero-row PostgREST probe
  (`select=created_at&limit=0` returns 42703). The fix reads `clicked_at`, and a new
  `test/action-sends-column-contract.test.ts` parses the migrations and fails on any column named on
  `action_sends` that no migration declares. Without that fix, this PR would have paged on every spawn.

## Key Insight

A mocked data layer certifies whatever column names the code happens to use, so no suite that mocks
the client can catch a nonexistent column. The only instrument that can is one reading the schema:
the DDL or a live zero-row query. In the same PR, the new test fake returned UPDATE rows without
`.select()`. A fake that is more forgiving than the real client turns a missing `.select("id")` into
"no page ever" behind a green suite. Make fakes reject what the vendor rejects (no rows without
`.select()`, 22P02 for a non-UUID uuid operand, PGRST116 for a multi-row `maybeSingle`).

## Session Errors

1. **The `gh issue create` guard blocked two planning filings** (forwarded from session-state). **Prevention:** write the body file first, then include `User-Impact:` and `Mandated-By:`. This is already documented in the hook.
2. **`cat $S` with `$S` unset read stdin and hung a background command.** Recovery: TaskStop. **Prevention:** in one-shot Bash blocks, quote and `:?`-guard any variable that names a file operand.
3. **A multi-line import in `route.ts` counted as served functions (72 vs 70).** The extractor matched `  name,` file-wide, and the header comment contains `functions: []`. Recovery: scoped the extractor to the `serve({ … functions: [ … ] })` array and proved it both ways. **Prevention:** fixed in `function-registry-count.test.ts`.
4. **A generic `scoped()` Supabase helper hit TS2589.** Recovery: inlined the `.eq` chains. **Prevention:** don't write generics over the supabase-js builder types.
5. **`lint-followthrough-varq-ban.sh` was passed a file, but it takes a directory (exit 2).** **Prevention:** read the script's usage before invoking it.
6. **An assertion expected `.name === "StepError"`, but the SDK's StepError is named `"Error"`.** **Prevention:** assert `instanceof StepError`.
7. **I assumed `getConfig().retries` sits at the top level; it is under `steps.step.retries`.** **Prevention:** read `InngestFunction.getConfig` before asserting on its shape.
8. **`action_sends.created_at` never existed (P1, pre-existing); mocked suites hid it.** Recovery: `clicked_at`, plus a column contract test that reads the migrations. **Prevention:** that contract test. For any new `.from(<table>).select(...)`, check the column in the migrations.
9. **The new test fake returned UPDATE rows without `.select()`.** A mutation that dropped `.select("id")` left 213 tests green. Recovery: made the fake match the vendor. **Prevention:** give each fake a negative control proving it can reject.
10. **A reviewer's runbook remedy (read step breadcrumbs) was drafted without checking it.** Breadcrumbs cover a single HTTP invocation. Caught before commit. **Prevention:** a remedy proposed in review is a claim to measure. Grep the emitter's scope before writing it down.
11. **The runbook's Sentry command first used host `sentry.io`.** The org needs `jikigai-eu.sentry.io`. Caught before commit. **Prevention:** copy the host from `scripts/sentry-issue.sh`.
12. **The nav-states gate was blocked locally.** Playwright needs `chromium_headless_shell-1208`, and the install was stuck on a `__dirlock` another session held. Recovery: relied on the CI `e2e` check, which passed. **Prevention:** the existing QA INFRA-BLOCKED rule.
13. **The local affected gate was contended by two sibling full-gate runs.** The operator chose to rely on CI's required `test` context. **Prevention:** run `test-all.sh --capacity` before launching.
14. **A closing line promised a fix, and the unkept-promise Stop hook fired.** **Prevention:** when waiting on background agents, end with an explicit `<stop>BLOCKED: …</stop>`.

## Tags

category: integration-issues
module: agent-on-spawn-requested
