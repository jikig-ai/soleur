---
module: Web Platform
date: 2026-04-10
problem_type: integration_issue
component: testing_framework
symptoms:
  - "28 test failures: useTeamNames must be used within a TeamNamesProvider"
  - "esbuild parse error: Expected '>' but found 'value' on <Context value={}>"
  - "esbuild transform error: JSX in .ts file not processed"
  - "getByText('CMO') found multiple elements after badge text change"
root_cause: missing_validation
resolution_type: test_fix
severity: medium
tags: [react-context, vitest, esbuild, testing-library, team-names]
---

# Troubleshooting: Adding React Context Provider Breaks Existing Tests

## Problem

Adding a `useTeamNames()` context hook to the ChatPage component caused 28 existing tests to fail with "must be used within a TeamNamesProvider". Additional issues arose from esbuild/vitest incompatibilities with React 19 features and JSX file extensions.

## Environment

- Module: Web Platform (apps/web-platform)
- Framework: Next.js 15 + React 19
- Test runner: Vitest 3.2.4 with happy-dom
- Date: 2026-04-10

## Symptoms

- 28 tests in chat-page.test.tsx and error-states.test.tsx fail with context error
- `<TeamNamesContext value={...}>` fails esbuild parse (React 19 shorthand not supported)
- hooks/use-team-names.ts with JSX refused by esbuild (wrong file extension)
- Badge text change from 2-char to 3-char creates duplicate text in at-mention tests

## What Didn't Work

**Attempted Solution 1:** Using React 19 `<Context value>` shorthand
- **Why it failed:** Vitest uses esbuild for transforms, which does not support the React 19 `<Context value>` shorthand syntax even with `jsx: "automatic"` configured.

## Session Errors

**npx vitest stale cache (rolldown binding MODULE_NOT_FOUND)**
- **Recovery:** Ran `npm install` in the worktree to install local vitest
- **Prevention:** In worktrees, always run `npm install` before using vitest; never rely on npx global cache

**JSX in .ts file extension**
- **Recovery:** Renamed use-team-names.ts to use-team-names.tsx
- **Prevention:** Always use .tsx extension when creating files that contain JSX, even if the primary export is a hook

**Badge text change broke test selectors**
- **Recovery:** Updated tests to use `getAllByRole("option")` instead of `getByText("CMO")`
- **Prevention:** When changing display text in components, grep test files for affected string literals before committing

**28 tests missing context provider**
- **Recovery:** Added `vi.mock("@/hooks/use-team-names")` to affected test files
- **Prevention:** When adding a context hook to a widely-tested component, search for all test files that render it: `grep -r "ChatPage\|import.*page" test/`

**TypeScript discriminated union narrowing in tests**
- **Recovery:** Added `errorOf()` helper that narrows the union before accessing `.error`
- **Prevention:** Use narrowing helpers for discriminated union error fields in test files

**React 19 Context shorthand incompatible with esbuild**
- **Recovery:** Switched to `<Context.Provider value>` pattern
- **Prevention:** Use `.Provider` pattern in vitest-processed files until esbuild supports React 19 shorthand

## Solution

Three-part fix:

**1. File extension and JSX syntax:**
```tsx
// Use .tsx extension, not .ts, for files with JSX
// Use .Provider pattern, not React 19 <Context value> shorthand
<TeamNamesContext.Provider value={{...}}>
  {children}
</TeamNamesContext.Provider>
```

**2. Mock the context hook in existing tests:**
```typescript
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => ({
    names: {},
    getDisplayName: (id: string) => id.toUpperCase(),
    getBadgeLabel: (id: string) => id.toUpperCase().slice(0, 3),
    // ... other fields with defaults
  }),
  TeamNamesProvider: ({ children }) => children,
}));
```

**3. Use resilient test selectors:**
```typescript
// Before: breaks when badge adds duplicate text
expect(screen.getByText("CMO")).toBeInTheDocument();

// After: tolerates multiple matching elements
expect(screen.getAllByText("CMO").length).toBeGreaterThanOrEqual(1);
// Or use role-based selectors
const options = screen.getAllByRole("option");
```

## Why This Works

1. **esbuild limitation:** Vitest delegates JSX transformation to esbuild, which only processes `.tsx`/`.jsx` files and does not implement React 19's `<Context value>` shorthand. The `.Provider` pattern is universal.
2. **Context boundary:** React hooks that call `useContext` throw when rendered outside their Provider. Tests that rendered ChatPage directly (without the dashboard layout) never had a provider. Mocking the hook at the module level avoids the provider dependency entirely.
3. **Text duplication:** When a badge shows the same text as a label (both "CMO"), `getByText` finds multiple elements and throws. Role-based or count-based queries are more resilient to display changes.

## Prevention

- When adding a React context hook to a component, immediately search for all test files that render that component and add a mock
- Always use `.tsx` for files containing JSX, even if primarily exporting hooks
- Use `<Context.Provider>` not `<Context value>` in vitest-processed code
- Prefer `getAllByRole` or structural selectors over `getByText` for elements that may have duplicate text content

## Related Issues

No related issues documented yet.
