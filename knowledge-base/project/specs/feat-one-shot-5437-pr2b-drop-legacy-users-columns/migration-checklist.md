# Migration 112 — Dev apply + verification checklist

**Migration:** `112_drop_legacy_users_repo_columns.sql` (ADR-044 PR-2b, #5437)
**Applied to:** DEV Supabase (`soleur` Doppler config `dev`, project ref `mlwiodleouzwniehynfz`)
**Date:** 2026-06-18
**Apply method:** node-pg, mirroring `run-migrations.sh:336-343` — migration body +
`INSERT INTO public._schema_migrations (filename, content_sha)` in ONE transaction
(`BEGIN`/`COMMIT` == the runner's `psql --single-transaction`). Session-mode pooler
(`:5432`), read/write, `ALLOW_UNMERGED_DEV_APPLY=1` ack (unmerged-dev-apply gate,
learning 2026-05-21).

## Pre-apply safety gates (HARD BLOCK — both clean)

- **Drift gate COUNT=0 against PROD** (read-only, `DATABASE_URL_POOLER`):
  `repo_url_drift=0, install_drift=0, total_drift=0`.
  Context: users_total=16, workspaces_total=18, users_with_repo_url=4,
  users_with_install=2, ws_with_repo_url=5, ws_with_install=3. GATE: PASS.
- **Reader sweep = 0 live readers** on `origin/main` (fetched 2026-06-18):
  multi-line `from("users")…(3 cols)` + dual-shape `.eq/.in/.match` sweeps over
  `apps/web-platform/{app,server,lib}` — every hit classified as comment /
  different-column select (`email`, `health_snapshot`, `github_username`,
  `workspace_status`) / `workspaces`|`conversations` query / synthesized object.
- **Collision check:** 110 is max migration number on `origin/main` and locally;
  `112_drop_legacy_users_repo_columns.sql` is free.

## Apply result

- **content_sha (git hash-object):** `259b8c87214a021c97064be59be5d0694cb6ae3b`
- **Tracking row written:** YES — `112_drop_legacy_users_repo_columns.sql` now in
  `public._schema_migrations` on dev, committed in the same txn as the DDL.
- **Apply status:** `APPLIED 112 + tracking row committed in one transaction.`

## Post-apply verification

### AC10 — verify/112 (psql-equivalent, run-verify.sh shape) — PASS

| check_name | bad |
|---|---|
| users_github_installation_id_present | 0 |
| users_repo_url_present | 0 |
| users_workspace_path_present | 0 |
| users_github_installation_id_unique_idx_present | 0 |

All `bad=0` → run-verify.sh would report green.

### AC9 — REST discoverability probe (dev, expect HTTP 400 / 42703) — PASS

| column | HTTP | body |
|---|---|---|
| github_installation_id | 400 | `{"code":"42703",…"column users.github_installation_id does not exist"}` |
| repo_url | 400 | `{"code":"42703",…"column users.repo_url does not exist"}` |
| workspace_path | 400 | `{"code":"42703",…"column users.workspace_path does not exist"}` |

All three dropped columns are GONE on dev; PostgREST schema cache already reflects
the drop (no PGRST205 staleness window observed).

## Migration-number collision → renumbered 111 → 112

At plan/work-start, 110 was the highest migration on `origin/main` and 111 was free,
so this drop was authored + dev-applied as `111_drop_legacy_users_repo_columns.sql`.
While work was in flight, a sibling PR merged `111_email_triage_items_workspace_shared.sql`
to `origin/main` (the PR #4225 collision class). To avoid two `111_` files on `main`,
this migration was renumbered `111 → 112` (`git mv` of the up/down/verify files +
every textual reference). `112` is free on `origin/main` (highest is now the sibling's
`111`). The dev `_schema_migrations` ledger row was reconciled from
`111_drop_legacy_users_repo_columns.sql` → `112_drop_legacy_users_repo_columns.sql`
with the recomputed `content_sha`; the up-migration is idempotent (`DROP COLUMN IF
EXISTS`), so even an un-reconciled re-apply on dev would be a no-op.

## P1 review-blocker fix — `handle_new_user()` still wrote `users.workspace_path` (2026-06-18)

Two review agents (data-migration-expert + data-integrity-guardian) flagged a 100%
new-signup outage: the live `handle_new_user()` SECURITY DEFINER trigger (AFTER INSERT
on `auth.users`, defined in mig 091:136-191) still ran
`INSERT INTO public.users (id, email, workspace_path) …`. Post-drop, the next signup
would throw `42703 column "workspace_path" does not exist`.

**Fix (migration files):**
- `112_…up.sql`: prepended a `CREATE OR REPLACE FUNCTION public.handle_new_user()`
  block BEFORE the `DROP INDEX`/`DROP COLUMN` (defensive ordering — function becomes
  `workspace_path`-free in the same `--single-transaction` before the column vanishes).
  Body verbatim from mig 091 EXCEPT `INSERT … (id, email, workspace_path) VALUES (NEW.id,
  NEW.email, '/workspaces/'||NEW.id::text)` → `INSERT … (id, email) VALUES (NEW.id,
  NEW.email)`. `SECURITY DEFINER` + `SET search_path = public, pg_temp` + REVOKE + COMMENT
  re-issued verbatim (the 091 COMMENT never names `workspace_path`, so kept as-is).
- `112_…down.sql`: appended a `CREATE OR REPLACE FUNCTION` that RESTORES the mig-091 body
  VERBATIM (with the `workspace_path` write) AFTER the `ADD COLUMN`/`CREATE INDEX` —
  function and column stay in lockstep on rollback.
- `verify/112_…sql`: added a 5th `UNION ALL` branch `handle_new_user_no_workspace_path`
  asserting `pg_get_functiondef('public.handle_new_user()'::regprocedure)` does NOT
  `ILIKE '%workspace_path%'` (integer `bad`, uniform with the other branches).

**Dev re-apply (Doppler `soleur`/`dev`, `DATABASE_URL_POOLER` session-mode `:5432`,
`ALLOW_UNMERGED_DEV_APPLY=1`):** ran the `workspace_path`-free `CREATE OR REPLACE
FUNCTION` + REVOKE against dev (signup was broken there since the prior column drop).
`pg_get_functiondef(...) ILIKE '%workspace_path%'`: BEFORE=`true` → AFTER=`false`. Dev
signup is unblocked. The dev `_schema_migrations` `content_sha` for
`112_drop_legacy_users_repo_columns.sql` was re-synced (the up file changed — function
block added): `git hash-object` → `bbbb7e3f30aff6ee5ded176549d62e12b8771b26`.
