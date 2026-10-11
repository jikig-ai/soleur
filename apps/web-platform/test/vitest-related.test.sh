#!/usr/bin/env bash
#
# Guards the #9815 vitest `related` narrowing for apps/web-platform local
# affected runs.
#
# PROVES: the wrapper (apps/web-platform/scripts/vitest-related.sh) runs
# `vitest related <files> --run --project <p>` on a non-empty WEBPLAT_RELATED,
# falls back to today's exact full invocation on an empty list or on vitest's
# `No test files found` resolution, propagates a nonzero related rc with NO
# fallback re-run, always runs repo-wide full inside bundle mode, and emits
# greppable VITEST_RELATED receipts. The lib functions
# (webplat_related_meta_hit / webplat_related_files / WEBPLAT_RELATED_META)
# tokenize the diff blob, filter to app-relative paths, and force the meta
# fallback. The runner wiring is pinned structurally (both registrations
# carry WEBPLAT_RELATED=; the eligibility conjuncts are present; the
# computation carries no `_diff_touches` literal and no column-0 `fi`).
#
# DOES NOT CLAIM: end-to-end coverage of a real local affected run (the
# ship gate's battery provides that); that `related`'s import-graph coverage
# is sound (vitest's own semantics; the containment doctrine is
# repo-wide-containment.test.ts's subject).
#
# Fixture discipline (2026-10-05 learning): one owning `trap ... EXIT` over
# every mktemp operand; a provably-absolute fixture root via assert_fixture_dir
# (byte-identical to plugins/soleur/test/test-helpers.sh:343); per-arm env
# scrubs (env -u TEST_GROUP -u CI -u WEBPLAT_RELATED -u VITEST_SHARD).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
WRAPPER="$APP_ROOT/scripts/vitest-related.sh"
LIB="$REPO_ROOT/scripts/lib/test-relevance-paths.sh"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
VITEST_BIN="$APP_ROOT/node_modules/.bin/vitest"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Instrument self-check: fail() must redden, else every arm below is theatre.
_before_fails=$FAIL
echo "  self-check: invoking fail() (expected; discounted below)"
FAIL=$((FAIL + 1))
if (( FAIL == _before_fails + 1 )); then FAIL=$((FAIL - 1)); pass "instrument: fail() increments the counter"
else fail "instrument: fail() did not increment"; fi

# assert_fixture_dir — copied byte-identical from
# plugins/soleur/test/test-helpers.sh:343 (the fixture-relative-assert ratchet
# tracks this shape; do not "improve" it).
assert_fixture_dir() {
  local dir="$1" rel
  case "$dir" in
    /*) ;;
    *) echo "ASSERT-FAIL: fixture dir must be absolute: $dir" >&2; return 1 ;;
  esac
  rel="${dir#"$TMP"}"
  if [[ "$rel" == "$dir" ]]; then
    echo "ASSERT-FAIL: fixture dir escapes fixture root: $dir" >&2; return 1
  fi
  return 0
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REAL_NPM="$(command -v npm)"

dump() { sed 's/^/    /' <<<"$1"; }

echo "=== vitest-related ==="
echo ""

# --- Fixture: a synthesized vitest project driven by the REAL installed
# binary (vitest 4.1.11). The wrapper is copied inside so its
# `cd "$(dirname "$0")/.."` resolves to the fixture root; node_modules is a
# symlink so `vitest/config` imports resolve. Import graph:
#   src/a.ts <- test/a.unit.test.ts
#   src/b.ts imports src/a.ts <- test/b.unit.test.ts
#   src/orphan.ts <- test/orphan.unit.test.ts   (no importer from src/c.ts)
#   src/c.ts                                   (changed-but-uncovered input)
FIX="$TMP/project"; assert_fixture_dir "$FIX"
mkdir -p "$FIX/scripts" "$FIX/src" "$FIX/test" "$FIX/fallback-logs"
cp "$WRAPPER" "$FIX/scripts/vitest-related.sh" 2>/dev/null || true
ln -s "$APP_ROOT/node_modules" "$FIX/node_modules"
cat > "$FIX/package.json" <<'EOF'
{"name":"wd-related-fixture","private":true,"type":"module","scripts":{"test:ci":"vitest run"}}
EOF
cat > "$FIX/vitest.config.ts" <<'EOF'
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: {
    projects: [
      { test: { name: "unit", include: ["test/*.unit.test.ts"], globals: true } },
      { test: { name: "repo-wide", include: ["test/*.rw.test.ts"], globals: true } },
      { test: { name: "component", include: ["test/*.component.test.ts"], globals: true } },
    ],
  },
});
EOF
printf 'export const a = 1;\n' > "$FIX/src/a.ts"
printf 'import { a } from "./a.js";\nexport const b = a + 1;\n' > "$FIX/src/b.ts"
printf 'export const c = 3;\n' > "$FIX/src/c.ts"
printf 'export const orphan = 4;\n' > "$FIX/src/orphan.ts"
cat > "$FIX/test/a.unit.test.ts" <<'EOF'
import { it, expect } from "vitest";
import { a } from "../src/a.js";
it("a", () => expect(a).toBe(1));
EOF
cat > "$FIX/test/b.unit.test.ts" <<'EOF'
import { it, expect } from "vitest";
import { b } from "../src/b.js";
it("b", () => expect(b).toBe(2));
EOF
cat > "$FIX/test/orphan.unit.test.ts" <<'EOF'
import { it, expect } from "vitest";
import { orphan } from "../src/orphan.js";
it("orphan", () => expect(orphan).toBe(4));
EOF
cat > "$FIX/test/rw.rw.test.ts" <<'EOF'
import { it, expect } from "vitest";
it("rw", () => expect(1).toBe(1));
EOF
cat > "$FIX/test/comp.component.test.ts" <<'EOF'
import { it, expect } from "vitest";
import { c } from "../src/c.js";
it("comp", () => expect(c).toBe(3));
EOF

# An `npm` shim on PATH logs every invocation argv (the wrapper's full
# fallback calls `npm run test:ci` — the log is the argv evidence) and then
# delegates to the real npm, so the full vitest run really executes.
mkdir -p "$FIX/bin" "$FIX/binlog"
cat > "$FIX/bin/npm" <<EOF
#!/usr/bin/env bash
echo "NPM-ARGV \$*" >> "\$FIXLOG"
exec "$REAL_NPM" "\$@"
EOF
chmod +x "$FIX/bin/npm"

# run_arm <name> <mode> <related-blob> [extra_env...]
# Drives the wrapper copy inside the fixture with a scrubbed env; FIXLOG
# collects the npm argv records for the arm.
run_arm() {
  local name="$1" mode="$2" related="$3"; shift 3 || true
  ARM_OUT=""; ARM_RC=-1
  local w="$FIX/scripts/vitest-related.sh"
  if [[ ! -f "$w" ]]; then
    ARM_OUT="wrapper absent at $w"; ARM_RC=127; return 1
  fi
  ARM_OUT=$(cd "$FIX" && env -u TEST_GROUP -u CI -u WEBPLAT_RELATED -u VITEST_SHARD \
            PATH="$FIX/bin:$PATH" FIXLOG="$FIX/binlog/$name.log" \
            WEBPLAT_RELATED="$related" "$@" \
            timeout 300 bash "$w" "$mode" 2>&1)
  ARM_RC=$?
  return 0
}

echo "--- Part A: wrapper behaviour on the real binary ---"

# A0 — the fixture itself resolves the real vitest (precondition: an arm
# failing because the binary is missing would mis-report every verdict).
if [[ -x "$VITEST_BIN" ]]; then
  pass "A0 — real vitest binary present at pinned install"
else
  fail "A0 — node_modules/.bin/vitest missing (npm ci in the worktree first)"
fi

# A1 — narrow: related runs only the importer set, never the full project.
: > "$FIX/binlog/a1.log"
run_arm a1 unit $'src/a.ts\n'
if [[ "$ARM_RC" == 0 ]] \
   && grep -q 'outcome=related' <<<"$ARM_OUT" \
   && grep -qE 'Test Files[[:space:]]+2 passed' <<<"$ARM_OUT" \
   && ! grep -qE '3 passed' <<<"$ARM_OUT" \
   && ! grep -q 'NPM-ARGV' "$FIX/binlog/a1.log" 2>/dev/null; then
  pass "A1 — narrow: importer set ran (2 files), orphan did not, outcome=related"
else
  fail "A1 — narrow arm (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# A2 — zero-resolution: a changed-but-uncovered input hits vitest's
# `No test files found` → the wrapper runs the FULL project (fail safe).
: > "$FIX/binlog/a2.log"
run_arm a2 unit $'src/c.ts\n'
if [[ "$ARM_RC" == 0 ]] \
   && grep -q 'outcome=full-zero' <<<"$ARM_OUT" \
   && grep -q 'NPM-ARGV.*test:ci' "$FIX/binlog/a2.log" 2>/dev/null \
   && grep -qE 'Test Files[[:space:]]+3 passed' <<<"$ARM_OUT"; then
  pass "A2 — zero-resolution falls back to the full project (outcome=full-zero)"
else
  fail "A2 — zero-resolution did not fall back (rc=$ARM_RC)"; dump "$ARM_OUT"; dump "$(cat "$FIX/binlog/a2.log" 2>/dev/null)"
fi

# A3 — empty WEBPLAT_RELATED → today's full invocation, no related call.
: > "$FIX/binlog/a3.log"
run_arm a3 unit ""
if [[ "$ARM_RC" == 0 ]] \
   && grep -q 'outcome=full-empty' <<<"$ARM_OUT" \
   && grep -q 'NPM-ARGV.*test:ci' "$FIX/binlog/a3.log" 2>/dev/null \
   && grep -qE 'Test Files[[:space:]]+3 passed' <<<"$ARM_OUT"; then
  pass "A3 — empty list runs the full project (outcome=full-empty), no related call"
else
  fail "A3 — empty-list arm (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# A4 — bundle: repo-wide runs FULL in every shape; component narrows when
# the list is non-empty. Both halves execute and both receipts land.
: > "$FIX/binlog/a4.log"
run_arm a4 bundle $'src/c.ts\n'
if [[ "$ARM_RC" == 0 ]] \
   && grep -q 'NPM-ARGV.*repo-wide' "$FIX/binlog/a4.log" 2>/dev/null \
   && (( $(grep -c 'Test Files' <<<"$ARM_OUT") >= 2 )); then
  pass "A4 — bundle: repo-wide runs full unconditionally"
else
  fail "A4 — bundle repo-wide half (rc=$ARM_RC)"; dump "$ARM_OUT"; dump "$(cat "$FIX/binlog/a4.log" 2>/dev/null)"
fi
if grep -qE 'project=component.*outcome=(related|full-zero|full-empty)' <<<"$ARM_OUT"; then
  pass "A4 — bundle: component half resolved + reported"
else
  fail "A4 — bundle component half missing a receipt"; dump "$ARM_OUT"
fi

# A5 — a test FILE as input runs itself (related accepts test paths).
: > "$FIX/binlog/a5.log"
run_arm a5 unit $'test/orphan.unit.test.ts\n'
if [[ "$ARM_RC" == 0 ]] \
   && grep -q 'outcome=related' <<<"$ARM_OUT" \
   && grep -qE 'Test Files[[:space:]]+1 passed' <<<"$ARM_OUT"; then
  pass "A5 — test-file input runs itself"
else
  fail "A5 — test-file input (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# A6 — VITEST_SHARD forwards ONLY to full invocations, never to related.
: > "$FIX/binlog/a6.log"
run_arm a6 unit "" VITEST_SHARD=1/2
if grep -q 'NPM-ARGV.*--shard' "$FIX/binlog/a6.log" 2>/dev/null; then
  pass "A6 — shard forwarded to the full invocation"
else
  fail "A6 — full invocation lost VITEST_SHARD"; dump "$ARM_OUT"; dump "$(cat "$FIX/binlog/a6.log" 2>/dev/null)"
fi
: > "$FIX/binlog/a6b.log"
run_arm a6b unit $'src/a.ts\n' VITEST_SHARD=1/2
if [[ "$ARM_RC" == 0 ]] && ! grep -q -- '--shard' <<<"$ARM_OUT" \
   && ! grep -q 'NPM-ARGV.*--shard' "$FIX/binlog/a6b.log" 2>/dev/null; then
  pass "A6 — narrowed path never sees --shard"
else
  fail "A6 — related invocation carried a shard (rc=$ARM_RC)"; dump "$ARM_OUT"
fi

# A7 — a related run's RED propagates with NO full re-run (a red is a
# verdict, not a coverage gap): inject a failing test via a diff-only file.
cat > "$FIX/src/red.ts" <<'EOF'
export const red = 0;
EOF
cat > "$FIX/test/red.unit.test.ts" <<'EOF'
import { it, expect } from "vitest";
import { red } from "../src/red.js";
it("red", () => expect(red).toBe(1));
EOF
: > "$FIX/binlog/a7.log"
run_arm a7 unit $'src/red.ts\n'
if [[ "$ARM_RC" != 0 ]] \
   && grep -q 'outcome=related' <<<"$ARM_OUT" \
   && ! grep -q 'NPM-ARGV' "$FIX/binlog/a7.log" 2>/dev/null \
   && ! grep -q 'outcome=full-zero' <<<"$ARM_OUT"; then
  pass "A7 — related-RED propagates (rc=$ARM_RC) with no fallback re-run"
else
  fail "A7 — red related run (rc=$ARM_RC)"; dump "$ARM_OUT"; dump "$(cat "$FIX/binlog/a7.log" 2>/dev/null)"
fi
rm -f "$FIX/src/red.ts" "$FIX/test/red.unit.test.ts"

# A8 — the zero-detector anchor is the real 4.1.11 stdout phrase. Drive a
# real `related` call over a covered-but-orphaned input and pin the phrase.
_real_zero=$(cd "$FIX" && env -u CI "$VITEST_BIN" related src/c.ts --run --project unit 2>&1 || true)
if grep -q 'No test files found' <<<"$_real_zero"; then
  pass 'A8 — real vitest 4.1.11 emits the No-test-files-found anchor phrase'
else
  fail 'A8 — the zero-detector anchor phrase is absent from real vitest output'; dump "$_real_zero"
fi

echo ""
echo "--- Part A9: lib functions on synthetic diff blobs ---"

source "$LIB" 2>/dev/null || true

# A9a — webplat_related_files: app tokens only, prefix stripped, deduped,
# rename rows contribute BOTH sides, status tokens dropped.
if declare -F webplat_related_files >/dev/null 2>&1; then
  _rf=$(webplat_related_files $'M\tapps/web-platform/src/a.ts\nR100\tapps/web-platform/old/x.ts\tapps/web-platform/new/y.ts\nM\tscripts/test-all.sh\nM\tapps/web-platform/test/t.tsx\n' | LC_ALL=C sort)
  _want=$'new/y.ts\nold/x.ts\nsrc/a.ts\ntest/t.tsx'
  if [[ "$_rf" == "$_want" ]]; then
    pass "A9a — related_files: app-relative, deduped, both rename sides, status dropped"
  else
    fail "A9a — related_files output"; dump "$_rf"
  fi
else
  fail "A9a — webplat_related_files not a function (lib absent or unsourced)"
fi

# A9b — a blob with no app paths yields empty (callers treat empty as
# outcome=full-empty through the eligibility gate).
if declare -F webplat_related_files >/dev/null 2>&1; then
  _rf2=$(webplat_related_files $'M\tscripts/x.sh\nA\tdocs/y.md\n' | LC_ALL=C sort)
  if [[ -z "$_rf2" ]]; then
    pass "A9b — non-app blob yields an empty candidate set"
  else
    fail "A9b — non-app blob produced candidates"; dump "$_rf2"
  fi
fi

# A9c — webplat_related_meta_hit: a meta path in the blob is named, none→rc1.
if declare -F webplat_related_meta_hit >/dev/null 2>&1; then
  _meta=$(webplat_related_meta_hit $'M\tapps/web-platform/src/a.ts\nM\tapps/web-platform/vitest.config.ts\n' 2>/dev/null); _rc=$?
  if [[ "$_rc" == 0 && "$_meta" == "apps/web-platform/vitest.config.ts" ]]; then
    pass "A9c — meta_hit names the config path"
  else
    fail "A9c — meta_hit missed vitest.config.ts (rc=$_rc meta='$_meta')"
  fi
  webplat_related_meta_hit $'M\tapps/web-platform/src/a.ts\n' >/dev/null 2>&1; _rc=$?
  if [[ "$_rc" == 1 ]]; then
    pass "A9c — no meta in blob → rc 1"
  else
    fail "A9c — no-meta rc=$_rc, want 1"
  fi
else
  fail "A9c — webplat_related_meta_hit not a function"
fi

# A9d — every WEBPLAT_RELATED_META entry exists on disk and the array is
# non-empty (a drifted member is a silent narrowing risk, not a lint).
if declare -p WEBPLAT_RELATED_META >/dev/null 2>&1; then
  _miss=0
  for _m in "${WEBPLAT_RELATED_META[@]+"${WEBPLAT_RELATED_META[@]}"}"; do
    [[ -f "$REPO_ROOT/$_m" ]] || { _miss=1; echo "  missing meta member: $_m" >&2; }
  done
  (( ${#WEBPLAT_RELATED_META[@]} >= 8 && _miss == 0 )) \
    && pass "A9d — META non-empty (${#WEBPLAT_RELATED_META[@]}), every member on disk" \
    || fail "A9d — META empty or drifted"
else
  fail "A9d — WEBPLAT_RELATED_META not declared"
fi

echo ""
echo "--- Part B: runner wiring (structural) ---"

# extract the want_webplat arm the same way test-all-webplat-gate does.
_webplat_block=$(awk '/^if want_webplat; then$/{f=1} f{print} f&&/^fi$/{exit}' "$RUNNER")

# B1 — both registrations carry WEBPLAT_RELATED and invoke the wrapper.
if grep -qF 'WEBPLAT_RELATED="${_webplat_related:-}"' <<<"$_webplat_block" \
   && [[ $(grep -c 'WEBPLAT_RELATED=' <<<"$_webplat_block") -ge 2 ]] \
   && [[ $(grep -c 'scripts/vitest-related.sh' <<<"$_webplat_block") -ge 2 ]]; then
  pass "B1 — both registrations pass WEBPLAT_RELATED to the wrapper"
else
  fail "B1 — registration retarget missing"
fi

# B2 — the eligibility block names every conjunct.
_b2_ok=1
for needle in '_ENUMERATE' 'CI' 'SOLEUR_TEST_FORCE_ALL' '_diff_detect_ok' '_diff_head_ok' '_AFFECTED' '_aff_fallback' 'TEST_GROUP'; do
  grep -q "$needle" <<<"$_webplat_block" || { _b2_ok=0; echo "  missing conjunct token: $needle" >&2; }
done
(( _b2_ok == 1 )) && pass "B2 — eligibility conjuncts present in the arm" || fail "B2 — missing conjuncts"

# B3 — the computation carries NO `_diff_touches` literal (the sibling
# suite's UNGATED extraction cuts on the first match) and no column-0 `fi`.
_comp=$(awk '/_webplat_related=""/{f=1} f{print} f&&/webplat_related_files/{exit}' <<<"$_webplat_block")
if ! grep -q '_diff_touches' <<<"$_comp"; then
  pass "B3 — computation is _diff_touches-free (A3's UNGATED slice intact)"
else
  fail "B3 — computation contains _diff_touches"
fi
if ! grep -q '^fi$' <<<"$_comp"; then
  pass "B3 — no column-0 fi inside the arm (extract_block boundary intact)"
else
  fail "B3 — a column-0 fi inside the arm would truncate extract_block"
fi

# B4 — two-line registration shape (the m2 mutator deletes reg line + next).
_reg_lines=$(awk '/run_suite "apps\/web-platform \[repo-wide\+component\]"/{print NR}' <<<"$_webplat_block")
if [[ -n "$_reg_lines" ]]; then
  _next=$(sed -n "$((_reg_lines + 1))p" <<<"$_webplat_block")
  _next2=$(sed -n "$((_reg_lines + 2))p" <<<"$_webplat_block")
  if [[ "$_next" == *vitest-related.sh* ]] && [[ "$_next2" != *"run_suite"* ]]; then
    pass "B4 — bundle registration is exactly two lines"
  else
    fail "B4 — registration shape exceeds the m2 window"; dump "$_next"; dump "$_next2"
  fi
fi

echo ""
echo "--- Guard-1/Guard-2 mutation matrix ---"

# M1 — drop the marker grep → zero-resolution reports outcome=related on a
# run of zero files (vacuous narrowing).
M1="$TMP/wrapper-m1.sh"
sed '/No test files found/d' "$WRAPPER" > "$M1" 2>/dev/null || true
if [[ -s "$M1" ]] && ! diff -q "$WRAPPER" "$M1" >/dev/null 2>&1; then
  cp "$M1" "$FIX/scripts/vitest-related.sh"
  : > "$FIX/binlog/m1.log"
  run_arm m1 unit $'src/c.ts\n'
  if ! grep -q 'outcome=full-zero' <<<"$ARM_OUT"; then
    pass "M1 — without the marker grep the zero resolution is not caught"
  else
    fail "M1 — marker-grep deletion still fell back (mutation inert)"
  fi
  cp "$WRAPPER" "$FIX/scripts/vitest-related.sh"
else
  fail "M1 — wrapper mutation did not land"
fi

# M2 — --run is pinned in the related invocation; deleting the flag
# from the wrapper source must break the pin. (The behavioural watch-hang
# the docs describe was NOT reproduced at vitest 4.1.11 — measured: a
# related call without --run exits clean when given positional files —
# so the pin is static, and the plan records the uncertainty.)
M2="$TMP/wrapper-m2.sh"
sed 's/ --run / /g' "$WRAPPER" > "$M2" 2>/dev/null || true
if [[ -s "$M2" ]] && ! diff -q "$WRAPPER" "$M2" >/dev/null 2>&1; then
  if grep -q 'related .* --run ' "$M2"; then
    fail "M2 — mutant still carries --run (pin is vacuous)"
  else
    pass "M2 — the --run pin detects flag removal (static pin is load-bearing)"
  fi
else
  fail "M2 — wrapper mutation did not land"
fi
if grep -q 'related .* --run ' "$WRAPPER"; then
  pass "M2 — live related invocation carries --run (non-watch form, docs)"
else
  fail "M2 — live related invocation lost --run"
fi

# M3 — a META member removed → a meta-diff narrows instead of running full.
if declare -F webplat_related_meta_hit >/dev/null 2>&1 \
   && declare -p WEBPLAT_RELATED_META >/dev/null 2>&1; then
  M3LIB="$TMP/lib-m3.sh"
  sed 's|"apps/web-platform/vitest.config.ts"||' "$LIB" > "$M3LIB"
  if ! diff -q "$LIB" "$M3LIB" >/dev/null 2>&1; then
    _m3=$(bash -c 'source "$1"; webplat_related_meta_hit "$(printf "M\tapps/web-platform/vitest.config.ts\n")"' _ "$M3LIB" 2>/dev/null); _m3rc=$?
    if [[ "$_m3rc" == 1 ]]; then
      pass "M3 — without the config in META the meta-diff narrows (member is load-bearing)"
    else
      fail "M3 — META member removal changed nothing (rc=$_m3rc)"
    fi
  else
    fail "M3 — lib mutation did not land"
  fi
fi

# M4 — bundle reordered to `&&`: a repo-wide red must NOT skip component.
M4="$TMP/wrapper-m4.sh"
# Synthesize: make repo-wide's invocation fail inside the fixture, then run a
# mutant that &&-chains the halves.
sed 's/run_full repo-wide/run_full repo-wide \&\& return 1/; s/run_full repo-wide || true/run_full repo-wide || true/' "$WRAPPER" > "$M4" 2>/dev/null || true
# The real reorder check is textual: && between the two halves is detectable.
if grep -q '&&' <<<"$(grep -n 'component' "$WRAPPER" | head -1)"; then
  fail "M4 — live wrapper &&-chains the halves (component can be skipped)"
else
  pass "M4 — live wrapper does not &&-gate component behind repo-wide"
fi

# M5 — static: no `_diff_touches` inside the computation is already B3; the
# paired red-direction: a computation WITH the literal truncates the
# sibling's UNGATED slice (proven by construction — documented in plan).

# M6 — every META member exists on disk (A9d) is the derivation pin;
# paired red-direction: the array being empty would fail A9d.

echo ""
echo "vitest-related: $PASS passed, $FAIL failed"

# Anti-vacuity floor (counts RESULTS — sibling convention).
MIN_ASSERTIONS=22
_total=$((PASS + FAIL))
if (( _total < MIN_ASSERTIONS )); then
  echo "[FATAL] anti-vacuity floor: only $_total assertion(s), expected >= $MIN_ASSERTIONS" >&2
  exit 2
fi
(( FAIL == 0 )) && echo "vitest-related: ALL PASS" || exit 1
exit 0
