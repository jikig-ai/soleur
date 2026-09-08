#!/usr/bin/env bash
# Anti-vacuity floor for preflight Check 10's regression suites (#7393).
#
# WHY THIS LIVES OUTSIDE THE SUITE IT GUARDS. Every anti-vacuity mechanism inside
# a bun/vitest file — a per-assertion count, a non-vacuity anchor, a mutation
# battery — is defeated by the same move: not running the assertions. Measured on
# this branch:
#
#   perl -pi -e 's/^(\s*)test\(/$1test.skip(/' <both suites>
#   => "0 pass, 110 skip, 0 fail", exit code 0
#
# CI reads the exit code, so a suite that asserts nothing is indistinguishable
# from a suite that passed. Check 10 is a security boundary (it executes
# attacker-authorable commands on the operator's workstation), so "the tests
# silently stopped running" is not an acceptable failure mode.
#
# A floor written INSIDE the suite cannot close this: the guard would itself be
# skippable. Hence a separate registered gate — `plugins/soleur/test/*.test.sh`
# is auto-globbed by scripts/test-all.sh (see its `for f in` loop), so this runs
# in the `scripts` shard whether or not the bun suites execute at all.
#
# The floor is a FLOOR, never an equality: the counts grow as coverage is added,
# and `-eq` would turn every new test into a spurious failure. Derived from a
# green run, and it ratchets upward only.
set -uo pipefail

# /tmp is a machine-global RAM-backed tmpfs shared by every parallel worktree, and
# this repo's runners already banner when it drops below their headroom floor
# (observed at 143MB against a 1024MB floor while writing this). Default TMPDIR
# the same way scripts/test-all.sh does, so a DIRECT invocation of this gate --
# the documented inner loop -- does not add to that pressure.
export TMPDIR="${TMPDIR:-/var/tmp}"

cd "$(git rev-parse --show-toplevel)" || exit 1

SUITES=(
  plugins/soleur/test/preflight-discoverability-test.test.ts
  plugins/soleur/test/observability-schema-parity.test.ts
  plugins/soleur/test/fullsuite-merge-gate.test.ts
)

# QUANTITY floors are a secondary tripwire only. On their own they were defeated
# three ways at 9 tests / 97 assertions of slack: deleting two whole describes
# stayed green; neutering seven tests with an early `return` plus padding kept the
# test count identical and RAISED the assertion count above the floor; and a
# line-broken `test\n.todo(` evaded the grep while bun counts todo separately from
# skip. Quantity measures the size of the input, not the work performed -- the
# same vacuity shape this gate exists to prevent, one level up.
#
# The primary control is now the NAMED-TEST MANIFEST: a committed list of every
# test name, asserted as a subset of what the sources declare. A deleted describe,
# a renamed test, or a `.todo` all become explicit diff lines.
MANIFEST="plugins/soleur/test/fixtures/check10-test-manifest.txt"
# Ratcheted to the MEASURED green value, with no slack. The previous 113/460 sat
# 7 tests and 37 assertions below the real counts, and that gap was not padding —
# it was the budget an attacker spends: gutting a manifest-listed test's BODY to
# `expect(true).toBe(true)` (name intact, so the manifest is satisfied) and
# deleting the 6 generated fold-indicator tests both landed inside it while all
# every check stayed green. These suites have no environment-conditional
# branching, so the counts are deterministic and an exact floor is safe.
# Ratchet both UPWARD when coverage is added; never widen the gap.
# All THREE floors live here, together, under one contract: absolute, ratcheted to
# the measured value, upward only. MIN_MANIFEST_LINES used to sit buried inside the
# manifest block's else-branch, which is how a reader misses that it carries the
# same rule. An EMPTY manifest previously passed vacuously as
# "[ok] all 0 manifest tests still declared", so this floor is what makes the
# primary identity control non-vacuous.
MIN_TESTS=131
MIN_ASSERTIONS=537
MIN_MANIFEST_LINES=126

PASS=0
FAIL=0
cases=0
# `cases` is incremented at the CALL SITE, never inside pass()/fail(). That placement is the
# whole substance of the conservation check at the bottom of this file: a counter that moves
# inside both verdict helpers moves WITH the verdict, so stubbing fail() to a no-op drops the
# row and its count together and `PASS+FAIL == cases` still holds. It is also what makes the
# own-dispatch floor below independent of the helpers it exists to police — a floor read off
# PASS+FAIL is read off the suspect.
#
# Never increment inside `$( )` — a subshell discards it.
pass() { PASS=$((PASS + 1)); printf '  [ok] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1"; }

# ONE cleanup, ONE trap, registered before ANY tempfile is allocated. Bash EXIT
# traps are not additive: the previous form registered `rm -f $DECLARED` in the
# manifest block and then had it silently REPLACED by a later `trap cleanup EXIT`,
# so $DECLARED leaked on every single run. Measured in the real worktree: 21
# orphaned check10-declared.*.txt in TMPDIR, 0 orphaned logs — the exact tmpdir
# pressure this file's own ADR-129 commentary exists to prevent, caused by the
# ownership mechanism it was citing. Both names are declared empty up front so
# the handler is safe to fire at any point.
DECLARED=""
LOG=""
KEEP_LOG=0
cleanup() {
  [[ -n "$DECLARED" ]] && rm -f "$DECLARED"
  if [[ "$KEEP_LOG" == "1" ]]; then
    [[ -n "$LOG" ]] && echo "  (log retained: $LOG)"
    return 0
  fi
  [[ -n "$LOG" ]] && rm -f "$LOG"
  return 0
}
trap cleanup EXIT

# --- Parser for bun's summary counters (#7466) ------------------------------
# bun writes its summary block with ANSI colour, so a grep anchored at
# `^[[:space:]]*` cannot reach the digits: the line begins with an ESC. The four
# counter greps were anchored and `expect() calls` was not, which is why a
# coloured run reported `pass=0` alongside `expect=539` — one asymmetry, one
# cause. The parse therefore runs over a STRIPPED copy, produced here.
#
# ESC is built with printf, never with the backslash-x escape form. That form is a
# GNU extension; BSD sed matches the literal characters `x1b` instead, so a strip
# written with it silently does nothing on macOS while passing review.
ESC=$(printf '\033')

strip_ansi() {                  # <path> -> stripped text on stdout
  # `[0-?]`, `[ -/]` and `[@-~]` are ECMA-48's parameter, intermediate and final
  # byte ranges; the second rule catches every two-byte escape (`ESC 7` DECSC,
  # `ESC ( B` charset). A narrower SGR-only class is NOT enough — measured, a
  # colon-separated SGR, a DECSC and a charset designator each survive it, and each
  # survivor is then a hard RED on a healthy tree.
  #
  # LC_ALL=C is load-bearing: the byte ranges are locale-dependent without it.
  # The `|` delimiter avoids the `/`-inside-bracket trap — an escaped `/` in a
  # bracket expression was measured turning the class into 0x20-0x5C and eating
  # ` 122 p`.
  # `tr` TRANSLATES CR to newline, never deletes it: deleting a CR concatenates the
  # overwritten text onto the summary line and the anchor fails again.
  #
  # Out of scope, stated rather than implied: OSC (`ESC ] ... BEL`), which bun does
  # not emit, and a `\e[1G` rewrite whose stale text precedes the escape — neither
  # is recoverable by stripping alone.
  LC_ALL=C tr '\r' '\n' < "$1" \
    | LC_ALL=C sed -e "s|${ESC}\[[0-?]*[ -/]*[@-~]||g" -e "s|${ESC}[ -/]*[0-~]||g"
}

# parse_bun_summary is the SOLE PRODUCER of counter values: it echoes them and one
# `read` binds them, so no counter can enter this gate by another path. It assigns
# nothing in the caller's scope — a function that wrote back would be silently lost
# when reached through a pipe (a subshell), and the loss mimics the very bug this
# fixes. Its internals are named `plain`/`v`/`out`, never `n_*`.
#
# It reads its input EXACTLY ONCE. Fixtures arrive as process substitutions, which
# are PIPES: measured, a parser stripping once per counter returns `122 - - - -` for
# every fixture while the live path (a real, re-readable file) returns all five, so
# the self-checks and the live run would disagree in a way that looks exactly like
# the defect being fixed.
#
# `-` marks an unread field. An empty field would collapse under `read`'s default
# IFS and shift every later field one position left.
parse_bun_summary() {           # <path> -> "pass fail skip todo expect"
  local plain v out
  plain="$(strip_ansi "$1")"
  v="$(grep -oE '^[[:space:]]*([0-9]+) pass' <<<"$plain" | grep -oE '[0-9]+' | tail -1)"
  out="${v:--}"
  v="$(grep -oE '^[[:space:]]*([0-9]+) fail' <<<"$plain" | grep -oE '[0-9]+' | tail -1)"
  out="$out ${v:--}"
  v="$(grep -oE '^[[:space:]]*([0-9]+) skip' <<<"$plain" | grep -oE '[0-9]+' | tail -1)"
  out="$out ${v:--}"
  # bun classifies `todo` SEPARATELY from `skip`, so a suite suppressed via
  # `.todoIf(...)` reported 0 skip and this gate called it "no tests skipped at
  # runtime". Parsing it is what makes the whole suppression family visible by
  # MEASUREMENT rather than by source pattern-matching.
  v="$(grep -oE '^[[:space:]]*([0-9]+) todo' <<<"$plain" | grep -oE '[0-9]+' | tail -1)"
  out="$out ${v:--}"
  # The first stage gains the `^[[:space:]]*` anchor the other four already had —
  # without it a mid-log stack frame quoting `999 expect() calls` is read as the
  # summary. The second stage must stay UNANCHORED: anchoring stage one makes the
  # match carry its leading whitespace, so a `^[0-9]+` second stage matches nothing
  # and a healthy `539 expect() calls` parses EMPTY — a false RED on every green run.
  v="$(grep -oE '^[[:space:]]*([0-9]+) expect\(\) calls' <<<"$plain" | grep -oE '[0-9]+' | tail -1)"
  out="$out ${v:--}"
  printf '%s\n' "$out"
}

# summary_measured is the SOLE decision site for "was this summary read at all".
# `expect` is deliberately NOT an input: bun omits `expect() calls` when the count
# is zero, so requiring it would report the all-skip run — the flagship suppression
# case this gate exists to catch — as an unparseable summary and suppress the
# `coverage silently removed` diagnosis. `pass` and `fail` are the only counters bun
# prints unconditionally.
summary_measured() {            # exit 0 iff $1 and $2 are both integers
  [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]]
}

echo "=== preflight Check 10 suite integrity ==="

# --- 0. Parser self-test ----------------------------------------------------
# Runs BEFORE the live run so a broken parser is NAMED rather than surfacing only as
# a confusing "0 tests passed". It does not short-circuit: fail() records a verdict
# and returns, so the live `bun test` still executes.
declare -F strip_ansi parse_bun_summary summary_measured >/dev/null \
  || { printf '\n[FATAL] parser symbols absent — a missing function would read as a wrong answer.\n' >&2; exit 1; }

# `cases` moves inside these wrappers, unconditionally, BEFORE the pass/fail branch —
# never inside pass()/fail(), which is what keeps the conservation identity at the
# bottom of this file non-tautological.
assert_parse() {                # <label> <expected tuple> <path>
  cases=$((cases + 1))
  local got
  got="$(parse_bun_summary "$3")"
  if [[ "$got" == "$2" ]]; then
    pass "$1"
  else
    fail "$1 — parsed [$got], expected [$2]"
  fi
}

assert_measured() {             # <label> <pass> <fail> <true|false>
  cases=$((cases + 1))
  local got=false
  summary_measured "$2" "$3" && got=true
  if [[ "$got" == "$4" ]]; then
    pass "$1"
  else
    fail "$1 — summary_measured($2, $3) returned $got, expected $4"
  fi
}

# S1 — plain text, deliberately NOT the all-green canonical shape. Its first line is
# the no-over-strip control: a stripper whose bracket class is too wide eats it.
assert_parse "S1 plain summary parses all five counters" "122 3 1 2 514" \
  <(printf '  at foo (/src/a.ts:10:5) expected [1;2] arr[0]a\n 122 pass\n 3 fail\n 1 skip\n 2 todo\n 514 expect() calls\n')

# S2a/S2b — REAL bytes captured from bun 1.3.11 with FORCE_COLOR=1, pasted from
# `cat -v`. Colour placement is VALUE-DEPENDENT, so one coloured fixture cannot
# represent bun's output: a non-zero counter is `^[[0m^[[32m 132 pass^[[0m` (ESC
# first), a zero `pass` is ` 0 pass^[[0m` (space first), and `skip` is
# ` ^[[0m^[[33m2 skip^[[0m` (space, then ESC, then the digits).
assert_parse "S2a coloured non-zero summary parses (real bun 1.3.11 bytes)" "132 0 - - 539" \
  <(printf '%s[0m%s[32m 132 pass%s[0m\n%s[0m%s[2m 0 fail%s[0m\n 539 expect() calls\n' \
      "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC")

# S2b — the all-skip run: the case this gate exists to catch. bun prints NO
# `expect() calls` line at all here (measured: grep -c => 0), which is why
# summary_measured must not require it.
assert_parse "S2b coloured all-skip summary parses (no expect() line at all)" "0 0 2 - -" \
  <(printf ' 0 pass%s[0m\n %s[0m%s[33m2 skip%s[0m\n%s[0m%s[2m 0 fail%s[0m\n' \
      "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC")

# S3 — escapes an SGR-only strip does not reach: a COLON-separated SGR, a two-byte
# DECSC (`ESC 7`, no `[`), and a charset designator (`ESC ( B`). Each one survives a
# narrow strip and is then a hard RED on a healthy tree — the cries-wolf mode that
# gets a gate bypassed.
assert_parse "S3 colon-SGR, DECSC and charset escapes are stripped" "122 3 1 - -" \
  <(printf '%s[38:2:0:255:0m 122 pass%s[0m\n%s7 3 fail\n%s(B 1 skip\n' "$ESC" "$ESC" "$ESC" "$ESC")

# S4 — a decoy: `999 expect() calls` MID-LINE in a stack frame, and a `pass` token
# that is not a counter. Nothing here is a summary block, so nothing may be read.
assert_parse "S4 mid-log decoys are not read as the summary" "- - - - -" \
  <(printf '  at bar (/src/b.ts:1:1) 999 expect() calls\n  running 42 pass-through checks\n')

# V1-V4 — the predicate. V1 cannot distinguish which member was dropped (it is false
# under either single-member edit); V2 is the sole detector for `fail` and V3 the sole
# detector for `pass`, so the pair NAMES the omission. V4 is the true case: without it
# a predicate stuck at false would score green.
assert_measured "V1 neither counter read is UNMEASURED" "-" "-" false
assert_measured "V2 pass read, fail unread is UNMEASURED" "122" "-" false
assert_measured "V3 fail read, pass unread is UNMEASURED" "-" "0" false
assert_measured "V4 both counters read is MEASURED" "122" "0" true

# N2 — instrument self-test. Every check above is scored by one comparator; a
# comparator stubbed to always call pass() would leave this whole section green and
# the conservation identity intact (a stub still records one verdict per counted
# check). So drive it once with an expectation that MUST fail and require FAIL to
# move by exactly one. Its output is discarded and its counters are restored, so the
# probe records no verdict of its own — the row below is the verdict.
_pb=$PASS; _fb=$FAIL; _cb=$cases
assert_parse "instrument probe (its FAIL is expected and discarded)" "9 9 9 9 9" \
  <(printf ' 1 pass\n 0 fail\n') >/dev/null
_fd=$((FAIL - _fb)); _pd=$((PASS - _pb))
PASS=$_pb; FAIL=$_fb; cases=$_cb
cases=$((cases + 1))
if [[ "$_fd" -eq 1 && "$_pd" -eq 0 ]]; then
  pass "N2 instrument self-test: a wrong expectation moves FAIL by exactly 1"
else
  fail "N2 instrument self-test: a wrong expectation moved FAIL by $_fd and PASS by $_pd (expected 1 and 0) — the comparator is not scoring"
fi

# --- 1. No suppressed tests -------------------------------------------------
# `.skip`/`.only`/`.todo` silently remove coverage while the runner still exits 0.
for f in "${SUITES[@]}"; do
  if [[ ! -f "$f" ]]; then
    cases=$((cases + 1))
    fail "suite missing: $f"
    continue
  fi
  # Anchor on the call form so prose/comments mentioning ".skip" cannot trip it,
  # and so a future `describe.skip` is caught as well as `test.skip`.
  # Newline-tolerant: `test\n    .todo("…")` is valid JS and evaded a line-anchored
  # grep, while bun classifies `todo` separately from `skip` so the runtime
  # counter could not see it either. Collapse whitespace before matching.
  # The `(skip|only|todo)` + immediate `(` form missed the CONDITIONAL variants:
  # `describe.todoIf(true)("…")` suppressed four whole tests while all seven
  # checks stayed green and this gate printed "no tests skipped at runtime" — bun
  # counts those as `todo`, which the runtime counter below never parsed either.
  # `[A-Za-z]*` admits the If-suffixed forms; the bracket alternative admits
  # `test["todo"](…)`. The trailing `\(` anchor is DELIBERATELY kept so that
  # prose and comments naming `.skip` still cannot trip the gate.
  SUPPRESS_RE='(test|it|describe)[[:space:]]*(\.[[:space:]]*(skip|only|todo|failing)[A-Za-z]*[[:space:]]*\(|\[[[:space:]]*["'"'"'](skip|only|todo|failing)[A-Za-z]*["'"'"'][[:space:]]*\][[:space:]]*\()'
  # One check is about to be decided — counted HERE, outside the verdict helpers.
  cases=$((cases + 1))
  if tr '\n' ' ' < "$f" | grep -qE "$SUPPRESS_RE"; then
    # Braces are required: `$SUPPRESS_RE[` parses as array-index syntax (SC1087).
    tr '\n' ' ' < "$f" | grep -oE "${SUPPRESS_RE}[^)]{0,80}" | head -5
    fail "$f contains a suppressed or exclusive test (see above)"
  else
    pass "$f has no .skip/.only/.todo"
  fi

  # REBINDING GUARD. `test`, `it` and `describe` are ordinary JS bindings, and
  # SUPPRESS_RE anchors on those literal identifiers followed by a call form.
  # `const it = test.failing;` has no `(` after `.failing`, so the pattern misses
  # it entirely — and `.failing` is the ONE member of the suppression family the
  # runtime counters cannot see: bun scores a failing `.failing` test as a PASS
  # (measured: 2 pass / 0 fail), so n_skip and n_todo both stay 0. Measured
  # end-to-end: delete `env -i` from the runtime of record, alias one test to the
  # rebound `it`, and this gate reported a full green with pass=121.
  # Adds no expect() calls, so MIN_ASSERTIONS is unaffected.
  REBIND_RE='(^|[;{}[:space:]])(const|let|var|function)[[:space:]]+(test|it|describe)([[:space:]]|=|;|\()'
  cases=$((cases + 1))
  if tr '\n' ' ' < "$f" | grep -qE "$REBIND_RE"; then
    tr '\n' ' ' < "$f" | grep -oE "${REBIND_RE}[^;]{0,60}" | head -5
    fail "$f REBINDS test/it/describe — the source-pattern gate can be aliased around"
  else
    pass "$f does not rebind test/it/describe"
  fi
done

# --- 1b. Named-test manifest ------------------------------------------------
# Identity, not quantity. Every name in the committed manifest must still be
# declared by the sources; a deletion or rename is then a diff line rather than a
# silent count change absorbed by the floor's slack.
if [[ ! -f "$MANIFEST" ]]; then
  cases=$((cases + 1))
  fail "manifest missing at $MANIFEST"
else
  DECLARED="$(mktemp -t check10-declared.XXXXXXXX.txt)"
  # Collation must be PINNED and IDENTICAL on both sides. `comm` compares with
  # strcoll only, while GNU `sort` applies a last-resort byte tie-break, so an
  # unpinned pipeline can hand `comm` input it considers unsorted: measured, that
  # emits "file N is not in sorted order", EXITS 0, and prints a wall of spurious
  # `missing:` lines under LC_ALL=C (a common CI default). Loud rather than
  # silent, but it leaves the primary control one locale change from being
  # disabled-by-noise. The manifest is committed in C collation to match.
  #
  # Backtick-named declarations are extracted too. The double-quote-only form was
  # structurally blind to `test(\`${id} …\`)`, leaving 6 generated tests (120
  # runtime vs 114 manifest) outside the "identity, not quantity" guarantee — and
  # deleting all 5 stayed green inside MIN_TESTS' slack. The literal source text
  # is a stable identity for them even though the runtime name interpolates.
  { grep -hoE '^[[:space:]]*(test|it)\([[:space:]]*"[^"]+"' "${SUITES[@]}" \
      | sed -E 's/^[[:space:]]*(test|it)\([[:space:]]*"//; s/"$//'
    # shellcheck disable=SC2016  # backticks are regex literals here; expansion is exactly what we do NOT want
    grep -hoE '^[[:space:]]*(test|it)\([[:space:]]*`[^`]+`' "${SUITES[@]}" \
      | sed -E 's/^[[:space:]]*(test|it)\([[:space:]]*`//; s/`$//'
  } | LC_ALL=C sort -u > "$DECLARED"

  # An EMPTY manifest made this control pass VACUOUSLY — `comm -23 <empty> …`
  # is empty, so it printed "[ok] all 0 manifest tests still declared" while four
  # sandbox-boundary tests were deleted and a writable --bind /home added. The
  # floor reasoning applied to the test counts was never applied to the manifest
  # itself. Ratchets upward with the manifest.
  # The delta pinned LC_ALL=C on the sort that builds $DECLARED and on comm, but
  # NOT on the committed manifest. Measured: this manifest passes `LC_ALL=C sort -c`
  # and FAILS `en_US.UTF-8 sort -c` at line 30 — so regenerating it the obvious way
  # (`sort -u` in a normal UTF-8 locale) desorts it relative to comm, which then
  # emits 81 spurious "no longer declared" lines accusing a deletion that never
  # happened. A gate that cries wolf gets bypassed, so name the remedy in the message.
  cases=$((cases + 1))
  if ! LC_ALL=C sort -c "$MANIFEST" 2>/dev/null; then
    fail "$MANIFEST is not in C collation — regenerate with: LC_ALL=C sort -u -o $MANIFEST $MANIFEST"
  else
    pass "manifest is in C collation (comm's operands agree)"
  fi
  # Count ENTRIES, not newlines: `wc -l` under-counts a file whose last line lost
  # its terminator, turning a formatting nit into a "gutted?" accusation, and it
  # counts duplicates — so 116 copies of one name would satisfy a raw line floor.
  n_manifest=$(LC_ALL=C sort -u "$MANIFEST" | wc -l | tr -d ' ')
  n_declared=$(wc -l < "$DECLARED" | tr -d ' ')
  # SUT floor, reported DIRECTLY. This measures the system under test (the committed manifest),
  # and a floor that reports by calling fail() increments the same counter the exit status reads
  # — neuter fail() and the floor goes silent along with the rows it exists to backstop. A floor
  # enforced through the suspect cannot witness the suspect. Kept inside this else-branch: it is
  # only meaningful once $MANIFEST is known to exist.
  if [[ "$n_manifest" -lt "$MIN_MANIFEST_LINES" ]]; then
    printf '\n[FATAL] SUT floor: manifest has only %d entries, floor is %d (manifest gutted?).\n' \
      "$n_manifest" "$MIN_MANIFEST_LINES" >&2
    echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
    exit 1
  elif [[ "$n_declared" -eq 0 ]]; then
    cases=$((cases + 1))
    fail "extracted ZERO declared test names — extraction is broken, treating as UNMEASURED"
  else
    cases=$((cases + 1))
    MISSING="$(LC_ALL=C comm -23 "$MANIFEST" "$DECLARED" | head -20)"
    if [[ -n "$MISSING" ]]; then
      printf '%s\n' "$MISSING" | sed 's/^/      missing: /'
      fail "$(printf '%s\n' "$MISSING" | wc -l | tr -d ' ') manifest test(s) no longer declared — deleted or renamed"
    else
      pass "all $n_manifest manifest tests still declared"
    fi
  fi
fi

# --- 2. The suites actually execute, and clear the floor --------------------
# Reading the runner's own summary rather than trusting its exit code: a suite
# that skipped everything exits 0 too.
#
# The trap OWNS the tempfile (ADR-129, enforced by
# scripts/lint-trap-tempfile-ownership.py): without it, a die between allocation
# and the `rm` at the end leaks the log into a /tmp that is already the
# contended resource this repo's runners warn about. Registered BEFORE the
# assignment so there is no window where the file exists and the trap does not.
# $LOG is owned by the single cleanup()/trap registered near the top of this
# file (ADR-129), which also owns $DECLARED. KEEP_LOG is set by any diagnostic
# path that tells the reader to open the log, so the evidence outlives the run.
LOG="$(mktemp -t check10-integrity.XXXXXXXX.log)"
bun test "${SUITES[@]}" >"$LOG" 2>&1
RC=$?

cases=$((cases + 1))
if [[ "$RC" -ne 0 ]]; then
  fail "bun test exited $RC — see $LOG"
  KEEP_LOG=1
else
  pass "bun test exited 0"
fi

# The counters come from bun's summary block, through the single producer/binder
# pair defined at the top of this file. ONE `read` is the only way a counter enters
# this gate.
read -r n_pass n_fail n_skip n_todo n_expect <<<"$(parse_bun_summary "$LOG")"

# Bind the verdict BEFORE anything touches the counters, so no later statement can
# change what "measured" meant.
if summary_measured "$n_pass" "$n_fail"; then MEASURED=1; else MEASURED=0; fi

# Printed before the branch, and printed RAW: on an unparsed run this line reads
# `pass=- fail=-`, which is more honest than the `pass=0` that the five deleted
# zero-defaults used to manufacture. Correctness must not depend on statement order.
echo "  (measured: pass=$n_pass fail=$n_fail skip=$n_skip todo=$n_todo expect=$n_expect)"

# An UNPARSED summary must not read as "measured zero". Without this, a run that
# never produced a summary block still printed "[ok] no tests skipped at runtime".
# This row is UNCONDITIONAL — it has an `else` — which makes the check count
# deterministic and, under FORCE_COLOR, is the only per-check record that the strip
# worked on real bun output. Everything else asserting that property is a fixture.
cases=$((cases + 1))
if [[ "$MEASURED" == 1 ]]; then
  pass "bun's summary block parsed"
else
  fail "could not parse bun's summary block — treating as UNMEASURED, not as zero (log: $LOG)"
  KEEP_LOG=1
fi

if [[ "$MEASURED" == 1 ]]; then
  # skip / todo / expect are omitted from bun's summary when zero, so `-` means 0
  # HERE — and only here. Outside this branch `-` means UNKNOWN. Nothing below may
  # compare a `-`: measured, `[[ "" -gt 0 ]]` is fail-CLOSED but `[[ "-" -gt 0 ]]`
  # prints one arithmetic error to stderr nobody reads and returns FALSE, so the
  # skip/todo arm would print `[ok] no tests skipped` on a comparison that errored.
  # These are the FIRST statements of the branch, before any arithmetic.
  for v in n_skip n_todo n_expect; do [[ "${!v}" == "-" ]] && printf -v "$v" 0; done

  # N1 — the normalisation above is what this asserts. Deleting it leaves `-` at
  # every comparison, which is invisible to the terminal line and to the exit code.
  cases=$((cases + 1))
  if [[ "$n_pass" =~ ^[0-9]+$ && "$n_fail" =~ ^[0-9]+$ && "$n_skip" =~ ^[0-9]+$ \
     && "$n_todo" =~ ^[0-9]+$ && "$n_expect" =~ ^[0-9]+$ ]]; then
    pass "every counter is an integer at the point of comparison"
  else
    fail "a counter is not an integer at the point of comparison (pass=$n_pass fail=$n_fail skip=$n_skip todo=$n_todo expect=$n_expect) — a '-' here is fail-OPEN"
  fi

  cases=$((cases + 1))
  if [[ "$n_fail" -gt 0 ]]; then
    fail "$n_fail test(s) FAILED per bun's own summary"
    KEEP_LOG=1
  else
    pass "bun's summary reports no failing tests"
  fi

  cases=$((cases + 1))
  if [[ "$n_skip" -gt 0 || "$n_todo" -gt 0 ]]; then
    fail "$n_skip skipped + $n_todo todo test(s) — coverage silently removed"
  else
    pass "no tests skipped or todo'd at runtime"
  fi
else
  # Every arm fails CLOSED, each naming the same cause. The regression this file
  # exists to close was the opposite: `[ok] bun's summary reports no failing tests`
  # printed directly beneath `[FAIL] could not parse bun's summary block`, a passing
  # verdict about a count that was never read.
  cases=$((cases + 1))
  fail "failing-test count UNMEASURED — an unparsed summary is not a zero (log: $LOG)"
  cases=$((cases + 1))
  fail "skip/todo count UNMEASURED — an unparsed summary is not a zero (log: $LOG)"
  KEEP_LOG=1
fi

# SUT floors, reported DIRECTLY for the same reason as the manifest floor above: they are the
# backstop for the rows, so they must not be routed through the helper a mutation neuters.
#
# Each floor carries its OWN measurement gate, at the comparison. Relying on the
# enclosing `MEASURED` branch would put the predicate and the comparison in different
# statements, where a later edit separates them and nothing reddens — and the
# separated form is fail-OPEN, not fail-closed: `[[ "-" -lt 131 ]]` errors, returns
# false, and control falls through to a green `[ok] test count` on a count nobody read.
#
# Note for a future reader: this UNMEASURED FATAL, like the two floors below it and
# the manifest floor above, exits before the accounting-conservation check. That is
# compliant with ADR-193 Decision #4, which orders conservation first only where a
# floor and conservation can fire on the SAME fault — they cannot here, since the
# floors read the counters and conservation reads PASS+FAIL against `cases`. Do not
# "fix" the order.
if ! [[ "$n_pass" =~ ^[0-9]+$ ]]; then
  printf '\n[FATAL] SUT floor: test count UNMEASURED — an unparsed summary is not a zero.\n' >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
elif [[ "$n_pass" -lt "$MIN_TESTS" ]]; then
  printf '\n[FATAL] SUT floor: only %d test(s) passed, floor is %d (coverage removed? — if "bun test exited 0" also failed, this is a consequence of that, not a cause).\n' \
    "$n_pass" "$MIN_TESTS" >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
fi
cases=$((cases + 1))
pass "test count $n_pass >= floor $MIN_TESTS"

if ! [[ "$n_expect" =~ ^[0-9]+$ ]]; then
  printf '\n[FATAL] SUT floor: assertion count UNMEASURED — an unparsed summary is not a zero.\n' >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
elif [[ "$n_expect" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] SUT floor: only %d expect() call(s), floor is %d (assertions gutted? — if "bun test exited 0" also failed, this is a consequence of that, not a cause).\n' \
    "$n_expect" "$MIN_ASSERTIONS" >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
fi
cases=$((cases + 1))
pass "assertion count $n_expect >= floor $MIN_ASSERTIONS"

# (the EXIT trap removes $LOG)

# THE GATE'S OWN ANTI-VACUITY FLOOR. Every control above routes through pass()/fail(),
# so both are a single point of silence: neutering them to no-ops printed
# "=== 0 passed, 0 failed ===" and exited 0, and the realistic half-mutation
# (fail() still prints, stops counting) printed "[FAIL] manifest has only 0 entries"
# and STILL exited 0, because the only terminal below reads $FAIL. CI reads the exit
# code. This file's whole thesis is that a suite asserting nothing is
# indistinguishable from one that passed — that applies to this file too.
# Ratchet with the check count, exactly like MIN_TESTS. Ratcheted to the MEASURED green value
# (25) with no slack: an earlier 11 carried 2 checks of slack, and slack in an own-dispatch
# floor is the budget a silent regression spends — deleting two whole checks stayed green.
# 13 of the 25 are the parser self-test section, which is the only thing standing between a
# regressed strip and a gate that reports a confident zero.
#
# Read off `cases`, NOT off PASS+FAIL. The counter must be independent of the helpers the floor
# exists to police: PASS+FAIL is exactly what a neutered fail() suppresses, so a floor read off
# it fires on the wrong cause (or, with the row deleted rather than silenced, not at all). With
# `cases`, this floor answers ONLY "did the checks dispatch?", and the conservation check below
# answers "were their verdicts recorded?" — two distinct failures with two distinct sentinels.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never by incrementing FAIL: the terminal below
# reads $FAIL, which is the same counter a stubbed fail() stops moving. A floor enforced through
# the suspect cannot witness the suspect — measured on the previous shape: fail() neutered, the
# gate printed a clean total and exited 0.
MIN_CHECKS=25
if [[ "$cases" -lt "$MIN_CHECKS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d check(s) dispatched, floor is %d — the gate itself went silent.\n' \
    "$cases" "$MIN_CHECKS" >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
fi

# --- Accounting conservation -------------------------------------------------
# The arm that actually catches a neutered verdict helper. The floor above catches "no checks
# RAN"; it cannot catch "checks ran and their verdicts were discarded", because $cases keeps its
# full value when fail() is a no-op. Every check records exactly one verdict, so PASS+FAIL MUST
# equal $cases. Reported directly for the same reason as the floor.
if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != cases (%d).\n' \
    "$((PASS + FAIL))" "$cases" >&2
  if [[ $((PASS + FAIL)) -lt "$cases" ]]; then
    printf '  A check was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
fi

echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
[[ "$FAIL" -eq 0 ]] || exit 1
