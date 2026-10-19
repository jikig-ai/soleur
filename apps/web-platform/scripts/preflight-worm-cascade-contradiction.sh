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
# auth-delete (the workspace_member_actions pattern), never SET NULL /
# CASCADE — OR the second sanctioned pattern: ON DELETE SET NULL plus a
# row-level `col NOT NULL -> NULL` carve-out inside the WORM trigger
# (the audit_byok_use founder_id shape, mig 066; dsar_export_audit_pii
# user_id, mig 160; action_sends.message_id, mig 162 — the last two
# additionally bind the transition to a deleted parent via NOT EXISTS).
# Honest limit: this gate's `prosrc ILIKE '%RAISE EXCEPTION%'` heuristic
# cannot distinguish the carved-out form, so it emits a permanent
# ::warning:: for those rows — expected residue, not a live contradiction.
#
# #10379 ENVELOPE EXTENSION — the census no longer scans only FKs to
# public.users. It computes the user-erasure DELETE CONE (a recursive CTE
# rooted at auth.users + public.users, propagating through CASCADE edges
# only — only CASCADE propagates row deletion; UNION dedup terminates FK
# cycles) and classifies EVERY FK on EVERY WORM-gated table into four
# classes:
#   cone-refuse    RESTRICT/NO ACTION ('r'/'a') FK to an IN-CONE non-users
#                  parent — the #10254 wedge class: the cascade delete of
#                  the parent is REFUSED (23503) inside GoTrue's
#                  transaction. No in-schema carve-out exists for an FK
#                  refusal (no child mutation is attempted), so this is
#                  ::error:: when owned — at ANY trigger level.
#   cone-write-stmt write-firing ('n'/'c'/'d') FK to an in-cone parent
#                  with a STATEMENT-level raising trigger matched on the
#                  event — ::error:: when owned (today's hard class).
#   cone-write-row write-firing FK to an in-cone parent with a ROW-level
#                  raising trigger — ::warning:: (carve-out residue can be
#                  legitimate; the heuristic cannot see it).
#   dormant        FK to an OUT-OF-CONE parent — no contradiction today,
#                  but the anchor wedges the day the parent gains a delete
#                  path (or joins the cone): ::warning:: naming the parent.
# Silently excluded: confrelid ∈ {public.users, auth.users} with 'r'/'a'
# — the sanctioned RESTRICT+pre-anonymise shape.
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

# One query, pipe-delimited: class|table|trigger|fn|fk|fk_action|level|timing|parent.
# - confdeltype: 'n' = SET NULL and 'd' = SET DEFAULT (both fire child
#   UPDATE), 'c' = CASCADE (fires child DELETE), 'r'/'a' = RESTRICT /
#   NO ACTION (refuse the parent delete — no child mutation is attempted,
#   so no trigger-level carve-out can ever admit them: ruled fail-closed
#   per CTO 2026-10-19). 'd' groups with the write-firing actions — it is
#   a real child write, not a refusal (the prior comment lumped it with
#   'r'/'a' was wrong).
# - tgtype bits: &16 = UPDATE, &8 = DELETE, &1 = ROW (else STATEMENT),
#   &2 = BEFORE (else AFTER). BEFORE *and* AFTER raising triggers both abort
#   the cascade transaction, so timing is NOT filtered — only reported.
# - Action↔event matching is load-bearing: 'n'/'d'→UPDATE (&16),
#   'c'→DELETE (&8). 'r'/'a' need no event match — the refusal aborts on
#   the PARENT delete regardless of trigger; the trigger's presence just
#   marks the table WORM-gated.
# - DISTINCT ON (con.oid) dedupes per-FK across multi-trigger tables,
#   preferring STATEMENT rows (worst-case severity wins).
# - prosrc heuristic: an unconditional or conditional RAISE EXCEPTION /
#   ASSERT in the trigger body. A trigger that never aborts (pure
#   audit/log via RAISE LOG/NOTICE) does not block and is not flagged.
SQL=$(cat <<'EOSQL'
WITH RECURSIVE del(rel) AS (
  SELECT 'auth.users'::regclass
  UNION SELECT 'public.users'::regclass
  UNION
  SELECT con.conrelid
  FROM pg_constraint con
  JOIN del ON con.confrelid = del.rel
  WHERE con.confdeltype = 'c'
)
SELECT DISTINCT ON (con.oid)
  CASE
    WHEN con.confdeltype IN ('r','a') AND prel.oid IN (SELECT rel FROM del)
      THEN 'cone-refuse'
    WHEN con.confdeltype IN ('n','c','d') AND prel.oid IN (SELECT rel FROM del)
         AND (tg.tgtype & 1) = 0
      THEN 'cone-write-stmt'
    WHEN con.confdeltype IN ('n','c','d') AND prel.oid IN (SELECT rel FROM del)
      THEN 'cone-write-row'
    ELSE 'dormant'
  END AS class,
  rel.relname,
  tg.tgname,
  fn.proname,
  con.conname,
  CASE con.confdeltype
    WHEN 'n' THEN 'SET NULL'
    WHEN 'c' THEN 'CASCADE'
    WHEN 'd' THEN 'SET DEFAULT'
    WHEN 'r' THEN 'RESTRICT'
    WHEN 'a' THEN 'NO ACTION'
  END AS action,
  CASE WHEN (tg.tgtype & 1) = 0 THEN 'STATEMENT' ELSE 'ROW' END AS level,
  CASE WHEN (tg.tgtype & 2) = 2 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
  ns.nspname || '.' || prel.relname AS parent
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
JOIN pg_class prel ON prel.oid = con.confrelid
JOIN pg_namespace ns ON ns.oid = prel.relnamespace
JOIN pg_trigger tg ON tg.tgrelid = con.conrelid AND NOT tg.tgisinternal
JOIN pg_proc fn ON fn.oid = tg.tgfoid
WHERE con.contype = 'f'
  -- WORM-gated tables only: a raising UPDATE/DELETE trigger exists. The
  -- event match fires for write actions; 'r'/'a' rows match any raising
  -- UPDATE/DELETE trigger on the table (marker, not event).
  -- Column-scoping is load-bearing: a BEFORE UPDATE OF <cols> trigger
  -- fires only when a listed column changes, and the RI SET NULL/SET
  -- DEFAULT write touches only the FK columns (con.conkey). Empty tgattr
  -- = unscoped trigger (fires on every column). Without this clause the
  -- mig-162 residue (action_sends.message_id SET NULL, whose statement
  -- trigger lists 11 columns EXCLUDING message_id) false-flags
  -- cone-write-stmt — caught by the live census before merge.
  AND (
        (con.confdeltype IN ('n','d') AND (tg.tgtype & 16) = 16
         AND (
           tg.tgattr = ''::int2vector
           OR EXISTS (
             SELECT 1 FROM unnest(con.conkey) AS ck(attnum)
             WHERE ck.attnum::text = ANY (string_to_array(tg.tgattr::text, ' '))
           )
         ))
     OR (con.confdeltype = 'c'        AND (tg.tgtype & 8)  = 8)
     OR (con.confdeltype IN ('r','a') AND (tg.tgtype & 24) <> 0)
      )
  AND (fn.prosrc ILIKE '%RAISE EXCEPTION%' OR fn.prosrc ILIKE '%ASSERT %')
  -- Silent carve: sanctioned RESTRICT/NO ACTION to the users roots
  -- (pre-anonymise shape) is never a contradiction.
  AND NOT (con.confrelid IN ('public.users'::regclass, 'auth.users'::regclass)
           AND con.confdeltype IN ('r','a'))
ORDER BY con.oid, (tg.tgtype & 1), 2, 5;
EOSQL
)

if ! rows=$(run_sql "$SQL"); then
  echo "::error::WORM-cascade contradiction query failed; cannot verify Art-17 deletability."
  exit 1
fi

errors=""
warnings=""
while IFS='|' read -r cls tbl trg fn fk action level timing parent; do
  [[ -z "$cls" ]] && continue
  case "$cls" in
    cone-refuse)
      line="public.$tbl — FK $fk → $parent is $action: the erasure cascade's delete of $parent rows is REFUSED (23503) for any user with rows in $tbl. No in-schema carve-out exists for an FK refusal (WORM-gated via $trg / fn $fn, $level $timing)."
      ;;
    cone-write-stmt|cone-write-row)
      line="public.$tbl — trigger $trg (fn $fn, $level $timing) raises on the $action cascade from FK $fk → $parent"
      ;;
    dormant)
      line="public.$tbl — dormant anchor FK $fk → $parent ($action): no contradiction today, but the WORM gate ($trg / fn $fn) blocks the parent delete the day $parent gains a delete path or joins the erasure cone — file a tracking issue before adding one."
      ;;
    *) continue ;;
  esac
  if [[ "$cls" == "cone-refuse" || "$cls" == "cone-write-stmt" ]]; then
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
  echo "::warning::Latent, out-of-ref, or dormant WORM-vs-cascade contradiction(s) — deletion breaks only when the user has rows in these tables, the table belongs to another open migration-PR, or the out-of-cone parent gains a delete path (ensure account-delete.ts pre-anonymises before auth-delete; the owning PR must fix its migration):"
  while IFS= read -r l; do [[ -z "$l" ]] && continue; echo "::warning::  - $l"; done <<<"$warnings"
fi

if [[ -n "$errors" ]]; then
  echo "::error::WORM-vs-cascade contradiction breaks GDPR Art-17 account deletion for users with rows in these tables (#5372, extended #10379):"
  while IFS= read -r l; do [[ -z "$l" ]] && continue; echo "::error::  - $l"; done <<<"$errors"
  echo "::error::Two shapes abort auth.admin.deleteUser inside GoTrue's transaction: a write-firing FK (SET NULL/CASCADE/SET DEFAULT) whose cascade UPDATE/DELETE fires a STATEMENT-level raising trigger — even against 0 rows — and a RESTRICT/NO ACTION FK to an in-cone parent whose delete is REFUSED (23503)."
  echo "::error::Fix: for a refusal shape use ON DELETE SET NULL + a row-level WORM carve-out admitting the cascade transition (the mig 160/162 pattern), or repoint the FK to an out-of-cone parent; for a write shape use ON DELETE RESTRICT + pre-anonymise in account-delete.ts (the workspace_member_actions pattern) or SET NULL + row-level carve-out (mig 066) — see issues #5372 and #10379."
  exit 1
fi

echo "Preflight: WORM-vs-cascade contradiction check passed (no deletion-blocking FK shapes owned by this ref in the erasure cone)."
