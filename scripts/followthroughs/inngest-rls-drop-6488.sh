#!/usr/bin/env bash
# Follow-through verification for #6488 — post-cutover drop of the 14 orphaned
# dark-Inngest tables on soleur-dev + atomic retirement of 0002/apply-inngest-rls-dev.yml.
# Source PR: #6485.
#
# CLOSE CRITERION IS "THE DROP HAPPENED", NOT "THE DROP IS SAFE".
# #6488 tracks doing the drop, so it may only close once the tables are GONE. An
# earlier draft of this probe gated on the plan's safety trigger
# (INNGEST_CUTOVER_FLIP == done AND DSN != dev-ref AND soak elapsed) — that is the
# precondition for STARTING the work, and PASSing on it would have auto-closed a
# tracker whose work had never been done. Table absence is the completion signal,
# is directly observable, and cannot false-close.
#
# It is also the only formulation reachable from the sweeper: INNGEST_CUTOVER_FLIP
# lives in Doppler soleur-inngest/prd behind DOPPLER_TOKEN_INNGEST_ARM, a token bound
# to the environment-gated `inngest-cutover` GitHub environment. The sweeper runs
# unenvironmented and cannot read it, and minting a sweeper-scoped token would be an
# operator step (the thing follow-throughs exist to avoid). Table absence needs only
# SUPABASE_ACCESS_TOKEN, already in the sweeper env.
#
# Note the counters cannot prove the cutover on their own: the dark host is idle
# (15 cumulative writes since 2026-04-26), so "no new writes" is equally consistent
# with "cut over" and "still pointed here, just quiet". They are reported as
# operator CONTEXT in the FAIL comment, never as a PASS input.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (all 14 tables gone → sweeper closes #6488)
#   1 = FAIL       (>=1 table remains → sweeper comments with state, leaves open)
#   * = TRANSIENT  (API unreachable, auth/parse failure)
#
# Required env: SUPABASE_ACCESS_TOKEN (declared via the directive's secrets=).

set -uo pipefail

# Explicit empty-check, NOT `${VAR:?}`: under a non-interactive shell `:?` aborts
# with status 1, which the sweeper maps to FAIL — the opposite of the intended
# TRANSIENT. An unprovisioned GitHub secret resolves to "" in the sweeper env.
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "TRANSIENT: SUPABASE_ACCESS_TOKEN not set" >&2
  exit 2
fi

# soleur-dev. Pinned, never derived: pointing this probe at prd
# (ifsccnjhymdmidffkzhl) would read an unrelated catalog and could PASS on the
# absence of tables that never existed there.
PROJECT_REF="mlwiodleouzwniehynfz"
API="https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query"

# The 14 dark-Inngest tables. Mirrors ALLOW_14 in
# apps/web-platform/infra/inngest-rls/inngest-rls.test.sh — that suite pins the set
# against the live catalog, so drift there is caught before it reaches here.
ALLOW_14="'apps','event_batches','events','function_finishes','function_runs','functions','goose_db_version','history','migrations','queue_snapshot_chunks','spans','trace_runs','traces','worker_connections'"

# Baseline captured 2026-07-15 against the live catalog (stats_reset
# 2026-04-26 02:16:05+00, 14/14 tables present, 15 cumulative writes).
BASELINE_WRITES=15

read -r -d '' QUERY <<SQL
SELECT
  (SELECT count(*) FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
      AND c.relname IN (${ALLOW_14}))                                    AS tables_remaining,
  (SELECT count(*) FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
      AND c.relname IN (${ALLOW_14}) AND c.relrowsecurity = false)       AS rls_disabled,
  (SELECT coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0)
     FROM pg_stat_user_tables
    WHERE schemaname = 'public' AND relname IN (${ALLOW_14}))            AS writes
SQL

RESP=$(curl -sS --max-time 30 -X POST "$API" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$(jq -nc --arg q "$QUERY" '{query: $q}')" 2>&1)
CURL_RC=$?

if [[ "$CURL_RC" -ne 0 ]]; then
  echo "TRANSIENT: Supabase Management API unreachable (curl rc=$CURL_RC)" >&2
  exit 2
fi

REMAINING=$(printf '%s' "$RESP" | jq -er '.[0].tables_remaining' 2>/dev/null)
if [[ -z "$REMAINING" || ! "$REMAINING" =~ ^[0-9]+$ ]]; then
  # Includes the auth-failure path: an error envelope has no .tables_remaining.
  # Fail TRANSIENT, never PASS — a parse failure must not read as "tables gone".
  echo "TRANSIENT: could not parse tables_remaining from API response" >&2
  printf '%s\n' "$RESP" | head -c 400 >&2
  exit 2
fi

RLS_OFF=$(printf '%s' "$RESP" | jq -er '.[0].rls_disabled' 2>/dev/null || echo "?")
WRITES=$(printf '%s' "$RESP" | jq -er '.[0].writes' 2>/dev/null || echo "?")

if [[ "$REMAINING" -eq 0 ]]; then
  echo "PASS: all 14 dark-Inngest tables are gone from soleur-dev (${PROJECT_REF}) — the #6488 drop is done."
  echo "Remember the atomic other half: 0002_dev_inngest_tables_lockdown.sql and apply-inngest-rls-dev.yml should retire in the same PR as the drop."
  exit 0
fi

echo "FAIL: ${REMAINING}/14 dark-Inngest tables still present on soleur-dev (${PROJECT_REF}) — the drop has not happened yet."
echo ""
echo "Operator context (NOT close inputs — reported so the state is visible without a dashboard):"
echo "  - RLS still disabled on: ${RLS_OFF}/14 tables (expected 0 — anything else is a lockdown REGRESSION and is more urgent than the drop)."
echo "  - Cumulative writes to the 14: ${WRITES} (baseline ${BASELINE_WRITES} at 2026-07-15). Unchanged means nothing wrote them since; it does NOT prove the cutover, because the dark host is idle either way."
echo "  - Safety precondition for starting the drop is unchanged and lives in the plan: INNGEST_CUTOVER_FLIP == done AND the DSN no longer targets ${PROJECT_REF} AND the soak window has elapsed."
exit 1
