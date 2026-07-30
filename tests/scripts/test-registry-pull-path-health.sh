#!/usr/bin/env bash
# Test suite for scripts/registry-pull-path-health.sh (D10, #6929).
#
# The property that matters most here is NON-VACUITY: this gate replaced a specified-but-blind
# Better Stack query that could never return a row. So the suite's first duty is to prove the
# gate CAN go red — a positive control — and only then that it goes green when it should.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/scripts/registry-pull-path-health.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# make_stub <file> <ghcr-count> <local-cache-count> <zot-gate-degraded-count> <zot-count>
# Dispatches on the QUERY STRING, so a stub that ignored its argv (and would therefore validate
# nothing about which signals are actually queried) cannot pass.
#
# The last argument is the DENOMINATOR (registry="zot"): how many pulls zot actually served in
# the window. It is not a fourth degraded signal — it is what makes a zero in the three counters
# above mean "healthy" rather than "we observed nothing". Healthy fixtures must therefore supply
# a POSITIVE value; a zero there is its own ABORT case, covered below.
#
# Arm order is load-bearing: `*zot-gate-degraded*` must precede `*zot*`, or the degraded query
# would fall into the denominator arm and the third signal would silently read as the wrong
# number.
make_stub() {
  local f="$1" ghcr="$2" lc="$3" zgd="$4" zot="$5"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in\n'
    printf '  *ghcr-fallback*)      printf "%%s" %q ;;\n' "$ghcr"
    printf '  *local-cache*)        printf "%%s" %q ;;\n' "$lc"
    printf '  *zot-gate-degraded*)  printf "%%s" %q ;;\n' "$zgd"
    printf '  *zot*)                printf "%%s" %q ;;\n' "$zot"
    printf '  *) printf "UNEXPECTED_QUERY" ;;\n'
    printf 'esac\n'
  } > "$f"
  chmod +x "$f"
}

check() {
  local name="$1" want_rc="$2" needle="$3" stub="$4"; shift 4
  local out rc
  out="$(REGISTRY_PULL_HEALTH_QUERY_CMD="$stub" bash "$GATE" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== registry-pull-path-health ===\n\n'

# ── POSITIVE CONTROL: the gate must be able to go RED. ───────────────────────────────────────
# This is the assertion whose ABSENCE let the original Better Stack formulation ship blind.
make_stub "$TMP/one-ghcr.sh" 1 0 0 5
check "1 ghcr-fallback event => ABORT (positive control: the gate CAN fire)" \
  1 "ghcr-fallback=1" "$TMP/one-ghcr.sh"

make_stub "$TMP/one-lc.sh" 0 1 0 5
check "1 local-cache event => ABORT (both watched signals are wired)" \
  1 "local-cache=1" "$TMP/one-lc.sh"

# The third signal. ZOT_ACTIVE=0 means ci-deploy never ATTEMPTED zot, so it emits no
# ghcr-fallback at all while the fleet runs entirely on GHCR — invisible to the two counters
# above, and the likeliest real-world trigger for this gate.
make_stub "$TMP/one-zgd.sh" 0 0 1 5
check "1 zot-gate-degraded event => ABORT (the silent all-GHCR state is wired)" \
  1 "zot_gate_degraded=1" "$TMP/one-zgd.sh"

make_stub "$TMP/many.sh" 3 2 0 5
check "5 degraded events => ABORT naming the incident-vs-recut exit" \
  1 "INCIDENT path" "$TMP/many.sh"

# ── THE GATE NO LONGER HAS A PASS CONDITION (2026-07-30, #7071). ─────────────────────────────
# These three rows asserted `rc=0` on a healthy fleet, which was the correct contract while the
# gate's premise held: "zero degraded pull events" meant the GHCR fallback could cover the
# empty-store window the recut opens.
#
# That premise is retracted. GHCR is unreadable (read PAT revoked -> 401, minter disabled ->
# 403 DENIED), so nothing covers the window; and the gate's most direct operand went dark with
# it, because `ghcr-fallback` is emitted ONLY inside the success branch of a GHCR pull and can
# therefore never fire again. A clean count is now a statement about zot's own health that
# reads as authorization to destroy the only thing serving pulls.
#
# So the contract is now: still count, still print (the counts are real and worth having), and
# REFUSE. The rows below assert exactly that — the counters survive, the exit does not.
make_stub "$TMP/clean.sh" 0 0 0 5
check "zero degraded events => REFUSE (the gate has no valid PASS condition)" \
  1 "REFUSING" "$TMP/clean.sh"
check "the refusal names the retracted premise rather than a generic failure" \
  1 "no longer readable" "$TMP/clean.sh"
check "the refusal names the dark operand, so the reader knows the gate cannot self-correct" \
  1 "never fire" "$TMP/clean.sh"
check "the refusal routes to re-deriving an authorization condition" \
  1 "TO PROCEED" "$TMP/clean.sh"
# The counting half must keep working: a refusal that stopped measuring would hide the very
# signal a future authorization condition will be built from.
check "zero degraded events => counter line is still machine-readable" 1 "total=0 threshold=0" "$TMP/clean.sh"
check "the counter line still reports the denominator" 1 "zot_served=5" "$TMP/clean.sh"

# ── THE DENOMINATOR: zero degraded events is only evidence if something was served. ──────────
# Without this arm, states 2/3/4 from the script header (quiet window, ZOT_ACTIVE=0, dark
# emitter) are indistinguishable from a healthy fleet, and the gate authorizes an irreversible
# destroy on an absence of data.
make_stub "$TMP/unobserved.sh" 0 0 0 0
check "zero degraded AND zero served => ABORT (unobserved is not healthy)" \
  1 "UNOBSERVED" "$TMP/unobserved.sh"
check "the unobserved ABORT names the exit that exercises the pull path" \
  1 "web-platform-release.yml" "$TMP/unobserved.sh"

make_stub "$TMP/den-broken.sh" 0 0 0 "QUERY_FAILED"
check "denominator query failure => fail-closed ABORT" \
  1 "denominator query" "$TMP/den-broken.sh"

make_stub "$TMP/den-empty.sh" 0 0 0 ""
check "empty denominator response => fail-closed, never a counted zero" \
  1 "denominator query" "$TMP/den-empty.sh"

# ── FAIL-CLOSED on an unusable query. ────────────────────────────────────────────────────────
make_stub "$TMP/broken.sh" "QUERY_FAILED" 0 0 5
check "query failure on ghcr signal => fail-closed ABORT" \
  1 "FAIL-CLOSED" "$TMP/broken.sh"

make_stub "$TMP/broken2.sh" 0 "QUERY_FAILED" 0 5
check "query failure on local-cache signal => fail-closed ABORT" \
  1 "FAIL-CLOSED" "$TMP/broken2.sh"

make_stub "$TMP/broken3.sh" 0 0 "QUERY_FAILED" 5
check "query failure on zot-gate-degraded signal => fail-closed ABORT" \
  1 "FAIL-CLOSED" "$TMP/broken3.sh"

# An empty response must NOT be read as a counted zero.
make_stub "$TMP/empty.sh" "" 0 0 5
check "empty response => fail-closed, never a counted zero" \
  1 "FAIL-CLOSED" "$TMP/empty.sh"

# ── Argument validation. ─────────────────────────────────────────────────────────────────────
make_stub "$TMP/ok.sh" 0 0 0 5
# rc is 1 on every healthy-fleet row now (the gate refuses unconditionally, #7071) — what this
# row asserts is the WINDOW, which is unchanged.
check "--since-hours accepts a positive integer" 1 "(12h)" "$TMP/ok.sh" --since-hours 12
check "--since-hours rejects zero" 1 "positive integer" "$TMP/ok.sh" --since-hours 0
check "--since-hours rejects non-numeric" 1 "positive integer" "$TMP/ok.sh" --since-hours abc
check "unknown argument rejected" 1 "unknown argument" "$TMP/ok.sh" --nope

# ── The stub dispatches on argv, so the gate must query ALL declared signals. ─────────────────
# If the gate ever stopped passing the tag query through (or dropped a signal), the stub's
# fallback arm returns UNEXPECTED_QUERY, which is non-numeric => fail-closed.
make_stub "$TMP/strict.sh" 0 0 0 5
out="$(REGISTRY_PULL_HEALTH_QUERY_CMD="$TMP/strict.sh" bash "$GATE" 2>&1)"; rc=$?
# The subject here is the QUERY SHAPE, not the verdict. Since #7071 the gate refuses on every
# path, so rc is 1 even when every signal was queried correctly — the discriminator is the
# absence of UNEXPECTED_QUERY (the stub's fallback arm for a query it did not recognise), plus
# the presence of the counter line proving the responses were actually parsed. Asserting rc
# here would only re-assert the refusal, which four rows above already pin.
if [[ "$out" != *"UNEXPECTED_QUERY"* && "$out" == *"total=0 threshold=0"* ]]; then
  pass "all three watched signals + the denominator queried with their expected tag strings"
else
  fail "the gate must query all declared signals with the ci-deploy.sh tag shape" "$rc" "$out"
fi

# The WATCHED arity self-check must track the declared signal count, so adding a signal without
# updating it cannot ship a partial verdict.
if grep -qE '\$\{#WATCHED\[@\]\} != 3' "$GATE"; then
  pass "the WATCHED arity self-check matches the three declared signals"
else
  fail "the WATCHED arity self-check drifted from the declared signal count" "?" \
    "$(grep -nE '\$\{#WATCHED\[@\]\}' "$GATE" || true)"
fi

# The mask emit must be Actions-scoped: outside a runner `::add-mask::` is a plain echo that
# would print the live prd Sentry credential to the operator's terminal, and the runbook tells
# them to run this gate locally.
#
# Asserted on the GUARD's proximity to the emit, not on GITHUB_ACTIONS appearing anywhere in the
# file — the latter would pass on any unrelated use of the variable, which is the vacuity this
# suite exists to avoid. Every add-mask EMIT must have GITHUB_ACTIONS within the 2 lines above it.
#
# Comments are stripped first. The header above this gate's mask block explains `::add-mask::` in
# prose, so a bare body-grep counts that sentence as an emit and the assertion mismeasures — the
# same comments-are-not-code trap recorded in pre-merge-rebase-parity.test.sh T-S.
grep -vE '^[[:space:]]*#' "$GATE" > "$TMP/gate-nocomments.sh"
mask_emits=$(grep -c 'echo "::add-mask::' "$TMP/gate-nocomments.sh" || true)
mask_guarded=$(grep -B2 'echo "::add-mask::' "$TMP/gate-nocomments.sh" | grep -c 'GITHUB_ACTIONS' || true)
if [[ "$mask_emits" -ge 1 && "$mask_guarded" -ge "$mask_emits" ]]; then
  pass "the ::add-mask:: emit is guarded on GITHUB_ACTIONS (no local token echo)"
else
  fail "::add-mask:: must be Actions-scoped or it leaks the token locally" \
    "emits=$mask_emits guarded=$mask_guarded" "$(grep -n -B2 'add-mask' "$GATE" || true)"
fi

# ── Without a token AND without the seam, the gate refuses rather than assuming health. ──────
out="$(env -u SENTRY_AUTH_TOKEN -u REGISTRY_PULL_HEALTH_QUERY_CMD bash "$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"SENTRY_AUTH_TOKEN unset"* ]]; then
  pass "no token => refuses to authorize a destroy against an unverifiable pull path"
else
  fail "missing SENTRY_AUTH_TOKEN must fail closed" "$rc" "$out"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
