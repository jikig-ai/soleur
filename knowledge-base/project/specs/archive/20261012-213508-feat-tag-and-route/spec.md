# Feature: Tag-and-Route UX Model

## Problem Statement

The current web platform uses a "department offices" model: the dashboard displays 8 domain leader cards, each linking to a dedicated chat page (`/dashboard/chat/new?leader={id}`). The database enforces a single leader per conversation (`domain_leader NOT NULL` with CHECK constraint). The WebSocket `start_session` message requires a `leaderId`. The agent runner builds a hardcoded single-leader system prompt.

This model forces the founder to know which department to visit before asking a question, breaks multi-domain conversations, provides no context from the page being viewed, and creates a UX that must be torn down for the target model.

## Goals

- Founder can start conversations from any context (KB viewer, dashboard, roadmap) with domain leaders auto-detected
- Multiple leaders can respond in the same conversation thread as separate attributed messages
- Routing reuses the proven brainstorm domain-config assessment questions
- Full artifact content is injected when conversations start from a context page
- Chat is available as both a persistent sidebar and full-page view
- @-mention override allows founder to explicitly tag leaders
- Data model supports multi-leader, context-aware conversations from day one
- Public framing shifts to "One command center, 8 departments"

## Non-Goals

- Cross-conversation context sharing (conversations are independent)
- User-configurable routing rules (auto-detection only, with @-mention override)
- Mobile-optimized responsive design (desktop-first for P1)
- Conversation search/inbox UI (P3, item 3.3)
- AI-generated conversation summaries
- Voice input/output

## Functional Requirements

### FR1: Contextual conversation creation

Conversations can be started from any page. The source context (artifact path, page type, artifact content) is captured and associated with the conversation. Leaders receive the full artifact content in their system prompt.

### FR2: Auto-routing via domain assessment

Each user message is analyzed against the brainstorm domain-config assessment questions to determine which 1-N domain leaders should respond. The routing layer selects the most relevant leaders per message.

### FR3: Multi-leader responses

Multiple leaders can respond to a single user message. Each response is a separate message bubble attributed to a specific leader (with name/avatar). Responses may stream in parallel.

### FR4: @-mention override

Founder can explicitly tag leaders using @-mention syntax (e.g., @CLO, @CTO). When @-mentions are present, only the mentioned leaders respond, overriding auto-detection.

### FR5: Persistent chat sidebar

A collapsible chat panel is available on every page, inheriting the current page's context. The sidebar can be expanded to a full-page chat view. Conversations persist across page navigation.

### FR6: Full-page chat view

A dedicated full-page chat view for deep conversations. Sidebar conversations can be "expanded" to full-page. Full-page conversations can be "collapsed" to sidebar.

### FR7: Dashboard transformation

The dashboard evolves from an 8-card grid to a command center. The chat input is the primary interaction element. Domain leaders are still discoverable but not the primary navigation.

## Technical Requirements

### TR1: Schema migration

- `conversations.domain_leader` becomes nullable (remove NOT NULL constraint and CHECK)
- Add `conversations.context_path` (text, nullable) — artifact path that started the conversation
- Add `conversations.context_type` (text, nullable) — page type (kb-viewer, dashboard, roadmap)
- Add `messages.leader_id` (text, nullable) — which leader authored this assistant message
- Add `conversation_leaders` junction table for tracking which leaders have participated

### TR2: WebSocket protocol changes

- `start_session` no longer requires `leaderId` — becomes optional (for @-mention only)
- Add `context` field to `start_session` (artifact path, content, page type)
- Support streaming multiple leader responses per user message, each tagged with `leader_id`
- Add message type for routing metadata (which leaders were selected and why)

### TR3: Routing layer

- Port brainstorm domain-config assessment questions to a server-side routing module
- Input: user message text + conversation context
- Output: list of 1-N relevant leader IDs, ranked by relevance
- Support @-mention parsing as override

### TR4: Agent runner refactor

- Support running multiple agent sessions (one per leader) for a single user message
- Each session gets: conversation history, artifact context, leader-specific system prompt
- Responses attributed to specific leaders in the message stream

### TR5: Context injection

- When a conversation starts from a context page, fetch the full artifact content
- Inject artifact content into each responding leader's system prompt
- Context persists across the conversation (not just the first message)

### TR6: Client-side chat components

- Sidebar component: collapsible panel, inherits page context, available on all pages
- Full-page component: expanded view with full message history
- Message attribution: leader name, avatar/icon, domain color per message bubble
- @-mention autocomplete in chat input
