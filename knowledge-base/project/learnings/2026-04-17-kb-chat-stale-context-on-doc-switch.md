---
title: "KB chat panel carries stale conversation when switching documents"
date: 2026-04-17
category: ui-bugs
module: apps/web-platform/kb
tags: [kb, chat, react, state, sessionStorage, next-navigation]
---

# KB chat panel carries stale conversation when switching documents

## Problem

In the Knowledge Base UI, when a user had the chat panel open on document A
and then clicked document B in the KB tree, the chat panel's header updated
to document B's filename (because `contextPath` is derived reactively from
`usePathname()`) but the conversation content stayed mounted from
document A. Result: user sees document B but is still reading/talking to
document A's Desi (CPO) thread.

## Root Cause

`apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` persists
`sidebarOpen` across navigations via `sessionStorage` (key
`kb.chat.sidebarOpen`). The panel's visibility gate is:

```ts
const showChat = kbChatFlag && !!contextPath && sidebarOpen;
```

When `contextPath` changes, `showChat` stays true (both `!!contextPath` and
`sidebarOpen` remain truthy), so the chat `<Panel>` is NOT unmounted. The
`ChatSurface` inside uses `conversationId="new"` with `resumeByContextPath`,
but its internal effects don't force a clean re-init on prop change for the
new conversation — so the prior thread remains visible while the header
(a plain derived `filename`) updates in place.

## Solution

Close the chat panel whenever the user navigates to a different document.
The `<Panel>` unmounts, and re-opening via "Continue thread" mounts a fresh
`ChatSurface` against the new document's conversation.

```tsx
// layout.tsx
const prevContextPathRef = useRef<string | null>(contextPath);
useEffect(() => {
  if (prevContextPathRef.current === contextPath) return;
  prevContextPathRef.current = contextPath;
  closeSidebar();
}, [contextPath, closeSidebar]);
```

Ref-based prev-value comparison skips the initial mount so the sessionStorage
restore still works on page reload.

## Key Insight

A React component tree can be "partially stale": some props (computed each
render from a reactive source) reflect current state, while children rooted
at a stable parent retain their own internal state. When a feature is bound
to a URL-derived key, the cheapest correctness guarantee is to unmount on
key change rather than propagating reset logic through N layers of children.

## Prevention

When a sidebar/panel is bound to a URL-derived identifier, verify the panel
unmounts (not just re-renders) when that identifier changes. Checklist for
URL-bound panels/overlays:

- Does the gating boolean drop to false when the URL key changes?
- Or, is the child keyed (`<Child key={urlKey} />`) so React remounts it?
- Or, does every stateful descendant re-initialize on prop change?

If none of the above, the panel will carry stale state across navigations.

## Session Errors

- **Test mock for `next/navigation` omitted `useSearchParams`** — symptom was
  an empty test DOM after `rerender` (a descendant component threw
  "No `useSearchParams` export is defined on the `next/navigation` mock").
  The error only surfaced post-rerender because the descendant wasn't
  exercised until a second render pass reached it.
  **Recovery:** added `useSearchParams: () => new URLSearchParams()` to the
  `vi.mock("next/navigation", ...)` block.
  **Prevention:** when mocking `next/navigation` for any component that
  indirectly mounts chat/form surfaces, stub `useSearchParams` alongside
  `useRouter` and `usePathname` — all three are common call sites.

## References

- PR: (this commit)
- Related file: `apps/web-platform/components/chat/kb-chat-content.tsx`
- Test: `apps/web-platform/test/kb-layout-chat-close-on-switch.test.tsx`
