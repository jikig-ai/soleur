---
title: "Tasks — Move Releases nav tab into info/settings group"
branch: feat-one-shot-releases-info-tab-group
lane: single-domain
plan: knowledge-base/project/plans/2026-07-07-feat-releases-nav-info-group-plan.md
---

# Tasks — Group Releases nav tab with Status & Settings

Derived from `knowledge-base/project/plans/2026-07-07-feat-releases-nav-info-group-plan.md` (post plan-review).

## Phase 1 — Setup

- [ ] 1.1 Read `apps/web-platform/app/(dashboard)/layout.tsx` (primary nav loop ~L408–462, footer chrome ~L464–512, `settingsActive`/`drill` at ~L187–188, `RocketIcon` at ~L835).
- [ ] 1.2 Confirm `NAV_ITEMS` (`components/command-palette/nav-items.ts:39`) will stay **unchanged** — it is the shared source for the ⌘K palette, `g l` shortcut, and `?` help overlay.

## Phase 2 — Implementation (single file: `layout.tsx`)

- [ ] 2.1 Add `const RELEASES_HREF = "/dashboard/releases";` near the top of the dashboard layout component (single pin for the three new references below).
- [ ] 2.2 Add `const releasesActive = pathname.startsWith(RELEASES_HREF);` near the existing `settingsActive`. Do NOT use `drill === "releases"` (not a `DrillLevel` — TS error).
- [ ] 2.3 Change the primary nav render source to `navItems.filter((i) => i.href !== RELEASES_HREF)` so Releases is dropped from the action-tab loop (keep `ADMIN_NAV_ITEMS` behavior).
- [ ] 2.4 Insert a Releases `<Link>` as the **first** action in the footer chrome `<div>` (above Status), cloning the Settings `<Link>` markup: `href={RELEASES_HREF}`, direct `<RocketIcon />` (not `NAV_ICONS`), `title={collapsed ? "Releases" : undefined}`, `aria-current={releasesActive ? "page" : undefined}`, `data-tour-id={RELEASES_HREF}`, and the neutral active/hover className block driven by `releasesActive`.
- [ ] 2.5 Verify the footer block is still gated on `drill === null` only, never newly on `collapsed` (ADR-047 invariant).

## Phase 3 — Verification

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — passes. (AC7)
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts` — passes unchanged (proves palette + `g l` intact). (AC5)
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite green. (AC7)
- [ ] 3.4 `/verify` or Playwright: primary group = Dashboard, Inbox, Workstream, Knowledge Base, Routines (no Releases); footer group = Releases → Status → Settings → Sign out → Theme. Check active highlight on `/dashboard/releases` (neutral, not gold) and collapsed icon-only state. Cross-check against `knowledge-base/product/design/dashboard/releases-nav-relocation.pen`. (AC1–AC4, AC8)
- [ ] 3.5 Grep: `/dashboard/releases` `<Link>` renders exactly once in `layout.tsx`; no duplicate in the primary group. (AC2)

## Phase 4 — Ship

- [ ] 4.1 Commit code + design artifacts (`.pen` + screenshot already created under `knowledge-base/product/design/dashboard/`).
- [ ] 4.2 PR body: `Ref` the code-review overlap #2193 as acknowledged (disjoint concern, no fold-in).
