#!/usr/bin/env bash
#
# Functional suite for the knowledge-base index merge driver (#7935).
#
# WHAT THIS SUITE IS FOR. `knowledge-base/INDEX.md` is a committed generated
# artifact. Without a merge driver git merges it as prose, and the reflex
# resolution (`git checkout --theirs`) takes one side's copy whole — silently
# discarding the rows the other side added. That dropped the ADR-206 row three
# times on PR #7896. Every assertion below is made against a REAL `git merge`
# in a throwaway repository, never against a reading of the driver's source:
# the defect this closes is invisible to source inspection by construction.
#
# SEAM. This file holds the FUNCTIONAL scenarios. The two mutation batteries
# (`kb-index-check-guard-mutation.test.sh`, `merge-kb-index-driver-mutation.test.sh`) hold
# the "can each guard be driven red" question. That split is the one
# `scripts/test-all.sh` already documents for every guard-with-battery pair in
# the tree: bundling them makes a red run ambiguous between "a scenario broke"
# and "a guard stopped being enforceable".
#
# KB_DIR IS PINNED ON EVERY GENERATOR CALL. `generate-kb-index.sh` defaults
# KB_DIR to the real tree, which costs seconds per call (6,439 files; 6.7s measured 2026-09-08). An
# omitted pin would silently add minutes of real-corpus work to CI with nothing
# in the suite that would notice.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

GEN="$REPO_ROOT/scripts/generate-kb-index.sh"
DRIVER="$REPO_ROOT/scripts/merge-kb-index.sh"
RENDER_LIB="$REPO_ROOT/scripts/lib/kb-index-render.sh"

# `/tmp` is a machine-global 4 GiB tmpfs shared by every worktree on this box; a
# direct invocation of this suite (the documented inner loop) would otherwise
# inherit it while the runners default to /var/tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"

WORK=""
cleanup() { [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM HUP

WORK="$(mktemp -d -t kbmerge.XXXXXXXX)"
assert_fixture_dir "$WORK"

# --- fixture plumbing --------------------------------------------------------
# Hermetic git: no global/system config reaches these repos, so a developer's
# `merge.kb-index.driver` (which this very PR installs) cannot leak in and make
# the UNREGISTERED cases vacuously pass. That is not hypothetical — after this
# PR merges, every machine running the suite has the key set.
fx_git() {
  local dir="$1"; shift
  assert_fixture_dir "$dir"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$dir" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"
}

# Build a throwaway repo carrying a small knowledge-base corpus.
# `-b trunk`, never `main`: the commit-on-main guardrail blocks fixture commits
# (precedent: plugins/soleur/test/gitleaks-merge-commit.test.sh).
new_repo() {
  local name="$1"
  local dir="$WORK/$name"
  mkdir -p "$dir/knowledge-base/engineering" "$dir/knowledge-base/project"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q -b trunk "$dir"
  printf '# Alpha\n' > "$dir/knowledge-base/engineering/alpha.md"
  printf '# Beta\n'  > "$dir/knowledge-base/project/beta.md"
  gen "$dir"
  fx_git "$dir" add -A
  fx_git "$dir" commit -q -m base
  printf '%s' "$dir"
}

# The ONLY sanctioned way to produce an index in this suite.
gen() { KB_DIR="$1/knowledge-base" bash "$GEN" >/dev/null 2>&1; }

register_driver() {
  fx_git "$1" config merge.kb-index.driver "bash $DRIVER %O %A %B %P"
  printf 'knowledge-base/INDEX.md merge=kb-index\n' > "$1/.gitattributes"
  printf 'knowledge-base/kb-tags.txt merge=union\n' >> "$1/.gitattributes"
  printf 'knowledge-base/kb-categories.txt merge=union\n' >> "$1/.gitattributes"
  fx_git "$1" add .gitattributes
  fx_git "$1" commit -q -m attrs
}

idx() { printf '%s' "$1/knowledge-base/INDEX.md"; }

row_count()   { grep -c '^- \[' "$1" || true; }
header_count() { sed -n 's/^> Total files: \([0-9][0-9]*\)$/\1/p' "$1"; }

# A fresh generation of the SAME tree, produced off to the side so the
# comparison never mutates the artifact under test.
fresh_of() {
  local dir="$1"
  local out="$WORK/fresh.$$.$RANDOM"
  mkdir -p "$out"
  cp -r "$dir/knowledge-base" "$out/knowledge-base"
  rm -f "$out/knowledge-base/INDEX.md"
  KB_DIR="$out/knowledge-base" bash "$GEN" >/dev/null 2>&1
  printf '%s' "$out/knowledge-base/INDEX.md"
}

echo "=== T1/AC1-AC4: two branches each add a file, real merge, driver registered ==="
R="$(new_repo t1)"
register_driver "$R"
fx_git "$R" checkout -q -b side-a
printf '# Gamma\n' > "$R/knowledge-base/engineering/gamma.md"; gen "$R"
fx_git "$R" add -A; fx_git "$R" commit -q -m a
fx_git "$R" checkout -q trunk
fx_git "$R" checkout -q -b side-b
printf '# Delta\n' > "$R/knowledge-base/project/delta.md"; gen "$R"
fx_git "$R" add -A; fx_git "$R" commit -q -m b
fx_git "$R" checkout -q trunk
merge_rc=0
fx_git "$R" merge -q --no-ff -m merge side-a >/dev/null 2>&1 || merge_rc=$?
fx_git "$R" merge --no-ff -m merge2 side-b >/dev/null 2>&1 || merge_rc=$?
assert_eq "0" "$merge_rc" "T1: merge of both sides completes without conflict"
I="$(idx "$R")"
assert_eq "1" "$(grep -c 'engineering/gamma\.md' "$I" || true)" "AC1: side-a's row survives the merge"
assert_eq "1" "$(grep -c 'project/delta\.md' "$I" || true)" "AC1: side-b's row survives the merge"
assert_eq "$(row_count "$I")" "$(header_count "$I")" "AC4: header count equals the row count"
assert_eq "3" "$(fx_git "$R" rev-list --parents -1 HEAD | wc -w | tr -d ' ')" "AC3: a genuine two-parent merge, not a fast-forward"
assert_eq "" "$(diff "$I" "$(fresh_of "$R")" || echo DIFFERS)" "AC2: merged index is byte-identical to a fresh generation"

echo "=== T2/AC5: the same scenario UNREGISTERED is caught ==="
R2="$(new_repo t2)"
fx_git "$R2" checkout -q -b side-a
printf '# Gamma\n' > "$R2/knowledge-base/engineering/gamma.md"; gen "$R2"
fx_git "$R2" add -A; fx_git "$R2" commit -q -m a
fx_git "$R2" checkout -q trunk
printf '# Delta\n' > "$R2/knowledge-base/project/delta.md"; gen "$R2"
fx_git "$R2" add -A; fx_git "$R2" commit -q -m b
fx_git "$R2" merge --no-ff -m m side-a >/dev/null 2>&1 || true
# Whatever git produced here (a conflict left in the tree, or a clean line-merge
# that lies about the count), the property is the same: it is NOT what the
# generator would emit, and --check must say so.
I2="$(idx "$R2")"
unreg_differs=DIFFERS
diff -q "$I2" "$(fresh_of "$R2")" >/dev/null 2>&1 && unreg_differs=SAME
assert_eq "DIFFERS" "$unreg_differs" "AC5: an unregistered merge does not match a fresh generation"
chk_rc=0
KB_DIR="$R2/knowledge-base" bash "$GEN" --check >/dev/null 2>&1 || chk_rc=$?
assert_eq "1" "$([[ "$chk_rc" -ne 0 ]] && echo 1 || echo 0)" "AC5: --check exits non-zero on the unregistered result"

echo "=== T6/AC6: an unparseable ancestor row produces a LOUD failure, not a clean-looking file ==="
mkdir -p "$WORK/t6"
# Built through the REAL renderer, then corrupted by a targeted edit. Four
# fixtures here used to hand-write the whole rendered format as printf literals
# while every other builder in this file sourced kb_render_index. That is an
# unpinned replication of the layout: renderer drift (the change class rows G11
# and C10 exist for) would silently make them non-canonical, and T6/T18/T19 would
# then keep passing for the WRONG reason — failing round-trip validation instead
# of the property each one names.
mk_render() { local out="$1"; shift; local tsv="$WORK/.mkr.$$"; : > "$tsv"
  local r; for r in "$@"; do printf '%s\n' "$r" >> "$tsv"; done
  LC_ALL=C sort -o "$tsv" "$tsv"; ( source "$RENDER_LIB"; kb_render_index "$tsv" ) > "$out"; rm -f "$tsv"; }
# THE CORRUPTION IS A ROW, NOT THE DERIVED COUNT — and it was the count until
# T22 was written. `> Total files: 99` is not a corrupt ancestor in any sense the
# driver cares about: the count is a function of the rows, the driver never reads
# it, and its output recomputes it. Asserting a refusal on it pinned the
# over-strict behaviour that made the driver refuse this PR's own first sync
# against a perfectly parseable ancestor (see T22). What a corrupt ancestor
# actually means is a row the parser cannot key unambiguously, so that is what
# this case now injects. AND IT HAS TO KEEP THE DOMAIN. The first attempt used
# `- [Weird](x/x/a](x/b.md)`, whose mis-keyed rel `x/b.md` makes the renderer emit
# a `## x` heading the fixture does not carry — so ROUND-TRIP caught it and
# neutering the separator guard changed no assertion in either suite. Measured
# both ways. A same-domain row is the true round-trip fixed point: it re-renders
# byte-identically, so the separator count is the only thing that can see it.
mk_render "$WORK/t6/O" "$(printf 'engineering/alpha.md\tAlpha')" "$(printf 'engineering/z.md\tWeird](engineering/x')"
cp "$WORK/t6/O" "$WORK/t6/A"; cp "$WORK/t6/O" "$WORK/t6/B"
d_rc=0
bash "$DRIVER" "$WORK/t6/O" "$WORK/t6/A" "$WORK/t6/B" knowledge-base/INDEX.md >/dev/null 2>&1 || d_rc=$?
assert_eq "1" "$([[ "$d_rc" -ne 0 ]] && echo 1 || echo 0)" "T6: driver exits non-zero on an ancestor row it cannot key"
assert_eq "1" "$(grep -c '^<<<<<<< kb-index' "$WORK/t6/A" || true)" "AC6: the sentinel conflict marker is written exactly once"

echo "=== T19/AC25: the driver refuses any path but knowledge-base/INDEX.md ==="
mkdir -p "$WORK/t19"
mk_render "$WORK/t19/O" "$(printf 'engineering/alpha.md\tAlpha')"
cp "$WORK/t19/O" "$WORK/t19/A"; cp "$WORK/t19/O" "$WORK/t19/B"
p_rc=0
bash "$DRIVER" "$WORK/t19/O" "$WORK/t19/A" "$WORK/t19/B" some/other/file.md >/dev/null 2>&1 || p_rc=$?
assert_eq "1" "$([[ "$p_rc" -ne 0 ]] && echo 1 || echo 0)" "T19: driver refuses a foreign %P"
# THE REFUSAL MUST NOT WRITE. An earlier revision asserted the opposite, and that
# assertion pinned a real defect: git writes %A into the working tree even when a
# driver exits non-zero, so writing the sentinel on a path this driver does not
# own PERFORMS the denial of service the %P check exists to prevent. One
# committed `* merge=kb-index` line would then have every merge in every worktree
# prepend a text line to every file, corrupting binaries with a UTF-8 prefix.
assert_eq "0" "$(grep -c '^<<<<<<< kb-index' "$WORK/t19/A" || true)" "T19: the refusal does NOT write to a path this driver does not own"
assert_eq "" "$(diff "$WORK/t19/O" "$WORK/t19/A" || echo DIFFERS)" "T19: the refused file is left byte-identical"

echo "=== T18/AC25: a row escaping knowledge-base/ is rejected even though it round-trips ==="
mkdir -p "$WORK/t18"
mk_render "$WORK/t18/O" "$(printf 'engineering/alpha.md\tAlpha')"
cp "$WORK/t18/O" "$WORK/t18/A"
mk_render "$WORK/t18/B" "$(printf 'engineering/alpha.md\tAlpha')" "$(printf '../../.env\tNote')"
c_rc=0
bash "$DRIVER" "$WORK/t18/O" "$WORK/t18/A" "$WORK/t18/B" knowledge-base/INDEX.md >/dev/null 2>&1 || c_rc=$?
assert_eq "1" "$([[ "$c_rc" -ne 0 ]] && echo 1 || echo 0)" "T18: a ../ escaping rel is rejected"
assert_eq "1" "$(grep -c '^<<<<<<< kb-index' "$WORK/t18/A" || true)" "T18: rejection writes the sentinel"

echo "=== AC13/AC24: render parity and an inert parser ==="
assert_file_exists "$RENDER_LIB" "AC13: the shared render helper exists"
# The design stakes the sentinel's visibility on `guardrails:block-conflict-markers`,
# whose regex is `^\+(<{7}|={7}|>{7})`. That coupling is a property of the marker's
# SHAPE — exactly seven `<` — and nothing asserted it.
_sent_line="$(grep -m1 '^readonly SENTINEL_PREFIX=' "$DRIVER" | sed "s/^readonly SENTINEL_PREFIX='//; s/'$//")"
assert_eq "1" "$(printf '%s' "$_sent_line" | grep -cE '^<{7}[^<]' || true)" \
  "AC6b: the sentinel begins with exactly seven '<' so guardrails:block-conflict-markers matches it"
# BOTH BATTERIES MUST BE AUTO-DISCOVERABLE, not hand-registered. `SUITE_GLOBS`
# covers `plugins/soleur/test/*.test.sh` and `lint-orphan-test-suites.sh` walks
# `*.test.sh`, so the `*-mutation.test.sh` convention every registered bash
# battery in this repo already uses makes both surfaces see them for free. The
# earlier `*.mutation.sh` spelling was invisible to both and needed a manual
# `run_suite` line plus a comment explaining why -- restating the hazard instead
# of deriving it away, and adding two members to the class #7942 tracks.
for _bat in kb-index-check-guard-mutation merge-kb-index-driver-mutation; do
  assert_file_exists "$SCRIPT_DIR/${_bat}.test.sh" "AC15b: ${_bat} uses the auto-discoverable *-mutation.test.sh name"
done
assert_eq "0" "$(git -C "$REPO_ROOT" ls-files 'plugins/soleur/test/*kb-index*.mutation.sh' 'plugins/soleur/test/*merge-kb-index*.mutation.sh' | wc -l | tr -d ' ')" \
  "AC15b: neither battery carries the *.mutation.sh spelling that no glob and no lint can see"
# Comment-stripped: a correct generator that DOCUMENTS where the header comes from would
# otherwise false-fail this — the same collision the three fixed instances above carry.
assert_eq "0" "$(grep -vE '^[[:space:]]*#' "$GEN" | grep -c 'Total files:' || true)" "AC13: the header literal appears nowhere in the generator's CODE"
# ANCHORED ON THE CALL SHAPE, NOT THE BARE TOKEN. A `grep -c 'eval'` here
# false-FAILS on the driver's own comment explaining that it uses no eval --
# the exact collision cq-assert-anchor-not-bare-token describes, and it fired on
# the first run of this suite. `eval` is a builtin, so a real call sits at a
# command position: start of line, or after a separator.
assert_eq "0" "$(grep -cE '(^|[;&|(]|&&|\|\|)[[:space:]]*eval[[:space:]]' "$DRIVER" || true)" \
  "AC24: the driver makes no call to eval"

echo "=== T21/AC24: a hostile title round-trips as inert text ==="
mkdir -p "$WORK/t21"
HOSTILE='Danger $(id) `whoami` ; rm -rf / '"'"'quote'"'"''
mkdir -p "$WORK/t21/repo/knowledge-base/engineering"
printf -- '---\ntitle: "%s"\n---\n' "$HOSTILE" > "$WORK/t21/repo/knowledge-base/engineering/hostile.md"
KB_DIR="$WORK/t21/repo/knowledge-base" bash "$GEN" >/dev/null 2>&1
HI="$WORK/t21/repo/knowledge-base/INDEX.md"
assert_eq "1" "$(grep -cF '$(id)' "$HI" || true)" "T21: the hostile title reaches the index verbatim (the premise)"
cp "$HI" "$WORK/t21/O"; cp "$HI" "$WORK/t21/A"; cp "$HI" "$WORK/t21/B"
h_rc=0
bash "$DRIVER" "$WORK/t21/O" "$WORK/t21/A" "$WORK/t21/B" knowledge-base/INDEX.md >/dev/null 2>&1 || h_rc=$?
assert_eq "0" "$h_rc" "T21: the driver resolves a hostile-title index without error"
assert_eq "" "$(diff "$HI" "$WORK/t21/A" || echo DIFFERS)" "T21: the hostile row round-trips byte-identically; nothing executed"

echo "=== T20: the same rel added on BOTH sides with different titles ==="
mkdir -p "$WORK/t20"
mk_index() {
  # $1 = out path, remaining args = rel<TAB>title rows
  local out="$1"; shift
  local tsv="$WORK/t20/tsv.$$"
  : > "$tsv"
  local r
  for r in "$@"; do printf '%s\n' "$r" >> "$tsv"; done
  LC_ALL=C sort -o "$tsv" "$tsv"
  ( source "$RENDER_LIB"; kb_render_index "$tsv" ) > "$out"
  rm -f "$tsv"
}
mk_index "$WORK/t20/O" "$(printf 'engineering/alpha.md\tAlpha')"
mk_index "$WORK/t20/A" "$(printf 'engineering/alpha.md\tAlpha')" "$(printf 'engineering/new.md\tOurTitle')"
mk_index "$WORK/t20/B" "$(printf 'engineering/alpha.md\tAlpha')" "$(printf 'engineering/new.md\tTheirTitle')"
t20_rc=0
bash "$DRIVER" "$WORK/t20/O" "$WORK/t20/A" "$WORK/t20/B" knowledge-base/INDEX.md >/dev/null 2>&1 || t20_rc=$?
assert_eq "1" "$([[ "$t20_rc" -ne 0 ]] && echo 1 || echo 0)" "T20: a two-sided add with differing titles refuses rather than picking one"
assert_eq "1" "$(grep -c '^<<<<<<< kb-index' "$WORK/t20/A" || true)" "T20: the refusal writes the sentinel"

echo "=== T4: both sides retitle the same file differently ==="
mkdir -p "$WORK/t4"
mk4() { local out="$1" title="$2" tsv="$WORK/t4/tsv"; printf 'engineering/alpha.md\t%s\n' "$title" > "$tsv"; ( source "$RENDER_LIB"; kb_render_index "$tsv" ) > "$out"; }
mk4 "$WORK/t4/O" "Base"; mk4 "$WORK/t4/A" "Ours"; mk4 "$WORK/t4/B" "Theirs"
t4_rc=0
bash "$DRIVER" "$WORK/t4/O" "$WORK/t4/A" "$WORK/t4/B" knowledge-base/INDEX.md >/dev/null 2>&1 || t4_rc=$?
assert_eq "1" "$([[ "$t4_rc" -ne 0 ]] && echo 1 || echo 0)" "T4: a two-sided retitle refuses rather than picking one"
assert_eq "1" "$(grep -c '^<<<<<<< kb-index' "$WORK/t4/A" || true)" "T4: the refusal writes the sentinel"

echo "=== T4b: a ONE-sided retitle takes the changed side ==="
mk4 "$WORK/t4/O2" "Base"; mk4 "$WORK/t4/A2" "Base"; mk4 "$WORK/t4/B2" "Renamed"
bash "$DRIVER" "$WORK/t4/O2" "$WORK/t4/A2" "$WORK/t4/B2" knowledge-base/INDEX.md >/dev/null 2>&1
assert_eq "1" "$(grep -c 'Renamed' "$WORK/t4/A2" || true)" "T4b: the one changed title wins"

echo "=== T3: one side adds a file, the other deletes a different one ==="
R3="$(new_repo t3)"
register_driver "$R3"
fx_git "$R3" checkout -q -b add-side
printf '# Gamma\n' > "$R3/knowledge-base/engineering/gamma.md"; gen "$R3"
fx_git "$R3" add -A; fx_git "$R3" commit -q -m add
fx_git "$R3" checkout -q trunk
rm "$R3/knowledge-base/project/beta.md"; gen "$R3"
fx_git "$R3" add -A; fx_git "$R3" commit -q -m del
t3_rc=0
fx_git "$R3" merge --no-ff -m m add-side >/dev/null 2>&1 || t3_rc=$?
I3="$(idx "$R3")"
assert_eq "0" "$t3_rc" "T3: add-vs-delete merges cleanly"
assert_eq "1" "$(grep -c 'engineering/gamma\.md' "$I3" || true)" "T3: the addition is present"
assert_eq "0" "$(grep -c 'project/beta\.md' "$I3" || true)" "T3: the deletion is NOT resurrected"
assert_eq "" "$(diff "$I3" "$(fresh_of "$R3")" || echo DIFFERS)" "T3: still byte-identical to a fresh generation"

echo "=== T5: one side unchanged -- run PAIRED so 'the driver ran' is distinguishable ==="
# With the driver unset, plain git also resolves this input cleanly, so a single
# run proves nothing. The pair is what makes it evidence.
for mode in registered unset; do
  R5="$(new_repo "t5-$mode")"
  [[ "$mode" == registered ]] && register_driver "$R5"
  fx_git "$R5" checkout -q -b quiet
  # `quiet` MUST advance. An earlier revision branched it and left it at trunk's
  # tip, which makes it an ANCESTOR: `git merge --no-ff quiet` then prints
  # "Already up to date." and creates no commit at all (--no-ff forces a merge
  # commit for a fast-forward, not for an already-up-to-date merge). The driver
  # ran in NEITHER arm, all four assertions passed unconditionally, and the
  # comment below claimed the pair was what made it evidence — the exact inverse
  # of what the code did. Measured: rc=0, 2 parents, HEAD subject unchanged.
  printf 'quiet side\n' > "$R5/knowledge-base/engineering/quiet-note.md"
  fx_git "$R5" add -A; fx_git "$R5" commit -q -m quiet-advances
  fx_git "$R5" checkout -q trunk
  printf '# Gamma\n' > "$R5/knowledge-base/engineering/gamma.md"; gen "$R5"
  fx_git "$R5" add -A; fx_git "$R5" commit -q -m change
  r5_rc=0
  fx_git "$R5" merge --no-ff -m m quiet >/dev/null 2>&1 || r5_rc=$?
  assert_eq "0" "$r5_rc" "T5[$mode]: a quiet side never over-conflicts"
  # The gitleaks precedent asserts this PER FIXTURE precisely so a broken fixture
  # fails the suite instead of fabricating a clean result.
  assert_eq "3" "$(fx_git "$R5" rev-list --parents -1 HEAD | wc -w | tr -d ' ')" "T5[$mode]: a real two-parent merge actually happened"
  assert_eq "1" "$(grep -c 'engineering/gamma\.md' "$(idx "$R5")" || true)" "T5[$mode]: the changed side's row is present"
done

echo "=== T7/T8: the facet files union rather than side-picking ==="
R7="$(new_repo t7)"
register_driver "$R7"
mklearn() { mkdir -p "$1/knowledge-base/project/learnings"; printf -- '---\ntags: [%s]\ncategory: %s\n---\n# L\n' "$2" "$3" > "$1/knowledge-base/project/learnings/$4.md"; }
fx_git "$R7" checkout -q -b tag-a
mklearn "$R7" "alpha-tag" "alpha-cat" la; gen "$R7"
fx_git "$R7" add -A; fx_git "$R7" commit -q -m ta
fx_git "$R7" checkout -q trunk
mklearn "$R7" "beta-tag" "beta-cat" lb; gen "$R7"
fx_git "$R7" add -A; fx_git "$R7" commit -q -m tb
fx_git "$R7" merge --no-ff -m m tag-a >/dev/null 2>&1 || true
assert_eq "1" "$(grep -cx 'alpha-tag' "$R7/knowledge-base/kb-tags.txt" || true)" "T7: side-a's tag survives the union merge"
assert_eq "1" "$(grep -cx 'beta-tag' "$R7/knowledge-base/kb-tags.txt" || true)" "T7: side-b's tag survives the union merge"
assert_eq "1" "$(grep -cx 'alpha-cat' "$R7/knowledge-base/kb-categories.txt" || true)" "T8: side-a's category survives"
assert_eq "1" "$(grep -cx 'beta-cat' "$R7/knowledge-base/kb-categories.txt" || true)" "T8: side-b's category survives"

echo "=== T12: the driver fires for rebase, not only merge ==="
R12="$(new_repo t12)"
register_driver "$R12"
fx_git "$R12" checkout -q -b topic
printf '# Gamma\n' > "$R12/knowledge-base/engineering/gamma.md"; gen "$R12"
fx_git "$R12" add -A; fx_git "$R12" commit -q -m topic
fx_git "$R12" checkout -q trunk
printf '# Delta\n' > "$R12/knowledge-base/project/delta.md"; gen "$R12"
fx_git "$R12" add -A; fx_git "$R12" commit -q -m trunkside
fx_git "$R12" checkout -q topic
t12_rc=0
fx_git "$R12" rebase trunk >/dev/null 2>&1 || t12_rc=$?
assert_eq "0" "$t12_rc" "T12: rebase completes without conflict"
I12="$(idx "$R12")"
assert_eq "1" "$(grep -c 'engineering/gamma\.md' "$I12" || true)" "T12: the topic row survives the rebase"
assert_eq "1" "$(grep -c 'project/delta\.md' "$I12" || true)" "T12: the trunk row survives the rebase"

echo "=== T13: the refs/pull/N/merge shape -- equal additions line-merge to a wrong count ==="
# Both sides add the SAME NUMBER of files, so both write identical count text and
# git merges the line cleanly to a value that is wrong by construction. Rows
# union in; nothing is lost; --check is red. Pinned so a future reader does not
# rediscover this as a mystery: it is a true positive on the artifact, and the
# only fix is to re-sync the branch.
R13="$(new_repo t13)"
fx_git "$R13" checkout -q -b s1
printf '# G\n' > "$R13/knowledge-base/engineering/g.md"; gen "$R13"
fx_git "$R13" add -A; fx_git "$R13" commit -q -m s1
fx_git "$R13" checkout -q trunk
printf '# D\n' > "$R13/knowledge-base/project/d.md"; gen "$R13"
fx_git "$R13" add -A; fx_git "$R13" commit -q -m s2
fx_git "$R13" merge --no-ff -m m s1 >/dev/null 2>&1 || true
I13="$(idx "$R13")"
assert_eq "1" "$(grep -c 'engineering/g\.md' "$I13" || true)" "T13: rows union in even without the driver"
assert_eq "1" "$(grep -c 'project/d\.md' "$I13" || true)" "T13: both rows present"
t13_hdr="$(header_count "$I13")"; t13_rows="$(row_count "$I13")"
assert_eq "1" "$([[ "$t13_hdr" != "$t13_rows" ]] && echo 1 || echo 0)" "T13: the header count is wrong with no conflict and no marker"
t13_chk=0
KB_DIR="$R13/knowledge-base" bash "$GEN" --check >/dev/null 2>&1 || t13_chk=$?
assert_eq "1" "$([[ "$t13_chk" -ne 0 ]] && echo 1 || echo 0)" "T13: --check catches it"

echo "=== T16: an UNHANDLED shell error still writes the sentinel (the ERR trap) ==="
# THE DISTINCTION IS LOAD-BEARING AND WAS INITIALLY GOT WRONG HERE. An over-long
# row trips an explicit `die`, which writes the sentinel BY HAND -- so it proves
# nothing about the ERR trap, and the trap survived its own mutation row while
# this case was the only thing claiming to cover it. The trap exists for the
# paths with no `die` on them: an unbound variable, an awk crash on adversarial
# input, disk-full while writing %A. A broken TMPDIR kills the driver at its
# `mktemp -d`, before any validation runs, which is that shape exactly.
mkdir -p "$WORK/t16"
mk4b() { local out="$1" tsv="$WORK/t16/tsv"; printf 'engineering/alpha.md\tAlpha\n' > "$tsv"; ( source "$RENDER_LIB"; kb_render_index "$tsv" ) > "$out"; }
mk4b "$WORK/t16/O"; mk4b "$WORK/t16/A"; mk4b "$WORK/t16/B"
{ printf -- '- ['; head -c 9000 /dev/zero | tr '\0' 'x'; printf '](engineering/huge.md)\n'; } >> "$WORK/t16/B"
t16_rc=0
bash "$DRIVER" "$WORK/t16/O" "$WORK/t16/A" "$WORK/t16/B" knowledge-base/INDEX.md >/dev/null 2>&1 || t16_rc=$?
assert_eq "1" "$([[ "$t16_rc" -ne 0 ]] && echo 1 || echo 0)" "T16: an over-long row fails closed (the HANDLED path)"
assert_eq "1" "$(grep -c '^<<<<<<< kb-index' "$WORK/t16/A" || true)" "T16: the handled path writes the sentinel"
# The genuinely unhandled path: nothing on it calls die.
mk4b "$WORK/t16/A2"
t16u_rc=0
TMPDIR="$WORK/t16/definitely-not-a-directory" bash "$DRIVER" \
  "$WORK/t16/O" "$WORK/t16/A2" "$WORK/t16/B" knowledge-base/INDEX.md >/dev/null 2>&1 || t16u_rc=$?
assert_eq "1" "$([[ "$t16u_rc" -ne 0 ]] && echo 1 || echo 0)" "T16: an UNHANDLED failure exits non-zero"
assert_eq "1" "$(grep -c '^<<<<<<< kb-index' "$WORK/t16/A2" || true)" "T16: the ERR trap writes the sentinel where no die exists"

echo "=== T14: the Guard 3 GIT_* tripwire aborts a leaked fixture ==="
t14_rc=0
GIT_DIR=/tmp/leaked bash -c 'source "$1/test-helpers.sh"' _ "$SCRIPT_DIR" >/dev/null 2>&1 || t14_rc=$?
assert_eq "97" "$t14_rc" "T14: an inherited GIT_DIR aborts with exit 97"

echo "=== AC12/T9: .gitattributes routes exactly the three generated paths ==="
ca() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$REPO_ROOT" check-attr merge -- "$1" | sed 's/.*: //'; }
assert_eq "kb-index" "$(ca knowledge-base/INDEX.md)" "AC12: INDEX.md routes to the kb-index driver"
assert_eq "union" "$(ca knowledge-base/kb-tags.txt)" "AC12: kb-tags.txt routes to union"
assert_eq "union" "$(ca knowledge-base/kb-categories.txt)" "AC12: kb-categories.txt routes to union"
assert_eq "unspecified" "$(ca plugins/soleur/knowledge-base/INDEX.md)" "AC12: the hand-maintained plugin mirror is untouched"

echo "=== AC18/AC19/AC20/AC26: the surrounding wiring ==="
# NOT COMMENT-STRIPPED, and that is the whole point of this row. The prescription
# only ever LIVED in a comment, so stripping comments first made the assertion
# unfalsifiable: restoring the removed line verbatim leaves it green. Measured.
# The comment-strip that makes AC13 and AC18 correct makes this one vacuous.
assert_eq "0" "$(grep -c 'After merge conflicts on INDEX.md, regenerate' "$GEN" || true)"   "AC20: the generator no longer prescribes the hand-run remedy"
# ANCHORED ON THE GUIDANCE SENTENCE, not the basename. `grep -c merge-kb-index.sh
# >= 1` is satisfied by an unrelated architecture note elsewhere in the file, so
# deleting the whole replacement block left this green — the seventh instance of
# cq-assert-anchor-not-bare-token on this branch.
assert_eq "1" "$(grep -c 'never resolve it by taking one side' "$GEN" || true)"   "AC20: the replacement names the driver and the rule"
# ANCHORED ON THE `run:` LINE. `grep -c 'kb-tags.txt' lefthook.yml >= 1` is satisfied by a
# COMMENT — and this is the assertion for the behaviour this PR changes, so it failed OPEN:
# reverting the stanza to main's `git add knowledge-base/INDEX.md` while a comment still
# named the file left it PASSING (measured). Fourth instance of the anchor class here, and
# the only one in the dangerous direction. Trailing comments are stripped because the
# first attempt at this fix — anchoring on the `run:` line — was ALSO satisfiable: the
# comment naming the files sits INLINE on that very line, so it matched anyway.
assert_eq "1" "$(grep -E '^[[:space:]]*run:' "$REPO_ROOT/lefthook.yml" | sed 's/#.*//' | grep -cE 'git add.*kb-tags[.]txt.*kb-categories[.]txt' || true)"   "AC18: the lefthook run: line STAGES all three artifacts (trailing comments stripped)"
assert_eq "1" "$([[ "$(grep -c 'knowledge-base/INDEX.md' "$REPO_ROOT/plugins/soleur/skills/merge-pr/SKILL.md" || true)" -ge 1 ]] && echo 1 || echo 0)"   "AC19: merge-pr routing names the index explicitly"
# ANCHORED ON THE ROW SYNTAX, not the basename. A bare-basename count reads 4
# here because the block's own comment explains WHY merge-kb-index.sh needs a
# row -- the second instance of cq-assert-anchor-not-bare-token in this one
# change (the first was AC24's `eval`). A CODEOWNERS row is a leading `/path`
# followed by an `@owner`; a comment line starts with `#` and cannot match.
assert_eq "3" "$(grep -cE '^/scripts/(merge-kb-index|lib/kb-index-render|install-kb-merge-driver)[.]sh[[:space:]]+@' "$REPO_ROOT/.github/CODEOWNERS" || true)" "AC26: all three gate-critical scripts carry CODEOWNERS rows"

# ---------------------------------------------------------------------------
# T22/AC27/AC28 — A STALE DERIVED COUNT IN THE ANCESTOR MUST NOT BLOCK THE MERGE.
#
# Found by running this PR's own driver on this PR's own first sync, not by
# inspection. Round-trip validation originally byte-compared the WHOLE file,
# ancestor included, and refused with "not a canonical generated index". The
# ancestor was fine: its rows parsed perfectly. Its `> Total files:` header was
# one short of its body, because main's generator counted `${#all_files[@]}`
# (the find result) while emitting rows from a separate pass. Measured on
# origin/main 2026-09-08: two of the last twelve commits touching INDEX.md carry
# that off-by-one (68b0e6d79 header 6430 / body 6431; 8094a685d 6432 / 6433).
#
# An ancestor is a historical commit BY CONSTRUCTION, so validating a derived
# field in it makes the driver refuse ordinary merges at a rate set by how often
# that field was ever stale. The count is a function of the rows, the driver
# never reads it, and its output always recomputes it — so it is exempt, and
# NOTHING ELSE IS (AC28).
echo "=== T22/AC27/AC28: a stale derived count in the ancestor ==="
R22="$(new_repo t22)"
register_driver "$R22"
# Corrupt ONLY the ancestor's header numeral, leaving every row intact. `sed` on
# the committed file then amend, so the stale value is what git hands the driver
# as %O rather than something the working tree can quietly regenerate away.
I22="$(idx "$R22")"
# UNDERCOUNT, not 999. The measured historical blobs are header = body - 1
# (68b0e6d79: 6430/6431; 8094a685d: 6432/6433) because main's generator counted
# the find pass while emitting rows from another. An OVERCOUNT is a different
# event entirely -- rows removed while the count line survived -- and the driver
# now refuses it (AC29 below). A fixture using 999 modelled the direction that
# must FAIL while asserting the one that must pass.
sed -i 's/^> Total files: \([0-9][0-9]*\)$/> Total files: 1/' "$I22"
fx_git "$R22" add -A; fx_git "$R22" commit -q --amend --no-edit
assert_eq "1" "$(header_count "$I22")" "T22: the ancestor really does carry a stale count"
assert_eq "1" "$([[ "$(header_count "$I22")" -lt "$(row_count "$I22")" ]] && echo 1 || echo 0)" \
  "T22: and it is an UNDERCOUNT — the direction history actually produces"
fx_git "$R22" checkout -q -b side-a
printf '# Gamma\n' > "$R22/knowledge-base/engineering/gamma.md"; gen "$R22"
fx_git "$R22" add -A; fx_git "$R22" commit -q -m a
fx_git "$R22" checkout -q trunk
printf '# Delta\n' > "$R22/knowledge-base/project/delta.md"; gen "$R22"
fx_git "$R22" add -A; fx_git "$R22" commit -q -m b
m22=0
fx_git "$R22" merge --no-ff -m merge side-a >/dev/null 2>&1 || m22=$?
assert_eq "0" "$m22" "AC27: the merge resolves despite the ancestor's stale count"
assert_eq "0" "$(grep -c '<<<<<<<' "$I22" || true)" "AC27: no sentinel was written"
assert_eq "1" "$(grep -c 'engineering/gamma\.md' "$I22" || true)" "AC27: side-a's row survives"
assert_eq "1" "$(grep -c 'project/delta\.md' "$I22" || true)" "AC27: trunk's row survives"
assert_eq "$(row_count "$I22")" "$(header_count "$I22")" "AC27: the OUTPUT's count is recomputed, not inherited"

# AC28 — the exemption is the numeral and nothing else. Same scenario, but the
# ancestor's header LINE is reshaped rather than merely stale. A mask that
# tolerated the whole line (or the whole header block) would pass this too, and
# would stop pinning the renderer's byte-identity to the generator's.
# ---------------------------------------------------------------------------
# AC29 — AN OVERCOUNT IS ROW LOSS, AND IT MUST REFUSE. On a LIVE side, not the
# ancestor: this is the shape a hand-stripped conflict leaves behind, and it is
# how the ADR-206 row was dropped three times on PR #7896.
#
# Measured before the guard existed: ours = one row with a header saying two,
# theirs = that row plus two more. The merge resolved rc=0, wrote no sentinel,
# and silently dropped the row — this change's own mask reintroducing the exact
# defect the change exists to prevent. Every other stale-count case in both
# suites corrupts the ANCESTOR, so none of them could see it.
echo "=== AC29: an overcount on a live side is row loss, and refuses ==="
mkdir -p "$WORK/ac29"
mk_render "$WORK/ac29/O" "$(printf 'engineering/alpha.md\tAlpha')" "$(printf 'engineering/gamma.md\tGamma')"
mk_render "$WORK/ac29/A" "$(printf 'engineering/alpha.md\tAlpha')"
sed -i 's/^> Total files: 1$/> Total files: 2/' "$WORK/ac29/A"
mk_render "$WORK/ac29/B" "$(printf 'engineering/alpha.md\tAlpha')" "$(printf 'engineering/gamma.md\tGamma')" "$(printf 'project/beta.md\tBeta')"
ac29_rc=0
bash "$DRIVER" "$WORK/ac29/O" "$WORK/ac29/A" "$WORK/ac29/B" knowledge-base/INDEX.md >/dev/null 2>&1 || ac29_rc=$?
assert_eq "1" "$([[ "$ac29_rc" -ne 0 ]] && echo 1 || echo 0)" "AC29: an overcount on the ours side refuses"
assert_eq "1" "$(grep -c '^<<<<<<< kb-index' "$WORK/ac29/A" || true)" "AC29: and writes exactly one sentinel naming the cause"
assert_eq "1" "$(grep -c 'rows were removed while the count line survived' "$WORK/ac29/A" || true)" "AC29: the sentinel names row loss, not a generic mismatch"

echo "=== AC28: only the numeral is exempt, not the header line ==="
R23="$(new_repo t23)"
register_driver "$R23"
I23="$(idx "$R23")"
sed -i 's/^> Total files: [0-9][0-9]*$/> Total files: many/' "$I23"
fx_git "$R23" add -A; fx_git "$R23" commit -q --amend --no-edit
fx_git "$R23" checkout -q -b side-a
printf '# Gamma\n' > "$R23/knowledge-base/engineering/gamma.md"; gen "$R23"
fx_git "$R23" add -A; fx_git "$R23" commit -q -m a
fx_git "$R23" checkout -q trunk
printf '# Delta\n' > "$R23/knowledge-base/project/delta.md"; gen "$R23"
fx_git "$R23" add -A; fx_git "$R23" commit -q -m b
m23=0
fx_git "$R23" merge --no-ff -m merge side-a >/dev/null 2>&1 || m23=$?
assert_eq "1" "$([[ "$m23" -ne 0 ]] && echo 1 || echo 0)" "AC28: a reshaped header line still refuses"
assert_eq "1" "$([[ "$(grep -c '<<<<<<<' "$I23" || true)" -ge 1 ]] && echo 1 || echo 0)" "AC28: and the refusal writes a sentinel naming the cause"


echo "=== AC17: the COMMITTED artifacts are fresh — the guard's only real-tree caller ==="
# THIS IS THE WIRING, NOT A NICETY. Every other --check invocation in this suite
# is KB_DIR-pinned to a fixture, which exercises the guard's LOGIC and asserts
# nothing about the repository. Without this case `generate-kb-index.sh --check`
# has no caller against the real tree at all: it would be reachable only by hand,
# and "I ran it once while writing the PR" is a claim, not a gate. Since git
# gives NO signal when .gitattributes names an unregistered merge driver, that
# would leave the silent-line-merge case — the one this whole change exists to
# close — caught by nothing.
#
# COST IS DELIBERATE AND BOUNDED. This is the ONE call in the entire suite
# permitted to run against the real corpus (6,439 rows; 6.7s measured 2026-09-08); every other call
# pins KB_DIR at a fixture of ten files or fewer, because an omitted pin would
# silently add minutes per run with nothing here that would notice.
ac17_rc=0
ac17_out="$(cd "$REPO_ROOT" && bash "$GEN" --check 2>&1)" || ac17_rc=$?
if [[ "$ac17_rc" -ne 0 ]]; then
  # Print the diff: a bare "stale" verdict sends the reader to re-derive what
  # this run already computed.
  printf '%s\n' "$ac17_out" | head -40 >&2
fi
assert_eq "0" "$ac17_rc" "AC17: the committed INDEX.md/kb-tags.txt/kb-categories.txt match a fresh generation"

# ---------------------------------------------------------------------------
# ASSERTION-HELPER POSITIVE CONTROL.
#
# The `print_results <floor>` floor counts PASS+FAIL+SKIPPED, so it discriminates
# DISPATCH (were the helpers called) and not VERDICT (can they still fail).
# Measured: replacing assert_eq's comparison with `if true; then` — leaving the
# FAIL branch present and unreachable — reports `Passed: 60  Failed: 0
# ALL TESTS PASSED`, byte-identical to a genuine green run, and no floor of any
# size can tell those apart. Raising the floor to compare PASS instead does not
# help for the same reason.
#
# The only thing that can is driving both arms and checking both counters moved.
# This runs LAST so it cannot mask a real failure, snapshots and restores the
# counters, and reports by direct printf + exit rather than through the helper it
# is testing.
_pc_pass_before="$PASS"; _pc_fail_before="$FAIL"
assert_eq "control" "control" "positive control: assert_eq can PASS"
assert_eq "control" "MISMATCH-EXPECTED" "positive control: assert_eq can FAIL (this FAIL line is expected)"
if (( PASS != _pc_pass_before + 1 )); then
  printf 'POSITIVE CONTROL BROKEN: PASS moved %d -> %d, expected exactly +1.\n' "$_pc_pass_before" "$PASS" >&2
  printf 'The assertion helpers cannot pass, so every green above is meaningless.\n' >&2
  exit 1
fi
if (( FAIL != _pc_fail_before + 1 )); then
  printf 'POSITIVE CONTROL BROKEN: FAIL moved %d -> %d, expected exactly +1.\n' "$_pc_fail_before" "$FAIL" >&2
  printf 'The assertion helpers cannot FAIL, so every green above is meaningless.\n' >&2
  exit 1
fi
# Unwind the control's own bookkeeping so it does not colour the real verdict.
PASS=$_pc_pass_before
FAIL=$_pc_fail_before

print_results 78
