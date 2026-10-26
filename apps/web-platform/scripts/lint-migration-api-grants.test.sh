#!/usr/bin/env bash
# Tests for lint-migration-api-grants.sh (ADR-303 — the static tier of the
# two-tier api-role table-grant guard).
#
# Covers the plan's Guard-1 mutation matrix:
#   T1 — ungranted create-table → exit 1, names the relation
#   T2 — lowercase single-role grant → exit 0 (non-canonical permitted form)
#   T3 — two tables, grant covers only the first → exit 1 (a check stopping at
#        the first member is the defect itself)
#   T4 — dead-detector → the pass-case output must report >=1 relation scanned
#        (a lint reporting "0 scanned" on a file that creates one is vacuous)
#   T5 — .down.sql containing create table → exit 0 (never applied)
#   T6 — GENERATED ALWAYS AS IDENTITY + table grant, no sequence grant → exit 1
#        (the sequence arm; post-flip sequences keep no USAGE default)
#   T7 — soleur:no-data-api sentinel with reason → exit 0
#   T8 — create table inside a -- comment / dollar-quoted body → exit 0
#        (the noise-stripper must not see non-DDL text)
#   T9 — harness-mutation guard: a stub cannot satisfy the suite — T1's fixture
#        must produce rc=1 AND an ::error:: marker AND the relation name, and
#        the assertion floor keeps a dropped-case edit loud.
# Extra rows mirroring the AC4 wording: case-insensitive create, view arm,
# sequence-grant-satisfies-identity variant, reason-free sentinel RED,
# nonexistent-file rc=2.
#
# Run: bash apps/web-platform/scripts/lint-migration-api-grants.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/lint-migration-api-grants.sh"

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

run_lint() { # prints "rc|output"
  local out rc
  set +e
  out=$(bash "$LINT" "$@" 2>&1)
  rc=$?
  set -e
  printf '%s|%s' "$rc" "$out"
}

# ----------------------------------------------------------------------
echo "T1: ungranted create-table → fails, names the relation"
cat > "$tmp/900_ungranted.sql" <<'SQL'
CREATE TABLE public.t1_ungranted (
  id uuid PRIMARY KEY
);
SQL
res=$(run_lint "$tmp/900_ungranted.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1"; else fail "expected 1, got $rc ($out)"; fi
if grep -q 't1_ungranted' <<<"$out"; then pass "names t1_ungranted"; else fail "no relation name: $out"; fi
if grep -q '::error::' <<<"$out"; then pass "emits ::error:: markers"; else fail "no error marker: $out"; fi

# ----------------------------------------------------------------------
echo "T2: lowercase single-role grant → passes (non-canonical permitted form)"
cat > "$tmp/900_granted.sql" <<'SQL'
create table public.t2_granted (
  id uuid primary key
);
grant select on public.t2_granted to anon;
SQL
res=$(run_lint "$tmp/900_granted.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0"; else fail "expected 0, got $rc ($out)"; fi

# ----------------------------------------------------------------------
echo "T3: two tables, grant covers only the first → fails (no early-stop)"
cat > "$tmp/900_two.sql" <<'SQL'
CREATE TABLE public.t3_first (id uuid PRIMARY KEY);
CREATE TABLE public.t3_second (id uuid PRIMARY KEY);
GRANT SELECT ON public.t3_first TO anon;
SQL
res=$(run_lint "$tmp/900_two.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1"; else fail "expected 1, got $rc ($out)"; fi
if grep -q 't3_second' <<<"$out" && ! grep -q "'t3_first'" <<<"$out"; then
  pass "names t3_second only"
else
  fail "expected violation on t3_second only: $out"
fi

# ----------------------------------------------------------------------
echo "T4: relation-scanned count is non-zero on a file that creates one"
cat > "$tmp/900_scancount.sql" <<'SQL'
CREATE TABLE public.t4_scanned (id uuid PRIMARY KEY);
GRANT SELECT ON public.t4_scanned TO service_role;
SQL
res=$(run_lint "$tmp/900_scancount.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]] && grep -Eq '[1-9][0-9]* relation\(s\) scanned' <<<"$out"; then
  pass "reports >=1 relation scanned"
else
  fail "expected rc=0 and nonzero scan count; got rc=$rc, out=$out"
fi

# ----------------------------------------------------------------------
echo "T5: .down.sql containing create table → skipped, exit 0"
cat > "$tmp/900_rollback.down.sql" <<'SQL'
CREATE TABLE public.t5_down_only (id uuid PRIMARY KEY);
SQL
res=$(run_lint "$tmp/900_rollback.down.sql")
rc="${res%%|*}"
if [[ "$rc" == "0" ]]; then pass "exit 0; .down.sql skipped"; else fail "expected 0, got $rc"; fi

# ----------------------------------------------------------------------
echo "T6: identity column + table grant but no sequence GRANT USAGE → fails"
cat > "$tmp/900_identity.sql" <<'SQL'
CREATE TABLE public.t6_identity (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payload text
);
GRANT SELECT ON public.t6_identity TO authenticated;
SQL
res=$(run_lint "$tmp/900_identity.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1 (sequence arm)"; else fail "expected 1, got $rc ($out)"; fi
if grep -Eq 'USAGE|sequence' <<<"$out"; then pass "names the sequence requirement"; else fail "no sequence hint: $out"; fi

echo "T6b: identity column + table grant + matching sequence GRANT USAGE → passes"
cat > "$tmp/900_identity_seq.sql" <<'SQL'
CREATE TABLE public.t6b_identity (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);
GRANT SELECT ON public.t6b_identity TO authenticated;
GRANT USAGE ON SEQUENCE public.t6b_identity_id_seq TO service_role;
SQL
res=$(run_lint "$tmp/900_identity_seq.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0"; else fail "expected 0, got $rc ($out)"; fi

echo "T6c: serial column without sequence grant → fails"
cat > "$tmp/900_serial.sql" <<'SQL'
CREATE TABLE public.t6c_serial (
  id serial PRIMARY KEY
);
GRANT SELECT ON public.t6c_serial TO anon;
SQL
res=$(run_lint "$tmp/900_serial.sql")
rc="${res%%|*}"
if [[ "$rc" == "1" ]]; then pass "exit 1 (serial arm)"; else fail "expected 1, got $rc"; fi

# ----------------------------------------------------------------------
echo "T7: soleur:no-data-api sentinel with reason → passes"
cat > "$tmp/900_sentinel.sql" <<'SQL'
CREATE TABLE public.t7_audit_x (id uuid PRIMARY KEY);
-- soleur:no-data-api: t7_audit_x — internal-only, definer-RPC access
SQL
res=$(run_lint "$tmp/900_sentinel.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0"; else fail "expected 0, got $rc ($out)"; fi

echo "T7b: sentinel without a reason → fails (reason REQUIRED)"
cat > "$tmp/900_sentinel_noreason.sql" <<'SQL'
CREATE TABLE public.t7b_audit_y (id uuid PRIMARY KEY);
-- soleur:no-data-api: t7b_audit_y
SQL
res=$(run_lint "$tmp/900_sentinel_noreason.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1"; else fail "expected 1, got $rc ($out)"; fi
if grep -q 'reason' <<<"$out"; then pass "explains reason is required"; else fail "no reason diagnostic: $out"; fi

# ----------------------------------------------------------------------
echo "T8: create table inside comments / dollar-quoted body → not detected, passes"
cat > "$tmp/900_noise.sql" <<'SQL'
-- This migration documents the convention: CREATE TABLE public.t8_comment (id int);
/* And a block comment too:
   CREATE TABLE public.t8_block (id int);
*/
DO $$
BEGIN
  EXECUTE 'CREATE TABLE public.t8_dynamic (id int)';
END $$;
CREATE TABLE public.t8_real (id uuid PRIMARY KEY);
GRANT SELECT ON public.t8_real TO anon;
SQL
res=$(run_lint "$tmp/900_noise.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 — noise stripped"; else fail "expected 0, got $rc ($out)"; fi
if ! grep -Eq 't8_comment|t8_block|t8_dynamic' <<<"$out"; then
  pass "comment/string creates unseen"
else
  fail "noise leaked into detection: $out"
fi

echo "T8c: literal GRANT inside a DO \$\$ to_regclass block DOES count (the corpus convention — mig 174's shape)"
cat > "$tmp/900_doblock_grant.sql" <<'SQL'
CREATE TABLE public.t8c_conditional (id uuid PRIMARY KEY);
DO $$
BEGIN
  IF to_regclass('public."t8c_conditional"') IS NOT NULL THEN
    GRANT SELECT ON TABLE public."t8c_conditional" TO anon;
  END IF;
END $$;
SQL
res=$(run_lint "$tmp/900_doblock_grant.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 — DO-block GRANT counted"; else fail "expected 0, got $rc ($out)"; fi

echo "T8b: GRANT inside a dollar-quoted body does NOT satisfy the requirement"
cat > "$tmp/900_grant_in_string.sql" <<'SQL'
CREATE TABLE public.t8b_string_grant (id uuid PRIMARY KEY);
DO $$
BEGIN
  EXECUTE 'GRANT SELECT ON public.t8b_string_grant TO anon';
END $$;
SQL
res=$(run_lint "$tmp/900_grant_in_string.sql")
rc="${res%%|*}"
if [[ "$rc" == "1" ]]; then pass "exit 1 — string GRANT not counted"; else fail "expected 1, got $rc"; fi

# ----------------------------------------------------------------------
echo "T9: view arm + case-insensitive create"
cat > "$tmp/900_view.sql" <<'SQL'
create view public.t9_view as select 1 as id;
grant select on public.t9_view to anon;
SQL
res=$(run_lint "$tmp/900_view.sql")
rc="${res%%|*}"
if [[ "$rc" == "0" ]]; then pass "view + lowercase grant → 0"; else fail "expected 0, got $rc"; fi

cat > "$tmp/900_view_ungranted.sql" <<'SQL'
CREATE VIEW public.t9b_view AS SELECT 1 AS id;
SQL
res=$(run_lint "$tmp/900_view_ungranted.sql")
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]] && grep -q 't9b_view' <<<"$out"; then pass "ungranted view → 1, named"; else fail "expected 1 + name, got $rc ($out)"; fi

# ----------------------------------------------------------------------
echo "T10: partition-child and temp-table creates are not public relations"
cat > "$tmp/900_partition.sql" <<'SQL'
CREATE TABLE public.t10_parent (id int) PARTITION BY RANGE (id);
CREATE TABLE public.t10_child PARTITION OF public.t10_parent FOR VALUES FROM (0) TO (100);
CREATE TEMP TABLE public.t10_tmp (id int);
SQL
res=$(run_lint "$tmp/900_partition.sql")
rc="${res%%|*}"; out="${res#*|}"
# t10_parent IS a public relation (needs a grant); child + temp are exempt.
if [[ "$rc" == "1" ]] && grep -q 't10_parent' <<<"$out" && ! grep -Eq 't10_child|t10_tmp' <<<"$out"; then
  pass "partition child + temp exempt, parent flagged"
else
  fail "expected t10_parent only; got rc=$rc, out=$out"
fi

# ----------------------------------------------------------------------
echo "T11: nonexistent file → exit 2"
set +e
out=$(bash "$LINT" "$tmp/does-not-exist.sql" 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]]; then pass "exit 2"; else fail "expected 2, got $rc"; fi

# ----------------------------------------------------------------------
echo "T12: no args → exit 2"
set +e
out=$(bash "$LINT" 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]]; then pass "exit 2 on no args"; else fail "expected 2, got $rc"; fi

# ----------------------------------------------------------------------
# Assertion-count floor — deleting cases or no-op-ing pass/fail must not let
# the suite certify nothing (the supabase-local.test.sh precedent).
# ----------------------------------------------------------------------
MIN_ASSERTIONS=22
echo ""
echo "lint-migration-api-grants.test.sh: $PASS passed, $FAIL failed"
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  echo "ASSERTION FLOOR BREACHED: ran $PASS, expected >= $MIN_ASSERTIONS." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
