---
title: "Runbook: Fleet-wide per-workflow spend"
category: observability
tags: [supabase, cost, byok, workflow, psql, fleet-wide]
date: 2026-09-07
# Deliberately EMPTY, not omitted -- same reasoning as supabase-log-query.md: this
# documents a QUERY, not an incident procedure, so incident/SKILL.md Phase 3 should
# never offer it as a symptom match.
triggers: []
---

# Runbook: Fleet-wide per-workflow spend

**TL;DR:** one SQL block against the application database, run through Doppler. This is the
**fleet-wide** counterpart to the per-user breakdown in Settings → API Usage.

```bash
doppler run -p soleur -c prd -- psql "$DATABASE_URL"
```

```sql
-- Per-workflow spend, all users, any window. Exact and durable -- this is the
-- source the per-user settings breakdown partitions, not a copy of it.
SELECT COALESCE(active_workflow, 'legacy') AS bucket,
       count(*)            AS conversations,
       sum(total_cost_usd) AS usd
  FROM conversations
 WHERE total_cost_usd > 0
   AND created_at >= '<since>'
 GROUP BY 1
 ORDER BY 3 DESC;
```

Replace `<since>` with the window you want (`date_trunc('month', now())` for month-to-date).
The invocation mechanism is the one `apps/web-platform/scripts/run-migrations.sh` already
documents. **No SSH** (`hr-no-ssh-fallback-in-runbooks`).

## Why this is not the same query the UI runs

The UI calls `sum_user_mtd_cost_by_workflow(uid, since)` (migration 136), which is
`SECURITY DEFINER`, `service_role`-only, and **scoped to one user**. This runbook's query has
no `user_id` predicate, so it answers a question the RPC deliberately cannot: *where is spend
going across the whole fleet?*

Two differences to keep in mind when reconciling the two:

- **Bucket naming.** The RPC normalises the storage sentinel `__unrouted__` to `unrouted`.
  This raw query does not — it will show `__unrouted__` verbatim. That is intentional here:
  an operator querying the table should see what the table holds.
- **The window is `created_at`, not spend time.** A conversation created last month that
  accrued cost this month counts against **last** month in both this query and the UI. That
  is a pre-existing property of the MTD headline, not something migration 136 introduced;
  changing it would change a number users already see. Tracked separately.

## Reading the `legacy` bucket

`legacy` is `active_workflow IS NULL` — conversations that predate workflow attribution, or
that never entered a named workflow. On a young deployment this bucket can be **everything**:
as of 2026-09-07 it was 100% of costed conversations on dev.

A large `legacy` share is therefore not a defect signal on its own. It becomes one only if it
stays large for conversations created *after* workflow attribution shipped — which is the
query to run if you suspect the write path has regressed:

```sql
SELECT COALESCE(active_workflow, 'legacy') AS bucket, count(*)
  FROM conversations
 WHERE created_at >= '<date attribution shipped>'
 GROUP BY 1 ORDER BY 2 DESC;
```

## Related

- [`supabase-log-query.md`](./supabase-log-query.md) — platform logs (postgres/auth/postgrest)
  via the Management API's ClickHouse endpoint. A **different mechanism** from this runbook:
  that one queries logs through a helper script, this one queries application tables through
  `psql`. Do not reach for `supabase-logs-query.sh` to answer a cost question.
- `apps/web-platform/supabase/migrations/136_workflow_cost_rollup.sql` — the per-user RPC and
  its bucket normalisation.
