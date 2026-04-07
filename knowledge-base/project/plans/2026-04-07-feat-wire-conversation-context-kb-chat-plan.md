---
title: "feat: wire ConversationContext for KB Chat about this flow"
type: feat
date: 2026-04-07
---

# Wire ConversationContext for KB "Chat about this" Flow

## Problem

The KB viewer's "Chat about this" button constructs a URL:

```text
/dashboard/chat/new?msg=Tell me about the file at <path>&leader=cto
```

The chat page sends this as a plain text message. The agent must then use the `Read` tool to fetch the file -- an extra round-trip that feels broken from the user's perspective ("I just told it which file I was looking at, why is it reading it again?").

The `ConversationContext` infrastructure already exists end-to-end:

- `lib/types.ts:27-31` -- `ConversationContext` interface with `path`, `type`, `content` fields
- `lib/ws-client.ts:386` -- `startSession` accepts `ConversationContext` as second param
- `lib/types.ts:38` -- `start_session` WS message carries optional `context` field
- `server/ws-handler.ts:200` -- handler passes `msg.context` to `startAgentSession`
- `server/agent-runner.ts:347-349` -- injects `context?.content` into agent system prompt

The gap is in the chat page component (`app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`):

1. Line 55: `startSession(leaderId ?? undefined)` -- never passes a `ConversationContext`
2. The KB viewer does not pass the artifact path as a structured `?context=` param
3. No code fetches the file content before starting the session

## Approach

Add a `?context=` URL param carrying the KB file path. On the chat page, fetch the file content from the existing REST API, construct a `ConversationContext`, and pass it to `startSession`. The agent then receives the full file content in its system prompt without needing a tool call.

### Why `?context=` param vs. parsing `?msg=`

Parsing the path out of the natural-language `?msg=` string is fragile (regex on "file at X"). A dedicated `?context=` param is explicit, type-safe, and decoupled from the message wording. It also lets the message text evolve independently (e.g., "Explain this roadmap" instead of "Tell me about the file at...").

## Implementation

### 1. KB viewer: add `?context=` param to chat URL

**File:** `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`

Change line 97 from:

```typescript
const chatUrl = `/dashboard/chat/new?msg=${encodeURIComponent(`Tell me about the file at ${joinedPath}`)}&leader=cto`;
```

To:

```typescript
const chatUrl = `/dashboard/chat/new?msg=${encodeURIComponent(`Tell me about the file at ${joinedPath}`)}&leader=cto&context=${encodeURIComponent(joinedPath)}`;
```

### 2. Chat page: fetch content and pass ConversationContext

**File:** `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

Read the `?context=` param from URL. Before starting the session, fetch the file content from `/api/kb/content/<path>`. Pass the result as `ConversationContext` to `startSession`.

Key design choices:

- **Fetch happens client-side** via the existing REST API (`/api/kb/content/<path>`), which handles auth, workspace resolution, path traversal protection, and error responses. No new API needed.
- **Non-blocking**: If the fetch fails (404, auth error, network), start the session without context. The agent can still use the `Read` tool as fallback. This matches the existing graceful degradation pattern.
- **Session start waits for context fetch**: The `startSession` call moves into a `useEffect` that waits for both `status === "connected"` and the context fetch to resolve (or fail). This avoids a race where the session starts before content is available.

Pseudocode for the new effect:

```typescript
const contextParam = searchParams.get("context");

// Fetch KB content when context param is present
const [kbContext, setKbContext] = useState<ConversationContext | undefined>();
const [contextLoading, setContextLoading] = useState(!!contextParam);

useEffect(() => {
  if (!contextParam) return;
  let cancelled = false;

  (async () => {
    try {
      const res = await fetch(`/api/kb/content/${contextParam}`);
      if (res.ok && !cancelled) {
        const data = await res.json();
        setKbContext({
          path: contextParam,
          type: "kb-viewer",
          content: data.content,
        });
      }
    } catch {
      // Graceful degradation: proceed without context
    } finally {
      if (!cancelled) setContextLoading(false);
    }
  })();

  return () => { cancelled = true; };
}, [contextParam]);

// Start session when connected AND context is resolved
useEffect(() => {
  if (status === "connected" && conversationId === "new" && !sessionStarted && !contextLoading) {
    startSession(leaderId ?? undefined, kbContext);
    setSessionStarted(true);
  }
}, [status, conversationId, leaderId, sessionStarted, startSession, contextLoading, kbContext]);
```

### 3. No server-side changes needed

The entire server-side pipeline (`ws-handler.ts` -> `agent-runner.ts`) already handles `ConversationContext`:

- `ws-handler.ts:200` passes `msg.context` to `startAgentSession` for directed sessions
- `agent-runner.ts:347-349` injects `context?.content` into system prompt
- `agent-runner.ts:290` accepts `ConversationContext` parameter

No modifications required on the server.

## Acceptance Criteria

- [x] KB viewer "Chat about this" URL includes `?context=<kb-path>` param
- [x] Chat page fetches file content from `/api/kb/content/<path>` when `?context=` is present
- [x] `startSession` receives `ConversationContext` with `{ path, type: "kb-viewer", content }`
- [x] Agent's system prompt includes the artifact content (visible in server logs or agent behavior)
- [x] Session starts without context if the KB content fetch fails (graceful degradation)
- [x] Session starts normally when no `?context=` param is present (no regression)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal plumbing change wiring existing infrastructure.

## Test Scenarios

### Unit Tests (`apps/web-platform/test/chat-page.test.tsx`)

- Given `?context=product/roadmap.md` param, when session starts, then `startSession` is called with `ConversationContext` containing `{ path: "product/roadmap.md", type: "kb-viewer", content: "..." }`
- Given `?context=product/roadmap.md` param and the KB API returns 404, when session starts, then `startSession` is called without context (graceful degradation)
- Given no `?context=` param, when session starts, then `startSession` is called with `undefined` context (no regression)
- Given `?context=` param, session should not start until context fetch resolves (no race condition)
- Given `?context=` with empty string value, when session starts, then `startSession` is called with `undefined` context (treated as no context)

### Protocol Tests (`apps/web-platform/test/ws-protocol.test.ts`)

- `start_session` message with `context` field is valid client message

### Integration Verification

- Navigate to KB viewer, click "Chat about this", verify URL contains `?context=` param
- Verify agent response references file content without making a `Read` tool call

## References

- Issue: #1729
- KB viewer PR: #1711
- `ConversationContext` interface: `apps/web-platform/lib/types.ts:27-31`
- Agent system prompt injection: `apps/web-platform/server/agent-runner.ts:347-349`
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- KB content page: `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`
- KB content API: `apps/web-platform/app/api/kb/content/[...path]/route.ts`
- WS client: `apps/web-platform/lib/ws-client.ts`
- WS handler: `apps/web-platform/server/ws-handler.ts`
