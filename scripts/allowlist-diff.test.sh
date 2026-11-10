#!/usr/bin/env bash
# Tests for apps/web-platform/scripts/allowlist-diff.sh (the secret-scan allowlist-widening gate, #3323).
#
# This suite lives in scripts/, NOT next to its subject: apps/web-platform/scripts/ is in
# guard-vacuity-floor's DEFERRED_DIRS (shrink-only), so a floor-bearing suite born there reddens ARM 5c.
#
# WHY THIS SUITE EXISTS (D7 remainder). The gate's first step decides whether .gitleaks.toml changed at all
# and skips the whole widening check when it did not. That decision used to be
#   grep -Fxq '.gitleaks.toml' < <(git diff --name-only BASE..HEAD)
# which fails open three ways: (1) a failing git diff (bad SHA, shallow clone) is an EMPTY list inside a
# process substitution, so the gate read "unchanged; skipping" and exited 0; (2) `diff.relative=true` run from
# a subdirectory lists names relative to the cwd, so `.gitleaks.toml` is never on the list; (3) rename
# detection lists only a rename's NEW path, so moving the config away was read as "unchanged". The fix is a
# repo-top, literal pathspec read with --no-renames, whose git status is checked: a git failure is exit 2 with
# an ::error:: annotation (the secret-scan smoke case `allowlist-diff-fires` expects a non-zero exit AND an
# ::error:: line, and this script runs under that smoke matrix).
#
# Exit contract of the SUT: 0 unchanged / removals only / override, 1 widening without acknowledgement,
# 2 required input missing or git failed.
#
# Fixtures are synthesized git repos under mktemp (cq-test-fixtures-synthesized-only) carrying the REAL
# .gitleaks.toml and parser, so the allowlist shape under test is the one that ships.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT_REL="apps/web-platform/scripts/allowlist-diff.sh"
SUT="$REPO_ROOT/$SUT_REL"
PARSER_REL="apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"

# Sourcing the library ARMS the git-location tripwire (a suite started under an inherited GIT_DIR aborts
# with rc 97 instead of committing into the developer's live branch) and supplies git_fixture_env.
# shellcheck source=/dev/null
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

# The body below is the CANONICAL copy, asserted byte-for-byte against every other copy by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
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

PASS=0
FAIL=0
ROWS=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n  detail: %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

# Instrument controls. pass()/fail() must each move their own counter, and expect() (the verdict-owning helper every row goes through) must
# FAIL a wrong rc and PASS a right one: a neutered fail() or an expect() that always says yes would otherwise leave every row green. The
# counters are unwound afterwards so the row floor stays exact; a broken instrument exits directly, never through fail().
_p0=$PASS; _f0=$FAIL
pass "instrument (expected)" >/dev/null
fail "instrument (expected, subtracted)" >/dev/null
if [ "$PASS" -ne $((_p0 + 1)) ] || [ "$FAIL" -ne $((_f0 + 1)) ]; then
  echo "FATAL: pass()/fail() did not each move their counter" >&2; exit 1
fi
PASS=$_p0; FAIL=$_f0

for tool in node jq git python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "harness: $tool missing; this suite would assert nothing" >&2; exit 2; }
done
[[ -f "$SUT" ]] || { echo "FAIL: SUT missing at $SUT" >&2; exit 1; }
[[ -f "$REPO_ROOT/$PARSER_REL" ]] || { echo "harness: parser missing" >&2; exit 2; }
[[ -f "$REPO_ROOT/.gitleaks.toml" ]] || { echo "harness: .gitleaks.toml missing" >&2; exit 2; }

WORK="$(mktemp -d -t allowdiff.XXXXXXXX)" || { echo "harness: mktemp -d failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

# mk_repo <name> — a git repo carrying the real parser + .gitleaks.toml in one base commit.
mk_repo() {
  local d="$WORK/$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/apps/web-platform/scripts" "$d/sub" || return 1
  git_fixture_env "$d" || return 1
  cp "$REPO_ROOT/$PARSER_REL" "$d/$PARSER_REL" || return 1
  cp "$REPO_ROOT/.gitleaks.toml" "$d/.gitleaks.toml" || return 1
  printf 'x\n' > "$d/sub/keep.txt" || return 1
  git -C "$d" init -q -b main || return 1
  git -C "$d" add -A >/dev/null 2>&1 || return 1
  git -C "$d" commit -q -m base || return 1
  printf '%s' "$d"
}

# widen <repo> — append one brand-new path to the top-level [allowlist] block and commit it.
widen() {
  local d="$1"
  assert_fixture_dir "$d"
  python3 - "$d/.gitleaks.toml" <<'PYEOF' || return 1
import re, sys
p = sys.argv[1]
s = open(p).read()
s2 = re.sub(r"(\[allowlist\][\s\S]*?paths = \[)", r"\1\n  '''smoke/synthetic/path/added\\.txt$''',", s, count=1)
assert s != s2, "widen fixture: regex did not match the [allowlist] block"
open(p, "w").write(s2)
PYEOF
  git -C "$d" add .gitleaks.toml >/dev/null 2>&1 || return 1
  git -C "$d" commit -q -m "widen allowlist" || return 1
}

# run_sut <repo> <base> <head> [cwd-subdir] [labels] — sets SUT_RC / SUT_OUT (stdout+stderr merged).
run_sut() {
  local d="$1" base="$2" head="$3" sub="${4:-}" labels="${5:-[]}"
  assert_fixture_dir "$d"
  SUT_OUT="$(cd "$d/$sub" && BASE_SHA="$base" HEAD_SHA="$head" PR_LABELS="$labels" bash "$d/$SUT_REL" 2>&1)"
  SUT_RC=$?
}

# expect <label> <want-rc> [must-contain-substring]
# ROWS is bumped at the call site (independent of the verdict), the floor at the bottom reads it.
expect() {
  local label="$1" want="$2" needle="${3:-}"
  ROWS=$((ROWS + 1))
  if [[ "$SUT_RC" != "$want" ]]; then
    fail "$label" "expected rc=$want got rc=$SUT_RC; output: $(printf '%s' "$SUT_OUT" | head -4 | tr '\n' ' ')"
    return
  fi
  if [[ -n "$needle" ]] && ! grep -qF -- "$needle" <<<"$SUT_OUT"; then
    fail "$label" "rc=$want ok but output lacks '$needle': $(printf '%s' "$SUT_OUT" | head -4 | tr '\n' ' ')"
    return
  fi
  pass "$label"
}

_p0=$PASS; _f0=$FAIL; _r0=$ROWS; SUT_RC=0; SUT_OUT=""
expect "instrument: a wrong rc (expected FAIL)" 1 >/dev/null
_df=$((FAIL - _f0)); _dp=$((PASS - _p0))
expect "instrument: a right rc (expected PASS)" 0 >/dev/null
if [ "$_df" -ne 1 ] || [ "$_dp" -ne 0 ] || [ "$((PASS - _p0))" -ne 1 ] || [ "$((FAIL - _f0))" -ne 1 ]; then
  echo "FATAL: expect() did not FAIL a wrong rc and PASS a right one (fail+$_df pass+$_dp); the verdict helper is inert" >&2; exit 1
fi
PASS=$_p0; FAIL=$_f0; ROWS=$_r0

# Copy the SUT into every fixture so it resolves REPO_ROOT (git rev-parse) and the parser from the fixture.
install_sut() {
  local d="$1"
  assert_fixture_dir "$d"
  cp "$SUT" "$d/$SUT_REL" || return 1
}

# ---------------------------------------------------------------------------
# AD-1: .gitleaks.toml unchanged -> exit 0, "skipping".
# ---------------------------------------------------------------------------
R1="$(mk_repo unchanged)" || { echo "harness: setup failed" >&2; exit 2; }
install_sut "$R1"
printf 'y\n' > "$R1/sub/other.txt"
assert_fixture_dir "$R1"
git -C "$R1" add -A >/dev/null 2>&1
git -C "$R1" commit -q -m "unrelated"
run_sut "$R1" "$(git -C "$R1" rev-parse HEAD~1)" "$(git -C "$R1" rev-parse HEAD)"
expect "AD-1 unchanged .gitleaks.toml skips with exit 0" 0 "unchanged; skipping"

# ---------------------------------------------------------------------------
# AD-2: widening without acknowledgement -> exit 1 with an ::error:: annotation (the smoke case's contract).
# ---------------------------------------------------------------------------
R2="$(mk_repo widened)" || exit 2
install_sut "$R2"
git -C "$R2" add -A >/dev/null 2>&1
git -C "$R2" commit -q -m "install sut"
widen "$R2" || { echo "harness: widen failed" >&2; exit 2; }
B2="$(git -C "$R2" rev-parse HEAD~1)"
H2="$(git -C "$R2" rev-parse HEAD)"
run_sut "$R2" "$B2" "$H2"
expect "AD-2 un-acknowledged widening exits 1 with ::error::" 1 "::error::Allowlist widening detected"

# AD-3: the label override still acknowledges the same widening.
run_sut "$R2" "$B2" "$H2" "" '["secret-scan-allowlist-ack"]'
expect "AD-3 label override acknowledges a widening" 0 "acknowledged by"

# ---------------------------------------------------------------------------
# AD-4: a bad SHA makes `git diff` fail. That is exit 2 with an ::error:: annotation, NEVER "unchanged;
# skipping" at exit 0 (the process-substitution read turned the failure into an empty file list).
# ---------------------------------------------------------------------------
run_sut "$R2" "$B2" "0000000000000000000000000000000000000001"
expect "AD-4 a failing git diff exits 2 with ::error::" 2 "::error::allowlist-diff: git diff "

# ---------------------------------------------------------------------------
# AD-5: diff.relative=true run from a subdirectory lists cwd-relative names, so `.gitleaks.toml` was never on
# the list. The repo-top literal pathspec is independent of cwd and of that config.
# ---------------------------------------------------------------------------
R5="$(mk_repo relative)" || exit 2
install_sut "$R5"
git -C "$R5" add -A >/dev/null 2>&1
git -C "$R5" commit -q -m "install sut"
widen "$R5" || { echo "harness: widen failed" >&2; exit 2; }
git -C "$R5" config diff.relative true
run_sut "$R5" "$(git -C "$R5" rev-parse HEAD~1)" "$(git -C "$R5" rev-parse HEAD)" sub
expect "AD-5 widening is still seen under diff.relative=true from a subdirectory" 1 "::error::Allowlist widening detected"

# ---------------------------------------------------------------------------
# AD-6: moving .gitleaks.toml AWAY. Default rename detection lists only the new path (`legacy.toml`), so the
# gate read "unchanged; skipping" at exit 0 while the allowlist config vanished from its canonical path. With
# --no-renames the deletion is on the list, the gate proceeds and cannot read the head config: a non-zero exit.
# ---------------------------------------------------------------------------
R6="$(mk_repo renamedaway)" || exit 2
install_sut "$R6"
git -C "$R6" add -A >/dev/null 2>&1
git -C "$R6" commit -q -m "install sut"
git -C "$R6" mv .gitleaks.toml legacy.toml
git -C "$R6" commit -q -m "move the config away"
run_sut "$R6" "$(git -C "$R6" rev-parse HEAD~1)" "$(git -C "$R6" rev-parse HEAD)"
expect "AD-6 moving .gitleaks.toml away exits 2 naming the cause (never read as unchanged)" 2 "::error::allowlist-diff: .gitleaks.toml is absent at"

# ---------------------------------------------------------------------------
# AD-7: a rename INTO .gitleaks.toml carrying a widening is still detected.
# ---------------------------------------------------------------------------
R7="$(mk_repo renamedin)" || exit 2
install_sut "$R7"
git -C "$R7" mv .gitleaks.toml legacy.toml
git -C "$R7" add -A >/dev/null 2>&1
git -C "$R7" commit -q -m "park the config under another name"
git -C "$R7" mv legacy.toml .gitleaks.toml
widen "$R7" || { echo "harness: widen failed" >&2; exit 2; }
run_sut "$R7" "$(git -C "$R7" rev-parse HEAD~1)" "$(git -C "$R7" rev-parse HEAD)"
expect "AD-7 a widening that arrives through a rename into .gitleaks.toml is detected" 1 "::error::Allowlist widening detected"

# ---------------------------------------------------------------------------
# MB-1: mutation. Restore the old plain `git diff --name-only` process-substitution read on a scratch copy of
# the SUT; AD-4 must go from exit 2 back to a silent exit 0, proving the row can go red.
# ---------------------------------------------------------------------------
MUT="$WORK/mutant-allowlist-diff.sh"
cp "$SUT" "$MUT" || { echo "harness: cp failed" >&2; exit 2; }
python3 - "$MUT" <<'PYEOF'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
start = s.index('cfg="$(git -C')
end_marker = 'fi\n'
end = s.index('echo "allowlist-diff: .gitleaks.toml unchanged; skipping."', start)
end = s.index(end_marker, end) + len(end_marker)
old_block = ("if ! grep -Fxq '.gitleaks.toml' < <(git diff --name-only \"${BASE_SHA}..${HEAD_SHA}\"); then\n"
             "  echo \"allowlist-diff: .gitleaks.toml unchanged; skipping.\"\n  exit 0\nfi\n")
p.write_text(s[:start] + old_block + s[end:])
PYEOF
if diff -q "$SUT" "$MUT" >/dev/null 2>&1; then
  ROWS=$((ROWS + 1))
  fail "MB-1 mutation" "the mutation did not land"
else
  install_mut_dir="$R2"
  assert_fixture_dir "$install_mut_dir"
  cp "$MUT" "$install_mut_dir/apps/web-platform/scripts/allowlist-diff-mutant.sh"
  SUT_OUT="$(cd "$R2" && BASE_SHA="$B2" HEAD_SHA="0000000000000000000000000000000000000001" PR_LABELS='[]' \
    bash "$R2/apps/web-platform/scripts/allowlist-diff-mutant.sh" 2>&1)"
  SUT_RC=$?
  expect "MB-1 the old process-substitution read turns a git failure back into a silent exit 0" 0 "unchanged; skipping"
fi

# ---------------------------------------------------------------------------
# Anti-vacuity floor on this harness's own dispatch. ROWS is bumped at every call site, independent of the
# verdict, and the floor exits directly (it does not run through `fail`, the thing it witnesses).
# ---------------------------------------------------------------------------
MIN_ROWS=8
if [ "$ROWS" -lt "$MIN_ROWS" ]; then
  echo "FATAL: allowlist-diff.test.sh dispatched only $ROWS rows (expected >= $MIN_ROWS); vacuous run" >&2
  exit 1
fi

echo
echo "allowlist-diff: $PASS passed, $FAIL failed, $ROWS rows"
[ "$FAIL" -eq 0 ] || exit 1
