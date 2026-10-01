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
doppler run -p soleur -c prd -- bash -c 'psql "${DATABASE_URL_POOLER:-$DATABASE_URL}" \
  --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "
SELECT COALESCE(active_workflow, '"'"'legacy'"'"') AS bucket,
       count(*)            AS conversations,
       sum(total_cost_usd) AS usd
  FROM conversations
 WHERE total_cost_usd > 0
   AND created_at >= date_trunc('"'"'month'"'"', now() AT TIME ZONE '"'"'UTC'"'"')
 GROUP BY 1
 ORDER BY 3 DESC;"
```

Three details in that invocation are load-bearing, and all three were wrong in the first
version of this runbook (caught by the agent-native review on #7916):

- **`bash -c '...'` with SINGLE quotes.** `doppler run -- psql "$DATABASE_URL"` expands
  `$DATABASE_URL` in the INVOKING shell, before Doppler injects anything. That shell does not
  have it (verified: unset), so the command reduces to `psql ""` -- an empty conninfo, which
  libpq silently resolves to a local socket and `$USER` database. You do not get an error that
  says "wrong database"; you get a connection to the wrong one. Single quotes defer expansion
  until Doppler has injected.
- **`${DATABASE_URL_POOLER:-$DATABASE_URL}`.** Every script in this repo resolves the pooler
  first (`run-migrations.sh`, `run-verify.sh`, `preflight-schema-vs-ledger.sh`); the direct URL
  fails on an IPv6-less runner. `hr-no-dashboard-eyeball-pull-data-yourself` names the pooler
  variable specifically.
- **`-c "<query>"`, not a bare `psql`.** A bare `psql` opens an interactive REPL, which blocks
  an agent on stdin until its tool timeout. `hr-no-ssh-fallback-in-runbooks` forbids an
  interactive in-host step as a primary debug action, not merely `ssh` -- and
  `scripts/lint-infra-no-human-steps.py` does not match bare interactive `psql`, so CI will not
  catch a regression here. Keep the `-c`.

Swap the `date_trunc` for any window you want. `AT TIME ZONE 'UTC'` is deliberate: the UI
computes its window with `Date.UTC(...)` in `computeMonthStartIso`, while a bare
`date_trunc('month', now())` evaluates in the session's `TimeZone` GUC. Supabase defaults to
UTC so the two agree today, but pinning it keeps them agreeing.

## Per-user spend — the question the UI answers

The RPC behind Settings → API Usage is `service_role`-only, so an agent holding a user session
cannot call it. This is the same aggregate, runnable directly:

```bash
doppler run -p soleur -c prd -- bash -c 'psql "${DATABASE_URL_POOLER:-$DATABASE_URL}" \
  --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "
SELECT CASE
         WHEN active_workflow IS NULL          THEN '"'"'legacy'"'"'
         WHEN active_workflow = '"'"'__unrouted__'"'"' THEN '"'"'unrouted'"'"'
         ELSE active_workflow END AS bucket,
       count(*)            AS conversations,
       sum(total_cost_usd) AS usd
  FROM conversations
 WHERE user_id = '"'"'<user-uuid>'"'"'
   AND total_cost_usd > 0
   AND created_at >= date_trunc('"'"'month'"'"', now() AT TIME ZONE '"'"'UTC'"'"')
 GROUP BY 1
 ORDER BY 3 DESC;"'
```

The `CASE` is the same normalisation migration 136 applies, so these bucket keys match what the
UI groups by. Note the figures are RAW: the screen renders largest-remainder **allocated**
values, so a bucket can differ from the screen by one display unit, and this query will show
`0.000400` where the UI shows `<$0.0001`. The raw number is the better answer for a machine;
they are not in conflict.

## Bucket key → the label the user sees

Users speak in labels; every machine-reachable surface carries keys. The map is
`apps/web-platform/lib/messages/workflow-copy.ts` (`WORKFLOW_COPY`), reproduced here so an
agent answering "the planning one is eating my budget" can find the row:

| key | label on screen |
|---|---|
| `one-shot` | Idea to shipped |
| `brainstorm` | Exploring an idea |
| `plan` | Planning the work |
| `work` | Doing the work |
| `review` | Reviewing the code |
| `drain-labeled-backlog` | Clearing the backlog |
| `unrouted` | No workflow started |
| `legacy` | Before workflow tracking |

If this table and `workflow-copy.ts` disagree, the TS module wins -- it carries the
`satisfies Record<WorkflowBucket, WorkflowCopy>` rail.

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
