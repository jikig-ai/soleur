---
title: "fix: Stripe webhook swallows an Inngest send failure and returns 200 with the dedup row claimed"
date: 2026-10-20
slug: stripe-webhook-inngest-send-failure
branch: feat-one-shot-10542-stripe-webhook-inngest-send-failure
issue: 10542
closes: 10542
type: fix
priority: p1
domain: engineering
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-10-20. **Agents used:** CTO (two rulings), dhh-rails, kieran-rails, code-simplicity
(plan review), observability-coverage, security-sentinel; Context7 (Inngest), Stripe docs fetch.

### Key Improvements
1. Sentry capture switched to the `err = null` message path (#8629): an `Error`-path report would have
   been unfindable by the new tags. T1 pins it.
2. Test model made stateful (claimed-id set) so T3/T4 prove the dedup release really ran.
3. Idempotency and retry claims now carry sources (Inngest 24 h event-id dedup; Stripe 3-day live retry).
4. Honest observability: no alert rule exists for the new tags; filed #10660 instead of claiming paging.

### New Considerations Discovered
- Unconditional 500 vs a freshness bound: ruled unconditional (CTO, 2026-10-20); revisit if Stripe
  documents a disable threshold or Sentry shows failures lasting over 24 h.
- Concurrent-duplicate race and pre-existing PII log lines noted; #10662 tracks the latter.

## Overview

The Stripe webhook route acknowledges a Stripe event as handled even when forwarding the
`finance.payment_failed` event to Inngest fails, and its dedup row stays claimed, so Stripe's
redelivery is dropped and the CFO draft is lost for good. The log text says "Stripe redelivery will
retry", which is false. The fix makes a failed send (after `sendInngestWithRetry`'s three attempts)
release the claimed dedup row, return HTTP 500 so Stripe redelivers, and report the failure to
Sentry with accurate wording. It matches how the GitHub-push and Resend-inbound handlers already
behave. Part of epic #10205 item 4 (#10136). Deadline from the issue: before 2026-11-05, because it
blocks the Inngest host-replace go in #10136 plan act A1.

## Research Insights

**Premise Validation.** Checked: #10542 is OPEN with no closing PR; #10136 and #10205 are OPEN;
`apps/web-platform/app/api/webhooks/stripe/route.ts` exists on `origin/main` (700 lines) and the
`invoice.payment_failed` case still does `reportSilentFallback(...)` then `break`, so the premise
holds: this is a behavioral fix on an existing route, not a build. Stale-premise scan: no cited
blocker is closed. The ADR corpus holds no decision that rejects "release dedup row + 5xx" for
webhooks; the precedent is the three sibling handlers and the learning
`2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern.md` (step 4 mandates
`releaseDedupRow()` before every 5xx exit in the switch). The brief's claim that siblings return 500
was verified by reading both: `github/route.ts` (push branch and non-push branch) and
`resend-inbound/route.ts` each do `logger.error` + `Sentry.captureException` + release +
`NextResponse.json({ error: "Dispatch failed" }, { status: 500 })`.

**Property List.**

1. A failed Inngest send for `invoice.payment_failed` is observable in Sentry without SSH.
2. A failed send causes Stripe to redeliver the event (non-2xx response).
3. The redelivered event is not swallowed by the dedup gate (the claimed row is released first).
4. A redelivery after a failed send re-attempts the send, and a successful send is not duplicated
   (idempotent via event id `stripe-${event.id}` plus the dedup row on the success path).
5. The success path and every non-send branch (flag off, no founder, no grant) keep returning 200.
6. The log/Sentry text no longer claims a retry that cannot happen.

**Cut List.** None of the mechanisms named in the ask is cut: each buys a listed property and nothing
on `origin/main` already buys it. The route already owns `releaseDedupRow()` (grepped in
`route.ts`: inner function after the dedup insert), so release needs no new helper, and no shared
"dispatch or release" helper is introduced (the three call sites differ in dedup table, column and
Sentry tags; a helper would be a premature abstraction).

**Existing mechanisms reused.** `releaseDedupRow()` (route.ts inner fn; logs and Sentry-reports its
own DELETE failure), `reportSilentFallback` (`server/observability.ts`: pino `logger.error` plus
`Sentry.captureException`, with address-redaction and `userId` pseudonymization),
`sendInngestWithRetry` (`server/inngest/send-with-retry.ts`: 3 attempts, throws on exhaustion).

**Relevant learnings.** `knowledge-base/project/learnings/integration-issues/2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern.md`
(insert-first dedup with delete-on-error; tests must route `from()` mocks by table so the dedup
`insert`/`delete().eq()` chain is isolated). In the current test file `mockDeleteEq` is a bare
`vi.fn()`, so `const { error } = await ...delete().eq()` would destructure `undefined`; the test
setup must resolve it.

**Not in scope (tracked).** The founder-lookup DB error in the same case is also swallowed and
returns 200 (same loss class). Ruled out of this PR by the CTO agent; tracked as #10657
(`deferred-scope-out`, same milestone as #10542). `isGranted` stays fail-closed by design (TR9). Also filed from the deepen pass: #10660 (Sentry alert
rule for the new tags) and #10662 (raw `founderId` in a pino `logger.info`, and unredacted retry
`logger.warn`).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` is re-run against the two planned file paths
at deepen-plan; the check is recorded here so the next planner sees it ran.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "release the claimed dedup row and return a non-2xx (500, matching the GitHub-push and Resend-inbound webhook handlers in this repo) so Stripe redelivers" [brief] | Phase 2 steps 2-3 (route.ts catch block) | mapped |
| 2 | "mirror the failure to Sentry per cq-silent-fallback-must-mirror-to-sentry" [brief] | Phase 2 step 2 (`reportSilentFallback`, tags `stripe-webhook` / `inngest-send-payment-failed`) | mapped |
| 3 | "fix the misleading log text" [brief] | Phase 2 steps 2 and 4 (message and stale comments) | mapped |
| 4 | "Write the failing test first (cq-write-failing-tests-before)" [brief] | Phase 1 (RED before Phase 2) | mapped |
| 5 | "send failure releases the dedup row and returns 500" [brief] | Phase 1 tests T1, T2 | mapped |
| 6 | "a redelivery after the failure re-attempts the send" [brief] | Phase 1 test T3 | mapped |
| 7 | "success path unchanged" [brief] | Phase 1 step 6 (existing success test strengthened) | mapped |
| 8 | "Add a replay-check note (Stripe dedup rows without a CFO draft) to the PR body" [brief] | PR Body Reminders section | mapped |
| 9 | "the PR body uses 'Ref #10542' and 'Ref #10136', and closes #10542 only via 'Closes #10542' in the body (not the title)" [brief] | PR Body Reminders section | mapped |
| 10 | "STOP before merge: do NOT run gh pr merge and do NOT arm auto-merge" [brief] | Phase 4 (stop after CI green) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| route.ts catch block rewrite | "release the claimed dedup row and return a non-2xx" | asked |
| Sentry tags `stripe-webhook` / `inngest-send-payment-failed` | "mirror the failure to Sentry per cq-silent-fallback-must-mirror-to-sentry" | asked (tag shape ruled by CTO, see decision-challenges.md) |
| Rewrite two existing tests that assert 200 on failure | "send failure releases the dedup row and returns 500" | asked (the old assertions contradict the required behavior) |
| Stale-comment cleanup in the case body | "fix the misleading log text" | asked (the comments make the same false claim as the log text) |
| Follow-up issue #10657 for the founder-lookup error | — | inferred — justification: found while reading the same case body; CTO ruled it out of scope; filed so the same loss class is not invisible (wg-when-deferring-a-capability-create-a) |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 2 edited (1 source, 1 test) plus plan artifacts | Estimated changed lines: ~120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `apps/web-platform/app/api/webhooks/stripe/route.ts` — in `case "invoice.payment_failed"` catch block: report, release, return 500; fix comments.
- `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts` — add/rewrite failing tests; resolve `mockDeleteEq` in `beforeEach`; update the header contract comment (last bullet and the line-number references).

## Files to Create

None (plan artifacts under `knowledge-base/project/{plans,specs}/` only).

## Implementation Phases

### Phase 1 — RED: failing tests first (`cq-write-failing-tests-before`)

Edit `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts`:

1. In `beforeEach` model the dedup table instead of stubbing it: keep a `claimed = new Set<string>()`
   reset per test; `mockInsert` resolves `{ data: null, error: { code: "23505", message: "duplicate key" } }`
   when the inserted `event_id` is already in `claimed`, else adds it and resolves `{ data: null, error: null }`;
   `mockDeleteEq` (called with `("event_id", id)`) removes the id and resolves `{ error: null }`. A bare
   `mockDeleteEq` would make the route's `const { error } = await ...delete().eq()` destructure
   `undefined` and throw, and a stateless `mockInsert` could not tell whether the release ever ran
   (review finding: the old code would pass the second half of a stateless redelivery test). The
   existing "Stripe redelivery (same event.id twice)" test keeps working (its second delivery overrides
   `mockInsert` once with a 23505).
2. Rewrite `"Inngest unreachable → reportSilentFallback fires, webhook returns 200"` as **T1**:
   `mockInngestSend.mockRejectedValueOnce(new Error("ECONNREFUSED 127.0.0.1:8288"))` (a plain
   `Error` is not matched by `isTransientFetchError`, so one attempt and no timer) → expect
   `res.status === 500`, `await res.json()` equals `{ error: "Dispatch failed" }`, `mockDeleteEq`
   called once with `("event_id", "evt_pf_001")`, `mockReportSilentFallback` called once with first argument `null` (pins the #8629 message path) and context
   `feature: "stripe-webhook"`, `op: "inngest-send-payment-failed"`, a `message` that does NOT contain
   "will retry" and does name the dedup release, and `extra` with `userId === FOUNDER_ID` (pins the
   pseudonymized key at the call site), `eventId`, `invoiceId`, `errorName`, no `founderId` key, no raw
   error message and no `customerEmailHash`.
3. Rewrite `"Inngest transient failure → retries exhaust..."` as **T2**: three
   `TypeError("fetch failed")` rejections → 3 send attempts with REAL timers (the existing test already
   does this: 500 + 1000 ms backoff, about 1.5 s, well inside the repo's `testTimeout` of 16 s; fake
   timers would only add risk), then 500, `mockDeleteEq` called exactly once, report exactly once.
4. Add **T3** (redelivery after failure re-attempts the send): first `POST` with
   `mockInngestSend.mockRejectedValueOnce(non-transient error)` → 500 and the id removed from
   `claimed`; second `POST` of the SAME event with `mockInngestSend` resolving → `res2.status === 200`,
   `mockInngestSend` called 2 times in total. Because the insert mock is stateful, this passes only if
   the release really ran. This is the behavior the old code lost.
5. Add **T4** (the CTO-ruled "500 anyway" contract, and the inverse coupling): first `POST` with a
   failing send and `mockDeleteEq.mockResolvedValueOnce({ error: { message: "delete failed" } })`
   (the id stays in `claimed`) → 500, `mockLogger.error` called with `eventId` and a message
   containing "failed to release dedup row" (the pino line from `releaseDedupRow`; assert the text and
   `eventId` so an unrelated `logger.error` cannot satisfy it); a redelivery then short-circuits with
   200 and `mockInngestSend` is NOT called again. This documents the accepted residual loss (release
   failure) instead of leaving it implicit.
6. Success path unchanged: no new test. In the existing `"... fires inngest.send exactly once with v=1
   envelope"` test add `expect(mockDeleteEq).not.toHaveBeenCalled()` and
   `expect(mockReportSilentFallback).not.toHaveBeenCalled()`.
7. Update the file header contract comment: the last bullet becomes "Inngest unreachable → dedup row
   released, webhook returns 500 (Stripe redelivers)", and remove the stale "(lines 116-118)" line
   references.

Run, one suite at a time with stdin from `/dev/null`:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/server/webhooks/stripe-payment-failed-inngest.test.ts < /dev/null` (vitest is the runner per `package.json` `scripts.test`; the path satisfies the `test/**/*.test.ts` include glob).
Expected RED: T1, T2, T3, T4 fail (route returns 200 and never calls the release); the existing
success tests, including the strengthened one, pass. Keep the RED run output in the work log as evidence of test-first authoring.

### Phase 2 — GREEN: route change

Edit `apps/web-platform/app/api/webhooks/stripe/route.ts`, `case "invoice.payment_failed"`:

1. Keep the `try { ...sendInngestWithRetry(...) }` block as is.
2. Replace the catch body with, in order:
   - `reportSilentFallback(null, { feature: "stripe-webhook", op: "inngest-send-payment-failed",
     message: "Stripe webhook: inngest.send failed for invoice.payment_failed — releasing dedup row, returning 500 so Stripe redelivers",
     extra: { userId: founderId, invoiceId: invoice.id, eventId: event.id, errorName, errorCode } })`
     where `errorName = err instanceof Error ? err.name : typeof err` and `errorCode` is `err.code` when it
     is a string. **`err` is passed as `null` (the message path), not the caught `Error`:** a real
     `Error` is captured first by the pino mirror with only `feature=pino-mirror` and Sentry drops the
     tagged second capture (#8629; precedent `server/c4-writer.ts` and `server/account-delete.ts`, which
     both pass `null` for exactly this reason), so an `Error`-path report would be unfindable by
     `feature`/`op` tag. Keep the message text fixed and low-cardinality (Sentry groups a message
     capture by its text). Do not put the raw error message or `customerEmailHash` in `extra`.
     `reportSilentFallback` still does the pino `logger.error` plus the Sentry capture (verified in
     `server/observability.ts`), so there is no separate `logger.error` or `Sentry.captureException`.
     Use the `userId` key (not `founderId`) so the emit boundary pseudonymizes it (Recital 26); the
     current code passes a raw `founderId`, so this also closes a small PII gap.
   - Order matters: report FIRST, then release. If the release throws, the Sentry event for the send
     failure already exists and the route still answers 5xx (an unhandled throw is a 500 in Next).
   - `await releaseDedupRow();`
   - `return NextResponse.json({ error: "Dispatch failed" }, { status: 500 });`
3. Return 500 for every send failure, transient or not (CTO ruling: `isTransientFetchError` covers
   only network errors, so a 4xx would otherwise fall into a silent-loss bucket again; the retry is
   idempotent through the `stripe-${event.id}` Inngest event id: Inngest treats a repeated event `id`
   within 24 hours as a duplicate, stored but triggering no new run, source
   https://www.inngest.com/docs/durable-execution/guides-and-advanced/idempotency, read 2026-10-20).
   Put two short comment lines above the catch body stating (a) that idempotency basis and (b) that every
   send failure returns 500 and the `SOLEUR_FR5_ENABLED=false` kill switch is the escape for a
   deterministic failure. Nothing after the send can throw in this case, so a send that landed server-side
   but errored client-side is the only duplicate-send exposure, and the event id covers it.
4. Fix the stale comments in the same case: replace "Stripe redelivery upstream covers the gap if the
   operator forgets — at-least-once." and the "dedup INSERT at line 116 ... short-circuited at
   line 126" comment with accurate prose (the dedup claim happens before the switch; a failed send now
   releases it and returns 500). Cite content, not line numbers
   (`cq-cite-content-anchor-not-line-number`). Add a one-line comment above the ignored `founderRow`
   error pointing at #10657.
5. Re-run the Phase 1 suite: all green. Then run the sibling Stripe suites one at a time
   (`stripe-webhook-invoice.test.ts`, `stripe-webhook-plan-tier.test.ts`,
   `webhook-subscription.test.ts`) with stdin from `/dev/null`, then `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (never `npm run -w`; the repo root declares no workspaces).

No other branch of the switch changes. Nothing in `invoice.payment_failed` mutates state before the
send (log only), so releasing the row and letting Stripe redeliver cannot double-apply anything.

### Phase 3 — PR body and replay-check note

The PR body (set at ship) carries the reminders below. The replay check is a read-only query
description for an operator or agent to run after merge with the owner's go; this plan does not run
it (owner constraint 6: no production system is touched).

### Phase 4 — ship, stop before merge

Review and QA as normal, push, mark the PR ready, poll CI with Monitor until green, then report the
PR number and CI state and pause. Do NOT run `gh pr merge` and do NOT arm auto-merge (owner
constraint 2). The merge needs a separate go naming the merge.

## PR Body Reminders

- `Ref #10542`, `Ref #10136`, and the closing keyword `Closes #10542` in the BODY only, never the
  title (`wg-use-closes-n-in-pr-body-not-title-to`). Also `Ref #10657` for the follow-up.
- **Replay-check note (Stripe dedup rows without a CFO draft).** Before the Inngest host-replace
  window, run a read-only check for events lost by the old behavior: count `processed_stripe_events`
  rows with `event_type = 'invoice.payment_failed'` since `SOLEUR_FR5_ENABLED` was set to `true` in prd,
  per founder holding an active `finance.payment_failed` grant, and compare with that founder's CFO
  draft rows in `messages` (Stripe source, `owning_domain = 'cfo'`; CFO drafts carry no `source_ref`,
  so the match is by founder and time window). A founder with more dedup rows than drafts has
  candidate lost events. Re-sending one through Stripe requires deleting its dedup row first, which is
  a production write that needs its own go. Rows from before the flag flip or for founders without a
  grant legitimately have no draft.
- Also state in the PR body: (a) a concurrent duplicate delivery can get a 200 from the 23505 short-circuit
  while the first delivery then fails and releases, losing the draft (rare, accepted); (b) no Sentry alert
  rule exists for the new tags yet (#10660); (c) `Ref #10660`, `Ref #10662` for the follow-ups; (d) the
  Sentry capture carries only a pseudonymized user id plus opaque Stripe ids, so no new Art. 30
  processing activity (the capture sink already exists).
- Residual risk to state: Stripe retries a failed delivery for up to three days with exponential
  backoff in live mode, and only three times within a few hours for test-mode events (source:
  https://docs.stripe.com/webhooks, "Automatic retries", read 2026-10-20). If the Inngest server stays
  unavailable longer than that window, Stripe stops retrying and the draft is lost, now with a Sentry
  event as evidence instead of silence. `SOLEUR_FR5_ENABLED=false` is the kill switch that stops the
  500s during a long disruption. This route is the single endpoint for all Stripe subscription events,
  so sustained 500s on one event type are a risk to the endpoint as a whole; the fetched Stripe page
  states no endpoint-disable threshold, so treat that consequence as unverified and keep the kill
  switch as the stated mitigation.

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder whose card payment failed sees no CFO
  draft card in their Today queue (the failed-payment nudge never appears) and no signal that it was
  lost; or, if the fix over-reaches, Stripe sees 500s on `invoice.payment_failed` and retries.
  Two review-found vectors sit behind that: (1) sustained 500s while the Inngest server is
  unavailable could lead Stripe to disable this shared endpoint, which would stop
  `customer.subscription.*` and `checkout.session.completed` updates for every user (the disable
  threshold is unverified; mitigation is the kill switch, effective on restart, and the alert is
  unwired until #10660); (2) a send that landed but errored, redelivered after Inngest's 24 h
  event-id window, can add a second draft card, because the CFO function inserts drafts without a
  `source_ref` (its own comment defers that wiring to PR-G).
- **If this leaks, the user's money / workflow is exposed via:** no new exposure vector: the change
  adds no data to any payload; the Sentry `extra` carries only event/invoice ids and a pseudonymized
  user id, never the customer email hash.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the loss is a missed internal draft card, not a billing
  state change (`customer.subscription.updated` remains the source of truth for subscription status)
  and not a data exposure, so one occurrence is not a brand-ending incident; a recurring Inngest
  disruption would drop drafts for every founder, which is why it is not `none`.

## Observability

```yaml
liveness_signal:
  what: Sentry message events (err=null path, #8629) tagged feature=stripe-webhook op=inngest-send-payment-failed (failure signal; absence alongside healthy Stripe deliveries means sends succeed)
  cadence: per Stripe invoice.payment_failed delivery
  alert_target: none until #10660 lands (until then, Sentry search for feature:stripe-webhook op:inngest-send-payment-failed)
  configured_in: apps/web-platform/app/api/webhooks/stripe/route.ts (reportSilentFallback in the invoice.payment_failed catch block)

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN, plus pino logger.error to Better Stack (both emitted by reportSilentFallback)
  fail_loud: HTTP 500 {"error":"Dispatch failed"} to Stripe, visible in Stripe's webhook delivery log, plus the Sentry event

failure_modes:
  - mode: Inngest unreachable or send rejected after 3 attempts
    detection: layer 2 (reportSilentFallback message path: Sentry event op=inngest-send-payment-failed plus a pino error line in Better Stack); Stripe delivery log shows the 500 and the redelivery
    alert_route: none yet - Sentry search by tag only; the alert rule is tracked as #10660 (infra that auto-applies on merge, out of this PR's no-production-touch scope)
  - mode: dedup-row release DELETE fails after a send failure (redelivery will be short-circuited)
    detection: layer 2 (existing releaseDedupRow reporting: Sentry event op=dedup-release plus a pino error line in Better Stack) alongside the send-failure event; correlate by eventId in Better Stack (not searchable in Sentry extra)
    alert_route: none yet - Sentry search by tag only (#10660 covers the send-failure rule; the existing dedup-release capture is untouched)
  - mode: deterministic non-transient send error (for example a 4xx) returns 500 on every redelivery
    detection: layer 2 (repeated op=inngest-send-payment-failed events carrying the same eventId, queryable in Better Stack through the pino line) and the Stripe delivery log showing repeated 500s
    alert_route: none yet (#10660); mitigation is the SOLEUR_FR5_ENABLED=false flip in Doppler prd, effective on the next container restart (a production write that needs the owner's separate go; not performed by this PR)

logs:
  where: pino stdout aggregated to Better Stack, and Sentry
  retention: Better Stack and Sentry plan retention (not changed by this plan)

discoverability_test:
  command: rg -n "inngest-send-payment-failed" apps/web-platform/app/api/webhooks/stripe/route.ts
  expected_output: inngest-send-payment-failed
```

## Architecture Decision (ADR/C4)

No architectural decision: this is a bug fix on an existing route that brings it in line with its
two sibling handlers. Checked against the C4 model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`, read at deepen-plan):
the external actors and systems involved (Stripe webhook edge, Inngest, Supabase
`processed_stripe_events`, Sentry) and their relationships are unchanged; no element, edge or
cardinality moves, so no `.c4` edit and no ADR. The `c4-count-parity` gate is unaffected (no
workflow or monitor counts change).

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-20 on four technical forks (Sentry shape, release-failure
handling, scope of the founder-lookup swallow, transient-only 500). Recorded as rows in
`knowledge-base/project/specs/feat-one-shot-10542-stripe-webhook-inngest-send-failure/decision-challenges.md`.

Product/UX Gate: none (no user-facing page, component or copy). Finance (CFO) not spawned: the CFO
draft content and the Inngest function are untouched; only whether the event reaches Inngest changes.
GDPR gate: `app/api/**` matches the canonical regex, but the change adds no field, no processing
activity and no data movement (it removes a silent drop and keeps `customerEmailHash` out of the
error context); advisory re-check by `soleur:gdpr-gate` at work Phase 2 exit.

## Plan Review (applied 2026-10-20)

DHH, Kieran and code-simplicity reviewed. Applied as mechanical: stateful dedup-table mock so T3/T4
prove the release ran (Kieran P1), real timers for T2, success-path test folded into the existing
test instead of a new T5 (DHH, simplicity), call-site pin of `extra.userId`, the Inngest 24 h event-id
idempotency citation, a shorter replay note, an endpoint-risk sentence in the PR body reminders.
Not applied, with reason: dropping the Sentry tag rename (CTO ruling, recorded in
`decision-challenges.md`); dropping the three sibling Stripe suites (the route file changes, the runs
are cheap); dropping the `#10657` pointer comment (CTO asked for it). T4 kept but reshaped as the
documented residual-loss case.

## Acceptance Criteria

### Functional

- [x] With `SOLEUR_FR5_ENABLED=true`, a founder with an active grant and a send that fails after the
  retries: the route returns 500 with `{"error":"Dispatch failed"}` and the `processed_stripe_events`
  row for `event.id` is deleted (T1, T2).
- [x] A second delivery of the same `event.id` after that failure re-enters the handler, claims the
  row again, and calls `inngest.send` again (T3).
- [x] The failure is reported once through `reportSilentFallback` with `feature: "stripe-webhook"`,
  `op: "inngest-send-payment-failed"`, a message that does not contain "will retry", and no
  `customerEmailHash` in `extra` (T1).
- [x] Success path unchanged: 200, no release, no failure report (strengthened existing test); flag off,
  no founder, and no-grant branches still return 200 without sending (existing tests).
- [x] A failed release after a failed send still returns 500, logs the release failure with the event id, and the redelivery is short-circuited without a send (T4).

### Quality gates

- [x] The RED run (Phase 1) failed on T1-T4 before the route change; the GREEN run passes.
- [x] `stripe-webhook-invoice`, `stripe-webhook-plan-tier` and `webhook-subscription` suites pass.
- [x] `./node_modules/.bin/tsc --noEmit` clean in `apps/web-platform`.
- [x] `rg -n "will retry|upstream covers the gap" apps/web-platform/app/api/webhooks/stripe/route.ts`
  returns no match after the change.
- [ ] PR body contains `Ref #10542`, `Ref #10136`, `Closes #10542`, and the replay-check note; the
  title contains no closing keyword.
- [ ] CI green, PR marked ready, and NO merge or auto-merge armed (owner constraint 2).

## Test Scenarios

| # | Scenario | Setup | Expected |
|---|----------|-------|----------|
| T1 | Non-transient send failure | send rejects `Error("ECONNREFUSED ...")` | 500, release called with `("event_id","evt_pf_001")`, one report with the new tags |
| T2 | Transient failure exhausts 3 attempts | send rejects `TypeError("fetch failed")` x3 | 3 attempts, 500, one release, one report |
| T3 | Redelivery after failure | fail once then resolve; same event twice | 500 then 200; `inngest.send` called twice; insert called twice |
| T4 | Release itself fails | send rejects; `mockDeleteEq` resolves `{error}` | still 500; release failure logged with eventId; redelivery short-circuits (200, no send) |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6; this plan fills it (aggregate pattern).
- `mockDeleteEq` is a bare `vi.fn()`; if the test setup does not resolve it, the route's
  `const { error } = await ...delete().eq()` throws a TypeError inside the catch and the test fails
  for the wrong reason. Set it in `beforeEach` (Phase 1 step 1).
- The idempotency of a retried send is the `stripe-${event.id}` event id passed to `inngest.send`;
  T3 plus the existing envelope assertion (`envelope.id === "stripe-evt_pf_001"`) pin it. Do not try
  to simulate Inngest's server-side dedup in the unit test.
- When `err` is an `Error`, Sentry groups by the error, and `reportSilentFallback`'s `message` is
  only the pino text; the new `op` tag, not the message, is what operators filter on.
- Owner constraints that bind later phases: run suites one at a time with stdin from `/dev/null`;
  use the words "unavailable" or "disruption" for the vendor-down case; poll CI with Monitor; touch
  no production system.
- Renaming the Sentry `feature`/`op` tags could dark a monitor that filters on them. Measured at
  plan time: `git grep -n "inngest-emit\|stripe-webhook" -- apps/web-platform/infra` returns no match
  (the Sentry alert definitions under `apps/web-platform/infra/sentry/` never name either tag), and
  `inngest-emit` appears only in `route.ts` and the one test assertion being rewritten. Better Stack
  saved searches and runbooks are not visible from the repo: at ship, check the runbooks tree with
  `git grep -n "inngest-emit" -- knowledge-base` and note any Better Stack saved search in the PR body.
