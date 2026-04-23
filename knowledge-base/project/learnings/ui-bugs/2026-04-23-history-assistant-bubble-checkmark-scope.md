# Learning: History assistant bubbles incorrectly rendered completion checkmark

## Problem

PR #2209 (fixing #2139) set `state: "done"` on all assistant messages loaded from DB history
in `fetchConversationHistory()` (`apps/web-platform/lib/ws-client.ts`). `MessageBubble`
renders a completion checkmark badge whenever `isDone && role === "assistant"`. Because
`isDone = messageState === "done"`, every historical assistant bubble showed the checkmark
when reopening a conversation — a badge that should only appear on messages that completed
via a WS stream event in the current session.

## Solution

Removed the `state: "done"` assignment from history messages in `ws-client.ts`. History
messages now carry `state: undefined`. The `renderBubbleContent` `default` switch case
handles `undefined` identically to `case "done"` for history messages (both render
`<MarkdownRenderer content={content} />`), since DB-loaded history has no `toolsUsed` data.
The checkmark is now only set by WS stream completion events during the live session.

Single file changed: `apps/web-platform/lib/ws-client.ts`.

## Key Insight

State assignments made to simplify conditional logic (eliminating fallback heuristics) can
introduce unintended UI side effects when other components key off that same state field.
Before assigning a sentinel value to all records of a type, grep every consumer of that
field for conditional rendering or badge logic. The fix direction is to narrow state
assignment to the lifecycle moment that actually owns the state transition (stream completion),
not the data-loading path.

## Session Errors

1. `worktree-manager.sh --yes create` failed with `fatal: this operation must be run in a work tree`.
   - Prevention: `worktree-manager.sh` must validate it is invoked from a valid git working
     tree or bare repo root before calling `git worktree add`. Fall back to `git -C <bare-root>`
     invocation automatically.

2. Worktree node_modules absent — `npm ci` required before tests could run.
   - Prevention: `worktree-manager.sh create` should run `npm ci` (or detect a lockfile and
     warn) as a post-create hook so the worktree is immediately runnable.

## Tags

category: ui-bug
module: apps/web-platform/lib/ws-client.ts, apps/web-platform/components/message-bubble.tsx
issues: #2139, #2209, #2218
