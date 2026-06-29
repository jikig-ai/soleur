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
from Inngest's perspective). Inngest therefore never re-runs it. The in-function
fetch-level retry is the correct and only layer that can recover this class of
failure.

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
   - `const SENTRY_FETCH_BACKOFF_BASE_MS = 500; // backoff = BASE * 3**attempt → 500ms, 1500ms`
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
           await delay(SENTRY_FETCH_BACKOFF_BASE_MS * 3 ** attempt);
           continue;
         }
         if (!res.ok) {
           // Deterministic 4xx (or transient class with retries exhausted): token-free.
           throw Object.assign(new Error(`Sentry GET returned HTTP ${res.status}`), {
             sentryTransient: res.status >= 500 || res.status === 429,
           });
         }
         return await res.json();
       } catch (err) {
         // Network / AbortSignal.timeout TimeoutError → transient (isRetryable).
         if (attempt < SENTRY_FETCH_MAX_RETRIES && isRetryable(err)) {
           await delay(SENTRY_FETCH_BACKOFF_BASE_MS * 3 ** attempt);
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
     string carries `res.status` only. Token-free invariant preserved.
   - `sentryTransient` is a boolean flag (no token) used by the outer catch to
     route the observability warning (Phase 2). It does NOT alter the verdict.
   - 5xx/429 are classified inline (we hold `res.status`); network/timeout are
     classified in the catch via the canonical `isRetryable`. This is the exact
     split `github-api.ts fetchWithRetry` uses — do NOT add a blanket
     `status >= 500` arm to `isRetryable` (over-retry hazard documented in
     `github-retry.ts:71`).

### Phase 2 — Observability: surface transient-exhaustion (no verdict change)

Today a fail-closed `info` verdict is posted as a GitHub comment but is NOT
mirrored to Sentry (only `verdict === "fail"` calls `reportSilentFallback`). That
silence is exactly why the 10-day outage was invisible. Add a **warning-level**
mirror when retries are exhausted on a *transient* error, leaving the verdict
unchanged:

1. Import `warnSilentFallback` alongside `reportSilentFallback`
   (`@/server/observability` — both already exist; the test file already mocks
   both).
2. In the outer `catch` (`:188-193`), classify and warn before returning
   `failClosed`:

   ```ts
   } catch (err) {
     const transient = isRetryable(err) ||
       (err && typeof err === "object" && (err as { sentryTransient?: boolean }).sentryTransient === true);
     if (transient) {
       warnSilentFallback(err, {
         feature: FUNCTION_NAME,
         op: "sentry-issue-rate-retry-exhausted",
         message: "sentry-issue-rate fetch failed after bounded retries",
         extra: { fn: FUNCTION_NAME, check: "sentry-issue-rate" },
       });
     }
     const msg = err instanceof Error ? err.message : String(err);
     return failClosed(`Sentry query failed (${msg.slice(0, 80)})`);
   }
   ```

   - Verdict semantics unchanged: still returns `failClosed(...)` → `info`,
     `close: false`. Deterministic 4xx → `transient === false` → no Sentry warn
     (single-shot fail-closed comment only, as today).
   - The `warnSilentFallback` payload carries no token (op slug + feature +
     check name only); `err.message` is the token-free `HTTP <status>` / network
     message.

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

Add to the `eventScheduledReminderHandler — sentry-issue-rate` describe. The
existing `stubFetch` returns a fixed body per URL class; extend it (or add a
small `stubFetchSequence` helper) so the FIRST search call can fail transiently
and the SECOND succeed. New cases (all assert `closeCall()` / `lastComment()`
exactly as the sibling cases do):

1. **Transient HTTP 5xx then success → real verdict (not fail-closed).** Search
   returns `503` on attempt 1, then the issue list on attempt 2; detail returns a
   pass series → assert `{ ok: true, reason: "named-check-pass" }`, comment
   contains `**pass**`, NOT `fail-closed`.
2. **Transient network/timeout then success → real verdict.** Attempt 1 throws a
   `DOMException("aborted", "TimeoutError")` (or a `TypeError("fetch failed")`),
   attempt 2 resolves → real verdict. Asserts the catch-path classifier.
3. **HTTP 4xx does NOT retry.** Search returns `403` → exactly ONE fetch call to
   the search URL (`fetchMock` call count for the search URL === 1), result is
   `named-check-info` (fail-closed), comment contains `fail-closed`.
4. **Retries are bounded.** Search returns `503` on every attempt → exactly
   `SENTRY_FETCH_MAX_RETRIES + 1` (= 3) fetch calls to the search URL, then
   `named-check-info` fail-closed; assert `warnSilentFallbackSpy` called with
   `op === "sentry-issue-rate-retry-exhausted"`.
5. **Retry on the SECOND (detail) call too.** Search succeeds (1 issue); detail
   returns `500` then a series → real verdict — proves both call sites are
   covered.
6. **Token never leaks across retries.** A 5xx-exhaustion path: assert the
   report comment body and every `reportSilentFallback`/`warnSilentFallback` call
   argument do NOT contain `ENV.SENTRY_ISSUE_RW_TOKEN` nor `Bearer` (extends the
   existing token-non-leak test to the retry/warn path).

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts test/lib/sentry-issue-rate.test.ts`
Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`

## Files to Edit

- `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`
  — import `isRetryable`/`delay` + `warnSilentFallback`; add 2 backoff
  constants; rewrite `sentryGet` as a bounded retry loop; add transient-exhaustion
  warn in the outer catch.
- `apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts`
  — partial-mock `delay`; add the 6 retry/observability cases; extend the
  token-non-leak assertion to the retry path.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `git diff` shows `sentryGet` retries on HTTP 5xx, HTTP 429, and
  `isRetryable(err)` (network/`TimeoutError`) only; HTTP 4xx (≠429) throws on the
  first attempt with no `delay` call. Verify by reading the loop + the new tests.
- [ ] AC2 — `SENTRY_FETCH_MAX_RETRIES === 2` (3 total attempts) and backoff is
  `SENTRY_FETCH_BACKOFF_BASE_MS * 3 ** attempt` → 500 ms, 1500 ms. Asserted by
  the bounded-retry test (exactly 3 fetch calls on persistent 5xx).
- [ ] AC3 — Transient-then-success yields the REAL verdict
  (`named-check-pass`/`named-check-fail`), not `named-check-info` fail-closed —
  for BOTH the search call and the detail call.
- [ ] AC4 — After retries are exhausted the handler still returns the existing
  `failClosed(...)` `info` verdict with `close: false` (comment contains
  `fail-closed`, no PATCH close), and emits `warnSilentFallback` with
  `op === "sentry-issue-rate-retry-exhausted"`.
- [ ] AC5 — Token-free invariant holds across all retry/warn paths: report
  comment body and every `reportSilentFallback`/`warnSilentFallback` argument
  contain neither `Bearer` nor `SENTRY_ISSUE_RW_TOKEN`. (Run:
  `grep -n "SENTRY_ISSUE_RW_TOKEN\|Bearer" apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`
  → the token appears ONLY in the `Authorization` header line.)
- [ ] AC6 — Per-attempt timeout preserved: each attempt uses a fresh
  `AbortSignal.timeout(SENTRY_FETCH_TIMEOUT_MS)` (10 s).
- [ ] AC7 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] AC8 — Both test files pass via the vitest command above (no behavioral
  regression in the existing 13 sentry-issue-rate cases).
- [ ] AC9 — `CHECK_REGISTRY` exact-set membership test still passes
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
  destination: Sentry via reportSilentFallback (verdict=fail) + warnSilentFallback (NEW: sentry-issue-rate-retry-exhausted)
  fail_loud: true  # transient exhaustion is no longer comment-only-silent — it now mirrors a Sentry warning
failure_modes:
  - mode: Sentry transient latency / 5xx / 429
    detection: retried 2x (500ms, 1500ms); on exhaustion warnSilentFallback op=sentry-issue-rate-retry-exhausted
    alert_route: Sentry warning
  - mode: Sentry deterministic 4xx (auth / not-found)
    detection: single-shot fail-closed info comment (no retry)
    alert_route: GitHub issue comment
  - mode: wrong-issue-count / malformed stats shape
    detection: fail-closed info comment (return-before-throw; retry-exempt by construction)
    alert_route: GitHub issue comment
  - mode: verdict=fail (rate above threshold)
    detection: reportSilentFallback op=named-check-failed
    alert_route: Sentry error
logs:
  where: Sentry (Inngest function runtime) + GitHub report_to_issue comment thread
  retention: Sentry project default
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts
  expected_output: retry suite passes — transient-then-success → real verdict; 4xx no-retry; bounded to 3 attempts; warn on exhaustion
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
- **Token-free invariant is load-bearing.** Every new throw/flag/warn carries
  status + slugs only. The existing token-non-leak test is extended to the retry
  and warn paths; do not regress it.
- **Import path.** Confirm `@/server/github-retry` resolves from this file (the
  file mixes `@/server/...` and relative `./` imports); use whichever the
  surrounding imports use and let `tsc` confirm.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Reuse `withGithubRetry` from `github-retry.ts` wholesale | It is octokit-shaped (`isRetryableGithubError` cause-chain walk, 1 s/2 s budget) and does NOT handle raw-fetch `!res.ok` status. The raw-fetch shape (`fetchWithRetry`) is the right precedent; reuse only the leaf `isRetryable` + `delay`. |
| Keep `AbortController`, extend classifier to match `AbortError` | Forks the canonical `isRetryable`. Switching to `AbortSignal.timeout` (already the `github-api.ts` idiom) avoids the fork and deletes manual timer bookkeeping. |
| Add a `SENTRY_FETCH_BACKOFF_MS` env var for test-time speed | Adds config surface (and an Infra-gate trigger) for no production benefit. Partial-mocking `delay` is cleaner and zero-surface. |
| Move the retry loop into the pure `lib/inngest/sentry-issue-rate.ts` helper | That file's invariant is "no server-only import"; `isRetryable`/`delay` live under `server/`. Keep the orchestration in the handler; keep `lib/` pure. |
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
