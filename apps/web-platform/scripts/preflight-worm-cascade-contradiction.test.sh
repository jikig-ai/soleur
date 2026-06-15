#!/usr/bin/env bash
# Tests for preflight-worm-cascade-contradiction.sh (#5372).
#
# The gate scans the live dev schema for the contradiction class that broke
# the GDPR Art-17 account-delete cascade: a table with an ON DELETE
# SET NULL / CASCADE foreign key to public.users (which fires a child
# UPDATE/DELETE during auth.users deletion, inside GoTrue's GUC-less
# transaction) that ALSO carries a BEFORE UPDATE/DELETE trigger whose
# function raises (WORM-style). STATEMENT-level such triggers break
# deletion unconditionally (fire even on a 0-row cascade) → ::error:: +
# exit 1. ROW-level are latent (break only when rows exist; may be
# pre-anonymised) → ::warning:: + exit 0.
#
# Run via: bash apps/web-platform/scripts/preflight-worm-cascade-contradiction.test.sh
#
# Test environment: a fake `psql` on PATH returns the canned contradiction
# rows from $MOCK_ROWS based on the SQL it receives. The live DATABASE_URL
# is never touched.

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

run_gate() {
  # $1 = MOCK_ROWS payload. Returns the gate's exit code; stdout in $GATE_OUT.
  GATE_OUT=$(PATH="$tmp/bin:$PATH" DATABASE_URL_POOLER="postgres://fake" \
    MOCK_ROWS="$1" bash "$GATE" 2>&1) && return 0 || return $?
}

# ---- Test 1: STATEMENT-level contradiction → exit 1 + ::error:: naming table
rc=0
run_gate $'error|routine_runs|routine_runs_no_update|routine_runs_no_mutate|routine_runs_actor_id_fkey|SET NULL|STATEMENT\n' || rc=$?
if [[ "$rc" == "1" ]]; then pass "statement-level contradiction exits 1"; else fail "statement-level should exit 1 (got $rc)"; fi
if grep -q "::error::" <<<"$GATE_OUT" && grep -q "routine_runs" <<<"$GATE_OUT"; then
  pass "statement-level emits ::error:: naming the table"
else
  fail "statement-level must emit ::error:: naming routine_runs; got: $GATE_OUT"
fi

# ---- Test 2: ROW-level only → exit 0 + ::warning:: (latent, not fatal)
rc=0
run_gate $'warning|some_audit|some_audit_no_update|some_audit_no_mutate|some_audit_user_fkey|SET NULL|ROW\n' || rc=$?
if [[ "$rc" == "0" ]]; then pass "row-level latent contradiction exits 0"; else fail "row-level should exit 0 (got $rc)"; fi
if grep -q "::warning::" <<<"$GATE_OUT"; then pass "row-level emits ::warning::"; else fail "row-level must emit ::warning::; got: $GATE_OUT"; fi
if grep -q "::error::" <<<"$GATE_OUT"; then fail "row-level must NOT emit ::error::; got: $GATE_OUT"; else pass "row-level emits no ::error::"; fi

# ---- Test 3: no contradictions → exit 0 + pass message
rc=0
run_gate "" || rc=$?
if [[ "$rc" == "0" ]]; then pass "clean schema exits 0"; else fail "clean schema should exit 0 (got $rc)"; fi
if grep -qi "passed" <<<"$GATE_OUT"; then pass "clean schema prints passed"; else fail "clean schema must print a pass message; got: $GATE_OUT"; fi

# ---- Test 4: mixed (statement error + row warning) → exit 1 (error dominates)
rc=0
run_gate $'warning|t_row|t_row_nu|t_row_fn|t_row_fk|SET NULL|ROW\nerror|t_stmt|t_stmt_nu|t_stmt_fn|t_stmt_fk|CASCADE|STATEMENT\n' || rc=$?
if [[ "$rc" == "1" ]]; then pass "mixed set exits 1 (error dominates)"; else fail "mixed should exit 1 (got $rc)"; fi

# ---- Test 5: missing DATABASE_URL → exit 1
rc=0
GATE_OUT=$(PATH="$tmp/bin:$PATH" bash "$GATE" 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "1" ]]; then pass "missing DATABASE_URL exits 1"; else fail "missing DATABASE_URL should exit 1 (got $rc)"; fi

echo ""
echo "preflight-worm-cascade-contradiction: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]]
