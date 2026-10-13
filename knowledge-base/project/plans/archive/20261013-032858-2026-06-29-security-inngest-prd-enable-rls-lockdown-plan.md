---
title: "security: enable RLS + revoke anon/authenticated on soleur-inngest-prd (rls_disabled_in_public)"
date: 2026-06-29
type: security
branch: feat-one-shot-inngest-prd-rls-enable
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: ops-remediation (prod-write via Management API, auto-applied on merge)
project_ref: pigsfuxruiopinouvjwy
project_name: soleur-inngest-prd
advisor_rule: rls_disabled_in_public (lint 0013, ERROR/SECURITY)
finding_dated: 2026-06-22
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: no new server/secret/vendor is provisioned. The remediation is a
     versioned SQL artifact auto-applied to an existing project via a merge-triggered GitHub
     Actions workflow using the existing SUPABASE_ACCESS_TOKEN secret — no SSH, no psql by
     hand, no dashboard clicks. The out-of-band inngest project is intentionally not in TF
     (inngest.tf:212-217). "operator" mentions in this plan describe steps that are AUTOMATED
     AWAY, not manual infra actions. See ## Infrastructure (IaC). -->

# security: enable RLS + lock down `soleur-inngest-prd` public tables (rls_disabled_in_public)

🔒 **CRITICAL Supabase security-advisor remediation on a PRODUCTION project.**

Remediate the `rls_disabled_in_public` finding (14 tables) on the dedicated EU Inngest
backing project **soleur-inngest-prd** (`pigsfuxruiopinouvjwy`, eu-west-1). The fix
enables Row-Level Security with **no permissive policies** and **revokes `anon` +
`authenticated` grants**, then stops the recurrence at its source (Supabase default
privileges). Delivered as a forward SQL migration auto-applied on merge via the Supabase
Management API (no SSH, no manual infra step), with advisor before/after + anon-role
read-test evidence in the PR body.

> **Note (spec lane):** no `spec.md` exists for this branch; `lane: cross-domain` set
> explicitly (touches Engineering + Legal/GDPR). Not a fail-closed default — chosen from
> the change shape.

---

## Enhancement Summary

**Deepened on:** 2026-06-29
**Agents:** semantics-verification (sonnet) · security-sentinel · data-integrity-guardian · architecture-strategist
**Hard gates:** 4.6 User-Brand Impact ✔ · 4.7 Observability (5/5 fields, no-ssh) ✔ · 4.8 PAT-shape (no GitHub PAT) ✔ · 4.9 UI-wireframe (no UI surface → skip) ✔

### Key improvements folded in
1. **All 7 load-bearing Postgres/Supabase claims verified** against authoritative docs (see Verified Semantics). Owner-bypass safety, RLS-no-policy default-deny, `ALTER DEFAULT PRIVILEGES` future-only, and the Management-API-bypasses-RLS test caveat all CONFIRM.
2. **Lock-contention hardening (HIGH).** `ALTER TABLE … ENABLE RLS` takes ACCESS EXCLUSIVE; a single DO-block holds all 14 locks. Added `SET lock_timeout='3s'` + `statement_timeout`, per-statement autocommit, retry on `55P03`, and softened the overstated "zero downtime" claim.
3. **GraphQL front door (P1).** PostgREST exposes `public,graphql_public` → pg_graphql `/graphql/v1` is a second door. Added an anon GraphQL data + introspection verification.
4. **Fail-closed project-identity preflight (P1).** A destructive `REVOKE`-all must not inherit the read-only sibling's weak ref-string guard — assert project = `soleur-inngest-prd` / Inngest sentinel before the destructive step.
5. **Authoritative post-apply gate = direct catalog/grant query** (advisor lints can be served stale); advisor count is corroborating only.
6. **GDPR log-retention horizon (P1, convergent).** Retention is likely shorter than the 2026-06-17→now window → "clean logs" can be a false negative. Gate now records the actual retained window; coverage gap ⇒ **inconclusive** (route to CLO), never "clean". Added service_role-key exposure check + anon-key rotation branch.
7. **Self-healing recurrence (P1).** Collapse apply + recurrence-probe into ONE `push:`+`schedule:` workflow; a scheduled run re-applies the idempotent SQL (no-op when clean) instead of deferring to "file an issue".
8. **Workflow security parity:** both `strip_log_injection` AND `scrub_pat`, `::add-mask::` the retrieved anon key, pin endpoint to `api.supabase.com`, `curl 2>/dev/null`, SHA-pin all `uses:`, `concurrency:` group, kill-switch, CODEOWNERS rows.
9. **Default-priv revoke widened to SEQUENCES (+ FUNCTIONS);** existing public sequences revoked; post-apply `pg_default_acl` assertion.
10. **C4 correction:** the Inngest store is ALREADY modeled (`model.c4:155-157`, edge `:245`) and is INTERNAL — do NOT add an external node or an anon "vulnerability" edge; optionally refresh the description. ADR lands as **invariant I8** + amendment-log entry (matching I7/#5450/#5560 precedent), not `## Decision` prose.

### Verified Semantics (authoritative-doc citations)
| Claim | Verdict | Source |
|---|---|---|
| Owner `postgres` bypasses RLS when NOT forced (Inngest keeps access) | CONFIRMS | postgresql.org/docs/current/ddl-rowsecurity.html; postgres has `BYPASSRLS` on Supabase |
| RLS enabled + zero policies = default-deny for non-owners EVEN WITH grants | CONFIRMS | postgresql.org/docs/current/ddl-rowsecurity.html ("default-deny policy is used") |
| `REVOKE` is defense-in-depth (RLS-no-policy already blocks) | CONFIRMS | same default-deny rule |
| PostgREST anon exposure = exposed schema + USAGE + table grant; no-RLS ⇒ anon reads all | CONFIRMS | supabase.com/docs/guides/api/securing-your-api |
| `ALTER DEFAULT PRIVILEGES … REVOKE` = future objects only, not existing | CONFIRMS | postgresql.org/docs/current/sql-alterdefaultprivileges.html |
| postgres CAN alter its-own default privs; CANNOT for `supabase_admin` (not a member) | CONFIRMS | PG membership rule + Supabase role hierarchy |
| Management API `database/query` bypasses RLS → anon test must use `SET LOCAL ROLE anon` | CONFIRMS | postgresql.org/docs/current/sql-set-role.html + Supabase RLS docs |

Live confirmation: the Inngest pooler connection's effective role IS `postgres` (the owner) — `scheduled-inngest-health.yml:225` already asserts `usename == "postgres"`. C4: `inngestPostgres` already modeled at `model.c4:155-157` with edge at `:245`.

---

## Premise Validation (Phase 0.6)

All premises were verified **live** against the project before this plan was written
(read-only Supabase Management API, account-scoped PAT `SUPABASE_ACCESS_TOKEN` from Doppler
`soleur/prd_terraform` — the same auth path `scheduled-inngest-health.yml` already uses):

- **Project identity** — `pigsfuxruiopinouvjwy` = `soleur-inngest-prd`, eu-west-1, the
  dedicated Inngest backing store per ADR-030 (`apps/web-platform/infra/inngest.tf:170-184`).
  Distinct from the web-platform Supabase project (hr-dev-prd-distinct-supabase-projects). ✔
- **The finding is live and real** — `GET /v1/projects/pigsfuxruiopinouvjwy/advisors/security`
  returns **14** `rls_disabled_in_public` lints (level ERROR, category SECURITY), one per
  public table. List captured below; this is the PR-body "before" evidence. ✔
- **The worst case is REAL, not theoretical** — `anon` and `authenticated` hold **full DML**
  on every flagged table; PostgREST serves the `public` schema; anon has schema USAGE
  (details under Live Investigation). ✔
- **No external issue/PR cited** — the task is a finding remediation; no `#N` premise to
  re-validate. ADR-030 (`...decisions/ADR-030-inngest-as-durable-trigger-layer.md`) exists
  and is the relevant decision record. ✔
- **Own-capability claims verified** — there is **no** repo-managed migration path for this
  project (Inngest auto-creates its schema at startup); the only `supabase/migrations/` dir
  targets web-platform (verified by directory walk, latest = 113). This plan therefore creates
  a *new* inngest-project SQL artifact + apply workflow rather than adding a `NNN_*.sql`
  migration. ✔

---

## Research Reconciliation — Spec vs. Codebase

| Claim (implied by task framing) | Reality (verified live / in repo) | Plan response |
|---|---|---|
| "Tables in public have RLS disabled" | True — **all 14** public base tables: RLS off, 0 policies, owner `postgres` | Enable RLS on all; no policies |
| "RLS-disable may be intentional" | It is the **default** for tables created by a tool (Inngest) with no RLS awareness; not a deliberate Supabase design choice. Inngest connects only as `postgres` over the session pooler | Treat as misconfiguration; enable RLS — safe because owner `postgres` bypasses non-forced RLS |
| "Anon grant may be absent (lower risk)" | **FALSE — anon + authenticated have full DML** (`SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER`) on all 14; PostgREST `db_schema="public,graphql_public"` | Revoke anon/authenticated; this is the load-bearing exposure fix, not just the lint |
| "Inngest run-state, not PII" | Partly — tables embed **tenant identifiers** (`account_id`, `workspace_id`, `event_user`) and **payload/output blobs** (`events.event_data`, `function_finishes.output`, `history.result`, `spans.input/output/attributes`) that **can contain personal data** | Raise brand-survival threshold to single-user incident; add GDPR actual-access gate |
| "Fix lands as a migration in supabase/migrations/" | That dir targets the **web-platform** project, not `pigsfuxruiopinouvjwy` | New `apps/web-platform/infra/inngest-rls/` artifact + Management-API apply workflow |
| "Pin search_path on SECURITY DEFINER helpers touched" | **No** SECURITY DEFINER functions and **no** views exist in public | N/A — nothing to pin; this plan creates none (pure DDL/DCL). Recorded so the gate is satisfied-by-absence |

---

## Live Investigation Findings (PR-body "before" evidence)

**Captured 2026-06-29 via read-only Management API. No production row data was read — only
the system catalog, grants, and column *schema*.**

### Flagged tables (14) — `GET /advisors/security`
All `rls_disabled_in_public`, level **ERROR**, category **SECURITY**:

`migrations`, `goose_db_version` (Inngest's own migration trackers) · `apps`, `functions`,
`events`, `function_runs`, `function_finishes`, `history`, `event_batches`, `traces`,
`trace_runs`, `queue_snapshot_chunks`, `worker_connections`, `spans` (Inngest
durable-execution state, queue, telemetry).

### RLS / ownership (Q1)
Every one of the 14: `relrowsecurity=false`, `relforcerowsecurity=false`, `policy_count=0`,
`owner=postgres`. Total public base tables = 14 (matches the 14 lints exactly).

### Grants — the real exposure (Q2, Q3, Q7)
- `anon` **and** `authenticated` each granted `DELETE,INSERT,REFERENCES,SELECT,TRIGGER,
  TRUNCATE,UPDATE` on **all 14** tables.
- `has_schema_privilege('anon','public','USAGE') = true`; same for `authenticated`.
- `has_table_privilege('anon','public.events','SELECT'|'INSERT'|'UPDATE'|'DELETE') = true`
  (effective, confirmed for `events` and `history`).
- PostgREST config: `db_schema = "public,graphql_public"`, `max_rows=1000` → the REST API
  **serves these tables to the anon role**.

> **Exposure conclusion:** anyone holding the project URL (`https://pigsfuxruiopinouvjwy.supabase.co`)
> **+ the anon publishable key** can today `GET /rest/v1/events?select=*` (read every event
> payload + tenant ids) and `DELETE`/`TRUNCATE` the durable run-state. This is confirmed
> **real, internet-facing reachability** — materially worse than the advisor's "theoretical".

### Recurrence root cause — default privileges (Q4)
`pg_default_acl` shows `ALTER DEFAULT PRIVILEGES` (grantor `postgres`) granting
`anon,authenticated,service_role` full `arwdDxtm` on **all future tables** in `public`.
Inngest adds tables across versions → **each new table re-opens the same hole** unless the
default privilege is revoked. Enabling RLS on only the current 14 is necessary but **not
durable**.

### PII assessment (Q6 — column schema only, no rows)
Payload/identifier-bearing columns confirmed present:
- `events.event_data`, `events.event_user`, `events.account_id`, `events.workspace_id`
- `function_finishes.output` · `history.result`, `history.wait_result`,
  `history.invoke_function_result`, `history.step_name`
- `spans.input`, `spans.output`, `spans.attributes` (jsonb), `spans.account_id`
- `event_batches.account_id/workspace_id`, `worker_connections.account_id/workspace_id/worker_ip`

→ Classification: **internal Inngest run-state that CAN embed personal data** (operator/tenant
identifiers + event payloads + step I/O). Not "merely internal" for GDPR purposes.

### Negative findings (gate-satisfying)
- **No** SECURITY DEFINER functions in public (Q5 → empty). → search_path-pin gate (cq-pg-security-definer-search-path-pin-pg-temp) is **N/A**.
- **No** views/matviews in public (Q8 → empty). → no `security_definer` view risk.

---

## User-Brand Impact

- **If this lands broken, the user experiences:** server-side agentic runs stall — if RLS were
  enabled with `FORCE` or grants revoked from `postgres`/the pooler role, Inngest could no
  longer read/write its own tables and every durable workflow (cron triggers, agent sessions,
  reminders) would fail. **Mitigation: enable RLS WITHOUT `FORCE`, and never revoke from
  `postgres`/`service_role`.** The pooler role is `postgres` (the table owner); a non-forced
  RLS policy-set does not apply to the owner, so Inngest is unaffected.
- **If this leaks, the user's data is exposed via:** the live PostgREST anon endpoint on
  `pigsfuxruiopinouvjwy` — every operator's Inngest event payloads, step inputs/outputs, and
  `account_id`/`workspace_id` identifiers are readable, and the durable run-state is
  deletable/truncatable, by anyone with the anon key + URL. **This is the current state.**
- **Brand-survival threshold:** **single-user incident** — one unauthorized read of one
  operator's event payload, or one `TRUNCATE` wiping durable run-state, is brand-fatal.
  → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review time.

---

## GDPR / Compliance Analysis + Art. 33 Escalation Gate (Phase 2.7)

This plan touches a regulated-data surface (a misconfiguration that exposed tables which can
embed personal data). `/soleur:gdpr-gate` MUST run at /work against this plan + the SQL artifact.

**Escalation status at plan time: confirmed *real reachability*, NO evidence of *actual
unauthorized access*.** Per the task's escalation rule, the hard STOP → CLO / Art. 33 72h
clock fires only on evidence that personal data was **actually** accessed by unauthorized
parties — which has not (yet) been established. Reachability alone does not start the clock,
but given it is *confirmed real* (not theoretical), the actual-access investigation is a
**load-bearing, blocking Phase 0 gate** with a hard escalation branch:

> **GATE G-ESCALATE (blocking, runs before remediation):**
> 1. **Key-exposure check (anon AND service_role).** Determine whether the `pigsfuxruiopinouvjwy`
>    anon publishable key was ever published/embedded (client bundles, git history, public docs,
>    Doppler audit). As a dedicated backing project, its anon key is expected to live only in the
>    dashboard/Doppler and never to have shipped in a client — confirm. **Also check the
>    `service_role` key** (security P2): service_role BYPASSES RLS entirely, so if it leaked, the
>    breach surface is total and RLS is irrelevant — check git history, CI logs, Doppler audit.
> 2. **Establish the actual log-retention horizon FIRST** (data-integrity + security, convergent
>    P1). Query the retained log window for `pigsfuxruiopinouvjwy`. Supabase log/analytics
>    retention is tier-bounded and is **likely shorter than the ~12-day exposure window** — so a
>    "zero hits" result over a partial window is **absence of evidence, NOT evidence of absence.**
> 3. **Access-log analysis** — pull PostgREST/edge/pg_graphql request logs over the exposure
>    window (**from the true PostgREST-exposure start** — justify it: project-creation / first
>    public-table-served date per `inngest.tf:170-184` provisioning on 2026-06-17, not merely a
>    table's `relfilenode` ctime — **to** remediation date), filtered to anon-authenticated
>    requests against `/rest/v1/*` and `/graphql/v1`.
> 4. **Branch on coverage:**
>    - **Evidence of actual unauthorized anon/service_role access → STOP.** Route to the
>      legal-threshold / CLO path (GDPR Art. 33 72h clock; Art. 30 record). Capture timestamps/IPs.
>    - **Logs cover the FULL window and are clean → proceed;** record the negative finding (window,
>      queries, zero hits) + Art. 30 "no breach — reachability only, remediated" note.
>    - **Logs do NOT cover the full window → verdict is INCONCLUSIVE, not clean.** Record the
>      window actually covered, route the residual-window decision to the CLO, and state the
>      coverage limitation explicitly in the Art. 30 note. Never silently conclude "no breach"
>      from a partial pull.
> 5. **On confirmed key exposure (anon or service_role):** in addition to escalating, **rotate the
>    exposed key** (anon/JWT or service_role) — revoking grants protects the locked tables, but
>    rotation is the clean remediation and de-risks any window before the lockdown applies.

`gdpr-gate` is expected to surface fold-in items beyond this (e.g., DSAR reachability of
event payloads, data-minimization/retention on `events`/`history`/`spans`). Treat its output
as expected signal, not noise.

---

## Implementation Phases

### Phase 0 — Pre-remediation investigation (blocking)
0.1 Re-run the live advisor + grant capture (this plan's Live Investigation queries) to
    confirm state is unchanged; archive JSON as the PR-body "before" evidence.
0.2 **Run GATE G-ESCALATE** (anon-key exposure + access-log analysis). Branch per above.
0.3 Run `/soleur:gdpr-gate` against this plan + the SQL artifact; fold Critical findings.
0.4 Confirm the live consumer's EFFECTIVE role is `postgres` (table owner) so non-forced RLS is
    non-breaking. Two checks: (a) `owner=postgres` on all 14 (captured); (b) the live pooler
    connection's effective role — `scheduled-inngest-health.yml:225` already asserts
    `usename == "postgres"`; additionally run `SELECT current_user, session_user;` over the
    `INNGEST_POSTGRES_URI` session-pooler path and assert both are `postgres`. If the pooler
    resolves to a non-owner role, the owner-bypass guarantee does NOT hold — HALT.

### Phase 1 — Author the forward SQL migration (RED/idempotent)
Create `apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql` (idempotent;
runs as `postgres` via Management API; lock-timeout-guarded; fail-closed identity preflight;
break-glass comment). See **Remediation SQL** below.

### Phase 2 — Author the unified apply + recurrence + verify workflow
Create ONE `.github/workflows/apply-inngest-rls.yml` with BOTH triggers (architecture P1 —
collapse apply + recurrence-probe + self-heal into a single idempotent artifact):
- `push: { branches: [main], paths: [apps/web-platform/infra/inngest-rls/**] }` — initial apply.
- `schedule:` (daily) — re-applies the idempotent SQL (no-op when clean) → durable recurrence
  self-heal, instead of deferring to "file an issue". Rides external GH-Actions (not an Inngest
  cron, per the `new-scheduled-cron-prefer-inngest` gate-override: an Inngest cron can't watch
  the Inngest project's own posture). Daily cadence — do NOT overload the 15-min health watchdog.
- `workflow_dispatch:` — manual re-run.

Security posture mirrors `scheduled-inngest-health.yml` VERBATIM: env-var secret injection (never
argv), **both** `strip_log_injection` AND `scrub_pat` (`sbp_…` redaction) copied verbatim
(functions don't cross GH-Actions steps; `cq-regex-unicode-separators-escape-only`), endpoint
pinned to `api.supabase.com` (no env override), `curl … 2>/dev/null` to keep the `Authorization`
header out of captured output, `::add-mask::` on the retrieved anon key, all `uses:` SHA-pinned
(40-char), a `concurrency:` group, and a `[skip-inngest-rls-apply]` kill-switch.

Steps: fail-closed identity preflight → POST the SQL to `/v1/projects/pigsfuxruiopinouvjwy/database/query`
(retry with backoff on SQLSTATE `55P03` lock-timeout) → **authoritative gate** = direct
catalog/grant query (`relrowsecurity=true` on all public tables AND `has_table_privilege('anon',…,'SELECT')=false`
for all) → corroborate with `GET /advisors/security` (`rls_disabled_in_public == 0`) → inline
postgres-liveness round-trip + anon read-test + `pg_default_acl` assertion (capture all).

### Phase 3 — Local verification harness
Add `apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` (mirrors sibling
`inngest-*.test.sh`): assert the SQL is idempotent-shaped (DO-loop, `REVOKE`, `ALTER DEFAULT
PRIVILEGES FOR ROLE postgres`), contains **no** `FORCE ROW LEVEL SECURITY`, **no** `CREATE
POLICY`, and **never** revokes from `postgres`/`service_role`.

### Phase 4 — ADR-030 amendment + C4
Amend ADR-030 with the RLS-lockdown invariant; verify/extend the C4 model (see Architecture
Decision section).

### Phase 5 — Post-merge verification (automated, no manual step)
The apply workflow runs on merge (and self-heals daily via `schedule:` — no separate recurrence
monitor to file). Capture the authoritative-gate result + advisor + anon/GraphQL + `pg_default_acl`
evidence into the PR/issue. `Ref #<finding-issue>` in PR body (NOT `Closes` — the remediation
completes post-merge when the workflow applies); close the issue after the authoritative catalog
gate is green.

---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Files to Create

- `apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql` — the forward migration (lock-guarded, identity-preflighted, sequences + default-priv, break-glass comment).
- `.github/workflows/apply-inngest-rls.yml` — UNIFIED `push:`+`schedule:`+`workflow_dispatch:` Management-API apply + recurrence self-heal + authoritative catalog gate + advisor corroboration.
- `apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` — static guards on the SQL shape (see Phase 3).

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — add RLS-lockdown as **invariant I8** under `## Load-bearing invariants` + a dated `## Updates / amendment log` entry (matching the I7/#5450/#5560 placement precedent — NOT prose appended to `## Decision`).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — OPTIONAL: refresh the `inngestPostgres` element *description* (`:155-157`) to note "public tables RLS-locked; reachable only as `postgres` owner". The store + edge are ALREADY modeled (`model.c4:155-157`, edge `:245`, rendered in `views.c4`) and are INTERNAL — do NOT add an external node or an anon "vulnerability" edge (C4 models legitimate architecture, not revoked exposures). `spec.c4`/`views.c4` unchanged.
- `apps/web-platform/infra/inngest.tf` — add a header comment cross-referencing the RLS-lockdown artifact near the `INNGEST_POSTGRES_URI` out-of-band paragraph (documentation only).
- `.github/CODEOWNERS` — add explicit load-bearing rows for `/apps/web-platform/infra/inngest-rls/` and `/.github/workflows/apply-inngest-rls.yml` (umbrella coverage already exists by inheritance; explicit rows match every sibling apply-workflow's intent-signaling).

---

## Remediation SQL (the forward migration)

```sql
-- apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql
-- Remediates rls_disabled_in_public (lint 0013) on soleur-inngest-prd (pigsfuxruiopinouvjwy).
-- TARGET: the DEDICATED Inngest backing project ONLY. NEVER the web-platform project.
-- Applied as role `postgres` via the Supabase Management API (database/query). Idempotent.
--
-- SAFETY: RLS is enabled WITHOUT FORCE. Inngest connects as `postgres` (the table owner) over
-- the session pooler; a non-forced policy-set does not apply to the owner, so Inngest keeps
-- full access. We NEVER revoke from postgres/service_role. Zero policies: these tables are
-- service-internal and must never be reachable by anon/authenticated.

-- 0) Lock-acquisition + statement guards (data-integrity HIGH). ALTER TABLE ... ENABLE RLS takes
--    ACCESS EXCLUSIVE; on a live queue/telemetry DB a hot table (function_runs, queue_snapshot_
--    chunks, spans, history) may have an in-flight txn. lock_timeout makes a blocked ALTER FAIL
--    FAST (SQLSTATE 55P03) instead of stalling Inngest behind the lock queue. Because the
--    migration is idempotent + the workflow retries, a lock-timeout failure is a safe, retryable
--    outcome — NOT a stall. (Metadata-only DDL: no table rewrite.)
SET lock_timeout = '3s';
SET statement_timeout = '30s';

-- 0b) FAIL-CLOSED project-identity preflight (architecture P1; hr-dev-prd-distinct-supabase-projects).
--     A destructive REVOKE-all must NOT trust only the workflow URL's ref string. Abort unless an
--     Inngest-specific sentinel table exists — i.e. we are on the Inngest project, never web-platform.
DO $$
BEGIN
  IF to_regclass('public.goose_db_version') IS NULL
     OR to_regclass('public.function_runs') IS NULL THEN
    RAISE EXCEPTION 'ABORT: Inngest sentinel tables absent — refusing to run lockdown against a non-Inngest project';
  END IF;
END $$;

-- 1) Enable RLS + revoke client-role grants on every current public base table + sequence.
--    Each ALTER/REVOKE is its own statement (autocommit) so a contended table holds only its own
--    ACCESS EXCLUSIVE lock, not all N at once. (If the Management-API endpoint wraps the whole
--    payload in one txn regardless, lock_timeout above remains the load-bearing mitigation.)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', r.tablename);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated;', r.tablename);
  END LOOP;
  -- Sequences: anon retaining USAGE/SELECT on serial/identity sequences is residual surface (security P2).
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON SEQUENCE public.%I FROM anon, authenticated;', r.sequencename);
  END LOOP;
END $$;

-- 2) Stop recurrence at the source. Supabase default privileges auto-GRANT anon/authenticated
--    full DML on every NEW table created by `postgres`; Inngest adds tables across versions.
--    Revoking the default (grantor = postgres, the role Inngest creates tables as) closes the
--    hole for future tables too. TABLES + SEQUENCES + FUNCTIONS (security P2). (The
--    supabase_admin-grantor default ACL governs Supabase's own tables, not Inngest's, and
--    postgres cannot alter it — intentionally omitted; verified postgres is not a supabase_admin member.)
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON FUNCTIONS FROM anon, authenticated;

-- ============================================================================================
-- BREAK-GLASS (NOT auto-applied — incident response only). If the apply ever breaks Inngest
-- (e.g. the connection role proves NOT to be the owner in prod), the FASTEST non-re-exposing
-- unblock is to DISABLE RLS while KEEPING grants revoked (anon stays locked out by missing grant):
--     ALTER TABLE public.<t> DISABLE ROW LEVEL SECURITY;   -- per affected table
-- Re-GRANTing anon/authenticated is the LAST resort (it re-opens the vulnerability) and must be
-- paired with an immediate re-apply of this lockdown. There is intentionally NO automated .down.
-- ============================================================================================
```

> Idempotency: `ENABLE ROW LEVEL SECURITY`, `REVOKE`, and `ALTER DEFAULT PRIVILEGES … REVOKE`
> are all safe to re-run. The DO-loop self-maintains over whatever public tables/sequences exist
> at apply time (no hard-coded 14), so a re-apply after an Inngest version bump re-locks any new
> object. **Expected post-apply lint shift:** enabling RLS with zero policies clears the ERROR
> `rls_disabled_in_public` but introduces the INFO/WARN `rls_enabled_no_policy` (lint 0008) on
> each table — this is EXPECTED and correct (owner-only, intentionally client-unreachable); the
> workflow's pass/fail gate is scoped to `rls_disabled_in_public` only, so the info lint is not a
> regression.

---

## Verification — advisor before/after + anon-role read test (PR-body evidence)

**Authoritative gate = the direct catalog/grant query (architecture P1).** Supabase advisor lints
are computed periodically and can be served STALE right after a DDL change (false-green or
false-red). So the workflow's pass/fail is the direct query; the advisor count is corroborating.

1. **Advisor before** — archived JSON above (14 × `rls_disabled_in_public`).
2. **AUTHORITATIVE after-gate (fail the job on any violation)** — direct catalog/grant query over
   ALL public tables (not just `events` — the DO-loop is dynamic; data-integrity MED):
   ```sql
   SELECT count(*) AS violations FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND (c.relrowsecurity = false OR has_table_privilege('anon', c.oid, 'SELECT'));
   ```
   Assert `violations = 0`. Corroborate with `GET /advisors/security` → `rls_disabled_in_public == 0`
   (expect 14 × `rls_enabled_no_policy` INFO — not a regression). Capture both.
3. **Default-priv revoke landed (the durable fix — security/data-integrity P2)** — assert
   `pg_default_acl` has no `anon`/`authenticated` default grant for grantor `postgres` in `public`:
   ```sql
   SELECT count(*) FROM pg_default_acl d JOIN pg_namespace n ON n.oid=d.defaclnamespace
   WHERE n.nspname='public' AND d.defaclrole='postgres'::regrole
     AND (d.defaclacl::text LIKE '%anon=%' OR d.defaclacl::text LIKE '%authenticated=%');
   ```
   Assert `0`. (Or: create a throwaway table as `postgres`, assert anon has zero privilege, drop it.)
4. **Inline postgres-liveness (catches a break immediately, not on the 15-min watchdog)** — in the
   apply workflow: `BEGIN; SET LOCAL ROLE postgres; SELECT count(*) FROM public.events; ROLLBACK;`
   succeeds → Inngest's owner access intact; fail the job otherwise.
5. **Anon read-test (in-DB, no row exfiltration)** — via Management API:
   ```sql
   BEGIN; SET LOCAL ROLE anon; SELECT count(*) FROM public.events; ROLLBACK;
   ```
   (Management API bypasses RLS → `SET LOCAL ROLE anon` is the correct simulation, verified.)
   **Before:** returns a count. **After:** errors `permission denied for table events`. Capture.
   `count(*)` (a scalar), never row data, to avoid reading personal data.
6. **Anon read-test (PostgREST, most faithful)** — `::add-mask::` then retrieve the anon key via
   `GET /v1/projects/pigsfuxruiopinouvjwy/api-keys`, then count-only (no rows):
   ```
   curl -sI "https://pigsfuxruiopinouvjwy.supabase.co/rest/v1/events?select=count" \
     -H "apikey: <anon>" -H "Authorization: Bearer <anon>" -H "Prefer: count=exact" 2>/dev/null
   ```
   Before → 200 + count; After → 401/permission-denied. Capture.
7. **Anon GraphQL test — the SECOND front door (security P1).** `db_schema` is `public,graphql_public`
   (pg_graphql). As anon against `https://pigsfuxruiopinouvjwy.supabase.co/graphql/v1`:
   (a) a data query (`{ eventsCollection { edges { node { internalId } } } }`) returns
   permission-denied/empty; (b) an introspection query does NOT enumerate the Inngest tables/columns
   (per-role schema should drop them once grants are revoked). Before → visible; After → denied/absent.

---

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `0001_enable_rls_lockdown.sql` exists, is idempotent, contains the DO-loop + `REVOKE` (tables
      + sequences) + `ALTER DEFAULT PRIVILEGES FOR ROLE postgres` (TABLES + SEQUENCES + FUNCTIONS) +
      `SET lock_timeout`/`statement_timeout` + the fail-closed Inngest-sentinel identity preflight +
      a break-glass comment, and contains **no** `FORCE ROW LEVEL SECURITY`, **no** `CREATE POLICY`,
      **no** revoke of `postgres`/`service_role` (all asserted by `inngest-rls.test.sh`; the test
      also asserts `lock_timeout` IS present and the identity preflight IS present;
      `bash apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` exits 0).
- [ ] `apply-inngest-rls.yml`: `push:`(paths `inngest-rls/**`)+`schedule:`+`workflow_dispatch:`;
      `SUPABASE_ACCESS_TOKEN` via env (never argv); **both** `strip_log_injection` AND `scrub_pat`
      copied verbatim and `sanitize()` runs on every echoed body; endpoint pinned to `api.supabase.com`
      (no override) with `curl … 2>/dev/null`; `::add-mask::` on the retrieved anon key; all `uses:`
      SHA-pinned (40-char); a `concurrency:` group; a `[skip-inngest-rls-apply]` kill-switch; the
      fail-closed identity preflight runs BEFORE the destructive step; retry on SQLSTATE `55P03`;
      **authoritative gate = direct catalog/grant query** (advisor `rls_disabled_in_public` is
      corroborating only).
- [ ] PR body carries advisor "before" JSON (14) + GATE G-ESCALATE result, including the **actual
      log-retention window covered** and an explicit verdict of clean / **inconclusive** / escalate
      (anon AND service_role key-exposure findings).
- [ ] `actionlint` passes on the new workflow; embedded `run:` shell passes `bash -c`.
- [ ] ADR-030 gets invariant **I8** + amendment-log entry; C4 cited "already modeled" (optional
      `inngestPostgres` description refresh) — NO external node / anon edge added.
- [ ] `.github/CODEOWNERS` has explicit rows for the new SQL dir + workflow.
- [ ] PR body uses `Ref #<issue>` (not `Closes`) — remediation completes post-merge.

### Post-merge (automated by the apply workflow; no manual step)
- [ ] Authoritative catalog gate: `violations = 0` (all public tables `relrowsecurity=true` AND
      anon has no SELECT) — workflow asserts; evidence captured.
- [ ] `GET /advisors/security` → **0** `rls_disabled_in_public` (corroborating; expect 14 ×
      `rls_enabled_no_policy` INFO — not a regression).
- [ ] `pg_default_acl` shows no `anon`/`authenticated` default grant for grantor `postgres` in
      `public` (durable recurrence fix verified).
- [ ] Inline postgres-liveness round-trip succeeds in the apply job (owner access intact).
- [ ] In-DB anon read-test errors `permission denied` on `public.events` (captured).
- [ ] PostgREST anon-key count-test → 401/permission-denied; GraphQL `/graphql/v1` anon data query
      denied/empty AND introspection does not enumerate Inngest tables (captured).
- [ ] `scheduled-inngest-health.yml` probe green after apply (no durable-run regression).
- [ ] Scheduled re-apply run is a no-op-when-clean (recurrence self-heal proven on first `schedule:` fire).
- [ ] `gh issue close <finding-issue>` after the authoritative gate is green.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO). Product = NONE (no user-facing surface).

### Engineering (CTO)
**Status:** assessed (inline; deepen-plan + review phase will deepen via data-integrity-guardian + security-sentinel + architecture-strategist).
**Assessment:** Pure DDL/DCL on a dedicated backing store. The load-bearing risk is breaking
Inngest's own access — mitigated by non-forced RLS + owner (`postgres`) bypass + never
revoking `postgres`/`service_role`. The durable-recurrence fix (default-privilege revoke) is
the architecturally significant addition. No SECURITY DEFINER funcs/views → no search_path
surface. Cross-project blast radius is zero (web-platform project untouched).

### Legal (CLO)
**Status:** assessed (inline); `/soleur:gdpr-gate` + GATE G-ESCALATE run at /work.
**Assessment:** Confirmed real reachability of tables that can embed personal data
(operator/tenant identifiers + event payloads). No evidence of actual access yet → no Art. 33
clock started, but the actual-access investigation is a blocking gate with a hard escalation
branch. Art. 30 note required either way (reachability-only-remediated, or breach).

### Product/UX Gate
Not applicable — no `components/**`, no `app/**/page.tsx`, no user-facing surface. Tier: NONE.

**CPO sign-off:** required at plan time (threshold = single-user incident). Confirm CPO has
reviewed before `/work` begins.

---

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

This is not Terraform (no Supabase provider is declared — `inngest.tf:212-217` documents why
the out-of-band inngest project is not in TF). The IaC here is the **versioned SQL artifact +
merge-triggered apply workflow**, consistent with how the repo already touches this project
(Management API + `SUPABASE_ACCESS_TOKEN` PAT). **No SSH, no `psql` by hand, no dashboard
clicks** (hr-all-infrastructure-provisioning-servers, hr-no-ssh-fallback-in-runbooks).

### Apply path
ONE unified `apply-inngest-rls.yml` with `push:` (paths `inngest-rls/**`) + `schedule:` (daily) +
`workflow_dispatch:`. The merge IS the human authorization (the four sibling apply workflows —
`apply-web-platform-infra.yml`, `apply-sentry-infra.yml`, `apply-github-infra.yml`,
`apply-deploy-pipeline-fix.yml` — deliberately dropped the `environment:` reviewer gate per #4220;
CODEOWNERS + branch protection are the load-bearing control). The job POSTs the SQL to the
Management API as `postgres` after a fail-closed identity preflight, runs the authoritative
catalog gate, and self-heals recurrence: the daily `schedule:` re-applies the idempotent SQL
(no-op when clean), re-locking any table a new Inngest version added — NO "file an issue" defer.

**Lock posture (corrected — not "zero downtime"):** the DDL is metadata-only but takes ACCESS
EXCLUSIVE per table; `lock_timeout='3s'` makes a contended ALTER fail-fast (`55P03`) and the job
retries with backoff. Worst case is a fast-failing retryable apply, NOT a stall of live Inngest
traffic. Owner-bypass governs *correctness after RLS is on*, not *lock acquisition during apply* —
these are distinct and the earlier "zero downtime" framing conflated them.

### Secrets / auth
Reuses the existing `SUPABASE_ACCESS_TOKEN` GH Actions secret (published by
`inngest.tf:232-236` from Doppler `prd_terraform`). **No new secret, no new vendor, no mint.**
Anti-exfil parity with `scheduled-inngest-health.yml`: both `strip_log_injection` AND `scrub_pat`
verbatim, endpoint pinned to `api.supabase.com` (no override), `curl … 2>/dev/null`,
`::add-mask::` on the retrieved anon key, all `uses:` SHA-pinned, `concurrency:` group + kill-switch.

### Distinctness / drift safeguards
Defense-in-depth against the wrong-project hazard (a destructive REVOKE-all must not trust only a
URL string — architecture P1): (1) the workflow URL hard-codes ref `pigsfuxruiopinouvjwy`; (2) the
SQL itself runs a **fail-closed identity preflight** (`RAISE EXCEPTION` unless the Inngest sentinel
tables `goose_db_version` + `function_runs` exist) before any REVOKE; (3) the artifact lives under
`infra/inngest-rls/`, not `supabase/migrations/`, so the web-platform migration runner can never
pick it up.

---

## Observability

```yaml
liveness_signal:
  what: authoritative catalog/grant gate (violations=0) in apply-inngest-rls.yml; advisor count corroborating
  cadence: on every merge touching infra/inngest-rls/** AND daily via schedule: (self-healing re-apply)
  alert_target: GitHub Actions job failure → tracking issue ONLY when a re-apply does not clear violations
  configured_in: .github/workflows/apply-inngest-rls.yml
error_reporting:
  destination: GitHub Actions run logs (job fails loud); Inngest-health probe (scheduled-inngest-health.yml) covers connection-breakage regression
  fail_loud: true  # advisor>0 OR SQL error OR Inngest probe red => job fails, no silent pass
failure_modes:
  - mode: SQL apply error (e.g. permission denied on ALTER DEFAULT PRIVILEGES)
    detection: workflow step non-zero exit
    alert_route: GH Actions failure
  - mode: advisor still reports rls_disabled_in_public post-apply
    detection: post-apply GET /advisors/security assertion
    alert_route: GH Actions failure (job red)
  - mode: Inngest can no longer reach its tables (regression if FORCE/wrong revoke shipped)
    detection: scheduled-inngest-health.yml probe (15-min) + heartbeat
    alert_route: existing inngest watchdog (auto-restart + P1 issue + Sentry)
  - mode: recurrence — new Inngest-version table reappears as rls_disabled_in_public
    detection: recommended scheduled advisor probe
    alert_route: tracking issue
logs:
  where: GitHub Actions run logs (apply workflow); Better Stack (Vector inngest logs) for runtime
  retention: GH Actions default; Better Stack per plan
discoverability_test:
  command: 'curl -s -H "Authorization: Bearer $PAT" https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/advisors/security | jq "[.lints[]|select(.name==\"rls_disabled_in_public\")]|length"'
  expected_output: "0 after remediation (14 before). No SSH."
```

---

## Architecture Decision (ADR/C4)

This tightens an access boundary on an existing substrate (it does not change the
architecture), so it **amends ADR-030** rather than creating a new ADR.

### ADR
Add to `ADR-030-inngest-as-durable-trigger-layer.md` a numbered **load-bearing invariant I8**
(under `## Load-bearing invariants`) plus a dated `## Updates / amendment log` entry — matching how
I7 (#5560 secrets-via-env) and the #5450 durable-backend amendment were placed. Do NOT append prose
to `## Decision`. Invariant text:
> **I8 — RLS lockdown.** The Inngest backing project's public tables have RLS **enabled (not
> forced)**, **zero policies**, and **`anon`/`authenticated` table+sequence grants revoked**;
> Supabase default privileges for role `postgres` in `public` (TABLES/SEQUENCES/FUNCTIONS) are
> revoked so future Inngest tables do not re-open anon access. Inngest reaches its tables solely as
> the `postgres` owner over the session pooler (owner bypass), so the lockdown is non-breaking.

### C4 views
The Inngest backing store is **ALREADY correctly modeled** and verified against all three `.c4`
files: `model.c4:155-157` defines `inngestPostgres = database "Supabase PostgreSQL (Inngest)"`
inside `platform.infra`, with edge `inngest -> inngestPostgres "Config + run history"` (`:245`),
rendered in `views.c4` (`containers`). It is **INTERNAL** to the platform boundary — so **no C4
structural change**: do NOT add an `#external` node, and do NOT draw an anon-access edge (C4 models
legitimate architecture, not a now-revoked vulnerability). The only legitimate, OPTIONAL touch is
refreshing the `inngestPostgres` *description* to record "public tables RLS-locked; reachable only
as `postgres` owner". Enumeration checked (per the C4 completeness mandate): external human actors
— none new; external systems/vendors — none new (the store is internal, Supabase Management API is
an existing ops edge); containers/data-stores — `inngestPostgres` already present; access
relationships — the `inngest → inngestPostgres` owner edge is unchanged (anon was never a modeled
edge). If only the description is touched, re-run `apps/web-platform/test/c4-code-syntax.test.ts` +
`c4-render.test.ts`.

---

## Risks & Sharp Edges

- **FORCE RLS would break Inngest.** Use `ENABLE`, never `FORCE`. The owner (`postgres`)
  bypasses non-forced RLS; `FORCE` removes the owner bypass and would lock Inngest out of its
  own tables. The test harness asserts `FORCE` is absent.
- **Never revoke from `postgres`/`service_role`.** Only `anon`, `authenticated`. Revoking the
  owner/service role breaks the legitimate consumer. Asserted by the test harness.
- **`ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin` would fail** — `postgres` is not a
  member of `supabase_admin`. Intentionally omitted; only the `postgres`-grantor default ACL
  governs Inngest's future tables.
- **The advisor lint can recur on the NEXT Inngest version's tables** even after this fix:
  default-privilege revoke removes the *anon grant* on future tables (so a new table is
  grant-safe), but RLS is not a privilege and cannot be auto-enabled, so the lint reappears.
  **Mitigation (self-healing, NOT defer):** the unified `apply-inngest-rls.yml` carries a daily
  `schedule:` trigger that re-applies the idempotent SQL — a no-op when clean, and a re-lock when a
  new table appeared. This closes the loop with zero human action (mirrors the watchdog's
  auto-restart pattern; honors `hr-exhaust-all-automated-options-before` + the never-defer-operator
  feedback). The authoritative catalog gate fails the scheduled job if a re-apply does NOT clear it
  → that failure (not a routine recurrence) is what files a tracking issue.
- **Lock contention during apply (HIGH).** `ALTER TABLE … ENABLE RLS` takes ACCESS EXCLUSIVE; a
  hot Inngest table (`function_runs`, `queue_snapshot_chunks`, `spans`, `history`) may have an
  in-flight txn. Mitigated by `SET lock_timeout='3s'` (fail-fast `55P03`, safe to retry because
  idempotent) + per-statement autocommit so a contended table holds only its own lock. The
  "zero downtime" framing was corrected to "metadata-only DDL, lock-timeout-guarded; worst case is
  a fast-failing retryable apply, not a stall."
- **GDPR log-retention can falsify a "clean" verdict.** Supabase log retention is likely shorter
  than the 2026-06-17→now exposure window; a partial-window "zero hits" is absence-of-evidence.
  GATE G-ESCALATE records the actual covered window and returns **inconclusive** (→ CLO), never
  "clean", on a coverage gap. service_role-key exposure is also in-scope (it bypasses RLS).
- **Wrong-project hazard.** The web-platform `supabase/migrations/` dir (at 113) targets a
  DIFFERENT project. This artifact must live under `infra/inngest-rls/` and be applied only via
  the workflow's hard-coded `pigsfuxruiopinouvjwy` URL.
- **GDPR actual-access gate is blocking.** Do not skip GATE G-ESCALATE to rush the code fix —
  if logs show anon reads, the Art. 33 clock is the priority, not the migration.
- **The Management API `database/query` runs as a superuser-ish role and bypasses RLS** — so it
  is unsuitable for the *anon* read-test; the test must `SET LOCAL ROLE anon` (or use the
  PostgREST anon key) to exercise the real client path.
- **AC discipline:** advisor-after, anon-test, and Inngest-liveness ACs assert *checkable
  post-conditions* (advisor count = 0; permission-denied error; probe green), not phase
  ceremony.

---

## Open Code-Review Overlap

None — no open `code-review` issue touches `apps/web-platform/infra/inngest-rls/**` (new
path), `apply-inngest-rls.yml` (new), or ADR-030. (Re-run the overlap query at /work once the
finding-issue number is known.)

---

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Enable RLS only (skip grant revoke) | Clears the lint but leaves the **real** anon DML exposure; the grants are the actual hole |
| Add permissive policies for anon | Wrong — these tables must never be client-reachable; re-opens access (explicitly forbidden by scope) |
| `FORCE ROW LEVEL SECURITY` | Breaks Inngest (removes owner bypass) |
| Apply via manual `psql`/dashboard | Violates no-SSH/no-manual-infra rules; the Management-API workflow is fully automatable |
| Put SQL in `supabase/migrations/NNN_*.sql` | Targets the WRONG project (web-platform), not `pigsfuxruiopinouvjwy` |
| Skip default-privilege revoke | Leaves recurrence open on every future Inngest table |
