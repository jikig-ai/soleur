---
title: "fix(ci): tenant-integration mig 062 fails on missing public.workspaces — schema-vs-ledger drift on dev"
issue: 4338
branch: feat-one-shot-mig062-workspaces-dep-4294
type: fix
lane: cross-domain
date: 2026-05-22
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): tenant-integration mig 062 fails on missing public.workspaces — schema-vs-ledger drift on dev

## Overview

Restore the `Tenant integration (dev-Supabase)` CI workflow to green by closing the schema-vs-ledger drift on dev-Supabase: `public._schema_migrations` records `053_organizations_and_workspace_members.sql`, `058_workspace_member_attestations.sql`, `059_workspace_keyed_rls_sweep.sql`, and `060_current_organization_jwt_hook.sql` as applied, but the schema state does not contain `public.workspaces` (verified at issue-file time via run `26280818623` — only `062` reached the `Applying:` line; 053-061 were skipped as already-applied; 062 then died with `ERROR: relation "public.workspaces" does not exist`).

The fix has four parts:

1. **Operator-paced (manual against dev-Supabase):** reconcile dev's `_schema_migrations` ledger with its actual schema state — either re-run 053/058/059/060 forward (re-create the workspace tables) OR delete the stale ledger rows so the runner re-applies them on the next CI run.
2. **Apply-time defense (automated code fix in `run-migrations.sh`):** before applying a migration, probe for the schema objects the next migration's body declares it depends on (best-effort, opt-in). When the dependency is missing AND the ledger claims it's applied, fail with a clear `::error::` that names the missing relation and links to this learning, instead of crashing inside the apply transaction.
3. **Code fix (062 idempotency hardening):** wrap the create/RLS/RPC body in a transaction-level fail-loud assertion that `public.workspaces` exists before touching it. Future migrations get the same shape via a `\\set ON_ERROR_STOP` + a `SELECT 1 FROM information_schema.tables …` precondition pattern documented in the learning file.
4. **Visibility (CI workflow preflight):** add a `tenant-integration.yml` step that, before invoking `run-migrations.sh`, asserts EVERY table/function the upcoming migrations are about to reference exists in dev's schema. The probe runs against the ledger's current state, NOT against `origin/main`'s migration files, so a future ledger-vs-schema split surfaces with a precise object name BEFORE the next migration crashes inside its apply transaction.

The four parts work together: (1) clears the current dev state so CI can move past today's red; (2) and (3) make future occurrences fail loud with a diagnosable error instead of "relation does not exist" three layers deep; (4) catches the next occurrence before any DDL runs.

## Root Cause

Run `26280818623` log (verified at plan-write time):

```
##[warning]053_organizations_and_workspace_members.sql is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1.
##[warning]058_workspace_member_attestations.sql is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1.
##[warning]059_workspace_keyed_rls_sweep.sql is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1.
##[warning]061_byok_audit_workspace_id_rpcs.sql is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1.
##[warning]062_workspace_member_removals_and_remove_rpc_update.sql is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1.
Applying: 062_workspace_member_removals_and_remove_rpc_update.sql
ERROR:  relation "public.workspaces" does not exist
##[error]Migration failed: 062_workspace_member_removals_and_remove_rpc_update.sql
```

Only `062` reached the `Applying:` line. 053-061 were marked already-applied in dev's `_schema_migrations` (the runner's filename-keyed check at `apps/web-platform/scripts/run-migrations.sh:250-254` short-circuits on `count > 0`). Yet `062_workspace_member_removals_and_remove_rpc_update.sql:77` (`workspace_id … REFERENCES public.workspaces(id) ON DELETE SET NULL`) failed because the table doesn't exist.

The ledger state and the schema state have diverged. Three hypotheses, ordered by likelihood:

- **H1 (most likely — schema-vs-ledger split from prior remediation):** During the #4241 remediation window (2026-05-21 12:46-21:00 UTC), the operator applied paired down-migrations against dev (drop the tables) AND deleted the `_schema_migrations` rows. When PR #4225 merged (2026-05-21, commit `7a922264`), CI re-ran the renumbered forward migrations (053, 058, 059, 060). Something in that re-apply chain inserted the ledger rows WITHOUT successfully creating the schema — either: (a) a partial-failure where the `--single-transaction` wrapper rolled back the schema changes but a separate session inserted the row, or (b) the operator manually inserted the rows out of band to unblock another red CI, or (c) a runner edge case where `CREATE TABLE IF NOT EXISTS` no-op'd against a pre-existing partial schema and the insert succeeded but no fresh tables were created. Without a `_schema_migrations.applied_at` query against dev (operator-paced step), we cannot pick between (a), (b), and (c).
- **H2 (ruled out by log evidence):** `bunx supabase migration up` ran 062 before 053 despite filename sort. The log explicitly shows 053-061 considered before 062 (in alphabetical order), and the runner uses bash glob expansion, which is alphabetical. The `Applying:` line only appears for migrations that pass the `already_applied` gate (line 250). So 053-061 were considered AND found in the ledger. Order is correct; the bug is that the ledger says "applied" when the schema disagrees.
- **H3 (ruled out by direct grep):** 053 silently failed/skipped during apply. The runner uses `psql --single-transaction --set ON_ERROR_STOP=1`. A failure in the body of 053 would have rolled BOTH the schema changes AND the `INSERT INTO _schema_migrations` back in the same transaction. The row's presence implies the transaction committed. The hypothesis would require Postgres to commit half a transaction, which it doesn't.

The ALSO-relevant observation: the `Detect dev-vs-main migration drift` probe step that ran immediately before the failing apply reported `No dev-vs-main migration drift detected.` — meaning every row in dev's `_schema_migrations` matches a file on `origin/main`. So the drift class the probe was designed to catch (#4241-style "rows for migrations that never merged") is NOT firing. This is a DIFFERENT drift class: ledger rows for migrations that DID merge to main, but whose schema state on dev was clobbered between apply and now. The existing probe has no visibility into schema state — it cross-references the ledger against `git ls-tree origin/main`, not against `information_schema.tables`. That gap is the load-bearing observability hole this plan closes.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Reality | Plan response |
|---|---|---|
| Issue body cites three hypotheses: (1) 053 silently failed, (2) ledger-vs-schema drift, (3) `bunx supabase migration up` ordering. | (1) and (3) ruled out by log evidence + runner shape (atomic transaction; bash-glob alphabetical order; `Applying:` line only for non-already-applied rows). (2) is the surviving hypothesis. | Plan focuses on (2). Operator-paced step inspects dev's `_schema_migrations` to confirm WHICH sub-mechanism produced the split. |
| Issue body suggests `bunx supabase migration up` may have run 062 before 053. | The CI workflow does NOT call `bunx supabase migration up`. It calls `bash scripts/run-migrations.sh --bootstrap=skip` (tenant-integration.yml:175). The runner uses native bash glob expansion (`for migration_file in "$MIGRATIONS_DIR"/*.sql; do`), which sorts alphabetically/lexically. 062 reaches the `Applying:` line only because 053-061 are already in the ledger. | Plan body corrects the issue-body's mental model of the apply path. |
| Issue body says "053 mig appears in the prelude as 'not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1'". | The "not on origin/main" warning fires for EVERY migration in the log (001 through 062). Verified at plan-write time: the workflow's `git fetch` in the drift-probe action runs with `actions/checkout@v4` default `fetch-depth=1` plus a `git fetch --depth=1 origin main` belt-and-braces. The fetch SHOULD populate `refs/remotes/origin/main`, but the warning shows the gate's `git ls-tree origin/main -- <path>` returns empty for ALL migrations — including 001 which is unambiguously on main since the repo's first commit. | Plan files a follow-up tracking issue (post-merge AC) to investigate why `git fetch origin main` does not populate `refs/remotes/origin/main` reliably in this workflow. Out-of-scope for THIS PR (the gate is opt-in via `ALLOW_UNMERGED_DEV_APPLY=1` which the workflow sets, so the false-positive is annoying but non-blocking). |
| The prior #4241 fix shipped a workflow gate that "fails loud instead of swallowing silently". | True — `apps/web-platform/scripts/run-migrations.sh:200-205` errors when a migration is not on `origin/main` AND `ALLOW_UNMERGED_DEV_APPLY=1` is unset. The CI workflow sets the env var (tenant-integration.yml:152), so the gate degrades to a warning in CI. This is the intended behavior for the CI legitimate apply path. | Plan adds a NEW gate orthogonal to the unmerged-apply gate: a schema-presence probe (Phase 3) that fires regardless of `ALLOW_UNMERGED_DEV_APPLY`. |
| Three fix candidates in the prompt: (a) guard 062 with `IF EXISTS`, (b) harden ledger-drift detection, (c) operator-paced dev reconciliation, (d) preflight schema check. | (a) is partial — `CREATE TABLE IF NOT EXISTS public.workspace_member_removals (…REFERENCES public.workspaces …)` cannot tolerate a missing referenced table; the FK declaration parses at DDL time. The guard has to be a precondition assertion BEFORE the CREATE TABLE, not an `IF EXISTS` clause on the body. The plan adopts (a) reshaped as a `DO $$ … RAISE EXCEPTION` precondition wrapper. | All four candidates are folded in; (a) is reshaped to a precondition assertion + a generalized pattern documented in the learning file. |

## User-Brand Impact

**If this lands broken, the user experiences:** continued red CI on every PR that touches `apps/web-platform/server/**` or `apps/web-platform/supabase/migrations/**`. No production user impact — prd Supabase is unaffected; CI is the only consumer of dev. The downstream impact is to engineering velocity: PRs cannot merge with confidence because the tenant-integration gate is broken. The PRs sitting on the gate today (verified at plan-write time via `gh run list --workflow=tenant-integration.yml --branch main --limit 10`: 7 failures, 2 successes, since 2026-05-21 13:10 UTC) accumulate.

**If this leaks, the user's data is exposed via:** N/A — no production data path involved. Dev-Supabase contains only synthetic `tenant-isolation-*@soleur.test` fixtures (per `cq-test-fixtures-synthesized-only`).

**Brand-survival threshold:** none — this is a CI-only regression on a dev-only Supabase project. Per `hr-dev-prd-distinct-supabase-projects`, dev and prd are distinct projects; the schema-vs-ledger drift exists only on dev. Production posture is fine (the failing migration 062 ships against prd via a separate operator-paced apply workflow that is not exercised by tenant-integration). Threshold scope-out reason: CI tooling failure on a dev-only schema; no operator/customer data or workflow touched.

## Hypotheses (ruled in/out)

- **H1 (ruled in, sub-mechanism TBD by Phase 0):** Schema-vs-ledger split on dev. `_schema_migrations` rows exist for 053/058/059/060 but `public.workspaces` is absent. Operator-paced step (Phase 0.5) determines whether the split came from (a) the #4241 remediation chain, (b) a manual `INSERT INTO _schema_migrations` to unblock another red CI, or (c) a re-apply that no-op'd due to a pre-existing partial schema.
- **H2 (ruled out):** `bunx supabase migration up` ordering. The runner uses bash glob, not `bunx supabase`. Order is alphabetical and deterministic.
- **H3 (ruled out):** 053 silent-failed. `psql --single-transaction` plus the in-script `INSERT INTO _schema_migrations` means schema + ledger commit together. The ledger row's presence implies the schema changes committed (at the time the row was inserted).
- **H4 (NOT explored — out of scope):** A separate non-runner apply path inserted `_schema_migrations` rows without running the SQL bodies. Possible candidates: Supabase dashboard "Database → Migrations" UI, a custom operator script, a partial-apply via `psql -f` outside the runner. The Phase 0.5 inspection will surface evidence (e.g., `applied_at` clustering, NULL `content_sha` on a post-054 row) but a confirmed root cause requires reading dev's Supabase audit log. Filed as a post-merge tracking issue if the Phase 0.5 sub-mechanism isn't (a) or (c).

## Implementation Phases

### Phase 0 — Preconditions

- [ ] **0.1** Confirm worktree CWD is `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-mig062-workspaces-dep-4294` and branch is `feat-one-shot-mig062-workspaces-dep-4294`. Per `hr-when-in-a-worktree-never-read-from-bare`, all paths in this plan are relative to that worktree root.

- [ ] **0.2** Re-grep `apps/web-platform/supabase/migrations/` on the current branch (HEAD = main) for the workspaces table creation site and confirm 053 is present:

  ```bash
  grep -n "CREATE TABLE IF NOT EXISTS public.workspaces" \
    apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql
  # Expected: one hit at line 61.
  ```

- [ ] **0.3** Confirm the dev Doppler config and assert `environment=dev` before any psql call (mirrors `.github/workflows/tenant-integration.yml:88-114`):

  ```bash
  env_name=$(doppler configs get dev_scheduled -p soleur --json | jq -r '.environment // empty')
  test "$env_name" = "dev" || { echo "ABORT: dev_scheduled resolves to ${env_name}, expected dev"; exit 1; }
  ```

  Per `hr-dev-prd-distinct-supabase-projects` and `hr-menu-option-ack-not-prod-write-auth`, this is a dev-only write; no prd flag flips.

### Phase 0.5 — Operator-paced: inspect dev's schema-vs-ledger split

Per `hr-no-dashboard-eyeball-pull-data-yourself`, the operator pulls the data via psql; the dashboard is not the source of truth. This step is operator-paced (the inspection requires interactive judgment on the sub-mechanism), but every query is automated.

- [ ] **0.5.1** Snapshot dev's `_schema_migrations` rows for the 053-062 window:

  ```bash
  doppler run -p soleur -c dev_scheduled -- \
    psql "$DATABASE_URL_POOLER" -F "|" -c "
    SELECT filename, applied_at, content_sha
      FROM public._schema_migrations
     WHERE filename LIKE '05%' OR filename LIKE '06%'
     ORDER BY applied_at, filename;" | tee /tmp/dev-schema-migrations-053-062.txt
  ```

  Document the output in the PR body as a `<details>` block. Capture (a) the `applied_at` ordering — if 062 appears chronologically BEFORE 053, the runner can't have produced this state, ruling sub-mechanism (a)/(c) out; (b) whether `content_sha` is NULL for any rows — pre-054 rows have NULL by design, but a NULL on a 058+ row implies a manual INSERT bypassing the runner.

- [ ] **0.5.2** Snapshot dev's schema for the missing-table window:

  ```bash
  doppler run -p soleur -c dev_scheduled -- \
    psql "$DATABASE_URL_POOLER" -F "|" -c "
    SELECT to_regclass('public.organizations'),
           to_regclass('public.workspaces'),
           to_regclass('public.workspace_members'),
           to_regclass('public.workspace_member_attestations'),
           to_regclass('public.workspace_member_removals');"
  ```

  Expected current state (per the CI failure): all five return NULL. If any are non-NULL, the drift is partial — pick the resolution branch in 0.5.3 accordingly.

- [ ] **0.5.3** Choose resolution branch based on the snapshots in 0.5.1 + 0.5.2:

  - **Branch A (recommended — clean re-apply):** Delete the stale `_schema_migrations` rows for 053/058/059/060/061 so the next CI run re-applies them. The runner is idempotent against `CREATE TABLE IF NOT EXISTS` + the `INSERT NOT EXISTS` backfill discriminator (053 §6 lines 187-188), so the re-apply will run clean even if a partial schema exists. Apply:

    ```bash
    doppler run -p soleur -c dev_scheduled -- \
      psql "$DATABASE_URL_POOLER" -v ON_ERROR_STOP=1 -c "
      DELETE FROM public._schema_migrations
       WHERE filename IN (
         '053_organizations_and_workspace_members.sql',
         '058_workspace_member_attestations.sql',
         '059_workspace_keyed_rls_sweep.sql',
         '060_current_organization_jwt_hook.sql',
         '061_byok_audit_workspace_id_rpcs.sql'
       );"
    ```

  - **Branch B (operator judgment — manual forward apply):** Apply the 053/058/059/060/061 forward migration files directly via psql against dev, in order, then verify `to_regclass('public.workspaces')` is non-NULL. Use this branch only if 0.5.1 shows the rows have non-NULL `content_sha` matching origin/main's blob (drift probe confirms no content drift) AND 0.5.2 shows partial schema state — i.e., the rows tracked the apply, but a manual operator action (DROP TABLE) clobbered the schema after. Branch A is strictly safer because it re-runs the full migration body with the runner's atomic-transaction discipline.

- [ ] **0.5.4** Verify resolution: re-run 0.5.2's snapshot. If any of the 5 `to_regclass` calls still return NULL after Branch A, escalate — the runner didn't pick up the deleted rows on the next apply; investigate the runner's idempotency machinery before proceeding.

### Phase 1 — Re-run the tenant-integration suite locally against dev to confirm green

Per `hr-no-dashboard-eyeball-pull-data-yourself`, do NOT wait for the next push to confirm; trigger the suite from the worktree.

- [ ] **1.1** Trigger a fresh `tenant-integration.yml` run via `gh workflow run` against this PR's branch:

  ```bash
  gh workflow run tenant-integration.yml --ref feat-one-shot-mig062-workspaces-dep-4294
  ```

  Wait for completion; expected: green (all 15+ tenant-isolation suites pass; `Applying: 053_…`, `Applying: 058_…`, `Applying: 059_…`, `Applying: 060_…`, `Applying: 061_…` lines appear; `Applying: 062_…` does NOT error).

- [ ] **1.2** Spot-check the suites the PR-J merge (#4294) added so the schema-vs-ledger split's recovery doesn't mask a real PR-J regression:
  - `test/server/dsar/workspace-member-removals.tenant-isolation.test.ts` (if present — verify file exists before running)
  - `test/server/dsar/anonymise-removal-cascade.tenant-isolation.test.ts` (if present)

### Phase 2 — Code fix: precondition assertion in 062 for resilience against future schema-vs-ledger splits

The current 062 body starts with `CREATE TABLE IF NOT EXISTS public.workspace_member_removals (…REFERENCES public.workspaces …)`. The FK declaration parses at DDL time, so an `IF EXISTS` clause on the body cannot guard against a missing `workspaces` table. The fix is a precondition assertion ABOVE the CREATE TABLE that fails loud with a self-describing error.

- [ ] **2.1** Prepend a precondition block to `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql` (before the existing `-- 1. Table` section header at line ~62):

  ```sql
  -- Precondition: public.workspaces must exist. If absent, the
  -- _schema_migrations ledger is out of sync with schema state (the
  -- #4338 failure class). Fail loud with a self-describing error
  -- naming the missing relation + linking to the recovery learning.
  DO $$
  BEGIN
    IF to_regclass('public.workspaces') IS NULL THEN
      RAISE EXCEPTION
        'Migration 062 precondition failed: public.workspaces does not exist. '
        'This indicates a schema-vs-ledger drift on this Supabase project — '
        '_schema_migrations claims 053_organizations_and_workspace_members is '
        'applied but the workspaces table is absent. See '
        'knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md '
        'for the recovery procedure (delete the stale ledger rows; re-apply 053).';
    END IF;
  END $$;
  ```

  The precondition surfaces the actual drift class in the error message, instead of the cryptic `relation "public.workspaces" does not exist` that surfaces from the FK parser two layers deep.

- [ ] **2.2** Verify the precondition fires correctly against a dry-run state. Use a transaction-scoped test against dev (after Phase 0.5 + Phase 1 confirm the schema is restored):

  ```bash
  doppler run -p soleur -c dev_scheduled -- psql "$DATABASE_URL_POOLER" -v ON_ERROR_STOP=1 <<'SQL'
  BEGIN;
  -- Simulate the drift by dropping workspaces in this transaction.
  DROP TABLE IF EXISTS public.workspaces CASCADE;
  -- Run the precondition block in isolation.
  DO $$
  BEGIN
    IF to_regclass('public.workspaces') IS NULL THEN
      RAISE NOTICE 'PRECONDITION FIRED (expected)';
    END IF;
  END $$;
  ROLLBACK;
  SQL
  ```

  Expected: `NOTICE: PRECONDITION FIRED (expected)`. The `ROLLBACK` ensures the dropped table is restored in the same transaction.

### Phase 3 — Apply-time defense: pre-apply schema-presence probe in run-migrations.sh

The schema-vs-ledger split today surfaced as a cryptic FK error inside 062's transaction. Add a runner-level probe that, BEFORE every apply, queries `to_regclass` for every relation the about-to-apply migration's body REFERENCES, and fails loud with a self-describing error if any are missing. The probe is best-effort (does not fail closed if the parse logic can't find references — that case degrades gracefully to today's behavior).

The probe is opt-in via a new env var `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` so it can be rolled out gradually (CI sets it; ad-hoc operator runs default to off). The CI workflow sets it after Phase 4 wires the env.

- [ ] **3.1** Add the probe to `apps/web-platform/scripts/run-migrations.sh` between line 254 (post-already-applied skip) and line 256 (`echo "Applying: $filename"`):

  ```bash
  # Schema-presence probe (#4338). Before applying a migration, extract
  # the `REFERENCES public.<table>` mentions from its body and confirm
  # each table exists in the live schema. Catches the schema-vs-ledger
  # drift class (ledger says applied; schema disagrees) one migration
  # earlier than the FK parser would, with an error message that names
  # the missing relation and links to the recovery learning.
  # Best-effort: degrades gracefully on parse-failure (the FK parser
  # remains the last line of defense).
  if [[ "${MIGRATION_SCHEMA_PRECONDITION_PROBE:-0}" == "1" ]]; then
    referenced_tables=$(grep -oE 'REFERENCES public\.[a-z_][a-z0-9_]*' "$migration_file" \
      | awk '{print $2}' \
      | sort -u || true)
    missing_tables=""
    while IFS= read -r tbl; do
      [[ -z "$tbl" ]] && continue
      exists=$(run_sql "SELECT to_regclass('$tbl') IS NOT NULL;" || echo "f")
      if [[ "$exists" != "t" ]]; then
        missing_tables+="$tbl "
      fi
    done <<<"$referenced_tables"
    if [[ -n "$missing_tables" ]]; then
      echo "::error::Migration $filename references tables that do not exist: $missing_tables"
      echo "::error::This indicates a schema-vs-ledger drift on this Supabase project."
      echo "::error::See knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md for the recovery procedure."
      exit 1
    fi
  fi
  ```

  **Why best-effort, not always-on.** The probe's parse logic (`grep -oE 'REFERENCES public\.…'`) catches the common case (FK declarations in `CREATE TABLE`) but misses dynamic SQL (`EXECUTE format('… REFERENCES public.%I …', …)`), dependencies on functions/views/types/sequences (only relation-class objects are probed), and dependencies hidden behind `DO $$ … $$` blocks. A future migration could pass the probe and still trip a different missing-relation error. The probe is a load-bearing diagnostic improvement, NOT a complete dependency resolver — that's why the FK parser remains the last line of defense.

- [ ] **3.2** Add a test for the probe in `apps/web-platform/scripts/lib/run-migrations-schema-probe.test.sh` (matching the existing `*.test.sh` convention in `apps/web-platform/scripts/`):

  ```bash
  #!/usr/bin/env bash
  # Tests apps/web-platform/scripts/run-migrations.sh's
  # MIGRATION_SCHEMA_PRECONDITION_PROBE behavior. Synthesizes a
  # migration file with a REFERENCES public.<missing> FK and confirms
  # the probe exits non-zero with the named relation in the error.
  # Uses a local Postgres if available; skip otherwise.
  set -euo pipefail
  # … (full test body to be written at /work time; mirrors the
  # existing postgrest-reload-schema.test.sh structure)
  ```

  Per `cq-write-failing-tests-before`, write this test FIRST in the RED state; confirm it fails against the current `run-migrations.sh`; THEN add the probe block from 3.1; confirm GREEN.

### Phase 4 — Visibility: CI workflow preflight schema-presence check

The runner-level probe (Phase 3) fires per-migration. Add a workflow-level preflight that, before invoking the runner, asserts that EVERY relation declared as `CREATE TABLE … public.<name>` across all migrations in `apps/web-platform/supabase/migrations/*.sql` exists in dev's schema OR has not yet been applied. Catches the ledger-vs-schema split at workflow-time, BEFORE the runner enters its apply loop. This is the visibility layer that complements the runner's apply-time defense.

- [ ] **4.1** Add a `Preflight: schema-vs-ledger consistency check` step to `.github/workflows/tenant-integration.yml`, inserted between the existing `Detect dev-vs-main migration drift` step (line ~125) and the `Apply migrations to dev` step (line ~146):

  ```yaml
  # Preflight: schema-vs-ledger consistency check (#4338). For every
  # `_schema_migrations` row on dev, parse the corresponding migration
  # file on this checkout and confirm the `CREATE TABLE public.<name>`
  # relations exist in dev's schema. Catches the drift class where the
  # ledger says "applied" but the schema disagrees, BEFORE the runner
  # tries to apply a downstream migration whose FK declaration depends
  # on the missing table. Severity is `::error::` (fail-closed) because
  # by the time this step runs, the runner is about to crash anyway —
  # surfacing the precise missing relation is strictly more useful than
  # the FK parser's cryptic "relation does not exist".
  - name: Preflight schema-vs-ledger consistency check
    working-directory: apps/web-platform
    env:
      DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}
    run: |
      set -uo pipefail
      # 1. Read applied filenames from dev's ledger.
      applied=$(doppler run -p soleur -c dev_scheduled -- \
        sh -c 'psql "$DATABASE_URL_POOLER" --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "SELECT filename FROM public._schema_migrations ORDER BY filename;"')
      # 2. For each applied filename, parse local file for CREATE TABLE
      # public.<name> declarations and verify each exists in dev schema.
      missing=""
      while IFS= read -r filename; do
        [[ -z "$filename" ]] && continue
        path="supabase/migrations/$filename"
        [[ -f "$path" ]] || continue   # ledger row for a deleted/renamed file → skip
        declared_tables=$(grep -oE 'CREATE TABLE (IF NOT EXISTS )?public\.[a-z_][a-z0-9_]*' "$path" \
          | awk '{print $NF}' | sort -u || true)
        while IFS= read -r tbl; do
          [[ -z "$tbl" ]] && continue
          exists=$(doppler run -p soleur -c dev_scheduled -- \
            sh -c "psql \"\$DATABASE_URL_POOLER\" --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c \"SELECT to_regclass('$tbl') IS NOT NULL;\"" || echo "f")
          if [[ "$exists" != "t" ]]; then
            missing+="  - ledger claims $filename applied, but $tbl is missing"$'\n'
          fi
        done <<<"$declared_tables"
      done <<<"$applied"
      if [[ -n "$missing" ]]; then
        echo "::error::Schema-vs-ledger drift detected on dev-Supabase:"
        printf '%s' "$missing" | while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "::error::$line"
        done
        echo "::error::See knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md for recovery."
        exit 1
      fi
      echo "Preflight: schema-vs-ledger consistency check passed."
  ```

- [ ] **4.2** Wire the `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` env var into the existing `Apply migrations to dev` step so the runner-level probe (Phase 3) also fires under CI. Insert into the existing `env:` block (tenant-integration.yml:148-163):

  ```yaml
      env:
        DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}
        ALLOW_UNMERGED_DEV_APPLY: "1"
        MIGRATION_SCHEMA_PRECONDITION_PROBE: "1"   # #4338 — best-effort schema probe.
  ```

  The two probes (Phase 4.1 workflow-level + Phase 3 runner-level) compose: 4.1 catches the drift at workflow-time before the runner starts; Phase 3 catches it per-migration if 4.1 false-negatives (e.g., a future migration's table declared via dynamic SQL that 4.1's grep can't parse).

### Phase 5 — Documentation: capture the schema-vs-ledger split as a learning

- [ ] **5.1** Write the learning file `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md` capturing: (a) the symptom (062 fails with `relation "public.workspaces" does not exist` while ledger claims 053 is applied), (b) the root cause (ledger and schema state diverged — the `_schema_migrations` row's presence is necessary but not sufficient evidence the schema state is current), (c) the misdiagnosis trap (the three hypotheses in issue #4338 — 062 ordering before 053, 053 silent-failed, ledger-schema drift — only the third survives log evidence; the first two are ruled out by the runner's atomic-transaction + bash-glob shape), (d) the fix (operator-paced ledger reconcile + 062 precondition + runner schema probe + workflow preflight), (e) the generalized recipe (every future migration whose body REFERENCES a relation from a prior migration MUST include a precondition assertion if that relation is foundational — the four-line `DO $$ … RAISE EXCEPTION` block in Phase 2.1 is the canonical shape; document it). Per `cq-test-fixtures-synthesized-only`, no real user data appears in the learning.

- [ ] **5.2** Update the prior #4241 learning file `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` with a forward-pointer to the new #4338 learning, noting that the #4241 drift class (ledger rows for unmerged files) is orthogonal to the #4338 drift class (ledger says applied, schema disagrees) and BOTH probes are now in place (filename-vs-main from #4241 + schema-vs-ledger from #4338).

## Files to Edit

- `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql` — Phase 2.1 precondition assertion.
- `apps/web-platform/scripts/run-migrations.sh` — Phase 3.1 schema-presence probe.
- `.github/workflows/tenant-integration.yml` — Phase 4.1 preflight step + Phase 4.2 env-var wiring.
- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` — Phase 5.2 forward-pointer.

## Files to Create

- `apps/web-platform/scripts/lib/run-migrations-schema-probe.test.sh` — Phase 3.2 test for the runner probe.
- `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md` — Phase 5.1 learning file.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `grep -n "public\\.workspaces" apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql` shows the precondition `DO $$` block above line 70 (the `CREATE TABLE` line). Verified by reading the file.
- [ ] **AC2** `grep -n "MIGRATION_SCHEMA_PRECONDITION_PROBE" apps/web-platform/scripts/run-migrations.sh` returns ≥1 match.
- [ ] **AC3** `grep -n "Preflight schema-vs-ledger consistency check" .github/workflows/tenant-integration.yml` returns 1 match, AND the step appears AFTER the `Detect dev-vs-main migration drift` step AND BEFORE the `Apply migrations to dev` step (verified by line-number ordering).
- [ ] **AC4** `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` appears in `tenant-integration.yml`'s `Apply migrations to dev` step's `env:` block.
- [ ] **AC5** The next push of this PR's branch to GitHub produces a green `Tenant integration (dev-Supabase)` check (full 15+ suites pass; the `Applying: 062_…` line completes without error). Per `wg-after-marking-a-pr-ready-run-gh-pr-merge` the auto-merge can fire only after this check passes.
- [ ] **AC6** Operator-paced: Phase 0.5 snapshot (the `<details>` block in the PR body) shows the ledger-vs-schema split that motivated this fix — at least one of the 5 `to_regclass` calls returns NULL while the corresponding `_schema_migrations` row exists. (If this snapshot shows NO drift at PR-creation time, the dev state has self-healed between issue-file and PR-create; the AC then verifies the empty-drift case via the new preflight step's log.)
- [ ] **AC7** `bash apps/web-platform/scripts/lib/run-migrations-schema-probe.test.sh` exits 0 (Phase 3.2 test, GREEN state).

### Post-merge (operator)

- [ ] **AC8** Within 24 hours of merge, operator opens a follow-up tracking issue for the `git fetch origin main` reliability gap noted in Research Reconciliation row #3 (workflow's drift-probe action sees every migration as "not on origin/main", which means the gate is degraded to a permanent warning). Tracking-only; not a code change in this PR. Labels: `domain/engineering`, `chore`, `priority/p3-low`.
- [ ] **AC9** Operator verifies prd-Supabase is unaffected by running `gh workflow run web-platform-release.yml --ref main` and confirming the migrate job lands green. Prd ledger + schema state are managed via a separate apply path (per `hr-dev-prd-distinct-supabase-projects`); the drift class addressed here is dev-only.

## Test Scenarios

- **TS1 — Schema-presence probe catches drift.** Phase 3.2's test synthesizes a migration file with `REFERENCES public.nonexistent` and confirms the runner exits non-zero with the named relation in the error.
- **TS2 — Workflow preflight catches ledger-vs-schema split.** Manually `DROP TABLE public.workspaces CASCADE` against a local Postgres with `_schema_migrations` populated for 053, then run the Phase 4.1 preflight step. Confirm `::error::` is emitted naming `public.workspaces` as missing. (Don't run against dev — synthesize a local Postgres for the test.)
- **TS3 — 062 precondition fires.** Phase 2.2's transaction-scoped test. Confirms the `RAISE EXCEPTION` body's message contains the canonical recovery learning path.
- **TS4 — Probe is opt-in.** Run `run-migrations.sh` without `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` against a migration with a `REFERENCES public.nonexistent` body; confirm the probe does NOT fire and the runner falls through to the existing FK parser's behavior (the precondition only fires when the env is set).
- **TS5 — Phase 0.5 Branch A clears CI.** After Phase 0.5.3 Branch A's `DELETE FROM _schema_migrations` against dev, the next CI run re-applies 053/058/059/060/061 cleanly AND `Applying: 062_…` completes without error.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on a dev-only Supabase project. No user-facing surface, no compliance or legal artifact (the workspace_member_removals WORM ledger that #4294 introduced is in scope for the GDPR Art. 30 register, but THIS plan only fixes the apply path; the ledger contract is unchanged), no marketing/sales/finance touchpoint. Skipped per the Phase 2.5 NONE branch.

## Observability

| Field | Value |
|---|---|
| `liveness_signal` | The `Tenant integration (dev-Supabase)` GitHub Actions workflow on every push/PR that touches the path filter, AND the scheduled cron at `.github/workflows/scheduled-dev-migration-drift.yml` (every 6 hours). Cadence: per-push + 6-hourly. Alert target: GitHub Checks status (red → merge blocked); cron emits `::warning::` annotations on drift. Configured in: `.github/workflows/tenant-integration.yml:38-46` + `.github/workflows/scheduled-dev-migration-drift.yml:21-23`. |
| `error_reporting` | Workflow failure surfaces a red check on the PR; the `Preflight schema-vs-ledger consistency check` step emits `::error::` with the missing-relation enumeration; the `Apply migrations to dev` step echoes the failing SQL filename via `psql -v ON_ERROR_STOP=1`. Fail-loud: yes (no `\|\| true` swallowing on the preflight). |
| `failure_modes` | (1) Schema-vs-ledger drift recurs (the precise mechanism varies — operator UI write, manual `INSERT INTO _schema_migrations`, partial apply). Detection: Phase 4.1's preflight step emits `::error::` naming the missing relations. Alert route: GitHub Actions red check + PR-blocking. (2) Runner probe false-positive (probe fires on a relation declared via dynamic SQL the parser can't see). Detection: operator manually clears the probe via `MIGRATION_SCHEMA_PRECONDITION_PROBE=0` once verified safe. Alert route: GitHub Actions log inspection. (3) Phase 0.5 Branch A's `DELETE` fails partway (network drop). Detection: re-run 0.5.2 — if any `to_regclass` still NULL, escalate. |
| `logs` | `psql -v ON_ERROR_STOP=1` outputs are captured in the GitHub Actions step log (retention: 90 days per default). `_schema_migrations` snapshots in `/tmp/dev-schema-migrations-053-062.txt` are session-local and pasted into the PR body's `<details>` block. |
| `discoverability_test` | See canonical block below. No SSH required. |

discoverability_test:
  command: doppler run -p soleur -c dev_scheduled -- psql "$DATABASE_URL_POOLER" -tAc "SELECT to_regclass('public.workspaces') IS NOT NULL AND EXISTS (SELECT 1 FROM public._schema_migrations WHERE filename = '053_organizations_and_workspace_members.sql');"
  expected_output: "t"

The canonical probe asserts that BOTH the workspaces table exists AND the `_schema_migrations` row claims 053 is applied. Anything other than `t` indicates schema-vs-ledger drift. The probe is dev-only (per `hr-dev-prd-distinct-supabase-projects`); the prd equivalent is the post-merge `web-platform-release.yml` migrate job which runs against the prd Supabase project on every release. No SSH required.

## Risks

- **R1: Phase 0.5 Branch A causes a re-apply chain to fail.** The runner is idempotent against `CREATE TABLE IF NOT EXISTS` + `INSERT NOT EXISTS` backfill (053 §6 lines 187-188), so the re-apply should be safe. Mitigation: 053-061's backfill bodies all use the `WHERE NOT EXISTS (...)` discriminator pattern (verified at plan-write time via the 053 file body); the re-apply logs `0/0/0` rows inserted for the backfill against the existing schema. Lower risk because the team-workspace branch's authors explicitly designed 053 for re-apply per the file header comments.
- **R2: The Phase 4.1 preflight step false-positives on a future migration with dynamic-SQL CREATE TABLE.** Mitigation: the grep is a hard `CREATE TABLE (IF NOT EXISTS )?public\.[a-z_][a-z0-9_]*` pattern — dynamic-SQL `EXECUTE format('CREATE TABLE %I.%I …', …)` does not match. Future migrations using dynamic CREATE TABLE will pass the preflight silently, falling through to the runner. This is the right failure mode (don't block on a parse the preflight can't see).
- **R3: The runner schema-presence probe (Phase 3) misses a non-FK schema dependency.** A migration might `SELECT FROM public.workspaces` inside a function body without using `REFERENCES`. The grep only catches FK declarations. Mitigation: the preflight at Phase 4.1 catches the `CREATE TABLE public.<name>` declarations, which is the stronger signal for "this table SHOULD exist if its parent migration is applied". The two probes together cover the common cases; a complete solution would parse the SQL AST, which is out of scope.
- **R4: The CI `git fetch origin main` reliability gap noted in Research Reconciliation row #3 is unrelated to this fix.** Per AC8, a follow-up tracking issue is opened post-merge. Mitigation: the workflow sets `ALLOW_UNMERGED_DEV_APPLY=1`, so the false-positive degrades to a noisy warning, not a blocker.
- **R5: Phase 2.1's precondition makes 062 non-idempotent against a future fresh apply where workspaces is being created in the same batch.** Mitigation: the runner applies migrations one-at-a-time with separate transactions (`--single-transaction` per file). 053 commits and `workspaces` is visible to 062 before 062's precondition runs. The precondition only fires when the ledger says 053 is applied AND the schema disagrees — exactly the drift class we're catching.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in \
  apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql \
  apps/web-platform/scripts/run-migrations.sh \
  .github/workflows/tenant-integration.yml; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

None. (Probe to be re-run inline at /work time — record `None` if no matches; otherwise enumerate with fold-in/acknowledge/defer dispositions per Phase 1.7.5.)

## Sharp Edges

- A `## User-Brand Impact` section whose threshold resolves to `none` AND whose diff touches a non-sensitive path. This plan's diff touches `apps/web-platform/scripts/run-migrations.sh`, `.github/workflows/tenant-integration.yml`, and `knowledge-base/`, plus `apps/web-platform/supabase/migrations/062_*.sql`. The migration file IS under `**/migrations/**` (per preflight Check 6 canonical regex), so a `threshold: none, reason:` scope-out bullet is technically required at ship-time. Reason: dev-only schema-vs-ledger reconcile; no production data path; no operator/customer workflow touched; mig 062 is a precondition assertion + comments, not a schema change.
- Per `wg-use-closes-n-in-pr-body-not-title-to`, the PR body uses `Closes #4338` (this issue resolves at merge — the dev schema is restored at Phase 0.5, before merge; the workflow gate + runner probe that prevent recurrence land at merge).
- Per `hr-no-ssh-fallback-in-runbooks`: all discoverability and apply paths use `doppler run -- psql` and `gh run view`. No SSH. The Phase 3 + Phase 4 probes use `psql` via the Doppler-injected `DATABASE_URL_POOLER`; the workflow's preflight uses `doppler run … sh -c 'psql …'` per the existing drift-probe action's pattern.
- The `to_regclass()` function returns NULL for relations that don't exist; the probe uses `IS NOT NULL` rather than `EXISTS (SELECT … FROM information_schema.tables …)` because `to_regclass` is a single function call and tolerates schema-qualified relation names without parsing — it's the canonical Postgres idiom for "does this relation exist".
- Per `cq-pg-security-definer-search-path-pin-pg-temp`: 062's existing SECURITY DEFINER bodies pin `search_path = public, pg_temp` (verified at the file's RPC declarations). The Phase 2.1 precondition does NOT introduce a new SECURITY DEFINER function — it's an anonymous `DO $$` block that inherits the caller's `search_path`, which is `public` (the default for the runner's psql invocation). No new search-path concern.
- The Phase 3 runner probe uses `grep -oE 'REFERENCES public\.[a-z_][a-z0-9_]*'`. This pattern requires the FK declaration to literally read `REFERENCES public.<name>` — a future migration that writes `REFERENCES "public"."workspaces"` (quoted) or `REFERENCES workspaces` (unqualified) will not match. The plan accepts this limitation: the precedent in 053/058/059/061/062 all use the unquoted `REFERENCES public.<name>` form (verified at plan-write time via `grep -h "REFERENCES public\\." apps/web-platform/supabase/migrations/*.sql | head`); future migrations should follow the same convention. Document in the learning file.
- Per `cq-test-fixtures-synthesized-only`: Phase 3.2's test (`run-migrations-schema-probe.test.sh`) synthesizes a temp Postgres or operates against a transient `_schema_migrations` row in a transaction it rolls back. No real user data appears in the test.

## References

- Issue: #4338
- Failing run: `26280818623` (2026-05-22 09:49 UTC, branch `main`)
- Sibling/precedent PRs:
  - #4294 (PR-J, mig 062) — merged 2026-05-22 in commit `ce53967f`. The migration that surfaces the drift.
  - #4225 (team-workspace, mig 053/058/059/060) — merged 2026-05-21 in commit `7a922264`. The migration that originally creates `public.workspaces`.
  - #4251 — merged 2026-05-21 in commit `7ab25b71`. Added the unmerged-apply gate + filename-vs-main drift probe (the precedent for THIS plan's schema-vs-ledger probe).
  - #4286 — merged in commit `be69fa94`. Added the post-apply PostgREST schema-cache reload (sibling concern, NOT the drift class addressed here).
- Migration runner: `apps/web-platform/scripts/run-migrations.sh`
- Workflow: `.github/workflows/tenant-integration.yml`
- Drift-probe composite action: `.github/actions/dev-migration-drift-probe/action.yml`
- Scheduled drift workflow: `.github/workflows/scheduled-dev-migration-drift.yml`
- Prior learning (filename-vs-main drift class): `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
- Related hard rules: `hr-dev-prd-distinct-supabase-projects`, `hr-menu-option-ack-not-prod-write-auth`, `hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-as-plan-quality-gate`, `cq-pg-security-definer-search-path-pin-pg-temp`, `cq-test-fixtures-synthesized-only`.
- Related workflow gates: `wg-when-a-workflow-gap-causes-a-mistake-fix`, `wg-use-closes-n-in-pr-body-not-title-to`, `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
