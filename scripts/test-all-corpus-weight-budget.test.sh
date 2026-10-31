#!/usr/bin/env bash
# test-all-corpus-weight-budget — the #11662 corpus-wide committed-weight cap.
#
# Property: no registered suite's committed weight exceeds CORPUS_SUITE_CAP_MS
# unless recorded in scripts/suite-weight-exemptions.tsv
# (label<TAB>cap_ms<TAB>reason — the reason MUST cite a #NNN tracking ref), and
# no in-scope registration lacks a committed weight row (unmeasured != exempt —
# the #9763 three-direction-closed allowlist shape). Scope: the three committed
# tables — scripts/suite-durations.tsv (light), scripts/suite-durations-heavy.tsv,
# apps/web-platform/infra/suite-durations.tsv. bun/webplat registrations carry
# no duration table and are declared out of scope v1.
#
# Chokepoint: the cap is a value-pinned literal in THIS file and the weights are
# read from the committed tables, never re-measured — a wall-clock budget would
# flake; a committed-weight budget cannot.
#
# Ledger rules (#11662 R6): cap_ms must cover the row's current weight AND stay
# within ~1.3x of it (slack is bounded); a row whose suite fits the default cap
# reds (minimal ledger — no permanent exemptions); a row keyed on a label no
# durations table carries reds (stale-key parity).
#
# Instrument self-check: the helpers are driven both directions below, and the
# fixture arms run the CAP and PARITY predicates red and green in every
# invocation (a predicate inversion is a dead guard).
#
# Requires bash >= 4 (declare -A, mapfile).

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUR_LIGHT="$REPO_ROOT/scripts/suite-durations.tsv"
DUR_HEAVY="$REPO_ROOT/scripts/suite-durations-heavy.tsv"
DUR_INFRA="$REPO_ROOT/apps/web-platform/infra/suite-durations.tsv"
EXEMPTIONS="$REPO_ROOT/scripts/suite-weight-exemptions.tsv"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
INFRA_RUNNER="$REPO_ROOT/apps/web-platform/infra/run-registered-suites.sh"

CORPUS_SUITE_CAP_MS=600000

TESTROOT="$(mktemp -d -t corpus-weight-budget.XXXXXXXX)"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

pass_n=0
fails=0
cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

# ---------------------------------------------------------------------------
# check_corpus <light> <heavy> <infra> <exemptions> <labels> <infra-labels>
#   [allowlist_mode]
# Driven against the real files below and against fixtures in the arms.
# <labels> = scripts+scripts-heavy registration labels (one per line);
# <infra-labels> = infra --enumerate paths (one per line).
# ---------------------------------------------------------------------------
check_corpus() {
  local dur_light="$1" dur_heavy="$2" dur_infra="$3" exem="$4" labels="$5" infra_labels="$6" allowlist_mode="${7:-strict}"
  local _rc=0 f l ms c r

  local -A weight=()
  for f in "$dur_light" "$dur_heavy" "$dur_infra"; do
    [[ -r "$f" ]] || { echo "    [check] durations table unreadable: $f" >&2; return 3; }
    while IFS=$'\t' read -r l ms _; do
      [[ "$l" == \#* || -z "$l" ]] && continue
      [[ "$ms" =~ ^[0-9]+$ ]] && weight["$l"]=$ms
    done < "$f"
  done
  (( ${#weight[@]} >= 3 )) || { echo "    [check] census: only ${#weight[@]} weight rows parsed" >&2; return 3; }

  local -A ex_cap=() ex_reason=()
  if [[ -r "$exem" ]]; then
    while IFS=$'\t' read -r l c r; do
      [[ "$l" == \#* || -z "$l" ]] && continue
      ex_cap["$l"]="$c"; ex_reason["$l"]="$r"
    done < "$exem"
  fi

  local -a over=() badex=()
  for l in "${!weight[@]}"; do
    (( weight[$l] <= CORPUS_SUITE_CAP_MS )) && continue
    if [[ -z "${ex_cap[$l]+x}" ]]; then
      over+=("$l=${weight[$l]}")
    elif ! [[ "${ex_cap[$l]}" =~ ^[0-9]+$ ]] || (( ex_cap[$l] < weight[$l] )); then
      badex+=("$l (cap_ms ${ex_cap[$l]:-<none>} < weight ${weight[$l]})")
    fi
  done

  # Ledger invariants: minimal (fits default cap -> red), slack bound (~1.3x),
  # stale-key parity, #NNN tracking ref in every reason.
  local -a minimal=() slack=() stalek=() noref=()
  for l in "${!ex_cap[@]}"; do
    if [[ -z "${weight[$l]+x}" ]]; then stalek+=("$l"); continue; fi
    (( weight[$l] <= CORPUS_SUITE_CAP_MS )) && minimal+=("$l")
    if [[ "${ex_cap[$l]}" =~ ^[0-9]+$ ]] && (( ex_cap[$l] * 10 > weight[$l] * 13 )); then
      slack+=("$l (cap_ms ${ex_cap[$l]} > 1.3x weight ${weight[$l]})")
    fi
    [[ "${ex_reason[$l]:-}" =~ "#"[0-9]+ ]] || noref+=("$l")
  done

  # Unmeasured direction: in-scope registration labels with no weight row.
  local -a missing=()
  for f in "$labels" "$infra_labels"; do
    while IFS= read -r l; do
      [[ -n "$l" && -z "${weight[$l]+x}" ]] && missing+=("$l")
    done < "$f"
  done
  local -a unexp=() stalea=() departed=() KNOWN_UNMEASURED_CORPUS=()
  if [[ "$allowlist_mode" == "strict" ]]; then
    # Three-direction-closed unmeasured allowlist: a NEW unmeasured label reds,
    # an allowlisted label gaining a row reds, an allowlisted label leaving the
    # registration stream reds. Empty is the goal state — the regen flow gives
    # every registration a floor row at write time.
    KNOWN_UNMEASURED_CORPUS=()
    local _k _member
    for _k in ${KNOWN_UNMEASURED_CORPUS[@]+"${KNOWN_UNMEASURED_CORPUS[@]}"}; do
      [[ -n "${weight[$_k]+x}" ]] && stalea+=("$_k")
      _member=0
      while IFS= read -r l; do [[ "$l" == "$_k" ]] && { _member=1; break; }; done < "$labels"
      (( _member == 0 )) && while IFS= read -r l; do [[ "$l" == "$_k" ]] && { _member=1; break; }; done < "$infra_labels"
      (( _member == 0 )) && departed+=("$_k")
    done
  fi
  for l in ${missing[@]+"${missing[@]}"}; do
    _member=0
    for _k in ${KNOWN_UNMEASURED_CORPUS[@]+"${KNOWN_UNMEASURED_CORPUS[@]}"}; do [[ "$l" == "$_k" ]] && { _member=1; break; }; done
    (( _member == 0 )) && unexp+=("$l")
  done

  (( ${#over[@]} ))     && { printf '    [check] committed weight(s) over %dms with no exemption: %s\n' "$CORPUS_SUITE_CAP_MS" "${over[@]}" >&2; _rc=1; }
  (( ${#badex[@]} ))    && { printf '    [check] exemption cap below current weight: %s\n' "${badex[@]}" >&2; _rc=1; }
  (( ${#minimal[@]} ))  && { printf '    [check] exemption row(s) for suite(s) inside the default cap: %s\n' "${minimal[@]}" >&2; _rc=1; }
  (( ${#slack[@]} ))    && { printf '    [check] exemption slack over ~1.3x: %s\n' "${slack[@]}" >&2; _rc=1; }
  (( ${#stalek[@]} ))   && { printf '    [check] exemption row(s) keyed on absent label(s): %s\n' "${stalek[@]}" >&2; _rc=1; }
  (( ${#noref[@]} ))    && { printf '    [check] exemption reason(s) without a #NNN ref: %s\n' "${noref[@]}" >&2; _rc=1; }
  (( ${#unexp[@]} ))    && { printf '    [check] registration(s) with no committed weight row: %s\n' "${unexp[@]}" >&2; _rc=1; }
  (( ${#stalea[@]} ))   && { printf '    [check] unmeasured-allowlist label(s) that gained a row: %s\n' "${stalea[@]}" >&2; _rc=1; }
  (( ${#departed[@]} )) && { printf '    [check] unmeasured-allowlist label(s) no longer registered: %s\n' "${departed[@]}" >&2; _rc=1; }
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
  : # helpers dispatch correctly; counters moved both directions
else
  echo "[FATAL] instrument self-test: pass/fail helpers did not move counters" >&2; exit 2
fi
pass_n=$((pass_n - 1)); fails=$((fails - 1))

# ---------------------------------------------------------------------------
# Canonical run against the real tables + live registration streams.
# ---------------------------------------------------------------------------
env -u TEST_GROUP -u SCRIPTS_SHARD -u SOLEUR_ENUM_DEADLINE_S SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --enumerate scripts 2>/dev/null \
  | sed -n 's/^SUITE_REGISTRATION\t//p' > "$FIX/labels.txt"
env -u TEST_GROUP -u SCRIPTS_SHARD -u SOLEUR_ENUM_DEADLINE_S env -u TEST_GROUP -u SCRIPTS_SHARD -u SOLEUR_ENUM_DEADLINE_S SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --enumerate scripts-heavy 2>/dev/null \
  | sed -n 's/^SUITE_REGISTRATION\t//p' >> "$FIX/labels.txt"
( cd "$REPO_ROOT" && bash "$INFRA_RUNNER" --enumerate ) 2>/dev/null \
  | sed -n 's/^SUITE_REGISTRATION\t//p' > "$FIX/infra-labels.txt"

cases=$((cases + 1))
(( $(wc -l < "$FIX/labels.txt") > 100 && $(wc -l < "$FIX/infra-labels.txt") > 50 )) \
  && pass "registration streams enumerated ($(wc -l < "$FIX/labels.txt" | tr -d ' ') light+heavy, $(wc -l < "$FIX/infra-labels.txt" | tr -d ' ') infra)" \
  || fail "registration streams under-enumerated — the corpus check certified a subset"

cases=$((cases + 1))
if check_corpus "$DUR_LIGHT" "$DUR_HEAVY" "$DUR_INFRA" "$EXEMPTIONS" "$FIX/labels.txt" "$FIX/infra-labels.txt"; then
  pass "canonical corpus is inside the committed-weight budget"
else
  fail "canonical corpus violates the committed-weight budget"
fi

# ---------------------------------------------------------------------------
# Mutation arms (Guard 2 matrix).
# ---------------------------------------------------------------------------
printf 'a/one\t300\tmeasured\na/two\t500\tmeasured\n' > "$FIX/d.tsv"
printf 'a/heavy\t20000\tmeasured\n' > "$FIX/dh.tsv"
printf 'a/infra\t5000\tmeasured\n' > "$FIX/di.tsv"
printf 'a/one\na/two\n' > "$FIX/l.txt"
printf 'a/infra\n' > "$FIX/li.txt"

# M1: a 700s-weight suite with no exemption reds.
cases=$((cases + 1))
printf 'a/big\t700000\tmeasured\n' >> "$FIX/d.tsv"
printf 'a/big\n' >> "$FIX/l.txt"
: > "$FIX/ex.tsv"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M1: an unexempted 700s weight stayed green"
else
  pass "M1: unexempted over-cap weight reddens"
fi

# M2 (must-PASS): the same weight with a covering ledger row greens.
cases=$((cases + 1))
printf 'a/big\t900000\tdeclared-big suite; #000\n' > "$FIX/ex.tsv"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  pass "M2 (must-PASS): covering exemption greens"
else
  fail "M2: covering exemption reddened"
fi

# M3: an exemption cap BELOW the actual weight reds.
cases=$((cases + 1))
printf 'a/big\t500000\tdeclared-big suite; #000\n' > "$FIX/ex.tsv"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M3: an under-covering exemption stayed green"
else
  pass "M3: under-covering exemption reddens"
fi

# M4: a registration with no weight row reds (unmeasured != exempt).
cases=$((cases + 1))
printf 'a/big\t900000\tdeclared-big suite; #000\n' > "$FIX/ex.tsv"
printf 'a/ghost\n' >> "$FIX/l.txt"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M4: an unmeasured registration stayed green"
else
  pass "M4: unmeasured registration reddens"
fi

# M5: removing the ledger line while the suite stays at 700s reds (WORM).
cases=$((cases + 1))
sed -i '/^a\/ghost$/d' "$FIX/l.txt"
: > "$FIX/ex.tsv"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M5: a removed exemption silently un-reddened"
else
  pass "M5: WORM — dropping the exemption re-reddens"
fi

# M6 (totality): a SECOND unmeasured label is not absorbed by the first's
# handling — the scan must enumerate the whole population.
cases=$((cases + 1))
printf 'a/big\t900000\tdeclared-big suite; #000\n' > "$FIX/ex.tsv"
printf 'a/ghost1\na/ghost2\n' >> "$FIX/l.txt"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M6: additional unmeasured labels went unreported"
else
  pass "M6: totality — every unmeasured label reddens"
fi

# M7: ledger invariant arms — stale key, minimal-ledger, slack, missing #ref.
cases=$((cases + 1))
printf 'a/big\t900000\tdeclared-big suite; #000\n' > "$FIX/ex.tsv"
printf 'a/vanished\t900000\tgone; #000\n' >> "$FIX/ex.tsv"
sed -i '/^a\/ghost/d' "$FIX/l.txt"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M7a: a stale-key exemption row stayed green"
else
  pass "M7a: stale-key exemption reddens"
fi

cases=$((cases + 1))
printf 'a/big\t900000\tdeclared-big suite; #000\na/one\t350\tneedless; #000\n' > "$FIX/ex.tsv"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M7b: a minimal-ledger violation stayed green"
else
  pass "M7b: exemption for an in-cap suite reddens"
fi

cases=$((cases + 1))
printf 'a/big\t999000\tdeclared-big suite; #000\n' > "$FIX/ex.tsv"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M7c: an over-slack exemption cap stayed green"
else
  pass "M7c: cap beyond ~1.3x weight reddens"
fi

cases=$((cases + 1))
printf 'a/big\t900000\tno tracking ref here\n' > "$FIX/ex.tsv"
if check_corpus "$FIX/d.tsv" "$FIX/dh.tsv" "$FIX/di.tsv" "$FIX/ex.tsv" "$FIX/l.txt" "$FIX/li.txt" none 2>/dev/null; then
  fail "M7d: a reason without a #NNN ref stayed green"
else
  pass "M7d: reason missing #NNN reddens"
fi

# ---------------------------------------------------------------------------
# Table census: a fourth suite-durations*.tsv would evade the check silently
# (the join names exactly the three committed tables — R8 pins exact names).
# ---------------------------------------------------------------------------
cases=$((cases + 1))
mapfile -t _tabs < <(compgen -G "$REPO_ROOT/scripts/suite-durations*.tsv" | sort)
if [[ "${_tabs[*]}" == "$REPO_ROOT/scripts/suite-durations-heavy.tsv $REPO_ROOT/scripts/suite-durations.tsv" && -r "$DUR_INFRA" ]]; then
  pass "durations-table census: exactly the three committed tables joined"
else
  printf '  [FAIL] unexpected durations table(s): %s
' "${_tabs[*]}" >&2; fails=$((fails + 1))
fi

# ---------------------------------------------------------------------------
# Drift pin: the cap literal (a value pin cannot self-mutate under sed).
# ---------------------------------------------------------------------------
cases=$((cases + 1))
(( CORPUS_SUITE_CAP_MS == 600000 )) \
  && pass "cap literal pinned (600s)" || fail "cap literal drifted"

# ---------------------------------------------------------------------------
# Conservation + floor.
# ---------------------------------------------------------------------------
if (( pass_n + fails != cases )); then
  echo "[FATAL] conservation breach: pass_n=$pass_n fails=$fails cases=$cases" >&2; exit 2
fi
MIN_ASSERTIONS=12
if (( cases < MIN_ASSERTIONS )); then
  echo "[FATAL] anti-vacuity floor: only $cases assertion(s) ran, expected >= $MIN_ASSERTIONS" >&2; exit 2
fi
if (( fails > 0 )); then
  echo "test-all-corpus-weight-budget: $pass_n passed, $fails failed" >&2; exit 1
fi
echo "test-all-corpus-weight-budget: ALL PASS ($cases assertions, 0 failed)"
