# Brainstorm: Inbox attention-count badge (remove dashboard "Needs attention" pager)

**Date:** 2026-07-03
**Branch:** feat-inbox-attention-badge
**PR:** #5931 (draft)
**Lane:** cross-domain (auto, per #5175)

## What We're Building

Move the "Needs attention" list off the main Dashboard and surface it as a **count badge on the Inbox left-nav item** instead.

Today the Dashboard renders an email-triage "Needs attention" block (`dashboard/page.tsx:790-815`) that duplicates the Inbox's Active view — same data, same SWR cache key (`swrKeys.inboxEmails("active")`), same `EmailTriageRow` component, per ADR-067. On an operator with many triaged emails (e.g. Sentry notification emails like *WEB-PLATFORM-4B*), this block dominates the screen and makes the Dashboard read as a confusing alert pager.

The change:
1. **Delete** the email-triage "Needs attention" block from the Dashboard (`page.tsx:790-815`, plus the now-orphaned `emailItems`/`fetchEmailItems` wiring and the `fetchInboxItems` import).
2. **Add a numeric count badge** to the Inbox nav item = the number of active (unarchived) inbox items. Reuses the existing shared SWR key so the badge and the Inbox can never disagree, and updates on window-focus / right after an archive-or-acknowledge for free.

Everything else on the Dashboard stays (Today section, Foundation cards, filter bar, conversation list).

## Why This Approach

- **The data is already unified.** The Dashboard block and the Inbox share one cache key by design (ADR-067). A badge fed by that same key is the honest, drift-proof representation — no second source of truth.
- **Zero new backend.** Count = `items.length` of the active `/api/inbox/emails` feed. No new endpoint, no new RLS surface, no migration. Purely presentational.
- **YAGNI.** A dedicated `count`-head endpoint was considered and rejected — it adds a route and a second source of truth that can drift from the Inbox list, for a payload win that isn't a measured problem (list is capped at 100).
- **The "View all →" link already pointed at the Inbox**, so users already treat the Inbox as the canonical home for these items. Badging it formalizes what the UI already implied.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Badge count semantics | **Active inbox items** (`status <> 'archived'`) | Mirrors the Inbox "Active" tab exactly; badge can never disagree with the list. Operator-confirmed. |
| Dashboard scope | **Remove only the email-triage block** | Keep Today / Foundation / conversations / filters. Matches "remove all of those." Operator-confirmed. |
| Count mechanism | **Reuse shared SWR key** (`swrKeys.inboxEmails("active")`) in a small nav hook | Zero new API, free dedup, auto-updates on focus/after-mutation. Recommended; adopted as operator was AFK (clear YAGNI winner). |
| Zero-state | **Badge omitted entirely** at count 0 (never an empty pill) | Standard notification-count behavior. |
| Badge color | **Neutral `#2f2f2f` pill, white 11/600 text** | Gold is reserved for the active-state left-bar + active label; a gold badge would blur into the "active" signal. Per wireframe. |
| Collapsed rail | **Corner-overlay dot / mini-count** on the Inbox icon (2px `#141414` ring) | Badge must work in both expanded (240px) and collapsed (56px) rail states. |
| Visual design | Wireframe: `knowledge-base/product/design/dashboard-nav/inbox-attention-badge.pen` (3 frames) | Establishes the first nav-badge pattern in the app. |

## Open Questions (for the plan)

1. **SWR provider scope.** The badge hook must mount *inside* the same `InboxDataCacheProvider` / `SWRConfig` as the Inbox page for cache sharing (layout.tsx:255 mounts it "at a structurally higher level"). Plan must verify the nav `<Link>` map (layout.tsx:404-442) is a descendant of that provider; if not, the count fetch would not dedup with the Inbox and could double-fetch. This is a wiring detail, not a scope change.
2. **Badge data shape.** Extend `NAV_ITEMS` with an optional `badge` hook/flag vs. special-casing the Inbox item inline in the layout map. Plan's call; prefer the least-invasive form that keeps `nav-items.ts` as pure route/label data.
3. **Live-on-inbound refresh** (deferred — see Non-Goals).

## Non-Goals (deferred)

- **Live badge update on brand-new inbound email.** Email-triage has no realtime/polling today (SWR revalidates on focus + after mutation only). Adding a `refreshInterval` or Supabase realtime on `email_triage_items` is a fast-follow, not part of this change. → deferred issue.
- **Badges on other nav items** (Workstream, KB, etc.). Establish the pattern on Inbox first.
- **Changing what "needs attention" means** (e.g. unacknowledged-only). Confirmed as full active list.

## User-Brand Impact

- **Artifact:** the Inbox nav count badge + the Dashboard email-triage surface (`dashboard/page.tsx`, `layout.tsx` nav).
- **Vector:** a miscounted or stale badge under-represents unhandled statutory/legal/security triage items, so the operator misses a time-sensitive item they believed was surfaced — a trust breach in the one surface meant to guarantee "nothing important is hidden."
- **Threshold:** single-user incident.

Tagged **user-brand-critical** (auto, per #5175). Scope is presentational only — no change to `email_triage_items`, its RLS, or the read route — so the exposure is *accuracy of the count*, not data leakage. The load-bearing check is the `user-impact-reviewer` at PR review: the badge count MUST equal what the Inbox Active tab shows for the same workspace, and must not silently swallow a fetch error into a "0" (a failed count must be visually distinct from a genuine zero, or omit rather than lie).

## Domain Assessments

**Assessed:** Engineering, Product, Legal (triad per user-brand-critical). Assessment folded in-line by the brainstorm orchestrator rather than spawning three full domain leaders — the change is a presentational reorg with no data-model, auth, or RLS surface, so a 3-agent fan-out would burn budget without changing the posture. The `user-impact-reviewer` at PR review remains the load-bearing gate.

### Engineering (CTO)

**Summary:** Low-risk, ~2-file change (`dashboard/page.tsx` deletion + `layout.tsx`/`nav-items.ts` badge). Main technical care-point is SWR-provider scope (Open Question 1) — the count hook must share the Inbox's cache to avoid a divergent second fetch. No new endpoint, migration, or realtime. Reuse the existing `fetchInboxItems` + `swrKeys.inboxEmails("active")`.

### Product (CPO)

**Summary:** Directly reduces Dashboard confusion the operator reported. The Inbox already was the canonical destination ("View all →"), so this formalizes existing intent. Establishes the first nav-badge pattern — keep it neutral and scoped to Inbox to avoid badge-proliferation. Zero-state must hide, not show "0".

### Legal (CLO)

**Summary:** Not applicable as a data/compliance surface — no change to what data is stored, who can read it, or retention. One carry-forward: statutory-pinned triage rows must still be reachable and countable; the badge counting the *active* feed (which includes unacknowledged statutory rows) preserves that. No new disclosure surface.
