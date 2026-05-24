#!/usr/bin/env bash
# Tests for lint-migration-fk-preconditions.sh (Delta 2, issue 4325 follow-up).
#
# Three core cases per spec AC2:
#   T1 — unguarded cross-file FK → exit 1, names the table in error
#   T2 — guarded cross-file FK (to_regclass present) → exit 0
#   T3 — self-FK (target CREATE-d in same file) → exit 0, no false positive
# Plus T4 — down-sibling file is skipped silently.
#
# Run: bash apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/lint-migration-fk-preconditions.sh"

if [[ ! -x "$LINT" ]]; then
  echo "ERROR: $LINT not found or not executable" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ----------------------------------------------------------------------
# T1: unguarded cross-file FK → exit 1, names the table
# ----------------------------------------------------------------------
echo "T1: unguarded cross-file FK → fails"
cat > "$tmp/099_unguarded.sql" <<'SQL'
-- Unguarded cross-file FK; no to_regclass precondition.
CREATE TABLE public.t1_child_lint_test (
  id uuid PRIMARY KEY,
  parent_id uuid REFERENCES public.t1_parent_in_another_mig(id) ON DELETE CASCADE
);
SQL

set +e
out=$(bash "$LINT" "$tmp/099_unguarded.sql" 2>&1)
rc=$?
set -e

if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q 't1_parent_in_another_mig'; then
  pass "exit 1 with referenced table name in error"
else
  fail "expected rc=1 + table name; got rc=$rc, out=$out"
fi

# ----------------------------------------------------------------------
# T2: guarded cross-file FK (to_regclass present) → passes
# ----------------------------------------------------------------------
echo "T2: guarded cross-file FK (to_regclass present) → passes"
cat > "$tmp/099_guarded.sql" <<'SQL'
-- Guarded cross-file FK with canonical to_regclass precondition.
DO $$
BEGIN
  IF to_regclass('public.t2_parent_in_another_mig') IS NULL THEN
    RAISE EXCEPTION USING MESSAGE = 'precondition failed';
  END IF;
END $$;

CREATE TABLE public.t2_child_lint_test (
  id uuid PRIMARY KEY,
  parent_id uuid REFERENCES public.t2_parent_in_another_mig(id) ON DELETE CASCADE
);
SQL

set +e
out=$(bash "$LINT" "$tmp/099_guarded.sql" 2>&1)
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  pass "exit 0; to_regclass precondition recognized"
else
  fail "expected rc=0; got rc=$rc, out=$out"
fi

# ----------------------------------------------------------------------
# T3: self-FK (target CREATE-d in same file) → passes
# ----------------------------------------------------------------------
echo "T3: self-FK (target CREATE-d in same file) → no false positive"
cat > "$tmp/099_self_ref.sql" <<'SQL'
-- Self-FK pattern. parent is created in this file; child references it.
-- Must NOT trigger lint (same-file CREATEs subtracted from references).
CREATE TABLE public.t3_parent_self_ref (id uuid PRIMARY KEY);
CREATE TABLE public.t3_child_self_ref (
  id uuid PRIMARY KEY,
  parent_id uuid REFERENCES public.t3_parent_self_ref(id) ON DELETE CASCADE
);
SQL

set +e
out=$(bash "$LINT" "$tmp/099_self_ref.sql" 2>&1)
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  pass "exit 0; self-FK subtracted"
else
  fail "expected rc=0; got rc=$rc, out=$out"
fi

# ----------------------------------------------------------------------
# T4: down-sibling file → skipped silently
# ----------------------------------------------------------------------
echo "T4: .down.sql file → skipped silently"
cat > "$tmp/099_unguarded.down.sql" <<'SQL'
DROP TABLE IF EXISTS public.t1_child_lint_test;
SQL

set +e
out=$(bash "$LINT" "$tmp/099_unguarded.down.sql" 2>&1)
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  pass "exit 0; .down.sql skipped"
else
  fail "expected rc=0; got rc=$rc, out=$out"
fi

# ----------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1
