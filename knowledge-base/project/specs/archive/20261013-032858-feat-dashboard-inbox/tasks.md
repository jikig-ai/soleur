---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 5512
branch: feat-dashboard-inbox
plan: knowledge-base/project/plans/2026-06-18-feat-dashboard-inbox-surface-plan.md
---

# Tasks: Dedicated Inbox Surface (`/dashboard/inbox`)

## Phase 1 — Tests first (RED)

- [ ] 1.1 `apps/web-platform/test/inbox-surface.test.tsx` (vitest, happy-dom `component` project; `bun test` blocked). Cover for `<InboxSurface />`:
  - [ ] 1.1.1 Active fetch renders `EmailTriageRow`s in API order (no re-sort).
  - [ ] 1.1.2 Archived tab fetches `?status=archived`; deep-link to `?status=archived` highlights Archived (query-derived active state).
  - [ ] 1.1.3 Active-empty → "No items needing attention"; Archived-empty → "Nothing archived yet"; both gated on `!loading && !error`.
  - [ ] 1.1.4 "Loading…" shown before content (no empty→populated flash).
  - [ ] 1.1.5 Fetch failure → `ErrorCard` with retry that refetches the current tab; tabs stay rendered in the error state.
- [ ] 1.2 Extend `apps/web-platform/e2e/nav-states-shell.e2e.ts`: "Inbox" nav entry renders; routing to `/dashboard/inbox` shows the list (existing `**/api/inbox/emails*` mock at :228 covers it).

## Phase 2 — Server page + client surface (GREEN)

- [ ] 2.1 `apps/web-platform/app/(dashboard)/dashboard/inbox/page.tsx` (Server): `export const dynamic = "force-dynamic"`; `supabase.auth.getUser()` → `redirect("/login")`; render `<main className="mx-auto max-w-5xl px-6 py-8">` + h1 "Inbox" + description, wrapping `<Suspense fallback="Loading…"><InboxSurface /></Suspense>`.
- [ ] 2.2 `apps/web-platform/components/inbox/inbox-surface.tsx` (`"use client"`): fetch `/api/inbox/emails[?status=archived]` (non-silent); Active/Archived tabs mirroring `routines-surface.tsx` `TabButton`/`role="tab"`; `useSearchParams` drives `?status=archived`; tab-active derives from the query param.
- [ ] 2.3 Map items → `EmailTriageRow` (`{item, onChanged: refetch}`); import `EmailTriageItem` from `email-triage-row.tsx` (no redeclare); render in API order (no `useMemo(sort)`); probes hidden.
- [ ] 2.4 States: "Loading…" line; reuse `ErrorCard` (`onRetry` → refetch current tab); distinct empty copy.

## Phase 3 — Wire-up

- [ ] 3.1 `layout.tsx`: add `{ href: "/dashboard/inbox", label: "Inbox", icon: InboxIcon }` to `NAV_ITEMS` (:95) + inline `InboxIcon`; verify `segmentToDrillLevel("/dashboard/inbox")` → `null`.
- [ ] 3.2 `dashboard/page.tsx:796`: section header on the `emailItems` block with "View all →" → `/dashboard/inbox` (wireframe 12).
- [ ] 3.3 `email/[emailId]/page.tsx`: add "← Inbox" link → `/dashboard/inbox` (additive; no auth/RLS/notFound change).

## Phase 4 — Verify

- [ ] 4.1 `./node_modules/.bin/vitest run test/inbox-surface.test.tsx` green.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 4.3 `next build` succeeds (catches the `useSearchParams`/Suspense bailout `tsc` misses).
- [ ] 4.4 Acceptance Criteria in the plan all checked; review (observability-coverage + user-impact) pass.
