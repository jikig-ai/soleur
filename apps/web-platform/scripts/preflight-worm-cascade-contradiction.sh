#!/usr/bin/env bash
# Preflight: WORM-trigger-vs-cascade-FK contradiction gate (#5372).
#
# Detects the schema contradiction that broke the GDPR Art-17 account-delete
# cascade and reddened `Tenant integration (dev-Supabase)` on main: a table
# with an ON DELETE SET NULL / CASCADE foreign key to public.users that ALSO
# carries a BEFORE UPDATE/DELETE trigger whose function raises (WORM-style
# append-only reject).
#
# WHY THIS IS A CONTRADICTION: deleting a user runs through
# auth.admin.deleteUser, whose FK cascade fires `UPDATE child SET fk=NULL`
# (SET NULL) or `DELETE FROM child` (CASCADE) on the referencing table —
# INSIDE GoTrue's own transaction, where account-delete.ts cannot set the
# `app.worm_bypass` GUC. So a raising BEFORE trigger on that child table
# aborts the whole erasure saga, surfacing as an opaque GoTrue 500
# ("Account deletion failed at auth-delete"). A `app.worm_bypass` carve-out
# does NOT save it — the GUC is never set in GoTrue's cascade transaction.
#
# SEVERITY:
#   STATEMENT-level trigger → ::error:: + exit 1. The cascade UPDATE/DELETE
#     statement fires the trigger even against 0 matching rows, so deletion
#     is broken for EVERY user (this was routine_runs / #5342). Hard fail.
#   ROW-level trigger       → ::warning:: + exit 0. Fires only when the
#     deleted user actually has rows in the child table; account-delete.ts
#     may pre-anonymise them before auth-delete. Latent — surface, don't block.
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

# One query, pipe-delimited: severity|table|trigger|fn|fk|fk_action|level.
# - confdeltype: 'n' = SET NULL (fires child UPDATE), 'c' = CASCADE (fires
#   child DELETE). 'r'/'a'/'d' (RESTRICT/NO ACTION/SET DEFAULT) do not fire a
#   blockable child mutation in the cascade and are intentionally excluded.
# - tgtype bits: &2 = BEFORE, &16 = UPDATE, &8 = DELETE, &1 = ROW (else STMT).
# - Match the trigger event to the cascade's child operation: SET NULL→UPDATE,
#   CASCADE→DELETE.
# - prosrc ILIKE '%RAISE EXCEPTION%' is the WORM heuristic: an unconditional
#   or conditional raise in the trigger body. A trigger that never raises
#   (pure audit/log) does not block the cascade and is not flagged.
SQL=$(cat <<'EOSQL'
SELECT
  CASE WHEN (tg.tgtype & 1) = 0 THEN 'error' ELSE 'warning' END,
  rel.relname,
  tg.tgname,
  fn.proname,
  con.conname,
  -- No ELSE branch: confdeltype is type "char", so an `ELSE con.confdeltype`
  -- would unify the CASE result to "char" and truncate 'SET NULL'->'S'. The
  -- WHERE clause already constrains confdeltype to ('n','c'), so ELSE is dead.
  CASE con.confdeltype WHEN 'n' THEN 'SET NULL' WHEN 'c' THEN 'CASCADE' END,
  CASE WHEN (tg.tgtype & 1) = 0 THEN 'STATEMENT' ELSE 'ROW' END
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
JOIN pg_trigger tg ON tg.tgrelid = con.conrelid AND NOT tg.tgisinternal
JOIN pg_proc fn ON fn.oid = tg.tgfoid
WHERE con.contype = 'f'
  AND con.confrelid = 'public.users'::regclass
  AND con.confdeltype IN ('n', 'c')
  AND (tg.tgtype & 2) = 2
  AND (
        (con.confdeltype = 'n' AND (tg.tgtype & 16) = 16)
     OR (con.confdeltype = 'c' AND (tg.tgtype & 8)  = 8)
      )
  AND fn.prosrc ILIKE '%RAISE EXCEPTION%'
ORDER BY 1, 2, 3;
EOSQL
)

if ! rows=$(run_sql "$SQL"); then
  echo "::error::WORM-cascade contradiction query failed; cannot verify Art-17 deletability."
  exit 1
fi

errors=""
warnings=""
while IFS='|' read -r severity tbl trg fn fk action level; do
  [[ -z "$severity" ]] && continue
  line="public.$tbl — trigger $trg (fn $fn, $level) raises on the $action cascade from FK $fk → public.users"
  if [[ "$severity" == "error" ]]; then
    errors+="$line"$'\n'
  else
    warnings+="$line"$'\n'
  fi
done <<<"$rows"

if [[ -n "$warnings" ]]; then
  echo "::warning::Latent WORM-vs-cascade contradiction(s) — deletion breaks only when the user has rows in these tables (ensure account-delete.ts pre-anonymises them before auth-delete):"
  while IFS= read -r l; do [[ -z "$l" ]] && continue; echo "::warning::  - $l"; done <<<"$warnings"
fi

if [[ -n "$errors" ]]; then
  echo "::error::WORM-vs-cascade contradiction breaks GDPR Art-17 account deletion for ALL users (#5372):"
  while IFS= read -r l; do [[ -z "$l" ]] && continue; echo "::error::  - $l"; done <<<"$errors"
  echo "::error::A STATEMENT-level WORM trigger fires on the FK cascade even against 0 rows, aborting auth.admin.deleteUser as a GoTrue 500."
  echo "::error::Fix: use ON DELETE RESTRICT + pre-anonymise in account-delete.ts (the audit_byok_use pattern), not SET NULL/CASCADE. See issue #5372."
  exit 1
fi

echo "Preflight: WORM-vs-cascade contradiction check passed (no deletion-blocking triggers on users-cascade FKs)."
