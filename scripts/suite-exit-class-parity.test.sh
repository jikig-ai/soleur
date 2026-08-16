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
# They are duplicated rather than shared because ADR-177 §A3 binds — and for the
# reason ADR-187 records after review, not the one first written here:
# run-registered-suites.test.sh drives a python SINGLE-FILE mutator over its
# `cp "$SUT" "$PRISTINE"` copy, so the two rows that mutate the classifier BODY
# (drop-rc128-guard, drop-name-guard) could not be applied AT ALL if it lived in
# scripts/lib/. The originally-stated reason — "a sourced lib would be absent from
# the copy" — does not follow: the runner cd's to $ROOT first, so a $ROOT-anchored
# source resolves fine from the sandbox.
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
# `cases` is incremented at the CALL SITE — immediately before each block that resolves to
# exactly one verdict — and NEVER inside ok()/bad(). That placement is the whole substance of
# the conservation check at the bottom of this file, and it is also why the assertion floor
# below reads `cases` rather than `pass_n + fail_n`: a counter derived from the two verdict
# counters moves WITH the verdict, so stubbing `bad() { :; }` drops the row and its count
# together — the floor then fires with the WRONG diagnosis ("an arm was deleted") or, once the
# margin is wide enough, does not fire at all.
#
# Never increment inside `$( )` — a subshell discards it.
cases=0
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
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never through bad(). A floor that reports by
# calling bad() increments the same counter the exit status reads, so neutering bad() silences
# the rows AND the floor that exists to notice the silence. A floor enforced through the
# suspect cannot witness the suspect.
MIN_BODY_LINES=5
for pair in "test-all:$TA_BODY" "run-all:$RA_BODY" "infra:$IN_BODY"; do
  label="${pair%%:*}"; body="${pair#*:}"
  n=$(printf '%s\n' "$body" | grep -c . || true)
  cases=$((cases+1))
  if (( n < MIN_BODY_LINES )); then
    printf '\n[FATAL] anti-vacuity floor: only %d line(s) extracted for the %s classifier, expected >= %d — the anchor stopped matching; every parity assertion below would be vacuous.\n' \
      "$n" "$label" "$MIN_BODY_LINES" >&2
    echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ==="
    exit 1
  else
    ok "extraction floor: '$label' classifier extracted ($n lines)"
  fi
done
(( fail_n == 0 )) || { echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ==="; exit 1; }

# --- Byte parity, where the shape is genuinely shared -----------------------
cases=$((cases+1))
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
  cases=$((cases+1))
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
#
# Reported directly for the same reason as the extraction floor above: a narrowed domain makes
# every parity row below vacuous, and a floor routed through bad() is silenced by exactly the
# fault it exists to notice.
cases=$((cases+1))
MIN_RC_CASES=17
if (( ${#RC_DOMAIN[@]} < MIN_RC_CASES )); then
  printf '\n[FATAL] anti-vacuity floor: only %d rc case(s) in the domain, expected >= %d — the domain was narrowed and every parity row below is vacuous.\n' \
    "${#RC_DOMAIN[@]}" "$MIN_RC_CASES" >&2
  echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ==="
  exit 1
else
  ok "rc-domain floor: ${#RC_DOMAIN[@]} cases"
fi

# EXPECTED VALUES, not just agreement. Measured at review: collapsing ALL THREE classifiers
# to "never signal-shaped" passed this suite 35/0, because every row asked only whether they
# agreed and they agreed on `killed=0` for everything. Agreement is a tautology in the accept
# direction unless something says what the answer must BE. `\1` = must classify killed,
# `0` = must not. Derived from the taxonomy, not from any classifier's output.
declare -A RC_EXPECT=(
  [0]=0 [1]=0 [2]=0 [3]=0 [124]=0        # 124 is GNU timeout's own attributed verdict
  [128]=0                                 # kill -l 0 yields EXIT; rc>128 is what excludes it
  [129]=1 [130]=1 [137]=1 [143]=1 [154]=1 [159]=1 [192]=1
  [160]=0 [161]=0                         # kill -l 32/33: rc 0 with EMPTY name -> the -n guard
  [193]=0 [200]=0 [254]=0 [255]=0         # kill -l 65..127 fails -> rejected earlier
)
compared=0
expected_checked=0
for rc in "${RC_DOMAIN[@]}"; do
  ta=$(suite_exit_class "$rc");    [[ "$ta" == killed ]] && ta=1 || ta=0
  ra=$(ra_suite_exit_class "$rc"); [[ "$ra" == killed ]] && ra=1 || ra=0
  if suite_rc_is_signal_shaped "$rc"; then inf=1; else inf=0; fi
  compared=$((compared+1))
  cases=$((cases+1))
  if [[ "$ta" == "$ra" && "$ta" == "$inf" ]]; then
    ok "parity rc=[$rc]: all three agree (killed=$ta)"
  else
    bad "parity rc=[$rc]: DISAGREE — test-all=$ta run-all=$ra infra=$inf"
  fi
  # The absolute half. Only numeric rows have an expectation; `abc`/"" are the
  # fail-closed shapes and are pinned by agreement alone.
  # `[[ -n "${A[$k]+set}" ]]` errors on an EMPTY subscript, and "" is deliberately in the
  # domain as a fail-closed shape — so gate on numeric-ness first.
  if [[ "$rc" =~ ^[0-9]+$ ]] && [[ -n "${RC_EXPECT[$rc]+set}" ]]; then
    expected_checked=$((expected_checked+1))
    cases=$((cases+1))
    if [[ "$ta" == "${RC_EXPECT[$rc]}" ]]; then
      ok "expected rc=[$rc]: classified killed=${RC_EXPECT[$rc]} as required"
    else
      bad "expected rc=[$rc]: classified killed=$ta, taxonomy requires ${RC_EXPECT[$rc]} — all three may agree and all three be wrong"
    fi
  fi
done
cases=$((cases+1))
if (( expected_checked == ${#RC_EXPECT[@]} )); then
  ok "expected-value accounting: checked all ${expected_checked} pinned rc values"
else
  bad "expected-value accounting: checked ${expected_checked} of ${#RC_EXPECT[@]} pinned values — RC_DOMAIN and RC_EXPECT have drifted apart"
fi

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
    cases=$((cases+1))
    if [[ "$ta" == 0 && "$ra" == 0 && "$inf" == 0 ]]; then
      ok "name-guard (permissive-kill shell) rc=[$rc]: all three still reject"
    else
      bad "name-guard (permissive-kill shell) rc=[$rc]: a bogus signal name was accepted — test-all=$ta run-all=$ra infra=$inf"
    fi
  done
  # Fixture self-check: if the shadow did not take effect the three rows above
  # would pass for the ORDINARY reason and prove nothing.
  local probe; probe=$(kill -l 65 2>/dev/null); local prc=$?
  cases=$((cases+1))
  if (( prc == 0 )) && [[ -z "$probe" ]]; then
    ok "name-guard fixture self-check: the permissive-kill shadow is in effect"
  else
    bad "name-guard fixture self-check: shadow NOT in effect (kill -l 65 rc=$prc out=[$probe]) — the three rows above were vacuous"
  fi
  # Written as a full if/else rather than `(( … )) || bad …`: a bare `||` records a verdict
  # ONLY on the failing side, so the row is counted by no counter at all on the passing side
  # and the conservation check below would read it as a missing verdict.
  cases=$((cases+1))
  if (( examined == 3 )); then
    ok "name-guard arm: examined all 3 rc values"
  else
    bad "name-guard arm: examined $examined of 3"
  fi
  # bash function definitions are GLOBAL regardless of nesting, so without this the
  # permissive-kill shadow survives the arm's return for the rest of the process and any
  # arm appended below would silently run against a synthesized shell — passing for the
  # wrong reason. Latent today (nothing follows), live the moment someone appends.
  unset -f kill
}
_parity_name_guard_arm
# Fixture teardown must actually have happened: a shadow that outlived the arm would make
# every later assertion in this file suspect, so prove the real builtin is back.
cases=$((cases+1))
if [[ "$(kill -l 65 2>/dev/null; echo "rc=$?")" == "rc=1" ]]; then
  ok "name-guard teardown: the real kill builtin is restored (shadow did not leak)"
else
  bad "name-guard teardown: the permissive-kill shadow LEAKED past its arm — assertions below it may pass for the wrong reason"
fi

# Loop-accounting floor. A `pass()`-counting floor cannot see a loop whose body
# never executed: a gutted loop still leaves the earlier ok() calls counted. So
# reconcile what the loop EXAMINED against the domain it was handed.
cases=$((cases+1))
if (( compared == ${#RC_DOMAIN[@]} )); then
  ok "loop accounting: compared $compared of ${#RC_DOMAIN[@]} rc values"
else
  bad "loop accounting: compared $compared but the domain holds ${#RC_DOMAIN[@]} — the comparison loop did not run over its input"
fi

# POSITIVE CONTROL on the dispatch itself. Measured at review: rewriting `bad()` to increment
# pass_n left this suite 35/0 and rc 0 while a real classifier drift was live. Nothing above can
# see that — every assertion is observed THROUGH these two helpers. Ported from
# run-registered-suites.test.sh, the only suite in this PR that already had it.
#
# `cases` is rolled back alongside pass_n/fail_n so the two deliberate helper calls below do not
# unbalance the conservation identity: net effect on a healthy run is exactly one recorded
# verdict and exactly one counted case.
_ctl_p=$pass_n; _ctl_f=$fail_n; _ctl_c=$cases
cases=$((cases+1))
ok "positive control: ok() increments the pass counter"
cases=$((cases+1))
bad "positive control: bad() increments the fail counter (this FAIL line is expected)"
if (( pass_n == _ctl_p + 1 && fail_n == _ctl_f + 1 )); then
  pass_n=$_ctl_p; fail_n=$_ctl_f; cases=$_ctl_c
  cases=$((cases+1))
  ok "positive control: ok()/bad() both move their own counters"
else
  pass_n=$_ctl_p; fail_n=$((_ctl_f + 1)); cases=$((_ctl_c + 1))
  printf '\n[FATAL] positive control: ok()/bad() do NOT move their counters — every verdict in this file is unreliable.\n' >&2
  echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ==="
  exit 1
fi

# --- Anti-vacuity floor -----------------------------------------------------------------------
# Deleting a whole arm dropped this suite 35 -> 31 and still exited 0.
#
# Two changes from the shape that let that through. First it is reported with `printf >&2` +
# `exit 1` DIRECTLY: the previous form did `fail_n=$((fail_n + 1))`, and `fail_n` is exactly
# what the exit status reads, so neutering the verdict machinery silenced the rows AND the floor
# meant to notice the silence. Second it counts `cases` — incremented at the call site — rather
# than `pass_n + fail_n`, which is derived from the verdict counters and therefore collapses
# with them under the same fault, making the floor blame a deleted arm for a discarded verdict.
#
# Measured from a green run with ZERO slack: 57 assertions. Ratchet upward only.
MIN_PARITY_ASSERTIONS=57
if (( cases < MIN_PARITY_ASSERTIONS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d — an arm was deleted.\n' \
    "$cases" "$MIN_PARITY_ASSERTIONS" >&2
  echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ($cases assertions) ==="
  exit 1
fi

# --- Accounting conservation --------------------------------------------------------------
# The arm that actually catches a neutered verdict helper. The floor above catches "no
# assertions RAN"; it cannot catch "assertions ran and their verdicts were discarded", because
# `cases` keeps its full value when bad() is a no-op. Every assertion records exactly one
# verdict, so pass_n+fail_n MUST equal cases. Reported directly for the same reason as the floor.
if (( pass_n + fail_n != cases )); then
  printf '\n[FATAL] accounting: pass_n+fail_n (%d) != cases (%d).\n' "$((pass_n + fail_n))" "$cases" >&2
  if (( pass_n + fail_n < cases )); then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered ok()/bad() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases+1))` before it. This is a harness bug, not a parity failure: add the increment at that call site.\n' >&2
  fi
  echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ($cases assertions) ==="
  exit 1
fi

echo ""
echo "=== suite-exit-class parity: $pass_n passed, $fail_n failed ($cases assertions) ==="
(( fail_n == 0 ))
