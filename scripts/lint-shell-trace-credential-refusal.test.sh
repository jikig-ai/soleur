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

# One Rule E finding per offending call site, always starting with this phrase.
# Rows COUNT these messages: an rc alone cannot tell "Rule E fired once" from
# "some other rule fired" or "Rule E fired on the wrong call".
#
# THE FINDING GRAMMAR IS PINNED: `<path>:<LINE>: credential header on curl argv<anything>`.
# For a YAML file <path> is the file and <LINE> is the best-effort line of the `run` body
# (the lint appends ` (step "<name>")` after the phrase). Every `want=0` row counts matches
# of THIS regex, so a regex that no longer matches the lint's wording would score zero
# matches and pass vacuously -- the self-check row below proves it still matches a known
# violating fixture's real output, and the lint's wording is changed only together with it.
E_MSG_RE='^[^[:space:]]+:[0-9]+: credential header on curl argv'

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

# --- Rule D: one fixture per LIMB, ALONE (#7873) ------------------------------
# Each fixture is compliant on every other limb, so a verdict can only be
# attributed to the limb it violates. A fixture breaking two limbs at once would
# make both rows pass while either check was dead.
rc="$(rc_of "$LINT" "$FIX/violation-ruled-no-disable.sh")"
[ "$rc" = "1" ] && pass "Rule D: credentialed curl without --disable is reported" \
  || fail "Rule D no-disable should report rc=1, got rc=$rc"

rc="$(rc_of "$LINT" "$FIX/violation-ruled-no-noproxy.sh")"
[ "$rc" = "1" ] && pass "Rule D: credentialed curl without --noproxy '*' is reported" \
  || fail "Rule D no-noproxy should report rc=1, got rc=$rc"

# POSITION, not presence. A presence-only check passes this fixture, and curl has
# already read ~/.curlrc by the time a late --disable is parsed -- so the flag is
# there and buys nothing. This is the row that makes the check mean what it says.
rc="$(rc_of "$LINT" "$FIX/violation-ruled-disable-not-first.sh")"
[ "$rc" = "1" ] && pass "Rule D: --disable present but NOT first is still reported" \
  || fail "Rule D disable-not-first should report rc=1, got rc=$rc"

# --- Rule D: the DESTINATION-PIN limb, both directions ------------------------
# This limb had ZERO fixtures in either direction, so eight independent mutations
# of it survived at full green -- including making `_adjudicated` return False
# unconditionally, and widening the `case` arm back to bare `*`.
rc="$(rc_of "$LINT" "$FIX/compliant-ruled-pinned-destination.sh")"
[ "$rc" = "0" ] && pass "Rule D: an adjudicated env-settable destination PASSES (must-pass direction)" \
  || fail "Rule D pinned-destination should pass, got rc=$rc"

rc="$(rc_of "$LINT" "$FIX/violation-ruled-vacuous-case-pin.sh")"
[ "$rc" = "1" ] && pass "Rule D: a \`case\` whose only arm is bare \`*\` is not a pin" \
  || fail "Rule D vacuous-case pin should report rc=1, got rc=$rc"

# The RHS class once contained `$`, so comparing the destination against another
# env-settable variable counted as adjudicated -- a second env var redirected the
# credential with the pin intact.
rc="$(rc_of "$LINT" "$FIX/violation-ruled-indirect-pin.sh")"
[ "$rc" = "1" ] && pass "Rule D: comparison against another env-settable variable is not a pin" \
  || fail "Rule D indirect pin should report rc=1, got rc=$rc"

# The `--config` channel: BOTH credential and destination live in a file the curl
# line does not name. Without a fixture here, `_inline_config_file` had no
# coverage at all -- and a review pass recommended deleting it as "measured zero
# impact", which was true of the FIXED tree and false of the regression it exists
# to catch (removing zot-inventory.sh's pin goes from detected to invisible).
# Two shapes the FIRST cut of the destination limb scored as fully compliant.
# Both are transport-confined and credentialed; only the pin is missing, and in
# each case the limb could not see it -- once because of the variable's NAME,
# once because the assignment carried no default.
rc="$(rc_of "$LINT" "$FIX/violation-ruled-unnamed-destination.sh")"
[ "$rc" = "1" ] && pass "Rule D: destination named \$SINK (no URL/HOST token in the name) is reported" \
  || fail "Rule D: unnamed destination should report rc=1, got rc=$rc"

rc="$(rc_of "$LINT" "$FIX/violation-ruled-bare-assignment-pin.sh")"
[ "$rc" = "1" ] && pass "Rule D: destination assigned bare from another variable is reported" \
  || fail "Rule D: bare-assignment destination should report rc=1, got rc=$rc"

rc="$(rc_of "$LINT" "$FIX/violation-ruled-config-file.sh")"
[ "$rc" = "1" ] && pass "Rule D: a --config file's env-settable destination is reported" \
  || fail "Rule D config-file destination should report rc=1, got rc=$rc"

# MUST-PASS. The flags are first at RUNTIME though the curl line names none of
# them. Without this row the rule can be "fixed" into a false positive on every
# array-built call site and the suite stays green -- measured on zot-inventory.sh.
rc="$(rc_of "$LINT" "$FIX/compliant-ruled-array.sh")"
[ "$rc" = "0" ] && pass "Rule D: array-built curl with the flags first PASSES (no false positive)" \
  || fail "Rule D array-built compliant should pass, got rc=$rc"

# Process-substitution token feed (`--config - "$URL" < <(printf ... "$TOK")`).
# The token inside <(...) is data on curl's stdin, never an operand. It used to be
# read as the destination, so a correctly pinned call site failed on "$TOK".
rc="$(rc_of "$LINT" "$FIX/compliant-stdin-bearer-procsub-bare.sh")"
[ "$rc" = "0" ] && pass "Rule D: bare process-substitution stdin-bearer curl with a pinned destination PASSES" \
  || fail "Rule D procsub-bare compliant should pass, got rc=$rc"

# ...and the same feed must NOT launder a genuinely unpinned destination.
rc="$(rc_of "$LINT" "$FIX/violation-ruled-procsub-unpinned.sh")"
[ "$rc" = "1" ] && pass "Rule D: procsub still flags a genuinely unpinned destination (rc=1)" \
  || fail "Rule D procsub-unpinned should report rc=1, got rc=$rc"
grep -q 'sends to \$SINK_URL,' "$WORK/out" "$WORK/err" \
  && pass "Rule D: procsub-unpinned message names the destination \$SINK_URL" \
  || fail "Rule D procsub-unpinned must name \$SINK_URL as the destination"
grep -q 'sends to \$SENTRY_AUTH_TOKEN' "$WORK/out" "$WORK/err" \
  && fail "Rule D procsub-unpinned must NOT name the token feed as the destination" \
  || pass "Rule D: procsub-unpinned does not name the token feed as the destination"

# --- SECRET_SIGNALS: one fixture per class, ALONE ----------------------------
for c in doppler-get capture gh-auth; do
  rc="$(rc_of "$LINT" "$FIX/violation-signal-$c.sh")"
  [ "$rc" = "1" ] && pass "signal class '$c' alone brings a file into scope" \
    || fail "signal class '$c' should bring the file into scope, got rc=$rc"
done

# --- Unenumerable credential set: the hatch is unrepresentable ---------------
# A file in scope via ${!name} ALONE names no credential, so a `${VAR:+x}` hatch
# has nothing real to test and is open by construction. Both rows are required:
# the must-PASS one is the positive control that separates "discriminates" from
# "rejects every indirect file".
rc="$(rc_of "$LINT" "$FIX/violation-indirect-conditional-hatch.sh")"
[ "$rc" = "1" ] && pass "indirect-only file with a conditional hatch is rejected" \
  || fail "indirect-only + conditional hatch should report rc=1, got rc=$rc"

# `${!arr[@]}` is array-KEY expansion, a different construct from `${!name}`
# indirect expansion: it yields index names, never a value. This fixture carries
# NO xtrace refusal, so it is rc=1 the moment it is treated as in scope — which
# is what the bare `\$\{!` spelling did to every script iterating an associative
# array (#7935; that script has since been retired by #8377).
rc="$(rc_of "$LINT" "$FIX/outofscope-array-key-expansion.sh")"
[ "$rc" = "0" ] && pass "array-key expansion \${!arr[@]} is OUT of scope (no credential, no refusal needed)" \
  || fail "array-key expansion should report rc=0, got rc=$rc"
reports "outofscope-array-key-expansion" \
  && fail "array-key expansion must not be NAMED as a violation" \
  || pass "array-key expansion is not named in the report"

rc="$(rc_of "$LINT" "$FIX/compliant-indirect-unconditional.sh")"
[ "$rc" = "0" ] && pass "indirect-only file refusing UNCONDITIONALLY is accepted (positive control)" \
  || fail "indirect-only + unconditional refusal should report rc=0, got rc=$rc"

# --- Production gates under tests/ are carved back in by ROLE, not by path ----
# The `tests/` exclusion exempted a live CI gate that binds a Cloudflare token
# and whose 2>&1 capture is posted verbatim into a public issue comment. The
# carve-out keys on a positive identity the executed role owns (shebang + exec
# bit), so a SOURCED gate -- which runs under the caller's `$-` -- stays out.
# Asserted against the real repo files: the predicate reads the filesystem, so a
# staged copy under $WORK could not exercise it.
_pred() { python3 -c "
import importlib.util,sys
s=importlib.util.spec_from_file_location('l','$LINT');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
print(m.excluded(sys.argv[1]))" "$1"; }

[ "$(_pred tests/scripts/lib/preapply-entrypoint-gate.sh)" = "False" ] \
  && pass "executed production gate under tests/ is IN scope (shebang + exec bit)" \
  || fail "executed production gate must not be excluded -- the #7797 leak path"

[ "$(_pred tests/scripts/lib/web-host-replace-gate.sh)" = "True" ] \
  && pass "SOURCED gate stays excluded (runs under the caller's \$-)" \
  || fail "sourced gate should stay excluded, the caller's preamble governs it"

[ "$(_pred tests/scripts/lib/no-such-gate.sh)" = "True" ] \
  && pass "unreadable gate path falls back to EXCLUDED (fail-closed carve-out)" \
  || fail "an unreadable gate path must not be carved in"

# --- --write-baseline must never write a TRUNCATED population ----------------
_bl="$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.baseline.txt"
_before="$(md5sum "$_bl" | cut -d" " -f1)"
rc="$(rc_of "$LINT" --write-baseline --changed --base origin/main)"
[ "$rc" = "2" ] && pass "--write-baseline refuses to run with --changed (would truncate the baseline)" \
  || fail "--write-baseline with --changed must exit 2, got rc=$rc"
rc="$(rc_of "$LINT" --write-baseline "$FIX/compliant-canonical.sh")"
[ "$rc" = "2" ] && pass "--write-baseline refuses explicit paths (would truncate the baseline)" \
  || fail "--write-baseline with explicit paths must exit 2, got rc=$rc"
[ "$(md5sum "$_bl" | cut -d" " -f1)" = "$_before" ] \
  && pass "the refused --write-baseline runs left the baseline byte-identical" \
  || fail "a refused --write-baseline still rewrote the baseline"

# --- The SCAFFOLD must be born compliant -------------------------------------
# The stub template is where every future probe starts. If it ships without a
# refusal, each new probe is born violating the guard and the population grows
# faster than the drawdown.
_tpl="$REPO_ROOT/plugins/soleur/skills/ship/references/followthrough-stub-template.sh"
if [ -f "$_tpl" ]; then
  cp "$_tpl" "$WORK/fx/probe-scaffolded.sh"
  printf 'TOK="$SENTRY_AUTH_TOKEN"\ncurl --disable --noproxy '"'"'*'"'"' --config - https://example.invalid < <(printf '"'"'header = "Authorization: Bearer %%s"\\n'"'"' "$TOK") >/dev/null 2>&1 || true\n' \
    >> "$WORK/fx/probe-scaffolded.sh"
  rc="$(rc_of "$LINT" "$WORK/fx/probe-scaffolded.sh")"
  [ "$rc" = "0" ] && pass "a probe scaffolded from the stub template passes the lint" \
    || fail "the stub template scaffolds a NON-COMPLIANT probe (rc=$rc) -- every new probe is born violating"
  _n="$(SENTRY_AUTH_TOKEN=SEKRIT_SCAFFOLD bash -x "$WORK/fx/probe-scaffolded.sh" 2>&1 </dev/null | grep -c 'SEKRIT_SCAFFOLD')"
  [ "$_n" = "0" ] && pass "the scaffolded probe leaks NO token value under bash -x" \
    || fail "the scaffolded probe leaked $_n line(s) under bash -x"
else
  fail "stub template not found at the expected path -- the scaffold guard cannot run"
fi

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
    + '\n\ncurl --disable --noproxy \'*\' -sS --config - https://example.invalid/ < <(printf \'header = "Authorization: Bearer %s"\\n\' "$SENTRY_AUTH_TOKEN") || true\n'
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
#
# Optional 6th arg: the exact number of Rule E messages the MUTANT run must print.
# A Python syntax error in the mutant exits 1 and would read as a RED mutant, so
# every row also refuses a mutant whose stderr carries a Traceback/SyntaxError --
# that is an instrument error, never a kill.
mutate_row() { # <label> <perl-expr> <fixture> <baseline-rc> <expected-mutant-rc> [<expected-mutant-E-count>]
  local label="$1" expr="$2" fx="$3" want_base="$4" want_mut="$5" want_e="${6:-}"
  local sandbox="$WORK/mut.py" base mut en
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
  if grep -qE 'Traceback|SyntaxError' "$WORK/err"; then
    fail "$label: INSTRUMENT ERROR -- the mutant crashed (Traceback/SyntaxError on stderr); a crash exits non-zero and would read as RED"
    return
  fi
  if [ -n "$want_e" ]; then
    en="$(cat "$WORK/out" "$WORK/err" | grep -cE "$E_MSG_RE")"
    if [ "$en" != "$want_e" ]; then
      fail "$label: mutant printed $en Rule E message(s), expected $want_e"
      return
    fi
  fi
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
# INSTRUMENT SELF-TEST for mutate_row (#7898 review). It is the only helper that
# owns its own pass/fail decision, and ALL 17 mutation rows route through it, so
# neutering it disarms every one of them at once: measured, inserting
# `pass "$1: DISARMED"; return 0` as its first line left this suite at
# "=== 61 passed, 0 failed ===", exit 0, floor satisfied. pass()/fail() are
# already driven in both directions; this closes the same gap one level up.
#
# Drive it with a row that MUST fail (a no-op mutation cannot change the rc, so
# the mutant rc equals the baseline and the row must be scored a failure), then
# unwind the counters. Reported with printf + exit, never through the helper.
_mr_p="$PASS" _mr_f="$FAIL"
mutate_row "instrument self-test (expected; not a real failure)" \
  's/NOTHING_MATCHES_THIS_TOKEN/x/' "$FIX/violation-no-preamble.sh" 1 2 >/dev/null 2>&1
if [ "$FAIL" -eq "$_mr_f" ]; then
  printf '[FATAL] instrument self-test: mutate_row did not report a failure for a no-op mutation (FAIL %d -> %d). The mutation harness is disarmed; all 17 rows below are meaningless.\n' \
    "$_mr_f" "$FAIL" >&2
  exit 1
fi
PASS="$_mr_p" FAIL="$_mr_f"
unset _mr_p _mr_f

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
  's/abc \+= check_rule_b\(/abc += [] and check_rule_b(/' \
  "$FIX/violation-trace-below-preamble.sh" 1 0

# M6 needs its own expected pair: the fail-closed arm moves 2 -> 0, and NEITHER
# value is 1. A generic "mutant is not 1" predicate would score this row green
# while the fail-closed arm was fully disarmed.
mutate_row 'M6 fail-closed: unparseable treated as clean' \
  's/return 2, \[\]  # unparseable/return 0, []  # unparseable/' \
  "$FIX/malformed-not-utf8.sh" 2 0

# M8: the INDIRECT arm is the one this PR added; without a row, deleting it
# leaves every unenumerable file silently accepting a hatch that cannot fire.
mutate_row 'M8 unenumerable: indirect arm dropped' \
  's/if INDIRECT_RE\.search\(body\) and not referenced_credentials\(lines\):/if False:/' \
  "$FIX/violation-indirect-conditional-hatch.sh" 1 0

# M9: the array-key EXCLUSION on SIGNAL_INDIRECT (#7935). Reverting it to the bare
# `${!` spelling puts every associative-array iteration back in scope, and the
# fixture — which binds no credential and carries no refusal — goes rc=0 -> rc=1.
# Without this row the exclusion is deletable at full green, and without the
# exclusion the guard reports a violation on a script that handles no secret,
# whose only remedies are a false xtrace refusal or a false baseline entry.
mutate_row 'M9 array-key exclusion reverted to the bare ${! spelling' \
  's/SIGNAL_INDIRECT = r"\\\$\\\{!\(\?!\[A-Za-z_\]\[A-Za-z0-9_\]\*\\\[\[\@\*\]\\\]\\\}\)"/SIGNAL_INDIRECT = r"\\\$\\\{!"/' \
  "$FIX/outofscope-array-key-expansion.sh" 0 1

# --- Rule D mutation rows: the GUARD's own operands ---------------------------
# Anchored on the CONDITION KEYWORD, not on the full expression. Pinning the
# exact `if _pin_re(var).search(body):` text meant that adding a second disjunct
# to that line made the sed a no-op -- and a mutation that does not land reports
# the baseline, which is indistinguishable from a pass. Same coupling as D3.
mutate_row 'D6 Rule D: destination adjudication disabled' \
  's/^(\s*)if _pin_re\(var\)[^\n]*$/${1}if False:/m' \
  "$FIX/compliant-ruled-pinned-destination.sh" 0 1

mutate_row 'D7 Rule D: pin accepts a variable RHS again (the `$` back in the class)' \
  's/\[A-Za-z0-9_\.\/:-\]/[A-Za-z0-9\$_.\/:-]/' \
  "$FIX/violation-ruled-indirect-pin.sh" 1 0

# D5 mutates the config-file resolution specifically. It is the one Rule D helper
# whose deletion looks free on a healthy tree: every verdict is unchanged until a
# destination pin regresses, which is exactly when it is needed.
mutate_row 'D5 Rule D: --config file resolution removed' \
  's/^(\s*)cmd = _inline_config_file\(cmd, lines\)$/${1}pass/m' \
  "$FIX/violation-ruled-config-file.sh" 1 0

# D8/D9 mutate the two fail-OPENs the ship-gate consult found in this rule's own
# operands. Both were live: each mutant is the code as first written.
mutate_row 'D8 Rule D: destination limb gated on the variable NAME again' \
  's/if var not in dest_vars:/if not re.search(r"(?:URL|URI|ENDPOINT|HOST)\\b", var):/' \
  "$FIX/violation-ruled-unnamed-destination.sh" 1 0

mutate_row 'D9 Rule D: bare-assignment spelling dropped from env_settable' \
  's/^BARE_ASSIGN_RHS = .*$/BARE_ASSIGN_RHS = r"ZZZNEVERMATCHES"/m' \
  "$FIX/violation-ruled-bare-assignment-pin.sh" 1 0

# Every row above mutates a FIXTURE and confirms Rule D reds. These mutate the
# RULE and confirm it does not silently WIDEN -- a guard that accepts everything
# is indistinguishable from a healthy run.
mutate_row 'D1 Rule D: --disable check degenerated to always-match' \
  's/CURL_DISABLE_FIRST = re\.compile\(r"[^"]*"\)/CURL_DISABLE_FIRST = re.compile(r"")/' \
  "$FIX/violation-ruled-no-disable.sh" 1 0

mutate_row 'D2 Rule D: --noproxy check degenerated to always-match' \
  's/CURL_NOPROXY = re\.compile\(r"[^"]*"\)/CURL_NOPROXY = re.compile(r"")/' \
  "$FIX/violation-ruled-no-noproxy.sh" 1 0

# Anchored on the ASSIGNMENT, not on the expression's exact text. The first
# version pinned `    d = check_rule_d(` including its indentation, so adding a
# scope guard to that line made the sed a no-op -- and a mutation that does not
# land reports the BASELINE, which is indistinguishable from a pass.
mutate_row 'D3 Rule D skipped entirely' \
  's/^(\s*)d = [^\n]*check_rule_d[^\n]*$/${1}d = []/m' \
  "$FIX/violation-ruled-no-disable.sh" 1 0

# The credential classifier is Rule D's scope gate: narrow it and the rule goes
# green over the population it was written for, which is exactly how a baseline
# shared with A/B/C would have neutered it.
# The fixture's credential reaches curl ONLY on stdin, so SECRET_SIGNALS cannot
# see it in argv either -- narrowing this one channel is the whole difference
# between reporting the site and waving it through. A row scored against an
# already-compliant fixture would read 0 -> 0 and prove nothing.
mutate_row 'D4 Rule D: credential classifier narrowed (stdin-header channel dropped)' \
  's/CURL_STDIN_HEADER = re\.compile\(r"[^"]*"\)/CURL_STDIN_HEADER = re.compile(r"(?!x)x")/' \
  "$FIX/violation-ruled-stdin-header.sh" 1 0

# D10/D11 mutate the two operand-scan edits that make the procsub rows hold.
# D10: the redirection target is an operand again -> the compliant fixture reds.
mutate_row 'D10 Rule D: redirection target read as a curl operand again' \
  's/^(\s*)if _REDIR_OP\.match\(toks\[i - 1\]\):$/${1}if False:/m' \
  "$FIX/compliant-stdin-bearer-procsub-bare.sh" 0 1

# D11: a bare `-` (stdin) read as a flag whose argument is skipped -> the unpinned
# destination after `--config -` goes invisible and the violation fixture greens.
mutate_row 'D11 Rule D: bare `-` treated as a flag, hiding the operand after it' \
  's/ and toks\[i - 1\] != "-":/:/' \
  "$FIX/violation-ruled-procsub-unpinned.sh" 1 0

# --- Rule E (#9597): bearer token on curl argv --------------------------------
# One row per fixture, and every row COUNTS Rule E's own messages (one per call
# site) AND the lint's total violation count. rc alone cannot tell "Rule E fired on
# the call it should" from "some other rule fired" or "Rule E fired twice on one
# call". Each violation fixture starts from a Rule-A/B/C/D-clean copy, so the total
# must equal the Rule E count. Each compliant fixture must exit 0 with zero Rule E
# messages.
E_ROWS=0
Y_ROWS=0
e_row() { # <label> <lint> <fixture> <want-E-count>
  local label="$1" lint="$2" fx="$3" want="$4" rc en tot
  E_ROWS=$((E_ROWS + 1))
  rc="$(rc_of "$lint" "$fx")"
  if grep -qE 'Traceback|SyntaxError' "$WORK/err"; then
    fail "$label: INSTRUMENT ERROR -- the lint crashed (Traceback/SyntaxError on stderr)"
    return
  fi
  en="$(cat "$WORK/out" "$WORK/err" | grep -cE "$E_MSG_RE")"
  tot="$(grep -ohE '[0-9]+ violation\(s\)' "$WORK/err" | grep -oE '^[0-9]+')"
  tot="${tot:-0}"
  if [ "$want" = "0" ]; then
    if [ "$rc" = "0" ] && [ "$en" = "0" ]; then
      pass "$label: rc=0 with 0 Rule E messages"
    else
      fail "$label: expected rc=0 and 0 Rule E messages, got rc=$rc E=$en total=$tot"
    fi
  elif [ "$rc" = "1" ] && [ "$en" = "$want" ] && [ "$tot" = "$want" ]; then
    pass "$label: rc=1 with exactly $want Rule E message(s) and no other rule firing"
  else
    fail "$label: expected rc=1, $want Rule E message(s) and $want total, got rc=$rc E=$en total=$tot"
  fi
}

# Mutate a COPY of a fixture (never the corpus), assert the mutation landed, then
# score the copy like any other fixture.
fx_mut_row() { # <label> <perl-expr> <source-fixture> <want-E-count> [<suffix, default .sh>]
  # The suffix is a PARAMETER because the lint dispatches on it: a YAML twin copied to a
  # `.sh` name would be scored by the shell arm and the row would test the wrong feeder.
  local label="$1" expr="$2" src="$3" want="$4" suffix="${5:-.sh}" copy
  copy="$WORK/fxmut$suffix"
  cp "$src" "$copy" || { fail "$label: fixture copy failed"; return; }
  perl -0pi -e "$expr" "$copy"
  if diff -q "$src" "$copy" >/dev/null 2>&1; then
    fail "$label: fixture mutation did NOT land -- the row would score the unmutated fixture"
    return
  fi
  [ "$suffix" = ".sh" ] || Y_ROWS=$((Y_ROWS + 1))
  e_row "$label" "$LINT" "$copy" "$want"
}

e_row 'Rule E: literal -H "Authorization: Bearer" on argv is reported' "$LINT" "$FIX/violation-argv-bearer-literal.sh" 1
e_row 'Rule E: a SECOND curl in the same script is judged too (compliant neighbour does not launder it)' "$LINT" "$FIX/violation-argv-bearer-second-member.sh" 1
e_row 'Rule E: header held in a variable and passed as -H "$var" is reported' "$LINT" "$FIX/violation-argv-bearer-variable-held.sh" 1
e_row 'Rule E: header held in an array (`=(`, `+=(` and an assignment after `&&`) is reported, one message per call site' "$LINT" "$FIX/violation-argv-bearer-array-held.sh" 3
e_row 'Rule E: --header single-quoted lower case, -H"..." with no space, and a header AFTER the URL: one message each' "$LINT" "$FIX/violation-argv-bearer-long-form.sh" 3
e_row 'Rule E: config-stdin hazards (-v, -d @-, here-string) on a --config - call: one message each' "$LINT" "$FIX/violation-argv-bearer-config-hazards.sh" 3
# Wrapper awareness (plan 1.2): the bearer is an argument of a CALL to a file-local
# function that invokes curl. Six call sites, ALL above their wrapper's definition:
# a direct call, a transitive wrapper, a call after `||`, one inside $(...), one after
# `! ` chained by `&&`, and one inside backticks.
e_row 'Rule E: bearer at six call sites of file-local wrappers (defined AFTER use, transitive, after ||, in $(...), after !, in backticks): one message each' "$LINT" "$FIX/violation-argv-bearer-wrapper.sh" 6

# MUST-PASS rows. The canonical row is NOT the only one: a suite whose single
# compliant fixture is the canonical form cannot tell "discriminates" from
# "flags every curl that mentions a bearer".
e_row 'Rule E: canonical `--config -` fed by a process substitution inside $(...) passes' "$LINT" "$FIX/compliant-stdin-bearer-procsub.sh" 0
e_row 'Rule E: bare `--config -` fed by a process substitution passes' "$LINT" "$FIX/compliant-stdin-bearer-procsub-bare.sh" 0
e_row 'Rule E: `printf ... | curl -H @-` passes (the assembly names a bearer, the invocation does not)' "$LINT" "$FIX/compliant-stdin-bearer-header-at-stdin.sh" 0
e_row 'Rule E: --header @<(...), -K -, --config <(...), a trailing-comment bearer and a standalone anon-key apikey: all pass' "$LINT" "$FIX/compliant-all-safe-forms.sh" 0
# A wrapper whose own curl keeps the bearer on stdin, called with only a URL and flags
# (also rc 0 = Rule D clean on the spliced call), plus a wrapper NAME used as an
# argument of `echo`, which is not a call.
e_row 'Rule E: a wrapper with a stdin bearer called with only a URL/flags passes (Rule D clean too); a wrapper name as an echo argument is not a call' "$LINT" "$FIX/compliant-stdin-bearer-wrapper.sh" 0

# Rule D through a wrapper: the wrapper's own curl names no destination ("$@"), the
# call passes an env-settable "$API_URL" that is never pinned. Exactly one Rule D
# message, nothing from Rule E (the bearer is on stdin) or A/B/C.
rc="$(rc_of "$LINT" "$FIX/violation-ruled-wrapper-env-url.sh")"
d_msgs="$(cat "$WORK/out" "$WORK/err" | grep -cE 'credentialed curl sends to \$API_URL, which is env-settable')"
d_tot="$(grep -ohE '[0-9]+ violation\(s\)' "$WORK/err" | grep -oE '^[0-9]+')"
e_msgs="$(cat "$WORK/out" "$WORK/err" | grep -cE "$E_MSG_RE")"
if [ "$rc" = "1" ] && [ "$d_msgs" = "1" ] && [ "${d_tot:-0}" = "1" ] && [ "$e_msgs" = "0" ]; then
  pass "Rule D: a wrapper called with an env-settable \"\$API_URL\" that is never pinned is reported once, and only by Rule D"
else
  fail "Rule D wrapper env-url: expected rc=1 with exactly one destination message and nothing else, got rc=$rc D=$d_msgs total=${d_tot:-0} E=$e_msgs"
fi

# Matrix row 1: the canonical compliant fixture with its --config - call replaced
# by the argv form must read RED with exactly one Rule E message.
fx_mut_row 'E1 canonical compliant with the --config - call replaced by -H "Authorization: Bearer"' \
  's/--config - "\$SINK_URL" < <\(printf \x27header = "Authorization: Bearer %s"\\n\x27 "\$SENTRY_AUTH_TOKEN"\)/-H "Authorization: Bearer \${SENTRY_AUTH_TOKEN}" "\$SINK_URL"/' \
  "$FIX/compliant-stdin-bearer-procsub.sh" 1

# --- Rule E widened (#9597 S1, decision D1): credential vocabulary ------------------
# The vocabulary is ONE named constant (E_CREDENTIAL: any `Authorization:` scheme,
# CF-Access-Client-Id/-Secret, X-Signature-256, X-API-Key) read at FIVE sites. Each site gets
# a fixture that ONLY that site can report, so re-narrowing exactly one of them to the legacy
# `Authorization: Bearer` reddens exactly one row (mutation rows V-S1..V-S5 below).

# SELF-CHECK for E_MSG_RE (see its definition): it must match a violating fixture's real
# output exactly once, and the retired wording must be gone. Without this row a regex that
# drifted away from the lint's wording makes every `want=0` row count zero matches and pass.
rc="$(rc_of "$LINT" "$FIX/violation-argv-bearer-literal.sh")"
_n_new="$(cat "$WORK/out" "$WORK/err" | grep -cE "$E_MSG_RE")"
_n_old="$(cat "$WORK/out" "$WORK/err" | grep -c 'bearer token on curl argv')"
if [ "$rc" = "1" ] && [ "$_n_new" = "1" ] && [ "$_n_old" = "0" ]; then
  pass "E_MSG_RE self-check: the pinned grammar matches a known violating fixture's output once (retired wording absent)"
else
  fail "E_MSG_RE self-check: rc=$rc, pinned-grammar matches=$_n_new (want 1), retired-wording matches=$_n_old (want 0) -- every want=0 Rule E row is vacuous until these agree"
fi
unset _n_new _n_old

e_row 'Rule E vocab: a CF-Access-Client-Id header HELD IN A VARIABLE (-H "$cf_hdr") is reported [held-name read site]' "$LINT" "$FIX/violation-argv-cred-held.sh" 1
e_row 'Rule E vocab: a CF-Access-Client-Secret header in an array assigned after && is reported [array-capture read site]' "$LINT" "$FIX/violation-argv-cred-array-late.sh" 1
e_row 'Rule E vocab: a literal X-Signature-256 header on argv is reported [header-scan read site]' "$LINT" "$FIX/violation-argv-cred-literal.sh" 1
e_row 'Rule E vocab: an X-Signature-256 header passed to a file-local wrapper is reported' "$LINT" "$FIX/violation-argv-cred-wrapper.sh" 1
e_row 'Rule E vocab: a stdin Authorization: Bot header plus an argv apikey: is reported as a second credential [call-level read site]' "$LINT" "$FIX/violation-argv-cred-second-credential.sh" 1
e_row 'Rule E vocab: a wrapper keeping Authorization: Bot on stdin, called with an argv apikey:, is reported [wrapper-site read site]' "$LINT" "$FIX/violation-argv-cred-second-wrapper.sh" 1
e_row 'Rule E vocab: ANY Authorization scheme is a credential (Bot, Digest, a ${SCHEME} variable, a glued lower-case authorization:): one message each' "$LINT" "$FIX/violation-argv-cred-schemes.sh" 4
e_row 'Rule E vocab: one site per alternate of the constant (Authorization, CF-Access-Client-Id, CF-Access-Client-Secret, X-Signature-256, X-API-Key): five messages' "$LINT" "$FIX/violation-argv-cred-alternates.sh" 5

# Known miss (discord-setup.sh): the Authorization: Bot header lives in a MULTI-LINE
# `local curl_args=(` array (no `-a`). The declaration regex only knew `local -a`, so the
# declaration was skipped and only the later `+=(-d ...)` append was inlined.
e_row 'Rule E: an Authorization: Bot header in a plain `local curl_args=(` array with a conditional += append is reported (the discord-setup.sh shape)' "$LINT" "$FIX/violation-argv-cred-local-array.sh" 1

# MUST-PASS rows for the widened vocabulary (a suite whose only compliant fixture is the old
# canonical one cannot tell "discriminates" from "flags every new header name").
e_row 'Rule E vocab: the new header names on the SAFE spellings (--config - procsub, printf | curl -H @-) pass' "$LINT" "$FIX/compliant-stdin-cred-nonbearer.sh" 0
# Rule D must see through the same declaration: a compliant call whose --disable-first flags
# sit in a plain `local curl_args=(` array was a FALSE Rule D finding while the declaration
# regex was blind to it.
e_row 'Rule D/E: flags-first flags in a plain `local curl_args=(` array pass (no false Rule D finding)' "$LINT" "$FIX/compliant-ruled-local-array.sh" 0
# PINNED BLIND SPOTS (xfail): rc 0 is the CURRENT, documented verdict. Widening the vocabulary
# to cookies or vendor headers must be a visible edit to this row, not a silent drift.
e_row 'Rule E xfail: -b "session=$T", -H "Cookie: s=$T" and x-gitlab-token are NOT in the vocabulary (pinned blind spot)' "$LINT" "$FIX/outofscope-blindspot-cookie-custom-header.sh" 0

# --- Rule E widened (#9597 S1, D1): the YAML arm -----------------------------------
# `.github/**` YAML is scanned by extracting every `run` string value with PyYAML (so a
# folded scalar and an inline `run: "curl ..."` step reach bash exactly as bash sees them);
# cloud-init files are scanned by RAW LINES because they are Terraform-templated and do not
# parse. Dispatch keys on SUFFIX and CONTENT (`#cloud-config`), never on a repo-relative
# `.github/` prefix: the fixture copies live at absolute out-of-repo paths, so a prefix test
# would scan nothing and every row below would pass vacuously.
#
# POSITIVE CONTROL: the copied fixture corpus must hold the YAML fixtures. A guard that
# scans no YAML cannot then pass the must-PASS set unnoticed.
Y_FIXTURES="$(find "$FIX" -maxdepth 1 -name '*.yml' | wc -l)"
if [ "$Y_FIXTURES" -lt 17 ]; then
  fail "YAML positive control: only $Y_FIXTURES .yml fixtures were copied, anti-vacuity floor is 17"
else
  pass "YAML positive control: $Y_FIXTURES .yml fixtures present in the fixture copy (anti-vacuity floor 17)"
fi
y_row() { Y_ROWS=$((Y_ROWS + 1)); e_row "$@"; }

y_row 'Rule E YAML: literal block (run: |) after a compliant first step is reported' "$LINT" "$FIX/violation-yaml-literal.yml" 1
y_row 'Rule E YAML: FOLDED scalar (run: >-) is reported' "$LINT" "$FIX/violation-yaml-folded.yml" 1
y_row 'Rule E YAML: inline single-quoted run: is reported' "$LINT" "$FIX/violation-yaml-inline-quoted.yml" 1
y_row 'Rule E YAML: inline double-quoted run: with escaped quotes is reported' "$LINT" "$FIX/violation-yaml-inline-escaped.yml" 1
y_row 'Rule E YAML: list-item run: with a backslash-continued header is reported' "$LINT" "$FIX/violation-yaml-list-continuation.yml" 1
y_row 'Rule E YAML: a ${{ secrets.X }} interpolation inside the header is reported' "$LINT" "$FIX/violation-yaml-interpolation.yml" 1
y_row 'Rule E YAML: a composite-action step (runs.steps[*] with shell: bash) is reported' "$LINT" "$FIX/violation-yaml-composite.yml" 1
y_row 'Rule E YAML: a workflow step with NO shell: key is reported (bash is the default)' "$LINT" "$FIX/violation-yaml-noshell.yml" 1
y_row 'Rule E YAML: a step under defaults.run.shell: bash is reported' "$LINT" "$FIX/violation-yaml-defaults-shell.yml" 1
y_row 'Rule E YAML: two offending steps are two messages' "$LINT" "$FIX/violation-yaml-second-site.yml" 2
y_row 'Rule E cloud-init: a Terraform-templated cloud-init file (not valid YAML) is scanned by raw lines and its curl is reported' "$LINT" "$FIX/cloud-init-violation.yml" 1

y_row 'Rule E YAML must-PASS: echo/printf of a runbook curl line and a comment inside run: are not executed curl commands' "$LINT" "$FIX/compliant-yaml-echo-only.yml" 0
y_row 'Rule E YAML must-PASS: printf | curl -H @- and curl --config - < <(printf ...) inside run: pass' "$LINT" "$FIX/compliant-yaml-stdin.yml" 0
y_row 'Rule E YAML must-PASS: a step whose shell: is python is not bash and is skipped' "$LINT" "$FIX/compliant-yaml-nonbash-shell.yml" 0
y_row 'Rule E YAML must-PASS: a step with no shell: under defaults.run.shell: python is not bash and is skipped' "$LINT" "$FIX/compliant-yaml-defaults-nonbash.yml" 0
y_row 'Rule E cloud-init must-PASS: a templated cloud-init file with only the stdin forms passes' "$LINT" "$FIX/cloud-init-compliant.yml" 0

# Violating TWIN of each must-PASS (harness row c): the minimal edit that makes the same
# fixture an offender must read RED, so "passes" means "discriminates", not "scans nothing".
fx_mut_row 'Rule E YAML twin: the echoed runbook curl line, executed instead of printed, reads RED' \
  's/echo "Retry with: (curl -H [^\n]*)"\n/$1\n/' \
  "$FIX/compliant-yaml-echo-only.yml" 1 .yml
fx_mut_row 'Rule E YAML twin: the commented-out curl line, uncommented, reads RED' \
  's/# (curl -H "Authorization: Bearer \$\{FIXTURE_TOKEN\}" "\$SINK_URL")/$1/' \
  "$FIX/compliant-yaml-echo-only.yml" 1 .yml
fx_mut_row 'Rule E YAML twin: -H @- replaced by the argv header reads RED' \
  's/(\| curl [^\n]*? )-H @-/${1}-H "Authorization: Bearer \${FIXTURE_TOKEN}"/' \
  "$FIX/compliant-yaml-stdin.yml" 1 .yml
fx_mut_row 'Rule E YAML twin: shell: python changed to shell: bash reads RED' \
  's/^(\s+)shell: python$/${1}shell: bash/m' \
  "$FIX/compliant-yaml-nonbash-shell.yml" 1 .yml
fx_mut_row 'Rule E YAML twin: defaults.run.shell python changed to bash reads RED' \
  's/^(\s+)shell: python$/${1}shell: bash/m' \
  "$FIX/compliant-yaml-defaults-nonbash.yml" 1 .yml
fx_mut_row 'Rule E cloud-init twin: the stdin-form curl replaced by the argv header reads RED' \
  's/printf \x27X-API-Key: %s\\n\x27 "\$FIXTURE_TOKEN" \| curl --disable --noproxy \x27\*\x27 -sS -H @-/curl --disable --noproxy \x27*\x27 -sS -H "X-API-Key: \${FIXTURE_TOKEN}"/' \
  "$FIX/cloud-init-compliant.yml" 1 .yml

# An unparseable `.github`-style YAML file is exit 2 ("cannot evaluate", ADR-157), never a
# skip and never a raw-line fallback. The fixture ALSO holds a raw-detectable site, because
# otherwise "skipped" and "fallback found nothing" would both read rc 0.
Y_ROWS=$((Y_ROWS + 1))
rc="$(rc_of "$LINT" "$FIX/violation-yaml-unparseable.yml")"
if [ "$rc" = "2" ] && grep -q 'violation-yaml-unparseable.yml: cannot evaluate (YAML did not parse' "$WORK/err" \
  && ! grep -qE "$E_MSG_RE" "$WORK/out" "$WORK/err"; then
  pass "Rule E YAML: an unparseable YAML file exits exactly 2 with the pinned note, not a skip and not a raw-line fallback"
else
  fail "Rule E YAML: unparseable fixture should exit 2 with the pinned note and no Rule E message, got rc=$rc: $(head -c 300 "$WORK/err")"
fi

# PyYAML is imported LAZILY (the `--changed` path is stdlib-only) and a missing PyYAML is exit
# 2, not "no YAML findings". `yaml.py` raising ImportError ahead of site-packages hides it.
NOYAML="$WORK/noyaml"
mkdir -p "$NOYAML" && printf 'raise ImportError("PyYAML hidden by the suite")\n' > "$NOYAML/yaml.py"
rc_env() { # <PYTHONPATH> <lint> <target...> -> echoes rc
  local pp="$1" lint="$2"
  shift 2
  PYTHONPATH="$pp" python3 "$lint" "$@" >"$WORK/out" 2>"$WORK/err"
  printf '%s' "$?"
}
Y_ROWS=$((Y_ROWS + 1))
rc="$(rc_env "$NOYAML" "$LINT" "$FIX/violation-yaml-literal.yml")"
if [ "$rc" = "2" ] && grep -q 'PyYAML is required to scan workflow YAML' "$WORK/err" && ! grep -q 'did not parse' "$WORK/err"; then
  pass "Rule E YAML: a missing PyYAML exits 2 with its own note (not the unparseable-file note, not rc 0)"
else
  fail "Rule E YAML: hidden PyYAML should exit 2 with the 'PyYAML is required' note, got rc=$rc: $(head -c 300 "$WORK/err")"
fi
Y_ROWS=$((Y_ROWS + 1))
rc="$(rc_env "$NOYAML" "$LINT" "$FIX/violation-argv-bearer-literal.sh" "$FIX/compliant-canonical.sh")"
if [ "$rc" = "1" ] && grep -qE "$E_MSG_RE" "$WORK/err"; then
  pass "Rule E YAML: PyYAML is imported lazily -- the shell-only path works with PyYAML hidden"
else
  fail "Rule E YAML: the shell-only path must not need PyYAML, got rc=$rc: $(head -c 300 "$WORK/err")"
fi

# Only yaml.YAMLError is the unparseable path. A loader that fails any OTHER way is a broken
# instrument and must surface as a crash, never as "this file did not parse".
BROKENYAML="$WORK/brokenyaml"
mkdir -p "$BROKENYAML"
cat > "$BROKENYAML/yaml.py" <<'PYSHIM'
class YAMLError(Exception):
    pass
class SafeLoader:
    pass
def compose_all(text, Loader=None):
    raise RuntimeError("shim: loader failed in a way that is not a YAML syntax error")
PYSHIM
Y_ROWS=$((Y_ROWS + 1))
rc="$(rc_env "$BROKENYAML" "$LINT" "$FIX/violation-yaml-literal.yml")"
if [ "$rc" != "0" ] && [ "$rc" != "2" ] && grep -q 'RuntimeError' "$WORK/err" && ! grep -q 'did not parse' "$WORK/err"; then
  pass "Rule E YAML: a non-YAMLError loader failure surfaces as a crash (rc=$rc), never as an unparseable-file verdict"
else
  fail "Rule E YAML: a non-YAMLError failure must not be reported as 'did not parse' or rc 0/2, got rc=$rc: $(head -c 300 "$WORK/err")"
fi

# HARNESS ROW (b): the fixture runner must NOT ignore the exit status. Drive e_row with a
# stand-in lint that exits 0 and prints nothing: a violation row (want 1) MUST be scored a
# failure, and a stand-in that exits 1 silently must fail a must-PASS row. Counters are
# unwound; the verdict is reported directly, never through the helper under test.
printf 'import sys\nsys.exit(0)\n' > "$WORK/fake-ok.py"
printf 'import sys\nsys.exit(1)\n' > "$WORK/fake-red.py"
_h_f="$FAIL" _h_p="$PASS" _h_e="$E_ROWS"
e_row 'instrument self-test: always-0 stand-in on a violation row (expected failure)' "$WORK/fake-ok.py" "$FIX/violation-yaml-literal.yml" 1 >/dev/null 2>&1
_h_a=$((FAIL - _h_f))
e_row 'instrument self-test: always-1 stand-in on a must-PASS row (expected failure)' "$WORK/fake-red.py" "$FIX/compliant-yaml-stdin.yml" 0 >/dev/null 2>&1
_h_b=$((FAIL - _h_f - _h_a))
PASS="$_h_p" FAIL="$_h_f" E_ROWS="$_h_e"
if [ "$_h_a" != "1" ] || [ "$_h_b" != "1" ]; then
  printf '[FATAL] instrument self-test: e_row ignores the exit status / message count (violation row failures=%s, must-PASS row failures=%s, want 1 and 1). Every Rule E row below is meaningless.\n' "$_h_a" "$_h_b" >&2
  exit 1
fi
unset _h_f _h_p _h_e _h_a _h_b

# Real-corpus discovery floors (matrix row 2, against the real tree): the lint's own file
# set must hold the measured YAML population. A discovery reverted to `*.sh` reports "0
# checked" for YAML and exits 0, which no per-file row can see.
YAML_TARGETS="$(python3 - "$LINT" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("l", sys.argv[1])
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
files = m.rule_e_files()
print(sum(1 for p in files if p.suffix in (".yml", ".yaml")))
PY
)"
if [ "${YAML_TARGETS:-0}" -lt 103 ]; then
  fail "Rule E discovery: rule_e_files() lists ${YAML_TARGETS:-0} YAML files, anti-vacuity floor is 103 (98 .github + 5 cloud-init at implementation time; grow-only)"
else
  pass "Rule E discovery: rule_e_files() lists $YAML_TARGETS YAML files (anti-vacuity floor 103)"
fi
# Every `git ls-files` pathspec the discovery uses must match at least one real file
# (hr-when-a-plan-specifies-relative-paths-e-g), except the `.yaml` spelling, which GitHub
# accepts and the tree does not use yet: it is exercised by the sandbox row below instead.
_dead=0
_nps=0
while IFS= read -r _ps; do
  [ -n "$_ps" ] || continue
  _nps=$((_nps + 1))
  case "$_ps" in *.yaml) continue ;; esac
  [ "$(git -C "$REPO_ROOT" ls-files -- "$_ps" | wc -l)" -ge 1 ] || { _dead=$((_dead + 1)); printf 'dead pathspec: %s\n' "$_ps" >&2; }
done < <(python3 - "$LINT" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("l", sys.argv[1])
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
print("\n".join(m.E_YAML_PATHSPECS))
PY
)
if [ "$_nps" -lt 3 ]; then
  fail "Rule E discovery: read only $_nps YAML pathspec(s) from the lint, anti-vacuity floor is 3"
elif [ "$_dead" != "0" ]; then
  fail "Rule E discovery: $_dead YAML pathspec(s) match no tracked file"
else
  pass "Rule E discovery: all $_nps YAML pathspecs read from the lint match at least one tracked file (the .yaml spelling is covered by the sandbox row)"
fi
unset _dead _ps _nps

# Floors on EXECUTED fixture rows, hung on call-site counters (E_ROWS counts every e_row call,
# Y_ROWS every YAML-arm row). Each threshold is the EXACT measured count, so deleting one row
# reads RED, and a dead dispatch or a deleted loop reads RED instead of "0 checked". Written
# `-lt N` with the lower-case words `anti-vacuity floor` so scripts/guard-vacuity-floor.test.sh
# can see and mutation-test them.
if [ "$E_ROWS" -lt 47 ]; then
  fail "Rule E: only $E_ROWS fixture rows executed, anti-vacuity floor is 47"
else
  pass "Rule E: $E_ROWS fixture rows executed (anti-vacuity floor 47)"
fi
if [ "$Y_ROWS" -lt 26 ]; then
  fail "Rule E YAML arm: only $Y_ROWS rows executed, anti-vacuity floor is 26"
else
  pass "Rule E YAML arm: $Y_ROWS rows executed (anti-vacuity floor 26)"
fi

# --census must agree with baseline E: a dispatch that never runs Rule E reports
# offenders_e=0 against a non-empty baseline.
BASE_E_FILE="$REPO_ROOT/scripts/lint-shell-trace-credential-refusal-e.baseline.txt"
python3 "$LINT" --census >"$WORK/census" 2>"$WORK/census.err"
census_e="$(head -1 "$WORK/census" | grep -oE 'offenders_e=[0-9]+' | cut -d= -f2)"
base_e="$(grep -cvE '^(#|[[:space:]]*$)' "$BASE_E_FILE" 2>/dev/null)"
if [ -n "$census_e" ] && [ "$census_e" = "$base_e" ]; then
  pass "Rule E: --census offenders_e ($census_e) equals baseline E's length ($base_e)"
else
  fail "Rule E: --census offenders_e='$census_e' does not equal baseline E length '$base_e'"
fi
# HARNESS ROW (d): baseline E vs the hand-reviewed census ceiling. `--write-baseline-e` seeds
# the baseline from the tool under test, so a false positive would otherwise be certified by
# its own output. Every baseline path must be in the ceiling table with a count at or below it.
CEIL_FILE="$FIX/rule-e-census-ceiling.tsv"
_bad=0
_listed=0
while IFS=$'\t' read -r _bp _bn; do
  case "$_bp" in '' | '#'*) continue ;; esac
  _listed=$((_listed + 1))
  _ceil="$(awk -F'\t' -v p="$_bp" '$1 == p { print $2 }' "$CEIL_FILE")"
  if [ -z "$_ceil" ] || [ "$_bn" -gt "$_ceil" ]; then
    _bad=$((_bad + 1))
    printf 'baseline E entry above its census ceiling or absent from it: %s (listed %s, ceiling %s)\n' "$_bp" "$_bn" "${_ceil:-none}" >&2
  fi
done < "$BASE_E_FILE"
if [ "$_listed" -lt 1 ]; then
  fail "Rule E baseline vs census ceiling: baseline E lists no entries, anti-vacuity floor is 1"
elif [ "$_bad" != "0" ]; then
  fail "Rule E baseline vs census ceiling: $_bad baseline E entr(ies) exceed or are missing from the hand-reviewed census table"
else
  pass "Rule E baseline vs census ceiling: all $_listed baseline E entries are in the census table at or below their ceiling"
fi
unset _bad _listed _ceil _bp _bn

grep -qx -- '--- rule E ---' "$WORK/census" \
  && pass "Rule E: --census carries a '--- rule E ---' list" \
  || fail "Rule E: --census has no '--- rule E ---' list"

# Matrix row 2: delete the check_rule_e assignment in check_file() (anchored on its
# own line, scoped to that function). Mutant must read GREEN on a violation fixture.
mutate_row 'E2 Rule E dispatch dead: the check_rule_e assignment in check_file() removed' \
  's/(def check_file\(.*?)^(\s*)e = [^\n]*check_rule_e[^\n]*$/${1}${2}e = []/ms' \
  "$FIX/violation-argv-bearer-literal.sh" 1 0 0

# Matrix row 3: only the FIRST curl command judged -> the second member goes unseen.
mutate_row 'E3 Rule E judges only the first curl command' \
  's/(def check_rule_e\(.*?for \w+, \w+ in _curl_commands\(lines\))(:)/${1}[:1]${2}/s' \
  "$FIX/violation-argv-bearer-second-member.sh" 1 0 0

# Matrix row 4: variable-held, array-held and long-form members, each mutated away.
mutate_row 'E4a Rule E: file-wide variable-held header resolution removed' \
  's/(def check_rule_e\(.*?)held = _e_held_names\([^\n]*\)/${1}held = set()/s' \
  "$FIX/violation-argv-bearer-variable-held.sh" 1 0 0
# Array members are covered by TWO paths (call-site inlining, then a file-wide
# fallback for expansions the inliner could not resolve), so killing either alone is
# an equivalent mutant for the first two sites. E4b kills BOTH; E4e kills only the
# fallback, which must lose exactly the `&&`-assigned third site.
mutate_row 'E4b Rule E: array bodies resolved by neither the inliner nor the file-wide fallback' \
  's/ARRAY_EXPANSION = re\.compile\(r"[^\n]*\n/ARRAY_EXPANSION = re.compile(r"(?!x)x")\n/; s/E_ARRAY_WORD = re\.compile\(r"[^\n]*\n/E_ARRAY_WORD = re.compile(r"(?!x)x")\n/' \
  "$FIX/violation-argv-bearer-array-held.sh" 1 0 0
mutate_row 'E4e Rule E: file-wide array fallback dropped (the `&&`-assigned array goes unseen)' \
  's/E_ARRAY_WORD = re\.compile\(r"[^\n]*\n/E_ARRAY_WORD = re.compile(r"(?!x)x")\n/' \
  "$FIX/violation-argv-bearer-array-held.sh" 1 1 2
mutate_row 'E4c Rule E: bearer match made case-sensitive' \
  's/(E_CREDENTIAL = re\.compile\([^\n]*), re\.I\)/${1})/' \
  "$FIX/violation-argv-bearer-long-form.sh" 1 1 1
mutate_row 'E4d Rule E: attached -H"..." (no space) form dropped' \
  's/E_HDR_ATTACHED = re\.compile\(r"[^\n]*\n/E_HDR_ATTACHED = re.compile(r"(?!x)x")\n/' \
  "$FIX/violation-argv-bearer-long-form.sh" 1 1 2

# Matrix row 6 members, each mutated away on its own fixture.
mutate_row 'E6a Rule E: -v/--verbose/--trace hazard dropped' \
  's/E_VERBOSE = re\.compile\(r"[^\n]*\n/E_VERBOSE = re.compile(r"(?!x)x")\n/' \
  "$FIX/violation-argv-bearer-config-hazards.sh" 1 1 2
mutate_row 'E6b Rule E: stdin-body hazard dropped' \
  's/E_STDIN_BODY = re\.compile\(\s*r"[^\n]*"\s*\)/E_STDIN_BODY = re.compile(r"(?!x)x")/' \
  "$FIX/violation-argv-bearer-config-hazards.sh" 1 1 2
mutate_row 'E6c Rule E: here-string/heredoc hazard dropped' \
  's/E_HEREDOC = re\.compile\(r"[^\n]*\n/E_HEREDOC = re.compile(r"(?!x)x")\n/' \
  "$FIX/violation-argv-bearer-config-hazards.sh" 1 1 2

# --- Rule E baseline: a sandbox repo (rows 8 and 9) ----------------------------
# The repo-wide arm compares baseline E to the live offender set on PATH AND COUNT.
# That cannot be exercised against the real tree (editing the real baseline is
# exactly what the rule forbids), so each row builds a mini git repo holding a
# perl-mutated COPY of the lint, empty A/B/C and D baselines, baseline E, one
# E-only offender and one clean file. `git init && git add` is what makes
# `git ls-files` (the repo-wide walk) see them. The sandbox lives under $WORK; the
# real checkout is never touched.
SBX_N=0
SBX=""
SBX_GIT=(env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE git)
sbx_repo() { # <baseline-E body (printf-escaped)> [<perl-expr applied to the lint copy>] [<yaml fixture -> .github/workflows/offender.yml>] [<yaml fixture -> .github/workflows/offender2.yaml>]
  SBX_N=$((SBX_N + 1))
  SBX="$WORK/sbx$SBX_N"
  local lintc="$SBX/scripts/lint-shell-trace-credential-refusal.py"
  mkdir -p "$SBX/scripts" || return 1
  cp "$LINT" "$lintc" || return 1
  if [ -n "${2:-}" ]; then
    perl -0pi -e "$2" "$lintc"
    if diff -q "$LINT" "$lintc" >/dev/null 2>&1; then
      printf 'sbx_repo: perl mutation did not land\n' >&2
      return 1
    fi
  fi
  printf '# sandbox\n' > "$SBX/scripts/lint-shell-trace-credential-refusal.baseline.txt"
  printf '# sandbox\n' > "$SBX/scripts/lint-shell-trace-credential-refusal-d.baseline.txt"
  # shellcheck disable=SC2059
  printf "# sandbox (#9597)\n$1" > "$SBX/scripts/lint-shell-trace-credential-refusal-e.baseline.txt"
  cp "$FIX/violation-argv-bearer-literal.sh" "$SBX/scripts/offender.sh"
  cp "$FIX/compliant-stdin-bearer-procsub.sh" "$SBX/scripts/clean.sh"
  if [ -n "${3:-}" ]; then
    mkdir -p "$SBX/.github/workflows" || return 1
    cp "$3" "$SBX/.github/workflows/offender.yml" || return 1
    if [ -n "${4:-}" ]; then
      cp "$4" "$SBX/.github/workflows/offender2.yaml" || return 1
    fi
  fi
  "${SBX_GIT[@]}" -C "$SBX" init -q >/dev/null 2>&1 && "${SBX_GIT[@]}" -C "$SBX" add -A >/dev/null 2>&1
}
sbx_run() { # <lint-args...> -> echoes rc; runs from inside the sandbox
  ( cd "$SBX" && env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE \
      python3 scripts/lint-shell-trace-credential-refusal.py "$@" ) >"$WORK/out" 2>"$WORK/err"
  printf '%s' "$?"
}
sbx_clean_run() { # -> 0 when the last run left no crash on stderr
  ! grep -qE 'Traceback|SyntaxError' "$WORK/err"
}

# Sanity first: baseline E listing the offender with its exact count is GREEN.
if sbx_repo 'scripts/offender.sh\t1\n'; then
  rc="$(sbx_run)"
  if [ "$rc" = "0" ] && grep -q 'Rule E' "$WORK/out" && sbx_clean_run; then
    pass "Rule E baseline: an offender listed with its exact count is accepted and the OK line names Rule E"
  else
    fail "Rule E baseline: exact-count sandbox expected rc=0 naming Rule E, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
  # Row 9d: an explicit path BYPASSES baseline E, the repo-wide run above does not.
  rc="$(sbx_run scripts/offender.sh)"
  if [ "$rc" = "1" ] && grep -qE "$E_MSG_RE" "$WORK/err" && sbx_clean_run; then
    pass "Rule E baseline: an explicit path to a baselined file reports (bypass) while the repo-wide run does not"
  else
    fail "Rule E baseline: explicit path to a baselined offender should report rc=1, got rc=$rc"
  fi
  # --changed bypasses it too: commit, touch the offender, diff against the parent.
  "${SBX_GIT[@]}" -C "$SBX" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -qm base >/dev/null 2>&1
  printf '# touched\n' >> "$SBX/scripts/offender.sh"
  "${SBX_GIT[@]}" -C "$SBX" add -A >/dev/null 2>&1
  "${SBX_GIT[@]}" -C "$SBX" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -qm touch >/dev/null 2>&1
  rc="$(sbx_run --changed --base HEAD~1)"
  if [ "$rc" = "1" ] && grep -qE "$E_MSG_RE" "$WORK/err" && sbx_clean_run; then
    pass "Rule E baseline: --changed bypasses baseline E and reports the touched offender"
  else
    fail "Rule E baseline: --changed on a baselined offender should report rc=1, got rc=$rc"
  fi
else
  fail "Rule E baseline: could not build the sandbox repo"
fi

# Row 8: drop the "e" entry from the rule -> baseline map. An E-only offender listed
# in baseline E must then REPORT (it falls back to the A/B/C list, which lacks it).
if sbx_repo 'scripts/offender.sh\t1\n' 's/, "e": baseline_e_ok(?=\})//'; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -qE "$E_MSG_RE" "$WORK/err" && sbx_clean_run; then
    pass "Rule E baseline M8: dropping the \"e\" entry from baselines_by_rule reddens a correctly baselined offender"
  else
    fail "Rule E baseline M8: mutant (no \"e\" map entry) should report rc=1, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
else
  fail "Rule E baseline M8: could not build the mutated sandbox (mutation did not land?)"
fi

# Row 9: equality on path AND count.
if sbx_repo 'scripts/offender.sh\t1\nscripts/clean.sh\t1\n'; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q 'scripts/clean.sh' "$WORK/err" && sbx_clean_run; then
    pass "Rule E baseline M9a: a clean file listed in baseline E is reported (a listed file must still offend)"
  else
    fail "Rule E baseline M9a: clean file in baseline E should report rc=1 naming it, got rc=$rc"
  fi
fi
if sbx_repo ''; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -qE "$E_MSG_RE" "$WORK/err" && grep -q 'scripts/offender.sh' "$WORK/err" && sbx_clean_run; then
    pass "Rule E baseline M9b: a still-violating file removed from baseline E is reported"
  else
    fail "Rule E baseline M9b: unlisted offender should report rc=1, got rc=$rc"
  fi
fi
if sbx_repo 'scripts/offender.sh\t2\n'; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q 'scripts/offender.sh' "$WORK/err" && sbx_clean_run; then
    pass "Rule E baseline M9c: a listed file whose live site count differs is reported (equality, not suppression)"
  else
    fail "Rule E baseline M9c: count 2 vs live 1 should report rc=1, got rc=$rc"
  fi
fi
if sbx_repo 'scripts/offender.sh\t1\nscripts/gone.sh\t1\n'; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q 'scripts/gone.sh' "$WORK/err" && sbx_clean_run; then
    pass "Rule E baseline M9d: a listed path that no longer exists is reported"
  else
    fail "Rule E baseline M9d: stale listed path should report rc=1 naming it, got rc=$rc"
  fi
fi

# --- Rule E widened (#9597 S1): repo-wide rows for the YAML arm ----------------------
# `mutate_row` copies the lint to $WORK/mut.py and runs it on ONE explicit path, which bypasses
# the baseline and the discovery walk. The repo-wide properties (equality on a YAML file, the
# discovery set, the dispatch of the new arm) are only observable through a mini repo, so these
# rows use `sbx_repo` extended with `.github/workflows/offender.yml` (and a `.yaml` twin).
YAML_LIT="$FIX/violation-yaml-literal.yml"
YAML_TWO="$FIX/violation-yaml-second-site.yml"

# Sanity: a YAML offender listed with its exact count is GREEN, and the OK line counts it.
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n' '' "$YAML_LIT"; then
  rc="$(sbx_run)"
  if [ "$rc" = "0" ] && grep -q '2 site(s)' "$WORK/out" && sbx_clean_run; then
    pass "Rule E YAML baseline: a workflow offender listed with its exact count is accepted (the OK line counts its site)"
  else
    fail "Rule E YAML baseline: exact-count YAML sandbox expected rc=0 and '2 site(s)', got rc=$rc: $(head -c 300 "$WORK/err") $(head -c 200 "$WORK/out")"
  fi
  rc="$(sbx_run .github/workflows/offender.yml)"
  if [ "$rc" = "1" ] && grep -qE "$E_MSG_RE" "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML baseline: an explicit YAML path to a baselined file reports (bypass) and runs Rule E only"
  else
    fail "Rule E YAML baseline: explicit YAML path should report rc=1, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
else
  fail "Rule E YAML baseline: could not build the YAML sandbox repo"
fi

# Matrix row 1: a SECOND argv credential site in a baselined workflow (live 2, listed 1) must
# redden repo-wide equality and name the file. The same row is "a baseline seeded lower than live".
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n' '' "$YAML_TWO"; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q '.github/workflows/offender.yml' "$WORK/err" && grep -qE "$E_MSG_RE" "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML baseline M1: a second site in a baselined workflow (live 2, listed 1) is reported and names the file"
  else
    fail "Rule E YAML baseline M1: live 2 vs listed 1 should report rc=1 naming the workflow, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
fi
if sbx_repo 'scripts/offender.sh\t1\n' '' "$YAML_LIT"; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q '.github/workflows/offender.yml' "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML baseline M1b: a YAML offender missing from baseline E is reported"
  else
    fail "Rule E YAML baseline M1b: unlisted YAML offender should report rc=1, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
fi

# Matrix row 2: discovery reverted to shell-only (and, separately, the dispatch of the arm
# dropped): the listed YAML file then has live count 0 and equality must fail naming it. This
# is the mutant that reports "0 checked" and exits 0 when no baseline lists the file.
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n' 's/^(    return shell) \+ \w+$/$1/m' "$YAML_LIT"; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q '.github/workflows/offender.yml' "$WORK/err" && grep -q 'no longer carries' "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML M2a: rule_e_files() reverted to shell-only -> the listed workflow reads 'no longer carries' (RED)"
  else
    fail "Rule E YAML M2a: shell-only discovery mutant should report rc=1 naming the workflow, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
else
  fail "Rule E YAML M2a: could not build the mutated sandbox (mutation did not land?)"
fi
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n' 's/return rule_e_files\(\)/return all_shell_files()/' "$YAML_LIT"; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q '.github/workflows/offender.yml' "$WORK/err" && grep -q 'no longer carries' "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML M2b: targets_from_args() no longer dispatches the YAML arm -> RED"
  else
    fail "Rule E YAML M2b: dropped-dispatch mutant should report rc=1 naming the workflow, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
else
  fail "Rule E YAML M2b: could not build the mutated sandbox (mutation did not land?)"
fi

# The `.yaml` spelling: GitHub accepts it, the tree has none yet, so a dead pathspec would
# never be noticed on the real corpus. Listed with its count it is GREEN; with the pathspec
# removed it reads 'no longer carries'.
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n.github/workflows/offender2.yaml\t1\n' '' "$YAML_LIT" "$YAML_LIT"; then
  rc="$(sbx_run)"
  if [ "$rc" = "0" ] && grep -q '3 site(s)' "$WORK/out" && sbx_clean_run; then
    pass "Rule E YAML: a .github/**/*.yaml workflow is discovered and scanned (listed with its count -> GREEN)"
  else
    fail "Rule E YAML: .yaml sandbox expected rc=0 and '3 site(s)', got rc=$rc: $(head -c 300 "$WORK/err") $(head -c 200 "$WORK/out")"
  fi
fi
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n.github/workflows/offender2.yaml\t1\n' 's/"\.github\/\*\*\/\*\.yaml", //' "$YAML_LIT" "$YAML_LIT"; then
  rc="$(sbx_run)"
  if [ "$rc" = "1" ] && grep -q 'offender2.yaml' "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML M2c: the .yaml pathspec removed -> the listed .yaml workflow reads RED"
  else
    fail "Rule E YAML M2c: dropped .yaml pathspec should report rc=1 naming offender2.yaml, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
else
  fail "Rule E YAML M2c: could not build the mutated sandbox (mutation did not land?)"
fi

# D1: `--changed` stays *.sh-only. Touching a baselined workflow must NOT pull it into the
# `--changed` scan (an unrelated edit to a big workflow would otherwise force its full
# remediation). Commit, touch ONLY the YAML, diff against the parent.
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n' '' "$YAML_LIT"; then
  "${SBX_GIT[@]}" -C "$SBX" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -qm base >/dev/null 2>&1
  printf '# touched\n' >> "$SBX/.github/workflows/offender.yml"
  "${SBX_GIT[@]}" -C "$SBX" add -A >/dev/null 2>&1
  "${SBX_GIT[@]}" -C "$SBX" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -qm touch >/dev/null 2>&1
  rc="$(sbx_run --changed --base HEAD~1)"
  if [ "$rc" = "0" ] && ! grep -qE "$E_MSG_RE" "$WORK/out" "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML: --changed stays shell-only (a touched baselined workflow is not scanned)"
  else
    fail "Rule E YAML: --changed must not scan YAML, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
fi
# ...and its mutant: a `--changed` that DOES pull touched YAML in reads the baselined workflow
# (the explicit-path/--changed bypass of baseline E) and goes RED.
if sbx_repo 'scripts/offender.sh\t1\n.github/workflows/offender.yml\t1\n' 's/c\.endswith\("\.sh"\)/c.endswith((".sh", ".yml"))/' "$YAML_LIT"; then
  "${SBX_GIT[@]}" -C "$SBX" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -qm base >/dev/null 2>&1
  printf '# touched\n' >> "$SBX/.github/workflows/offender.yml"
  "${SBX_GIT[@]}" -C "$SBX" add -A >/dev/null 2>&1
  "${SBX_GIT[@]}" -C "$SBX" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -qm touch >/dev/null 2>&1
  rc="$(sbx_run --changed --base HEAD~1)"
  if [ "$rc" = "1" ] && grep -qE "$E_MSG_RE" "$WORK/err" && sbx_clean_run; then
    pass "Rule E YAML M-changed: a --changed that includes YAML reports the touched workflow (RED), so the shell-only row bites"
  else
    fail "Rule E YAML M-changed: the YAML-including --changed mutant should report rc=1, got rc=$rc: $(head -c 300 "$WORK/err")"
  fi
else
  fail "Rule E YAML M-changed: could not build the mutated sandbox (mutation did not land?)"
fi

# --- Rule E widened (#9597 S1): mutation rows -----------------------------------------
# Vocabulary. Legacy narrowing is written without backslashes so it survives the perl
# replacement text: `authorization *: *bearer` is the old E_BEARER.
LEGACY='re.compile("authorization *: *bearer", re.I)'
mutate_row 'V-M1 vocabulary narrowed back to Authorization: Bearer (every non-Bearer site goes unseen)' \
  's/^E_CREDENTIAL = re\.compile\(.*$/E_CREDENTIAL = re.compile(r"authorization\\s*:\\s*bearer", re.I)/m' \
  "$FIX/violation-argv-cred-alternates.sh" 1 0 0
mutate_row 'V-S1 ONLY the held-name capture re-narrowed to the legacy constant' \
  "s/(if m and )E_CREDENTIAL(\\.search\\(m\\.group\\(2\\)\\))/\${1}$LEGACY\${2}/" \
  "$FIX/violation-argv-cred-held.sh" 1 0 0
mutate_row 'V-S2 ONLY the array capture re-narrowed to the legacy constant' \
  "s/(if not hv\\.startswith\\(\"\\@\"\\) and \\()E_CREDENTIAL(\\.search\\(hv\\))/\${1}$LEGACY\${2}/" \
  "$FIX/violation-argv-cred-array-late.sh" 1 0 0
mutate_row 'V-S3 ONLY the _e_scan header branch re-narrowed to the legacy constant' \
  "s/(elif )E_CREDENTIAL(\\.search\\(hv\\) or \\(held_re)/\${1}$LEGACY\${2}/" \
  "$FIX/violation-argv-cred-literal.sh" 1 0 0
mutate_row 'V-S4 ONLY the call-level bearer_in_call re-narrowed to the legacy constant' \
  "s/(bearer_in_call = bearer_argv or bool\\()E_CREDENTIAL(\\.search\\(cmd\\))/\${1}$LEGACY\${2}/" \
  "$FIX/violation-argv-cred-second-credential.sh" 1 0 0
mutate_row 'V-S5 ONLY the wrapper-site bearer_ctx re-narrowed to the legacy constant' \
  "s/(bearer_ctx = bearer_ctx or bool\\()E_CREDENTIAL(\\.search\\(r\\[\"cmd\"\\]\\))/\${1}$LEGACY\${2}/" \
  "$FIX/violation-argv-cred-second-wrapper.sh" 1 0 0

# One alternate deleted at a time, over the alternates DERIVED from the constant's own source
# (a hand-copied list would survive someone adding or dropping an alternate). The fixture
# holds one site per alternate, so each mutant must keep rc 1 and print exactly N-1 messages.
_nalt="$(awk '/^E_CREDENTIAL_HEADERS = \(/{f=1;next} f&&/^\)/{f=0} f' "$LINT" | grep -c .)"
if [ "$_nalt" -lt 5 ]; then
  fail "V-ALT: derived only $_nalt alternates from E_CREDENTIAL_HEADERS, anti-vacuity floor is 5"
else
  pass "V-ALT: $_nalt alternates derived from E_CREDENTIAL_HEADERS (anti-vacuity floor 5)"
fi
for ((_k = 1; _k <= _nalt; _k++)); do
  _expr="s/(^E_CREDENTIAL_HEADERS = \\(\\n(?:[^\\n]*\\n){$((_k - 1))})[^\\n]*\\n/\${1}    r\"(?!x)x\",\\n/m"
  mutate_row "V-ALT-$_k alternate #$_k of $_nalt deleted from E_CREDENTIAL_HEADERS" \
    "$_expr" "$FIX/violation-argv-cred-alternates.sh" 1 1 "$((_nalt - 1))"
done
unset _k _expr

# Array declaration (matrix row 4): the discord-setup.sh miss. Reverting the shared prefix to
# `local -a` / `declare -a` / `readonly -a` must redden BOTH the Rule E fixture (finding lost)
# and the Rule D must-PASS (false finding: --disable no longer first).
_decl_old='s/^_ARRAY_DECL_PREFIX = .*$/_ARRAY_DECL_PREFIX = r"^\\s*(?:local\\s+-a\\s+|declare\\s+-a\\s+|readonly\\s+-a\\s+)?"/m'
mutate_row 'V-D1 array-declaration prefix reverted to `local -a` only: the Authorization: Bot array finding is lost' \
  "$_decl_old" "$FIX/violation-argv-cred-local-array.sh" 1 0 0
mutate_row 'V-D2 array-declaration prefix reverted to `local -a` only: Rule D reads a false finding on a compliant plain `local x=(` array' \
  "$_decl_old" "$FIX/compliant-ruled-local-array.sh" 0 1 0
unset _decl_old

# YAML extractor (matrix rows 5 to 7).
# 5: a raw-line feeder for workflows. One mutant per shape, each shape in its OWN fixture
# (a combined fixture would only change the count while rc stays 1).
_raw='s/if _feeds_raw_lines\(path, text\):/if True:/'
mutate_row 'Y-M5a workflows fed as raw lines: a FOLDED scalar is missed' "$_raw" "$FIX/violation-yaml-folded.yml" 1 0 0
mutate_row 'Y-M5b workflows fed as raw lines: an inline single-quoted run: is missed' "$_raw" "$FIX/violation-yaml-inline-quoted.yml" 1 0 0
mutate_row 'Y-M5c workflows fed as raw lines: an inline double-quoted-escaped run: is missed' "$_raw" "$FIX/violation-yaml-inline-escaped.yml" 1 0 0
# ...and the converse: a cloud-init file pushed through PyYAML does not parse (rc 2, not 1).
mutate_row 'Y-M5d cloud-init routed through PyYAML: the templated file is unparseable (rc 1 -> 2)' \
  's/if _feeds_raw_lines\(path, text\):/if False:/' "$FIX/cloud-init-violation.yml" 1 2
unset _raw
# 6: a composite-action step skipped, and a step with no shell: key skipped.
mutate_row 'Y-M6a extractor skips `runs` (a composite-action step goes unseen)' \
  's/(\n(\s+)for key_node, val_node in node\.value:\n)/$1$2    if getattr(key_node, "value", None) == "runs":\n$2        continue\n/' \
  "$FIX/violation-yaml-composite.yml" 1 0 0
mutate_row 'Y-M6b a step with no shell: key is treated as non-bash (the default flips from bash)' \
  's/(shell = [^\n]* or )"bash"/${1}"python"/' \
  "$FIX/violation-yaml-noshell.yml" 1 0 0
mutate_row 'Y-M6c defaults.run.shell no longer honoured (a python-default step is scanned as bash)' \
  's/^(\s+)default_shell = _yaml_default_shell\(node\) or default_shell$/${1}default_shell = None/m' \
  "$FIX/compliant-yaml-defaults-nonbash.yml" 0 1 1
# 7: an unparseable YAML file skipped, or silently scanned as raw lines.
mutate_row 'Y-M7a an unparseable YAML file is skipped (rc 2 -> 0)' \
  's/(except yaml\.YAMLError as exc:\n(?:[^\n]*\n)*?\s*)return 2, \[\]/${1}return 0, []/' \
  "$FIX/violation-yaml-unparseable.yml" 2 0
mutate_row 'Y-M7b an unparseable YAML file silently falls back to raw lines (rc 2 -> 1)' \
  's/(except yaml\.YAMLError as exc:\n(?:[^\n]*\n)*?\s*)return 2, \[\]/${1}return _check_yaml_raw(rel, text)/' \
  "$FIX/violation-yaml-unparseable.yml" 2 1 1

# 7c/7d need PyYAML hidden or broken, so they run a mutated copy through rc_env.
mutant_copy() { # <perl-expr> -> $WORK/mut2.py, rc 1 when the mutation did not land
  cp "$LINT" "$WORK/mut2.py" || return 1
  perl -0pi -e "$1" "$WORK/mut2.py"
  ! diff -q "$LINT" "$WORK/mut2.py" >/dev/null 2>&1
}
if mutant_copy 's/(except ImportError as exc:\n(?:[^\n]*\n)*?\s*)sys\.exit\(2\)/${1}return 0, []/'; then
  rc="$(rc_env "$NOYAML" "$WORK/mut2.py" "$FIX/violation-yaml-literal.yml")"
  [ "$rc" = "0" ] && pass "Y-M7c a missing PyYAML falling through (rc 2 -> 0) is caught by the hidden-PyYAML row" \
    || fail "Y-M7c: missing-PyYAML fall-through mutant should read rc 0, got rc=$rc"
else
  fail "Y-M7c: mutation did not land"
fi
if mutant_copy 's/except yaml\.YAMLError as exc:/except Exception as exc:/'; then
  rc="$(rc_env "$BROKENYAML" "$WORK/mut2.py" "$FIX/violation-yaml-literal.yml")"
  if [ "$rc" = "2" ] && grep -q 'did not parse' "$WORK/err"; then
    pass "Y-M7d a blanket except Exception (a broken loader reported as an unparseable file) is caught by the broken-loader row"
  else
    fail "Y-M7d: blanket-except mutant should exit 2 with 'did not parse', got rc=$rc"
  fi
else
  fail "Y-M7d: mutation did not land"
fi


# --- Guard 2 (#7946): Rule C empty-predicate hardening ------------------------
# A single-credential file whose only `${VAR:+x}` limb was deleted leaves `[ -n "" ]`,
# which Rule C's `":+" not in window` branch used to read as an UNCONDITIONAL refusal --
# the strongest possible guard -- when it is one that can never fire.
rc="$(rc_of "$LINT" "$FIX/violation-empty-predicate-double.sh")"
[ "$rc" = "1" ] && pass "G2-M1 empty predicate [ -n \"\" ] is reported" \
  || fail "G2-M1 empty predicate [ -n \"\" ] should report rc=1, got rc=$rc"
python3 "$LINT" "$FIX/violation-empty-predicate-double.sh" >"$WORK/g2msg" 2>&1
grep -q 'violation-empty-predicate-double.sh:6:' "$WORK/g2msg" \
  && pass "G2-M1 cites the preamble line (:6)" \
  || fail "G2-M1 did not cite the preamble line: $(head -3 "$WORK/g2msg")"
grep -q 'can never fire' "$WORK/g2msg" && grep -q ':+x' "$WORK/g2msg" \
  && pass "G2-M1 message names the restore-or-refuse-unconditionally remedy" \
  || fail "G2-M1 message lacks the remedy text: $(head -5 "$WORK/g2msg")"

# G2-M2: the other syntax + quote style, in the SAME run after a compliant file -- both the
# `[[ -n '' ]]` form and "the walk does not stop at the first member".
rc="$(rc_of "$LINT" "$FIX/compliant-canonical.sh" "$FIX/violation-empty-predicate-double.sh" "$FIX/violation-empty-predicate-single.sh")"
[ "$rc" = "1" ] \
  && reports 'violation-empty-predicate-double.sh' && reports 'violation-empty-predicate-single.sh' \
  && pass "G2-M2 both quote styles reported in one run, after a compliant file" \
  || fail "G2-M2 expected rc=1 naming both fixtures, got rc=$rc: $(cat "$WORK/out" "$WORK/err" | head -6)"
reports 'compliant-canonical.sh' \
  && fail "G2-M2 the compliant file must not be named" \
  || pass "G2-M2 the compliant file is not named"

# G2-M3: the dispatch row -- a sandbox copy with the hardening's predicate removed lets M1
# through (1 -> 0). The regex is the hardening's own; degenerating it to never-match is the
# "hardening deleted" mutant without touching the surrounding early return.
mutate_row 'G2-M3 Rule C: empty-predicate hardening removed' \
  's/^EMPTY_PREDICATE = re\.compile\(\n.*?\n\)\n/EMPTY_PREDICATE = re.compile(r"(?!x)x")\n/ms' \
  "$FIX/violation-empty-predicate-double.sh" 1 0

# G2-H2: must-PASS, not the canonical -- the genuinely unconditional refusal shares the early
# return the hardening sits in front of; it must stay accepted.
rc="$(rc_of "$LINT" "$FIX/compliant-indirect-unconditional.sh")"
[ "$rc" = "0" ] && pass "G2-H2 a genuinely unconditional refusal still passes" \
  || fail "G2-H2 unconditional refusal should report rc=0, got rc=$rc"

# G2-M4: the other three spellings of the empty predicate -- `test -n ""`, `[ ! -z "" ]` and
# the bare `[ "" ]` -- each reported, in one run after a compliant file.
rc="$(rc_of "$LINT" "$FIX/compliant-canonical.sh" "$FIX/violation-empty-predicate-test.sh" "$FIX/violation-empty-predicate-not-z.sh" "$FIX/violation-empty-predicate-bare.sh")"
[ "$rc" = "1" ] \
  && reports 'violation-empty-predicate-test.sh' && reports 'violation-empty-predicate-not-z.sh' && reports 'violation-empty-predicate-bare.sh' \
  && pass "G2-M4 test/! -z/bare spellings of the empty predicate all reported" \
  || fail "G2-M4 expected rc=1 naming all three spellings, got rc=$rc: $(cat "$WORK/out" "$WORK/err" | head -8)"

# G2-M5: the deleted-name case. The file's only literal credential name went in the same edit
# that emptied the predicate, so `referenced` is EMPTY; a check placed after the
# `not referenced` return never runs. The fixture is in scope via its indirect read.
rc="$(rc_of "$LINT" "$FIX/violation-empty-predicate-indirect.sh")"
[ "$rc" = "1" ] && pass "G2-M5 empty predicate with NO literal credential name is still reported" \
  || fail "G2-M5 expected rc=1 on the indirect fixture, got rc=$rc"
# Dispatch: a copy with the `not referenced` return hoisted ABOVE the Guard 2 block lets it through.
mutate_row 'G2-M5 Rule C: not-referenced return hoisted above the empty-predicate check' \
  's/(    # Guard 2 \(#7946\): predicates that can NEVER fire)/    if not referenced:\n        return out\n\n$1/' \
  "$FIX/violation-empty-predicate-indirect.sh" 1 0

# G2-M6: an EMPTY alternate -- `${VAR:+}` -- expands to "" either way; reported by name.
rc="$(rc_of "$LINT" "$FIX/violation-empty-alternate.sh")"
[ "$rc" = "1" ] && grep -q 'alternate is EMPTY' "$WORK/out" "$WORK/err" \
  && pass "G2-M6 \${VAR:+} (empty alternate) is reported as never firing" \
  || fail "G2-M6 expected rc=1 with the empty-alternate message, got rc=$rc: $(cat "$WORK/out" "$WORK/err" | head -4)"

# G2-M7: the INVERTED guard -- `-z "${VAR:+x}"` refuses only while the credential is empty.
# Baseline reports it; a copy with INVERTED_GUARD degenerated reads the `:+x` as a guard and
# passes it (1 -> 0), so the regex is the mechanism.
rc="$(rc_of "$LINT" "$FIX/violation-inverted-guard.sh")"
[ "$rc" = "1" ] && grep -q 'INVERTED' "$WORK/out" "$WORK/err" \
  && pass "G2-M7 -z \"\${VAR:+x}\" (inverted guard) is reported" \
  || fail "G2-M7 expected rc=1 with the INVERTED message, got rc=$rc: $(cat "$WORK/out" "$WORK/err" | head -4)"
# G2-H3: the correct guard under an OUTER negation, or in `||` form, is NOT inverted -- both
# refuse when the credential is SET. Reported by the ship-phase advisor consult as a false
# positive of the first INVERTED_GUARD; a control fixture per spelling.
rc="$(rc_of "$LINT" "$FIX/compliant-negated-z.sh" "$FIX/compliant-z-or-exit.sh")"
[ "$rc" = "0" ] && pass "G2-H3 ! [ -z \"\${VAR:+x}\" ] and [ -z … ] || exit are accepted (not inverted)" \
  || fail "G2-H3 negated/|| forms of -z should report rc=0, got rc=$rc: $(cat "$WORK/out" "$WORK/err" | head -4)"
mutate_row 'G2-M7 Rule C: inverted-guard detection removed' \
  's/^INVERTED_GUARD = re\.compile\(.*\)$/INVERTED_GUARD = re.compile(r"(?!x)x")/m' \
  "$FIX/violation-inverted-guard.sh" 1 0

# G2-M8: a `${VAR:+x}` that survives only in a COMMENT inside the arm is not a guard. The
# fixture guards one of two credentials and carries the other's limb commented out; the
# comment-keeping window (the mutant) counts it and passes the file (1 -> 0).
rc="$(rc_of "$LINT" "$FIX/violation-guard-in-comment.sh")"
[ "$rc" = "1" ] && grep -q 'Unguarded: BETTERSTACK_API_TOKEN' "$WORK/out" "$WORK/err" \
  && pass "G2-M8 a commented-out limb does not count as a guard (BETTERSTACK_API_TOKEN unguarded)" \
  || fail "G2-M8 expected rc=1 naming BETTERSTACK_API_TOKEN as unguarded, got rc=$rc: $(cat "$WORK/out" "$WORK/err" | head -4)"
mutate_row 'G2-M8 Rule C: arm window keeps comment lines' \
  's/line = strip_comment\(raw\)\n        out\.append\(line\)/line = raw\n        out.append(line)/' \
  "$FIX/violation-guard-in-comment.sh" 1 0

# --- H1: the floor must fail via a DIRECT exit, not through the helpers -------
# H1: assert the floor by DRIVING it, not by grepping for its name -- the old
# check searched for a literal its own grep line contains, so deleting the floor
# block entirely left it passing. An outside witness is the only real test.
_h1="$WORK/h1.sh"
sed 's/^MIN_ASSERTIONS=[0-9]*$/MIN_ASSERTIONS=99999/' "${BASH_SOURCE[0]}" > "$_h1"
if [ -s "$_h1" ] && ! diff -q "$_h1" "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
  # The probe file goes in $WORK (mktemp'd, trap-cleaned), NOT into the tracked
  # scripts/ dir under a fixed name: an interrupted run used to leave an untracked
  # .sh behind, and two concurrent runs in one checkout raced on that path.
  # Runs from scripts/ because the probe resolves REPO_ROOT and its fixtures
  # relative to that CWD -- running it from $WORK made it exit 2 during setup,
  # which is NOT the floor firing and would have made this row assert the wrong
  # thing. Unique filename rather than the old fixed .h1probe.tmp.sh: that name
  # left an untracked .sh in the tracked tree on an interrupted run, and raced
  # between two concurrent runs in one checkout.
  _h1err="$WORK/h1.err"
  _h1probe="$(mktemp "$REPO_ROOT/scripts/.h1probe.XXXXXXXX.sh")"
  cp "$_h1" "$_h1probe"
  ( cd "$REPO_ROOT/scripts" && bash "$_h1probe" >/dev/null 2>"$_h1err" )
  _h1rc=$?
  rm -f "$_h1probe"
  # rc alone is NOT sufficient (#7898 review): the inner probe always emits at
  # least one FAIL by construction -- its own H1 block sees a source already at
  # 99999, diff reports identical, and it takes the "could not build" else branch
  # -- so it exits 1 whether or not the floor exists. Measured: `if false; then`
  # on the floor predicate left this row PASSing. Assert the floor's own FATAL
  # text, which only the floor can emit.
  if [ "$_h1rc" = "1" ] && grep -q 'assertions ran; floor is' "$_h1err"; then
    pass "H1 the assertion floor actually bites (unreachable floor -> its own FATAL + exit 1)"
  else
    fail "H1 floor did not bite: rc=$_h1rc, floor FATAL text $(grep -c 'assertions ran; floor is' "$_h1err" 2>/dev/null || echo 0) time(s); expected rc 1 with the FATAL"
  fi
else
  fail "H1 could not build the floor probe -- the assertion would be vacuous"
fi

# --- verdict -----------------------------------------------------------------
# The token-shape guard `_bearer_ok` is copied inline into every converted script (host-deployed and
# plugin-shipped scripts cannot source a repo-relative lib), so nothing but THIS row stops the copies
# drifting apart: every definition, including the prefixed variants of sourced libs, must carry the
# one canonical body, and the population must not silently collapse.
_CANON_BODY='{ local LC_ALL=C; case "${1:-}" in '"''"'|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }'
_copies="$(git grep -hE '_bearer_ok\(\) *\{' -- '*.sh' ':!*.test.sh' ':!tests/scripts/test-*' ':!scripts/fixtures' | sed -E 's/^[[:space:]]*[A-Za-z0-9_]*_bearer_ok\(\) *//')"
_n_copies="$(printf '%s\n' "$_copies" | grep -c . || true)"
_n_off="$(printf '%s\n' "$_copies" | grep -vcxF -- "$_CANON_BODY" || true)"
if [ "$_n_copies" -ge 40 ] && [ "$_n_off" = "0" ]; then
  pass "token-shape guard: all $_n_copies inline copies of _bearer_ok carry the one canonical body"
else
  fail "token-shape guard drift: copies=$_n_copies off-canonical=$_n_off (expected >= 40 copies, 0 off-canonical)"
fi

printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"

# Absolute floor, recorded from a MEASURED green run (never from expectation --
# that was wrong three times in sibling PR #7806). Reported with printf + exit 1
# directly, never via fail(), so one edit cannot disarm both.
#
# Re-measured at 61 (#7873, Guard 1 row H1). It was 43 against a suite that had
# grown to 61 rows, and an 18-row slack meant DELETING a must-PASS row was
# invisible: removing the `compliant-ruled-pinned-destination.sh` must-pass
# assertion was measured GREEN at 60/0. That is the failure H1 names -- a suite
# whose only pin fixture is a violation cannot detect a classifier that rejects
# everything, and here the loss of the positive direction was not even reported.
# A floor at the measured count makes any row deletion RED. It is a LOWER bound,
# so adding rows never trips it; re-measure and raise it when rows are added.
# Re-measured at 198 (#9597 S1: the Rule E credential vocabulary and YAML-arm rows, the extractor, discovery, harness and
# mutation rows added on top of the 119 recorded for the original Rule E rows).
MIN_ASSERTIONS=198
if [ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' \
    "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[ "$FAIL" -eq 0 ] || exit 1
