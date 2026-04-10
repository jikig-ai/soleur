# Learning: Vitest vi.hoisted() for typed error classes in mocked modules

## Problem

When a test needs to use a typed error class (e.g., `GitHubApiError`) both in the mock factory for `vi.mock()` and in test assertions, `importOriginal` in the mock factory triggers transitive dependency loading. If those dependencies have their own mocks (e.g., a logger module), the original module's imports fail because the mocked dependencies don't provide all expected exports.

Concrete example: `vi.mock("@/server/github-app", async (importOriginal) => { ... })` tried to load the real `github-app.ts`, which imports `@/server/logger`. The logger mock only provides `{ warn, error, info }` but the real module expects `createChildLogger` — causing a "No createChildLogger export" error.

## Solution

Define the typed error class inside `vi.hoisted()` and include it in the mock's return value. The hoisted class is the same reference the route handler receives via `@/server/github-app`, so `instanceof` checks work correctly.

```typescript
const { mockCreateRepo, GitHubApiError } = vi.hoisted(() => {
  class GitHubApiError extends Error {
    constructor(message: string, public readonly statusCode: number) {
      super(message);
      this.name = "GitHubApiError";
    }
  }
  return { mockCreateRepo: vi.fn(), GitHubApiError };
});

vi.mock("@/server/github-app", () => ({
  createRepo: mockCreateRepo,
  GitHubApiError, // same class reference the SUT receives
}));

// In tests: new GitHubApiError("msg", 422) creates instances
// the route handler recognizes via instanceof
```

## Key Insight

When a module mock needs to provide a class that's used for `instanceof` checks, the class must be the **same reference** in both the mock and the test code. `vi.hoisted()` is the canonical way to share values between the mock factory (hoisted to file top) and test bodies. Avoid `importOriginal` when the real module has complex dependency trees — it defeats the purpose of mocking.

## Session Errors

1. **Ralph loop setup script wrong path** — Used `./plugins/soleur/skills/one-shot/scripts/` instead of `./plugins/soleur/scripts/`. Recovery: tried correct path. Prevention: the one-shot skill references this path; verify script exists before calling.
2. **Vitest importOriginal triggered transitive dependency crash** — Recovery: switched to `vi.hoisted()` pattern. Prevention: documented in this learning.
3. **Edit tool ambiguous match** — `throw new Error(errorMessage)` appeared in two functions. Recovery: provided more surrounding context. Prevention: always include 3+ lines of surrounding context when editing common patterns.

## Tags

category: test-failures
module: web-platform
