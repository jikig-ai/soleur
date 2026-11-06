#!/usr/bin/env bash
# inngest-gate-witness-classify.sh — token→action classifier for the #8080
# satisfiability witness arm in .github/workflows/scheduled-inngest-health.yml.
#
# WHY EXTRACTED. The verdict→action table must be drivable RED
# (apps/web-platform/infra/inngest-gate-witness-classify.test.sh): an inline
# `case` in a workflow `run:` block is untestable — the same idiom as
# scripts/inngest-dedicated-host-classify.sh.
#
# USAGE:
#   inngest-gate-witness-classify.sh <token> [cutover_flag]   → prints satisfy | refusal | suppressed
#   inngest-gate-witness-classify.sh --selftest               → prints "inngest-gate-witness-classify selftest: ok"
#
# <token> is the stdout verdict of `inngest_execute_registry_gate`
# (tests/scripts/lib/inngest-host-dark-gate.sh): `dark` or a refusal token.
# <cutover_flag> is the newest available INNGEST_CUTOVER_FLIP value — the
# gate's emit file `flag=`/`hb_flag=` field when present, else the newest
# probe row's `cutover_flag=`, else `unknown`.
#
# TABLE (CTO ruling 2026-11-01):
#   armed-class flag ({armed,flipping,flushed,done} via the lib's own
#     `_erg_flag_class` partition) OR token `flag_armed` → `suppressed`
#     (a cutover is in flight or done — the refusal is expected; the streak
#     is HELD, not incremented and not reset. `done` suppresses permanently:
#     self-retirement; a rollback re-arms the witness automatically).
#   `dark`                                             → `satisfy`  (streak := 0)
#   any refusal token, `host_serving` included         → `refusal`  (streak += 1)
#   ANY UNKNOWN TOKEN                                  → `refusal`  (fail-closed:
#     an unmappable verdict is a broken instrument, never a silent pass).
#
# Suppression is evaluated BEFORE the token table so an armed flag holds even
# a contradictory dark token (unreachable in practice — the gate refuses
# flag_armed before it can emit dark — but the rule reads cleanly).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# INNGEST_HOST_DARK_GATE_LIB is the test-sandbox override, mirroring
# INNGEST_PROBE_ROW_LIB in the gate lib itself.
_IGW_LIB="${INNGEST_HOST_DARK_GATE_LIB:-$REPO_ROOT/tests/scripts/lib/inngest-host-dark-gate.sh}"
# shellcheck source=tests/scripts/lib/inngest-host-dark-gate.sh
source "$_IGW_LIB" 2>/dev/null || true

# $1 = gate verdict token, $2 = newest cutover flag (may be empty/unknown)
inngest_gate_witness_classify() {
  local token="${1:-}" flag="${2:-}"
  if declare -F _erg_flag_class >/dev/null 2>&1; then
    [[ "$(_erg_flag_class "$flag")" == "armed" ]] && { echo "suppressed"; return 0; }
  else
    # The lib did not load: the flag partition cannot be evaluated, so nothing
    # may suppress — fail closed to refusal (a broken instrument files, never
    # reads as satisfy).
    echo "refusal"; return 0
  fi
  case "$token" in
    dark)             echo "satisfy" ;;
    flag_armed)       echo "suppressed" ;;
    # The lib's refusal vocabulary, spelled out token-by-token so the suite's
    # `_ihdg_verdict` census pins an arm for every literal the lib can emit —
    # an added lib token lands UNLISTED and the census reddens.
    unreadable|silent|wrong_host|stale_row|stale_schema|host_serving|flag_unreadable|fsm_unreadable|fsm_silent)
                      echo "refusal" ;;
    *)                echo "refusal" ;;
  esac
}

case "${1:-}" in
  --selftest)
    ok=1
    [[ "$(inngest_gate_witness_classify dark aborted)" == "satisfy" ]] || ok=0
    [[ "$(inngest_gate_witness_classify stale_row rolled-back)" == "refusal" ]] || ok=0
    [[ "$(inngest_gate_witness_classify stale_row armed)" == "suppressed" ]] || ok=0
    [[ "$(inngest_gate_witness_classify flag_armed rolled-back)" == "suppressed" ]] || ok=0
    [[ "$(inngest_gate_witness_classify not_a_token aborted)" == "refusal" ]] || ok=0
    if [[ "$ok" -eq 1 ]]; then
      echo "inngest-gate-witness-classify selftest: ok"
      exit 0
    fi
    echo "inngest-gate-witness-classify selftest: FAILED" >&2
    exit 1
    ;;
  "")
    echo "usage: $0 <token> [cutover_flag] | --selftest" >&2
    exit 2
    ;;
  *)
    inngest_gate_witness_classify "$1" "${2:-}"
    ;;
esac
