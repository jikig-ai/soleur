# KB chat agent protocol

This document explains how non-WebSocket agents (CLIs, background jobs, MCP
tools) interact with the KB chat subsystem. It documents the two idempotency
contracts the subsystem depends on so agent authors don't need to re-derive
them from the code.

## Summary

- Conversations are uniquely keyed on `(user_id, context_path)`. Resume via
  `resumeByContextPath` returns the same row each time — no de-duplication
  logic needed in the agent.
- Quoted selections are inserted client-side as a `> ...\n\n` prefix to the
  draft. There is no dedicated "quote API" — agents that need to seed a
  draft just send markdown with the blockquote already embedded.

## 1. `resumeByContextPath` idempotency

The WebSocket `start_session` message accepts a `resumeByContextPath`
field. When present, the server looks up the existing conversation row
for `(user_id, context_path)` and resumes it. When absent, a fresh
pending conversation is created.

Idempotency contract:

- Two `start_session` calls with the same `(user_id, context_path)`
  return the same `conversationId`.
- The row is identified by `context_path` equality (not prefix match).
  `knowledge-base/a.md` and `knowledge-base/a.md#section` are distinct.
- Only non-archived rows are eligible — archived conversations are
  skipped; a new row is created in their place.

HTTP agents that need to discover whether a row already exists can use
`GET /api/conversations?context_path=<path>` (see below). The response
is `null` when no row exists, so a POST of a new message to a fresh
conversation is always valid.

### Discovery endpoint

```http
GET /api/conversations?context_path=knowledge-base/product/roadmap.md
```

Response (200):

```json
{
  "conversationId": "c_abc123",
  "context_path": "knowledge-base/product/roadmap.md",
  "last_active": "2026-04-17T10:00:00.000Z",
  "message_count": 7
}
```

Response (200) when no row exists:

```json
null
```

Errors: `400` (bad path), `401` (unauthenticated), `500` (lookup error).

## 2. Quote-prepend convention

When the user selects text in the KB viewer and clicks the
"Quote in chat" pill, the chat input prepends the selection using a
Markdown blockquote:

```text
> <selected text>

<existing draft>
```

The existing draft is pushed two newlines below. If the draft is
empty, the block sits at the top.

Agents that want to produce the same effect from outside the browser
do not need a separate endpoint. They just send a message whose content
starts with `>` — the server already treats this as a normal message
body (no special interpretation) and the Markdown renderer handles the
display. Analytics marks this pattern via the `kb.chat.selection_sent`
goal, which fires client-side when `/^\s*>/` matches.

### Example: CLI agent posting a quoted message

```bash
MESSAGE="> The pricing section needs a research link for the \$49 tier claim.

Can you pull Gartner's 2025 SaaS benchmark?"

# Via the /api/messages endpoint (hypothetical — use your real post path)
curl -X POST /api/messages \
  -H "Content-Type: application/json" \
  -d "{\"conversationId\": \"c_abc123\", \"content\": $(jq -Rs . <<< "$MESSAGE")}"
```

## Related code

- Lookup helper: `apps/web-platform/server/lookup-conversation-for-path.ts`
- Thread-info route (`{ messageCount }`): `apps/web-platform/app/api/chat/thread-info/route.ts`
- Conversations route (full row): `apps/web-platform/app/api/conversations/route.ts`
- Quote pill: `apps/web-platform/components/kb/selection-toolbar.tsx`
- Quote bridge provider: `apps/web-platform/components/kb/kb-chat-quote-bridge.tsx`
- Analytics: `kb.chat.selection_sent` goal in `apps/web-platform/components/chat/kb-chat-content.tsx`
