#!/usr/bin/env bash
# Tests for preflight-worm-cascade-contradiction.sh (#5372, extended #10379).
#
# The gate scans the live dev schema for the contradiction class that broke
# the GDPR Art-17 account-delete cascade: a FK on a table carrying a raising
# UPDATE/DELETE trigger (WORM-style append-only reject) whose parent is
# reachable from auth.users by CASCADE deletion ("in-cone"). The #10379
# extension adds the user-erasure delete-cone (recursive CTE rooted at
# auth.users + public.users propagating confdeltype='c') so table-to-table
# chains — action_sends.message_id → public.messages was the one that
# shipped the #10254 wedge — are covered, plus refusal-class (RESTRICT /
# NO ACTION) and dormant-anchor (out-of-cone) classification.
#
# SCOPE OF THIS TEST: it covers the bash gate's DISPOSITION logic — exit
# codes, ::error::/::warning:: routing per class, and the per-ref OWNERSHIP
# gate (block only when the offending table is owned by a migration in the
# current checkout; warn on a leave-behind from another open PR). The SQL's
# own class DERIVATION (cone membership, action↔event matching, trigger
# level) runs inside Postgres and is exercised by the live
# tenant-integration CI step + account-delete.*.integration.test.ts
# behavioural backstop, NOT here — the mock emits a pre-computed `class`
# column. To keep the mock honest, every mock row's class is kept
# consistent with its `level` field (col 7): cone-write-stmt carries
# STATEMENT, cone-write-row carries ROW.
#
# Run via: bash apps/web-platform/scripts/preflight-worm-cascade-contradiction.test.sh
#
# Test environment: a fake `psql` on PATH returns the canned census rows
# from $MOCK_ROWS; MIGRATIONS_DIR_OVERRIDE points at a temp migrations dir
# whose contents decide ownership. The live DATABASE_URL is never touched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/preflight-worm-cascade-contradiction.sh"

if [[ ! -f "$GATE" ]]; then
  echo "ERROR: $GATE not found" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fake psql: emits $MOCK_ROWS verbatim for the census query
# (recognised by the 'pg_constraint' substring), empty otherwise.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/psql" <<'FAKE'
#!/usr/bin/env bash
sql=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) sql="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ "$sql" == *pg_constraint* ]]; then
  printf '%s' "${MOCK_ROWS:-}"
fi
exit 0
FAKE
chmod +x "$tmp/bin/psql"

# Two migrations dirs: one that OWNS the fixture tables (mentions them),
# one that does not.
owned_dir="$tmp/mig-owned"
unowned_dir="$tmp/mig-unowned"
mkdir -p "$owned_dir" "$unowned_dir"
cat > "$owned_dir/104_fixture_tables.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS public.routine_runs ( id uuid PRIMARY KEY );
CREATE TABLE IF NOT EXISTS public.worm_ledger ( id uuid PRIMARY KEY );
CREATE TABLE IF NOT EXISTS public.worm_tab ( id uuid PRIMARY KEY );
SQL
cat > "$unowned_dir/001_unrelated.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS public.users ( id uuid PRIMARY KEY );
SQL

run_gate() {
  # $1 = MOCK_ROWS payload, $2 = migrations dir. GATE_OUT captures stdout+stderr.
  GATE_OUT=$(PATH="$tmp/bin:$PATH" DATABASE_URL_POOLER="postgres://fake" \
    MIGRATIONS_DIR_OVERRIDE="$2" MOCK_ROWS="$1" bash "$GATE" 2>&1) && return 0 || return $?
}

# Row schema (post-#10379): class|tbl|trg|fn|fk|action|level|timing|parent
ROW_STMT=$'cone-write-stmt|routine_runs|routine_runs_no_update|routine_runs_no_mutate|routine_runs_actor_id_fkey|SET NULL|STATEMENT|BEFORE|public.users\n'
ROW_ROW=$'cone-write-row|audit_byok_use|audit_byok_use_no_update|audit_byok_use_no_mutate|audit_byok_use_founder_id_fkey|SET NULL|ROW|BEFORE|public.users\n'
ROW_REFUSE_STMT=$'cone-refuse|worm_ledger|worm_ledger_no_update|worm_ledger_no_mutate|worm_ledger_message_id_fkey|NO ACTION|STATEMENT|BEFORE|public.messages\n'
ROW_REFUSE_ROW=$'cone-refuse|worm_tab|worm_tab_no_update|worm_tab_no_mutate|worm_tab_grant_id_fkey|RESTRICT|ROW|BEFORE|public.conversations\n'
ROW_WRITE_ROW_TRANS=$'cone-write-row|action_sends|action_sends_message_id_guard|action_sends_no_mutate|action_sends_message_id_fkey|SET NULL|ROW|BEFORE|public.messages\n'
ROW_WRITE_STMT_TRANS=$'cone-write-stmt|worm_tab|worm_tab_no_update|worm_tab_no_mutate|worm_tab_message_id_fkey|SET NULL|STATEMENT|BEFORE|public.messages\n'
ROW_DORMANT_A=$'dormant|dsar_export_audit_pii|dsar_export_audit_pii_no_mutate_trigger|dsar_export_audit_pii_no_mutate|dsar_export_audit_pii_job_id_fkey|NO ACTION|ROW|BEFORE|public.dsar_export_jobs\n'
ROW_DORMANT_B=$'dormant|action_sends|action_sends_no_update|action_sends_no_mutate|action_sends_grant_id_fkey|NO ACTION|STATEMENT|BEFORE|public.scope_grants\n'
ROW_DORMANT_R=$'dormant|email_triage_items|email_triage_items_no_mutate_trigger|email_triage_items_no_mutate|email_triage_items_workspace_id_fkey|RESTRICT|ROW|BEFORE|public.workspaces\n'

# ---- Test 1: owned STATEMENT write contradiction → exit 1 + ::error::
rc=0
run_gate "$ROW_STMT" "$owned_dir" || rc=$?
if [[ "$rc" == "1" ]]; then pass "owned statement-level write contradiction exits 1"; else fail "owned statement-level should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "routine_runs" <<<"$GATE_OUT"; then
  pass "owned statement-level emits ::error:: naming the table"
else
  fail "owned statement-level must emit ::error:: naming routine_runs; got: $GATE_OUT"
fi

# ---- Test 2: STATEMENT write contradiction NOT owned → exit 0 + ::warning:: leave-behind
rc=0
run_gate "$ROW_STMT" "$unowned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "leave-behind statement-level contradiction exits 0 (not owned)"; else fail "leave-behind should exit 0 (got $rc)"; fi
if grep -q "::warning::" <<<"$GATE_OUT" && grep -qi "leave-behind" <<<"$GATE_OUT"; then
  pass "leave-behind emits ::warning:: tagged as leave-behind"
else
  fail "leave-behind must emit ::warning:: tagged leave-behind; got: $GATE_OUT"
fi
if grep -q "::error::" <<<"$GATE_OUT"; then fail "leave-behind must NOT emit ::error::; got: $GATE_OUT"; else pass "leave-behind emits no ::error::"; fi

# ---- Test 3: ROW-level write → exit 0 + ::warning:: (unowned fixture; the
# cone-write-row arm never consults ownership, so one variant suffices)
rc=0
run_gate "$ROW_ROW" "$owned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "row-level latent contradiction exits 0"; else fail "row-level should exit 0 (got $rc)"; fi
if grep -q "::warning::" <<<"$GATE_OUT"; then pass "row-level emits ::warning::"; else fail "row-level must emit ::warning::; got: $GATE_OUT"; fi
if grep -q "::error::" <<<"$GATE_OUT"; then fail "row-level must NOT emit ::error::; got: $GATE_OUT"; else pass "row-level emits no ::error::"; fi

# ---- Test 4: no rows → exit 0 + pass message
rc=0
run_gate "" "$owned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "clean schema exits 0"; else fail "clean schema should exit 0 (got $rc)"; fi
if grep -qi "passed" <<<"$GATE_OUT"; then pass "clean schema prints passed"; else fail "clean schema must print a pass message; got: $GATE_OUT"; fi

# ---- Test 5: owned error + row warning → exit 1 (error dominates), both surfaced
rc=0
run_gate "${ROW_ROW}${ROW_STMT}" "$owned_dir" || rc=$?
if [[ "$rc" == "1" ]]; then pass "mixed (owned error + row warning) exits 1"; else fail "mixed should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "::warning::" <<<"$GATE_OUT"; then
  pass "mixed surfaces both ::error:: and ::warning::"
else
  fail "mixed must surface both annotations; got: $GATE_OUT"
fi

# ---- Test 6: missing DATABASE_URL → exit 1
rc=0
GATE_OUT=$(PATH="$tmp/bin:$PATH" MIGRATIONS_DIR_OVERRIDE="$owned_dir" bash "$GATE" 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "1" ]]; then pass "missing DATABASE_URL exits 1"; else fail "missing DATABASE_URL should exit 1 (got $rc)"; fi

# ---- Test 7 (#10379): owned cone-refuse NO ACTION to in-cone non-users parent
# (the #10254 wedge class) → exit 1 + ::error:: naming table + parent
rc=0
run_gate "$ROW_REFUSE_STMT" "$owned_dir" || rc=$?
if [[ "$rc" == "1" ]]; then pass "owned cone-refuse (NO ACTION -> messages) exits 1"; else fail "cone-refuse should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "worm_ledger" <<<"$GATE_OUT" && grep -q "public.messages" <<<"$GATE_OUT"; then
  pass "cone-refuse ::error:: names table and transitive parent"
else
  fail "cone-refuse must emit ::error:: naming worm_ledger + public.messages; got: $GATE_OUT"
fi

# ---- Test 8: same cone-refuse row, unowned → exit 0 + ::warning:: leave-behind
rc=0
run_gate "$ROW_REFUSE_STMT" "$unowned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "leave-behind cone-refuse exits 0"; else fail "leave-behind cone-refuse should exit 0 (got $rc)"; fi
if grep -q "::warning::" <<<"$GATE_OUT" && ! grep -q "::error::" <<<"$GATE_OUT"; then
  pass "leave-behind cone-refuse emits ::warning:: only"
else
  fail "leave-behind cone-refuse must warn, not error; got: $GATE_OUT"
fi

# ---- Test 9: cone-write-row on a TRANSITIVE parent (post-162 residue) →
# exit 0 + ::warning::, never ::error::
rc=0
run_gate "$ROW_WRITE_ROW_TRANS" "$owned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "transitive cone-write-row exits 0"; else fail "cone-write-row should exit 0 (got $rc)"; fi
if grep -q "::warning::" <<<"$GATE_OUT" && grep -q "public.messages" <<<"$GATE_OUT" && ! grep -q "::error::" <<<"$GATE_OUT"; then
  pass "cone-write-row warns and names transitive parent"
else
  fail "cone-write-row must warn naming public.messages; got: $GATE_OUT"
fi

# ---- Test 10: owned cone-write-stmt on transitive parent → exit 1 + ::error::
rc=0
run_gate "$ROW_WRITE_STMT_TRANS" "$owned_dir" || rc=$?
if [[ "$rc" == "1" ]]; then pass "owned transitive cone-write-stmt exits 1"; else fail "transitive cone-write-stmt should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "public.messages" <<<"$GATE_OUT"; then
  pass "transitive cone-write-stmt errors naming parent"
else
  fail "transitive cone-write-stmt must error naming public.messages; got: $GATE_OUT"
fi

# ---- Test 11: dormant anchors (audit parity) → exit 0, warnings name both parents
rc=0
run_gate "${ROW_DORMANT_A}${ROW_DORMANT_B}${ROW_DORMANT_R}" "$owned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "dormant anchors exit 0"; else fail "dormant anchors should exit 0 (got $rc)"; fi
if grep -q "public.dsar_export_jobs" <<<"$GATE_OUT" && grep -q "public.scope_grants" <<<"$GATE_OUT" && grep -q "public.workspaces" <<<"$GATE_OUT"; then
  pass "dormant warnings name all three parents"
else
  fail "dormant warnings must name dsar_export_jobs + scope_grants + workspaces; got: $GATE_OUT"
fi
if grep -q "::error::" <<<"$GATE_OUT"; then fail "dormant anchors must NOT emit ::error::; got: $GATE_OUT"; else pass "dormant anchors emit no ::error::"; fi

# ---- Test 12 (ruling-pinned): cone-refuse at ROW level (RESTRICT to in-cone
# parent) → still exit 1 when owned — an FK refusal has no carve-out at any level
rc=0
run_gate "$ROW_REFUSE_ROW" "$owned_dir" || rc=$?
if [[ "$rc" == "1" ]]; then pass "row-level cone-refuse (RESTRICT -> conversations) exits 1"; else fail "row-level cone-refuse should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "public.conversations" <<<"$GATE_OUT"; then
  pass "row-level cone-refuse errors naming in-cone parent"
else
  fail "row-level cone-refuse must error naming public.conversations; got: $GATE_OUT"
fi

# ---- Test 13: unrecognised census class → fail-loud exit 1 + ::error::
# (guards a future SQL edit adding a 5th class without a disposition arm)
ROW_BOGUS=$'mystery-class|routine_runs|t|f|k|SET NULL|ROW|BEFORE|public.users\n'
rc=0
run_gate "$ROW_BOGUS" "$owned_dir" || rc=$?
if [[ "$rc" == "1" ]]; then pass "unknown census class exits 1 (fail-loud)"; else fail "unknown class should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "mystery-class" <<<"$GATE_OUT"; then
  pass "unknown class emits ::error:: naming it"
else
  fail "unknown class must emit ::error:: naming the class; got: $GATE_OUT"
fi

echo ""
echo "preflight-worm-cascade-contradiction: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]]
