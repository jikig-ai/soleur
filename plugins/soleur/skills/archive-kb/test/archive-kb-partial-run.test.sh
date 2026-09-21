#!/usr/bin/env bash
# Pins the partial-run warning in archive-kb.sh (#8416).
#
# The gap: `discover_artifacts` derives ONE slug per run, and a feature's plan
# and spec routinely carry different slugs. The unmatched class is then silently
# absent while the run prints `Archived N artifact(s)` and exits 0. SKILL.md had
# documented that in prose since it was first hit; it was hit again on #8325,
# which is what makes a committed harness the fix rather than more prose
# (`wg-when-a-workflow-gap-causes-a-mistake-fix`).
#
# Coverage is by STATE, not by count: all four plan/spec combinations run, so the
# suite sees over-warning (the two silent states) as well as under-warning. A
# suite carrying only the two must-warn states could not distinguish this guard
# from one that warns unconditionally.
set -uo pipefail

SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/archive-kb.sh"
[[ -x "$SUT" ]] || { printf 'FATAL: SUT not executable at %s\n' "$SUT" >&2; exit 2; }

# Copied byte-identical from plugins/soleur/test/test-helpers.sh (not sourced:
# this suite lives outside that tree). plugins/soleur/test/fixture-dir-operand-assert.test.sh
# compares every copy.
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

# `cases` is incremented at every CALL SITE, never inside pass()/fail(). That is
# what keeps the conservation identity below non-tautological: a verdict helper
# rewritten to always-pass, or one whose counter is redirected, still leaves
# `cases` where the call sites put it, so `PASS + FAIL == cases` breaks. A counter
# incremented inside the helpers would move with them and prove nothing.
PASS=0; FAIL=0; cases=0
pass() { PASS=$((PASS + 1)); printf '  [ok] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1"; }

# Instrument self-test: drive BOTH verdict helpers once, require each counter to
# move, then unwind. Reported via printf + exit, never through the helpers under
# test. Runs before any real row (ADR-193).
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (pass arm)" >/dev/null
fail "instrument self-test (fail arm) — expected, unwound" >/dev/null
[[ $PASS -eq $((_p0 + 1)) && $FAIL -eq $((_f0 + 1)) ]] || {
  printf '[FATAL] verdict helpers do not both record; the suite cannot report.\n' >&2; exit 2; }
PASS=$_p0; FAIL=$_f0

ROOT="$(mktemp -d -p "${TMPDIR:-/var/tmp}" archive-kb-partial.XXXXXXXX)"
trap 'rm -rf "$ROOT"' EXIT
assert_fixture_dir "$ROOT"

# `want` is the expected warning count, so each row asserts a DIRECTION rather
# than merely that something was printed.
run_case() {
  local name="$1" mkplan="$2" mkspec="$3" want="$4"
  local d="$ROOT/$name"
  mkdir -p "$d/knowledge-base/project/plans" "$d/knowledge-base/project/specs"
  assert_fixture_dir "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name t
  [[ "$mkplan" == yes ]] && printf 'x\n' > "$d/knowledge-base/project/plans/2026-01-01-feat-demo-plan.md"
  if [[ "$mkspec" == yes ]]; then
    mkdir -p "$d/knowledge-base/project/specs/feat-demo"
    printf 'x\n' > "$d/knowledge-base/project/specs/feat-demo/tasks.md"
  fi
  local out rc got
  out="$( cd "$d" && bash "$SUT" --dry-run demo 2>&1 )"; rc=$?
  got="$(printf '%s' "$out" | grep -c 'WARNING: found a' || true)"
  cases=$((cases + 1))
  if [[ "$rc" -eq 0 && "$got" -eq "$want" ]]; then
    pass "$name: rc=0, warnings=$want"
  else
    fail "$name: rc=$rc warnings=$got (want $want) out='$out'"
  fi
}

run_case both      yes yes 0   # both classes present — must stay silent
run_case plan-only yes no  1   # spec missing
run_case spec-only no  yes 1   # the #8325 shape: plan named for its topic, not the branch
run_case neither   no  no  0   # nothing discovered — the pre-existing message, not a warning

# The warning must NAME the absent class, or it cannot tell the operator which
# slug to re-run with. Anchored on the emitted sentence, not a bare token.
d="$ROOT/spec-only"
out="$( cd "$d" && bash "$SUT" --dry-run demo 2>&1 )"
cases=$((cases + 1))
if printf '%s' "$out" | grep -q 'but NO plan\.'; then
  pass "spec-only warning names the missing class (plan)"
else
  fail "spec-only warning does not name the missing class: '$out'"
fi
d="$ROOT/plan-only"
out="$( cd "$d" && bash "$SUT" --dry-run demo 2>&1 )"
cases=$((cases + 1))
if printf '%s' "$out" | grep -q 'but NO spec\.'; then
  pass "plan-only warning names the missing class (spec)"
else
  fail "plan-only warning does not name the missing class: '$out'"
fi

# Conservation first, then the floor. Both emitted by printf + exit 1 and never
# routed through the pass()/fail() they backstop (ADR-193) — a floor dispatched
# through the helper it protects is disarmed by the same one-line edit.
if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf '[FATAL] accounting conservation: %s + %s != %s\n' "$PASS" "$FAIL" "$cases" >&2
  exit 1
fi
MIN_ASSERTIONS=6
if [[ "$cases" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s case(s) ran, floor is %s\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '%s passed, %s failed (%s cases)\n' "$PASS" "$FAIL" "$cases"
[[ "$FAIL" -eq 0 ]] || exit 1
