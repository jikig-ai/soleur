#!/usr/bin/env bash
# Tests for the MIGRATION_SCHEMA_PRECONDITION_PROBE in run-migrations.sh
# (#4338). The probe extracts REFERENCES public.<table> mentions from
# each migration's body, subtracts same-file CREATE TABLE declarations,
# and verifies each remaining cross-file dependency exists in the live
# schema before applying the migration. Catches the schema-vs-ledger
# drift class one migration earlier than the FK parser, with a self-
# describing error that names the missing relation.
#
# Also covers the post-apply PostgREST reload hook (#8028): the runner
# invokes postgrest-reload-schema.sh on every run and propagates its exit
# code, so a rejected credential fails the migration job. A stub hook is
# planted in every temp tree (plant_reload_stub) so the relocated runner
# finds one; its exit code is driven by FAKE_RELOAD_HOOK_RC.
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

# Plant a stub postgrest-reload-schema.sh beside the relocated runner
# (#8028). The runner now calls the hook on EVERY run, so a tree without
# one would exit 127 before any assertion. The stub records that it ran
# (../hook-ran, i.e. $tmp/hook-ran) and exits FAKE_RELOAD_HOOK_RC.
# The heredoc MUST stay quoted: an unquoted one would expand
# `$(dirname "$0")` at plant time into THIS test's directory (touching a
# file inside the live repo) and freeze the rc default to 0, making the
# hook-failure cases vacuous.
plant_reload_stub() {
  local tmp="$1"
  cat > "$tmp/scripts/postgrest-reload-schema.sh" <<'STUB'
#!/usr/bin/env bash
# Stub reload hook for run-migrations-schema-probe.test.sh (#8028).
touch "$(dirname "$0")/../hook-ran"
exit "${FAKE_RELOAD_HOOK_RC:-0}"
STUB
  chmod +x "$tmp/scripts/postgrest-reload-schema.sh"
}

# Build a temp tree with the runner relocated and a fake psql.
#   $tmp/scripts/run-migrations.sh   (copy of real)
#   $tmp/supabase/migrations/099_test_missing_ref.sql
#   $tmp/bin/psql                    (fake)
make_temp_tree() {
  local tmp="$1"
  local bad_table="$2"
  mkdir -p "$tmp/bin" "$tmp/scripts" "$tmp/supabase/migrations"
  cp "$RUNNER" "$tmp/scripts/run-migrations.sh"
  plant_reload_stub "$tmp"
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
    # FAKE_ALREADY_APPLIED=1 → the migration is already in the ledger, so
    # the runner applies nothing (applied=0) — the R4 shape (#8028).
    echo "\${FAKE_ALREADY_APPLIED:-0}" ;;
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
plant_reload_stub "$tmp3"
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
# --- #8028: the post-apply reload hook runs on every run and its exit ----
# --- code reaches the runner's exit ---------------------------------------
# Probe is OFF for R1–R3 (their fixture references a missing table; the
# hook is what is under test, not the probe). Fake env goes on the env -i
# line — the harness strips the ambient environment.
# ------------------------------------------------------------------------
tmpr1=$(mktemp -d); tmpr2=$(mktemp -d); tmpr3=$(mktemp -d); tmpr4=$(mktemp -d)
trap 'rm -rf "$tmp1" "$tmp2" "$tmp2b" "$tmp3" "$tmpr1" "$tmpr2" "$tmpr3" "$tmpr4"' EXIT

echo "R1: apply + hook rc 0 → runner exit 0, hook ran, no ::error"
make_temp_tree "$tmpr1" "nonexistent_xyz_4338"
set +e
out=$(env -i PATH="$tmpr1/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        MIGRATION_SCHEMA_PRECONDITION_PROBE=0 \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        FAKE_RELOAD_HOOK_RC=0 \
        bash "$tmpr1/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] && [[ -e "$tmpr1/hook-ran" ]] && ! printf '%s' "$out" | grep -q '::error'; then
  pass "exit 0, hook ran, no ::error"
else
  fail "expected rc=0 + hook-ran + no ::error; got rc=$rc hook-ran=$([[ -e "$tmpr1/hook-ran" ]] && echo yes || echo no) out=$out"
fi

echo "R2: apply + hook rc 2 (rejected credential) → runner exit 2 with titled error"
make_temp_tree "$tmpr2" "nonexistent_xyz_4338"
set +e
out=$(env -i PATH="$tmpr2/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        MIGRATION_SCHEMA_PRECONDITION_PROBE=0 \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        FAKE_RELOAD_HOOK_RC=2 \
        bash "$tmpr2/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -qF '::error title=Supabase rejected the migration credential::'; then
  pass "exit 2 with the rejected-credential title"
else
  fail "expected rc=2 + titled error; got rc=$rc out=$out"
fi

echo "R3: apply + hook rc 127 (hook missing/bug) → runner exit 127 with the rc in the title"
make_temp_tree "$tmpr3" "nonexistent_xyz_4338"
set +e
out=$(env -i PATH="$tmpr3/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        MIGRATION_SCHEMA_PRECONDITION_PROBE=0 \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        FAKE_RELOAD_HOOK_RC=127 \
        bash "$tmpr3/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e
if [[ "$rc" == "127" ]] && printf '%s' "$out" | grep -qF '::error title=Schema reload hook failed (rc=127)::'; then
  pass "exit 127 propagated with the rc in the title"
else
  fail "expected rc=127 + titled error; got rc=$rc out=$out"
fi

echo "R4: nothing applied (already in ledger) + hook rc 2 → hook still runs, runner exit 2"
make_temp_tree "$tmpr4" "nonexistent_xyz_4338"
set +e
out=$(env -i PATH="$tmpr4/bin:/usr/bin:/bin" HOME="$HOME" \
        DATABASE_URL_POOLER="postgresql://fake@fake/fake" \
        MIGRATION_SCHEMA_PRECONDITION_PROBE=0 \
        ALLOW_UNMERGED_DEV_APPLY=1 \
        FAKE_ALREADY_APPLIED=1 \
        FAKE_RELOAD_HOOK_RC=2 \
        bash "$tmpr4/scripts/run-migrations.sh" --bootstrap=skip 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && [[ -e "$tmpr4/hook-ran" ]] && printf '%s' "$out" | grep -q '0 applied'; then
  pass "hook ran at applied=0 and its rc 2 failed the run"
else
  fail "expected rc=2 + hook-ran + '0 applied'; got rc=$rc hook-ran=$([[ -e "$tmpr4/hook-ran" ]] && echo yes || echo no) out=$out"
fi

# ------------------------------------------------------------------------
# --- #7795: the origin/main refresh must not auto-follow tags ------------
# This suite is why the assertion lives HERE. It copies run-migrations.sh
# into a tmp tree and runs it WITHOUT cd-ing (four times), so the script's
# un-`-C`'d `git fetch` executes with the LIVE repository as cwd — making
# this suite itself a battery-reachable author of refs/tags/**, which
# scripts/lib/repo-write-boundary.sh classifies as a suite writing to the
# operator's repo. Anchored on the whole fetch command, not a bare
# `--no-tags` grep: the flag landing on some other fetch would satisfy that
# while this site kept auto-following tags. Both counts are asserted, so a
# second unflagged fetch reddens this as well.
_nt_all=$({ grep -cE '^[[:space:]]*(if ! )?git fetch ' "$RUNNER" || true; })
_nt_ok=$({ grep -cE '^if ! git fetch( --[a-z-]+)* --no-tags( --[a-z-]+)* origin main ' "$RUNNER" || true; })
if [[ "$_nt_all" == "1" && "$_nt_ok" == "1" ]]; then
  pass "the origin/main refresh passes --no-tags (cannot write refs/tags/** into the live repo)"
else
  fail "fetch not --no-tags-scoped (fetch sites=$_nt_all, flagged=$_nt_ok; both must be 1)"
fi

# ------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"

# VACUITY FLOOR, reported DIRECTLY rather than through fail() (ADR-193): a
# floor enforced through the helper it backstops cannot witness that helper
# being neutered. Derived as the as-written case count, so deleting any arm
# — including the #7795 one above, which is a single line of source-grep and
# therefore the easiest to lose in an edit — reddens instead of shrinking
# the suite silently.
# Gated on assertions EXECUTED, not on PASS alone: keyed on PASS, one genuinely FAILING arm trips
# this first and reports "an arm was deleted or short-circuited" for a real defect, which is the
# wrong haystack to hand an operator (#7795 review). Deleted and failed are now distinguishable.
if [[ $((PASS + FAIL)) -lt 9 ]]; then
  printf '\n[FATAL] vacuity guard: only %d assertion(s) EXECUTED; expected >= 9.\n' "$((PASS + FAIL))" >&2
  printf '        An arm was deleted or short-circuited, or the floor needs a deliberate bump.\n' >&2
  exit 1
fi

[[ "$FAIL" == "0" ]] || exit 1
