#!/usr/bin/env bash
set -euo pipefail

# Automated migration runner for Supabase/PostgreSQL.
# Applies unapplied SQL files from the migrations directory,
# tracking state in a _schema_migrations table.
#
# Usage: doppler run -c prd -- bash run-migrations.sh
# Requires: DATABASE_URL or DATABASE_URL_POOLER environment variable.
#   Prefers DATABASE_URL_POOLER (IPv4 pooler) for CI where IPv6 is unavailable.
# Rollback: See apps/web-platform/docs/migration-rollback.md

# Argument parsing.
# Placed before any side-effects (psql/DATABASE_URL checks) so --help works
# on a fresh checkout without env or psql installed.
# Long-options only, with the `=` form (e.g. `--bootstrap=skip`).
# `--bootstrap skip` (separate token) is not supported and falls through to
# the unknown-arg branch below — keep this constraint in mind when adding
# future flags.
bootstrap_mode="auto"  # auto = legacy bootstrap fires when table empty
verify_mode=""         # --verify: diff tracked vs. filesystem, then exit
for arg in "$@"; do
  case "$arg" in
    --bootstrap=skip) bootstrap_mode="skip" ;;
    --bootstrap=auto) bootstrap_mode="auto" ;;
    --verify) verify_mode="1" ;;
    --help|-h)
      cat <<'USAGE'
Usage: run-migrations.sh [--bootstrap=skip|auto] [--verify]

Applies SQL files from supabase/migrations/ in filename order, tracking state
in public._schema_migrations.

Options:
  --bootstrap=auto   (default) On an empty tracking table, seed sentinel rows
                     for migrations 001-010 (assumed pre-applied on legacy prd).
                     Required for the prd CI migrate job.
  --bootstrap=skip   Disable the bootstrap seed. Use this on first-time
                     provisioning of a fresh Supabase project where 001-010
                     have NOT been applied. All migrations apply in order.
                     Equivalent: BOOTSTRAP_MIGRATIONS=0 bash run-migrations.sh.
  --verify           Diff the _schema_migrations tracking table against the
                     filesystem and exit. Exits 0 if in sync; exits 1 on drift
                     (untracked files or phantom rows). Does NOT apply migrations.
                     Use to detect out-of-band applies (issue #3370) or block CI
                     on ledger drift.
  --help, -h         Print this message and exit.

Environment:
  DATABASE_URL_POOLER     Preferred (IPv4 pooler) for CI.
  DATABASE_URL            Fallback (direct connection, IPv6).
  BOOTSTRAP_MIGRATIONS=0  Same effect as --bootstrap=skip. When set, this
                          OVERRIDES the flag — `BOOTSTRAP_MIGRATIONS=0` plus
                          `--bootstrap=auto` still results in skip mode.
USAGE
      exit 0 ;;
    *)
      echo "::error::Unknown argument: $arg"
      echo "Run with --help for usage."
      exit 2 ;;
  esac
done

# Env-var override: BOOTSTRAP_MIGRATIONS=0 forces skip mode regardless of flag.
# Set when CI/cron callers cannot easily change argv.
if [[ "${BOOTSTRAP_MIGRATIONS:-1}" == "0" ]]; then
  bootstrap_mode="skip"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default to the real dir; tests may override via RUN_MIGRATIONS_TEST_DIR to
# a temp staging dir so they never write transient *.sql into the real
# migrations tree (#4957). The git ls-tree gate (below) intentionally stays
# anchored to the canonical repo path — a temp-dir filename absent from
# origin/main still trips the gate, which is exactly what the gate test
# exercises. A test-scoped var name (not MIGRATIONS_DIR) avoids any collision
# with a same-named secret a future Doppler config might inject via
# `doppler run` in the prod migrate step.
MIGRATIONS_DIR="${RUN_MIGRATIONS_TEST_DIR:-$SCRIPT_DIR/../supabase/migrations}"

command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH"; exit 1; }

# Prefer DATABASE_URL_POOLER (IPv4 pooler) for CI environments where IPv6 is unavailable.
# Falls back to DATABASE_URL (direct connection) for environments with IPv6 support.
DATABASE_URL="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"

if [[ -z "$DATABASE_URL" ]]; then
  echo "::error::Neither DATABASE_URL_POOLER nor DATABASE_URL is set. Ensure Doppler injects them."
  exit 1
fi

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "::error::Migrations directory not found: $MIGRATIONS_DIR"
  exit 1
fi

run_sql() {
  psql "$DATABASE_URL" --no-psqlrc --set ON_ERROR_STOP=1 -tAq -c "$1"
}

# --verify mode (#3370): diff the _schema_migrations tracking table against
# the filesystem and exit without applying anything. Detects two drift classes:
#   untracked — file exists on disk but absent from _schema_migrations (e.g.
#               applied out-of-band via dashboard or `supabase db push`).
#   phantom   — row in _schema_migrations but file no longer on disk.
# Exits 0 on clean; exits 1 on any drift so CI can block on ledger skew.
if [[ "$verify_mode" == "1" ]]; then
  echo "Verifying migration tracking state..."

  run_sql "CREATE TABLE IF NOT EXISTS public._schema_migrations (
    filename TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );"

  tracked_tmp=$(mktemp)
  fs_tmp=$(mktemp)

  # Collect all tracked filenames, sorted for comm.
  run_sql "SELECT filename FROM public._schema_migrations ORDER BY filename;" | sort > "$tracked_tmp"

  # Collect all forward migration filenames from disk, sorted for comm.
  for mig in "$MIGRATIONS_DIR"/*.sql; do
    fn="$(basename "$mig")"
    case "$fn" in *.down.sql) continue ;; esac
    echo "$fn"
  done | sort > "$fs_tmp"

  # comm -23: in filesystem, NOT in tracking table (untracked drift).
  # comm -13: in tracking table, NOT in filesystem (phantom drift).
  untracked=$(comm -23 "$fs_tmp" "$tracked_tmp")
  phantom=$(comm -13 "$fs_tmp" "$tracked_tmp")

  rm -f "$tracked_tmp" "$fs_tmp"

  drift=0
  if [[ -n "$untracked" ]]; then
    drift=1
    echo "::error::Drift detected: migration file(s) on disk NOT tracked in _schema_migrations (applied out-of-band or never applied):"
    while IFS= read -r fn; do
      [[ -z "$fn" ]] && continue
      echo "::error::  untracked: $fn"
    done <<<"$untracked"
    echo "::error::Recovery: INSERT missing filenames into public._schema_migrations (ON CONFLICT DO NOTHING) if already applied out-of-band; otherwise re-run without --verify to apply them."
  fi

  if [[ -n "$phantom" ]]; then
    drift=1
    echo "::error::Drift detected: _schema_migrations row(s) with no corresponding file on disk:"
    while IFS= read -r fn; do
      [[ -z "$fn" ]] && continue
      echo "::error::  phantom: $fn"
    done <<<"$phantom"
    echo "::error::Recovery: DELETE the phantom row(s) from public._schema_migrations if the migration file was intentionally removed."
  fi

  if [[ "$drift" -eq 0 ]]; then
    tracked_count=$(run_sql "SELECT count(*) FROM public._schema_migrations;")
    echo "Verify OK: ${tracked_count} tracked, filesystem in sync."
  else
    echo "::error::Migration tracking drift detected. See above for details. Ref #3370."
    exit 1
  fi
  exit 0
fi

# Create tracking table if it does not exist
run_sql "CREATE TABLE IF NOT EXISTS public._schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);"

echo "Migration tracking table ready."

# Bootstrap: if the tracking table is empty, seed all known pre-existing migrations.
# These were applied manually to production before this runner existed.
# This list is frozen — new migrations are tracked automatically by the runner.
row_count=$(run_sql "SELECT count(*) FROM public._schema_migrations;")
if [[ "$row_count" -eq 0 ]]; then
  if [[ "$bootstrap_mode" == "skip" ]]; then
    echo "Empty tracking table detected — skipping bootstrap (--bootstrap=skip)."
    echo "All migrations will apply in filename order."
  else
    echo "Empty tracking table detected — bootstrapping known migrations..."
    run_sql "INSERT INTO public._schema_migrations (filename) VALUES
      ('001_initial_schema.sql'),
      ('002_add_byok_and_stripe_columns.sql'),
      ('003_fix_encrypted_key_column_type.sql'),
      ('004_add_not_null_iv_auth_tag.sql'),
      ('005_add_tc_accepted_at.sql'),
      ('006_restrict_tc_accepted_at_update.sql'),
      ('007_remediate_fabricated_tc_accepted_at.sql'),
      ('007_remove_tc_accepted_metadata_trust.sql'),
      ('008_add_tc_accepted_version.sql'),
      ('009_byok_hkdf_per_user_keys.sql'),
      ('010_tag_and_route.sql')
    ON CONFLICT (filename) DO NOTHING;"
    echo "Bootstrapped pre-existing migrations."
  fi
fi

# Refresh origin/main once so the unmerged-apply gate below (issue #4241)
# reads a current `git ls-tree`. Tolerate offline; emit a visible warning so
# a stale ref does not silently route every file through the ack-bypass path.
if ! git fetch --quiet origin main 2>/tmp/run-migrations-fetch.err; then
  echo "::warning::git fetch origin main failed (see /tmp/run-migrations-fetch.err); unmerged-apply gate may produce false positives."
fi

# Same-integer-prefix collision check (#4241 follow-up). The convention is
# "one forward migration per integer prefix"; the runner is filename-keyed,
# so two distinct `NNN_*.sql` files coexist as separate `_schema_migrations`
# rows and apply in alphabetical order — order set by accident, not
# convention. Severity is `::warning::` (not `::error::`) because main today
# already carries one pre-existing collision (053_append_kb_sync_row_rpc.sql
# from PR-H #4066 vs 053_template_authorizations.sql from PR-I #4213) that
# the runner has been tolerating since both merged; failing here would block
# every dev/prd apply until the collision is renumbered, which is its own
# follow-up. The warning surfaces the convention violation at every apply so
# the next reviewer who notices it can schedule the renumber.
collision_check=$(find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -not -name '*.down.sql' -printf '%f\n' \
  | awk -F'_' '{print $1}' \
  | sort \
  | uniq -d)
if [[ -n "$collision_check" ]]; then
  echo "::warning::Migration filename prefix collision detected. Convention is one forward migration per integer prefix; renumber-on-rebase before adding a new collider."
  while IFS= read -r prefix; do
    [[ -z "$prefix" ]] && continue
    echo "::warning::  prefix '$prefix' is shared by:"
    find "$MIGRATIONS_DIR" -maxdepth 1 -name "${prefix}_*.sql" -not -name '*.down.sql' -printf '::warning::    - %f\n'
  done <<<"$collision_check"
fi

# Apply unapplied migrations in sorted order
applied=0
skipped=0

for migration_file in "$MIGRATIONS_DIR"/*.sql; do
  filename="$(basename "$migration_file")"

  # Skip down-migration artifacts. These are manual-rollback files (e.g.,
  # `053_template_authorizations.down.sql`) — they live alongside the
  # forward migration for paired-edit visibility but MUST NOT be applied
  # during forward runs. Bash glob expansion sorts `.down.sql` BEFORE
  # `.sql` (`.d` < `.s` lexically), so without this skip, a down file
  # whose first statement targets an as-yet-uncreated relation (e.g.,
  # `DROP TRIGGER ... ON public.<table>`) fails before the corresponding
  # `.sql` runs. **Why:** PR-I (#4213) — mig 053 down file led with
  # `DROP TRIGGER ... ON public.template_authorizations`; the dev apply
  # job failed with "relation does not exist" because `.down.sql` was
  # applied first. Mig 051's down file did not trip the same gate
  # because its first statement is `CREATE OR REPLACE FUNCTION
  # grant_action_class(...)` which is no-op-friendly against the prior
  # mig-048 grant function. Filter at the glob level so the runner is
  # independent of down-file shape.
  case "$filename" in
    *.down.sql) continue ;;
  esac

  # Filename shape whitelist — defense in depth for the SQL literal interpolations
  # below and the `git ls-tree` path interpolation in the unmerged-apply gate.
  # The *.sql glob does NOT exclude quotes, newlines, backslashes, or path-
  # traversal sequences in filenames; an attacker with repo-write would otherwise
  # have a small SQL-injection surface against the dev-only `_schema_migrations`
  # table via crafted migration filenames.
  case "$filename" in
    *[!a-zA-Z0-9._-]*)
      echo "::error::Migration filename contains unsupported characters: $filename"
      exit 1 ;;
  esac

  # Unmerged-apply gate (#4241). Block apply of migration filenames that are
  # not on origin/main unless the operator explicitly acks with
  # ALLOW_UNMERGED_DEV_APPLY=1. Closes the dev-vs-main drift class that broke
  # `Tenant integration (dev-Supabase)` on 2026-05-21 when migrations 053-057
  # from an unmerged branch were applied to dev. `git ls-tree origin/main`
  # reads the local fetch (refreshed once before the loop above). The opt-in
  # env var is a local-iteration valve: dev is unshared and synthetic-only per
  # hr-dev-prd-distinct-supabase-projects, so the ack here prevents leave-behind
  # drift rather than authorising a destructive prd write (distinct from the
  # prd-only ack class governed by hr-menu-option-ack-not-prod-write-auth).
  if [[ -z "$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename" 2>/dev/null)" ]]; then
    if [[ "${ALLOW_UNMERGED_DEV_APPLY:-0}" != "1" ]]; then
      echo "::error::Migration $filename is NOT on origin/main. Applying unmerged migrations to dev creates dev-vs-main drift (precedent: #4241). To override locally, re-run with ALLOW_UNMERGED_DEV_APPLY=1 and revert the dev schema before pushing — see knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md."
      exit 1
    fi
    echo "::warning::$filename is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1."

    # Cross-branch collision warning (#4225 follow-up). The file just passed
    # the unmerged-apply gate under ALLOW_UNMERGED_DEV_APPLY=1 — surface
    # whether origin/main already carries DIFFERENT file(s) at the same
    # numeric prefix. That class fires when a sibling PR landed a same-
    # numbered migration to main WHILE this branch was in flight (the
    # actual #4225 → #4251 failure mode: branch's 054_workspace_member_
    # attestations was in flight when main landed 054_schema_migrations_
    # content_sha). The local same-prefix warning earlier in the script
    # only fires AFTER rebase; this inline surface catches the gap when
    # the operator applies BEFORE rebasing (direct-pg fallback, manual
    # psql, anything that bypasses this script's discipline).
    #
    # Severity is ::warning:: (not ::error::) to match the pre-loop
    # same-prefix tolerance — the 053-class triple-add (PR-H + PR-I +
    # this branch) is by-design and would otherwise block every CI run
    # for any future PR adding a sibling-prefix migration. The warning
    # is the load-bearing signal: operator who sees it in their CI log
    # has the chance to renumber before merge. See learning
    # 2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md
    # §3 "Parallel-branch migration coordination" for the rename +
    # `public._schema_migrations` reconcile recovery pattern.
    file_prefix=$(printf '%s' "$filename" | awk -F'_' '{print $1}')
    if [[ "$file_prefix" =~ ^[0-9]{3}$ ]]; then
      main_with_prefix=$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/" 2>/dev/null \
        | awk '{print $NF}' \
        | xargs -I{} basename {} \
        | grep -E "^${file_prefix}_[^.]+\.sql$" \
        | grep -v '\.down\.sql$' \
        | grep -v "^${filename}$" || true)
      if [[ -n "$main_with_prefix" ]]; then
        echo "::warning::Cross-branch migration filename collision: branch '${filename}' shares prefix ${file_prefix} with origin/main file(s). Renumber the branch's collider to the next free prefix before merge (typical pattern: 054→058, 055→059, …) to avoid the tracking-table reconcile recovery class."
        # printf '%s\n' (NOT '%s') so the final coexists-with line is newline-
        # terminated — without the trailing newline, the next iteration's
        # ::warning::… line glues onto the same line and a regex looking for
        # `<prior-file>.*is not on origin/main` matches across the boundary
        # (broke run-migrations-unmerged-gate.test.ts positive-control case).
        printf '%s\n' "$main_with_prefix" | sed 's/^/::warning::  coexists-with: /'
      fi
    fi
  fi

  # Filenames are from a controlled glob (*.sql) AND have passed the shape
  # whitelist above — safe for direct interpolation.
  already_applied=$(run_sql "SELECT count(*) FROM public._schema_migrations WHERE filename = '$filename';")
  if [[ "$already_applied" -gt 0 ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  # Schema-presence probe (#4338). Before applying a migration, extract
  # the `REFERENCES public.<table>` mentions from its body, SUBTRACT the
  # tables the same file CREATEs, and confirm each remaining cross-file
  # dependency exists in the live schema. Catches the schema-vs-ledger
  # drift class (ledger says applied, schema disagrees) one migration
  # earlier than the FK parser, with an error message that names the
  # missing relation and links to the recovery learning.
  #
  # SUBTRACTING same-file CREATEs is load-bearing: migration 053 creates
  # public.workspaces AND has an FK to it (workspace_members.workspace_id).
  # Without the subtraction, a fresh-DB first-apply of 053 would fail the
  # probe because the table doesn't yet exist when the probe runs — but
  # it will exist immediately after 053's body executes. Self-references
  # are the canonical FK pattern within a single migration; the probe
  # must only catch CROSS-FILE dependencies.
  #
  # Best-effort: default-on. Opt out with MIGRATION_SCHEMA_PRECONDITION_PROBE=0
  # to fall back to the FK parser as the only line of defense. The FK
  # parser remains the last line of defense regardless of probe state for
  # dependency shapes the regex can't see (dynamic SQL, function-body
  # SELECTs, view dependencies, etc.). Default-on per #4325 follow-up:
  # CI was already setting "=1" in tenant-integration.yml; this brings
  # operator-local invocations to parity.
  if [[ "${MIGRATION_SCHEMA_PRECONDITION_PROBE:-1}" == "1" ]]; then
    # Regex assumes the codebase convention: uppercase DDL keywords,
    # lowercase + `public.`-qualified relation names. Shapes outside
    # that convention (lowercase `references`, schema-less `<name>`,
    # quoted `"public"."Foo"`, dynamic `EXECUTE format(...)`) bypass
    # this probe; the FK parser remains the last line of defense.
    referenced_tables=$(grep -oE 'REFERENCES public\.[a-z_][a-z0-9_]*' "$migration_file" 2>/dev/null \
      | awk '{print $2}' \
      | sort -u || true)
    same_file_creates=$(grep -oE 'CREATE TABLE (IF NOT EXISTS )?public\.[a-z_][a-z0-9_]*' "$migration_file" 2>/dev/null \
      | awk '{print $NF}' \
      | sort -u || true)
    # comm -23: lines in referenced_tables NOT in same_file_creates.
    # Both inputs are pre-sorted; sed strips blank lines so comm
    # doesn't error on empty input.
    cross_file_deps=$(comm -23 \
      <(printf '%s\n' "$referenced_tables" | sed '/^$/d') \
      <(printf '%s\n' "$same_file_creates" | sed '/^$/d') 2>/dev/null || true)
    missing_tables=""
    while IFS= read -r tbl; do
      [[ -z "$tbl" ]] && continue
      exists=$(run_sql "SELECT to_regclass('$tbl') IS NOT NULL;" 2>/dev/null || echo "f")
      if [[ "$exists" != "t" ]]; then
        missing_tables+="$tbl "
      fi
    done <<<"$cross_file_deps"
    if [[ -n "$missing_tables" ]]; then
      echo "::error::Migration $filename references tables that do not exist in the live schema: $missing_tables"
      echo "::error::This indicates a schema-vs-ledger drift on this Supabase project — the _schema_migrations ledger claims the parent migration(s) are applied, but the schema disagrees."
      echo "::error::See knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md for the recovery procedure (delete the stale ledger rows; the runner re-applies the parent migrations on the next CI run)."
      exit 1
    fi
  fi

  echo "Applying: $filename"
  # Compute the git blob SHA-1 of the file body so the drift probe can detect
  # same-filename content drift (mig 054 adds the content_sha column to
  # _schema_migrations). Same hash space as `git ls-tree origin/main`'s third
  # column. Mig 054 is itself the first row to carry content_sha; pre-054 rows
  # stay NULL by design (no apply-time history to retroactively populate).
  content_sha=$(git hash-object "$migration_file" 2>/dev/null || echo "")
  if [[ -z "$content_sha" ]]; then
    # Fall back to sha1sum on systems without git available (no git is a
    # broken state for this runner, but the script should still complete the
    # apply — drift probe just won't have content_sha to compare).
    content_sha=$(sha1sum "$migration_file" 2>/dev/null | awk '{print $1}' || echo "")
  fi
  # Apply migration and record it in a single atomic transaction. The INSERT
  # row carries content_sha when known; NULL otherwise (column is nullable).
  if ! {
    cat "$migration_file"
    if [[ -n "$content_sha" ]]; then
      printf "\nINSERT INTO public._schema_migrations (filename, content_sha) VALUES ('%s', '%s');\n" "$filename" "$content_sha"
    else
      printf "\nINSERT INTO public._schema_migrations (filename) VALUES ('%s');\n" "$filename"
    fi
  } | psql "$DATABASE_URL" --no-psqlrc --single-transaction --set ON_ERROR_STOP=1; then
    echo "::error::Migration failed: $filename"
    exit 1
  fi
  echo "  Applied successfully."
  applied=$((applied + 1))
done

echo "Migration run complete: $applied applied, $skipped skipped."

# Post-apply: force a PostgREST schema-cache reload via the Supabase
# Management API (issue #4285). Direct-pg apply paths through the IPv4
# session-mode pooler cannot deliver NOTIFY to PostgREST's LISTEN — every
# supabase-js call against a freshly-added table returns PGRST205 until
# PostgREST's natural ~10-min schema poll. The Management-API path runs
# the NOTIFY on a backend that shares process identity with PostgREST's
# listener, so the reload actually fires. `--best-effort` ensures a
# missing SUPABASE_PAT or any transient upstream error never fails the
# migration run. See learning 2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md §Prevention #5.
if [[ "$applied" -gt 0 ]]; then
  # The hook is --best-effort: any non-zero exit it returns is itself a bug
  # in the script (best-effort always exits 0). Surface that case as an
  # attributable GHA annotation rather than swallowing with `|| true`, which
  # would erase even the inner ::warning:: from this step's log context and
  # make downstream PGRST205 test flakes hard to trace.
  if ! bash "$SCRIPT_DIR/postgrest-reload-schema.sh" --best-effort; then
    echo "::warning title=PostgREST schema reload hook failed::Migration applied OK; supabase-js may return PGRST205 for up to ~10 min until natural PostgREST poll. Re-run apps/web-platform/scripts/postgrest-reload-schema.sh manually if tests fail."
  fi
fi
