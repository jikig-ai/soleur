# Learning: happy-dom getAllByRole("img") fails for decorative images

## Problem

When writing component tests with vitest + happy-dom + @testing-library/react, `screen.getAllByRole("img", { hidden: true })` throws "Unable to find an accessible element with the role 'img'" for `<img alt="">` elements. The `alt=""` attribute marks the image as decorative (presentational), and happy-dom does not include presentational elements in role queries even with the `hidden: true` option.

This differs from jsdom behavior where `hidden: true` includes all elements regardless of their implicit role.

## Solution

Use `container.querySelector` with CSS attribute selectors instead of role-based queries for decorative images:

```tsx
const { container } = render(<Component />);
const img = container.querySelector<HTMLImageElement>("img[src*='logo']");
expect(img).not.toBeNull();
expect(img).toHaveAttribute("alt", "");
```

For non-decorative images (with meaningful `alt` text), `screen.getByRole("img")` works fine in happy-dom.

## Key Insight

In happy-dom, decorative images (`alt=""`) are invisible to `getAllByRole("img")` even with `hidden: true`. Use `container.querySelector` for decorative images and reserve role-based queries for semantic images. This is a happy-dom-specific limitation — jsdom handles this differently.

## Session Errors

1. **happy-dom `getAllByRole("img")` incompatibility with `alt=""` images** — Recovery: switched to `container.querySelector` approach. **Prevention:** When writing tests for decorative images (`alt=""`), start with `container.querySelector` instead of `getAllByRole("img")`.

2. **`git add` from wrong CWD** — Ran `git add` without the worktree root as CWD. Recovery: re-ran from correct directory. **Prevention:** Always use absolute paths or verify CWD before `git add` in worktrees.

3. **Dev server startup failure (missing SUPABASE_URL)** — QA auto-started dev server but Doppler dev config didn't provide SUPABASE_URL to the worktree environment. Recovery: skipped browser QA; component tests covered all scenarios. **Prevention:** QA skill should check for required env vars before attempting server startup, or fall back gracefully with a clearer message.

## Tags
category: test-failures
module: web-platform
