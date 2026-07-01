# Brainstorm: Guided Onboarding Tour

**Date:** 2026-06-30
**Branch:** feat-guided-tour · **PR:** #5750 (draft) · **Issue:** #5743
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident

## What We're Building

A guided onboarding tour for app.soleur.ai: a **circular spotlight cutout over a
dark mid-opacity overlay** that highlights each main left-sidebar nav item in turn,
with an explanatory card (title + body + Back/Next/Skip + progress). Walks a new
user through the 6 core surfaces, auto-starts once on first login, and is
re-launchable on demand.

## Decisions (operator-confirmed + workflow-synthesized)

| Decision | Choice |
|---|---|
| Trigger | Auto-start ONCE on first login (`tour_completed_at IS NULL`) + manual relaunch |
| Launch points | "Take a tour" in the support slide-over + a "Get started" item in the `?` help overlay |
| Scope | 6 steps: Welcome → Dashboard → Inbox → Workstream → Knowledge Base → Routines |
| Rendering | **Build from scratch (no tour library)** — single-element box-shadow spotlight |
| State | Dedicated `TourProvider` React context (mirrors `ShortcutsProvider`), `useTour()` |
| Persistence | New `users.tour_completed_at` column (migration 119) via **service-role API route** |
| Targeting | `data-tour-id={item.href}` on the sidebar `<Link>` (layout.tsx:396); attribute, not index |
| Gating | New `guided-tour` runtime flag, default OFF / fail-closed |
| Mobile (<md) | Centered cards for the 5 nav steps (rail is an off-screen drawer; spotlight skipped) |
| Skip/Escape | Persist `tour_completed_at` (so auto-start never re-fires); manual relaunch still available |
| Visual design | Wireframes in `.pen` (ux-design-lead) — pending sign-off |

## Why This Approach

- **No library (rejected driver.js / react-joyride / @reactour / @floating-ui):** the
  rail has exactly one left-edge anchor per step, so a dependency-free re-measure
  engine (step-change + capture-phase window scroll + window resize + ResizeObserver
  on the target) + force-expanding the rail at start covers every layout-shift case
  — without lockfile churn or non-token popover chrome. YAGNI.
- **Single-element box-shadow spotlight:** one absolutely-positioned div sized from
  the live `getBoundingClientRect` (+~8px pad, `border-radius:9999px`) painted with
  `boxShadow: 0 0 0 9999px rgba(0,0,0,0.6)` — the huge spread dims the whole viewport
  except the hole. `rgba()` not hex (satisfies no-raw-hex; matches `bg-black/60`).
- **Reuse shipped primitives:** the support-panel.tsx overlay/focus-trap/Escape/
  reduced-motion patterns, `GoldButton`, `soleur-*` tokens, `useOptionalFeatureFlag`.
- **Service-role persistence:** migration 006 REVOKEd client UPDATE on `public.users`
  (email column only), so a client `updateUserField` write silently no-ops — completion
  MUST go through a service-role `/api/tour/complete` route. Read path is free under RLS.

## Key Implementation Anchors

- Mount `<TourProvider>` in `app/(dashboard)/layout.tsx` wrapping the subtree with
  `<HelpOverlay/>` (≈L572) + `<SupportLauncher/>` (≈L575), mirroring `ShortcutsProvider`.
- Overlay root `fixed inset-0 z-[70]` (above support panel z-[60], bubble z-50).
- `data-tour-id={item.href}` on the nav `<Link>` (layout.tsx:396, drill===null branch).
- Flag: add `"guided-tour": "FLAG_GUIDED_TOUR"` to `RUNTIME_FLAGS` + `.env.example`.
- Migration: `supabase/migrations/119_tour_completed_state.sql` (+ `.down.sql`) —
  renumbered to 119 (114-118 taken by parallel migrations on main); MUST be the only `119_*`.

## Step List

1. **Welcome** (centered card, no spotlight) — "Take a 60-second tour…"
2. **Dashboard** — live overview of what your org is building + what needs attention.
3. **Inbox** — outside-world email/signals, triaged.
4. **Workstream** — work in flight: conversations + tasks your agents are moving.
5. **Knowledge Base** — shared memory (vision, docs, context every agent draws on).
6. **Routines** — schedule recurring agent work.

## Gap Fixes Carried Into Spec (from completeness critic)

- **Auto-start gating (HIGH):** condition = `onboardingLoaded && tour_completed_at IS NULL
  && NOT first-run-hero-active && no other overlay active` (sign-out modal `inert`,
  mobile drawer, support panel). Provider needs visibility into onboarding/first-run state.
- **Persistence-failure (HIGH):** `/api/tour/complete` is fire-and-forget from the client;
  on failure, still close the tour locally (optimistic) + mirror to Sentry; do NOT loop.
- **Mobile (HIGH):** centered cards under `md` (targets are off-screen in the drawer).
- **Zero-rect / hidden-but-mounted target (MED):** treat zero/off-screen rect like a null
  target → centered card fallback (not a tracked invisible element).
- **Mid-tour breakpoint cross (MED):** re-evaluate desktop↔mobile on resize; swap to
  centered card if the target left the viewport.
- **Scroll-lock + inert cleanup (MED):** body-scroll-lock and any `inert` mutation MUST be
  in a guaranteed `useEffect` cleanup (flag-off mid-tour, unmount, finish/skip).
- **Focus return with no trigger (MED):** auto-start has no launcher; on finish/skip move
  focus to a sensible target (the spotlighted nav item, or main), not `<body>`.
- **Analytics (MED):** emit `tour_started / step_viewed / tour_completed / tour_skipped`
  via existing `lib/analytics-client.ts` track() (fail-soft).
- **Existing-user backfill (LOW):** all current users have NULL → tour auto-fires once for
  the whole base on first login after rollout. Accepted (one-time, flag-gated rollout).
- **Duplicate user fetch (LOW):** extend the existing `use-onboarding` SELECT to include
  `tour_completed_at` and share it, rather than a second `getUser()+select`.
- **SSR/hydration (LOW):** overlay is client-only; all side effects strictly `useEffect`-guarded.

## Open Questions

- Mobile: centered-card (recommended) is the default — acceptable, or force-open drawer?
- Existing-user mass auto-trigger on rollout — fine as a one-time onboarding, or restrict
  to accounts created after rollout? (Default: fire for all, once.)

## User-Brand Impact

- **Artifact:** the guided-tour overlay + `TourProvider` + `/api/tour/complete` route in
  app.soleur.ai.
- **Vector:** an overlay that traps focus / locks scroll without a guaranteed teardown, or
  auto-fires over a concurrent modal, would lock a user out of the app at first login —
  the worst possible first impression.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Product, Engineering, Legal (triad, USER_BRAND_CRITICAL auto per #5175)

### Product
**Summary:** Auto-once-on-first-login + replay is the right discoverability pattern;
spotlighting the always-visible rail (no cross-route nav) keeps it simple. Sequence after
the existing first-run naming/hero so two overlays never stack.

### Engineering
**Summary:** Build-from-scratch box-shadow spotlight + dedicated TourProvider; reuse
support-panel overlay/focus-trap primitives; service-role persistence route (client UPDATE
on users is revoked); guaranteed scroll-lock/inert cleanup is the load-bearing safety detail.

### Legal
**Summary:** `tour_completed_at` is a non-PII UX timestamp; no new processing of personal
data. No consent/retention implications. Read under existing RLS; write via service role.
