# Spec: First-Time Onboarding Walkthrough

**Issue:** [#1375](https://github.com/jikig-ai/soleur/issues/1375)
**Brainstorm:** [2026-04-03-onboarding-walkthrough-brainstorm.md](../../brainstorms/2026-04-03-onboarding-walkthrough-brainstorm.md)
**Branch:** onboarding-walkthrough
**Phase:** 2 (Secure for Beta) -- last open item

## Problem Statement

New users land on the Command Center dashboard with no guided path to their first meaningful interaction. The existing UX (suggested prompt cards, hint text) provides passive discovery but no active nudge toward the activation moment: sending an @-mention message to a domain leader. iOS users also lack guidance on installing the PWA.

## Goals

- G1: Drive first-time users to send their first @-mention message within their first session
- G2: Provide iOS Safari users with PWA install guidance
- G3: Track onboarding completion as an activation metric
- G4: Match brand voice -- declarative, bold, no hand-holding

## Non-Goals

- Multi-step guided tour (tour library like Shepherd.js or React Joyride)
- Onboarding for returning users or feature announcements
- Android PWA install guidance (handled natively by the browser)
- Offline onboarding (requires service worker changes)
- Full analytics platform integration (deferred to plan phase for instrumentation decision)

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | Welcome card appears above chat input on first visit (user has no `onboarding_completed_at` value) | P1 |
| FR2 | Welcome card auto-dismisses when user sends their first message | P1 |
| FR3 | Welcome card copy produced by copywriter agent, following brand guide voice | P1 |
| FR4 | @-mention hint text has a pulsing CSS animation on first visit | P2 |
| FR5 | Pulsing animation stops after user's first @-mention interaction | P2 |
| FR6 | iOS Safari PWA install banner appears on first visit for iOS Safari users only | P2 |
| FR7 | PWA banner is dismissible with an x button; dismissal persisted in DB | P2 |
| FR8 | Analytics events fired: onboarding_card_shown, first_message_sent, pwa_banner_shown, pwa_banner_dismissed | P2 |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Add `onboarding_completed_at` (nullable timestamp) and `pwa_banner_dismissed_at` (nullable timestamp) columns to users table via Supabase migration |
| TR2 | iOS Safari detection via user agent string (check for iPhone/iPad + Safari, exclude Chrome/Firefox on iOS) |
| TR3 | No third-party tour or tooltip library dependencies |
| TR4 | Welcome card and PWA banner are React components within the existing dashboard page |
| TR5 | Pulsing animation is pure CSS (Tailwind `animate-pulse` or custom keyframes) |
| TR6 | Analytics events use a lightweight custom event system (implementation details deferred to plan) |

## Acceptance Criteria

- [ ] First-time user sees welcome card above chat input on dashboard
- [ ] Welcome card disappears after user sends first message
- [ ] @-mention hint pulses on first visit, stops after first @-mention
- [ ] iOS Safari user sees PWA install banner; dismissal persists across sessions
- [ ] `onboarding_completed_at` set in DB when first message sent
- [ ] `pwa_banner_dismissed_at` set in DB when PWA banner dismissed
- [ ] No tour library in package.json
- [ ] Welcome card copy approved by copywriter agent
- [ ] Analytics events fire correctly (verified in browser dev tools)

## Test Scenarios

| # | Scenario | Expected |
|---|----------|----------|
| T1 | New user (no onboarding_completed_at) visits dashboard | Welcome card visible, @-mention hint pulsing |
| T2 | User sends first message | Welcome card disappears, onboarding_completed_at set in DB |
| T3 | Returning user (onboarding_completed_at set) visits dashboard | No welcome card, no pulsing hint |
| T4 | iOS Safari user on first visit | PWA install banner visible |
| T5 | Non-iOS user on first visit | No PWA install banner |
| T6 | iOS user dismisses PWA banner | Banner gone, pwa_banner_dismissed_at set in DB, banner stays gone on return |
| T7 | User clears browser data, logs in on new device | Onboarding state preserved (DB-backed), no card shown |
