---
title: octokit.request() wraps undici connect timeouts in a RequestError — a top-level transient classifier misses them
date: 2026-06-12
category: integration-issues
module: apps/web-platform/server/github-retry.ts
tags: [octokit, undici, retry, github-api, inngest-cron, sentry, error-cause-chain]
sentry_issue: 448a4173f90a436382c4396371927796
pr: 5227
---

# Learning: octokit wraps undici connect timeouts — classify on the cause chain, not the top-level error

## Problem

Prod Sentry issue `448a4173…` fired an `error`-level mirror from the Inngest cron
`cron-stale-deferred-scope-outs`: `Connect Timeout Error (attempted address:
api.github.com:443, timeout: 10000ms)` / `TypeError: fetch failed`. The cron's
`octokit.request(...)` calls (issue search, comment, close via `createProbeOctokit()`)
had no per-call transient retry, so a single transient connect timeout escalated to an
operator-paging Sentry event even though Inngest `retries: 1` self-heals on the next
attempt.

The obvious fix — "reuse the existing `isRetryable` from `github-retry.ts`" — **silently
does not work**, and a naive test seeded with a bare `TypeError("fetch failed")` would
pass while production stays broken.

## Root cause / key insight

`octokit.request()` does NOT rethrow the raw undici `TypeError: fetch failed`. Verified
against installed source (`@octokit/request@7.x` `dist-src/fetch-wrapper.js` +
`@octokit/request-error@7.x` `dist-src/index.js`):

- On a network throw, fetch-wrapper sets `error.status = 500` on the undici TypeError,
  then constructs `new RequestError(message, 500, ...)` and assigns
  `requestError.cause = <original TypeError>`.
- `RequestError` sets `this.name = "HttpError"`, `this.status` — and **does NOT copy
  `.code` to the top level**.

So the thrown object is:

```
RequestError { name: "HttpError", status: 500, message: "fetch failed",
  cause: TypeError { message: "fetch failed",
    cause: { code: "UND_ERR_CONNECT_TIMEOUT" } } }
```

The existing `isRetryable(err)` keys on `err instanceof TypeError && err.message === "fetch failed"`
OR a **top-level** `err.code`. Against octokit's wrapper that is a `RequestError` (not a
TypeError), with no top-level `.code` and a non-retryable-looking `.status: 500` — so
`isRetryable` returns **false** and the timeout is never retried.

`octokit` also surfaces a *genuine* GitHub 5xx as a `RequestError` with the real status,
so a tempting "retry on status >= 500" arm would over-retry real server errors. The
precise discriminator is to walk the `.cause` chain and apply `isRetryable` at each link.

## Solution

Add a cause-chain-aware classifier + a thin retry wrapper to the shared leaf
`apps/web-platform/server/github-retry.ts` (kept dependency/logger-free to preserve its
no-cycle property), and route the cron's octokit calls through it:

```ts
const MAX_CAUSE_DEPTH = 5; // octokit's real chain is 3 links; bound guards a .cause cycle

export function isRetryableGithubError(err: unknown): boolean {
  let cur: unknown = err;
  for (let depth = 0; depth < MAX_CAUSE_DEPTH && cur != null; depth++) {
    if (isRetryable(cur)) return true;          // depth 1 catches the inner TypeError
    cur = (cur as { cause?: unknown }).cause;
  }
  return false;
}

export async function withGithubRetry<T>(fn: () => Promise<T>): Promise<T> {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try { return await fn(); }
    catch (err) {
      if (attempt < MAX_RETRIES && isRetryableGithubError(err)) {
        await delay(BASE_DELAY_MS * 2 ** attempt); continue;
      }
      throw err;
    }
  }
  throw new Error("withGithubRetry: unreachable");
}
```

Wrap the search in `fetchCandidates`, and the per-issue comment + close as **two
SEPARATE** `withGithubRetry` calls (one wrapper around both would re-POST the
non-idempotent comment on a close-timeout retry). A genuine 403 has no transient cause →
classifier returns false → rethrown on attempt 1 into the existing per-issue catch,
preserving the `issue_write_403` discriminator.

## Prevention

- **Test the real thrown shape, not a convenient bare TypeError.** Seed
  `Object.assign(new Error("fetch failed"), { name:"HttpError", status:500, cause: Object.assign(new TypeError("fetch failed"), { cause:{ code:"UND_ERR_CONNECT_TIMEOUT" } }) })`.
  A bare-TypeError seed passes against the top-level `isRetryable` and hides the entire
  reason the cause-walk exists.
- **For any `octokit.request()` resilience work, classify on the cause chain.** The same
  no-per-call-retry gap exists in sibling probe-octokit crons (`cron-github-app-drift-guard`,
  `cron-oauth-probe`) and `createProbeOctokit`'s 401-only loop — tracked in #5230.
- **When hoisting a shared budget constant, don't over-claim consumers in the comment.**
  `createProbeOctokit` keeps its own `PROBE_JWT_*` constants; only `fetchWithRetry` and
  `withGithubRetry` import the hoisted `MAX_RETRIES`/`BASE_DELAY_MS`.

## Session Errors

1. **AC7 grep-proxy false-fail on a prose token** — An acceptance criterion used
   `git grep -c "UND_ERR_CONNECT_TIMEOUT" <cron> == 0` as a proxy for "the cron does not
   hand-roll a transient classifier." My explanatory code comment mentioned the literal
   token and tripped the grep. **Recovery:** reworded the comment to drop the literal.
   **Prevention:** a `grep == 0` AC that proxies "no hand-rolled logic" also forbids the
   literal in comments — either avoid the token in prose or scope the grep to code lines.
   (One-off — specific to this AC's wording.)
2. **Unhandled-rejection warning from a fake-timer rejection test** — the AC6 handler
   rejected *during* `vi.runAllTimersAsync()`, before the `await expect(p).rejects` handler
   was attached, so vitest flagged an unhandled rejection (tests still passed).
   **Recovery:** attach `const rejection = expect(p).rejects.toThrow(...)` BEFORE advancing
   timers, then `await rejection` after. **Prevention:** with fake timers, attach the
   rejection assertion before `runAllTimersAsync()` whenever the SUT can reject mid-advance.
   (Known vitest idiom — already covered by existing test-failure learnings.)
3. **`git grep` "ambiguous argument"** — ran a repo-root-relative grep from the
   `apps/web-platform` CWD (Bash tool CWD does not persist across calls and had drifted).
   **Recovery:** re-ran from the worktree root with `-- <path>`. **Prevention:** already
   covered by existing AGENTS/work-skill rules on Bash CWD non-persistence; chain
   `cd <root> && git grep …` in one call.
