#!/usr/bin/env bash
# audit-not-null-column-insert-coverage.sh
#
# Catch the migration-059 failure class: a large migration adds a NOT-NULL
# column with NO DB default to an EXISTING table (e.g. `workspace_id`), but one
# or more `.insert()/.upsert()` writers are never updated to set it — so every
# write to that table fails with Postgres 23502 in production, surfacing as a
# silent 500. (The 2026-06-04 "Generate link" outage: `kb_share_links.workspace_id`.)
#
# No SSH, no dashboard: reads the LIVE schema via psql + Doppler-injected
# DATABASE_URL_POOLER (same connection convention as preflight-schema-vs-ledger.sh),
# then greps every `.from("<table>")…insert/upsert` site in the app source and
# flags any whose payload window does not set the column.
#
# Usage (run during migration work AND at ship — see the supabase-migrations
# runbook §"NOT-NULL column insert-site sweep"):
#   doppler run -p soleur -c dev -- bash apps/web-platform/scripts/audit-not-null-column-insert-coverage.sh
#   doppler run -p soleur -c prd -- bash apps/web-platform/scripts/audit-not-null-column-insert-coverage.sh --only workspace_id
#
# Flags:
#   --only <col>   restrict to a single column name (default: every NOT-NULL no-default column)
#
# Exit: 0 = no MISS; 1 = at least one insert/upsert omits a required column.
# REVIEW lines (payload built via a helper/spread/variable we cannot statically
# prove) are printed but do not fail the gate — eyeball them.
#
# LIMITATION (read before trusting a clean run): this is a static grep. It
# reliably catches INLINE writes — `.from("t").insert({ … })` — but CANNOT
# follow helper-indirected handles where `.from("t")` is assigned to a variable
# and the `.insert()` happens elsewhere (the createShare blind spot). Those are
# emitted as REVIEW lines that name the file — you MUST trace each by hand and
# (per the runbook) reproduce one insert against `DATABASE_URL_POOLER` in a
# `BEGIN; … ROLLBACK;` tx to confirm coverage. A clean MISS count is necessary,
# not sufficient. See knowledge-base/.../2026-06-04-migration-not-null-column-insert-sweep.md.
set -uo pipefail

ONLY=""
[[ "${1:-}" == "--only" ]] && ONLY="${2:-}"

DATABASE_URL="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"
if [[ -z "$DATABASE_URL" ]]; then
  echo "::error::Neither DATABASE_URL_POOLER nor DATABASE_URL is set (run under: doppler run -c <env> -- ...)." >&2
  exit 2
fi
command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH" >&2; exit 2; }

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCAN=("$REPO_ROOT/apps/web-platform/server" "$REPO_ROOT/apps/web-platform/app" "$REPO_ROOT/apps/web-platform/lib")

# NOT NULL, no default, not generated/identity, not the DB-populated trio.
WHERE_ONLY=""
[[ -n "$ONLY" ]] && WHERE_ONLY="AND c.column_name = '${ONLY//\'/}'"
SQL="SELECT c.table_name || ' ' || c.column_name
     FROM information_schema.columns c
     WHERE c.table_schema='public'
       AND c.is_nullable='NO'
       AND c.column_default IS NULL
       AND c.is_generated='NEVER'
       AND c.identity_generation IS NULL
       AND c.column_name NOT IN ('id','created_at','updated_at')
       ${WHERE_ONLY}
     ORDER BY 1;"

mapfile -t PAIRS < <(psql "$DATABASE_URL" --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$SQL")

miss=0
for pair in "${PAIRS[@]}"; do
  [[ -z "$pair" ]] && continue
  table="${pair%% *}"; column="${pair##* }"
  # Every `.from("<table>")` line in the app source (excluding tests).
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
    [[ "$file" == *"/test/"* || "$file" == *.test.ts ]] && continue
    # Is there an insert/upsert within 6 lines of this .from()?
    block="$(sed -n "${line},$((line+6))p" "$file")"
    if ! grep -qE "\.(insert|upsert)\(" <<<"$block"; then
      # No inline insert here. If the file assigns/returns this `.from()` to a
      # VARIABLE (helper-indirection — e.g. `const table = client.from("…")`)
      # AND the file has insert/upsert sites elsewhere, a purely-static grep
      # cannot tie them together (this is exactly the createShare blind spot:
      # `from("kb_share_links")` at one line, `table.insert({…})` 130 lines
      # down). Emit a REVIEW so the operator traces those writers by hand.
      if grep -qE "(=|return)\s*[a-zA-Z0-9_.\$]*\.from\(\"${table}\"\)" "$file" \
        && grep -qE "\.(insert|upsert)\(" "$file"; then
        relfile="${file#"$REPO_ROOT"/}"
        echo "REVIEW    ${table}.${column}  ${relfile}:${line}  (helper-indirected table handle — TRACE every .insert/.upsert on it for ${column})"
      fi
      continue
    fi
    voff="$(grep -nE "\.(insert|upsert)\(" <<<"$block" | head -1 | cut -d: -f1)"
    vline=$((line + voff - 1))
    relfile="${file#"$REPO_ROOT"/}"
    # If the insert/upsert argument is a BARE IDENTIFIER (e.g. `.insert(row)`)
    # the payload is built elsewhere (a `buildRow(...)`-style helper) — we
    # cannot statically prove the column, so REVIEW rather than MISS.
    verbarg="$(sed -n "${vline},$((vline+1))p" "$file")"
    if grep -qE "\.(insert|upsert)\(\s*[a-zA-Z_\$][a-zA-Z0-9_\$]*\s*[,)]" <<<"$verbarg"; then
      echo "REVIEW    ${table}.${column}  ${relfile}:${vline}  (payload is a pre-built variable — verify the builder sets ${column})"
      continue
    fi
    # Inline object-literal payload — the column name MUST appear in the window.
    win="$(sed -n "${vline},$((vline+18))p" "$file")"
    if grep -qE "\b${column}\b" <<<"$win"; then
      : # column is set — OK
    elif grep -qE "\.\.\.[a-zA-Z]" <<<"$win"; then
      echo "REVIEW    ${table}.${column}  ${relfile}:${vline}  (payload spreads another object — verify it sets ${column})"
    else
      echo "*** MISS  ${table}.${column}  ${relfile}:${vline}  (insert omits ${column} → 23502 risk)"
      miss=1
    fi
  done < <(grep -rnE "\.from\(\"${table}\"\)" "${SCAN[@]}" --include=*.ts --include=*.tsx 2>/dev/null || true)
done

if [[ "$miss" -eq 0 ]]; then
  echo "OK — every .insert/.upsert to a NOT-NULL-no-default column sets it${ONLY:+ (column=$ONLY)}."
fi
exit "$miss"
