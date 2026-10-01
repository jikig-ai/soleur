#!/usr/bin/env bash
# Guard 1 mutation battery — the shared cloud-init strip helpers (#7968).
#
# THE PROPERTY. For every base64gzip'd host, `cloud-init-user-data-size.test.ts` models the strip
# production applies only when the host's `.tf` declares exactly one live strip local and wires it,
# uniquely, inside the render call — decided from COMMENT-STRIPPED source, never from prose.
#
# WHY A BATTERY AND NOT JUST THE ARMS. The property is carried by two shared functions
# (`extractStripRegex`, `stripIsApplied`) that every per-host wrapper delegates to. Removing the
# comment-strip from those functions leaves the real-tree suite 47/47 GREEN (measured 2026-09-18):
# every live `.tf` is unambiguous, so no real-tree arm can see the raw-source fail-open that #7965
# mutation-found in its own first commit (a green suite over a 42,360 B tree against the 32,768 B
# cap — caught in review, never merged; the class is that a fourth copy could ship it). The
# synthetic fixture arms in the `shared strip helpers are structural (#7968)` describe block are
# what can red; this battery proves they DO red when the helpers regress.
#
# EVERY ROW MUTATES A SCRATCH COPY OF THE SUITE, NEVER THE TRACKED FILE. The scratch tree
# replicates the depth the suite assumes — it derives REPO_ROOT from `import.meta.dir/../../..`,
# so the copy must sit exactly three directories deep — and symlinks the read-only inputs
# (`apps/web-platform/{infra,Dockerfile,.dockerignore}`) from the real tree. The pristine copy is
# stored WITHOUT a `.test.ts` suffix: `bun test <path>` treats the positional as a FILTER over
# every test file under the cwd, so a second `.test.ts` anywhere under $WORK would be discovered
# too and double the `Ran N` count.
#
# A ROW IS RED ONLY FOR THE RIGHT REASON. `expect_red` requires `Ran N` equal to the pristine
# total AND no summary `error(s)` line AND rc != 0 AND the named arm under `(fail)` — in that
# order, so the reason printed for a compile-broken mutant (`Ran 1 test`, measured on bun 1.3.14)
# is the load-time break, not a missing arm title. Such a row is INVALID, not RED. A substitution
# whose anchor is missing, ambiguous, or changes nothing is a LANDING-FAILED row. A SURVIVED or
# INVALID row prints the substitution and bun's `error:`/`Ran` lines inline: the scratch tree is
# removed on exit, so the run log is the only evidence.
#
# EXIT CODES. 2 = FATAL precondition (nothing was measured: pristine copy red, scratch tree does
# not resolve infra/, bun/python3 missing). 1 = measured: a row SURVIVED / LANDING-FAILED, or
# FLOOR (the harness's own accounting is inconsistent). 0 = every row ok and restore verified.
#
# MUTATION MATRIX (observed verdicts; every row RED = the guard holds)
#   R1  extractStripRegex reads RAW source (comment-strip removed) ......... RED  (A1)
#   R2  stripIsApplied reads RAW source — the #7965 M3 fail-open ............ RED  (A6)
#   R3  stripIsApplied accepts a second anchor (first-match semantics) ...... RED  (A7)
#   R4  extractStripRegex accepts a duplicate live definition ............... RED  (A2)
#   R5  stripHclLineComments keeps `/* block */` comments ................... RED  (A6b)
#   R6  stripIsApplied drops the anchor-call bound (region = whole file) .... RED  (A9c)
#   R7  stripHclLineComments keeps TRAILING `#` comments .................... RED  (A1b)
#   R8  stripIsApplied checks every chain link but the first ................ RED  (A8 first)
#   R9  stripIsApplied accepts a MENTION in the span instead of arg 2 ....... RED  (A11 var)
#   H1  expect_red against the CONTROL output must NOT return ok ............ ok
#   H1b expect_red with the WRONG arm title against R1's output must NOT ok . ok
#   H2  a benign single-occurrence edit stays GREEN ......................... GREEN
#   H3  re-applying R1 to an already-mutated copy is LANDING-FAILED (rc 2) .. ok
#   H4  expect_red against a synthetic `Ran 1 test` output must NOT return ok ok
#   K1  row_red on a benign edit is REPORTED as SURVIVED (netted out) ....... ok
#   K2  row_red on a drifted anchor is REPORTED as LANDING-FAILED (netted) .. ok
#
# AXIS DISCLOSURE. R1–R9 perturb SUT SOURCE CONTENT inside the three shared functions; that is
# one axis. H1/H1b/H4 perturb the harness's VERDICT INPUT (a green output, a wrong arm name, a
# load-time break); H2 is the must-PASS non-canonical edit; H3 perturbs the LANDING check; K1/K2
# drive the ROW RUNNER end to end (row_red → expect_red → survived()/landing()) with a known
# survivor and a known landing failure, so a `survived()` that counts into PASS, or a row_red
# whose verdict branch is `if true`, is a FLOOR mismatch rather than a green run. This battery
# does NOT edit fixture shape or direction in the TS arms (A5/A10 are the must-PASS controls; the
# negatives are single-`.replace` derivations covering both sides — link first/last, mention
# before/after — so the arms carry that axis), the walker's member cardinality, or the wrappers'
# constants: measured 2026-09-18, a wrong local-name or anchor constant reds 2–4 real-tree arms
# every run, while a dropped inngest chain link and a git-data wrapper pointed at the sibling
# payload local did NOT — those two are now pinned by the real-tree `first chain link bypasses
# the render` and `git-data template strip preserves #cloud-config` arms rather than by a row.
#
# SCRATCH-TREE CONSTRAINT. The copy runs with no `node_modules` and no repo `bunfig.toml`; the
# suite imports only `bun:test` and `node:*` builtins, and the git-tripwire preload the root
# bunfig would have applied is passed explicitly (`--preload`). A future bare-specifier import in
# the suite fails resolution here while the tracked suite stays green — the FATAL names it.
#
# ANCHOR DRIFT. The `old` strings below are slices of the helpers' text. A rename that breaks one
# is reported as LANDING-FAILED by the row (H3 and K2 pin the mechanism), never as a silent pass;
# the fix is a one-line anchor update here.

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate (%s); refusing\n' "$SCRIPT_DIR" >&2; exit 2 ;;
  /*) : ;;
  *)  printf 'FATAL: SCRIPT_DIR is relative; refusing\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT

TRACKED="$REPO_ROOT/plugins/soleur/test/cloud-init-user-data-size.test.ts"
[[ -f "$TRACKED" ]] || { printf 'FATAL: suite missing at %s\n' "$TRACKED" >&2; exit 2; }
for input in apps/web-platform/infra apps/web-platform/Dockerfile apps/web-platform/.dockerignore; do
  [[ -e "$REPO_ROOT/$input" ]] || { printf 'FATAL: suite input missing at %s\n' "$REPO_ROOT/$input" >&2; exit 2; }
done
command -v bun >/dev/null 2>&1 || { printf 'FATAL: bun not on PATH\n' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'FATAL: python3 not on PATH\n' >&2; exit 2; }
TRIPWIRE="$REPO_ROOT/plugins/soleur/test/lib/git-tripwire.ts"
[[ -f "$TRIPWIRE" ]] || { printf 'FATAL: git-tripwire preload missing at %s\n' "$TRIPWIRE" >&2; exit 2; }

WORK="$(mktemp -d -t cistrip.XXXXXXXX)" || exit 2
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *)  printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
M="$WORK/mut"; mkdir -p "$M" || exit 2

# The scratch tree: the SUT three directories deep, read-only inputs symlinked from the real tree.
SUT_DIR="$WORK/plugins/soleur/test"
SUT="$SUT_DIR/cloud-init-user-data-size.test.ts"
PRISTINE="$WORK/suite.pristine"
mkdir -p "$SUT_DIR" "$WORK/apps/web-platform" || { printf 'FATAL: mkdir scratch tree failed\n' >&2; exit 2; }
for input in infra Dockerfile .dockerignore; do
  ln -s "$REPO_ROOT/apps/web-platform/$input" "$WORK/apps/web-platform/$input" \
    || { printf 'FATAL: ln -s %s failed\n' "$input" >&2; exit 2; }
done
cp "$TRACKED" "$SUT"      || { printf 'FATAL: cp suite failed\n' >&2; exit 2; }
cp "$SUT" "$PRISTINE"     || { printf 'FATAL: cp pristine failed\n' >&2; exit 2; }
restore() { cp "$PRISTINE" "$SUT" || { printf 'FATAL: restore failed\n' >&2; exit 2; }; }

ARM_PREFIX='(fail) shared strip helpers are structural (#7968) > '
readonly ARM_PREFIX
A1='extractor ignores a commented decoy definition'
A1B='extractor ignores a trailing-comment decoy definition'
A2='extractor refuses a duplicate live definition'
A6='predicate is not satisfied by a comment naming the chain'
A6B='predicate is not satisfied by a block-commented render'
A7='predicate refuses a second anchor'
A8F='predicate requires every chain link (first)'
A9="predicate bounds the local to the anchor's own replace() call"
A11V="predicate requires the local as replace()'s second argument (templatefile var)"
WALKER_TITLE="every base64gzip'd host has a committed byte measurement"
FIXTURE_DESCRIBE='shared strip helpers are structural'
MIN_FIXTURE_ARMS=10
MIN_EXPECT_CALLS=130
readonly A1 A1B A2 A6 A6B A7 A8F A9 A11V WALKER_TITLE FIXTURE_DESCRIBE MIN_FIXTURE_ARMS MIN_EXPECT_CALLS

# run_suite <out-file>: runs the (possibly mutated) scratch suite; sets RC. Output goes to a
# file, ANSI-stripped into <out-file>.plain, so nothing here is unbounded.
# P1b (#7708): the only guard shape `fixture-relative-assert.test.sh` recognises over a redirect
# operand. The body is a byte-exact COPY of the canonical definition in
# plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh asserts the equality,
# so do not reword it here alone.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
run_suite() {
  local out="$1"
  assert_fixture_dir "$out"
  (cd "$WORK" && bun test --preload "$TRIPWIRE" plugins/soleur/test/cloud-init-user-data-size.test.ts > "$out" 2>&1)
  RC=$?
  LC_ALL=C sed -r 's/\x1B\[[0-9;]*[mGKHF]//g' "$out" > "$out.plain"
}
# Field readers over a plain output file. Each prints the figure or nothing.
ran_n()   { LC_ALL=C grep -oE '^Ran [0-9]+ tests? across' "$1" | grep -oE '[0-9]+' | tail -1; }
calls_n() { LC_ALL=C grep -oE '^[[:space:]]*[0-9]+ expect\(\) calls' "$1" | grep -oE '[0-9]+' | tail -1; }
fail_n()  { LC_ALL=C grep -oE '^[[:space:]]*[0-9]+ fail$' "$1" | grep -oE '[0-9]+' | tail -1; }
# The SUMMARY error line only (`error:` prose appears in every failing run and must not match).
has_error_line() { LC_ALL=C grep -qE '^[[:space:]]*[0-9]+ errors?$' "$1"; }

# mutate <fn-name> <old> <new>: function-scoped substitution on the scratch SUT. Slices the copy
# between `function <fn-name>(` and the next `\n}\n`, requires <old> EXACTLY ONCE in that slice,
# substitutes once. RETURNS (never exits) 2 when the anchor is absent or ambiguous, or when the
# file is byte-identical afterwards — the caller records LANDING-FAILED.
cat > "$M/subst.py" <<'MUT'
import sys
path, fn, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(path, encoding="utf-8").read()
head = "function " + fn + "("
if s.count(head) != 1:
    sys.stderr.write("function %s not found exactly once\n" % fn); sys.exit(2)
a = s.index(head)
b = s.index("\n}\n", a)
body = s[a:b]
n = body.count(old)
if n == 0:
    sys.stderr.write("anchor missing in %s\n" % fn); sys.exit(2)
if n != 1:
    sys.stderr.write("anchor is AMBIGUOUS (%d occurrences) in %s\n" % (n, fn)); sys.exit(2)
out = s[:a] + body.replace(old, new, 1) + s[b:]
if out == s:
    sys.stderr.write("zero-byte edit\n"); sys.exit(2)
open(path, "w", encoding="utf-8").write(out)
MUT
mutate() {
  local fn="$1" old="$2" new="$3"
  python3 "$M/subst.py" "$SUT" "$fn" "$old" "$new" 2>"$WORK/mut.err" || return 2
  if diff -q "$PRISTINE" "$SUT" >/dev/null 2>&1; then
    printf 'file unchanged after substitution\n' > "$WORK/mut.err"; return 2
  fi
  return 0
}

# expect_red <row> <arm-title> <plain-out> <rc>: the run failed, the NAMED arm is under (fail),
# there is no summary error line, and Ran N equals the pristine total. Returns non-zero — and
# prints the reason to $WORK/why — otherwise, so INVALID is reported distinctly from "still green".
expect_red() {
  local row="$1" arm="$2" plain="$3" rc="$4" ran
  : > "$WORK/why"
  ran="$(ran_n "$plain")"
  if [[ "$ran" != "$PRISTINE_TOTAL" ]]; then
    printf 'INVALID: Ran %s != pristine %s (load-time break?)' "${ran:-none}" "$PRISTINE_TOTAL" > "$WORK/why"; return 1
  fi
  if has_error_line "$plain"; then printf 'INVALID: summary error line present' > "$WORK/why"; return 1; fi
  if [[ "$rc" == "0" ]]; then printf 'rc 0 (still green)' > "$WORK/why"; return 1; fi
  if ! LC_ALL=C grep -Fq -- "${ARM_PREFIX}${arm}" "$plain"; then
    printf 'INVALID: arm "%s" not under (fail)' "$arm" > "$WORK/why"; return 1
  fi
  return 0
}
# expect_green <plain-out> <rc>: rc 0, Ran N equals the pristine total, expect-calls at the floor.
expect_green() {
  local plain="$1" rc="$2" ran calls
  : > "$WORK/why"
  if [[ "$rc" != "0" ]]; then printf 'rc %s' "$rc" > "$WORK/why"; return 1; fi
  ran="$(ran_n "$plain")"
  if [[ "$ran" != "$PRISTINE_TOTAL" ]]; then
    printf 'Ran %s != pristine %s' "${ran:-none}" "$PRISTINE_TOTAL" > "$WORK/why"; return 1
  fi
  calls="$(calls_n "$plain")"
  if [[ -z "$calls" ]] || (( calls < MIN_EXPECT_CALLS )); then
    printf 'expect() calls %s < %d' "${calls:-none}" "$MIN_EXPECT_CALLS" > "$WORK/why"; return 1
  fi
  return 0
}

PASS=0; FAIL=0; declare -a RESULTS=()
ok()       { printf '  %-4s %-5s (want %-5s) ok       — %s\n' "$1" "$2" "$3" "$4"; PASS=$((PASS+1)); RESULTS+=("$1 ok"); }
# survived <row> <got> <want> <desc> [<plain-out>]: prints the reason and, when an output file is
# given, bun's own error/summary lines (bounded) — the scratch tree does not outlive the run.
survived() {
  printf '  %-4s %-5s (want %-5s) SURVIVED — %s [%s]\n' "$1" "$2" "$3" "$4" "$(cat "$WORK/why")"
  [[ -n "${LAST_SUBST:-}" ]] && printf '        substitution: %s\n' "$LAST_SUBST"
  if [[ -n "${5:-}" && -f "$5" ]]; then
    LC_ALL=C grep -E '^error:|^[[:space:]]*[0-9]+ (pass|fail|errors?)$|^Ran ' "$5" | head -6 | sed 's/^/        | /'
  fi
  FAIL=$((FAIL+1)); RESULTS+=("$1 SURVIVED")
}
landing()  { printf '  %-4s LANDING-FAILED (%s) — %s\n' "$1" "$(tail -1 "$WORK/mut.err")" "$2"; FAIL=$((FAIL+1)); RESULTS+=("$1 LANDING-FAILED"); }

# row_red <row> <fn> <old> <new> <arm-title> <desc>: mutate, run, require RED for the named arm.
# Keeps the row's plain output at $WORK/<row>.plain and its rc in RC_<row> for the harness rows.
row_red() {
  local row="$1" fn="$2" old="$3" new="$4" arm="$5" desc="$6"
  LAST_SUBST="$fn: '$old' -> '$new'"
  restore
  if ! mutate "$fn" "$old" "$new"; then landing "$row" "$desc"; restore; return; fi
  run_suite "$WORK/$row.out"
  printf '%s' "$RC" > "$WORK/$row.rc"
  if expect_red "$row" "$arm" "$WORK/$row.out.plain" "$RC"; then ok "$row" RED RED "$desc"
  else survived "$row" "$( [[ "$RC" == "0" ]] && echo GREEN || echo INVAL )" RED "$desc" "$WORK/$row.out.plain"; fi
  restore
}

# ---- CONTROL (exit-2 precondition, not a row) -------------------------------------------------
restore
run_suite "$WORK/control.out"
CONTROL_PLAIN="$WORK/control.out.plain"
if [[ "$RC" != "0" ]]; then
  printf 'FATAL: control run of the pristine suite exited %s; last lines:\n' "$RC" >&2
  tail -20 "$CONTROL_PLAIN" >&2; exit 2
fi
if [[ "$(fail_n "$CONTROL_PLAIN")" != "0" ]] || has_error_line "$CONTROL_PLAIN"; then
  printf 'FATAL: control run reports failures or a summary error line\n' >&2; exit 2
fi
# The pristine total is MEASURED, not carried forward: every row's `Ran N` discriminator compares
# against it, so a sibling PR adding a real-tree arm moves both sides together. What is pinned is
# the FIXTURE describe: a `-t`-filtered run must find at least MIN_FIXTURE_ARMS arms, all passing
# — a deleted or renamed describe block would otherwise leave every row's arm grep unreachable.
PRISTINE_TOTAL="$(ran_n "$CONTROL_PLAIN")"
if [[ ! "$PRISTINE_TOTAL" =~ ^[0-9]+$ ]] || (( PRISTINE_TOTAL < 47 )); then
  printf 'FATAL: control run Ran %s tests, expected at least the 47 pre-#7968 real-tree arms\n' "${PRISTINE_TOTAL:-none}" >&2; exit 2
fi
readonly PRISTINE_TOTAL
(cd "$WORK" && bun test --preload "$TRIPWIRE" plugins/soleur/test/cloud-init-user-data-size.test.ts -t "$FIXTURE_DESCRIBE" > "$WORK/fixture.out" 2>&1)
fixture_rc=$?
LC_ALL=C sed -r 's/\x1B\[[0-9;]*[mGKHF]//g' "$WORK/fixture.out" > "$WORK/fixture.plain"
FIXTURE_ARMS="$(ran_n "$WORK/fixture.plain")"
if [[ "$fixture_rc" != "0" ]] || [[ ! "$FIXTURE_ARMS" =~ ^[0-9]+$ ]] || (( FIXTURE_ARMS < MIN_FIXTURE_ARMS )) \
   || ! LC_ALL=C grep -qE "^[[:space:]]*${FIXTURE_ARMS} pass$" "$WORK/fixture.plain"; then
  printf 'FATAL: the "%s" describe ran %s arm(s) (rc %s), expected >= %d all passing\n' "$FIXTURE_DESCRIBE" "${FIXTURE_ARMS:-none}" "$fixture_rc" "$MIN_FIXTURE_ARMS" >&2
  tail -8 "$WORK/fixture.plain" >&2; exit 2
fi
CONTROL_CALLS="$(calls_n "$CONTROL_PLAIN")"
if [[ -z "$CONTROL_CALLS" ]] || (( CONTROL_CALLS < MIN_EXPECT_CALLS )); then
  printf 'FATAL: control run made %s expect() calls, floor is %d\n' "${CONTROL_CALLS:-none}" "$MIN_EXPECT_CALLS" >&2; exit 2
fi
# The walker arm passing pins that `readdirSync(INFRA)` resolved through the `infra` symlink. bun
# prints `(fail)` lines only (never `(pass)`), so the pin is a `-t`-filtered run of that one arm:
# it must report `1 pass` and `Ran 1 test` — a filter matching nothing reports `0 pass`.
(cd "$WORK" && bun test --preload "$TRIPWIRE" plugins/soleur/test/cloud-init-user-data-size.test.ts -t "$WALKER_TITLE" > "$WORK/walker.out" 2>&1)
walker_rc=$?
LC_ALL=C sed -r 's/\x1B\[[0-9;]*[mGKHF]//g' "$WORK/walker.out" > "$WORK/walker.plain"
if [[ "$walker_rc" != "0" ]] || [[ "$(ran_n "$WORK/walker.plain")" != "1" ]] \
   || ! LC_ALL=C grep -qE '^[[:space:]]*1 pass$' "$WORK/walker.plain"; then
  printf 'FATAL: walker arm "%s" did not pass in isolation (rc %s) — the scratch tree does not resolve infra/\n' "$WALKER_TITLE" "$walker_rc" >&2
  tail -8 "$WORK/walker.plain" >&2; exit 2
fi
printf 'control: pristine suite GREEN (Ran %s, %s expect() calls; %s fixture arms)\n' "$PRISTINE_TOTAL" "$CONTROL_CALLS" "$FIXTURE_ARMS"

# ---- MUTATION ROWS -----------------------------------------------------------------------------
printf '=== the shared helpers read comment-stripped source ===\n'
row_red R1 extractStripRegex 'stripHclLineComments(tfSrc)' 'tfSrc' "$A1" \
  'extractStripRegex reads RAW source — a commented decoy becomes a second definition'
row_red R2 stripIsApplied 'stripHclLineComments(tfSrc)' 'tfSrc' "$A6" \
  'stripIsApplied reads RAW source — a comment naming the chain returns true (#7965)'

row_red R5 stripHclLineComments 'if (c === "/" && line[i + 1] === "*") {' 'if (false) {' "$A6B" \
  'stripHclLineComments keeps /* block */ comments — a block-commented render returns true'
row_red R7 stripHclLineComments 'if (c === "#" || (c === "/" && line[i + 1] === "/")) break;' 'if (false) break;' "$A1B" \
  'stripHclLineComments keeps trailing # comments — a trailing-comment decoy definition is captured'

printf '=== the shared helpers require uniqueness, the balanced-call bound, arg position, every link ===\n'
row_red R3 stripIsApplied 'if (anchors.length > 1)' 'if (false && anchors.length > 1)' "$A7" \
  'stripIsApplied accepts a second anchor (first-match semantics)'
row_red R4 extractStripRegex 'if (all.length > 1)' 'if (false && all.length > 1)' "$A2" \
  'extractStripRegex accepts a duplicate live definition'
row_red R6 stripIsApplied 'const region = src.slice(start, end + 1);' 'const region = src;' "$A9" \
  'stripIsApplied drops the anchor-call bound — an earlier unrelated replace() using the local certifies the render'
row_red R8 stripIsApplied 'return chain.every((re) => re.test(src));' 'return chain.slice(1).every((re) => re.test(src));' "$A8F" \
  'stripIsApplied skips the first chain link — a bypassed _b64gz render returns true'
row_red R9 stripIsApplied 'if (args[1] !== `local.${localName}`) return false;' 'if (!region.includes(`local.${localName}`)) return false;' "$A11V" \
  'stripIsApplied accepts a mention in the span instead of replace()'"'"'s second argument (M14)'

# ---- HARNESS ROWS ------------------------------------------------------------------------------
printf '=== harness self-test ===\n'
# H1: the battery cannot mark a GREEN run as RED.
if expect_red H1 "$A1" "$CONTROL_PLAIN" 0; then
  printf '  %-4s %-5s (want %-5s) SURVIVED — expect_red certified the control (green) output\n' H1 ok fail
  FAIL=$((FAIL+1)); RESULTS+=("H1 SURVIVED")
else
  ok H1 fail fail 'expect_red refuses the control output (a green run is not RED)'
fi

# H1b: the named-arm grep is live — R1's own output (A1 red, A2 green) with the WRONG title.
if [[ -s "$WORK/R1.rc" && -f "$WORK/R1.out.plain" ]]; then
  if expect_red H1b "$A2" "$WORK/R1.out.plain" "$(cat "$WORK/R1.rc")"; then
    printf '  %-4s %-5s (want %-5s) SURVIVED — expect_red accepted a wrong arm title against R1 output\n' H1b ok fail
    FAIL=$((FAIL+1)); RESULTS+=("H1b SURVIVED")
  else
    ok H1b fail fail 'expect_red refuses the wrong arm title against R1 output (rc alone is not RED)'
  fi
else
  printf '  %-4s LANDING-FAILED (R1 produced no output/rc to test against)\n' H1b
  FAIL=$((FAIL+1)); RESULTS+=("H1b LANDING-FAILED")
fi

# H2: a benign single-occurrence edit stays GREEN — the battery is not rejecting every edit.
restore
if ! mutate extractStripRegex 'const all = [' 'const all /* benign */ = ['; then
  landing H2 'benign edit'; restore
else
  run_suite "$WORK/H2.out"
  if expect_green "$WORK/H2.out.plain" "$RC"; then ok H2 GREEN GREEN 'a benign single-occurrence edit stays GREEN'
  else survived H2 RED GREEN 'a benign single-occurrence edit stays GREEN'; fi
  restore
fi

# H3: re-applying R1 to a copy on which R1 already landed is LANDING-FAILED (returns 2) — a
# renamed helper cannot make a row a silent no-op.
restore
if ! mutate extractStripRegex 'stripHclLineComments(tfSrc)' 'tfSrc'; then
  landing H3 'first application of R1 for H3'; restore
else
  mutate extractStripRegex 'stripHclLineComments(tfSrc)' 'tfSrc'; h3rc=$?
  if [[ "$h3rc" == "2" ]] && LC_ALL=C grep -q 'anchor missing' "$WORK/mut.err"; then
    ok H3 rc2 rc2 'a second application of R1 is reported as LANDING-FAILED (anchor missing)'
  else
    printf '  %-4s rc%-3s (want rc2  ) SURVIVED — a drifted anchor would be a silent no-op\n' H3 "$h3rc"
    FAIL=$((FAIL+1)); RESULTS+=("H3 SURVIVED")
  fi
  restore
fi

# H4: the `Ran N == pristine` discriminator is live — a synthetic load-time-break output.
{
  printf '%s%s [0.10ms]\n' "$ARM_PREFIX" "$A1"
  printf ' 0 pass\n 1 fail\n 1 error\nRan 1 test across 1 file. [5.00ms]\n'
} > "$WORK/H4.synthetic.plain"
# The error line is present too, so strip it for a SECOND probe: the Ran discriminator alone must
# refuse, not only the error-line term.
LC_ALL=C grep -vE '^[[:space:]]*1 error$' "$WORK/H4.synthetic.plain" > "$WORK/H4.noerr.plain"
if expect_red H4 "$A1" "$WORK/H4.noerr.plain" 1; then
  printf '  %-4s %-5s (want %-5s) SURVIVED — expect_red accepted a Ran 1 output as RED\n' H4 ok fail
  FAIL=$((FAIL+1)); RESULTS+=("H4 SURVIVED")
elif ! LC_ALL=C grep -q 'Ran 1 != pristine' "$WORK/why"; then
  printf '  %-4s %-5s (want %-5s) SURVIVED — refused for the wrong reason: %s\n' H4 fail fail "$(cat "$WORK/why")"
  FAIL=$((FAIL+1)); RESULTS+=("H4 SURVIVED")
else
  ok H4 fail fail 'expect_red refuses a synthetic Ran 1 output (load-time break is INVALID, not RED)'
fi

# K1: a known SURVIVOR through the real row runner. A benign edit is driven through row_red
# expecting RED; it must be REPORTED as SURVIVED (FAIL +1, RESULTS gains "K1 SURVIVED"), then the
# row is netted out. A row_red whose verdict branch is `if true`, or a survived() that counts into
# PASS, leaves FAIL unmoved and this row records the harness defect instead.
k_fail_before=$FAIL; k_pass_before=$PASS; k_len_before=${#RESULTS[@]}
row_red K1 extractStripRegex 'const all = [' 'const all /* benign */ = [' "$A1" \
  '(harness control) a benign edit driven through row_red'
if (( FAIL == k_fail_before + 1 && PASS == k_pass_before )) && [[ "${RESULTS[-1]}" == "K1 SURVIVED" ]]; then
  FAIL=$k_fail_before; RESULTS=("${RESULTS[@]:0:$k_len_before}")
  ok K1 surv surv 'row_red reports a known survivor as SURVIVED (netted out)'
else
  printf '  %-4s (want SURVIVED via FAIL+1) SURVIVED — row_red/survived() did not record the known survivor (FAIL %s->%s, PASS %s->%s)\n' K1 "$k_fail_before" "$FAIL" "$k_pass_before" "$PASS"
  FAIL=$((k_fail_before+1)); PASS=$k_pass_before; RESULTS=("${RESULTS[@]:0:$k_len_before}" "K1 SURVIVED")
fi

# K2: a known LANDING failure through the real row runner (a drifted anchor).
k_fail_before=$FAIL; k_pass_before=$PASS; k_len_before=${#RESULTS[@]}
row_red K2 extractStripRegex 'this anchor does not exist in the helper' 'x' "$A1" \
  '(harness control) a drifted anchor driven through row_red'
if (( FAIL == k_fail_before + 1 && PASS == k_pass_before )) && [[ "${RESULTS[-1]}" == "K2 LANDING-FAILED" ]]; then
  FAIL=$k_fail_before; RESULTS=("${RESULTS[@]:0:$k_len_before}")
  ok K2 land land 'row_red reports a drifted anchor as LANDING-FAILED (netted out)'
else
  printf '  %-4s (want LANDING-FAILED via FAIL+1) SURVIVED — row_red/landing() did not record the known landing failure (FAIL %s->%s, PASS %s->%s)\n' K2 "$k_fail_before" "$FAIL" "$k_pass_before" "$PASS"
  FAIL=$((k_fail_before+1)); PASS=$k_pass_before; RESULTS=("${RESULTS[@]:0:$k_len_before}" "K2 SURVIVED")
fi

restore
printf '\n=== summary ===\n'
printf '  %d ok, %d problem(s)\n' "$PASS" "$FAIL"
for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done

# Reported by direct printf and its OWN exit, never through the FAIL counter the rows above
# increment: a floor that shares a lifetime with what it guards is not a floor.
EXPECTED_ROWS=16
if (( PASS + FAIL != EXPECTED_ROWS )); then
  printf 'FLOOR: ran %d rows, expected %d\n' "$((PASS+FAIL))" "$EXPECTED_ROWS" >&2
  exit 1
fi
if ! diff -q "$PRISTINE" "$SUT" >/dev/null 2>&1; then
  printf 'FLOOR: restore did not return the scratch copy to pristine\n' >&2
  exit 1
fi
if ! diff -q "$TRACKED" "$PRISTINE" >/dev/null 2>&1; then
  printf 'FLOOR: the tracked suite differs from the pristine copy taken at start\n' >&2
  exit 1
fi
printf '  restore verified clean (scratch copy mutated only; the tracked suite was never written)\n'
if (( FAIL > 0 )); then exit 1; fi
exit 0
