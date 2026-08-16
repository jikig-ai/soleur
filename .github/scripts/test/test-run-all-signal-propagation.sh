#!/usr/bin/env bash
# Guard 3 (#7429) — `.github/scripts/test/run-all.sh` propagates the SIGNAL SHAPE of a
# terminated fixture suite instead of flattening it into a boolean 1.
#
# PROPERTY. When a fixture suite is terminated by a signal and none failed an assertion, the
# runner exits signal-shaped (128+N), so scripts/test-all.sh's `run_suite` renders `[KILLED]`
# and the top level exits 3 (ADR-177 taxonomy, ADR-187 nested-runner rule).
#
# ASSEMBLY. The rc of EVERY iteration of the `for t in "$DIR"/test-*.sh` loop — captured, not
# discarded. Chokepoints: the loop body and the terminal exit block.
#
# WHY EVERY ARM STAGES >= MIN_SUITES SUITES. run-all.sh carries a `MIN_SUITES` floor (#7068)
# that DOMINATES every other verdict. An arm staging fewer suites than the floor measures the
# floor firing, not the row it claims to test — a vacuous row that passes for the wrong reason.
# Each arm below therefore asserts its staged count against the floor value PARSED OUT OF THE
# RUNNER (never a hardcoded 10), so raising MIN_SUITES cannot silently hollow this suite out.
# M4 is the deliberate inverse: it stages FEWER on purpose and asserts the floor still wins.
#
# WHY M1 USES A REAL SIGNAL. `exit 143` and death by SIGTERM are indistinguishable by `$?` —
# that indistinguishability is the premise of ADR-177 and the reason a fixture asserting the
# propagation must use the real thing. run-all.sh invokes each suite directly (`bash "$t"`),
# with no `xargs` and no shim in between, so the suite's death IS the child death the loop
# observes; here the real signal is load-bearing.
#
# SAFETY. Every fixture signals ITSELF (`kill -TERM $$` inside its own body, followed by a
# `sleep` so there is no async-kill race). This suite never runs `pgrep`, `pkill`, or any
# pattern-matched kill, so it cannot reach a concurrent session's processes on a shared box.
#
# BASH-ONLY (#6454): this file is auto-globbed into `guard-script-fixture-tests`, a REQUIRED
# check with no path filter running on a bare ubuntu-latest with only `actions/checkout`. It
# uses nothing beyond bash + coreutils/grep/sed already on that image — no terraform, no node,
# no python, no apt.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TARGET="$REPO_ROOT/.github/scripts/test/run-all.sh"
TESTALL="$REPO_ROOT/scripts/test-all.sh"
[[ -f "$TARGET" ]]  || { echo "FAIL: $TARGET not found";  exit 1; }
[[ -f "$TESTALL" ]] || { echo "FAIL: $TESTALL not found"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS [$1]"; PASS=$((PASS + 1)); }
fail() { echo "FAIL [$1]: $2" >&2; FAIL=$((FAIL + 1)); }

assert_eq() { # <id> <want> <got>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "want '$2', got '$3'"; fi
}

# Counts FULL LINES matching an ERE. Anchored patterns only — a bare token would also match
# this runner's own explanatory comments, which is how guards in this repo have historically
# passed by matching their own prose.
count_re() { # <ere> <file>
  # `|| n=0` would collapse grep's TWO non-zero exits into one clean answer:
  # rc 1 is "no match" (a legitimate 0) and rc >= 2 is "could not read the file /
  # bad regex" (an error). Six assertions in this suite read a 0 from here as their
  # PASS verdict, so folding rc 2 into 0 makes every negative row report clean
  # having measured nothing — the exact fail-open shape `lint-orphan-test-suites.sh`
  # refuses `|| true` for, a few files over. Abort loudly instead; a counting helper
  # that cannot count must not answer.
  local n=0 rc=0
  n=$(grep -cE -- "$1" "$2") || rc=$?
  if (( rc >= 2 )); then
    printf '[FATAL] count_re: grep exited %s on %s (unreadable file or bad ERE: %s) — refusing to report a count nothing measured\n' \
      "$rc" "$2" "$1" >&2
    exit 2
  fi
  printf '%s\n' "$n"
}

# ---------------------------------------------------------------------------
# Group 0 — the floor value and the classifier, both READ FROM THE SOURCE OF TRUTH.
# ---------------------------------------------------------------------------
MIN_SUITES_REAL=$(grep -m1 -E '^MIN_SUITES=[0-9]+$' "$TARGET" | cut -d= -f2)
if [[ "$MIN_SUITES_REAL" =~ ^[0-9]+$ ]] && (( MIN_SUITES_REAL > 0 )); then
  pass "floor:parsed (MIN_SUITES=$MIN_SUITES_REAL, read from the runner, not hardcoded here)"
else
  fail "floor:parsed" "could not parse '^MIN_SUITES=<n>$' out of $TARGET — every arm below would be unable to prove it cleared the floor"
  echo "ONE OR MORE ASSERTIONS FAILED" >&2
  exit 1
fi
# Every non-floor arm stages one more suite than the floor demands.
STAGE_N=$(( MIN_SUITES_REAL + 1 ))

extract_classifier() { awk '/^suite_exit_class\(\) \{$/,/^\}$/' "$1"; }

# The classifier is inlined into three files (test-all.sh, run-registered-suites.sh,
# run-all.sh) because ADR-177 §A3 measured a shared lib fatal under the single-file `cp`
# sandboxes. Three copies are only safe if something pins them together textually.
assert_eq "parity:one-definition-in-runner"  "1" "$(count_re '^suite_exit_class\(\) \{$' "$TARGET")"
assert_eq "parity:one-definition-in-test-all" "1" "$(count_re '^suite_exit_class\(\) \{$' "$TESTALL")"
CLS_TARGET=$(extract_classifier "$TARGET")
CLS_TESTALL=$(extract_classifier "$TESTALL")
if [[ -n "$CLS_TESTALL" && "$CLS_TARGET" == "$CLS_TESTALL" ]]; then
  pass "parity:classifier-byte-identical-to-test-all"
else
  fail "parity:classifier-byte-identical-to-test-all" "the inlined suite_exit_class in run-all.sh has drifted from scripts/test-all.sh (or one extraction was empty)"
fi

# Load the REAL classifier out of scripts/test-all.sh so the arms below can assert that the rc
# run-all.sh exits with is the one test-all.sh will call `killed` — the half of the end-to-end
# claim this file can execute without rebuilding test-all.sh's sandbox harness. (The
# `^[KILLED]` render + top-level exit 3 half is asserted by AC6's arm in
# scripts/test-all-killed-classification.test.sh, which already owns that harness.)
eval "$CLS_TESTALL"
if [[ "$(type -t suite_exit_class)" == "function" ]]; then
  pass "classifier:loaded-from-test-all"
else
  fail "classifier:loaded-from-test-all" "suite_exit_class did not define; every classification assertion below would be vacuous"
  echo "ONE OR MORE ASSERTIONS FAILED" >&2
  exit 1
fi

# Structural anchors on the loop body. Full-line matches, so a comment mentioning either shape
# cannot satisfy them. These are also the DID-NOT-LAND anchors M3 mutates.
CAPTURE_LINE='  bash "$t" || rc=$?'
assert_eq "shape:rc-captured-exactly-once" "1" "$(grep -cFx -- "$CAPTURE_LINE" "$TARGET")"
assert_eq "shape:no-boolean-if-in-code"    "0" "$(count_re '^[[:space:]]*if ! bash "\$t"' "$TARGET")"
assert_eq "shape:no-literal-exit-3"        "0" "$(count_re '(^|[^0-9])exit[[:space:]]+3([^0-9]|$)' "$TARGET")"

# ---------------------------------------------------------------------------
# Sandbox helpers. Each arm gets its own directory holding a copy of the runner plus the
# fixture suites it stages; run-all.sh resolves $DIR from its own location, so the copy sees
# exactly and only those suites.
# ---------------------------------------------------------------------------
new_arm() { # <name> [runner] -> echoes the arm dir
  local dir="$TMP/$1"
  mkdir -p "$dir"
  cp "${2:-$TARGET}" "$dir/run-all.sh"
  printf '%s\n' "$dir"
}

add_ok()   { printf '#!/usr/bin/env bash\nexit 0\n'                 > "$1/$2"; }
add_bad()  { printf '#!/usr/bin/env bash\nexit 1\n'                 > "$1/$2"; }
# Signals ITSELF, so there is no timing race with an external killer and no dependency on
# anything else running on this host. The trailing `sleep` gives the kernel a window to
# deliver the signal before the script could otherwise fall off its end with rc 0.
add_term() { printf '#!/usr/bin/env bash\nkill -TERM $$\nsleep 5\n' > "$1/$2"; }
add_kill() { printf '#!/usr/bin/env bash\nkill -KILL $$\nsleep 5\n' > "$1/$2"; }

fill_to() { # <dir> <total> — pads with passing suites until <total> test-*.sh exist
  local dir="$1" total="$2" have i
  have=$(find "$dir" -maxdepth 1 -type f -name 'test-*.sh' | wc -l)
  for (( i = have + 1; i <= total; i++ )); do
    add_ok "$dir" "$(printf 'test-ok-%02d.sh' "$i")"
  done
}

suite_count() { find "$1" -maxdepth 1 -type f -name 'test-*.sh' | wc -l; }

# THE ANTI-MASKING ASSERTION. Run for every arm that is not testing the floor itself.
assert_clears_floor() { # <id> <dir>
  local n; n=$(suite_count "$2")
  if (( n >= MIN_SUITES_REAL )); then
    pass "$1:clears-floor ($n staged >= MIN_SUITES=$MIN_SUITES_REAL, so the floor cannot be what this arm measured)"
  else
    fail "$1:clears-floor" "staged only $n suites against MIN_SUITES=$MIN_SUITES_REAL — the floor fires first and MASKS this row"
  fi
}

ARM_RC=0
ARM_OUT=""
run_arm() { # <dir>
  ARM_OUT="$1/output.log"        # not test-*.sh, so it never enters the glob
  ARM_RC=0
  bash "$1/run-all.sh" > "$ARM_OUT" 2>&1 || ARM_RC=$?
}

# ---------------------------------------------------------------------------
# C0 — positive control. Without it, a harness that reddened everything (wrong runner path,
# unwritable temp dir) would score every mutation row as a kill.
# ---------------------------------------------------------------------------
D=$(new_arm c0-control); fill_to "$D" "$STAGE_N"
assert_clears_floor "C0" "$D"
run_arm "$D"
assert_eq "C0:rc-zero"      "0" "$ARM_RC"
assert_eq "C0:pass-banner"  "1" "$(count_re '^ALL FIXTURE TESTS PASS$' "$ARM_OUT")"

# ---------------------------------------------------------------------------
# M1 — one suite dies by a REAL signal, nothing fails. The runner must exit signal-shaped.
# ---------------------------------------------------------------------------
D=$(new_arm m1-real-signal)
add_term "$D" "test-m1-selfterm.sh"
fill_to "$D" "$STAGE_N"
assert_clears_floor "M1" "$D"
run_arm "$D"
assert_eq "M1:rc-is-signal-shaped-143"     "143"    "$ARM_RC"
assert_eq "M1:real-classifier-says-killed" "killed" "$(suite_exit_class "$ARM_RC")"
# Anchored AND counted: exactly one KILLED line, naming the suite, at the start of a line.
assert_eq "M1:killed-line-anchored-and-counted" "1" \
  "$(count_re '^\[KILLED\] test-m1-selfterm\.sh \(exit=143, signal-shaped 128\+15 = SIGTERM\)' "$ARM_OUT")"
assert_eq "M1:no-pass-banner" "0" "$(count_re '^ALL FIXTURE TESTS PASS$' "$ARM_OUT")"
assert_eq "M1:not-reported-as-failure" "0" "$(count_re '^ONE OR MORE FIXTURE TESTS FAILED$' "$ARM_OUT")"

# ---------------------------------------------------------------------------
# M2 — one killed AND one failed. Failure dominates: exit 1, mirroring ADR-177's top-level
# contract. A killed suite must never launder a genuine assertion failure into UNRESOLVED.
# ---------------------------------------------------------------------------
D=$(new_arm m2-killed-and-failed)
add_term "$D" "test-m2-selfterm.sh"
add_bad  "$D" "test-m2-assertfail.sh"
fill_to "$D" "$STAGE_N"
assert_clears_floor "M2" "$D"
run_arm "$D"
assert_eq "M2:failure-dominates-rc-1" "1" "$ARM_RC"
assert_eq "M2:fail-banner"            "1" "$(count_re '^ONE OR MORE FIXTURE TESTS FAILED$' "$ARM_OUT")"
# The kill is still SEEN and said out loud; it is only outranked.
assert_eq "M2:kill-still-reported"    "1" "$(count_re '^\[KILLED\] test-m2-selfterm\.sh ' "$ARM_OUT")"

# ---------------------------------------------------------------------------
# M3 — restore the pre-#7429 boolean body. The M1 assertion must RED against the mutant, or
# M1 was never measuring the capture.
# ---------------------------------------------------------------------------
MUTANT="$TMP/run-all.mutant.sh"
if (( $(grep -cFx -- "$CAPTURE_LINE" "$TARGET") == 1 )); then
  sed 's#^  bash "$t" || rc=$?$#  if ! bash "$t"; then rc=1; else rc=0; fi#' "$TARGET" > "$MUTANT"
  if cmp -s "$TARGET" "$MUTANT"; then
    fail "M3:mutation-landed" "DID-NOT-LAND — the sed matched nothing, so the arm below would score a phantom kill against an UNMUTATED runner"
  else
    pass "M3:mutation-landed"
    D=$(new_arm m3-boolean-revert "$MUTANT")
    add_term "$D" "test-m1-selfterm.sh"
    fill_to "$D" "$STAGE_N"
    assert_clears_floor "M3" "$D"
    run_arm "$D"
    # The mutant flattens 143 into 1: the exact defect #7429 exists to remove.
    assert_eq "M3:mutant-flattens-to-1"   "1" "$ARM_RC"
    assert_eq "M3:mutant-loses-killed-line" "0" \
      "$(count_re '^\[KILLED\] test-m1-selfterm\.sh ' "$ARM_OUT")"
  fi
else
  fail "M3:mutation-landed" "the capture line anchor is not present exactly once in $TARGET"
fi

# ---------------------------------------------------------------------------
# M4 — killed suite present AND RAN < MIN_SUITES. The pre-existing floor must still DOMINATE:
# a short run is a short run, whatever shape one of its members died in.
# ---------------------------------------------------------------------------
D=$(new_arm m4-floor-dominates)
add_term "$D" "test-m4-selfterm.sh"
fill_to "$D" 3
M4_N=$(suite_count "$D")
if (( M4_N < MIN_SUITES_REAL )); then
  pass "M4:below-floor-on-purpose ($M4_N staged < MIN_SUITES=$MIN_SUITES_REAL — this arm is the floor's own row)"
else
  fail "M4:below-floor-on-purpose" "staged $M4_N against MIN_SUITES=$MIN_SUITES_REAL; the floor cannot fire and the row is vacuous"
fi
run_arm "$D"
assert_eq "M4:floor-wins-rc-1" "1" "$ARM_RC"
assert_eq "M4:floor-message"   "1" "$(count_re '^::error::run-all: ran only 3 fixture suite\(s\), expected >= ' "$ARM_OUT")"

# ---------------------------------------------------------------------------
# M5 — two suites killed by DIFFERENT signals. The loop must not stop at the first, and the
# reported rc must follow the runner's stated deterministic rule (lexicographically-first
# killed suite basename, byte-ordered) rather than "the largest", "the last", or "whichever
# the glob happened to reach first". Two mirrored arms: the same pair of signals with the
# names swapped must move the answer, which is what separates the stated rule from an
# accident.
# ---------------------------------------------------------------------------
D=$(new_arm m5a-term-first)
add_term "$D" "test-m5-a.sh"
add_kill "$D" "test-m5-b.sh"
fill_to "$D" "$STAGE_N"
assert_clears_floor "M5a" "$D"
run_arm "$D"
assert_eq "M5a:rc-from-lexicographically-first-killed" "143" "$ARM_RC"
assert_eq "M5a:both-kills-seen" "2" "$(count_re '^\[KILLED\] test-m5-[ab]\.sh ' "$ARM_OUT")"
assert_eq "M5a:selection-named" "1" "$(count_re '^2 FIXTURE SUITE\(S\) TERMINATED SIGNAL-SHAPED, NONE FAILED — exiting 143 \(from test-m5-a\.sh\)$' "$ARM_OUT")"

D=$(new_arm m5b-kill-first)
add_kill "$D" "test-m5-a.sh"
add_term "$D" "test-m5-b.sh"
fill_to "$D" "$STAGE_N"
assert_clears_floor "M5b" "$D"
run_arm "$D"
assert_eq "M5b:rc-from-lexicographically-first-killed" "137" "$ARM_RC"
assert_eq "M5b:both-kills-seen" "2" "$(count_re '^\[KILLED\] test-m5-[ab]\.sh ' "$ARM_OUT")"
assert_eq "M5b:selection-named" "1" "$(count_re '^2 FIXTURE SUITE\(S\) TERMINATED SIGNAL-SHAPED, NONE FAILED — exiting 137 \(from test-m5-a\.sh\)$' "$ARM_OUT")"

# ---------------------------------------------------------------------------
# Summary + anti-vacuity floor on this suite's OWN assertion count.
#
# A FLOOR, not equality: developer-incremented, set a little below a green run so ordinary
# growth does not trip it. Without it, deleting every arm above leaves a file that exits 0
# having asserted nothing — the same silent-and-green shape this suite exists to catch, one
# level up. Mirrors the MIN_SUITES idiom in run-all.sh itself.
# ---------------------------------------------------------------------------
TOTAL=$(( PASS + FAIL ))
echo ""
echo "run-all signal propagation: $PASS passed, $FAIL failed ($TOTAL assertions)"


# POSITIVE CONTROL on the dispatch. Measured at review: rewriting `fail()` to increment PASS
# left this suite fully green (rc 0) while a real regression was live in the SUT. Every
# assertion here is observed THROUGH these two helpers, so nothing above can see them go
# silent -- and an assertion-count floor cannot either, because a rewritten fail() still
# counts. Ported from run-registered-suites.test.sh, the only suite that already had it.
_ctl_p=$PASS; _ctl_f=$FAIL
pass "positive control: pass() increments the pass counter"
fail "positive control: fail() increments the fail counter" "this FAIL line is expected"
if (( PASS == _ctl_p + 1 && FAIL == _ctl_f + 1 )); then
  PASS=$_ctl_p; FAIL=$_ctl_f
  pass "positive control: pass()/fail() both move their own counters"
else
  PASS=$_ctl_p; FAIL=$((_ctl_f + 1))
  echo "FAIL: positive control -- pass()/fail() do NOT move their counters; every verdict in this file is unreliable" >&2
fi

# Floor set to the CURRENT measured count, not below it: slack is deletion budget.
# TOTAL is recomputed HERE, after the positive control above: it was captured before the
# control ran, so the control's own assertions were outside the floor it feeds.
TOTAL=$(( PASS + FAIL ))
MIN_ASSERTIONS=37
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "FAIL: only $TOTAL assertions ran (floor $MIN_ASSERTIONS) — arms were removed or short-circuited" >&2
  exit 1
fi

(( FAIL == 0 )) || exit 1
echo "ALL RUN-ALL PROPAGATION ASSERTIONS PASS"
