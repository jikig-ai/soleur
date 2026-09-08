#!/usr/bin/env bash
# Guard 1 mutation battery — scripts/generate-kb-index.sh --check.
#
# THE PROPERTY. No knowledge-base/INDEX.md, kb-tags.txt or kb-categories.txt
# reaches main whose content differs from what the generator would emit for the
# tree it sits in.
#
# WHY THIS GUARD CARRIES THE WHOLE FAIL-OPEN CASE. Git gives NO signal when
# .gitattributes names a merge driver that is not registered -- it silently
# falls back to the default text merge and the output is byte-identical to
# having no .gitattributes at all. There is no hook for detecting that. So the
# only thing standing between an unregistered driver and a wrong index on main
# is this check, and a vacuous --check would restore the exact silence the whole
# change exists to remove.
#
# IT IS A REGENERATION DIFF, NOT A STRUCTURAL LINT, and the rows below are what
# make that concrete: a checklist of structural assertions would re-implement
# the generator's row-eligibility predicate in a second place, and still could
# not see renderer drift, title drift, or a side-picked resolve. Regenerating
# catches all of them.
#
# EVERY GENERATOR CALL PINS KB_DIR AT A FIXTURE. The generator defaults KB_DIR
# to the real tree (6,434 files; `bash scripts/generate-kb-index.sh --check` measured 6.7s on 2026-09-08); this battery makes on the order
# of thirty calls, so an omitted pin would silently add minutes with nothing in
# the run that would notice.
#
# MUTATION MATRIX (observed verdicts; every row RED = the guard holds)
#   C1  --check always exits 0 ............................ RED
#   C2  the per-file diff result is discarded ............. RED
#   C3  INDEX.md is dropped from the compared set ......... RED
#   C4  kb-tags.txt is dropped from the compared set ...... RED
#   C5  kb-categories.txt is dropped from the compared set  RED
#   C6  --check regenerates OVER the tracked artifacts .... RED
#   C7  --out is ignored, so --check diffs a file vs itself RED
#   C8  --check is accepted but never dispatched .......... RED
#   C9  --out writes only INDEX.md, leaving stale facets .. RED
#   C10 the renderer's header line drifts ................. RED
#   C11 the row-eligibility predicate drifts (archive/) ... RED (needs Q9)
#   H1  facet extraction gutted: a fresh generation must differ  RED
#
# AXIS DISCLOSURE. Every row above perturbs SUT SOURCE CONTENT; that is one axis,
# not twelve. This battery does NOT edit fixture shape, fixture direction, the
# harness's own dispatch, or set cardinality. An earlier revision of this header
# claimed H1 neutered "the probe's corruption step" and scaffolded a
# NEUTER_CORRUPTION flag for it that nothing ever set — five inert guards, one
# carrying an `A || B && C` precedence bug that would have misfired had it ever
# been wired. The flag is gone and the claim now matches what H1 does.

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate (%s); refusing\n' "$SCRIPT_DIR" >&2; exit 2 ;;
  /*) : ;;
  *)  printf 'FATAL: SCRIPT_DIR is relative; refusing\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT

TRACKED_GEN="$REPO_ROOT/scripts/generate-kb-index.sh"
TRACKED_RENDER="$REPO_ROOT/scripts/lib/kb-index-render.sh"
[[ -f "$TRACKED_GEN" ]]    || { printf 'FATAL: generator missing at %s\n' "$TRACKED_GEN" >&2; exit 2; }
[[ -f "$TRACKED_RENDER" ]] || { printf 'FATAL: renderer missing at %s\n' "$TRACKED_RENDER" >&2; exit 2; }

WORK="$(mktemp -d -t g1kb.XXXXXXXX)" || exit 2
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *)  printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK
M="$WORK/mut"; mkdir -p "$M" || exit 2

PRISTINE_GEN="$WORK/gen.pristine"
PRISTINE_RENDER="$WORK/render.pristine"
# MUTATE A COPY, NEVER THE TRACKED FILE. An earlier revision mutated
# `scripts/generate-kb-index.sh` in place -- the generator lefthook invokes on
# every commit touching knowledge-base/. Measured during review: a concurrent
# `--check` in this worktree returned a false "kb index artifacts are fresh"
# against a knowingly-stale file, because the generator was on disk mid-mutation
# with its failure branch neutered. The trap covers EXIT/INT/TERM/HUP; it cannot
# cover a SIGKILL, an OOM, or a concurrent reader.
#
# The copy replicates the directory shape: the generator sources
# `$SCRIPT_DIR/lib/kb-index-render.sh`, and `--check` re-execs `"$0" --out`.
SUT="$WORK/sut"
mkdir -p "$SUT/lib" || exit 2
GEN="$SUT/generate-kb-index.sh"
RENDER="$SUT/lib/kb-index-render.sh"
cp "$TRACKED_GEN" "$GEN"        || { printf 'FATAL: cp generator failed\n' >&2; exit 2; }
cp "$TRACKED_RENDER" "$RENDER"  || { printf 'FATAL: cp renderer failed\n' >&2; exit 2; }
chmod +x "$GEN"                 || { printf 'FATAL: chmod generator failed\n' >&2; exit 2; }
cp "$GEN" "$PRISTINE_GEN"       || { printf 'FATAL: cp generator failed\n' >&2; exit 2; }
cp "$RENDER" "$PRISTINE_RENDER" || { printf 'FATAL: cp renderer failed\n' >&2; exit 2; }
restore() {
  cp "$PRISTINE_GEN" "$GEN"       || { printf 'FATAL: restore generator failed\n' >&2; exit 2; }
  cp "$PRISTINE_RENDER" "$RENDER" || { printf 'FATAL: restore renderer failed\n' >&2; exit 2; }
}

# A RUNNABLE pristine generator, and it must REPLICATE THE DIRECTORY SHAPE.
# generate-kb-index.sh sources "$SCRIPT_DIR/lib/kb-index-render.sh", so a flat
# copy resolves to a non-existent path: the copy would fail to run and every row
# using it would report a spurious RED that is a missing-file crash rather than
# a caught defect -- a battery that looks perfect while testing nothing.
PRISTINE_TREE="$WORK/pristine"
mkdir -p "$PRISTINE_TREE/lib" || exit 2
cp "$PRISTINE_GEN"    "$PRISTINE_TREE/generate-kb-index.sh" || exit 2
chmod +x "$PRISTINE_TREE/generate-kb-index.sh" || exit 2
cp "$PRISTINE_RENDER" "$PRISTINE_TREE/lib/kb-index-render.sh" || exit 2
PRISTINE_RUNNABLE="$PRISTINE_TREE/generate-kb-index.sh"
trap 'restore; rm -rf "$WORK"' EXIT INT TERM HUP

# A fresh fixture corpus per probe call: the probe MUTATES artifacts, so a
# shared corpus would leak one property's corruption into the next.
build_corpus() {
  local kb="$1"
  rm -rf "$kb"
  mkdir -p "$kb/engineering" "$kb/project/learnings" "$kb/project/archive"
  printf '# Alpha\n' > "$kb/engineering/alpha.md"
  printf '# Beta\n'  > "$kb/project/beta.md"
  printf -- '---\ntags: [zeta-tag]\ncategory: zeta-cat\n---\n# L\n' > "$kb/project/learnings/l1.md"
  printf '# Archived\n' > "$kb/project/archive/old.md"
  KB_DIR="$kb" bash "$GEN" >/dev/null 2>&1
}
# Builds the corpus AND its artifacts with the PRISTINE generator, so a
# mutation to the installed generator's rules shows up as a difference rather
# than being applied to both sides of the comparison.
build_corpus_pristine() {
  local kb="$1"
  rm -rf "$kb"
  mkdir -p "$kb/engineering" "$kb/project/learnings" "$kb/project/archive"
  printf '# Alpha\n' > "$kb/engineering/alpha.md"
  printf '# Beta\n'  > "$kb/project/beta.md"
  printf -- '---\ntags: [zeta-tag]\ncategory: zeta-cat\n---\n# L\n' > "$kb/project/learnings/l1.md"
  printf '# Archived\n' > "$kb/project/archive/old.md"
  KB_DIR="$kb" bash "$PRISTINE_RUNNABLE" >/dev/null 2>&1
}

check() { KB_DIR="$1" bash "$GEN" --check >/dev/null 2>&1; }

PROBE_FAIL=0
probe_fail() { PROBE_FAIL=$((PROBE_FAIL + 1)); printf '      probe: %s\n' "$1" >> "$WORK/probe.log"; }

probe() {
  PROBE_FAIL=0
  : > "$WORK/probe.log"
  local kb="$WORK/kb"

  # Q1 — a freshly generated tree is clean. Without this the guard could pass
  # every corruption row below by simply always failing.
  build_corpus "$kb"
  check "$kb" || probe_fail "Q1 a freshly generated tree should be clean"

  # Q2 — a row DELETED from the index is caught. This is the shape the
  # unregistered driver produces: a side-picked resolve that drops rows.
  build_corpus "$kb"
  grep -v 'project/beta\.md' "$kb/INDEX.md" > "$kb/INDEX.md.t"
  mv "$kb/INDEX.md.t" "$kb/INDEX.md"
  check "$kb" && probe_fail "Q2 a dropped index row should be caught"

  # Q3 — a LYING header count is caught with every row still present. This is
  # the failure the default text merge produces when both sides add the same
  # NUMBER of files: identical count text, a clean line-merge, no marker.
  build_corpus "$kb"
  sed -i 's/^> Total files: .*/> Total files: 999/' "$kb/INDEX.md"
  check "$kb" && probe_fail "Q3 a wrong header count should be caught"

  # Q4 — a stale kb-tags.txt is caught.
  build_corpus "$kb"
  printf 'ghost-tag\n' >> "$kb/kb-tags.txt"
  check "$kb" && probe_fail "Q4 a stale kb-tags.txt should be caught"

  # Q5 — a stale kb-categories.txt is caught.
  build_corpus "$kb"
  printf 'ghost-cat\n' >> "$kb/kb-categories.txt"
  check "$kb" && probe_fail "Q5 a stale kb-categories.txt should be caught"

  # Q6 — TITLE DRIFT is caught: the file set is unchanged and every row is
  # present, so no count and no structural assertion moves. Only regenerating
  # sees it, which is the whole argument for a diff over a lint.
  build_corpus "$kb"
  printf '# Alpha Renamed\n' > "$kb/engineering/alpha.md"
  check "$kb" && probe_fail "Q6 title drift should be caught"

  # Q7 — --check must not MUTATE the tracked artifacts. A check that regenerates
  # in place reports clean forever and destroys the evidence it was asked about.
  build_corpus "$kb"
  sed -i 's/^> Total files: .*/> Total files: 999/' "$kb/INDEX.md"
  local before after
  before="$(cat "$kb/INDEX.md")"
  check "$kb" >/dev/null 2>&1
  after="$(cat "$kb/INDEX.md")"
  [[ "$before" == "$after" ]] || probe_fail "Q7 --check rewrote the artifact it was asked to inspect"

  # Q8 — --out writes a COMPLETE artifact set off to the side and touches
  # nothing tracked.
  build_corpus "$kb"
  local out="$WORK/out"
  rm -rf "$out"; mkdir -p "$out"
  KB_DIR="$kb" bash "$GEN" --out "$out" >/dev/null 2>&1
  local f
  for f in INDEX.md kb-tags.txt kb-categories.txt; do
    [[ -s "$out/$f" ]] || probe_fail "Q8 --out did not write $f"
    cmp -s "$out/$f" "$kb/$f" || probe_fail "Q8 --out $f differs from the tracked artifact on a clean tree"
  done

  # Q9 — GENERATOR RULE DRIFT is caught. Every property above regenerates the
  # corpus with whatever generator is currently installed, so a change to the
  # generator's OWN rules moves both sides of the comparison together and is
  # invisible: the row-eligibility mutation survived this battery until this
  # property existed. The real shape is an artifact committed under the OLD
  # rules meeting a generator carrying the NEW ones -- which is exactly the
  # merge-time divergence the driver documents as its honest limit, and the
  # reason this guard is a regeneration diff rather than a structural lint.
  build_corpus_pristine "$kb"
  check "$kb" || probe_fail "Q9 a tree generated by the pristine generator should still read clean"

  (( PROBE_FAIL == 0 ))
}

PASS=0; FAIL=0
declare -a RESULTS=()

printf '=== control (unmutated) ===\n'
if probe; then
  printf '  GREEN — baseline valid\n'
else
  printf 'FATAL: unmutated control is RED. Every row below would be meaningless.\n' >&2
  cat "$WORK/probe.log" >&2
  exit 2
fi

apply() {
  local id="$1" target="$2" expect="$3" desc="$4"
  restore
  if ! python3 "$M/$id.py" "$target" 2>"$WORK/mut.err"; then
    printf '  %-4s LANDING-FAILED (mutator errored: %s)\n' "$id" "$(tail -1 "$WORK/mut.err")"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return
  fi
  local pristine
  case "$target" in
    "$GEN")    pristine="$PRISTINE_GEN" ;;
    "$RENDER") pristine="$PRISTINE_RENDER" ;;
    *) printf '  %-4s FATAL: unknown target\n' "$id"; FAIL=$((FAIL+1)); return ;;
  esac
  if diff -q "$pristine" "$target" >/dev/null 2>&1; then
    printf '  %-4s LANDING-FAILED (file unchanged) — %s\n' "$id" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id LANDING-FAILED"); return
  fi
  local got
  if probe; then got="GREEN"; else got="RED"; fi
  if [[ "$got" == "$expect" ]]; then
    printf '  %-4s %-5s (want %-5s) ok       — %s\n' "$id" "$got" "$expect" "$desc"
    PASS=$((PASS+1)); RESULTS+=("$id ok")
  else
    printf '  %-4s %-5s (want %-5s) SURVIVED — %s\n' "$id" "$got" "$expect" "$desc"
    FAIL=$((FAIL+1)); RESULTS+=("$id SURVIVED")
  fi
}

# --- mutators (quoted heredocs disable every bash expansion inside) ------------

cat > "$M/C1.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '''  if [[ "$_check_rc" -ne 0 ]]; then
    echo "Run: bash scripts/generate-kb-index.sh" >&2
    exit 1
  fi'''
assert old in s, "C1 anchor missing"
open(p, 'w').write(s.replace(old, '  :', 1))
MUT

cat > "$M/C2.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '      _check_rc=1'
assert old in s, "C2 anchor missing"
open(p, 'w').write(s.replace(old, '      _check_rc=0', 1))
MUT

cat > "$M/C3.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  for _f in INDEX.md kb-tags.txt kb-categories.txt; do'
assert old in s, "C3 anchor missing"
open(p, 'w').write(s.replace(old, '  for _f in kb-tags.txt kb-categories.txt; do', 1))
MUT

cat > "$M/C4.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  for _f in INDEX.md kb-tags.txt kb-categories.txt; do'
assert old in s, "C4 anchor missing"
open(p, 'w').write(s.replace(old, '  for _f in INDEX.md kb-categories.txt; do', 1))
MUT

cat > "$M/C5.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  for _f in INDEX.md kb-tags.txt kb-categories.txt; do'
assert old in s, "C5 anchor missing"
open(p, 'w').write(s.replace(old, '  for _f in INDEX.md kb-tags.txt; do', 1))
MUT

cat > "$M/C6.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '  "$0" --out "$_check_dir" >/dev/null'
assert old in s, "C6 anchor missing"
# Regenerate IN PLACE first: the check then always compares a file with itself
# and reports clean forever, having destroyed the evidence it was asked about.
open(p, 'w').write(s.replace(old, '  "$0" >/dev/null; "$0" --out "$_check_dir" >/dev/null', 1))
MUT

cat > "$M/C7.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'if ! cmp -s "$KB_DIR/$_f" "$_check_dir/$_f"; then'
assert old in s, "C7 anchor missing"
# Compare the committed artifact against ITSELF -- vacuously clean.
open(p, 'w').write(s.replace(old, 'if ! cmp -s "$KB_DIR/$_f" "$KB_DIR/$_f"; then', 1))
MUT

cat > "$M/C8.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'if [[ "$CHECK" == 1 ]]; then'
assert old in s, "C8 anchor missing"
# The flag parses and is accepted, and nothing dispatches on it. A silent no-op
# that exits 0 is the worst shape this guard can take.
open(p, 'w').write(s.replace(old, 'if [[ "$CHECK" == 2 ]]; then', 1))
MUT

cat > "$M/C9.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = '''  INDEX_FILE="$OUT_DIR/INDEX.md"
  TAGS_FILE="$OUT_DIR/kb-tags.txt"
  CATEGORIES_FILE="$OUT_DIR/kb-categories.txt"'''
assert old in s, "C9 anchor missing"
# --out redirects only the index, so the facet files are written over the
# TRACKED artifacts -- which both corrupts the tree and makes the facet
# comparisons vacuous.
open(p, 'w').write(s.replace(old, '  INDEX_FILE="$OUT_DIR/INDEX.md"', 1))
MUT

cat > "$M/C10.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = "  printf '> Total files: %s\\n' \"$total\""
assert old in s, "C10 anchor missing"
# RENDERER DRIFT with the generator pristine: a fresh generation stops matching
# the committed artifact. Only a regeneration diff can see this.
open(p, 'w').write(s.replace(old, "  printf '> Indexed files: %s\\n' \"$total\"", 1))
MUT

cat > "$M/C11.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
old = "    -not -path '*/archive/*' \\\n"
assert old in s, "C11 anchor missing"
# ROW-ELIGIBILITY DRIFT: archived files start being indexed. A structural lint
# that re-implemented the predicate would agree with the drift and stay green;
# a regeneration diff cannot.
open(p, 'w').write(s.replace(old, "", 1))
MUT

cat > "$M/H1.py" <<'MUT'
import sys
p = sys.argv[1]; s = open(p).read()
# HARNESS SELF-TEST. Gut the generator's facet-extraction arm so a fresh
# generation must differ from any previously-committed one. A probe still
# reporting GREEN here is comparing nothing, and every row above it is void.
old = '  { grep $\'^tag\\t\' "$facets_tmp" || true; } | cut -f2 | LC_ALL=C sort -u > "$TAGS_FILE.tmp.$$"'
assert old in s, "H1 anchor missing"
open(p, 'w').write(s.replace(old, '  : > "$TAGS_FILE.tmp.$$"', 1))
MUT

printf '=== --check dispatch and comparison set ===\n'
apply C1  "$GEN" RED '--check always exits 0'
apply C2  "$GEN" RED 'the per-file diff result is discarded'
apply C3  "$GEN" RED 'INDEX.md is dropped from the compared set'
apply C4  "$GEN" RED 'kb-tags.txt is dropped from the compared set'
apply C5  "$GEN" RED 'kb-categories.txt is dropped from the compared set'
apply C6  "$GEN" RED '--check regenerates OVER the tracked artifacts first'
apply C7  "$GEN" RED '--out is ignored: the file is diffed against itself'
apply C8  "$GEN" RED '--check is accepted but never dispatched'
apply C9  "$GEN" RED '--out redirects only INDEX.md, writing facets over the tree'

printf '=== drift the guard exists to catch ===\n'
apply C10 "$RENDER" RED 'the renderer header drifts while the generator stays pristine'
apply C11 "$GEN"    RED 'row eligibility drifts — archived files start being indexed'

printf '=== harness self-test ===\n'
apply H1  "$GEN" RED 'facet extraction is gutted — a fresh generation must differ'

restore
printf '\n=== summary ===\n'
printf '  %d ok, %d problem(s)\n' "$PASS" "$FAIL"
for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done

# Reported by direct printf and its OWN exit, never through the FAIL counter the
# rows above increment: a floor that shares a lifetime with what it guards is
# not a floor.
EXPECTED_ROWS=12
if (( PASS + FAIL != EXPECTED_ROWS )); then
  printf 'FLOOR: ran %d rows, expected %d\n' "$((PASS+FAIL))" "$EXPECTED_ROWS" >&2
  exit 1
fi
if ! diff -q "$PRISTINE_GEN" "$GEN" >/dev/null 2>&1 \
   || ! diff -q "$PRISTINE_RENDER" "$RENDER" >/dev/null 2>&1; then
  printf 'FLOOR: restore did not return the tree to pristine\n' >&2
  exit 1
fi
printf '  restore verified clean (copies under %s; the tracked files were never written)\n' "$SUT" 
if (( FAIL > 0 )); then exit 1; fi
exit 0
