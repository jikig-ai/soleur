---
status: pending
priority: p3
issue_id: "1289"
tags: [code-review, architecture, quality]
---

# Extract @-mention orchestration to custom hook

## Problem Statement

Dashboard page and chat page duplicate identical @-mention state management: `atQuery`, `atVisible`, `atPosition`, `insertRef`, and 3-4 handler functions. Changes to @-mention behavior require parallel edits in both files.

## Findings

- `dashboard/page.tsx` lines 36-83: 3 state hooks + insertRef + 4 useCallback handlers
- `chat/[conversationId]/page.tsx` lines 33-35: same 3 state hooks + insertRef + inline handlers
- The `insertRef` pattern (imperative ref-as-callback) inverts React data flow

## Proposed Solutions

1. **Custom hook `useAtMention()`** — returns all state + handlers. Both pages consume the hook.
2. **Composite component `ChatInputWithMentions`** — owns all @-mention internals. Parents only see `onSend` + `disabled`.

## Technical Details

- Affected files: `dashboard/page.tsx`, `chat/[conversationId]/page.tsx`, `chat-input.tsx`
- Estimated effort: Small
