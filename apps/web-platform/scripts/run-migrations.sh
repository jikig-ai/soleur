#!/usr/bin/env bash
set -euo pipefail

# Automated migration runner for Supabase/PostgreSQL.
# Applies unapplied SQL files from the migrations directory,
# tracking state in a _schema_migrations table.
#
# Usage: doppler run -c prd -- bash run-migrations.sh
# Requires: DATABASE_URL environment variable (PostgreSQL connection string)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"

command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH"; exit 1; }

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "::error::DATABASE_URL is not set. Ensure Doppler injects it."
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

# Apply unapplied migrations in sorted order
applied=0
skipped=0

for migration_file in "$MIGRATIONS_DIR"/*.sql; do
  filename="$(basename "$migration_file")"

  already_applied=$(psql "$DATABASE_URL" --no-psqlrc --set ON_ERROR_STOP=1 -tAq \
    -v fname="$filename" \
    -c "SELECT count(*) FROM public._schema_migrations WHERE filename = :'fname';")
  if [[ "$already_applied" -gt 0 ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  echo "Applying: $filename"
  # Apply migration and record it in a single atomic transaction
  {
    cat "$migration_file"
    printf "\nINSERT INTO public._schema_migrations (filename) VALUES (:'fname');\n"
  } | psql "$DATABASE_URL" --no-psqlrc --single-transaction --set ON_ERROR_STOP=1 \
      -v fname="$filename"

  if [[ $? -ne 0 ]]; then
    echo "::error::Migration failed: $filename"
    exit 1
  fi
  echo "  Applied successfully."
  applied=$((applied + 1))
done

echo "Migration run complete: $applied applied, $skipped skipped."
