# Learning: RTL waitFor replaces setTimeout for negative assertions; getByText exact match prevents multi-element collisions

## Problem

The `chat-page.test.tsx` tests used `await new Promise((r) => setTimeout(r, 50))` before negative assertions (`expect(fn).not.toHaveBeenCalled()`). This is inherently racy -- 50ms may not be enough for effects to settle, or the timer fires before the component mounts on slow CI runners. Additionally, 3 test scenarios from the plan's acceptance criteria were missing: handleSend independence from sessionConfirmed, no-msg-param baseline, and server error path.

## Solution

1. **Replace setTimeout with waitFor:** Wrap each negative assertion in `await waitFor(() => { expect(mockSendMessage).not.toHaveBeenCalled(); })`. RTL's `waitFor` retries until the assertion passes or times out (default 1000ms), removing the arbitrary delay.

2. **Exact string match for ErrorCard:** Changed `screen.getByText(/rate limited/i)` to `screen.getByText("You've been rate limited.")` (exact string). The regex matched two DOM nodes (the card's heading and its body message), causing RTL's "found multiple elements" error.

3. **Added 3 new test cases** using existing mock patterns: handleSend via userEvent, no-msg-param baseline, and error card + no-send combined assertion.

## Key Insight

For negative assertions in React tests ("X was NOT called after effects settle"), `waitFor` is the correct RTL pattern -- it ensures React's scheduler has flushed pending effects before the assertion runs, without relying on wall-clock timing. When `getByText` matches multiple elements, prefer exact string match or `getByRole` over broadening the regex -- specificity prevents future collisions as the component tree grows.

## Session Errors

1. **npx vitest from worktree root picked up stale cached version** — Running `npx vitest run` from the worktree root failed with `MODULE_NOT_FOUND: rolldown-binding.linux-x64-gnu.node` because npx resolved a stale global cache entry instead of the project's pinned version.
   **Recovery:** Ran vitest from `apps/web-platform/` directory instead (`cd apps/web-platform && npx vitest run`).
   **Prevention:** Always run test commands from the app directory, not the worktree root. The worktree-manager already runs `bun install` post-create, but npx resolution still favors the global cache. Use the project's `npm test` or `cd` into the app directory first.

2. **getByText regex matched multiple elements in ErrorCard** — `screen.getByText(/rate limited/i)` matched both the ErrorCard title ("Rate Limited") and the error message ("You've been rate limited."), throwing "Found multiple elements."
   **Recovery:** Used exact string match `screen.getByText("You've been rate limited.")`.
   **Prevention:** Prefer `getByRole` with `name` option as default query strategy. When using `getByText`, use exact strings or scope with `within()` when the component renders the same text in multiple locations.

3. **cd state lost between Bash tool calls** — After `cd apps/web-platform`, the next Bash call reverted to the worktree root. Required re-cd'ing or using absolute paths.
   **Recovery:** Used absolute paths or re-cd in each Bash call.
   **Prevention:** This is expected Bash tool behavior (each call is a new shell). Always use absolute paths or chain commands with `&&`.

## Related Documentation

- `knowledge-base/project/learnings/technical-debt/2026-03-03-timer-based-async-settling-in-bridge-tests.md` — Same setTimeout anti-pattern in telegram-bridge tests
- `knowledge-base/project/learnings/runtime-errors/2026-04-03-useeffect-race-optimistic-flag-vs-server-ack.md` — useEffect race condition that created the sessionConfirmed gate being tested
- #1596 — Review finding: negative waitFor assertions pass without verifying effect cycle

## Tags

category: test-failures
module: web-platform
