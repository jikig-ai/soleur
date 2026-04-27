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
for arg in "$@"; do
  case "$arg" in
    --bootstrap=skip) bootstrap_mode="skip" ;;
    --bootstrap=auto) bootstrap_mode="auto" ;;
    --help|-h)
      cat <<'USAGE'
Usage: run-migrations.sh [--bootstrap=skip|auto]

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
MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"

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

# Apply unapplied migrations in sorted order
applied=0
skipped=0

for migration_file in "$MIGRATIONS_DIR"/*.sql; do
  filename="$(basename "$migration_file")"

  # Filenames are from a controlled glob (*.sql) — safe for direct interpolation.
  already_applied=$(run_sql "SELECT count(*) FROM public._schema_migrations WHERE filename = '$filename';")
  if [[ "$already_applied" -gt 0 ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  echo "Applying: $filename"
  # Apply migration and record it in a single atomic transaction
  if ! {
    cat "$migration_file"
    printf "\nINSERT INTO public._schema_migrations (filename) VALUES ('%s');\n" "$filename"
  } | psql "$DATABASE_URL" --no-psqlrc --single-transaction --set ON_ERROR_STOP=1; then
    echo "::error::Migration failed: $filename"
    exit 1
  fi
  echo "  Applied successfully."
  applied=$((applied + 1))
done

echo "Migration run complete: $applied applied, $skipped skipped."
