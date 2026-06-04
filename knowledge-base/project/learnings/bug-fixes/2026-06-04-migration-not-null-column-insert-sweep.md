---
title: "Large RLS/tenancy migrations: a NOT-NULL column added to existing tables MUST sweep every insert writer (silent 23502 otherwise)"
date: 2026-06-04
category: bug-fixes
tags: [supabase, migrations, workspace-id, write-boundary, no-ssh, 23502, misdiagnosis]
related_prs: [4913, 4922]
related_migrations: [059_workspace_keyed_rls_sweep]
related_rules: [hr-write-boundary-sentinel-sweep-all-write-sites, hr-no-dashboard-eyeball-pull-data-yourself, hr-no-ssh-fallback-in-runbooks]
related_learnings:
  - 2026-06-01-symptom-root-cause-trace-the-actual-redirect-not-the-plan-hypothesis
  - 2026-06-03-no-ssh-prod-signal-toolchain-never-hand-the-operator-an-ssh-task
---

## TL;DR

Migration `059_workspace_keyed_rls_sweep` added `workspace_id uuid NOT NULL` (no DB default) to ~13 existing tables and rewrote their RLS to be workspace-member-keyed — but it did **not** sweep every `.insert()/.upsert()` writer to set the new column. Result: **every** write to those tables failed in production with Postgres **23502 (not-null violation)**, surfacing as a silent 500. The "Generate link" button (`kb_share_links`), new push subscriptions (`push_subscriptions`), and the repo-setup sync conversation (`conversations`) were all silently broken. The broad sweep (PR #4922) found and fixed all three.

**This is the canonical example of why `hr-write-boundary-sentinel-sweep-all-write-sites` must explicitly cover the "migration adds a NOT-NULL column to an existing table" class — not just new sentinel/guard additions.**

## The failure mechanism

`ALTER TABLE t ADD COLUMN workspace_id uuid NOT NULL` (no default) means the DB rejects any INSERT that omits `workspace_id`. The app's writers were written before the column existed, so they still insert the old column set → 23502 → the route returns a 500 `db-error` → the client treats any non-ok as "reset to idle." No crash, no obvious error — just a dead button. Because the db-error path's `reportSilentFallback` had no alert wired to its rate, it sat latent until a founder hit it.

## The mandatory sweep (run during migration work AND at ship)

When a migration adds a NOT-NULL column with no default to an EXISTING table (or `ALTER COLUMN … SET NOT NULL` on a no-default column), you MUST verify every writer sets it. Do all four:

1. **Enumerate the impacted (table, column) set from the LIVE schema** (no SSH, no dashboard — `hr-no-dashboard-eyeball-pull-data-yourself`):
   ```sql
   SELECT table_name, column_name FROM information_schema.columns
   WHERE table_schema='public' AND is_nullable='NO' AND column_default IS NULL
     AND is_generated='NEVER' AND identity_generation IS NULL;
   ```
   via `doppler run -p soleur -c prd -- psql "$DATABASE_URL_POOLER" -tAq -c "…"`.

2. **Run the audit script** — `apps/web-platform/scripts/audit-not-null-column-insert-coverage.sh` (introspects the schema, greps every insert/upsert site, exits non-zero on a MISS). It catches inline `.from("t").insert({…})` omissions outright.

3. **Trace the helper-indirected writers by hand.** A pure grep CANNOT follow `const table = client.from("t"); … table.insert({…})` (the createShare blind spot — `from("kb_share_links")` and the `.insert()` were 130 lines apart). The script flags these as `REVIEW (helper-indirected)` lines; open each file and confirm the column is set.

4. **Reproduce one insert per table against `DATABASE_URL_POOLER` in a rollback tx** — the only way to be certain:
   ```js
   await c.query('BEGIN');
   try { await c.query(`INSERT INTO t (…old cols…) VALUES (…)`); console.log('MISSING-WS-OK?'); }
   catch(e){ console.log(e.code, e.message); }      // 23502 here == a broken writer
   finally { await c.query('ROLLBACK'); }
   ```
   `23502` without the column + success with it == confirmed bug + confirmed fix.

Tables written exclusively via SECURITY DEFINER RPCs that take `p_workspace_id` (e.g. `workspace_members`, `audit_byok_use`) are safe — the RPC sets it.

## Resolving the column value

For a workspace-keyed insert, resolve the workspace id via the canonical
`resolveCurrentWorkspaceId(userId, client)` (claim → solo fallback = `userId`).
Do **NOT** use `workspace_members…maybeSingle()` — it THROWS for a user who owns
>1 workspace (the founder owns 2), silently skipping the write or erroring.

## Two meta-lessons this incident also encodes

1. **Do not ship a fix on an unverified hypothesis.** The first attempt (PR #4913) blamed PR #3854's tenant-JWT mint from git archaeology and shipped a service-role fallback — without pulling the actual prod error. It did not fix the button. The real `23502` was one `DATABASE_URL_POOLER` insert-reproduction away. Trace the ACTUAL producer error before coding (see `2026-06-01-symptom-root-cause-trace-the-actual-redirect-not-the-plan-hypothesis`).

2. **The no-SSH prod toolchain finds this in minutes.** `SENTRY_IAC_AUTH_TOKEN` reads issues (the runtime `SENTRY_AUTH_TOKEN` is monitors-only → 403); `DATABASE_URL_POOLER` introspects the schema, replicates RLS reads under simulated `request.jwt.claims`, and reproduces inserts in rollback txns. The tenant-mint read was DISPROVEN by minting a real founder JWT via the GoTrue admin `generateLink + verifyOtp` path and replaying the exact read (it returned the row). See `2026-06-03-no-ssh-prod-signal-toolchain-never-hand-the-operator-an-ssh-task`.

## Prevention checklist (for the next big tenancy/RLS migration)

- [ ] For every `ADD COLUMN … NOT NULL` / `SET NOT NULL` (no default) on an existing table: run `audit-not-null-column-insert-coverage.sh` → zero MISS.
- [ ] Resolve every `REVIEW (helper-indirected)` file by hand.
- [ ] Reproduce one insert per impacted table against prd (rollback tx) → succeeds with the column.
- [ ] Wire (or confirm) an alert on the relevant `reportSilentFallback` / db-error rate so a constraint that breaks every insert pages, not sits latent.
