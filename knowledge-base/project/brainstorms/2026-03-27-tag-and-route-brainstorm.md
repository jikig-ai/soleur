# Tag-and-Route UX Model Brainstorm

**Date:** 2026-03-27
**Issue:** #1059
**Status:** Complete
**Branch:** feat/tag-and-route

## What We're Building

A unified conversation model where domain leaders are contextually routed to the founder, replacing the current "department offices" pattern (8 separate leader cards linking to dedicated chat pages). The North Star: the founder runs the company from one command center, and the right experts show up based on context.

### Core Concept

Instead of navigating to a department to talk to its leader, the founder starts a conversation from any context (KB viewer, roadmap, dashboard) and the system auto-detects which leaders should respond. Multiple leaders can respond in the same thread as separate message bubbles, like a group chat with domain experts.

## Why This Approach

### Meta-Router Pattern

Chosen over Router Agent (single meta-voice) and Progressive Enhancement (incremental rollout) because:

1. **Reuses proven routing logic** — the brainstorm domain-config already has assessment questions per domain that determine relevance from natural language. This is the routing layer, applied to user messages instead of feature descriptions.
2. **Preserves domain leader personality** — each leader responds as themselves with their own bubble/avatar, maintaining the "full AI organization" brand positioning.
3. **Matches the CLI pattern** — the Claude Code plugin already does contextual domain routing in brainstorm Phase 0.5. The web platform gets the same intelligence.

### Alternatives Considered

- **Router Agent Pattern:** Single meta-agent consolidates responses. Simpler architecture but loses multi-voice UX. Doesn't match the "organization" metaphor.
- **Progressive Enhancement:** Build incrementally across P1/P2/P3. Safest but three migration steps create throwaway UX. The user explicitly chose to build the full meta-router in P1.

## Key Decisions

1. **Multi-domain threading model:** Unified thread, multi-voice. All tagged leaders respond in the same thread as separate message bubbles. System auto-detects which 1-N leaders should respond to each message.

2. **Routing control:** System auto-decides using brainstorm domain-config assessment questions. No explicit @-tagging required (but supported as override). Cap at most relevant leaders per message.

3. **Response attribution:** Multiple bubbles — each leader gets their own message bubble with name/avatar attribution. Not consolidated into a single response.

4. **Context inheritance:** Full artifact content. When a conversation starts from a context page (KB viewer, roadmap), the full artifact being viewed is injected into the conversation context. Leaders respond as if they've read it.

5. **Chat UI placement:** Both sidebar + full page. Persistent collapsible sidebar for quick questions on every page, full-page view for deep conversations. Sidebar conversations can be expanded to full page.

6. **Entry points:** Chat available from everywhere — KB viewer, dashboard, roadmap, and any future page. Context auto-detected from the page being viewed.

7. **Public framing:** "One command center, 8 departments." Keeps departments as a scope descriptor but leads with the unified experience. Dashboard becomes the command center.

8. **P1 scope:** Full meta-router implementation. Refactor data model, build routing layer, multi-leader responses, contextual sidebar, @-mentions. Reuse brainstorm domain-config routing pattern extensively.

9. **@-mention override:** Founder can explicitly tag leaders (e.g., @CLO) to override auto-routing. Auto-routing is the default; @-mentions are the escape hatch.

10. **Multi-turn dependency:** Resolved — #1044 is merged. Persistent sessions enable routing context to accumulate across turns.

## Open Questions

1. **Routing accuracy in free-form conversation:** The brainstorm domain-config assessment questions are designed for feature descriptions, not arbitrary user messages. "Help me draft an email to a vendor" needs to route to CMO, not COO. How much adaptation is needed?

2. **Latency of multi-leader responses:** Multiple parallel agent calls per user message increases latency and cost. Should there be a budget/cap on how many leaders respond? Should responses stream in parallel or sequentially?

3. **Conversation history for context:** When a leader joins a conversation mid-thread (e.g., CTO auto-detected on turn 5), how much prior context do they get? Full thread? Summary? Just the triggering message?

4. **Dashboard transformation:** The current dashboard is a grid of 8 leader cards. How does it become a "command center"? Does the grid disappear entirely, or does it become a secondary navigation below the chat?

5. **Mobile/responsive design:** A sidebar + full-page dual mode has responsive design implications. What's the mobile experience?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Every layer has hard-coded single-leader assumptions (DB CHECK constraint, WebSocket `start_session` requiring `leaderId`, agent-runner building single-leader system prompts). Multi-turn dependency (#1044) now resolved. Schema migration is safe to do before beta signups. The brainstorm domain-config routing pattern is the right server-side model to reuse.

### Product (CPO)

**Summary:** No spec existed prior to this brainstorm. Roadmap is consistent (P1 item 1.11, P3 item 3.9). Business validation already confirmed (PIVOT verdict). The brainstorm domain-config proves domain detection works in controlled contexts — needs adaptation for free-form conversation. Auto-detection accuracy is the key risk; @-mention override is the mitigation.

### Marketing (CMO)

**Summary:** HIGH concern — "departments" metaphor is baked into all content (hero, stats, meta tags, 15+ published pieces). "Choose a domain leader" copy describes the exact UX being deprecated. Opportunity: "One command center" is a stronger positioning upgrade. All public surfaces mentioning the old interaction model must be updated at P1 ship. SEO keyword continuity should be checked before deprecating "departments" from headings.
