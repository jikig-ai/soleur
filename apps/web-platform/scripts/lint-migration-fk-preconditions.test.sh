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

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

# The body below is the CANONICAL copy, asserted byte-for-byte against every other copy by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

tmp=$(mktemp -d -t fkprecond.XXXXXXXX) || { echo "harness: mktemp -d failed" >&2; exit 2; }
assert_fixture_dir "$tmp"
trap 'rm -rf "$tmp"' EXIT
# Fixture env (author/committer identity, no developer config) in THIS shell: the mk_* helpers run in command substitutions, so
# exports made there never reach the parent's later `git commit` calls, which fail on a runner with no global identity.
git_fixture_env "$tmp" || { echo "harness: git_fixture_env refused $tmp" >&2; exit 2; }

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

if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -c >/dev/null 't1_parent_in_another_mig'; then
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
# --from-pr-diff rows (D7 remainder): the diff read must fail closed (a git
# failure is exit 2, never "nothing to check"), see a rename as a new file to
# lint (--no-renames), and see a name git would C-quote (-z).
# ----------------------------------------------------------------------
UNGUARDED_SQL='CREATE TABLE public.pr_child_lint_test (
  id uuid PRIMARY KEY,
  parent_id uuid REFERENCES public.pr_parent_in_another_mig(id)
);'
GUARDED_SQL="DO \$\$ BEGIN IF to_regclass('public.pr_parent_in_another_mig') IS NULL THEN RAISE EXCEPTION 'x'; END IF; END \$\$;
$UNGUARDED_SQL"

# mk_pr_repo <name> <with-origin-main: 1|0> — a scratch repo laid out like the real one (the lint
# resolves REPO_ROOT from its own location), base commit holds one unguarded migration.
mk_pr_repo() {
  local d="$tmp/$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/apps/web-platform/scripts" "$d/apps/web-platform/supabase/migrations" || return 1
  git_fixture_env "$d" || return 1
  cp "$LINT" "$d/apps/web-platform/scripts/lint-migration-fk-preconditions.sh" || return 1
  printf '%s\n' "$UNGUARDED_SQL" > "$d/apps/web-platform/supabase/migrations/100_base.sql"
  git -C "$d" init -q -b main || return 1
  git -C "$d" add -A >/dev/null 2>&1 || return 1
  git -C "$d" commit -q -m base || return 1
  if [[ "$2" == "1" ]]; then
    git -C "$d" update-ref refs/remotes/origin/main HEAD || return 1
  fi
  printf '%s' "$d"
}

# run_pr <repo> — sets PR_RC / PR_OUT
run_pr() {
  assert_fixture_dir "$1"
  set +e
  PR_OUT=$(cd "$1" && bash apps/web-platform/scripts/lint-migration-fk-preconditions.sh --from-pr-diff 2>&1)
  PR_RC=$?
  set -e
}

MIGDIR=apps/web-platform/supabase/migrations

echo "T5: --from-pr-diff with an unresolvable origin/main → exit 2 (git failure is not 'nothing to check')"
d=$(mk_pr_repo nobase 0)
assert_fixture_dir "$d"
run_pr "$d"
if [[ "$PR_RC" == "2" ]]; then pass "exit 2 on a failing diff"; else fail "expected rc=2; got rc=$PR_RC, out=$PR_OUT"; fi

echo "T6: --from-pr-diff, unguarded migration added → exit 1 (git arm control)"
d=$(mk_pr_repo added 1)
assert_fixture_dir "$d"
printf '%s\n' "$UNGUARDED_SQL" > "$d/$MIGDIR/101_added.sql"
git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -q -m add
run_pr "$d"
if [[ "$PR_RC" == "1" ]]; then pass "exit 1; added file linted"; else fail "expected rc=1; got rc=$PR_RC, out=$PR_OUT"; fi

echo "T7: --from-pr-diff, guarded migration added → exit 0"
d=$(mk_pr_repo addedok 1)
assert_fixture_dir "$d"
printf '%s\n' "$GUARDED_SQL" > "$d/$MIGDIR/101_ok.sql"
git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -q -m add
run_pr "$d"
if [[ "$PR_RC" == "0" ]] && grep -qF '1 file(s) checked' <<<"$PR_OUT"; then pass "exit 0; guarded file checked"; else fail "expected rc=0 + 1 file checked; got rc=$PR_RC, out=$PR_OUT"; fi

echo "T8: --from-pr-diff, unguarded migration RENAMED → linted at its new path (exit 1)"
d=$(mk_pr_repo renamed 1)
assert_fixture_dir "$d"
git -C "$d" mv "$d/$MIGDIR/100_base.sql" "$d/$MIGDIR/102_renamed.sql"
git -C "$d" commit -q -m rename
run_pr "$d"
if [[ "$PR_RC" == "1" ]]; then pass "exit 1; renamed file linted"; else fail "expected rc=1; got rc=$PR_RC, out=$PR_OUT"; fi

echo "T9: --from-pr-diff, a name git would C-quote (non-ASCII, tab) → linted (exit 1)"
for variant in "caf$(printf '\303\251').sql" "a$(printf '\t')b.sql"; do
  d=$(mk_pr_repo "quoted-$(printf '%s' "$variant" | od -An -tx1 | tr -d ' \n')" 1)
  assert_fixture_dir "$d"
  printf '%s\n' "$UNGUARDED_SQL" > "$d/$MIGDIR/103_$variant"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -q -m quoted
  run_pr "$d"
  if [[ "$PR_RC" == "1" ]]; then pass "exit 1; quoted-name file linted"; else fail "expected rc=1 for a quoted name; got rc=$PR_RC, out=$PR_OUT"; fi
done

# ----------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1
