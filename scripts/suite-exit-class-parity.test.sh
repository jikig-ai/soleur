#!/usr/bin/env bash
# suite-exit-class-parity.test.sh — the three signal-shape classifiers must agree.
#
# WHY THIS EXISTS (#7429, ADR-187 §"Why the classifier is inlined three times").
#
# Three runners now decide "is this rc signal-shaped?" independently:
#
#   scripts/test-all.sh                            suite_exit_class()        tri-state
#   .github/scripts/test/run-all.sh                suite_exit_class()        tri-state
#   apps/web-platform/infra/run-registered-suites.sh  suite_rc_is_signal_shaped()  boolean
#
# They are duplicated rather than shared because ADR-177 §A3 binds:
# run-registered-suites.test.sh sandboxes its subject with a SINGLE-FILE
# `cp "$SUT" "$PRISTINE"`, so a sourced lib would be absent from the pristine copy,
# the runner's degradation path would fire, and every KILLED assertion in that
# battery would silently exercise the fallback instead of the classifier. A guard
# that certifies the wrong code path is worse than no guard.
#
# Duplication under a pin is the lesser evil — but only while the pin exists. This
# is that pin.
#
# WHY IT IS NOT A BYTE COMPARISON ACROSS ALL THREE. It cannot be, and discovering
# that is the point. The infra runner's call site already counts RED (every
# non-zero child), so it needs a BOOLEAN "is this rc the killed subset?"; the other
# two classify a bare rc into ok/killed/failed and need a TRI-STATE. Forcing one
# shape on both call sites would mean adapter code at one of them, which is a third
# thing to drift. So:
#
#   - byte parity is asserted where the shape IS shared (test-all.sh <-> run-all.sh);
#   - BEHAVIOURAL parity is asserted across all three, over the rc domain.
#
# The behavioural arm is the load-bearing one. It is what catches the change a byte
# comparison structurally cannot see: someone editing one classifier's LOGIC in a
# file whose body was never expected to match the others byte-for-byte.
#
# The domain deliberately includes 193..255. That is the ONLY range where the
# `<= 192` legibility bound present in the tri-state form and absent from the
# boolean form could produce a disagreement. Measured 2026-08-13: it does not
# (for rc 193..255 the `kill -l` operand is 65..127, which kill -l rejects, so the
# non-empty-name guard already excludes them). If a future edit makes that bound
# load-bearing in one form and not the other, this file is what says so.

set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

pass_n=0; fail_n=0
ok()   { pass_n=$((pass_n+1)); echo "[ok] $*"; }
bad()  { fail_n=$((fail_n+1)); echo "[FAIL] $*" >&2; }

TEST_ALL="scripts/test-all.sh"
RUN_ALL=".github/scripts/test/run-all.sh"
INFRA="apps/web-platform/infra/run-registered-suites.sh"

for f in "$TEST_ALL" "$RUN_ALL" "$INFRA"; do
  [[ -f "$f" ]] || { echo "[FATAL] missing subject: $f" >&2; exit 2; }
done

# --- Extraction -------------------------------------------------------------
# Anchored on the function-definition line, never a bare name: all three names
# also appear in comments and in call sites within their own files, so a bare-token
# grep would extract prose. cq-assert-anchor-not-bare-token.
extract() {  # <file> <awk-range-start-regex>
  awk "/$2/,/^\}\$/" "$1"
}

TA_BODY="$(extract "$TEST_ALL" '^suite_exit_class\(\) \{$')"
RA_BODY="$(extract "$RUN_ALL"  '^suite_exit_class\(\) \{$')"
IN_BODY="$(extract "$INFRA"    '^suite_rc_is_signal_shaped\(\) \{$')"

# ANTI-VACUITY FLOOR. If an extraction silently returns empty — a rename, a
# reindent, a shape change — every assertion below would source nothing, the
# functions would be undefined, and a naive suite would report a clean pass over
# zero comparisons. That is the exact failure this file exists to prevent, one
# level up. Fail CLOSED and loudly instead.
MIN_BODY_LINES=5
for pair in "test-all:$TA_BODY" "run-all:$RA_BODY" "infra:$IN_BODY"; do
  label="${pair%%:*}"; body="${pair#*:}"
  n=$(printf '%s\n' "$body" | grep -c . || true)
  if (( n < MIN_BODY_LINES )); then
    bad "extraction floor: '$label' classifier extracted only $n line(s) (< $MIN_BODY_LINES) — the anchor stopped matching; every parity assertion below would be vacuous"
  else
    ok "extraction floor: '$label' classifier extracted ($n lines)"
  fi
done
(( fail_n == 0 )) || { echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ==="; exit 1; }

# --- Byte parity, where the shape is genuinely shared -----------------------
if [[ "$TA_BODY" == "$RA_BODY" ]]; then
  ok "byte parity: run-all.sh suite_exit_class is byte-identical to test-all.sh's"
else
  bad "byte parity: run-all.sh suite_exit_class has DRIFTED from test-all.sh's canonical body"
  diff <(printf '%s\n' "$TA_BODY") <(printf '%s\n' "$RA_BODY") >&2 || true
fi

# --- Behavioural parity across all three ------------------------------------
# Sourced into THIS shell from the extracted text, so what is under test is the
# code as it sits in the runners today — not a copy maintained here, which would
# be a fourth thing to drift.
eval "$TA_BODY"
eval "$(printf '%s\n' "$RA_BODY" | sed '1s/^suite_exit_class()/ra_suite_exit_class()/')"
eval "$IN_BODY"

for fn in suite_exit_class ra_suite_exit_class suite_rc_is_signal_shaped; do
  if declare -F "$fn" >/dev/null 2>&1; then
    ok "loaded: $fn is defined after sourcing"
  else
    bad "loaded: $fn is NOT defined after sourcing — parity rows below cannot run"
  fi
done
(( fail_n == 0 )) || { echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ==="; exit 1; }

# rc domain. 193..255 is load-bearing (see header). The malformed and empty cases
# pin the fail-closed contract. Keep this list append-only.
# 160 and 161 are the load-bearing pair and were MISSING from the first cut of this domain.
# On this shell `kill -l 32` (rc 160) and `kill -l 33` (rc 161) succeed with EMPTY output —
# glibc's internal SIGCANCEL/SIGSETXID — so the `[[ -n "$name" ]]` guard is the ONLY thing
# rejecting them, natively, with no synthesized shell required. test-all.sh's own classifier
# comment already documented 160 for exactly this reason; the domain here simply skipped it,
# so the permissive-kill arm below was reaching for a property this shell exhibits two values
# away. Measured: without these rows, mutating the infra guard to `return 0` produced ZERO
# in-domain disagreements. Found by structural enumeration at review.
RC_DOMAIN=(0 1 2 3 124 128 129 130 137 143 154 159 160 161 192 193 200 254 255 abc "")
MIN_RC_CASES=17
if (( ${#RC_DOMAIN[@]} < MIN_RC_CASES )); then
  bad "rc-domain floor: ${#RC_DOMAIN[@]} cases (< $MIN_RC_CASES) — the domain was narrowed"
else
  ok "rc-domain floor: ${#RC_DOMAIN[@]} cases"
fi

compared=0
for rc in "${RC_DOMAIN[@]}"; do
  ta=$(suite_exit_class "$rc");    [[ "$ta" == killed ]] && ta=1 || ta=0
  ra=$(ra_suite_exit_class "$rc"); [[ "$ra" == killed ]] && ra=1 || ra=0
  if suite_rc_is_signal_shaped "$rc"; then inf=1; else inf=0; fi
  compared=$((compared+1))
  if [[ "$ta" == "$ra" && "$ta" == "$inf" ]]; then
    ok "parity rc=[$rc]: all three agree (killed=$ta)"
  else
    bad "parity rc=[$rc]: DISAGREE — test-all=$ta run-all=$ra infra=$inf"
  fi
done

# --- The defensive name-guard, under the only shell that makes it decide -----
#
# WHY THIS ARM EXISTS. Mutating `[[ -n "$name" ]]` out of the infra predicate (and
# the equivalent guard out of the tri-state form) SURVIVES every row above. That is
# not a fixture oversight in the rows — it is a fact about this shell: measured
# 2026-08-13, `kill -l 65` exits **1** with empty output, so the preceding
# `|| return 1` / `|| name=""` already catches every rc the name-guard would decide.
# On bash 5.2 / this coreutils the guard is unreachable-as-decider.
#
# It is still correct to KEEP it: POSIX does not require that exit status, and a
# shell returning 0-with-empty-output would make the guard the only thing standing
# between rc 193..255 and a bogus `killed`. So rather than record a survivor and
# move on, this arm SYNTHESIZES that shell — `kill` is a builtin, and the
# classifiers were eval'd into this shell, so shadowing it as a function puts the
# guard back on the decision path.
#
# Without this arm the guard is untested in both files and could be deleted from
# either with every suite green. cq-test-fixtures-synthesized-only: the shell is
# synthesized, not captured.
_parity_name_guard_arm() {
  # Shadow `kill` so an out-of-range operand returns 0 with EMPTY output — the
  # permissive shell. `kill -<sig> <pid>` (non `-l`) must still reach the builtin,
  # or anything else in scope that signals would silently no-op.
  kill() {
    if [[ "${1-}" == "-l" ]]; then
      case "${2-}" in
        ''|*[!0-9]*) builtin kill "$@"; return $?;;
        *) if (( $2 >= 1 && $2 <= 64 )); then builtin kill "$@"; return $?
           else printf '\n'; return 0; fi;;
      esac
    fi
    builtin kill "$@"
  }
  local rc examined=0
  for rc in 193 200 255; do
    examined=$((examined+1))
    local ta ra inf
    ta=$(suite_exit_class "$rc");    [[ "$ta" == killed ]] && ta=1 || ta=0
    ra=$(ra_suite_exit_class "$rc"); [[ "$ra" == killed ]] && ra=1 || ra=0
    if suite_rc_is_signal_shaped "$rc"; then inf=1; else inf=0; fi
    if [[ "$ta" == 0 && "$ra" == 0 && "$inf" == 0 ]]; then
      ok "name-guard (permissive-kill shell) rc=[$rc]: all three still reject"
    else
      bad "name-guard (permissive-kill shell) rc=[$rc]: a bogus signal name was accepted — test-all=$ta run-all=$ra infra=$inf"
    fi
  done
  # Fixture self-check: if the shadow did not take effect the three rows above
  # would pass for the ORDINARY reason and prove nothing.
  local probe; probe=$(kill -l 65 2>/dev/null); local prc=$?
  if (( prc == 0 )) && [[ -z "$probe" ]]; then
    ok "name-guard fixture self-check: the permissive-kill shadow is in effect"
  else
    bad "name-guard fixture self-check: shadow NOT in effect (kill -l 65 rc=$prc out=[$probe]) — the three rows above were vacuous"
  fi
  (( examined == 3 )) || bad "name-guard arm: examined $examined of 3"
  # bash function definitions are GLOBAL regardless of nesting, so without this the
  # permissive-kill shadow survives the arm's return for the rest of the process and any
  # arm appended below would silently run against a synthesized shell — passing for the
  # wrong reason. Latent today (nothing follows), live the moment someone appends.
  unset -f kill
}
_parity_name_guard_arm
# Fixture teardown must actually have happened: a shadow that outlived the arm would make
# every later assertion in this file suspect, so prove the real builtin is back.
if [[ "$(kill -l 65 2>/dev/null; echo "rc=$?")" == "rc=1" ]]; then
  ok "name-guard teardown: the real kill builtin is restored (shadow did not leak)"
else
  bad "name-guard teardown: the permissive-kill shadow LEAKED past its arm — assertions below it may pass for the wrong reason"
fi

# Loop-accounting floor. A `pass()`-counting floor cannot see a loop whose body
# never executed: a gutted loop still leaves the earlier ok() calls counted. So
# reconcile what the loop EXAMINED against the domain it was handed.
if (( compared == ${#RC_DOMAIN[@]} )); then
  ok "loop accounting: compared $compared of ${#RC_DOMAIN[@]} rc values"
else
  bad "loop accounting: compared $compared but the domain holds ${#RC_DOMAIN[@]} — the comparison loop did not run over its input"
fi

echo ""
echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ==="
(( fail_n == 0 ))
