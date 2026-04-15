# Learning: Testing next/dynamic components in vitest with happy-dom

## Problem

When testing a component that uses `next/dynamic` with `ssr: false`, the dynamically imported component never renders in vitest/happy-dom. The naive mock approach using `.then()` to resolve the component fails because Promise callbacks are asynchronous — the component is still `null` when React first renders.

## Solution

Mock `next/dynamic` using `React.lazy` + `Suspense`, which integrates with React's rendering scheduler:

```tsx
vi.mock("next/dynamic", () => ({
  __esModule: true,
  default: (loader: () => Promise<any>, _opts?: any) => {
    const LazyComponent = React.lazy(() =>
      loader().then((mod: any) => ({
        default:
          typeof mod === "function"
            ? mod
            : mod.default || (Object.values(mod)[0] as any),
      })),
    );
    return function MockDynamic(props: any) {
      return (
        <React.Suspense fallback={null}>
          <LazyComponent {...props} />
        </React.Suspense>
      );
    };
  },
}));
```

All tests that render the dynamically imported component must be `async` and use `waitFor` to allow the lazy component to resolve.

## Key Insight

`next/dynamic` with `ssr: false` is effectively `React.lazy` + `Suspense` under the hood. Mocking it the same way ensures the test environment matches production behavior. The critical detail: `.then()` callbacks never fire synchronously, so any mock that relies on synchronous Promise resolution will render `null`.

This is the first `next/dynamic` usage in the codebase. The pattern should be reused for future dynamic imports (e.g., heavy chart libraries, code editors).

## Session Errors

1. **Phantom worktree creation** — First `worktree-manager.sh feature` call printed success but directory didn't exist; second call succeeded. Prevention: Verify worktree exists with `ls -d` after creation before proceeding.
2. **Bun lockfile location assumption** — Plan said "bun.lock at repo root" but it lives in `apps/web-platform/`. Initial `bun install` at root did nothing. Prevention: Always check lockfile location with `ls` before running package manager commands.

## Tags

category: test-failures
module: apps/web-platform
