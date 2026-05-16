---
date: 2026-05-07
category: test-failures
component: vitest, apps/web-platform/test
related_pr: 3441
related_issues: [3438, 3439]
tags: [vitest, mocking, vi.doMock, error-handling, observability-tests]
---

# Vitest `vi.doMock` factory throw produces synthetic-wrapper Error — inner message is unobservable

## Problem

Writing the direct unit test for the `lazy_import_failed` branch in
`apps/web-platform/server/pdf-text-extract.ts:106-123` (closes #3438), the
test simulated a pdfjs module-init failure via:

```ts
vi.doMock("pdfjs-dist/legacy/build/pdf.mjs", () => {
  throw new Error("simulated module-init failure");
});
```

The SUT's `catch` block calls `reportSilentFallback(importErr, ...)` with the
caught error. The first version of the test asserted on the inner message:

```ts
expect((errArg as Error).message).toContain("simulated module-init failure");
```

This failed with:

```
AssertionError: expected '[vitest] There was an error when mocking a module…'
  to contain 'simulated module-init failure'
Expected: "simulated module-init failure"
Received: "[vitest] There was an error when mocking a module. If you are using
  'vi.mock' factory, make sure there are no top level variables inside, since
  this call is hoisted to top of the file. ..."
```

## Root Cause

Vitest wraps any throw from a `vi.doMock` factory function with its own
synthetic `Error` whose `.message` is a generic vitest diagnostic (the
"top-level variables" hint, even though we're using `doMock` which is NOT
hoisted). The inner error string is **not** preserved on the wrapper's
`.message` field — it appears to be discarded in favor of vitest's own
guidance text.

This means: any SUT that catches a failed lazy `import("mocked-spec")` and
exposes the caught error via observability (Sentry mirror, log line, etc.)
sees vitest's wrapper Error, not the test author's intended Error.

## Solution

Don't assert on the inner message. Assert on **observable behavior** the SUT
guarantees regardless of the wrapper:

1. The discriminated-union return value (`result.error === "lazy_import_failed"`).
2. The shape of the Sentry-mirror call (`feature`, `op`, `extra.nodeVersion`).
3. That `errArg` is an `Error` instance (the `instanceof` check survives
   wrapping).

Final assertion shape:

```ts
expect(result).toMatchObject({ error: "lazy_import_failed" });
expect(reportSilentFallback).toHaveBeenCalledTimes(1);
const [errArg, ctxArg] = reportSilentFallback.mock.calls[0];
expect(errArg).toBeInstanceOf(Error);
// NOT: expect(errArg.message).toContain("simulated module-init failure");
expect(ctxArg).toMatchObject({
  feature: "kb-concierge-context",
  op: "extractPdfText.import",
});
expect(ctxArg.extra).toMatchObject({ nodeVersion: process.versions.node });
```

## Key Insight

When mocking a module to throw at init time via `vi.doMock`/`vi.mock` factory,
the test author's `new Error("X")` is a *trigger*, not a *contract*. Vitest
owns the error surface that reaches the SUT, and that surface is opaque to
the consumer. Assert on the SUT's contract (return shape, observability
emission), not on the trigger's identity.

The same applies to any test framework that mediates module loading: Jest,
bun's mocking, esbuild's plugin layer. The framework-mediated throw is a
test fixture; the test fixture's content is not load-bearing.

## Prevention

- When designing a test that simulates a module-init failure, decide upfront:
  what observable contract does the SUT expose to its caller? That is the
  assertion target — not the failure mechanism.
- If a future review-reviewer says "this test should assert on the Error
  message," push back: cite this learning, link to vitest's wrapper behavior.
- Keep a `// NOT` comment in the test next to the contract-level assertions
  so future maintainers don't re-add the message check on a bug-fix branch.

## Session Errors

**vi.doMock factory throw inner-message swallowed by vitest wrapper**
— Recovery: dropped `expect(errArg.message).toContain(...)` assertion in
favor of `errArg instanceof Error` + the discriminated-union/observability
contract assertions.
— Prevention: documented in this learning. The `// NOT` comment in
`apps/web-platform/test/pdf-text-extract.test.ts` (around the
`lazy_import_failed` test) makes the trade-off visible at the call site.

## References

- PR #3441 — engine-floor guard for sibling pdfjs suites + lazy_import_failed
  test (closes #3439, #3438)
- `apps/web-platform/test/pdf-text-extract.test.ts:262-310` — final test
- `apps/web-platform/server/pdf-text-extract.ts:106-123` — covered branch
- Related: `knowledge-base/project/learnings/test-failures/2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race.md`
  — sibling vitest-mocking gotcha (`mockReturnValue` factory eagerness)
