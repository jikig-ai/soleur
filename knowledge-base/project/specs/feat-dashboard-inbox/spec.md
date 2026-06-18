---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 5512
branch: feat-dashboard-inbox
pr: 5524
brainstorm: knowledge-base/project/brainstorms/2026-06-18-dashboard-inbox-surface-brainstorm.md
wireframes: knowledge-base/product/design/inbox/dashboard-inbox.pen
---

# Feature: Dedicated Inbox Surface (`/dashboard/inbox` list page + nav entry)

## Problem Statement

The operator email-triage inbox surfaces only two ways today: inline on the Dashboard
"Command Center" via `EmailTriageRow` (`dashboard/page.tsx:799`), and as a single-item
deep-link target `/dashboard/inbox/email/[emailId]` reached from notification emails.
There is no `/dashboard/inbox` list route and no nav entry, so a workspace Owner cannot
browse the full inbox as a destination, and the **archived view**
(`GET /api/inbox/emails?status=archived`) is unreachable from the UI entirely.

PR #5494 (ADR-066, migration 111) already made the inbox a shared workspace inbox with
workspace-Owner RLS — so this is a presentation/navigation gap only.

## Goals

- Add a browsable `/dashboard/inbox` list page (default Active view + Archived view).
- Add a top-level "Inbox" nav entry AND a "View all →" link from the Command Center section.
- Make the archived view reachable from the UI for the first time.
- Provide a reassuring empty-state so a usually-empty top-level entry never reads as broken.
- Reuse the existing API and `EmailTriageRow` — no backend, schema, or RLS change.

## Non-Goals

- Any "connect / set up email" capability (per-workspace inbound addresses, Gmail OAuth,
  Proton). The inbox is single-tenant today (one `ops@soleur.ai` address, one hardcoded
  `EMAIL_TRIAGE_OWNER_USER_ID`). Deferred to its own brainstorm (CLO+Ops+CTO).
- Unread/read-state data model or nav badge counts.
- Backend / schema / RLS changes (settled by #5494).
- Pagination beyond the existing `LIST_LIMIT=100` (statutory rows stay uncapped).
- A separate route for archived (it is a tab on the same route).

## Functional Requirements

### FR1: `/dashboard/inbox` list page

A new client page at `app/(dashboard)/dashboard/inbox/page.tsx` that fetches
`GET /api/inbox/emails` and renders each item with the existing `EmailTriageRow`
(`{item, onChanged}`), passing a refetch callback as `onChanged`. Header mirrors the
Routines template (h1 "Inbox" + one-line description, centered column). Links each row to
the existing detail route. Maps to wireframe `09-dashboard-inbox-active-populated.png`.

### FR2: Active / Archived tabs driving `?status=archived`

A tab control (Active | Archived) on the page. Active is default; selecting Archived sets
the `?status=archived` URL query param and fetches `GET /api/inbox/emails?status=archived`.
The view is shareable/deep-linkable via the query param. Probe rows stay hidden (no
`?include_probes`). Archived wording must NOT imply deletion/erasure — use "Archived —
still retained" / "Done". Maps to wireframes 09 (Active) + `10-dashboard-inbox-archived-retained.png`.

### FR3: Top-level "Inbox" nav entry

Add `{ href: "/dashboard/inbox", label: "Inbox", icon: <InboxIcon> }` to `NAV_ITEMS`
(`app/(dashboard)/layout.tsx:95`). Active-state follows the existing `pathname.startsWith`
convention. Confirm `segmentToDrillLevel("/dashboard/inbox")` resolves to a sane (default)
drill level (no secondary rail). Icon from the existing icon module.

### FR4: Command Center "View all →" link

Add a "View all →" link to the existing inbox `EmailTriageRow` section header on the
Dashboard (`dashboard/page.tsx:~796`) pointing to `/dashboard/inbox`. Maps to wireframe
`12-command-center-inbox-view-all-link.png`.

### FR5: Reassuring empty-state

When the fetch returns zero items, render a calm empty-state ("No items needing attention"
+ supporting line), NOT a broken/blank page and NOT a connect-email CTA. Empty-state render
keys on the inbox fetch alone (decoupled from unrelated async). Maps to wireframe
`11-dashboard-inbox-empty-active.png`.

## Technical Requirements

### TR1: Client component, reuse the bounded API

Use CTO option A — a client page that fetches `/api/inbox/emails`, mirroring
`dashboard/page.tsx`'s `emailItems`/`fetchEmailItems` pattern. Do NOT re-implement the
route's filter logic (unfinalized-stub / probe / statutory-pin exclusion, `route.ts:18-44`)
in the page. Do NOT add `.eq("user_id", ...)` anywhere (would re-narrow below workspace
RLS and hide co-Owner rows — ADR-066).

### TR2: Visible error + retry, Sentry-mirrored

On non-2xx / network failure, render a visible error state with retry (mirror the
dashboard `ErrorCard` pattern, `dashboard/page.tsx:770`). Any client-side catch that
degrades silently MUST mirror to Sentry (`cq-silent-fallback-must-mirror-to-sentry`). The
server route already routes failures through `reportSilentFallback` → Sentry (`route.ts:71-78`).

### TR3: Statutory visibility preserved

The list must never paginate or filter a statutory item out of sight. The API pins
unacknowledged statutory rows uncapped (`route.ts:31-44`); the page must render them
(pinned-first ordering is preserved by the API response order).

### TR4: e2e harness mock

The new client fetch of `/api/inbox/emails` on an e2e-covered dashboard route must be added
to `setupNavMocks` (an unmocked fetch wedges the dev server → goto-timeout cascade). Use a
valid UUID for `MOCK_USER.id`. (Ref: learnings 2026-06-11 WORM/e2e-mock, 2026-06-03 fetch-coalescing.)

### TR5: Tests first

Per `cq-write-failing-tests-before` + `rf-never-skip-qa-review`: write failing tests for
the list page (Active/Archived fetch, empty-state, error+retry, nav entry render) before
implementation.

## Acceptance Criteria

- Top-level "Inbox" nav entry renders and is active on `/dashboard/inbox`.
- `/dashboard/inbox` lists Active items; Archived tab loads `?status=archived` and is deep-linkable.
- Empty-state renders reassuring copy (no connect CTA) when zero items.
- Archived view never uses deletion/erasure wording.
- Probe rows are hidden by default; statutory pinned rows render.
- Command Center "View all →" link navigates to `/dashboard/inbox`.
- Client fetch failure shows a visible error+retry and mirrors to Sentry.
- No backend/schema/RLS change; no `.eq("user_id")` filter added.
- Wireframes (09–12) committed; observability-coverage-reviewer passes pre-merge.
