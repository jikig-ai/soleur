# Tasks: Tag-and-Route UX Model (#1059)

## Phase 1: Data Model + Types (Foundation)

- [ ] 1.1 Create schema migration `010_tag_and_route.sql`
  - [ ] 1.1.1 ALTER conversations: drop NOT NULL and CHECK on domain_leader
  - [ ] 1.1.2 ADD leader_id column to messages
- [ ] 1.2 Update TypeScript types (`lib/types.ts`)
  - [ ] 1.2.1 Conversation.domain_leader → nullable
  - [ ] 1.2.2 Add leader_id to Message
  - [ ] 1.2.3 Update WSMessage start_session (leaderId optional, add context)
  - [ ] 1.2.4 Add required leaderId to stream message type
  - [ ] 1.2.5 Add stream_start / stream_end message types (per-leader lifecycle)
- [ ] 1.3 Update existing server code for nullable domain_leader
  - [ ] 1.3.1 ws-handler.ts: createConversation() — leaderId optional
  - [ ] 1.3.2 agent-runner.ts: sendUserMessage() — handle null domain_leader
  - [ ] 1.3.3 agent-runner.ts: startAgentSession() — leaderId optional
- [ ] 1.4 Verify all existing tests pass with nullable changes

## Phase 2: Domain Router (Routing Logic)

- [ ] 2.1 Create `server/domain-router.ts`
  - [ ] 2.1.1 Port assessment questions from brainstorm-domain-config.md
  - [ ] 2.1.2 Implement routeMessage() — Claude API classification call
  - [ ] 2.1.3 Implement parseAtMentions() — @-mention extraction
  - [ ] 2.1.4 Implement leader ranking and cap (max 3)
- [ ] 2.2 Write tests for domain-router
  - [ ] 2.2.1 Test @-mention parsing (case-insensitive, invalid mentions)
  - [ ] 2.2.2 Test routing classification (mock Claude API response)
  - [ ] 2.2.3 Test @-mention override (explicit > auto-detect)

## Phase 3: Agent Runner Refactor (Multi-Leader Support)

- [ ] 3.1 Create dispatchToLeaders() function
  - [ ] 3.1.1 Parallel dispatch via Promise.allSettled
  - [ ] 3.1.2 Each leader gets own system prompt + context
  - [ ] 3.1.3 Send stream_start before each leader streams
  - [ ] 3.1.4 All stream chunks include required leaderId
  - [ ] 3.1.5 Send stream_end when each leader completes
- [ ] 3.2 Refactor sendUserMessage() to use router
  - [ ] 3.2.1 Call routeMessage() before dispatching
  - [ ] 3.2.2 Call dispatchToLeaders() instead of single session
- [ ] 3.3 Update saveMessage() for leader attribution
- [ ] 3.4 Add context injection to system prompt
- [ ] 3.5 Write tests for multi-leader dispatch

## Phase 4: WebSocket Protocol Changes

- [ ] 4.1 Server: update start_session handler
  - [ ] 4.1.1 leaderId optional, add context field
- [ ] 4.2 Server: stream_start/stream/stream_end all include leaderId
- [ ] 4.3 Client: update useWebSocket hook
  - [ ] 4.3.1 startSession() accepts optional leaderId + context
  - [ ] 4.3.2 ChatMessage type gets leaderId field
  - [ ] 4.3.3 Replace single streamIndexRef with Map<DomainLeaderId, number>
  - [ ] 4.3.4 Handle stream_start → create new bubble, record in map
  - [ ] 4.3.5 Handle stream → use leaderId to find correct bubble
  - [ ] 4.3.6 Handle stream_end → finalize bubble, remove from map
- [ ] 4.4 Update WebSocket protocol tests

## Phase 5: UI Components

- [ ] 5.1 Message attribution in chat page
  - [ ] 5.1.1 Add leader name/icon to MessageBubble
  - [ ] 5.1.2 Domain color coding per leader
- [ ] 5.2 Dashboard transformation
  - [ ] 5.2.1 Replace leader grid with command center chat input
  - [ ] 5.2.2 Leader discovery as secondary element
  - [ ] 5.2.3 Update heading/copy to "Command Center"
- [ ] 5.3 KB viewer context injection
  - [ ] 5.3.1 Capture artifact path and content
  - [ ] 5.3.2 Pass as transient context in start_session

## Deferred (follow-up PRs)

- Chat sidebar (collapsible panel on every page)
- @-mention autocomplete dropdown
- routing_info status pill
- conversation_leaders junction table
- context_path/context_type DB columns
