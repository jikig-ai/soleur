---
module: Supabase Migrations
date: 2026-05-15
problem_type: security_issue
component: rails_model
symptoms:
  - "pg_cron retention sweep DELETE silently rejected with P0001 on every fire"
  - "Audit-trail rows accumulate past their documented retention envelope"
  - "Art. 5(1)(e) storage-limitation non-compliance with no visible failure signal"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [worm-trigger, pg-cron, retention, security-definer, gdpr, art-5, supabase, defense-in-depth]
related_issues: [3744, 3777]
related_files:
  - "apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql"
  - "apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql"
synced_to: []
---

# WORM trigger silently blocks pg_cron retention sweep when bypass is role-gated

## Problem

When a Supabase migration combines a WORM-protected audit table (BEFORE UPDATE/DELETE triggers raising `P0001`) with a `pg_cron`-scheduled retention sweep that issues `DELETE FROM ... WHERE <retention_col> < now()`, the trigger blocks the sweep silently.

Concrete failure mode in `041_dsar_export_jobs.sql:182-213` (and would have shipped in `043_tenant_deploy_audit.sql` if not caught at review):

```sql
-- WORM trigger function (lines 182-213)
IF v_anonymise_flag <> '' AND current_user = 'service_role' THEN
  RETURN COALESCE(NEW, OLD);  -- bypass for Art. 17 anonymise flow
END IF;
RAISE EXCEPTION 'dsar_export_audit_pii is append-only (WORM)' USING ERRCODE = 'P0001';

-- pg_cron retention sweep (lines 382-396)
DELETE FROM public.dsar_export_audit_pii
 WHERE event_at < now() - interval '24 months';
```

`pg_cron` jobs execute as the role that called `cron.schedule()` — typically `postgres` (the migration runner), never `service_role`. The retention sweep sets no GUC and runs as `postgres`. The trigger's `current_user = 'service_role'` test evaluates false. `RAISE EXCEPTION` fires. Every nightly retention DELETE returns `P0001 'is append-only (WORM)'` to pg_cron and the entire DELETE rolls back. Rows accumulate forever; the audit table's documented retention envelope is fictional.

The silent-failure surface is the worst part: pg_cron's per-job error appears in `cron.job_run_details` but does not page anyone. The 24-month retention envelope passes a reviewer's reading test ("the cron job is scheduled") while failing the actual storage-limitation requirement (no rows ever get deleted).

## Detection gap (why this slipped reviews before)

PR #3744 caught this defect class in 043 only because two reviewers independently flagged it via different reasoning paths:

- **user-impact-reviewer F6** (P2): enumerated `## User-Brand Impact` failure modes against the diff and noticed the plan never named "retention sweep blocked by WORM" as a covered vector.
- **security-sentinel Informational**: noted the role-gate semantics in passing and recommended a dev-apply smoke test.

The **data-integrity-guardian** agent, which ran a 10-point verification specifically scoped to migration safety, **did not** flag the issue. Its checks (FK direction, search_path order, REVOKE/GRANT shape, regex tightness, oidc_jti type, enum membership, etc.) verified each element in isolation; none of them composed the bypass clause against the cron-sweep caller role.

This is a **feature-wiring composition bug** (see `2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md`): module A (WORM trigger) is correct in isolation, module B (retention cron) is correct in isolation, but A+B together violate a constraint that lives in module C (the operational role the cron job runs under). Reviewer prompts must enumerate the downstream caller-role explicitly for agents to reach it.

## Solution

Add a row-state-based bypass clause to the WORM trigger that gates on the row's own retention column — not on the caller's role. The bypass is then independent of which role pg_cron runs as.

```sql
CREATE OR REPLACE FUNCTION public.tenant_deploy_audit_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_anonymise_flag text;
BEGIN
  v_anonymise_flag := current_setting('app.tenant_deploy_anonymise_in_progress', true);

  -- Bypass 1: Art. 17 anonymise (role + GUC gated)
  IF v_anonymise_flag <> '' AND current_user = 'service_role' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Bypass 2: Retention sweep (row-state gated, role-independent).
  -- pg_cron's scheduling role is `postgres`, not `service_role`, so
  -- Bypass 1's role gate cannot apply. The retention DELETE must still
  -- succeed. The bypass condition is mechanically tight: only DELETE
  -- (UPDATEs never bypass), only rows whose retention_until is past
  -- now(). WORM property is preserved for non-expired rows and for any
  -- UPDATE attempt; Art. 5(1)(e) makes retention the authorization
  -- basis, not access role.
  IF TG_OP = 'DELETE'
     AND OLD.retention_until IS NOT NULL
     AND OLD.retention_until < now() THEN
    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'tenant_deploy_audit is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;
```

Three invariants the row-state bypass preserves:

1. **UPDATE remains rejected unconditionally.** The `TG_OP = 'DELETE'` guard means audit-trail row integrity is never compromised by a runtime-driven mutation.
2. **DELETE of non-expired rows remains rejected.** Even a `service_role` session calling `DELETE` without setting the anonymise GUC must fail; bypass 2 only fires when `retention_until < now()`.
3. **The bypass is independent of caller role.** Any operator with DML access on the table (service_role, superuser, or pg_cron's scheduling role) can reap expired rows. Per Art. 5(1)(e), retention is the legal basis for deletion — not role identity.

Verified empirically in dev for migration 043 (`/soleur:ship` Phase 5.4): three test paths under transaction-rollback wrappers confirmed (a) UPDATE on non-expired row → P0001, (b) DELETE on non-expired row → P0001, (c) DELETE on row with `retention_until` forced into past → succeeds under non-service_role context.

## Prevention

When authoring or reviewing a migration that combines WORM triggers with pg_cron retention sweeps:

1. **Enumerate the cron job's caller role explicitly** in the review prompt. The default for `cron.schedule()` invoked from a `DO $$ ... $$` block in a migration is the migration runner's role (`postgres` in Supabase), NOT `service_role`. Naming the role surfaces the bypass mismatch.

2. **Verify bypass clauses against every legitimate mutator.** For each row state that should be deletable/updatable (Art. 17 anonymise → role+GUC; Art. 5(1)(e) retention → row-state), the trigger must have a corresponding bypass clause. Enumerate the legitimate-mutator matrix before writing the trigger body.

3. **Smoke-test the retention sweep in dev.** A focused test: insert a row, force `retention_until` to a past value (via Bypass 1's anonymise context), then attempt DELETE under a non-service_role connection. If the DELETE is blocked, the bypass is incomplete.

4. **Prefer row-state over role-state bypasses for time-based deletion.** Role gates couple the bypass to operational architecture (which scheduler, which role, which Supabase project). Row-state gates couple the bypass to the regulatory authorization (the retention column is the Art. 5(1)(e) authorization). The latter is more durable across infrastructure changes.

## Session Errors

**WebFetch returned navigation-only content for ToS pages** — Hetzner/Cloudflare/Doppler ToS landing pages are dynamic SPAs that don't return ToS body via simple HTTP fetch. Recovery: authored ToS-research artifact from training knowledge with cited URLs marked DRAFT. Prevention: when the source is a dynamic doc site, fetch via Playwright MCP or pull the doc PDF directly.

**Supabase MCP OAuth unavailable in pipeline mode** — couldn't auto-execute dev migration apply during /work phase. Recovery: deferred dev apply to /ship Phase 5.4, then used `doppler run + Docker-wrapped psql` because postgresql-client wasn't installed locally. Prevention: SKILL.md's operator-automation gate should distinguish "tool exists but unauthenticated" from "tool unavailable". When MCP needs OAuth, fall back to CLI + Doppler-injected DATABASE_URL or to a Docker-wrapped client.

**psql not installed locally** — `apps/web-platform/scripts/run-migrations.sh` requires it. Recovery: built a Docker wrapper `docker run --rm -i --network host postgres:17-alpine psql "$@"` and prepended to `PATH`. Prevention: document the Docker-wrapped fallback in `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`.

**WORM trigger blocked pg_cron retention DELETE (the primary subject of this learning)** — caught by cross-agent concurrence at review (user-impact-reviewer F6 + security-sentinel Informational); data-integrity-guardian's 10-point check did not surface it. Recovery: added `Bypass 2: DELETE when retention_until < now()` clause; filed #3777 for the same defect class in pre-existing 041. Prevention: see Prevention section above — name the cron job's caller role in the review prompt.

**`target_repo` CHECK regex was overly permissive** — original `[A-Za-z0-9_./-]{1,255}` accepted `..`, `./.`, `-rf`, no-slash values. security-sentinel P2-A caught it. Recovery: tightened to enforce GitHub `owner/repo` shape (owner 1-39 chars alnum-bounded; repo 1-100 chars starting alnum or underscore). Prevention: when a column stores an identifier with a known external format (GitHub repo slug, RFC 7519 jti, etc.), the CHECK regex should enforce the format-spec, not just the charset.

**Plan AC named wrong migration-apply CLI** — plan said `npx supabase migration up`; actual mechanism is `apps/web-platform/scripts/run-migrations.sh` which uses `psql` + `public._schema_migrations` tracking. Recovery: discovered the right script via repo inspection during /ship Phase 5.4. Prevention: plan-time CTO assessment must verify CLI invocations against the actual runner script — `git ls-files "*scripts/*" | grep -iE "migration|migrate"` would have surfaced the truth.

## References

- PR #3744 — `feat-soleur-managed-deploy-substrate-3723` (where this defect class was caught at review).
- Issue #3777 — symmetric fix pending in pre-existing migration 041 (`pre-existing-unrelated` scope-out).
- `apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql` — the corrected pattern (lines 116-146).
- `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:182-213` — the uncorrected precedent.
- `knowledge-base/project/learnings/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md` — parent defect class (feature-wiring composition bugs).
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — cross-agent concurrence as detection method.
