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

# make_stub <file> <ghcr-count> <local-cache-count>
# Dispatches on the QUERY STRING, so a stub that ignored its argv (and would therefore validate
# nothing about which signals are actually queried) cannot pass.
make_stub() {
  local f="$1" ghcr="$2" lc="$3"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$*" in\n'
    printf '  *ghcr-fallback*) printf "%%s" %q ;;\n' "$ghcr"
    printf '  *local-cache*)   printf "%%s" %q ;;\n' "$lc"
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
make_stub "$TMP/one-ghcr.sh" 1 0
check "1 ghcr-fallback event => ABORT (positive control: the gate CAN fire)" \
  1 "ghcr-fallback=1" "$TMP/one-ghcr.sh"

make_stub "$TMP/one-lc.sh" 0 1
check "1 local-cache event => ABORT (both watched signals are wired)" \
  1 "local-cache=1" "$TMP/one-lc.sh"

make_stub "$TMP/many.sh" 3 2
check "5 degraded events => ABORT naming the incident-vs-recut exit" \
  1 "INCIDENT path" "$TMP/many.sh"

# ── The healthy fleet passes. ────────────────────────────────────────────────────────────────
make_stub "$TMP/clean.sh" 0 0
check "zero degraded events => PASS" 0 "PASS — zero degraded pull events" "$TMP/clean.sh"
check "zero degraded events => counter line is machine-readable" 0 "total=0 threshold=0" "$TMP/clean.sh"

# ── FAIL-CLOSED on an unusable query. ────────────────────────────────────────────────────────
make_stub "$TMP/broken.sh" "QUERY_FAILED" 0
check "query failure on ghcr signal => fail-closed ABORT" \
  1 "FAIL-CLOSED" "$TMP/broken.sh"

make_stub "$TMP/broken2.sh" 0 "QUERY_FAILED"
check "query failure on local-cache signal => fail-closed ABORT" \
  1 "FAIL-CLOSED" "$TMP/broken2.sh"

# An empty response must NOT be read as a counted zero.
make_stub "$TMP/empty.sh" "" 0
check "empty response => fail-closed, never a counted zero" \
  1 "FAIL-CLOSED" "$TMP/empty.sh"

# ── Argument validation. ─────────────────────────────────────────────────────────────────────
make_stub "$TMP/ok.sh" 0 0
check "--since-hours accepts a positive integer" 0 "(12h)" "$TMP/ok.sh" --since-hours 12
check "--since-hours rejects zero" 1 "positive integer" "$TMP/ok.sh" --since-hours 0
check "--since-hours rejects non-numeric" 1 "positive integer" "$TMP/ok.sh" --since-hours abc
check "unknown argument rejected" 1 "unknown argument" "$TMP/ok.sh" --nope

# ── The stub dispatches on argv, so the gate must query BOTH declared signals. ────────────────
# If the gate ever stopped passing the tag query through (or dropped a signal), the stub's
# fallback arm returns UNEXPECTED_QUERY, which is non-numeric => fail-closed.
make_stub "$TMP/strict.sh" 0 0
out="$(REGISTRY_PULL_HEALTH_QUERY_CMD="$TMP/strict.sh" bash "$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 && "$out" != *"UNEXPECTED_QUERY"* ]]; then
  pass "both watched signals queried with their expected tag strings"
else
  fail "the gate must query both declared signals with the ci-deploy.sh tag shape" "$rc" "$out"
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
