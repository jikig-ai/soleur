---
name: feat-guided-tour
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-30-guided-tour-brainstorm.md
branch: feat-guided-tour
pr: 5750
issue: 5743
---

# Feature: Guided Onboarding Tour

## Problem Statement
New users land in app.soleur.ai with no guided introduction to the main surfaces.
Build a spotlight-overlay tour that auto-starts once on first login and is
re-launchable, walking the user through the 6 core nav surfaces.

## Goals
- A circular spotlight cutout over a dark overlay highlighting each sidebar nav item.
- Tour card with title + body + Back/Next/Skip + step progress.
- Auto-start once (first login), manual relaunch from support panel + `?` overlay.
- Persist completion durably; never re-auto-fire after finish/skip.
- Gated behind a `guided-tour` flag (default OFF, fail-closed).
- Accessible (focus trap, Escape, reduced-motion) with guaranteed teardown.

## Non-Goals
- No cross-route navigation (spotlights the always-visible rail items in place).
- No tour-builder/admin UI; steps are a static in-code list.
- No third-party tour library.
- Mobile spotlight tracking — under `md` the tour uses centered cards.

## Functional Requirements

### FR1: Spotlight overlay (`guided-tour.tsx`)
Overlay root `fixed inset-0 z-[70]`. Single box-shadow spotlight: one
absolutely-positioned div sized from the live target `getBoundingClientRect`
(+~8px pad, `border-radius:9999px`) with `boxShadow: 0 0 0 9999px rgba(0,0,0,0.6)`.
Welcome step + any null/zero-rect/off-screen target → centered card, no cutout.
Position transitions gated by `motion-reduce:transition-none`. Body-scroll-lock
for the tour lifetime via guaranteed `useEffect` cleanup.
Wireframes: `knowledge-base/product/design/onboarding/screenshots/04-08-*.png`.

### FR2: Tour card (`role="dialog"`)
Separate from the spotlight: title, body, progress ("N of 6" + bar), Back (hidden
on step 1), Skip (hidden on last step), Next (gold `GoldButton`) / Finish on last
step. Focus-trapped; Escape = Skip. Card positioned near the target (right of rail);
centered for Welcome/mobile/fallback.

### FR3: TourProvider + useTour (`tour-provider.tsx`)
React context mounted in `app/(dashboard)/layout.tsx` wrapping the
`<HelpOverlay/>` + `<SupportLauncher/>` subtree (mirrors `ShortcutsProvider`).
Exposes `useTour() → { active, stepIndex, startTour, next, back, skip, finish }`.
Gated by `useOptionalFeatureFlag("guided-tour")` → renders nothing when off.
Owns auto-first-run, mounts `<GuidedTour/>`.

### FR4: Steps (`tour-steps.ts`)
Static 6-step list: Welcome (no target) → Dashboard → Inbox → Workstream →
Knowledge Base → Routines, each `{ target: data-tour-id href, title, body }`.

### FR5: Targeting
Add `data-tour-id={item.href}` to the sidebar `<Link>` (layout.tsx:396,
drill===null branch). Target by attribute; admin-safe (ADMIN_NAV_ITEMS appends).
At tour start, dispatch the rail-expand event so a collapsed rail shows full rows.

### FR6: Auto-start gating
Auto-start once when: `onboardingLoaded && tour_completed_at IS NULL && NOT
first-run-hero-active && no other overlay active` (sign-out modal, mobile drawer,
support panel). Lands on `/dashboard`. Existing first-run naming/hero takes
precedence (tour defers).

### FR7: Persistence (`/api/tour/complete` + migration 119)
`users.tour_completed_at timestamptz NULL` via migration `119_tour_completed_state.sql`
(+ `.down.sql`); MUST be the only `119_*` (adr-ordinals gate). Client UPDATE on
`public.users` is REVOKED (migration 006) → completion persists via a **service-role**
`POST /api/tour/complete` route (sets `tour_completed_at = now()` for the auth user).
Finish AND Skip/Escape both persist. Read path: extend the existing `use-onboarding`
SELECT to include `tour_completed_at` (no second fetch).

### FR8: Launch points
- Support panel: a "Take a tour" control; `SupportPanel` stays presentational,
  receives `onStartTour`; `SupportLauncher` sources `startTour` via `useTour()` and
  calls `onClose()` BEFORE `startTour()` (tear down the panel focus-trap first).
- `?` help overlay: a "Get started → Take a tour" command item (separate group, not
  in the keycap SHORTCUTS array); handler closes help then `startTour()`.

### FR9: Flag
Add `"guided-tour": "FLAG_GUIDED_TOUR"` to `RUNTIME_FLAGS` (server.ts) + `FLAG_GUIDED_TOUR=0`
in `.env.example`. Provision via `soleur:flag-create guided-tour` (operator, default OFF).

### FR10: Analytics
Emit `tour_started / step_viewed / tour_completed / tour_skipped` (+ trigger source)
via `lib/analytics-client.ts` `track()` (fail-soft).

## Technical Requirements
- TR1: Reuse support-panel.tsx overlay/focus-trap/Escape/reduced-motion patterns;
  `GoldButton`; `soleur-*` tokens; no raw hex (`rgba()` allowed for the dim).
- TR2: All overlay side effects strictly `useEffect`-guarded (SSR-safe); scroll-lock +
  any `inert` mutation cleaned up on finish/skip/unmount/flag-off.
- TR3: Persistence is fire-and-forget from the client: on `/api/tour/complete` failure,
  still close the tour locally (optimistic) + mirror to Sentry; never loop.
- TR4: Re-measure on step change, capture-phase window scroll, window resize, and a
  ResizeObserver on the target; swap to centered card if target leaves the viewport.
- TR5: Typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; tests via
  `./node_modules/.bin/vitest run test/components/tour/` (paths under `test/**/*.test.tsx`).

## Acceptance Criteria
### Pre-merge
- [ ] Flag OFF → TourProvider renders nothing (no overlay, no auto-start).
- [ ] Flag ON + `tour_completed_at` NULL + on /dashboard, no blocking modal → tour
      auto-starts once; spotlight tracks the correct rail item per step.
- [ ] Next/Back/Skip/Finish + progress work; Escape = Skip; focus trapped; focus
      returns sensibly on exit (not `<body>`).
- [ ] Finish AND Skip POST `/api/tour/complete`; re-login does NOT re-auto-start.
- [ ] "Take a tour" in support panel and `?` overlay both start the tour (panel closes first).
- [ ] Null/off-screen target → centered card (no broken cutout); under `md` → centered cards.
- [ ] Scroll-lock released + no `inert` left on finish/skip/unmount/flag-off mid-tour.
- [ ] `grep -rnE '#[0-9a-fA-F]{3,6}' apps/web-platform/components/tour/` returns nothing.
- [ ] `tsc --noEmit` clean; `vitest run test/components/tour/` green; full suite green.
- [ ] Migration 119 applies on dev; `tour_completed_at` column present; `/api/tour/complete`
      sets it for the auth user (service role).

### Post-merge (operator)
- [ ] `soleur:flag-create guided-tour` — Flagsmith + Doppler dev/prd, default OFF.

## Files to Create
- `apps/web-platform/components/tour/tour-provider.tsx`
- `apps/web-platform/components/tour/guided-tour.tsx`
- `apps/web-platform/components/tour/tour-steps.ts`
- `apps/web-platform/app/api/tour/complete/route.ts`
- `apps/web-platform/supabase/migrations/119_tour_completed_state.sql`
- `apps/web-platform/supabase/migrations/119_tour_completed_state.down.sql`
- tests under `apps/web-platform/test/components/tour/`

## Files to Edit
- `apps/web-platform/lib/feature-flags/server.ts` (+ `.env.example`)
- `apps/web-platform/app/(dashboard)/layout.tsx` (mount provider + `data-tour-id`)
- `apps/web-platform/components/support/support-panel.tsx` + `support-launcher.tsx`
- `apps/web-platform/components/command-palette/help-overlay.tsx`
- `apps/web-platform/hooks/use-onboarding.ts` (SELECT + expose `tour_completed_at`)

## Design Artifacts
- Wireframes (approved 2026-06-30): `knowledge-base/product/design/onboarding/guided-tour.pen`
  + `screenshots/04-08-*.png`.

## User-Brand Impact
- **If broken:** an overlay that traps focus / locks scroll without teardown, or
  auto-fires over a modal, locks a user out at first login.
- **Threshold:** single-user incident. `user-impact-reviewer` runs at PR review.
