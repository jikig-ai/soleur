---
title: "security: durable RLS self-heal on soleur-inngest-prd via a ddl_command_end event trigger"
date: 2026-06-30
type: security
branch: feat-one-shot-durable-rls-inngest-prd
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: rejected-alternative (2026-07-01 — event trigger declined at the CPO gate; shipped change was the cron daily→hourly tightening, see ⛔ banner + ADR-030 changelog 2026-07-01)
classification: ops-remediation — REJECTED ALTERNATIVE (the event-trigger mechanism below was not built; the shipped remediation is the cron daily→hourly change in apply-inngest-rls.yml, auto-applied on merge + hourly self-heal, no new SQL artifact)
project_ref: pigsfuxruiopinouvjwy
project_name: soleur-inngest-prd
advisor_rule: rls_disabled_in_public (lint 0013, ERROR/SECURITY) — recurrence prevention
extends: knowledge-base/project/plans/2026-06-29-security-inngest-prd-enable-rls-lockdown-plan.md
adr: ADR-030 (amended 2026-07-01 — I8 cadence daily→hourly; event-trigger alternative recorded as declined)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- REJECTED-ALTERNATIVE NOTE (2026-07-01): the Phase 2.8 review below was for the event-trigger
     design, which was NOT adopted. As-shipped there is NO new 0002_*.sql artifact — only a one-line
     cron-cadence change (daily→hourly) in the EXISTING apply-inngest-rls.yml. The original ack is
     retained verbatim for the reasoning trail.
     Phase 2.8 reviewed: no new server / secret / vendor. [Event-trigger design, declined:] would have
     added ONE idempotent SQL artifact (0002_*.sql) applied to an EXISTING project via the EXISTING
     merge-triggered apply-inngest-rls.yml workflow using the EXISTING SUPABASE_ACCESS_TOKEN. No SSH,
     no psql by hand, no dashboard clicks. See ## Infrastructure (IaC). -->

# security: durable RLS self-heal on `soleur-inngest-prd` via a `ddl_command_end` event trigger

> ## ⛔ DECISION 2026-07-01 — event trigger NOT adopted; this plan is a rejected-alternative record
> The `requires_cpo_signoff` gate below (and the deepen-plan's "right-sizing dissent") routed the primary-mechanism choice to the CPO. **The CPO chose the cheaper, zero-new-risk alternative: tighten the existing `apply-inngest-rls.yml` self-heal cron from daily (`17 4 * * *`) to hourly (`17 * * * *`)**, bounding the *cosmetic* `rls_disabled_in_public` advisor-recurrence window to ≤1h. The `ddl_command_end` event trigger described in the rest of this plan was **declined** — it fires inside Inngest's own `CREATE TABLE` transaction (migration-abort risk on the brand-survival-critical path) to remove only a cosmetic advisor email, an asymmetric trade. The data-exposure hole was already closed permanently by the 2026-06-29 lockdown's `ALTER DEFAULT PRIVILEGES … REVOKE` (new tables are born ungranted). Shipped change + decision record: ADR-030 changelog 2026-07-01. **Everything below is retained for the reasoning trail; it was not implemented.**

🔒 **Recurrence-prevention hardening on a PRODUCTION project.** Brand-survival threshold: `single-user incident` (carry-forward from the parent lockdown — the Inngest tables can embed tenant identifiers + event payloads).

Make the `rls_disabled_in_public` critical advisor on the dedicated EU Inngest backing project **soleur-inngest-prd** (`pigsfuxruiopinouvjwy`) genuinely **non-recurring** by adding a Postgres `ddl_command_end` event trigger that **auto-enables ROW LEVEL SECURITY on every new public table the instant Inngest's goose migrations create it** — closing the up-to-24h advisor-recurrence window the existing daily self-heal cron otherwise leaves open. No permissive policies (deny-all is intentional; Inngest connects as the `postgres` owner over the session pooler and bypasses non-forced RLS).

> **Note (spec lane):** no `spec.md` exists for this branch; `lane: cross-domain` set explicitly (Engineering + Legal/GDPR), matching the parent lockdown plan and ADR-030. Not a fail-closed default — chosen from the change shape.

---

## Enhancement Summary (deepen-plan, 2026-06-30)

**Hard gates:** 4.6 User-Brand Impact ✔ · 4.7 Observability (5/5 fields, no-ssh) ✔ · 4.8 PAT-shape (none) ✔ · 4.9 UI-wireframe (no UI surface → skip) ✔
**Review agents:** data-integrity-guardian · security-sentinel · architecture-strategist · code-simplicity-reviewer (all 4 converged: no blocking violation; design is safe; fold-ins below).

### Key improvements folded in
1. **Broadened `WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')`** (architecture) — all three emit `object_type='table'`, so this closes the CTAS/SELECT-INTO gap for free and makes the "cannot recur" claim true for every per-table DDL Inngest can emit. `object_type='table'` stays the load-bearing filter, preserving the `%s`-on-`object_identity` quoting-safety invariant.
2. **Recursion rationale corrected** (data-integrity + security): the load-bearing guard is the `WHEN TAG` filter (the function's own `ALTER`/`REVOKE` carry other tags), NOT any "PG disables event triggers in-function" behavior (PG does fire them). Phrasing fixed so a future maintainer doesn't relax `WHEN TAG`.
3. **Break-glass ↔ daily-gate reconciliation** (data-integrity, operational bug): a break-glass `ALTER EVENT TRIGGER … DISABLE` (`evtenabled='D'`) would have tripped `trg_present=0` → a P1 `[ci/inngest-rls]` issue filed **every day** until re-enabled. Gate split into `trg_exists` (FAIL if the row is absent = real regression) vs `trg_enabled` (WARN-not-fail when intentionally disabled).
4. **`object_type='table'` + `%s`-on-`object_identity` documented as the load-bearing injection-safety invariant** (security) — any future widening of the object-type/tag scope must re-examine quoting.
5. **`fn_ok` gate tightened** to exact `search_path=public, pg_temp` (security) instead of `%public%pg_temp%`.
6. **Self-test residue guard** `DROP TABLE IF EXISTS` before create (architecture) — a killed run no longer leaves a probe table.
7. **ADR: add I9 (not extend I8); brand-survival weight on the exception-safety constraint**, advisor-non-recurrence as defense-in-depth (architecture framing correction).

### Right-sizing dissent → **CPO decides the primary mechanism before `/work`**
Both code-simplicity and architecture independently flagged the trade as **asymmetric**: the event trigger introduces a new failure mode on the brand-survival-critical path (it fires inside Inngest's `CREATE TABLE` txn — an unswallowed raise would abort an Inngest goose migration) in exchange for eliminating a **cosmetic** ≤24h advisor-email window on a table anon already cannot read. The cheaper alternative (tighten the existing daily cron to **hourly** — one line, zero new primitive, zero migration-abort risk, ≤1h window) is by the plan's own admission viable. **The task explicitly named the event trigger as the preferred approach, so this plan keeps it primary — but the decision is routed to the already-required `requires_cpo_signoff` gate:** CPO must explicitly choose **event-trigger (window→0, +migration-abort risk, mitigated by exception-safety)** vs **cron-hourly (window≤1h, zero new risk)** before `/work` begins. Honest framing per the reviewers; the exception-safety apparatus + the live self-test + the migration-abort risk section all exist *only because* the chosen primitive carries that risk.

### Honesty corrections
- The headline "genuinely non-recurring" holds for every per-table DDL (now incl. CTAS/SELECT INTO); only a `pg_restore`-style bulk reload (no per-table event) bypasses the trigger — covered by the default-priv revoke + daily cron backstop.
- **Daily functional correctness of the trigger relies on the cron `violations>0` backstop** — the live self-test is push/dispatch-only, so a silently-inert trigger (swallows everything, never enables RLS) passes `trg_exists=1 AND fn_ok=1` and is caught only when the next real table appears (≤24h). Stated plainly rather than implying continuous functional verification.

---

## Premise Validation (Phase 0.6)

All premises were verified **live** against `pigsfuxruiopinouvjwy` on 2026-06-30 (read-only Supabase MCP / Management API, plus two self-cleaning rolled-back probes) **and** against the repo. **The task framing is partially stale and the plan is re-scoped accordingly — this is the load-bearing finding.**

- **Current advisor state — RESOLVED, as the task says.** `get_advisors(security)` returns **only 14 × `rls_enabled_no_policy` (INFO)** and **zero `rls_disabled_in_public`**. Live catalog: 14 public tables, `tables_rls_off = 0`. The deny-all posture is correct. ✔
- **"Yesterday's fix was a manual `ALTER TABLE` … NOT durable" — STALE.** Yesterday's PR (`feat-one-shot-inngest-prd-rls-enable`, ADR-030 amendment 2026-06-29) shipped a **durable, automated** mechanism, not a manual ALTER:
  - `apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql` — an **idempotent dynamic DO-loop** over *all current* public tables (no hard-coded 14), `ENABLE RLS` (not forced) + `REVOKE ALL FROM anon, authenticated` on tables/sequences/matviews.
  - **`ALTER DEFAULT PRIVILEGES FOR ROLE postgres … REVOKE`** (TABLES/SEQUENCES/FUNCTIONS) — so a **new** postgres-created table **never receives an anon/authenticated grant**. The *actual anon-reachability* of a future table is therefore **already closed at creation time**.
  - `.github/workflows/apply-inngest-rls.yml` — applies on merge **and runs daily (`cron: 17 4 * * *`)**, re-applying the idempotent SQL (no-op when clean) → already self-heals new tables within ≤24h, with an authoritative catalog/grant gate and a tracking-issue-on-failure path.
  - Backed by a test (`inngest-rls.test.sh`), a postmortem, a GDPR/CLO determination ("reachability-only, no notifiable breach"), and ADR-030 invariant **I8**.
- **So what actually recurs?** Only the **cosmetic** advisor lint. A new Inngest table has `relrowsecurity = false` until the daily cron flips it on, so `rls_disabled_in_public` fires (CRITICAL email) for **up to 24h** — even though anon **cannot read it** (grant already revoked). The recurrence is an advisor-state lag, **not** a data-exposure hole. The plan must say this honestly so the change is right-sized.
- **Preferred approach (event trigger) — FEASIBLE.** `CREATE EVENT TRIGGER` is normally superuser-gated and `postgres` here is **`is_superuser = off` / `rolsuper = false`**. But an empirical, self-cleaning, rolled-back probe via the Management API `database/query` path (the **same path the apply workflow uses**) returned **`CREATE_EVENT_TRIGGER_OK`**. Six Supabase-owned event triggers already exist (`pgrst_ddl_watch`, `issue_pg_cron_access`, …, all `supabase_admin`); a 7th named `inngest_rls_self_heal_trg` will not collide. ✔
- **Capability self-check (`hr-verify-repo-capability-claim-before-assert`).** The workflow's `SQL_FILE` env applies a single file today; applying a second file requires a small workflow edit (verified by reading `apply-inngest-rls.yml:75,98,106`). CODEOWNERS already covers the dir (`/apps/web-platform/infra/inngest-rls/` → `@deruelle`, line 123). No `0002_*.sql` exists yet (`ls` confirmed). ✔
- **Not a Supabase-tracked migration.** `list_migrations(pigsfuxruiopinouvjwy)` is empty (Inngest goose-managed schema); the web-platform `supabase/migrations/` dir targets a **different** project. The artifact correctly lives under `infra/inngest-rls/`. ✔

**No external issue/PR is cited by the task** — nothing to re-resolve via `gh`. ADR-030 is the relevant decision record; this plan **amends** it (extends I8 / adds I9), it does not contradict it.

---

## Research Reconciliation — Spec vs. Codebase

| Claim (task framing) | Reality (verified live / in repo, 2026-06-30) | Plan response |
|---|---|---|
| "Yesterday's fix was a manual `ALTER TABLE` … not durable" | It is a versioned idempotent SQL + `ALTER DEFAULT PRIVILEGES REVOKE` + **daily self-heal cron** (`apply-inngest-rls.yml`), already shipped | Re-scope: this plan **adds Layer 3** (instant DDL-time enable) on top, it does not build durability from scratch |
| "A new Inngest table re-opens the anon hole / re-triggers the critical advisor" | The **anon hole is already closed** at creation (default-priv revoke = no grant on new tables). Only the **cosmetic advisor lint** recurs (≤24h) until the cron flips RLS on | Close the residual **advisor-recurrence window** to ~0; state explicitly this is window-elimination + defense-in-depth, not a new exposure fix |
| "Use a `ddl_command_end` event trigger (preferred)" | Feasible: `CREATE EVENT TRIGGER` as `postgres` via the Management API returns OK despite `is_superuser=off` (live probe) | Adopt the event trigger as the primary mechanism; keep the daily cron as the **backstop** |
| "SECURITY DEFINER, search_path pinned to `pg_temp`" | Project convention `cq-pg-security-definer-search-path-pin-pg-temp` is `SET search_path = public, pg_temp` (**public FIRST**) + qualify relations | Pin `public, pg_temp` (the actual convention), qualify via `pg_event_trigger_ddl_commands().object_identity` (already schema-qualified) |
| "One-time backfill for existing tables missing RLS" | `0001`'s DO-loop already backfills all existing tables; live `tables_rls_off = 0` | Backfill = re-confirm `0001` (no new backfill needed); the event trigger covers **future** tables |
| "Lives on the Inngest-managed DB, not a Supabase-tracked migration" | True — `list_migrations` empty; artifact under `infra/inngest-rls/` | Keep under `infra/inngest-rls/`; document in ADR-030 + `inngest.tf` cross-ref |

---

## User-Brand Impact

- **If this lands broken, the user experiences:** stalled server-side agentic runs. The **only new failure mode** this change introduces is that the event trigger fires inside Inngest's `CREATE TABLE` transaction (`ddl_command_end`), so a function that **raised an exception would roll back Inngest's goose migration** and break the very Inngest upgrade we are protecting. **Mitigation (load-bearing):** the function body is **exception-safe** — every action is wrapped so a failure `RAISE WARNING`s and is swallowed, never propagated; the daily cron remains the backstop; and a break-glass `ALTER EVENT TRIGGER … DISABLE;` is documented in the SQL.
- **If this leaks, the user's data is exposed via:** nothing new — the change strictly *reduces* exposure (it enables RLS earlier). The pre-existing exposure vector (anon PostgREST on `pigsfuxruiopinouvjwy`) is already closed by `0001` (grants revoked + RLS on). This plan adds **no** policy and **never** re-grants anon/authenticated.
- **Brand-survival threshold:** **single-user incident** (carry-forward from ADR-030 / the parent lockdown). → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review time. CPO sign-off here is the single product-owner ack on the approach; CLO/CTO concerns are reflected in Risks + Domain Review (not re-signed per the staged sign-off model).

---

## GDPR / Compliance Note (Phase 2.7)

This touches a `.sql` + DB-security surface, so it is in `gdpr-gate` scope, but it introduces **no new processing activity and no new data movement** — it strictly strengthens the existing deny-all posture (enables RLS earlier on tables that anon already cannot read). The parent PR ran the full `GATE G-ESCALATE` + CLO determination (`reachability-only, no notifiable breach`; Art. 33/34 not triggered) and that determination is **unchanged** by this hardening. `gdpr-gate` may run at `/work` against `0002` + the workflow diff; it is expected **low-signal** (no Art. 9 data, no new lawful-basis question, no new sub-processor). Record the determination in the PR body; no Article 30 amendment required (the substrate and data flow are identical to I8).

---

## Implementation Phases

### Phase 0 — Pre-implementation re-confirmation (blocking, read-only)
0.1 Re-run the live state capture (advisors + `pg_class.relrowsecurity` + `pg_event_trigger`): confirm `rls_disabled_in_public = 0`, `tables_rls_off = 0`, and no pre-existing `inngest_rls_self_heal_trg`. Archive as PR-body "before" evidence.
0.2 Re-run the **feasibility probe** (self-cleaning, rolled-back `CREATE EVENT TRIGGER` as `postgres`) to confirm `CREATE_EVENT_TRIGGER_OK` is still true at `/work` time. If it ever returns FAIL, **HALT** and fall back to the cron-cadence alternative (see Alternatives) — do not ship a trigger that cannot be created on the apply path.
0.3 Confirm the consumer's effective role is `postgres` (owner) — reuse the parent's evidence (`scheduled-inngest-health.yml:225` asserts `usename == "postgres"`; `0001` already verified owner-bypass). The event trigger ALTERs a postgres-owned table as postgres → non-breaking.

### Phase 1 — Author the idempotent event-trigger SQL (`0002`)
Create `apps/web-platform/infra/inngest-rls/0002_rls_self_heal_event_trigger.sql` (full text under **Setup SQL** below): fail-closed Inngest-sentinel preflight → `CREATE OR REPLACE FUNCTION public.inngest_rls_self_heal()` (`SECURITY DEFINER`, `SET search_path = public, pg_temp`, **exception-safe**, scoped to `CREATE TABLE` + `object_type='table'` + `schema_name='public'`, `ENABLE RLS` + defensive `REVOKE`) → `REVOKE ALL ON FUNCTION … FROM PUBLIC, anon, authenticated` → idempotent `DROP EVENT TRIGGER IF EXISTS … ; CREATE EVENT TRIGGER … WHEN TAG IN ('CREATE TABLE')` → break-glass comment.

### Phase 2 — Wire `0002` into the existing apply workflow
Edit `.github/workflows/apply-inngest-rls.yml`:
- **Apply both SQL files in deterministic order** (`0001` then `0002`). Replace the single `SQL_FILE` POST with a sorted loop over `apps/web-platform/infra/inngest-rls/0*.sql` (each POSTed as its own `database/query`, keeping the `55P03` retry/backoff). Preserves all existing anti-exfil parity (`strip_log_injection`+`scrub_pat`, pinned `api.supabase.com`, `curl … 2>/dev/null`, SHA-pinned `uses:`, `concurrency:`, `[skip-inngest-rls-apply]` kill-switch).
- **Extend the authoritative gate** (catalog-only, runs on every trigger incl. the daily schedule). **Break-glass-aware (data-integrity):** distinguish a *missing* trigger row (DROP = real regression → FAIL) from an *intentionally-disabled* one (`evtenabled='D'` via break-glass → WARN, do NOT fail — otherwise a break-glass disable would file a daily P1 issue forever):
  ```sql
  select
    -- trg_exists: the trigger ROW is present (any evtenabled). Absence = regression (dropped) → FAIL.
    (select count(*) from pg_event_trigger where evtname='inngest_rls_self_heal_trg') as trg_exists,
    -- trg_enabled: O/R/A = live; D = intentionally break-glass-disabled → WARN, not fail.
    (select count(*) from pg_event_trigger
       where evtname='inngest_rls_self_heal_trg' and evtenabled in ('O','R','A')) as trg_enabled,
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='inngest_rls_self_heal'
         and p.prosecdef
         and array_to_string(coalesce(p.proconfig,'{}'),',') like '%search_path=public, pg_temp%') as fn_ok;
  ```
  Job logic: **FAIL** (record `selfheal_trigger_missing` / `selfheal_fn_misconfigured`) unless `trg_exists=1 AND fn_ok=1`. If `trg_exists=1 AND trg_enabled=0` (break-glass DISABLE), emit a **non-failing WARNING** (do not file the daily P1 issue). The `fn_ok` match is the **exact** `search_path=public, pg_temp` element (security: avoids a loose `%public%pg_temp%` that would pass an interposed schema).
- **Live trigger self-test (push + `workflow_dispatch` only — NOT the daily schedule; effectively the one-time post-merge functional confirmation)**: create a throwaway table, assert RLS auto-enabled + anon has no grant, drop it (proves the trigger is live, not merely present). **Residue-guarded** so a killed run leaves nothing behind:
  ```sql
  drop table if exists public._rls_selfheal_probe;   -- residue guard (a prior killed run)
  create table public._rls_selfheal_probe(id int);
  select relrowsecurity as rls_on,
         has_table_privilege('anon','public._rls_selfheal_probe','SELECT') as anon_select
  from pg_class where oid='public._rls_selfheal_probe'::regclass;
  drop table public._rls_selfheal_probe;
  ```
  Assert `rls_on = true AND anon_select = false`; record `selfheal_trigger_inert` on failure. **Note (architecture):** because the function is intentionally exception-safe, daily *functional* correctness is NOT continuously verified — a silently-inert trigger passes `trg_exists/fn_ok`; the cron `violations>0` gate is the genuine functional backstop (catches it ≤24h when a real table appears).
- **Implementation-time security checks (at `/work`, per security review):** the new `run:` steps MUST build their SQL from constants only (the literal ref `pigsfuxruiopinouvjwy` + the literal probe name) — interpolate NO `${{ github.event.* }}` / `inputs.*`. Do not add any `workflow_dispatch` input (the self-test needs none); if one is ever added it must be regex-validated before use. Keep every `uses:` SHA-pinned (no `@vN` tag).

### Phase 3 — Test harness
Extend `apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` to also static-shape-guard `0002` (comment-stripped, mirroring the existing pattern): `SECURITY DEFINER` present; `SET search_path = public, pg_temp` present (public first); exception-safe (`EXCEPTION WHEN OTHERS` + `RAISE WARNING` present); scoped (`WHEN TAG IN ('CREATE TABLE')` + `schema_name = 'public'`); `ENABLE ROW LEVEL SECURITY` present; idempotent install (`DROP EVENT TRIGGER IF EXISTS` + `CREATE EVENT TRIGGER`); and the forbidden set reused from `0001` — **no** `FORCE ROW LEVEL SECURITY`, **no** `CREATE POLICY`, **no** `REVOKE` targeting `postgres`/`service_role`.

### Phase 4 — ADR-030 amendment + C4
Extend invariant **I8** (or add **I9 — RLS self-heal at DDL time**) and add a dated `## Updates / amendment log` entry. **No C4 structural change** (see Architecture Decision section — the `inngestPostgres` store + owner edge are already modeled and internal). Run the C4 freshness suite only if a `.c4` *description* is touched.

### Phase 5 — Post-merge verification (automated, no manual step)
The merge fires `apply-inngest-rls.yml` (push trigger): applies `0001`+`0002`, runs the extended authoritative gate + the live trigger self-test, captures evidence. `Ref #<tracking-issue>` in the PR body (NOT `Closes` — remediation completes post-merge when the workflow applies); close the issue after the gate + self-test are green.

---

## Files to Create

- `apps/web-platform/infra/inngest-rls/0002_rls_self_heal_event_trigger.sql` — idempotent `SECURITY DEFINER` event-trigger install (full text below).

## Files to Edit

- `.github/workflows/apply-inngest-rls.yml` — apply `0*.sql` in sorted order; extend authoritative gate with the event-trigger + function-config assertion; add the push/dispatch-only live trigger self-test; add `selfheal_*` failure modes to the issue-filing branch.
- `apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` — add `0002` static-shape guards (Phase 3).
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — extend I8 / add I9 + amendment-log entry.
- `apps/web-platform/infra/inngest.tf` — one-line comment cross-referencing `0002` near the existing `INNGEST_POSTGRES_URI` out-of-band paragraph (documentation only).

(CODEOWNERS already covers `/apps/web-platform/infra/inngest-rls/` + `apply-inngest-rls.yml`, lines 123–124 — no edit needed.)

---

## Setup SQL (the idempotent event-trigger artifact)

```sql
-- apps/web-platform/infra/inngest-rls/0002_rls_self_heal_event_trigger.sql
-- Layer-3 self-heal for soleur-inngest-prd (pigsfuxruiopinouvjwy): a ddl_command_end event
-- trigger that auto-ENABLEs ROW LEVEL SECURITY on every NEW public table the instant Inngest's
-- goose migrations CREATE it — closing the up-to-24h advisor-recurrence window that the daily
-- self-heal cron (0001 re-apply) otherwise leaves open.
--
-- ADDITIVE, not a replacement. 0001 already (a) backfills RLS on all existing public tables,
-- (b) REVOKEs anon/authenticated, and (c) ALTER DEFAULT PRIVILEGES ... REVOKE so a NEW
-- postgres-created table never gets an anon grant — the ACTUAL anon-reachability is already closed
-- at creation. The only residual is the COSMETIC advisor lint rls_disabled_in_public (fires while
-- relrowsecurity=false, ≤24h until the cron flips it). This trigger flips it on SYNCHRONOUSLY at
-- CREATE TABLE, so the critical advisor genuinely cannot recur.
--
-- FEASIBILITY (verified live 2026-06-30): role postgres (is_superuser=off) CAN create event
-- triggers via the Supabase Management API database/query path (the apply workflow's path).
--
-- SAFETY — MUST NOT break Inngest upgrades: ddl_command_end fires INSIDE the CREATE TABLE txn, so
-- any exception this function raises would ROLL BACK Inngest's goose migration. The body is
-- EXCEPTION-SAFE: every action is wrapped; a failure RAISE WARNINGs and is swallowed, NEVER
-- propagated. The daily cron remains the backstop. Deny-all only: NEVER creates a policy, NEVER
-- re-grants anon/authenticated, NEVER revokes from postgres/service_role.

SET lock_timeout = '3s';
SET statement_timeout = '30s';

-- Fail-closed Inngest-identity preflight (same guard as 0001): refuse to install on a non-Inngest project.
DO $$
BEGIN
  IF to_regclass('public.goose_db_version') IS NULL
     OR to_regclass('public.function_runs') IS NULL THEN
    RAISE EXCEPTION 'ABORT: Inngest sentinel tables absent — refusing to install RLS self-heal on a non-Inngest project';
  END IF;
END $$;

-- SECURITY DEFINER, owned by postgres, search_path pinned public,pg_temp (public FIRST) per
-- cq-pg-security-definer-search-path-pin-pg-temp. object_identity is already schema-qualified.
CREATE OR REPLACE FUNCTION public.inngest_rls_self_heal()
  RETURNS event_trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  obj record;
BEGIN
  FOR obj IN
    -- object_type='table' is the LOAD-BEARING filter (security + data-integrity): it (a) isolates
    -- the base relation from the sequence/index rows a single CREATE TABLE also emits, and (b)
    -- guarantees object_identity is canonically schema-qualified + quoted, which is the sole reason
    -- format('… %s …', object_identity) (NOT %I) is injection-safe. ANY future widening of the
    -- object_type set MUST re-examine this quoting assumption. (No command_tag filter here — the
    -- WHEN TAG clause on the trigger already gates which tags fire; all three emit object_type='table'.)
    SELECT object_identity
    FROM pg_event_trigger_ddl_commands()
    WHERE object_type = 'table'
      AND schema_name = 'public'
  LOOP
    BEGIN
      -- Idempotent; NOT forced (owner bypass preserved). object_identity = public.<table>, already quoted.
      EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY;', obj.object_identity);
      -- Defense-in-depth: strip any anon/authenticated grant (0001's default-priv revoke already
      -- prevents one, but a belt-and-suspenders REVOKE costs nothing and survives a default-priv regression).
      EXECUTE format('REVOKE ALL ON %s FROM anon, authenticated;', obj.object_identity);
    EXCEPTION WHEN OTHERS THEN
      -- NEVER propagate — propagating would abort Inngest's CREATE TABLE migration.
      RAISE WARNING 'inngest_rls_self_heal: could not lock down % (sqlstate=%, msg=%); daily cron will backstop.',
        obj.object_identity, SQLSTATE, SQLERRM;
    END;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'inngest_rls_self_heal: outer failure (sqlstate=%, msg=%); daily cron will backstop.', SQLSTATE, SQLERRM;
END;
$fn$;

-- Defensive: the event-trigger machinery invokes the function regardless of EXECUTE grant; revoke PUBLIC.
REVOKE ALL ON FUNCTION public.inngest_rls_self_heal() FROM PUBLIC, anon, authenticated;

-- Idempotent (re)install. WHEN TAG gates firing to the three relkind-'table'-emitting CREATE forms
-- (CREATE TABLE AS / SELECT INTO included so the non-recurrence guarantee is COMPLETE, not just
-- plain CREATE TABLE — they all surface object_type='table' through the loop above). RECURSION
-- GUARD: the function's own ALTER/REVOKE carry OTHER command tags, so they can never re-fire this
-- trigger — the WHEN TAG filter is the load-bearing guard (do NOT rely on any "PG disables event
-- triggers in-function" behavior; PG does fire them — e.g. the 6 Supabase pgrst_* triggers see the
-- ALTER harmlessly). If a future edit ADDS a tag here, recheck that no internal statement matches it.
DROP EVENT TRIGGER IF EXISTS inngest_rls_self_heal_trg;
CREATE EVENT TRIGGER inngest_rls_self_heal_trg
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION public.inngest_rls_self_heal();

-- ============================================================================================
-- BREAK-GLASS (incident response only). If this trigger is ever suspected of interfering with an
-- Inngest goose migration, DISABLE it (keeps the function + daily cron intact):
--     ALTER EVENT TRIGGER inngest_rls_self_heal_trg DISABLE;   -- sets evtenabled='D'
-- The apply workflow's gate treats evtenabled='D' as a WARN (NOT a failure), so a break-glass
-- disable does NOT file a daily P1 issue. To remove entirely instead:
--     DROP EVENT TRIGGER IF EXISTS inngest_rls_self_heal_trg;  -- this DOES trip trg_exists=0 → gate FAILS
-- The daily self-heal cron (0001 re-apply) remains the backstop for new-table RLS either way.
-- ============================================================================================
```

> **Idempotency:** `CREATE OR REPLACE FUNCTION` + `DROP EVENT TRIGGER IF EXISTS` then `CREATE` makes the whole file safe to re-apply on every merge and daily schedule. **Recursion (corrected per review):** the load-bearing guard is the `WHEN TAG` filter — the function's own `ALTER`/`REVOKE` carry tags outside the list, so they never re-fire this trigger. Do NOT rely on any "PG disables event triggers in-function" behavior (PG *does* fire them; the claim is false and was removed). **Coverage:** the three `WHEN TAG` values catch every relkind-`table` DDL Inngest can emit (incl. CTAS / `SELECT INTO`); only a `pg_restore`-style bulk reload (no per-table `ddl_command_end`) bypasses it — covered by the default-priv revoke + daily cron backstop. **Multi-row CREATE:** a single `CREATE TABLE` with a serial/PK emits multiple `pg_event_trigger_ddl_commands()` rows (table + sequence + index); `object_type='table'` isolates the base relation, and the spawned sequence is covered by `0001`'s default-priv revoke (sequences can't carry RLS). **`SET lock_timeout/statement_timeout`** at the top bind the INSTALL session (the Management-API POST) only — NOT trigger execution during Inngest migrations; that's fine because the just-created table is locked by Inngest's own txn and invisible to other sessions (no lock wait is possible).

---

## Verification (PR-body evidence)

1. **Before:** `get_advisors(security)` → 0 × `rls_disabled_in_public` (14 × `rls_enabled_no_policy` INFO); `pg_event_trigger` has no `inngest_rls_self_heal_trg`.
2. **Authoritative gate (extended, every run):** `violations = 0` (parent gate) **AND** `trg_exists = 1 AND fn_ok = 1` (new; WARN-not-fail when `trg_enabled = 0` from a break-glass DISABLE). Job fails loud otherwise.
3. **Live simulation (the task's acceptance — push/dispatch run):** `create table public._rls_selfheal_probe(id int)` → assert `relrowsecurity = true` **immediately** (proves synchronous enable) AND `has_table_privilege('anon', …, 'SELECT') = false` → `drop table`. Then `get_advisors(security)` shows **no** `rls_disabled_in_public` introduced.
4. **Non-breaking:** `scheduled-inngest-health.yml` probe green post-apply; the parent's owner-liveness + anon-deny checks still pass.
5. **Discoverability (no SSH):** `curl -s -H "Authorization: Bearer $PAT" https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/advisors/security | jq '[.lints[]|select(.name=="rls_disabled_in_public")]|length'` → `0`.

---

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `0002_rls_self_heal_event_trigger.sql` exists and contains: the fail-closed Inngest-sentinel preflight; `CREATE OR REPLACE FUNCTION public.inngest_rls_self_heal()` with `RETURNS event_trigger`, `SECURITY DEFINER`, `SET search_path = public, pg_temp`; an `EXCEPTION WHEN OTHERS` + `RAISE WARNING` exception-safe body; `WHEN TAG IN ('CREATE TABLE')` + `schema_name = 'public'` scoping; `ENABLE ROW LEVEL SECURITY`; idempotent `DROP EVENT TRIGGER IF EXISTS` + `CREATE EVENT TRIGGER`; a break-glass comment; and **no** `FORCE ROW LEVEL SECURITY`, **no** `CREATE POLICY`, **no** `REVOKE` of `postgres`/`service_role` (all asserted by `inngest-rls.test.sh`; `bash apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` exits 0).
- [ ] `apply-inngest-rls.yml` applies `0*.sql` in sorted order (0001 before 0002), retains all anti-exfil parity, extends the authoritative gate with `trg_exists=1 AND fn_ok=1` (WARN-not-fail on break-glass `trg_enabled=0`), and adds the residue-guarded push/dispatch-only live trigger self-test; new failure modes wired to the issue-filing branch.
- [ ] `actionlint` passes on the edited workflow; embedded `run:` shell passes `bash -c`.
- [ ] ADR-030 gets the I8 extension / I9 + amendment-log entry; "no C4 structural change" cited with the external-actor/system/relationship enumeration.
- [ ] PR body carries the live "before" evidence (advisor=0, no trigger) + the feasibility-probe result, and uses `Ref #<tracking-issue>` (not `Closes`).

### Post-merge (automated by the apply workflow; no manual step)
- [ ] Extended authoritative gate green: `violations = 0` AND `trg_exists = 1` AND `fn_ok = 1` (captured; `trg_enabled = 1` on a normal run).
- [ ] Live trigger self-test on the push run: throwaway `public._rls_selfheal_probe` had `relrowsecurity = true` and `anon SELECT = false` at creation, then dropped (captured).
- [ ] `get_advisors(security)` → still **0** `rls_disabled_in_public` (no regression; INFO `rls_enabled_no_policy` expected).
- [ ] `scheduled-inngest-health.yml` probe green (no durable-run regression).
- [ ] First daily `schedule:` run is a clean no-op (re-apply idempotent; gate green).
- [ ] `gh issue close <tracking-issue>` after the gate + self-test are green.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO). Product = NONE (no `components/**`, no `app/**/page.tsx` — no user-facing surface). Carried forward from the parent lockdown plan + ADR-030; assessed inline (deepen-plan + review will deepen via data-integrity-guardian + security-sentinel + architecture-strategist).

### Engineering (CTO)
**Status:** assessed (inline).
**Assessment:** Pure DDL/DCL on a dedicated backing store; layered cleanly on the shipped lockdown. The one new risk is the event trigger aborting an Inngest goose migration — fully mitigated by the exception-safe body (never propagates) + the cron backstop + a break-glass disable. Feasibility (postgres can create event triggers via the Management API) is empirically confirmed, not assumed. Scope is tight (`CREATE TABLE` + `public` only), idempotent, zero recurring cost (passive trigger). Cross-project blast radius zero (web-platform untouched; fail-closed identity preflight).

### Legal (CLO)
**Status:** assessed (inline). See **GDPR / Compliance Note (Phase 2.7)** above — not repeated here. Summary: no new processing / data movement / sub-processor; strictly reduces the exposure window on an already-analyzed surface; the parent's `reachability-only, no notifiable breach` determination stands; no Article 30 amendment.

### Product/UX Gate
Not applicable — no UI surface. Tier: NONE.

**CPO sign-off:** required at plan time (threshold = single-user incident). **Two items to ack before `/work` begins:** (1) the **primary-mechanism choice** surfaced by the simplicity + architecture reviewers — event-trigger (advisor window→0, + a migration-abort failure mode mitigated by exception-safety) vs the cheaper cron-to-hourly (window ≤1h, zero new risk); the plan keeps the event trigger primary per the task's explicit preference, but CPO confirms or redirects. (2) the residual availability risk itself (trigger-vs-Inngest-migration), accepting the exception-safety + cron-backstop mitigation.

---

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Not Terraform (no Supabase provider declared; `inngest.tf:212-217` documents why the out-of-band Inngest project is not in TF). The IaC here is the **versioned SQL artifact + the existing merge-triggered + daily apply workflow** — identical pattern to the parent lockdown. **No SSH, no `psql` by hand, no dashboard clicks** (`hr-all-infrastructure-provisioning-servers`, `hr-no-ssh-fallback-in-runbooks`).

### Terraform changes
None. No new `.tf` resource, provider, or variable.

### Apply path
`apply-inngest-rls.yml` (existing) — `push:` (paths `inngest-rls/**`) applies `0001`+`0002` on merge; `schedule:` (daily) re-applies idempotently as the backstop; `workflow_dispatch:` for manual re-run. The merge IS the human authorization (CODEOWNERS + branch protection; the four sibling apply workflows dropped the `environment:` reviewer gate per #4220). Blast radius: metadata-only DDL, `lock_timeout='3s'` fail-fast + retry; the event trigger install is `CREATE OR REPLACE`/`DROP IF EXISTS` (no rewrite).

### Secrets / auth
Reuses the existing `SUPABASE_ACCESS_TOKEN` (published from Doppler `prd_terraform`). **No new secret, no new vendor, no mint.** Anti-exfil parity with `scheduled-inngest-health.yml` preserved.

### Distinctness / drift safeguards
(1) Workflow hard-codes ref `pigsfuxruiopinouvjwy`; (2) **both** SQL files run a fail-closed Inngest-sentinel preflight (`RAISE EXCEPTION` unless `goose_db_version` + `function_runs` exist) before any DDL; (3) the artifact lives under `infra/inngest-rls/`, never `supabase/migrations/`, so the web-platform migration runner can never pick it up.

### Vendor-tier reality check
N/A — no provider tier gate; Supabase Management API `database/query` is available on the existing plan and already used by the parent workflow.

---

## Observability

```yaml
liveness_signal:
  what: extended authoritative gate in apply-inngest-rls.yml — violations=0 AND trg_present=1 AND fn_ok=1; advisor count corroborating
  cadence: on every merge touching infra/inngest-rls/** AND daily via schedule: (catalog-only re-verify); live trigger self-test on push/dispatch
  alert_target: GitHub Actions job failure → [ci/inngest-rls] tracking issue (filed/commented only when a run does NOT verify clean)
  configured_in: .github/workflows/apply-inngest-rls.yml
error_reporting:
  destination: GitHub Actions run logs (job fails loud); scheduled-inngest-health.yml covers connection-breakage regression
  fail_loud: true  # gate violation OR SQL error OR trigger inert/missing OR fn misconfigured => job fails, no silent pass
failure_modes:
  - mode: event trigger row missing post-apply (dropped = regression)
    detection: authoritative gate trg_exists!=1
    alert_route: GH Actions failure → tracking issue (selfheal_trigger_missing)
  - mode: event trigger intentionally break-glass-disabled (evtenabled='D')
    detection: authoritative gate trg_exists=1 AND trg_enabled=0
    alert_route: non-failing WARNING only (NOT a daily P1 issue — break-glass is deliberate)
  - mode: function not SECURITY DEFINER / search_path unpinned
    detection: authoritative gate fn_ok!=1
    alert_route: GH Actions failure → tracking issue (selfheal_fn_misconfigured)
  - mode: trigger present but inert (does not enable RLS on a new table)
    detection: live trigger self-test (throwaway table relrowsecurity!=true) on push/dispatch
    alert_route: GH Actions failure → tracking issue (selfheal_trigger_inert)
  - mode: trigger aborts an Inngest goose migration (the brand-survival case)
    detection: scheduled-inngest-health.yml probe (15-min) red + Inngest upgrade failure
    alert_route: existing inngest watchdog (auto-restart + P1 issue); break-glass DISABLE in 0002 comment
  - mode: new Inngest-version table still appears as rls_disabled_in_public (trigger bypassed, e.g. CREATE TABLE AS)
    detection: daily authoritative gate violations>0 (cron backstop catches within 24h)
    alert_route: GH Actions failure → tracking issue
logs:
  where: GitHub Actions run logs (apply workflow); RAISE WARNING surfaces in Postgres logs (Better Stack/Vector inngest sink) for any swallowed per-table failure
  retention: GH Actions default; Better Stack per plan
discoverability_test:
  command: 'curl -s -H "Authorization: Bearer $PAT" https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/advisors/security | jq "[.lints[]|select(.name==\"rls_disabled_in_public\")]|length"'
  expected_output: "0 (stays 0 across Inngest upgrades once the trigger is installed). No SSH."
```

---

## Architecture Decision (ADR/C4)

This **tightens the timing of an existing access boundary** on an existing substrate (it does not change the architecture), so it **amends ADR-030** — it does NOT create a new ADR and is NOT a deferred follow-up.

### ADR
In `ADR-030-inngest-as-durable-trigger-layer.md`, **add invariant I9** (do NOT fold into I8 — I8 is a *state-posture* invariant; I9 is a *distinct DDL-time-enforcement* guarantee with its own artifacts; this matches the I7-sibling-to-I4 precedent), plus a dated `## Updates / amendment log` entry (NOT prose appended to `## Decision`). **Framing correction (architecture review):** the `## Load-bearing invariants` banner reads "violation = brand-survival regression." Advisor-non-recurrence is NOT brand-survival (a missing trigger reverts to the cron-covered cosmetic window); the **exception-safety constraint IS** (an unswallowed raise aborts an Inngest migration). So I9 carries the brand-survival weight on exception-safety, with advisor-non-recurrence as defense-in-depth:
> **I9 — RLS self-heal at DDL time (advisor-non-recurrence; defense-in-depth over I8).** A `SECURITY DEFINER` event trigger `inngest_rls_self_heal_trg` (`ON ddl_command_end WHEN TAG IN ('CREATE TABLE','CREATE TABLE AS','SELECT INTO')`; function `SET search_path = public, pg_temp`) auto-`ENABLE`s RLS (not forced) + revokes anon/authenticated on every new `public` table at creation, so `rls_disabled_in_public` cannot recur across Inngest upgrades. **BRAND-SURVIVAL constraint (this is the load-bearing half):** the function MUST be exception-safe — it executes inside Inngest's `CREATE TABLE` transaction, so it must NEVER raise/propagate (failures `RAISE WARNING` only) or it would abort an Inngest goose migration. Injection-safety rests on `object_type='table'` (canonical `object_identity` quoting → `%s` is safe); recursion-safety rests on the `WHEN TAG` filter. The daily cron is the functional backstop. **Enforced by** `0002_rls_self_heal_event_trigger.sql` + `inngest-rls.test.sh` (no FORCE / no CREATE POLICY / no postgres-service_role revoke / exception-safe shape) + the workflow's `trg_exists=1 AND fn_ok=1` gate (WARN-not-fail on break-glass DISABLE) + the push/dispatch live self-test.

### C4 views
**No C4 structural change.** Enumeration per the completeness mandate (read against `model.c4`/`views.c4`/`spec.c4`): external human actors — none new; external systems/vendors — none new (the Supabase Management API ops edge already exists); containers/data-stores — `inngestPostgres` already modeled (`model.c4:155-157`, edge `:245`, rendered in `views.c4`) and INTERNAL; access relationships — the `inngest → inngestPostgres` owner edge is unchanged (anon was never a modeled edge; the event trigger is an internal DB mechanism, not a new actor/edge). The only optional touch is refreshing the `inngestPostgres` *description* to note "RLS self-heals on new tables via a ddl_command_end trigger" — if touched, run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` AND `bash scripts/regenerate-c4-model.sh` (commit `model.likec4.json` in the same commit, per the parent PR's session-error learning).

---

## Risks & Sharp Edges

- **An event trigger that raises aborts Inngest's `CREATE TABLE` migration (brand-survival).** `ddl_command_end` runs inside the DDL txn. The function MUST be exception-safe — inner `BEGIN…EXCEPTION WHEN OTHERS…RAISE WARNING…END` per table AND an outer guard. Asserted by the test (`EXCEPTION WHEN OTHERS` + `RAISE WARNING` present). The cron is the backstop; break-glass `DISABLE` is documented.
- **`CREATE EVENT TRIGGER` is normally superuser-only.** Confirmed feasible here via the Management API path (live probe), but `is_superuser=off` — re-run the Phase 0.2 probe at `/work`; if it ever FAILs, HALT and fall back to the cron-cadence alternative. Do not assume.
- **Scope creep / firing cost.** `WHEN TAG IN ('CREATE TABLE')` + `object_type='table'` + `schema_name='public'` keeps it minimal and coexisting with the 6 Supabase-owned `ddl_command_end` triggers. `CREATE TABLE AS` / `SELECT INTO` carry a different tag and are NOT caught — covered by default-priv revoke + cron; documented, not a gap.
- **`object_identity` is already schema-qualified + quoted** — use `format('… %s …', object_identity)` (NOT `%I`, which double-quotes). The search_path pin (`public, pg_temp`) + the explicit `public.`-qualified identity satisfy `cq-pg-security-definer-search-path-pin-pg-temp`.
- **Right-sizing (DHH/simplicity challenge, pre-empted).** This does NOT close a data hole (the default-priv revoke already did). Its value is eliminating the ≤24h cosmetic-advisor window that "surfaced twice" + passive defense-in-depth. The daily cron is retained as the backstop, not replaced. If CPO judges the ≤24h cron window acceptable, the cheaper alternative (tighten cron to hourly) is viable — see Alternatives.
- **Daily prod-write noise.** The live trigger self-test creates+drops a throwaway table; restricted to push/`workflow_dispatch` (not the daily schedule) to avoid a daily prod write. The daily run asserts presence catalog-only.
- **Two-file apply ordering.** The workflow must apply `0001` before `0002` (sorted glob). `0002`'s preflight is independent, but keeping order deterministic avoids surprise.
- **Break-glass DISABLE vs. the daily gate (data-integrity review).** A naive gate counting "present" only when `evtenabled in ('O','R','A')` would re-file a daily P1 issue throughout any break-glass-disable incident. Resolved: the gate FAILs only on `trg_exists=0` (dropped) or `fn_ok=0` (misconfigured), and WARNs (no issue) on `trg_exists=1 AND trg_enabled=0` (intentional disable). The SQL break-glass comment documents which path trips the gate.
- **`object_type='table'` is the injection-safety invariant (security review).** It is the sole reason `format('… %s …', object_identity)` is safe (`object_identity` is canonically quoted only for that object class). Any future widening of the `WHERE object_type`/`WHEN TAG` scope to other object classes MUST re-examine quoting (switch to `%I` on a bare name, or re-verify). Encoded as a test-guard rationale + ADR I9 note.
- **Daily functional correctness relies on the cron backstop (architecture review).** The catalog gate proves the trigger is *installed + configured*, not that it *fires correctly*; the live self-test runs only on push/dispatch. A silently-inert trigger is caught only by the daily `violations>0` gate when a real table appears (≤24h). Acceptable — the violations gate is a genuine backstop — but stated plainly, not implied as continuous functional verification.
- **Partial two-file apply (data-integrity review).** `0001` and `0002` are POSTed as separate `database/query` calls; if `0001` succeeds and `0002` fails mid-run, the apply is partial. Acceptable because both files are idempotent and the daily cron + extended gate re-converge on the next run; the gate fails loud on the partial state until `0002` lands.
- **Never `FORCE`, never `CREATE POLICY`, never revoke `postgres`/`service_role`** — same invariants as `0001`; reused test guards.

---

## Open Code-Review Overlap

None — no open `code-review` issue touches `apps/web-platform/infra/inngest-rls/**`, `apply-inngest-rls.yml`, or `ADR-030`. (Re-run the overlap query at `/work` once the tracking-issue number is known.)

---

## Alternative Approaches Considered

| Approach | Why not chosen (as primary) |
|---|---|
| **Event trigger (chosen, pending CPO confirm)** | Only approach that makes the advisor truly non-recurring (synchronous enable at CREATE TABLE, all per-table DDL tags); feasible; passive. Risk (migration abort) mitigated by exception-safety + cron backstop. **Both simplicity + architecture reviewers flag the trade as asymmetric** (brand-survival-path failure mode for a cosmetic gain) → primary-mechanism choice routed to the `requires_cpo_signoff` gate (see Enhancement Summary). |
| Rely on the existing daily cron only | Already shipped; leaves a ≤24h cosmetic-advisor window — the exact recurrence the task targets ("surfaced twice"). Kept as the **backstop**, not the primary. |
| Advisor acknowledgement / suppression for a known-accepted finding | Not available — the Supabase Management API `advisors/security` endpoint is **read-only / recomputed**; it exposes no durable per-finding ack/ignore primitive for `rls_disabled_in_public`. So the noise can only be silenced by actually keeping `relrowsecurity=true` (what this plan + the cron do), not by suppressing the lint. Recorded to answer the "window-0 vs cosmetic" simplicity challenge on the record. |
| Tighten the cron to hourly/6-hourly | One-line change, no migration-abort risk, but still leaves a ≤1h/6h window + burns Actions minutes. Viable fallback if CPO deems the event trigger's availability risk not worth the window elimination, or if the Phase 0.2 feasibility probe ever FAILs. |
| Hook the apply into the Inngest deploy/restart workflow | Deterministic at deploy time, no superuser primitive — but misses tables Inngest creates lazily at runtime (not only at deploy). Weaker coverage than a DDL-time trigger. |
| Add permissive RLS policies | Explicitly forbidden — these tables must never be client-reachable; deny-all is intentional. |
| `FORCE ROW LEVEL SECURITY` | Breaks Inngest (removes owner bypass). |
| Put SQL in `supabase/migrations/NNN_*.sql` | Targets the WRONG project (web-platform), not `pigsfuxruiopinouvjwy`. |

---

## GitHub Tracking Issue

**Opened: [#5809](https://github.com/jikig-ai/soleur/issues/5809)** (labels `domain/engineering` + `priority/p2-medium`; milestone `Post-MVP / Later`) — *"security: durable RLS self-heal on soleur-inngest-prd via ddl_command_end event trigger"*. Summarizes the residual ≤24h advisor-recurrence window, the event-trigger approach + feasibility-confirmed note, and the exception-safety constraint. **PR body MUST use `Ref #5809`** (NOT `Closes` — ops-remediation completes post-merge when `apply-inngest-rls.yml` runs); close #5809 after the post-merge gate + live self-test are green.
