#!/usr/bin/env bash
# Tests for scripts/lint-window-closure-assertion.py.
#
# The defect: a closure assertion (`toEqual([...])`) derived from a REGEX-
# EXTRACTED WINDOW of a source file pins only what the window happens to span.
# The originating instance is `sandboxWindow()` in
# plugins/soleur/test/preflight-discoverability-test.test.ts, which scoped to
# `BWRAP_ARGS=( … )` while GIT_BIND, BWRAP_PROC and the exec line ALSO injected
# mounts — three one-line edits each re-opened the operator's credential surface
# with the whole suite green.
#
# What this lint enforces is a DECLARATION, not semantic completeness: no static
# checker can prove a window equals its assembly. It forces the author to name
# the assembly at the point of the defect, per helper, exactly as the plan-time
# Guard Contract forces it at design time. That is the honest scope.
#
# Every fixture is SYNTHESIZED under mktemp (cq-test-fixtures-synthesized-only).
#
# Exit contract of the SUT: 0 PASS/skip, 1 FAIL, 2 argument/IO error.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-window-closure-assertion.py"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

WORK="$(mktemp -d)" || { echo "harness: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# write_test_file <path> <<'EOF' ... EOF
write_test_file() {
  mkdir -p "$(dirname "$1")" || return 1
  cat > "$1"
}

run_sut() {
  local dir="$1"; shift
  local out rc
  set +e
  out="$(cd "$dir" && python3 "$SUT" --repo-root "$dir" "$@" 2>&1)"
  rc=$?
  set -e
  printf 'rc=%s\n%s\n' "$rc" "$out"
}

assert_case() {
  local label="$1" want_rc="$2" needle="$3" dir="$4"; shift 4
  local combined rc body
  combined="$(run_sut "$dir" "$@")"
  rc="${combined%%$'\n'*}"; rc="${rc#rc=}"
  body="${combined#*$'\n'}"
  if [[ "$rc" != "$want_rc" ]]; then
    fail "$label" "expected rc=$want_rc got rc=$rc; output: $(printf '%s' "$body" | head -4 | tr '\n' ' ')"
    return
  fi
  if [[ -n "$needle" ]] && ! grep -qF -- "$needle" <<<"$body"; then
    fail "$label" "rc ok but needle '$needle' absent; output: $(printf '%s' "$body" | head -4 | tr '\n' ' ')"
    return
  fi
  pass "$label"
}

# ---------------------------------------------------------------------------
# TS-0: SUT exists
# ---------------------------------------------------------------------------
if [[ ! -f "$SUT" ]]; then
  echo "FAIL: TS-0 SUT missing at $SUT"
  echo "RED as expected before implementation."
  exit 1
fi

ROOT_REL="plugins/soleur/test"

# ---------------------------------------------------------------------------
# TS-1: window helper + closure assertion, NO declaration -> RED
# ---------------------------------------------------------------------------
D1="$WORK/ts1"
write_test_file "$D1/$ROOT_REL/bad.test.ts" <<'EOF'
const sandboxWindow = (): string => {
  return src.match(/BWRAP_ARGS=\(([^)]*)\)/)![1];
};
it("pins the mount set", () => {
  expect(mountsIn(sandboxWindow())).toEqual(["/repo", "/tmp"]);
});
EOF
assert_case "TS-1 undeclared window + closure assertion fails" 1 "sandboxWindow" "$D1"

# ---------------------------------------------------------------------------
# TS-2: same file WITH a per-helper declaration -> PASS
# ---------------------------------------------------------------------------
D2="$WORK/ts2"
write_test_file "$D2/$ROOT_REL/good.test.ts" <<'EOF'
// window-assembly: sandboxWindow — the mount set is BWRAP_ARGS plus GIT_BIND,
// BWRAP_PROC and the exec line; a sibling assertion below pins the union.
const sandboxWindow = (): string => {
  return src.match(/BWRAP_ARGS=\(([^)]*)\)/)![1];
};
it("pins the mount set", () => {
  expect(mountsIn(sandboxWindow())).toEqual(["/repo", "/tmp"]);
});
EOF
assert_case "TS-2 declared window passes" 0 "" "$D2"

# ---------------------------------------------------------------------------
# TS-3: window helper but NO closure assertion -> PASS (not in scope)
# ---------------------------------------------------------------------------
D3="$WORK/ts3"
write_test_file "$D3/$ROOT_REL/nowin.test.ts" <<'EOF'
const gateWindow = (): string => src.slice(0, 100);
it("checks a substring", () => {
  expect(gateWindow()).toContain("hello");
});
EOF
assert_case "TS-3 window without closure assertion is out of scope" 0 "" "$D3"

# ---------------------------------------------------------------------------
# TS-4: closure assertion but NO window helper -> PASS
# ---------------------------------------------------------------------------
D4="$WORK/ts4"
write_test_file "$D4/$ROOT_REL/plain.test.ts" <<'EOF'
it("pins a list", () => {
  expect(collect()).toEqual(["a", "b"]);
});
EOF
assert_case "TS-4 closure assertion without a window helper is out of scope" 0 "" "$D4"

# ---------------------------------------------------------------------------
# TS-5: TWO helpers, only the FIRST declared -> RED naming the SECOND.
# The per-helper (not per-file) requirement: a single marker must not cover an
# undeclared sibling. This is the first-member degradation class.
# ---------------------------------------------------------------------------
D5="$WORK/ts5"
write_test_file "$D5/$ROOT_REL/two.test.ts" <<'EOF'
// window-assembly: firstWindow — declared.
const firstWindow = (): string => src.match(/A=\((.*)\)/)![1];
const secondRegion = (): string => src.match(/B=\((.*)\)/)![1];
it("pins both", () => {
  expect(a(firstWindow())).toEqual(["x"]);
  expect(b(secondRegion())).toEqual(["y"]);
});
EOF
assert_case "TS-5 undeclared SECOND helper fails (per-helper, not per-file)" 1 "secondRegion" "$D5"

# ---------------------------------------------------------------------------
# TS-6: allowlisted helper -> PASS
# ---------------------------------------------------------------------------
D6="$WORK/ts6"
write_test_file "$D6/$ROOT_REL/legacy.test.ts" <<'EOF'
const legacyWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(legacyWindow())).toEqual(["x"]); });
EOF
printf '%s\n' "$ROOT_REL/legacy.test.ts::legacyWindow" > "$D6/allow.txt"
assert_case "TS-6 allowlisted helper passes" 0 "" "$D6" --allowlist allow.txt

# ---------------------------------------------------------------------------
# TS-7: allowlist covers ONE helper, a second undeclared one still fails.
# An allowlist entry must not become a whole-file waiver.
# ---------------------------------------------------------------------------
D7="$WORK/ts7"
write_test_file "$D7/$ROOT_REL/legacy2.test.ts" <<'EOF'
const legacyWindow = (): string => src.match(/A=\((.*)\)/)![1];
const freshWindow = (): string => src.match(/B=\((.*)\)/)![1];
it("pins", () => {
  expect(a(legacyWindow())).toEqual(["x"]);
  expect(b(freshWindow())).toEqual(["y"]);
});
EOF
printf '%s\n' "$ROOT_REL/legacy2.test.ts::legacyWindow" > "$D7/allow.txt"
assert_case "TS-7 allowlist entry is per-helper, not a file waiver" 1 "freshWindow" "$D7" --allowlist allow.txt

# ---------------------------------------------------------------------------
# TS-8: a file relocated one directory DEEPER is still found (directory walk,
# not a fixed glob depth).
# ---------------------------------------------------------------------------
D8="$WORK/ts8"
write_test_file "$D8/$ROOT_REL/nested/deeper/bad.test.ts" <<'EOF'
const deepWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(deepWindow())).toEqual(["x"]); });
EOF
assert_case "TS-8 nested test file is found by the walk" 1 "deepWindow" "$D8"

# ---------------------------------------------------------------------------
# TS-9: the OTHER test root is walked too.
# ---------------------------------------------------------------------------
D9="$WORK/ts9"
write_test_file "$D9/apps/web-platform/test/other.test.ts" <<'EOF'
const otherWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(otherWindow())).toEqual(["x"]); });
EOF
assert_case "TS-9 second test root is walked" 1 "otherWindow" "$D9"

# ---------------------------------------------------------------------------
# TS-10: dispatch count is reported (so MUT:floor has something to neuter).
# ---------------------------------------------------------------------------
combined="$(run_sut "$D2")"
if grep -qE 'scanned [0-9]+ test file' <<<"$combined"; then
  pass "TS-10 SUT reports a dispatch count"
else
  fail "TS-10 SUT reports a dispatch count" "$(printf '%s' "$combined" | head -3 | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# TS-11: an EMPTY tree (zero test files) must FAIL, not silently exit 0.
# A gate that dispatches nothing must never report success — the anti-vacuity
# floor on its own dispatch (the fourth instance from the originating evidence).
# ---------------------------------------------------------------------------
D11="$WORK/ts11"; mkdir -p "$D11/$ROOT_REL" || exit 2
assert_case "TS-11 zero scanned files fails (anti-vacuity floor)" 1 "scanned 0" "$D11"

# ---------------------------------------------------------------------------
# TS-12 (W-5): .test.tsx / .spec.ts are the SAME defect surface. 247 such files
# exist in-repo and were entirely outside the walk.
# ---------------------------------------------------------------------------
D12="$WORK/ts12"
write_test_file "$D12/$ROOT_REL/benign.test.ts" <<'EOF'
it("nothing", () => { expect(1).toBe(1); });
EOF
write_test_file "$D12/$ROOT_REL/bad.test.tsx" <<'EOF'
const tsxWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(tsxWindow())).toEqual(["x"]); });
EOF
assert_case "TS-12 .test.tsx is in scope" 1 "tsxWindow" "$D12"

D13="$WORK/ts13"
write_test_file "$D13/$ROOT_REL/bad.spec.ts" <<'EOF'
const specWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(specWindow())).toEqual(["x"]); });
EOF
assert_case "TS-13 .spec.ts is in scope" 1 "specWindow" "$D13"

# ---------------------------------------------------------------------------
# TS-14 (B2/B3/B7): declaration forms HELPER_RE could not see. Each moved a real
# window helper out of reach at zero cost.
# ---------------------------------------------------------------------------
D14="$WORK/ts14"
write_test_file "$D14/$ROOT_REL/forms.test.ts" <<'EOF'
const helpers = { objWindow: (s: string) => s.match(/A=\((.*)\)/)![1] };
it("pins", () => { expect(a(helpers.objWindow(src))).toEqual(["x"]); });
EOF
assert_case "TS-14 an object-property helper is in scope" 1 "objWindow" "$D14"

D15="$WORK/ts15"
write_test_file "$D15/$ROOT_REL/asyncform.test.ts" <<'EOF'
export async function asyncWindow(): Promise<string> { return src.match(/A=\((.*)\)/)![1]; }
it("pins", () => { expect(a(asyncWindow())).toEqual(["x"]); });
EOF
assert_case "TS-15 an async/exported function helper is in scope" 1 "asyncWindow" "$D15"

# ---------------------------------------------------------------------------
# TS-16 (C2): hoisting the expected array to a const took the WHOLE FILE out of
# scope, because the closure test is a file-level switch.
# ---------------------------------------------------------------------------
D16="$WORK/ts16"
write_test_file "$D16/$ROOT_REL/constexpected.test.ts" <<'EOF'
const EXPECTED_MOUNTS = ["/repo", "/tmp"];
const hoistWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(mountsIn(hoistWindow())).toEqual(EXPECTED_MOUNTS); });
EOF
assert_case "TS-16 toEqual(CONST) is still a closure assertion" 1 "hoistWindow" "$D16"

# ---------------------------------------------------------------------------
# TS-17 (D1/W-4): a bare marker with no justification satisfied the gate. The
# plan's stated property requires a justification; the gate did not enforce it.
# ---------------------------------------------------------------------------
D17="$WORK/ts17"
write_test_file "$D17/$ROOT_REL/bare.test.ts" <<'EOF'
// window-assembly: bareWindow
const bareWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(bareWindow())).toEqual(["x"]); });
EOF
assert_case "TS-17 a declaration with no justification is rejected" 1 "justification" "$D17"

# ---------------------------------------------------------------------------
# TS-18: node_modules must be excluded. 492 of 1420 "scanned" files were
# vendored, so the anti-vacuity floor could be satisfied by third-party code and
# a dependency bump could red CI on code the author cannot edit.
# ---------------------------------------------------------------------------
D18="$WORK/ts18"
write_test_file "$D18/$ROOT_REL/ok.test.ts" <<'EOF'
// window-assembly: fineWindow — pinned by the sibling assertion below.
const fineWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(fineWindow())).toEqual(["x"]); });
EOF
write_test_file "$D18/apps/web-platform/node_modules/vendor/v.test.ts" <<'EOF'
const vendorWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(vendorWindow())).toEqual(["x"]); });
EOF
assert_case "TS-18 node_modules is excluded from the walk" 0 "" "$D18"

# ---------------------------------------------------------------------------
# TS-19 (M-9): a stale allowlist entry naming a file that no longer exists must
# be reported. "Members drift; assembly is structural" applies to the allowlist.
# ---------------------------------------------------------------------------
D19="$WORK/ts19"
write_test_file "$D19/$ROOT_REL/present.test.ts" <<'EOF'
it("nothing", () => { expect(1).toBe(1); });
EOF
printf '%s
' "$ROOT_REL/gone.test.ts::ghostWindow" > "$D19/allow.txt"
assert_case "TS-19 a stale allowlist entry is reported" 1 "stale" "$D19" --allowlist allow.txt

# ---------------------------------------------------------------------------
# TS-20 (w4): TWO in-scope files, the FIRST compliant and the SECOND not. Every
# other fixture holds exactly one in-scope file, which is what let
# `find_test_files(root)[:1]` survive the whole battery — the gate proved
# all-members at the HELPER level and first-member at the FILE level.
# ---------------------------------------------------------------------------
D20="$WORK/ts20"
write_test_file "$D20/$ROOT_REL/aaa-first.test.ts" <<'EOF'
// window-assembly: firstFileWindow — pinned by the sibling assertion below.
const firstFileWindow = (): string => src.match(/A=\((.*)\)/)![1];
it("pins", () => { expect(a(firstFileWindow())).toEqual(["x"]); });
EOF
write_test_file "$D20/$ROOT_REL/zzz-second.test.ts" <<'EOF'
const secondFileWindow = (): string => src.match(/B=\((.*)\)/)![1];
it("pins", () => { expect(b(secondFileWindow())).toEqual(["y"]); });
EOF
assert_case "TS-20 the SECOND in-scope file is checked (all-files, not first-file)" 1 "secondFileWindow" "$D20"

# ---------------------------------------------------------------------------
# MB — mutation battery.
# ---------------------------------------------------------------------------
PRISTINE="$WORK/pristine.py"
cp "$SUT" "$PRISTINE" || { echo "harness: cp failed" >&2; exit 2; }

mb_case() {
  local label="$1" marker="$2" dir="$3"; shift 3
  local mutant="$WORK/mutant-$marker.py"
  cp "$PRISTINE" "$mutant" || { fail "$label" "cp failed"; return; }
  grep -v "# MUT:${marker}\b" "$mutant" > "$mutant.new" 2>/dev/null || true
  mv "$mutant.new" "$mutant"
  if diff -q "$PRISTINE" "$mutant" >/dev/null 2>&1; then
    fail "$label" "mutation marker '$marker' matched nothing"
    return
  fi
  local out rc
  set +e
  out="$(cd "$dir" && python3 "$mutant" --repo-root "$dir" "$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" == "0" ]]; then
    pass "$label"
  else
    fail "$label" "mutant still failed (rc=$rc): $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
  fi
}

mb_case "MB-1 deleting the declaration check makes TS-1 pass" marker "$D1"
mb_case "MB-2 deleting the zero-dispatch floor makes TS-11 pass" floor "$D11"
mb_case "MB-3 deleting the justification check makes TS-17 pass" justification "$D17"
mb_case "MB-4 deleting the stale-allowlist check makes TS-19 pass" stale "$D19" --allowlist allow.txt

# ---------------------------------------------------------------------------
# Anti-vacuity floor on THIS harness's own dispatch.
# ---------------------------------------------------------------------------
EXPECTED_MIN=24
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  echo "FAIL: harness dispatched only $TOTAL assertions (expected >= $EXPECTED_MIN) — vacuous run" >&2
  exit 1
fi

echo
echo "lint-window-closure-assertion: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -eq 0 ]] || exit 1
