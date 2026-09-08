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
MIN_TESTS=132
MIN_ASSERTIONS=539
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
#
# VERDICTS is an APPEND-ONLY transcript, one character per recorded verdict, and
# it is what makes the accounting below DIRECTIONAL. The conservation identity
# `PASS+FAIL == cases` is a SUM, so it cannot see a verdict recorded in the wrong
# bucket: measured, `fail() { PASS=$((PASS + 1)); ... }` — one token — printed
# three `[FAIL]` lines and still reported `25 passed, 0 failed`, exit 0, because
# the sum was conserved and `cases` never moved. Neither the own-dispatch floor
# (which reads `cases`, deliberately independent of these helpers) nor
# scripts/guard-vacuity-floor.test.sh caught it — that guard constructs a
# NEUTERED helper (verdict lost), which is a different mutation from a MISROUTED
# one (verdict recorded against the wrong counter).
VERDICTS=""
pass() { PASS=$((PASS + 1)); VERDICTS="${VERDICTS}P"; printf '  [ok] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); VERDICTS="${VERDICTS}F"; printf '  [FAIL] %s\n' "$1"; }

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
# Reduce a parsed digit-run to an integer bash can compare, or to `-`.
#
# `^[0-9]+$` is NOT an integer guard for `[[ ]]`. Arithmetic evaluation reads a
# leading zero as OCTAL, so `08` and `09` satisfy that regex and then make EVERY
# comparison abort with `value too great for base` and return FALSE — measured,
# that bypassed all three floors at once while the integer check above them
# printed `[ok] every counter is an integer at the point of comparison` on the
# very value breaking the comparison. `10#` forces base 10. The length cap is a
# separate hazard: 2^63 satisfies both the regex and `10#`, then WRAPS negative,
# so `-gt 0` reads false on a huge failure count.
_int_or_dash() {                # <digit-run> -> integer, or `-` if unusable
  local v="${1:-}"
  [[ "$v" =~ ^[0-9]+$ && "${#v}" -le 15 ]] || { printf -- '-'; return; }
  printf '%s' "$((10#$v))"
}

parse_bun_summary() {           # <path> -> "pass fail skip todo expect ran"
  local plain term block v out=""
  plain="$(strip_ansi "$1")"

  # THE TRUSTED REGION IS BUN'S SUMMARY BLOCK, NOT THE WHOLE LOG.
  #
  # `$LOG` is bun's stdout AND stderr, so every byte a test prints lands in it —
  # including bytes a test crafts to look like a counter. Two measured forgeries,
  # both of which produced a clean green before this bound existed:
  #
  #   1. A single `console.log(" 999999 expect() calls")` in a suite of 132
  #      assertion-free tests parsed as expect=999999 and cleared MIN_ASSERTIONS.
  #      A suite that asserts NOTHING scored 25/25. That is this file's whole
  #      thesis, defeated at the counter it trusts most, and the source-pattern
  #      and manifest controls both pass because the test NAMES are intact.
  #   2. `bun test >"$LOG" 2>&1` hands fd 1 to every child a test spawns, so a
  #      child can name it as /proc/self/fd/1, busy-poll for the terminator, and
  #      APPEND forged counters after bun has exited — where `tail -1` prefers
  #      them. Measured: the race was won on every attempt, handing over all
  #      five counters.
  #
  # So the parse is bounded to the contiguous counter block ENDING at bun's own
  # terminator. A missing terminator yields all-unread, which is fail-closed.
  # This also retires the file's former claim that `$LOG` has a single writer —
  # it does not, and the OSC/scope argument below rests on bun's behaviour only
  # for the bytes bun itself emits.
  term="$(LC_ALL=C grep -nE '^Ran [0-9]+ tests? across' <<<"$plain" | tail -1 | cut -d: -f1)"
  if [[ -z "$term" ]]; then
    printf -- '- - - - - -\n'
    return
  fi
  # Walk UP from the terminator keeping only counter-shaped lines, stopping at
  # the first line that is not one (bun writes a blank line above the block). A
  # forged counter earlier in the log is outside the region by construction.
  block="$(sed -n "1,$((term - 1))p" <<<"$plain" | tac | sed -n '/^[[:space:]]*[0-9][0-9]* [a-z]/!q;p')"

  # Five deliberately-separate greps rather than a loop: a loop cannot express
  # reverting ONE counter, which is how mutations M2/M3/M5 prove each anchor is
  # load-bearing. Each carries BOTH anchors — leading `^[[:space:]]*` so a
  # mid-line stack frame is not read as a summary, and trailing `$` so ` 7 passed`
  # is not read as ` 7 pass` (measured: without it, a line-leading `9 passed`
  # after the block parsed as 9).
  v="$(LC_ALL=C grep -oE '^[[:space:]]*([0-9]+) pass[[:space:]]*$' <<<"$block" | grep -oE '[0-9]+' | tail -1)"
  out="$(_int_or_dash "$v")"
  v="$(LC_ALL=C grep -oE '^[[:space:]]*([0-9]+) fail[[:space:]]*$' <<<"$block" | grep -oE '[0-9]+' | tail -1)"
  out="$out $(_int_or_dash "$v")"
  v="$(LC_ALL=C grep -oE '^[[:space:]]*([0-9]+) skip[[:space:]]*$' <<<"$block" | grep -oE '[0-9]+' | tail -1)"
  out="$out $(_int_or_dash "$v")"
  # bun classifies `todo` SEPARATELY from `skip`, so a suite suppressed via
  # `.todoIf(...)` reported 0 skip and this gate called it "no tests skipped at
  # runtime". Parsing it is what makes the whole suppression family visible by
  # MEASUREMENT rather than by source pattern-matching.
  v="$(LC_ALL=C grep -oE '^[[:space:]]*([0-9]+) todo[[:space:]]*$' <<<"$block" | grep -oE '[0-9]+' | tail -1)"
  out="$out $(_int_or_dash "$v")"
  # The second stage stays UNANCHORED here and everywhere: the first stage's
  # anchor makes the match carry its leading whitespace, so a `^[0-9]+` second
  # stage matches nothing and a healthy ` 539 expect() calls` parses EMPTY.
  v="$(LC_ALL=C grep -oE '^[[:space:]]*([0-9]+) expect\(\) calls[[:space:]]*$' <<<"$block" | grep -oE '[0-9]+' | tail -1)"
  out="$out $(_int_or_dash "$v")"
  # `Ran N tests across M files.` — the one line bun prints UNCONDITIONALLY, and
  # the reason the three optional counters are checkable at all. See the
  # conservation check at the consumption site.
  v="$(LC_ALL=C grep -oE '^Ran [0-9]+ tests? across' <<<"$plain" | grep -oE '[0-9]+' | tail -1)"
  out="$out $(_int_or_dash "$v")"

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
  || { printf '\n[FATAL] parser symbols absent — a missing function would read as a wrong answer.\n' >&2
       echo "=== $PASS passed, $FAIL failed ($cases checks) ==="; exit 1; }

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

# Fixtures carry bun's terminator line, because real bun always emits it and the
# parser now requires it. Expected tuples are "pass fail skip todo expect ran".

# S1 — plain text, deliberately NOT the all-green canonical shape.
assert_parse "S1 plain summary parses all six fields" "122 3 1 2 514 128" \
  <(printf ' 122 pass\n 3 fail\n 1 skip\n 2 todo\n 514 expect() calls\nRan 128 tests across 1 file.\n')

# S2a/S2b — REAL bytes captured from bun 1.3.11 with FORCE_COLOR=1, pasted from
# `cat -v`. Colour placement is VALUE-DEPENDENT, so one coloured fixture cannot
# represent bun's output: a non-zero counter is `^[[0m^[[32m 132 pass^[[0m` (ESC
# first), a zero `pass` is ` 0 pass^[[0m` (space first), and `skip` is
# ` ^[[0m^[[33m2 skip^[[0m` (space, then ESC, then the digits).
assert_parse "S2a coloured non-zero summary parses (real bun 1.3.11 bytes)" "132 0 - - 539 132" \
  <(printf '%s[0m%s[32m 132 pass%s[0m\n%s[0m%s[2m 0 fail%s[0m\n 539 expect() calls\nRan 132 tests across 3 files.\n' \
      "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC")

# S2b — the all-skip run: the case this gate exists to catch. bun prints NO
# `expect() calls` line at all here (measured: grep -c => 0), which is why
# summary_measured must not require it.
assert_parse "S2b coloured all-skip summary parses (no expect() line at all)" "0 0 2 - - 2" \
  <(printf ' 0 pass%s[0m\n %s[0m%s[33m2 skip%s[0m\n%s[0m%s[2m 0 fail%s[0m\nRan 2 tests across 1 file.\n' \
      "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC")

# S3 — escapes an SGR-only strip does not reach: a COLON-separated SGR, a two-byte
# DECSC (`ESC 7`, no `[`), and a charset designator (`ESC ( B`). Each survives a
# narrow class and is then a hard RED on a healthy tree — the cries-wolf mode that
# gets a gate bypassed. Its coloured `todo` line is the only one in the fixture
# set, and the only fixture carrying skip AND todo together.
assert_parse "S3 colon-SGR, DECSC and charset escapes are stripped" "122 3 1 4 - 130" \
  <(printf '%s[38:2:0:255:0m 122 pass%s[0m\n%s7 3 fail\n%s(B 1 skip\n %s[0m%s[35m4 todo%s[0m\nRan 130 tests across 1 file.\n' \
      "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC" "$ESC")

# S4 — FORGERY. $LOG carries every byte the suites print, so a test can craft a
# counter-shaped line. Both placements are here and both must be excluded: three
# decoys BEFORE the block (one of them line-anchored, the shape that defeated the
# leading anchor alone) and a post-terminator ` 9 passed` (the shape that defeats
# a missing trailing anchor, and where `tail -1` would prefer it). Only the real
# block between the blank line and the terminator may be read.
assert_parse "S4 forged counters outside the summary block are not read" "2 0 - - 2 2" \
  <(printf '  at bar (/src/b.ts:1:1) 999 expect() calls\n  running 42 pass-through checks\n 999999 expect() calls\n\n 2 pass\n 0 fail\n 2 expect() calls\nRan 2 tests across 1 file.\n 9 passed\n')

# S5 — no terminator at all. A summary block bun never finished writing (a killed
# runner, a truncated log) is UNMEASURED, not zero. Also carries a CR overwrite,
# which `tr` must TRANSLATE rather than delete: deleting it would concatenate the
# overwritten text onto the next line and the anchors would miss again.
assert_parse "S5 a log with no terminator is entirely unread" "- - - - - -" \
  <(printf ' 500 pass\r 500 pass\n 0 fail\n')

# T1 — the strip asserted at TEXT level, not only through the counters. Without
# this, S3's escape-bearing fixture can be swapped for plain SGR with its name and
# slot intact and a narrowed strip class then goes green — measured. It is also
# the honest form of the no-over-strip control: the surviving text is what a
# too-wide class eats, and the five integers cannot witness that.
cases=$((cases + 1))
_t1_got="$(strip_ansi <(printf '%s[38:2:0:255:0m 122 pass%s[0m\n%s7 ok\n%s(B done\n  at foo (/src/a.ts:10:5) expected [1;2] arr[0]a\n' "$ESC" "$ESC" "$ESC" "$ESC"))"
_t1_want="$(printf ' 122 pass\n ok\n done\n  at foo (/src/a.ts:10:5) expected [1;2] arr[0]a\n')"
if [[ "$_t1_got" == "$_t1_want" ]]; then
  pass "T1 strip removes every escape class and leaves all other text byte-identical"
else
  fail "T1 strip output differs — got [$_t1_got]"
fi

# V1-V4 — the predicate. V1 cannot distinguish which member was dropped (it is
# false under either single-member edit); V2 is the sole detector for `fail` and
# V3 the sole detector for `pass`, so the pair NAMES the omission. V4 is the true
# case: without it a predicate stuck at false would score green.
assert_measured "V1 neither counter read is UNMEASURED" "-" "-" false
assert_measured "V2 pass read, fail unread is UNMEASURED" "122" "-" false
assert_measured "V3 fail read, pass unread is UNMEASURED" "-" "0" false
assert_measured "V4 both counters read is MEASURED" "122" "0" true

# N2/N3 — instrument self-tests, one per comparator. Every check above is scored
# by one of two wrappers, and a wrapper stubbed to always call pass() leaves this
# whole section green with the conservation identity intact (a stub still records
# one verdict per counted check). N2 covered `assert_parse` only; measured, that
# left `assert_measured` — four verdicts, including the sole detector for the
# #7466 fail-open — provable by nothing. Each probe drives its wrapper once with
# an expectation that MUST fail, requires FAIL to move by exactly one, and
# unwinds every counter it touched so the probe records no verdict of its own.
#
# `_fd`/`_pd` are recomputed from PASS/FAIL at the comparison rather than bound
# earlier, so pinning them to constants cannot fake the result. Keep the `-eq`:
# rewriting either as `-lt`/`-le`/`-ge` makes them floor candidates in
# scripts/guard-vacuity-floor.test.sh's floor_lines_of(), whose construction
# budget is at zero headroom.
_probe_wrapper() {              # <label> <wrapper-invocation...>
  local label="$1"; shift
  local _pb=$PASS _fb=$FAIL _cb=$cases _vb="$VERDICTS"
  "$@" >/dev/null
  local _fd=$((FAIL - _fb)) _pd=$((PASS - _pb))
  PASS=$_pb; FAIL=$_fb; cases=$_cb; VERDICTS="$_vb"
  cases=$((cases + 1))
  if [[ "$_fd" -eq 1 && "$_pd" -eq 0 ]]; then
    pass "$label"
  else
    fail "$label — a wrong expectation moved FAIL by $_fd and PASS by $_pd (expected 1 and 0)"
  fi
}

_probe_wrapper "N2 assert_parse scores a wrong expectation as one failure" \
  assert_parse "instrument probe (its FAIL is expected and discarded)" "9 9 9 9 9 9" \
    <(printf ' 1 pass\n 0 fail\nRan 1 tests across 1 file.\n')

_probe_wrapper "N3 assert_measured scores a wrong expectation as one failure" \
  assert_measured "instrument probe (its FAIL is expected and discarded)" "122" "0" false

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
# FORCE_COLOR=1 is deliberate: bun does not colour a redirected stream, so
# without it the strip's only CI evidence is this file's own frozen fixtures and
# the live path never exercises the parser against real escapes — which is
# exactly how #7466 survived. It changes no counter.
FORCE_COLOR=1 bun test "${SUITES[@]}" >"$LOG" 2>&1
RC=$?

cases=$((cases + 1))
if [[ "$RC" -ne 0 ]]; then
  fail "bun test exited $RC — see $LOG"
  KEEP_LOG=1
else
  pass "bun test exited 0"
fi

# The counters come from bun's summary block, through the single producer/binder
# pair defined at the top of this file. ONE `read` is the only way a counter
# enters this gate.
#
# COUNTERS is the single source of truth for the counter set: the normalisation
# loop and the integrity check below both derive from it, so adding a seventh
# field is one edit here plus one grep in the producer. Before this, the set was
# restated at five hand-maintained sites and missing two of them let a new
# counter reach its comparison as `-` — fail-open, one unread stderr line, a
# green [ok]. That is this file's own defect class, re-armed by an additive edit.
COUNTERS=(n_pass n_fail n_skip n_todo n_expect n_ran)
OPTIONAL_COUNTERS=(n_skip n_todo n_expect)   # bun omits these entirely when zero

read -r n_pass n_fail n_skip n_todo n_expect n_ran <<<"$(parse_bun_summary "$LOG")"

# Bind the verdict BEFORE anything touches the counters, so no later statement
# can change what "measured" meant.
if summary_measured "$n_pass" "$n_fail"; then MEASURED=1; else MEASURED=0; fi

# Printed before the branch, and printed RAW: on an unparsed run this line reads
# `pass=- fail=-`, which is more honest than the `pass=0` that the five deleted
# zero-defaults used to manufacture. Correctness must not depend on statement
# order. `-` is rendered `?` so a reader who has never opened this file is not
# asked to distinguish two meanings of one glyph on sight.
_render() { [[ "$1" == "-" ]] && printf '?' || printf '%s' "$1"; }
echo "  (measured: pass=$(_render "$n_pass") fail=$(_render "$n_fail") skip=$(_render "$n_skip") todo=$(_render "$n_todo") expect=$(_render "$n_expect") ran=$(_render "$n_ran"))"

# An UNPARSED summary must not read as "measured zero". Without this, a run that
# never produced a summary block still printed "[ok] no tests skipped at runtime".
# This row is UNCONDITIONAL — it has an `else` — and both branches below dispatch
# the SAME number of checks, so the own-dispatch floor's count is path-invariant.
# It was not: the measured arm ran three rows and the unmeasured arm two, so a
# genuinely unparsed summary landed one short and the floor fired
# `the gate itself went silent` directly beneath three rows naming the real cause.
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
  # compare a `-`: measured, `[[ "-" -gt 0 ]]` prints one arithmetic error to
  # stderr nobody reads and returns FALSE. Note `[[ "" -gt 0 ]]` returns FALSE
  # too — at THIS arm both are fail-open and the normalisation is what closes it.
  # The polarity difference between `""` and `-` is real only at the FLOOR
  # comparisons below (`""` fires the floor, `-` silently skips it).
  for v in "${OPTIONAL_COUNTERS[@]}"; do
    if [[ "${!v}" == "-" ]]; then printf -v "$v" 0; fi
  done

  # N1 — every counter must be an integer where it is compared. Derived from
  # COUNTERS so a seventh field is covered by existing code.
  cases=$((cases + 1))
  _n1_bad=""
  for v in "${COUNTERS[@]}"; do
    [[ "${!v}" =~ ^[0-9]+$ ]] || _n1_bad="$_n1_bad $v=${!v}"
  done
  if [[ -z "$_n1_bad" ]]; then
    pass "every counter is an integer at the point of comparison"
  else
    fail "a counter is not an integer at the point of comparison:$_n1_bad — a '-' here is fail-OPEN"
    KEEP_LOG=1
  fi

  # The counter-conservation check. `Ran N tests` is the ONE line bun prints
  # unconditionally, so it is the only thing that can tell "bun omitted a zero"
  # from "we failed to read a line that was there". Without it, summary_measured
  # covers pass and fail and the other three are an INFERENCE: measured, a parse
  # failure confined to skip/todo produced `skip=? todo=?` and
  # `[ok] no tests skipped or todo'd at runtime` on adjacent lines — this file's
  # own defect, surviving in its fix, for three of five counters.
  cases=$((cases + 1))
  _sum=$((n_pass + n_fail + n_skip + n_todo))
  if [[ "$n_ran" =~ ^[0-9]+$ && "$_sum" -eq "$n_ran" ]]; then
    pass "counters reconcile with bun's own total ($_sum == $n_ran ran)"
  else
    fail "counters do not reconcile with bun's total: pass+fail+skip+todo=$_sum but Ran=$(_render "$n_ran") — a counter was misread (log: $LOG)"
    KEEP_LOG=1
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
    fail "$n_skip skipped + $n_todo todo test(s) — coverage silently removed (log: $LOG)"
    KEEP_LOG=1
  else
    pass "no tests skipped or todo'd at runtime"
  fi
else
  # Every arm fails CLOSED, each naming the same cause, and there are as many of
  # them as the measured branch has, so `cases` does not depend on which branch
  # ran. The regression this file exists to close was the opposite:
  # `[ok] bun's summary reports no failing tests` printed directly beneath
  # `[FAIL] could not parse bun's summary block` — a passing verdict about a
  # count that was never read.
  cases=$((cases + 1)); fail "counter integrality UNMEASURED — an unparsed summary is not a zero (log: $LOG)"
  cases=$((cases + 1)); fail "counter reconciliation UNMEASURED — an unparsed summary is not a zero (log: $LOG)"
  cases=$((cases + 1)); fail "failing-test count UNMEASURED — an unparsed summary is not a zero (log: $LOG)"
  cases=$((cases + 1)); fail "skip/todo count UNMEASURED — an unparsed summary is not a zero (log: $LOG)"
  KEEP_LOG=1
fi

# SUT floors, reported DIRECTLY for the same reason as the manifest floor above: they are the
# backstop for the rows, so they must not be routed through the helper a mutation neuters.
#
# Each floor carries its OWN measurement gate, at the comparison. Relying on the
# enclosing `MEASURED` branch would put the predicate and the comparison in
# different statements, where a later edit separates them and nothing reddens —
# and the separated form is fail-OPEN, not fail-closed: `[[ "-" -lt 131 ]]`
# errors, returns false, and control falls through to a green `[ok] test count`
# on a count nobody read.
#
# Note for a future reader: this UNMEASURED FATAL, like the two floors below it
# and the manifest floor above, exits before the accounting-conservation check.
# That is compliant with ADR-193 Decision #4, which orders conservation first
# only where a floor and conservation can fire on the SAME fault — they cannot
# here, since the floors read BUN's counters and `cases`, all independent of
# PASS/FAIL. (Single-fault statement: under a compound fault the early exit does
# leave a deeper cause unnamed, exactly as the pre-existing floors already did.)
# Do not "fix" the order.
if ! [[ "$n_pass" =~ ^[0-9]+$ ]]; then
  KEEP_LOG=1
  printf '\n[FATAL] SUT floor: test count UNMEASURED — an unparsed summary is not a zero (log: %s).\n' "$LOG" >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
elif [[ "$n_pass" -lt "$MIN_TESTS" ]]; then
  KEEP_LOG=1
  printf '\n[FATAL] SUT floor: only %s test(s) passed, floor is %s (coverage removed? — if "bun test exited 0" also failed, this is a consequence of that, not a cause). Log: %s\n' \
    "$n_pass" "$MIN_TESTS" "$LOG" >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
fi
cases=$((cases + 1))
pass "test count $n_pass >= floor $MIN_TESTS"

if ! [[ "$n_expect" =~ ^[0-9]+$ ]]; then
  KEEP_LOG=1
  printf '\n[FATAL] SUT floor: assertion count UNMEASURED — an unparsed summary is not a zero (log: %s).\n' "$LOG" >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
elif [[ "$n_expect" -lt "$MIN_ASSERTIONS" ]]; then
  KEEP_LOG=1
  printf '\n[FATAL] SUT floor: only %s expect() call(s), floor is %s (assertions gutted? — if "bun test exited 0" also failed, this is a consequence of that, not a cause). Log: %s\n' \
    "$n_expect" "$MIN_ASSERTIONS" "$LOG" >&2
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
# (29) with no slack: an earlier 11 carried 2 checks of slack, and slack in an own-dispatch
# floor is the budget a silent regression spends — deleting two whole checks stayed green.
# 13 of the 29 are the parser self-test section (MEASURED by instrumenting `cases` at the
# section boundary, not counted by eye — an earlier revision of this comment said 13 of 25
# when the section dispatched 10, having carried the previous floor value forward).
#
# That section does NOT prevent a confident zero on its own — measured, deleting it whole
# and lowering this floor to match still fails closed, via summary_measured, the fail-closed
# arms and the integer-gated floors. What it buys is NAMING the cause at the fixture level
# instead of as one opaque unparsed-summary FAIL.
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
MIN_CHECKS=29
if [[ "$cases" -lt "$MIN_CHECKS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d check(s) dispatched, floor is %d — the gate itself went silent.\n' \
    "$cases" "$MIN_CHECKS" >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="
  exit 1
fi

# --- Verdict routing ---------------------------------------------------------
# Read the append-only transcript, not the counters. This is the arm that catches
# a MISROUTED verdict helper, which conservation structurally cannot: silencing
# the gate now requires editing the transcript AND the counter in the same
# helper, and dropping the transcript write alone fires this too.
_v_pass="${VERDICTS//F/}"
_v_fail="${VERDICTS//P/}"
if [[ "${#_v_pass}" -ne "$PASS" || "${#_v_fail}" -ne "$FAIL" ]]; then
  printf '\n[FATAL] verdict routing: %d [ok] verdict(s) recorded against PASS=%d, %d [FAIL] verdict(s) against FAIL=%d.\n' \
    "${#_v_pass}" "$PASS" "${#_v_fail}" "$FAIL" >&2
  printf '  A verdict was counted in the wrong bucket — that is what a misrouted pass()/fail() looks like, and the PASS+FAIL sum cannot see it.\n' >&2
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
