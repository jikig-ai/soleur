# Feature: Chat UX Redesign

## Problem Statement

The Command Center dashboard requires users to navigate through a department selection screen (8 leader cards) before they can start chatting. This adds unnecessary friction — extra clicks to reach the primary interaction. The @-mention routing system already exists server-side but has no client-side UX (no autocomplete, no visual hints). Users must know to type `@CMO` manually.

## Goals

- Remove the department grid as the primary entry point — the chat input IS the primary interaction
- Surface @-mention autocomplete with rich leader descriptions as the discovery mechanism
- Preserve discoverability of all 8 departments without requiring a separate screen
- Support auto-routing (system detects relevant leaders) as the default, @-mentions as the override

## Non-Goals

- Multi-session management / conversation inbox (deferred to #672, roadmap item 3.3)
- Conversation search or filtering
- Custom leader configurations or user-defined departments
- Mobile app (native) — web responsive only

## Functional Requirements

### FR1: Chat-First Dashboard

The dashboard replaces the department grid with a centered chat input as the hero element. Users can start typing immediately without clicking anything first. A headline communicates the product's purpose. Four suggested prompt cards show example use cases with which leaders would respond, teaching the auto-routing mental model.

### FR2: @-Mention Autocomplete

When the user types `@` in the chat input, a dropdown appears showing matching leaders. Each entry displays: color-coded avatar, abbreviation (CMO), full title (Chief Marketing Officer), and scope description (GTM, content, brand, growth). The dropdown filters as the user types (e.g., `@cm` shows CMO and CCO). Maximum 8 results (all leaders). Keyboard navigation supported.

### FR3: Department Discoverability Strip

A subtle "YOUR ORGANIZATION" section at the bottom of the empty state lists all 8 department abbreviations. This ensures a new user can learn what's available without requiring the @-mention dropdown.

### FR4: Multi-Leader Response Attribution

When multiple leaders respond, each gets a distinct message bubble with: colored left border, colored name badge with abbreviation, full title on first appearance. A routing badge at the top of the conversation shows "Auto-routed to CMO, CRO, CPO" or similar.

### FR5: Conversation Sidebar

A persistent collapsible sidebar available on every page (KB viewer, roadmap, dashboard). Collapsed state: chat icon with notification badge on the right edge. Expanded state: narrow chat panel with context banner showing what page content was injected (e.g., "Context: Product Roadmap").

### FR6: Mobile Experience

Full-page chat on mobile (no sidebar). Dedicated `@` button next to the send button for easier mention access on mobile keyboards. Same color-coded leader attribution. Status bar showing "N leaders responding."

## Technical Requirements

### TR1: Reuse Existing Server-Side Routing

The `domain-router.ts` already implements `parseAtMentions()` and Claude API auto-classification. No server-side routing changes needed — this is a client-side UX layer on top of existing infrastructure.

### TR2: Client-Side @-Mention Component

Build a React component for the chat input that:

- Detects `@` character and triggers autocomplete dropdown
- Reads leader metadata from `domain-leaders.ts` for display
- Inserts the selected leader ID into the message text
- Supports keyboard navigation (arrow keys, enter to select, escape to dismiss)

### TR3: Remove Department Grid Page

Remove or repurpose the dashboard page that renders the 8-leader card grid. The `/dashboard` route should render the new chat-first experience. Existing deep links to `/dashboard/chat/new?leader=cmo` should continue to work.

### TR4: Sidebar Integration

Add a collapsible chat sidebar component to the dashboard layout. When opened from a context page (KB viewer, roadmap), inject the current page content as conversation context via the existing `start_session` WebSocket message.

### TR5: Responsive Design

Tailwind breakpoints: sidebar visible on `lg:` and above, full-page chat on smaller screens. The `@` button appears only on mobile viewports where the on-screen keyboard makes typing `@` less discoverable.

## Design Artifacts

- Wireframes: `knowledge-base/product/design/command-center/chat-ux-redesign.pen`
- Screenshots: `knowledge-base/product/design/command-center/screenshots/`
  - `01-dashboard-empty-state.png` — Chat-first landing with suggested prompts
  - `02-at-mention-autocomplete.png` — @-mention dropdown with filtered results
  - `03-active-conversation-multi-leader.png` — Multi-leader response thread
  - `04-conversation-sidebar.png` — Collapsed and expanded sidebar states
  - `05-mobile-experience.png` — Full-page mobile chat

## Related

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-27-tag-and-route-brainstorm.md`
- Closed issue: #1059 (brainstorm completed, implementation not shipped)
- Roadmap: Phase 2, item 3.9 (tag-and-route UX enhancements)
- Depends on: #672 for conversation inbox (deferred)
