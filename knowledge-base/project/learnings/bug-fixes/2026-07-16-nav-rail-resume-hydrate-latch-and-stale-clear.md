# Nav-rail position resume: hydrate latch + stale clear (#4826)

## Context
Implementing RQ4 (sessionStorage last-open KB path / chat id / expanded / scrollTop).
Concierge previously died mid one-shot on this issue; product scope reopened after
infra PRs had reused the issue number.

## Session errors / review findings

1. **One-shot seed latches before workspaceId** — `expandedSeededRef` / `restoredRef`
   set true on first effect tick when `readExpanded()`/`readScrollTop()` return empty
   because `workspaceId` is still null. When active-repo later settles, restore never
   runs. **Fix:** only latch after `workspaceId` is known.

2. **Stale chat re-persists** — storing a UUID then landing on a deleted conversation
   re-writes the same id from pathname. AC10 needs a probe + `clearChatId` +
   `router.replace("/dashboard/chat/new")` on the conversation page, not only on bare
   index when the key is missing.

3. **Document 404 ≠ tree not-found** — tree SWR `"not-found"` is workspace/repo
   missing. Per-file 404 is `/api/kb/content` on `[...path]`. Clear path + replace to
   section root there so the pathname persist effect cannot rewrite the bad path.

4. **Unbounded scroll restore rAF** — wait for overflow with a frame cap (20), not
   infinite rAF.

## Pattern
Any "restore once from sessionStorage" effect that gates on workspace-scoped keys
must treat **workspace not ready** as "not yet", not "nothing to restore".
