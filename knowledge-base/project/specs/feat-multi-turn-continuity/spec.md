# Feature: Multi-Turn Conversation Continuity

## Problem Statement

Each user message spawns a fresh Agent SDK `query()` with no memory of prior exchange. `persistSession: false` is explicitly set in `agent-runner.ts:215`. The `sendUserMessage` function calls `startAgentSession()` which creates a brand-new agent every turn with a hardcoded greeting prompt — the user's actual message is saved to Supabase but never fed to the agent. The agent has complete amnesia between turns.

## Goals

- Agent remembers full context from prior messages in the same conversation
- User can ask follow-up questions and get contextual answers
- Session survives WebSocket reconnection
- Conversation history persists across server restarts (graceful degradation via message replay)
- Data model supports future TTL-based retention and user-initiated deletion

## Non-Goals

- Cross-domain leader context sharing (deferred to tag-and-route #1.11)
- GDPR deletion/export implementation (P2, item 2.9 — but data model accounts for it)
- Conversation inbox UI (P3, item 3.3)
- Context window management (summarization/truncation for long conversations)
- Exact TTL duration setting (CLO determines in P2)

## Functional Requirements

### FR1: Multi-turn context retention

On subsequent messages in a conversation, the agent has access to the full conversation history including prior user messages, assistant responses, and tool execution context.

### FR2: Session resume via SDK

When an active SDK session exists, subsequent messages resume the session using the SDK's `resume` option with the stored `session_id`, preserving full tool execution context.

### FR3: Message replay fallback

When no active SDK session exists (server restart, session expired, container redeploy), the system loads prior messages from Supabase and injects them as conversation context into a new `query()` call. Tool execution context is lost but conversational memory is preserved.

### FR4: Conversation lifecycle management

Conversations close via three triggers:

- Inactivity timeout (configurable, default 24 hours) — reclaims server resources
- Explicit new chat — user starts a fresh conversation
- Work completion — issue/feature/bug fix is done

### FR5: User message delivery

The user's actual message content is passed as the prompt to the agent on subsequent turns, not the hardcoded greeting.

## Technical Requirements

### TR1: Session ID persistence

Capture `session_id` from the SDK's `init` system message during `startAgentSession`. Store it in `conversations.session_id` (column already exists, currently null).

### TR2: SDK resume verification (spike)

Before production implementation, verify empirically:

- Where `persistSession: true` writes files in containerized Docker deployment
- Whether `resume` works across process restarts with pinned SDK 0.2.80
- Session file location relative to persistent `/workspaces/<userId>` volume

### TR3: Supabase error handling

Every Supabase query return value must be destructured and checked (per learning: Supabase JS client silently discards errors via `{ data, error }` pattern).

### TR4: WebSocket reconnection

On WebSocket reconnect, the client must be able to resume the conversation without starting a new session. Add a `resume_session` message type or auto-resume based on `conversationId`.

### TR5: Error sanitization

All new error paths (session expired, resume failed, replay fallback) must route through `error-sanitizer.ts`. Add new error messages to the safe messages allowlist.

### TR6: Retention-ready data model

Data model must support future TTL-based auto-deletion and user-initiated deletion without schema changes. No new migrations needed for this requirement — existing schema supports it.
