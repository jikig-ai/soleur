---
date: 2026-06-29
type: fix
title: Harden sentry-issue-rate named-check with bounded transient-retry
branch: feat-one-shot-sentry-issue-rate-retry-hardening
lane: cross-domain
brand_survival_threshold: none
related_issues: [5417, 5669]
status: planned
---

# fix: Bounded transient-retry for the `sentry-issue-rate` named-check

🐛 / ♻️ Reliability hardening of a post-deploy verification primitive.

> Spec lacks a `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed). The change is functionally engineering/infra-tooling only.

## Enhancement Summary

**Deepened on:** 2026-06-29
**Review agents:** code-simplicity-reviewer, observability-coverage-reviewer,
architecture-strategist, Explore (claims verification). All 4 gates passed
(User-Brand Impact, Observability, PAT-shaped, UI-wireframe).

### Key improvements folded in
1. **Observability broadened (P1):** the warn moved from transient-only into the
   `failClosed` helper, so EVERY fail-closed (transient-exhausted **and**
   deterministic 401/403 token-rot, env-unset, shape/param) mirrors to Sentry at
   warning level (`op=sentry-issue-rate-fail-closed`). The observability review
   showed token-rot is the same silent class a retry can never heal — and a
   GitHub comment is not an observability layer.
2. **Simplified:** centralizing the warn dropped the `sentryTransient` flag and
   the catch-side classification (code-simplicity P3-c); backoff is now an
   explicit `[500, 1500]` array (removes the 3** vs 2** exponent ambiguity).
3. **Latency corrected (architecture P2):** worst case is ~55 s, not ~32 s (two
   sequential `sentryGet` loops). Added AC7 to verify Inngest step-timeout
   headroom + a concurrency-slot-hold note.
4. **New alternative recorded:** per-fetch `step.run` decomposition (durable
   across worker restarts) considered and deferred to #5669; in-step retry is a
   within-invocation defense only.

### Verified claims (Explore agent, file:line)
- `isRetryable` matches `TimeoutError`, MISSES `AbortError` → the
  `AbortSignal.timeout` switch is necessary (`github-retry.ts:18`).
- Token never reaches `buildSentryUrl` (no token param; `sentry-issue-rate.ts:85`).
- A NEW `stubFetchSequence` test helper is required (existing `stubFetch` can't
  sequence same-URL responses; `event-scheduled-reminder.test.ts:221-240`).

## Overview

The `sentry-issue-rate` named-check in
`apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`
(`CHECK_REGISTRY["sentry-issue-rate"]`) makes two Sentry REST reads — an org
issues search and an issue-detail GET — through a single `sentryGet` closure.
That closure wraps each `fetch` in an `AbortController` bounded by
`SENTRY_FETCH_TIMEOUT_MS = 10_000` with **no retry**. On 2026-06-19 a transient
Sentry latency spike blew the 10 s bound; the check fail-closed
("This operation was aborted") and — because it was armed as a **one-time**
reminder with no retry — the AC12 verification for #5417 died silently for 10
days. Both fetches measure ~2 s under normal conditions, so a single transient
spike should be recoverable.

This plan wraps the Sentry fetch in a **bounded transient-retry** (2 retries,
exponential backoff ~500 ms then ~1500 ms) that recovers from transient failures
only — `AbortSignal.timeout` timeouts, undici network errors, and HTTP 5xx/429 —
while leaving deterministic failures (HTTP 4xx other than 429, wrong-issue-count,
malformed stats shape) single-shot fail-closed exactly as today. The existing
per-attempt timeout, the token-free-by-construction error invariant, and the
fail-closed verdict semantics are all preserved. The only behavioral change is
that a single transient spike now recovers instead of permanently fail-closing.

**Why the retry belongs at the fetch layer (not the Inngest function layer):**
the Inngest function already declares `retries: 1`, but the handler **catches**
the fetch failure and returns a `failClosed` `info` verdict (i.e. it *succeeds*
from Inngest's perspective). Inngest therefore never re-runs it (and step-level
retry is equally inert — it fires only on a step *throw*). The in-function
fetch-level retry is the correct and only layer that can recover this class of
failure. It is a **within-invocation** defense: it does NOT survive a mid-step
worker restart (the #5417 container-restart class), which replays the whole
`run-check` step from scratch; the durable decoupling that addresses restarts is
tracked in #5669 and is complementary, not substituted, by this change.

**Worst-case added latency (corrected by deepen-plan architecture review):** there
are TWO sequential `sentryGet` calls (search, then detail), **each with its own
3-attempt retry loop**. The realistic worst case is ~22 s on the search call
(succeeds on its 3rd attempt) followed by ~32 s on the detail call (exhausts all
3) ≈ **~55 s of single-step wall-time**, not the naive ~32 s. Two consequences,
both addressed in Acceptance Criteria / Risks: (a) the self-hosted Inngest
step/executor request timeout must exceed ~55 s (AC7), else a transient spike
newly trips an Inngest-level timeout; (b) a ~55 s run holds the sole
`cron-platform` account concurrency slot (`concurrency: [{account, key:
"cron-platform", limit:1}]`), head-of-line-blocking other reminders for the
duration — low impact (reminders are infrequent) but stated for honesty.

### Reuse, don't reinvent (canonical precedent)

`apps/web-platform/server/github-api.ts` `fetchWithRetry` is the house-style
raw-`fetch`-with-retry: per-attempt `AbortSignal.timeout(TIMEOUT_MS)`, inline
`status >= 500 && attempt < MAX_RETRIES` retry (drains the body before retrying),
and `isRetryable(err)` in the catch for network/timeout errors. The transient
classifier and `delay()` live in the **dependency-free leaf**
`apps/web-platform/server/github-retry.ts` (`isRetryable`, `delay`,
`MAX_RETRIES`, `BASE_DELAY_MS`). Its header explicitly sanctions sibling retry
sites keeping their own local backoff budgets, so the check may import
`isRetryable` + `delay` and apply the scope-specified `[500, 1500]` schedule
without forking the classifier. `server/inngest/send-with-retry.ts`
(`isTransientFetchError`, same undici code set, 500 ms base) is a third sibling
precedent.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task / background) | Codebase reality (verified) | Plan response |
|---|---|---|
| `sentryGet` wraps each fetch in an AbortController, `SENTRY_FETCH_TIMEOUT_MS=10_000`, no retry | Confirmed — `event-scheduled-reminder.ts:121-136`; `const SENTRY_FETCH_TIMEOUT_MS = 10_000` at `:52` | Wrap in bounded retry; keep the per-attempt 10 s timeout |
| Two Sentry fetches (search + detail) both go through `sentryGet` | Confirmed — `:144` (search), `:163` (detail); single closure | Retry wraps `sentryGet` once → both calls covered, no per-call-site change |
| Deterministic failures must stay single-shot fail-closed | wrong-issue-count (`:145-148`), no-id (`:150-152`), malformed shape (`:167-169`) are **return failClosed** inside the outer try — they never throw through `sentryGet`, so they are already retry-exempt by construction | No change needed; only HTTP-4xx (currently a generic throw at `:130`) must be classified non-transient |
| Errors are token-free by construction | Confirmed — token is only in the `Authorization` header; thrown string is `Sentry GET returned HTTP <status>` (`:130`); outer catch slices `err.message` (`:191`) | Preserve: new throws carry status only; backoff/classifier add no token; keep the existing token-non-leak test and extend it |
| Timeout currently rejects with `AbortError` | Confirmed — `ctrl.abort()` → DOMException `AbortError`; the canonical `isRetryable` matches `TimeoutError` (from `AbortSignal.timeout`), NOT `AbortError` | Switch to `AbortSignal.timeout(SENTRY_FETCH_TIMEOUT_MS)` per attempt (mirrors `github-api.ts`) so the timeout maps to a `TimeoutError` already classified transient — removes the manual `setTimeout`/`clearTimeout` bookkeeping while keeping the same 10 s per-attempt bound |
| #5417 (AC12 target) | OPEN — `fix(infra): soleur-web-platform container restarts … killing heavy crons` | In scope to fix the verification reliability; not closed by this PR |
| #5669 (durable deploy-coupling fix) | OPEN issue (not a PR) — durable decoupling of crons from deploy lifecycle | Explicitly OUT of scope; referenced in PR body |
| A schedule/cron file exists for this check | None — `rg "sentry-issue-rate" .github/` returns zero; the check is HTTP-armed via `POST /api/internal/schedule-reminder` | Do NOT add a schedule file; note the recurring-vs-one-time guidance in the PR body only |
| C4 models the check / Sentry edge | `model.c4`/`views.c4`/`spec.c4` have zero `sentry|issue-rate|scheduled-reminder|named-check` references | No C4 update (see Architecture Decision section) |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is an
operator-only post-deploy verification primitive. A regression would, at worst,
reproduce today's behavior (a fail-closed `info` verdict comment on the report
issue) or, if the retry classifier were wrong, post a fail-closed comment where a
recovery was possible. The retry re-attempts only the **fetch**; the verdict math
(`computeRatePerDay`) and the `close_on_pass` decision are unchanged, so no
spurious-`pass`/premature-close path is introduced.

**If this leaks, the user's data is exposed via:** N/A — the check reads Sentry
**aggregate** issue stats (no user PII) and posts to a GitHub issue. The only
secret in play is `SENTRY_ISSUE_RW_TOKEN`, which is token-free-by-construction in
all error paths (load-bearing invariant, asserted by an existing test that this
plan extends).

**Brand-survival threshold:** none, reason: internal post-deploy verification
tooling with no end-user surface and no user data; the secret-leak vector is
already closed by the token-free invariant which this plan preserves and
re-asserts. (No sensitive-path file is touched — the change is confined to
`server/inngest/functions/` + tests.)

## Implementation Phases

### Phase 1 — Wrap `sentryGet` in a bounded transient-retry (RED first)

Edit `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`:

1. Import the canonical primitives at the top:
   `import { isRetryable, delay } from "@/server/github-retry";`
   (relative `../../github-retry` per the file's existing import style — verify
   the alias resolves; `@/server/...` is used elsewhere in this file's imports).
2. Add module constants near `SENTRY_FETCH_TIMEOUT_MS` (`:52`):
   - `const SENTRY_FETCH_MAX_RETRIES = 2; // 3 total attempts`
   - `const SENTRY_FETCH_BACKOFF_MS = [500, 1500] as const; // per-retry backoff (scope-mandated)`
   - (Explicit array > `BASE * N ** attempt`: it removes the exponent-base
     ambiguity — siblings use `2 **` → 500/1000, the scope mandates 500/1500 —
     and reads as exactly the schedule the scope specifies. `SENTRY_FETCH_MAX_RETRIES`
     could instead `import { MAX_RETRIES }` from the leaf (same value, 2); a local
     self-documenting name is the equally-valid sanctioned-sibling-budget choice.)
3. Rewrite the `sentryGet` closure (`:121-136`) into a retry loop mirroring
   `github-api.ts fetchWithRetry` — illustrative shape:

   ```ts
   const sentryGet = async (url: string): Promise<unknown> => {
     for (let attempt = 0; attempt <= SENTRY_FETCH_MAX_RETRIES; attempt++) {
       try {
         // Fresh per-attempt timeout — a timed-out signal cannot be reused.
         const res = await fetch(url, {
           headers: { Authorization: `Bearer ${token}` },
           signal: AbortSignal.timeout(SENTRY_FETCH_TIMEOUT_MS),
         });
         // Transient HTTP (5xx / 429): drain + backoff + retry while attempts remain.
         if ((res.status >= 500 || res.status === 429) && attempt < SENTRY_FETCH_MAX_RETRIES) {
           await res.text().catch(() => {}); // drain body (socket keep-alive hygiene)
           await delay(SENTRY_FETCH_BACKOFF_MS[attempt]);
           continue;
         }
         if (!res.ok) {
           // Deterministic 4xx (or transient class with retries exhausted): token-free.
           throw new Error(`Sentry GET returned HTTP ${res.status}`);
         }
         return await res.json();
       } catch (err) {
         // Network / AbortSignal.timeout TimeoutError → transient (isRetryable).
         if (attempt < SENTRY_FETCH_MAX_RETRIES && isRetryable(err)) {
           await delay(SENTRY_FETCH_BACKOFF_MS[attempt]);
           continue;
         }
         throw err;
       }
     }
     // Unreachable — loop always returns or throws above.
     throw new Error("sentryGet: unreachable");
   };
   ```

   Notes that are load-bearing, not optional:
   - The `Authorization` header is the ONLY place the token appears; the thrown
     string carries `res.status` only (network/timeout errors carry no token
     either). Token-free invariant preserved — no flag/annotation needed
     (observability is centralized in `failClosed`, Phase 2).
   - 5xx/429 are classified inline (we hold `res.status`); network/timeout are
     classified in the catch via the canonical `isRetryable`. This is the exact
     split `github-api.ts fetchWithRetry` uses — do NOT add a blanket
     `status >= 500` arm to `isRetryable` (over-retry hazard documented in
     `github-retry.ts:71`).
   - **Why `AbortSignal.timeout` (not the existing `AbortController`):** the
     2026-06-19 failure was the timeout itself. `AbortController.abort()` rejects
     with a DOMException named `AbortError`; the canonical `isRetryable`
     (`github-retry.ts:18`) matches `TimeoutError`, NOT `AbortError` — so keeping
     `AbortController` would leave the retry inert against the very failure that
     caused the outage. `AbortSignal.timeout()` rejects with `TimeoutError`
     (classified transient) and deletes the manual `setTimeout`/`clearTimeout`/
     `finally` bookkeeping. (Verified by deepen-plan agent against the installed
     `isRetryable`.)

### Phase 2 — Observability: mirror EVERY fail-closed to Sentry (no verdict change)

Today a fail-closed `info` verdict is posted only as a GitHub comment and is NOT
mirrored to Sentry (only `verdict === "fail"` calls `reportSilentFallback`). That
silence is exactly why the 10-day outage was invisible — and a transient latency
spike is NOT the only way to hit it. Deepen-plan's observability review surfaced
the same dark-degradation class for **deterministic** fail-closes that no retry
can heal: a revoked/expired `SENTRY_ISSUE_RW_TOKEN` (401/403), a misconfigured
tag/param, or `SENTRY_ISSUE_RW_TOKEN`/host/org/project unset (`:114-116`) would
fail-close on *every* fire and be visible *nowhere* (a GitHub comment is not one
of the six observability layers — `hr-observability-layer-citation`). A recurring
schedule self-heals a transient spike but never a revoked token.

Therefore mirror **every** fail-closed (not just transient-exhaustion) to Sentry
at **warning** level by emitting from inside the `failClosed` helper itself — one
emit site that subsumes the transient-exhausted, deterministic-4xx, env-unset,
and shape/param paths. This also drops the need for a `sentryTransient` flag
(code-simplicity P3-c) — the warn no longer branches on transient-ness.

1. Import `warnSilentFallback` alongside `reportSilentFallback`
   (`@/server/observability` — both already exist; the test file already mocks
   both).
2. Add the warn to the `failClosed` helper (`:97-101`), keeping its return shape
   identical:

   ```ts
   const failClosed = (reason: string): CheckResult => {
     warnSilentFallback(new Error(`sentry-issue-rate fail-closed: ${reason}`), {
       feature: FUNCTION_NAME,
       op: "sentry-issue-rate-fail-closed",
       message: "sentry-issue-rate fail-closed",
       extra: { fn: FUNCTION_NAME, check: "sentry-issue-rate", reason },
     });
     return {
       verdict: "info" as const,
       body: `\`sentry-issue-rate\`: fail-closed — ${reason}. No action taken.`,
       close: false,
     };
   };
   ```

   - **Verdict semantics unchanged:** still returns `info`, `close: false` for
     every reason; only the (additive) Sentry warning is new. Warning level (not
     error) is correct — a fail-closed `info` verdict should not page; the durable
     fix is #5669.
   - **Token-free:** `reason` is either a static string (`invalid-tag`,
     `Sentry env not configured`, `expected exactly 1 issue…`) or the outer
     catch's already-token-free `Sentry query failed (HTTP <status>…)` /
     network-error slice. The `Error` wraps `reason` only — never the token.
   - **Operator query:** the next fail-close (transient OR deterministic) is now
     discoverable in Sentry by `op:sentry-issue-rate-fail-closed feature:event-scheduled-reminder`,
     with the `reason` in `extra` distinguishing transient (`Sentry query failed
     (HTTP 503…)`) from token-rot (`Sentry query failed (HTTP 403…)`) from
     config (`Sentry env not configured`). `warnSilentFallback` uses
     `Sentry.captureException(err, { level: "warning" })`, so the Sentry title is
     the wrapped reason and the `op` tag is the stable handle.
   - The outer catch (`:188-193`) is unchanged except that it no longer needs the
     `sentryTransient` flag — it still builds the token-free `reason` and calls
     `failClosed(...)`, which now emits.

### Phase 3 — Tests (extend the existing handler suite)

The retry lives in the handler closure, so tests belong in
`apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts`
(node-env, matched by the `test/**/*.test.ts` vitest glob). The pure-helper test
`test/lib/sentry-issue-rate.test.ts` needs no change (no lib edit) — note that in
its file-level comment is unnecessary; leave it untouched.

**Make backoff instant and deterministic** by partial-mocking the leaf so
`delay` is a no-op while `isRetryable` stays real (avoids fake-timer/`AbortSignal`
interaction entirely):

```ts
vi.mock("@/server/github-retry", async (orig) => ({
  ...(await orig<typeof import("@/server/github-retry")>()),
  delay: vi.fn(() => Promise.resolve()),
}));
```

Add to the `eventScheduledReminderHandler — sentry-issue-rate` describe. **A new
helper is required** (verified): the existing `stubFetch` (`:221-240`) assigns one
`vi.fn` that maps URL-class → a single fixed `{status, body}`; it has NO
per-attempt sequencing for the same URL. Add a small `stubFetchSequence` helper
that uses `vi.fn().mockImplementationOnce(...).mockImplementationOnce(...)` (the
describe-scope `fetchMock` is already accessible) so attempt 1 and attempt 2 of
the SAME URL return different responses. New cases (all assert `closeCall()` /
`lastComment()` exactly as the sibling cases do):

1. **Transient HTTP 5xx then success → real verdict (not fail-closed).** Search
   returns `503` on attempt 1, then the issue list on attempt 2; detail returns a
   pass series → assert `{ ok: true, reason: "named-check-pass" }`, comment
   contains `**pass**`, NOT `fail-closed`.
2. **Transient network/timeout then success → real verdict.** Attempt 1 throws a
   `DOMException("The operation timed out", "TimeoutError")` (the exact shape
   `AbortSignal.timeout` produces; OR a `TypeError("fetch failed")`), attempt 2
   resolves → real verdict. Asserts the catch-path `isRetryable` classifier.
   (Do NOT use `AbortError` — it is correctly NOT classified transient.)
3. **HTTP 4xx does NOT retry.** Search returns `403` → exactly ONE fetch call to
   the search URL (`fetchMock` call count for the search URL === 1), result is
   `named-check-info` (fail-closed), comment contains `fail-closed`; assert
   `warnSilentFallbackSpy` called with `op === "sentry-issue-rate-fail-closed"`
   and `extra.reason` containing `HTTP 403` (the deterministic-fail-close is now
   Sentry-visible — the P1 the observability review surfaced).
4. **Retries are bounded.** Search returns `503` on every attempt → exactly
   `SENTRY_FETCH_MAX_RETRIES + 1` (= 3) fetch calls to the search URL, then
   `named-check-info` fail-closed; assert `warnSilentFallbackSpy` called with
   `op === "sentry-issue-rate-fail-closed"`.
5. **Retry on the SECOND (detail) call too.** Search succeeds (1 issue); detail
   returns `500` then a series → real verdict — proves both call sites are
   covered.
6. **Env-unset fail-close is Sentry-visible.** With `SENTRY_ISSUE_RW_TOKEN=""`
   (mirrors the existing "missing Sentry env" case): assert `warnSilentFallbackSpy`
   fired `op === "sentry-issue-rate-fail-closed"`, `extra.reason` ===
   `"Sentry env not configured"`, and NO fetch occurred. (Closes the token-rot /
   config silence class.)
7. **Token never leaks across retries/warns.** A 5xx-exhaustion path: assert the
   report comment body AND every `reportSilentFallback`/`warnSilentFallback` call
   argument (`JSON.stringify(call)`) contain neither `ENV.SENTRY_ISSUE_RW_TOKEN`
   nor `Bearer` (extends the existing token-non-leak test to the retry + the new
   warn path).

**Existing cases stay green (additive warn):** the current fail-closed cases
(ambiguous >1 issues, missing-env, invalid-tag, no-id, malformed-shape) now also
trigger `warnSilentFallback(op="sentry-issue-rate-fail-closed")`. No existing
assertion forbids a warn, so they remain green; the new behavior is additive.

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts test/lib/sentry-issue-rate.test.ts`
Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`

## Files to Edit

- `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`
  — import `isRetryable`/`delay` (`@/server/github-retry`) + `warnSilentFallback`
  (`@/server/observability`); add `SENTRY_FETCH_MAX_RETRIES` + `SENTRY_FETCH_BACKOFF_MS`
  constants; rewrite `sentryGet` as a bounded retry loop (`AbortSignal.timeout`
  per attempt); add the `warnSilentFallback(op="sentry-issue-rate-fail-closed")`
  emit inside the `failClosed` helper.
- `apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts`
  — partial-mock `delay` from `@/server/github-retry`; add a `stubFetchSequence`
  helper; add the 7 retry/observability cases; extend the token-non-leak
  assertion to the retry + warn paths.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `git diff` shows `sentryGet` retries on HTTP 5xx, HTTP 429, and
  `isRetryable(err)` (network/`TimeoutError`) only; HTTP 4xx (≠429) throws on the
  first attempt with no `delay` call. Verify by reading the loop + the new tests.
- [x] AC2 — `SENTRY_FETCH_MAX_RETRIES === 2` (3 total attempts) and backoff is
  the explicit `SENTRY_FETCH_BACKOFF_MS = [500, 1500]` schedule. Asserted by the
  bounded-retry test (exactly 3 fetch calls on persistent 5xx).
- [x] AC3 — Transient-then-success yields the REAL verdict
  (`named-check-pass`/`named-check-fail`), not `named-check-info` fail-closed —
  for BOTH the search call and the detail call.
- [x] AC4 — After retries are exhausted the handler still returns the existing
  `failClosed(...)` `info` verdict with `close: false` (comment contains
  `fail-closed`, no PATCH close), and emits `warnSilentFallback` with
  `op === "sentry-issue-rate-fail-closed"`. Additionally a deterministic 4xx and
  the env-unset path BOTH emit the same warn op (the no-longer-silent
  deterministic class).
- [x] AC5 — Token-free invariant holds across all retry/warn paths: report
  comment body and every `reportSilentFallback`/`warnSilentFallback` argument
  contain neither `Bearer` nor `SENTRY_ISSUE_RW_TOKEN`. (Run:
  `grep -n "SENTRY_ISSUE_RW_TOKEN\|Bearer" apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`
  → the token appears ONLY in the `Authorization` header line.)
- [x] AC6 — Per-attempt timeout preserved: each attempt uses a fresh
  `AbortSignal.timeout(SENTRY_FETCH_TIMEOUT_MS)` (10 s).
- [x] AC7 — Inngest step-timeout headroom: confirm the self-hosted Inngest
  step/executor request timeout comfortably exceeds the new worst-case
  single-step wall-time (~55 s — two sequential `sentryGet` loops, each up to
  3×10 s + 2 s backoff; see Risks). If the configured step timeout is < ~60 s,
  the retry could newly trip an Inngest-level timeout — verify before merge (grep
  the Inngest worker/executor config or the `inngest.createFunction` timeout, if
  set) and document the headroom in the PR body.
- [x] AC8 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] AC9 — Both test files pass via the vitest command above (no behavioral
  regression in the existing 13 sentry-issue-rate cases — they now also warn).
- [x] AC10 — `CHECK_REGISTRY` exact-set membership test still passes
  (`{open-silence-issue-count, sentry-issue-rate}`) — no registry change.

### Post-merge (operator)

- None. This is a pure code change against an already-provisioned surface (no
  migration, no secret mint, no infra apply). Recurring-vs-one-time scheduling is
  an operator scheduling concern, surfaced in the PR body (see below) — not a code
  deliverable here.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` cross-referenced against
the two edited file paths returned no matching open scope-outs.)

## Domain Review

**Domains relevant:** none

Infrastructure/tooling reliability change. No Product/UI surface (Files to Edit
are a server `.ts` function + its vitest spec; no path matches the UI-surface
term list / `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). No
finance/legal/marketing/sales/support/ops implications. Engineering-only; the
CTO lens is satisfied inline by the precedent-reuse + fail-closed-preservation
design above.

## Observability

```yaml
liveness_signal:
  what: the named-check posts a result comment to report_to_issue on each fire
  cadence: per-fire (HTTP-armed; recurring scheduling is an operator concern — PR body note)
  alert_target: GitHub report_to_issue thread + Sentry (on fail verdict / transient-exhaustion)
  configured_in: apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts (CHECK_REGISTRY["sentry-issue-rate"])
error_reporting:
  destination: Sentry via reportSilentFallback (verdict=fail, error) + warnSilentFallback (NEW: every fail-closed, op=sentry-issue-rate-fail-closed, warning)
  fail_loud: true  # EVERY fail-closed (transient-exhausted, deterministic-4xx, env-unset, shape/param) now mirrors a Sentry warning — no comment-only-silent path remains
failure_modes:
  - mode: Sentry transient latency / 5xx / 429
    detection: retried 2x (500ms, 1500ms); on exhaustion failClosed → warnSilentFallback op=sentry-issue-rate-fail-closed (reason carries HTTP 5xx)
    alert_route: Sentry warning
  - mode: Sentry deterministic 4xx (auth/token-rot 401/403, not-found)
    detection: single-shot (no retry) failClosed → warnSilentFallback op=sentry-issue-rate-fail-closed (reason carries HTTP 4xx)
    alert_route: Sentry warning
  - mode: env unset (SENTRY_ISSUE_RW_TOKEN/host/org/project) — token rot/deprovision
    detection: pre-fetch failClosed → warnSilentFallback op=sentry-issue-rate-fail-closed (reason="Sentry env not configured")
    alert_route: Sentry warning
  - mode: wrong-issue-count / no-id / malformed stats shape / invalid param
    detection: failClosed → warnSilentFallback op=sentry-issue-rate-fail-closed (reason carries the specific shape/param tag)
    alert_route: Sentry warning
  - mode: verdict=fail (rate above threshold)
    detection: reportSilentFallback op=named-check-failed (unchanged)
    alert_route: Sentry error
logs:
  where: Sentry (Inngest function runtime, captureException level=warning/error) + pino logger.warn mirror + GitHub report_to_issue comment thread
  retention: Sentry project default
discoverability_test:
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/inngest
  expected_output: 401
  rationale: anonymous GET to the Inngest serve endpoint returns 401 (signature required), proving the function host that runs this named-check is deployed and reachable without SSH
  unit_test: cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts (retry suite — transient-then-success → real verdict; 4xx no-retry; bounded to 3 attempts; every fail-closed warns op=sentry-issue-rate-fail-closed)
  live_probe: Sentry search `op:sentry-issue-rate-fail-closed feature:event-scheduled-reminder` shows the next live fail-close (no SSH)
```

## Architecture Decision (ADR / C4)

No architectural decision. This is a bounded-retry behavioral hardening on an
existing surface — it introduces no ownership/tenancy boundary, no new substrate,
no resolver/dispatch/trust-boundary change, and reverses no ADR. ADR-033
invariants are preserved (I1: all IO stays inside `step.run`; I5: deterministic
plain-JSON return shapes unchanged). The durable deploy-coupling decision lives
in #5669 / the `inngest-scheduled-durability` brainstorm (ADR-030 successor) and
is explicitly out of scope.

**C4 completeness check:** read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`) — none
reference Sentry, the `sentry-issue-rate` check, the `event-scheduled-reminder`
function, or a named-check actor/system/edge. Enumerated for this change:
(a) external human actors — none (operator-only, no new correspondent);
(b) external systems — Sentry (read) and GitHub (comment/close) are both already
implicit Inngest-function dependencies, NOT modeled as C4 elements, and this
change adds no new edge to them; (c) data stores — none touched; (d) access
relationships — unchanged. No `.c4` edit required.

## Infrastructure (IaC)

Skip — no new infrastructure. No server, systemd unit, cron, vendor account, DNS,
TLS, secret, or firewall rule is introduced. `SENTRY_ISSUE_RW_TOKEN` already
exists; no new env var is added (backoff is module constants, not config). Pure
code change under `server/`.

## Risks & Sharp Edges

- **Timeout-mechanism swap (`AbortController` → `AbortSignal.timeout`).** The
  rewrite changes the timeout rejection from `AbortError` to `TimeoutError` so the
  canonical `isRetryable` classifies it without forking. This is the
  `github-api.ts fetchWithRetry` precedent. Any test that simulates the timeout
  MUST throw a `DOMException(..., "TimeoutError")` (or a `TypeError("fetch failed")`)
  — an `AbortError` would NOT be classified transient and would not retry.
- **Do NOT widen `isRetryable` with a blanket `status >= 500` arm.** The leaf's
  header (`github-retry.ts:71`) documents why (octokit over-retry). For raw fetch
  we hold `res.status` directly, so the 5xx/429 decision is made inline in the
  loop — never inside the shared classifier.
- **Test backoff must be neutralized.** Partial-mock `delay` from
  `@/server/github-retry` to a resolved no-op (keeping `isRetryable` real) rather
  than relying on `vi.useFakeTimers()` — fake timers interact awkwardly with
  `AbortSignal.timeout`'s internal timer. (Fake timers + `vi.runAllTimersAsync()`
  is a workable fallback if the partial mock proves insufficient.)
- **Deterministic failures are retry-exempt by construction, not by classifier.**
  wrong-issue-count / no-id / malformed-shape are `return failClosed(...)` inside
  the outer try — they never throw through `sentryGet`, so they are already
  single-shot. Only HTTP-4xx needed explicit non-transient classification.
- **Token-free invariant is load-bearing.** Every new throw/warn carries status +
  slugs + the static/sliced `reason` only. The existing token-non-leak test is
  extended to the retry and warn paths; do not regress it.
- **Import path.** Confirm `@/server/github-retry` resolves from this file (the
  file imports siblings via `@/server/...`, so `@/server/github-retry` is the
  right form); let `tsc` confirm.
- **Inngest step-timeout headroom (P2).** The ~55 s worst-case single-step
  wall-time must sit under the self-hosted Inngest step/executor request timeout
  — verify before merge (AC7). A retry that recovers a transient spike but trips
  an Inngest step timeout would trade one failure surface for another.
- **Step-replay re-fire of comment/close (pre-existing, P3).** The Sentry reads,
  the comment POST (`:303`), and the close PATCH (`:327`) share one `run-check`
  step; on a mid-step worker restart the whole step replays and the comment/close
  can re-fire (Inngest has no exactly-once for un-memoized steps). This is NOT
  introduced by this PR — the fetch retry is side-effect-free and all retries
  complete before the first GitHub write — but lengthening the step modestly
  widens the restart window in which a replay double-posts. Noted, not fixed here;
  the durable fix path is the per-fetch `step.run` decomposition (Alternatives) +
  #5669.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Reuse `withGithubRetry` from `github-retry.ts` wholesale | It is octokit-shaped (`isRetryableGithubError` cause-chain walk, 1 s/2 s budget) and does NOT handle raw-fetch `!res.ok` status. The raw-fetch shape (`fetchWithRetry`) is the right precedent; reuse only the leaf `isRetryable` + `delay`. |
| Keep `AbortController`, extend classifier to match `AbortError` | Forks the canonical `isRetryable`. Switching to `AbortSignal.timeout` (already the `github-api.ts` idiom) avoids the fork and deletes manual timer bookkeeping. |
| Add a `SENTRY_FETCH_BACKOFF_MS` env var for test-time speed | Adds config surface (and an Infra-gate trigger) for no production benefit. Partial-mocking `delay` is cleaner and zero-surface. |
| Move the retry loop into the pure `lib/inngest/sentry-issue-rate.ts` helper | That file's invariant is "no server-only import"; `isRetryable`/`delay` live under `server/`. Keep the orchestration in the handler; keep `lib/` pure. |
| Decompose the two reads into separate `step.run` units (so Inngest memoizes a successful search across a detail failure/restart and applies native step-level retry) | **Considered, deferred.** This is the more durable shape — it would make a successful search survive a mid-step worker restart and let Inngest's own retry compose with the fetch retry. But it is a larger change to step structure and the return-into-state shape, and the restart-durability concern is exactly what #5669 tracks. In-step fetch retry is the minimal within-invocation fix; the step decomposition is the durable follow-on, not this PR. |
| Restrict the new Sentry warn to ONLY the transient-exhaustion path | Rejected at deepen-plan — the observability review showed deterministic fail-closes (token-rot 401/403, env-unset) are the SAME silent class and a recurring schedule never heals them. Mirroring every fail-closed (one emit in `failClosed`) is both more complete and simpler (drops the `sentryTransient` flag). |
| Fix the one-time→recurring scheduling here | Out of scope — scheduling is an operator concern and no schedule file exists for this check. The durable decoupling is #5669. Note in PR body only. |
| Change the AC rate threshold | Explicitly out of scope. |

## PR Body Notes (for /ship)

- `Ref #5417` (the AC12 verification this hardens) and `Ref #5669` (the durable
  deploy-coupling fix, out of scope). Do NOT `Closes` either — #5417 is the infra
  parent and #5669 is separate work.
- **Operator scheduling guidance (no code change):** fail-closed verifications
  like `sentry-issue-rate` should be armed as **recurring** reminders rather than
  one-time, so a transient-exhausted fail-closed self-heals on the next fire. This
  PR makes a single transient spike recoverable in-flight; recurring scheduling is
  the complementary operator-side defense. The durable substrate fix is tracked in
  #5669.
