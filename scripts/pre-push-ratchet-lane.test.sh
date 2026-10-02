#!/usr/bin/env bash
# pre-push-ratchet-lane.test.sh — Guard Contract battery for the #9400 pre-push
# ratchet lane (scripts/pre-push-ratchet-lane.sh).
#
# WHAT IS UNDER TEST. The lane's dispatch contract — every member produces
# exactly one receipt line and one verdict; merged-tree evaluation (members run
# AFTER the in-scratch merge, never on the operator's tree); the degrade/abort
# arms; scratch-worktree lifecycle and cleanup; the git-location env scrub. The
# lane's MEMBERS are not re-verified here (each carries its own suite); the
# member PARITY arm asserts the lane's argv equals the registration's argv.
#
# HOW. Fixture git repos under $TESTROOT (synthesized, cq-test-fixtures-
# synthesized-only): a bare `origin` remote, a `feat-x` branch one commit
# ahead. The member table is substituted wholesale through the shipped
# PREPUSH_LANE_MEMBERS_FILE seam, so the battery drives stub members and never
# runs a real ratchet over a fixture tree. The reorder arm splices the shipped
# script's own marker comments (__MERGE_BLOCK__ / __DISPATCH_BLOCK__) — a
# content anchor the file carries deliberately, not a line-shape guess.
#
# AUTHORING CONSTRAINTS honoured here (each cost a debug cycle somewhere):
#   - never `producer | grep -q` under pipefail — grep a FILE instead
#   - a deliberately-nonzero command gets `rc=0; cmd || rc=$?` on its own line
#   - counters move at the CALL SITE, never inside a verdict helper
#   - assert_fixture_dir is the byte-identical canonical copy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/pre-push-ratchet-lane.sh"

PASS=0; FAIL=0; ASSERTED=0
TESTROOT="$(mktemp -d "${TMPDIR:-/tmp}/prepush-lane-suite.XXXXXXXX")" || exit 2

# BYTE-IDENTICAL to plugins/soleur/test/test-helpers.sh's assert_fixture_dir() —
# copied, not sourced, per the suite-side precedent
# (scripts/check-tom4-rls-posture.test.sh). Two repo-global ratchets police the
# fixture-write discipline this enforces.
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
assert_fixture_dir "$TESTROOT"
trap 'rm -rf "$TESTROOT"' EXIT

pass() { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

# Instrument self-test — a suite whose verdict helpers cannot move both counters
# certifies nothing. The probes are subtracted afterwards.
_p0=$PASS; _f0=$FAIL
pass "__selftest-ok" >/dev/null
fail "__selftest-no" >/dev/null 2>&1
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf 'FATAL: instrument self-test did not move both counters\n' >&2; exit 2
fi
PASS=$_p0; FAIL=$_f0
printf '  (instrument verified; counters reset)\n\n'

[[ -f "$SUT" ]] || { printf 'FATAL: SUT not found: %s\n' "$SUT" >&2; exit 1; }
ASSERTED=$((ASSERTED + 1))

# Hermetic git for every fixture build below — a developer's global config
# (init.templateDir, commit.gpgsign, hooksPath) must not reach the fixtures.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

# --- helpers -------------------------------------------------------------------

# g <repo> <git args...> — fixture git with a fixed identity.
g() { git -C "$1" -c user.email=suite@example.com -c user.name=suite "${@:2}"; }

# new_fixture <name> — a fixture repo at $TESTROOT/<name>/repo with a bare origin
# at <name>/origin.git and a `feat-x` branch one commit ahead of origin/main.
# Sets F (repo path) and FD (case dir) — global by name, because printing the
# pair breaks under a whitespace TMPDIR.
new_fixture() {
  local d="$TESTROOT/$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git init -q -b main "$d/repo"
  git init -q --bare "$d/origin.git"
  g "$d/repo" remote add origin "$d/origin.git"
  printf 'seed\n' > "$d/repo/seed.txt"
  g "$d/repo" add seed.txt
  g "$d/repo" commit -qm seed
  g "$d/repo" push -q origin main
  g "$d/repo" fetch -q origin
  g "$d/repo" checkout -qb feat-x
  printf 'branch\n' > "$d/repo/branch-file.txt"
  g "$d/repo" add branch-file.txt
  g "$d/repo" commit -qm branch-work
  F="$d/repo"; FD="$d"
}

# write_members <file> — stub member table from stdin rows `name|tier|argv`.
write_members() {
  local f="$1"
  assert_fixture_dir "$f"
  cat > "$f"
}

# stub <path> <body-lines...> — write an executable stub member script.
stub() {
  local f="$1"; shift
  assert_fixture_dir "$f"
  printf '#!/usr/bin/env bash\n' > "$f"
  printf '%s\n' "$@" >> "$f"
  chmod +x "$f"
}

SEQ=0
LANE_RC=0; LANE_OUT=""
# run_lane <repo> <members-file> [ENV=val ...] — runs the SUT with cwd=<repo>.
run_lane() {
  local repo="$1" mf="$2"; shift 2
  LANE_OUT="$TESTROOT/lane-out.$((SEQ))"; SEQ=$((SEQ + 1))
  assert_fixture_dir "$LANE_OUT"
  LANE_RC=0
  ( cd "$repo" && env "$@" PREPUSH_LANE_MEMBERS_FILE="$mf" SOLEUR_SCRATCH_ROOT="$TESTROOT/scratchbase" bash "$SUT" ) \
    >"$LANE_OUT" 2>&1 || LANE_RC=$?
}

worktree_count() { git -C "$1" worktree list | grep -c .; }

# grep wrapper for receipt assertions — file operand, never a pipe.
has() { grep -qF "$1" "$LANE_OUT"; }

# Re-emit the operand guard AFTER the last function definition: the provenance
# scanner's guard window opens at the nearest enclosing function head, so the
# assertion beside the TESTROOT binding above is invisible to the arm code
# below and every $TESTROOT-chained write in the arms would read unguarded.
assert_fixture_dir "$TESTROOT"

# --- Arm 1: --print-members is a pure print ------------------------------------
# Runs OUTSIDE any repository: any hidden fetch/worktree/git dependence would
# exit non-zero. The member table must name the conditional member.
printf '== arm 1: --print-members\n'
PRC=0
( cd "$TESTROOT" && bash "$SUT" --print-members ) > "$TESTROOT/pm.out" 2>&1 || PRC=$?
if [[ $PRC -eq 0 ]] && grep -qF 'test-affected-kb-consumers' "$TESTROOT/pm.out" \
   && grep -qF 'lint-trap-tempfile-ownership' "$TESTROOT/pm.out"; then
  pass "print-members exits 0 outside a repo and names the member set"
else
  fail "print-members rc=$PRC; out: $(head -5 "$TESTROOT/pm.out")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 2: clean branch, all stubs pass ---------------------------------------
printf '== arm 2: clean run PASS + non-mutation\n'
new_fixture a2
write_members "$FD/members.txt" <<'EOF'
stub-a|fast|bash STUBDIR/stub-a.sh
stub-b|fast|bash STUBDIR/stub-b.sh
EOF
sed -i "s|STUBDIR|$FD|g" "$FD/members.txt"
stub "$FD/stub-a.sh" 'exit 0'
stub "$FD/stub-b.sh" 'exit 0'
_head_before="$(g "$F" rev-parse HEAD)"
_status_before="$(git -C "$F" status --porcelain)"
_wt_before="$(worktree_count "$F")"
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 0 ]] && has 'member=stub-a' && has 'member=stub-b' \
   && has 'merge=ok' && grep -qE 'RATCHET_LANE verdict=PASS' "$LANE_OUT"; then
  pass "clean run: exit 0, per-member receipt, merge=ok, verdict=PASS"
else
  fail "clean run rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))
if [[ "$(g "$F" rev-parse HEAD)" == "$_head_before" ]] \
   && [[ "$(git -C "$F" status --porcelain)" == "$_status_before" ]] \
   && [[ "$(worktree_count "$F")" == "$_wt_before" ]]; then
  pass "non-mutation: branch tip, working tree and worktree list are identical after a run"
else
  fail "non-mutation: HEAD/status/worktree-list changed across the lane run"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 3: merged-tree evaluation (F1) + reorder mutant -----------------------
printf '== arm 3: merged-tree evaluation + reorder mutant\n'
new_fixture a3
# main gains a marker AFTER the branch forked — invisible to the unmerged tree.
g "$F" checkout -q main
printf 'trip\n' > "$F/main-marker.txt"
g "$F" add main-marker.txt
g "$F" commit -qm main-marker
g "$F" push -q origin main
g "$F" checkout -q feat-x
stub "$FD/hw-stub.sh" '[[ -f main-marker.txt ]] && exit 1; exit 0'
write_members "$FD/members.txt" <<EOF
highwater-stub|fast|bash $FD/hw-stub.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 1 ]] && has 'member=highwater-stub' && has 'verdict=RED'; then
  pass "merged-tree eval: member reds only where main's marker landed — F1 class covered"
else
  fail "merged-tree eval: rc=$LANE_RC expected 1; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))
# Reorder mutant: dispatch members BEFORE the in-scratch merge — the shipped
# order is the mechanism under test, so the mutant must MISS the marker. The
# splice is anchored on the marker comments the SUT carries deliberately.
_mbs="$(grep -nF '__MERGE_BLOCK_BEGIN__' "$SUT" | cut -d: -f1 || true)"
_mbe="$(grep -nF '__MERGE_BLOCK_END__' "$SUT" | cut -d: -f1 || true)"
_dbs="$(grep -nF '__DISPATCH_BLOCK_BEGIN__' "$SUT" | cut -d: -f1 || true)"
_dbe="$(grep -nF '__DISPATCH_BLOCK_END__' "$SUT" | cut -d: -f1 || true)"
if [[ -z "$_mbs" || -z "$_mbe" || -z "$_dbs" || -z "$_dbe" ]] \
   || ! (( _mbs < _mbe && _mbe < _dbs && _dbs < _dbe )); then
  printf 'FATAL: SUT marker layout changed (mbs=%s mbe=%s dbs=%s dbe=%s) — the reorder arm cannot splice\n' \
    "$_mbs" "$_mbe" "$_dbs" "$_dbe" >&2
  exit 2
fi
MUT="$FD/lane-mutant.sh"
{
  head -n "$((_mbs - 1))" "$SUT"
  sed -n "${_dbs},${_dbe}p" "$SUT"
  sed -n "${_mbs},${_mbe}p" "$SUT"
  tail -n "+$((_dbe + 1))" "$SUT"
} > "$MUT"
# The mutant resolves its scratch lib relative to its own path — give it one.
mkdir -p "$FD/lib"
cp "$REPO_ROOT/scripts/lib/scratch-root.sh" "$FD/lib/scratch-root.sh"
MRC=0
( cd "$F" && env PREPUSH_LANE_MEMBERS_FILE="$FD/members.txt" SOLEUR_SCRATCH_ROOT="$TESTROOT/scratchbase" bash "$MUT" ) \
  > "$TESTROOT/mut.out" 2>&1 || MRC=$?
if [[ $MRC -eq 0 ]] && grep -qF 'verdict=PASS' "$TESTROOT/mut.out"; then
  pass "reorder mutant misses the merged-only marker — dispatch-after-merge is load-bearing"
else
  fail "reorder mutant rc=$MRC (expected 0+PASS — a RED mutant proves the row never tested ordering); $(tail -8 "$TESTROOT/mut.out")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 4: conditional tier triggers (F2) --------------------------------------
printf '== arm 4: conditional tier\n'
# (a) branch touches a suite file carrying a knowledge-base/ literal -> fires.
new_fixture a4a
mkdir -p "$F/scripts"
cat > "$F/scripts/kb-reader.test.sh" <<'LEAF'
#!/usr/bin/env bash
# reads knowledge-base/ paths
echo kb
LEAF
g "$F" add scripts/kb-reader.test.sh
g "$F" commit -qm kb-suite
stub "$FD/kbc.sh" 'echo stub-kb-consumers; exit 1'
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
test-affected-kb-consumers|conditional|bash $FD/kbc.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 1 ]] && has 'member=test-affected-kb-consumers' && has 'verdict=RED'; then
  pass "conditional tier fires on a kb-reading suite in the branch diff — F2 class covered"
else
  fail "conditional trigger (a): rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# (b) the merge delta adds a scripts/*.baseline.txt -> trigger fires.
new_fixture a4b
mkdir -p "$F/scripts"
g "$F" checkout -q main
printf '42\n' > "$F/scripts/new.baseline.txt"
g "$F" add scripts/new.baseline.txt
g "$F" commit -qm new-baseline
g "$F" push -q origin main
g "$F" checkout -q feat-x
stub "$FD/kbc.sh" 'exit 1'
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
test-affected-kb-consumers|conditional|bash $FD/kbc.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 1 ]] && has 'member=test-affected-kb-consumers' && has 'verdict=RED'; then
  pass "conditional tier fires on a new baseline arriving via the merge delta"
else
  fail "conditional trigger (b): rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# (c) branch touches a declared input of the ratchet -> trigger fires.
new_fixture a4c
mkdir -p "$F/scripts"
printf '#!/usr/bin/env bash\n# touched by the branch\n' > "$F/scripts/test-all.sh"
g "$F" add scripts/test-all.sh
g "$F" commit -qm touch-runner
stub "$FD/kbc.sh" 'exit 1'
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
test-affected-kb-consumers|conditional|bash $FD/kbc.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 1 ]] && has 'member=test-affected-kb-consumers'; then
  pass "conditional tier fires when the ratchet's declared inputs moved"
else
  fail "conditional trigger (c): rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# (d) no trigger -> SKIP receipt, lane still PASS.
new_fixture a4d
stub "$FD/kbc.sh" 'exit 1'
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
test-affected-kb-consumers|conditional|bash $FD/kbc.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 0 ]] && has 'member=test-affected-kb-consumers' && has 'verdict=SKIP' \
   && has 'verdict=PASS'; then
  pass "conditional tier prints SKIP with a reason when no trigger fired"
else
  fail "conditional skip arm: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 5: dispatch vacuity ----------------------------------------------------
printf '== arm 5: dispatch vacuity\n'
new_fixture a5
: > "$FD/members.txt"
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -ne 0 ]] && has 'verdict=RED'; then
  pass "an empty member table cannot pass — dispatch refuses to certify nothing"
else
  fail "vacuity: rc=$LANE_RC expected non-zero+RED; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 6: two failing members, both reported ---------------------------------
printf '== arm 6: stop-at-first is the defect\n'
new_fixture a6
stub "$FD/f1.sh" 'exit 1'
stub "$FD/f2.sh" 'exit 1'
write_members "$FD/members.txt" <<EOF
first|fast|bash $FD/f1.sh
second|fast|bash $FD/f2.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 1 ]] && has 'member=first' && has 'member=second' \
   && [[ "$(grep -c 'verdict=RED' "$LANE_OUT")" -ge 2 ]]; then
  pass "both failing members are reported — no stop-at-first dispatch"
else
  fail "stop-at-first: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 7: fetch failure degrades, members still run ---------------------------
printf '== arm 7: fetch failure degrade\n'
new_fixture a7
g "$F" remote set-url origin "$FD/does-not-exist.git"
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 0 ]] && has 'merge=skipped' && has 'member=stub-pass' && has 'verdict=PASS'; then
  pass "fetch failure: merge=skipped receipt, members still evaluate the unmerged tree"
else
  fail "fetch degrade: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 8: worktree-add failure is an ABORT, never a pass ----------------------
printf '== arm 8: worktree-add failure\n'
new_fixture a8
mkdir -p "$FD/notempty"
printf 'x\n' > "$FD/notempty/occupied"
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
EOF
LANE_OUT="$TESTROOT/lane-out.$((SEQ))"; SEQ=$((SEQ + 1))
LANE_RC=0
( cd "$F" && env PREPUSH_LANE_MEMBERS_FILE="$FD/members.txt" SOLEUR_SCRATCH_ROOT="$TESTROOT/scratchbase" \
    PREPUSH_LANE_WORKTREE_DIR="$FD/notempty" bash "$SUT" ) >"$LANE_OUT" 2>&1 || LANE_RC=$?
if [[ $LANE_RC -eq 2 ]] && has 'verdict=ABORT'; then
  pass "worktree-add failure exits 2 with verdict=ABORT — infra abort is not a pass"
else
  fail "worktree-add failure: rc=$LANE_RC expected 2+ABORT; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 9: PASS text with non-zero rc is RED ----------------------------------
printf '== arm 9: verdict is the exit code, never the banner\n'
new_fixture a9
stub "$FD/liar.sh" 'echo PASS; exit 1'
write_members "$FD/members.txt" <<EOF
liar|fast|bash $FD/liar.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 1 ]] && has 'member=liar' && has 'verdict=RED'; then
  pass "a member printing PASS and exiting 1 is scored RED — verdicts read rc, not banners"
else
  fail "banner-vs-rc: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 10: must-PASS non-canonical member order --------------------------------
printf '== arm 10: must-pass, non-canonical order\n'
new_fixture a10
stub "$FD/p1.sh" 'exit 0'
stub "$FD/p2.sh" 'exit 0'
stub "$FD/p3.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
zz-last|fast|bash $FD/p3.sh
aa-first|fast|bash $FD/p1.sh
mm-mid|fast|bash $FD/p2.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 0 ]] && has 'verdict=PASS'; then
  pass "all-green run on a non-canonical member order — the lane is not a reject-everything stub"
else
  fail "must-pass: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 11: merge conflict -> distinct verdict, cleanup -------------------------
printf '== arm 11: merge conflict\n'
new_fixture a11
g "$F" checkout -q main
printf 'main-side\n' > "$F/conflict.txt"
g "$F" add conflict.txt
g "$F" commit -qm main-conflict
g "$F" push -q origin main
g "$F" checkout -q feat-x
printf 'branch-side\n' > "$F/conflict.txt"
g "$F" add conflict.txt
g "$F" commit -qm branch-conflict
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
EOF
_wt_before="$(worktree_count "$F")"
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 2 ]] && has 'verdict=MERGE_CONFLICT'; then
  pass "merge conflict: exit 2 with verdict=MERGE_CONFLICT — distinct from member RED"
else
  fail "merge conflict: rc=$LANE_RC expected 2+MERGE_CONFLICT; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))
if [[ "$(worktree_count "$F")" == "$_wt_before" ]]; then
  pass "merge-conflict arm leaves no scratch worktree behind"
else
  fail "merge-conflict arm leaked a scratch worktree"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 12: git-location + ambient env scrub reaches members -------------------
printf '== arm 12: env scrub\n'
new_fixture a12
stub "$FD/env-probe.sh" \
  'if env | grep -qE "^(GIT_DIR|GIT_INDEX_FILE|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_NAMESPACE|GIT_TEMPLATE_DIR|GIT_EXEC_PATH|SSH_ASKPASS|CI|GITHUB_ACTIONS|LEFTHOOK|GIT_TRACE)="; then exit 1; fi' \
  'exit 0'
write_members "$FD/members.txt" <<EOF
env-probe|fast|bash $FD/env-probe.sh
EOF
LANE_OUT="$TESTROOT/lane-out.$((SEQ))"; SEQ=$((SEQ + 1))
LANE_RC=0
( cd "$F" && env PREPUSH_LANE_MEMBERS_FILE="$FD/members.txt" SOLEUR_SCRATCH_ROOT="$TESTROOT/scratchbase" \
    GIT_DIR="$F/.git" GIT_INDEX_FILE="$F/.git/index" GIT_TRACE=1 CI=1 GITHUB_ACTIONS=true \
    LEFTHOOK=1 SSH_ASKPASS=/bin/false bash "$SUT" ) >"$LANE_OUT" 2>&1 || LANE_RC=$?
if [[ $LANE_RC -eq 0 ]] && has 'verdict=PASS'; then
  pass "members see none of the git-location/ambient vars the hook runtime exports"
else
  fail "env scrub: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 13: branch-touched tier env shaping (F4/F5 shape) ----------------------
printf '== arm 13: branch-touched tier\n'
# (i) a branch-added suite file runs inside the deps-free, disk-backed-TMPDIR
# scratch: the leaf asserts the shape it was promised and exits 0 only there.
new_fixture a13a
mkdir -p "$F/tests/scripts"
cat > "$F/tests/scripts/test-envleaf.sh" <<'LEAF'
#!/usr/bin/env bash
set -euo pipefail
[[ -z "${CI:-}" ]] || { echo "CI leaked into branch tier" >&2; exit 1; }
[[ -z "${GITHUB_ACTIONS:-}" ]] || { echo "GITHUB_ACTIONS leaked" >&2; exit 1; }
[[ ! -d apps/web-platform/node_modules ]] || { echo "node_modules present in scratch" >&2; exit 1; }
# TMPDIR is pinned to the scratch's SIBLING dir — disk-backed but outside the
# worktree, so a fixture's mktemp root does not resolve git against the scratch.
[[ "$TMPDIR" == "$(dirname "$PWD")/lane-tmp" ]] || { echo "TMPDIR not pinned to the lane scratch sibling: $TMPDIR" >&2; exit 1; }
# and the pin must be outside any repository:
git -C "$TMPDIR" rev-parse --git-dir >/dev/null 2>&1 && { echo "TMPDIR resolves inside a repo" >&2; exit 1; }
exit 0
LEAF
g "$F" add tests/scripts/test-envleaf.sh
g "$F" commit -qm env-leaf
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
EOF
LANE_OUT="$TESTROOT/lane-out.$((SEQ))"; SEQ=$((SEQ + 1))
LANE_RC=0
( cd "$F" && env PREPUSH_LANE_MEMBERS_FILE="$FD/members.txt" SOLEUR_SCRATCH_ROOT="$TESTROOT/scratchbase" \
    CI=1 GITHUB_ACTIONS=true bash "$SUT" ) >"$LANE_OUT" 2>&1 || LANE_RC=$?
if [[ $LANE_RC -eq 0 ]] && has 'member=test-envleaf' && has 'verdict=PASS'; then
  pass "branch tier runs the diff's suite in a scrubbed, deps-free, TMPDIR-pinned scratch"
else
  fail "branch-tier shaping: rc=$LANE_RC; out: $(tail -12 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))
# (ii) a branch-touched suite that fails there reds the lane and is named.
new_fixture a13b
mkdir -p "$F/tests/scripts"
printf '#!/usr/bin/env bash\nexit 1\n' > "$F/tests/scripts/test-redleaf.sh"
g "$F" add tests/scripts/test-redleaf.sh
g "$F" commit -qm red-leaf
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 1 ]] && has 'member=test-redleaf' && has 'verdict=RED'; then
  pass "a failing branch-touched suite reds the lane and is named in the receipt"
else
  fail "branch-tier red: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))
# (iii) the runner and lib files are NOT suites: a branch touching
# scripts/test-all.sh or a lib-side test-*.sh must not see either dispatched as
# a branch member (the dogfood caught test-all's rc=4 refusal reading as RED).
new_fixture a13c
mkdir -p "$F/scripts/lib"
printf '#!/usr/bin/env bash\n# runner stub\n' > "$F/scripts/test-all.sh"
printf '# lib helper\n' > "$F/scripts/lib/test-helper.sh"
g "$F" add scripts/test-all.sh scripts/lib/test-helper.sh
g "$F" commit -qm touch-runner-and-lib
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
EOF
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 0 ]] && ! has 'member=test-all' && ! has 'member=test-helper'; then
  pass "branch tier declines the runner and lib files — only registered suites dispatch"
else
  fail "branch-tier exclusions: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 14: no-diff early exit --------------------------------------------------
printf '== arm 14: no-diff early exit\n'
new_fixture a14
g "$F" checkout -q main   # HEAD == origin/main tip — nothing to gate
stub "$FD/pass.sh" 'exit 0'
write_members "$FD/members.txt" <<EOF
stub-pass|fast|bash $FD/pass.sh
EOF
_wt_before="$(worktree_count "$F")"
run_lane "$F" "$FD/members.txt"
if [[ $LANE_RC -eq 0 ]] && has 'verdict=PASS' && has 'no-diff' \
   && [[ "$(worktree_count "$F")" == "$_wt_before" ]]; then
  pass "a branch carrying no diff exits 0 early and materializes no scratch"
else
  fail "no-diff arm: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 15: member timeout -------------------------------------------------------
printf '== arm 15: member timeout\n'
new_fixture a15
stub "$FD/slow.sh" 'sleep 30'
write_members "$FD/members.txt" <<EOF
slow|fast|bash $FD/slow.sh
EOF
LANE_OUT="$TESTROOT/lane-out.$((SEQ))"; SEQ=$((SEQ + 1))
LANE_RC=0
( cd "$F" && env PREPUSH_LANE_MEMBERS_FILE="$FD/members.txt" SOLEUR_SCRATCH_ROOT="$TESTROOT/scratchbase" \
    PREPUSH_LANE_MEMBER_TIMEOUT=2 bash "$SUT" ) >"$LANE_OUT" 2>&1 || LANE_RC=$?
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  if [[ $LANE_RC -eq 1 ]] && has 'member=slow' && has 'verdict=RED'; then
    pass "a member exceeding its bound is scored RED (timeout), not waited on forever"
  else
    fail "member timeout: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
  fi
else
  # No timeout binary on this host — the documented bare-fallback arm; the slow
  # member would run to completion, so skip it there rather than park the suite.
  if [[ $LANE_RC -eq 0 ]]; then
    pass "no timeout binary: bare fallback ran the member unbounded (documented arm)"
  else
    fail "bare-timeout arm: rc=$LANE_RC; out: $(tail -8 "$LANE_OUT")"
  fi
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 16: member-table parity with the registrations ---------------------------
printf '== arm 16: member parity\n'
# Extract the shipped member table between its marker comments.
LANE_TABLE="$TESTROOT/lane-table.txt"
sed -n '/^# __LANE_MEMBERS_BEGIN__$/,/^# __LANE_MEMBERS_END__$/p' "$SUT" \
  | grep -oE '"[^"]+\|[^"]+\|[^"]+"' | tr -d '"' > "$LANE_TABLE"
if [[ -s "$LANE_TABLE" ]] && (( $(grep -c . "$LANE_TABLE") >= 8 )); then
  pass "member table extracted non-empty ($(grep -c . "$LANE_TABLE") rows)"
else
  fail "member table extraction returned nothing — marker comments moved?"
fi
ASSERTED=$((ASSERTED + 1))

# Expected rows: name|tier|argv|registration-source. argv uses the __BASE__
# placeholder exactly as the lane's table spells it.
EXPECTED="$TESTROOT/expected-members.txt"
cat > "$EXPECTED" <<'EOF'
lint-trap-tempfile-ownership|fast|python3 scripts/lint-trap-tempfile-ownership.py --check-highwater|ci:.github/workflows/ci.yml:lint-trap-tempfile-ownership.py --check-highwater
lint-supabase-deprecated-endpoints|fast|bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater|ci:.github/workflows/ci.yml:lint-supabase-deprecated-endpoints.sh --check-highwater
lint-diagnosis-claims|fast|bash scripts/lint-diagnosis-claims.test.sh|suite:scripts/lint-diagnosis-claims
alarm-issue-filing-guard|fast|bash scripts/alarm-issue-filing-guard.test.sh|suite:scripts/alarm-issue-filing-guard
lint-workflow-step-env-refs|fast|python3 scripts/lint-workflow-step-env-refs.py|suite:scripts/lint-workflow-step-env-refs-live
plugin-root-anchor-debt|fast|bash scripts/plugin-root-anchor-debt.sh|probe:scripts/plugin-root-anchor-debt.sh
fixture-relative-assert|fast|bash plugins/soleur/test/fixture-relative-assert.test.sh|glob:plugins/soleur/test/
fixture-dir-operand-assert|fast|bash plugins/soleur/test/fixture-dir-operand-assert.test.sh|glob:plugins/soleur/test/
fixture-cd-containment|fast|bash plugins/soleur/test/fixture-cd-containment.test.sh|glob:plugins/soleur/test/
skill-body-budget|fast|python3 scripts/lint-skill-body-budget.py --base __BASE__|ci:.github/workflows/ci.yml:lint-skill-body-budget.py --base
rule-bodies|fast|python3 scripts/lint-rule-bodies.py --check --base __BASE__|ci:.github/workflows/ci.yml:lint-rule-bodies.py --check --base
test-affected-kb-consumers|conditional|bash scripts/test-affected-kb-consumers.test.sh|suite:scripts/test-affected-kb-consumers
EOF

# Every shipped row must match an expected row verbatim (name|tier|argv); every
# expected row must be shipped. Both directions are asserted — a parity check
# that only looks one way is blind to the member someone added without telling it.
while IFS= read -r row; do
  if grep -qF "$row" "$EXPECTED"; then
    pass "parity: shipped member [${row%%|*}] matches its expected row"
  else
    fail "parity: shipped member row has no expected entry (unclassified): $row"
  fi
  ASSERTED=$((ASSERTED + 1))
done < "$LANE_TABLE"
while IFS= read -r erow; do
  ekey="${erow%%|*}"
  if grep -q "^${ekey}|" "$LANE_TABLE"; then
    pass "parity: expected member [$ekey] is shipped"
  else
    fail "parity: expected member [$ekey] missing from the shipped table"
  fi
  ASSERTED=$((ASSERTED + 1))
done < "$EXPECTED"

# Registration anchoring: each expected row's argv must be anchored where its
# verdict is registered — a CI step, a run_suite line, a SUITE_GLOB, or the
# standalone probe file itself.
SUITE_GLOBS="$(bash "$REPO_ROOT/scripts/test-all.sh" --print-suite-globs 2>/dev/null || true)"
while IFS= read -r erow; do
  IFS='|' read -r ename etier eargv espec <<<"$erow"
  src="${espec%%:*}"; rest="${espec#*:}"
  case "$src" in
    ci)
      file="${rest%%:*}"; needle="${rest#*:}"
      if grep -qF "$needle" "$REPO_ROOT/$file"; then
        pass "anchor: $ename argv appears in $file"
      else
        fail "anchor: $ename argv not found in $file (needle: $needle)"
      fi
      ;;
    suite)
      if grep -qF "run_suite \"$rest\"" "$REPO_ROOT/scripts/test-all.sh"; then
        pass "anchor: $ename registered via run_suite \"$rest\""
      else
        fail "anchor: $ename registration run_suite \"$rest\" not found in test-all.sh"
      fi
      ;;
    glob)
      member_file="$(printf '%s\n' "$eargv" | awk '{print $NF}')"
      if printf '%s\n' "$SUITE_GLOBS" | grep -qF "${rest}*.test.sh" \
         && [[ -f "$REPO_ROOT/$member_file" ]]; then
        pass "anchor: $ename covered by a SUITE_GLOB and its file exists"
      else
        fail "anchor: $ename — glob ${rest}*.test.sh absent from --print-suite-globs or $member_file missing"
      fi
      ;;
    probe)
      if [[ -f "$REPO_ROOT/$rest" ]]; then
        pass "anchor: $ename is the standalone probe $rest (no registration — documented residual)"
      else
        fail "anchor: $ename probe $rest missing"
      fi
      ;;
    *) fail "anchor: unknown source class '$src' for $ename" ;;
  esac
  ASSERTED=$((ASSERTED + 1))
done < "$EXPECTED"

# --- Arm 17: scrub-list parity ----------------------------------------------------
printf '== arm 17: scrub-list parity\n'
# The lane's unset line must cover the canonical GIT_LOCATION_VARS set plus
# SSH_ASKPASS. Derive the source of truth from the TS lib — the same derivation
# git-env-list-parity.test.sh performs.
TS_LIST="$(sed -n '/^export const GIT_LOCATION_VARS = \[/,/^\] as const;/p' \
  "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.ts" | grep -oE '"GIT_[A-Z_]+"' | tr -d '"' | sort || true)"
if [[ -z "$TS_LIST" ]]; then
  printf 'FATAL: could not derive GIT_LOCATION_VARS from the TS source\n' >&2; exit 2
fi
LANE_UNSET="$(grep -E '^unset GIT_DIR' "$SUT" | tr ' ' '\n' | grep -E '^[A-Z_]+$' | sort -u || true)"
missing_scrub="$(comm -23 <(printf '%s\n' "$TS_LIST"; printf 'SSH_ASKPASS\n') <(printf '%s\n' "$LANE_UNSET") | tr '\n' ' ')"
if [[ -z "${missing_scrub// }" ]]; then
  pass "the lane's scrub covers the whole GIT_LOCATION_VARS set plus SSH_ASKPASS"
else
  fail "the lane's scrub misses: $missing_scrub"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 18: receipt wording ------------------------------------------------------
printf '== arm 18: receipt wording\n'
if grep -nE 'tests verified|all green' "$SUT" >/dev/null; then
  fail "receipt wording: SUT contains 'tests verified'/'all green' — CLO wording rule"
else
  pass "receipt wording: no 'tests verified'/'all green' phrasing in the lane"
fi
ASSERTED=$((ASSERTED + 1))
if grep -qE 'RATCHET_LANE verdict=' "$SUT"; then
  pass "receipt emits the RATCHET_LANE verdict= terminal marker"
else
  fail "receipt emits no RATCHET_LANE verdict= marker"
fi
ASSERTED=$((ASSERTED + 1))

# --- Arm 19: the lane takes no runner lock (ADR-133 interplay) ---------------------
printf '== arm 19: no runner lock\n'
if grep -nE 'tc_acquire|flock' "$SUT" >/dev/null; then
  fail "the lane acquires the test-all advisory lock — it must stay a narrow gate"
else
  pass "the lane takes no test-all flock/tc_acquire (ADR-133)"
fi
ASSERTED=$((ASSERTED + 1))

printf '\n=== Results: %s passed, %s failed ===\n' "$PASS" "$FAIL"

# ANTI-VACUITY FLOOR — raise in lockstep when adding assertions. The floor
# counts ASSERTED (call-site increments), not pass/fail, so a verdict-helper
# mutation cannot satisfy it.
MIN_ASSERTED=60
if (( ASSERTED < MIN_ASSERTED )); then
  printf 'FAIL: only %s assertions ran (expected >= %s) — a suite that measured less certifies less\n' \
    "$ASSERTED" "$MIN_ASSERTED" >&2
  exit 1
fi
(( FAIL == 0 ))
