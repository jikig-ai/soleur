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
# class, #4241). This preflight checks selected ledgered table presence
# (#4338); neither check proves complete schema equivalence or a safe apply.

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${DATABASE_URL:+x}${DATABASE_URL_POOLER:+x}" ]; then
      printf '[FATAL] refusing to trace database credentials (see #11096)\n' >&2
      exit 78
    fi
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"

# Mirror run-migrations.sh:70 — prefer the IPv4 pooler (CI), fall back
# to the direct connection (developer workstations where DATABASE_URL is
# the only Doppler-injected name). Keeps idiom parity with the runner so
# operators don't trip on inconsistent env-var contracts between scripts.
DATABASE_URL="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"

if [[ -z "$DATABASE_URL" ]]; then
  echo "::error::Neither DATABASE_URL_POOLER nor DATABASE_URL is set. Ensure Doppler injects them."
  exit 1
fi

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "::error::Migrations directory not found: $MIGRATIONS_DIR"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH"; exit 1; }
command -v timeout >/dev/null 2>&1 || { echo "::error::timeout not found on PATH; preflight is unverified."; exit 1; }
SQL_TIMEOUT_SECONDS="${PREFLIGHT_SQL_TIMEOUT_SECONDS:-10}"
if [[ ! "$SQL_TIMEOUT_SECONDS" =~ ^([1-9]|[12][0-9]|30)$ ]]; then
  echo "::error::Invalid preflight SQL timeout; expected 1 to 30 seconds."
  exit 1
fi

run_sql() {
  # Bounds the local client wait, including connection setup. It does not prove
  # that a remote backend stopped after the client was terminated.
  timeout --signal=TERM --kill-after=1s "${SQL_TIMEOUT_SECONDS}s" psql "$DATABASE_URL" --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$1"
}

if ! applied=$(run_sql "SELECT filename FROM public._schema_migrations ORDER BY filename;" 2>/dev/null); then
  echo "::error::Could not read the migration ledger; schema-vs-ledger preflight is unverified."
  exit 1
fi

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
  # Regex assumes the codebase convention: lowercase, `public.`-
  # qualified relation names. Migrations using uppercase keywords
  # (`Create Table`), schema-less `<name>`, or quoted identifiers
  # (`"Public"."Foo"`) bypass this check — the FK parser remains the
  # last line of defense for those shapes.
  if declared_matches=$(grep -oE 'CREATE TABLE (IF NOT EXISTS )?public\.[a-z_][a-z0-9_]*' "$path" 2>/dev/null); then
    grep_rc=0
  else
    grep_rc=$?
  fi
  if [[ "$grep_rc" -gt 1 ]]; then
    echo "::error::Could not inspect a ledgered migration; schema-vs-ledger preflight is unverified."
    exit 1
  fi
  if ! declared_tables=$(printf '%s\n' "$declared_matches" | awk '{print $NF}' 2>/dev/null | sort -u 2>/dev/null); then
    echo "::error::Could not inspect a ledgered migration; schema-vs-ledger preflight is unverified."
    exit 1
  fi
  while IFS= read -r tbl; do
    [[ -z "$tbl" ]] && continue
    # tbl matches public.[a-z_][a-z0-9_]* — regex-bounded; safe for SQL.
    if ! exists=$(run_sql "SELECT to_regclass('$tbl') IS NOT NULL;" 2>/dev/null); then
      echo "::error::Could not verify a ledgered table; schema-vs-ledger preflight is unverified."
      exit 1
    fi
    if [[ "$exists" == "f" ]]; then
      missing+="  - ledger claims $filename applied, but $tbl is missing"$'\n'
    elif [[ "$exists" != "t" ]]; then
      echo "::error::Unexpected ledgered table probe result; schema-vs-ledger preflight is unverified."
      exit 1
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
