#!/usr/bin/env bash
# Tests for the MIGRATION_SCHEMA_PRECONDITION_PROBE in run-migrations.sh
# (#4338). The probe extracts REFERENCES public.<table> mentions from
# each migration's body, subtracts same-file CREATE TABLE declarations,
# and verifies each remaining cross-file dependency exists in the live
# schema before applying the migration. Catches the schema-vs-ledger
# drift class one migration earlier than the FK parser, with a self-
# describing error that names the missing relation.
#
# Run via: bash apps/web-platform/scripts/run-migrations-schema-probe.test.sh
#
# Test environment: each test builds a temp tree with a fake `psql` on
# PATH that returns canned responses based on the SQL it receives. The
# live DATABASE_URL is never touched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/run-migrations.sh"

if [[ ! -f "$RUNNER" ]]; then
  echo "ERROR: $RUNNER not found" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

# Allocate all temp dirs upfront with a single trap so partial-failure
# in any test still cleans up every dir. Cascading per-test `trap …
# EXIT` lines (the prior shape) only register the LAST tmpdir mentioned;
# if make_temp_tree errors between trap installs, earlier dirs leak.
# Single-quote the trap body so the variables expand at signal-fire
# time, not at trap-install time (avoids shellcheck SC2064 class).
tmp1=$(mktemp -d)
tmp2=$(mktemp -d)
tmp3=$(mktemp -d)
trap 'rm -rf "$tmp1" "$tmp2" "$tmp3"' EXIT

# Build a temp tree with the runner relocated and a fake psql.
#   $tmp/scripts/run-migrations.sh   (copy of real)
#   $tmp/supabase/migrations/099_test_missing_ref.sql
#   $tmp/bin/psql                    (fake)
make_temp_tree() {
  local tmp="$1"
  local bad_table="$2"
  mkdir -p "$tmp/bin" "$tmp/scripts" "$tmp/supabase/migrations"
  cp "$RUNNER" "$tmp/scripts/run-migrations.sh"
  cat > "$tmp/supabase/migrations/099_test_missing_ref.sql" <<SQL
-- Test migration: references a deliberately-missing table.
CREATE TABLE IF NOT EXISTS public.test_dependent_4338 (
  id uuid PRIMARY KEY,
  ref_id uuid REFERENCES public.${bad_table}(id) ON DELETE CASCADE
);
SQL
  cat > "$tmp/bin/psql" <<FAKE
#!/usr/bin/env bash
# Fake psql for run-migrations-schema-probe.test.sh.
# Parses -c <SQL> and emits canned responses based on substring match.
# Stdin invocations (apply path) consume + return 0.
sql=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -c) sql="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -z "\$sql" ]]; then
  # apply path — consume + succeed
  cat > /dev/null
  exit 0
fi
case "\$sql" in
  *"to_regclass('public.${bad_table}')"*)
    echo "f" ;;
  *"to_regclass("*)
    # Default: every other to_regclass returns true (table exists)
    echo "t" ;;
  *"count(*) FROM public._schema_migrations WHERE filename"*)
    echo "0" ;;
  *"count(*) FROM public._schema_migrations"*)
    echo "0" ;;
  *)
    : ;;
esac
exit 0
FAKE
  chmod +x "$tmp/bin/psql"
}

# ------------------------------------------------------------------------
# T1 — Probe ENABLED + missing-table reference → non-zero exit with table
#       name in error message. This is the load-bearing diagnostic case
#       the probe exists to surface.
# ------------------------------------------------------------------------
echo "T1: probe enabled, missing referenced table → fail with named relation"
make_temp_tree "$tmp1" "nonexistent_xyz_4338"

set +e
# env -i strips host env (matches postgrest-reload-schema.test.sh:53) so
# host-exported MIGRATION_SCHEMA_PRECONDITION_PROBE / ALLOW_UNMERGED_DEV_APPLY
# can't bleed in and mask T2/T3's opt-in / self-ref-subtract assertions.
out=$(env -i PATH="$tmp1/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        MIGRATION_SCHEMA_PRECONDITION_PROBE=1 \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        bash "$tmp1/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e

if [[ "$rc" != "0" ]] && printf '%s' "$out" | grep -q 'nonexistent_xyz_4338'; then
  pass "exit $rc with nonexistent_xyz_4338 in error"
else
  fail "expected non-zero exit + table name in error; got rc=$rc, out=$out"
fi

# ------------------------------------------------------------------------
# T2 — Probe explicit opt-out (MIGRATION_SCHEMA_PRECONDITION_PROBE=0) →
#       does NOT block apply on the missing-table reference. The probe
#       defaults to ON (#4325 follow-up); explicit "=0" is the documented
#       escape hatch when the FK parser is the only desired line of
#       defense.
# ------------------------------------------------------------------------
echo "T2: probe explicit opt-out (=0) → apply proceeds (no probe-emitted error)"
make_temp_tree "$tmp2" "nonexistent_xyz_4338"

set +e
out=$(env -i PATH="$tmp2/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        MIGRATION_SCHEMA_PRECONDITION_PROBE=0 \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        bash "$tmp2/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e

# When probe is OFF, the runner reaches the apply phase. Our fake psql
# accepts stdin and returns 0, so the apply succeeds. The probe-emitted
# error string must NOT appear.
if [[ "$rc" == "0" ]] && ! printf '%s' "$out" | grep -q 'references tables that do not exist'; then
  pass "exit 0; probe error message absent"
else
  fail "expected rc=0 + no probe error; got rc=$rc, out=$out"
fi

# ------------------------------------------------------------------------
# T2b — Probe ENABLED via default (env unset) → MUST block apply on the
#       missing-table reference. Verifies the #4325-follow-up default
#       flip ({:-1} in run-migrations.sh:276): operator-local invocations
#       get the same protection CI gets without needing to set the env.
# ------------------------------------------------------------------------
echo "T2b: probe default-on (env unset) → fail with named relation"
tmp2b=$(mktemp -d)
trap 'rm -rf "$tmp1" "$tmp2" "$tmp2b" "$tmp3"' EXIT
make_temp_tree "$tmp2b" "nonexistent_xyz_4338"

set +e
# Note: NO MIGRATION_SCHEMA_PRECONDITION_PROBE in env. The default ({:-1})
# inside the runner must enable the probe.
out=$(env -i PATH="$tmp2b/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        bash "$tmp2b/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e

if [[ "$rc" != "0" ]] && printf '%s' "$out" | grep -q 'nonexistent_xyz_4338'; then
  pass "exit $rc with nonexistent_xyz_4338 in error (default-on)"
else
  fail "expected non-zero exit + table name; got rc=$rc, out=$out"
fi

# ------------------------------------------------------------------------
# T3 — Probe ENABLED + same-file CREATE TABLE matches REFERENCES (self-
#       FK pattern, e.g. mig 053's workspace_members → workspaces).
#       MUST NOT fail on the self-reference: the probe subtracts same-
#       file CREATEs from the referenced set so fresh-DB first-apply
#       works even when a table both creates and references itself.
# ------------------------------------------------------------------------
echo "T3: probe enabled, self-referencing CREATE TABLE → does not block"
mkdir -p "$tmp3/bin" "$tmp3/scripts" "$tmp3/supabase/migrations"
cp "$RUNNER" "$tmp3/scripts/run-migrations.sh"
# Migration that both CREATES public.parent_4338 AND has an FK to it
# (mirrors mig 053's workspaces self-reference shape).
cat > "$tmp3/supabase/migrations/099_test_self_ref.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS public.parent_4338 (id uuid PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.child_4338 (
  id uuid PRIMARY KEY,
  parent_id uuid REFERENCES public.parent_4338(id) ON DELETE CASCADE
);
SQL

# Fake psql that returns 'f' for parent_4338 (it doesn't exist yet — we
# are checking the probe SUBTRACTS the same-file CREATE before querying).
cat > "$tmp3/bin/psql" <<'FAKE'
#!/usr/bin/env bash
sql=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) sql="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -z "$sql" ]]; then
  cat > /dev/null
  exit 0
fi
case "$sql" in
  *"to_regclass('public.parent_4338')"*) echo "f" ;;
  *"to_regclass("*) echo "t" ;;
  *"count(*) FROM public._schema_migrations"*) echo "0" ;;
  *) : ;;
esac
exit 0
FAKE
chmod +x "$tmp3/bin/psql"

set +e
out=$(env -i PATH="$tmp3/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        MIGRATION_SCHEMA_PRECONDITION_PROBE=1 \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        bash "$tmp3/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e

# parent_4338 is self-referenced — probe must SUBTRACT it. Apply
# proceeds, exit 0, probe error absent.
if [[ "$rc" == "0" ]] && ! printf '%s' "$out" | grep -q 'parent_4338'; then
  pass "exit 0; self-reference subtracted (parent_4338 not in error)"
else
  fail "expected rc=0 + no parent_4338 error; got rc=$rc, out=$out"
fi

# ------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1
