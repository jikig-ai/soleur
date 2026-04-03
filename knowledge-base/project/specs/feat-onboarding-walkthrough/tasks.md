# Tasks: First-Time Onboarding Walkthrough

**Issue:** [#1375](https://github.com/jikig-ai/soleur/issues/1375)
**Plan:** [2026-04-03-feat-onboarding-walkthrough-plan.md](../../plans/2026-04-03-feat-onboarding-walkthrough-plan.md)
**Branch:** onboarding-walkthrough

## Pre-requisites (Complete)

- [x] Copywriter copy approved: "Your Organization Is Ready / Eight department leaders are standing by. Type @ to put one to work."
- [x] PWA banner copy approved: "Add Soleur to Your Home Screen / Open on any device, no app store needed."
- [x] @-mention hint text reviewed — keep existing

## Phase 1: Database Migration

- [x] 1.1 Create `apps/web-platform/supabase/migrations/012_onboarding_state.sql`
  - [x] 1.1.1 `ALTER TABLE public.users ADD COLUMN onboarding_completed_at timestamptz;`
  - [x] 1.1.2 `ALTER TABLE public.users ADD COLUMN pwa_banner_dismissed_at timestamptz;`
- [x] 1.2 Verify RLS policies cover new columns (table-level SELECT/UPDATE — no changes needed)

## Phase 2: Welcome Card + Pulse

- [x] 2.1 Write failing tests: `apps/web-platform/test/welcome-card.test.tsx`
  - [x] 2.1.1 Test: renders card with approved copy when `onboarding_completed_at` is null
  - [x] 2.1.2 Test: does not render when `onboarding_completed_at` is set
- [x] 2.2 Create `apps/web-platform/components/chat/welcome-card.tsx`
  - Approved copy: "Your Organization Is Ready" + "Eight department leaders are standing by. Type @ to put one to work."
  - Tailwind: dark theme, amber-500 accent, neutral-900 bg
- [x] 2.3 Write failing tests for dashboard integration: `apps/web-platform/test/dashboard-page.test.tsx`
  - [x] 2.3.1 Test: dashboard fetches user onboarding state on mount
  - [x] 2.3.2 Test: welcome card visible for new user
  - [x] 2.3.3 Test: welcome card hidden for returning user
  - [x] 2.3.4 Test: hint text has pulse class for new user
  - [x] 2.3.5 Test: onboarding UI hidden until fetch resolves
- [x] 2.4 Modify `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - Fetch onboarding state on mount via `createClient()` from `@/lib/supabase/client`
  - Conditionally render `<WelcomeCard />` and pulse class
  - On `handleSend`: fire-and-forget DB update, then navigate
- [x] 2.5 All Phase 2 tests pass

## Phase 3: iOS PWA Install Banner

- [x] 3.1 Write failing tests: `apps/web-platform/test/pwa-install-banner.test.tsx`
  - [x] 3.1.1 Test: renders for iOS Safari user when `pwa_banner_dismissed_at` is null
  - [x] 3.1.2 Test: does not render for non-iOS user
  - [x] 3.1.3 Test: does not render when `pwa_banner_dismissed_at` is set
  - [x] 3.1.4 Test: dismiss button hides banner
- [x] 3.2 Create `apps/web-platform/components/chat/pwa-install-banner.tsx`
  - iOS Safari detection: UA check for iPhone/iPad + Safari, excluding CriOS/FxiOS
  - Approved copy: "Add Soleur to Your Home Screen" + instructions
  - Renders below suggested prompts (per gap #3)
- [x] 3.3 Modify dashboard page to render `<PwaInstallBanner />`
- [x] 3.4 All Phase 3 tests pass

## Phase 4: Testing & QA

- [x] 4.1 All component tests pass (`bun test`)
- [x] 4.2 Browser QA: new user flow → welcome card → send message → card gone
- [x] 4.3 Browser QA: returning user → no onboarding UI
- [x] 4.4 Responsive check: mobile, tablet, desktop
- [x] 4.5 Verify Supabase migration applied (REST API query)
