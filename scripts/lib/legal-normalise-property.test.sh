#!/usr/bin/env bash
# legal-normalise-property.test.sh -- reference generated-input (property-style)
# suite for the shell harness. Subject: scripts/lib/legal-normalise.sh collapse().
#
# Two properties over synthesized legal-doc-shaped input (cq-test-fixtures-
# synthesized-only -- every document is generated in-suite):
#   idempotence    -- collapse(collapse(d)) == collapse(d)
#   residue-free   -- collapsed output contains none of collapse()'s LHS patterns
#
# The LHS set is EXTRACTED from the SUT's sed body at run time (never hand-copied,
# BOTH `s|` and `s/` delimiters) with a conservation count against the rule
# census: a new rewrite rule joins the residue oracle automatically, and a
# delimiter the extractor cannot read fails the suite instead of silently
# shrinking coverage. The generator ALPHABET is hand-maintained -- a NEW
# transform still needs a new alphabet token; extraction guarantees the oracle.
#
# Auto-globbed by test-all.sh (`scripts/lib/*.test.sh`); its `source` of
# legal-normalise.sh is also the derived edge that selects it on SUT diffs.
#
# Reproducibility: PROP_SEED=<n> replays the case stream (same host/bash);
# PROP_RUNS=<n> overrides the default 100-case budget. On failure, shrink the
# counterexample and pin it as a named case labelled
# `# regression fixture: PROP_SEED=<s> iter=<i>` -- see property-harness.md.

set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$REPO_ROOT/scripts/lib/legal-normalise.sh"

# shellcheck source=/dev/null
. "$SUT"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/property-harness.sh"

fails=0
passes=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

cap="$(mktemp -t legal-norm-prop.XXXXXXXX)"
trap 'rm -f "$cap"' EXIT

# ---------------------------------------------------------------------------
# Extract every LHS pattern from collapse()'s sed block. The check is
# conservation, not a magic floor: extracted count must equal the rule census,
# so a delimiter the extractor cannot read (the s/ rules) counts as missing
# coverage, not as a smaller oracle.
# ---------------------------------------------------------------------------
RULE_COUNT="$(awk '/^collapse\(\)/,/^}/' "$SUT" | grep -cE '^ +s[|/]')"
mapfile -t LHS_PATTERNS < <(
  awk '/^collapse\(\)/,/^}/' "$SUT" \
    | sed -nE 's/^ +s\|([^|]*)\|.*/\1/p; s/^ +s\/([^/]*)\/.*/\1/p'
)
if (( ${#LHS_PATTERNS[@]} == RULE_COUNT && RULE_COUNT > 0 )); then
  pass "extracted all ${#LHS_PATTERNS[@]} collapse LHS patterns (${RULE_COUNT} sed rules)"
else
  fail "extracted ${#LHS_PATTERNS[@]} LHS patterns from ${RULE_COUNT} sed rules -- a delimiter the extractor cannot read silently narrows the residue oracle"
  echo "suite cannot continue without the LHS inventory" >&2
  echo "passed: $passes  failed: $fails" >&2
  exit 1
fi

# grep -qE returns 2 on an INVALID pattern, and `if grep -qE` reads rc>=2 the
# same as no-match -- an uncompilable extracted LHS would join the oracle as a
# permanent no-op. Compile-check each pattern up front so a bad one fails the
# suite rather than silently skipping its residue.
for p in "${LHS_PATTERNS[@]}"; do
  if grep -qE "$p" </dev/null; then rc=0; else rc=$?; fi
  if (( rc > 1 )); then
    fail "extracted LHS pattern is not a valid ERE: $p"
    echo "suite cannot continue with an uncompilable oracle pattern" >&2
    echo "passed: $passes  failed: $fails" >&2
    exit 1
  fi
done
unset p rc

prop_init "legal-normalise-collapse"

# ---------------------------------------------------------------------------
# Instrument self-test (after prop_init so seed/iter are bound): the failure
# channel must work before any green is trusted. Drive prop_fail in a
# captured subshell; assert marker + non-zero.
# ---------------------------------------------------------------------------
if ( prop_fail selftest "deliberate" ) 2>"$cap"; then
  fail "instrument self-test: prop_fail returned 0"
elif grep -qE 'PROP_FAIL selftest seed=[0-9]+ iter=[0-9]+ deliberate' "$cap"; then
  pass "instrument self-test: prop_fail emits PROP_FAIL marker and fails"
else
  fail "instrument self-test: prop_fail marker malformed: $(cat "$cap")"
fi

# ---------------------------------------------------------------------------
# Generator: docs over a token alphabet covering EVERY LHS transform (one
# concrete member per pattern) plus benign noise. Numeric/var forms are
# generated so the [0-9]+ and {{ stats.* }} LHS arms both fire.
# ---------------------------------------------------------------------------
ALPHABET=(
  "(privacy-policy.md)" "(/legal/privacy-policy/)" "(./privacy-policy.md)"
  "(gdpr-policy.md)" "(/legal/gdpr-policy/)" "(./gdpr-policy.md)"
  "(disclaimer.md)" "(./disclaimer.md)" "(/legal/disclaimer/)"
  "(individual-cla.md)" "(./individual-cla.md)" "(/legal/individual-cla/)"
  "(corporate-cla.md)" "(./corporate-cla.md)" "(/legal/corporate-cla/)"
  "(acceptable-use-policy.md)" "(./acceptable-use-policy.md)" "(/legal/acceptable-use-policy/)"
  "(cookie-policy.md)" "(./cookie-policy.md)" "(/legal/cookie-policy/)"
  "(data-protection-disclosure.md)" "(./data-protection-disclosure.md)" "(/legal/data-protection-disclosure/)"
  "(terms-and-conditions.md)" "(./terms-and-conditions.md)" "(/legal/terms-and-conditions/)"
  "(https://soleur.ai)" "(https://www.soleur.ai)"
  "[https://soleur.ai]" "[https://www.soleur.ai]"
  "{{ stats.agents }} AI agents" "{{ stats.skills }} skills"
  "across {{ stats.departments }} domains"
  "(Engineering, Legal, Marketing, Operations, Product)"
  "({{ agents.departmentList }})"
  "# Generated Fixture Heading"
  "A plain free-text line about terms."
  "Trailing-space line "
  ""    # blank-line member -- blank runs 0..N arise from consecutive picks
)
WORDS=(engineering legal marketing operations product growth support)

gen_doc() {
  # _doc is the LOCAL build buffer; printf -v must write the caller's name,
  # never a local of the same name (bash dynamic scoping would swallow it).
  local _out="$1" n i tok n2 w _doc=""
  prop_rand 26 n; n=$(( n + 1 ))          # 1..26 lines
  for (( i = 0; i < n; i++ )); do
    prop_rand 10 tok
    case "$tok" in
      0) prop_rand 90 n2; tok="$n2 AI agents" ;;
      1) prop_rand 20 n2; tok="$n2 skills" ;;
      2) prop_pick w "${WORDS[@]}"; tok="across $w domains" ;;
      *) prop_pick tok "${ALPHABET[@]}" ;;
    esac
    _doc+="$tok"$'\n'
  done
  printf -v "$_out" '%s' "$_doc"
}

residue_free() {
  local _doc="$1" p
  for p in "${LHS_PATTERNS[@]}"; do
    if grep -qE "$p" <<<"$_doc"; then
      return 1
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# Negative property control: an oracle that DEMANDS an LHS residue must reject
# collapsed output -- proving residue-freedom is measured, not vacuous.
# ---------------------------------------------------------------------------
control_in=$'# Doc\n\nSee [policy](privacy-policy.md) and [terms](terms-and-conditions.md).\n\n\n7 AI agents across nine domains\n'
control_out="$(printf '%s' "$control_in" | collapse)"
if residue_free "$control_out"; then
  pass "negative control: collapsed output carries zero LHS residue"
else
  fail "negative control: collapse left an LHS pattern in a fully-covered doc"
fi
if grep -qE '\(privacy-policy\.md\)' <<<"$control_out"; then
  fail "negative control: demand-residue oracle should have rejected collapsed output"
else
  pass "negative control: demand-residue oracle correctly rejects collapsed output"
fi

# ---------------------------------------------------------------------------
# The property loop.
# ---------------------------------------------------------------------------
i=0
doc=""   # assigned per case via gen_doc's printf -v outvar (invisible to shellcheck)
while (( i < PROP_RUNS_ACTIVE )); do
  prop_iter; i=$PROP_ITER
  gen_doc doc
  once="$(printf '%s' "$doc" | collapse)"
  twice="$(printf '%s' "$once" | collapse)"
  if [[ "$twice" != "$once" ]]; then
    prop_fail "idempotence" "collapse(collapse(d)) != collapse(d)" || fails=$((fails + 1))
    printf '%s' "$doc" >"$cap.doc"
    printf 'counterexample doc saved to %s\n' "$cap.doc" >&2
    continue
  fi
  if ! residue_free "$once"; then
    prop_fail "residue-free" "collapsed output still matches an LHS pattern" || fails=$((fails + 1))
    printf '%s' "$doc" >"$cap.doc"
    printf 'counterexample doc saved to %s\n' "$cap.doc" >&2
    continue
  fi
  passes=$((passes + 1))
done

# Run-count floor: never emit PROP_PASS for a loop that did not run.
if (( PROP_ITER < PROP_RUNS_ACTIVE )); then
  fail "property loop ran only $PROP_ITER of $PROP_RUNS_ACTIVE cases"
fi
if (( PROP_FAILS == 0 && PROP_ITER >= PROP_RUNS_ACTIVE )); then
  prop_pass "legal-normalise-collapse" "$PROP_ITER"
fi

echo "passed: $passes  failed: $fails"
# 4 fixed assertions (LHS-floor, self-test, 2x negative control) + one pass
# per generated case — the floor scales with the PROP_RUNS budget.
MIN_ASSERTIONS=$((PROP_RUNS_ACTIVE + 4))
total=$((passes + fails))
if (( total < MIN_ASSERTIONS )); then
  echo "suite ran only ${total} assertions, expected at least ${MIN_ASSERTIONS} -- assertions are not running" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
