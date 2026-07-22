#!/usr/bin/env bash
#
# Tests for inngest-config-drift-compare.sh — the ADR-133 off-box drift comparator core
# (#6780, HARD-8 / AC19). Hermetic; no network, no LLM, no prod writes. Registered in
# .github/workflows/infra-validation.yml.
#
# Run: bash apps/web-platform/infra/inngest-config-drift-compare.test.sh
#
# Invariants (each mutation-checkable):
#   PENDING     — empty pointer ⇒ PENDING, exit 0 (channel-not-live, HARD-11; no false alarm).
#   OK          — applied sha256 == pointer ⇒ OK, exit 0.
#   DEAD-TIMER  — pointer set + no marker ⇒ DIVERGED, exit 2.
#   FLOOR-STUCK — pointer names a higher digest but only version=floor booted ⇒ DIVERGED, exit 2
#                 (the boot-floor marker does NOT mask a stuck delta — the distinguishability HARD-8
#                 requires).
#   FLOOR-OK    — pointer still equals the floor's own sha (nothing promoted above floor) ⇒ OK
#                 (the floor booting is NOT a divergence when the pointer is the floor).
#   MISMATCH    — applied sha256 != pointer ⇒ DIVERGED, exit 2.
#   NORMALIZE   — a "sha256:"-prefixed pointer compares equal to a bare-hex applied sha.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMP="${DIR}/inngest-config-drift-compare.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[[ -f "$CMP" ]] || { echo "FAIL: comparator not found: $CMP" >&2; exit 1; }

DIGEST_A="1111111111111111111111111111111111111111111111111111111111111111"
DIGEST_B="2222222222222222222222222222222222222222222222222222222222222222"
FLOOR_SHA="9999999999999999999999999999999999999999999999999999999999999999"

# run <expect_verdict-prefix> <expect_rc> -- <args...>
run_case() {
  local want_verdict="$1" want_rc="$2"; shift 2
  [[ "$1" == "--" ]] && shift
  local out rc
  out="$("$CMP" "$@" 2>&1)"; rc=$?
  local got_verdict="${out%% *}"
  if [[ "$got_verdict" == "$want_verdict" && "$rc" -eq "$want_rc" ]]; then pass
  else fail "expected ${want_verdict}/rc=${want_rc}, got ${got_verdict}/rc=${rc} — out: ${out}"; fi
}

# PENDING — empty pointer (pre-cutover). Even WITH a floor marker present, empty pointer is PENDING.
run_case PENDING 0 -- --pointer "" --marker ""
run_case PENDING 0 -- --pointer "" --marker "SOLEUR_INFRA_PULL_APPLIED version=floor sha256=${FLOOR_SHA} verify=ok"

# OK — applied matches pointer.
run_case OK 0 -- --pointer "$DIGEST_A" --marker "SOLEUR_INFRA_PULL_APPLIED version=7 sha256=${DIGEST_A} verify=ok"

# NORMALIZE — sha256:-prefixed pointer equals bare-hex applied sha.
run_case OK 0 -- --pointer "sha256:${DIGEST_A}" --marker "SOLEUR_INFRA_PULL_APPLIED version=7 sha256=${DIGEST_A} verify=ok"

# DEAD-TIMER — pointer promoted, no marker at all.
run_case DIVERGED 2 -- --pointer "$DIGEST_A" --marker ""

# FLOOR-STUCK — pointer names a higher digest but only version=floor booted.
run_case DIVERGED 2 -- --pointer "$DIGEST_A" --marker "SOLEUR_INFRA_PULL_APPLIED version=floor sha256=${FLOOR_SHA} verify=ok"

# FLOOR-OK — pointer still equals the floor's own sha (nothing promoted above floor): NOT divergence.
run_case OK 0 -- --pointer "$FLOOR_SHA" --marker "SOLEUR_INFRA_PULL_APPLIED version=floor sha256=${FLOOR_SHA} verify=ok"

# MISMATCH — applied sha != pointer (a real applied version, wrong digest).
run_case DIVERGED 2 -- --pointer "$DIGEST_A" --marker "SOLEUR_INFRA_PULL_APPLIED version=6 sha256=${DIGEST_B} verify=ok"

# The FLOOR-STUCK verdict must be distinguishable from a plain mismatch (HARD-8 message contract):
out="$("$CMP" --pointer "$DIGEST_A" --marker "SOLEUR_INFRA_PULL_APPLIED version=floor sha256=${FLOOR_SHA} verify=ok" 2>&1)"
case "$out" in
  *floor-only-stuck-delta*) pass ;;
  *) fail "FLOOR-STUCK verdict must name floor-only-stuck-delta (HARD-8 distinguishability) — got: $out" ;;
esac

echo "inngest-config-drift-compare.test.sh: ${passes} passed, ${fails} failed"
[[ $fails -eq 0 ]] || exit 1
