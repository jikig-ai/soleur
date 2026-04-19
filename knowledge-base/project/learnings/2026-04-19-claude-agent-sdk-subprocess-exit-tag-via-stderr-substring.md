# Learning: Tag Sentry by stderr-substring when SDK subprocess does process.exit(1)

**Date:** 2026-04-19
**PR:** #2646
**Issue:** #2634
**Files:** `apps/web-platform/server/agent-runner.ts`,
`apps/web-platform/test/agent-runner-sandbox-config.test.ts`

## Problem

`@anthropic-ai/claude-agent-sdk` runs the Claude Code CLI as a subprocess.
When `Options.sandbox.failIfUnavailable: true` trips in the subprocess, the
SDK writes a recognisable substring to **subprocess stderr** and calls
`process.exit(1)`:

```
Error: sandbox required but unavailable: <reason>
  sandbox.failIfUnavailable is set — refusing to start without a working sandbox.
```

In the parent Node process, the `for await (const message of query(...))`
loop throws — but the thrown `Error` only carries a stderr-derived message
(usually a generic "command failed" / pipe-closed shape), with **no
structured field** identifying it as a sandbox-availability problem.

The default `Sentry.captureException(err)` therefore lands an untagged event
that on-call cannot filter. AGENTS rule
`cq-silent-fallback-must-mirror-to-sentry` is *technically* satisfied
(Sentry is notified), but operational triage time regresses from seconds to
tens of minutes.

## Solution

In the catch around the SDK call, do a substring match on `err.message` and
route through the project's `reportSilentFallback` helper with explicit
`feature` and `op` tags before falling back to bare `captureException`:

```ts
const errMsg = err instanceof Error ? err.message : String(err);
if (errMsg.includes("sandbox required but unavailable")) {
  reportSilentFallback(err, {
    feature: "agent-sandbox",
    op: "sdk-startup",
    extra: { userId, conversationId, leaderId },
  });
} else {
  Sentry.captureException(err);
}
```

The substring is part of the SDK's user-facing UX text and changes only
across breaking SDK releases — stable for our pin window. Degraded fallback
(missed substring) reverts to plain `captureException` — never silent.

## Key Insight

When an SDK runs as a subprocess and signals failure via stderr +
`process.exit(N)`, structured error metadata does NOT cross the process
boundary. The only durable signal is the stderr substring that lands inside
the parent's thrown `Error.message`. Tag at the catch site by substring;
don't wait for the SDK to expose typed errors that the IPC layer cannot
preserve.

This pattern generalises beyond the Agent SDK to any tool invoked via
`spawn`, `exec`, or stream-based RPC where the parent sees only an exit
code + text.

## Test pattern

When asserting that a spy on a shared helper (e.g.
`reportSilentFallback`) was called for a specific feature, **filter
`mock.calls` by tag rather than by total invocation count**. Production
code may call the same helper from sibling-module init paths (e.g.
`kb-share` baseUrl warning fires at module load when `NEXT_PUBLIC_APP_URL`
is unset in the test env). `toHaveBeenCalledOnce()` and
`not.toHaveBeenCalled()` both fail in that case for reasons unrelated to
the test:

```ts
// Wrong — fails because module-init also called the helper
expect(mockReportSilentFallback).toHaveBeenCalledOnce();

// Right — filter to the call(s) you actually own
const sandboxCalls = mockReportSilentFallback.mock.calls.filter(
  ([, opts]) => opts?.feature === "agent-sandbox",
);
expect(sandboxCalls).toHaveLength(1);
```

## Session Errors

1. **Unbounded grep on minified SDK file (`apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/cli.js`)** —
   `grep -nC1 "<pattern>" cli.js | head -50` overflowed because the file is
   ~700 KB on a single minified line. Recovery: switched to the `Grep` tool
   with specific patterns and `head_limit`. **Prevention:** AGENTS.md
   `hr-never-run-commands-with-unbounded-output` already covers this, and
   the project's tmpfs-sink hook captured the overflow correctly. No new
   rule needed.

2. **Test mock-call assertion broken by sibling-module init code** — first
   draft of the new `feature: "agent-sandbox"` regression tests used
   `expect(mockReportSilentFallback).toHaveBeenCalledOnce()` and
   `not.toHaveBeenCalled()`. Both failed because `agent-runner` module load
   also fires a `feature: "kb-share"` baseUrl warning through the same
   helper. Recovery: filter `mock.calls` by `opts.feature ===
   "agent-sandbox"` before counting. **Prevention:** see "Test pattern"
   above.

## Tags

category: integration-issues
module: agent-runner
related: #2634, #2646, knowledge-base/project/learnings/security-issues/2026-04-19-socat-load-bearing-for-bwrap-sandbox.md
