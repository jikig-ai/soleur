#!/usr/bin/env bash
# Suite for .github/scripts/check-workflow-duplicate-keys.py (Ref #12283, #9927).
#
# The guard is the strict duplicate-key parse that runs as the `workflow-duplicate-keys` member
# step of the required `quality-guards` umbrella (pr-quality-guards.yml). It exists because a
# merge candidate whose ci.yml carried two `fetch-depth` keys in one `with:` mapping merged
# cleanly in git, failed to load in GitHub Actions, and stalled the merge queue for 175 minutes.
#
# BASH-ONLY per the run-all.sh CONTRACT (#6454): PyYAML via python3, no terraform / apt / network.
# Fixtures are SYNTHESIZED under mktemp -d (cq-test-fixtures-synthesized-only); the guard takes a
# root path, so every fixture is a tiny `.github/` tree. No literal file count is asserted
# anywhere: counts are compared with an independent enumerator (`find` on a fixture, `git ls-files`
# on the real tree).
#
# SHAPE
#   battery <guard>   drives the guard over the fixture trees and records one verdict per row id in
#                     BAT_RES (ok | reason). It is a pure function of the guard path, so the SAME
#                     battery runs against the real guard (rows must be green) and against sandbox
#                     copies carrying one literal mutation each (some row must go RED, and the RED
#                     row must be the NAMED one).
#   wiring_check <yml> structural rows over pr-quality-guards.yml (member step, aggregate row).
#                     Mutated on a sandbox copy of the workflow (lint-umbrella-aggregate.sh reads
#                     the repo's hard-coded path and cannot be pointed at a copy; it independently
#                     guards the real file in CI).
#   Five control rows prove the mutation helper itself fails when it should: mutation did not land,
#   guard stayed GREEN, RED for the wrong reason (the named row does not exist), mutant does not
#   compile, and clean-path rows crash under the mutant. A mutant counts as KILLED only when it
#   compiles, a NAMED row goes RED, and the clean-path rows (B2, B10) stay GREEN: a crashed guard
#   fails every row and proves nothing. Mutation batteries evaluate only the named rows plus the
#   clean-path rows (the kill criterion is unchanged; the real-tree row runs once, not per mutant).
#
# MUTATION MATRIX (Guard 1) -- M1 strict collector swapped for yaml.safe_load (last-wins), M2 zero
# files exit-2 arm removed, M3 raise-first across files, M3b raise-first within a file, M4a/M4b
# extension coverage narrowed, M5 line off by one, M6a-g member wiring (strip !cancelled(), drop the
# aggregate row, append || true, add continue-on-error, drop merge_group, aggregate reads outcome,
# drop python3 -I), M7a-c fail-closed arms neutered, M8 missing-PyYAML exit-2 arm, M9 pure-python
# seam, M10a-d key identity (no ASCII fold, full upper(), merge-key skip, non-scalar keys), M11a/b
# case-sensitive suffix/action names, M12a/b isfile gate / directory gate, M13 recursion into
# workflows/, M14 default root, M15 pyyaml= field, M16-M18 walker cardinality (first sequence item
# only, stop after first repeat, first-at drift), M19 annotation escaping, M20 strict stdout.
# Non-battery rows: R1/R2 real-tree no-argument runs, T1/T1c composite-action tripwire (+ control),
# W1/W1m GITHUB_SCRIPTS_SUITE_PATHS still names .github (+ mutation).
# The exact pass floor sits at the bottom, a literal adjacent to its `if`.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GUARD_REAL="$REPO_ROOT/.github/scripts/check-workflow-duplicate-keys.py"
WF_REAL="$REPO_ROOT/.github/workflows/pr-quality-guards.yml"

passes=0; fails=0; skips=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# Instrument self-test: both verdict helpers must record before anything is trusted.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

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

case "$REPO_ROOT" in
  "")      echo "FATAL: REPO_ROOT is empty; refusing" >&2; exit 2 ;;
  /|//|/.) echo "FATAL: REPO_ROOT resolves to the filesystem root; refusing" >&2; exit 2 ;;
  /*)      : ;;
  *)       echo "FATAL: REPO_ROOT is RELATIVE; refusing" >&2; exit 2 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "[FATAL] python3 not found" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "[FATAL] PyYAML is required" >&2; exit 2; }

# The file under test is repo-owned: its absence is a RED suite, not an environment problem.
if [[ ! -f "$GUARD_REAL" ]]; then
  echo "[FAIL] guard not found at $GUARD_REAL -- every row below would assert nothing" >&2
  exit 1
fi

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
FX="$WORK/fx"; assert_fixture_dir "$FX"; mkdir -p "$FX" || exit 2
SB="$WORK/sandbox"; assert_fixture_dir "$SB"; mkdir -p "$SB" || exit 2

# ---- fixture helpers ---------------------------------------------------------------------------
# mk_root <name> -> sets ROOT to a fresh absolute fixture root (guarded in THIS shell, never in $(...)).
ROOT=""
mk_root() {
  ROOT="$FX/$1"; assert_fixture_dir "$ROOT"
  mkdir -p "$ROOT" || exit 2
}
# put <root> <relpath>   (content on stdin)
put() {
  local r="$1" rel="$2"
  assert_fixture_dir "$r"
  mkdir -p "$r/$(dirname "$rel")" || exit 2
  cat > "$r/$rel"
}
# Independent enumerator for fixture trees (the guard's own glob is NOT used).
count_fx() {
  local r="$1" a b
  a="$(find "$r/.github/workflows" -maxdepth 1 -type f \( -iname '*.yml' -o -iname '*.yaml' \) 2>/dev/null | wc -l)"
  b="$(find "$r/.github/actions" -type f \( -iname action.yml -o -iname action.yaml \) 2>/dev/null | wc -l)"
  echo $((a + b))
}
# nth_line <file> <regex> <n> -> line number of the n-th match (independent of the guard).
nth_line() { awk -v re="$2" -v n="$3" '$0 ~ re { c++; if (c == n) { print NR; exit } }' "$1"; }

run_guard() { # <guard> <root> [VAR=val ...] -> G_OUT (stdout+stderr), G_RC
  local g="$1" r="$2"; shift 2
  G_OUT="$(env "$@" timeout 60 python3 "$g" "$r" 2>&1)"; G_RC=$?
}

# ---- fixtures ----------------------------------------------------------------------------------
# B1: the incident shape -- two fetch-depth keys in one nested `with:` mapping.
mk_root inc; R_INC="$ROOT"
put "$R_INC" .github/workflows/ci.yml <<'EOF'
name: CI
on:
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-depth: 1
      - run: echo done
EOF
INC_L1="$(nth_line "$R_INC/.github/workflows/ci.yml" 'fetch-depth' 1)"
INC_L2="$(nth_line "$R_INC/.github/workflows/ci.yml" 'fetch-depth' 2)"

# B2: clean tree (workflow + yaml workflow + composite action).
mk_root clean; R_CLEAN="$ROOT"
put "$R_CLEAN" .github/workflows/ci.yml <<'EOF'
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
EOF
put "$R_CLEAN" .github/workflows/other.yaml <<'EOF'
name: Other
on: [push]
jobs: {}
EOF
put "$R_CLEAN" .github/actions/setup/action.yml <<'EOF'
name: setup
runs:
  using: composite
  steps:
    - run: echo hi
      shell: bash
EOF

# B3: two duplicates in one file.
mk_root two; R_TWO="$ROOT"
put "$R_TWO" .github/workflows/two.yml <<'EOF'
name: Two
on: [push]
jobs:
  a:
    runs-on: ubuntu-latest
    env:
      FOO: 1
      FOO: 2
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-depth: 1
EOF

# B4: three files, clean first, duplicates in the 2nd and 3rd.
mk_root three; R_THREE="$ROOT"
put "$R_THREE" .github/workflows/a-clean.yml <<'EOF'
name: A
on: [push]
jobs: {}
EOF
put "$R_THREE" .github/workflows/b-dup.yml <<'EOF'
name: B
on: [push]
name: B2
jobs: {}
EOF
put "$R_THREE" .github/workflows/c-dup.yml <<'EOF'
name: C
on: [push]
jobs:
  j:
    runs-on: x
    runs-on: y
EOF

# B5: .yaml workflow and a deep action.yaml, each with a duplicate.
mk_root ext; R_EXT="$ROOT"
put "$R_EXT" .github/workflows/w.yaml <<'EOF'
name: W
on: [push]
jobs: {}
jobs: {}
EOF
put "$R_EXT" .github/actions/deep/er/action.yaml <<'EOF'
name: deep
name: deeper
runs:
  using: composite
  steps: []
EOF

# B6: flow-mapping duplicate; B6q: quote style does not hide a duplicate.
mk_root flow; R_FLOW="$ROOT"
put "$R_FLOW" .github/workflows/flow.yml <<'EOF'
name: F
on: [push]
vars: {a: 1, a: 2}
jobs: {}
EOF
mk_root quote; R_QUOTE="$ROOT"
put "$R_QUOTE" .github/workflows/q.yml <<'EOF'
name: Q
on: [push]
m:
  "a": 1
  a: 2
jobs: {}
EOF

# B7: fail closed -- unparseable (tab indentation), multi-document, non-mapping top level, empty.
mk_root unp; R_UNP="$ROOT"
printf 'name: U\njobs:\n\tbad: 1\n' | put "$R_UNP" .github/workflows/u.yml
mk_root multi; R_MULTI="$ROOT"
printf 'name: M\non: [push]\n---\nname: M2\non: [push]\n' | put "$R_MULTI" .github/workflows/m.yml
mk_root nonmap; R_NONMAP="$ROOT"
printf -- '- a\n- b\n' | put "$R_NONMAP" .github/workflows/n.yml
mk_root empty; R_EMPTY="$ROOT"
: | put "$R_EMPTY" .github/workflows/e.yml

# B8: environment -- no .github at all, an empty workflows dir, and a missing root.
mk_root noroot; R_NOROOT="$ROOT"
mk_root nowf; R_NOWF="$ROOT"
mkdir -p "$R_NOWF/.github/workflows" || exit 2
R_MISSING="$FX/does-not-exist"; assert_fixture_dir "$R_MISSING"

# B10: must-PASS corpus that is NOT the canonical clean tree.
mk_root pass; R_PASS="$ROOT"
put "$R_PASS" .github/workflows/sibling.yml <<'EOF'
name: S
on: [push]
jobs:
  one:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/checkout@v4
        with:
          fetch-depth: 1
  two:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
EOF
put "$R_PASS" .github/workflows/flowok.yml <<'EOF'
name: F
on: [push]
vars: {k: 1, j: 2}
list: [{k: 1}, {k: 2}]
jobs: {}
EOF
put "$R_PASS" .github/workflows/merge.yml <<'EOF'
name: Merge
on: [push]
base: &b
  a: 1
  b: 2
derived:
  <<: *b
  a: 2
jobs: {}
EOF
put "$R_PASS" .github/workflows/onkey.yml <<'EOF'
name: On
on:
  push:
    branches: [main]
jobs: {}
EOF
put "$R_PASS" .github/workflows/multiline.yml <<'EOF'
name: ML
on: [push]
jobs:
  j:
    runs-on: x
    steps:
      - run: |
          key: 1
          key: 2
EOF
printf 'name: CRLF\r\non: [push]\r\njobs:\r\n  j:\r\n    runs-on: x\r\n' | put "$R_PASS" .github/workflows/crlf.yml
put "$R_PASS" .github/workflows/alias.yml <<'EOF'
name: Alias
on: [push]
a: &x {k: 1}
b: *x
c: *x
d: [*x, *x]
jobs: {}
EOF
put "$R_PASS" .github/workflows/cycle.yml <<'EOF'
name: Cycle
on: [push]
loop: &c [*c]
jobs: {}
EOF
put "$R_PASS" .github/workflows/intbool.yml <<'EOF'
name: IntBool
on: [push]
m:
  1: a
  true: b
  "2": c
jobs: {}
EOF
put "$R_PASS" .github/actions/ok/action.yml <<'EOF'
name: ok
runs:
  using: composite
  steps: []
EOF

# B13: key identity is GitHub's, not YAML's (D13): the key TEXT with ASCII letters folded to upper case.
mk_root keycase; R_KEYCASE="$ROOT"
put "$R_KEYCASE" .github/workflows/kc.yml <<'EOF'
name: KC
on: [push]
m:
  Fetch-Depth: 0
  fetch-depth: 1
jobs: {}
EOF
KC_L1="$(nth_line "$R_KEYCASE/.github/workflows/kc.yml" 'Fetch-Depth' 1)"
KC_L2="$(nth_line "$R_KEYCASE/.github/workflows/kc.yml" 'fetch-depth' 1)"
# B14: `on` and `true` are one bool to YAML but two different strings to GitHub: clean.
mk_root ontrue; R_ONTRUE="$ROOT"
put "$R_ONTRUE" .github/workflows/ot.yml <<'EOF'
name: OT
m:
  on: 1
  true: 2
jobs: {}
EOF
# B15: the merge key is an ordinary key: a second `<<` in one mapping is a repeat.
mk_root twomerge; R_TWOMERGE="$ROOT"
put "$R_TWOMERGE" .github/workflows/tm.yml <<'EOF'
name: TM
on: [push]
base: &b {a: 1}
other: &o {c: 3}
twice:
  <<: *b
  <<: *o
jobs: {}
EOF
TM_L1="$(nth_line "$R_TWOMERGE/.github/workflows/tm.yml" '^  <<:' 1)"
TM_L2="$(nth_line "$R_TWOMERGE/.github/workflows/tm.yml" '^  <<:' 2)"
# B15n: non-scalar (complex) keys are skipped, not crashed on, not compared.
mk_root nonscalar; R_NONSCALAR="$ROOT"
put "$R_NONSCALAR" .github/workflows/ns.yml <<'EOF'
name: NS
on: [push]
m:
  ? [a, b]
  : 1
  ? [a, b]
  : 2
jobs: {}
EOF
# B16: the fold is ASCII-only (.NET OrdinalIgnoreCase does not equate these; Python .upper() does).
mk_root nofold; R_NOFOLD="$ROOT"
put "$R_NOFOLD" .github/workflows/nf.yml <<'EOF'
name: NF
on: [push]
m:
  "ß": 1
  "SS": 2
n:
  "ı": 1
  "i": 2
jobs: {}
EOF

# B17: enumeration (D14): upper-case suffixes are reached; a dangling symlink is a finding; a
# directory named like a workflow and a subdirectory of workflows/ are not scanned.
mk_root upper; R_UPPER="$ROOT"
put "$R_UPPER" .github/workflows/UP.YML <<'EOF'
name: Up
on: [push]
name: Up2
jobs: {}
EOF
put "$R_UPPER" .github/actions/x/ACTION.YAML <<'EOF'
name: x
name: y
runs:
  using: composite
  steps: []
EOF
mk_root dangling; R_DANG="$ROOT"
put "$R_DANG" .github/workflows/ok.yml <<'EOF'
name: Ok
on: [push]
jobs: {}
EOF
ln -s nowhere.yml "$R_DANG/.github/workflows/x.yml" || exit 2
mk_root subdir; R_SUB="$ROOT"
put "$R_SUB" .github/workflows/ok.yml <<'EOF'
name: Ok
on: [push]
jobs: {}
EOF
put "$R_SUB" .github/workflows/sub/nested.yml <<'EOF'
name: Nested
name: Twice
EOF
mkdir -p "$R_SUB/.github/workflows/dir.yml" || exit 2

# B3b/B3c/B3d: walker cardinality -- a duplicate in step 2 AND step 3 (never only the first or last
# item), two repeats inside ONE mapping, a triple, and annotation escaping of key and path text.
mk_root walk; R_WALK="$ROOT"
put "$R_WALK" .github/workflows/walk.yml <<'EOF'
name: W
on: [push]
jobs:
  j:
    runs-on: x
    steps:
      - uses: a/one@v1
        with:
          k: 0
      - uses: a/two@v1
        with:
          fetch-depth: 0
          fetch-depth: 1
      - uses: a/three@v1
        with:
          depth: 0
          depth: 1
EOF
WALK_L1="$(nth_line "$R_WALK/.github/workflows/walk.yml" 'fetch-depth' 1)"
WALK_L2="$(nth_line "$R_WALK/.github/workflows/walk.yml" 'fetch-depth' 2)"
WALK_D1="$(nth_line "$R_WALK/.github/workflows/walk.yml" '^          depth:' 1)"
WALK_D2="$(nth_line "$R_WALK/.github/workflows/walk.yml" '^          depth:' 2)"
mk_root multidup; R_MULTIDUP="$ROOT"
put "$R_MULTIDUP" .github/workflows/md.yml <<'EOF'
name: MD
on: [push]
m:
  a: 1
  a: 2
  b: 1
  b: 2
t:
  c: 1
  c: 2
  c: 3
jobs: {}
EOF
MD_A1="$(nth_line "$R_MULTIDUP/.github/workflows/md.yml" '^  a:' 1)"; MD_A2="$(nth_line "$R_MULTIDUP/.github/workflows/md.yml" '^  a:' 2)"
MD_B1="$(nth_line "$R_MULTIDUP/.github/workflows/md.yml" '^  b:' 1)"; MD_B2="$(nth_line "$R_MULTIDUP/.github/workflows/md.yml" '^  b:' 2)"
MD_C1="$(nth_line "$R_MULTIDUP/.github/workflows/md.yml" '^  c:' 1)"; MD_C2="$(nth_line "$R_MULTIDUP/.github/workflows/md.yml" '^  c:' 2)"
MD_C3="$(nth_line "$R_MULTIDUP/.github/workflows/md.yml" '^  c:' 3)"
mk_root esc; R_ESC="$ROOT"
put "$R_ESC" '.github/workflows/sp:ec,ial.yml' <<'EOF'
name: E
on: [push]
m:
  "p%q": 1
  "p%q": 2
  "n\nm": 1
  "n\nm": 2
jobs: {}
EOF
# B21: a non-ASCII duplicate key must still produce its annotation under an ASCII-only stdout.
mk_root enc; R_ENC="$ROOT"
put "$R_ENC" .github/workflows/enc.yml <<'EOF'
name: Enc
on: [push]
m:
  "é": 1
  "é": 2
jobs: {}
EOF

PYYAML_VER="$(python3 -c 'import yaml; print(yaml.__version__)')"

# PyYAML-less interpreter shim for B9: a `yaml` package that refuses to import, ahead of site-packages.
SHIM="$WORK/noyaml"; assert_fixture_dir "$SHIM"; mkdir -p "$SHIM/yaml" || exit 2
printf 'raise ImportError("PyYAML deliberately blocked by the suite")\n' > "$SHIM/yaml/__init__.py"

EXPECT_LOADER="py"
python3 -c 'import sys, yaml; sys.exit(0 if hasattr(yaml, "CSafeLoader") else 1)' 2>/dev/null && EXPECT_LOADER="c"

# ---- the battery -------------------------------------------------------------------------------
declare -A BAT_RES
declare -A BAT_DESC
BAT_IDS=(B1 B1p B2 B3 B3b B3c B3d B4 B5 B6 B6q B7 B7m B7n B7e B8 B8w B8m B9 B10 B10s B12 B13 B14 B15 B15n B16 B17 B17d B19 B20 B21)
CLEAN_IDS=(B2 B10)   # clean-path rows: they must stay GREEN under any mutant, or the mutant crashed
BAT_DESC[B1]="nested with: fetch-depth x2 -> rc 1, file/line/col/first-line, FAIL summary, loader=$EXPECT_LOADER"
BAT_DESC[B1p]="same fixture under WFDK_PURE_PYTHON=1 -> rc 1, same line, loader=py"
BAT_DESC[B2]="clean tree -> rc 0, OK summary, files= equals an independent find count"
BAT_DESC[B3]="two duplicates in one file -> both reported"
BAT_DESC[B4]="clean, dup, dup across three files -> both dup files reported, clean file silent"
BAT_DESC[B5]=".yaml workflow and deep action.yaml duplicates -> both reported (extension coverage)"
BAT_DESC[B6]="flow-mapping duplicate -> rc 1"
BAT_DESC[B6q]="quoted and plain spelling of one key collide -> rc 1"
BAT_DESC[B7]="unparseable file (tab indentation) -> rc 1, unparseable=1, path named"
BAT_DESC[B7m]="multi-document file -> rc 1 (fail closed)"
BAT_DESC[B7n]="non-mapping top level -> rc 1 (fail closed)"
BAT_DESC[B7e]="empty file -> rc 1 (fail closed)"
BAT_DESC[B8]="root with no .github -> rc 2"
BAT_DESC[B8w]="empty .github/workflows (zero files scanned) -> rc 2, never OK"
BAT_DESC[B8m]="root path that does not exist -> rc 2"
BAT_DESC[B9]="PyYAML not importable -> rc 2, no pip fallback"
BAT_DESC[B10]="must-PASS corpus (sibling keys, flow, << with override, on, multiline, CRLF, aliases, cycle, 1/true/2) -> rc 0"
BAT_DESC[B12]="real tree -> rc 0, OK, files= equals git ls-files count (SKIP outside a git work tree)"
BAT_DESC[B3b]="duplicates in step 2 AND step 3 of one steps: list -> both reported (the walk reaches every sequence item)"
BAT_DESC[B3c]="a,a,b,b in ONE mapping and a triple c,c,c -> 4 findings, each repeat names the FIRST line"
BAT_DESC[B3d]="key and file name with % : , newline -> escaped in the annotation (%25 %3A %2C %0A)"
BAT_DESC[B10s]="workflows/ subdirectory and a directory named dir.yml are not scanned -> rc 0, files= equals find count"
BAT_DESC[B13]="Fetch-Depth vs fetch-depth in one mapping -> flagged, under BOTH loaders"
BAT_DESC[B14]="on vs true in one mapping -> clean (distinct strings to GitHub), under BOTH loaders"
BAT_DESC[B15]="two << keys in one mapping -> flagged (the merge key is an ordinary key), under BOTH loaders"
BAT_DESC[B15n]="non-scalar keys repeated -> skipped, clean, under BOTH loaders"
BAT_DESC[B16]="sharp-s vs SS and dotless-i vs i -> clean (ASCII-only fold), under BOTH loaders"
BAT_DESC[B17]="upper-case .YML workflow and ACTION.YAML action with duplicates -> both flagged, files= equals icase find count"
BAT_DESC[B17d]="dangling symlink x.yml in workflows/ -> rc 1, unparseable finding naming it (never skipped)"
BAT_DESC[B19]="NO-argument default root (as CI runs it) from the root and from a subdirectory cwd -> OK, files= equals find count"
BAT_DESC[B20]="OK and FAIL summary lines carry pyyaml=<yaml.__version__>"
BAT_DESC[B21]="non-ASCII duplicate key under an ASCII-only stdout -> annotation still printed, no traceback"

# Real-tree enumerator pathspecs, ALL case-insensitive (the guard matches suffixes and action names
# case-insensitively, D14); the independent count must use the same breadth.
LS_PATHSPECS=(':(icase,glob).github/workflows/*.yml' ':(icase,glob).github/workflows/*.yaml'
              ':(icase,glob).github/actions/**/action.yml' ':(icase,glob).github/actions/**/action.yaml')

b_ok() { BAT_RES["$1"]="ok"; }
b_no() { BAT_RES["$1"]="$2"; }
snip() { printf '%s' "${G_OUT:0:240}" | tr '\n' '|'; }

real_ls_count() { # independent enumerator of the real tree: tracked files that exist on disk
  local f n=0
  while IFS= read -r -d '' f; do
    [[ -f "$REPO_ROOT/$f" ]] && n=$((n + 1))
  done < <(git -C "$REPO_ROOT" ls-files -z -- "${LS_PATHSPECS[@]}")
  echo "$n"
}
# stray_actions <repo>: tracked action.yml/action.yaml (any case) OUTSIDE .github/actions. The guard
# scans only .github/actions for composite actions (D14 residual); this is its tripwire.
stray_actions() {
  git -C "$1" ls-files -z -- ':(icase,glob)**/action.yml' ':(icase,glob)**/action.yaml' | tr '\0' '\n' | grep -v '^\.github/actions/'
  return 0
}
# paths_has_github <file>: does GITHUB_SCRIPTS_SUITE_PATHS still name `.github` (the relevance gate
# that makes run-all.sh, hence this suite and its real-tree row, run on a workflow-only diff)?
paths_has_github() {
  awk '/^GITHUB_SCRIPTS_SUITE_PATHS=\(/ { inb = 1; next } inb && /^\)/ { inb = 0 } inb' "$1" \
    | grep -qE '^[[:space:]]+"\.github"([[:space:]]|$)'
}

# Predicates over G_RC/G_OUT for the rows that run under BOTH loaders.
p_clean() { [[ "$G_RC" -eq 0 && "$G_OUT" == *"workflow-duplicate-keys=OK "* && "$G_OUT" != *"::error"* ]]; }
p_keycase() { [[ "$G_RC" -eq 1 && "$G_OUT" == *"line=$KC_L2,col=3::duplicate key 'fetch-depth' (first at line $KC_L1)"* && "$G_OUT" == *"duplicates=1"* ]]; }
p_twomerge() { [[ "$G_RC" -eq 1 && "$G_OUT" == *"line=$TM_L2,col=3::duplicate key '<<' (first at line $TM_L1)"* && "$G_OUT" == *"duplicates=1"* ]]; }
check_both() { # <row> <guard> <root> <predicate>: the predicate must hold under the C loader AND the pure one
  local id="$1" g="$2" r="$3" pred="$4" lv extra
  for lv in default pure; do
    extra=(); [[ "$lv" == "pure" ]] && extra=(WFDK_PURE_PYTHON=1)
    run_guard "$g" "$r" "${extra[@]}"
    if ! "$pred"; then b_no "$id" "loader=$lv rc=$G_RC out=$(snip)"; return 0; fi
  done
  b_ok "$id"
}

# noarg_layout <guard>: lay a synthesized repo out around a COPY of the guard at
# .github/scripts/check-workflow-duplicate-keys.py and run it with NO argument, exactly as CI does, from
# the root, from a subdirectory and from an unrelated cwd. Sets NOARG_OK (1/0) and NOARG_WHY.
NOARG_OK=0; NOARG_WHY=""
noarg_layout() {
  local g="$1" r="$FX/noarg" cwd n out rc
  assert_fixture_dir "$r"; rm -rf "$r"; mkdir -p "$r/.github/scripts" || exit 2
  cp "$g" "$r/.github/scripts/check-workflow-duplicate-keys.py" || exit 2
  put "$r" .github/workflows/ci.yml <<'EOF'
name: CI
on: [push]
jobs: {}
EOF
  put "$r" .github/actions/setup/action.yml <<'EOF'
name: setup
runs:
  using: composite
  steps: []
EOF
  n="$(count_fx "$r")"; NOARG_OK=0
  for cwd in "$r" "$r/.github/scripts" "$WORK"; do
    if [[ "$cwd" == "$r" ]]; then
      out="$(cd "$cwd" && timeout 60 python3 .github/scripts/check-workflow-duplicate-keys.py 2>&1)"; rc=$?
    else
      out="$(cd "$cwd" && timeout 60 python3 "$r/.github/scripts/check-workflow-duplicate-keys.py" 2>&1)"; rc=$?
    fi
    if [[ "$rc" -ne 0 || "$out" != *"workflow-duplicate-keys=OK files=$n "* ]]; then
      NOARG_WHY="cwd=$cwd rc=$rc want files=$n out=${out:0:200}"; return 0
    fi
  done
  NOARG_OK=1
}

sel() { [[ -z "${SEL:-}" || " $SEL " == *" $1 "* ]]; }   # row selected? (SEL is battery()'s dynamic local)

battery() { # <guard> [row ids to evaluate; default all]
  local g="$1" id n want pv_ok pv_rc SEL="${2:-}"
  for id in "${BAT_IDS[@]}"; do BAT_RES["$id"]="not run"; done
  if sel B1; then
    run_guard "$g" "$R_INC"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/ci.yml,line=$INC_L2,col=11::duplicate key 'fetch-depth' (first at line $INC_L1)"* \
          && "$G_OUT" == *"workflow-duplicate-keys=FAIL"* && "$G_OUT" == *"duplicates=1"* && "$G_OUT" == *"loader=$EXPECT_LOADER"* ]]; then
      b_ok B1; else b_no B1 "rc=$G_RC want line=$INC_L2 first=$INC_L1 out=$(snip)"; fi
  fi

  if sel B1p; then
    run_guard "$g" "$R_INC" WFDK_PURE_PYTHON=1
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"line=$INC_L2,col=11::duplicate key 'fetch-depth'"* && "$G_OUT" == *"loader=py"* ]]; then
      b_ok B1p; else b_no B1p "rc=$G_RC want loader=py line=$INC_L2 out=$(snip)"; fi
  fi

  if sel B2; then
    run_guard "$g" "$R_CLEAN"
    n="$(count_fx "$R_CLEAN")"
    if [[ "$G_RC" -eq 0 && "$G_OUT" == *"workflow-duplicate-keys=OK files=$n "* && "$G_OUT" != *"::error"* ]]; then
      b_ok B2; else b_no B2 "rc=$G_RC want files=$n out=$(snip)"; fi
  fi

  if sel B3; then
    run_guard "$g" "$R_TWO"
    n="$(printf '%s\n' "$G_OUT" | grep -c "^::error file=.github/workflows/two.yml,line=.*::duplicate key")"
    if [[ "$G_RC" -eq 1 && "$n" -eq 2 && "$G_OUT" == *"duplicate key 'FOO'"* && "$G_OUT" == *"duplicate key 'fetch-depth'"* && "$G_OUT" == *"duplicates=2"* ]]; then
      b_ok B3; else b_no B3 "rc=$G_RC findings=$n out=$(snip)"; fi
  fi

  if sel B3b; then
    run_guard "$g" "$R_WALK"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"line=$WALK_L2,col=11::duplicate key 'fetch-depth' (first at line $WALK_L1)"* \
          && "$G_OUT" == *"line=$WALK_D2,col=11::duplicate key 'depth' (first at line $WALK_D1)"* && "$G_OUT" == *"duplicates=2"* ]]; then
      b_ok B3b; else b_no B3b "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B3c; then
    run_guard "$g" "$R_MULTIDUP"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"duplicates=4"* \
          && "$G_OUT" == *"line=$MD_A2,col=3::duplicate key 'a' (first at line $MD_A1)"* \
          && "$G_OUT" == *"line=$MD_B2,col=3::duplicate key 'b' (first at line $MD_B1)"* \
          && "$G_OUT" == *"line=$MD_C2,col=3::duplicate key 'c' (first at line $MD_C1)"* \
          && "$G_OUT" == *"line=$MD_C3,col=3::duplicate key 'c' (first at line $MD_C1)"* ]]; then
      b_ok B3c; else b_no B3c "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B3d; then
    run_guard "$g" "$R_ESC"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/sp%3Aec%2Cial.yml,line="* \
          && "$G_OUT" == *"duplicate key 'p%25q'"* && "$G_OUT" == *"duplicate key 'n%0Am'"* && "$G_OUT" == *"duplicates=2"* ]]; then
      b_ok B3d; else b_no B3d "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B4; then
    run_guard "$g" "$R_THREE"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/b-dup.yml,line=3,"* && "$G_OUT" == *"file=.github/workflows/c-dup.yml,line=6,"* \
          && "$G_OUT" != *"a-clean.yml"* && "$G_OUT" == *"duplicates=2"* ]]; then
      b_ok B4; else b_no B4 "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B5; then
    run_guard "$g" "$R_EXT"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/w.yaml,line=4,"* && "$G_OUT" == *"file=.github/actions/deep/er/action.yaml,line=2,"* ]]; then
      b_ok B5; else b_no B5 "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B6; then
    run_guard "$g" "$R_FLOW"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/flow.yml,line=3,"*"duplicate key 'a'"* ]]; then
      b_ok B6; else b_no B6 "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B6q; then
    run_guard "$g" "$R_QUOTE"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/q.yml,line=5,"*"duplicate key 'a'"* ]]; then
      b_ok B6q; else b_no B6q "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B7; then
    run_guard "$g" "$R_UNP"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/u.yml"* && "$G_OUT" == *"workflow-duplicate-keys=FAIL"* && "$G_OUT" == *"unparseable=1"* ]]; then
      b_ok B7; else b_no B7 "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B7m; then
    run_guard "$g" "$R_MULTI"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/m.yml"* && "$G_OUT" == *"unparseable=1"* ]]; then
      b_ok B7m; else b_no B7m "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B7n; then
    run_guard "$g" "$R_NONMAP"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/n.yml"* && "$G_OUT" == *"unparseable=1"* ]]; then
      b_ok B7n; else b_no B7n "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B7e; then
    run_guard "$g" "$R_EMPTY"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/e.yml"* && "$G_OUT" == *"unparseable=1"* ]]; then
      b_ok B7e; else b_no B7e "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B8; then
    run_guard "$g" "$R_NOROOT"
    if [[ "$G_RC" -eq 2 && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B8; else b_no B8 "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B8w; then
    run_guard "$g" "$R_NOWF"
    if [[ "$G_RC" -eq 2 && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B8w; else b_no B8w "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B8m; then
    run_guard "$g" "$R_MISSING"
    if [[ "$G_RC" -eq 2 && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B8m; else b_no B8m "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B9; then
    run_guard "$g" "$R_CLEAN" "PYTHONPATH=$SHIM"
    if [[ "$G_RC" -eq 2 && "$G_OUT" == *"PyYAML"* && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B9; else b_no B9 "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B10; then
    run_guard "$g" "$R_PASS"
    n="$(count_fx "$R_PASS")"
    if [[ "$G_RC" -eq 0 && "$G_OUT" == *"workflow-duplicate-keys=OK files=$n "* && "$G_OUT" != *"::error"* ]]; then
      b_ok B10; else b_no B10 "rc=$G_RC want files=$n out=$(snip)"; fi
  fi

  if sel B10s; then
    run_guard "$g" "$R_SUB"
    n="$(count_fx "$R_SUB")"
    if [[ "$G_RC" -eq 0 && "$G_OUT" == *"workflow-duplicate-keys=OK files=$n "* && "$G_OUT" != *"::error"* ]]; then
      b_ok B10s; else b_no B10s "rc=$G_RC want files=$n out=$(snip)"; fi
  fi

  sel B13 && check_both B13 "$g" "$R_KEYCASE" p_keycase
  sel B14 && check_both B14 "$g" "$R_ONTRUE" p_clean
  sel B15 && check_both B15 "$g" "$R_TWOMERGE" p_twomerge
  sel B15n && check_both B15n "$g" "$R_NONSCALAR" p_clean
  sel B16 && check_both B16 "$g" "$R_NOFOLD" p_clean

  if sel B17; then
    run_guard "$g" "$R_UPPER"
    n="$(count_fx "$R_UPPER")"
    if [[ "$G_RC" -eq 1 && "$n" -eq 2 && "$G_OUT" == *"files=$n "* && "$G_OUT" == *"file=.github/workflows/UP.YML,line=3,"*"duplicate key 'name'"* \
          && "$G_OUT" == *"file=.github/actions/x/ACTION.YAML,line=2,"*"duplicate key 'name'"* ]]; then
      b_ok B17; else b_no B17 "rc=$G_RC want files=$n out=$(snip)"; fi
  fi

  if sel B17d; then
    run_guard "$g" "$R_DANG"
    n="$(find "$R_DANG/.github/workflows" -maxdepth 1 \( -type f -o -type l \) | wc -l)"
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/x.yml::unparseable"* && "$G_OUT" == *"unparseable=1"* && "$G_OUT" == *"files=$n "* ]]; then
      b_ok B17d; else b_no B17d "rc=$G_RC want files=$n out=$(snip)"; fi
  fi

  if sel B19; then
    noarg_layout "$g"
    if [[ "$NOARG_OK" -eq 1 ]]; then b_ok B19; else b_no B19 "$NOARG_WHY"; fi
  fi

  if sel B20; then
    run_guard "$g" "$R_CLEAN"
    pv_ok="$G_OUT"; pv_rc="$G_RC"
    run_guard "$g" "$R_INC"
    if [[ "$pv_rc" -eq 0 && "$pv_ok" == *"workflow-duplicate-keys=OK files="*" loader=$EXPECT_LOADER pyyaml=$PYYAML_VER" \
          && "$G_RC" -eq 1 && "$G_OUT" == *"workflow-duplicate-keys=FAIL files="*" loader=$EXPECT_LOADER pyyaml=$PYYAML_VER"* ]]; then
      b_ok B20; else b_no B20 "want pyyaml=$PYYAML_VER ok=${pv_ok: -80} fail=$(snip)"; fi
  fi

  if sel B21; then
    run_guard "$g" "$R_ENC" PYTHONIOENCODING=ascii:strict
    if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/enc.yml,line="*"duplicate key '"* && "$G_OUT" == *"duplicates=1"* \
          && "$G_OUT" != *"Traceback"* ]]; then
      b_ok B21; else b_no B21 "rc=$G_RC out=$(snip)"; fi
  fi

  if sel B12; then
    if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      want="$(real_ls_count)"
      run_guard "$g" "$REPO_ROOT"
      if [[ "$G_RC" -eq 0 && "$want" -gt 0 && "$G_OUT" == *"workflow-duplicate-keys=OK files=$want "* ]]; then
        b_ok B12; else b_no B12 "rc=$G_RC want files=$want out=$(snip)"; fi
    else
      b_ok B12
      BAT_SKIPPED_B12=1
    fi
  fi
}
BAT_SKIPPED_B12=0

# ---- wiring (structural rows over pr-quality-guards.yml) ---------------------------------------
WIRING="$WORK/wiring.py"
cat > "$WIRING" <<'PY'
import re
import sys
import yaml

d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
job = d["jobs"]["quality-guards"]
reasons = []
trig = d.get("on", d.get(True)) or {}   # PyYAML loads the bare key `on` as bool True
if "merge_group" not in trig:
    reasons.append("on: lacks merge_group (the umbrella must report on the queue ref)")
if "if" in job:
    reasons.append("job-level if: present on quality-guards")
steps = job["steps"]
mem = [s for s in steps if s.get("id") == "workflow-duplicate-keys"]
if len(mem) != 1:
    reasons.append("member step workflow-duplicate-keys missing or duplicated")
else:
    s = mem[0]
    if "!cancelled()" not in str(s.get("if", "")):
        reasons.append("member step if: lacks !cancelled()")
    if "continue-on-error" in s:
        reasons.append("member step has continue-on-error")
    run = (s.get("run") or "").strip()
    if run != "python3 -I .github/scripts/check-workflow-duplicate-keys.py":
        reasons.append("member step run is not the bare guard command (%r)" % run)
agg = [s for s in steps if s.get("id") == "aggregate"]
if len(agg) != 1:
    reasons.append("aggregate step missing")
else:
    rows = [l for l in (agg[0].get("run") or "").splitlines()
            if re.match(r"\s*member\s+workflow-yaml-strict\s", l)]
    if len(rows) != 1:
        reasons.append("aggregate lacks exactly one member workflow-yaml-strict row")
    else:
        r = rows[0].rstrip()
        if not r.endswith("|| failed=1"):
            reasons.append("aggregate member row does not end with || failed=1")
        if "|| true" in r:
            reasons.append("aggregate member row carries || true")
        want = ("member workflow-yaml-strict '*' 'workflow-duplicate-keys' "
                "'${{ steps.workflow-duplicate-keys.conclusion }}' '${{ steps.workflow-duplicate-keys.outcome }}' || failed=1")
        if r.strip() != want:
            reasons.append("aggregate member row does not read the step conclusion/outcome with scope '*' (%r)" % r.strip())
print("; ".join(reasons))
sys.exit(1 if reasons else 0)
PY

WFMUT="$WORK/wf_mutate.py"
cat > "$WFMUT" <<'PY'
import re
import sys

kind, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src, encoding="utf-8").read().split("\n")
start = next((i for i, l in enumerate(lines) if re.match(r"\s+- id: workflow-duplicate-keys\s*$", l)), None)
if start is None:
    sys.exit(3)
end = next((j for j in range(start + 1, len(lines)) if re.match(r"\s+- id: \S+\s*$", lines[j])), len(lines))
if kind == "strip-cancelled":
    for i in range(start, end):
        if re.match(r"\s+if:", lines[i]):
            lines[i] = "        if: ${{ success() }}"
            break
elif kind == "drop-member-row":
    lines = [l for l in lines if not re.match(r"\s*member\s+workflow-yaml-strict\s", l)]
elif kind == "append-true":
    for i in range(start, end):
        if re.match(r"\s+run: python3 -I \.github/scripts/check-workflow-duplicate-keys\.py\s*$", lines[i]):
            lines[i] = lines[i].rstrip() + " || true"
elif kind == "drop-merge-group":
    lines = [l for l in lines if not re.match(r"\s+merge_group:\s*$", l)]
elif kind == "swap-conclusion":
    lines = [l.replace("'${{ steps.workflow-duplicate-keys.conclusion }}'", "'${{ steps.workflow-duplicate-keys.outcome }}'")
             if re.match(r"\s*member\s+workflow-yaml-strict\s", l) else l for l in lines]
elif kind == "drop-isolation":
    for i in range(start, end):
        if re.match(r"\s+run: python3 -I ", lines[i]):
            lines[i] = lines[i].replace("python3 -I ", "python3 ")
elif kind == "add-coe":
    lines.insert(start + 1, "        continue-on-error: true")
else:
    sys.exit(4)
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY

REASON=""
wiring_check() { # <yml> -> 0 ok; else REASON
  local y="$1"
  REASON="$(python3 "$WIRING" "$y" 2>&1)"
  return $?
}

# ---- mutation harness --------------------------------------------------------------------------
# mutate_guard <label> <expected-failing-row-regex> <old-literal> <new-literal> [clean-rows-allowed-red]
# Applies the literal replacement to a SANDBOX copy of the guard (never the real file), requires
# the mutation to have LANDED (the copy differs from the pristine bytes), then requires the battery
# to go RED on a row matching the expected regex.
MUT_N=0
mutate_guard() {
  local label="$1" want="$2" old="$3" new="$4" exempt="${5:-}" cp id failed="" cid unresolved="" sel_ids=""
  MUT_N=$((MUT_N + 1))
  cp="$SB/mut${MUT_N}.py"
  cp "$GUARD_REAL" "$cp" || { fail "$label (could not copy the guard)"; return 0; }
  OLD="$old" NEW="$new" python3 - "$cp" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
o, n = os.environ["OLD"], os.environ["NEW"]
if s.count(o) == 1:
    open(p, "w", encoding="utf-8").write(s.replace(o, n))
PY
  if cmp -s "$GUARD_REAL" "$cp"; then
    fail "$label: mutation did not land (literal absent, duplicated or identical)"; return 0
  fi
  # A mutant that does not even compile fails EVERY row, including the named one: that is a crash,
  # not a kill. Refuse it before the battery runs.
  if ! python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$cp" 2>/dev/null; then
    fail "$label: mutant does not compile (a crashed mutant is not a kill)"; return 0
  fi
  # Only the NAMED rows plus the clean-path rows are evaluated: the kill criterion (a named row goes RED,
  # the clean rows stay GREEN) is unchanged, the unrelated rows were never part of it, and re-running all
  # of them (plus the real-tree row) per mutant was the suite's whole cost.
  for id in "${BAT_IDS[@]}"; do
    grep -qE "$want" <<<" $id" && sel_ids="$sel_ids $id"
  done
  if [[ -z "$sel_ids" ]]; then
    fail "$label: RED for the wrong reason (wanted /$want/ names no battery row, so nothing can kill this mutant)"; return 0
  fi
  battery "$cp" "$sel_ids ${CLEAN_IDS[*]}"
  for id in $sel_ids; do
    [[ "${BAT_RES[$id]}" == "ok" ]] || failed="$failed $id"
  done
  if [[ -z "$failed" ]]; then
    fail "$label: guard stayed GREEN under the mutation"; return 0
  fi
  # The clean-path rows must survive every mutant: if one went RED the mutant broke the guard
  # wholesale (a runtime crash), so the named row going RED proves nothing.
  for cid in "${CLEAN_IDS[@]}"; do
    [[ "${BAT_RES[$cid]}" == "ok" || " $exempt " == *" $cid "* ]] || unresolved="$unresolved $cid"
  done
  if [[ -n "$unresolved" ]]; then
    fail "$label: UNRESOLVED -- clean-path rows went RED under the mutant (verdict-less crash, not a kill):$unresolved"; return 0
  fi
  if grep -qE "$want" <<<"$failed"; then
    pass "$label -> RED on:${failed}"
  else
    fail "$label: RED for the wrong reason (failed:${failed}; wanted /$want/)"
  fi
}

mutate_wiring() { # <label> <kind> <expected-reason-regex>
  local label="$1" kind="$2" want="$3" y
  MUT_N=$((MUT_N + 1))
  y="$SB/wf${MUT_N}.yml"
  if ! python3 "$WFMUT" "$kind" "$WF_REAL" "$y" 2>/dev/null; then
    fail "$label: mutation did not land (member step absent from the workflow)"; return 0
  fi
  if cmp -s "$WF_REAL" "$y"; then
    fail "$label: mutation did not land (copy identical)"; return 0
  fi
  if wiring_check "$y"; then
    fail "$label: wiring check stayed GREEN under the mutation"
  elif grep -q 'Traceback' <<<"$REASON"; then
    fail "$label: UNRESOLVED -- the structural check crashed instead of reporting ($REASON)"
  elif grep -qE "$want" <<<"$REASON"; then
    pass "$label -> RED ($REASON)"
  else
    fail "$label: RED for the wrong reason ($REASON; wanted /$want/)"
  fi
}

# ---- 1. the battery against the real guard -----------------------------------------------------
echo "== battery: real guard =="
battery "$GUARD_REAL"
for id in "${BAT_IDS[@]}"; do
  if [[ "${BAT_RES[$id]}" == "ok" ]]; then
    if [[ "$id" == "B12" && "$BAT_SKIPPED_B12" -eq 1 ]]; then
      skips=$((skips + 1)); echo "  SKIP: $id outside a git work tree (printed notice; counted as a skip, not a pass)"
    else
      pass "$id ${BAT_DESC[$id]}"
    fi
  else
    fail "$id ${BAT_DESC[$id]} :: ${BAT_RES[$id]}"
  fi
done

echo "== wiring: real pr-quality-guards.yml =="
if wiring_check "$WF_REAL"; then
  pass "B11 member step workflow-duplicate-keys: !cancelled(), bare command, no continue-on-error, aggregate member row ends || failed=1, no job-level if:"
else
  fail "B11 wiring :: $REASON"
fi

# ---- 1b. real-tree rows that are not guard-path functions --------------------------------------
echo "== real tree: no-argument run, tripwire, relevance gate =="
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  want="$(real_ls_count)"
  # Exactly as CI runs it: the bare command from the repo root, and from a subdirectory cwd.
  rt_out="$(cd "$REPO_ROOT" && timeout 120 python3 .github/scripts/check-workflow-duplicate-keys.py 2>&1)"; rt_rc=$?
  if [[ "$rt_rc" -eq 0 && "$want" -gt 0 && "$rt_out" == *"workflow-duplicate-keys=OK files=$want "* ]]; then
    pass "R1 no-argument run from the repo root -> rc 0, OK, files= equals git ls-files count"
  else fail "R1 no-argument run from the repo root :: rc=$rt_rc want files=$want out=${rt_out:0:200}"; fi
  rt_out="$(cd "$REPO_ROOT/.github/scripts" && timeout 120 python3 check-workflow-duplicate-keys.py 2>&1)"; rt_rc=$?
  if [[ "$rt_rc" -eq 0 && "$rt_out" == *"workflow-duplicate-keys=OK files=$want "* ]]; then
    pass "R2 no-argument run from a subdirectory cwd -> rc 0, OK, same files= count"
  else fail "R2 no-argument run from a subdirectory cwd :: rc=$rt_rc want files=$want out=${rt_out:0:200}"; fi
  stray="$(stray_actions "$REPO_ROOT")"
  if [[ -z "$stray" ]]; then
    pass "T1 tripwire: no tracked action.yml/action.yaml outside .github/actions (the guard's composite-action scan surface)"
  else fail "T1 tripwire: tracked composite action(s) outside .github/actions are NOT scanned: $(printf '%s' "$stray" | tr '\n' ' ')"; fi
  # T1 control: the tripwire must see a stray file in a throwaway repo, and ignore .github/actions.
  TRIP="$WORK/triprepo"; assert_fixture_dir "$TRIP"; mkdir -p "$TRIP" || exit 2
  git -C "$TRIP" init -q || exit 2
  put "$TRIP" .github/actions/a/action.yml </dev/null
  put "$TRIP" pkg/action.yml </dev/null
  put "$TRIP" x/Action.YAML </dev/null
  git -C "$TRIP" add -A >/dev/null 2>&1 || exit 2
  stray="$(stray_actions "$TRIP")"
  if [[ "$stray" == *"pkg/action.yml"* && "$stray" == *"x/Action.YAML"* && "$stray" != *".github/actions/a"* ]]; then
    pass "T1c tripwire control: flags stray pkg/action.yml and x/Action.YAML (any case), ignores .github/actions"
  else fail "T1c tripwire control :: got '$(printf '%s' "$stray" | tr '\n' ' ')'"; fi
else
  skips=$((skips + 4)); echo "  SKIP: R1 R2 T1 T1c outside a git work tree (printed notice; counted as skips, not passes)"
fi
PATHS_FILE="$REPO_ROOT/scripts/lib/test-relevance-paths.sh"
if paths_has_github "$PATHS_FILE"; then
  pass "W1 GITHUB_SCRIPTS_SUITE_PATHS still contains .github (a workflow-only diff still triggers run-all.sh and this suite)"
else fail "W1 GITHUB_SCRIPTS_SUITE_PATHS no longer contains .github :: a workflow-only diff would skip this suite locally and in the ci.yml gate"; fi
grep -v '^  "\.github"[[:space:]]' "$PATHS_FILE" > "$SB/paths-mut.sh"
if ! cmp -s "$PATHS_FILE" "$SB/paths-mut.sh" && ! paths_has_github "$SB/paths-mut.sh"; then
  pass "W1m mutation: dropping the .github element turns W1 RED"
else fail "W1m mutation :: dropping the .github element did not turn W1 RED"; fi

# ---- 2. mutation rows --------------------------------------------------------------------------
echo "== mutations =="
# M0: an UNMUTATED sandbox copy must be fully green, so a sandbox-harness defect cannot pose as a RED.
cp "$GUARD_REAL" "$SB/control.py"
battery "$SB/control.py"
m0_bad=""
for id in "${BAT_IDS[@]}"; do [[ "${BAT_RES[$id]}" == "ok" ]] || m0_bad="$m0_bad $id"; done
if [[ -z "$m0_bad" ]]; then pass "M0 positive control: unmutated sandbox copy of the guard is GREEN on every row"; else fail "M0 positive control (failed:$m0_bad)"; fi

mutate_guard "M1 strict collector swapped for yaml.safe_load (last-wins) -> RED" '(^| )B1( |$)' \
  '        collect_duplicates(node, dups)' '        yaml.safe_load(data)'
mutate_guard "M2 zero-files exit-2 arm removed -> RED" '(^| )B8w( |$)' \
  '    if not files:' '    if False:'
mutate_guard "M3 raise-first across files (stop after the first failing file) -> RED" '(^| )B4( |$)' \
  '        unparseable += n_unp' $'        unparseable += n_unp\n        if n_dup or n_unp:\n            break'
mutate_guard "M3b raise-first within a file (stop after the first repeat) -> RED" '(^| )B3( |$)' \
  '            dups.append((line, col, label, seen[ident]))' $'            dups.append((line, col, label, seen[ident]))\n            raise SystemExit(1)'
mutate_guard "M4a workflow suffix glob narrowed to .yml only -> RED" '(^| )B5( |$)' \
  'WF_SUFFIXES = (".yml", ".yaml")' 'WF_SUFFIXES = (".yml",)' B2   # B2 legitimately counts the .yaml sibling
mutate_guard "M4b action name narrowed to action.yml only -> RED" '(^| )B5( |$)' \
  'ACTION_NAMES = ("action.yml", "action.yaml")' 'ACTION_NAMES = ("action.yml",)'
mutate_guard "M5 reported line loses the +1 (off by one) -> RED" '(^| )B1( |$)' \
  '        line = key_node.start_mark.line + 1' '        line = key_node.start_mark.line'
mutate_wiring "M6a member step loses !cancelled() -> RED" strip-cancelled 'cancelled'
mutate_wiring "M6b aggregate member row dropped -> RED" drop-member-row 'aggregate lacks exactly one'
mutate_wiring "M6c member step run gains || true -> RED" append-true 'not the bare guard command'
mutate_wiring "M6d member step gains continue-on-error -> RED" add-coe 'continue-on-error'
mutate_wiring "M6e on: loses merge_group -> RED" drop-merge-group 'merge_group'
mutate_wiring "M6f aggregate member row reads the outcome instead of the conclusion -> RED" swap-conclusion 'conclusion/outcome'
mutate_wiring "M6g member step loses python3 -I isolation -> RED" drop-isolation 'not the bare guard command'
mutate_guard "M7a unparseable file no longer counted (parse error skipped) -> RED" '(^| )B7( |$)' \
  '        return 0, 1  # fail-closed:parse' '        return 0, 0  # fail-closed:parse'
mutate_guard "M7b non-mapping top level no longer counted -> RED" '(^| )B7n( |$)' \
  '        return 0, 1  # fail-closed:non-mapping' '        return 0, 0  # fail-closed:non-mapping'
mutate_guard "M7c empty file no longer counted -> RED" '(^| )B7e( |$)' \
  '        return 0, 1  # fail-closed:empty' '        return 0, 0  # fail-closed:empty'
mutate_guard "M8 missing-PyYAML exit-2 arm turned into a pass -> RED" '(^| )B9( |$)' \
  '        return 2  # env:pyyaml' '        return 0  # env:pyyaml'
mutate_guard "M9 pure-python seam ignored (WFDK_PURE_PYTHON=1 no longer forces SafeLoader) -> RED" '(^| )B1p( |$)' \
  '    if os.environ.get("WFDK_PURE_PYTHON") == "1":' '    if False:'
mutate_guard "M10a key identity loses the ASCII fold (case variants no longer collide) -> RED" '(^| )B13( |$)' \
  '        ident = key_node.value.translate(ASCII_FOLD)' '        ident = key_node.value'
mutate_guard "M10b key identity uses Python full upper() (sharp-s collides with SS) -> RED" '(^| )B16( |$)' \
  '        ident = key_node.value.translate(ASCII_FOLD)' '        ident = key_node.value.upper()'
mutate_guard "M10c merge key skipped again (two << keys read as clean) -> RED" '(^| )B15( |$)' \
  '        ident = key_node.value.translate(ASCII_FOLD)' $'        if key_node.value == "<<":\n            continue\n        ident = key_node.value.translate(ASCII_FOLD)'
mutate_guard "M10d non-scalar keys no longer skipped (complex key reaches .value.translate) -> RED" '(^| )B15n( |$)' \
  '        if not isinstance(key_node, yaml.ScalarNode):' '        if False:'
mutate_guard "M11a workflow suffix match made case-sensitive -> RED" '(^| )B17( |$)' \
  '            if name.lower().endswith(WF_SUFFIXES) and not os.path.isdir(path):' '            if name.endswith(WF_SUFFIXES) and not os.path.isdir(path):'
mutate_guard "M11b action name match made case-sensitive -> RED" '(^| )B17( |$)' \
  '                if name.lower() in ACTION_NAMES and not os.path.isdir(path):' '                if name in ACTION_NAMES and not os.path.isdir(path):'
mutate_guard "M12a isfile gate restored (dangling symlink skipped) -> RED" '(^| )B17d( |$)' \
  '            if name.lower().endswith(WF_SUFFIXES) and not os.path.isdir(path):' '            if name.lower().endswith(WF_SUFFIXES) and os.path.isfile(path):'
mutate_guard "M12b directory gate removed (dir.yml opened as a file) -> RED" '(^| )B10s( |$)' \
  '            if name.lower().endswith(WF_SUFFIXES) and not os.path.isdir(path):' '            if name.lower().endswith(WF_SUFFIXES):'
mutate_guard "M13 workflows/ enumeration recurses into subdirectories -> RED" '(^| )B10s( |$)' \
  '        for name in sorted(os.listdir(wf_dir)):' '        for name in sorted(os.path.relpath(os.path.join(d, f), wf_dir) for d, _s, fs in os.walk(wf_dir) for f in fs):'
mutate_guard "M14 default root loses one dirname (no-argument run scans the wrong directory) -> RED" '(^| )B19( |$)' \
  '        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))' '        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))'
mutate_guard "M15 pyyaml= field dropped from the summary lines -> RED" '(^| )B20( |$)' \
  '    tail = " loader=%s pyyaml=%s" % (loader_name, yaml.__version__)' '    tail = " loader=%s" % loader_name'
mutate_guard "M16 sequence walk reaches only the first item -> RED" '(^| )B3b( |$)' \
  '            stack.extend(node.value)' '            stack.extend(node.value[:1])'
mutate_guard "M17 stop after the first repeat inside a mapping -> RED" '(^| )B3c( |$)' \
  '            dups.append((line, col, label, seen[ident]))' $'            dups.append((line, col, label, seen[ident]))\n            break'
mutate_guard "M18 first-at drifts to the previous occurrence -> RED" '(^| )B3c( |$)' \
  '            dups.append((line, col, label, seen[ident]))' $'            dups.append((line, col, label, seen[ident]))\n            seen[ident] = line'
mutate_guard "M19 annotation escaping removed -> RED" '(^| )B3d( |$)' \
  '    return str(s).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")' '    return str(s)'
mutate_guard "M20 stdout error handler left strict (non-ASCII key crashes the print) -> RED" '(^| )B21( |$)' \
  '            stream.reconfigure(errors="replace")' '            pass'

# ---- 3. controls: the mutation helper must FAIL on inputs that must fail ------------------------
# control_fails <label> <wanted-message-substring> <cmd...>: drive a verdict helper once with an input
# that must fail; the failure counter must move by exactly one (carrying the substring); the recorded
# failure is then unwound. A control that did not fail aborts by printf + exit, so a neutered helper
# (`pass "$label"; return`) cannot be masked by a green count.
control_fails() {
  local label="$1" want_msg="$2"; shift 2
  local p0="$passes" f0="$fails" n0="${#FAILED[@]}" moved=0 msg_ok=0
  "$@" >/dev/null 2>&1
  [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] && moved=1
  [[ "${FAILED[$((${#FAILED[@]} - 1))]:-}" == *"$want_msg"* ]] && msg_ok=1
  passes="$p0"; fails="$f0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ "$moved" -eq 1 && "$msg_ok" -eq 1 ]]; then
    pass "control: $label fails on an input that must fail"
  else
    printf '[FATAL] control: %s did not record a failure carrying "%s" on an input that must fail (moved=%s msg=%s)\n' "$label" "$want_msg" "$moved" "$msg_ok" >&2
    exit 1
  fi
}
control_fails "mutate_guard (mutation did not land)" "mutation did not land" \
  mutate_guard "CTL-a" 'B1' '#!/usr/bin/env python3' '#!/usr/bin/env python3'
control_fails "mutate_guard (guard stayed GREEN)" "stayed GREEN" \
  mutate_guard "CTL-b" 'B1' '#!/usr/bin/env python3' $'#!/usr/bin/env python3\n# harmless'
control_fails "mutate_guard (RED for the wrong reason)" "wrong reason" \
  mutate_guard "CTL-c" 'NO_SUCH_ROW' '    if not files:' '    if False:'
control_fails "mutate_guard (mutant does not compile)" "does not compile" \
  mutate_guard "CTL-d" 'B1' '    if not files:' '    if not files::'
control_fails "mutate_guard (clean-path rows crash under the mutant)" "UNRESOLVED" \
  mutate_guard "CTL-e" 'B1' '    LOADER, loader_name = pick_loader()' $'    LOADER, loader_name = pick_loader()\n    raise RuntimeError("boom")'

# ---- accounting (exact floor; printf + exit so a neutered helper cannot mask it) ----------------
printf '=== %s passed, %s failed, %s skipped ===\n' "$passes" "$fails" "$skips"
if [[ "$fails" -ne 0 ]]; then
  printf '[FAIL] rows failed:\n' >&2; printf '  %s\n' "${FAILED[@]}" >&2; exit 1
fi
# EXACT floor: every row either passes or is a counted SKIP, so a dropped row or a neutered
# verdict helper moves the total. Update the literal deliberately when a row is added.
if [[ $((passes + skips)) -ne 80 ]]; then
  printf '[FAIL] verdict count %s != exact floor 80 (a row was dropped or added)\n' "$((passes + skips))" >&2; exit 1
fi
exit 0
