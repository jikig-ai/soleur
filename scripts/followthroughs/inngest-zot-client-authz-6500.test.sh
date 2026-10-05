#!/usr/bin/env bash
# Exit-code harness for inngest-zot-client-authz-6500.sh (#6500).
#
# This probe closes the issue that AUTHORIZES ADR-096 5.3b-i / 5.6 for the dedicated inngest host
# (#6500, CLOSED as COMPLETED 2026-09-24; zot-soak-6122.sh's blocker arm still reads it),
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
# Instrument self-test (ported from zot-soak-6122.test.sh): drive fail() and pass() once each and
# require that fail() moved the counter the verdict reads (fails) and that both moved checks,
# then unwind. A fail() that only bumped checks would read every real failure as green. Reported
# with printf + exit, never through the helpers under test.
fail "self-test (expected)" 2>/dev/null; pass "self-test (expected)" >/dev/null
if [[ "$fails" -ne 1 || "$checks" -ne 2 ]]; then
  printf 'FATAL: the verdict helpers do not count (fails=%s checks=%s)\n' "$fails" "$checks" >&2
  exit 1
fi
fails=0; checks=0

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The stub is on PATH, not injected through a variable. It MOVED there on 2026-09-20, when the
# probe was migrated onto scripts/lib/trusted-verdict.sh: the lib calls `gh` directly (a security
# lib must not take an injectable binary path — that is an env-settable key on the thing it
# authenticates), so an `INNGEST_AUTHZ_6500_GH_BIN` seam could no longer reach it. A PATH shim is
# the stronger seam anyway, because it also intercepts the lib's own `gh api` permission call.
#
# It ASSERTS ITS ARGV and exits 64 on anything it was not built to answer. A stub that answers
# regardless of the request puts the fixture seam ABOVE the code under test, so it cannot detect
# the probe asking the wrong question — and dropping the `--repo` pin (which would resolve
# permissions against the wrong repository) would stay green.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
argv="$*"
if [[ "${1:-}" == "api" ]]; then
  # scripts/lib/trusted-verdict.sh resolving a commenter's effective permission.
  ep="${2:-}"
  case "$ep" in
    repos/jikig-ai/soleur/collaborators/*/permission) : ;;
    *) echo "stub: unexpected gh api endpoint: $ep" >&2; exit 64 ;;
  esac
  login="${ep#*/collaborators/}"; login="${login%/permission}"
  perm="$(printf '%s\n' "${STUB_PERMS:-}" | awk -F'=' -v l="$login" '$1==l{print $2}')"
  # Absent from $STUB_PERMS == GitHub's "not a user" 404: definitive, drop that author.
  [[ -n "$perm" ]] || { printf 'gh: %s is not a user (HTTP 404)\n' "$login" >&2; exit 1; }
  printf '%s\n' "$perm"; exit 0
fi
[[ "$argv" == *"--json comments"* ]] || { echo "stub: gh call missing --json comments (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--repo"* ]] || { echo "stub: gh call missing --repo pin (argv: $argv)" >&2; exit 64; }
# $STUB_BODIES is one verdict body per line; render it as the comments payload the lib reads,
# attributed to $STUB_AUTHOR so the permission arm above decides whether it counts. The REAL
# --jq expression is then applied to it: running the SUT's own expression (rather than a
# canned output) is what keeps the lib's selection genuinely exercised instead of simulated.
jqexpr=""; prev=""
for a in "$@"; do [[ "$prev" == "--jq" ]] && jqexpr="$a"; prev="$a"; done
[[ -n "$jqexpr" ]] || { echo "stub: gh call carried no --jq (argv: $argv)" >&2; exit 64; }
jq -Rn --arg a "${STUB_AUTHOR:-operator}" \
   '[inputs | {author:{login:$a}, body:.}] | {comments: .}' < "${STUB_BODIES:-/dev/null}" \
  | jq -r "$jqexpr"
STUB
chmod +x "$WORK/bin/gh"

# Default: a trusted author, so the pre-existing rows keep asserting what they always asserted.
export STUB_PERMS='operator=admin
drive-by=none'

run() {
  OUT="$(GH_TOKEN=t PATH="$WORK/bin:$PATH" STUB_BODIES="$1" STUB_RC="${STUB_RC:-0}" \
        STUB_AUTHOR="${STUB_AUTHOR:-operator}" bash "$PROBE" 2>&1)"
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
OUT="$(PATH="$WORK/bin:$PATH" STUB_BODIES="$WORK/none.txt" \
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

# --- A10 FORGERY: an untrusted author cannot authorise the retirement ----------------------------------------
# THE ROW THIS HARNESS DID NOT HAVE. Until 2026-09-20 this probe read `.comments[].body` with no
# author filter at all, so a `RESULT: PASS` from any authenticated GitHub user on this PUBLIC repo
# would have closed a tracker that authorises an ADR-096 Phase 5.3-5.5 supply-chain retirement.
# Twelve green checks said nothing about it, because every fixture was implicitly the operator.
printf 'RESULT: PASS\n' > "$WORK/forged.txt"
STUB_AUTHOR=drive-by run "$WORK/forged.txt"
expect "A10 a stranger's RESULT: PASS does NOT authorise (untrusted -> no verdict)" 2 "reason=awaiting_operator_verdict"

# --- A11 the same verdict from a trusted author DOES authorise -------------------------------------------------
# The must-PASS half. Without it, A10 is satisfied by a filter that rejects everyone — which is
# indistinguishable from a working filter on the negative case, and is exactly how the lib's own
# subshell-memo defect hid during development.
STUB_AUTHOR=operator run "$WORK/forged.txt"
expect "A11 a trusted author's RESULT: PASS still authorises" 0 ""

# --- A12 a failed permission read is TRANSIENT, never an authorisation -----------------------------------------
STUB_AUTHOR=ghost run "$WORK/forged.txt"
expect "A12 an unresolvable author is dropped, not trusted" 2 "reason=awaiting_operator_verdict"

# --- A9 anti-vacuity ----------------------------------------------------------------------------------------
if [[ "$checks" -ne 14 ]]; then
  fail "A9 anti-vacuity: expected 14 checks before this one, ran $checks"
else
  pass "A9 anti-vacuity: full inventory ran (14 checks + this one)"
fi

echo
if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails of $checks checks" >&2
  exit 1
fi
echo "OK: all $checks exit-code checks correct"
