# Learning: defensive state clear on useEffect remount

## Problem

After a `key_invalid` WebSocket error, the error card persisted when the user navigated to settings, rotated their key, and returned via browser back. The `useEffect` that sets up the WebSocket connection ran `connect()` on remount but did not clear `lastError` or `disconnectReason`, leaving stale error UI visible.

The root cause involves browser back-forward cache (bfcache): React does not re-run `useState` initializers on bfcache restore — the component tree is restored with all prior state values intact. Next.js App Router soft navigation compounds this by varying between full reload and state-preserving navigation.

## Solution

Add `setLastError(null)` and `setDisconnectReason(undefined)` at the top of the connection setup `useEffect`, before calling `connect()`. This mirrors the existing `reconnect()` callback pattern that already clears both fields:

```typescript
useEffect(() => {
  mountedRef.current = true;
  setLastError(null);             // Clear stale error from prior session
  setDisconnectReason(undefined); // Clear stale disconnect reason
  connect();
  return () => { /* cleanup */ };
}, [connect, conversationId]);
```

## Key Insight

When a `useEffect` manages connection lifecycle (connect/disconnect/reconnect), its setup function should clear all UI state from the previous lifecycle before starting the new one. This is especially important when the effect depends on a route parameter (`conversationId`) — navigating between routes should give a clean slate. The principle: "clear stale state before starting new state" applies to both manual reconnect (user clicks retry) and automatic reconnect (component remounts). If the manual path clears state, the automatic path should too.

## Session Errors

1. **`worktree-manager.sh draft-pr` failed in bare repo worktree** — Recovery: created draft PR manually via `gh pr create`. Prevention: already documented in `2026-03-18-worktree-manager-bare-repo-false-positive.md` — the `require_working_tree()` function needs fixing.

2. **Git commands failed due to `core.bare=true` propagation** — Recovery: used `GIT_DIR`/`GIT_WORK_TREE` env vars. Prevention: already documented in multiple bare repo learnings. The worktree-manager script should set these env vars automatically.

3. **`git add` with wrong relative paths after CWD change** — Recovery: used paths relative to actual CWD. Prevention: always use absolute paths for `git add` when the CWD may have changed (e.g., after running tests from a subdirectory).

## Tags

category: ui-bugs
module: web-platform/ws-client
