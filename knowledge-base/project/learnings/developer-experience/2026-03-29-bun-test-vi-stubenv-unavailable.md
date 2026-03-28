---
module: web-platform
date: 2026-03-29
problem_type: developer_experience
component: testing_framework
symptoms:
  - "vi.stubEnv is not a function when running bun test"
  - "30 test failures after switching from process.env assignment to vi.stubEnv"
  - "TypeScript TS2540 error: Cannot assign to NODE_ENV because it is a read-only property"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
tags: [bun-test, vitest, process-env, typescript-strict, vi-stubenv]
---

# Troubleshooting: vi.stubEnv unavailable in bun's test runner

## Problem

After enabling TypeScript strict mode type-checking locally, `process.env.NODE_ENV = "value"` assignments in test files produce TS2540 errors. The natural fix (`vi.stubEnv` from Vitest 3.1+) fails at runtime because tests run via `bun test`, which shims vitest's `vi` object but does not implement `stubEnv`/`unstubAllEnvs`.

## Environment

- Module: web-platform
- Runtime: Bun 1.2+ with vitest 3.2.4
- Affected Component: Test files that mutate `process.env.NODE_ENV`
- Date: 2026-03-29

## Symptoms

- `TypeError: vi.stubEnv is not a function` when running `bun test`
- 30 test failures across 5 test files
- TypeScript TS2540: `Cannot assign to 'NODE_ENV' because it is a read-only property` under strict mode

## What Didn't Work

**Attempted Solution 1:** Use `vi.stubEnv('NODE_ENV', 'production')` and `vi.unstubAllEnvs()` (Vitest 3.1+ API)

- **Why it failed:** `bun test` shims vitest's `vi` object for basic mocking (`vi.fn()`, `vi.mock()`) but does not implement environment-specific APIs like `vi.stubEnv`. The shim is partial -- it covers the most common APIs but not all.

## Session Errors

**Variable shadowing caused TS2448 after review fix**

- **Recovery:** Used a local `mutableEnv` alias scoped to the single test that had the shadowing conflict, instead of reusing the describe-level `env` alias.
- **Prevention:** When using aliased variables (`const env = process.env as ...`), check for local variable declarations with the same name in inner scopes before using the alias. TypeScript's block-scoped variable rules treat the inner declaration as the reference for the entire block.

**Previous session chose vi.stubEnv without testing against bun's runner**

- **Recovery:** Replaced all `vi.stubEnv`/`vi.unstubAllEnvs` calls with `process.env as Record<string, string | undefined>` cast pattern.
- **Prevention:** When a plan recommends a test-framework API, verify the API is available in the actual test runner (bun test vs vitest CLI vs jest) before implementing across multiple files. Run a single test file first.

## Solution

Cast `process.env` as `Record<string, string | undefined>` to bypass TypeScript's readonly constraint while remaining compatible with bun's test runner.

**Code changes:**

```typescript
// Before (TS2540 error under strict mode):
process.env.NODE_ENV = "production";

// After (type-safe, works with bun test):
const env = process.env as Record<string, string | undefined>;
env.NODE_ENV = "production";
```

For tests with save/restore patterns:

```typescript
const env = process.env as Record<string, string | undefined>;
const origNodeEnv = env.NODE_ENV;

beforeEach(() => { env.NODE_ENV = "production"; });
afterEach(() => { env.NODE_ENV = origNodeEnv; });
```

For inline mutations, use try/finally to guarantee restoration:

```typescript
const env = process.env as Record<string, string | undefined>;
const origEnv = env.NODE_ENV;
env.NODE_ENV = "development";
try {
  expect(someFunction()).toBe(expected);
} finally {
  env.NODE_ENV = origEnv;
}
```

## Why This Works

1. **Root cause:** Node.js `@types/node` declares `process.env.NODE_ENV` as `readonly` under TypeScript strict mode. This is a type-level constraint, not a runtime one -- `process.env` is genuinely mutable at runtime in Node/Bun.
2. **Why the cast works:** `Record<string, string | undefined>` is the actual runtime shape of `process.env`. The cast tells TypeScript to use the real type instead of the narrower `NodeJS.ProcessEnv` interface with its readonly properties.
3. **Why not type augmentation:** A global `declare namespace NodeJS { interface ProcessEnv { NODE_ENV: string; } }` would make NODE_ENV writable everywhere, including production code where the readonly constraint serves as a useful guard against accidental mutation.

## Prevention

- When tests run via `bun test` (not the vitest CLI), only use `vi` APIs that bun has shimmed: `vi.fn()`, `vi.mock()`, `vi.spyOn()`, `vi.clearAllMocks()`, `vi.resetAllMocks()`. Avoid `vi.stubEnv`, `vi.stubGlobal`, and other environment-specific APIs.
- Before adopting a test-framework API across multiple files, run one test file with `bun test <file>` to verify runtime compatibility.
- For env var mutations in tests, prefer the `Record<string, string | undefined>` cast pattern with explicit save/restore over framework-specific APIs.

## Related Issues

- See also: [2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md](../2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md) (Session Error #2: TypeScript implicit `any` only caught by CI)
- PR #1219 (original CI failure), PR #1220 (type fix), Issue #1225 (this fix)
