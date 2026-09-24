#!/usr/bin/env bash
# ticket-triage intake pre-check — clause presence.
#
# WHY THIS EXISTS, AND WHY IT IS NOT THE SUITE IT REPLACES.
#
# `ticket-triage-mirror-parity.test.sh` asserted that the intake pre-check block was
# BYTE-IDENTICAL between two copies: the Claude agent (`agents/support/ticket-triage.md`)
# and the OpenHands mirror (`.openhands/skills/ticket-triage/SKILL.md`). ADR-245 retired
# the OpenHands port, so the identity assertion lost its second operand and the suite was
# deleted with the tree it guarded.
#
# Identity was never the whole property, though — the old suite said so itself, and asserted
# the clauses separately "because identity alone is satisfied by two copies that have BOTH
# lost a sentence." That half survives the retirement intact and is what this file keeps.
#
# The property: the advisory-only clause and the precedence rule are still IN the agent's
# pre-check block. ADR-234 traces the loss of "a hit is reported to a human and escalates;
# it never acts" through two automated hops to a permanently-closed issue attributed to a
# human decision that never happened. That consequence does not depend on how many copies
# of the prose exist.
#
# Direction note, carried over verbatim in force: this suite asserts NOTHING about identity
# between `skills/triage/SKILL.md` and the agent. That file is deliberately not a mirror —
# it is the attended WRITE path and carries a whole step the read-only reader must not have.
# It gets only the two clauses it actually owns, listed separately below.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AGENT="$ROOT/plugins/soleur/agents/support/ticket-triage.md"
SKILL="$ROOT/plugins/soleur/skills/triage/SKILL.md"

for f in "$AGENT" "$SKILL"; do
  [[ -r "$f" ]] || { printf 'FATAL: cannot read %s\n' "$f" >&2; exit 2; }
done

passes=0; fails=0; asserted=0
VERDICT_LOG="$(mktemp -t tt-clauses.XXXXXXXX.log)" || { printf 'FATAL: no scratch\n' >&2; exit 2; }
trap 'rm -f "$VERDICT_LOG"' EXIT
ok()  { printf '  PASS: %s\n' "$1"; printf 'PASS\n' >> "$VERDICT_LOG"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; printf 'FAIL\n' >> "$VERDICT_LOG"; fails=$((fails + 1)); }
ck()  { asserted=$((asserted + 1)); }

# --- INSTRUMENT SELF-TEST ------------------------------------------------------------------------
# Drive both verdict helpers once each against a sandbox ledger before any real row runs, and
# refuse to continue unless BOTH counters moved. A suite whose fail() has been disarmed reports
# a clean run that is indistinguishable from a real one (work/SKILL.md §ASSERT THE VALUE THAT
# MUST NEVER APPEAR). Reported with printf + exit, never through the helpers under test.
_st_log="$VERDICT_LOG"; _st_p=$passes; _st_f=$fails; _st_a=$asserted
VERDICT_LOG="$(mktemp -t tt-clauses-selftest.XXXXXXXX.log)" || { printf 'FATAL: no scratch\n' >&2; exit 2; }
passes=0; fails=0
ok "instrument self-test: pass() increments" >/dev/null
bad "instrument self-test: fail() increments" 2>/dev/null
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf '\nFATAL: instrument self-test: pass()=%d fail()=%d, both must be 1. A disarmed helper makes every row below vacuous.\n' \
    "$passes" "$fails" >&2
  exit 1
fi
rm -f "$VERDICT_LOG"
VERDICT_LOG="$_st_log"; passes=$_st_p; fails=$_st_f; asserted=$_st_a

# The shared block, derived from a content anchor at each end rather than from line numbers —
# the file carries unrelated prose above and below it, and a line-number slice would rot on the
# next edit (cq-cite-content-anchor-not-line-number).
block_of() { # <file>
  awk '/^- \*\*Prior-art pre-check \(read-only\)\.\*\*/{f=1}
       f{print}
       f && /write path is the attended/{exit}' "$1"
}
A_BLOCK="$(block_of "$AGENT")"

# --- ANTI-VACUITY FLOOR --------------------------------------------------------------------------
# An extraction that matched nothing leaves every `grep -qF` below searching an empty string. Today
# that fails LOUD, which is the safe direction — but it fails for the wrong reason, naming five lost
# clauses when the real fault is a moved anchor (AP-021), and any future edit that inverts one of
# these greps turns the same empty block silently green. Floor the block on its own, reported with
# printf + exit 1, never through ok()/bad() (ADR-193).
# The bound is derived: `block_of <file> | wc -c`, measured 2026-09-23 at 1653 bytes.
MIN_BLOCK_BYTES=900
if [[ "${#A_BLOCK}" -lt "$MIN_BLOCK_BYTES" ]]; then
  printf '\nFATAL: the agent pre-check block extracted %s byte(s), floor is %s — the content anchors no longer match, so every clause assertion below would be searching an empty string.\n' \
    "${#A_BLOCK}" "$MIN_BLOCK_BYTES" >&2
  exit 1
fi

# --- the clauses the agent's read-only pre-check must keep ---------------------------------------
# Each is a sentence whose LOSS authorises an action the pre-check exists to forbid. Asserted
# against the extracted BLOCK, not the whole file: a clause that migrated out of the pre-check
# into unrelated prose elsewhere in the document no longer governs the pre-check.
for clause in 'reported to a human and escalates' \
              'never, on its own, grounds to close' \
              'deferred-scope-out` must never be applied' \
              'fails open' \
              'the entry is STALE'; do
  ck
  if grep -qF -- "$clause" <<<"$A_BLOCK"; then
    ok "agent pre-check states '$clause'"
  else
    bad "the agent's intake pre-check has LOST the clause '$clause'. ADR-234 traces that loss through two automated hops to a permanently-closed issue attributed to a human decision that never happened."
  fi
done

# --- the two clauses the attended WRITE path owns ------------------------------------------------
# Deliberately a short list. `skills/triage/SKILL.md` is not a mirror of the agent and must not be
# forced into one; these two are the properties it shares because they are about the no-list LOOKUP,
# which both surfaces perform.
for clause in 'fails open' 'the entry is STALE'; do
  ck
  if grep -qF -- "$clause" "$SKILL"; then
    ok "attended triage skill states '$clause'"
  else
    bad "plugins/soleur/skills/triage/SKILL.md has LOST the clause '$clause' — the WRITE path is the surface where a stale or failed lookup does damage."
  fi
done

# --- accounting conservation ---------------------------------------------------------------------
_lp="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_lf="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
if [[ "${_lp:-0}" -ne "$passes" || "${_lf:-0}" -ne "$fails" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail) disagrees with the counters (%d / %d).\n' \
    "${_lp:-0}" "${_lf:-0}" "$passes" "$fails" >&2
  exit 1
fi
MIN_ASSERTIONS=7  # 5 agent clauses + 2 write-path clauses. Raise in the edit that adds a row.
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: %d assertion(s) executed, floor is %d (5 agent clauses + 2 write-path clauses). The suite ran but did not assert.\n' \
    "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: passes+fails (%d) != asserted (%d).\n' "$((passes + fails))" "$asserted" >&2
  exit 1
fi

printf '\nticket-triage-clauses.test.sh: %d passed, %d failed, %d assertion(s) executed; agent pre-check block %s bytes (floor %s), assertion floor %s\n' \
  "$passes" "$fails" "$asserted" "${#A_BLOCK}" "$MIN_BLOCK_BYTES" "$MIN_ASSERTIONS"

_lf_final="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
[[ "${_lf_final:-0}" -eq 0 && "$fails" -eq 0 && "$passes" -gt 0 ]] || exit 1
exit 0
