# Multi-Turn Conversation Continuity Brainstorm

**Date:** 2026-03-27
**Issue:** #1044
**Participants:** Founder, CTO, CPO

## What We're Building

Fix the agent amnesia bug: each user message currently spawns a fresh Agent SDK `query()` with no memory of prior exchange. `persistSession: false` is explicitly set, and `sendUserMessage` calls `startAgentSession()` which creates a brand-new agent every turn. Messages are saved to Supabase but never loaded back.

The fix implements persistent conversation threads where the agent remembers full context across sessions, surviving WebSocket reconnections, server restarts, and multi-day gaps.

## Why This Approach

**Hybrid architecture (SDK resume primary, message replay fallback):**

- SDK `resume` provides full context fidelity including tool execution history — the agent remembers not just what was said but what was done
- Message replay from Supabase provides graceful degradation when SDK sessions expire (container restart, inactivity timeout, redeploy)
- The `session_id` column already exists in the `conversations` table but is never populated — the schema is ready
- A 1-hour spike verifies SDK `resume` behavior in containerized deployment before committing to production code

**Why not replay-only:** Loses tool execution context on every turn. The SDK `query()` V1 API takes a single `prompt` string, not a messages array — history injection is prompt engineering, not a first-class API.

**Why not V2 SDK migration:** `unstable_v2_createSession` may not exist in pinned SDK 0.2.80. "Unstable" API with unclear stability guarantees. Larger migration surface for a critical bug fix.

## Key Decisions

1. **Product promise: Persistent threads.** Conversations are permanent. User returns next day, agent has full context. Not just within-session continuity.

2. **Architecture: Hybrid with SDK-primary.** SDK `resume` as primary path (full context fidelity). Message replay from Supabase as fallback when session expires (graceful degradation with conversational memory, minus tool context).

3. **Cross-domain scope: Single-leader conversations.** Multi-turn is scoped to one domain leader per conversation. Cross-domain routing deferred to tag-and-route (#1.11) — these features share a design surface but can be built independently with this constraint.

4. **Conversation lifecycle: Three close triggers.**
   - Inactivity timeout (e.g., 24 hours) — reclaims server resources
   - Explicit new chat — user starts fresh
   - Work completion — issue/feature/bug fix is done

5. **Data retention: TTL with user control.** Conversations auto-delete after N days (exact duration set by CLO in P2 GDPR work, item 2.9). Users can manually delete anytime. Data model must account for this from the start.

6. **Process: Spike first.** 1-hour empirical spike to verify SDK `resume` works across process restarts in containerized deployment. If session files live outside the persistent `/workspaces/<userId>` volume, pivot approach before writing production code.

## Open Questions

1. **SDK session file location.** Where does `persistSession: true` write files in Docker? If outside the workspace volume, need to configure `sessionFilePath` (if SDK supports it) or accept that resume only works for active sessions.

2. **Context window limits.** Long conversations will eventually exceed the model's context window. Summarization? Truncation? Deferred to implementation but the architecture should accommodate it.

3. **Concurrent session handling.** Current code aborts existing sessions on new message (line 159). With `resume`, abort-and-restart needs to ensure session file integrity.

4. **Exact TTL duration.** CLO to determine in P2. Implementation should parameterize this.

5. **SDK 0.2.80 compatibility.** Spike must verify `resume` option exists at this pinned version.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Option 1 (SDK session resume) is the right first move. The SDK provides a first-class `resume` option, the DB schema already has `session_id`, and the change is ~30 lines in `agent-runner.ts`. Critical risk: session files are on container filesystem and lost on restart — a 1-hour spike must verify storage location and cross-restart behavior before production code. Estimated 1-2 days including spike.

### Product (CPO)

**Summary:** "This is not a feature. It is a prerequisite for the product to exist." The architecture choice propagates to 5+ downstream roadmap items across 3 phases (GDPR account deletion, session lifecycle policy, conversation inbox, tag-and-route, legal PII surface). Recommends spec before implementation to document data model implications. Key product questions: conversation scope (resolved: single-leader), lifetime (resolved: timeout + close + completion), retention (resolved: TTL with user control).

## Downstream Dependencies

| Dependency | Phase | Impact |
|-----------|-------|--------|
| GDPR account deletion (2.4, 2.9) | P2 | Must purge conversation history. TTL policy helps scope this. |
| Session lifecycle policy (2.3) | P2 | Session timeout depends on knowing what a "session" is post-fix. |
| Conversation inbox (3.3) | P3 | Inbox renders threads. Multi-turn must produce a renderable data structure. |
| Tag-and-route (1.11) | P1 | Single-leader constraint avoids design conflict. Cross-domain deferred. |
| Legal: conversation PII (2.9) | P2 | More retained context = more PII. TTL with user control mitigates. |
