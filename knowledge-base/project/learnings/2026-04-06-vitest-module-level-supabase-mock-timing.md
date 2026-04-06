# Learning: Vitest mock timing for module-level Supabase client

## Problem

When testing functions that use a module-level `createClient()` call (Supabase client created at import time), overriding the mock's `from()` method inside a test function is too late. The module-level `supabase` variable already holds the mock created during module initialization. Calling `vi.mocked(createClient)("url", "key")` in a test creates a NEW mock client unrelated to the one the module is using.

## Solution

Move tracked mock functions (e.g., `conversationUpdate`) into the `vi.mock()` factory function itself, which runs before module initialization. The factory's `from()` implementation routes table names to the appropriate mocks. Test assertions then check the module-level mock references directly.

```typescript
// Tracked mock defined OUTSIDE vi.mock but BEFORE imports
const conversationUpdate = vi.fn().mockReturnValue({ eq: vi.fn().mockReturnValue({ error: null }) });

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({
    from: vi.fn((table: string) => {
      if (table === "conversations") {
        return { update: conversationUpdate };  // routes to tracked mock
      }
      // ... other tables with generic mocks
    }),
  })),
}));
```

For integration tests that need different responses per table (api_keys returns data, users returns workspace path), override `mockClient.from` via `vi.mocked(createClient).mock.results[0].value` — this accesses the SAME mock instance the module received.

## Key Insight

Vitest `vi.mock()` factories are hoisted to the top of the file and run before any imports. Variables declared in the factory closure are accessible in tests. Use this to create "tracked mocks" that survive module initialization.

## Session Errors

1. **TypeScript error: `createClient()` called without args** -- `vi.mocked(createClient)()` missing required parameters. Recovery: added dummy args `("http://localhost", "test-key")`. Prevention: always provide required args even on mocked functions to satisfy TypeScript.
2. **`npx tsc` resolved to wrong package from wrong directory** -- Running from worktree root found the npm `tsc` package (v2.0.4) instead of TypeScript. Recovery: ran from `apps/web-platform/` where `typescript` is a devDependency. Prevention: always `cd` to the package directory before running `npx tsc`.
3. **Test assertion failure: mock set up too late** -- `conversationUpdate` mock configured after module load, so the module's `supabase.from("conversations")` returned the generic mock. Recovery: moved tracked mock into `vi.mock()` factory. Prevention: this learning documents the pattern.

## Tags

category: test-failures
module: web-platform
