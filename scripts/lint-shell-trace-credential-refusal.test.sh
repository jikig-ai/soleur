#!/usr/bin/env bash
# Suite for scripts/lint-shell-trace-credential-refusal.py (#7797).
#
# The lint enforces two rules on every tracked shell script that BINDS a live
# credential:
#   Rule A (prologue)  -- the xtrace refusal appears before any command other
#                         than set/shopt.
#   Rule B (below)     -- no trace-enabling token appears after the preamble.
#
# WHY THE MATRIX IS WRITTEN AGAINST A PRISTINE COPY. A battery that restores via
# `git checkout --` restores to HEAD, which is a different thing from "what I had
# a moment ago" while a fix is in flight -- rows then score the defect against
# itself. Every row here copies the lint to a sandbox, mutates the COPY, asserts
# the mutation LANDED (a mutation that silently fails to apply reports the
# baseline, which is indistinguishable from a pass), and runs the copy.
set -uo pipefail

# Direct invocation inherits the bare /tmp (a machine-global 4 GiB tmpfs shared
# by parallel worktrees); test-all.sh sets /var/tmp. Default it here so this
# suite's verdicts are not a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LINT="$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.py"
FIXSRC="$REPO_ROOT/scripts/fixtures/shell-trace-refusal"

WORK="$(mktemp -d -t shell-trace-refusal.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# Lint the fixtures from a copy OUTSIDE the repo. The lint excludes any path
# under a `fixtures/` directory from its repo walk (so the corpus never lands in
# the baseline), which would otherwise make every violation fixture read as
# out-of-scope and score this whole suite vacuously green. Copying also makes
# the suite independent of where the corpus lives. `.test.sh` stays exercised
# for real because it is a FILENAME pattern, which travels with the copy.
FIX="$WORK/fx"
mkdir -p "$FIX" || { printf '[FATAL] mkdir failed\n' >&2; exit 2; }
cp "$FIXSRC"/. -r "$FIX"/ 2>/dev/null || cp -r "$FIXSRC"/* "$FIX"/ || {
  printf '[FATAL] fixture copy failed -- a harness that cannot set up must abort, not continue\n' >&2
  exit 2
}

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

# --- POSITIVE CONTROL (ADR-193) ----------------------------------------------
# Drive both helpers once each and refuse to continue unless BOTH counters move.
# Reported with printf + exit 1 directly, never through the helpers it backstops
# -- a floor that routes through the suspect cannot witness the suspect.
_p=$PASS
_f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS - _p)) -ne 1 ] || [ $((FAIL - _f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2
  exit 1
fi
PASS=$_p
FAIL=$_f

if [ ! -f "$LINT" ]; then
  printf '[FATAL] lint not found at %s (RED phase: this is expected before GREEN)\n' "$LINT" >&2
  exit 1
fi

# --- helpers -----------------------------------------------------------------
# rc_of <lint-path> <target...> -> echoes the exit code. Never pipes into
# grep -q (a producer feeding grep -q takes SIGPIPE under pipefail and the
# guard fails OPEN on every negative assertion).
rc_of() {
  local lint="$1"
  shift
  python3 "$lint" "$@" >"$WORK/out" 2>"$WORK/err"
  printf '%s' "$?"
}

PROBE_TOKEN="FAKE_notarealtoken_0000000000"

reports() { # reports <basename> -> 0 if the last run named that file
  grep -q -- "$1" "$WORK/out" "$WORK/err"
}

# --- Rule A / scope: the baseline verdicts ------------------------------------
rc="$(rc_of "$LINT" "$FIX/violation-no-preamble.sh")"
[ "$rc" = "1" ] && pass "no-preamble + credential bind is reported (rc=1)" \
  || fail "no-preamble should report rc=1, got rc=$rc"

rc="$(rc_of "$LINT" "$FIX/compliant-canonical.sh")"
[ "$rc" = "0" ] && pass "canonical compliant passes (rc=0)" \
  || fail "canonical compliant should pass, got rc=$rc"

# H3 must-PASS, NON-canonical: differs in comment text and bind style. Proves
# the lint matches SHAPE, not a fixed string -- a suite whose only must-PASS is
# the canonical fixture cannot detect a matcher that rejects everything else.
rc="$(rc_of "$LINT" "$FIX/compliant-noncanonical.sh")"
[ "$rc" = "0" ] && pass "H3 non-canonical compliant passes (rc=0)" \
  || fail "H3 non-canonical compliant should pass, got rc=$rc"

rc="$(rc_of "$LINT" "$FIX/outofscope-no-credential.sh")"
[ "$rc" = "0" ] && pass "credential-free script is out of scope (stays traceable)" \
  || fail "credential-free script should be out of scope, got rc=$rc"

# The class the review CUT: `doppler run --` binds nothing in the PARENT.
rc="$(rc_of "$LINT" "$FIX/outofscope-doppler-run-only.sh")"
[ "$rc" = "0" ] && pass "doppler-run-only is out of scope (secret enters the CHILD)" \
  || fail "doppler-run-only should be out of scope, got rc=$rc"

# --- Rule A: ORDER. The property is about a WINDOW, so a delete-only battery
#     would certify it untested. This case observes INSIDE the window. --------
rc="$(rc_of "$LINT" "$FIX/violation-preamble-not-prologue.sh")"
[ "$rc" = "1" ] && pass "preamble present but NOT in the prologue is reported" \
  || fail "non-prologue preamble should report rc=1, got rc=$rc"

# --- Rule B: the point-in-time gap Rule A cannot close -----------------------
rc="$(rc_of "$LINT" "$FIX/violation-trace-below-preamble.sh")"
[ "$rc" = "1" ] && pass "Rule B: 'set -x' below a compliant preamble is reported" \
  || fail "Rule B set -x below preamble should report rc=1, got rc=$rc"

rc="$(rc_of "$LINT" "$FIX/violation-xtrace-spelling-below.sh")"
[ "$rc" = "1" ] && pass "Rule B: 'set -o xtrace' spelling below preamble is reported" \
  || fail "Rule B xtrace spelling should report rc=1, got rc=$rc"

# --- SECRET_SIGNALS: one fixture per class, ALONE ----------------------------
for c in doppler-get capture gh-auth; do
  rc="$(rc_of "$LINT" "$FIX/violation-signal-$c.sh")"
  [ "$rc" = "1" ] && pass "signal class '$c' alone brings a file into scope" \
    || fail "signal class '$c' should bring the file into scope, got rc=$rc"
done

# --- Fail-closed: unparseable input exits EXACTLY 2 (not merely non-zero) ----
rc="$(rc_of "$LINT" "$FIX/malformed-not-utf8.sh")"
[ "$rc" = "2" ] && pass "unparseable input exits exactly 2 (fail-closed, distinguishable from a violation)" \
  || fail "unparseable input must exit exactly 2, got rc=$rc"

# --- H4 must-PASS: an EXCLUDED *.test.sh is not reported ---------------------
cp "$FIX/excluded-suite.test.sh.fixture" "$WORK/excluded-suite.test.sh"
rc="$(rc_of "$LINT" "$WORK/excluded-suite.test.sh")"
[ "$rc" = "0" ] && pass "H4 excluded *.test.sh with a synthesized token is not reported" \
  || fail "H4 excluded *.test.sh should not be reported, got rc=$rc"

# --- The violation message must be actionable --------------------------------
rc_of "$LINT" "$FIX/violation-no-preamble.sh" >/dev/null
if reports 'violation-no-preamble.sh'; then
  pass "violation output names the offending file"
else
  fail "violation output must name the offending file"
fi
if grep -q 'case "\$-"' "$WORK/out" "$WORK/err"; then
  pass "violation output emits paste-ready preamble text"
else
  fail "violation output must emit paste-ready preamble text (a guard that fails without saying how to satisfy it is a dead end)"
fi

# --- The emitted remedy must itself PASS the lint -----------------------------
# This is what keeps the message from rotting: if the text the lint tells you to
# paste does not satisfy the lint, the developer journey dead-ends.
python3 "$LINT" "$FIX/violation-no-preamble.sh" >"$WORK/msg" 2>&1
if python3 - "$WORK/msg" "$WORK/remedy.sh" <<'PY'
import re, sys
msg = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'(case "\$-" in.*?\besac)', msg, re.S)
if not m:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(
    "#!/usr/bin/env bash\nset -uo pipefail\n\n"
    + m.group(1)
    + '\n\ncurl -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" https://example.invalid/ || true\n'
)
PY
then
  rc="$(rc_of "$LINT" "$WORK/remedy.sh")"
  [ "$rc" = "0" ] && pass "the emitted remedy text itself passes the lint (message cannot rot)" \
    || fail "the emitted remedy text does NOT pass the lint (rc=$rc) -- following the message leaves you red"

  # LINT-COMPLIANT IS NOT LEAK-SAFE. The remedy is the text every remediating
  # author pastes, so reverting its `:+x` to `:-` reintroduces the PR's own
  # headline defect into the canonical source while staying lint-clean. The
  # leak probe previously ran on ONE fixture and never on this.
  n="$(SENTRY_AUTH_TOKEN="$PROBE_TOKEN" bash -x "$WORK/remedy.sh" 2>&1 | grep -c "$PROBE_TOKEN")"
  [ "$n" = "0" ] && pass "the emitted remedy text is LEAK-SAFE under bash -x (0 trace lines)" \
    || fail "the emitted remedy LEAKS in $n line(s) -- the text 131 scripts are told to paste expands the value"
else
  fail "could not extract a paste-ready preamble from the violation message"
fi

# --- FUNCTIONAL: the preamble must not LEAK while refusing --------------------
# The lint checks that a refusal is PRESENT; nothing above checks what the
# refusal does at runtime. That gap shipped a real defect during this PR: the
# first draft guarded with `[ -n "${VAR:-}" ]`, which expands the value, so
# xtrace printed `+ '[' -n <TOKEN> ']'` -- the preamble reintroduced, in
# miniature, the exact leak it exists to prevent. `${VAR:+x}` is the same
# predicate without ever placing the value on a command line.
#
# Assert the value that must NEVER appear, over both arms.
leak_probe() { # <script> -> number of trace lines containing the token
  SENTRY_AUTH_TOKEN="$PROBE_TOKEN" bash -x "$1" 2>&1 | grep -c "$PROBE_TOKEN"
}

n="$(leak_probe "$FIX/compliant-canonical.sh")"
[ "$n" = "0" ] && pass "refusal leaks NO token value under bash -x (0 trace lines)" \
  || fail "refusal LEAKED the token value in $n trace line(s) -- the guard expands the value it protects"

SENTRY_AUTH_TOKEN="$PROBE_TOKEN" bash -x "$FIX/compliant-canonical.sh" >/dev/null 2>&1
rc=$?
[ "$rc" = "78" ] && pass "refusal exits 78 (EX_CONFIG) -- not 64, which is EX_USAGE at 57 sites" \
  || fail "refusal should exit 78, got $rc"

env -u SENTRY_AUTH_TOKEN bash -x "$FIX/compliant-canonical.sh" >/dev/null 2>&1
rc=$?
[ "$rc" != "78" ] && pass "escape hatch: tracing is allowed when the credential is unset" \
  || fail "escape hatch closed -- a guard that blocks a state you must recover from is a P1"

# The leaky form must be DETECTABLE, or the assertion above is unfalsifiable.
cp "$FIX/compliant-canonical.sh" "$WORK/leaky.sh"
perl -0pi -e 's/\$\{([A-Z_]+):\+x\}/\${$1:-}/' "$WORK/leaky.sh"
if diff -q "$FIX/compliant-canonical.sh" "$WORK/leaky.sh" >/dev/null 2>&1; then
  fail "M7 leaky-guard mutation did NOT land"
else
  n="$(leak_probe "$WORK/leaky.sh")"
  [ "$n" -gt 0 ] && pass "M7 reverting to the value-expanding guard LEAKS ($n line(s)) -- the no-leak assertion is falsifiable" \
    || fail "M7 leaky guard leaked nothing -- the no-leak assertion cannot fail and proves nothing"
fi

# --- MUTATION MATRIX ---------------------------------------------------------
# Every row: copy to a sandbox, assert the mutation LANDED, then assert the
# mutant's verdict changed on ITS OWN fixture. Each row names the fixture it
# reddens -- a row scored against a fixture that does not exercise its class is
# a row that cannot fail.
mutate_row() { # <label> <perl-expr> <fixture> <baseline-rc> <expected-mutant-rc>
  local label="$1" expr="$2" fx="$3" want_base="$4" want_mut="$5"
  local sandbox="$WORK/mut.py" base mut
  cp "$LINT" "$sandbox" || { fail "$label: sandbox copy failed"; return; }

  base="$(rc_of "$LINT" "$fx")"
  if [ "$base" != "$want_base" ]; then
    fail "$label: BASELINE is rc=$base, expected rc=$want_base -- a red baseline voids the row"
    return
  fi

  perl -0pi -e "$expr" "$sandbox"
  if diff -q "$LINT" "$sandbox" >/dev/null 2>&1; then
    fail "$label: mutation did NOT land -- the row scores the BASELINE, which is indistinguishable from a pass"
    return
  fi

  mut="$(rc_of "$sandbox" "$fx")"
  if [ "$mut" = "$want_mut" ]; then
    pass "$label: mutant verdict moved $want_base -> $mut"
  else
    fail "$label: mutant verdict is rc=$mut, expected rc=$want_mut -- SURVIVING. Decide which: fixture-inadequate, or equivalent (prove no verdict changes and record it)"
  fi
}

# Own dispatch first: a lint that resolves nothing and exits 0 is the vacuity
# every other row is structurally blind to.
# Expected mutant rc is 2, not 0: the zero-target guard added after review turns
# "the walker resolved nothing" into an explicit refusal rather than a silent
# clean report. A row expecting 0 here would now fail for the RIGHT reason.
mutate_row 'M5 own-dispatch: walker yields nothing' \
  's|(def targets_from_args[^\n]*\n)|$1    return []\n|s' \
  "$FIX/violation-no-preamble.sh" 1 2

mutate_row 'M1 SECRET_SIGNALS: doppler-get class removed' \
  's/SIGNAL_DOPPLER_GET = r"[^"]*"/SIGNAL_DOPPLER_GET = r"__NEVER_MATCHES__"/' \
  "$FIX/violation-signal-doppler-get.sh" 1 0

mutate_row 'M2 Rule A: preamble accepted anywhere in the file' \
  's/PROLOGUE_MAX_CMDS = \d+/PROLOGUE_MAX_CMDS = 100000/' \
  "$FIX/violation-preamble-not-prologue.sh" 1 0

mutate_row 'M3 Rule B: xtrace spelling dropped from TRACE_TOKENS' \
  's/TRACE_XTRACE_LONG = r"[^"]*"/TRACE_XTRACE_LONG = r"__NEVER_MATCHES__"/' \
  "$FIX/violation-xtrace-spelling-below.sh" 1 0

mutate_row 'M4 Rule B skipped entirely' \
  's/violations \+= check_rule_b\(/violations += [] and check_rule_b(/' \
  "$FIX/violation-trace-below-preamble.sh" 1 0

# M6 needs its own expected pair: the fail-closed arm moves 2 -> 0, and NEITHER
# value is 1. A generic "mutant is not 1" predicate would score this row green
# while the fail-closed arm was fully disarmed.
mutate_row 'M6 fail-closed: unparseable treated as clean' \
  's/return 2, \[\]  # unparseable/return 0, []  # unparseable/' \
  "$FIX/malformed-not-utf8.sh" 2 0

# --- H1: the floor must fail via a DIRECT exit, not through the helpers -------
# H1: assert the floor by DRIVING it, not by grepping for its name -- the old
# check searched for a literal its own grep line contains, so deleting the floor
# block entirely left it passing. An outside witness is the only real test.
_h1="$WORK/h1.sh"
sed 's/^MIN_ASSERTIONS=[0-9]*$/MIN_ASSERTIONS=99999/' "${BASH_SOURCE[0]}" > "$_h1"
if [ -s "$_h1" ] && ! diff -q "$_h1" "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
  ( cd "$REPO_ROOT/scripts" && cp "$_h1" .h1probe.tmp.sh && bash .h1probe.tmp.sh >/dev/null 2>&1 )
  _h1rc=$?
  rm -f "$REPO_ROOT/scripts/.h1probe.tmp.sh"
  [ "$_h1rc" = "1" ] && pass "H1 the assertion floor actually bites (unreachable floor -> exit 1)" \
    || fail "H1 floor did not bite: raising it to 99999 exited $_h1rc, expected 1"
else
  fail "H1 could not build the floor probe -- the assertion would be vacuous"
fi

# --- verdict -----------------------------------------------------------------
printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"

# Absolute floor, recorded from a MEASURED green run (never from expectation --
# that was wrong three times in sibling PR #7806). Reported with printf + exit 1
# directly, never via fail(), so one edit cannot disarm both.
MIN_ASSERTIONS=28
if [ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' \
    "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[ "$FAIL" -eq 0 ] || exit 1
