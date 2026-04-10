---
title: "useRouter mock instability causes useEffect re-fires in component tests"
category: test-failures
module: web-platform/testing
date: 2026-04-07
tags: [vitest, react, testing-library, useRouter, useEffect, mock-stability]
---

# Learning: useRouter mock instability causes useEffect re-fires

## Problem

Component tests for the dashboard page failed with `TypeError: Cannot read properties of undefined (reading 'then')` in the KB tree `useEffect`. The error occurred because the `fetchMock.mockResolvedValueOnce()` was consumed by the first render's useEffect, and a second useEffect invocation got `undefined`.

The root cause: the `useRouter()` mock created a new object on every call:

```typescript
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),  // new object each render
}));
```

Since `router` was in the useEffect dependency array, React detected a "change" on every render and re-ran the effect. The first run consumed the `mockResolvedValueOnce`, and the second run got `undefined` from the bare `vi.fn()`.

## Solution

Return a stable reference from the mock:

```typescript
const mockPush = vi.fn();
const mockRouter = { push: mockPush };
vi.mock("next/navigation", () => ({
  useRouter: () => mockRouter,  // same object every render
}));
```

This matches the real Next.js behavior where `useRouter()` returns a memoized reference.

## Key Insight

When mocking React hooks that return objects, always return a stable reference (module-level constant). If the mock creates a new object per call, any `useEffect` that depends on the hook's return value will re-fire on every render, consuming `mockResolvedValueOnce` handlers and causing cascading failures.

This applies to any hook mock, not just `useRouter`: `useSearchParams`, `usePathname`, custom hooks returning objects.

## Session Errors

1. **Read tool used bare repo path instead of worktree path** — Recovery: switched to worktree-relative paths. Prevention: when in a worktree, always construct paths from the worktree root, not the bare repo root.

2. **npx vitest used cached global version** — Recovery: ran `npm install` in the worktree. Prevention: always install deps before running tests in a fresh worktree.

3. **cd in Bash tool changed persistent CWD** — Recovery: used absolute paths. Prevention: avoid `cd` in Bash tool; use absolute paths instead.

4. **git add failed with parenthesized directory** — Recovery: used relative path without the prefix. Prevention: quote or escape parentheses in shell paths, or use relative paths from the correct CWD.

5. **useRouter mock instability (this learning's topic)** — Recovery: stable reference pattern. Prevention: always use module-level constants for hook mock return values.

6. **Command Center test regression from adding useOnboarding** — Recovery: added `.single()` and KB tree mock to existing test. Prevention: when adding new hooks to a component, audit all existing test files for that component.

7. **Off-by-one in escape sequence counting** — Recovery: fixed assertion. Prevention: `\n` is 1 character, not 2; count the rendered string, not the source literal.

## Tags

category: test-failures
module: web-platform/testing
