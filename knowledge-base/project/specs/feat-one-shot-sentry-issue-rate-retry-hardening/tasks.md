# Tasks — sentry-issue-rate transient-retry hardening

Plan: `knowledge-base/project/plans/2026-06-29-fix-sentry-issue-rate-transient-retry-hardening-plan.md`
Lane: cross-domain (spec lacks `lane:` — TR2 fail-closed default)

## Phase 1 — Bounded transient-retry in `sentryGet`

- [ ] 1.1 Import `{ isRetryable, delay }` from `@/server/github-retry` into
  `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`.
- [ ] 1.2 Add module constants: `SENTRY_FETCH_MAX_RETRIES = 2`,
  `SENTRY_FETCH_BACKOFF_MS = [500, 1500] as const`.
- [ ] 1.3 Rewrite the `sentryGet` closure as a retry loop: per-attempt
  `AbortSignal.timeout(SENTRY_FETCH_TIMEOUT_MS)`; inline 5xx/429 drain+backoff+retry
  (`delay(SENTRY_FETCH_BACKOFF_MS[attempt])`) while attempts remain; `!res.ok`
  throws a token-free `Sentry GET returned HTTP <status>` error (NO flag); catch
  retries on `isRetryable(err)`; rethrow on exhaustion.
- [ ] 1.4 Confirm both call sites (search `:144`, detail `:163`) inherit the retry
  (single closure — no per-call-site change).

## Phase 2 — Observability (no verdict change)

- [ ] 2.1 Import `warnSilentFallback` from `@/server/observability`.
- [ ] 2.2 Emit `warnSilentFallback` INSIDE the `failClosed` helper (one site;
  covers transient-exhausted + deterministic-4xx + env-unset + shape/param) with
  `op: "sentry-issue-rate-fail-closed"`, `message: "sentry-issue-rate fail-closed"`,
  `extra: { fn, check, reason }`, wrapping `new Error("sentry-issue-rate fail-closed: " + reason)`.
  Return shape unchanged (`info`, `close: false`). Token-free (`reason` is static
  or the catch's already-sliced token-free string). Outer catch no longer needs a flag.

## Phase 3 — Tests

- [ ] 3.1 Partial-mock `@/server/github-retry` so `delay` is an instant no-op and
  `isRetryable` stays real (`vi.mock(..., async (orig) => ({ ...(await orig()), delay: vi.fn(() => Promise.resolve()) }))`).
- [ ] 3.2 Add a NEW `stubFetchSequence` helper (existing `stubFetch` cannot
  sequence same-URL responses — use `mockImplementationOnce` chains) in
  `apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts`.
- [ ] 3.3 Add cases: (1) 5xx-then-success → real verdict; (2) `TimeoutError`/
  `fetch failed`-then-success → real verdict (NOT `AbortError`); (3) 4xx → exactly
  1 fetch, fail-closed, warn op=sentry-issue-rate-fail-closed (reason has HTTP 403);
  (4) bounded to 3 attempts on persistent 5xx + warn op=sentry-issue-rate-fail-closed;
  (5) detail-call 500-then-success → real verdict; (6) env-unset → warn
  op=sentry-issue-rate-fail-closed, reason="Sentry env not configured", no fetch;
  (7) token never leaks across retry/warn.
- [ ] 3.4 Confirm existing fail-closed cases stay green (warn is additive).
- [ ] 3.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] 3.6 Verify Inngest step-timeout headroom > ~55 s worst-case (AC7).
- [ ] 3.7 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts test/lib/sentry-issue-rate.test.ts` passes (incl. unchanged existing cases).

## Ship

- [ ] PR body: `Ref #5417`, `Ref #5669` (no `Closes`); operator note that
  fail-closed verifications should be scheduled recurring (durable fix = #5669).
