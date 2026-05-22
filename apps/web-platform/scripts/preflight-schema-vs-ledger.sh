#!/usr/bin/env bash
# Preflight: schema-vs-ledger consistency check (#4338).
#
# For every `_schema_migrations` row, parse the corresponding local
# migration file for `CREATE TABLE public.<name>` declarations and
# verify each declared table exists in the live schema. Catches the
# drift class where the ledger says "applied" but the schema state
# disagrees, BEFORE the next runner invocation crashes with a cryptic
# "relation does not exist" three layers deep inside a downstream FK
# declaration.
#
# Run via:  doppler run -p soleur -c dev_scheduled -- bash apps/web-platform/scripts/preflight-schema-vs-ledger.sh
# Requires: DATABASE_URL_POOLER environment variable (Doppler-injected).
#
# Orthogonal to the dev-migration-drift-probe composite action: the
# drift probe checks ledger-vs-origin/main (filename + content_sha drift
# class, #4241). This preflight checks ledger-vs-live-schema (the
# #4338 drift class). Both passing is the necessary-and-sufficient
# condition for a safe apply.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"

if [[ -z "${DATABASE_URL_POOLER:-}" ]]; then
  echo "::error::DATABASE_URL_POOLER is not set. Run under 'doppler run -p soleur -c dev_scheduled --'."
  exit 1
fi

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "::error::Migrations directory not found: $MIGRATIONS_DIR"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH"; exit 1; }

run_sql() {
  psql "$DATABASE_URL_POOLER" --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$1"
}

applied=$(run_sql "SELECT filename FROM public._schema_migrations ORDER BY filename;")

missing=""
while IFS= read -r filename; do
  [[ -z "$filename" ]] && continue
  # Filename shape whitelist — same pattern as run-migrations.sh:184.
  # Defense against SQL/shell metacharacters via the dev ledger.
  case "$filename" in
    *[!a-zA-Z0-9._-]*) continue ;;
  esac
  path="$MIGRATIONS_DIR/$filename"
  # Ledger row for a deleted/renamed file → skip (file-rename is out-
  # of-scope for this drift class; the dev-migration-drift-probe action
  # catches that class separately).
  [[ -f "$path" ]] || continue
  declared_tables=$(grep -oE 'CREATE TABLE (IF NOT EXISTS )?public\.[a-z_][a-z0-9_]*' "$path" 2>/dev/null \
    | awk '{print $NF}' | sort -u || true)
  while IFS= read -r tbl; do
    [[ -z "$tbl" ]] && continue
    # tbl matches public.[a-z_][a-z0-9_]* — regex-bounded; safe for SQL.
    exists=$(run_sql "SELECT to_regclass('$tbl') IS NOT NULL;" 2>/dev/null || echo "f")
    if [[ "$exists" != "t" ]]; then
      missing+="  - ledger claims $filename applied, but $tbl is missing"$'\n'
    fi
  done <<<"$declared_tables"
done <<<"$applied"

if [[ -n "$missing" ]]; then
  echo "::error::Schema-vs-ledger drift detected:"
  printf '%s' "$missing" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "::error::$line"
  done
  echo "::error::See knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md for recovery."
  exit 1
fi

echo "Preflight: schema-vs-ledger consistency check passed."
