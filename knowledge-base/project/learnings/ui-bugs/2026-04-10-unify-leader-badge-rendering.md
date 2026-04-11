---
title: Unify leader badge rendering across all views
date: 2026-04-10
category: ui-bugs
module: web-platform/dashboard
tags: [badge, leader, visual-consistency, component-reuse]
---

# Learning: Unify leader badge rendering across all views

## Problem

After PR #1900 replaced text-based leader badges with the Soleur logo mark in the conversation list, two other views still rendered colored-text abbreviations (CTO, CMO, etc.):

- Chat page `MessageBubble` used `LEADER_BG_COLORS[leaderId]` with `badgeText` for the leader avatar
- Dashboard foundation cards and `LeaderStrip` used `LEADER_BG_COLORS[leaderId]` with `leaderId.toUpperCase()`

This created inconsistent leader representation across views.

## Solution

Replaced all colored-text badge renderings with the same Soleur logo mark `<img>` pattern used in `conversation-row.tsx`:

```tsx
<span className="flex h-7 w-7 items-center justify-center overflow-hidden rounded-md"
      aria-label={`Soleur ${leaderId.toUpperCase()}`}>
  <img src="/icons/soleur-logo-mark.png" alt="" width={28} height={28}
       className="h-full w-full object-cover" />
</span>
```

Removed unused `LEADER_BG_COLORS` imports and the `getBadgeLabel` prop chain from `MessageBubble`.

## Key Insight

When introducing a new visual pattern in one view, file a tracking issue for all other views that render the same concept. The PR #1900 test plan explicitly noted "No changes to chat page message bubbles (out of scope)" -- this was correct scoping, but the follow-up issue (#1903) was essential to prevent indefinite drift.

## Session Errors

1. **`npx tsc --noEmit` failed** -- TypeScript not installed at app level. Recovery: ran `npm install` first. Prevention: check `node_modules/.bin/tsc` exists before invoking.
2. **`npx next build --typecheck` unknown option** -- Next.js 16 does not support `--typecheck`. Recovery: used local `tsc` binary. Prevention: use `node_modules/.bin/tsc --noEmit` directly.
3. **Stale line numbers from issue** -- Issue referenced lines 373, 327, 543 but actual files were 225 and 46 lines. Recovery: read full files. Prevention: always read files before trusting issue-provided line numbers.
4. **Worktree behind origin/main** -- Initial grep found no badge pattern because PR #1900 was not in the worktree. Recovery: verified via `git fetch` and confirmed worktree was actually up to date after merge. Prevention: run `git fetch origin main` and check divergence at session start.

## Tags

category: ui-bugs
module: web-platform/dashboard
