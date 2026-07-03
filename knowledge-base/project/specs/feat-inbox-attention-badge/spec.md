---
title: Inbox attention-count badge (remove dashboard "Needs attention" pager)
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-03-inbox-attention-badge-brainstorm.md
design: knowledge-base/product/design/dashboard-nav/inbox-attention-badge.pen
created: 2026-07-03
---

# Spec: Inbox attention-count badge

## Problem Statement

The Dashboard renders an email-triage "Needs attention" list (`apps/web-platform/app/(dashboard)/dashboard/page.tsx:790-815`) that duplicates the Inbox's Active view — same data, same SWR cache key (`swrKeys.inboxEmails("active")`), same `EmailTriageRow`, per ADR-067. For an operator with many triaged emails (e.g. Sentry notification mail such as *WEB-PLATFORM-4B*), this block dominates the screen and makes the Dashboard read as a confusing alert pager. Now that the Inbox is a first-class left-nav destination, the attention items belong there, surfaced as a count — not spread across the Dashboard.

## Goals

- **G1.** Remove the email-triage "Needs attention" block from the Dashboard, keeping the rest of the Dashboard intact (Today section, Foundation cards, filter bar, conversation list).
- **G2.** Add a numeric count badge to the Inbox left-nav item showing the number of active (unarchived) inbox items (`status <> 'archived'`).
- **G3.** The badge count equals what the Inbox "Active" tab shows for the same workspace — one shared source of truth, no drift.
- **G4.** The badge auto-updates on window-focus and immediately after an archive/acknowledge, reusing the existing SWR cache (no new backend).
- **G5.** The badge works in both the expanded (240px) and collapsed (56px, icon-only) rail states.

## Non-Goals

- **NG1.** Live badge update on brand-new inbound email (no realtime/polling on `email_triage_items` today). → deferred fast-follow issue.
- **NG2.** Badges on any other nav item (Workstream, KB, Routines, Analytics). Establish the pattern on Inbox only.
- **NG3.** Any change to `email_triage_items`, its RLS, the `/api/inbox/emails` route, or the triage lifecycle. Purely presentational.
- **NG4.** Redefining "needs attention" (e.g. unacknowledged-only). Count is the full active feed.

## Functional Requirements

- **FR1.** Delete the email-triage "Needs attention" block (`page.tsx:790-815`) and its now-orphaned wiring (`emailItems`, `fetchEmailItems`, and the `fetchInboxItems` import if unused elsewhere in the file). Wireframe: `inbox-attention-badge.pen` frame 1 (dashboard unaffected regions stay).
- **FR2.** Render a count badge on the Inbox nav item (`layout.tsx:404-442` map). Count = `items.length` of the active `/api/inbox/emails` feed via `swrKeys.inboxEmails("active")`. Wireframe frame 1 (expanded, trailing pill after label).
- **FR3.** Zero-state: omit the badge entirely when count is 0 — never render an empty pill. Wireframe frame 3.
- **FR4.** Collapsed rail: show a corner-overlay dot / mini-count on the Inbox icon's top-right with a 2px `#141414` ring. Wireframe frame 2.
- **FR5.** Badge visual: neutral `#2f2f2f` pill, white 11px/600 text, radius 999, ~18px height, `min-width = height` (single digit reads as a circle); large counts cap at `99+`. Gold is NOT used (reserved for active-state). Wireframe frame 3.
- **FR6.** A failed count fetch must not render as a false "0" — omit the badge (or a distinct error affordance), never silently claim zero attention items.

## Technical Requirements

- **TR1.** The badge count hook MUST mount inside the same `InboxDataCacheProvider` / `SWRConfig` as the Inbox page (ADR-067, `layout.tsx:255`) so the fetch dedups with the Inbox and cannot diverge. Verify the nav map is a descendant of that provider before wiring; if not, restructure minimally so it is.
- **TR2.** Keep `nav-items.ts` as pure route/label data. Prefer extending `NavItem` with an optional badge flag consumed by the layout, or special-case the Inbox item inline in the layout map — whichever is least invasive. Do not push a data-fetch into the shared `nav-items.ts` module.
- **TR3.** Reuse the existing `fetchInboxItems` fetcher and `swrKeys.inboxEmails("active")` key — no new API route, no migration, no new Supabase count query.
- **TR4.** No change to the `/api/inbox/emails` route, `email_triage_items` schema, or RLS.

## Acceptance Criteria

- Dashboard no longer shows the "Needs attention" email-triage block; Today/Foundation/conversation list unchanged.
- Inbox nav item shows a neutral count pill equal to the Inbox Active-tab item count; badge disappears at 0.
- Archiving/acknowledging an item (from the Inbox) decrements the badge without a full reload.
- Badge renders correctly in expanded and collapsed rail.
- No new network route; the count reuses the shared SWR cache (verifiable: no duplicate `/api/inbox/emails` request when both nav badge and Inbox are mounted).
- `user-impact-reviewer` passes: count is honest (matches the list; a fetch error does not read as 0).
