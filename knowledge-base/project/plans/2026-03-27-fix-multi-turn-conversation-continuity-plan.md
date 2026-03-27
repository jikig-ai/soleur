---
title: "fix: Multi-turn conversation continuity"
type: fix
date: 2026-03-27
---

# fix: Multi-turn conversation continuity

## Overview

Each user message spawns a fresh Agent SDK `query()` with no memory of prior exchange. `persistSession: false` is explicitly set at `agent-runner.ts:215`. The `sendUserMessage` function (line 437) calls `startAgentSession()` which creates a brand-new agent every turn with a hardcoded greeting — the user's actual message is saved to Supabase but never fed to the agent.

This plan implements persistent conversation threads via a hybrid architecture: SDK `resume` as primary path (full context fidelity), message replay from Supabase as fallback when sessions expire.

## Problem Statement

The agent has complete amnesia between turns. This is the single highest-leverage P1 item — three of six Phase 1 exit criteria depend on multi-turn working. A chat product without memory is not a chat product.

**Root cause:** `sendUserMessage` at `apps/web-platform/server/agent-runner.ts:437-478` calls `startAgentSession()` which creates a new `query()` with `persistSession: false`. The comment at line 445 acknowledges this: `// For multi-turn, we'd need to start a new query with resume.`

## Proposed Solution

**Hybrid architecture:**

1. **Primary path (SDK resume):** Capture `session_id` from streamed messages (available on every message, not just init). Store in `conversations.session_id` (column already exists, never populated). On subsequent turns, pass `options: { resume: sessionId }` to `query()`.

2. **Fallback path (message replay):** When `resume` fails (server restart, session expired, container redeploy), load prior messages from Supabase `messages` table and inject as conversation context into a new `query()` prompt. Loses tool execution context but preserves conversational memory.

3. **Lifecycle management:** Sessions close on inactivity timeout (24h), explicit new chat, or work completion. Data retention via TTL with user control (exact duration set by CLO in P2).

## Technical Considerations

### Architecture

- SDK `resume` uses the `session_id` returned on every streamed message (capture from the first message received). The `resume` option is a first-class SDK feature, not a workaround.
- **Note:** The SDK default for `persistSession` is `true`. The codebase explicitly sets it to `false` to disable persistence. Removing the line entirely achieves the same result as setting it to `true`.
- The `conversations.session_id` column already exists in `001_initial_schema.sql:51` and is typed in `lib/types.ts:53` — no migration needed.
- `activeSessions` Map (line 52) tracks in-memory session state but only stores `AbortController` — needs extension to track `session_id`.

### Performance

- SDK `resume` replays conversation context to the model, so token usage grows linearly with conversation length. Bounded by existing `maxBudgetUsd: 5.0`.
- Message replay path sends full history on every turn — no SDK-level caching optimization.

### Security

- Session files scoped per-workspace via `cwd`. Existing sandbox (bubblewrap, filesystem restrictions, `canUseTool`) applies identically to resumed sessions.
- New error paths must route through `error-sanitizer.ts` (per learning: WebSocket error sanitization CWE-209).
- **Authorization:** All conversation lookups in `sendUserMessage` and `ws-handler.ts` must filter by `user_id`. Currently `sendUserMessage` reads the conversation without ownership check — add `.eq("user_id", userId)` to prevent cross-user conversation access.
- **Session ID exposure:** `session_id` is stored in `conversations` table and visible to users via RLS. If the SDK's session ID has security significance, consider excluding it from client-visible queries. Low risk but worth noting.

### Infrastructure Risk

- **Critical:** Session files live on the container filesystem. If stored outside the persistent `/workspaces/<userId>` volume, they are lost on restart/redeploy. The spike (Phase 0) must verify storage location.
- Cloudflare terminates idle WebSocket connections after 100 seconds — 30-second keepalive pings already in place (per learning: WebSocket through Cloudflare).

### Learnings to Apply

- Check every Supabase return value — `{ data, error }` pattern silently discards failures (learning: Supabase silent error return values)
- Re-check `ws.readyState` after every `await` before mutating session maps (learning: WebSocket first-message auth TOCTOU race)
- Wire WebSocket disconnect to session cleanup via AbortSignal + timeout safety nets (learning: review gate promise leak)
- Use typed error codes for session state transitions via `WSErrorCode` discriminated union (learning: typed error codes for WebSocket key invalidation)

## Alternative Approaches Considered

**Message replay only:** No filesystem dependency, survives everything. But SDK `query()` V1 takes a single `prompt` string — history injection is prompt engineering, not a first-class API. Loses tool execution context on every turn.

**V2 SDK migration:** `unstable_v2_createSession` / `unstable_v2_resumeSession` supports multi-turn natively via `send()`/`stream()`. But "unstable" API may not exist in pinned SDK 0.2.80. Larger migration surface for a critical bug fix.

**Both rejected** in favor of hybrid (primary resume + fallback replay) per CTO recommendation.

## Implementation Phases

### Phase 0: SDK Resume Spike

Empirical verification before production code. ~1 hour.

- [ ] 0.1 Remove `persistSession: false` (or set to `true`) in `agent-runner.ts:215` — SDK default is already `true`
- [ ] 0.2 Complete a session, capture `session_id` from the first streamed message (`message.session_id` is available on every message)
- [ ] 0.3 Locate session files on disk (`find / -newer <timestamp> -name "*.json" 2>/dev/null`)
- [ ] 0.4 Verify session file location is inside persistent `/workspaces/<userId>` volume
- [ ] 0.5 Kill and restart the server process
- [ ] 0.6 Attempt `query()` with `options: { resume: sessionId }` — verify full tool execution context
- [ ] 0.7 Confirm `resume` option exists in SDK 0.2.80 (`node_modules/@anthropic-ai/claude-agent-sdk`)
- [ ] 0.8 Document findings in `knowledge-base/project/learnings/2026-03-27-sdk-resume-spike.md`

**Decision gate:** If session files are outside persistent volume or `resume` fails across restarts, pivot to replay-primary architecture. If `resume` works, proceed with hybrid.

### Phase 1: Core Session Resume

Primary path implementation. Modify `agent-runner.ts`.

- [ ] 1.1 Extend `AgentSession` type to include `sessionId: string | null` alongside existing `AbortController`
  - File: `apps/web-platform/server/agent-runner.ts:52-67`
- [ ] 1.2 Remove `persistSession: false` line (or set to `true`) in `startAgentSession` query options
  - File: `apps/web-platform/server/agent-runner.ts:215`
  - SDK default is already `true` — removing the line is sufficient
- [ ] 1.3 Capture `session_id` from the first streamed message in the streaming loop
  - File: `apps/web-platform/server/agent-runner.ts:350-399`
  - Pattern: `if (!sessionId) { sessionId = message.session_id; }` — `session_id` is available on every streamed message, not just init
- [ ] 1.4 Store `session_id` in `conversations.session_id` via Supabase update
  - Check return value: `const { error } = await supabase.from("conversations").update({ session_id }).eq("id", conversationId)`
  - If error, log but don't fail — session still works for current turn
- [ ] 1.5 Refactor `startAgentSession` to accept optional `sessionId` and `userMessage` parameters
  - File: `apps/web-platform/server/agent-runner.ts:151-432`
  - **Architecture decision:** Refactor `startAgentSession` to branch internally rather than creating a separate function. The resume path still needs the same infrastructure (sandbox, hooks, canUseTool, API key, workspace path) so duplicating setup logic is worse than branching.
  - If `sessionId` provided: call `query()` with `options: { resume: sessionId }` and `userMessage` as `prompt`
  - If no `sessionId`: create new session as before (first turn)
  - The resumed `query()` needs all the same options — only `prompt` and `resume` differ
- [ ] 1.6 Refactor `sendUserMessage` to read `session_id` and route accordingly
  - File: `apps/web-platform/server/agent-runner.ts:437-478`
  - Read `session_id` from conversation record (add `.eq("user_id", userId)` for authorization check)
  - If `session_id` exists: call `startAgentSession` with `sessionId` and user's message
  - If no `session_id`: call `startAgentSession` without `sessionId` (creates new session)
- [ ] 1.7 First turn uses user's actual message, not hardcoded greeting
  - **Decision:** Remove the hardcoded `[Session started with ${leader.name}] How can I help you today?` greeting
  - The `start_session` WebSocket message triggers conversation creation only — no agent turn
  - First agent turn happens when the user sends their first `chat` message, which calls `sendUserMessage` → `startAgentSession` with no `sessionId` (new session) and the user's actual message as `prompt`
  - This eliminates the wasted agent turn on a canned response
- [ ] 1.8 Don't mark conversation as `completed` after each turn
  - File: `apps/web-platform/server/agent-runner.ts:376`
  - Set status to `waiting_for_user` instead of `completed` after a successful turn
  - `completed` only on explicit close or work completion

### Phase 2: Message Replay Fallback

Graceful degradation when SDK session expires.

- [ ] 2.1 Add `loadConversationHistory` function to read messages from Supabase
  - File: `apps/web-platform/server/agent-runner.ts` (new function)
  - Query: `supabase.from("messages").select("role, content, created_at").eq("conversation_id", conversationId).order("created_at", { ascending: true })`
  - Check `{ data, error }` return value
- [ ] 2.2 Format messages as conversation context for prompt injection
  - Build a structured prompt: `"Previous conversation:\n[User]: ...\n[Assistant]: ...\n\nNew message: <user's message>"`
  - Concrete truncation strategy: keep last 20 messages; if total exceeds token estimate, drop oldest messages first
  - Do not replay tool calls — summarize tool interactions in a system prompt note instead (tool outputs may be stale)
- [ ] 2.3 Add resume-with-fallback logic in `sendUserMessage`
  - Try `query({ prompt: message, options: { resume: sessionId } })`
  - If resume throws or returns an error: clear `session_id` from DB, load messages, create new session with history-injected prompt
  - Capture new `session_id` from the fresh session
- [ ] 2.4 Add server startup cleanup for orphaned conversations
  - On server boot, transition all `active`/`waiting_for_user` conversations older than 5 minutes to `failed` status
  - These represent conversations from before a restart whose in-memory state is gone
- [ ] 2.5 Add REST endpoint for client-side message history loading
  - Endpoint: `GET /api/conversations/:id/messages` (or Supabase client query)
  - Required for page refresh, browser back/forward, and mobile tab restoration
  - The WebSocket should not be the only data channel — client needs to load history on mount
  - Include authorization: filter by authenticated user's ID

### Phase 3: WebSocket Reconnection

Session survives WebSocket disconnect/reconnect.

- [ ] 3.1 Don't abort session on WebSocket disconnect if conversation is active
  - File: `apps/web-platform/server/ws-handler.ts:358-372`
  - Currently: `ws.on("close", () => { abortSession(userId, current.conversationId); })`
  - Change: Only abort if conversation status is not `active`/`waiting_for_user`
  - Add grace period (e.g., 30 seconds) before aborting to allow reconnection
- [ ] 3.2 On reconnect, restore conversation context from `ClientSession.conversationId`
  - File: `apps/web-platform/server/ws-handler.ts`
  - When client reconnects and sends a message for an existing conversation, resume the session
  - Don't require a new `start_session` message — auto-detect from `conversationId`
- [ ] 3.3 Re-check `ws.readyState` after every `await` in the reconnection path
  - Per learning: TOCTOU race creates phantom sessions
- [ ] 3.4 Add typed error code for session state transitions
  - Extend `WSErrorCode` union in `lib/types.ts` with `session_expired`, `session_resumed`
  - Add `resume_session` to `WSMessage` discriminated union (the `default` case uses `never` exhaustiveness — must update both type and handler switch in `ws-handler.ts`)
  - Route new error messages through `error-sanitizer.ts` (add to safe messages allowlist)

### Phase 4: Lifecycle Management

Conversation close triggers and cleanup.

- [ ] 4.1 Add inactivity timeout for session cleanup
  - Track `last_active` (already in schema) — update on each message
  - Background interval checks for conversations inactive > 24 hours
  - On timeout: set status to `completed`, clean up session resources
  - Use `timer.unref()` on cleanup interval (per learning: Bun segfault from leaked timers)
- [ ] 4.2 Add explicit close mechanism
  - Add `close_conversation` to `WSMessage` union in `lib/types.ts`
  - Add handler case in `ws-handler.ts` `handleMessage` switch (exhaustive `never` check requires both type and handler update)
  - Sets status to `completed`, aborts active session, cleans up resources
- [ ] 4.3 Handle work completion close
  - When agent produces a `result` that indicates completion, set status accordingly
  - Don't auto-close on every result — only on explicit completion signals
- [ ] 4.4 Session file cleanup for expired sessions
  - On conversation close/timeout, delete associated session files from disk
  - Fallback: periodic sweep for orphan session files older than TTL

### Phase 5: Testing

- [ ] 5.1 Test multi-turn context retention
  - Send message A, get response. Send follow-up B referencing A. Verify B's response shows context from A.
- [ ] 5.2 Test WebSocket reconnection
  - Establish session, disconnect WebSocket, reconnect, send follow-up. Verify context preserved.
- [ ] 5.3 Test fallback replay
  - Establish session, restart server (clear in-memory state). Send follow-up. Verify conversational memory (tool context loss is expected).
- [ ] 5.4 Test session expiry
  - Establish session, simulate 24h+ inactivity. Verify session cleaned up and conversation marked completed.
- [ ] 5.5 Test concurrent message handling
  - Send two messages rapidly. Verify no race condition on session state.

## Acceptance Criteria

- [ ] Agent remembers context from prior messages in the same conversation
- [ ] User can ask follow-up questions and get contextual answers
- [ ] Session survives WebSocket reconnection
- [ ] Conversation history persists across server restarts (graceful degradation via message replay)
- [ ] Conversation lifecycle: inactivity timeout, explicit close, and work completion all work
- [ ] All Supabase operations check `{ error }` return values
- [ ] Error messages route through `error-sanitizer.ts`
- [ ] No leaked timers or promises on disconnect (AbortSignal pattern)

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Option 1 (SDK session resume) is the right first move. The SDK provides a first-class `resume` option, the DB schema already has `session_id`, and the change is ~30 lines in `agent-runner.ts`. Critical risk: session files are on container filesystem — spike must verify storage location and cross-restart behavior. Recommended 1-hour spike before production code.

### Product (CPO)

**Status:** reviewed
**Assessment:** This is a prerequisite for the product to exist, not a feature. Architecture choice propagates to 5+ downstream roadmap items (GDPR deletion, session lifecycle, conversation inbox, tag-and-route, legal PII surface). Key decisions made in brainstorm: persistent threads, single-leader scope, TTL retention with user control.

## Test Scenarios

- Given a conversation with 2+ turns, when the user sends a follow-up referencing prior context, then the agent responds with awareness of the full conversation history
- Given an active conversation, when the WebSocket disconnects and reconnects within 30 seconds, then the next message resumes the session without context loss
- Given a conversation with an expired SDK session (server restart), when the user sends a new message, then the system falls back to message replay and maintains conversational memory
- Given an inactive conversation (24h+), when checked by the cleanup interval, then the conversation is marked completed and session resources are freed
- Given a conversation, when the user sends `close_conversation`, then the session is terminated and resources cleaned up
- Given rapid sequential messages, when processed concurrently, then no race condition corrupts session state

## References

- Issue: #1044
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-27-multi-turn-continuity-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-multi-turn-continuity/spec.md`
- Agent SDK docs: `@anthropic-ai/claude-agent-sdk` v0.2.80 — `query()` with `resume` option
- Primary change site: `apps/web-platform/server/agent-runner.ts`
- WebSocket handler: `apps/web-platform/server/ws-handler.ts`
- DB schema: `apps/web-platform/supabase/migrations/001_initial_schema.sql`
- Types: `apps/web-platform/lib/types.ts`
