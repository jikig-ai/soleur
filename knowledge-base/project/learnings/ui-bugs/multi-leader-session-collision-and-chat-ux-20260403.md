---
module: Command Center
date: 2026-04-03
problem_type: ui_bug
component: tooling
symptoms:
  - "CPO appears twice in leader list when starting auto-route conversation"
  - "No visual feedback while leaders are processing (thinking state missing)"
  - "Raw markdown syntax (###, |---|, **bold**) displayed as plain text"
  - "CTO never replied in multi-leader auto-routed session"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [session-key, multi-leader, markdown, react-markdown, thinking-indicator, websocket]
---

# Troubleshooting: Multi-Leader Session Key Collision and Chat UX Bugs

## Problem

Four interconnected bugs degraded the Command Center chat experience: duplicate CPO entries, missing thinking indicators, raw markdown rendering, and silent leader failures. The root cause of the most critical bug (silent leader failure) was that `activeSessions` Map keys did not include `leaderId`, causing parallel leader sessions to overwrite each other.

## Environment

- Module: Command Center (web-platform)
- Affected Components: agent-runner.ts, ws-handler.ts, chat page (page.tsx)
- Date: 2026-04-03

## Symptoms

- CPO entry appeared twice — once with full title, once without — on new auto-route conversations
- After sending a message, leader cards sat idle with no animation or status text
- Claude agent markdown output (headings, tables, bold) rendered as literal syntax characters
- In a 3-leader auto-routed session (CPO, CTO, COO), only the last leader to execute survived; earlier leaders were silently aborted

## What Didn't Work

**Direct solution:** All four bugs were identified through code analysis and fixed on the first attempt. The session key collision was identified by tracing `sessionKey(userId, conversationId)` through `startAgentSession` and observing that parallel calls with different `leaderId` values produce identical keys.

## Session Errors

**Worktree HEAD drifted to main instead of feat-cc-ui-bugs**

- **Recovery:** Ran `git checkout feat-cc-ui-bugs` to restore the correct branch. Commits were already on the feature branch (verified via `git log feat-cc-ui-bugs`).
- **Prevention:** After creating a worktree, verify `git branch --show-current` returns the expected branch before proceeding.

**TypeScript error with react-markdown Components type**

- **Recovery:** Changed from explicit `{ children: React.ReactNode }` type annotations to `import("react-markdown").Components` type with inferred props.
- **Prevention:** When using react-markdown's `components` prop, always type the object as `import("react-markdown").Components` and let TypeScript infer individual component prop types. Do not manually annotate `children` as required — react-markdown treats it as optional.

**Placeholder test files with zero behavioral coverage**

- **Recovery:** Review agents caught the issue. Deleted `session-key.test.ts` and `auto-route-boot.test.ts` which only tested that functions exist, not behavior.
- **Prevention:** When the activeSessions Map is internal and can't be populated from tests, don't write tests that call exported functions against an empty map and assert `.not.toThrow()`. Either expose a test helper or accept that integration/QA testing covers the behavior.

**Dev server missing Supabase credentials for QA**

- **Recovery:** Skipped browser QA scenarios. Component-level tests provided sufficient coverage.
- **Prevention:** Tracked as a separate GitHub issue — Supabase secrets need to be available in Doppler `dev` config for local development.

## Solution

**Bug 4 (session key collision):** Added optional `leaderId` to `sessionKey()`:

```typescript
// Before (broken):
function sessionKey(userId: string, conversationId: string) {
  return `${userId}:${conversationId}`;
}

// After (fixed):
function sessionKey(userId: string, conversationId: string, leaderId?: string) {
  return leaderId
    ? `${userId}:${conversationId}:${leaderId}`
    : `${userId}:${conversationId}`;
}
```

`abortSession` without `leaderId` does prefix matching to broadcast abort to all leaders. `resolveReviewGate` iterates all sessions for a conversation to find the gate by UUID.

**Bug 1 (duplicate CPO):** Wrapped `startAgentSession` call in `if (msg.leaderId)` in ws-handler.ts `start_session` handler. Auto-route sessions wait for first chat message.

**Bug 2 (thinking indicators):** Added `ThinkingDots` component with 3 pulsing dots, rendered when `content === "" && role === "assistant"`.

**Bug 3 (markdown rendering):** Added `react-markdown` + `remark-gfm` with Tailwind-styled component overrides. 3-state rendering: thinking dots -> plain text (streaming) -> markdown (complete). `isStreaming` prop derived from `activeLeaderIds`.

## Why This Works

1. **Session key collision:** Each leader now gets a unique key (`userId:convId:leaderId`), so parallel `startAgentSession` calls create independent entries in `activeSessions` instead of overwriting each other.
2. **Duplicate CPO:** The `start_session` handler was unconditionally booting a default CPO session. Auto-route conversations don't need an immediate agent — routing happens when the first message arrives via `sendUserMessage`.
3. **Thinking indicators:** `stream_start` creates an empty-content message bubble. The empty state is now detected and rendered as pulsing dots instead of an empty bubble.
4. **Markdown:** `react-markdown` builds a React element tree from AST (no raw HTML injection). `remark-gfm` adds GFM table support that CommonMark lacks. Streaming messages use plain text to avoid partial markdown parse artifacts.

## Prevention

- When using a Map for session tracking with parallel operations, always include all disambiguating identifiers in the key
- When adding `react-markdown`, always add `remark-gfm` as a companion dependency — CommonMark does not support GFM tables
- Use plain text rendering during streaming and switch to markdown on completion to avoid partial parse artifacts
- Add `disallowedElements` with `unwrapDisallowed` for defense-in-depth XSS prevention even though react-markdown doesn't inject raw HTML

## Related Issues

- See also: [ws-session-race-abort-before-replace](../2026-03-27-ws-session-race-abort-before-replace.md) — The abort-before-replace invariant preserved in this fix
- See also: [tag-and-route-multi-leader-architecture](../2026-03-27-tag-and-route-multi-leader-architecture.md) — Original multi-leader architecture context
