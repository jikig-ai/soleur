---
title: "Account-delete anonymise failure — verified findings & resume notes"
status: diagnosis-complete-implementation-pending
regulated_surface: "GDPR Article 17 (Right to Erasure)"
requires_cpo_signoff: true
created: 2026-05-31
branch: feat-one-shot-account-delete-anonymise-action-sends
draft_pr: 4679
---

# Account-delete `anonymise-action-sends` failure — verified findings

Companion to `plan-feat-account-delete-anonymise-action-sends.md`. This file
records what was **verified against the live dev database** (not hypothesised),
so the next session resumes from solid ground instead of re-running diagnostics.

## 1. Root cause — REPRODUCED (not a hypothesis)

Run against **dev** Supabase (`hr-dev-prd-distinct-supabase-projects`), inside a
rolled-back transaction (no writes persisted):

```
current_user = postgres,  rolsuper = f,  rolbypassrls = f
anonymise_action_sends owner = postgres,  owner_is_superuser = f
BEGIN;
SET LOCAL session_replication_role = 'replica';
  → ERROR: permission denied to set parameter "session_replication_role"   (SQLSTATE 42501)
ROLLBACK;
```

`session_replication_role` is a superuser-only (PGC_SUSET) GUC. On managed
Supabase the migration/function-owner role `postgres` is **not** a superuser, so
every `SET LOCAL session_replication_role = 'replica'` throws `42501`. The
`anonymise_action_sends` RPC throws before its UPDATE; `account-delete.ts:268-290`
catches it, mirrors to Sentry (`op=anonymise-action-sends`), and returns the UI
string *"Account deletion failed at anonymise-action-sends. Please try again."*

This is exactly the plan's "Defect A", now **confirmed**. The two other draft
defects (NOT NULL, missing grant) remain correctly retracted.

**Regression-test assertion string:** `permission denied to set parameter "session_replication_role"` / SQLSTATE `42501`.

## 2. Blast radius — SYSTEMIC, ~14 functions (much larger than the plan scoped)

`account-delete.ts` runs the anonymise RPCs in cascade order; `anonymise-action-sends`
is merely the **first** to hit the GUC. A live `pg_proc` scan
(`pg_get_functiondef ILIKE '%session_replication_role%'`) returned **14**
public functions that `SET LOCAL session_replication_role` — every one is
latently broken on managed Supabase. Confirmed members include:

- Saga (fatal) RPCs: `anonymise_action_sends` (051), `anonymise_template_authorizations` (053),
  `anonymise_workspace_member_actions` (063), `anonymise_byok_delegation_acceptances` (074),
  `anonymise_byok_delegation_withdrawals` (084).
- Saga (non-fatal) RPC: `anonymise_audit_github_token_use` (052).
- pg_cron retention purges: `purge_expired_workspace_member_actions`, `prune_dsar_export_audit`, … (run as `postgres` → also broken/erroring silently).

NOTE: `anonymise_scope_grants` (050) is already structural-shape and NOT affected.
`anonymise_byok_delegations` (064) appeared to already be structural-shape on one
read but a later categorisation query disagreed — **re-confirm its current body
from the live DB before touching it** (see §4 reliability caveat).

Fixing only `action_sends` would just move the failure to the next saga step
(`anonymise-template-authorizations`), so the user still could not delete their
account. **The correct fix is saga-wide + purge-wide.**

## 3. Fix mechanism — custom `app.worm_bypass` GUC (learning-blessed)

Primary source `knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`
explicitly blesses BOTH structural-shape AND a custom transaction-local GUC, and
explicitly names `session_replication_role` as unusable on Supabase:

> A GUC set with `SET LOCAL app.x = '...'` inside the RPC and read with
> `current_setting('app.x', true)` in the trigger IS reliable (same transaction,
> same backend). … `session_replication_role = 'replica'` requires superuser …
> on managed Supabase the `postgres` role canNOT set it … Use structural-shape
> or a SET LOCAL app.* GUC.

What migration 048 abandoned was a `current_user='service_role'` **role check**,
NOT custom GUCs. The plan's claim that the GUC approach was "abandoned" is a
paraphrase error — corrected here against the primary source.

**Chosen mechanism: a custom `app.worm_bypass` sentinel GUC.** Reasons:
- Uniform across ~14 functions; no per-table column enumeration (structural-shape
  would need that × every affected table).
- The byok/workspace WORM triggers **already** read a GUC
  (`current_setting('session_replication_role') = 'replica'`) — swapping the GUC
  name is minimal and consistent with their existing shape.
- Avoids the risky `action_sends` `FOR EACH STATEMENT → FOR EACH ROW` change the
  structural-shape route would force.

### CRITICAL correctness caveat (do not miss this)
`session_replication_role='replica'` makes the Postgres **engine skip firing
triggers** — so pure-reject triggers (`action_sends_no_mutate`,
`template_authorizations_no_mutate`) currently work with **no GUC check in their
body**. A custom `app.worm_bypass` GUC does **NOT** make the engine skip
triggers. Therefore **every** WORM trigger on an affected table must be rewritten
to **explicitly** check `current_setting('app.worm_bypass', true) = 'on'` →
`RETURN COALESCE(NEW, OLD)`, else `RAISE`. A blind GUC-name swap is NOT
sufficient for the pure-reject triggers. This is table-by-table work.

### Migration shape (next free number = 087; 086 is highest; 065 is taken)
For each affected table, in ONE forward migration (`087_*.sql`) + paired `.down.sql`:
1. `CREATE OR REPLACE` the WORM trigger function to honor `app.worm_bypass`
   (swap the GUC name for byok/workspace triggers; **inject** the guard for the
   pure-reject action_sends/template_authorizations triggers).
2. `CREATE OR REPLACE` every one of the ~14 SET-site functions, replacing
   `SET LOCAL session_replication_role = 'replica';` with
   `SET LOCAL app.worm_bypass = 'on';` and dropping any
   `RESET session_replication_role;`. Keep auth checks, search_path pin, grants.
3. Do NOT add `DROP NOT NULL` or new EXECUTE grants (already present — retracted).

## 4. Why implementation was NOT completed this session (reliability)

The diagnostic work above is solid (assertion-based, reproduced live). The
**implementation** was deliberately stopped because this session's tool channel
became unreliable: repeated truncation of `psql`/Read output, and one
**contradictory** reading of the same function (`anonymise_byok_delegations`
showed no `session_replication_role` in its body on one read but was flagged as a
SET-site on another). Hand-writing a 14-function WORM-bypass migration on an
irreversible GDPR-erasure surface, validated through a channel returning
contradictory source, risks a silent WORM hole or a broken erasure path. That
trade is not acceptable on this surface.

## 5. Resume checklist (next session)
1. Re-pull authoritative bodies from dev: `pg_get_functiondef` for all 14 SET-site
   functions + `pg_get_triggerdef`/trigger fns for each affected table. Trust the
   live DB, not migration files (append-only history may be superseded).
2. Write `087_worm_bypass_app_guc.sql` + `.down.sql` per §3 (mind the §3 caveat).
3. **Validate transactionally on dev** (assertion-based, truncation-immune):
   `BEGIN; <apply all CREATE OR REPLACE + trigger recreates>; <call every anonymise
   RPC against synthetic rows>; <assert success>; <assert ordinary UPDATE/DELETE
   still raises P0001>; ROLLBACK;` — gate on row-count/exception assertions.
4. Add the migration-SQL guardrail test + extend `action-sends-worm.test.ts`.
5. Run `soleur:gdpr-gate` on the diff (`hr-gdpr-gate-on-regulated-data-surfaces`).
6. Run `soleur:preflight`. Then ship — PR requires **CPO sign-off**
   (`requires_cpo_signoff: true`) before merge.

## Status of draft PR #4679
Draft only. Contains the plan + this findings doc. No migration written yet.
