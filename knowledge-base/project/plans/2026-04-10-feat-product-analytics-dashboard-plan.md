---
title: "feat: product analytics dashboard for P4 validation"
type: feat
date: 2026-04-10
semver: minor
---

# feat: Product Analytics Dashboard for P4 Validation

## Overview

Admin-only dashboard at `/dashboard/admin/analytics` that surfaces 7 per-user product validation metrics by querying existing Supabase operational data. KB growth history stored as a JSONB array on the `users` table. No new tables, no new event pipeline, no charting library, no third-party analytics.

Ref #1063

## Problem Statement

Phase 4 validation requires proving "5+ users engage 2+ domains for 2+ weeks" but no instrumentation exists to track these metrics. Without data, P4 exit criteria are unjudgeable. Six of seven metrics already exist in `conversations`/`users` tables — this is a query problem, not a collection problem.

## Proposed Solution

1. **Query existing data** — aggregate metrics from `conversations` and `users` tables using the service client (bypasses RLS for cross-user admin queries)
2. **Track KB growth** — count knowledge-base files at `syncPush` boundary, append to JSONB array on `users` table
3. **Admin gate** — environment variable `ADMIN_USER_IDS` (Doppler secret) checked in server component
4. **Render server-side** — server component fetches data, passes to client component for table + inline SVG sparklines

## Technical Approach

### Architecture

```text
/dashboard/admin/analytics (Next.js App Router)
├── page.tsx (server component)
│   ├── Auth check (createClient → getUser → redirect if !user)
│   ├── Admin check (ADMIN_USER_IDS env var → redirect if !admin)
│   └── Data fetch (createServiceClient → aggregate queries)
├── loading.tsx (skeleton table for Suspense boundary)
└── analytics-dashboard.tsx (client component)
    ├── Per-user metrics table with inline SVG sparklines
    └── Binary churn indicator (active / churning)
```

### Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `ADMIN_USER_IDS` env var (Doppler) for access control | No migration needed. 10 beta users = static admin list. Avoids RLS column-level security complexity (learnings #6, #7). Upgrade to role column if admin list grows. |
| 2 | App-level aggregation via Supabase JS client, not SQL views | Simple `.select()` / `.eq()` queries on ~10 users. Views add migration complexity for negligible performance gain. Deferred to #1924 if needed at scale. |
| 3 | JSONB array column on `users` for KB growth history | Sparklines need ~14 data points per user. A JSONB array of `{date, count}` objects avoids a new table, RLS policies, and FK constraints. Trimmed to last 14 entries in application code. |
| 4 | 14-day sparkline window | Matches P4 validation period (AC5). Daily aggregation = 14 data points per sparkline. |
| 5 | 7-day binary churn threshold | Half the 2-week validation window. Binary: active (last session within 7 days) or churning (>7 days). No intermediate "slowing" tier — the P4 question is binary. |
| 6 | No sidebar nav item — admins bookmark the URL | The dashboard layout is a `"use client"` component with a static `NAV_ITEMS` array. Passing admin status to the client requires cookie/prop plumbing disproportionate to value for ~2 admins. The page redirect is the real access gate. |

### Open Questions Resolved

From the spec's 4 open questions:

1. **Admin role mechanism** → `ADMIN_USER_IDS` env var in Doppler. Checked server-side in the page component. One-line inline check: `process.env.ADMIN_USER_IDS?.split(',').includes(userId)`.
2. **Sparkline time window** → 14 days (matching P4 validation window).
3. **KB sync stats schema** → JSONB array column `kb_sync_history` on `users` table. Each entry: `{date: string, count: number}`. Trimmed to 14 entries on each write.
4. **Churn threshold** → 7 days of inactivity (binary: active or churning).

### Metrics Query Design

All queries use `createServiceClient()` (bypasses RLS) in the server component via the **Supabase JS client API** (`.select()`, `.eq()`, `.not()`, `.order()`). The pseudo-SQL below illustrates the logic; implementation uses JS builder methods.

| Metric | Logic (pseudo-SQL) | JS Client Approach |
|--------|-------|--------|
| Domain engagement | `COUNT(*) per user_id, domain_leader` | `.from('conversations').select('user_id, domain_leader')` then group in JS |
| Session frequency | `COUNT(*) per user_id, DATE(created_at)` | `.from('conversations').select('user_id, created_at')` then bucket by day in JS |
| Multi-domain usage | `COUNT(DISTINCT domain_leader) per user_id` | Derive from domain engagement result: count unique leaders per user |
| KB growth | JSONB array from `users.kb_sync_history` | `.from('users').select('id, email, kb_sync_history, created_at')` |
| Time-to-first-value | `MIN(conversations.created_at) - users.created_at` | Fetch users + earliest conversation per user, compute diff in JS |
| Error rate | `COUNT(status='failed') / COUNT(*)` per user | `.from('conversations').select('user_id, status')` then compute ratio in JS |
| Churn signal | `NOW() - MAX(conversations.created_at)` per user | Derive from session data: max `created_at` per user, compare to now |

**Note:** For ~10 users with ~100s of conversations, fetching rows and aggregating in JS is simpler than raw SQL functions (`.rpc()`). The Supabase JS client does not support PostgreSQL `FILTER (WHERE ...)`, `COUNT(DISTINCT ...)`, or `LEFT JOIN` syntax — all aggregation happens in the server component after fetching.

### Implementation Phases

#### Phase 1: Migration + KB Growth Tracking

**Migration** (`apps/web-platform/supabase/migrations/017_kb_sync_history.sql`):

- `ALTER TABLE public.users ADD COLUMN kb_sync_history jsonb NOT NULL DEFAULT '[]'`
- Add restrictive RLS policy preventing client-side writes to `kb_sync_history` (per learning #6: new columns on RLS-enabled tables with permissive UPDATE policies are client-writable by default)

**KB growth hook** (`apps/web-platform/server/session-sync.ts`):

- After `syncPush` completes successfully (inside the try block, after the git push succeeds but before `updateLastSynced`), count `.md` files in the user's `knowledge-base/` directory
- Append `{date: ISO date string, count: number}` to `users.kb_sync_history` via the lazy service client
- Trim array to last 14 entries in the same update
- Best-effort: wrap in try/catch, log errors, never block session completion (matches existing sync patterns)
- Do NOT trigger if `syncPush` skips because there are no local commits (early return at the `hasLocalCommits` check)

**Files:**

- Create `apps/web-platform/supabase/migrations/017_kb_sync_history.sql`
- Edit `apps/web-platform/server/session-sync.ts` — add KB file count after successful push

**Doppler automation (admin IDs):**

- `doppler secrets set ADMIN_USER_IDS "<user-uuid>" -p soleur -c dev`
- `doppler secrets set ADMIN_USER_IDS "<user-uuid>" -p soleur -c prd`

#### Phase 2: Analytics Dashboard Page

**Server component** (`apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx`):

- Auth check: `createClient()` → `getUser()` → redirect to `/login` if no user
- Admin check: `process.env.ADMIN_USER_IDS?.split(',').includes(user.id)` → redirect to `/dashboard` if not admin. Fail closed: if env var is empty/missing, redirect all users.
- Data fetch: `createServiceClient()` → fetch all users, all conversations, compute 7 metrics in JS
- Pass aggregated data as props to client component
- Handle query errors: if any Supabase query returns `error`, render error state with retry link

**Loading state** (`apps/web-platform/app/(dashboard)/dashboard/admin/analytics/loading.tsx`):

- Skeleton table matching the dashboard's dark theme (neutral-900 animated bars)
- First `loading.tsx` in the app — establishes the pattern for future use

**Client component** (`apps/web-platform/components/analytics/analytics-dashboard.tsx`):

- Per-user metrics table with columns: User (email), Domains, Sessions, Multi-Domain, KB Growth, TTFV, Error Rate, Churn
- Inline SVG sparklines for session frequency and KB growth (14-day window) — helper function, not a separate component. A `<polyline>` with ≤14 points, auto-scaled. If data is empty, render a dash.
- Binary churn indicator: green dot (active — last session within 7 days) or red dot (churning — >7 days)
- Color scheme: existing dark neutral theme (neutral-950/900/800, amber accents)
- Empty states: "No conversations yet" for users with zero sessions, "—" for metrics with no data
- For users with < 14 days of history, sparkline shows only available data points

**Files:**

- Create `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx`
- Create `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/loading.tsx`
- Create `apps/web-platform/components/analytics/analytics-dashboard.tsx`

#### Phase 3: Tests + Verification

- Test admin access denial: non-admin user gets redirect (`apps/web-platform/test/analytics-access.test.ts`)
- Test metric query aggregation logic: given known conversation/user data, verify correct metric computation (`apps/web-platform/test/analytics-metrics.test.ts`)
- Start dev server and verify dashboard renders at `/dashboard/admin/analytics`
- Verify non-admin redirect in browser
- After merge: verify migration applied to production via Supabase REST API (AGENTS.md rule)

**Testing patterns from learnings:**

- Mock Supabase builders with `.then()` for thenable behavior (learning: supabase-query-builder-mock-thenable)
- Place mock setup in `vi.mock()` factory (learning: vitest-module-level-supabase-mock-timing)
- Import `SupabaseClient` type explicitly, never `ReturnType<typeof createClient>` (learning: supabase-returntype-resolves-to-never)
- Always destructure `{ data, error }` from queries (learning: supabase-silent-error-return-values)

**Files:**

- Create `apps/web-platform/test/analytics-access.test.ts`
- Create `apps/web-platform/test/analytics-metrics.test.ts`

## Non-Goals

- NG1: Sidebar navigation link for analytics (admins bookmark the URL directly)
- NG2: User-facing analytics dashboard (deferred to #1923)
- NG3: New event pipeline or analytics_events table (deferred to #1924)
- NG4: Third-party analytics integration (PostHog, Mixpanel)
- NG5: Real-time metrics or auto-refresh (on-demand page load is sufficient)
- NG6: CLI plugin instrumentation (only web platform is instrumented this iteration)
- NG7: Privacy policy updates (parallel P2 workstream, not a blocker)
- NG8: Table sorting, filtering, or pagination (static table is sufficient for ~10 users)

## Acceptance Criteria

- [ ] AC1: Dashboard shows per-user domain engagement counts matching conversations table data
- [ ] AC2: Dashboard accessible only to admin users; non-admins redirected to `/dashboard`
- [ ] AC3: KB growth displayed per user (absolute file count + delta derived from consecutive `kb_sync_history` entries), updated after each session-sync push
- [ ] AC4: All 7 P4 metrics visible on a single page
- [ ] AC5: Sparklines show up to 14-day trend for session frequency and KB growth (users with < 14 days show available data points only)
- [ ] AC6: Page loads in under 2 seconds with 50 users of data
- [ ] AC7: Empty states handled gracefully (no data shows "—", zero conversations shows "No conversations yet")

## Test Scenarios

### Acceptance Tests

- Given an admin user, when they navigate to `/dashboard/admin/analytics`, then they see a table with all registered users and 7 metric columns
- Given a non-admin user, when they navigate to `/dashboard/admin/analytics`, then they are redirected to `/dashboard`
- Given an unauthenticated visitor, when they navigate to `/dashboard/admin/analytics`, then they are redirected to `/login`
- Given a user with 5 conversations across 3 domain leaders, when the admin views analytics, then that user's row shows domain count = 3 and session count = 5
- Given a user who ran syncPush, when the admin views analytics, then that user's KB growth column shows a file count and a delta from the previous sync
- Given a user who signed up but never started a session, when the admin views analytics, then that user appears with zero sessions, zero domains, and a churning indicator

### Edge Cases

- Given a user with < 14 days of history, when sparkline renders, then it shows only available data points (variable width)
- Given a user with only failed sessions, when the admin views analytics, then error rate shows 100%
- Given `ADMIN_USER_IDS` env var is empty or missing, when any user navigates to analytics, then they are redirected (fail closed)
- Given a user with empty `kb_sync_history`, when the admin views analytics, then KB growth shows "—" instead of crashing
- Given a Supabase query fails, when the admin views analytics, then an error state renders with a retry link

### Browser Verification

- **Navigate:** Open `/dashboard/admin/analytics` as admin user → verify metrics table renders with data
- **Verify access:** Open `/dashboard/admin/analytics` in incognito (no session) → verify redirect to `/login`
- **Verify loading:** Observe skeleton table while data loads (loading.tsx Suspense boundary)

## Domain Review

**Domains relevant:** Product, Engineering, Marketing, Legal

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Recommends querying existing data as simplest path. Flags that web platform and CLI plugin must converge on shared user identity (Supabase Auth provides this for web). Two collection surfaces exist but only web platform is instrumented in this iteration. Session = WebSocket connection lifecycle.

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Do not announce instrumentation publicly. Announce insights when P4 data is meaningful. User-facing growth curves (showing founders their KB growth) identified as competitive differentiator — deferred to post-P4 (#1923). Privacy messaging matters when eventually exposed.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Querying existing operational data for internal metrics does NOT require privacy policy update. KB file count is a derived integer, not personal data. Recommends adding "internal product analytics" as processing purpose in P2 item 2.9 as belt-and-suspenders.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

This creates a new admin page, but it is admin-only (not user-facing) and displays internal metrics in a simple table format. No user flows, no onboarding, no forms. Advisory tier — the page design is straightforward enough to implement directly.

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| SQL views for metrics | Adds migration complexity for ~10 users. App-level aggregation is simpler to modify. Deferred to #1924. |
| `.rpc()` with PostgreSQL functions | More powerful SQL (FILTER, COUNT DISTINCT, LEFT JOIN) but adds DB function management overhead. JS aggregation is simpler for this data volume. |
| `is_admin` column on `users` table | Requires migration + restrictive RLS policy (learning #6). Env var is simpler for static admin list. |
| `kb_sync_stats` dedicated table | Cleaner for querying at scale but requires new table, RLS policies, FK, and index for ~420 rows over 14 days. JSONB array on `users` is sufficient. |
| Separate `sparkline.tsx` component | Only used in 2 columns of 1 table. A 15-line inline helper avoids a file + test for a component no other page needs. |
| `lib/admin.ts` utility module | One-line string split doesn't need its own file, cache, or unit test. Inline in server component. |
| Conditional sidebar nav item | Layout is `"use client"` with static `NAV_ITEMS`. Passing admin status to client requires cookie/prop plumbing for ~2 admins. Bookmark instead. |
| PostHog / third-party analytics | Overkill for 10 beta users. Adds privacy surface area. Deferred to #1924. |
| Materialized views | Unnecessary for this data volume. Would require refresh scheduling. |

## Dependencies and Risks

| Dependency | Status | Risk |
|------------|--------|------|
| `conversations` table with `domain_leader` column | Exists (migration 010) | Low — production data |
| `users` table with `created_at` | Exists (migration 001) | Low — production data |
| `session-sync.ts` syncPush function | Exists | Low — well-tested module |
| Doppler access for `ADMIN_USER_IDS` | Available | Low — existing secret management |
| Migration applied to production | Must verify post-merge | Medium — silent failure if missed (learning #10) |

## Rollback Plan

- **Code:** Revert the PR (single squash commit)
- **Migration:** `ALTER TABLE public.users DROP COLUMN kb_sync_history` — removes the JSONB column. No data loss risk since KB growth data can be regenerated from git history.
- **Doppler:** Remove `ADMIN_USER_IDS` from dev/prd configs (optional — unused env var causes no harm)
- **No external resources** to tear down (no new tables, no new services, no infrastructure)

## Success Metrics

- All 7 P4 validation metrics visible and accurate
- Admin can determine P4 exit criteria pass/fail from a single page load
- KB growth tracking captures count on every successful session-sync push

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-10-product-analytics-instrumentation-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-product-analytics/spec.md`
- Issue: #1063
- Deferred: #1923 (user-facing dashboard), #1924 (full analytics pipeline)
- Settings page pattern: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`
- Session sync module: `apps/web-platform/server/session-sync.ts`
- KB reader: `apps/web-platform/server/kb-reader.ts`
- Supabase client factories: `apps/web-platform/lib/supabase/server.ts`, `apps/web-platform/lib/supabase/service.ts`
- Dashboard layout: `apps/web-platform/app/(dashboard)/layout.tsx:8` (NAV_ITEMS — not modified, admins bookmark URL directly)
- Test directory: `apps/web-platform/test/` (flat structure, not `__tests__/`)
