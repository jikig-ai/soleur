#!/usr/bin/env bash
# Cross-check + semantic tests for the frontmatter-strip contract (issue #5999,
# ADR-094; third impl strip.ts added for #6794). For every fixture in
# frontmatter-strip/fixtures/*.in:
#   1. PARITY  — strip.sh, strip.py, and strip.ts outputs are byte-identical.
#   2. SEMANTIC — named fixtures satisfy the contract (SPEC.md).
# Parity alone could pass on identically-wrong impls, so both are asserted.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/frontmatter-strip"
SH="$DIR/strip.sh"
PY="$DIR/strip.py"
TS="$DIR/strip.ts"
FIX="$DIR/fixtures"

PASS=0; FAIL=0; TOTAL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "FAIL: $1"; echo "  detail: ${2:-}"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

command -v perl    >/dev/null 2>&1 || { echo "SKIP: perl missing"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing"; exit 0; }
# strip.ts needs a TS runtime; the scripts CI shard has none. Skip the TS arm
# (the sh<->py parity still runs) when bun is absent — this suite is registered
# in test-all.sh's `want_bun` block where bun is guaranteed present. Mirrors the
# perl/python3 skip-gates above.
HAS_BUN=0
command -v bun >/dev/null 2>&1 && HAS_BUN=1
[[ -f "$SH" && -f "$PY" ]] || { echo "SKIP: strip impls not present (RED)"; exit 0; }
if [[ "$HAS_BUN" -eq 1 ]]; then
  [[ -f "$TS" ]] || { echo "FAIL: strip.ts missing but bun present"; exit 1; }
fi

# --- PARITY across every fixture -------------------------------------------
for f in "$FIX"/*.in; do
  name=$(basename "$f" .in)
  sh_out=$(bash "$SH" < "$f"; printf 'x')      # 'x' sentinel preserves trailing newlines
  py_out=$(python3 "$PY" < "$f"; printf 'x')
  if [[ "$sh_out" == "$py_out" ]]; then
    pass "parity: strip.sh == strip.py on $name"
  else
    fail "parity: $name" "sh=<<${sh_out}>> py=<<${py_out}>>"
  fi
  if [[ "$HAS_BUN" -eq 1 ]]; then
    ts_out=$(bun run "$TS" < "$f"; printf 'x')
    if [[ "$ts_out" == "$py_out" ]]; then
      pass "parity: strip.ts == strip.py on $name"
    else
      fail "parity(ts): $name" "ts=<<${ts_out}>> py=<<${py_out}>>"
    fi
  fi
done

# --- SEMANTIC: well-formed frontmatter is removed, rules survive -----------
wf=$(bash "$SH" < "$FIX/with-frontmatter.in")
if ! grep -q 'last_reviewed:' <<<"$wf" && ! grep -q 'review_cadence:' <<<"$wf"; then
  pass "with-frontmatter: last_reviewed/review_cadence stripped"
else
  fail "with-frontmatter: frontmatter keys should be gone" "$wf"
fi
if grep -q '\[id: hr-alpha\]' <<<"$wf" && grep -q '\[id: hr-beta\]' <<<"$wf"; then
  pass "with-frontmatter: rule bodies preserved"
else
  fail "with-frontmatter: rule bodies must survive" "$wf"
fi

# --- SEMANTIC: no leading frontmatter → unchanged (embedded --- untouched) --
nf_in=$(cat "$FIX/no-frontmatter.in")
nf_out=$(bash "$SH" < "$FIX/no-frontmatter.in")
if [[ "$nf_in" == "$nf_out" ]]; then
  pass "no-frontmatter: input returned unchanged (embedded --- not treated as frontmatter)"
else
  fail "no-frontmatter: must be unchanged" "out=$nf_out"
fi

# --- SEMANTIC: malformed (unterminated) → empty (over-strip signal) --------
mf_out=$(bash "$SH" < "$FIX/malformed-unterminated.in")
if [[ -z "$mf_out" ]]; then
  pass "malformed-unterminated: consumed to empty (over-strip signal)"
else
  fail "malformed-unterminated: expected empty output" "out=$mf_out"
fi

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
