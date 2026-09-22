#!/usr/bin/env bash
# Tests for lint-migration-immutability.sh (issue 8583 — the third leg of
# migration hygiene: on-main supabase/migrations files are immutable).
#
# Drives the guard over a SYNTHESIZED fixture repo (mktemp + git init —
# cq-test-fixtures-synthesized-only; the live tree's git state is never
# reused) covering the plan's mutation matrix:
#
#   1  modify an on-main migration (the #8507 shape)        -> rc 1, names file
#   2  delete an on-main migration                          -> rc 1
#   3  git mv an on-main migration (rename-detection evade) -> rc 1 (--no-renames)
#   4  add-collides: branch adds a path main gained post-divergence -> rc 1
#   5  diff touches migrations -> summary reports counted shape (audible)
#   6  stubbed oracle (ls-tree always empty) -> clean BUT checked=0 visible
#   7  add NNN beyond max-on-main                           -> rc 0
#   8  modify an on-main *.down.sql                         -> rc 0 (exempt)
#   9  bogus --base                                          -> rc 2 (fail closed)
#   10 wiring: tenant-integration.yml references the guard    -> else suite RED
#
# Run: bash apps/web-platform/scripts/lint-migration-immutability.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/lint-migration-immutability.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -f "$GUARD" ]]; then
  echo "ERROR: $GUARD not found" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

FIX="$tmp/fixture"
mkdir -p "$FIX/apps/web-platform/supabase/migrations"
git -C "$FIX" init -q -b main
git -C "$FIX" config user.email "fixture@example.invalid"
git -C "$FIX" config user.name "Fixture"
git -C "$FIX" config commit.gpgsign false

cat > "$FIX/apps/web-platform/supabase/migrations/001_a.sql" <<'SQL'
CREATE TABLE public.fixture_a (id uuid PRIMARY KEY);
SQL
cat > "$FIX/apps/web-platform/supabase/migrations/002_b.sql" <<'SQL'
CREATE TABLE public.fixture_b (id uuid PRIMARY KEY);
SQL
cat > "$FIX/apps/web-platform/supabase/migrations/003_b.down.sql" <<'SQL'
DROP TABLE public.fixture_b;
SQL
git -C "$FIX" add -A
git -C "$FIX" commit -qm 'base migrations'

run_guard() {
  set +e
  out=$(bash "$GUARD" --repo "$FIX" --base main --head feat 2>&1)
  rc=$?
  set -e
}

reset_feat() {
  git -C "$FIX" switch -qC feat main
}

# ----------------------------------------------------------------------
echo "T1: modify an on-main migration -> rc 1, names the file"
# ----------------------------------------------------------------------
reset_feat
printf 'ALTER TABLE public.fixture_b ADD COLUMN extra int;\n' >> "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" commit -qam 'mutate 002'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '002_b.sql'; then
  pass "rc=1 names the mutated file"
else
  fail "expected rc=1 naming 002_b.sql; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T2: delete an on-main migration -> rc 1"
# ----------------------------------------------------------------------
reset_feat
git -C "$FIX" rm -q apps/web-platform/supabase/migrations/001_a.sql
git -C "$FIX" commit -qm 'delete 001'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '001_a.sql'; then
  pass "rc=1 names the deleted file"
else
  fail "expected rc=1 naming 001_a.sql; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T3: git mv on an on-main migration -> rc 1 (rename detection cannot hide the source)"
# ----------------------------------------------------------------------
reset_feat
git -C "$FIX" mv apps/web-platform/supabase/migrations/001_a.sql apps/web-platform/supabase/migrations/010_a.sql
git -C "$FIX" commit -qm 'rename 001 -> 010'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '001_a.sql'; then
  pass "rc=1 names the rename SOURCE (--no-renames is load-bearing)"
else
  fail "expected rc=1 naming 001_a.sql; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T4: add-collides — branch adds a path main gained after divergence -> rc 1"
# ----------------------------------------------------------------------
reset_feat
# main gains 009_late.sql while feat diverges with its own 009_late.sql.
git -C "$FIX" switch -q main
cat > "$FIX/apps/web-platform/supabase/migrations/009_late.sql" <<'SQL'
CREATE TABLE public.late_main (id uuid PRIMARY KEY);
SQL
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'main adds 009_late'
git -C "$FIX" switch -q feat
# feat branched before main's 009_late commit: rewrite feat off the OLD main.
git -C "$FIX" reset -q --hard "$(git -C "$FIX" rev-parse main~1)"
cat > "$FIX/apps/web-platform/supabase/migrations/009_late.sql" <<'SQL'
CREATE TABLE public.late_feat (id uuid PRIMARY KEY, different int);
SQL
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'feat adds colliding 009_late'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '009_late.sql'; then
  pass "rc=1 names the colliding path (ls-tree identity, not diff status)"
else
  fail "expected rc=1 naming 009_late.sql; got rc=$rc out=$out"
fi
# restore fixture main/feat relationship for later cases
git -C "$FIX" switch -q main
git -C "$FIX" reset -q --hard HEAD

# ----------------------------------------------------------------------
echo "T5: diff touches migrations -> summary reports the counted shape"
# ----------------------------------------------------------------------
reset_feat
printf 'SELECT 1;\n' >> "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" commit -qam 'touch 002 again'
run_guard
if printf '%s' "$out" | grep -qE 'touched=[1-9]' && printf '%s' "$out" | grep -qE 'on-main-checked=[1-9]'; then
  pass "summary exposes touched>=1 and on-main-checked>=1 (no silent zero-row enumeration)"
else
  fail "expected counted summary with touched/on-main-checked >=1; got out=$out"
fi

# ----------------------------------------------------------------------
echo "T6: stubbed oracle — ls-tree returns empty -> clean BUT checked=0 is visible"
# ----------------------------------------------------------------------
# A git stub whose ls-tree emits nothing makes every touched path look
# 'new'. The guard cannot distinguish that from a real all-new diff, so
# the contract is observability: the report must state on-main-checked=0
# plus the ::notice::, so a degenerate pass is never indistinguishable
# from a real check.
STUB="$tmp/gitstub"
mkdir -p "$STUB"
cat > "$STUB/git" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == "ls-tree" ]]; then exit 0; fi
done
# forward everything else to the real git
exec /usr/bin/git "$@"
SH
chmod +x "$STUB/git"
set +e
out=$(cd "$FIX" && PATH="$STUB:$PATH" bash "$GUARD" --repo "$FIX" --base main --head feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'on-main-checked=0' && printf '%s' "$out" | grep -q '::notice::migration-immutability: 0 on-main migration files checked'; then
  pass "stubbed-oracle clean is self-describing (checked=0 + notice), not a silent green"
else
  fail "expected rc=0 with visible checked=0 notice under stubbed ls-tree; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T7: add a file numbered beyond max-on-main -> rc 0"
# ----------------------------------------------------------------------
reset_feat
cat > "$FIX/apps/web-platform/supabase/migrations/140_new.sql" <<'SQL'
CREATE TABLE public.new_beyond_max (id uuid PRIMARY KEY);
SQL
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'add 140_new'
run_guard
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'migration-immutability: clean'; then
  pass "rc=0 — numbering beyond max-on-main is free to iterate"
else
  fail "expected rc=0 clean; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T8: modify an on-main *.down.sql -> rc 0 (documented exemption)"
# ----------------------------------------------------------------------
reset_feat
printf 'DROP TABLE public.fixture_b;\n' >> "$FIX/apps/web-platform/supabase/migrations/003_b.down.sql"
git -C "$FIX" commit -qam 'edit down file'
run_guard
if [[ "$rc" == "0" ]]; then
  pass "rc=0 — down files are never applied or ledgered"
else
  fail "expected rc=0 for down.sql edit; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T9: bogus --base -> rc 2 (fail closed on cannot-measure)"
# ----------------------------------------------------------------------
set +e
out=$(bash "$GUARD" --repo "$FIX" --base bogus-ref-does-not-exist --head feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]]; then
  pass "rc=2 on unresolvable base ref"
else
  fail "expected rc=2; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T10: wiring — tenant-integration.yml names the guard script"
# ----------------------------------------------------------------------
if grep -q 'lint-migration-immutability' "$REPO_ROOT/.github/workflows/tenant-integration.yml"; then
  pass "workflow wiring present"
else
  fail "tenant-integration.yml does not reference lint-migration-immutability — guard is detached"
fi

echo ""
echo "lint-migration-immutability.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
