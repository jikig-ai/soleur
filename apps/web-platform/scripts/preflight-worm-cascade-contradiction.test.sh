#!/usr/bin/env bash
# Tests for preflight-worm-cascade-contradiction.sh (#5372).
#
# The gate scans the live dev schema for the contradiction class that broke
# the GDPR Art-17 account-delete cascade: a table with an ON DELETE
# SET NULL / CASCADE foreign key to public.users that ALSO carries a raising
# UPDATE/DELETE trigger (WORM-style).
#
# SCOPE OF THIS TEST: it covers the bash gate's DISPOSITION logic — the exit
# code, the ::error::/::warning:: routing, and the per-ref OWNERSHIP gate
# (block only when the offending table is owned by a migration in the current
# checkout; warn on a leave-behind from another open PR). The SQL's own
# severity DERIVATION (STATEMENT->error / ROW->warning via `tgtype & 1`) runs
# inside Postgres and is exercised by the live tenant-integration CI step +
# the account-delete.*.integration.test.ts behavioural backstop, NOT here — the
# mock emits a pre-computed `severity` column. To keep the mock honest, every
# mock row's severity is kept consistent with its `level` field (col 7).
#
# Run via: bash apps/web-platform/scripts/preflight-worm-cascade-contradiction.test.sh
#
# Test environment: a fake `psql` on PATH returns the canned contradiction
# rows from $MOCK_ROWS; MIGRATIONS_DIR_OVERRIDE points at a temp migrations
# dir whose contents decide ownership. The live DATABASE_URL is never touched.

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

# Fake psql: emits $MOCK_ROWS verbatim for the contradiction query
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

# Two migrations dirs: one that OWNS routine_runs (mentions it), one that does not.
owned_dir="$tmp/mig-owned"
unowned_dir="$tmp/mig-unowned"
mkdir -p "$owned_dir" "$unowned_dir"
cat > "$owned_dir/104_routine_runs.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS public.routine_runs ( id uuid PRIMARY KEY );
SQL
cat > "$unowned_dir/001_unrelated.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS public.users ( id uuid PRIMARY KEY );
SQL

run_gate() {
  # $1 = MOCK_ROWS payload, $2 = migrations dir. GATE_OUT captures stdout+stderr.
  GATE_OUT=$(PATH="$tmp/bin:$PATH" DATABASE_URL_POOLER="postgres://fake" \
    MIGRATIONS_DIR_OVERRIDE="$2" MOCK_ROWS="$1" bash "$GATE" 2>&1) && return 0 || return $?
}

# Row schema: severity|tbl|trg|fn|fk|action|level|timing
ROW_STMT=$'error|routine_runs|routine_runs_no_update|routine_runs_no_mutate|routine_runs_actor_id_fkey|SET NULL|STATEMENT|BEFORE\n'
ROW_ROW=$'warning|audit_byok_use|audit_byok_use_no_update|audit_byok_use_no_mutate|audit_byok_use_founder_id_fkey|SET NULL|ROW|BEFORE\n'

# ---- Test 1: STATEMENT-level contradiction OWNED by this ref → exit 1 + ::error::
rc=0
run_gate "$ROW_STMT" "$owned_dir" || rc=$?
if [[ "$rc" == "1" ]]; then pass "owned statement-level contradiction exits 1"; else fail "owned statement-level should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "routine_runs" <<<"$GATE_OUT"; then
  pass "owned statement-level emits ::error:: naming the table"
else
  fail "owned statement-level must emit ::error:: naming routine_runs; got: $GATE_OUT"
fi

# ---- Test 2: STATEMENT-level contradiction NOT owned (leave-behind) → exit 0 + ::warning::
rc=0
run_gate "$ROW_STMT" "$unowned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "leave-behind statement-level contradiction exits 0 (not owned)"; else fail "leave-behind should exit 0 (got $rc)"; fi
if grep -q "::warning::" <<<"$GATE_OUT" && grep -qi "leave-behind" <<<"$GATE_OUT"; then
  pass "leave-behind emits ::warning:: tagged as leave-behind"
else
  fail "leave-behind must emit ::warning:: tagged leave-behind; got: $GATE_OUT"
fi
if grep -q "::error::" <<<"$GATE_OUT"; then fail "leave-behind must NOT emit ::error::; got: $GATE_OUT"; else pass "leave-behind emits no ::error::"; fi

# ---- Test 3: ROW-level → exit 0 + ::warning:: regardless of ownership
rc=0
run_gate "$ROW_ROW" "$owned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "row-level latent contradiction exits 0"; else fail "row-level should exit 0 (got $rc)"; fi
if grep -q "::warning::" <<<"$GATE_OUT"; then pass "row-level emits ::warning::"; else fail "row-level must emit ::warning::; got: $GATE_OUT"; fi
if grep -q "::error::" <<<"$GATE_OUT"; then fail "row-level must NOT emit ::error::; got: $GATE_OUT"; else pass "row-level emits no ::error::"; fi

# ---- Test 4: no contradictions → exit 0 + pass message
rc=0
run_gate "" "$owned_dir" || rc=$?
if [[ "$rc" == "0" ]]; then pass "clean schema exits 0"; else fail "clean schema should exit 0 (got $rc)"; fi
if grep -qi "passed" <<<"$GATE_OUT"; then pass "clean schema prints passed"; else fail "clean schema must print a pass message; got: $GATE_OUT"; fi

# ---- Test 5: owned statement error + row warning → exit 1 (error dominates), both surfaced
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

echo ""
echo "preflight-worm-cascade-contradiction: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]]
