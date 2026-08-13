#!/usr/bin/env bash
# Exit-code harness for inngest-zot-client-authz-6500.sh (#6500).
#
# This probe closes the issue that AUTHORIZES retiring GHCR push/egress (ADR-096 Phase 5.3-5.5),
# so every case below is a way a close could be granted that no operator granted. Two of them are
# the failure modes the sibling operator-confirmed probe actually shipped with (#7437): an
# unanchored verdict match, and PASS evaluated before FAIL so a retraction loses to the string it
# retracts.
#
# Values are synthesized (cq-test-fixtures-synthesized-only).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/inngest-zot-client-authz-6500.sh"
fails=0
checks=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The stub ASSERTS ITS ARGV. Without it, dropping --comments (which would return an empty comment
# set and wedge the probe at awaiting_operator_verdict forever) stays green.
cat > "$WORK/stub-gh" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
argv="$*"
[[ "$argv" == *"--comments"* ]] || { echo "stub: gh call missing --comments (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--repo"* ]] || { echo "stub: gh call missing --repo pin (argv: $argv)" >&2; exit 64; }
cat "${STUB_BODIES:-/dev/null}"
STUB
chmod +x "$WORK/stub-gh"

run() {
  OUT="$(GH_TOKEN=t INNGEST_AUTHZ_6500_GH_BIN="$WORK/stub-gh" STUB_BODIES="$1" STUB_RC="${STUB_RC:-0}" \
        bash "$PROBE" 2>&1)"
  RC=$?
}

expect() {
  local name="$1" want_rc="$2" want_sub="$3"
  if [[ "$RC" -ne "$want_rc" ]]; then
    fail "$name — rc=$RC want=$want_rc :: $(printf '%s' "$OUT" | head -1)"
  elif ! grep -qF "$want_sub" <<<"$OUT"; then
    fail "$name — rc ok but missing '$want_sub' :: $(printf '%s' "$OUT" | head -1)"
  else
    pass "$name"
  fi
}

echo "== inngest-zot-client-authz-6500.sh exit-code harness =="

# --- A1 no token -----------------------------------------------------------------------------------
: > "$WORK/none.txt"
OUT="$(INNGEST_AUTHZ_6500_GH_BIN="$WORK/stub-gh" STUB_BODIES="$WORK/none.txt" \
      env -u GH_TOKEN bash "$PROBE" 2>&1)"; RC=$?
expect "A1 GH_TOKEN unset -> TRANSIENT credentials_unprovisioned" 2 "reason=credentials_unprovisioned"

# --- A2 API failure ---------------------------------------------------------------------------------
STUB_RC=3 run "$WORK/none.txt"; STUB_RC=0
expect "A2 gh rc!=0 -> TRANSIENT api_unavailable" 2 "reason=api_unavailable"

# --- A3 the expected steady state ---------------------------------------------------------------------
printf 'just a normal comment\nno verdict here\n' > "$WORK/chatter.txt"
run "$WORK/chatter.txt"
expect "A3 no verdict -> TRANSIENT awaiting_operator_verdict" 2 "reason=awaiting_operator_verdict"

# --- A4 the only PASS -----------------------------------------------------------------------------------
printf 'looks good to me\nRESULT: PASS\n' > "$WORK/ok.txt"
run "$WORK/ok.txt"
expect "A4 an anchored RESULT: PASS -> PASS" 0 "an operator authorized #6500"

# --- A5 ANCHORING: a question about the criterion must not authorize ---------------------------------
printf 'what exactly is the RESULT: PASS criterion here?\n' > "$WORK/question.txt"
run "$WORK/question.txt"
expect "A5 verdict quoted mid-sentence does NOT authorize" 2 "reason=awaiting_operator_verdict"
printf '  RESULT: PASS\n' > "$WORK/indented.txt"
run "$WORK/indented.txt"
expect "A5b an indented verdict does NOT authorize (line-start anchor)" 2 "reason=awaiting_operator_verdict"
printf 'RESULT: PASSED\n' > "$WORK/passed.txt"
run "$WORK/passed.txt"
expect "A5c 'RESULT: PASSED' is not the exact token" 2 "reason=awaiting_operator_verdict"

# --- A6 ORDERING: a retraction must beat the PASS it retracts ------------------------------------------
printf 'RESULT: PASS\nactually no, reverting that\nRESULT: FAIL\n' > "$WORK/retract.txt"
run "$WORK/retract.txt"
expect "A6 RESULT: FAIL after RESULT: PASS -> FAIL (retraction wins)" 1 "reason=authorization_refused"
printf 'RESULT: FAIL\nRESULT: PASS\n' > "$WORK/failfirst.txt"
run "$WORK/failfirst.txt"
expect "A6b order-independent: any refusal blocks regardless of position" 1 "reason=authorization_refused"

# --- A7 CRLF from the GitHub web UI must not defeat the anchor ------------------------------------------
printf 'RESULT: PASS\r\n' > "$WORK/crlf.txt"
run "$WORK/crlf.txt"
expect "A7 a CRLF verdict still authorizes (web-UI comments carry \\r)" 0 "an operator authorized #6500"

# --- A8 the banned form -----------------------------------------------------------------------------------
# Mirrors scripts/lint-followthrough-varq-ban.sh: raw grep for line numbers, then drop full-line comments.
if grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$PROBE" | grep -qvE '^[0-9]+:[[:space:]]*#'; then
  fail "A8 probe uses the banned \${VAR:?} form in code"
else
  pass "A8 probe avoids the banned \${VAR:?} form in code"
fi

# --- A9 anti-vacuity ----------------------------------------------------------------------------------------
if [[ "$checks" -ne 11 ]]; then
  fail "A9 anti-vacuity: expected 11 checks before this one, ran $checks"
else
  pass "A9 anti-vacuity: full inventory ran (11 checks + this one)"
fi

echo
if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails of $checks checks" >&2
  exit 1
fi
echo "OK: all $checks exit-code checks correct"
