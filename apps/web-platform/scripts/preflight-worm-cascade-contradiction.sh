#!/usr/bin/env bash
# Preflight: WORM-trigger-vs-cascade-FK contradiction gate (#5372).
#
# Detects the schema contradiction that broke the GDPR Art-17 account-delete
# cascade and reddened `Tenant integration (dev-Supabase)` on main: a table
# with an ON DELETE SET NULL / CASCADE foreign key to public.users that ALSO
# carries a raising UPDATE/DELETE trigger (WORM-style append-only reject).
#
# WHY THIS IS A CONTRADICTION: deleting a user runs through
# auth.admin.deleteUser, whose FK cascade fires `UPDATE child SET fk=NULL`
# (SET NULL) or `DELETE FROM child` (CASCADE) on the referencing table —
# INSIDE GoTrue's own transaction, where account-delete.ts cannot set the
# `app.worm_bypass` GUC. So a raising trigger on that child table aborts the
# whole erasure saga, surfacing as an opaque GoTrue 500 ("Account deletion
# failed at auth-delete"). A `app.worm_bypass` carve-out does NOT save it —
# the GUC is never set in GoTrue's cascade transaction.
#
# SEVERITY (two axes — trigger level AND per-ref ownership):
#   STATEMENT-level trigger → breaks deletion for EVERY user (the cascade
#     UPDATE/DELETE statement fires the trigger even against 0 matching rows;
#     this was routine_runs / #5342). Hard class.
#   ROW-level trigger → breaks only when the deleted user actually has rows in
#     the child table; account-delete.ts may pre-anonymise them before
#     auth-delete. Latent class → always ::warning::.
#
#   Per-ref ownership gate (CRITICAL — prevents shared-dev false-red on main):
#   the dev project is SHARED; every open migration-PR applies its in-flight
#   migrations to dev via ALLOW_UNMERGED_DEV_APPLY=1 and leaves them there. So
#   a STATEMENT-level contradiction can sit on the LIVE dev schema as a
#   leave-behind from ANOTHER ref (e.g. #5342's routine_runs) even though the
#   CURRENT checkout's migrations are clean. Blocking unconditionally would red
#   main on every other PR's leave-behind — the exact failure the orphan-drift
#   blocking gate was rejected for. So a STATEMENT-level contradiction is a
#   blocking ::error:: ONLY when the offending table is OWNED by a migration in
#   the CURRENT checkout (the table name appears in supabase/migrations/*.sql on
#   this ref). A leave-behind from another ref is downgraded to ::warning::.
#   Net effect: #5342's own CI fails (it owns routine_runs); main and unrelated
#   PRs stay green; a genuinely-merged bad migration on main still errors
#   (main owns it).
#
# HEURISTIC LIMITATION (the backstop): "raising trigger" is detected via
# `prosrc ILIKE '%RAISE EXCEPTION%' OR ILIKE '%ASSERT %'`. The codebase WORM
# convention uniformly uses literal `RAISE EXCEPTION` (verified across
# migrations), so this is sound today. A future trigger that aborts via a bare
# `RAISE;` re-raise, a raise inside a PERFORM-ed helper, or a non-literal
# sqlstate raise would slip past THIS gate — the end-to-end minimal-user
# deleteAccount regression test (account-delete.cascade.integration.test.ts)
# is the behavioural backstop that catches any raise idiom. This gate is a
# fail-fast NAMED-relation early-warning, not a complete proof of deletability.
#
# THE CONVENTION THIS ENFORCES: WORM tables that reference users must use
# ON DELETE RESTRICT and be pre-anonymised in account-delete.ts before
# auth-delete (the audit_byok_use / workspace_member_actions pattern), never
# SET NULL / CASCADE.
#
# Run via:  doppler run -p soleur -c dev_scheduled -- bash apps/web-platform/scripts/preflight-worm-cascade-contradiction.sh
# Requires: DATABASE_URL_POOLER (Doppler-injected). Runs after migrations are
# applied (scans the LIVE schema), before the tenant-isolation test step, so a
# poisoned schema fails fast with a NAMED relation instead of a 500.
#
# Orthogonal to dev-migration-drift-probe (ledger-vs-origin/main, #4241) and
# preflight-schema-vs-ledger (ledger-vs-live-schema, #4338): this gate checks a
# behavioural schema invariant (deletability), independent of the ledger.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Overridable for tests; defaults to this repo's migrations dir on the checkout.
MIGRATIONS_DIR="${MIGRATIONS_DIR_OVERRIDE:-$SCRIPT_DIR/../supabase/migrations}"

# Mirror run-migrations.sh:70 / preflight-schema-vs-ledger.sh:30 — prefer the
# IPv4 pooler (CI), fall back to the direct connection (workstations).
DATABASE_URL="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"

if [[ -z "$DATABASE_URL" ]]; then
  echo "::error::Neither DATABASE_URL_POOLER nor DATABASE_URL is set. Ensure Doppler injects them."
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH"; exit 1; }

run_sql() {
  psql "$DATABASE_URL" --no-psqlrc -tAq --set ON_ERROR_STOP=1 -F '|' -c "$1"
}

# True when the current checkout's migrations manage this table (its name
# appears in any local migration file) — i.e. the offending object is OWNED by
# this ref, not a shared-dev leave-behind from another open PR.
owned_by_ref() {
  local tbl="$1"
  # tbl comes from pg_catalog relname: [a-z_][a-z0-9_]* — safe for regex.
  grep -qE "\b${tbl}\b" "$MIGRATIONS_DIR"/*.sql 2>/dev/null
}

# One query, pipe-delimited: severity|table|trigger|fn|fk|fk_action|level|timing.
# - confdeltype: 'n' = SET NULL (fires child UPDATE), 'c' = CASCADE (fires
#   child DELETE). 'r'/'a'/'d' (RESTRICT/NO ACTION/SET DEFAULT) do not fire a
#   blockable child mutation in the cascade and are intentionally excluded.
# - tgtype bits: &16 = UPDATE, &8 = DELETE, &1 = ROW (else STATEMENT),
#   &2 = BEFORE (else AFTER). BEFORE *and* AFTER raising triggers both abort the
#   cascade transaction, so timing is NOT filtered — only reported.
# - Match the trigger event to the cascade's child operation: SET NULL→UPDATE,
#   CASCADE→DELETE.
# - prosrc heuristic: an unconditional or conditional RAISE EXCEPTION / ASSERT
#   in the trigger body. A trigger that never aborts (pure audit/log via
#   RAISE LOG/NOTICE) does not block the cascade and is not flagged.
SQL=$(cat <<'EOSQL'
SELECT
  -- No ELSE branch on the CASE below: confdeltype is type "char", so an
  -- `ELSE con.confdeltype` would unify the CASE result to "char" and truncate
  -- 'SET NULL'->'S'. The WHERE clause constrains confdeltype to ('n','c'), so
  -- ELSE is dead.
  CASE WHEN (tg.tgtype & 1) = 0 THEN 'error' ELSE 'warning' END,
  rel.relname,
  tg.tgname,
  fn.proname,
  con.conname,
  CASE con.confdeltype WHEN 'n' THEN 'SET NULL' WHEN 'c' THEN 'CASCADE' END,
  CASE WHEN (tg.tgtype & 1) = 0 THEN 'STATEMENT' ELSE 'ROW' END,
  CASE WHEN (tg.tgtype & 2) = 2 THEN 'BEFORE' ELSE 'AFTER' END
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
JOIN pg_trigger tg ON tg.tgrelid = con.conrelid AND NOT tg.tgisinternal
JOIN pg_proc fn ON fn.oid = tg.tgfoid
WHERE con.contype = 'f'
  AND con.confrelid = 'public.users'::regclass
  AND con.confdeltype IN ('n', 'c')
  AND (
        (con.confdeltype = 'n' AND (tg.tgtype & 16) = 16)
     OR (con.confdeltype = 'c' AND (tg.tgtype & 8)  = 8)
      )
  AND (fn.prosrc ILIKE '%RAISE EXCEPTION%' OR fn.prosrc ILIKE '%ASSERT %')
ORDER BY 1, 2, 3;
EOSQL
)

if ! rows=$(run_sql "$SQL"); then
  echo "::error::WORM-cascade contradiction query failed; cannot verify Art-17 deletability."
  exit 1
fi

errors=""
warnings=""
while IFS='|' read -r severity tbl trg fn fk action level timing; do
  [[ -z "$severity" ]] && continue
  line="public.$tbl — trigger $trg (fn $fn, $level $timing) raises on the $action cascade from FK $fk → public.users"
  if [[ "$severity" == "error" ]]; then
    # Per-ref ownership gate: block only when THIS checkout owns the table.
    if owned_by_ref "$tbl"; then
      errors+="$line"$'\n'
    else
      warnings+="$line (leave-behind from another ref — not owned by this checkout; warning only)"$'\n'
    fi
  else
    warnings+="$line"$'\n'
  fi
done <<<"$rows"

if [[ -n "$warnings" ]]; then
  echo "::warning::Latent or out-of-ref WORM-vs-cascade contradiction(s) — deletion breaks only when the user has rows in these tables, or the table belongs to another open migration-PR (ensure account-delete.ts pre-anonymises before auth-delete; the owning PR must fix its migration):"
  while IFS= read -r l; do [[ -z "$l" ]] && continue; echo "::warning::  - $l"; done <<<"$warnings"
fi

if [[ -n "$errors" ]]; then
  echo "::error::WORM-vs-cascade contradiction breaks GDPR Art-17 account deletion for ALL users (#5372):"
  while IFS= read -r l; do [[ -z "$l" ]] && continue; echo "::error::  - $l"; done <<<"$errors"
  echo "::error::A STATEMENT-level WORM trigger fires on the FK cascade even against 0 rows, aborting auth.admin.deleteUser as a GoTrue 500."
  echo "::error::Fix: use ON DELETE RESTRICT + pre-anonymise in account-delete.ts (the audit_byok_use pattern), not SET NULL/CASCADE. See issue #5372."
  exit 1
fi

echo "Preflight: WORM-vs-cascade contradiction check passed (no deletion-blocking triggers owned by this ref on users-cascade FKs)."
