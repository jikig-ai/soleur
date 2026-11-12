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

echo "=== test-all.sh webplat split + relevance gate (#7498) + battery shard-gate (#12626) ==="
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

# --- A5/A6: the mutation batteries' VITEST_SHARD gate (#12626) ----------------
#
# The three web-platform mutation batteries (destroy-ask, approval-guard1,
# home-census) used to register unconditionally in the webplat arm — and
# VITEST_SHARD partitions vitest only, so EVERY vitest shard ran each battery
# in full: the duplicated serial cost that killed every scheduled
# main-health-monitor webplat leg at its 30-min step ceiling since 2026-11-10,
# and the same inflation on ci.yml's test-webplat legs. The batteries now live
# on dedicated `test-webplat-mutations` matrix legs in BOTH workflows, and the
# registration in this block declines under VITEST_SHARD — through skip_suite,
# never silently: a decline is a verdict (ADR-181) counted in the denominator,
# and the reason names the legs that carry the coverage.
#
# The properties asserted, per the plan's Guard Contract:
#   * EACH battery has a run_suite/skip_suite PAIR inside a
#     `[[ -n "${VITEST_SHARD:-}" ]]` conditional, in THIS block — quantified
#     over the three labels, so a check that stops at the first member is a
#     defect, not a coverage detail.
#   * The decline's reason names `test-webplat-mutations` — an unnamed decline
#     hides which legs carry the coverage.
#   * The gate sits BELOW the app-local unit gate — it must not reuse or
#     precede `_diff_touches` (the batteries are not app-diff-relevant; they
#     belong to exactly one surface per run).
#   * BOTH workflows carry a `matrix.battery` list naming all three stems —
#     a stem dropped from the matrix is a coverage hole the monitor cannot
#     see, because the leg simply never exists.
BATTERIES=(destroy-ask-mutation approval-guard1-mutation home-census-mutations)

# $1 = the extracted want_webplat block, $2 = a battery stem. Exit 0 iff the
# block contains a VITEST_SHARD conditional whose THEN arm carries this
# battery's skip_suite (reason naming test-webplat-mutations) and whose ELSE
# arm carries its run_suite — positional pairing, not a two-grep coincidence.
battery_pair_ok() {
  local block="$1" label="apps/web-platform/test/$2"
  awk -v label="$label" '
    index($0, "if [[ -n \"${VITEST_SHARD:-}\" ]]; then") { incond=1; sawskip=0; sawrun=0; next }
    incond && /^[[:space:]]*else[[:space:]]*$/ { phase=2; next }
    incond && /^[[:space:]]*fi[[:space:]]*$/ { if (sawskip && sawrun) found=1; incond=0; next }
    incond && index($0, "skip_suite \"" label "\" \"test-webplat-mutations\"") { sawskip=1 }
    incond && phase == 2 && index($0, "run_suite \"" label "\" ") { sawrun=1 }
    END { exit !found }
  ' <<<"$block"
}

echo "A5: each battery has a run_suite/skip_suite pair inside a VITEST_SHARD conditional"
for _b in "${BATTERIES[@]}"; do
  if battery_pair_ok "$BLOCK" "$_b"; then
    pass "$_b paired under VITEST_SHARD"
  else
    fail "$_b paired under VITEST_SHARD — a silent absence on shard legs, or an unconditional run_suite (the #12626 defect)"
  fi
done
check "3" "$(grep -cF 'if [[ -n "${VITEST_SHARD:-}" ]]; then' <<<"$BLOCK")" \
  "exactly three VITEST_SHARD conditionals in the webplat block"
# Position: the battery gates sit BELOW the unit gate — the block's last
# `_diff_touches` line must precede its first `if [[ -n "${VITEST_SHARD` line.
# (A bare VITEST_SHARD grep would hit the repo-wide registration's
# `env VITEST_SHARD=...` passthrough, which legitimately sits above the gate.)
_unit_ln=$(grep -nF '_diff_touches "${WEBPLAT_APP_PATHS[@]}"' <<<"$BLOCK" | tail -1 | cut -d: -f1)
_shard_ln=$(grep -nF 'if [[ -n "${VITEST_SHARD:-}" ]]; then' <<<"$BLOCK" | head -1 | cut -d: -f1)
if [[ -n "$_unit_ln" && -n "$_shard_ln" && "$_shard_ln" -gt "$_unit_ln" ]]; then
  pass "the battery shard-gate sits below the unit relevance gate"
else
  fail "the battery shard-gate sits below the unit relevance gate" \
    "unit gate at line ${_unit_ln:-none}, first VITEST_SHARD at ${_shard_ln:-none}"
fi
echo ""

echo "A6: both workflows carry a matrix.battery over the same three stems"
# $1 = workflow file. Exit 0 iff a `battery: [...]` matrix row names all three
# stems — asserted verbatim, so a renamed or dropped stem is a RED.
matrix_ok() {
  local f="$1" list b
  list="$(awk '/^        battery: \[/{print; exit}' "$f")"
  [[ -n "$list" ]] || return 1
  for b in "${BATTERIES[@]}"; do
    [[ "$list" == *"\"$b\""* ]] || return 1
  done
  return 0
}
CI_WF="$REPO_ROOT/.github/workflows/ci.yml"
MON_WF="$REPO_ROOT/.github/workflows/main-health-monitor.yml"
matrix_ok "$CI_WF" && pass "ci.yml matrix.battery carries all three stems" \
  || fail "ci.yml matrix.battery carries all three stems"
matrix_ok "$MON_WF" && pass "main-health-monitor.yml matrix.battery carries all three stems" \
  || fail "main-health-monitor.yml matrix.battery carries all three stems"
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

# --- #12626 Guard Contract rows --------------------------------------------
# Row 1 (silent-decline): deleting one battery's skip_suite arm turns its
# decline on shard legs into a silent absence — the coverage reads as declined
# in no summary, and the dedicated legs are the only place it still runs.
echo "WG-M1 (silent-decline): dropping a skip_suite arm must break A5"
mutate wm1 '/skip_suite "apps\/web-platform\/test\/destroy-ask-mutation"/,+1c\    : # mutant: decline arm removed' || exit 2
bash -n "$TMP/wm1.sh" && pass "WG-M1 mutant parses" || fail "WG-M1 mutant parses"
if battery_pair_ok "$(extract_block "$TMP/wm1.sh")" destroy-ask-mutation; then
  fail "WG-M1 mutant still shows the destroy-ask pair — A5 is vacuous"
else
  pass "silent-decline mutant is detected (A5 can be driven red)"
fi
echo ""

# Row 2 (matrix-drop): a battery stem dropped from either workflow's
# matrix.battery is a coverage hole the monitor cannot see — the leg never
# exists. Asserted against a COPY so the real workflow is never touched.
echo "WG-M2 (matrix-drop): a stem dropped from a workflow matrix must break A6"
cp "$MON_WF" "$TMP/mon-m2.yml"
sed -i 's/, "home-census-mutations"//' "$TMP/mon-m2.yml"
if diff -q "$MON_WF" "$TMP/mon-m2.yml" >/dev/null 2>&1; then
  echo "  FATAL: WG-M2 mutation did not land" >&2; exit 2
fi
pass "WG-M2 mutant dropped the home-census stem"
if matrix_ok "$TMP/mon-m2.yml"; then
  fail "WG-M2 mutant still validates — A6 is vacuous"
else
  pass "matrix-drop mutant is detected (A6 can be driven red)"
fi
echo ""

# Row 3 (second-member): a check that stops at the FIRST compliant battery is
# the defect itself. Break the LAST battery's pair while the first stays
# whole; A5 must still red.
echo "WG-M3 (second-member): breaking the LAST battery's pair must break A5"
mutate wm3 '/skip_suite "apps\/web-platform\/test\/home-census-mutations"/,+1c\    : # mutant: decline arm removed' || exit 2
bash -n "$TMP/wm3.sh" && pass "WG-M3 mutant parses" || fail "WG-M3 mutant parses"
WM3B="$(extract_block "$TMP/wm3.sh")"
battery_pair_ok "$WM3B" destroy-ask-mutation \
  && pass "WG-M3 leaves the first battery's pair intact (partial mutation landed as designed)" \
  || fail "WG-M3 leaves the first battery's pair intact"
if battery_pair_ok "$WM3B" home-census-mutations; then
  fail "WG-M3 mutant still shows the home-census pair — A5 stopped at the first member"
else
  pass "second-member mutant is detected (A5 quantifies over all three labels)"
fi
echo ""

# Row 4 (dispatch-red): point the guard at a file whose want_webplat anchor is
# gone — every A5 arm must red rather than pass vacuously over an empty block.
echo "WG-M4 (dispatch-red): an unreachable/absent block must red every A5 arm"
mutate wm4 '/^if want_webplat; then$/d' || exit 2
WM4B="$(extract_block "$TMP/wm4.sh")"
_w4_ok=0
for _b in "${BATTERIES[@]}"; do
  battery_pair_ok "$WM4B" "$_b" && _w4_ok=$((_w4_ok + 1))
done
if [[ "$_w4_ok" -eq 0 ]]; then
  pass "every A5 arm reds on a block-less mutant (no vacuous green)"
else
  fail "every A5 arm reds on a block-less mutant" "$_w4_ok arm(s) passed over an empty block"
fi
echo ""

echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
# Anti-vacuity floor: 31 assertions run above (16 for the #7498 split arms,
# 15 for the #12626 battery gate: 7 A5/A6 positive + 8 Guard Contract mutant
# rows). A refactor that silently drops arms must not read as a pass.
if (( PASS + FAIL < 31 )); then
  echo "ANTI-VACUITY FLOOR TRIPPED: only $((PASS + FAIL)) assertions ran, expected 31." >&2
  exit 1
fi
if (( FAIL > 0 )); then echo "SOME TESTS FAILED"; exit 1; fi
echo "ALL TESTS PASSED"
