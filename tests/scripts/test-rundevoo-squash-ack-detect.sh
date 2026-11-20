#!/usr/bin/env bash
# Tests for scripts/rundevoo-squash-ack-detect.sh (#12971). Mirrors
# tests/scripts/test-sentry-squash-ack-detect.sh (#6589).
#
# The predictor reconstructs GitHub's COMMIT_MESSAGES squash body ("* subject"
# + verbatim body lines, commits joined by a blank line) and tests THAT, not
# the raw inputs. Subject-acks must NOT detect (the bullet destroys the line
# anchor); body-line acks must.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DETECT="$REPO_ROOT/scripts/rundevoo-squash-ack-detect.sh"
pass=0; fail=0
EXPECTED_TESTS=14

_report() {
  if [[ "$2" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $1"
  else fail=$((fail + 1)); echo "[FAIL] $1 $3" >&2; fi
}

if [[ ! -f "$DETECT" ]]; then
  echo "ERROR: $DETECT does not exist — RED phase expected this." >&2
  exit 1
fi

_case() { # $1=label $2=want-rc $3=messages-json
  local rc=0
  printf '%s' "$3" | bash "$DETECT" || rc=$?
  if [[ "$rc" -eq "$2" ]]; then _report "$1 -> rc=$rc" ok
  else _report "$1" fail "rc=$rc want $2"; fi
}

# T1: [ack-destroy] on its own BODY line of the only commit — survives the
# "* subject" prefix because body lines are carried verbatim.
_case "T1 body-line ack in single commit detects" 0 \
  '["feat: drop zone record\n\n[ack-destroy]\n\nRefs #12971."]'

# T2: [ack-destroy] in the commit SUBJECT does NOT detect — GitHub renders it
# "* [ack-destroy] …" and the bullet destroys the line anchor the apply gate
# requires. The single most dangerous misread.
_case "T2 subject ack does NOT detect" 1 \
  '["feat: [ack-destroy] drop record"]'

# T3: no ack anywhere -> 1.
_case "T3 no ack -> 1" 1 \
  '["feat: drop record", "chore: tidy"]'

# T4: ack in the BODY of a non-head commit still detects — the squash body
# concatenates every commit's body verbatim.
_case "T4 ack in an earlier commit's body detects" 0 \
  '["feat: a", "feat: b\n\n[ack-destroy]", "feat: c"]'

# T5: mid-line [ack-destroy] in a body does NOT detect (anchored both sides).
_case "T5 mid-line body ack does NOT detect" 1 \
  '["feat: a\n\nthe fix is [ack-destroy] here"]'

# T6: an ack as the very LAST line of the squash body (no trailing newline)
# still detects — the ($|\n) right anchor permits end-of-string.
_case "T6 trailing body-line ack detects" 0 \
  '["feat: a\n\n[ack-destroy]"]'

# T7: empty input array -> 1 (fail closed, never a green on nothing).
_case "T7 empty commit list does NOT detect" 1 '[]'

# T8: the DISCRIMINATING case — an ack that IS the whole subject. It fails the
# anchored regex only because of the "* " bullet prefix; without it a raw
# grep over inputs would wrongly accept (and the apply gate would then red).
_case "T8 ack AS the whole subject does NOT detect" 1 '["[ack-destroy]"]'

# T9: same, buried among several commits.
_case "T9 whole-subject ack among several commits does NOT detect" 1 \
  '["chore: init","[ack-destroy]","feat: remove record"]'

# T10: ack with trailing text on the same body line is not line-anchored.
_case "T10 ack with trailing text on the body line does NOT detect" 1 \
  '["feat: x\n\n[ack-destroy] because the record is dead"]'

# T11-T13: near-miss literals must not satisfy the gate — a partially
# unanchored or case-insensitive regex "simplification" would green these.
_case "T11 [ack-destroy-all] does NOT detect" 1 \
  '["feat: x\n\n[ack-destroy-all]"]'
_case "T12 [ACK-DESTROY] (wrong case) does NOT detect" 1 \
  '["feat: x\n\n[ACK-DESTROY]"]'
_case "T13 bare ack-destroy without brackets does NOT detect" 1 \
  '["feat: x\n\nack-destroy"]'

# T14: non-vacuity anchor — the SAME literal must give different verdicts in
# body vs subject position. If both return the same, the script has been
# "simplified" back into a grep.
t_emulation_distinguishes_position() {
  local body_rc=0 subj_rc=0
  printf '%s' '["feat: x\n\n[ack-destroy]"]' | bash "$DETECT" >/dev/null 2>&1 || body_rc=$?
  printf '%s' '["[ack-destroy]"]'            | bash "$DETECT" >/dev/null 2>&1 || subj_rc=$?
  if [[ "$body_rc" -eq 0 && "$subj_rc" -eq 1 ]]; then
    _report "T14 body-vs-subject give DIFFERENT verdicts (emulation is real)" ok
  else
    _report "T14 body-vs-subject give DIFFERENT verdicts" fail \
      "body_rc=$body_rc (want 0) subj_rc=$subj_rc (want 1) — a grep returns the same verdict for both"
  fi
}

t_emulation_distinguishes_position

echo "=== $pass passed, $fail failed ==="
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
