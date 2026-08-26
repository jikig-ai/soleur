#!/usr/bin/env bash
#
# Guards the webplat vitest split in scripts/test-all.sh (#7498).
#
# The split gives the app-local projects (`unit`, `component`) a relevance gate
# on `apps/web-platform/`, while `repo-wide` and `component` run always. Two ways
# that can rot,
# both silent:
#
#   1. `repo-wide` acquires a gate. Then the suites whose entire purpose is to
#      catch drift in NON-app diffs get declined on exactly those diffs, and the
#      decline reads as intentional in the summary. This is the failure the
#      split exists to prevent, reintroduced.
#
#   2. The app-local gate is dropped. Then 52% of commits pay for 1,057 app
#      tests that cannot be affected by them — the cost the split exists to
#      remove — and nothing fails, so nobody notices.
#
# Both are shape properties of one `if` block, so this is a static guard. Each
# arm is paired with a MUTANT that must fail it; a shape assertion that cannot
# be driven red certifies nothing.
#
# Run: bash scripts/test-all-webplat-gate.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
REL_LIB="$REPO_ROOT/scripts/lib/test-relevance-paths.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (expected '$1', got '$2')"; fi; }

echo "=== test-all.sh webplat split + relevance gate (#7498) ==="
echo ""

# The webplat block, isolated so a match elsewhere in this 1600-line file cannot
# satisfy an arm. Anchored on `if want_webplat; then` through its closing `fi`.
extract_block() {
  awk '/^if want_webplat; then$/{f=1} f{print} f&&/^fi$/{exit}' "$1"
}

BLOCK="$(extract_block "$TEST_ALL")"

echo "A1: both webplat suites are declared"
grep -qF 'run_suite "apps/web-platform [repo-wide+component]"' <<<"$BLOCK" \
  && pass "repo-wide+component suite declared" || fail "repo-wide+component suite declared"
grep -qF 'run_suite "apps/web-platform [unit]"' <<<"$BLOCK" \
  && pass "app-local suite declared" || fail "app-local suite declared"
echo ""

echo "A2: the app-local suite is gated, and its decline is COUNTED"
grep -qF '_diff_touches "${WEBPLAT_APP_PATHS[@]}"' <<<"$BLOCK" \
  && pass "gate predicate present" || fail "gate predicate present"
grep -qF 'skip_suite "apps/web-platform [unit]"' <<<"$BLOCK" \
  && pass "decline goes through skip_suite (ADR-181: a decline is a verdict)" \
  || fail "decline goes through skip_suite"
grep -qF '_relevance_declined=$((_relevance_declined + 1))' <<<"$BLOCK" \
  && pass "decline increments the relevance counter" || fail "decline increments the counter"
echo ""

echo "A3: repo-wide + component are NOT gated"
# Everything before the `if _diff_touches` line is the ungated region.
UNGATED="$(awk '/_diff_touches/{exit} {print}' <<<"$BLOCK")"
grep -qF 'run_suite "apps/web-platform [repo-wide+component]"' <<<"$UNGATED" \
  && pass "repo-wide + component run outside the gate" \
  || fail "repo-wide + component run outside the gate — repo-wide would be declined on the diffs it guards"
echo ""

echo "A4: the predicate array is declared, non-empty, and app-scoped"
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$REL_LIB"
if declare -p WEBPLAT_APP_PATHS >/dev/null 2>&1; then
  pass "WEBPLAT_APP_PATHS declared"
  (( ${#WEBPLAT_APP_PATHS[@]} > 0 )) && pass "WEBPLAT_APP_PATHS non-empty" \
    || fail "WEBPLAT_APP_PATHS non-empty"
  # Trailing slash is load-bearing: `_diff_touches` is a SUBSTRING match, so a
  # bare `apps/web-platform` would also fire on a sibling like
  # `apps/web-platform-legacy/`. Over-matching only costs time here, but the
  # slash makes the intent explicit and cheap to keep.
  check "apps/web-platform/" "${WEBPLAT_APP_PATHS[0]}" "first entry is the app prefix, slash-terminated"
else
  fail "WEBPLAT_APP_PATHS declared"
fi
echo ""

# --- Mutants ---------------------------------------------------------------
# Each rewrites a COPY and asserts the corresponding arm above flips. The
# mutation is verified to have landed; a missed anchor would make the mutant
# identical to the original and the arm would "fail to fail" silently.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Writes the mutant to $TMP/$1.sh and returns non-zero on failure. NOT called
# in a command substitution: an `exit 2` inside `$( )` leaves only the subshell,
# so the designed fail-fast degraded into an empty path and two misleading
# "mutant parses" failures pointing at the wrong cause.
mutate() {
  # Split declarations: bash binds every name in one `local` before evaluating
  # the initialisers, so `local a="$1" b="$TMP/$a"` reads $a UNBOUND under
  # `set -u`. That failure is quiet here (no `set -e`) and leaves $out as
  # "$TMP/.sh" — the mutant file is then missing, `extract_block` reads nothing,
  # and both mutant arms "detect" the mutation for the wrong reason. A vacuous
  # pass in the guard whose entire job is to prevent vacuous passes.
  local name="$1" sed_expr="$2"
  local out="$TMP/$name.sh"
  cp "$TEST_ALL" "$out"
  sed -i "$sed_expr" "$out"
  if [[ ! -s "$out" ]]; then
    echo "  FATAL: mutant '$name' is missing or empty at $out" >&2
    return 2
  fi
  if diff -q "$TEST_ALL" "$out" >/dev/null 2>&1; then
    echo "  FATAL: mutation '$name' did not land — the arm below would pass vacuously" >&2
    return 2
  fi
  return 0
}

echo "M1: dropping the gate must break A2"
mutate m1 's/if _diff_touches "\${WEBPLAT_APP_PATHS\[@\]}"; then/if true; then/' || exit 2
M1="$TMP/m1.sh"
bash -n "$M1" && pass "M1 mutant is still a parseable script" || fail "M1 mutant parses"
[[ -n "$(extract_block "$M1")" ]] && pass "M1 mutant still contains the webplat block" \
  || fail "M1 mutant still contains the webplat block"
if grep -qF '_diff_touches "${WEBPLAT_APP_PATHS[@]}"' <<<"$(extract_block "$M1")"; then
  fail "M1 mutant still shows a gate — A2 is vacuous"
else
  pass "ungated mutant is detected (A2 can be driven red)"
fi
echo ""

echo "M2: gating repo-wide must break A3"
# The mutation A3 exists for is repo-wide moved INSIDE the gate — not deleted.
# Deletion is already covered by A1, and a mutant that only deletes leaves A3's
# real failure mode uncertified. So: delete the ungated pair, then re-emit it
# immediately after the `if _diff_touches` line, i.e. inside the gated arm.
mutate m2 '/run_suite "apps\/web-platform \[repo-wide+component\]"/,+1d' || exit 2
M2="$TMP/m2.sh"
awk '
  /if _diff_touches "\$\{WEBPLAT_APP_PATHS\[@\]\}"; then/ {
    print
    print "    run_suite \"apps/web-platform [repo-wide+component]\" env VITEST_SHARD=\"${VITEST_SHARD:-}\" \\"
    print "      bash -c '"'"'cd apps/web-platform \&\& npm run test:ci -- --project repo-wide'"'"'"
    next
  }
  { print }
' "$M2" > "$M2.tmp" && mv "$M2.tmp" "$M2"
grep -qF 'run_suite "apps/web-platform [repo-wide+component]"' "$M2" \
  && pass "M2 mutant re-emitted repo-wide inside the gate (the mutation A3 targets)" \
  || fail "M2 mutant re-emitted repo-wide inside the gate"
bash -n "$M2" && pass "M2 mutant is still a parseable script" || fail "M2 mutant parses"
[[ -n "$(extract_block "$M2")" ]] && pass "M2 mutant still contains the webplat block" \
  || fail "M2 mutant still contains the webplat block"
M2_UNGATED="$(awk '/_diff_touches/{exit} {print}' <<<"$(extract_block "$M2")")"
if grep -qF 'run_suite "apps/web-platform [repo-wide+component]"' <<<"$M2_UNGATED"; then
  fail "M2 mutant still shows repo-wide ungated — A3 is vacuous"
else
  pass "gated-repo-wide mutant is detected (A3 can be driven red)"
fi
echo ""

echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
# Anti-vacuity floor: 16 assertions run above. A refactor that silently drops
# arms must not read as a pass.
if (( PASS + FAIL < 16 )); then
  echo "ANTI-VACUITY FLOOR TRIPPED: only $((PASS + FAIL)) assertions ran, expected 16." >&2
  exit 1
fi
if (( FAIL > 0 )); then echo "SOME TESTS FAILED"; exit 1; fi
echo "ALL TESTS PASSED"
