---
title: "Partial vi.mock (importOriginal + override) does NOT intercept calls made BY sibling functions in the same module"
date: 2026-06-30
category: test-failures
module: apps/web-platform/test
issue: 5728
tags: [vitest, vi.mock, importOriginal, module-internal-binding, test-design]
---

# Partial module-mock does not intercept intra-module calls

## Problem

While writing a behavioral test for `cronCommunityMonitorHandler` (#5728), I
partial-mocked `_cron-shared` to keep the real `finalizeOutputAwareHeartbeat` and
`DeployInProgressError` while stubbing the spawn-adjacent deps:

```ts
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual = await importOriginal<typeof import(".../_cron-shared")>();
  return {
    ...actual,
    postSentryHeartbeat: (...a) => heartbeatSpy(...a),   // ← override the export
    resolveOutputAwareOk: (...a) => resolveOutputAwareOkSpy(...a),
    // ...
  };
});
```

The test then asserted `heartbeatSpy` was called once on the happy path. It was
called **0 times** — three tests failed with "expected vi.fn() to be called 1
times, but got 0 times" even though the handler clearly posts a heartbeat.

## Root cause

The handler does NOT call `postSentryHeartbeat` directly on the success path — it
calls the REAL `finalizeOutputAwareHeartbeat` (kept via `...actual`), which calls
`postSentryHeartbeat` **from inside its own module**. A `vi.mock` factory replaces
the module's *exports as seen by importERS* (the handler's `import { ... }`), but a
function defined in that module references its sibling via the module's **internal
lexical binding**, NOT the export object. So `finalizeOutputAwareHeartbeat`'s
internal `postSentryHeartbeat(...)` call resolved to the ORIGINAL function, which —
with no Sentry env set in the test — logged "Sentry env unset — skipping heartbeat"
and returned without touching `heartbeatSpy`.

This is the inverse of the wholesale-mock-drops-named-exports trap
([[2026-06-29-wholesale-module-mock-drops-named-exports-needed-by-transitive-siblings]]):
there, the factory dropped an export a transitive sibling needed; here, the factory
*added* an override that the sibling simply doesn't consult.

## Solution

Mock at a boundary the intra-module call actually crosses. `postSentryHeartbeat`'s
only external effect is `fetch(url)`, so I kept it REAL, set the Sentry env vars,
stubbed global `fetch`, and asserted on the POST URL (`?status=ok|error`):

```ts
// keep postSentryHeartbeat real; assert on the boundary it crosses
vi.stubEnv("SENTRY_INGEST_DOMAIN", "o4509.ingest.sentry.io"); // + PROJECT_ID + PUBLIC_KEY
fetchSpy = vi.fn().mockResolvedValue(new Response(null, { status: 202 }));
vi.stubGlobal("fetch", fetchSpy);
// ...
expect(heartbeatUrls()[0]).toContain("?status=ok");
```

This is also *more faithful*: the fetch is the real external seam (what Sentry
receives), so the assertion exercises real URL construction + `resp.ok` inspection
+ retry end-to-end.

## Key insight

A `vi.mock` partial override only affects what **importers** see. To intercept a
call made by function A to sibling B **within the same module**, you cannot override
B's export — you must either (a) mock the deeper boundary B itself crosses
(`fetch`, the DB client, `child_process`), or (b) mock A wholesale (losing A's real
behavior). When you want A's REAL behavior AND to observe B, option (a) is the only
faithful choice. Decision rule: **mock the seam the unit under test does not own**,
not a sibling export it calls through.

## Session Errors

1. **Partial module-mock didn't intercept the intra-module heartbeat call.**
   Recovery: keep `postSentryHeartbeat` real + stub `fetch` + assert the POST URL.
   Prevention: this learning + a bullet in the work skill's vi.mock gotcha list.
2. **Shared guard `cron-producer-output-wiring.test.ts` asserted moved/changed
   source anchors** (`if (!heartbeatOk)`, `spawnResult.stderrTail`) after the
   refactor relocated the gate into `finalizeOutputAwareHeartbeat`'s
   `onBeforeHeartbeat` and added `spawnResult!.X` non-null reads → failed for all 8
   producers. Recovery: updated anchors to the new wiring + strengthened to also
   assert `finalizeOutputAwareHeartbeat(` / `instanceof DeployInProgressError`.
   Prevention: already covered by
   [[2026-04-15-negative-space-tests-must-follow-extracted-logic]] — when extracting
   logic into a helper, update source-shape negative-space guards in the same change.
3. **CWD drift** (recovered via absolute paths). Recurring, already covered.
4. **tasks.md sed embedded-newline artifact** (one-off, cleaned via Edit).
5. **Forwarded:** plan-subagent Edit raced a linter touch mid-write (one-off, re-applied).
