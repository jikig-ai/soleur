# Spec: Conversation State Management

**Issue:** #1962
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-11-conversation-state-management-brainstorm.md`

## Problem Statement

The conversation command center has two usability issues: (1) some conversations
display as "Untitled" because the title derivation function lacks a meaningful
fallback chain, and (2) users cannot change conversation state — failed
conversations show "Needs attention" indefinitely with no escape hatch. A third
root cause is that empty conversations (session errored before any message) are
created in the database and pollute the inbox.

## Goals

- G1: Every conversation displays a meaningful title
- G2: Users can transition conversations to "completed" from the inbox
- G3: Junk conversations (no messages, only @-mentions) are never persisted

## Non-Goals

- NG1: Bulk state transitions (dismiss all failed)
- NG2: Server-side persisted title column
- NG3: New status values (archived, dismissed)
- NG4: Re-opening completed conversations
- NG5: Renaming conversations

## Functional Requirements

- FR1: `deriveTitle()` uses a 5-step fallback chain: user message content →
  raw message text → assistant message content → domain leader label →
  "Untitled conversation"
- FR2: Status badge is clickable on `failed` and `waiting_for_user` conversations
- FR3: Clicking the badge opens a dropdown with available transitions
- FR4: `failed` → `completed` ("Dismiss"), `waiting_for_user` → `completed`
  ("Mark resolved")
- FR5: Status badge is NOT clickable on `active` conversations (agent running)
- FR6: Completed conversations show no dropdown (terminal state)
- FR7: Conversation DB row is not created until the first user message with
  real content (after stripping @-mentions)
- FR8: Messages that are only @-mentions without additional content do not
  trigger conversation creation

## Technical Requirements

- TR1: Status update uses direct Supabase client (browser) with optimistic UI
- TR2: Must destructure `{ error }` from all Supabase calls (learning: silent
  error return values)
- TR3: Optimistic update captures previous state for rollback on error
- TR4: Realtime subscription (already exists) confirms the update idempotently
- TR5: Follow `share-popover.tsx` pattern for dropdown (useRef + outside-click)
- TR6: No database migration required for status changes
- TR7: Session creation in `ws-handler.ts` deferred to first real message

## Acceptance Criteria

- [ ] No conversation displays as "Untitled" when it has any messages
- [ ] Failed conversations can be dismissed from the inbox via badge click
- [ ] Waiting conversations can be marked resolved from the inbox via badge click
- [ ] Active conversations have non-clickable status badges
- [ ] Completed conversations have no dropdown actions
- [ ] Starting a session that errors before any message creates no conversation row
- [ ] Sending only "@cto" with no other content does not create a conversation
