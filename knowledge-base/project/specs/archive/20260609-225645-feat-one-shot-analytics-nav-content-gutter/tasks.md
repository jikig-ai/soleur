---
title: "Tasks — fix: Analytics page content gutter"
plan: knowledge-base/project/plans/2026-06-09-fix-analytics-content-gutter-plan.md
branch: feat-one-shot-analytics-nav-content-gutter
lane: single-domain
date: 2026-06-09
---

# Tasks — Analytics content gutter fix

Derived from `2026-06-09-fix-analytics-content-gutter-plan.md`. Pure
Tailwind-className gutter fix on the admin Analytics page; page-owned padding,
NOT a shared-layout change.

## Phase 1 — Core implementation

- [x] 1.1 Edit `apps/web-platform/components/analytics/analytics-dashboard.tsx`:
  wrap the **populated** branch root (`<div className="space-y-6">` at line 194)
  with the padded container — prefer merging into one element:
  `<div className="mx-auto max-w-6xl px-6 py-8 space-y-6">`. (AC1)
- [x] 1.2 Apply the **same** wrapper string to the **empty-state** branch
  (`metrics.length === 0`, `<div className="space-y-6">` at line 186). (AC2)
- [x] 1.3 Edit `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx`:
  wrap the error-state return (lines 44-55) so the failure message + Retry link
  inherit a left gutter (`px-6`, same `mx-auto max-w-6xl px-6 py-8`, or add
  `px-6` to the existing centered block). (AC3)
- [x] 1.4 Edit `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/loading.tsx`:
  wrap the skeleton root (`<div className="space-y-6">` at line 2) with the
  identical wrapper so the gutter does not flicker across loading→loaded→error. (AC4)
- [x] 1.5 Pick the `max-w-*` clamp (default `max-w-6xl`) such that the 8-column
  table is not narrowed vs today; if cramped, drop `max-w` and keep `px-6 py-8`.
  Use the same wrapper string across 1.1-1.4. (Implementation Notes)

## Phase 2 — Verification

- [x] 2.1 Confirm `app/(dashboard)/layout.tsx` `<main>` className is UNCHANGED:
  `git diff "apps/web-platform/app/(dashboard)/layout.tsx"` is empty. (AC5)
- [x] 2.2 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  exits 0. (AC6)
- [x] 2.3 Grep the wrapper landed on all four surfaces:
  `grep -rnE 'mx-auto max-w-6xl|px-6' apps/web-platform/components/analytics/analytics-dashboard.tsx apps/web-platform/app/\(dashboard\)/dashboard/admin/analytics/`
  shows the gutter on the populated + empty branches, error state, and skeleton.
  (AC1-AC4)

## Phase 3 — Visual confirmation

- [x] 3.1 Playwright: navigate `/dashboard/admin/analytics` (admin session),
  screenshot with sidebar **expanded** — visible left gutter between sidebar
  edge and Analytics heading/table. (AC7) — verified 2026-06-09, 1440×900,
  seeded QA admin via `ADMIN_USER_IDS` env override on a port-3099 dev server.
- [x] 3.2 Toggle sidebar **collapsed** (⌘B), screenshot — same gutter persists. (AC7)
  — verified 2026-06-09 (Ctrl+B); gutter identical against the icon rail.
- [x] 3.3 (Optional) Force empty-state and error-state to confirm those branches
  also carry the gutter. — SKIPPED (optional): wrapper string is grep-verified
  byte-identical across populated/empty/error/loading branches (task 2.3), so
  the visual result is structurally the same; forcing those states against dev
  data is not worth the setup cost.
