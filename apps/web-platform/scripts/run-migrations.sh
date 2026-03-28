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

run_sql_file() {
  psql "$DATABASE_URL" --no-psqlrc --single-transaction --set ON_ERROR_STOP=1 -f "$1"
}

# Create tracking table if it does not exist
run_sql "CREATE TABLE IF NOT EXISTS public._schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);"

echo "Migration tracking table ready."

# Bootstrap: if the tracking table is empty, seed all known pre-existing migrations.
# These were applied manually to production before this runner existed.
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
    ('010_tag_and_route.sql');"
  echo "Bootstrapped 11 pre-existing migrations."
fi

# Apply unapplied migrations in sorted order
applied=0
skipped=0

for migration_file in "$MIGRATIONS_DIR"/*.sql; do
  filename="$(basename "$migration_file")"

  already_applied=$(run_sql "SELECT count(*) FROM public._schema_migrations WHERE filename = '$filename';")
  if [[ "$already_applied" -gt 0 ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  echo "Applying: $filename"
  run_sql_file "$migration_file"

  run_sql "INSERT INTO public._schema_migrations (filename) VALUES ('$filename');"
  echo "  Applied successfully."
  applied=$((applied + 1))
done

echo "Migration run complete: $applied applied, $skipped skipped."
