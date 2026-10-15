# Conversation History Visibility in Command Center

**Date:** 2026-04-12
**Status:** Decided
**Participants:** Founder, CPO, CMO

## What We're Building

A UX fix to the Command Center dashboard that shows conversation history alongside incomplete foundation cards. Currently, the foundations state (`page.tsx`) renders as a full-page gate that completely hides the conversation inbox when any foundation is incomplete. Returning users see only foundation cards and a "New conversation" button, with no access to their past conversations.

This is not a new feature — the conversation inbox (roadmap 3.3) shipped via PR #1759 on 2026-04-07, including status badges, filters, archiving (#1990), and conversation state management (#1962). The inbox is fully functional but invisible when foundations are incomplete.

## Why This Approach

The foundation-card gate creates two problems:

1. **Moat invisibility (Theme T3):** Returning users see the same empty-state hero as first-time visitors. The platform's core value — that every session builds on the last — is invisible.
2. **UX confusion:** Users think conversation history doesn't exist. The gate gives no signal that an inbox will appear.

The fix is minimal: restructure the foundations state to render both foundation cards AND the conversation list on the same page, rather than treating them as mutually exclusive states.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Show conversations below foundation cards | Both concerns (foundations + history) belong on the Command Center page. Hiding one for the other loses context. |
| 2 | Always show conversation section (even when empty) | Sets the expectation that history will appear. A placeholder like "No conversations yet" teaches the mental model. |
| 3 | No backend changes needed | The conversation list API, hooks (`useConversations`), and `ConversationRow` component already exist. This is a layout change only. |
| 4 | Keep foundation cards as a visible nudge, not a gate | Foundation cards remain prominent at the top but don't block access to other Command Center functionality. |

## Open Questions

- Should foundation cards become collapsible/dismissible once the user has seen them a few times?
- At what point should foundation cards disappear entirely (all complete? user dismisses?)?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** The conversation inbox already shipped (3.3, #1690). The user is seeing the foundation-card gate, not a missing feature. Recommended confirming with the user, then fixing the empty-state discoverability. Flagged that roadmap Current State section is stale (claims P1.5/P2 are open, but both milestones are closed since 2026-04-03).

### Marketing (CMO)

**Summary:** The foundation gate undermines the "compounding knowledge" brand thesis — returning users see a blank slate instead of organizational activity. Status badges create re-engagement psychology (Zeigarnik Effect). The inbox with domain leader context is screenshot-ready differentiation vs. competitors. Flagged legal dependency (2.9: conversation history in privacy docs) and copy review needed for any new strings.
