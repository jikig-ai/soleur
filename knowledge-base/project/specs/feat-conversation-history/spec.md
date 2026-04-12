# Spec: Conversation History Visibility in Command Center

**Issue:** TBD
**Branch:** feat-conversation-history
**Brainstorm:** [2026-04-12-conversation-history-visibility-brainstorm.md](../../brainstorms/2026-04-12-conversation-history-visibility-brainstorm.md)

## Problem Statement

The Command Center dashboard hides the conversation inbox behind a full-page foundation-card gate. When any of the four foundations (Vision, Brand Identity, Business Validation, Legal Foundations) is incomplete, the page renders only foundation cards and a "New conversation" button. Users with past conversations cannot see or access them from the Command Center.

## Goals

- G1: Returning users always see their conversation history on the Command Center
- G2: Foundation cards remain visible as a nudge to complete onboarding
- G3: Empty conversation state sets the expectation that history will appear

## Non-Goals

- New API routes or database changes
- Redesigning the inbox component itself
- Modifying the first-run state (no `vision.md`, no conversations)
- Making foundation cards dismissible (deferred)

## Functional Requirements

| # | Requirement |
|---|-------------|
| FR1 | The foundations state renders foundation cards at the top AND conversation list below |
| FR2 | When conversations exist, the full inbox (filters, ConversationRow, status badges) renders below foundation cards |
| FR3 | When no conversations exist, an empty-state placeholder ("No conversations yet") renders below foundation cards |
| FR4 | The "New conversation" button remains accessible in both states |
| FR5 | Leader strip remains visible below the conversation section |

## Technical Requirements

| # | Requirement |
|---|-------------|
| TR1 | Changes scoped to `apps/web-platform/app/(dashboard)/dashboard/page.tsx` only |
| TR2 | Reuse existing `useConversations` hook and `ConversationRow` component — no new components |
| TR3 | Mobile-first responsive layout (foundation cards + conversation list must work on small viewports) |
