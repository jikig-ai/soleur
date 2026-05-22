---
runbook: cron-retention-monitor
date: 2026-05-22
owner: ops
domain: engineering
related:
  - issue: 4231
  - migration: apps/web-platform/supabase/migrations/062_workspace_member_actions.sql
  - register: knowledge-base/legal/article-30-register.md (PA-19)
---

# pg_cron Retention Monitor — `workspace-member-actions-retention`

Verifies the 7-year retention purge for `public.workspace_member_actions`
(mig 062 / PA-19) is running on schedule. A silently-skipped retention
sweep would be an **undetected Art. 5(1)(e) data-minimisation breach** —
the load-bearing detection signal for the single-user-incident brand-
survival threshold this PR was scoped against.

## 1. Schedule + observability surfaces

The job is scheduled in mig 062 as:

```sql
SELECT cron.schedule(
  'workspace-member-actions-retention',
  '0 4 * * *',
  $$SELECT public.purge_workspace_member_actions()$$
);
```

Daily at 04:00 UTC. The wrapper RPC is required because the pure-reject
WORM trigger on `workspace_member_actions` silently rejects direct
DELETE from `pg_cron` — see learning
`2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`. The wrapper
sets `SET LOCAL session_replication_role='replica'` to bypass the
trigger, performs the DELETE, captures the row count via
`GET DIAGNOSTICS`, RESETs the role, emits `RAISE LOG`, and returns the
count.

Three observability layers feed the monitor:

| Layer | Surface | Contents |
|---|---|---|
| **DB-internal** | `cron.job_run_details` | Auto-populated by pg_cron on every scheduled run. Columns: `jobid`, `runid`, `status` (`succeeded` / `failed` / `running`), `start_time`, `end_time`, `return_message` (the wrapper's RETURN value — the integer row count — appears here). Canonical source of truth for run cadence. |
| **Log stream** | Supabase logs → Vector → Better Stack | Wrapper emits `RAISE LOG 'audit_retention_purge table=workspace_member_actions deleted_count=%'`. Routed via `apps/web-platform/vector.toml`. |
| **Orphan-actor signal** | Same log stream | Trigger emits `RAISE LOG 'audit_orphan_actor workspace_id=% action=%'` (PII-scrubbed; `target_user_id` deliberately omitted per GDPR T-06) when an authenticated-role caller writes to `workspace_members` without setting the `workspace_audit.actor_user_id` GUC. Independent monitor — see §3. |

## 2. Verify the job is scheduled and running (operator MCP query)

Per `hr-no-dashboard-eyeball-pull-data-yourself` + `hr-no-ssh-fallback-in-runbooks`:
use the Supabase MCP server, never Supabase Studio or SSH.

**Manual MCP probe (any time):**

```text
mcp__plugin_supabase_supabase__execute_sql
  project_id: <prd_project_ref>
  query: |
    SELECT
      j.jobname,
      j.schedule,
      j.active,
      (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid AND d.status = 'succeeded') AS succeeded_runs,
      (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid AND d.status = 'failed') AS failed_runs,
      (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid AND d.status = 'succeeded') AS last_success
    FROM cron.job j
    WHERE j.jobname = 'workspace-member-actions-retention';
```

Expected: `active = true`, `last_success` within the last 26 hours,
`failed_runs = 0`.

**Recent run detail:**

```text
mcp__plugin_supabase_supabase__execute_sql
  project_id: <prd_project_ref>
  query: |
    SELECT start_time, end_time, status, return_message
    FROM cron.job_run_details
    WHERE jobname = 'workspace-member-actions-retention'
    ORDER BY start_time DESC
    LIMIT 7;
```

`return_message` carries the deleted row count; expect "0" for steady-
state operation (rows reach the 7y threshold only after many years).

## 3. Better Stack alert specifications

Configure two monitors post-merge (the runbook is the spec; the actual
provisioning is performed via Better Stack's API / dashboard at flag-
flip time).

### 3.1 Missing-purge alert (load-bearing)

- **Query (Supabase logs source):** `SELECT 1 FROM cron.job_run_details WHERE jobname = 'workspace-member-actions-retention' AND status = 'succeeded' AND start_time > now() - interval '26 hours'`
- **Condition:** zero rows → page.
- **Page route:** `ops@jikigai.com`.
- **Severity:** P1 — Art. 5(1)(e) breach detection. A skipped retention sweep is silently undetectable without this alert.
- **Acknowledgement procedure:** see §4.

### 3.2 Orphan-actor alert

- **Query (Supabase logs source):** filter the log stream for the literal `audit_orphan_actor`.
- **Condition:** more than 5 events in any 24-hour rolling window → page.
- **Page route:** `ops@jikigai.com`.
- **Severity:** P2 — the trigger still writes the audit row (with NULL actor) so there is no data loss, but a sustained signal means a new RPC author shipped a workspace_members writer without the `set_config('workspace_audit.actor_user_id', ...)` prepend. Land the GUC-setting fix in a follow-up PR.

## 4. Acknowledging a missing-purge page

If §3.1 fires:

1. Run the MCP probe in §2 to confirm. If `last_success` IS recent (race
   between Better Stack's source query window and a slightly-late run),
   resolve the page.
2. If `failed_runs` > 0 with no recent success: inspect the most-recent
   `return_message` for the failure shape. Common failures:
   - WORM trigger raised P0001 — means the wrapper RPC was DROPped or
     altered to remove `SET LOCAL session_replication_role='replica'`.
     Re-apply mig 062 or a fix migration that restores the bypass.
   - Permission error — means `GRANT EXECUTE ... TO postgres` was
     revoked. Re-grant.
   - Lock contention — extremely unlikely on this small table; if it
     recurs, investigate concurrent long-running transactions on
     `workspace_member_actions`.
3. If `active = false`: the job was unscheduled (manual operator action
   or a Supabase platform migration that affected pg_cron). Re-schedule
   via `SELECT cron.schedule('workspace-member-actions-retention', '0 4 * * *', $$SELECT public.purge_workspace_member_actions()$$);` (MCP query, NOT dashboard).
4. After remediation, manually invoke once to clear the alert:
   `SELECT public.purge_workspace_member_actions();` (MCP query as
   `postgres` role).
5. File a follow-up issue with the root cause, the remediation, and any
   migration that should land to prevent recurrence.

## 5. Why this runbook exists in this layer

Per `hr-observability-layer-citation`: every signal in the
`## Observability` section of the parent plan
(`knowledge-base/project/plans/2026-05-22-feat-workspace-member-actions-audit-plan.md`)
must name where it is configured. This runbook is the configured-in
layer for the cron-cadence signal; the Better Stack monitor created
per §3 is the alert-target layer; ops@jikigai.com is the route layer.

Per `hr-no-ssh-fallback-in-runbooks`: every verification step in this
runbook uses the Supabase MCP server. SSH access to the Supabase host
is not available to the operator (Supabase manages the postgres
instance); the MCP server is the canonical path.
