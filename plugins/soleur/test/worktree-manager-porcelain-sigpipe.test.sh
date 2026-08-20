#!/usr/bin/env bash

# Tests for worktree-manager.sh line-membership checks over `git worktree list`.
#
# The defect: the script runs under `set -euo pipefail` (line 29) and asked
# "is this line in the porcelain listing?" with
#
#     git worktree list --porcelain | grep -qxF "worktree $worktree_path"
#
# `grep -q` exits at the FIRST match and closes the pipe. When the match is not
# near the end of the listing, `git` is still writing, takes SIGPIPE, and exits
# 141 — which `pipefail` promotes to the pipeline's status. So the pipeline
# reports FAILURE precisely when the needle IS present and early. Measured on a
# repo with 27 registered worktrees:
#
#     rc=141                    (141 = SIGPIPE)
#     no-pipefail EARLY: MATCH
#     pipefail    EARLY: NOMATCH
#
# Two call sites made this reachable and consequential:
#
#   1. verify_worktree_created Check 2 — a freshly created worktree whose
#      porcelain entry does not sort last is declared "not registered", and the
#      handler DELETES the worktree it just created. Porcelain order follows
#      `.git/worktrees` readdir order, so which branch names break is
#      effectively arbitrary: `create feat-one-shot-7498-…` landed at line 49 of
#      120 and failed 100% of the time while a probe worktree that happened to
#      land last passed. That arbitrariness is what made it read as flaky
#      infrastructure rather than as a deterministic bug.
#
#   2. heal_stale_branch — "a branch checked out in ANY worktree is ACTIVE,
#      never heal it" is a FAIL-OPEN guard. A false negative falls through to
#      `git push origin --delete "$branch"`, so a live session's remote branch
#      is deleted precisely when it appears early in the listing. The local
#      prune below it is annotated "the not-checked-out condition is already
#      guaranteed by the early return at the top" — that assumption is what
#      breaks.
#
# A2/A4 are MUTANTS: they restore the piped idiom on a COPY of the script and
# require the corresponding arm to FAIL. Without them A1/A3 would pass against
# the unfixed script on any machine whose readdir order happened to put the
# fixture's needle last — a guard that cannot be driven red is vacuous.
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

# Sibling suites default this too: /tmp is a machine-global 4 GiB tmpfs shared by
# parallel worktrees, and a fixture that cannot be built yields a CONFIDENT WRONG
# verdict rather than a missing one.
export TMPDIR="${TMPDIR:-/var/tmp}"

# Isolate fixtures from the operator's git config. A host with
# `commit.gpgsign=true` + `gpg.format=ssh` (this machine) fails every fixture
# commit with "failed to write commit object", and `git clone` then reports only
# "you appear to have cloned an empty repository" — a warning, not an error. The
# arms would go red for a missing fixture while reading as a real SUT failure.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

echo "=== worktree-manager.sh porcelain membership under pipefail ==="
echo ""

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# --- gh stub ---------------------------------------------------------------
# heal_stale_branch's PR probe has three outcomes and only "gh present, OK,
# zero live PRs" reaches the remote delete. The real gh would ERROR against a
# file:// origin, which fails SAFE and would mask A4's data loss entirely.
STUB_DIR="$TEST_DIR/bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# `gh pr list … --jq '… | length'` → no live PRs, so heal proceeds to delete.
if [[ "${1:-} ${2:-}" == "pr list" ]]; then printf '0\n'; exit 0; fi
exit 1
EOF
chmod +x "$STUB_DIR/gh"
export PATH="$STUB_DIR:$PATH"

# --- git stub: make the SIGPIPE race DETERMINISTIC ------------------------
# The production failure needs the producer to be STILL WRITING when `grep -q`
# quits. A small fixture cannot reproduce that: ~14 lines of porcelain fit
# entirely in the 64 KiB pipe buffer, so git finishes and exits 0 before the
# consumer closes anything, and the unfixed script PASSES. (Measured: an
# earlier revision of this suite went green against the buggy script for
# exactly that reason.) The real repo failed because git was still stat-ing
# worktrees 50..120 when grep matched at 49.
#
# So pad the listing past the pipe buffer. The needle stays where the real
# listing put it — early — and the padding guarantees the writer outlives the
# reader. This tests the same mechanism, minus the timing lottery.
GIT_STUB_DIR="$TEST_DIR/gitbin"
mkdir -p "$GIT_STUB_DIR"
REAL_GIT="$(command -v git)"

# The padding is emitted by an EXTERNAL `cat`, not a bash `printf` loop.
# That distinction is the whole arm. Real git DIES on SIGPIPE; bash's printf
# builtin does not necessarily — on the CI runner it reports
# "write error: Broken pipe" and keeps looping, so the stub exited 0, the
# mutant never reproduced the bug, and A2 went red while A1 passed vacuously.
# `exec cat` makes the stub process BE cat, so it dies of SIGPIPE exactly as
# git would and the pipeline sees 141.
PAD_FILE="$TEST_DIR/porcelain-pad.txt"
: >"$PAD_FILE"
for ((_p = 0; _p < 2000; _p++)); do
  printf 'worktree /nonexistent/pad-%s\n\n' "$_p"
done >"$PAD_FILE"   # ~70 KiB: strictly more than the 64 KiB pipe buffer.

cat > "$GIT_STUB_DIR/git" <<EOF
#!/usr/bin/env bash
_is_wt_list=0
_seen_wt=0
for _a in "\$@"; do
  [[ "\$_a" == "worktree" ]] && _seen_wt=1
  [[ "\$_seen_wt" == 1 && "\$_a" == "--porcelain" ]] && _is_wt_list=1
done
if [[ "\$_is_wt_list" == 1 ]]; then
  "$REAL_GIT" "\$@" || exit \$?
  exec cat "$PAD_FILE"
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$GIT_STUB_DIR/git"


# --- Fixture ---------------------------------------------------------------
# A clone with a real `origin` (so the remote-delete path is live) and enough
# linked worktrees that the FIRST linked entry is provably not last.
#
# "First linked" is the deterministic lever: `git worktree list --porcelain`
# always emits the main worktree first, so entry index 1 is a linked worktree
# and, with >=3 entries, is never last. Which of wt1..wtN lands there is
# readdir-dependent and deliberately not assumed — the arms read the branch back
# out of the listing instead of hardcoding it.
NUM_LINKED=4

new_fixture() {
  local name="$1" root="$TEST_DIR/$1"
  local seed="$root/seed" origin="$root/origin.git" repo="$root/repo"
  mkdir -p "$root"
  git init -q -b main "$seed"
  git -C "$seed" config user.email "test@test.local"
  git -C "$seed" config user.name "Test"
  git -C "$seed" commit -q --allow-empty -m "seed"
  git clone -q --bare "$seed" "$origin"
  git clone -q "$origin" "$repo"
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "Test"

  local i
  for ((i = 1; i <= NUM_LINKED; i++)); do
    # 0 commits ahead of main and pushed: exactly the shape heal_stale_branch
    # classifies as a deletable "stale empty remote branch" once its
    # active-worktree guard has been defeated.
    git -C "$repo" worktree add -q -b "wt$i" "$repo/.worktrees/wt$i" main >/dev/null 2>&1
    git -C "$repo" push -q origin "wt$i" >/dev/null 2>&1
  done
  printf '%s' "$repo"
}

# Emit "<path>\t<branch>" for the Nth `worktree` entry (0-based) of the listing.
# Parsed in bash rather than piped into awk: this suite is about a pipeline that
# lies about its exit status, so its own fixture must not depend on one.
entry_at() {
  local repo="$1" want="$2"
  local line path="" branch="" n=-1
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        n=$((n + 1))
        [[ $n -gt $want ]] && break
        [[ $n -eq $want ]] && path="${line#worktree }"
        ;;
      "branch "*)
        [[ $n -eq $want ]] && branch="${line#branch }"
        ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain)
  printf '%s\t%s' "$path" "${branch#refs/heads/}"
}

# Total `worktree ` entries — used to prove index 1 is not last.
entry_count() {
  local n=0 line
  while IFS= read -r line; do
    [[ "$line" == "worktree "* ]] && n=$((n + 1))
  done < <(git -C "$1" worktree list --porcelain)
  printf '%s' "$n"
}

remote_has_branch() {
  # Deliberately pipe-free: a `… | grep -q` here would be the exact construct
  # this suite exists to outlaw, and would make the oracle share the bug.
  local out
  out="$(git -C "$1" ls-remote --heads origin "refs/heads/$2" 2>/dev/null)" || out=""
  [[ -n "$out" ]] && echo true || echo false
}

# --- Mutants ---------------------------------------------------------------
# Restore the piped `grep -q` idiom on a COPY. Each mutation is asserted to have
# landed (diff against the pristine script); a silently-missed anchor would make
# the mutant identical to the real script and the arm would pass vacuously.
make_mutant() {
  local name="$1" mutate="$2"
  local out="$TEST_DIR/$name.sh"
  cp "$SCRIPT" "$out" || { echo "FATAL: cp failed for $name" >&2; exit 2; }
  "$mutate" "$out"
  if diff -q "$SCRIPT" "$out" >/dev/null 2>&1; then
    echo "FATAL: mutation '$name' did not land — anchor missed; arm would pass vacuously" >&2
    exit 2
  fi
  printf '%s' "$out"
}

# M1: verify_worktree_created Check 2 back to the piped form.
neuter_verify() {
  perl -0pi -e 's/^_porcelain_has_line\(\) \{.*?^\}/_porcelain_has_line() {\n  local needle="\$1"\n  git worktree list --porcelain | grep -qxF "\$needle"\n}/ms' "$1"
}
# M2: heal_stale_branch's guard back to its ORIGINAL form — wholesale, not just
# the probe. Reverting only the probe would leave the `!= "1"` test in place,
# which maps SIGPIPE's 141 to "active" and would mask the very fall-through this
# arm exists to demonstrate. Spans from `local _wt_probe=0` to the guard's `fi`.
neuter_heal() {
  perl -0pi -e 's/  local _wt_probe=0\n.*?\n  fi\n/  if git worktree list --porcelain 2>\/dev\/null | grep -qx "branch refs\/heads\/\$branch"; then\n    return 0\n  fi\n/s' "$1"
}

# Run verify_worktree_created against an EXISTING worktree, in a subshell so the
# function's `exit 1` failure path is contained. Echoes the exit code.
run_verify() {
  local script="$1" repo="$2" path="$3" branch="$4" log="$5" rc=0
  ( export PATH="$GIT_STUB_DIR:$PATH"
    cd "$repo" && source "$script" && verify_worktree_created "$path" "$branch" main ) \
    >"$log" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# Run heal_stale_branch against a branch that IS checked out. Echoes exit code.
run_heal() {
  local script="$1" repo="$2" branch="$3" log="$4" rc=0
  ( export PATH="$GIT_STUB_DIR:$PATH"
    cd "$repo" && source "$script" && heal_stale_branch "$branch" main ) >"$log" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# ---------------------------------------------------------------------------
# A1 — the blocking arm. A worktree that IS registered but is not the last
#      porcelain entry must verify clean, and must still exist afterwards.
# ---------------------------------------------------------------------------
echo "A1: verify_worktree_created accepts a registered, non-last worktree"
R_A1=$(new_fixture a1)
COUNT_A1=$(entry_count "$R_A1")
assert_eq "true" "$([[ "$COUNT_A1" -ge 3 ]] && echo true || echo false)" \
  "fixture has >=3 porcelain entries (index 1 is provably not last; got $COUNT_A1)"

IFS=$'\t' read -r P_A1 B_A1 <<<"$(entry_at "$R_A1" 1)"
assert_eq "true" "$([[ -n "$P_A1" && -n "$B_A1" ]] && echo true || echo false)" \
  "parsed a non-last entry from the listing (path=$P_A1 branch=$B_A1)"

# A0 (inside A1's fixture): the stub must be a FAITHFUL producer. Piping it into
# a short-circuiting reader has to yield 141. This is not ceremony — the first
# version of this stub padded with a bash `printf` loop, and bash's printf
# builtin survives EPIPE on some hosts ("write error: Broken pipe", then keeps
# going). There the stub exited 0, the mutant could not reproduce the bug, and
# every arm below would have passed vacuously against a broken script.
STUB_RC=0
( export PATH="$GIT_STUB_DIR:$PATH"
  cd "$R_A1" && git worktree list --porcelain | grep -qxF "worktree $P_A1" ) || STUB_RC=$?
assert_eq "141" "$STUB_RC" \
  "stub git dies of SIGPIPE when a grep -q reader quits early (arms are not vacuous)"

RC_A1=$(run_verify "$SCRIPT" "$R_A1" "$P_A1" "$B_A1" "$TEST_DIR/a1.log")
assert_eq "0" "$RC_A1" "verify_worktree_created exits 0 for a registered non-last worktree"
assert_eq "true" "$([[ -d "$P_A1" ]] && echo true || echo false)" \
  "worktree still on disk (the failure handler deletes it)"
echo ""

# ---------------------------------------------------------------------------
# A2 — anti-vacuity for A1. With the piped idiom restored, the SAME call must
#      fail, proving A1 is driven by the fix and not by fixture ordering.
# ---------------------------------------------------------------------------
echo "A2: mutant (piped grep -q in Check 2) is driven RED by the same input"
MUT1=$(make_mutant m1-verify neuter_verify)
R_A2=$(new_fixture a2)
IFS=$'\t' read -r P_A2 B_A2 <<<"$(entry_at "$R_A2" 1)"
RC_A2=$(run_verify "$MUT1" "$R_A2" "$P_A2" "$B_A2" "$TEST_DIR/a2.log")
assert_eq "true" "$([[ "$RC_A2" -ne 0 ]] && echo true || echo false)" \
  "mutant exits non-zero (got $RC_A2) — A1 is not vacuous"
assert_contains "$(cat "$TEST_DIR/a2.log")" "SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=unregistered" \
  "mutant fails with the production marker operators actually saw"
echo ""

# ---------------------------------------------------------------------------
# A3 — the fail-open arm. heal_stale_branch must treat a branch checked out in
#      a worktree as ACTIVE and leave its remote branch alone.
# ---------------------------------------------------------------------------
echo "A3: heal_stale_branch spares a checked-out, early-listed branch"
R_A3=$(new_fixture a3)
IFS=$'\t' read -r _P_A3 BR_A3 <<<"$(entry_at "$R_A3" 1)"
assert_eq "true" "$(remote_has_branch "$R_A3" "$BR_A3")" \
  "precondition: origin/$BR_A3 exists before heal"
RC_A3=$(run_heal "$SCRIPT" "$R_A3" "$BR_A3" "$TEST_DIR/a3.log")
assert_eq "0" "$RC_A3" "heal_stale_branch returns 0 for checked-out $BR_A3"
assert_eq "true" "$(remote_has_branch "$R_A3" "$BR_A3")" \
  "origin/$BR_A3 SURVIVES — the active-worktree guard held"
assert_eq "true" \
  "$(git -C "$R_A3" show-ref --verify --quiet "refs/heads/$BR_A3" && echo true || echo false)" \
  "local branch $BR_A3 still exists"
echo ""

# ---------------------------------------------------------------------------
# A4 — anti-vacuity for A3, and the data-loss demonstration: with the piped
#      idiom restored, a LIVE session's remote branch is deleted.
# ---------------------------------------------------------------------------
echo "A4: mutant (piped grep -qx in heal_stale_branch) deletes a live branch"
MUT2=$(make_mutant m2-heal neuter_heal)
R_A4=$(new_fixture a4)
IFS=$'\t' read -r _P_A4 BR_A4 <<<"$(entry_at "$R_A4" 1)"
assert_eq "true" "$(remote_has_branch "$R_A4" "$BR_A4")" \
  "precondition: origin/$BR_A4 exists before heal (mutant)"
run_heal "$MUT2" "$R_A4" "$BR_A4" "$TEST_DIR/a4.log" >/dev/null
assert_eq "false" "$(remote_has_branch "$R_A4" "$BR_A4")" \
  "mutant DELETED origin/$BR_A4 while it was checked out — A3 is not vacuous"
echo ""

# ---------------------------------------------------------------------------
# A5 — end-to-end. `create` in a repo that already has worktrees must succeed.
#      This is the operator-visible failure: create checked out the whole tree,
#      then deleted it and exited 1.
# ---------------------------------------------------------------------------
echo "A5: create succeeds in a repo that already has several worktrees"
R_A5=$(new_fixture a5)
RC_A5=0
( cd "$R_A5" && bash "$SCRIPT" --yes create feat-sigpipe-probe main ) >"$TEST_DIR/a5.log" 2>&1 || RC_A5=$?
assert_eq "0" "$RC_A5" "create exits 0 (log: $TEST_DIR/a5.log)"
assert_eq "false" \
  "$(grep -q 'SOLEUR_GIT_WORKTREE_VERIFY_FAILED' "$TEST_DIR/a5.log" && echo true || echo false)" \
  "no verify-failed marker emitted"
assert_eq "true" "$([[ -d "$R_A5/.worktrees/feat-sigpipe-probe" ]] && echo true || echo false)" \
  "worktree survives verification"
echo ""

# ---------------------------------------------------------------------------
# A6 — static guard. Any future `git worktree list … | grep -q…` reintroduces
#      the same SIGPIPE race, and reintroduces it INVISIBLY: the needle is
#      present and only the exit code lies. Cheaper to block at review than to
#      re-diagnose from a worktree the script already deleted.
# ---------------------------------------------------------------------------
echo "A6: no 'git worktree list … | grep -q' pipeline remains in the script"
# `^[^#]*` so the helper's own explanatory comment — which quotes the outlawed
# spelling on purpose — is not counted as a use of it.
#
# `.*` between the pipe and the consumer, NOT `[^|]*`: the hazard is any
# short-circuiting reader ANYWHERE downstream, not just the next stage. With
# `[^|]*`, `git worktree list --porcelain | sed -n 's/^branch //p' | grep -qx …`
# reintroduces the identical bug (grep -q closes -> sed dies -> git dies -> 141
# promoted) while the guard stays green. `head`/`read` short-circuit the same way.
OFFENDERS=$(grep -nE '^[^#]*git worktree list.*\|.*(grep -q|head( |$)|read( |$))' "$SCRIPT" || true)
assert_eq "" "$OFFENDERS" "script has no piped grep -q over 'git worktree list'"
echo ""

# ---------------------------------------------------------------------------
# A7 — fail-closed. The active-worktree guard gates `git push origin --delete`
#      and `git branch -D`. If the listing cannot be READ at all, that is not
#      evidence the branch is an orphan, and it must not authorise a delete.
# ---------------------------------------------------------------------------
echo "A7: an unreadable worktree listing does not authorise a delete"
R_A7=$(new_fixture a7)
IFS=$'\t' read -r _P_A7 BR_A7 <<<"$(entry_at "$R_A7" 1)"
BROKEN_GIT="$TEST_DIR/brokenbin"
mkdir -p "$BROKEN_GIT"
cat > "$BROKEN_GIT/git" <<EOF
#!/usr/bin/env bash
# Everything works EXCEPT reading the worktree listing.
_seen_wt=0
for _a in "\$@"; do
  [[ "\$_a" == "worktree" ]] && _seen_wt=1
  if [[ "\$_seen_wt" == 1 && "\$_a" == "--porcelain" ]]; then
    echo "fatal: simulated listing failure" >&2; exit 128
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$BROKEN_GIT/git"
RC_A7=0
( export PATH="$BROKEN_GIT:$PATH"
  cd "$R_A7" && source "$SCRIPT" && heal_stale_branch "$BR_A7" main )   >"$TEST_DIR/a7.log" 2>&1 || RC_A7=$?
assert_eq "0" "$RC_A7" "heal_stale_branch returns 0 when the listing is unreadable"
assert_eq "true" "$(remote_has_branch "$R_A7" "$BR_A7")"   "origin/$BR_A7 SURVIVES an unreadable listing (fail-closed, not fail-open)"
echo ""

# ---------------------------------------------------------------------------
# A8 — the OTHER door into the fail-open. `git worktree list` can exit 0 and
#      still yield no records (the masked-config wedge this file documents).
#      Any valid repo emits at least the main worktree, so a zero-length parse
#      is a BROKEN REGISTRY, not "this branch is an orphan" — and answering it
#      with "absent" authorises the delete. Same standard as
#      cleanup_orphan_worktree_dirs' `reason=empty-parse` branch.
# ---------------------------------------------------------------------------
echo "A8: an EMPTY (rc 0) worktree listing does not authorise a delete"
R_A8=$(new_fixture a8)
IFS=$'\t' read -r _P_A8 BR_A8 <<<"$(entry_at "$R_A8" 1)"
EMPTY_GIT="$TEST_DIR/emptybin"
mkdir -p "$EMPTY_GIT"
cat > "$EMPTY_GIT/git" <<EOF
#!/usr/bin/env bash
# Succeeds, prints nothing — the rc check alone cannot catch this.
_seen_wt=0
for _a in "\$@"; do
  [[ "\$_a" == "worktree" ]] && _seen_wt=1
  [[ "\$_seen_wt" == 1 && "\$_a" == "--porcelain" ]] && exit 0
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$EMPTY_GIT/git"
RC_A8=0
( export PATH="$EMPTY_GIT:$PATH"
  cd "$R_A8" && source "$SCRIPT" && heal_stale_branch "$BR_A8" main ) \
  >"$TEST_DIR/a8.log" 2>&1 || RC_A8=$?
assert_eq "0" "$RC_A8" "heal_stale_branch returns 0 on an empty (rc 0) listing"
assert_eq "true" "$(remote_has_branch "$R_A8" "$BR_A8")" \
  "origin/$BR_A8 SURVIVES an empty parse (rc 0 is not proof of absence)"
echo ""

# ---------------------------------------------------------------------------
# A9 — verify must not answer "could not read the registry" with `rm -rf`.
#      The handler deletes a worktree `create` just checked out, and the marker
#      operators page on would assert the wrong cause.
# ---------------------------------------------------------------------------
echo "A9: an unreadable registry does not destroy the worktree under verify"
R_A9=$(new_fixture a9)
IFS=$'\t' read -r P_A9 B_A9 <<<"$(entry_at "$R_A9" 1)"
RC_A9=0
( export PATH="$BROKEN_GIT:$PATH"
  cd "$R_A9" && source "$SCRIPT" && verify_worktree_created "$P_A9" "$B_A9" main ) \
  >"$TEST_DIR/a9.log" 2>&1 || RC_A9=$?
assert_eq "true" "$([[ "$RC_A9" -ne 0 ]] && echo true || echo false)" \
  "verify fails (got $RC_A9) rather than passing blind"
assert_eq "true" "$([[ -d "$P_A9" ]] && echo true || echo false)" \
  "worktree SURVIVES an unreadable registry — fail-closed, no rm -rf"
assert_contains "$(cat "$TEST_DIR/a9.log")" "reason=registry-unavailable" \
  "marker names the real cause, not reason=unregistered"
echo ""

print_results 24
