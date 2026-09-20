#!/usr/bin/env bash
# ticket-triage mirror parity.
#
# WHY THIS EXISTS. The intake pre-checks ship in THREE places: the attended skill
# (`plugins/soleur/skills/triage/SKILL.md`), the Claude agent
# (`plugins/soleur/agents/support/ticket-triage.md`) and the OpenHands mirror
# (`.openhands/skills/ticket-triage/SKILL.md`). The last two are mirrors of one another — same
# description, same triggers, same prose — and nothing compared them.
#
# The two mirrors run on DIFFERENT ENGINES, which is what makes drift expensive rather than untidy.
# OpenHands has no lefthook and no CI arm here, so an agent reading the stale copy is the one whose
# writes reach the repository with the fewest gates in front of them. And the specific prose at stake
# is the advisory-only clause plus the precedence rule: a mirror that loses the sentence "a hit is
# reported to a human and escalates; it never acts" is a mirror that authorises an agent to close
# issues on the strength of a no-list entry, which ADR-234 traces through two automated hops to a
# permanently-closed issue attributed to a human decision that never happened.
#
# So the property is not "both files exist" and not "both mention the no-list". It is that the shared
# prose is BYTE-IDENTICAL, because that is the only form of the claim a drifted copy cannot satisfy.
#
# Direction note: this suite says nothing about `skills/triage/SKILL.md`. That file is deliberately
# NOT a mirror — it is the attended WRITE path and carries a whole step the read-only mirrors must not
# have. Asserting three-way identity would force the write path into the mirrors, which is the
# opposite of the boundary.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AGENT="$ROOT/plugins/soleur/agents/support/ticket-triage.md"
MIRROR="$ROOT/.openhands/skills/ticket-triage/SKILL.md"

for f in "$AGENT" "$MIRROR"; do
  [[ -r "$f" ]] || { printf 'FATAL: cannot read %s\n' "$f" >&2; exit 2; }
done

passes=0; fails=0; asserted=0
VERDICT_LOG="$(mktemp -t tt-mirror.XXXXXXXX.log)" || { printf 'FATAL: no scratch\n' >&2; exit 2; }
trap 'rm -f "$VERDICT_LOG"' EXIT
ok()  { printf '  PASS: %s\n' "$1"; printf 'PASS\n' >> "$VERDICT_LOG"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; printf 'FAIL\n' >> "$VERDICT_LOG"; fails=$((fails + 1)); }
ck()  { asserted=$((asserted + 1)); }

# The shared block, derived from a content anchor at each end rather than from line numbers — both
# files carry unrelated prose above and below it, and a line-number slice would rot on the next edit.
block_of() { # <file>
  awk '/^- \*\*Prior-art pre-check \(read-only\)\.\*\*/{f=1}
       f{print}
       f && /write path is the attended/{exit}' "$1"
}
A_BLOCK="$(block_of "$AGENT")"
M_BLOCK="$(block_of "$MIRROR")"

# --- ANTI-VACUITY FLOORS -------------------------------------------------------------------------
# Two empty strings are byte-identical, so an extraction that matched nothing would report perfect
# parity. Each side is floored on its own, reported with printf + exit 1, never through ok()/bad()
# (ADR-193). The bound is derived: `block_of <file> | wc -c` on either mirror.
MIN_BLOCK_BYTES=900
for pair in "agent:$A_BLOCK" "openhands-mirror:$M_BLOCK"; do
  _label="${pair%%:*}"; _body="${pair#*:}"
  if [[ "${#_body}" -lt "$MIN_BLOCK_BYTES" ]]; then
    printf '\nFATAL: the %s pre-check block extracted %s byte(s), floor is %s — the content anchors no longer match, so the parity assertion below would compare two empty strings and report them equal.\n' \
      "$_label" "${#_body}" "$MIN_BLOCK_BYTES" >&2
    exit 1
  fi
done

# --- the parity assertion -------------------------------------------------------------------------
ck
if [[ "$A_BLOCK" == "$M_BLOCK" ]]; then
  ok "the intake pre-check block is byte-identical across both mirrors (${#A_BLOCK} bytes)"
else
  bad "the intake pre-check block has DRIFTED between the two mirrors. The OpenHands copy runs on an engine with no lefthook and no CI arm in this repository, so the stale copy is the one whose writes reach the repository with the fewest gates. Diff:
$(diff <(printf '%s\n' "$A_BLOCK") <(printf '%s\n' "$M_BLOCK") | head -20)"
fi

# The clauses that must survive any future rewrite, asserted by content rather than by identity:
# identity alone is satisfied by two copies that have BOTH lost a sentence.
for clause in 'reported to a human and escalates' 'never, on its own, grounds to close' \
              'deferred-scope-out` must never be applied' 'fails open' 'the entry is STALE'; do
  for pair in "agent:$A_BLOCK" "openhands-mirror:$M_BLOCK"; do
    _label="${pair%%:*}"; _body="${pair#*:}"
    ck
    if grep -qF -- "$clause" <<<"$_body"; then
      ok "$_label states '$clause'"
    else
      bad "$_label has LOST the clause '$clause' — identity between the mirrors cannot see this, because both copies can lose the same sentence together"
    fi
  done
done

# --- accounting conservation ----------------------------------------------------------------------
_lp="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_lf="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
if [[ "${_lp:-0}" -ne "$passes" || "${_lf:-0}" -ne "$fails" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail) disagrees with the counters (%d / %d).\n' \
    "${_lp:-0}" "${_lf:-0}" "$passes" "$fails" >&2
  exit 1
fi
EXPECTED_ASSERTIONS=11
MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: %d assertion(s) executed, floor is %d (1 identity + 5 clauses x 2 mirrors). The suite ran but did not assert.\n' \
    "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: passes+fails (%d) != asserted (%d).\n' "$((passes + fails))" "$asserted" >&2
  exit 1
fi

printf '\nticket-triage-mirror-parity.test.sh: %d passed, %d failed, %d assertion(s) executed; shared block %s bytes (floor %s), assertion floor %s\n' \
  "$passes" "$fails" "$asserted" "${#A_BLOCK}" "$MIN_BLOCK_BYTES" "$MIN_ASSERTIONS"

_lf_final="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
[[ "${_lf_final:-0}" -eq 0 && "$fails" -eq 0 && "$passes" -gt 0 ]] || exit 1
exit 0
