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
#   Three control rows prove the mutation helper itself fails when it should: mutation did not
#   land, guard stayed GREEN, RED for the wrong reason.
#
# MUTATION MATRIX (Guard 1) -- M1 strict collector swapped for yaml.safe_load (last-wins), M2 zero
# files exit-2 arm removed, M3 raise-first across files, M3b raise-first within a file, M4a/M4b
# extension coverage narrowed, M5 line off by one, M6a-d member wiring (strip !cancelled(), drop
# the aggregate row, append || true, add continue-on-error), M7a-c fail-closed arms neutered, M8
# missing-PyYAML exit-2 arm, M9 pure-python seam, M10 merge-key skip.
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
  a="$(find "$r/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l)"
  b="$(find "$r/.github/actions" -type f \( -name action.yml -o -name action.yaml \) 2>/dev/null | wc -l)"
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
other: &o
  c: 3
derived:
  <<: *b
  a: 2
twice:
  <<: *b
  <<: *o
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
  "1": c
jobs: {}
EOF
put "$R_PASS" .github/actions/ok/action.yml <<'EOF'
name: ok
runs:
  using: composite
  steps: []
EOF

# PyYAML-less interpreter shim for B9: a `yaml` package that refuses to import, ahead of site-packages.
SHIM="$WORK/noyaml"; assert_fixture_dir "$SHIM"; mkdir -p "$SHIM/yaml" || exit 2
printf 'raise ImportError("PyYAML deliberately blocked by the suite")\n' > "$SHIM/yaml/__init__.py"

EXPECT_LOADER="py"
python3 -c 'import sys, yaml; sys.exit(0 if hasattr(yaml, "CSafeLoader") else 1)' 2>/dev/null && EXPECT_LOADER="c"

# ---- the battery -------------------------------------------------------------------------------
declare -A BAT_RES
declare -A BAT_DESC
BAT_IDS=(B1 B1p B2 B3 B4 B5 B6 B6q B7 B7m B7n B7e B8 B8w B8m B9 B10 B12)
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
BAT_DESC[B10]="must-PASS corpus (sibling keys, flow, <<, on, multiline, CRLF, aliases, cycle, 1/true) -> rc 0"
BAT_DESC[B12]="real tree -> rc 0, OK, files= equals git ls-files count (SKIP outside a git work tree)"

b_ok() { BAT_RES["$1"]="ok"; }
b_no() { BAT_RES["$1"]="$2"; }
snip() { printf '%s' "${G_OUT:0:240}" | tr '\n' '|'; }

battery() { # <guard>
  local g="$1" id n want
  for id in "${BAT_IDS[@]}"; do BAT_RES["$id"]="not run"; done

  run_guard "$g" "$R_INC"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/ci.yml,line=$INC_L2,col=11::duplicate key 'fetch-depth' (first at line $INC_L1)"* \
        && "$G_OUT" == *"workflow-duplicate-keys=FAIL"* && "$G_OUT" == *"duplicates=1"* && "$G_OUT" == *"loader=$EXPECT_LOADER"* ]]; then
    b_ok B1; else b_no B1 "rc=$G_RC want line=$INC_L2 first=$INC_L1 out=$(snip)"; fi

  run_guard "$g" "$R_INC" WFDK_PURE_PYTHON=1
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"line=$INC_L2,col=11::duplicate key 'fetch-depth'"* && "$G_OUT" == *"loader=py"* ]]; then
    b_ok B1p; else b_no B1p "rc=$G_RC want loader=py line=$INC_L2 out=$(snip)"; fi

  run_guard "$g" "$R_CLEAN"
  n="$(count_fx "$R_CLEAN")"
  if [[ "$G_RC" -eq 0 && "$G_OUT" == *"workflow-duplicate-keys=OK files=$n "* && "$G_OUT" != *"::error"* ]]; then
    b_ok B2; else b_no B2 "rc=$G_RC want files=$n out=$(snip)"; fi

  run_guard "$g" "$R_TWO"
  n="$(printf '%s\n' "$G_OUT" | grep -c "^::error file=.github/workflows/two.yml,line=.*::duplicate key")"
  if [[ "$G_RC" -eq 1 && "$n" -eq 2 && "$G_OUT" == *"duplicate key 'FOO'"* && "$G_OUT" == *"duplicate key 'fetch-depth'"* && "$G_OUT" == *"duplicates=2"* ]]; then
    b_ok B3; else b_no B3 "rc=$G_RC findings=$n out=$(snip)"; fi

  run_guard "$g" "$R_THREE"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/b-dup.yml,line=3,"* && "$G_OUT" == *"file=.github/workflows/c-dup.yml,line=6,"* \
        && "$G_OUT" != *"a-clean.yml"* && "$G_OUT" == *"duplicates=2"* ]]; then
    b_ok B4; else b_no B4 "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_EXT"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/w.yaml,line=4,"* && "$G_OUT" == *"file=.github/actions/deep/er/action.yaml,line=2,"* ]]; then
    b_ok B5; else b_no B5 "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_FLOW"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/flow.yml,line=3,"*"duplicate key 'a'"* ]]; then
    b_ok B6; else b_no B6 "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_QUOTE"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"file=.github/workflows/q.yml,line=5,"*"duplicate key 'a'"* ]]; then
    b_ok B6q; else b_no B6q "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_UNP"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/u.yml"* && "$G_OUT" == *"workflow-duplicate-keys=FAIL"* && "$G_OUT" == *"unparseable=1"* ]]; then
    b_ok B7; else b_no B7 "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_MULTI"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/m.yml"* && "$G_OUT" == *"unparseable=1"* ]]; then
    b_ok B7m; else b_no B7m "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_NONMAP"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/n.yml"* && "$G_OUT" == *"unparseable=1"* ]]; then
    b_ok B7n; else b_no B7n "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_EMPTY"
  if [[ "$G_RC" -eq 1 && "$G_OUT" == *"::error file=.github/workflows/e.yml"* && "$G_OUT" == *"unparseable=1"* ]]; then
    b_ok B7e; else b_no B7e "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_NOROOT"
  if [[ "$G_RC" -eq 2 && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B8; else b_no B8 "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_NOWF"
  if [[ "$G_RC" -eq 2 && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B8w; else b_no B8w "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_MISSING"
  if [[ "$G_RC" -eq 2 && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B8m; else b_no B8m "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_CLEAN" "PYTHONPATH=$SHIM"
  if [[ "$G_RC" -eq 2 && "$G_OUT" == *"PyYAML"* && "$G_OUT" != *"workflow-duplicate-keys=OK"* ]]; then b_ok B9; else b_no B9 "rc=$G_RC out=$(snip)"; fi

  run_guard "$g" "$R_PASS"
  n="$(count_fx "$R_PASS")"
  if [[ "$G_RC" -eq 0 && "$G_OUT" == *"workflow-duplicate-keys=OK files=$n "* && "$G_OUT" != *"::error"* ]]; then
    b_ok B10; else b_no B10 "rc=$G_RC want files=$n out=$(snip)"; fi

  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    want=0
    while IFS= read -r -d '' f; do
      [[ -f "$REPO_ROOT/$f" ]] && want=$((want + 1))
    done < <(git -C "$REPO_ROOT" ls-files -z -- ':(glob).github/workflows/*.yml' ':(glob).github/workflows/*.yaml' \
                 ':(glob).github/actions/**/action.yml' ':(glob).github/actions/**/action.yaml')
    run_guard "$g" "$REPO_ROOT"
    if [[ "$G_RC" -eq 0 && "$want" -gt 0 && "$G_OUT" == *"workflow-duplicate-keys=OK files=$want "* ]]; then
      b_ok B12; else b_no B12 "rc=$G_RC want files=$want out=$(snip)"; fi
  else
    b_ok B12
    BAT_SKIPPED_B12=1
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
    if run != "python3 .github/scripts/check-workflow-duplicate-keys.py":
        reasons.append("member step run is not the bare guard command (%r)" % run)
agg = [s for s in steps if s.get("id") == "aggregate"]
if len(agg) != 1:
    reasons.append("aggregate step missing")
else:
    rows = [l for l in (agg[0].get("run") or "").splitlines()
            if re.match(r"\s*member\s+workflow-yaml-strict\s+'\*'\s+'workflow-duplicate-keys'", l)]
    if len(rows) != 1:
        reasons.append("aggregate lacks exactly one member workflow-yaml-strict row")
    else:
        r = rows[0].rstrip()
        if not r.endswith("|| failed=1"):
            reasons.append("aggregate member row does not end with || failed=1")
        if "|| true" in r:
            reasons.append("aggregate member row carries || true")
        if "steps.workflow-duplicate-keys.conclusion" not in r:
            reasons.append("aggregate member row does not read the step conclusion")
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
        if re.match(r"\s+run: python3 \.github/scripts/check-workflow-duplicate-keys\.py\s*$", lines[i]):
            lines[i] = lines[i].rstrip() + " || true"
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
# mutate_guard <label> <expected-failing-row-regex> <old-literal> <new-literal>
# Applies the literal replacement to a SANDBOX copy of the guard (never the real file), requires
# the mutation to have LANDED (the copy differs from the pristine bytes), then requires the battery
# to go RED on a row matching the expected regex.
MUT_N=0
mutate_guard() {
  local label="$1" want="$2" old="$3" new="$4" cp rc id failed=""
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
  battery "$cp"
  for id in "${BAT_IDS[@]}"; do
    [[ "${BAT_RES[$id]}" == "ok" ]] || failed="$failed $id"
  done
  if [[ -z "$failed" ]]; then
    fail "$label: guard stayed GREEN under the mutation"; return 0
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
  'WF_SUFFIXES = (".yml", ".yaml")' 'WF_SUFFIXES = (".yml",)'
mutate_guard "M4b action name narrowed to action.yml only -> RED" '(^| )B5( |$)' \
  'ACTION_NAMES = ("action.yml", "action.yaml")' 'ACTION_NAMES = ("action.yml",)'
mutate_guard "M5 reported line loses the +1 (off by one) -> RED" '(^| )B1( |$)' \
  '        line = key_node.start_mark.line + 1' '        line = key_node.start_mark.line'
mutate_wiring "M6a member step loses !cancelled() -> RED" strip-cancelled 'cancelled'
mutate_wiring "M6b aggregate member row dropped -> RED" drop-member-row 'aggregate lacks exactly one'
mutate_wiring "M6c member step run gains || true -> RED" append-true 'not the bare guard command'
mutate_wiring "M6d member step gains continue-on-error -> RED" add-coe 'continue-on-error'
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
mutate_guard "M10 merge-key skip removed (two << keys read as a duplicate) -> RED" '(^| )B10( |$)' \
  '        if key_node.tag == MERGE_TAG:' '        if False:'

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

# ---- accounting (exact floor; printf + exit so a neutered helper cannot mask it) ----------------
printf '=== %s passed, %s failed, %s skipped ===\n' "$passes" "$fails" "$skips"
if [[ "$fails" -ne 0 ]]; then
  printf '[FAIL] rows failed:\n' >&2; printf '  %s\n' "${FAILED[@]}" >&2; exit 1
fi
# EXACT floor: every row either passes or is a counted SKIP, so a dropped row or a neutered
# verdict helper moves the total. Update the literal deliberately when a row is added.
if [[ $((passes + skips)) -ne 40 ]]; then
  printf '[FAIL] verdict count %s != exact floor 40 (a row was dropped or added)\n' "$((passes + skips))" >&2; exit 1
fi
exit 0
