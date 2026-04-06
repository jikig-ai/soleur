---
module: System
date: 2026-04-06
problem_type: test_failure
component: testing_framework
symptoms:
  - "ReferenceError: Cannot access 'mockDeleteWorkspace' before initialization"
  - "vi.mock factory references variables declared with const before vi.mock"
root_cause: test_isolation
resolution_type: code_fix
severity: medium
tags: [vitest, vi-mock, vi-hoisted, mock-hoisting, testing]
---

# Learning: vitest vi.mock() factory requires vi.hoisted() for shared mock references

## Problem

When writing vitest tests with `vi.mock()` factories that reference shared mock functions (e.g., `const mockFn = vi.fn()`), the test fails with `ReferenceError: Cannot access 'mockFn' before initialization`.

This happens because vitest hoists all `vi.mock()` calls to the top of the file at compile time — before any `const`/`let` declarations execute. The factory function runs before the variable is initialized.

```typescript
// BROKEN: mockDeleteWorkspace is not yet initialized when vi.mock runs
const mockDeleteWorkspace = vi.fn();

vi.mock("@/server/workspace", () => ({
  deleteWorkspace: mockDeleteWorkspace, // ReferenceError!
}));
```

## Solution

Use `vi.hoisted()` to declare mock functions that need to be available inside `vi.mock()` factories. `vi.hoisted()` returns values that are hoisted alongside the `vi.mock()` calls.

```typescript
// CORRECT: vi.hoisted ensures these are available when vi.mock factories run
const { mockDeleteWorkspace, mockGetUser } = vi.hoisted(() => ({
  mockDeleteWorkspace: vi.fn(),
  mockGetUser: vi.fn(),
}));

vi.mock("@/server/workspace", () => ({
  deleteWorkspace: mockDeleteWorkspace, // Works!
}));
```

## Key Insight

The pattern `const mockFn = vi.fn()` followed by `vi.mock("module", () => ({ fn: mockFn }))` looks correct sequentially but fails because vitest transpiles `vi.mock` to the top of the file. Always use `vi.hoisted()` when mock variables are shared between the declaration site and `vi.mock` factories.

## Session Errors

**vi.mock hoisting error** — `ReferenceError: Cannot access 'mockDeleteWorkspace' before initialization` in `disconnect-route.test.ts`. Recovery: Refactored to use `vi.hoisted()`. **Prevention:** When creating test files with `vi.mock` factories that reference external variables, always use `vi.hoisted()` from the start.

**bunx vitest rolldown binding error** — `MODULE_NOT_FOUND: rolldown-binding.linux-x64-gnu.node` when running `bunx vitest` for `.tsx` component tests. Recovery: Used `npx vitest` (project-local) instead of `bunx` (fetches latest). **Prevention:** Use `npx vitest` for this project — it resolves the locally installed version. `bunx vitest` fetches the latest version which may have incompatible native bindings.

**Lefthook timeout in worktree** — Pre-commit hook ran the full test suite but exceeded the Bash tool's 2-minute timeout. Recovery: Verified tests/typecheck manually, committed with `LEFTHOOK=0`. **Prevention:** Known lefthook/worktree interaction (documented in AGENTS.md). When lefthook times out, kill stalled processes, verify manually, commit with `LEFTHOOK=0`.

## Tags

category: test-failures
module: System
