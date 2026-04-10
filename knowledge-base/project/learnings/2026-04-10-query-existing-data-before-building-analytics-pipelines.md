# Learning: Query Existing Data Before Building Analytics Pipelines

## Problem

Phase 4 validation requires 7 specific metrics (domain engagement, session frequency, KB growth, multi-domain usage, time-to-first-value, error rate, churn signals) but no instrumentation exists. The default assumption was that a new event pipeline or analytics tool (PostHog, custom analytics_events table) was needed.

## Solution

Mapped each metric to existing data sources before designing new infrastructure. The `conversations` table already stores `user_id`, `domain_leader`, `status`, and timestamps — making 6 of 7 metrics queryable via SQL. The 7th (KB artifact growth) requires only a file count at the session-sync push boundary, not a full event pipeline.

The approach: Supabase SQL views + an admin dashboard at `/dashboard/admin/analytics` with per-user metrics table and sparklines. No new event pipeline, no third-party analytics, no privacy policy changes (CLO confirmed querying existing operational data is covered by Section 4.7).

## Key Insight

Before building new analytics infrastructure, inventory what existing operational data can answer. Databases already store rich behavioral signals as a side effect of normal operation. For small-scale validation (10 beta users), SQL queries over existing tables beat a dedicated analytics pipeline on every dimension: faster to build, no new privacy surface, no new dependencies, no legal blockers.

The CTO's full option (Supabase `analytics_events` table) and PostHog remain valid for scale — but they're deferred until P4 data proves the need for sub-session granularity or funnel analysis.

## Session Errors

**Worktree creation appeared successful but didn't persist** — The worktree-manager script reported success for `product-analytics-instrumentation` but the directory wasn't found on disk and didn't appear in `git worktree list`. Recovery: Recreated with shorter name `product-analytics`. Prevention: After worktree creation, always verify with `cd <path> && git branch --show-current` before proceeding. Consider filing an issue to investigate the worktree-manager's handling of long names.

## Related

- [#1063](https://github.com/jikig-ai/soleur/issues/1063) — Parent issue
- [#1923](https://github.com/jikig-ai/soleur/issues/1923) — Deferred: user-facing growth dashboard
- [#1924](https://github.com/jikig-ai/soleur/issues/1924) — Deferred: full analytics event pipeline
- [#1931](https://github.com/jikig-ai/soleur/issues/1931) — Deferred: standardized phase exit gate
- `knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md` — Plausible API patterns
- `knowledge-base/product/roadmap.md` line 189 — Roadmap item 3.11

## Tags

category: integration-issues
module: analytics
tags: [analytics, brainstorm, product-validation, supabase, worktree, data-reuse]
severity: low
resolved: true
