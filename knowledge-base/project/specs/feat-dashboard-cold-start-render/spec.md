---
feature: dashboard-cold-start-render
lane: single-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-25-dashboard-cold-start-render-brainstorm.md
status: draft
created: 2026-06-25
---

# Dashboard Cold-Start Render Unblock — Spec

## Problem Statement

On cold start (notably after a computer restart), the dashboard shows a
full-screen loading skeleton for several seconds before any content appears. The
entire page is gated behind the `GET /api/kb/tree` fetch via the `kbLoading`
early-return at `apps/web-platform/app/(dashboard)/dashboard/page.tsx:421`. That
fetch is uncached (the service worker skips `/api/*`) and sits behind a serial
per-request auth waterfall in `middleware.ts` (getUser → revocation RPC → users
SELECT) plus a token refresh after restart — yet its data only drives
foundation-card completion checkmarks, not the primary conversation list.

## Goals

- G1: The dashboard renders its real content (shell + conversation list /
  empty-state) on cold start without waiting for `/api/kb/tree`.
- G2: Foundation-card completion checkmarks fill in asynchronously once the KB
  tree resolves, with a localized loading/placeholder state for the cards only.
- G3: No regression to the provisioning (503) screen, error states, or the
  first-run experience.

## Non-Goals

- NG1: No persistent client-side cache (localStorage/IndexedDB). Revisits
  ADR-067 in-memory-only decision — out of scope.
- NG2: No changes to `middleware.ts` auth waterfall or `/api/kb/tree` latency.
- NG3: No service-worker changes.

## Functional Requirements

- FR1: Remove the unconditional full-page `kbLoading` skeleton early-return as
  the gate for the whole dashboard. The page's loading gate is the
  **conversation-list** load (`useConversations` `loading`), not the KB-tree
  load.
- FR2: While `kbData === undefined` (KB tree not yet resolved) the page MUST NOT
  enter the first-run empty state (`!visionExists && conversations.length === 0`
  …). `visionExists` is unknown during this window; treat unknown as
  "not-yet-first-run" so an existing user never flashes the
  "Tell your organization what you're building" screen.
- FR3: Foundation/operational cards render with a localized placeholder (or are
  hidden) while their backing `kbFiles` is still loading, then populate when the
  tree resolves — without a jarring layout shift.
- FR4: Preserve the `kbError === "provisioning"` (503) "Setting up your
  workspace…" screen and the existing conversation error/empty/filtered states.

## Technical Requirements

- TR1: Change is confined to `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  render flow (and small presentational tweaks to the foundation section if a
  loading placeholder is added). No server, middleware, or caching changes.
- TR2: Preserve the 401 → `/login` redirect behavior (currently the
  `DashKbTreeError("redirect")` path holds the skeleton through navigation) — an
  unauthenticated cold load must still redirect cleanly, not render dashboard
  chrome.
- TR3: Verify no other consumer depends on `kbFiles`/`visionExists` before first
  paint beyond foundation-card derivation (grep during implementation).

## Acceptance Criteria

- AC1: On a throttled cold load with an existing account + conversations, the
  conversation list paints without waiting for `/api/kb/tree` to resolve.
- AC2: An existing user never sees the first-run empty state flash during the
  KB-tree load window.
- AC3: Foundation-card checkmarks appear once the tree resolves; no layout-shift
  regression.
- AC4: Provisioning (503), 401-redirect, and conversation-error states behave as
  before.
