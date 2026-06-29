# Tasks — sentry-issue-rate transient-retry hardening

Plan: `knowledge-base/project/plans/2026-06-29-fix-sentry-issue-rate-transient-retry-hardening-plan.md`
Lane: cross-domain (spec lacks `lane:` — TR2 fail-closed default)

## Phase 1 — Bounded transient-retry in `sentryGet`

- [ ] 1.1 Import `{ isRetryable, delay }` from `@/server/github-retry` into
  `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`.
- [ ] 1.2 Add module constants: `SENTRY_FETCH_MAX_RETRIES = 2`,
  `SENTRY_FETCH_BACKOFF_BASE_MS = 500` (backoff = `BASE * 3 ** attempt` → 500, 1500).
- [ ] 1.3 Rewrite the `sentryGet` closure as a retry loop: per-attempt
  `AbortSignal.timeout(SENTRY_FETCH_TIMEOUT_MS)`; inline 5xx/429 drain+backoff+retry
  while attempts remain; `!res.ok` throws a token-free `HTTP <status>` error tagged
  `{ sentryTransient }`; catch retries on `isRetryable(err)`; rethrow on exhaustion.
- [ ] 1.4 Confirm both call sites (search `:144`, detail `:163`) inherit the retry
  (single closure — no per-call-site change).

## Phase 2 — Observability (no verdict change)

- [ ] 2.1 Import `warnSilentFallback` from `@/server/observability`.
- [ ] 2.2 In the outer `catch`, classify transient (`isRetryable(err) ||
  err.sentryTransient === true`) and, if transient, `warnSilentFallback` with
  `op: "sentry-issue-rate-retry-exhausted"` (token-free payload) BEFORE returning
  the existing `failClosed(...)` (`info`, `close: false`).

## Phase 3 — Tests

- [ ] 3.1 Partial-mock `@/server/github-retry` so `delay` is an instant no-op and
  `isRetryable` stays real.
- [ ] 3.2 Extend `stubFetch` (or add `stubFetchSequence`) for per-attempt
  pass/fail sequencing in
  `apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts`.
- [ ] 3.3 Add cases: 5xx-then-success → real verdict; network/`TimeoutError`-then-
  success → real verdict; 4xx → exactly 1 fetch, fail-closed (no retry); bounded
  to 3 attempts on persistent 5xx + `warnSilentFallback(op=retry-exhausted)`;
  detail-call 500-then-success → real verdict; token never leaks across retry/warn.
- [ ] 3.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] 3.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts test/lib/sentry-issue-rate.test.ts` passes (incl. unchanged existing cases).

## Ship

- [ ] PR body: `Ref #5417`, `Ref #5669` (no `Closes`); operator note that
  fail-closed verifications should be scheduled recurring (durable fix = #5669).
