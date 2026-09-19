#!/usr/bin/env bash
# Hermetic cases for plugins/soleur/scripts/sync-pr-behind.sh:
#   CLEAN  → exit 0, no merge
#   BEHIND + merge-tree clean → merge + push
#   DIRTY  + merge-tree rc=0  → merge + push (the kb-index GitHub-DIRTY class)
#   DIRTY  + merge-tree rc≠0  → exit 6
#   BEHIND + merge in progress (staged resolution) → exit 9, nothing aborted (#8339)
#
# Synthesized file:// repos. PATH-shimmed `gh`. No network.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUT="$REPO_ROOT/plugins/soleur/scripts/sync-pr-behind.sh"

# test-helpers.sh owns assert_fixture_dir -- the guard the fixture scanners
# (fixture-relative-assert, fixture-dir-operand-assert) recognize -- and
# git_fixture_env, the hermetic env for this suite's git fixture writes. It
# sets -euo pipefail, so the +e below restores this suite's
# accumulate-then-exit contract.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

FIXTURES=()
cleanup_fixtures() { rm -rf ${FIXTURES[@]+"${FIXTURES[@]}"}; }
trap cleanup_fixtures EXIT

make_pair() {
  local d="$1"
  assert_fixture_dir "$d"
  git_fixture_env "$d" || return 1
  git init -q --bare "$d/origin.git"
  git clone -q "file://$d/origin.git" "$d/work"
  git -C "$d/work" config user.email t@t
  git -C "$d/work" config user.name t
  echo base > "$d/work/f"
  git -C "$d/work" add f && git -C "$d/work" commit -q -m base
  git -C "$d/work" branch -M main
  git -C "$d/work" push -q origin main
  git -C "$d/work" checkout -q -b feat
  echo feat > "$d/work/g"
  git -C "$d/work" add g && git -C "$d/work" commit -q -m feat
  git -C "$d/work" push -q -u origin feat
  # SUT computes REPO_ROOT from BASH_SOURCE and `cd`s there. Copy it into
  # the temp tree so a run cannot fetch/merge/push the live worktree.
  mkdir -p "$d/work/plugins/soleur/scripts"
  cp "$SUT" "$d/work/plugins/soleur/scripts/sync-pr-behind.sh"
}

# First `gh pr view` returns $2; subsequent views return OPEN CLEAN so a
# successful sync is not scored as "still BEHIND" (exit 8).
install_gh() {
  local bin="$1" first_state="$2"
  assert_fixture_dir "$bin"
  mkdir -p "$bin"
  printf '%s\n' "0" > "$bin/gh-n"
  cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
nfile=\$(dirname "\$0")/gh-n
n=\$(cat "\$nfile")
n=\$((n+1))
echo "\$n" > "\$nfile"
if [[ "\$n" -eq 1 ]]; then
  echo "$first_state"
else
  echo "OPEN CLEAN"
fi
exit 0
EOF
  chmod +x "$bin/gh"
}

# --- CLEAN: no sync -----------------------------------------------------------
CLEAN="$(mktemp -d "$TMPDIR/sync-behind-clean.XXXXXXXX")"
FIXTURES+=("$CLEAN")
make_pair "$CLEAN"
install_gh "$CLEAN/bin" "OPEN CLEAN"
sha_before="$(git -C "$CLEAN/work" rev-parse HEAD)"
PATH="$CLEAN/bin:$PATH" bash "$CLEAN/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 >"$CLEAN/out" 2>&1
rc=$?
sha_after="$(git -C "$CLEAN/work" rev-parse HEAD)"
if [[ "$rc" -eq 0 && "$sha_before" == "$sha_after" ]] \
   && grep -q 'no sync needed' "$CLEAN/out"; then
  pass "CLEAN: exit 0, SHA unchanged"
else
  fail "CLEAN: rc=$rc sha_changed=$([[ "$sha_before" != "$sha_after" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$CLEAN/out")"
fi
rm -rf "$CLEAN"

# --- BEHIND + clean merge-tree -----------------------------------------------
BEHIND="$(mktemp -d "$TMPDIR/sync-behind-behind.XXXXXXXX")"
FIXTURES+=("$BEHIND")
make_pair "$BEHIND"
# Advance origin/main with a non-conflicting commit.
git clone -q "file://$BEHIND/origin.git" "$BEHIND/mainwt"
git -C "$BEHIND/mainwt" config user.email t@t
git -C "$BEHIND/mainwt" config user.name t
git -C "$BEHIND/mainwt" checkout -q main
echo extra > "$BEHIND/mainwt/h"
git -C "$BEHIND/mainwt" add h && git -C "$BEHIND/mainwt" commit -q -m extra
git -C "$BEHIND/mainwt" push -q origin main
install_gh "$BEHIND/bin" "OPEN BEHIND"
sha_before="$(git -C "$BEHIND/work" rev-parse HEAD)"
PATH="$BEHIND/bin:$PATH" bash "$BEHIND/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 >"$BEHIND/out" 2>&1
rc=$?
sha_after="$(git -C "$BEHIND/work" rev-parse HEAD)"
if [[ "$rc" -eq 0 && "$sha_before" != "$sha_after" ]] \
   && grep -q '\[pr-behind-sync\]' "$BEHIND/out" \
   && grep -q 'auto-sync' "$BEHIND/out"; then
  pass "BEHIND clean: merge+push, auto-sync token"
else
  fail "BEHIND clean: rc=$rc sha_changed=$([[ "$sha_before" != "$sha_after" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$BEHIND/out")"
fi
rm -rf "$BEHIND"

# --- DIRTY + merge-tree rc=0 (GitHub DIRTY, locally clean) -------------------
DIRTY_CLEAN="$(mktemp -d "$TMPDIR/sync-behind-dirty-clean.XXXXXXXX")"
FIXTURES+=("$DIRTY_CLEAN")
make_pair "$DIRTY_CLEAN"
git clone -q "file://$DIRTY_CLEAN/origin.git" "$DIRTY_CLEAN/mainwt"
git -C "$DIRTY_CLEAN/mainwt" config user.email t@t
git -C "$DIRTY_CLEAN/mainwt" config user.name t
git -C "$DIRTY_CLEAN/mainwt" checkout -q main
echo extra > "$DIRTY_CLEAN/mainwt/h"
git -C "$DIRTY_CLEAN/mainwt" add h && git -C "$DIRTY_CLEAN/mainwt" commit -q -m extra
git -C "$DIRTY_CLEAN/mainwt" push -q origin main
install_gh "$DIRTY_CLEAN/bin" "OPEN DIRTY"
sha_before="$(git -C "$DIRTY_CLEAN/work" rev-parse HEAD)"
PATH="$DIRTY_CLEAN/bin:$PATH" bash "$DIRTY_CLEAN/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 >"$DIRTY_CLEAN/out" 2>&1
rc=$?
sha_after="$(git -C "$DIRTY_CLEAN/work" rev-parse HEAD)"
if [[ "$rc" -eq 0 && "$sha_before" != "$sha_after" ]] \
   && grep -q '\[pr-behind-sync\]' "$DIRTY_CLEAN/out" \
   && grep -q 'auto-sync' "$DIRTY_CLEAN/out"; then
  pass "DIRTY merge-tree-clean: merge+push"
else
  fail "DIRTY merge-tree-clean: rc=$rc sha_changed=$([[ "$sha_before" != "$sha_after" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$DIRTY_CLEAN/out")"
fi
rm -rf "$DIRTY_CLEAN"

# --- DIRTY + merge-tree conflict ---------------------------------------------
DIRTY_CONFLICT="$(mktemp -d "$TMPDIR/sync-behind-dirty-conflict.XXXXXXXX")"
FIXTURES+=("$DIRTY_CONFLICT")
make_pair "$DIRTY_CONFLICT"
git clone -q "file://$DIRTY_CONFLICT/origin.git" "$DIRTY_CONFLICT/mainwt"
git -C "$DIRTY_CONFLICT/mainwt" config user.email t@t
git -C "$DIRTY_CONFLICT/mainwt" config user.name t
git -C "$DIRTY_CONFLICT/mainwt" checkout -q main
echo main-side > "$DIRTY_CONFLICT/mainwt/f"
git -C "$DIRTY_CONFLICT/mainwt" commit -q -am main-side
git -C "$DIRTY_CONFLICT/mainwt" push -q origin main
# Feature also edited f.
echo feat-side > "$DIRTY_CONFLICT/work/f"
git -C "$DIRTY_CONFLICT/work" commit -q -am feat-side
git -C "$DIRTY_CONFLICT/work" push -q origin feat
install_gh "$DIRTY_CONFLICT/bin" "OPEN DIRTY"
PATH="$DIRTY_CONFLICT/bin:$PATH" bash "$DIRTY_CONFLICT/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 >"$DIRTY_CONFLICT/out" 2>&1
rc=$?
if [[ "$rc" -eq 6 ]]; then
  pass "DIRTY merge-tree-conflict: exit 6"
else
  fail "DIRTY merge-tree-conflict: rc=$rc (want 6) out=$(tr '\n' ' ' < "$DIRTY_CONFLICT/out")"
fi
rm -rf "$DIRTY_CONFLICT"

# --- BEHIND + a merge already in progress: refuse, abort nothing (#8339) ------
INPROG="$(mktemp -d "$TMPDIR/sync-behind-inprogress.XXXXXXXX")"
FIXTURES+=("$INPROG")
make_pair "$INPROG"
git clone -q "file://$INPROG/origin.git" "$INPROG/mainwt"
git -C "$INPROG/mainwt" config user.email t@t
git -C "$INPROG/mainwt" config user.name t
git -C "$INPROG/mainwt" checkout -q main
echo main-side > "$INPROG/mainwt/f"
git -C "$INPROG/mainwt" commit -q -am main-side
git -C "$INPROG/mainwt" push -q origin main
echo feat-side > "$INPROG/work/f"
git -C "$INPROG/work" commit -q -am feat-side
git -C "$INPROG/work" push -q origin feat
# The operator started the merge, hit the conflict, and staged a resolution.
git -C "$INPROG/work" fetch -q origin main
git -C "$INPROG/work" merge origin/main --no-edit >/dev/null 2>&1
echo resolved > "$INPROG/work/f"
git -C "$INPROG/work" add f
install_gh "$INPROG/bin" "OPEN BEHIND"
PATH="$INPROG/bin:$PATH" bash "$INPROG/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 >"$INPROG/out" 2>&1
rc=$?
if [[ "$rc" -eq 9 ]] \
   && git -C "$INPROG/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ "$(git -C "$INPROG/work" diff --cached --name-only)" == "f" ]] \
   && [[ "$(cat "$INPROG/work/f")" == "resolved" ]] \
   && grep -q 'merge in progress' "$INPROG/out"; then
  pass "BEHIND merge-in-progress: exit 9, MERGE_HEAD kept, staged resolution survived"
else
  fail "BEHIND merge-in-progress: rc=$rc (want 9) merge_head=$(git -C "$INPROG/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && echo yes || echo no) staged=$(git -C "$INPROG/work" diff --cached --name-only | tr '\n' ' ') out=$(tr '\n' ' ' < "$INPROG/out")"
fi
rm -rf "$INPROG"

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 && "$PASS" -eq 5 ]]
exit $?
