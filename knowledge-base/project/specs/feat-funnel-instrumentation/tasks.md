---
feature: feat-funnel-instrumentation
issue: 5049
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-08-feat-waitlist-activation-funnel-plan.md
---

# Tasks: Activation funnel instrumentation (Supabase)

Scope: Supabase-derived activation funnel on the admin analytics dashboard.
Buttondown waitlist count deferred → #5071.

## Phase 1 — Funnel compute (TDD)

- [ ] 1.1 RED: write `apps/web-platform/test/analytics-funnel.test.ts` with
  synthesized fixtures (0 users; 1 user no convs; 1 non-failed domain; 2 domains
  <14d span; 2 domains ≥14d span → activated; all-failed → activatedCount===0 and
  not past first-conversation; boundary 13.99d vs 14.0d; zero-prior drop-off → `—`).
- [ ] 1.2 GREEN: add `computeFunnel(users, conversations, now?)` to
  `apps/web-platform/lib/analytics.ts`; extend `UserRow` with `workspace_status`.
  - [ ] 1.2.1 Non-failed population: all per-user derivations filter `status != 'failed'`.
  - [ ] 1.2.2 Activation = `nonFailedDomainCount ≥ 2` AND (last − first non-failed
    session) ≥ 14 days; expose `activationDef` string.
  - [ ] 1.2.3 Drop-off label relative to previous stage; zero-prior → `—`.
  - [ ] 1.2.4 Four independent stage counts (signed-up, workspace-ready,
    first-conversation, activated).

## Phase 2 — Dashboard render

- [ ] 2.1 Add `workspace_status` to the `users` SELECT in
  `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx`; call
  `computeFunnel`; pass to the dashboard.
- [ ] 2.2 Render the funnel section in
  `apps/web-platform/components/analytics/analytics-dashboard.tsx` per the wireframe
  (4 stage bars, drop-off labels, activated highlight + `activationDef` tooltip).
- [ ] 2.3 Empty state: `signupCount === 0` → "No signups recorded yet".
- [ ] 2.4 Decide `ADMIN_USER_IDS` exclusion from counts (Open Question); note in UI.

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/analytics-funnel.test.ts`
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 3.3 Grep `UserRow` consumers (`hr-type-widening-cross-consumer-grep`) — confirm
  only `analytics.ts` + `page.tsx`, both updated.

## Phase 4 — Ship

- [ ] 4.1 PR body: `Closes #5049`. Reference deferred #5071.
- [ ] 4.2 Post-merge: verify funnel renders for an admin via Playwright MCP (no ssh).
