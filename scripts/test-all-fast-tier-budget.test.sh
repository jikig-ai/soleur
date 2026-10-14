#!/usr/bin/env bash
# test-all-fast-tier-budget — the #9763 ratchet that keeps the local fast tier fast.
#
# Property: the local --affected tier cannot silently regrow. Every label in
# ALWAYS_ON_SUITES must have committed weight <= LOCAL_FAST_CAP_MS in
# scripts/suite-durations.tsv (or a pinned unmeasured exception), and the tier's
# summed weight must stay under LOCAL_FAST_TOTAL_CAP_MS. Heavier suites live as
# edge-selected registrations — they run in CI legs, merge_group, push and
# --full, and locally when their subject paths change.
#
# Chokepoint: both caps are literals in THIS file (value-pinned) and the sums are
# computed from the committed manifest, never re-measured — a wall-clock budget
# would flake; a committed-weight budget cannot.
#
# Instrument self-check: the mutation matrix requires the helpers to count both
# directions — stubbing fail() must itself redden — and check_tier is driven
# against synthetic index/manifest fixtures so the CAP PREDICATES THEMSELVES run
# red and green in every invocation (a predicate inversion is a dead guard).
#
# Requires bash >= 4 (declare -A, mapfile). Consistent with sibling suites that
# annotate the same floor; the runner host is modern bash.

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX="$REPO_ROOT/scripts/lib/test-affected-paths.sh"
DUR="$REPO_ROOT/scripts/suite-durations.tsv"

LOCAL_FAST_CAP_MS=10000
LOCAL_FAST_TOTAL_CAP_MS=300000

TESTROOT="$(mktemp -d -t fast-tier-budget.XXXXXXXX)"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

pass_n=0
fails=0
cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

# ---------------------------------------------------------------------------
# check_tier <index-file> <durations-file> — the budget check proper, driven
# against the real files below and against fixtures in the mutation arms.
# Expects labels to be an array named ALWAYS_ON_SUITES inside the index file —
# sourced, never re-parsed: indent/quote/append-shape edits cannot hide an
# entry from this census the way a text shape can.
# ---------------------------------------------------------------------------
check_tier() {
  local index="$1" dur="$2" allowlist_mode="${3:-strict}"
  local _rc=0

  local -a always=()
  mapfile -t always < <( source "$index" >/dev/null 2>&1 && printf '%s\n' ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"} )
  (( ${#always[@]} >= 3 )) || { echo "    [check] census: only ${#always[@]} labels parsed" >&2; return 3; }

  local -A weight=()
  local l
  while IFS=$'\t' read -r l ms _; do
    [[ "$ms" =~ ^[0-9]+$ ]] && weight["$l"]=$ms
  done < "$dur"

  local -a over=() missing=()
  local total=0
  for l in "${always[@]}"; do
    if [[ -z "${weight[$l]+x}" ]]; then missing+=("$l"); continue; fi
    total=$((total + weight[$l]))
    (( weight[$l] > LOCAL_FAST_CAP_MS )) && over+=("$l=${weight[$l]}")
  done

  # Bun-group registrations carry no suite-durations.tsv row (the manifest's
  # population is the scripts leg only). The exact set is pinned: a NEW
  # unmeasured label reds, an allowlisted label gaining a row reds, and an
  # allowlisted label leaving the tier reds — the allowlist is closed under
  # all three drift directions.
  local _known _k _member
  local -a unexp=() stale=() departed=() KNOWN_UNMEASURED_ALWAYS_ON=()
  if [[ "$allowlist_mode" == "strict" ]]; then
    KNOWN_UNMEASURED_ALWAYS_ON=("blog-link-validation" "scripts/frontmatter-strip-parity")
    (( ${#KNOWN_UNMEASURED_ALWAYS_ON[@]} == 2 )) || { echo "    [check] allowlist drift: ${#KNOWN_UNMEASURED_ALWAYS_ON[@]} != 2" >&2; _rc=1; }
    for _k in "${KNOWN_UNMEASURED_ALWAYS_ON[@]}"; do
      [[ -n "${weight[$_k]+x}" ]] && stale+=("$_k")
      _member=0
      for l in "${always[@]}"; do [[ "$l" == "$_k" ]] && { _member=1; break; }; done
      (( _member == 0 )) && departed+=("$_k")
    done
  fi
  for l in "${missing[@]}"; do
    _known=0
    for _k in ${KNOWN_UNMEASURED_ALWAYS_ON[@]+"${KNOWN_UNMEASURED_ALWAYS_ON[@]}"}; do [[ "$l" == "$_k" ]] && { _known=1; break; }; done
    (( _known == 0 )) && unexp+=("$l")
  done
  (( ${#unexp[@]} ))    && { printf '    [check] unaccountable always-on label(s): %s\n' "${unexp[@]}" >&2; _rc=1; }
  (( ${#stale[@]} ))    && { printf '    [check] allowlist drift — gained a weight row: %s\n' "${stale[@]}" >&2; _rc=1; }
  (( ${#departed[@]} )) && { printf '    [check] allowlist drift — left the tier: %s\n' "${departed[@]}" >&2; _rc=1; }

  (( ${#over[@]} )) && { printf '    [check] heavy always-on label(s): %s\n' "${over[@]}" >&2; _rc=1; }
  (( total > LOCAL_FAST_TOTAL_CAP_MS )) && { echo "    [check] total cap: ${total}ms > ${LOCAL_FAST_TOTAL_CAP_MS}ms" >&2; _rc=1; }
  return $_rc
}

# ---------------------------------------------------------------------------
# Self-check: the helpers count both directions (stubbed-helpers can't fake green).
# ---------------------------------------------------------------------------
cases=$((cases + 1))
_before_fails=$fails; fail "self-test (expected; discounted below)"
if (( fails == _before_fails + 1 )); then fails=$((fails - 1)); pass "instrument: fail() increments the counter"
else fail "instrument: fail() did not increment"; fi

# ---------------------------------------------------------------------------
# Inputs exist.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
if [[ -r "$INDEX" && -r "$DUR" ]]; then pass "inputs readable"; else fail "missing $INDEX or $DUR"; fi

# ---------------------------------------------------------------------------
# The budget check against the real corpus.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
if check_tier "$INDEX" "$DUR"; then pass "check_tier: real corpus within caps (always-on count, per-suite, total, allowlist)"
else fail "check_tier: real corpus violates the fast-tier budget"; fi

# ---------------------------------------------------------------------------
# Mutation arm M1: a >cap label in the fixture index must redden check_tier
# (exercises the per-suite predicate — a `>` to `<` inversion is caught here).
# ---------------------------------------------------------------------------
cases=$((cases + 1))
FIX="$TESTROOT/heavy"
mkdir -p "$FIX"
cat > "$FIX/index.sh" <<'EOF'
ALWAYS_ON_SUITES=(
  "scripts/test-contention"
  "scripts/fast-a"
  "scripts/fast-b"
)
EOF
cat > "$FIX/dur.tsv" <<'EOF'
scripts/test-contention	137000	measured
scripts/fast-a	500	measured
scripts/fast-b	800	measured
EOF
if check_tier "$FIX/index.sh" "$FIX/dur.tsv" none 2>/dev/null; then
  fail "M1: a >cap label in ALWAYS_ON stayed green"
else
  pass "M1: heavy label in fixture index reddens check_tier"
fi

# Mutation arm M2: a total over the cap with per-suite-legal rows must also
# redden (the total predicate, not just the per-suite one).
cases=$((cases + 1))
# 35 labels at 9999ms each — every row legal, the SUM violates the total cap.
printf 'ALWAYS_ON_SUITES=(\n' > "$FIX/index.sh"
: > "$FIX/dur.tsv"
for i in $(seq 1 35); do
  printf '  "a/n%d"\n' "$i" >> "$FIX/index.sh"
  printf 'a/n%d\t9999\tmeasured\n' "$i" >> "$FIX/dur.tsv"
done
printf ')\n' >> "$FIX/index.sh"
if check_tier "$FIX/index.sh" "$FIX/dur.tsv" none 2>/dev/null; then
  fail "M2: a summed weight over the total cap stayed green"
else
  pass "M2: total-cap violation reddens check_tier"
fi

# Mutation arm M3 (must-PASS): a compliant fixture stays green — the arms are
# not tuned to red on everything.
cases=$((cases + 1))
cat > "$FIX/index.sh" <<'EOF'
ALWAYS_ON_SUITES=(
  "a/one" "a/two" "a/three"
)
EOF
cat > "$FIX/dur.tsv" <<'EOF'
a/one	300	measured
a/two	500	measured
a/three	100	measured
EOF
if check_tier "$FIX/index.sh" "$FIX/dur.tsv" none 2>/dev/null; then
  pass "M3 (must-PASS): compliant fixture stays green"
else
  fail "M3 (must-PASS): compliant fixture reddened"
fi

# ---------------------------------------------------------------------------
# Registration truth: every always-on label resolves to a registration — an
# anchored literal run_suite line, or a file a SUITE_GLOB covers. Existence
# alone is NOT registration (an unregistered *.test.sh under scripts/ is an
# orphan by design — scripts/ is deliberately unglobbed).
# ---------------------------------------------------------------------------
cases=$((cases + 1))
mapfile -t always < <( source "$INDEX" >/dev/null 2>&1 && printf '%s\n' ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"} )
mapfile -t globs < <(bash "$REPO_ROOT/scripts/test-all.sh" --print-suite-globs 2>/dev/null)
missing_reg=()
for l in ${always[@]+"${always[@]}"}; do
  if awk -v l="$l" '{line=$0; sub(/^[[:space:]]*/,"",line); if (index(line, "run_suite \"" l "\"")==1) f=1} END{exit !f}' "$REPO_ROOT/scripts/test-all.sh"; then continue; fi
  if [[ -f "$REPO_ROOT/$l" ]]; then
    hit=0
    for g in "${globs[@]}"; do
      # label matches the glob iff its dir-prefix is the glob's dir prefix
      [[ "$l" == ${g%\*}* && "$l" == *${g##*\*} ]] && { hit=1; break; }
    done
    (( hit == 1 )) && continue
  fi
  missing_reg+=("$l")
done
if (( ${#missing_reg[@]} == 0 )); then pass "every always-on label resolves to a registration (run_suite or glob-covered file)"
else printf '  [FAIL] always-on label(s) with no registration: %s\n' "${missing_reg[@]}" >&2; fails=$((fails + 1)); fi

# ---------------------------------------------------------------------------
# Drift pins: cap VALUES (a value pin cannot self-mutate under sed) and the
# index demotion comment the withdrawal set is documented by.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
(( LOCAL_FAST_CAP_MS == 10000 && LOCAL_FAST_TOTAL_CAP_MS == 300000 )) \
  && pass "cap literals pinned (10s per-suite, 300s total)" || fail "cap literals drifted"

cases=$((cases + 1))
grep -q "withdrawn-to-edge-selection" "$INDEX" \
  && pass "index: demotion comment present (the >10s set is documented where it was removed)" \
  || fail "index: demotion comment missing"

# ---------------------------------------------------------------------------
# Conservation + floor.
# ---------------------------------------------------------------------------
if (( pass_n + fails != cases )); then
  echo "[FATAL] conservation breach: pass_n=$pass_n fails=$fails cases=$cases" >&2; exit 2
fi
MIN_ASSERTIONS=9
if (( cases < MIN_ASSERTIONS )); then
  echo "[FATAL] anti-vacuity floor: only $cases assertion(s) ran, expected >= $MIN_ASSERTIONS" >&2; exit 2
fi
if (( fails > 0 )); then
  echo "test-all-fast-tier-budget: $pass_n passed, $fails failed" >&2; exit 1
fi
echo "test-all-fast-tier-budget: ALL PASS ($cases assertions, 0 failed)"
