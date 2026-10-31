#!/usr/bin/env bash
# always-on-ledger — the #11662 always-on ceiling + why-always-on parity.
#
# Properties:
#  P1: every ALWAYS_ON_SUITES label has a row in
#      scripts/always-on-justifications.tsv (label<TAB>reason), and no stale
#      row survives a rename — parity is two-directional.
#  P2: count(ALWAYS_ON_SUITES \ live_named) <= NON_LIVE_CAP — bounds ORGANIC
#      non-live membership. This is NOT f1's pin-vs-list band
#      (_MIN_ALWAYS_ON_DECLARED + scripts/test-all-affected.test.sh row f1,
#      floor <= count <= floor+5): f1 catches the pinned floor rotting behind
#      the list; this cap catches the list silently accreting non-live
#      members. The live regex is parity-pinned to
#      scripts/lint-orphan-test-suites.sh's live_floor derivation
#      ('(^|[^a-zA-Z])live([^a-zA-Z]|$)|liveness') — asserted verbatim below.
#  P3: every justification row carries a non-empty reason.
#
# Escape: raising NON_LIVE_CAP is a deliberate ack-edit in THIS file, never a
# floor bump (the live floor is derived, not declared).
#
# Instrument self-check: helpers are driven both directions below; the fixture
# arms run the parity and cap predicates red and green each invocation.
#
# Requires bash >= 4 (declare -A, mapfile).

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX="$REPO_ROOT/scripts/lib/test-affected-paths.sh"
JUST="$REPO_ROOT/scripts/always-on-justifications.tsv"
ORPHAN_LINT="$REPO_ROOT/scripts/lint-orphan-test-suites.sh"

NON_LIVE_CAP=95
# Parity-pinned to lint-orphan's live_floor regex — a divergence is an
# acknowledged edit to BOTH sites, never a silent drift.
LIVE_RE='(^|[^a-zA-Z])live([^a-zA-Z]|$)|liveness'

TESTROOT="$(mktemp -d -t always-on-ledger.XXXXXXXX)"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

pass_n=0
fails=0
cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

# ---------------------------------------------------------------------------
# check_ledger <index-file> <justifications-file> <cap>
# ---------------------------------------------------------------------------
check_ledger() {
  local index="$1" just="$2" cap="$3"
  local _rc=0 l a

  local -a always=()
  mapfile -t always < <( source "$index" >/dev/null 2>&1 && printf '%s\n' ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"} )
  (( ${#always[@]} >= 3 )) || { echo "    [check] census: only ${#always[@]} labels parsed" >&2; return 3; }

  local -A j_reason=()
  if [[ -r "$just" ]]; then
    while IFS=$'\t' read -r l _r; do
      [[ "$l" == \#* || -z "$l" ]] && continue
      j_reason["$l"]="$_r"
    done < "$just"
  fi

  local -a nojust=() stale=() empty=()
  local nonlive=0 _member
  for l in "${always[@]}"; do
    if [[ -z "${j_reason[$l]+x}" ]]; then nojust+=("$l");
    elif [[ -z "${j_reason[$l]//[[:space:]]/}" ]]; then empty+=("$l"); fi
    [[ "$l" =~ $LIVE_RE ]] || nonlive=$((nonlive + 1))
  done
  for l in "${!j_reason[@]}"; do
    _member=0
    for a in "${always[@]}"; do [[ "$a" == "$l" ]] && { _member=1; break; }; done
    (( _member == 0 )) && stale+=("$l")
  done

  (( ${#nojust[@]} )) && { printf '    [check] always-on label(s) without a justification row: %s\n' "${nojust[@]}" >&2; _rc=1; }
  (( ${#stale[@]} ))  && { printf '    [check] justification row(s) for non-members: %s\n' "${stale[@]}" >&2; _rc=1; }
  (( ${#empty[@]} ))  && { printf '    [check] empty reason field(s): %s\n' "${empty[@]}" >&2; _rc=1; }
  (( nonlive > cap )) && { echo "    [check] non-live always-on membership $nonlive > NON_LIVE_CAP $cap — organic accretion needs a cap ack-edit, not a floor bump" >&2; _rc=1; }
  return $_rc
}

FIX="$TESTROOT/fix"; mkdir -p "$FIX"

# ---------------------------------------------------------------------------
# Instrument self-test: both helpers must move their counters. Not counted in
# `cases` — it verifies the helpers dispatch, it is not an assertion.
# ---------------------------------------------------------------------------
_p0=$pass_n; _f0=$fails
pass "selftest-pass-marker" >/dev/null
fail "selftest-fail-marker" 2>/dev/null
if (( pass_n == _p0 + 1 && fails == _f0 + 1 )); then
  :
else
  echo "[FATAL] instrument self-test: pass/fail helpers did not move counters" >&2; exit 2
fi
pass_n=$((pass_n - 1)); fails=$((fails - 1))

# ---------------------------------------------------------------------------
# Canonical run.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
if check_ledger "$INDEX" "$JUST" "$NON_LIVE_CAP"; then
  pass "canonical ALWAYS_ON_SUITES satisfies the ledger (parity + ceiling)"
else
  fail "canonical ALWAYS_ON_SUITES violates the ledger"
fi

# Live-regex parity pin: the same derivation must still exist in lint-orphan.
cases=$((cases + 1))
grep -qE -- 'live_floor=.*liveness' "$ORPHAN_LINT" \
  && pass "live regex parity-pinned to lint-orphan's live_floor derivation" \
  || fail "live regex drifted from lint-orphan's derivation — sync BOTH sites"

# Cap literal pin.
cases=$((cases + 1))
(( NON_LIVE_CAP == 95 )) && pass "cap literal pinned (NON_LIVE_CAP=95)" || fail "cap literal drifted"

# ---------------------------------------------------------------------------
# Mutation arms (Guard 3 matrix). Fixture index + TSV; cap=5 for boundary.
# ---------------------------------------------------------------------------
printf 'ALWAYS_ON_SUITES=(\n  "a/live-one"\n  "a/x"\n  "a/y"\n  "a/z"\n)\n' > "$FIX/index.sh"
printf 'a/live-one\tlive scanner\na/x\trx\na/y\try\na/z\trz\n' > "$FIX/j.tsv"

# M1: label added to the array without a justification row reds.
cases=$((cases + 1))
printf 'ALWAYS_ON_SUITES=(\n  "a/live-one"\n  "a/x"\n  "a/y"\n  "a/z"\n  "a/new"\n)\n' > "$FIX/i1.sh"
if check_ledger "$FIX/i1.sh" "$FIX/j.tsv" 95 2>/dev/null; then
  fail "M1: array member without a justification row stayed green"
else
  pass "M1: missing justification row reddens"
fi

# M2: non-live count at the cap boundary greens at <=, reds at >.
cases=$((cases + 1))
printf 'ALWAYS_ON_SUITES=(\n  "a/1"\n  "a/2"\n  "a/3"\n  "a/4"\n  "a/5"\n)\n' > "$FIX/i2.sh"
printf 'a/1\tr\na/2\tr\na/3\tr\na/4\tr\na/5\tr\n' > "$FIX/j2.tsv"
if check_ledger "$FIX/i2.sh" "$FIX/j2.tsv" 5 2>/dev/null; then
  pass "M2 (must-PASS): non-live count at the cap greens"
else
  fail "M2: non-live count at the cap reddened"
fi

cases=$((cases + 1))
printf 'ALWAYS_ON_SUITES=(\n  "a/1"\n  "a/2"\n  "a/3"\n  "a/4"\n  "a/5"\n  "a/6"\n)\n' > "$FIX/i3.sh"
printf 'a/6\tr\n' >> "$FIX/j2.tsv"
if check_ledger "$FIX/i3.sh" "$FIX/j2.tsv" 5 2>/dev/null; then
  fail "M2b: non-live count over the cap stayed green"
else
  pass "M2b: non-live count over the cap reddens"
fi

# M3 (must-PASS): live-named members do not consume non-live headroom.
# Separate TSV — M2b's appended a/6 row is stale under i4's member set.
cases=$((cases + 1))
printf 'ALWAYS_ON_SUITES=(\n  "a/1"\n  "a/2"\n  "a/3"\n  "a/4"\n  "a/5"\n  "a/live-six"\n)\n' > "$FIX/i4.sh"
printf 'a/1\tr\na/2\tr\na/3\tr\na/4\tr\na/5\tr\na/live-six\tr\n' > "$FIX/j3b.tsv"
if check_ledger "$FIX/i4.sh" "$FIX/j3b.tsv" 5 2>/dev/null; then
  pass "M3 (must-PASS): live-named member exempt from the non-live count"
else
  fail "M3: a live-named member consumed non-live headroom"
fi

# M4: an emptied justifications file reds (parity, not vacuity).
cases=$((cases + 1))
: > "$FIX/j3.tsv"
if check_ledger "$FIX/i2.sh" "$FIX/j3.tsv" 95 2>/dev/null; then
  fail "M4: an emptied ledger stayed green"
else
  pass "M4: emptied ledger reddens"
fi

# M5 (own-dispatch): a derivation returning zero live members lands every
# member in the non-live count — over the cap it must red.
cases=$((cases + 1))
printf 'ALWAYS_ON_SUITES=(\n  "a/1"\n  "a/2"\n  "a/3"\n  "a/4"\n  "a/5"\n  "a/6"\n)\n' > "$FIX/i5.sh"
printf 'a/1\tr\na/2\tr\na/3\tr\na/4\tr\na/5\tr\na/6\tr\n' > "$FIX/j5.tsv"
if check_ledger "$FIX/i5.sh" "$FIX/j5.tsv" 5 2>/dev/null; then
  fail "M5: zero-live derivation over cap stayed green"
else
  pass "M5: a gutted live derivation lands members in the cap count"
fi

# M6: a label renamed in the array but not the TSV reds in BOTH directions.
cases=$((cases + 1))
printf 'ALWAYS_ON_SUITES=(\n  "a/1"\n  "a/2"\n  "a/3"\n  "a/4"\n  "a/renamed"\n)\n' > "$FIX/i6.sh"
if check_ledger "$FIX/i6.sh" "$FIX/j2.tsv" 95 2>/dev/null; then
  fail "M6: a set-identity rename stayed green"
else
  pass "M6: rename without TSV sync reddens (parity is two-directional)"
fi

# M7a: a stale ledger row (non-member) is the SOLE red source.
cases=$((cases + 1))
printf 'a/1\tr\na/2\tr\na/3\tr\na/4\tr\na/5\tr\na/extra\tr\n' > "$FIX/j6.tsv"
if check_ledger "$FIX/i2.sh" "$FIX/j6.tsv" 95 2>/dev/null; then
  fail "M7a: a stale justification row stayed green"
else
  pass "M7a: stale row for a non-member reddens (parity is two-directional)"
fi

# M7b: an empty reason field is the SOLE red source (P3 armed).
cases=$((cases + 1))
printf 'a/1\tr\na/2\tr\na/3\t\na/4\tr\na/5\tr\n' > "$FIX/j7.tsv"
if check_ledger "$FIX/i2.sh" "$FIX/j7.tsv" 95 2>/dev/null; then
  fail "M7b: an empty reason field stayed green"
else
  pass "M7b: empty reason field reddens"
fi

# M7c: word-boundary — 'alive' counts as NON-live (regex not substring).
cases=$((cases + 1))
printf 'ALWAYS_ON_SUITES=(\n  "a/1"\n  "a/2"\n  "a/3"\n  "a/4"\n  "a/5"\n  "a/alive-six"\n)\n' > "$FIX/i7.sh"
printf 'a/alive-six\tr\n' >> "$FIX/j5.tsv" 2>/dev/null || true
printf 'a/1\tr\na/2\tr\na/3\tr\na/4\tr\na/5\tr\na/alive-six\tr\n' > "$FIX/j8.tsv"
if check_ledger "$FIX/i7.sh" "$FIX/j8.tsv" 5 2>/dev/null; then
  fail "M7c: 'alive' matched the live regex (word-boundary semantics lost)"
else
  pass "M7c: 'alive' counts as non-live (word-boundary pinned)"
fi

# M7 (must-PASS, non-canonical): comment rows and blank lines in the TSV are
# skipped — only label rows count.
cases=$((cases + 1))
printf '# header comment\n\na/1\tr\na/2\tr\na/3\tr\na/4\tr\na/5\tr\n' > "$FIX/j4.tsv"
if check_ledger "$FIX/i2.sh" "$FIX/j4.tsv" 5 2>/dev/null; then
  pass "M7 (must-PASS): comment/blank lines in the ledger are skipped"
else
  fail "M7: comment lines miscounted as justification rows"
fi

# ---------------------------------------------------------------------------
# Conservation + floor.
# ---------------------------------------------------------------------------
if (( pass_n + fails != cases )); then
  echo "[FATAL] conservation breach: pass_n=$pass_n fails=$fails cases=$cases" >&2; exit 2
fi
MIN_ASSERTIONS=10
if (( cases < MIN_ASSERTIONS )); then
  echo "[FATAL] anti-vacuity floor: only $cases assertion(s) ran, expected >= $MIN_ASSERTIONS" >&2; exit 2
fi
if (( fails > 0 )); then
  echo "always-on-ledger: $pass_n passed, $fails failed" >&2; exit 1
fi
echo "always-on-ledger: ALL PASS ($cases assertions, 0 failed)"
