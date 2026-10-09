#!/usr/bin/env bash
# test-all-fast-tier-budget — the #9763 ratchet that keeps the local fast tier fast.
#
# Property: the local --affected tier cannot silently regrow. Every label in
# ALWAYS_ON_SUITES must have committed weight <= LOCAL_FAST_CAP_MS in
# scripts/suite-durations.tsv, and the tier's summed weight must stay under
# LOCAL_FAST_TOTAL_CAP_MS. Heavier suites live as edge-selected registrations —
# they run in CI legs, merge_group, push and --full, and locally when their
# subject paths change.
#
# Chokepoint: both caps are literals in THIS file (pinned by M2) and the sums are
# computed from the committed manifest, never re-measured — a wall-clock budget
# would flake; a committed-weight budget cannot.
#
# Instrument self-check: the mutation matrix (M1–M6 in the plan) requires the
# helpers to count both directions — stubbing fail() must itself redden.
set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX="$REPO_ROOT/scripts/lib/test-affected-paths.sh"
DUR="$REPO_ROOT/scripts/suite-durations.tsv"

LOCAL_FAST_CAP_MS=10000
LOCAL_FAST_TOTAL_CAP_MS=300000

pass_n=0
fails=0
cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

# ---------------------------------------------------------------------------
# Self-check: the helpers count both directions (stubbed-helpers can't fake green).
# ---------------------------------------------------------------------------
cases=$((cases + 1))
_before_fails=$fails; fail "self-test (expected; discounted below)"
if (( fails == _before_fails + 1 )); then fails=$((fails - 1)); pass "instrument: fail() increments the counter"
else fail "instrument: fail() did not increment"; fi

# ---------------------------------------------------------------------------
# Inputs exist and parse.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
if [[ -r "$INDEX" && -r "$DUR" ]]; then pass "inputs readable"; else fail "missing $INDEX or $DUR"; fi

cases=$((cases + 1))
mapfile -t always < <(sed -n '/^ALWAYS_ON_SUITES=(/,/^)/p' "$INDEX" | grep -oE '^  "[^"]+"' | tr -d ' "')
if (( ${#always[@]} >= 100 )); then pass "always-on census: ${#always[@]} labels parsed (>=100, not gutted)"; else fail "always-on census: only ${#always[@]} labels — index parsed wrong or gutted"; fi

# ---------------------------------------------------------------------------
# Per-suite cap: no always-on label above LOCAL_FAST_CAP_MS committed weight.
# ---------------------------------------------------------------------------
declare -A weight=()
while IFS=$'\t' read -r label ms _; do
  [[ "$ms" =~ ^[0-9]+$ ]] && weight["$label"]=$ms
done < "$DUR"

over=()
missing=()
total=0
for l in "${always[@]}"; do
  if [[ -z "${weight[$l]+x}" ]]; then missing+=("$l"); continue; fi
  total=$((total + weight[$l]))
  (( weight[$l] > LOCAL_FAST_CAP_MS )) && over+=("$l=${weight[$l]}")
done

cases=$((cases + 1))
# Bun-group registrations carry no suite-durations.tsv row (the manifest's population is the
# scripts leg only) — the exact set is pinned so a NEW unmeasured label still reds and a stale
# entry (a label that gained a row) is caught too.
KNOWN_UNMEASURED_ALWAYS_ON=("blog-link-validation" "scripts/frontmatter-strip-parity")
_unexp_missing=(); for l in "${missing[@]}"; do
  _known=0; for k in "${KNOWN_UNMEASURED_ALWAYS_ON[@]}"; do [[ "$l" == "$k" ]] && { _known=1; break; }; done
  (( _known == 0 )) && _unexp_missing+=("$l")
done
_stale_allow=(); for k in "${KNOWN_UNMEASURED_ALWAYS_ON[@]}"; do
  [[ -n "${weight[$k]+x}" ]] && _stale_allow+=("$k")
done
if (( ${#_unexp_missing[@]} == 0 && ${#_stale_allow[@]} == 0 )); then
  pass "weight census: every always-on label has a committed weight or a pinned exception (${#KNOWN_UNMEASURED_ALWAYS_ON[@]})"
else
  ((${#_unexp_missing[@]})) && printf '  [FAIL] unaccountable always-on label(s): %s\n' "${_unexp_missing[@]}" >&2
  ((${#_stale_allow[@]})) && printf '  [FAIL] allowlist drift — now has a weight row: %s\n' "${_stale_allow[@]}" >&2
  fails=$((fails + 1))
fi

cases=$((cases + 1))
if (( ${#over[@]} == 0 )); then pass "per-suite cap: every always-on label <= ${LOCAL_FAST_CAP_MS}ms committed weight"
else printf '  [FAIL] heavy always-on label(s): %s\n' "${over[@]}" >&2; fails=$((fails + 1)); fi

# ---------------------------------------------------------------------------
# Total cap: the whole fast tier sums under LOCAL_FAST_TOTAL_CAP_MS.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
if (( total <= LOCAL_FAST_TOTAL_CAP_MS )); then pass "total cap: always-on committed weight ${total}ms <= ${LOCAL_FAST_TOTAL_CAP_MS}ms"
else fail "total cap: always-on committed weight ${total}ms exceeds ${LOCAL_FAST_TOTAL_CAP_MS}ms"; fi

# ---------------------------------------------------------------------------
# Registration truth: every always-on label is a live run_suite label (a label
# that selects but never registers is the worst silent shape).
# ---------------------------------------------------------------------------
cases=$((cases + 1))
missing_reg=()
while IFS= read -r l; do
  # A label registers three ways: an explicit `run_suite "<label>"` line, a file at
  # the label path picked up by SUITE_GLOBS, or a bracketed synthetic shard label.
  if grep -qE "^[[:space:]]*run_suite \"$l\"" "$REPO_ROOT/scripts/test-all.sh" \
     || [[ -e "$REPO_ROOT/$l" ]] || [[ "$l" == *"["* ]]; then continue; fi
  missing_reg+=("$l")
done < <(printf '%s\n' "${always[@]}")
if (( ${#missing_reg[@]} == 0 )); then pass "every always-on label resolves to a registration"
else printf '  [FAIL] always-on label(s) with no registration (run_suite, file, or shard): %s\n' "${missing_reg[@]}" >&2; fails=$((fails + 1)); fi

# ---------------------------------------------------------------------------
# Drift pins: the cap literals and the edge-demotion comment the lists rest on.
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
