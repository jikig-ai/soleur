#!/usr/bin/env bash
# Mutation battery for scripts/lint-integration-env-gates.sh (#9855).
#
# WHY THIS FILE EXISTS. The sentinel's failure mode is SILENT: a narrowed
# producer, a consumer that accepts comment-level mentions, or a file-level
# arm that stops checking collection all keep printing `uncovered=0` on a tree
# that deserves red -- byte-identical to healthy. Each row below builds a
# synthetic fixture repo that breaks ONE property and asserts the sentinel
# goes RED (or, for the must-PASS rows, stays green).
#
# THE FIXTURE IS A REAL GIT REPO, and small. The sentinel's producer is
# `git grep`, which enumerates NOTHING outside a work tree -- every row does
# `git init` + `git add -A` in a mktemp sandbox and drives the sentinel via its
# SOLEUR_LINT_GATES_ROOT seam. MIN_GATED_FILES is satisfied by padding the
# fixture with >= 50 pad files under test/pad/, all gated on a var a fixture
# workflow both sets and collects (test/pad/ dir token) -- the floor stays
# absolute in the SUT rather than gaining a tunable-env back door.
#
# MUTATORS FAIL CLOSED. `mutate` requires its anchor literal to occur EXACTLY
# ONCE in the mutated copy and exits 3 otherwise, so a drifted anchor aborts
# the harness instead of scoring a phantom kill against an unmutated file.
set -uo pipefail

# git exports these when this runs as a lefthook hook; they would repoint every
# sandbox `git` call at the parent repo.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="${LINT_GATES_TARGET_OVERRIDE:-$REPO_ROOT/scripts/lint-integration-env-gates.sh}"
export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

# Canonical fixture-dir guard (copied byte-for-byte from plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh pins every copy).
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

WORK="$(mktemp -d)"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
rows_run=0

ok()   { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
notok(){ printf 'FAIL %s\n' "$1"; failed=$((failed + 1)); }

# mutate <sut-copy> <literal> <replacement> -- anchor must occur exactly once.
mutate() {
  local f="$1" lit="$2" rep="$3"
  local n
  n="$(grep -cF "$lit" "$f")"
  if [[ "$n" != "1" ]]; then
    printf 'FATAL: mutate anchor occurs %s times (want 1): %s\n' "$n" "$lit" >&2
    exit 3
  fi
  local tmp="$f.mut"
  # index()+substr() surgery, never sub(): sub() re-matches the anchor as an
  # ERE and can replace a different occurrence than the literal index() found.
  awk -v lit="$lit" -v rep="$rep" '{
    i = index($0, lit)
    if (i) $0 = substr($0, 1, i - 1) rep substr($0, i + length(lit))
    print
  }' "$f" > "$tmp"
  mv "$tmp" "$f"
  grep -qF "$rep" "$f" || { printf 'FATAL: mutation did not land: %s\n' "$rep" >&2; exit 3; }
}

# mkrepo <dir> -- a minimal fixture repo satisfying the producer floor:
#   PAD_N pad files under apps/web-platform/test/pad/, gated on PAD_GATE,
#   collected by workflows/pad.yml which sets PAD_GATE=1 over `test/pad/`.
mkrepo() {
  local d="$1"
  mkdir -p "$d/apps/web-platform/test/pad" "$d/apps/web-platform/lib" "$d/.github/workflows"
  local i
  for i in $(seq 1 55); do
    printf 'const G = process.env.PAD_GATE === "1";\n' > "$d/apps/web-platform/test/pad/p${i}.test.ts"
  done
  cat > "$d/.github/workflows/pad.yml" <<'YAML'
name: pad
on: [push]
jobs:
  pad:
    runs-on: ubuntu-latest
    steps:
      - run: env PAD_GATE=1 npm run test:ci -- test/pad/ --project unit
YAML
  ( cd "$d" && git init -q && git add -A )
}

# run_sut <dir> -- rc is the verdict; output captured for token checks.
run_sut() {
  local d="$1"
  SOLEUR_LINT_GATES_ROOT="$d" bash "$SUT" > "$WORK/out" 2>&1
  echo $?
}

expect_red() {
  local name="$1" dir="$2" token="${3:-}"
  rows_run=$((rows_run + 1))
  local rc
  rc="$(run_sut "$dir")"
  # rc must be exactly 1 -- the sentinel's verdict exit. Any other non-zero
  # (2, 126, 127, 141) is instrument failure masquerading as a caught
  # mutation: abort the harness, do not count it as a kill.
  if [[ "$rc" != "0" && "$rc" != "1" ]]; then
    printf 'FATAL(harness): %s -- SUT exited %s, neither verdict rc (0|1)\n' "$name" "$rc" >&2
    cat "$WORK/out" >&2
    exit 3
  fi
  if [[ "$rc" == "0" ]]; then
    notok "$name -- expected RED, got exit 0"; cat "$WORK/out" >&2; return
  fi
  if [[ -n "$token" ]] && ! grep -qF "$token" "$WORK/out"; then
    notok "$name -- RED but missing token: $token"; cat "$WORK/out" >&2; return
  fi
  ok "$name"
}

expect_green() {
  local name="$1" dir="$2"
  rows_run=$((rows_run + 1))
  local rc
  rc="$(run_sut "$dir")"
  if [[ "$rc" != "0" ]]; then
    notok "$name -- expected GREEN, got exit $rc"; cat "$WORK/out" >&2; return
  fi
  grep -q 'uncovered=0' "$WORK/out" || { notok "$name -- green but no uncovered=0 summary"; cat "$WORK/out" >&2; return; }
  ok "$name"
}

# --- C0: control -- baseline fixture is green ---------------------------------
D="$WORK/c0"; mkrepo "$D"
expect_green "C0 baseline fixture green" "$D"

# --- M1: remove the wiring line -> RED ----------------------------------------
D="$WORK/m1"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/server"
printf 'const G = process.env.T1_GATE === "1";\n' > "$D/apps/web-platform/test/server/t1.test.ts"
( cd "$D" && git add -A )
# wired var + collected file -> green first
cat >> "$D/.github/workflows/pad.yml" <<'YAML'
      - run: env T1_GATE=1 npm run test:ci -- test/server/
YAML
expect_green "M1-pre wired+collected is green" "$D"
mutate "$D/.github/workflows/pad.yml" "env T1_GATE=1" "env OTHER=1"
expect_red "M1 unwired var" "$D" "T1_GATE"

# --- M2: repoint the producer at an empty path -> RED (vacuity) ---------------
D="$WORK/m2"; mkrepo "$D"
cp "$SUT" "$WORK/sut-m2.sh"
mutate "$WORK/sut-m2.sh" 'apps/web-platform/test apps/web-platform/lib' 'apps/web-platform/nonexistent-dir'
# LINT_GATES_TARGET_OVERRIDE is a battery-side TEST-ONLY seam (read at this
# script's start to repoint $SUT); the sentinel itself reads only
# SOLEUR_LINT_GATES_ROOT. M2 runs the mutated copy directly.
SOLEUR_LINT_GATES_ROOT="$D" bash "$WORK/sut-m2.sh" > "$WORK/out" 2>&1; rc=$?
rows_run=$((rows_run + 1))
if [[ "$rc" == "0" ]]; then
  notok "M2 zero-census -- expected RED, got 0"; cat "$WORK/out" >&2
elif ! grep -q "ZERO files" "$WORK/out"; then
  notok "M2 zero-census -- RED but missing the anti-vacuity arm's own error"; cat "$WORK/out" >&2
else
  ok "M2 zero-census"
fi

# --- M3: new gate, no wiring -> RED -------------------------------------------
D="$WORK/m3"; mkrepo "$D"
printf 'const G = process.env.NEW_GATE === "1";\n' > "$D/apps/web-platform/test/new-gate.test.ts"
( cd "$D" && git add -A )
expect_red "M3 unwired NEW_GATE" "$D" "NEW_GATE"

# --- M4: a SECOND unwired gate must also be named (not stop at first) ---------
D="$WORK/m4"; mkrepo "$D"
printf 'const G = process.env.GATE_A === "1";\n' > "$D/apps/web-platform/test/a.test.ts"
printf 'const G = process.env.GATE_B === "1";\n' > "$D/apps/web-platform/test/b.test.ts"
( cd "$D" && git add -A )
rows_run=$((rows_run + 1))
rc="$(run_sut "$D")"
if [[ "$rc" == "0" ]]; then
  notok "M4 -- expected RED"; cat "$WORK/out" >&2
elif grep -q 'GATE_A' "$WORK/out" && grep -q 'GATE_B' "$WORK/out"; then
  ok "M4 names both unwired gates"
else
  notok "M4 -- RED but did not name BOTH gates"; cat "$WORK/out" >&2
fi

# --- M5: rename gate in the test only (spelling drift) -> RED -----------------
D="$WORK/m5"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/server"
printf 'const G = process.env.DRIFT_GATE === "1";\n' > "$D/apps/web-platform/test/server/drift.test.ts"
( cd "$D" && git add -A )
cat >> "$D/.github/workflows/pad.yml" <<'YAML'
      - run: env DRIFT_GATE=1 npm run test:ci -- test/server/
YAML
expect_green "M5-pre spelled-alike green" "$D"
mutate "$D/apps/web-platform/test/server/drift.test.ts" 'process.env.DRIFT_GATE === "1"' 'process.env.DRIFT_GATE_TYPO === "1"'
( cd "$D" && git add -A )
expect_red "M5 test/workflow spelling drift" "$D" "DRIFT_GATE_TYPO"

# --- M7 (must-PASS): env-mapping form `FOO: "1"` counts as wired --------------
# All three live spellings of a "1" mapping value: double-quoted, single-
# quoted (SENTRY_DEPRECATION_FAIL), and bare (INNGEST_ENVS_FLOOR).
D="$WORK/m7"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/server"
printf 'const G = process.env.MAP_GATE === "1";\n' > "$D/apps/web-platform/test/server/map.test.ts"
printf 'const G = process.env.MAP_GATE_SQ === "1";\n' > "$D/apps/web-platform/test/server/map-sq.test.ts"
printf 'const G = process.env.MAP_GATE_BARE === "1";\n' > "$D/apps/web-platform/test/server/map-bare.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/map.yml" <<'YAML'
name: map
on: [push]
jobs:
  m:
    runs-on: ubuntu-latest
    env:
      MAP_GATE: "1"
      MAP_GATE_SQ: '1'
      MAP_GATE_BARE: 1
    steps:
      - run: npm run test:ci -- test/server/map.test.ts --project unit
      - run: npm run test:ci -- test/server/map-sq.test.ts --project unit
      - run: npm run test:ci -- test/server/map-bare.test.ts --project unit
YAML
expect_green "M7 env-mapping wiring (all three value spellings)" "$D"

# --- M8: gate var only inside a workflow comment -> RED ------------------------
# The comment must be SETTING-SHAPED (`# env X=1 …`): without the strip the
# line wires AND collects the file, so the strip is the only thing standing
# between this fixture and a green. A bare `# X=1` would red through the
# grammar, not the strip, and pin nothing.
D="$WORK/m8"; mkrepo "$D"
printf 'const G = process.env.COMMENT_GATE === "1";\n' > "$D/apps/web-platform/test/commented.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/comment.yml" <<'YAML'
name: comment
on: [push]
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
      # env COMMENT_GATE=1 npm run test:ci -- test/commented.test.ts
      - run: npm run test:ci -- test/commented.test.ts
YAML
expect_red "M8 commented-out setting is not wiring" "$D" "COMMENT_GATE"

# --- M9: gate planted under lib/ is in producer scope -> RED -------------------
D="$WORK/m9"; mkrepo "$D"
printf 'const G = process.env.LIB_GATE === "1";\n' > "$D/apps/web-platform/lib/thing.test.ts"
( cd "$D" && git add -A )
expect_red "M9 lib/-planted gate in scope" "$D" "LIB_GATE"

# --- M10: wired var but the FILE is collected by nothing -> RED ----------------
D="$WORK/m10"; mkrepo "$D"
printf 'const G = process.env.WIRED_UNCOL === "1";\n' > "$D/apps/web-platform/test/root-uncollected.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/w.yml" <<'YAML'
name: w
on: [push]
jobs:
  w:
    runs-on: ubuntu-latest
    steps:
      - run: env WIRED_UNCOL=1 npm run test:ci -- test/server/
YAML
expect_red "M10 wired var + uncollected file (departed-member shape)" "$D" "root-uncollected"

# --- M11 (must-PASS): file under test/server/ covered by the dir filter --------
D="$WORK/m11"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/server"
printf 'const G = process.env.DIR_GATE === "1";\n' > "$D/apps/web-platform/test/server/dir.test.ts"
( cd "$D" && git add -A )
cat >> "$D/.github/workflows/pad.yml" <<'YAML'
      - run: env DIR_GATE=1 npm run test:ci -- test/server/
YAML
expect_green "M11 dir-filter collection" "$D"

# --- M12: `echo FOO=1` is not a setting position -> RED ------------------------
D="$WORK/m12"; mkrepo "$D"
printf 'const G = process.env.ECHO_GATE === "1";\n' > "$D/apps/web-platform/test/echo.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/echo.yml" <<'YAML'
name: echo
on: [push]
jobs:
  e:
    runs-on: ubuntu-latest
    steps:
      - run: echo ECHO_GATE=1; npm run test:ci -- test/echo.test.ts
YAML
expect_red "M12 echo is not a setting" "$D" "ECHO_GATE"

# --- M13 (must-PASS): depth-3 ancestor dir coverage ----------------------------
D="$WORK/m13"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/server/scope-grants"
printf 'const G = process.env.DEEP_GATE === "1";\n' > "$D/apps/web-platform/test/server/scope-grants/deep.test.ts"
( cd "$D" && git add -A )
cat >> "$D/.github/workflows/pad.yml" <<'YAML'
      - run: env DEEP_GATE=1 npm run test:ci -- test/server/
YAML
expect_green "M13 ancestor-dir coverage" "$D"

# --- M14: two gates on one file, only one set in the collecting workflow -> RED
# CONJ_B is wired in a NON-COLLECTING workflow (pad.yml's test/pad/ token), so
# the var-level arm is green for BOTH vars and the ONLY possible red is the
# per-workflow all_set conjunction. Assert on the uncovered FILE token, not
# CONJ_B -- an UNWIRED-VAR red would mean the row is pinning the wrong arm.
D="$WORK/m14"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/server"
printf 'const A = process.env.CONJ_A === "1";\nconst B = process.env.CONJ_B === "1";\n' > "$D/apps/web-platform/test/server/conj.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/conj.yml" <<'YAML'
name: conj
on: [push]
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
      - run: env CONJ_A=1 npm run test:ci -- test/server/conj.test.ts
YAML
cat >> "$D/.github/workflows/pad.yml" <<'YAML'
      - run: env CONJ_B=1 npm run test:ci -- test/pad/
YAML
expect_red "M14 conjunction -- all_set across ONE workflow" "$D" "conj.test.ts"

# --- M15 (must-PASS): the idiom in a .md under test/ is prose, not a gate -----
D="$WORK/m15"; mkrepo "$D"
cat > "$D/apps/web-platform/test/README.md" <<'MD'
Gates use the `process.env.PROSE_GATE === "1"` idiom.
MD
( cd "$D" && git add -A )
expect_green "M15 doc mention is not a gate" "$D"

# --- M16: helper file (non-.test source) is var-level, not file-level ----------
D="$WORK/m16"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/helpers"
printf 'export const G = process.env.HELPER_GATE === "1";\n' > "$D/apps/web-platform/test/helpers/x.ts"
( cd "$D" && git add -A )
# Unwired helper gate -> RED at VAR level (dormant through every importer).
expect_red "M16a unwired helper gate" "$D" "HELPER_GATE"
# Wired helper gate -> GREEN: a helper is never a path-filter target, and
# flagging it UNCOVERED is the false positive this arm's exemption exists for.
cat >> "$D/.github/workflows/pad.yml" <<'YAML'
      - run: env HELPER_GATE=1 npm run test:ci -- test/server/
YAML
expect_green "M16b wired helper gate needs no path coverage" "$D"

# --- M17: `!==` polarity is a live grammar arm -> RED when unwired ------------
# mu1.integration.test.ts uses `process.env.MU1_INTEGRATION !== "1"` -- a
# producer narrowing to `===` would silently drop it below the count floor's
# blind spot (a SUBSTITUTION, not a narrowing, is invisible to the floor).
D="$WORK/m17"; mkrepo "$D"
printf 'const G = process.env.NEQ_GATE !== "1";\n' > "$D/apps/web-platform/test/neq.test.ts"
( cd "$D" && git add -A )
expect_red "M17 unwired !== polarity" "$D" "NEQ_GATE"

# --- M18: a depth-1 dir token must NOT cover ----------------------------------
# `test/` alone collects nothing in the grammar (the sibling-dir hazard: a
# `test/` filter over test/server/x.test.ts would false-cover every root file
# too). Pin the deliberate rejection.
D="$WORK/m18"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/test/server"
printf 'const G = process.env.DEPTH1_GATE === "1";\n' > "$D/apps/web-platform/test/server/depth1.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/d1.yml" <<'YAML'
name: d1
on: [push]
jobs:
  d:
    runs-on: ubuntu-latest
    steps:
      - run: env DEPTH1_GATE=1 npm run test:ci -- test/
YAML
expect_red "M18 depth-1 test/ token does not collect" "$D" "depth1.test.ts"

# --- M19 (must-PASS): wiring lands in a *.yaml workflow ------------------------
D="$WORK/m19"; mkrepo "$D"
printf 'const G = process.env.YAML_GATE === "1";\n' > "$D/apps/web-platform/test/yaml-gated.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/wired.yaml" <<'YAML'
name: wired-yaml
on: [push]
jobs:
  y:
    runs-on: ubuntu-latest
    steps:
      - run: env YAML_GATE=1 npm run test:ci -- test/yaml-gated.test.ts
YAML
expect_green "M19 .yaml workflow file is a wiring surface" "$D"

# --- M20: string-literal `env X=1` in a run line is not a setting --------------
D="$WORK/m20"; mkrepo "$D"
printf 'const G = process.env.STR_GATE === "1";\n' > "$D/apps/web-platform/test/str.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/str.yml" <<'YAML'
name: str
on: [push]
jobs:
  s:
    runs-on: ubuntu-latest
    steps:
      - run: echo "env STR_GATE=1 npm run test:ci -- test/str.test.ts"
YAML
expect_red "M20 quoted env X=1 is not wiring" "$D" "STR_GATE"

# --- M21: mid-line `X: 1` in a run line is not a setting -----------------------
D="$WORK/m21"; mkrepo "$D"
printf 'const G = process.env.MID_GATE === "1";\n' > "$D/apps/web-platform/test/mid.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/mid.yml" <<'YAML'
name: mid
on: [push]
jobs:
  s:
    runs-on: ubuntu-latest
    steps:
      - run: echo "MID_GATE: 1"; npm run test:ci -- test/mid.test.ts
YAML
expect_red "M21 mid-line mapping token is not wiring" "$D" "MID_GATE"

# --- M22: lib/ collection semantics -- dir token rejected, file token ok ------
D="$WORK/m22"; mkrepo "$D"
mkdir -p "$D/apps/web-platform/lib"
printf 'const G = process.env.LIBCOL_GATE === "1";\n' > "$D/apps/web-platform/lib/lc.test.ts"
( cd "$D" && git add -A )
cat > "$D/.github/workflows/lc.yml" <<'YAML'
name: lc
on: [push]
jobs:
  l:
    runs-on: ubuntu-latest
    steps:
      - run: env LIBCOL_GATE=1 npm run test:ci -- lib/
YAML
expect_red "M22a depth-1 lib/ token does not collect" "$D" "lc.test.ts"
cat >> "$D/.github/workflows/lc.yml" <<'YAML'
      - run: npm run test:ci -- lib/lc.test.ts
YAML
expect_green "M22b explicit lib file token collects" "$D"

# --- M23: non-zero census below the floor -> RED -------------------------------
# M2 exercises only the == 0 arm; the `<` arm needed its own row (a floor
# loosened to admit a shrunken census, or `<=`, must still fire).
D="$WORK/m23"; mkrepo "$D"
cp "$SUT" "$WORK/sut-m23.sh"
mutate "$WORK/sut-m23.sh" "MIN_GATED_FILES=50" "MIN_GATED_FILES=999"
SOLEUR_LINT_GATES_ROOT="$D" bash "$WORK/sut-m23.sh" > "$WORK/out" 2>&1; rc=$?
rows_run=$((rows_run + 1))
if [[ "$rc" == "0" ]]; then
  notok "M23 sub-floor census -- expected RED, got 0"; cat "$WORK/out" >&2
elif ! grep -q "below the floor" "$WORK/out"; then
  notok "M23 sub-floor census -- RED but missing the floor arm's own error"; cat "$WORK/out" >&2
else
  ok "M23 sub-floor census"
fi

# --- M6: harness self-check -- deleting a row must red the battery -------------
# EXACT count, not a floor: a `>=` bound admits deleting rows unnoticed, which
# is the defect this row exists to make visible. Bump DECLARED_ROWS in the same
# edit that adds or removes a row.
DECLARED_ROWS=28
rows_run=$((rows_run + 1))
if (( rows_run == DECLARED_ROWS )); then
  ok "M6 battery executed ${rows_run}/${DECLARED_ROWS} rows (anti-vacuity)"
else
  notok "M6 battery executed ${rows_run} rows, expected ${DECLARED_ROWS} -- a deleted or added row went unrecorded"
fi

echo "integration-env-gates battery: ${passed} passed, ${failed} failed"
(( failed == 0 ))
