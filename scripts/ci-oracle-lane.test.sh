#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Sentinel for #12156 (ADR-276 amendment 2026-11-05): the oracle-only fast lane.
# Guards 1 and 4 of knowledge-base/project/plans/2026-11-05-ci-oracle-only-fast-lane-plan.md.
#
# WHAT THIS PROVES. The oracle-selection driver (scripts/ci-oracle-lane.sh) may only ever err in
# one direction: ANY unknown yields the full battery (oracle_only=false, active=false, empty
# skip_legs). This suite does not grep the driver, it RUNS it, as the workflow does:
#   * against REAL throwaway git repositories with a genuine merge commit (pull_request shape:
#     HEAD = the merge ref, HEAD^1 the base, HEAD^2 the PR head) or a two-commit range
#     (merge_group shape: MERGE_GROUP_BASE_SHA..MERGE_GROUP_HEAD_SHA = the whole queued batch),
#   * under a PATH of bash, git, coreutils and POSIX text tools only (no node, bun, python, jq, gh),
#   * with env-only inputs: EVENT_NAME, SWITCH (exact `on`), PR_HEAD_SHA, HEAD_REPO, GH_REPO,
#     MERGE_GROUP_HEAD_SHA, MERGE_GROUP_BASE_SHA, RUN_ATTEMPT.
#
# THE ORACLE SURFACE (the lane's entire authority, Guard 1): a diff is oracle-only iff EVERY
# changed path is `scripts/ci-pr-affected-audit.accept.tsv`,
# `knowledge-base/**/*.md`, a root `*.md`, or `scripts/lib/test-affected-paths.sh` whose EVERY changed
# line lies inside an `^AFFECTED_[A-Z0-9_]+_PATHS=(` … `^)` extent computed in BOTH the base and the
# head image (so adding or deleting a whole array block still classifies — the PR #12150 shape).
# The load-bearing exclusion list — any one of `scripts/ci-pr-affected-replay.py`,
# `scripts/test-all.sh`, `plugins/soleur/scripts/lint-ratchet.py`, `.github/workflows/ci.yml`,
# `scripts/lib/**` other than the in-extent edit — is pinned by row_exclusions. The plan's sharp
# edge is pinned by row_extent_out: a whole-file path test for test-affected-paths.sh would let a
# LOGIC edit take the lane, so hunk extents are exercised, not just paths.
#
# GUARD 1 MATRIX MAPPING (plan §Guard Contract): row 1 → row_exclusions (replay.py + accept.tsv);
# row 2 → row_exclusions (one oracle path + each outside path); row 3 → row_extent_out
# (ALWAYS_ON_SUITES, _CLOSURE_LEAF_*, AFFECTED_CONSUMED_EDGES, comments, a function, a member-looking
# line outside the extents); row 4 → row_diff_error + row_event_out + the killed-driver row;
# row 5 → row_empty (an EMPTY surface membership must NOT classify: the vacuity arm);
# row 6 (must-PASS non-canonical) → fixture mustpass6: accept.tsv + a KB specs .md + a NEW
# AFFECTED_*_PATHS block, paths in non-sorted order.
#
# GUARD 4 MATRIX MAPPING (manifest parity): row 1 → check_manifest bogus-member copy;
# row 2 → check_manifest empty copy; row 3 → check_manifest copy that drops lint-orphan-test-suites;
# row 4 → row_index_job (the extracted oracle-index-check step must propagate a member's non-zero
# exit into the leg verdict); row 4b → the leg's checkout declares fetch-depth 0 and is gated on
# oracle_only (a static pin of ci.yml); row 5 → check_manifest reordered copy (a different member
# order is a PASS). Legs rows → check_legs mutants (unassigned, stale row, out-of-matrix, vacant leg,
# missing legs file, duplicate, malformed value, stray third field, repacked, reordered) and the
# sandbox arms over the extracted step body: ORACLE_LEG unset/malformed sweep, foreign leg, k==n
# green, malformed legs value, missing legs file, unassigned member, vacuous leg — each with a
# reason pin. The pin is BI-DIRECTIONAL: every manifest member must be a live `test-all.sh --enumerate`
# registration, and every live registration whose label matches the declared oracle-SUT name class
# (affected|lint-orphan-test-suites|ci-pr|ci-path-gating) must be a member OR named in a commented
# exclusion line — a NEW oracle-machinery registration cannot silently escape the leg.
#
# THE ACTIVATION LOCK (removed): `readonly ORACLE_LANE_LOCKED=1` used to keep active=false forever —
# the activation PR (#12156 follow-up) deleted it, so the driver ARMS on an oracle-only diff with
# SWITCH=on: active=true and skip_legs carries the five heavy legs. The env-read at O-LOCK-READ
# remains as the dark-mode revert path (ORACLE_LANE_LOCKED=1 in env re-locks — no ci.yml env wires it
# today, so reaching it is an excluded-path code edit; covered here because O-LOCK-READ is live machinery);
# row_lock covers it. The lock-neutralized copy (same edit recipe as ci-pr-selection.test.sh) is now
# identical to the pristine driver, which is itself the pinned absence check.
#
# GUARD ANCHORS (contract with the driver, same convention as scripts/ci-pr-selection.sh): the
# mutation battery below deletes or weakens lines tagged `# GUARD:<id>`; a driver line that carries
# no anchor cannot be proven killed. Required ids:
#   O-DEFAULTS        the defaults-first output block (crash-safe first write)
#   ALWAYS-EXIT-0     the trap that makes every path exit 0
#   O-EVENT           only pull_request / merge_group classify
#   O1-SWITCH-EXACT   the exact-`on` read maps SWITCH to sw (was listed as "O-SWITCH")
#   O1-SWITCH-GATE    the `sw = on` gate in classify() (the two switch anchors together are "O-SWITCH")
#   O-TWO-PARENTS     the merge-ref two-parent shape (pull_request)
#   O-PRHEAD          HEAD^2 == PR_HEAD_SHA (pull_request)
#   O1-HEAD-IS-GITHUB-SHA  HEAD == GITHUB_SHA (pull_request)
#   O-FORK            same-repo head (pull_request)
#   O1-MG-SHA         the merge_group sha pair is 40-hex (was listed as "O-MG-SHAPE")
#   O1-MG-RESOLVE     the merge_group shas resolve to commits (the other half of "O-MG-SHAPE")
#   O-ATTEMPT         run attempt 1 only
#   O-DIAGRAMS-FLAG   knowledge-base/engineering/architecture/diagrams/* drops test-webplat from the skip list
#   O-MAX-FILES       the ≤500 changed-file cap
#   O-STATUS          M/A/D status letters only
#   O-MODES           modes ⊆ {000000,100644,100755} on both sides
#   O-PATH-CHARS      printable-ASCII paths, no `::`, no `,`
#   O-EXCLUSION       the load-bearing exclusion list (any member ⇒ full battery)
#   O-SURFACE         the per-path surface membership check
#   O-EXTENT          the in-extent hunk check for test-affected-paths.sh
#   O-EXTENT-BASE     the base-image half of the extent check
#   O-EXTENT-HEAD     the head-image half of the extent check
#   O-BINARY-INDEX    a `Binary files` verdict on the index diff returns 1 (zero hunks must not pass vacuously)
#   O-ELEM-GRAMMAR    every +/- line inside an index hunk must match the element grammar
#   O-EMPTY-DIFF      a zero-path diff is NOT oracle-only (the vacuity arm)
#   O-LOCK-READ       the driver reads ORACLE_LANE_LOCKED
#   O-ARM             active=true only when unlocked AND switch `on` AND oracle_only
#   O-GRAMMAR         the output-grammar revalidation at the final printf
#
# NOTICE CONTRACT (observability): every pull_request/merge_group classification emits exactly one
# `::notice title=ci-oracle-lane::SOLEUR_ORACLE_LANE ` line carrying at least `oracle_only=`,
# `active=`, `locked=` and `would_skip=` fields; would_skip names the five heavy legs
# (test-webplat,test-bun,test-scripts,test-scripts-heavy,web-platform-build) on an oracle-only
# diff and `none` otherwise. No fixture path token, repo name, raw switch value or sha ever reaches
# stdout, stderr, the summary or the output file (the two audit shas are the gh.out exception).
#
# OUTPUT GRAMMAR: defaults first (oracle_only=false, active=false, skip_legs=, head_sha=, base_sha=),
# then optionally one final block — the file is exactly 5 lines (defaults only, a crash) or 10 lines
# (defaults + final), last value per key wins. Always exits 0 except a signal kill (137).
#
# Run: bash scripts/ci-oracle-lane.test.sh   (no network, no repo mutation: every repo is a throwaway)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation inherits the bare /tmp (a machine-global tmpfs shared by every worktree); the
# registered runners default to /var/tmp. Pin it so a verdict is never a function of disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

# Every GIT_* variable goes, by PREFIX, before the tripwire library is sourced (a hook-spawned run
# exports GIT_DIR and GIT_INDEX_FILE as absolute paths; those win over cwd and `git -C`).
for _v in ${!GIT_@}; do unset "$_v"; done
unset _v

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads a list that can only be silenced by DELETING
# evidence, never by moving a number.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRIVER="$REPO_ROOT/scripts/ci-oracle-lane.sh"
MANIFEST="$REPO_ROOT/scripts/ci-oracle-lane-suites.txt"
TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
[ -f "$DRIVER" ] || { printf 'FAIL: %s not found (the oracle-lane driver is the implementation deliverable)\n' "$DRIVER" >&2; exit 2; }
[ -f "$TEST_ALL" ] || { printf 'FAIL: %s not found\n' "$TEST_ALL" >&2; exit 2; }

# shellcheck source=../plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

SANDBOX=$(mktemp -d "$TMPDIR/ci-oracle-lane-test.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
# A harness that fails to SET UP must abort: a half-built sandbox yields a confident wrong verdict.
trap 'rm -rf "$SANDBOX"' EXIT
# Canonical body (plugins/soleur/test/test-helpers.sh), byte-equal by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh: every directory this suite writes into
# must be absolute.
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

echo "=== oracle-only fast lane: Guard 1 (classifier) + Guard 4 (manifest parity) (#12156) ==="

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected: this row proves fail() increments)" 2> /dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf 'FAIL: instrument self-test: pass()/fail() did not both move (passes %d->%d, fails %d->%d)\n' \
    "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
echo "  instrument self-test: pass() and fail() both move"

# ── The check primitive, with a PROBE mode (a mutant being driven counts into PROBE_FAILS only) ──
PROBE=0
PROBE_FAILS=0
if [ -n "${OLP_PROBE_VERBOSE:-}" ]; then exec 3>&2; else exec 3>/dev/null; fi
record() {  # $1=label $2=ok(1|0) $3=detail
  if [ "$PROBE" = 1 ]; then
    if [ "$2" != 1 ]; then
      PROBE_FAILS=$((PROBE_FAILS + 1))
      if [ -n "${OLP_PROBE_VERBOSE:-}" ] && { [ "$PROBE_FAILS" -eq 1 ] || [ "${OLP_PROBE_VERBOSE}" = all ]; }; then printf 'probe-red[mutant %s]: %s: %s\n' "$MUT_N" "$1" "$3" >&3; fi
    fi
    return 0
  fi
  if [ "$2" = 1 ]; then pass; else fail "$1: $3"; fi
}
check_eq() {  # $1=label $2=got $3=want
  if [ "$2" = "$3" ]; then record "$1" 1 ""; else record "$1" 0 "got '$2', want '$3'"; fi
}
check_match() {  # $1=label $2=got $3=regex
  if [[ "$2" =~ $3 ]]; then record "$1" 1 ""; else record "$1" 0 "got '$2', want /$3/"; fi
}
check_contains() {  # $1=label $2=haystack $3=needle
  if [[ "$2" == *"$3"* ]]; then record "$1" 1 ""; else record "$1" 0 "'$3' not found in '${2:0:300}'"; fi
}
rc_of() { "$@" > /dev/null 2>&1; echo $?; }
check_true() {  # $1=label $2=condition-result(0=true)
  if [ "$2" -eq 0 ]; then record "$1" 1 ""; else record "$1" 0 "condition false"; fi
}

# ── The PATH the driver gets: bash, git, coreutils and POSIX text tools only ──
BIN="$SANDBOX/bin"
mkdir -p "$BIN"
for _t in bash git env timeout mktemp wc tr rm cat mkdir sleep ls dirname basename head tail cut sort uniq touch cp mv \
          date id readlink pwd dd tee true false grep sed awk; do
  _p=$(command -v "$_t" 2>/dev/null) || continue
  case "$_p" in /*) ln -s "$_p" "$BIN/$_t" ;; esac
done
unset _t _p
_leaks=""
for _t in node bun python python3 jq gawk mawk egrep perl gh npm npx curl; do
  if env -i PATH="$BIN" bash -c "command -v $_t" >/dev/null 2>&1; then _leaks="$_leaks $_t"; fi
done
unset _t
if [ -n "$_leaks" ]; then
  printf 'FAIL: the restricted PATH still resolves:%s\n' "$_leaks" >&2; exit 2
fi
for _t in bash git timeout mktemp wc tr env rm; do
  [ -e "$BIN/$_t" ] || { printf 'FAIL: the restricted PATH is missing %s\n' "$_t" >&2; exit 2; }
done
unset _t
echo "  restricted PATH: bash, git, coreutils and POSIX text tools only (no node, bun, python, jq, perl, gh)"

# A second PATH whose `git diff` prints the REAL listing and then exits 1 (every other git
# subcommand is the real git): only the exit status can stop the driver.
BIN_GITFAIL="$SANDBOX/bin-gitfail"
mkdir -p "$BIN_GITFAIL"
for _t in "$BIN"/*; do [ "${_t##*/}" = git ] || ln -s "$(readlink "$_t")" "$BIN_GITFAIL/${_t##*/}"; done
_realgit=$(readlink "$BIN/git")
_realbash=$(readlink "$BIN/bash")
printf '#!%s\nif [ "${1:-}" = diff ]; then %s "$@"; exit 1; fi\nexec %s "$@"\n' "$_realbash" "$_realgit" "$_realgit" > "$BIN_GITFAIL/git"
chmod +x "$BIN_GITFAIL/git"
# A third PATH whose `git diff` SIGKILLs the driver mid-run (the defaults-first property: a step
# killed anywhere must leave exactly the defaults block behind).
BIN_GITKILL="$SANDBOX/bin-gitkill"
mkdir -p "$BIN_GITKILL"
for _t in "$BIN"/*; do [ "${_t##*/}" = git ] || ln -s "$(readlink "$_t")" "$BIN_GITKILL/${_t##*/}"; done
printf '#!%s\nif [ "${1:-}" = diff ]; then kill -KILL "$PPID"; sleep 30; fi\nexec %s "$@"\n' "$_realbash" "$_realgit" > "$BIN_GITKILL/git"
chmod +x "$BIN_GITKILL/git"
unset _t _realgit _realbash

# ── Fixture git environment (hermetic config, discovery ceiling, synthesized identity) ──
FX="$SANDBOX/fx"
mkdir -p "$FX" "$SANDBOX/rt" "$SANDBOX/home" "$SANDBOX/tmp" "$SANDBOX/r"
git_fixture_env "$FX/_anchor" || { printf 'FAIL: git_fixture_env refused\n' >&2; exit 2; }

# ── The pristine driver, and the lock-neutralized COPY ───────────────────────
PRISTINE="$SANDBOX/drv.pristine.sh"
cp "$DRIVER" "$PRISTINE"
# The lock line WAS ONE literal line, byte-exact (the PR_AFFECTED_LOCKED analogue), carried on its own
# line — the activation PR deleted it. LOCK_RE is kept as the absence pin: a re-lock must never sneak
# back in through an unrelated diff.
LOCK_RE='^readonly ORACLE_LANE_LOCKED=1([[:space:]]+#.*)?$'
UNLOCKED="$SANDBOX/drv.unlocked.sh"
sed -E "/$LOCK_RE/d" "$PRISTINE" > "$UNLOCKED"

# ── Fixture builders ─────────────────────────────────────────────────────────
ACCEPT="scripts/ci-pr-affected-audit.accept.tsv"
BASELINE="scripts/ci-pr-affected-audit.baseline.tsv"
TAP="scripts/lib/test-affected-paths.sh"
KB_A="knowledge-base/project/learnings/zzleak-a.md"
KB_B="knowledge-base/project/specs/zzleak-pipe/zzleak-y.md"
ORACLE_FIVE="test-webplat,test-bun,test-scripts,test-scripts-heavy,web-platform-build"
ORACLE_FOUR="test-bun,test-scripts,test-scripts-heavy,web-platform-build"
FIVE_RE='^(test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build)(,(test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build))*$'
DEFAULTS=$'oracle_only=false\nactive=false\nskip_legs=\nhead_sha=\nbase_sha='

# The load-bearing exclusion list, one path per member (Guard 1 row 2).
EXCLUSIONS=(
  "scripts/ci-pr-affected-replay.py"
  "scripts/test-all.sh"
  "plugins/soleur/scripts/lint-ratchet.py"
  ".github/workflows/ci.yml"
  "scripts/foo.sh"
  "scripts/lib/zzleak-other-lib.sh"
)

# near-miss doc paths: NOT knowledge-base/**/*.md and NOT a root *.md.
NEARMISS=(
  "knowledge-base-evil/zzleak-evil.md"
  "zzleak-root.mdx"
  "zzleak-x.md.sh"
  "knowledge-base/zzleak-x.md.sh"
  "knowledge-base/zzleak-x.json"
  "knowledge-base/zzleak-x.sh"
  "knowledge-base/zzleak-x.png"
  "docs/legal/zzleak-terms.md"
  "plugins/soleur/docs/zzleak-page.md"
  "apps/web-platform/zzleak-note.md"
)

FX_BASE="$FX/_base"
mkdir -p "$FX_BASE"
(
  cd "$FX_BASE" || exit 1
  git init -q -b main . || exit 1
  git config maintenance.auto false && git config gc.auto 0 || exit 1
  mk() { mkdir -p "$(dirname "$1")"; printf 'seed %s\n' "$1" > "$1"; }
  mk "$ACCEPT"; mk "$BASELINE"
  # The edge-declaration file the extent check parses. SYNTHESIZED, carrying every structural shape
  # of the real scripts/lib/test-affected-paths.sh: comment blocks, closure-leaf arrays, a
  # _CLOSURE_LEAF_RT_* array, ALWAYS_ON_SUITES, AFFECTED_CONSUMED_EDGES, two AFFECTED_*_PATHS arrays
  # and a function. Members carry the leak token so a path echo anywhere is a leak.
  mkdir -p scripts/lib
  cat > "$TAP" <<'TAPEOF'
# Synthesized edge-declaration file for the oracle-lane sentinel. Same structural
# shapes as scripts/lib/test-affected-paths.sh: comment blocks, closure-leaf
# arrays, _CLOSURE_LEAF_RT_* arrays, ALWAYS_ON_SUITES, AFFECTED_CONSUMED_EDGES,
# AFFECTED_*_PATHS arrays and a function.
CLOSURE_LEAF_FILES=(
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)
_CLOSURE_LEAF_RT_X=(
  "scripts/lib/scratch-root.sh"
)

ALWAYS_ON_SUITES=(
  "scripts/zzleak-always-a"
  "scripts/zzleak-always-b"
)

# A comment between declarations.
AFFECTED_CONSUMED_EDGES=(
  "scripts/zzleak-battery-a|ZZLEAK_A_PATHS"
  "scripts/zzleak-battery-b|ZZLEAK_B_PATHS"
)

AFFECTED_SCRIPTS_FOO_PATHS=(
  "scripts/zzleak-foo.test.sh"
  "scripts/zzleak-foo/"
  # THIS FILE: every declared edge set self-includes.
  "scripts/lib/test-affected-paths.sh"
)

AFFECTED_PLUGINS_BAR_PATHS=(
  "plugins/soleur/test/zzleak-bar.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

_zzleak_helper() {
  case "$1" in x) return 0 ;; esac
  return 1
}
TAPEOF
  mk "$KB_A"; mk "$KB_B"
  mk knowledge-base/zzleak-x.json
  mk README.md; mk AGENTS.md; mk CLAUDE.md
  for t in "${EXCLUSIONS[@]}" "${NEARMISS[@]}"; do mk "$t"; done
  mk apps/web-platform/zzleak-app.ts; mk Makefile
  git add -A && git commit -q -m base || exit 1
) || { printf 'FAIL: could not build the base fixture repo\n' >&2; exit 2; }

fx_new() {  # $1=name
  cp -a "$FX_BASE" "$FX/$1" && git -C "$FX/$1" checkout -q -b pr
}
fx_op() {  # $1=name $2=op(M|A|D|R|T|L|G|X) $3=path [$4=path2]
  local d="$FX/$1"
  case "$2" in
    M) printf 'edit %s\n' "$RANDOM" >> "$d/$3"; git -C "$d" add -- "$3" ;;
    A) mkdir -p "$d/$(dirname -- "$3")"; printf 'new\n' > "$d/$3"; git -C "$d" add -- "$3" ;;
    D) git -C "$d" rm -q -- "$3" ;;
    R) mkdir -p "$d/$(dirname -- "$4")"; git -C "$d" mv -- "$3" "$4" ;;
    T) rm -f "$d/$3"; ln -s /etc/hostname "$d/$3"; git -C "$d" add -- "$3" ;;
    L) mkdir -p "$d/$(dirname -- "$3")"; ln -s /etc/hostname "$d/$3"; git -C "$d" add -- "$3" ;;  # a NEW symlink (A, 120000)
    G) git -C "$d" update-index --add --cacheinfo "160000,$(git -C "$d" rev-parse HEAD),$3" ;;      # a NEW gitlink (A, 160000)
    X) chmod +x "$d/$3"; git -C "$d" update-index --chmod=+x -- "$3" ;;                            # mode flip 100644 -> 100755
  esac
}
# fx_tap <name> <edit-id>: one edit to the fixture's test-affected-paths.sh, then git add.
# Each edit-id lands exactly one hunk class the extent checker must classify.
fx_tap() {
  local d="$FX/$1" f="$FX/$1/$TAP"
  case "$2" in
    ins_member)      sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/a\  "scripts/zzleak-new.test.sh"' "$f" ;;
    ins_member_end)  sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/,/^)$/ s|^)$|  "scripts/zzleak-end.test.sh"\n)|' "$f" ;;
    del_member)      sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/,/^)$/ { s|^  "scripts/zzleak-foo.test.sh"$||; /^$/d }' "$f" ;;
    reorder)         sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/,/^)$/ { s|^  "scripts/zzleak-foo.test.sh"$|@@ZZLEAK_SWAP@@|; s|^  "scripts/zzleak-foo/"$|  "scripts/zzleak-foo.test.sh"|; s|^@@ZZLEAK_SWAP@@$|  "scripts/zzleak-foo/"| }' "$f" ;;
    new_array)       cat >> "$f" <<'NEOF'
AFFECTED_SCRIPTS_ZZLEAK_NEW_PATHS=(
  "scripts/zzleak-new.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
NEOF
                     ;;
    del_array)       sed -i '/^AFFECTED_PLUGINS_BAR_PATHS=($/,/^)$/d' "$f" ;;
    ren_array)       sed -i 's/^AFFECTED_PLUGINS_BAR_PATHS=($/AFFECTED_PLUGINS_BAZ_PATHS=(/' "$f" ;;
    comment_in)      sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/a\  # an in-extent note' "$f" ;;
    always_on)       sed -i '/^ALWAYS_ON_SUITES=($/a\  "scripts/zzleak-always-c"' "$f" ;;
    consumed)        sed -i '/^AFFECTED_CONSUMED_EDGES=($/a\  "scripts/zzleak-battery-c|ZZLEAK_C_PATHS"' "$f" ;;
    leaf)            sed -i '/^CLOSURE_LEAF_FILES=($/a\  "scripts/zzleak-leaf.sh"' "$f" ;;
    leaf_rt)         sed -i '/^_CLOSURE_LEAF_RT_X=($/a\  "scripts/zzleak-rt.sh"' "$f" ;;
    comment_out)     sed -i '1i\# a comment outside every extent' "$f" ;;
    func_edit)       sed -i '/^_zzleak_helper() {$/,/^}$/ s|return 1|return 2|' "$f" ;;
    after_paren)     sed -i '/^AFFECTED_PLUGINS_BAR_PATHS=($/,/^)$/ s|^)$|)\n  "scripts/zzleak-late.test.sh"|' "$f" ;;
    bin_nul)         printf '\x00' >> "$f" ;;                                                              # a NUL anywhere makes the blob binary: the -U0 diff is `Binary files`, zero hunks — must NOT pass vacuously
    ins_unquoted)    sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/a\  x' "$f" ;;                                  # an unquoted member inside an extent is code, not data
    ins_evil)        sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/a\  "$(evil)"' "$f" ;;                          # command substitution inside a quoted member — the file is SOURCED bash
    ins_evil_out)    sed -i '1i\  "$(evil)"' "$f" ;;                                                       # the same substitution OUTSIDE every extent
    ins_pp)          sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/a\++evil' "$f" ;;                              # content starts `++`: the diff line is `+++evil`, which must reach ELEM_RE, not the header-skip arm
    ins_member_comment) sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/a\  "scripts/zzleak-cmt.test.sh" # a comment' "$f" ;;  # grammar-legal: member + trailing comment
    unclosed)        sed -i '/^AFFECTED_PLUGINS_BAR_PATHS=($/,/^)$/{/^)$/d}' "$f" ;;                        # delete the closer: the head image's extent walk hits EOF with in=1
    nested)          sed -i '/^AFFECTED_SCRIPTS_FOO_PATHS=($/a\AFFECTED_ZZLEAK_NESTED_PATHS=(' "$f" ;;       # a second opener inside an extent: the bitmap walk refuses
    *) printf 'FAIL: unknown fx_tap edit %s\n' "$2" >&2; exit 2 ;;
  esac
  git -C "$d" add -- "$TAP"
}
fx_merge() {  # $1=name: commit the PR branch, then a genuine --no-ff merge commit on main
  local d="$FX/$1"
  git -C "$d" commit -q --allow-empty -m pr \
    && git -C "$d" checkout -q main \
    && git -C "$d" merge -q --no-ff -m merge pr
}
fx_case() { fx_new "$1" || { printf 'FAIL: fx_new %s\n' "$1" >&2; exit 2; }; }
fx_done() { fx_merge "$1" || { printf 'FAIL: fx_merge %s\n' "$1" >&2; exit 2; }; }

# ── Fixture inventory ────────────────────────────────────────────────────────
# ORACLE-ONLY (must classify true): surface members and in-extent hunks.
fx_case accept; fx_op accept M "$ACCEPT"; fx_done accept
# BASELINE-PATH (must classify false, outside_surface): baseline.tsv is a non-member since PR5z — the only
# possible diff on that path is the baseline-reintroduced alarm shape, which pays the full battery.
fx_case base1; fx_op base1 M "$BASELINE"; fx_done base1
fx_case ab; fx_op ab M "$ACCEPT"; fx_op ab M "$BASELINE"; fx_done ab
fx_case acceptdel; fx_op acceptdel D "$BASELINE"; fx_done acceptdel
fx_case kbdoc; fx_op kbdoc M "$KB_A"; fx_done kbdoc
fx_case kbspec; fx_op kbspec A "knowledge-base/project/specs/zzleak-pipe/zzleak-z.md"; fx_done kbspec
fx_case rootmd; fx_op rootmd M AGENTS.md; fx_done rootmd
fx_case rootnew; fx_op rootnew A zzleak-new-doc.md; fx_done rootnew
fx_case kbdel; fx_op kbdel D "$KB_A"; fx_done kbdel
fx_case kbrn; fx_op kbrn R "$KB_A" "knowledge-base/project/learnings/zzleak-a2.md"; fx_done kbrn
for _t in ins_member ins_member_end del_member reorder new_array del_array ren_array comment_in ins_member_comment; do
  fx_case "tap_$_t"; fx_tap "tap_$_t" "$_t"; fx_done "tap_$_t"
done
unset _t
# ELEMENT GRAMMAR (Guard 1 row 7): every +/- line inside an index hunk must match ELEM_RE — opener, `)`,
# `"member"` + optional comment, whole-line comment, or blank. A NUL makes the blob binary (zero hunks must
# not pass vacuously); a broken image (unclosed extent, nested opener) is extent_parse, not a hunk miss.
for _t in bin_nul ins_unquoted ins_evil ins_evil_out ins_pp unclosed nested; do
  fx_case "tap_$_t"; fx_tap "tap_$_t" "$_t"; fx_done "tap_$_t"
done
unset _t
# Guard 1 row 6 (must-PASS non-canonical): accept.tsv + a KB specs .md + a NEW array block (baseline.tsv was the
# third member until PR5z made it a non-member — accept.tsv keeps the row a must-PASS).
fx_case mustpass6; fx_op mustpass6 M "$ACCEPT"; fx_op mustpass6 M "$KB_B"; fx_tap mustpass6 new_array; fx_done mustpass6
# DIAGRAMS carve-out (ported from ci-pr-selection.sh): a diagrams .md inside an otherwise-oracle diff keeps
# oracle_only=true but drops test-webplat from would_skip/skip_legs.
fx_case diag; fx_op diag M "$ACCEPT"; fx_op diag A "knowledge-base/engineering/architecture/diagrams/zzleak-diag.md"; fx_done diag
fx_case diagx; fx_op diagx A "knowledge-base/engineering/architecture/diagrams/zzleak-diag.md"; fx_op diagx M "apps/web-platform/zzleak-code.ts"; fx_done diagx
# a mode flip on an oracle path stays oracle (both modes allowed)
fx_case mflip; fx_op mflip X "$ACCEPT"; fx_done mflip
fx_case mflipdoc; fx_op mflipdoc X "$KB_A"; fx_done mflipdoc

# OUT-OF-EXTENT hunks in test-affected-paths.sh (Guard 1 row 3): each MUST classify false even
# though the file is a surface member.
for _t in always_on consumed leaf leaf_rt comment_out func_edit after_paren; do
  fx_case "tapx_$_t"; fx_tap "tapx_$_t" "$_t"; fx_done "tapx_$_t"
done
unset _t

# EXCLUSIONS (Guard 1 rows 1-2): one oracle path plus each excluded/outside path must stay full.
fx_case replay; fx_op replay M "$ACCEPT"; fx_op replay M "scripts/ci-pr-affected-replay.py"; fx_done replay
fx_case ex_testall; fx_op ex_testall M "$ACCEPT"; fx_op ex_testall M "scripts/test-all.sh"; fx_done ex_testall
fx_case ex_ratchet; fx_op ex_ratchet M "$ACCEPT"; fx_op ex_ratchet M "plugins/soleur/scripts/lint-ratchet.py"; fx_done ex_ratchet
fx_case ex_ciyml; fx_op ex_ciyml M "$ACCEPT"; fx_op ex_ciyml M ".github/workflows/ci.yml"; fx_done ex_ciyml
fx_case ex_foo; fx_op ex_foo M "$ACCEPT"; fx_op ex_foo M "scripts/foo.sh"; fx_done ex_foo
fx_case ex_lib; fx_op ex_lib M "$ACCEPT"; fx_op ex_lib M "scripts/lib/zzleak-other-lib.sh"; fx_done ex_lib
# the lane's own machinery is excluded: a diff that edits the classifier, its sentinel or its validation
# manifest always pays the battery (outcome-redundant today — outside the surface — load-bearing if it widens)
fx_case ex_oracle_sh; fx_op ex_oracle_sh M "$ACCEPT"; fx_op ex_oracle_sh M "scripts/ci-oracle-lane.sh"; fx_done ex_oracle_sh
fx_case ex_oracle_test; fx_op ex_oracle_test M "$ACCEPT"; fx_op ex_oracle_test M "scripts/ci-oracle-lane.test.sh"; fx_done ex_oracle_test
fx_case ex_oracle_suites; fx_op ex_oracle_suites M "$ACCEPT"; fx_op ex_oracle_suites M "scripts/ci-oracle-lane-suites.txt"; fx_done ex_oracle_suites
fx_case ex_oracle_legs; fx_op ex_oracle_legs M "$ACCEPT"; fx_op ex_oracle_legs M "scripts/ci-oracle-lane-legs.tsv"; fx_done ex_oracle_legs
fx_case ex_tap; fx_op ex_tap M "$ACCEPT"; fx_tap ex_tap always_on; fx_done ex_tap
fx_case ex_code; fx_op ex_code M "$ACCEPT"; fx_op ex_code M "apps/web-platform/zzleak-app.ts"; fx_done ex_code
fx_case ex_mk; fx_op ex_mk M "$ACCEPT"; fx_op ex_mk M Makefile; fx_done ex_mk
for _i in "${!NEARMISS[@]}"; do fx_case "nd$_i"; fx_op "nd$_i" A "${NEARMISS[$_i]}"; fx_done "nd$_i"; done
unset _i
# a bare FILE named `knowledge-base` (the directory goes away in the same PR)
fx_case ndbare
( cd "$FX/ndbare" && git rm -rq knowledge-base && printf 'x\n' > knowledge-base && git add knowledge-base )
fx_done ndbare

# ODD PATHS (printable-ASCII / no `::` / no `,` arm): an in-surface prefix does not rescue them.
fx_case nl; fx_op nl A $'knowledge-base/zzleak-a\nb.md'; fx_done nl
fx_case cr; fx_op cr A $'knowledge-base/zzleak-cr\rx.md'; fx_done cr
fx_case tabp; fx_op tabp A $'knowledge-base/zzleak-tab\tx.md'; fx_done tabp
fx_case col; fx_op col A "knowledge-base/zzleak::warning.md"; fx_done col
fx_case com; fx_op com A "knowledge-base/zzleak,b.md"; fx_done com
fx_case nasc0; fx_op nasc0 A $'knowledge-base/zzleak-ls\xe2\x80\xa8x.md'; fx_done nasc0
fx_case nasc1; fx_op nasc1 A $'knowledge-base/zzleak-c1\xc2\x85x.md'; fx_done nasc1
fx_case nasc2; fx_op nasc2 A $'knowledge-base/zzleak-\xc3\xa9.md'; fx_done nasc2
fx_case nbad; fx_op nbad A $'knowledge-base/zzleak-\xffx.md'; fx_done nbad

# STATUS/MODES: typechange T, a new symlink and a new gitlink under knowledge-base.
fx_case typ; fx_op typ T "$KB_A"; fx_done typ
fx_case msym; fx_op msym L "knowledge-base/project/zzleak-sym.md"; fx_done msym
fx_case mgit; fx_op mgit G "knowledge-base/project/zzleak-gl.md"; fx_done mgit
# DELETING an existing symlink (old mode 120000, new 000000, status D)
cp -a "$FX_BASE" "$FX/mdsym" && ln -s /etc/hostname "$FX/mdsym/knowledge-base/project/zzleak-oldsym.md" \
  && git -C "$FX/mdsym" add -A && git -C "$FX/mdsym" commit -q -m sym && git -C "$FX/mdsym" checkout -q -b pr \
  && git -C "$FX/mdsym" rm -q -- knowledge-base/project/zzleak-oldsym.md || { printf 'FAIL: fixture mdsym\n' >&2; exit 2; }
fx_done mdsym

# SHAPE fixtures: a non-merge HEAD, an octopus, a shallow clone, a broken object, no repo.
fx_case nm; fx_op nm M "$KB_A"
git -C "$FX/nm" commit -q -m pr && git -C "$FX/nm" checkout -q main && git -C "$FX/nm" merge -q --ff-only pr > /dev/null 2>&1
fx_case octo; fx_op octo M "$KB_A"; git -C "$FX/octo" commit -q -m pr1
git -C "$FX/octo" checkout -q -b pr2 main && printf 'two\n' >> "$FX/octo/$KB_B" && git -C "$FX/octo" commit -q -am pr2
git -C "$FX/octo" checkout -q main && git -C "$FX/octo" merge -q --no-ff -m octopus pr pr2 > /dev/null 2>&1
git clone -q --depth 1 "file://$FX/kbdoc" "$FX/shallow" 2>/dev/null
cp -a "$FX/kbdoc" "$FX/broken"
_bt=$(git -C "$FX/broken" rev-parse 'HEAD^1^{tree}')
rm -f "$FX/broken/.git/objects/${_bt:0:2}/${_bt:2}"
unset _bt
mkdir -p "$FX/norepo"

# BULK: 501 in-surface files (over the cap) and exactly 500 (inside it), plus a >64 KB listing.
fx_case n501
( cd "$FX/n501" && mkdir -p knowledge-base/bulk && i=0 && while [ "$i" -lt 501 ]; do printf 'x\n' > "knowledge-base/bulk/zzleak-$i.md"; i=$((i + 1)); done && git add -A )
fx_done n501
fx_case n500
( cd "$FX/n500" && mkdir -p knowledge-base/bulk && i=0 && while [ "$i" -lt 500 ]; do printf 'x\n' > "knowledge-base/bulk/zzleak-$i.md"; i=$((i + 1)); done && git add -A )
fx_done n500
_long=$(printf 'd%.0s' $(seq 1 100))
_long2=$(printf 'f%.0s' $(seq 1 100))
fx_case big
( cd "$FX/big" && mkdir -p "knowledge-base/zzleak-$_long" && i=0 && while [ "$i" -lt 320 ]; do printf 'x\n' > "knowledge-base/zzleak-$_long/zzleak-$_long2-$i.md"; i=$((i + 1)); done && git add -A )
fx_done big
fx_case bigbad
( cd "$FX/bigbad" && mkdir -p "knowledge-base/zzleak-$_long" && i=0 && while [ "$i" -lt 320 ]; do printf 'x\n' > "knowledge-base/zzleak-$_long/zzleak-$_long2-$i.md"; i=$((i + 1)); done && git add -A )
fx_op bigbad M "apps/web-platform/zzleak-app.ts"
fx_done bigbad
unset _long _long2
# an empty diff: a genuine merge commit whose tree equals the base tree
fx_case empty; fx_done empty

# STALE BASE (#12418): the merge ref's HEAD^1 froze at a base tip BEFORE the main-side commit the PR head
# already merged. `diff HEAD^1..HEAD` re-counts that main-side change; merge-base(HEAD^2, live base) does not.
# `stale`: main advanced an outside-surface file; the PR merged it and edited a doc — old: outside_surface, new: lane.
fx_case stale
{ git -C "$FX/stale" checkout -q main \
  && printf 'main-side\n' >> "$FX/stale/scripts/foo.sh" \
  && git -C "$FX/stale" add scripts/foo.sh \
  && git -C "$FX/stale" commit -q -m main2 \
  && git -C "$FX/stale" update-ref refs/heads/zzleak-pr-base main \
  && git -C "$FX/stale" checkout -q pr \
  && git -C "$FX/stale" merge -q --no-ff -m merge-main main \
  && printf 'doc\n' >> "$FX/stale/$KB_A" \
  && git -C "$FX/stale" add -- "$KB_A" \
  && git -C "$FX/stale" commit -q -m pr \
  && git -C "$FX/stale" checkout -q --detach 'main~1' \
  && git -C "$FX/stale" merge -q --no-ff -m merge-ref pr; } \
  || { printf 'FAIL: fixture stale\n' >&2; exit 2; }
# `stale_code`: identical topology, but the PR's own delta carries a code file — proves the gate is not a
# reject-everything stub on merge-carrying branches (new: outside_surface on the PR delta).
fx_case stale_code
{ git -C "$FX/stale_code" checkout -q main \
  && printf 'main-side\n' >> "$FX/stale_code/scripts/foo.sh" \
  && git -C "$FX/stale_code" add scripts/foo.sh \
  && git -C "$FX/stale_code" commit -q -m main2 \
  && git -C "$FX/stale_code" update-ref refs/heads/zzleak-pr-base main \
  && git -C "$FX/stale_code" checkout -q pr \
  && git -C "$FX/stale_code" merge -q --no-ff -m merge-main main \
  && printf 'x\n' >> "$FX/stale_code/apps/web-platform/zzleak-app.ts" \
  && git -C "$FX/stale_code" add apps/web-platform/zzleak-app.ts \
  && git -C "$FX/stale_code" commit -q -m pr \
  && git -C "$FX/stale_code" checkout -q --detach 'main~1' \
  && git -C "$FX/stale_code" merge -q --no-ff -m merge-ref pr; } \
  || { printf 'FAIL: fixture stale_code\n' >&2; exit 2; }
# `unrel`: the fetched live base shares NO ancestor with the PR head — merge-base is empty, fail closed.
cp -a "$FX/accept" "$FX/unrel"
{ git -C "$FX/unrel" checkout -q --orphan zzleak-unrel \
  && git -C "$FX/unrel" commit -q --allow-empty -m unrel \
  && git -C "$FX/unrel" update-ref refs/heads/zzleak-pr-base zzleak-unrel \
  && git -C "$FX/unrel" checkout -q main; } \
  || { printf 'FAIL: fixture unrel\n' >&2; exit 2; }

# ── drive(): run the driver once, hermetically, and assert the invariants every run must hold ──
RUN_N=0
EXPECT_KILLED=0
LEAK="zzleak"
REPO_NAME="zzleak-org/zzleak-repo"   # carries the leak token: the repository name reaches no output

drive() {  # $1=fixture $2=driver-file; remaining args: KEY=VALUE overrides (later wins; UNSET:SWITCH removes)
  local name="$1" drv="$2"; shift 2
  local repo="$FX/$name" head prhead base o line
  RUN_N=$((RUN_N + 1))
  o="$SANDBOX/r/$RUN_N"
  assert_fixture_dir "$o"
  mkdir -p "$o"
  : > "$o/gh.out"; : > "$o/sum.out"
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || head="0000000000000000000000000000000000000000"
  prhead=$(git -C "$repo" rev-parse 'HEAD^2' 2>/dev/null) || prhead="$head"
  base=$(git -C "$repo" rev-parse 'HEAD^1' 2>/dev/null) || base="$head"
  # The live base ref the pull_request arm fetches (#12418): a self `file://` origin plus a `zzleak-pr-base`
  # branch at the merge ref's first parent keeps merge-base(HEAD^2, FETCH_HEAD) == HEAD^1 — the pre-#12418
  # diff — for every fixture that does not pre-create the ref elsewhere (the stale-base ones do).
  git -C "$repo" remote get-url origin >/dev/null 2>&1 \
    || git -C "$repo" remote add origin "file://$repo" 2>/dev/null || true
  git -C "$repo" rev-parse --verify -q refs/heads/zzleak-pr-base >/dev/null 2>&1 \
    || git -C "$repo" update-ref refs/heads/zzleak-pr-base "$base" 2>/dev/null || true
  local -a e=(
    "PATH=$BIN" "HOME=$SANDBOX/home" "TMPDIR=$SANDBOX/tmp" "LANG=C"
    "GIT_CEILING_DIRECTORIES=$GIT_CEILING_DIRECTORIES" "GIT_CONFIG_NOSYSTEM=1" "GIT_CONFIG_GLOBAL=/dev/null"
    "GIT_ATTR_NOSYSTEM=1" "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" "GIT_TERMINAL_PROMPT=0"
    "EVENT_NAME=pull_request" "SWITCH=on" "GITHUB_SHA=$head" "PR_HEAD_SHA=$prhead"
    "HEAD_REPO=$REPO_NAME" "GH_REPO=$REPO_NAME" "RUN_ATTEMPT=1"
    "MERGE_GROUP_HEAD_SHA=$head" "MERGE_GROUP_BASE_SHA=$base"
    "PR_BASE_REF=zzleak-pr-base"
    "GITHUB_OUTPUT=$o/gh.out" "GITHUB_STEP_SUMMARY=$o/sum.out" "RUNNER_TEMP=$SANDBOX/rt"
    "DRV=$drv"
  )
  local -a ov=() e2=()
  local a x
  for a in "$@"; do
    if [ "$a" = "UNSET:SWITCH" ]; then
      e2=()
      for x in "${e[@]}"; do case "$x" in SWITCH=*) ;; *) e2+=("$x") ;; esac; done
      e=("${e2[@]}")
    else
      ov+=("$a")
    fi
  done
  # sweep stale oracle-lane scratch dirs BEFORE the run (a SIGKILLed earlier row leaves one, legitimately — the
  # post-run reaped check below must see only THIS run's leak, not history's)
  rm -rf "$SANDBOX"/rt/oracle-lane.* "$SANDBOX"/tmp/oracle-lane.* 2>/dev/null
  { ( cd "$repo" && env -i "${e[@]}" "${ov[@]}" bash -c 'exec bash "$DRV"' ) > "$o/stdout" 2> "$o/stderr"; } 2> /dev/null
  RC=$?
  O="$o"
  # outputs: last value per key wins (the GITHUB_OUTPUT rule); the line count tells defaults-only
  # from defaults+final.
  O_OO=""; O_ACTIVE=""; O_SKIP=""; O_HEAD=""; O_BASE=""; O_NLINES=0; O_TEXT=""
  local badlines=0
  while IFS= read -r line; do
    O_NLINES=$((O_NLINES + 1))
    O_TEXT="${O_TEXT:+$O_TEXT$'\n'}$line"
    case "$line" in
      oracle_only=*) O_OO="${line#oracle_only=}" ;;
      active=*) O_ACTIVE="${line#active=}" ;;
      skip_legs=*) O_SKIP="${line#skip_legs=}" ;;
      head_sha=*) O_HEAD="${line#head_sha=}" ;;
      base_sha=*) O_BASE="${line#base_sha=}" ;;
      *) badlines=$((badlines + 1)) ;;
    esac
  done < "$o/gh.out"
  # the annotation: exactly one SOLEUR_ORACLE_LANE notice on every in-scope classified run
  NOTICE=""; NOTICE_N=0; STDOUT_N=0
  while IFS= read -r line; do
    STDOUT_N=$((STDOUT_N + 1))
    case "$line" in '::notice title=ci-oracle-lane::SOLEUR_ORACLE_LANE '*) NOTICE_N=$((NOTICE_N + 1)); NOTICE="$line" ;; esac
  done < "$o/stdout"
  # notice fields: key=value tokens after the prefix (the field SET is what's pinned, not order)
  N_OO=""; N_ACTIVE=""; N_LOCKED=""; N_WOULD=""; N_REASON=""; N_ATTEMPT=""; N_FILES=""
  if [ -n "$NOTICE" ]; then
    local rest="${NOTICE#::notice title=ci-oracle-lane::SOLEUR_ORACLE_LANE }" tok
    for tok in $rest; do
      case "$tok" in
        oracle_only=*) N_OO="${tok#oracle_only=}" ;;
        active=*) N_ACTIVE="${tok#active=}" ;;
        locked=*) N_LOCKED="${tok#locked=}" ;;
        would_skip=*) N_WOULD="${tok#would_skip=}" ;;
        reason=*) N_REASON="${tok#reason=}" ;;
        attempt=*) N_ATTEMPT="${tok#attempt=}" ;;
        files=*) N_FILES="${tok#files=}" ;;
      esac
    done
    NOTICE_OK=1
  else
    NOTICE_OK=0
  fi
  SUMTXT=""; [ -s "$o/sum.out" ] && SUMTXT=$(<"$o/sum.out")

  # ---- invariants (every run) ----
  if [ "$EXPECT_KILLED" = 1 ]; then
    check_eq "run$RUN_N($name) killed driver exits 137" "$RC" "137"
    check_eq "run$RUN_N($name) a killed step leaves ONLY the defaults" "$O_TEXT" "$DEFAULTS"
  else
    check_eq "run$RUN_N($name) the driver exits 0" "$RC" "0"
    check_eq "run$RUN_N($name) output lines are all grammar-shaped" "$badlines" "0"
    check_true "run$RUN_N($name) defaults then one final block (10 lines) or defaults only on a crash" \
      "$([ "$O_NLINES" = 10 ] || [ "$O_NLINES" = 5 ]; echo $?)"
    check_eq "run$RUN_N($name) exactly one SOLEUR_ORACLE_LANE notice" "$NOTICE_N" "1"
    check_eq "run$RUN_N($name) the notice carries oracle_only/active/locked/would_skip" \
      "$([ -n "$N_OO" ] && [ -n "$N_ACTIVE" ] && [ -n "$N_LOCKED" ] && [ -n "$N_WOULD" ]; echo $?)" "0"
    check_eq "run$RUN_N($name) the notice oracle_only equals the output-file oracle_only" "$N_OO" "$O_OO"
    check_eq "run$RUN_N($name) the notice active equals the output-file active" "$N_ACTIVE" "$O_ACTIVE"
  fi
  check_match "run$RUN_N($name) oracle_only grammar" "$O_OO" '^(true|false)?$'
  check_match "run$RUN_N($name) active grammar" "$O_ACTIVE" '^(true|false)?$'
  check_match "run$RUN_N($name) head_sha grammar" "$O_HEAD" '^([0-9a-f]{40})?$'
  check_match "run$RUN_N($name) base_sha grammar" "$O_BASE" '^([0-9a-f]{40})?$'
  check_match "run$RUN_N($name) skip_legs grammar" "$O_SKIP" '^([a-z-]+(,[a-z-]+)*)?$'
  check_true "run$RUN_N($name) skip_legs names only the five heavy legs" \
    "$( [ -z "$O_SKIP" ] || [[ "$O_SKIP" =~ $FIVE_RE ]]; echo $?)"
  if [ "$O_ACTIVE" = true ]; then
    check_true "run$RUN_N($name) active=true carries a non-empty skip list" "$([ -n "$O_SKIP" ]; echo $?)"
  else
    check_eq "run$RUN_N($name) skip_legs is empty unless active" "$O_SKIP" ""
  fi
  local f leaked=0 shaleak=0
  for f in "$o/gh.out" "$o/stdout" "$o/stderr" "$o/sum.out"; do
    if grep -qF "$LEAK" "$f"; then leaked=1; fi
  done
  for f in "$o/stdout" "$o/stderr" "$o/sum.out"; do
    if grep -qF -e "$head" -e "$prhead" -e "$base" "$f"; then shaleak=1; fi
  done
  check_eq "run$RUN_N($name) no raw path, repo name or switch value in any output, annotation or summary" "$leaked" "0"
  check_eq "run$RUN_N($name) no sha in stderr, the notice or the summary" "$shaleak" "0"
  if [ "$EXPECT_KILLED" != 1 ]; then
    check_eq "run$RUN_N($name) stderr is empty" "$(head -c 200 "$o/stderr")" ""
    # the EXIT trap owns scratch cleanup on EVERY path (normal, early return, abort): a leaked oracle-lane.*
    # workdir under RUNNER_TEMP or TMPDIR means the trap is gone or reordered. (EXPECT_KILLED rows are SIGKILLed
    # mid-run — an untrappable leak is the correct behaviour there and stays unasserted.)
    check_eq "run$RUN_N($name) the oracle scratch dir is reaped on exit" \
      "$(find "$SANDBOX/rt" "$SANDBOX/tmp" -maxdepth 1 -name 'oracle-lane.*' -type d 2>/dev/null | wc -l)" "0"
  fi
}

expect_lane() {  # $1=label: oracle_only=true, armed post-activation, audit shas bound
  local lbl="$1"
  check_eq "$lbl: oracle_only" "$O_OO" "true"
  check_eq "$lbl: active (unlocked)" "$O_ACTIVE" "true"
  check_eq "$lbl: skip_legs is the five heavy legs (unlocked)" "$O_SKIP" "$ORACLE_FIVE"
  check_eq "$lbl: would_skip telemetry is the five heavy legs" "$N_WOULD" "$ORACLE_FIVE"
  check_eq "$lbl: notice locked" "$N_LOCKED" "false"
  check_match "$lbl: head_sha bound" "$O_HEAD" '^[0-9a-f]{40}$'
  check_match "$lbl: base_sha bound" "$O_BASE" '^[0-9a-f]{40}$'
}
expect_full() {  # $1=label: oracle_only=false, nothing would be skipped
  local lbl="$1"
  check_eq "$lbl: oracle_only" "$O_OO" "false"
  check_eq "$lbl: active" "$O_ACTIVE" "false"
  check_eq "$lbl: skip_legs" "$O_SKIP" ""
  check_eq "$lbl: would_skip" "$N_WOULD" "none"
  check_eq "$lbl: notice active" "$N_ACTIVE" "false"
}

# ═══ THE ROWS ═══════════════════════════════════════════════════════════════
# Each row takes the driver file ($1), so the same row runs against the pristine driver (CONTROL)
# and a mutant copy (PROBE).

row_oracle_surface() {  # the must-PASS set: surface members and in-extent hunks all classify
  local d="$1" f
  for f in accept kbdoc kbspec rootmd rootnew kbdel kbrn mflip mflipdoc mustpass6; do
    drive "$f" "$d"
    expect_lane "O-SURFACE oracle-only fixture '$f'"
  done
  # baseline.tsv is NOT a surface member (PR5z strict-zero): the only possible diff on that path is a
  # baseline-reintroduced alarm shape — modify, modify-with-sibling and delete all pay the full battery.
  for f in base1 ab acceptdel; do
    drive "$f" "$d"
    expect_full "O-SURFACE baseline-path fixture '$f'"
    check_eq "O-SURFACE '$f': reason" "$N_REASON" "outside_surface"
  done
  # the diagrams carve-out: oracle_only stays true, would_skip drops test-webplat (four-name list)
  drive diag "$d"
  check_eq "O-DIAGRAMS accept+diagrams.md: oracle_only" "$O_OO" "true"
  check_eq "O-DIAGRAMS would_skip is the four-name subset" "$N_WOULD" "$ORACLE_FOUR"
  # the carve-out never rescues a contaminated diff: diagrams.md + a code path pays the full battery
  drive diagx "$d"
  expect_full "O-DIAGRAMS diagrams+contaminant pays the full battery"
  check_eq "O-DIAGRAMS contaminated: reason" "$N_REASON" "outside_surface"
  for f in tap_ins_member tap_ins_member_end tap_del_member tap_reorder tap_new_array tap_del_array tap_ren_array tap_comment_in; do
    drive "$f" "$d"
    expect_lane "O-EXTENT in-extent hunk '$f'"
  done
}
row_shape_ok() {  # the validated pull_request shape emits the audit values
  local d="$1" p1 p2
  drive accept "$d"
  p1=$(git -C "$FX/accept" rev-parse 'HEAD^1'); p2=$(git -C "$FX/accept" rev-parse 'HEAD^2')
  check_eq "O-1 valid shape: head_sha is HEAD^2" "$O_HEAD" "$p2"
  check_eq "O-1 valid shape: base_sha is HEAD^1" "$O_BASE" "$p1"
}
row_stale_base() {  # #12418: diff base is the merge-base against the fetched live base, never frozen HEAD^1
  local d="$1" m2
  # `stale`: HEAD^1 is a stale base tip and the PR head merged a newer main carrying an outside-surface edit.
  # The frozen-parent derivation re-counts that main-side file (outside_surface); the merge-base diff is the
  # PR's own delta only — one doc — so the lane fires and base_sha is the merge-base, not HEAD^1.
  drive stale "$d"
  expect_lane "O-BASE stale merge-ref: lane classifies on the PR's own delta"
  check_eq "O-BASE stale: files counts the PR delta only" "$N_FILES" "1"
  m2=$(git -C "$FX/stale" rev-parse refs/heads/zzleak-pr-base)
  check_eq "O-BASE stale: base_sha is the live merge-base, not HEAD^1" "$O_BASE" "$m2"
  # the same topology with a PR-side code file still pays the battery — not a reject-nothing arm either
  drive stale_code "$d"
  expect_full "O-BASE stale merge-ref + PR-side code pays the battery"
  check_eq "O-BASE stale+code: reason" "$N_REASON" "outside_surface"
  # every resolution failure is a named fail-closed arm, never a partial classification
  drive accept "$d" "PR_BASE_REF=zzleak-no-such-ref"
  expect_full "O-BASE an unresolvable live base fails closed"
  check_eq "O-BASE missing remote ref: reason" "$N_REASON" "base_fetch"
  drive unrel "$d"
  expect_full "O-BASE an unrelated live base (empty merge-base) fails closed"
  check_eq "O-BASE empty merge-base: reason" "$N_REASON" "no_merge_base"
  drive accept "$d" "PR_BASE_REF=+refs/heads/x:refs/heads/y"
  expect_full "O-BASE a refspec-shaped base ref is rejected before fetch"
  check_eq "O-BASE refspec-shaped ref: reason" "$N_REASON" "bad_base_ref"
  drive accept "$d" "PR_BASE_REF="
  expect_full "O-BASE an empty base ref is rejected before fetch"
  check_eq "O-BASE empty ref: reason" "$N_REASON" "bad_base_ref"
}
row_shape() {  # two-parent merge-ref only: octopus, non-merge HEAD, HEAD^2 != PR head, empty, shallow, not a repo
  local d="$1" b
  drive octo "$d"
  check_eq "O-1 three-parent merge: precondition (4 words in rev-list)" "$(git -C "$FX/octo" rev-list --parents -n 1 HEAD | wc -w)" "4"
  expect_full "O-1 three-parent merge"
  drive nm "$d"
  expect_full "O-1 a non-merge HEAD (one parent)"
  drive shallow "$d"
  expect_full "O-1 shallow checkout (depth-1 merge ref)"
  drive norepo "$d"
  expect_full "O-1 not a repository"
  b=$(git -C "$FX/accept" rev-parse 'HEAD^1')
  drive accept "$d" "PR_HEAD_SHA=$b"
  expect_full "O-1 HEAD^2 != PR head sha"
  check_eq "O-1 HEAD^2 != PR head sha: no audit values" "$O_HEAD$O_BASE" ""
  drive accept "$d" "PR_HEAD_SHA="
  expect_full "O-1 empty PR head sha"
  # the merge-ref HEAD must BE GITHUB_SHA (GUARD:O1-HEAD-IS-GITHUB-SHA): a different 40-hex or a non-hex value
  # is not the runner's merge commit — bad_merge_shape, fail closed.
  drive accept "$d" "GITHUB_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  expect_full "O-1 GITHUB_SHA != merge-ref HEAD"
  check_eq "O-1 GITHUB_SHA mismatch: reason" "$N_REASON" "bad_merge_shape"
  drive accept "$d" "GITHUB_SHA=nothex"
  expect_full "O-1 non-hex GITHUB_SHA"
  check_eq "O-1 non-hex GITHUB_SHA: reason" "$N_REASON" "bad_merge_shape"
}
row_exclusions() {  # Guard 1 rows 1-2: the load-bearing exclusion list plus every outside-surface path
  # the reason is pinned per row: the exclusion check is VERDICT-redundant with the surface check by design (its
  # members are already outside the surface), so dropping it only moves reason=excluded to reason=outside_surface.
  local d="$1"
  drive replay "$d"
  expect_full "O-EXC row1 replay.py beside accept.tsv"
  check_eq "O-EXC row1 replay.py: reason" "$N_REASON" "excluded"
  drive ex_testall "$d";  expect_full "O-EXC scripts/test-all.sh"
  check_eq "O-EXC test-all.sh: reason" "$N_REASON" "excluded"
  drive ex_ratchet "$d";  expect_full "O-EXC lint-ratchet.py"
  check_eq "O-EXC lint-ratchet.py: reason" "$N_REASON" "excluded"
  drive ex_ciyml "$d";    expect_full "O-EXC .github/workflows/ci.yml"
  check_eq "O-EXC ci.yml: reason" "$N_REASON" "excluded"
  drive ex_foo "$d";      expect_full "O-EXC scripts/foo.sh"
  check_eq "O-EXC scripts/foo.sh: reason" "$N_REASON" "outside_surface"
  drive ex_lib "$d";      expect_full "O-EXC other scripts/lib/**"
  check_eq "O-EXC scripts/lib/**: reason" "$N_REASON" "excluded"
  drive ex_oracle_sh "$d";   expect_full "O-EXC the lane driver itself"
  check_eq "O-EXC ci-oracle-lane.sh: reason" "$N_REASON" "excluded"
  drive ex_oracle_test "$d"; expect_full "O-EXC this sentinel"
  check_eq "O-EXC ci-oracle-lane.test.sh: reason" "$N_REASON" "excluded"
  drive ex_oracle_suites "$d"; expect_full "O-EXC the validation manifest"
  check_eq "O-EXC ci-oracle-lane-suites.txt: reason" "$N_REASON" "excluded"
  drive ex_oracle_legs "$d";  expect_full "O-EXC the leg assignment"
  check_eq "O-EXC ci-oracle-lane-legs.tsv: reason" "$N_REASON" "excluded"
  drive ex_tap "$d";      expect_full "O-EXC accept + out-of-extent hunk"
  check_eq "O-EXC out-of-extent hunk: reason" "$N_REASON" "extent_miss"
  drive ex_code "$d";     expect_full "O-EXC apps/web-platform ts"
  check_eq "O-EXC apps ts: reason" "$N_REASON" "outside_surface"
  drive ex_mk "$d";       expect_full "O-EXC Makefile"
  check_eq "O-EXC Makefile: reason" "$N_REASON" "outside_surface"
}
row_extent_out() {  # Guard 1 row 3: hunks outside AFFECTED_*_PATHS extents disqualify the whole diff
  local d="$1" t
  for t in always_on consumed leaf leaf_rt comment_out func_edit after_paren; do
    drive "tapx_$t" "$d"
    expect_full "O-EXTENT out-of-extent hunk '$t'"
  done
}
row_elem_grammar() {  # Guard 1 row 7: the element grammar inside index hunks, the binary-diff guard and the
  local d="$1"        # bitmap return-1 arms (unclosed extent / nested opener both fail closed as extent_parse)
  drive tap_bin_nul "$d";        expect_full "O-BINARY a NUL anywhere makes the index blob binary"
  check_eq "O-BINARY index blob: reason" "$N_REASON" "extent_miss"
  drive tap_ins_unquoted "$d";   expect_full "O-ELEM an unquoted member is code, not data"
  check_eq "O-ELEM unquoted member: reason" "$N_REASON" "extent_miss"
  drive tap_ins_evil "$d";       expect_full "O-ELEM quoted command substitution is code, not data"
  check_eq "O-ELEM quoted substitution: reason" "$N_REASON" "extent_miss"
  drive tap_ins_evil_out "$d";   expect_full "O-ELEM substitution outside every extent"
  check_eq "O-ELEM substitution outside extents: reason" "$N_REASON" "extent_miss"
  drive tap_ins_pp "$d";         expect_full "O-ELEM plus-prefixed content must reach the grammar arm, not the header skip"
  check_eq "O-ELEM plus-prefixed payload: reason" "$N_REASON" "extent_miss"
  drive tap_ins_member_comment "$d"; expect_lane "O-ELEM member + trailing comment stays oracle (no over-rejection)"
  drive tap_unclosed "$d";       expect_full "O-ELEM an unclosed extent image"
  check_eq "O-ELEM unclosed extent: reason" "$N_REASON" "extent_parse"
  drive tap_nested "$d";         expect_full "O-ELEM a second opener inside an extent"
  check_eq "O-ELEM nested opener: reason" "$N_REASON" "extent_parse"
}
row_allowlist() {  # the doc surface is knowledge-base/**/*.md or a root *.md — near-misses stay full
  local d="$1" i
  for i in "${!NEARMISS[@]}"; do
    drive "nd$i" "$d"
    expect_full "O-DOC near-miss '${NEARMISS[$i]}'"
  done
  drive ndbare "$d"
  expect_full "O-DOC a bare file named 'knowledge-base'"
}
row_fork() {  # same-repo head only (pull_request)
  local d="$1" v
  for v in "x/other" "" "${REPO_NAME^^}"; do
    drive accept "$d" "HEAD_REPO=$v"
    expect_full "O-FORK HEAD_REPO='$v'"
  done
  drive accept "$d" "HEAD_REPO=" "GH_REPO="
  expect_full "O-FORK both repos empty is NOT equal"
}
row_attempt() {  # attempt 1 only, on BOTH events
  local d="$1" v
  for v in 2 3 "" x "1 " 01 -1; do
    drive accept "$d" "RUN_ATTEMPT=$v"
    expect_full "O-ATTEMPT pull_request RUN_ATTEMPT='$v'"
  done
  for v in 2 ""; do
    drive accept "$d" "EVENT_NAME=merge_group" "RUN_ATTEMPT=$v"
    expect_full "O-ATTEMPT merge_group RUN_ATTEMPT='$v'"
  done
}
row_maxfiles() {  # the ≤500 cap
  local d="$1"
  drive n501 "$d"
  expect_full "O-MAX 501 changed files"
  drive n500 "$d"
  expect_lane "O-MAX 500 changed files is inside the cap"
  drive big "$d"
  local sz
  sz=$(git -C "$FX/big" diff -z --raw --no-renames --no-abbrev HEAD^1 HEAD | wc -c)
  check_true "O-MAX the >64KB fixture really is over 64 KB ($sz bytes)" "$([ "$sz" -gt 65536 ]; echo $?)"
  expect_lane "O-MAX a >64KB in-surface listing classifies"
  drive bigbad "$d"
  expect_full "O-MAX a >64KB listing with a code file at the end"
}
row_status_modes() {  # M/A/D only, modes ⊆ {000000,100644,100755}
  # reason is pinned per fixture: the status arm runs BEFORE the mode arms, so a typechange on an in-surface path
  # reads non_oracle_status (kill the status case and it falls through to non_oracle_mode — reason-visible only).
  local d="$1" f
  drive typ "$d"
  expect_full "O-MODE typechange fixture 'typ'"
  check_eq "O-STATUS typechange: reason" "$N_REASON" "non_oracle_status"
  for f in msym mgit mdsym; do
    drive "$f" "$d"
    expect_full "O-MODE symlink/gitlink fixture '$f'"
    check_eq "O-MODE '$f': reason" "$N_REASON" "non_oracle_mode"
  done
  drive mflip "$d"
  expect_lane "O-MODE a 100644->100755 flip on accept.tsv stays in-surface"
  drive mflipdoc "$d"
  expect_lane "O-MODE a mode flip on a KB doc stays in-surface"
}
row_odd() {  # control characters, `::`, `,`, non-ASCII and invalid UTF-8 in a path
  local d="$1" f
  for f in nl cr tabp col com nasc0 nasc1 nasc2 nbad; do
    drive "$f" "$d"
    expect_full "O-PATH odd path fixture '$f'"
  done
}
row_empty() {  # Guard 1 row 5: an EMPTY surface membership must NOT classify (the vacuity arm)
  # the reason is pinned: kill the vacuity arm and an empty listing falls through to files=0 → malformed_diff —
  # verdict-identical, reason-visible.
  local d="$1"
  drive empty "$d"
  expect_full "O-EMPTY pull_request empty diff"
  check_eq "O-EMPTY pull_request empty diff: reason" "$N_REASON" "empty_diff"
  drive empty "$d" "EVENT_NAME=merge_group"
  expect_full "O-EMPTY merge_group empty diff"
  check_eq "O-EMPTY merge_group empty diff: reason" "$N_REASON" "empty_diff"
  # the same with the head/base shas EQUAL (a zero-range batch)
  drive accept "$d" "EVENT_NAME=merge_group" "MERGE_GROUP_BASE_SHA=$(git -C "$FX/accept" rev-parse HEAD)"
  expect_full "O-EMPTY merge_group base==head (zero-range batch)"
  check_eq "O-EMPTY merge_group base==head: reason" "$N_REASON" "empty_diff"
}
row_diff_error() {  # Guard 1 row 4: the listing cannot be trusted → fail closed, never skip
  local d="$1"
  drive broken "$d"
  expect_full "O-DIFF git diff fails (missing tree object)"
  drive accept "$d" "PATH=$BIN_GITFAIL"
  expect_full "O-DIFF git diff prints a valid listing then exits 1"
  check_eq "O-DIFF git diff exit 1 with a listing: nothing would be skipped" "$N_WOULD" "none"
}
row_event_out() {  # only pull_request and merge_group classify
  local d="$1" ev
  for ev in push workflow_dispatch schedule ""; do
    drive accept "$d" "EVENT_NAME=$ev"
    check_eq "O-EVENT event='$ev': oracle_only" "$O_OO" "false"
    check_eq "O-EVENT event='$ev': active" "$O_ACTIVE" "false"
    check_eq "O-EVENT event='$ev': skip_legs" "$O_SKIP" ""
  done
}
row_mg() {  # the merge_group arm: whole-batch diff over MERGE_GROUP_BASE_SHA..MERGE_GROUP_HEAD_SHA
  local d="$1" f
  for f in accept kbdoc tap_new_array tap_ins_member mustpass6; do
    drive "$f" "$d" "EVENT_NAME=merge_group"
    expect_lane "O-MG oracle-only batch '$f'"
  done
  for f in replay ex_ciyml tapx_always_on tapx_func_edit nd0 typ empty ab; do
    drive "$f" "$d" "EVENT_NAME=merge_group"
    expect_full "O-MG non-oracle batch '$f'"
  done
  # a batch mixing an oracle PR and a code PR is not oracle-only (fail-closed by construction)
  drive accept "$d" "EVENT_NAME=merge_group" "MERGE_GROUP_BASE_SHA=0000000000000000000000000000000000000000"
  expect_full "O-MG unresolvable base sha"
  drive accept "$d" "EVENT_NAME=merge_group" "MERGE_GROUP_HEAD_SHA=notasha"
  expect_full "O-MG malformed head sha"
  drive accept "$d" "EVENT_NAME=merge_group" "MERGE_GROUP_BASE_SHA="
  expect_full "O-MG empty base sha"
}
row_switch() {  # the switch is compared EXACTLY (the lock-neutralized copy is now byte-identical to the driver — the recipe is the pinned no-op)
  local d="$1" v
  drive accept "$d" "SWITCH=on"
  check_eq "O-SWITCH SWITCH=on, unlocked, oracle diff: active" "$O_ACTIVE" "true"
  check_eq "O-SWITCH SWITCH=on, unlocked, oracle diff: skip_legs" "$O_SKIP" "$ORACLE_FIVE"
  check_eq "O-SWITCH SWITCH=on, unlocked: notice locked=false" "$N_LOCKED" "false"
  # the diagrams carve-out reaches skip_legs too (unlocked): four-name subset
  drive diag "$d" "SWITCH=on"
  check_eq "O-DIAGRAMS unlocked: active" "$O_ACTIVE" "true"
  check_eq "O-DIAGRAMS unlocked: skip_legs is the four-name subset" "$O_SKIP" "$ORACLE_FOUR"
  for v in "ON" "On" " on" "on " $'on\n' $'\non' "1" "true" "yes" "onn" "o" "off" "\"on\""; do
    drive accept "$d" "SWITCH=$v"
    check_eq "O-SWITCH SWITCH='${v//$'\n'/\\n}': oracle_only" "$O_OO" "false"
    check_eq "O-SWITCH SWITCH='${v//$'\n'/\\n}': active" "$O_ACTIVE" "false"
    check_eq "O-SWITCH SWITCH='${v//$'\n'/\\n}': skip_legs" "$O_SKIP" ""
    check_eq "O-SWITCH SWITCH='${v//$'\n'/\\n}': would_skip" "$N_WOULD" "none"
  done
  drive accept "$d" "UNSET:SWITCH"
  check_eq "O-SWITCH unset: oracle_only" "$O_OO" "false"
  check_eq "O-SWITCH unset: would_skip" "$N_WOULD" "none"
  drive ex_code "$d" "SWITCH=on"
  check_eq "O-SWITCH SWITCH=on on a code diff: oracle_only stays false" "$O_OO" "false"
}
row_lock() {  # post-activation: SWITCH=on classifies, annotates AND arms; the env-read
  # ORACLE_LANE_LOCKED remains as the dark-mode revert path (a mapped env can re-lock the lane —
  # no step env wires it today, so wiring is itself an excluded-path edit; O-LOCK-READ is still
  # live machinery, so it is covered here).
  local d="$1"
  drive accept "$d" "SWITCH=on"
  check_eq "O-ARM unlocked + SWITCH=on: active" "$O_ACTIVE" "true"
  check_eq "O-ARM unlocked + SWITCH=on: skip_legs" "$O_SKIP" "$ORACLE_FIVE"
  check_eq "O-ARM unlocked + SWITCH=on: notice locked" "$N_LOCKED" "false"
  check_eq "O-ARM the would-skip telemetry still names the five legs" "$N_WOULD" "$ORACLE_FIVE"
  drive accept "$d" "SWITCH=on" "ORACLE_LANE_LOCKED=1"
  check_eq "O-LOCK env re-lock + SWITCH=on: active" "$O_ACTIVE" "false"
  check_eq "O-LOCK env re-lock + SWITCH=on: skip_legs" "$O_SKIP" ""
  check_eq "O-LOCK env re-lock + SWITCH=on: notice locked" "$N_LOCKED" "true"
  check_eq "O-LOCK env re-lock keeps would_skip telemetry" "$N_WOULD" "$ORACLE_FIVE"
  drive accept "$d" "UNSET:SWITCH"
  check_eq "O-ARM dark (switch unset): oracle_only" "$O_OO" "false"
  check_eq "O-ARM dark (switch unset): would_skip" "$N_WOULD" "none"
}
row_defaults_first() {  # a step killed anywhere leaves exactly the defaults (adversarial: unlocked + on)
  local d="$1"
  EXPECT_KILLED=1
  drive accept "$d" "SWITCH=on" "PATH=$BIN_GITKILL"
  EXPECT_KILLED=0
}
row_leak() {  # the raw switch value, the repo name and the shas reach no output but gh.out's audit shas
  local d="$1"
  drive accept "$d" "SWITCH=zzleak-raw-switch-value"
  check_eq "O-LEAK a raw switch value never arms" "$O_ACTIVE" "false"
  check_eq "O-LEAK a raw switch value: oracle_only" "$O_OO" "false"
}
row_property() {  # Guard 1 property sweep: ANY generated combination of in-surface members must
  local d="$1" i j combo cname                       # classify; ONE contaminant anywhere flips it.
  # members: accept.tsv, baseline.tsv, an in-extent hunk, a KB doc, a root doc.
  i=0
  for a in 0 1; do for b in 0 1; do for c in 0 1; do for e in 0 1; do for g in 0 1; do
    [ "$((a + b + c + e + g))" -ge 1 ] || continue
    i=$((i + 1)); cname="sw$i"
    fx_case "$cname"
    [ "$a" = 1 ] && fx_op "$cname" M "$ACCEPT"
    [ "$b" = 1 ] && fx_op "$cname" M "$BASELINE"
    [ "$c" = 1 ] && fx_tap "$cname" ins_member
    [ "$e" = 1 ] && fx_op "$cname" M "$KB_A"
    [ "$g" = 1 ] && fx_op "$cname" M AGENTS.md
    fx_done "$cname"
    drive "$cname" "$d"
    if [ "$b" = 1 ]; then
      # baseline.tsv is a non-member (PR5z): any subset containing it pays the full battery
      expect_full "O-PROP baseline-containing subset {accept=$a,baseline=$b,edge=$c,doc=$e,root=$g}"
      check_eq "O-PROP baseline subset: reason" "$N_REASON" "outside_surface"
    else
      expect_lane "O-PROP in-surface subset {accept=$a,baseline=$b,edge=$c,doc=$e,root=$g}"
    fi
  done; done; done; done; done
  # every in-surface member plus ONE contaminant (the second member defeats it) — Guard 1 row 2
  # generalized: for each contaminant, a diff of [accept.tsv, in-extent hunk, KB doc] + contaminant.
  local -a CONTAM=(
    "scripts/ci-pr-affected-replay.py"
    "scripts/test-all.sh"
    "plugins/soleur/scripts/lint-ratchet.py"
    ".github/workflows/ci.yml"
    "scripts/lib/zzleak-other-lib.sh"
    "scripts/foo.sh"
    "apps/web-platform/zzleak-app.ts"
    "docs/legal/zzleak-terms.md"
    "plugins/soleur/docs/zzleak-page.md"
    "knowledge-base/zzleak-x.sh"
    "knowledge-base/zzleak-x.png"
    "zzleak-root.mdx"
    "Makefile"
  )
  j=0
  for i in "${!CONTAM[@]}"; do
    j=$((j + 1)); cname="swc$j"
    fx_case "$cname"
    fx_op "$cname" M "$ACCEPT"; fx_tap "$cname" ins_member; fx_op "$cname" M "$KB_A"
    fx_op "$cname" M "${CONTAM[$i]}"
    fx_done "$cname"
    drive "$cname" "$d"
    expect_full "O-PROP contaminant '${CONTAM[$i]}'"
    drive "$cname" "$d" "EVENT_NAME=merge_group"
    expect_full "O-PROP contaminant '${CONTAM[$i]}' on merge_group"
  done
}

# ── CONTROL: the unmutated driver must be GREEN before any mutant is read ────
_c0=$fails
row_oracle_surface "$PRISTINE"
row_shape_ok "$PRISTINE"
row_shape "$PRISTINE"
row_stale_base "$PRISTINE"
row_exclusions "$PRISTINE"
row_extent_out "$PRISTINE"
row_elem_grammar "$PRISTINE"
row_allowlist "$PRISTINE"
row_fork "$PRISTINE"
row_attempt "$PRISTINE"
row_maxfiles "$PRISTINE"
row_status_modes "$PRISTINE"
row_odd "$PRISTINE"
row_empty "$PRISTINE"
row_diff_error "$PRISTINE"
row_event_out "$PRISTINE"
row_mg "$PRISTINE"
row_lock "$PRISTINE"
row_leak "$PRISTINE"
row_defaults_first "$PRISTINE"
row_property "$PRISTINE"
row_switch "$UNLOCKED"
if [ "$fails" -ne "$_c0" ]; then
  printf '\nCONTROL ROWS FAILED: the battery is VOID, not failing. The unmutated driver does not\n' >&2
  printf 'satisfy its own contract, so every mutation verdict below would be measured against a\n' >&2
  printf 'broken baseline.\n' >&2
  printf 'rows=%d passed=%d failed=%d\n' "$((passes + fails))" "$passes" "$fails" >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
echo "  control: $((passes)) checks green against the pristine and the lock-neutralized driver"

# ── Static guards: the lock literal, the lock copy, and the driver's tool surface ──
_lockn=$(grep -c -E "$LOCK_RE" "$PRISTINE")
check_eq "O-LOCK the activation lock is ABSENT (removed by the activation PR; a re-lock is a driver edit, not an accident)" "$_lockn" "0"
check_eq "O-LOCK the lock-neutralization recipe is now a no-op on the unlocked driver" \
  "$(cmp -s "$PRISTINE" "$UNLOCKED"; echo $?)" "0"
check_eq "O-LOCK the neutralized copy has no lock line" "$(grep -c -E '^readonly ORACLE_LANE_LOCKED=' "$UNLOCKED")" "0"
check_true "O-LOCK the driver still READS an env lock for the arm (dark-mode revert path)" "$(grep -q 'ORACLE_LANE_LOCKED:-' "$PRISTINE"; echo $?)"
check_eq "PRISTINE copy is byte-identical to the live driver" "$(cmp -s "$PRISTINE" "$DRIVER"; echo $?)" "0"
# The driver's comment claims the doc allowlist grammar is IDENTICAL to ci-pr-selection.sh is_doc_path — enforce it
# byte-for-byte (a divergence between the two classifiers is exactly the drift the comment warns about).
_lp=$(sed -n '/^is_doc_path() {$/,/^}$/p' "$REPO_ROOT/scripts/ci-pr-selection.sh")
_ld=$(sed -n '/^is_doc_path() {$/,/^}$/p' "$DRIVER")
check_eq "O-DOCPARITY is_doc_path is byte-identical to ci-pr-selection.sh" "$_ld" "$_lp"
unset _lp _ld
# the surface and exclusion lists are committed literals in the driver (the plan's anchor): a
# one-commit weakening must edit the driver AND defeat this sentinel.
for _lit in "$ACCEPT" "$TAP" "scripts/ci-pr-affected-replay.py" "scripts/test-all.sh" \
            "plugins/soleur/scripts/lint-ratchet.py" ".github/workflows/ci.yml"; do
  check_true "O-LITERAL the driver names '$_lit'" "$(grep -qF -- "$_lit" "$PRISTINE"; echo $?)"
done
unset _lit
# inverted pin: baseline.tsv is deliberately NOT a surface member (PR5z strict-zero — the only possible diff on
# that path is the baseline-reintroduced alarm shape). The full path must NOT appear anywhere in the driver.
check_eq "O-LITERAL baseline.tsv is NOT named anywhere in the driver (PR5z strict zero)" \
  "$(grep -cF -- "$BASELINE" "$PRISTINE")" "0"
check_true "O-LITERAL the driver names the AFFECTED_*_PATHS extent pattern" \
  "$(grep -qE 'AFFECTED_.*_PATHS' "$PRISTINE"; echo $?)"

# ═══ GUARD 4 — oracle-index-check manifest parity ═══════════════════════════
# scripts/ci-oracle-lane-suites.txt is label + argv per line; `#` lines are comments carrying the
# committed exclusion list. The registration authority is `test-all.sh --enumerate` (the real run,
# once, cached) — a manifest member that is not a live registration, or a live oracle-machinery
# registration in neither the members nor the exclusion comments, is a Guard-4 red.
echo "=== Guard 4: oracle-index-check manifest parity ==="
REGS="$SANDBOX/registrations.txt"
if timeout 300 bash "$TEST_ALL" --enumerate > "$REGS" 2>"$SANDBOX/enum.err"; then
  pass
else
  fail "G4 the registration authority failed: 'bash scripts/test-all.sh --enumerate' exited $? ($(head -c 120 "$SANDBOX/enum.err"))"
  : > "$REGS"
fi
# The argv parity authority: `run_suite "<label>" <argv>` lines from the same file — a manifest member's argv
# must equal its registered argv verbatim (row-window drift like 387-596 vs 387-599 escapes a path-existence check).
REGS_ARGV="$SANDBOX/registrations-argv.txt"
grep -hE 'run_suite "' "$TEST_ALL" | sed -n 's/.*run_suite "\([^"]*\)"[[:space:]]\{1,\}\(.*\)/\1\t\2/p' > "$REGS_ARGV"
check_true "G4 the enumerate run produced registrations (vacuity floor)" "$(rc_of test "$(grep -c 'SUITE_REGISTRATION' "$REGS")" -ge 100)"

# The declared oracle-SUT set (plan §oracle-index-check membership, 14 names) and the committed
# exclusion list (9 names). Members are pinned one direction (each is a live registration); the
# exclusion names are pinned inside the manifest's COMMENT lines.
DECLARED_MEMBERS=(
  "scripts/lint-orphan-test-suites"
  "scripts/test-all-affected-a" "scripts/test-all-affected-b" "scripts/test-all-affected-c" "scripts/test-all-affected-d"
  "scripts/test-all-group-affected"
  "scripts/test-affected-derive" "scripts/test-affected-derive-cache" "scripts/test-affected-kb-consumers"
  "plugins/soleur/test/ci-pr-affected-replay-a" "plugins/soleur/test/ci-pr-affected-replay-b" "plugins/soleur/test/ci-pr-affected-replay-c"
  "scripts/ci-pr-selection"
  "plugins/soleur/test/ci-pr-affected-preactivation.test.sh"
  "scripts/ci-oracle-review"
)
DECLARED_EXCLUSIONS=(
  "scripts/lint-orphan-test-suites-mutations-a" "scripts/lint-orphan-test-suites-mutations-b"
  "scripts/test-all-orphan-log-retention"
  "plugins/soleur/scripts/affected-tests.test.sh" "plugins/soleur/test/affected-tests-pool-default.test.sh"
  "scripts/audit-suite-reads" "tests/scripts/lint-ratchet" "scripts/pre-push-ratchet-lane"
  "plugins/soleur/test/ci-path-gating.test.sh"
  # the lane driver suite is unreachable by a lane-eligible diff (driver files are in the hard-exclusion
  # list) — it belongs in the manifest's commented exclusion list, never in the members.
  "scripts/ci-oracle-lane"
)
# The name class a NEW oracle-machinery registration lands in: the parity check reads live
# registrations whose label matches it and requires manifest-or-exclusion coverage.
ORACLE_FAMILY_RE='affected|lint-orphan-test-suites|ci-pr|ci-path-gating|ci-oracle'

check_manifest() {  # $1=manifest path; prints tag lines (empty = clean)
  local mf="$1" line label nmembers=0
  local seen=" " argv atok apath tabs nf
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    label="${line%%[[:space:]]*}"
    nmembers=$((nmembers + 1))
    # a label listed twice would silently run the same suite twice in the leg
    case "$seen" in *" $label "*) printf 'MEMBER-DUPLICATE:%s\n' "$label" ;; esac
    seen="$seen$label "
    case "$line" in *[[:space:]]*) : ;; *) printf 'MEMBER-NO-ARGV:%s\n' "$label" ;; esac
    # the grammar is exactly label<TAB>argv: a stray third field is silently truncated by the leg's
    # `IFS=$'\t' read -r label argv`, and a space-separated line leaves argv empty.
    tabs="${line//[^$'\t']/}"
    nf=$(( ${#tabs} + 1 ))
    [ "$nf" -eq 2 ] || printf 'MEMBER-BAD-FIELDS:%s:%d\n' "$label" "$nf"
    # the argv's first non-shell token must name a file that exists in the checkout (typo'd paths fail at leg
    # runtime; the pin catches them here)
    argv="${line#*$'\t'}"
    apath=""
    for atok in $argv; do
      case "$atok" in bash|sh) continue ;; esac
      apath="$atok"; break
    done
    if [ -n "$apath" ] && [ ! -f "$REPO_ROOT/$apath" ]; then printf 'MEMBER-BAD-ARGV:%s:%s\n' "$label" "$apath"; fi
    # argv parity: the manifest's argv must equal the registration's argv verbatim — a row-range drift
    # (387-596 written where the registration runs 387-599) silently runs a different window.
    if [ -s "$REGS_ARGV" ]; then
      local rargv
      rargv=$(awk -F'\t' -v l="$label" '$1==l{print $2; exit}' "$REGS_ARGV")
      if [ -n "$rargv" ] && [ "$argv" != "$rargv" ]; then printf 'MEMBER-ARGV-DRIFT:%s:%s!=%s\n' "$label" "$argv" "$rargv"; fi
    fi
    if ! awk -v l="$label" '$2==l{f=1} END{exit !f}' "$REGS"; then
      printf 'MEMBER-NOT-REGISTERED:%s\n' "$label"
    fi
  done < "$mf"
  if [ "$nmembers" -lt 13 ]; then printf 'MANIFEST-TOO-SMALL:%d\n' "$nmembers"; fi
  # bi-directional: every live registration in the oracle-SUT name class is a member or exclusion.
  local reg covered
  while IFS=$'\t' read -r _ reg; do
    [[ "$reg" =~ $ORACLE_FAMILY_RE ]] || continue
    covered=0
    if awk -v l="$reg" '!/^[[:space:]]*#/ && NF && $1==l{f=1} END{exit !f}' "$mf"; then covered=1; fi
    # comment coverage is word-boundary, not substring: `scripts/lint-orphan-test-suites` must NOT be covered by the
    # `scripts/lint-orphan-test-suites-mutations-a` exclusion comment.
    if [ "$covered" = 0 ] && grep -qE -- "${reg//./\\.}([^[:alnum:]_-]|\$)" < <(grep -E '^[[:space:]]*#' "$mf"); then covered=1; fi
    [ "$covered" = 1 ] || printf 'UNCOVERED-REGISTRATION:%s\n' "$reg"
  done < "$REGS"
  # the declared member set: each name is a member or an exclusion comment (14 plan names).
  local dm
  for dm in "${DECLARED_MEMBERS[@]}"; do
    covered=0
    if awk -v l="$dm" '!/^[[:space:]]*#/ && NF && $1==l{f=1} END{exit !f}' "$mf"; then covered=1; fi
    if [ "$covered" = 0 ] && grep -qE -- "${dm//./\\.}([^[:alnum:]_-]|\$)" < <(grep -E '^[[:space:]]*#' "$mf"); then covered=1; fi
    [ "$covered" = 1 ] || printf 'DECLARED-MISSING:%s\n' "$dm"
  done
  # the committed exclusion list, each named in a comment line.
  local de
  for de in "${DECLARED_EXCLUSIONS[@]}"; do
    grep -qF -- "$de" < <(grep -E '^[[:space:]]*#' "$mf") || printf 'EXCLUSION-NOT-COMMENTED:%s\n' "$de"
  done
}

# Guard 4 legs: the manifest's members are dispatched across the oracle-index-check
# matrix legs by scripts/ci-oracle-lane-legs.tsv (label<TAB>leg — the ADR-240 checked-in
# assignment shape). check_legs pins the assignment bi-directionally: legs labels ≡
# manifest members, every live matrix leg owns >=1 member, leg values ⊆ the live
# `strategy.matrix.leg` set, and no member is assigned twice.
LEGS_FILE="$REPO_ROOT/scripts/ci-oracle-lane-legs.tsv"
check_legs() {  # $1=legs path $2=manifest path $3=space-separated live matrix leg set; prints tag lines (empty = clean)
  local lf="$1" mf="$2" mset=" $3 " line label leg seen=" " k
  if [ ! -f "$lf" ]; then printf 'LEGS-FILE-MISSING\n'; return; fi
  if [ ! -f "$mf" ]; then printf 'LEGS-MANIFEST-MISSING:%s\n' "$mf"; return; fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    label="${line%%[[:space:]]*}"
    leg="$(printf '%s\n' "$line" | awk -F'\t' '{print $2}')"
    # exactly label<TAB>leg like the manifest's MEMBER-BAD-FIELDS doctrine — a stray
    # third column is silently truncated by both this suite and the runtime awk.
    local lnf
    lnf="$(printf '%s\n' "$line" | awk -F'\t' '{print NF}')"
    [ "$lnf" = "2" ] || printf 'LEG-BAD-FIELDS:%s:%s\n' "$label" "$lnf"
    case "$seen" in *" $label "*) printf 'LEG-DUPLICATE:%s\n' "$label" ;; esac
    seen="$seen$label "
    case "$leg" in
      ''|*/*/*|*[!0-9/]*) printf 'LEG-BAD-VALUE:%s:%s\n' "$label" "$leg" ;;
      *) case "$mset" in *" $leg "*) : ;; *) printf 'LEG-OUT-OF-MATRIX:%s:%s\n' "$label" "$leg" ;; esac ;;
    esac
    # a legs row naming a label that is not a manifest member is a stale assignment
    awk -v l="$label" '!/^[[:space:]]*#/ && NF && $1==l{f=1} END{exit !f}' "$mf" \
      || printf 'LEG-STALE-ROW:%s\n' "$label"
  done < "$lf"
  # reverse direction: every manifest member is assigned to exactly one leg (the
  # run-block's fail-closed unassigned-member arm is the runtime backstop for this)
  while IFS=$'\t' read -r label _argv || [ -n "$label" ]; do
    case "$label" in ''|'#'*) continue ;; esac
    awk -v l="$label" '!/^[[:space:]]*#/ && NF && $1==l{f=1} END{exit !f}' "$lf" \
      || printf 'LEG-UNASSIGNED:%s\n' "$label"
  done < "$mf"
  # every matrix leg owns at least one member — a vacant leg would be a vacuous gate
  for k in $3; do
    awk -F'\t' -v leg="$k" '!/^[[:space:]]*#/ && NF && $2==leg{f=1} END{exit !f}' "$lf" \
      || printf 'LEG-VACANT:%s\n' "$k"
  done
  # the rebalance trigger, mechanised (arch P3-3): join each row to committed
  # scripts/suite-durations.tsv and red when a leg's projected serial total comes within
  # ~5 min of the 30-min bound (1500000 ms) — a duration drift otherwise surfaces only as
  # a timeout kill. A member with no measured row is LEG-UNMEASURED (never 0-min).
  local durs="$REPO_ROOT/scripts/suite-durations.tsv"
  if [ -f "$durs" ]; then
    awk -F'\t' -v durfile="$durs" '
      NR==FNR { if ($1 !~ /^[[:space:]]*#/ && NF >= 2) dur[$1]=$2; next }
      /^[[:space:]]*#/ || !NF { next }
      {
        if (!($1 in dur)) { printf "LEG-UNMEASURED:%s\n", $1; next }
        sum[$2] += dur[$1]
      }
      END { for (l in sum) if (sum[l] > 1500000) printf "LEG-OVER-BUDGET:%s:%d\n", l, sum[l] }
    ' "$durs" "$lf"
  else
    printf 'LEG-DURATIONS-MISSING\n'
  fi
}

OIC_LEGS="$(python3 - "$CI_YML" <<'PYX' || true
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
job = (doc.get("jobs") or {}).get("oracle-index-check") or {}
legs = (((job.get("strategy") or {}).get("matrix") or {}).get("leg")) or []
print(" ".join(str(x) for x in legs))
PYX
)"

if [ -f "$MANIFEST" ]; then
  _mtags=$(check_manifest "$MANIFEST")
  check_eq "G4 the live manifest is clean (members registered, parity, exclusions commented)" "$_mtags" ""
  # Guard 4 mutants over COPIES of the manifest: each must produce a tag.
  _mm="$SANDBOX/manifest-mut"
  mkdir -p "$_mm"
  awk '!/^[[:space:]]*#/ && NF && $1=="scripts/lint-orphan-test-suites"{next} {print}' "$MANIFEST" > "$_mm/no-orphan.txt"
  _mt=$(check_manifest "$_mm/no-orphan.txt")
  check_contains "G4 row3 dropping lint-orphan-test-suites is caught" "$_mt" "DECLARED-MISSING:scripts/lint-orphan-test-suites"
  { cat "$MANIFEST"; printf 'zz/not-a-real-suite bash zz/none.test.sh\n'; } > "$_mm/bogus.txt"
  _mt=$(check_manifest "$_mm/bogus.txt")
  check_contains "G4 row1 a non-registration member is caught" "$_mt" "MEMBER-NOT-REGISTERED:zz/not-a-real-suite"
  : > "$_mm/empty.txt"
  _mt=$(check_manifest "$_mm/empty.txt")
  check_contains "G4 row2 an empty manifest is caught" "$_mt" "MANIFEST-TOO-SMALL"
  # row5 must-PASS non-canonical: the member list in a different order still checks clean.
  awk '/^[[:space:]]*#/{print > "'$_mm'/comments"} !/^[[:space:]]*#/ && NF{print > "'$_mm'/members"}' "$MANIFEST"
  { cat "$_mm/comments"; tac "$_mm/members"; } > "$_mm/reordered.txt" 2>/dev/null || cp "$MANIFEST" "$_mm/reordered.txt"
  _mt=$(check_manifest "$_mm/reordered.txt")
  check_eq "G4 row5 a reordered member list stays clean" "$_mt" ""
  # a member line whose argv is absent must be caught (label + argv shape)
  { cat "$MANIFEST"; printf 'scripts/ci-pr-selection\n'; } > "$_mm/noargv.txt"
  _mt=$(check_manifest "$_mm/noargv.txt")
  check_contains "G4 a member without argv is caught" "$_mt" "MEMBER-NO-ARGV:scripts/ci-pr-selection"
  # dropping a declared exclusion comment is caught
  grep -vF 'lint-orphan-test-suites-mutations-a' "$MANIFEST" > "$_mm/no-excl.txt"
  _mt=$(check_manifest "$_mm/no-excl.txt")
  check_contains "G4 dropping a committed exclusion is caught" "$_mt" "EXCLUSION-NOT-COMMENTED:scripts/lint-orphan-test-suites-mutations-a"
  # a member label listed twice would silently run the same suite twice in the leg
  { cat "$MANIFEST"; printf 'scripts/ci-pr-selection\tbash scripts/ci-pr-selection.test.sh\n'; } > "$_mm/dup.txt"
  _mt=$(check_manifest "$_mm/dup.txt")
  check_contains "G4 a duplicate member label is caught" "$_mt" "MEMBER-DUPLICATE:scripts/ci-pr-selection"
  # a stray third TSV column is silently truncated by the leg's `IFS=$'\t' read -r label argv`
  awk 'BEGIN{FS=OFS="\t"} !/^[[:space:]]*#/ && NF==2 && !d {print $0"\tzz-extra"; d=1; next} {print}' "$MANIFEST" > "$_mm/threecol.txt"
  _mt=$(check_manifest "$_mm/threecol.txt")
  check_contains "G4 a stray third field is caught" "$_mt" "MEMBER-BAD-FIELDS"
  # an argv whose first non-shell token names a nonexistent file would fail only at leg runtime
  { cat "$MANIFEST"; printf 'scripts/ci-pr-selection\tbash zz/no-such-file.test.sh\n'; } > "$_mm/badargv.txt"
  _mt=$(check_manifest "$_mm/badargv.txt")
  check_contains "G4 an argv whose script does not exist is caught" "$_mt" "MEMBER-BAD-ARGV:scripts/ci-pr-selection:zz/no-such-file.test.sh"
  # an argv that names a real file but drifts from the registration's argv (a different row window)
  sed 's|--rows 1-167|--rows 1-160|' "$MANIFEST" > "$_mm/argvdrift.txt"
  _mt=$(check_manifest "$_mm/argvdrift.txt")
  check_contains "G4 an argv drifted from the registration is caught" "$_mt" "MEMBER-ARGV-DRIFT:plugins/soleur/test/ci-pr-affected-replay-a"
else
  fail "G4 $MANIFEST does not exist (the oracle-validation manifest is an implementation deliverable)"
fi

if [ -f "$LEGS_FILE" ]; then
  check_true "G4 legs ci.yml names a matrix leg set" "$(rc_of test -n "$OIC_LEGS")"
  _ltags=$(check_legs "$LEGS_FILE" "$MANIFEST" "$OIC_LEGS")
  check_eq "G4 legs the live assignment is clean (parity, matrix coverage)" "$_ltags" ""
  _lm="$SANDBOX/legs-mut"
  mkdir -p "$_lm"
  grep -vF 'scripts/lint-orphan-test-suites' "$LEGS_FILE" > "$_lm/unassigned.tsv"
  _mt=$(check_legs "$_lm/unassigned.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row1 an unassigned member is caught" "$_mt" "LEG-UNASSIGNED:scripts/lint-orphan-test-suites"
  { cat "$LEGS_FILE"; printf 'zz/not-a-member\t1/5\n'; } > "$_lm/stale.tsv"
  _mt=$(check_legs "$_lm/stale.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row2 a stale row naming a non-member is caught" "$_mt" "LEG-STALE-ROW:zz/not-a-member"
  awk 'BEGIN{FS=OFS="\t"} !/^[[:space:]]*#/ && NF && !d {print $1,"9/5"; d=1; next} {print}' "$LEGS_FILE" > "$_lm/oom.tsv"
  _mt=$(check_legs "$_lm/oom.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row3 a leg value outside the matrix set is caught" "$_mt" "LEG-OUT-OF-MATRIX"
  awk 'BEGIN{FS=OFS="\t"} !/^[[:space:]]*#/ && NF && $2=="5/5" {print $1,"1/5"; next} {print}' "$LEGS_FILE" > "$_lm/vacant.tsv"
  _mt=$(check_legs "$_lm/vacant.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row4 a vacant matrix leg is caught" "$_mt" "LEG-VACANT:5/5"
  _mt=$(check_legs "$_lm/does-not-exist.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row5 a missing legs file is caught" "$_mt" "LEGS-FILE-MISSING"
  { cat "$LEGS_FILE"; printf 'scripts/ci-pr-selection\t2/5\n'; } > "$_lm/dup.tsv"
  _mt=$(check_legs "$_lm/dup.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row6 a double-assigned member is caught" "$_mt" "LEG-DUPLICATE:scripts/ci-pr-selection"
  { cat "$LEGS_FILE"; printf 'scripts/ci-pr-selection\tbogus\n'; } > "$_lm/badval.tsv"
  _mt=$(check_legs "$_lm/badval.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row6b a malformed leg value is caught" "$_mt" "LEG-BAD-VALUE:scripts/ci-pr-selection:bogus"
  { cat "$LEGS_FILE"; printf 'scripts/ci-pr-selection\t5/5\tjunk\n'; } > "$_lm/threecol.tsv"
  _mt=$(check_legs "$_lm/threecol.tsv" "$MANIFEST" "$OIC_LEGS")
  check_contains "G4 legs row6c a stray third field is caught" "$_mt" "LEG-BAD-FIELDS:scripts/ci-pr-selection:3"
  awk 'BEGIN{FS=OFS="\t"} !/^[[:space:]]*#/ && NF && $1=="scripts/lint-orphan-test-suites" {print $1,"5/5"; next} {print}' "$LEGS_FILE" > "$_lm/permuted.tsv"
  grep -qF $'scripts/lint-orphan-test-suites\t5/5' "$_lm/permuted.tsv" \
    || fail "G4 legs row7 mutant did not land (label match produced a pristine copy)"
  _mt=$(check_legs "$_lm/permuted.tsv" "$MANIFEST" "$OIC_LEGS")
  check_eq "G4 legs row7 a repacked-but-complete assignment stays clean" "$_mt" ""
  { grep -E '^[[:space:]]*#' "$LEGS_FILE"; grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$LEGS_FILE" | tac; } > "$_lm/reordered.tsv"
  _mt=$(check_legs "$_lm/reordered.tsv" "$MANIFEST" "$OIC_LEGS")
  check_eq "G4 legs row8 reordered assignment rows stay clean" "$_mt" ""
else
  fail "G4 legs $LEGS_FILE does not exist (the leg assignment is an implementation deliverable)"
fi

# Guard 4 row 4: the oracle-index-check leg runs the manifest members its legs-file row
# assigns to ORACLE_LEG, and a member's non-zero exit
# propagates into the leg verdict. The step body is extracted from ci.yml by manifest-name mention
# and executed over a stub manifest in a sandbox repo (never the real suites — the stub argv is
# `true`/`false`, so the row is milliseconds, not the 10–20-minute leg itself).
if [ -f "$CI_YML" ]; then
  OIC_BODY="$SANDBOX/oic-body.sh"
  python3 - "$CI_YML" "$OIC_BODY" > "$SANDBOX/oic-which.txt" 2>"$SANDBOX/oic.err" <<'PYX' || true
import sys, yaml
try:
    doc = yaml.safe_load(open(sys.argv[1]))
except Exception as e:
    sys.stderr.write("ci.yml parse failed: %r\n" % (e,)); sys.exit(3)
job = (doc.get("jobs") or {}).get("oracle-index-check")
if job is None:
    sys.stderr.write("no oracle-index-check job\n"); sys.exit(3)
found = []
for st in job.get("steps") or []:
    if isinstance(st, dict) and "ci-oracle-lane-suites" in str(st.get("run", "")):
        found.append(st["run"])
if len(found) != 1:
    sys.stderr.write("expected exactly 1 manifest-running step, found %d\n" % len(found)); sys.exit(3)
open(sys.argv[2], "w").write(found[0])
print("ok")
PYX
  if [ -s "$OIC_BODY" ]; then
    _oic="$SANDBOX/oic-repo"
    assert_fixture_dir "$_oic"
    mkdir -p "$_oic/scripts"
    # the manifest grammar is label<TAB>argv — the step body reads IFS=$'\t', so a space-separated stub reads as a
    # member with no argv and exits 1 by design (the no-argv fail-closed arm).
    { printf 'scripts/fake-pass\ttrue\n'; printf 'scripts/fake-also-pass\ttrue\n'; printf 'scripts/fake-fail\tfalse\n'; printf 'scripts/fake-after\ttrue\n'; } > "$_oic/scripts/ci-oracle-lane-suites.txt"
    { printf 'scripts/fake-pass\t1/2\n'; printf 'scripts/fake-also-pass\t1/2\n'; printf 'scripts/fake-fail\t2/2\n'; printf 'scripts/fake-after\t2/2\n'; } > "$_oic/scripts/ci-oracle-lane-legs.tsv"
    ( cd "$_oic" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG=1/2 GITHUB_OUTPUT="$_oic/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic/pass.out" 2>&1
    _rc_pass=$?
    check_eq "G4 row4 an all-pass stub manifest leaves the leg green" "$_rc_pass" "0"
    check_eq "G4 legs only the leg-1 members ran on leg 1/2" "$(grep -c '── oracle-index-check:' "$_oic/pass.out")" "2"
    ( cd "$_oic" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG=2/2 GITHUB_OUTPUT="$_oic/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic/fail.out" 2>&1
    _rc_fail=$?
    check_true "G4 row4 a member's non-zero exit propagates into the leg verdict" "$(rc_of test "$_rc_fail" -ne 0)"
    ( cd "$_oic" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=false GITHUB_OUTPUT="$_oic/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic/off.out" 2>&1
    _rc_off=$?
    check_eq "G4 an off-lane run is a sub-minute no-op (exit 0) — the not-oracle-only exit precedes every leg check" "$_rc_off" "0"
    check_contains "G4 an off-lane run says not-oracle-only" "$(cat "$_oic/off.out")" "not-oracle-only"
    ( cd "$_oic" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true GITHUB_OUTPUT="$_oic/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic/noleg.out" 2>&1
    _rc_noleg=$?
    check_true "G4 legs unset ORACLE_LEG fails closed" "$(rc_of test "$_rc_noleg" -ne 0)"
    check_contains "G4 legs unset ORACLE_LEG names the malformed-ORACLE_LEG arm" "$(cat "$_oic/noleg.out")" "unset or malformed"
    for _badleg in "" "15" "1/5/2" "0/5" "5/0" "/5" "5/" "1/5 " "x/y"; do
      ( cd "$_oic" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG="$_badleg" GITHUB_OUTPUT="$_oic/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic/badleg.out" 2>&1
      _rc_badleg=$?
      check_true "G4 legs malformed ORACLE_LEG='${_badleg}' fails closed" "$(rc_of test "$_rc_badleg" -ne 0)"
      check_contains "G4 legs malformed ORACLE_LEG='${_badleg}' names the arm" "$(cat "$_oic/badleg.out")" "unset or malformed"
    done
    # a well-formed leg outside the live matrix set needs no dedicated arm — every member's
    # assignment fails the n==K check (or matches nothing), so the vacuous-leg arm reds it.
    for _forleg in 9/9 5/9; do
      ( cd "$_oic" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG="$_forleg" GITHUB_OUTPUT="$_oic/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic/forleg.out" 2>&1
      _rc_forleg=$?
      check_true "G4 legs a well-formed foreign leg ($_forleg) fails closed" "$(rc_of test "$_rc_forleg" -ne 0)"
      check_contains "G4 legs foreign leg $_forleg names the n==K arm" "$(cat "$_oic/forleg.out")" "malformed leg value"
    done
    # k==n green arm: a leg equal to K still runs its own members to green.
    _oic3="$_oic-kn"
    assert_fixture_dir "$_oic3"
    mkdir -p "$_oic3/scripts"
    { printf 'scripts/fake-pass\ttrue\n'; printf 'scripts/fake-also-pass\ttrue\n'; } > "$_oic3/scripts/ci-oracle-lane-suites.txt"
    { printf 'scripts/fake-pass\t2/2\n'; printf 'scripts/fake-also-pass\t2/2\n'; } > "$_oic3/scripts/ci-oracle-lane-legs.tsv"
    ( cd "$_oic3" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG=2/2 GITHUB_OUTPUT="$_oic3/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic3/kn.out" 2>&1
    _rc_kn=$?
    check_eq "G4 legs a k==n leg runs its members to green" "$_rc_kn" "0"
    check_eq "G4 legs the k==n leg ran both members" "$(grep -c '── oracle-index-check:' "$_oic3/kn.out")" "2"
    # a malformed legs-file row value is not a silent skip: it reds naming the row
    { printf 'scripts/fake-pass\t1/5 \n'; printf 'scripts/fake-also-pass\t1/2\n'; } > "$_oic3/scripts/ci-oracle-lane-legs.tsv"
    ( cd "$_oic3" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG=1/2 GITHUB_OUTPUT="$_oic3/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic3/mallegs.out" 2>&1
    _rc_mallegs=$?
    check_true "G4 legs a malformed legs-file value fails closed" "$(rc_of test "$_rc_mallegs" -ne 0)"
    check_contains "G4 legs a malformed legs-file value names the row" "$(cat "$_oic3/mallegs.out")" "malformed leg value"
    # the vacuous arm needs a leg that is VALID for its K but owns zero members — assign
    # the stub members to 1/3 and 2/3, then ask for 3/3.
    { printf 'scripts/fake-pass\t1/3\n'; printf 'scripts/fake-also-pass\t2/3\n'; } > "$_oic3/scripts/ci-oracle-lane-legs.tsv"
    ( cd "$_oic3" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG=3/3 GITHUB_OUTPUT="$_oic3/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic3/vacleg.out" 2>&1
    _rc_vacleg=$?
    check_true "G4 legs a leg owning zero members fails closed" "$(rc_of test "$_rc_vacleg" -ne 0)"
    check_contains "G4 legs the vacuous leg names the zero-member arm" "$(cat "$_oic3/vacleg.out")" "zero manifest members"
    _oic2="$_oic-nofile"
    assert_fixture_dir "$_oic2"
    mkdir -p "$_oic2/scripts"
    cp "$_oic/scripts/ci-oracle-lane-suites.txt" "$_oic2/scripts/"
    ( cd "$_oic2" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG=1/2 GITHUB_OUTPUT="$_oic2/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic2/nofile.out" 2>&1
    _rc_nofile=$?
    check_true "G4 legs a missing legs file fails closed" "$(rc_of test "$_rc_nofile" -ne 0)"
    check_contains "G4 legs the missing file names the legs-file arm" "$(cat "$_oic2/nofile.out")" "legs file"
    { printf 'scripts/fake-pass\ttrue\n'; printf 'scripts/fake-stray\ttrue\n'; } > "$_oic2/scripts/ci-oracle-lane-suites.txt"
    cp "$_oic/scripts/ci-oracle-lane-legs.tsv" "$_oic2/scripts/"
    ( cd "$_oic2" && env -i PATH=/usr/bin:/bin ORACLE_ONLY=true ORACLE_LEG=1/2 GITHUB_OUTPUT="$_oic2/gh.out" bash --noprofile --norc -eo pipefail "$OIC_BODY" ) > "$_oic2/stray.out" 2>&1
    _rc_stray=$?
    check_true "G4 legs an unassigned manifest member fails closed" "$(rc_of test "$_rc_stray" -ne 0)"
    check_contains "G4 legs the unassigned member names its arm" "$(cat "$_oic2/stray.out")" "no legs-file row"
    check_eq "G4 legs the failing-member leg ran only up to the failure" "$(grep -c '── oracle-index-check:' "$_oic/fail.out")" "1"
    check_contains "G4 legs leg 1/2 names the member it ran" "$(cat "$_oic/pass.out")" "scripts/fake-also-pass"
    check_eq "G4 legs leg 1/2 never saw the leg-2 failing member" "$(grep -c 'fake-fail' "$_oic/pass.out")" "0"
  else
    fail "G4 row4 the oracle-index-check manifest step could not be extracted from ci.yml ($(head -c 120 "$SANDBOX/oic.err"))"
  fi
  # Guard 4 row 4b: the leg's checkout carries full history AND runs on oracle-only runs. At the default depth 1
  # `origin/main` is not a ref, so the manifest's test-all-affected rows degrade to `undecidable-diff` and go red on the
  # first oracle-only run (PR #12245); a checkout whose `if:` is flipped never runs there at all. Pins the config, not the
  # behaviour: the behaviour is only observable on a real oracle-only run.
  _oic_depth="$(python3 - "$CI_YML" 2>/dev/null <<'PYX' || echo "parse-failed"
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
job = (doc.get("jobs") or {}).get("oracle-index-check") or {}
co = [s for s in (job.get("steps") or []) if isinstance(s, dict) and str(s.get("uses", "")).startswith("actions/checkout@")]
if len(co) == 1:
    print(len(co), (co[0].get("with") or {}).get("fetch-depth", "unset"), co[0].get("if", "unset"), "first" if (job.get("steps") or [None])[0] is co[0] else "late")
else:
    print(len(co), "n/a")
PYX
)"
  check_eq "G4 row4b the oracle-index-check leg has exactly one checkout: first step, fetch-depth 0, gated on oracle_only" "$_oic_depth" "1 0 needs.oracle-selection.outputs.oracle_only == 'true' first"
fi

# Self-registration: this sentinel is a registered suite with its own edge array (Phase 4 wiring).
check_true "SELF 'scripts/ci-oracle-lane' is a live registration" \
  "$(awk -v l=scripts/ci-oracle-lane '$2==l{f=1} END{exit !f}' "$REGS"; echo $?)"
check_true "SELF the driver declares AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS" \
  "$(grep -q 'AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS' "$REPO_ROOT/scripts/lib/test-affected-paths.sh"; echo $?)"

# ═══ MUTATION BATTERY (driver) ══════════════════════════════════════════════
# Each row mutates a COPY, asserts the mutation LANDED, drives the relevant rows in PROBE mode and
# requires at least one check to FAIL. The GUARD anchors are listed in the header contract.
MUT_TOTAL=0; MUT_KILLED=0; MUT_SURVIVED=()
MUT_N=0

mutate() {  # $1=label $2=base driver file $3=sed expression $4...=row functions to drive
  local label="$1" base="$2" expr="$3"; shift 3
  local m="$SANDBOX/mut.$((++MUT_N)).sh" fn
  MUT_TOTAL=$((MUT_TOTAL + 1))
  sed "$expr" "$base" > "$m"
  if cmp -s "$m" "$base"; then
    fail "MUTATION DID NOT LAND: $label (the sed expression matched nothing, so this row measured the BASELINE)"
    return
  fi
  if ! bash -n "$m" 2> /dev/null; then
    fail "MUTANT NOT WELL-FORMED: $label (a syntax error would kill every row for the wrong reason)"
    return
  fi
  [ -z "${OLP_PROBE_VERBOSE:-}" ] || printf 'probe-mutant %s: %s\n' "$MUT_N" "$label" >&3
  PROBE=1; PROBE_FAILS=0
  for fn in "$@"; do "$fn" "$m" > /dev/null 2>&1; done
  PROBE=0
  if [ "$PROBE_FAILS" -gt 0 ]; then
    pass; MUT_KILLED=$((MUT_KILLED + 1))
  else
    fail "MUTANT SURVIVED: $label (the guard rows did not detect this edit)"
    MUT_SURVIVED+=("$label")
  fi
}
kill_guard() { printf 's|^.*# GUARD:%s$|  : # MUTATED|' "$1"; }

# Guard 1 — the surface, the exclusion list, the extent check
# the surface guard spans four lines (if / diagrams-flag case / continue / fi) — a one-line kill would orphan the
# `then`; delete the whole block so every path falls through to outside_surface instead of classifying in-surface.
mutate "O-SURFACE the surface membership check is removed"      "$PRISTINE" '/if is_oracle_data_path "\$p" || is_doc_path "\$p"; then/,/fi  # GUARD:O-SURFACE/d'  row_oracle_surface row_allowlist
mutate "O-EXCLUSION the exclusion list is removed"              "$PRISTINE" "$(kill_guard O-EXCLUSION)"      row_exclusions
mutate "O-EXCLUSION replay.py dropped from the exclusion list"  "$PRISTINE" '/ci-pr-affected-replay\.py/d'     row_exclusions
mutate "O-EXCLUSION ci.yml dropped from the exclusion list"     "$PRISTINE" '/workflows\/ci\.yml/d'            row_exclusions
mutate "O-EXTENT the in-extent hunk check is removed (whole-file path test — the plan's named sharp edge)" "$PRISTINE" "$(kill_guard O-EXTENT)" row_extent_out
mutate "O-BINARY a binary index diff passes vacuously"              "$PRISTINE" "$(kill_guard O-BINARY-INDEX)" row_elem_grammar
mutate "O-ELEM-GRAMMAR non-grammar lines inside extents are accepted" "$PRISTINE" "$(kill_guard O-ELEM-GRAMMAR)" row_elem_grammar
mutate "O-EXTENT-BASE the base-image half is dropped (a deleted array is not checked)" "$PRISTINE" "$(kill_guard O-EXTENT-BASE)" row_oracle_surface
mutate "O-EXTENT-HEAD the head-image half is dropped (a new array is not checked)"     "$PRISTINE" "$(kill_guard O-EXTENT-HEAD)" row_oracle_surface
# the doc-widening sed must hit the is_doc_path CASE PATTERN `knowledge-base/?*.md` (the comment's `**` spelling is not
# the pattern site — a comment-only hit lands trivially and survives). BRE: literal `?`, escaped `*` and `.`.
mutate "O-SURFACE the doc allowlist widened to any .md"         "$PRISTINE" 's|knowledge-base/?\*\.md|*.md|' row_allowlist
# a REAL wholesale admission, well-formed: (a) the exclusion entry stops matching lib paths, (b) is_oracle_data_path
# gains scripts/lib/* — a one-arm no-op sed would leave the exclusion first in line and change nothing.
mutate "O-SURFACE scripts/lib/** admitted wholesale"            "$PRISTINE" 's|    scripts/lib/\*) return 0 ;;|    scripts/lib/ZZ-NOMATCH-XX) return 0 ;;|; s|    scripts/ci-pr-affected-audit.baseline.tsv) return 0 ;;|&\n    scripts/lib/*) return 0 ;;|' row_exclusions row_extent_out
# the preconditions
mutate "O-EVENT any event classifies"                           "$PRISTINE" "$(kill_guard O-EVENT)"          row_event_out
mutate "O-TWO-PARENTS the two-parent check is removed"          "$PRISTINE" "$(kill_guard O-TWO-PARENTS)"    row_shape
mutate "O-PRHEAD the HEAD^2==PR_HEAD_SHA check is removed"      "$PRISTINE" "$(kill_guard O-PRHEAD)"         row_shape
mutate "O-FORK the same-repo check is removed"                  "$PRISTINE" "$(kill_guard O-FORK)"           row_fork
mutate "O-ATTEMPT the attempt-1 check is removed"               "$PRISTINE" "$(kill_guard O-ATTEMPT)"        row_attempt
mutate "O-MAX-FILES the 500-file cap is removed"                "$PRISTINE" "$(kill_guard O-MAX-FILES)"      row_maxfiles
mutate "O-MAX-FILES the cap is 501"                             "$PRISTINE" 's|-le 500|-le 501|g'            row_maxfiles
mutate "O-STATUS any status letter is accepted"                 "$PRISTINE" "$(kill_guard O-STATUS)"         row_status_modes
mutate "O-MODES any mode is accepted"                           "$PRISTINE" "$(kill_guard O-MODES)"          row_status_modes
mutate "O-PATH-CHARS control/odd characters accepted in a path" "$PRISTINE" "$(kill_guard O-PATH-CHARS)"     row_odd
mutate "O-EMPTY-DIFF a zero-path diff classifies (the vacuous arm)" "$PRISTINE" "$(kill_guard O-EMPTY-DIFF)" row_empty
mutate "O-DIFF a failed git diff is trusted anyway"             "$PRISTINE" 's/ || return 0/ # MUTATED/'    row_diff_error
# #12418: the discriminating mutations — reverting either side of the merge-base derivation re-opens the
# stale-base misfire the fix exists to close, and the stale fixture must see it.
mutate "O-BASE the diff base reverts to the frozen HEAD^1"      "$PRISTINE" 's|\$(git merge-base HEAD\^2 FETCH_HEAD 2>/dev/null)|HEAD^1|' row_stale_base
mutate "O-BASE the audit base_sha reverts to HEAD^1"            "$PRISTINE" 's|base_sha="\$diff_base"|base_sha="$p1"|' row_stale_base
# the arm, the lock, the defaults
mutate "O-SWITCH the exact-on compare becomes non-empty"        "$UNLOCKED"  's|= on \]|=~ ^on]|'            row_switch
mutate "O-SWITCH any non-empty switch arms"                     "$UNLOCKED"  's|\[ "\${SWITCH:-}" = on \]|[ -n "${SWITCH:-}" ]|' row_switch
# a dead arm is verdict-identical on the LOCKED copy (active stays false by construction), so this one mutates the
# lock-neutralized driver and is read by the unlocked rows that expect active=true.
mutate "O-LOCK the arm ignores the lock"                        "$UNLOCKED"  "$(kill_guard O-ARM)"           row_switch
mutate "O-LOCK the lock is not read"                            "$PRISTINE"  "$(kill_guard O-LOCK-READ)"     row_lock
mutate "O-DEFAULTS the defaults are not written first"          "$PRISTINE"  "$(kill_guard O-DEFAULTS)"      row_defaults_first
mutate "O-EXIT the always-exit-0 trap is removed"               "$PRISTINE"  "$(kill_guard ALWAYS-EXIT-0)"   row_diff_error
mutate "O-DIAGRAMS the diagrams carve-out flag is removed"      "$PRISTINE"  "$(kill_guard O-DIAGRAMS-FLAG)" row_oracle_surface
# dead block, not an orphan: `if ! true; then` + a comment swallowing the rest of the line leaves a well-formed
# never-executing reset, so the emitted skip_legs survives to the final write (line-count and grammar rows both see it).
_e1='s/^if \[ "$active" != true/if ! true; then : # MUTATED-IF /'
mutate "O-GRAMMAR skip_legs written when not active (arm gating AND final validation removed)" \
  "$PRISTINE" 's|^  reason=|  printf "skip_legs=%s\\n" "$would_skip" >> "$OUT"\n  reason=|; '"$_e1" row_lock row_oracle_surface
unset _e1

# ── Verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((passes + fails))
echo
echo "mutation battery: $MUT_KILLED/$MUT_TOTAL killed"
if [ "${#MUT_SURVIVED[@]}" -gt 0 ]; then
  printf 'surviving mutants (fixture-gap or equivalent: label which):\n' >&2
  printf '  - %s\n' "${MUT_SURVIVED[@]}" >&2
fi

# ASSERTION FLOOR, reported with printf + exit rather than through the helpers it backstops
# (ADR-193). DERIVED FROM A MEASURED GREEN RUN, not guessed: re-derive after adding a row —
#   bash scripts/ci-oracle-lane.test.sh | tail -1
MIN_ROWS=400
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor: %d rows executed, at least %d required. Rows were removed or a loop stopped early.\n' \
    "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
MIN_MUTANTS=20
if [ "$MUT_TOTAL" -lt "$MIN_MUTANTS" ]; then
  printf 'FAIL: mutation floor: %d mutants executed, at least %d required.\n' "$MUT_TOTAL" "$MIN_MUTANTS" >&2
  exit 1
fi

echo "ci-oracle-lane.test.sh: $TOTAL rows, $passes passed, $fails failed"
if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '\nfailures:\n' >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
