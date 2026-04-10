# Tasks: Product Analytics Dashboard

**Plan:** [2026-04-10-feat-product-analytics-dashboard-plan.md](../../plans/2026-04-10-feat-product-analytics-dashboard-plan.md)
**Issue:** #1063
**Branch:** product-analytics

## Phase 1: Migration + KB Growth Tracking

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/017_kb_sync_history.sql`
  - [ ] 1.1.1 `ALTER TABLE public.users ADD COLUMN kb_sync_history jsonb NOT NULL DEFAULT '[]'`
  - [ ] 1.1.2 Add restrictive RLS policy preventing client-side writes to `kb_sync_history`
- [ ] 1.2 Add `ADMIN_USER_IDS` to Doppler (`dev` and `prd` configs)
- [ ] 1.3 Add KB file count logic to `apps/web-platform/server/session-sync.ts`
  - [ ] 1.3.1 After successful git push in `syncPush`, count `.md` files in workspace `knowledge-base/` directory
  - [ ] 1.3.2 Append `{date, count}` to `users.kb_sync_history` via service client, trim to 14 entries
  - [ ] 1.3.3 Wrap in try/catch — best-effort, never block session completion
  - [ ] 1.3.4 Skip if no local commits (respect existing early return)

## Phase 2: Analytics Dashboard Page

- [ ] 2.1 Create server component `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx`
  - [ ] 2.1.1 Auth check (createClient → getUser → redirect to /login if !user)
  - [ ] 2.1.2 Inline admin check (`process.env.ADMIN_USER_IDS?.split(',').includes(user.id)` → redirect to /dashboard if !admin, fail closed if env var missing)
  - [ ] 2.1.3 Fetch all users + conversations via createServiceClient
  - [ ] 2.1.4 Aggregate 7 metrics in JS, pass as props to client component
  - [ ] 2.1.5 Handle query errors: render error state with retry link
- [ ] 2.2 Create loading skeleton `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/loading.tsx`
- [ ] 2.3 Create dashboard component `apps/web-platform/components/analytics/analytics-dashboard.tsx`
  - [ ] 2.3.1 Per-user metrics table (User, Domains, Sessions, Multi-Domain, KB Growth, TTFV, Error Rate, Churn)
  - [ ] 2.3.2 Inline SVG sparkline helper function for session frequency and KB growth columns
  - [ ] 2.3.3 Binary churn indicator: green dot (active ≤7 days) / red dot (churning >7 days)
  - [ ] 2.3.4 Empty states: "—" for no data, "No conversations yet" for zero sessions

## Phase 3: Tests + Verification

- [ ] 3.1 Write admin access denial test (`apps/web-platform/test/analytics-access.test.ts`)
- [ ] 3.2 Write metric aggregation logic test (`apps/web-platform/test/analytics-metrics.test.ts`)
- [ ] 3.3 Run all tests locally
- [ ] 3.4 Start dev server and verify dashboard renders at `/dashboard/admin/analytics`
- [ ] 3.5 Verify non-admin redirect in browser
- [ ] 3.6 After merge: verify migration applied to production via Supabase REST API
