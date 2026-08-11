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

# ---------------------------------------------------------------------------
# Anti-vacuity floor on THIS harness's own dispatch.
# ---------------------------------------------------------------------------
EXPECTED_MIN=13
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  echo "FAIL: harness dispatched only $TOTAL assertions (expected >= $EXPECTED_MIN) — vacuous run" >&2
  exit 1
fi

echo
echo "lint-window-closure-assertion: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -eq 0 ]] || exit 1
