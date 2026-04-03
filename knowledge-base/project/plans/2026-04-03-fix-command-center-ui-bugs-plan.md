---
title: "fix: Command Center UI bugs (duplicate CPO, missing thinking indicators, raw markdown, silent leader failures)"
type: fix
date: 2026-04-03
---

# fix: Command Center UI Bugs

## Overview

Four bugs in the Command Center web UI degrade the chat experience: a duplicate CPO entry on new conversations, no visual feedback while leaders are thinking, raw markdown displayed as plain text, and a silent failure where routed leaders (CTO) never reply. Root cause analysis reveals two backend bugs and two frontend gaps.

## Problem Statement

1. **CPO appears twice** when starting a new conversation. The first entry shows "CPO Chief Product Officer" (full title), the second shows just "CPO" (name only). This happens because `start_session` unconditionally boots a default CPO agent session (via `startAgentSession` with `leaderId=undefined`, which defaults to `"cpo"` at `agent-runner.ts:283`), and then when the user's actual message arrives via `sendUserMessage`, auto-routing dispatches to CPO again -- producing two separate `stream_start` events for the same leader.

2. **No thinking indicators.** After sending a message, the leader cards sit idle with no animation or status text. The only visual is the initial "Routing to the right experts..." pulse that appears during classification. Once `stream_start` fires but before the first `stream` token arrives (which can take 5-15 seconds for complex prompts), users see nothing. There is no per-leader "thinking" state.

3. **Raw markdown displayed as plain text.** Claude agents produce markdown output (headings, tables, bold, lists, code blocks). The `MessageBubble` component renders content via `<p className="whitespace-pre-wrap">{content}</p>` (chat page line 327) -- no markdown parsing whatsoever. Users see literal `###`, `|---|`, `**bold**` syntax.

4. **CTO never replied** in a multi-leader auto-routed session. Root cause: `dispatchToLeaders` calls `startAgentSession` for each leader in parallel via `Promise.allSettled`. However, `startAgentSession` uses `sessionKey(userId, conversationId)` -- which does NOT include `leaderId` -- to track sessions in `activeSessions`. When multiple leaders are dispatched concurrently, each call to `startAgentSession` at line 267 aborts the previous leader's session (same key) and overwrites the `activeSessions` entry at line 276. Only the last leader to execute line 276 survives; earlier leaders are silently aborted. The `Promise.allSettled` catch at line 631 logs the error but the user never sees an explanation.

## Proposed Solution

### Bug 1: Remove Default CPO Boot on start_session

**Root cause:** `startAgentSession` is called from the `start_session` WS handler with `leaderId=undefined`, which defaults to CPO. This is unnecessary for auto-routed conversations -- the actual agent sessions should only start when the user's first message triggers `sendUserMessage` -> `routeMessage` -> `dispatchToLeaders`.

**Fix:** In `ws-handler.ts`, the `start_session` handler should NOT call `startAgentSession` when `msg.leaderId` is undefined. It should only create the conversation row, send `session_started`, and wait for the first `chat` message to trigger routing.

**Files:**

- `apps/web-platform/server/ws-handler.ts` -- conditional: skip `startAgentSession` when `leaderId` is falsy
- `apps/web-platform/test/chat-page.test.tsx` -- verify no premature CPO stream on auto-route sessions

### Bug 2: Add Per-Leader Thinking Indicators

**Problem:** Between `stream_start` (leader is assigned) and the first `stream` token, the UI shows nothing.

**Fix:** When `stream_start` fires for a leader, create the message bubble immediately (already done in `ws-client.ts` line 155) but add a thinking state. The `MessageBubble` component should show a pulsing animation when `content` is empty -- indicating the leader is formulating a response.

**Files:**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- update `MessageBubble` to show a thinking indicator (pulsing dots or shimmer) when `content` is empty string and `role === "assistant"`
- No backend changes needed -- the empty-content bubble from `stream_start` already exists in state

### Bug 3: Render Markdown in Message Bubbles

**Problem:** The `<p>` tag renders content as plain text.

**Fix:** Add `react-markdown` dependency and replace the raw `<p>{content}</p>` with a `<ReactMarkdown>` component. Apply Tailwind prose styling for headings, tables, code blocks, lists, and bold/italic.

**Files:**

- `apps/web-platform/package.json` -- add `react-markdown` dependency
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- replace `<p className="whitespace-pre-wrap">{content}</p>` with `<ReactMarkdown>` component in `MessageBubble`
- `apps/web-platform/bun.lock` -- regenerated after install
- `apps/web-platform/package-lock.json` -- regenerated after install (Dockerfile uses `npm ci`)

**Styling approach:** Use Tailwind's `prose` classes from `@tailwindcss/typography` or hand-roll minimal styles in the component. Given the project's CSS layer approach (`@layer` cascade), hand-rolling within the component's className is simpler and avoids adding another dependency. Alternatively, `react-markdown` with custom component overrides (mapping `h1` -> styled div, `table` -> styled table, etc.) gives full control without a typography plugin.

**Security:** `react-markdown` builds a React element tree from the AST -- it does NOT inject raw HTML. Plugins that allow raw HTML (e.g., `rehype-raw`) should NOT be enabled. The `disallowedElements` prop should exclude `script`, `iframe`, `form`, and other dangerous HTML elements as defense-in-depth.

### Bug 4: Fix Multi-Leader Session Key Collision

**Root cause:** `sessionKey(userId, conversationId)` does not include `leaderId`. Parallel leaders overwrite each other in `activeSessions`.

**Fix:** Include `leaderId` in the session key for multi-leader dispatch. When `dispatchToLeaders` calls `startAgentSession` for each leader, each gets its own `activeSessions` entry that cannot collide with siblings.

**Files:**

- `apps/web-platform/server/agent-runner.ts`:
  - Change `sessionKey` function to accept optional `leaderId` parameter: `return leaderId ? \`\${userId}:\${conversationId}:\${leaderId}\` : \`\${userId}:\${conversationId}\``
  - Pass `leaderId` through to `sessionKey` in `startAgentSession`
  - Update `abortSession` to handle both keyed and un-keyed lookups (single-leader sessions don't include leaderId)
  - Update `activeSessions.delete` in the `finally` block to use the correct key
- `apps/web-platform/test/domain-router.test.ts` -- add test for parallel dispatch session isolation

**Important consideration:** The `abortActiveSession` function in `ws-handler.ts` calls `abortSession(userId, oldConvId, "superseded")`. When aborting all leader sessions for a conversation (e.g., user starts a new conversation), it needs to abort ALL leader sessions for that conversation. This means `abortSession` should iterate over `activeSessions` entries matching the `userId:conversationId:*` prefix pattern when `leaderId` is not provided.

## Technical Considerations

### Architecture impacts

- Bug 4 fix changes the session tracking key format, which is an internal server data structure with no persistence or external API surface. The change is backward-compatible because single-leader sessions can continue using the 2-part key.
- Bug 3 adds a new dependency (`react-markdown`). Per constitution: "Never add a dependency for something an LLM can generate inline." However, markdown-to-HTML conversion is a complex parsing problem with edge cases (nested lists, table alignment, code block escaping) where a tested library is the correct choice. The alternative -- hand-rolling a regex-based parser -- would be fragile and security-risky.

### Performance implications

- `react-markdown` parses on every render. For streaming messages that update frequently (each `stream` token triggers a re-render), this could be expensive. **Mitigation:** Wrap the markdown renderer in `React.memo` keyed by content length checkpoints (e.g., only re-parse every 100 characters during streaming, or use `useDeferredValue`). Alternatively, render plain text during streaming and only parse markdown on `stream_end`.
- A practical alternative: render markdown only for completed messages (after `stream_end`), and use `whitespace-pre-wrap` during streaming. This avoids the performance hit entirely while still solving the core UX complaint.

### Dependency management

- Both `bun.lock` and `package-lock.json` must be regenerated after adding `react-markdown` (Dockerfile uses `npm ci`).

## Acceptance Criteria

- [ ] Starting a new conversation (auto-route, no @-mention) does NOT produce a premature CPO greeting
- [ ] After routing, each leader shows a thinking animation before their first token arrives
- [ ] Markdown headings, bold, italic, lists, tables, and code blocks render correctly in message bubbles
- [ ] Multi-leader auto-routed sessions (e.g., CPO + CTO + COO) all produce responses -- no silent failures
- [ ] Existing single-leader sessions (@-mention directed) continue working correctly
- [ ] Existing `resume_session` flow continues working correctly
- [ ] No XSS vulnerabilities from markdown rendering (no raw HTML passthrough)

## Test Scenarios

### Bug 1: Duplicate CPO

- Given a new auto-route conversation (no @-mention), when the session starts, then no `stream_start` fires until the user's first message is classified and routed
- Given a directed @CPO conversation, when the session starts, then CPO boots normally with a greeting

### Bug 2: Thinking Indicators

- Given a `stream_start` event for a leader, when no `stream` tokens have arrived yet, then the message bubble shows a pulsing/shimmer animation
- Given a `stream_start` followed by a `stream` token, when content is non-empty, then the thinking indicator disappears and content renders

### Bug 3: Markdown Rendering

- Given an assistant message containing `### Heading`, when rendered, then it displays as a styled heading (not raw `###` text)
- Given an assistant message containing a markdown table, when rendered, then it displays as an HTML table with borders
- Given an assistant message containing `**bold**`, when rendered, then it displays as bold text
- Given an assistant message containing a fenced code block, when rendered, then it displays with code styling
- Given an assistant message containing `<script>alert('xss')</script>`, when rendered, then the script tag is stripped (not executed)

### Bug 4: Multi-Leader Session Isolation

- Given auto-routing dispatches to CPO, CTO, and COO in parallel, when all three `startAgentSession` calls execute, then all three sessions run to completion (no silent aborts)
- Given a running multi-leader session, when the user starts a new conversation, then all leader sessions for the old conversation are aborted
- Given a single-leader @-mention session, when `abortSession` is called, then it correctly aborts the session (backward compatibility)

## Implementation Phases

### Phase 1: Fix session key collision (Bug 4) -- Backend

This is the highest-priority fix because it causes complete data loss (leader responses never delivered).

1. Update `sessionKey` to include optional `leaderId`
2. Update `startAgentSession` to pass `leaderId` to `sessionKey`
3. Update `abortSession` to handle prefix-matching for conversation-level aborts
4. Update `activeSessions.delete` in finally block
5. Add test for parallel session isolation

### Phase 2: Remove default CPO boot (Bug 1) -- Backend

1. In `ws-handler.ts` `start_session` handler, skip `startAgentSession` when `msg.leaderId` is undefined
2. Verify `session_started` is still sent (so the client knows the WS session is ready)
3. Update test to verify no premature stream

### Phase 3: Add thinking indicators (Bug 2) -- Frontend

1. Update `MessageBubble` to detect empty-content assistant messages
2. Add pulsing dots animation (consistent with existing "Routing to the right experts..." style)
3. Thinking indicator disappears when first content token arrives (natural -- `content` becomes non-empty)

### Phase 4: Markdown rendering (Bug 3) -- Frontend

1. Install `react-markdown` in `apps/web-platform`
2. Regenerate both lockfiles
3. Replace `<p>{content}</p>` with markdown renderer in `MessageBubble`
4. Add minimal Tailwind styling for markdown elements
5. Configure security: disable raw HTML passthrough, block dangerous elements
6. Optimization: render plain text during active streaming, markdown after `stream_end`

## Alternative Approaches Considered

| Approach | Considered For | Why Rejected |
|----------|---------------|--------------|
| `marked` + raw HTML injection | Bug 3 markdown | XSS risk; `react-markdown` builds React elements safely |
| Custom regex markdown parser | Bug 3 markdown | Fragile, incomplete, security risk -- markdown is complex |
| `@tailwindcss/typography` plugin | Bug 3 styling | Adds a dependency for minimal benefit; inline Tailwind classes suffice |
| Per-leader `Map<string, AbortController>` separate from activeSessions | Bug 4 sessions | Over-engineering; extending the existing key format is simpler |
| Remove multi-leader entirely, route to single best leader | Bug 4 sessions | Feature regression; multi-leader is the correct UX for cross-domain questions |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- these are bug fixes to existing UI and backend code with no product strategy, marketing, legal, or operational implications.

## References

- `apps/web-platform/server/agent-runner.ts` -- multi-leader dispatch, session tracking
- `apps/web-platform/server/ws-handler.ts` -- WebSocket message routing, start_session handler
- `apps/web-platform/lib/ws-client.ts` -- client-side WebSocket hook, stream multiplexing
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- chat UI, MessageBubble component
- `apps/web-platform/server/domain-leaders.ts` -- leader definitions
- `knowledge-base/project/learnings/2026-03-27-tag-and-route-multi-leader-architecture.md` -- original architecture context
