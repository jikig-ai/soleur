---
title: "fix: Command Center UI bugs (duplicate CPO, missing thinking indicators, raw markdown, silent leader failures)"
type: fix
date: 2026-04-03
deepened: 2026-04-03
---

# fix: Command Center UI Bugs

## Enhancement Summary

**Deepened on:** 2026-04-03
**Sections enhanced:** 6 (Proposed Solution x4, Technical Considerations, Implementation Phases)
**Research sources:** Context7 react-markdown docs, 4 institutional learnings, codebase analysis

### Key Improvements

1. **Bug 4 needs `remark-gfm` for tables** -- CommonMark (react-markdown default) does not support GFM tables. Without `remark-gfm`, table syntax renders as pipe-delimited text, not HTML tables.
2. **Streaming markdown optimization validated by prior art** -- Telegram bridge learning (2026-03-02) confirms "plain text during streaming, HTML on final edit" pattern prevents partial rendering artifacts.
3. **Session key race condition has a documented precursor** -- The `abortActiveSession` pattern from learning 2026-03-27 (ws-session-race) must be preserved when refactoring session keys. The abort-before-replace invariant is critical.
4. **`react-markdown` v10 is ESM-only** -- compatible with the project's `"type": "module"` config, but requires `remark-gfm` as a separate dependency for table support.
5. **Review gate cleanup must be updated** -- `abortSession` prefix-matching for multi-leader abort must also clean up `reviewGateResolvers` for each aborted session (learning 2026-03-20).

### New Considerations Discovered

- `remark-gfm` is a required second dependency (tables, strikethrough, task lists, autolinks)
- `react-markdown` already blocks `javascript:` URLs via `defaultUrlTransform` -- no extra sanitization needed for links
- The `components` prop pattern enables Tailwind styling without `@tailwindcss/typography`
- `MessageBubble` needs an `isStreaming` prop to toggle between plain text (streaming) and markdown (complete)

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

#### Research Insights: Conditional Agent Boot

**Concrete diff for ws-handler.ts `start_session` case:**

```typescript
// Before (broken): always boots agent, defaults to CPO for auto-route
startAgentSession(userId, conversationId, msg.leaderId, undefined, undefined, msg.context).catch(...);

// After (fixed): only boot agent for directed sessions
if (msg.leaderId) {
  startAgentSession(userId, conversationId, msg.leaderId, undefined, undefined, msg.context).catch(...);
}
// Auto-route sessions wait for first chat message -> sendUserMessage -> routeMessage
```

**Edge case -- directed sessions must still boot:** When `msg.leaderId` is provided (user typed `@CPO`), the agent should boot immediately with the default greeting. The fix must preserve this path. The `session_started` message is always sent (it confirms the conversation was created, not that the agent booted).

### Bug 2: Add Per-Leader Thinking Indicators

**Problem:** Between `stream_start` (leader is assigned) and the first `stream` token, the UI shows nothing.

**Fix:** When `stream_start` fires for a leader, create the message bubble immediately (already done in `ws-client.ts` line 155) but add a thinking state. The `MessageBubble` component should show a pulsing animation when `content` is empty -- indicating the leader is formulating a response.

**Files:**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- update `MessageBubble` to show a thinking indicator (pulsing dots or shimmer) when `content` is empty string and `role === "assistant"`
- No backend changes needed -- the empty-content bubble from `stream_start` already exists in state

#### Research Insights: Thinking Indicator Pattern

**Concrete implementation** -- three pulsing dots with staggered animation delays, matching the existing amber-500 color scheme from the "Routing to the right experts..." indicator:

```tsx
function ThinkingDots() {
  return (
    <div className="flex items-center gap-1.5 py-1">
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "0ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "150ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "300ms" }} />
    </div>
  );
}
```

**Integration into MessageBubble:** Replace the content rendering with a conditional:

```tsx
{content === "" && role === "assistant" ? (
  <ThinkingDots />
) : isStreaming ? (
  <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{content}</p>
) : (
  <MarkdownContent content={content} />
)}
```

**UX considerations:**

- Thinking state is inherently short (5-15s) and self-resolving -- the first `stream` token sets content to non-empty, which removes the dots naturally
- The leader avatar badge + name are already visible in the bubble, so users know WHICH leader is thinking
- The dots reuse Tailwind's `animate-pulse` (existing in the project) with staggered delays for a subtle wave effect

### Bug 3: Render Markdown in Message Bubbles

**Problem:** The `<p>` tag renders content as plain text.

**Fix:** Add `react-markdown` and `remark-gfm` dependencies and replace the raw `<p>{content}</p>` with a `<Markdown>` component using custom Tailwind-styled component overrides.

**Files:**

- `apps/web-platform/package.json` -- add `react-markdown` and `remark-gfm` dependencies
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- replace `<p className="whitespace-pre-wrap">{content}</p>` with `<MarkdownContent>` component in `MessageBubble`
- `apps/web-platform/bun.lock` -- regenerated after install
- `apps/web-platform/package-lock.json` -- regenerated after install (Dockerfile uses `npm ci`)

**Why `remark-gfm` is required:** CommonMark (react-markdown's default parser) does NOT support GFM tables. Without `remark-gfm`, markdown like `| a | b |\n| - | - |` renders as pipe-delimited text, not an HTML table. `remark-gfm` adds tables, strikethrough (`~~text~~`), task lists (`- [x]`), and autolinks.

#### Research Insights: react-markdown Implementation

**Component override pattern** (from Context7 docs, react-markdown v10):

```tsx
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";

const MARKDOWN_COMPONENTS = {
  h1: ({ children }: { children: React.ReactNode }) => (
    <h1 className="mb-3 mt-4 text-lg font-semibold text-white">{children}</h1>
  ),
  h2: ({ children }: { children: React.ReactNode }) => (
    <h2 className="mb-2 mt-3 text-base font-semibold text-white">{children}</h2>
  ),
  h3: ({ children }: { children: React.ReactNode }) => (
    <h3 className="mb-2 mt-3 text-sm font-semibold text-neutral-200">{children}</h3>
  ),
  p: ({ children }: { children: React.ReactNode }) => (
    <p className="mb-2 leading-relaxed">{children}</p>
  ),
  ul: ({ children }: { children: React.ReactNode }) => (
    <ul className="mb-2 ml-4 list-disc space-y-1">{children}</ul>
  ),
  ol: ({ children }: { children: React.ReactNode }) => (
    <ol className="mb-2 ml-4 list-decimal space-y-1">{children}</ol>
  ),
  li: ({ children }: { children: React.ReactNode }) => (
    <li className="text-neutral-200">{children}</li>
  ),
  table: ({ children }: { children: React.ReactNode }) => (
    <div className="mb-3 overflow-x-auto">
      <table className="w-full border-collapse text-sm">{children}</table>
    </div>
  ),
  th: ({ children }: { children: React.ReactNode }) => (
    <th className="border border-neutral-700 bg-neutral-800/50 px-3 py-1.5 text-left font-semibold text-neutral-200">
      {children}
    </th>
  ),
  td: ({ children }: { children: React.ReactNode }) => (
    <td className="border border-neutral-700 px-3 py-1.5 text-neutral-300">{children}</td>
  ),
  code: ({ className, children }: { className?: string; children: React.ReactNode }) => {
    const isBlock = /language-(\w+)/.test(className || "");
    return isBlock ? (
      <pre className="mb-3 overflow-x-auto rounded-lg bg-neutral-950 p-3">
        <code className="text-xs text-neutral-300">{children}</code>
      </pre>
    ) : (
      <code className="rounded bg-neutral-800 px-1.5 py-0.5 text-xs text-amber-300">{children}</code>
    );
  },
  strong: ({ children }: { children: React.ReactNode }) => (
    <strong className="font-semibold text-white">{children}</strong>
  ),
  a: ({ href, children }: { href?: string; children: React.ReactNode }) => (
    <a href={href} target="_blank" rel="noopener noreferrer"
      className="text-amber-400 underline hover:text-amber-300">{children}</a>
  ),
  blockquote: ({ children }: { children: React.ReactNode }) => (
    <blockquote className="mb-2 border-l-2 border-neutral-600 pl-3 italic text-neutral-400">
      {children}
    </blockquote>
  ),
};

function MarkdownContent({ content }: { content: string }) {
  return (
    <Markdown
      remarkPlugins={[remarkGfm]}
      components={MARKDOWN_COMPONENTS}
      disallowedElements={["script", "iframe", "form", "object", "embed"]}
      unwrapDisallowed
    >
      {content}
    </Markdown>
  );
}
```

**Security** (defense-in-depth layers):

1. `react-markdown` builds a React element tree from AST -- never injects raw HTML
2. `disallowedElements` strips dangerous elements; `unwrapDisallowed` preserves their text content
3. `defaultUrlTransform` (built-in) blocks `javascript:` protocol URLs automatically
4. Do NOT enable `rehype-raw` plugin -- it enables raw HTML passthrough and defeats layer 1

**Streaming optimization** (validated by Telegram bridge learning 2026-03-02):

- Render plain text (`whitespace-pre-wrap`) during active streaming
- Switch to `<MarkdownContent>` after `stream_end` fires
- This prevents partial markdown parsing artifacts (e.g., half-rendered tables) and avoids re-parsing on every token
- The `MessageBubble` component needs an `isStreaming` boolean prop, derived from whether the leader is in `activeStreamsRef`

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

#### Research Insights: Session Key Refactoring

**Institutional learning (2026-03-27: ws-session-race-abort-before-replace):** The `abortActiveSession` helper was introduced specifically to prevent the race condition where two `start_session` messages arrive in quick succession. The abort-before-replace invariant (abort runs synchronously before any `await`) is critical. The refactored `abortSession` must preserve this invariant:

- `abortSession(userId, convId)` (no leaderId) must abort ALL matching sessions synchronously
- The iteration over `activeSessions` entries must be synchronous (no async operations between the abort calls)
- The "superseded" abort reason must be passed through so the agent-runner catch block skips the "failed" status write

**Institutional learning (2026-03-20: review-gate-promise-leak):** Each `AgentSession` has a `reviewGateResolvers` map. When aborting sessions via prefix match, the AbortController abort will cause the `abortableReviewGate` promise to reject, which cleans up the resolver. However, verify that the `finally` block in `startAgentSession` uses the correct leader-scoped key when calling `activeSessions.delete(key)` -- a stale key reference would leak the session.

**Concrete implementation pattern:**

```typescript
function sessionKey(userId: string, conversationId: string, leaderId?: string) {
  return leaderId
    ? `${userId}:${conversationId}:${leaderId}`
    : `${userId}:${conversationId}`;
}

export function abortSession(
  userId: string,
  conversationId: string,
  reason?: "disconnected" | "superseded",
  leaderId?: string,
): void {
  if (leaderId) {
    // Targeted: abort specific leader session
    const key = sessionKey(userId, conversationId, leaderId);
    const session = activeSessions.get(key);
    if (session) {
      session.abort.abort(new Error(`Session aborted: ${reason ?? "disconnected"}`));
    }
    return;
  }

  // Broadcast: abort ALL sessions for this conversation (any leader)
  const prefix = `${userId}:${conversationId}`;
  for (const [key, session] of activeSessions) {
    if (key === prefix || key.startsWith(`${prefix}:`)) {
      session.abort.abort(new Error(`Session aborted: ${reason ?? "disconnected"}`));
    }
  }
}
```

**Edge case -- `abortAllUserSessions`:** This function iterates with prefix `userId:`. With the new key format `userId:convId:leaderId`, the existing prefix match still works correctly because the userId prefix is preserved.

## Technical Considerations

### Architecture impacts

- Bug 4 fix changes the session tracking key format, which is an internal server data structure with no persistence or external API surface. The change is backward-compatible because single-leader sessions can continue using the 2-part key.
- Bug 3 adds a new dependency (`react-markdown`). Per constitution: "Never add a dependency for something an LLM can generate inline." However, markdown-to-HTML conversion is a complex parsing problem with edge cases (nested lists, table alignment, code block escaping) where a tested library is the correct choice. The alternative -- hand-rolling a regex-based parser -- would be fragile and security-risky.

### Performance implications

- `react-markdown` parses on every render. For streaming messages that update frequently (each `stream` token triggers a re-render), this could be expensive.
- **Recommended approach: plain text during streaming, markdown after completion.** This is validated by the Telegram bridge streaming learning (2026-03-02): "Plain text during streaming, HTML on final edit -- avoids partial markdown rendering artifacts." The same principle applies here.
- **Implementation:** Track streaming state per message via `activeStreamsRef`. Pass `isStreaming` prop to `MessageBubble`. When `isStreaming=true`, render `<p className="whitespace-pre-wrap">`. When `isStreaming=false` (after `stream_end`), render `<MarkdownContent>`. The transition from plain text to markdown on completion causes a single re-render per message -- acceptable.
- **Why not `React.memo` or `useDeferredValue`:** These only reduce re-render frequency but still trigger markdown parsing during streaming. The plain-text-then-markdown approach eliminates the problem entirely with zero complexity cost.

### Dependency management

- Two new dependencies: `react-markdown` and `remark-gfm`
- Both are ESM-only packages, compatible with project's `"type": "module"` config
- Both `bun.lock` and `package-lock.json` must be regenerated (Dockerfile uses `npm ci`)
- Per constitution: verify `bunfig.toml` `minimumReleaseAge = 259200` allows installation (packages must be 72h old)

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

1. Install `react-markdown` AND `remark-gfm` in `apps/web-platform` (`bun add react-markdown remark-gfm`)
2. Regenerate both lockfiles (`bun install` + `npm install` in app directory)
3. Create `MarkdownContent` component using `components` prop with Tailwind-styled overrides (see code example in Bug 3 Research Insights)
4. Add `isStreaming` prop to `MessageBubble`, derived from `activeStreamsRef.current.has(msg.leaderId)`
5. Implement three-state rendering in `MessageBubble`: thinking dots (empty content) -> plain text (streaming) -> markdown (complete)
6. Configure security: `disallowedElements={["script", "iframe", "form", "object", "embed"]}` + `unwrapDisallowed` -- do NOT enable `rehype-raw`
7. Verify both lockfiles committed (`bun.lock` + `package-lock.json`)

## Alternative Approaches Considered

| Approach | Considered For | Why Rejected |
|----------|---------------|--------------|
| `marked` + raw HTML injection | Bug 3 markdown | XSS risk; `react-markdown` builds React elements safely |
| Custom regex markdown parser | Bug 3 markdown | Fragile, incomplete, security risk -- markdown is complex |
| `@tailwindcss/typography` plugin | Bug 3 styling | Adds a dependency for minimal benefit; `components` prop with inline Tailwind classes suffice |
| `react-markdown` without `remark-gfm` | Bug 3 tables | CommonMark does not support GFM tables; pipe syntax renders as text without the plugin |
| `markdown-to-jsx` instead of `react-markdown` | Bug 3 markdown | Lower benchmark score (23 vs 79); react-markdown has better plugin ecosystem and security defaults |
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
