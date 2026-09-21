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
# Owning trap installed BEFORE the helper is sourced: test-helpers.sh composes its
# incident-sandbox cleanup over an existing EXIT trap, whereas a trap installed
# afterwards replaces it and leaks the sandbox on every run (#8339 review).
FIXTURES=()
cleanup_fixtures() { rm -rf ${FIXTURES[@]+"${FIXTURES[@]}"}; }
trap cleanup_fixtures EXIT
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }


# The SUT operates on $PWD by design (it syncs the CALLER's worktree). That makes an
# un-cd'd invocation a live-repo hazard, so every case below runs inside `( cd "$X/work" && … )`
# and this guard turns a failed cd into an abort rather than a silent fall-through to the
# runner's own checkout. Before the BASH_SOURCE escape was removed the SUT's own `cd` masked
# this; it was protection by accident, and it was the same line that made the script sync the
# wrong repository in production.
assert_in_fixture() {
  local want="$1"
  [[ "$PWD" == "$want" ]] || { echo "FATAL: fixture cd failed, refusing to run against $PWD" >&2; exit 97; }
}

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
( cd "$CLEAN/work" && PATH="$CLEAN/bin:$PATH" bash "$CLEAN/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$CLEAN/out" 2>&1
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
( cd "$BEHIND/work" && PATH="$BEHIND/bin:$PATH" bash "$BEHIND/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$BEHIND/out" 2>&1
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
( cd "$DIRTY_CLEAN/work" && PATH="$DIRTY_CLEAN/bin:$PATH" bash "$DIRTY_CLEAN/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$DIRTY_CLEAN/out" 2>&1
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
( cd "$DIRTY_CONFLICT/work" && PATH="$DIRTY_CONFLICT/bin:$PATH" bash "$DIRTY_CONFLICT/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$DIRTY_CONFLICT/out" 2>&1
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
git -C "$INPROG/work" fetch -q --no-tags origin main
git -C "$INPROG/work" merge origin/main --no-edit >/dev/null 2>&1
echo resolved > "$INPROG/work/f"
git -C "$INPROG/work" add f
install_gh "$INPROG/bin" "OPEN BEHIND"
( cd "$INPROG/work" && PATH="$INPROG/bin:$PATH" bash "$INPROG/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$INPROG/out" 2>&1
rc=$?
if [[ "$rc" -eq 9 ]] \
   && git -C "$INPROG/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ "$(git -C "$INPROG/work" diff --cached --name-only)" == "f" ]] \
   && [[ "$(cat "$INPROG/work/f")" == "resolved" ]] \
   && grep -q 'kind=merge_in_progress' "$INPROG/out"; then
  pass "BEHIND merge-in-progress: exit 9, MERGE_HEAD kept, staged resolution survived"
else
  fail "BEHIND merge-in-progress: rc=$rc (want 9) merge_head=$(git -C "$INPROG/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && echo yes || echo no) staged=$(git -C "$INPROG/work" diff --cached --name-only | tr '\n' ' ') out=$(tr '\n' ' ' < "$INPROG/out")"
fi
rm -rf "$INPROG"

# --- SUT OUTSIDE THE TARGET REPO: operates on the CALLER's worktree, not its own ----------
#
# THE CONFIGURATION PRODUCTION ACTUALLY HAS, and the one every case above lacks. The others
# `cp` the SUT into their fixture repo, so the script's directory and the target are the SAME
# directory — under which a `cd "$(dirname "$BASH_SOURCE")/../../.."` is a no-op and its effect
# is unobservable. In production the script lives in the plugin install (or the primary
# checkout) while the target is a worktree: two different directories.
#
# This case makes the difference load-bearing by putting a DECOY repo exactly where the old
# BASH_SOURCE arithmetic pointed, on its own branch. Under the pre-fix code the run relocates
# into the decoy and syncs THAT; under the fix it stays in the caller's worktree. Assert both
# halves — the caller's repo moved AND the decoy did not — so a fix that merely stops working
# cannot pass.
OUTSIDE="$(mktemp -d "$TMPDIR/sync-behind-outside.XXXXXXXX")"
FIXTURES+=("$OUTSIDE")
make_pair "$OUTSIDE"
# Advance origin/main so the caller's `feat` is genuinely BEHIND and a sync must move it.
git -C "$OUTSIDE/work" checkout -q main
echo more > "$OUTSIDE/work/h"
git -C "$OUTSIDE/work" add h && git -C "$OUTSIDE/work" commit -q -m more
git -C "$OUTSIDE/work" push -q origin main
git -C "$OUTSIDE/work" checkout -q feat
# The decoy sits where `<script>/../../..` resolves, and is a valid repo on its own branch —
# i.e. the "primary checkout on a feature branch" case, which is the dangerous one.
mkdir -p "$OUTSIDE/decoy/plugins/soleur/scripts"
git init -q "$OUTSIDE/decoy"
git -C "$OUTSIDE/decoy" config user.email t@t
git -C "$OUTSIDE/decoy" config user.name t
echo decoy > "$OUTSIDE/decoy/d"
git -C "$OUTSIDE/decoy" add d && git -C "$OUTSIDE/decoy" commit -q -m decoy
git -C "$OUTSIDE/decoy" checkout -q -b decoy-branch
cp "$SUT" "$OUTSIDE/decoy/plugins/soleur/scripts/sync-pr-behind.sh"
install_gh "$OUTSIDE/bin" "OPEN BEHIND"
work_before="$(git -C "$OUTSIDE/work" rev-parse HEAD)"
decoy_before="$(git -C "$OUTSIDE/decoy" rev-parse HEAD)"
decoy_branch_before="$(git -C "$OUTSIDE/decoy" rev-parse --abbrev-ref HEAD)"
( cd "$OUTSIDE/work" && PATH="$OUTSIDE/bin:$PATH" bash "$OUTSIDE/decoy/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$OUTSIDE/out" 2>&1
rc=$?
work_after="$(git -C "$OUTSIDE/work" rev-parse HEAD)"
decoy_after="$(git -C "$OUTSIDE/decoy" rev-parse HEAD)"
decoy_branch_after="$(git -C "$OUTSIDE/decoy" rev-parse --abbrev-ref HEAD)"
if [[ "$rc" -eq 0 ]] \
   && [[ "$work_before" != "$work_after" ]] \
   && [[ "$decoy_before" == "$decoy_after" ]] \
   && [[ "$decoy_branch_before" == "$decoy_branch_after" ]]; then
  pass "SUT outside repo: synced the CALLER's worktree, decoy untouched"
else
  fail "SUT outside repo: rc=$rc work_moved=$([[ "$work_before" != "$work_after" ]] && echo yes || echo NO) decoy_moved=$([[ "$decoy_before" != "$decoy_after" ]] && echo YES || echo no) decoy_branch=$decoy_branch_before->$decoy_branch_after out=$(tr '\n' ' ' < "$OUTSIDE/out")"
fi
rm -rf "$OUTSIDE"

# =============================================================================
# --step: ONE attempt, no gh calls (#8383). This is the path both Phase 7 fences
# run, so every exit code the fences dispatch on is pinned here on REAL git.
# `gh` is a stub that records any call: --step must never make one (the fence
# already read mergeStateStatus this tick).
# =============================================================================
install_gh_forbidden() {
  local bin="$1"
  assert_fixture_dir "$bin"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\necho "UNEXPECTED gh call: $*"\nexit 99\n' > "$bin/gh"
  chmod +x "$bin/gh"
}

# advance_main <dir> <file> <content> — commit on origin/main from a second clone.
advance_main() {
  local d="$1" f="$2" c="$3"
  assert_fixture_dir "$d"
  [[ -d "$d/mainwt" ]] || {
    git clone -q "file://$d/origin.git" "$d/mainwt"
    git -C "$d/mainwt" config user.email t@t
    git -C "$d/mainwt" config user.name t
    git -C "$d/mainwt" checkout -q main
  }
  git -C "$d/mainwt" pull -q --no-tags origin main
  echo "$c" > "$d/mainwt/$f"
  git -C "$d/mainwt" add "$f" && git -C "$d/mainwt" commit -q -m "main-$f"
  git -C "$d/mainwt" push -q origin main
}

# run_step <dir> [extra args…] — runs --step from the caller's worktree; stdout and
# stderr are captured SEPARATELY so the stdout-only tagging contract is checkable.
run_step() {
  local d="$1"; shift
  ( cd "$d/work" && assert_in_fixture "$d/work" \
      && PATH="$d/bin:$PATH" bash "$d/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 --step "$@" ) \
    >"$d/out" 2>"$d/err"
}

no_gh() { ! grep -q 'UNEXPECTED gh call' "$1/out" "$1/err"; }

# --- step success: merge + push, rc 0, no tagged line --------------------------
S_OK="$(mktemp -d "$TMPDIR/sync-step-ok.XXXXXXXX")"
FIXTURES+=("$S_OK")
make_pair "$S_OK"
advance_main "$S_OK" h extra
install_gh_forbidden "$S_OK/bin"
before="$(git -C "$S_OK/work" rev-parse HEAD)"
run_step "$S_OK"; rc=$?
after="$(git -C "$S_OK/work" rev-parse HEAD)"
remote="$(git -C "$S_OK/work" rev-parse origin/feat)"
if [[ "$rc" -eq 0 && "$before" != "$after" && "$after" == "$remote" ]] \
   && ! grep -q '\[pr-behind-sync\] kind=' "$S_OK/out" && no_gh "$S_OK"; then
  pass "--step success: rc 0, merged, pushed (origin/feat == HEAD), no tagged line, no gh call"
else
  fail "--step success: rc=$rc moved=$([[ "$before" != "$after" ]] && echo yes || echo no) pushed=$([[ "$after" == "$remote" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$S_OK/out") err=$(tr '\n' ' ' < "$S_OK/err")"
fi
rm -rf "$S_OK"

# --- step conflict: rc 6, kind=merge rc=1 on STDOUT, merge aborted ---------------
S_CF="$(mktemp -d "$TMPDIR/sync-step-conflict.XXXXXXXX")"
FIXTURES+=("$S_CF")
make_pair "$S_CF"
advance_main "$S_CF" f main-side
echo feat-side > "$S_CF/work/f"
git -C "$S_CF/work" commit -q -am feat-side
git -C "$S_CF/work" push -q origin feat
install_gh_forbidden "$S_CF/bin"
before="$(git -C "$S_CF/work" rev-parse HEAD)"
run_step "$S_CF"; rc=$?
if [[ "$rc" -eq 6 ]] \
   && grep -q '^\[pr-behind-sync\] kind=merge rc=1 — ' "$S_CF/out" \
   && grep -qx 'f' "$S_CF/out" \
   && ! grep -q 'pr-behind-sync' "$S_CF/err" \
   && ! git -C "$S_CF/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ -z "$(git -C "$S_CF/work" status --porcelain -- f)" ]] \
   && [[ "$(git -C "$S_CF/work" rev-parse HEAD)" == "$before" ]] && no_gh "$S_CF"; then
  pass "--step conflict: rc 6, kind=merge rc=1 on stdout (not stderr), path named, merge aborted, HEAD unchanged"
else
  fail "--step conflict: rc=$rc out=$(tr '\n' ' ' < "$S_CF/out") err=$(tr '\n' ' ' < "$S_CF/err")"
fi
rm -rf "$S_CF"

# --- step refused: rc 10, nothing aborted, worktree state printed ----------------
# A tracked file with uncommitted edits that main also changes: git refuses to start
# the merge ("would be overwritten") and creates no MERGE_HEAD — the case the old
# script mislabelled "merge conflict" and answered with an --abort of nothing.
S_RF="$(mktemp -d "$TMPDIR/sync-step-refused.XXXXXXXX")"
FIXTURES+=("$S_RF")
make_pair "$S_RF"
advance_main "$S_RF" f main-side
echo uncommitted > "$S_RF/work/f"
for n in $(seq 1 25); do : > "$S_RF/work/untracked-$n"; done
install_gh_forbidden "$S_RF/bin"
run_step "$S_RF"; rc=$?
if [[ "$rc" -eq 10 ]] \
   && grep -q '^\[pr-behind-sync\] kind=merge_refused rc=[0-9]* — ' "$S_RF/out" \
   && grep -q '^ M f$' "$S_RF/out" \
   && ! grep -q 'merge --abort' "$S_RF/out" \
   && [[ "$(cat "$S_RF/work/f")" == "uncommitted" ]] && no_gh "$S_RF"; then
  pass "--step refused: rc 10, kind=merge_refused, status shown, uncommitted edit untouched"
else
  fail "--step refused: rc=$rc out=$(tr '\n' ' ' < "$S_RF/out" | cut -c1-600)"
fi
rm -rf "$S_RF"

# --- step with a merge already in progress: rc 9, staged resolution survives -----
S_IP="$(mktemp -d "$TMPDIR/sync-step-inprog.XXXXXXXX")"
FIXTURES+=("$S_IP")
make_pair "$S_IP"
advance_main "$S_IP" f main-side
echo feat-side > "$S_IP/work/f"
git -C "$S_IP/work" commit -q -am feat-side
git -C "$S_IP/work" fetch -q --no-tags origin main
git -C "$S_IP/work" merge origin/main --no-edit >/dev/null 2>&1
echo resolved > "$S_IP/work/f"
git -C "$S_IP/work" add f
install_gh_forbidden "$S_IP/bin"
run_step "$S_IP"; rc=$?
if [[ "$rc" -eq 9 ]] && grep -q '^\[pr-behind-sync\] kind=merge_in_progress — ' "$S_IP/out" \
   && git -C "$S_IP/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ "$(git -C "$S_IP/work" diff --cached --name-only)" == "f" ]] && no_gh "$S_IP"; then
  pass "--step merge-in-progress: rc 9, MERGE_HEAD and staged resolution kept"
else
  fail "--step merge-in-progress: rc=$rc out=$(tr '\n' ' ' < "$S_IP/out")"
fi
rm -rf "$S_IP"

# --- step on a detached HEAD: rc 9, nothing fetched or moved ---------------------
S_DH="$(mktemp -d "$TMPDIR/sync-step-detached.XXXXXXXX")"
FIXTURES+=("$S_DH")
make_pair "$S_DH"
advance_main "$S_DH" h extra
git -C "$S_DH/work" checkout -q --detach
install_gh_forbidden "$S_DH/bin"
before="$(git -C "$S_DH/work" rev-parse HEAD)"
run_step "$S_DH"; rc=$?
if [[ "$rc" -eq 9 ]] && grep -q '^\[pr-behind-sync\] kind=detached_head — ' "$S_DH/out" \
   && [[ "$(git -C "$S_DH/work" rev-parse HEAD)" == "$before" ]] && no_gh "$S_DH"; then
  pass "--step detached HEAD: rc 9, kind=detached_head, HEAD unchanged"
else
  fail "--step detached HEAD: rc=$rc out=$(tr '\n' ' ' < "$S_DH/out")"
fi
rm -rf "$S_DH"

# --- step push rejected: rc 7, local merge commit retained -----------------------
S_PR="$(mktemp -d "$TMPDIR/sync-step-push.XXXXXXXX")"
FIXTURES+=("$S_PR")
make_pair "$S_PR"
advance_main "$S_PR" h extra
printf '#!/bin/sh\necho "pre-receive: rejected by fixture" >&2\nexit 1\n' > "$S_PR/origin.git/hooks/pre-receive"
chmod +x "$S_PR/origin.git/hooks/pre-receive"
install_gh_forbidden "$S_PR/bin"
before="$(git -C "$S_PR/work" rev-parse HEAD)"
run_step "$S_PR"; rc=$?
parents="$(git -C "$S_PR/work" log -1 --format=%P | wc -w | tr -d ' ')"
if [[ "$rc" -eq 7 ]] && grep -q '^\[pr-behind-sync\] kind=push rc=1 — ' "$S_PR/out" \
   && [[ "$(git -C "$S_PR/work" rev-parse HEAD)" != "$before" && "$parents" -eq 2 ]] && no_gh "$S_PR"; then
  pass "--step push rejected: rc 7, kind=push rc=1, local merge commit retained"
else
  fail "--step push rejected: rc=$rc parents=$parents out=$(tr '\n' ' ' < "$S_PR/out")"
fi
rm -rf "$S_PR"

# --- argv strictness and --help (no fixture needed: neither touches git) ---------
bash "$SUT" 1 --bogus >/dev/null 2>&1; rc_bogus=$?
bash "$SUT" 1 --step --max-attempts 3 >/dev/null 2>&1; rc_mixed=$?
help_out="$(bash "$SUT" --help 2>/dev/null)"; rc_help=$?
if [[ "$rc_bogus" -eq 2 && "$rc_mixed" -eq 2 ]]; then
  pass "unknown argument and --step with --max-attempts both exit 2"
else
  fail "argv strictness: --bogus rc=$rc_bogus (want 2), --step --max-attempts 3 rc=$rc_mixed (want 2)"
fi
if [[ "$rc_help" -eq 0 ]] && grep -q -- '--step' <<<"$help_out" && grep -q 'exit codes' <<<"$help_out" \
   && grep -qE '^  10 ' <<<"$help_out"; then
  pass "--help: rc 0, names --step and the exit-code table (the fences' capability probe)"
else
  fail "--help: rc=$rc_help out=$help_out"
fi

# --- one merge/push path: the standalone loop reaches git only through sync_step --
# (M8) An inline `git merge origin` or `git push` outside sync_step() would be a
# second copy of the state machine this script exists to hold once.
outside="$(awk '/<<.USAGE.$/{doc=1; next} doc&&/^USAGE$/{doc=0; next} doc{next}
               /^sync_step\(\) \{/{in_fn=1} in_fn&&/^\}/{in_fn=0; next} !in_fn' "$SUT" \
  | grep -vE '^[[:space:]]*(#|echo )' | grep -nE '(^|[^-])git (merge (origin|--abort|--no-edit)|push( |$))' || true)"
inside="$(awk '/^sync_step\(\) \{/{in_fn=1} in_fn&&/^\}/{exit} in_fn' "$SUT" | grep -cE 'git merge origin/main --no-edit' || true)"
if [[ -z "$outside" && "$inside" -eq 1 ]]; then
  pass "git merge/push appear only inside sync_step()"
else
  fail "merge/push outside sync_step: ${outside:-none}; merge lines inside: $inside (want 1)"
fi

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 && "$PASS" -eq 15 ]]
exit $?
