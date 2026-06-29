# Learning: a fetch-retry loop that drains the body needs a `.text()` on every test stub

## Problem

While hardening the `sentry-issue-rate` named-check with a bounded transient-retry
(`apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`), the new
RED tests for the HTTP-5xx/429 path failed in an unexpected way: instead of
retrying, they returned `named-check-info` (fail-closed) with `searchCalls() === 1`
— as if the retry loop did not exist.

## Root cause

The retry loop drains the response body before backing off, for socket keep-alive
hygiene (mirrors `github-api.ts` `fetchWithRetry`):

```ts
if ((res.status >= 500 || res.status === 429) && attempt < MAX) {
  await res.text().catch(() => {}); // <-- requires res.text to exist
  await delay(backoff[attempt]);
  continue;
}
```

The test's `fetch` stub returned `{ ok, status, json }` with **no `.text`**. Calling
`res.text()` on a stub without that method throws a **synchronous** `TypeError`
(`res.text is not a function`) — which `.catch()` does NOT trap (it only catches a
rejected promise, not a synchronous throw at call time). That TypeError propagated to
the loop's outer `catch (err)`, where `isRetryable(TypeError "res.text is not a
function")` returns `false` (it is not the undici `"fetch failed"` TypeError), so the
loop rethrew → fail-closed on the first attempt. The retry was real; the *test
fixture* defeated it.

## Solution

Add `text: async () => ""` to every fetch stub the retry path can hit (both the
sequencing helper `stubFetchSequence` and the legacy `stubFetch`). The drained value
is discarded, so `""` is fine; what matters is that the method exists, matching a real
`fetch` Response.

## Key Insight

When you add body-drain (`res.text()` / `res.arrayBuffer()` / `res.json()` on the
error path) to a fetch wrapper, every test stub for that wrapper must provide the
drained method — a real `Response` always has it. The failure is doubly deceptive:
(1) the synchronous throw bypasses an adjacent `.catch()`, and (2) it surfaces as a
*classification* miss (the retry "doesn't fire") rather than an obvious
"text is not a function", so it reads like a logic bug in the loop, not a fixture gap.
Grep the stub factory for the methods the wrapper now calls before debugging the loop.

## Session Errors

- **5xx/429 retry tests failed (searchCalls=1, fail-closed) on first GREEN run.**
  Recovery: added `text: async () => ""` to both fetch stubs. Prevention: when a
  fetch wrapper gains a body-drain call, update the stub factory in the same edit
  (this learning); a `res.text` presence is part of stub-fidelity.
- **Edit `old_string` mismatch** (typed `500/1500`, file had `500/1000`). One-off
  typo; re-read and corrected. No prevention warranted.

## Tags
category: test-failures
module: apps/web-platform/server/inngest
related: [[2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race]]
