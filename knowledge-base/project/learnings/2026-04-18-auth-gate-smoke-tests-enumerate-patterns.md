---
title: Auth-gate smoke tests enumerate known auth patterns; new wrappers must extend the enumeration
date: 2026-04-18
category: test-failures
tags: [testing, security, auth, smoke-tests, regex, kb-security]
pr: "#2571"
closes: "#2510"
---

# Auth-gate smoke tests enumerate known auth patterns

## Problem

`apps/web-platform/test/kb-security.test.ts` enforces that every route under `app/api/kb/**` has an authentication gate. The test reads each route's source and matches against a known-safe set of auth patterns:

```ts
const hasInlineAuth = content.includes("supabase.auth.getUser");
const invokesHelper = /const\s+\w+\s*=\s*await\s+authenticateAndResolveKbPath\s*\(/.test(content);
const delegatesToHelper = invokesHelper && checksHelperResult;
expect(hasInlineAuth || delegatesToHelper).toBe(true);
```

After PR #2571 wrapped `kb/search/route.ts` with `withUserRateLimit` and removed the inner `getUser()` call (the wrapper now owns auth — a review-driven change to eliminate the duplicate auth round-trip), the smoke test failed with `app/api/kb/search/route.ts missing auth check`. The route IS auth-gated — the wrapper does it — but the test's regex list didn't know that pattern.

## Root cause

Auth-gate smoke tests pattern-match against a **finite enumerated list of known auth primitives**. They are deliberately coupled to the auth layer's public API so that a route deleting all auth and passing `{ status: 200 }` unconditionally fails fast, not at integration test time. Adding a new auth primitive (`withUserRateLimit` in this case) without extending the enumeration causes false positives on every route that migrates to the new pattern.

## Solution

Extended `kb-security.test.ts` with a third proven-auth signal — an export matching `withUserRateLimit(handler, ...)`:

```ts
const wrapsWithRateLimit =
  /export\s+const\s+(GET|POST|PUT|PATCH|DELETE)\s*=\s*withUserRateLimit\s*\(/.test(content);

expect(
  hasInlineAuth || delegatesToHelper || wrapsWithRateLimit,
  `${relativePath} missing auth check (inline getUser, authenticateAndResolveKbPath, or withUserRateLimit wrap)`,
).toBe(true);
```

The regex pins the **exact exported handler** — a bare `import { withUserRateLimit }` or dead reference will not pass. This matches the existing strictness of the `authenticateAndResolveKbPath` check (which requires both the `await` call and the `!result.ok` early return).

## Prevention

When introducing a new primitive that replaces an existing gate (auth, validation, rate-limit, etc.), grep for tests that pattern-match against the old primitive's name and extend the match list in the same commit:

```bash
# Before wrapping a route with a new primitive, find the smoke tests that check it
grep -rln "supabase.auth.getUser\|authenticateAndResolveKbPath" test/
```

Each hit is a candidate test to extend. If the grep returns zero, the new primitive may be net-new and no extension is needed — but verify by running the full suite before concluding.

Same class as `cq-raf-batching-sweep-test-helpers` (sweep test helpers when adding rAF) and `cq-preflight-fetch-sweep-test-mocks` (sweep fetch mocks when adding HEAD) — when a SUT change introduces a new cross-cutting pattern, the test primitives that enumerate the old pattern must be extended in the same edit.

## Session Errors

1. **TS cast error on SdkMcpToolDefinition in mock shape** — direct `as Array<{handler: ...}>` failed because the real handler signature is `(args, extra) => ...`, arity 2, while the test assumed arity 1. **Recovery:** Added `as unknown as Array<{...}>` intermediate cast. **Prevention:** When mocking third-party SDK types with test-private shapes, use `as unknown as` cast from the start to bypass structural-assignment checks.
2. **TS `Cannot find namespace 'z'`** after strengthening a Zod `safeParse` test via `await import("zod/v4")`. **Recovery:** Switched from `z.ZodRawShape` to `Parameters<typeof zodMod.z.object>[0]`. **Prevention:** Type annotations from dynamically-imported modules are not in scope; use `Parameters<>` or `ReturnType<>` helpers instead.
3. **kb-security auth-gate smoke test false-negative after auth-gate migration** — see Solution above. **Prevention:** this learning.
