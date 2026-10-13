# Feature: Supabase Prod Disk IO Budget Remediation

**Brand-survival threshold:** `single-user incident` (inherited from brainstorm)
**Source brainstorm:** `knowledge-base/project/brainstorms/2026-05-06-supabase-disk-io-budget-brainstorm.md`

## Problem Statement

Supabase has alerted that the prod project `ifsccnjhymdmidffkzhl` (soleur-web-platform) is depleting its Disk IO Budget. When the budget exhausts, the instance falls back to the Micro baseline (87 MB/s) and becomes unresponsive — every authenticated user sees timeouts, broken chat, failed sends. Live diagnostics show the IO is structural, not user-driven: the top consumers are the Realtime WAL parser (~1.1M ms exec time, 219K calls) polling every ~100ms regardless of activity, and the pg_cron `user_concurrency_slots` reaper running every minute (1,440 runs/day, only 38 actual rows deleted in 14+ days, 4 writes per run including 3 cron-plumbing writes). Active user data is tiny (58 conversations, 126 messages, 0 live concurrency slots).

## Goals

- Reduce structural Disk IO churn so the prod instance stays comfortably under the Micro baseline (87 MB/s) without a compute add-on upgrade.
- Keep dashboard refresh / live conversation list functional from the user's perspective.
- Ship via reversible migrations and a config edit that can be rolled back instantly if a side effect appears.
- Capture before/after `pg_stat_statements` and `pg_stat_user_tables` numbers in the PR description so the savings are demonstrable, not assumed.
- Inherit and respect the `single-user incident` brand threshold throughout planning, deepen-plan, work, review, ship, and preflight gates.

## Non-Goals

- Compute add-on tier upgrade (Micro → Small/Medium/Large). Tracked separately as a tripwire option, only re-evaluated if depletion accelerates during diagnosis.
- Closing the Supabase Terraform provider gap in `apps/web-platform/infra/`. Required prerequisite for any future tier change, not for this PR. Tracked separately.
- Fixing the 2 SECURITY DEFINER `pg_temp` search_path gaps in migrations `017_conversation_cost_tracking.sql:39` and `027_mtd_cost_aggregate.sql:48`. Security-correctness side-finding from research; tracked separately.
- Reducing the 30s WS heartbeat or 60s WS subscription refresh — not in top IO offenders given current load.
- Caching the per-request middleware `users` SELECT in `apps/web-platform/middleware.ts:106-110` — not in top 15 by exec time today.
- Read replica or pooler-tier change — wrong tool for WAL-write-amplification IO.
- Introducing any new data store (Redis/Upstash/KV) — would require Privacy Policy / DPA / GDPR processing-register edits per CLO assessment.

## Functional Requirements

### FR1: pg_cron `user_concurrency_slots` sweep cadence reduced

Lower the sweep frequency from `* * * * *` to `*/5 * * * *` or `*/15 * * * *` (decision deferred to plan after verifying no consumer reads slots assuming sub-5-min freshness). Implementation is a new migration in `apps/web-platform/supabase/migrations/` that calls `cron.alter_job` (or `cron.unschedule` + `cron.schedule`) — not a dashboard click.

### FR2: Realtime publication audit

Audit the Realtime publication on `conversations` + `messages` (added in migration 034). For each subscriber in `apps/web-platform/hooks/use-conversations.ts:232-279` and `:294-316`, decide one of:

- **Keep as-is** — only if the subscription is load-bearing for a feature the user notices and no narrower configuration suffices.
- **Scope** — narrow to specific event types (e.g., `INSERT, UPDATE` only) and/or row filters that match the actual UI needs. Update the publication via migration.
- **Replace** — drop the subscription on the client side and rely on on-demand fetch when the relevant UI surface mounts or the user navigates.

The decision and rationale belong in the plan; the spec only requires the decision is made and reflected in code + migration.

### FR3: Before/after diagnostics captured

The PR description must include:

- `pg_stat_statements` top 10 by total_exec_time, before and after.
- `pg_stat_user_tables` write counts on the affected tables, before and after.
- The Disk IO Budget gauge (or `/billing/addons` equivalent) trend across the change window.

Numbers come from the Supabase Management API queries already proven in the brainstorm (no new tooling needed).

## Technical Requirements

### TR1: Reversible migration only

The pg_cron change MUST be a forward migration that another forward migration can fully reverse. No `cron.unschedule` without re-`cron.schedule` ready in a follow-up file. The `cron.alter_job(jobid, schedule := ...)` form is preferred because it preserves the job identity.

### TR2: No new SECURITY DEFINER functions

If any helper SQL is introduced for the audit (e.g., a view or function exposing slot freshness), it MUST follow `cq-pg-security-definer-search-path-pin-pg-temp` — pin `SET search_path = public, pg_temp` and qualify every relation as `public.<table>`. Preferred: avoid SECURITY DEFINER entirely on this PR.

### TR3: Tests guard the cadence change

Add a Vitest test that asserts the migration produces a non-`* * * * *` cron schedule for `user_concurrency_slots` (the test can read the migration file and grep, since hitting prod from tests is out). If a behavior test exists for slot expiration, update the assumed window — do not silently let it pass on the new cadence.

### TR4: Realtime change must not break dashboard

If FR2 lands as "scope" or "replace", the affected pages in `apps/web-platform/hooks/use-conversations.ts` consumers MUST be functionally tested in a browser before merge. The `single-user incident` threshold rejects "probably fine across the fleet" — the fix must demonstrably leave the next user's dashboard working.

### TR5: PR labels

`semver:patch` (operational fix, no API or behavior contract change for users — the dashboard refresh path may change *how* it refreshes but not *whether* it refreshes).

### TR6: User-impact-reviewer + CPO gates

Per the inherited threshold, plan/deepen-plan must include the `## User-Brand Impact` section, and the review skill must invoke `user-impact-reviewer`. CPO sign-off mandatory before `/work` per `hr-weigh-every-decision-against-target-user-impact`.

### TR7: Stats reset before re-measurement

`pg_stat_statements_reset()` should be called immediately AFTER the migration applies to prod so the "after" window is clean. Do this from the Management API or via a one-off job, not committed to a migration.

### TR8: Roll-back plan

If post-merge the dashboard breaks (FR2) or some downstream code path silently depended on sub-minute slot freshness (FR1), the rollback is: revert the PR, redeploy. The cron migration can be reversed with a single `cron.alter_job(jobid, schedule := '* * * * *')` follow-up. Document this in the PR description.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-06-supabase-disk-io-budget-brainstorm.md`
- Migration that introduced the Realtime publication: `apps/web-platform/supabase/migrations/034_conversations_messages_realtime_publication.sql`
- Migration with the cron schedule: `apps/web-platform/supabase/migrations/029_plan_tier_and_concurrency_slots.sql:219-225`
- Realtime consumers: `apps/web-platform/hooks/use-conversations.ts:232-279`, `:294-316`
- Stuck-active separate path (do not cross-impact): `apps/web-platform/server/agent-runner.ts:523`, `apps/web-platform/supabase/migrations/037_stuck_active_finder_rpc.sql`
- Bound rules: `hr-dev-prd-distinct-supabase-projects` (verified pass), `hr-weigh-every-decision-against-target-user-impact`, `cq-pg-security-definer-search-path-pin-pg-temp`, `hr-all-infrastructure-provisioning-servers` (only relevant if a tripwire bump ships in a follow-up).
