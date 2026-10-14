# Product Analytics Instrumentation for P4 Validation

**Date:** 2026-04-10
**Issue:** #1063
**Branch:** product-analytics
**Status:** Decided

## What We're Building

An admin dashboard at `/dashboard/admin/analytics` that surfaces per-user product validation metrics by querying existing operational data in Supabase. A lightweight KB growth counter added at the session-sync boundary. No new event pipeline, no new tracking infrastructure, no third-party analytics tool.

The goal is to make Phase 4 validation data-driven rather than anecdotal. The P4 validation protocol requires proving "5+ users engage 2+ domains for 2+ weeks" -- this instrumentation makes that provable.

## Why This Approach

The `conversations` table already stores `user_id`, `domain_leader`, `status`, and timestamps for every session. Six of seven P4 metrics are derivable from existing operational data with SQL queries. Adding an event pipeline (PostHog, custom events table) would introduce unnecessary complexity, privacy surface area, and legal overhead for 10 beta users.

**Key insight:** The web platform already collects everything needed for functional purposes. Analytics is a query problem, not a collection problem.

## Key Decisions

| # | Decision | Rationale | Alternative Considered |
|---|----------|-----------|----------------------|
| 1 | Query existing Supabase data, no new event pipeline | 6/7 metrics already in `conversations`/`users` tables. Fastest path, minimal code, no new privacy concerns. | Supabase `analytics_events` table (CTO Option A) -- more flexible but overkill for P4 validation scope. Deferred. |
| 2 | Count KB files at session-sync push time | Only metric not in Supabase. Derived integer stored in new `kb_sync_stats` or column on existing table. Minimal code change at natural boundary. | Git log query on demand -- slower, requires repo access at query time. |
| 3 | Admin dashboard with metrics table + sparklines | Single page, server-rendered, no charting library. Per-user rows with domain count, session count, last active, KB growth, time-to-first-value. | Full analytics page with charts (3-5 days, premature). SQL views + CLI script (no UI, less accessible). |
| 4 | Proceed without legal doc update | CLO confirmed: querying existing operational data for internal metrics doesn't require privacy policy changes. KB file count is a derived integer, not personal data. Add "internal product analytics" as processing purpose in P2 item 2.9. | Gate on legal update first -- would delay P3 delivery for a non-blocker. |
| 5 | Admin-only access control | Validation metrics are internal. No user-facing analytics in this iteration. | User-facing growth dashboard (CMO noted as competitive differentiator -- deferred to post-P4). |

## Metrics Coverage

| P4 Metric | Data Source | Query Method |
|-----------|------------|--------------|
| Per-user domain engagement | `conversations(user_id, domain_leader)` | COUNT per user per domain |
| Session frequency | `conversations(user_id, created_at)` | Sessions per day/week per user |
| Multi-domain usage | `conversations(domain_leader)` | COUNT DISTINCT per user |
| KB artifact growth | New: count at sync time | Delta per sync event |
| Time-to-first-value | `users(created_at)` → first conversation | Timestamp diff |
| Error/failure rate | `conversations(status)` | COUNT where status='failed' |
| Churn signal | `conversations(created_at)` | Days since last activity per user |

## Open Questions

1. **Admin role mechanism.** How is admin access controlled? Hardcoded user IDs, a role column on `users`, or Supabase RLS policy? Needs a decision during planning.
2. **Sparkline time window.** What period do sparklines cover -- 7 days, 14 days, 30 days? Should align with P4's 2-week validation window.
3. **KB sync stats schema.** New table (`kb_sync_stats`) or new columns on `conversations`/`users`? Depends on whether KB growth is per-session or per-sync.
4. **Churn threshold.** How many days of inactivity signals churn? 3 days? 7 days? Needs product input during P4 protocol design.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Feature correctly placed in P3. Without instrumentation, P4 exit criteria become subjective opinion. Recommends queryable data over a dashboard, with privacy policy (P2 item 2.9) as a parallel dependency. Minimum viable: SQL queries against Supabase.

### Engineering (CTO)

**Summary:** Recommends Supabase event table + server-side emission as full option, but acknowledges querying existing data is simpler. Two collection surfaces (web platform server, CLI plugin) must converge on shared user identity. Supabase Auth provides this for the web platform. Flags need to define what "session" means (WebSocket connection lifecycle maps naturally).

### Marketing (CMO)

**Summary:** Don't announce instrumentation -- announce insights when P4 data is meaningful. User-facing growth curves (showing founders their own KB growth) would be a competitive differentiator vs Cursor/Tanka. Defer to post-P4 when data exists. Privacy messaging matters -- frame as "we measure so you don't have to."

### Legal (CLO)

**Summary:** Initial assessment flagged privacy policy Section 4.1 contradiction. On targeted follow-up, confirmed querying existing operational data for internal metrics does NOT require a privacy policy update. KB file count is a derived integer, not personal data. Recommends adding "internal product analytics" as processing purpose in P2 item 2.9 as belt-and-suspenders.

## Deferred Items

- **User-facing growth dashboard:** CMO identified showing founders their own KB growth curve as a competitive differentiator. Deferred to post-P4 validation when data exists to display.
- **Full analytics event pipeline:** CTO's Option A (Supabase `analytics_events` table) deferred. Revisit if P4 validation reveals metrics gaps that existing data can't cover.
- **PostHog integration:** CTO's Option B. Overkill for 10 beta users. Revisit at scale.
