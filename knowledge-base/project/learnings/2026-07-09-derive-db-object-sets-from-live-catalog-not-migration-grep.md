# Learning: Derive DB-object sets from the live catalog, not by grepping migration source

**Date:** 2026-07-09
**Context:** Planning the RLS/authz-fuzz harness (#6256). The plan draft enumerated the
target tables by grepping migration 068. 4-agent plan-review (architecture-strategist +
spec-flow-analyzer) caught it as a P0 false-green vector.

## Problem

The plan asserted "26 `<table>_jti_not_denied` tables, derived by `git grep`, including the
beta-CRM PII tables." All three claims were wrong:
1. Migration 068 creates its policies in a `DO $$ … format('CREATE POLICY %I_jti_not_denied', t)`
   **dynamic loop** — the table-qualified literals **never appear in source**, so `git grep`
   returns only the 5 tables added later via literal `CREATE POLICY` (migs 076/077/126) plus a
   garbage `I_jti_not_denied` capture from the format string.
2. Mig 068's array is **21** tables, not 26 (the set reached 26 via later migrations); the
   beta-CRM tables are not in 068 at all.
3. The harness anchored on the **jti-deny** set (26 tables) when the tenant-isolation invariant
   lives in the wider **`is_workspace_member` PERMISSIVE** set (44 RLS tables). Anchoring on the
   narrower, wrong set would silently skip workspace-isolated tables (`email_triage_items`,
   `workspace_invitations`, `routine_runs`, …).

Any one of these ships a harness that passes while isolation is broken.

## Key Insight

**For any plan/test that operates over a *set* of DB objects (tables, policies, functions,
grants), derive the set from the live system catalog after migrations apply — never by
grepping migration source.**

- Dynamic DDL (`format('%I_…', x)` loops, `EXECUTE`, templated `CREATE POLICY/FUNCTION`) emits
  object names that exist **only in the catalog**, never as source literals. A source grep
  under-enumerates and fails closed (or, worse, silently under-covers).
- The catalog is authoritative, migration-location-independent, and self-tracking (new objects
  appear automatically): `SELECT tablename FROM pg_policies WHERE …`, `pg_proc`/`pg_get_functiondef`,
  `pg_class WHERE relrowsecurity`, `information_schema.role_table_grants`.
- **Anchor on the invariant, not a proxy layer.** A RESTRICTIVE add-on layer (jti-deny) is not
  the same set as the PERMISSIVE isolation layer (`is_workspace_member`). Enumerate the layer
  that *is* the invariant; treat the others as overlaid dimensions.

## Generalizable Pattern

When a plan enumerates DB objects:
1. Derive the set at runtime from the catalog (`pg_policies`/`pg_proc`/`pg_class`), post-migration.
2. Fail the check if any object matching the invariant predicate has no coverage (self-tracking).
3. Never `git grep` migration source for a set that any migration builds dynamically.
4. For a security invariant, enumerate the *enforcing* policy layer, not an additive one.

Corollary (also from this review): a "0 rows / error = denied" test is vacuous unless it first
seeds a target row (as `service_role`) and asserts the privileged role sees `count=1` — and it
must discriminate SQLSTATE `42501` (RLS denial) from constraint errors (23502/23503/23514/42703),
which are test *errors*, not passes.

## Session Errors
- **Plan-draft paraphrase error:** asserted mig 068 defines 26 tables (incl. beta-CRM) greppable
  from source. Recovery: architecture + spec-flow review; rewrote to catalog-driven derivation.
  **Prevention:** the "verify named repo artifacts against current state" plan Sharp Edge extends
  to *sets* built by dynamic DDL — read the catalog, not the migration.

## Tags
category: workflow-patterns
module: plan / postgres-rls-testing
related: knowledge-base/project/plans/2026-07-09-feat-rls-authz-fuzz-harness-plan.md, #6256
