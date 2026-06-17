---
title: "A DROP COLUMN's pre-drop sweep must cover DB-side WRITERS (SECURITY DEFINER funcs / triggers), not just app-layer readers — a surviving signup-trigger writer = 100% new-signup outage"
date: 2026-06-18
category: security-issues
module: apps/web-platform
tags: [adr-044, drop-column, destructive-migration, handle_new_user, security-definer-trigger, reader-sweep, signup-outage, migration-collision]
issue: 5437
pr: 5508
---

# Learning: the destructive-DROP reader-sweep must include DB-side writers

## Problem

ADR-044 PR-2b dropped `users.{github_installation_id, repo_url, workspace_path}`. The
"0 live readers" safety gate had been run three times (the #5470/#5482/#5491 cutovers
+ this PR's work-start sweep) — but every sweep was scoped to **app-layer reads/filters
+ DB-side READERS**. None checked DB-side **WRITERS**.

The live `handle_new_user()` SECURITY DEFINER trigger (defined in mig 091, fired AFTER
INSERT on `auth.users`, wired by mig 001) still executed:
```sql
INSERT INTO public.users (id, email, workspace_path) VALUES (NEW.id, NEW.email, '/workspaces/'||NEW.id::text)
```
A `DROP COLUMN workspace_path` does NOT fail at apply time — PL/pgSQL function bodies
are late-bound (not parse-checked against the table until invoked). The failure is
deferred to the **next signup**, which throws `42703 column "workspace_path" does not
exist`, aborts the SECURITY DEFINER trigger, and therefore the entire `auth.users`
INSERT → **100% new-signup outage, irreversible** (the down restores schema, not data).

Every implementation-side check passed: `tsc` doesn't see SQL, the unit suite mocks
Supabase, and `verify/112` only asserted the columns were *gone* — none exercised the
signup trigger. The /work dev-apply even dropped the column on dev WITHOUT fixing the
trigger, so **dev signup was already silently broken** until two review agents
(data-migration-expert + data-integrity-guardian) independently caught it.

## Solution

**Before any `DROP COLUMN`, sweep DB-side writers AND readers of the column across all
live migration objects — not just app code.** The grep that finds app readers
(`from("users")…select`) and the grep that finds DB readers (`SELECT u.col`) both miss
a `CREATE OR REPLACE FUNCTION … INSERT INTO public.users (… col …)` trigger body. Run:
```
# writers in any function/trigger body (the missed class):
rg -nU 'INTO public\.<table>[\s\S]{0,300}?\b<col>\b|UPDATE public\.<table>[\s\S]{0,300}?\b<col>\b' apps/web-platform/supabase/migrations/
# then for each hit, confirm whether it is the LIVE definition (highest-numbered
# CREATE OR REPLACE wins) or a superseded/one-shot-backfill body.
```
The signup trigger `handle_new_user` is the highest-frequency writer of `users.*` — always check it explicitly when dropping a `users` column.

**The fix lives in the SAME migration, ordered before the drop:** `CREATE OR REPLACE
FUNCTION public.handle_new_user()` with the column removed from the INSERT (rest of the
body verbatim — preserve SECURITY DEFINER + `SET search_path` + REVOKE + COMMENT), THEN
the `DROP COLUMN`, all inside the one `--single-transaction`. The `.down.sql` must
`CREATE OR REPLACE` the OLD body (with the column write) in lockstep with re-adding the
column. Add a `verify/` sentinel asserting the live body is column-free:
`pg_get_functiondef('public.handle_new_user()'::regprocedure) NOT ILIKE '%<col>%'`.

## Key Insight

"0 live readers" is necessary but NOT sufficient to drop a column — a column has THREE
live surfaces: app reads, DB-function/trigger reads, and **DB-function/trigger writes**.
The writer surface is the deadliest (a signup-trigger writer is a total-signup outage)
and the most invisible (tsc, mocked unit tests, and column-presence verify all pass).
When dropping a `users.*` column, the FIRST thing to check is `handle_new_user`. Multi-
agent review earned its keep again: two orthogonal agents caught a guaranteed prod
outage that four green gates missed.

## Session Errors

1. **Migration-number collision (111→112).** Authored + dev-applied as `111`; a sibling
   `111_email_triage_items_workspace_shared.sql` merged to main DURING work (the
   work-start collision check passed when 111 was still free). Recovery: `git mv` the
   up/down/verify 111→112 + every textual reference, reconcile the dev `_schema_migrations`
   row (filename + content_sha). **Prevention:** re-run the `git ls-tree origin/main`
   migration-number collision check at SHIP time too, not only work-start — a long
   pipeline lets a sibling claim the number mid-flight (PR #4225 class).
2. **handle_new_user trigger writer missed by the reader-sweep → dev signup broke.** The
   /work dev-apply dropped `users.workspace_path` before the trigger was fixed, breaking
   dev signup silently. Recovery: `CREATE OR REPLACE` the trigger (workspace_path-free)
   in mig 112 before the drop + re-apply to dev. **Prevention:** this learning — sweep DB
   writers before a DROP; and a destructive DROP applied to dev should land the
   function-fix in the SAME apply, never column-drop-then-fix-later.
3. **TLS `rejectUnauthorized:false`** on the transient pooler drift-gate/reconcile
   scripts triggered a security-guidance hook warning. **Prevention:** sanctioned — the
   project documents this for transient, uncommitted node-pg verify scripts against the
   Supabase pooler's self-signed chain (mirrors `run-migrations.sh sslmode=require`); no
   committed code disables TLS verify. One-off, no action.

## Tags
category: security-issues
module: apps/web-platform
