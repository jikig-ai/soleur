# Inngest middleware: `onFunctionRun` ctx is `InitialRunInfo`, not `BaseContext` — `attempt`/`maxAttempts` live on `transformInput`'s ctx

**Date:** 2026-06-16
**Surfaced by:** multi-agent review of PR #5342 (feat-routines-management), data-integrity-guardian P1.

## The bug

The `run-log` Inngest middleware (`server/inngest/middleware/run-log.ts`) gated its
terminal-row write on a final-attempt check:

```ts
onFunctionRun({ ctx, fn }) {
  const attempt = (ctx as { attempt?: number }).attempt ?? 0;        // ALWAYS undefined → 0
  const maxAttempts = (ctx as { maxAttempts?: number }).maxAttempts ?? 1; // ALWAYS undefined → 1
  ...
  const isFinalAttempt = attempt >= maxAttempts - 1;                 // ALWAYS true
  if (failed && !isFinalAttempt) return;                            // gate NEVER fires
}
```

`onFunctionRun`'s argument is Inngest's **`InitialRunInfo`**, whose `ctx` is typed as
exactly `Readonly<{ event: EventPayload; runId: string }>` —
*"a partial context object... Does not necessarily contain all the data"*
(`node_modules/inngest/components/InngestMiddleware.d.ts`). `attempt`/`maxAttempts`
live on **`BaseContext`** (`node_modules/inngest/types.d.ts`), which is only handed to
**`transformInput`** (`MiddlewareRunArgs.ctx`). The `as` cast hid the type error, so the
gate degraded to always-write → a **double row** (a `failed` row on attempt 0 AND a
`completed` row on attempt 1) for every cron with `retries >= 1` that fails-then-succeeds.

## The fix

Capture the attempt fields inside `transformInput` (which receives the full run ctx) into
closure vars that `transformOutput` reads:

```ts
let attempt = 0, maxAttempts = 1;
return {
  transformInput({ ctx: runCtx }: { ctx: { attempt?: number; maxAttempts?: number } }) {
    attempt = runCtx.attempt ?? 0;
    maxAttempts = runCtx.maxAttempts ?? 1;
  },
  async transformOutput({ result, step }) { /* use attempt/maxAttempts */ },
};
```

## Why the test suite was green anyway (the real lesson)

The unit test fabricated a `ctx` with `attempt`/`maxAttempts` ON the `onFunctionRun`
object and called `transformInput()` with **no args** — a shape Inngest never produces.
That synthetic fixture made the dead gate look alive: a **synthesized-fixture false-green**.
The regression-proof fix was to make the test driver mirror the real hook contract
(attempt delivered ONLY via `transformInput`'s ctx, `onFunctionRun` ctx limited to
`{event, runId}`), so reverting the production fix now fails the test.

**Takeaway:** when a middleware/hook reads a field off a framework-provided context with an
`as` cast, verify against the framework's `.d.ts` *which* lifecycle hook actually carries
that field. Partial-context objects (`InitialRunInfo`-style "does not necessarily contain
all the data") are a trap: the cast compiles, the field is `undefined` at runtime, and a
gate built on it silently no-ops. Unit tests must drive the hook with the framework's real
argument shape, not a convenient flattened one.
