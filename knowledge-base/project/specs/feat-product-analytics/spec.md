# Spec: Product Analytics Instrumentation for P4 Validation

**Issue:** #1063
**Branch:** product-analytics
**Date:** 2026-04-10
**Brainstorm:** [2026-04-10-product-analytics-instrumentation-brainstorm.md](../../brainstorms/2026-04-10-product-analytics-instrumentation-brainstorm.md)

## Problem Statement

Phase 4 validation requires specific metrics (domain engagement, session frequency, KB growth, multi-domain usage) but no instrumentation exists to track them. Plausible covers marketing page views only. Without data, P4 exit criteria ("5+ users engage 2+ domains for 2+ weeks") are unjudgeable.

## Goals

- G1: Surface all 7 P4 validation metrics via an admin dashboard
- G2: Make metrics queryable before Phase 4 recruitment begins
- G3: Derive metrics from existing operational data with minimal new infrastructure
- G4: Track KB artifact growth at the session-sync boundary

## Non-Goals

- NG1: User-facing analytics dashboard (deferred to post-P4)
- NG2: New event pipeline or analytics_events table
- NG3: Third-party analytics integration (PostHog, Mixpanel)
- NG4: Privacy policy updates (parallel P2 workstream, not a blocker)
- NG5: Real-time metrics (batch/on-demand queries are sufficient)

## Functional Requirements

- FR1: Admin-only route at `/dashboard/admin/analytics` displaying per-user metrics table
- FR2: Per-user domain engagement metric (count of sessions per domain leader)
- FR3: Session frequency metric (sessions per day/week with sparkline trend)
- FR4: Multi-domain usage metric (count of distinct domain leaders per user)
- FR5: KB artifact growth metric (file count delta per sync event)
- FR6: Time-to-first-value metric (time from signup to first conversation)
- FR7: Error/failure rate metric (percentage of sessions with status='failed')
- FR8: Churn signal indicator (days since last activity per user)
- FR9: Inline sparklines for trend visualization (no external charting library)

## Technical Requirements

- TR1: All metrics derived from existing `conversations`, `messages`, `users` tables via SQL queries/views
- TR2: KB growth tracked by counting knowledge-base/ file changes during session-sync push operations
- TR3: Admin access control (mechanism TBD during planning -- role column, hardcoded IDs, or RLS policy)
- TR4: Server-rendered page (no client-side data fetching for metrics)
- TR5: No new third-party dependencies for charting (inline SVG sparklines)

## Acceptance Criteria

- AC1: Dashboard shows per-user domain engagement counts matching conversations table data
- AC2: Dashboard accessible only to admin users; non-admins see 403
- AC3: KB growth delta displayed per user, updated after each session-sync push
- AC4: All 7 P4 metrics visible on a single page
- AC5: Sparklines show at minimum 14-day trend (matching P4 validation window)
- AC6: Page loads in under 2 seconds with 50 users of data

## Dependencies

- Supabase `conversations` and `users` tables (existing)
- Session-sync module (`apps/web-platform/server/session-sync.ts`) for KB growth hook
- Admin role/access mechanism (to be designed)

## Open Design Questions

1. Admin access mechanism (hardcoded IDs vs role column vs RLS)
2. Sparkline time window (7, 14, or 30 days)
3. KB sync stats storage (new table vs column on existing table)
4. Churn threshold definition (days of inactivity)
