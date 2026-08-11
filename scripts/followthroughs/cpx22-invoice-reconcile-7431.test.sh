#!/usr/bin/env bash
# Exit-code harness for cpx22-invoice-reconcile-7431.sh (#7437).
#
# The probe decides whether a production ledger stands or gets corrected, and it decides it from
# free text a human typed into a GitHub comment. Two properties therefore matter more than the
# happy path:
#
#   * the verdict must be ANCHORED. This issue body necessarily quotes the strings `RESULT: PASS`
#     and `RESULT: FAIL` while explaining how to close it, and the probe reads COMMENTS — but any
#     of that prose can be pasted into a comment while discussing the reconciliation. An
#     unanchored grep would then close the issue on a comment that was asking a question about it.
#   * it must not be anchored at the END. Peers use `^RESULT: PASS$`, which rejects the actual
#     figure this issue REQUIRES the operator to state. A probe whose accept-shape contradicts its
#     own instructions never closes.
#
# THE SEAM is PATH: the probe shells out to `gh`, so a stub `gh` drives every arm through the real
# script and its real greps. Testing against the live issue would mean posting throwaway verdicts
# to a production tracker.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/cpx22-invoice-reconcile-7431.sh"
fails=0
checks=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# `gh issue list ...` -> the issue number in ISSUE_NUM (empty simulates "cannot find itself").
# `gh issue view ...` -> the comment bodies in COMMENTS.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  list) printf '%s' "${ISSUE_NUM:-}" ;;
  view) printf '%s' "${COMMENTS:-}" ;;
  *)    exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

run() { # run <comments> [issue_num]
  OUT="$(COMMENTS="$1" ISSUE_NUM="${2-7437}" PATH="$WORK/bin:$PATH" bash "$PROBE" 2>&1)"
  RC=$?
}

expect() { # expect <label> <want_rc> <want_substr>
  local label="$1" want_rc="$2" want_sub="$3"
  if [[ "$RC" != "$want_rc" ]]; then
    fail "$label — wanted rc=$want_rc, got rc=$RC. Output: $OUT"; return
  fi
  if [[ -n "$want_sub" && "$OUT" != *"$want_sub"* ]]; then
    fail "$label — rc correct but output lacks '$want_sub'. Output: $OUT"; return
  fi
  pass "$label (rc=$RC)"
}

echo "cpx22-invoice-reconcile-7431 harness"

# 1. The shape the issue actually asks for: a verdict WITH the figure. A `$`-anchored probe would
#    reject this, and then never close no matter what the operator wrote.
run 'Pulled the PDF.
RESULT: PASS  EUR 13.98 delta, gross == net, no VAT correction needed'
expect "PASS with the required figure closes" 0 "PASS"

# 2. FAIL reopens, and says both ledgers move together — correcting one leaves them disagreeing.
run 'RESULT: FAIL  invoice still shows the cx23 rate for soleur-registry'
expect "FAIL is exit 1" 1 "expenses.md AND cost-model.md"

# 3. No verdict yet. The overwhelmingly common state, and it must never be a pass.
run 'Chased ops@ for the PDF, nothing yet.'
expect "no verdict is TRANSIENT" 2 "no anchored RESULT"

# 4. ANCHORING. Someone quotes the instructions mid-sentence while asking a question. An unanchored
#    grep closes the issue here, on a comment that is literally asking whether it can be closed.
run 'Do I write RESULT: PASS once the invoice lands, or wait for the full month?'
expect "an inline mention of the token does not close the issue" 2 "no anchored RESULT"

# 5. FAIL must win when both appear — a later correction of an earlier premature PASS must not be
#    outvoted by the string it is correcting. Guards the arm ORDER, which is otherwise invisible.
run 'RESULT: PASS  looked right at first glance
RESULT: FAIL  retracting: that was the July invoice, August bills cx23'
expect "FAIL present alongside PASS still fails" 1 "FAIL"

# 6. Cannot self-locate -> TRANSIENT, never a pass. This is the arm that would have fired forever
#    had the probe taken the issue number as $1, since the sweeper passes no arguments.
run 'RESULT: PASS  whatever' ''
expect "unlocatable issue is TRANSIENT" 2 "could not locate"

MIN_CHECKS=6
if (( checks < MIN_CHECKS )); then
  echo "FAIL: only $checks assertions ran, expected >= $MIN_CHECKS" >&2
  fails=$((fails + 1))
fi

echo "cpx22-invoice-reconcile-7431: $((checks - fails))/$checks passed"
(( fails == 0 )) || exit 1
