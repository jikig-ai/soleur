#!/usr/bin/env bash
# Guard 4 (#8288, ADR-230): no temporary debug probe survives in Soleur's own tracked tree.
#
# PROPERTY. No tracked file outside `knowledge-base/**/*.md` contains a real `[DEBUG-<hex4>]`
# tag (either case) or EMITS a `SOLEUR_[A-Z_]*DEBUG` marker on one of the emit call-forms this
# tree uses: `echo`/`printf`/bash `log "…"`, JS `console.<level>(`, pino `log.<level>({ KEY:` or
# `(“…`, `logger.<level>(`, `process.std{out,err}.write(`, python `print(`. The first is the
# removable probe class; the second is a probe spelled with the permanent-marker prefix, which
# the marker drift guard's SENTINEL_RE does not see at the realistic injection site (a log
# call). Env READS (`process.env.SOLEUR_*`) are excluded at line level, not by narrowing the
# emit anchor. Untracked and ignored files, submodules, and a form outside that list are out of
# scope (the prose gate in reproduce-bug Phase 9 covers untracked files with `--untracked`).
# ADR-230 holds the two-class table; this file enforces the tree-wide consequence.
#
# ASSEMBLY. Two `git grep -l` predicates over one derived population, run from the repo
# toplevel because the exclusion pathspec is cwd-relative. `git grep -l` exits 1 on no match,
# which is the CLEAN verdict; 0 means residue (the paths are the finding); >=2 is a tool error
# and is fatal, never a verdict. No `-I`: git's binary heuristic skips a UTF-8 `.ts` carrying
# one NUL byte and anything under a `-diff` gitattribute (measured), and a probe hidden that
# way is exactly the residue this guard exists to name. Predicates run FIRST and print every
# finding on stdout; the population floor runs LAST, so a RED row is observable by the named
# path and not only by rc.
#
# THIS FILE IS IN ITS OWN POPULATION. It is tracked, and it is not under `knowledge-base/`, so
# nothing in it may spell a concrete four-hex tag or an emit-form `SOLEUR_*DEBUG` literal. The
# regexes below do not match themselves (measured: predicate 1 is rc 1 with this file tracked);
# every prose mention uses the `<hex4>` placeholder. Do not add an example tag to a comment.
#
# ARGUMENTS. `$1` is the repo to scan (default: this suite's own repo). `$2` is
# MIN_POPULATION (default 2500, derived from 5168 tracked files outside knowledge-base/ on
# 2026-09-19 -- a floor, not a pin, so the tree can shrink by half before it trips). The
# argument exists so the RED rows of the mutation matrix run against SYNTHESIZED throwaway
# repos with MIN_POPULATION=1 (`cq-test-fixtures-synthesized-only`), never against a probe
# planted in the real tree. The must-PASS rows run against the real tree with the defaults.
#
# ANTI-VACUITY (ADR-193). Three tree rows plus in-suite positive/negative controls of both
# predicates on a SYNTHESIZED throwaway repo (every marker token and tag is assembled at run
# time so this file never carries one), one independent `cases` counter moved at each call
# site (never inside ok()/bad(), never inside `$( ... )`), an instrument self-test, a
# conservation check, `MIN_CASES` in the shape `scripts/guard-vacuity-floor.test.sh` derives,
# and a population floor. Every floor reports with `printf >&2` + `exit 1` directly, never
# through the verdict helpers.
#
# Auto-registers via scripts/test-all.sh's `plugins/soleur/test/*.test.sh` glob.
set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# `git -C <dir> rev-parse --show-toplevel` on BOTH the default and the argument: the default
# is resolved from this file's own location (not the caller's cwd, which under the scripts
# shard is whatever the runner left behind), and the argument is normalised to its toplevel
# so a caller pointing at a subdirectory still scans the whole tree. The default is resolved
# ONLY when no argument is given: a sandbox copy of this file (the mutation matrix runs the
# SUT rows on one, outside any checkout) must be able to scan the repo it is pointed at.
if [[ -n "${1:-}" ]]; then
  ROOT_ARG="$1"
else
  ROOT_ARG="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
fi
ROOT="$(git -C "$ROOT_ARG" rev-parse --show-toplevel)"
MIN_POPULATION="${2:-2500}"
case "$ROOT" in
  /?*) : ;;
  *)   printf '[FATAL] repo root did not resolve to an absolute path: %q\n' "$ROOT" >&2; exit 2 ;;
esac
case "$MIN_POPULATION" in
  ''|*[!0-9]*) printf '[FATAL] MIN_POPULATION must be a non-negative integer, got %q\n' "$MIN_POPULATION" >&2; exit 2 ;;
esac
cd "$ROOT"

pass=0
fail=0
# The INDEPENDENT case counter (ADR-193 #2). Incremented at every CALL SITE, never inside
# ok()/bad(): a counter that moves with the verdict makes `pass + fail == cases` a tautology.
cases=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }
# Instrument self-test -- DIRECTION, not only presence (a bad() misrouted to `pass` keeps the
# conservation check and the floor green). Reported via printf >&2 + exit 1, never through the
# helper it checks (ADR-193).
bad "instrument self-test (expected -- proves bad() records a FAILURE)" >/dev/null
ok  "instrument self-test (expected -- proves ok() records a PASS)" >/dev/null
if [[ "$fail" != "1" || "$pass" != "1" ]]; then
  printf '[FATAL] HELPER CONTROL BROKEN: after one bad() and one ok(), fail=%s pass=%s (want 1/1)\n' "$fail" "$pass" >&2
  exit 1
fi
pass=0; fail=0

# The D4 predicate, tracked-files form. `-i` because a hand-typed uppercase tag is the
# realistic leak; `-l` because the finding is the PATH; `-E` for the `{4}` quantifier. The
# exclusion is the markdown under knowledge-base/ only -- a learning may quote a real tag from
# a session -- and NOT the whole directory: executables are tracked under knowledge-base/ too.
P1_RE='\[DEBUG-[0-9a-f]{4}\]'
# The emit call-forms this tree actually uses (measured 2026-09-19: 11 of the 12 real
# `SOLEUR_*` emits under apps/web-platform/server are the pino object form
# `log.warn({ SOLEUR_X: true, ...m }, "...")`; skill scripts use `echo "`/`printf '`/`log "`),
# with the token ANYWHERE later on the same line -- a prefix string, a template literal with an
# interpolation first, or a space after `(` must not hide it. The bare token alone is red on
# today's tree: `apps/web-platform/server/permission-log.ts` READS
# `process.env.SOLEUR_DEBUG_PERMISSION_LAYER`, a legitimate env flag, and its test names it too;
# reading a flag is not emitting a marker, so those LINES are excluded below (P2_LINE_EXCLUDE),
# never by narrowing the emit anchor. Case-sensitive: the permanent class is upper-case.
P2_RE='(\becho\b|\bprintf\b|\blog "|\bprint\(|console\.[a-z]+\(|\b(log|logger)\.(trace|debug|info|warn|error|fatal)\(|process\.std(out|err)\.write\()[^;]*SOLEUR_[A-Z_]*DEBUG'
P2_LINE_EXCLUDE='process\.env\.SOLEUR_[A-Z_]*DEBUG'
EXCLUDE=':!knowledge-base/**/*.md'

# Runs one predicate in the cwd. Prints every hit on stdout, prefixed, and returns 0 (residue),
# 1 (clean) or dies on a tool error. Captured with the exit decided explicitly: under `set -e` a
# bare `x=$(git grep ...)` would abort the suite on the CLEAN answer. With <line-exclude>, hits
# are taken per LINE (`-n`) and lines matching it are dropped before the verdict.
scan() { # <label> <grep-flags> <regex> [<line-exclude>]
  local label="$1" flags="$2" re="$3" lx="${4:-}" hits rc=0
  if [[ -n "$lx" ]]; then
    hits="$(git grep -nE -e "$re" -- . "$EXCLUDE")" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      hits="$(printf '%s\n' "$hits" | grep -vE "$lx" || true)"
      [[ -n "$hits" ]] || rc=1
    fi
  else
    hits="$(git grep "$flags" -e "$re" -- . "$EXCLUDE")" || rc=$?
  fi
  if [[ "$rc" -gt 1 ]]; then
    printf '[FATAL] %s: git grep exited %d -- a tool error, not a verdict.\n' "$label" "$rc" >&2
    exit 2
  fi
  if [[ "$rc" -eq 0 ]]; then
    printf '%s\n' "$hits" | sed "s|^|  residue ($label): |"
  fi
  return "$rc"
}

echo "debug-probe-residue: scanning $ROOT"

# --- Row 1: no real [DEBUG-<hex4>] tag in any tracked file outside knowledge-base/**/*.md ---
p1_rc=0
scan "predicate 1" -liE "$P1_RE" || p1_rc=$?
cases=$((cases + 1))
if [[ "$p1_rc" -eq 1 ]]; then
  ok "predicate 1: no tracked file outside knowledge-base/**/*.md carries a [DEBUG-<hex4>] tag (either case)"
else
  bad "predicate 1: the file(s) named above carry a [DEBUG-<hex4>] probe tag -- remove the probe, do not stage its removal as a fix (ADR-230, D4)"
fi

# --- Row 2: no tracked file EMITS a SOLEUR_*DEBUG marker ---------------------------------
p2_rc=0
scan "predicate 2" -lE "$P2_RE" "$P2_LINE_EXCLUDE" || p2_rc=$?
cases=$((cases + 1))
if [[ "$p2_rc" -eq 1 ]]; then
  ok "predicate 2: no tracked file emits a SOLEUR_*DEBUG marker on any listed call-form (env READS of such a flag are excluded per line, not by narrowing the anchor)"
else
  bad "predicate 2: the file(s) named above EMIT a SOLEUR_*DEBUG marker -- a temporary probe never wears the permanent-marker prefix; respell it [DEBUG-<hex4>] or promote it through MARKER_RE (ADR-230)"
fi

# --- Row 3: the population the predicates ran over is the one the floor measures -----------
# `git ls-files` is the index, outside any one file's control. The predicate pathspec excludes
# only `knowledge-base/**/*.md`; the population pathspec excludes all of `knowledge-base/`.
# The former is therefore a SUPERSET of the latter, and the row pins that: a predicate scope
# that ever became narrower than the counted population would be claiming coverage it does
# not have. Both counts are index reads, so neither can be satisfied by the predicates.
population="$(git ls-files -- . ':!knowledge-base' | wc -l | tr -d ' ')"
predicate_scope="$(git ls-files -- . "$EXCLUDE" | wc -l | tr -d ' ')"
cases=$((cases + 1))
if [[ "$population" =~ ^[0-9]+$ && "$predicate_scope" =~ ^[0-9]+$ && "$predicate_scope" -ge "$population" ]]; then
  ok "population: $population tracked file(s) outside knowledge-base/; the predicate scope ($predicate_scope files) covers all of them"
else
  bad "population: predicate scope ($predicate_scope) is NARROWER than the counted population ($population) -- the exclusion pathspecs have drifted apart"
fi

# --- Rows 4..: instrument controls on a SYNTHESIZED repo ------------------------------------
# One throwaway git repo, one file per emit form (positives) plus the env-read negative. The
# marker token and the hex tag are ASSEMBLED at run time (`DEB""UG`, printf %04x) so this file
# never carries a concrete emit-form literal or tag itself. A control that cannot go red is not
# a control: each positive must be found, the negative must not.
CTRL_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$CTRL_ROOT"' EXIT INT TERM
case "$CTRL_ROOT" in /?*) : ;; *) printf '[FATAL] mktemp gave %q\n' "$CTRL_ROOT" >&2; exit 2 ;; esac
# Hermetic git environment for the control repo (the repo's chokepoint, #7849): sweeps inherited
# GIT_*, GIT_CONFIG_GLOBAL=/dev/null, synthesized identity. The three tree rows above already ran
# against $ROOT; the ceiling this pins (the control repo's parent) does not reach $ROOT.
# shellcheck source=./lib/git-fixture-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-fixture-env.sh"
git_fixture_env "$CTRL_ROOT" || { printf '[FATAL] git_fixture_env refused %s\n' "$CTRL_ROOT" >&2; exit 2; }
M="SOLEUR_PROBE_DEB""UG"
TAG="[DEBUG-$(printf '%04x' 43981)]"
git -C "$CTRL_ROOT" init -q
mkdir -p "$CTRL_ROOT/knowledge-base/notes"
printf 'echo "%s fired"\n' "$M"                                   > "$CTRL_ROOT/p-echo-dq.sh"
printf "echo '%s fired'\n" "$M"                                   > "$CTRL_ROOT/p-echo-sq.sh"
printf 'echo probe: %s\n' "$M"                                    > "$CTRL_ROOT/p-echo-bare.sh"
printf "printf '%%s%s' \"%s\"\n" '\n' "$M"                          > "$CTRL_ROOT/p-printf-fmt.sh"
printf 'log "%s: step 3"\n' "$M"                                  > "$CTRL_ROOT/p-log-helper.sh"
printf 'console.info("%s");\n' "$M"                               > "$CTRL_ROOT/p-console-info.ts"
printf 'console.log( `ctx ${id} %s`);\n' "$M"                     > "$CTRL_ROOT/p-console-tpl.ts"
printf 'log.warn({ %s: true, ...m }, "probe");\n' "$M"            > "$CTRL_ROOT/p-pino-key.ts"
printf 'logger.info("%s");\n' "$M"                                > "$CTRL_ROOT/p-logger.ts"
printf 'process.stdout.write("%s%s");\n' "$M" '\n'                    > "$CTRL_ROOT/p-stdout.ts"
printf 'print("%s")\n' "$M"                                       > "$CTRL_ROOT/p-print.py"
printf 'const on = process.env.%s === "1";\n' "$M"                > "$CTRL_ROOT/n-env-read.ts"
printf 'const t = "%s";\n' "$TAG"                                 > "$CTRL_ROOT/p-tag.ts"
printf 'a session quoted %s here\n' "$TAG"                        > "$CTRL_ROOT/knowledge-base/notes/n-quoted-tag.md"
git -C "$CTRL_ROOT" add -A
git -C "$CTRL_ROOT" commit -q -m "controls"
# ctrl_scan <label> <flags> <regex> [<line-exclude>] -> rc, in the control repo, hits swallowed.
ctrl_scan() {
  local rc=0
  ( cd "$CTRL_ROOT" && scan "$@" >/dev/null ) || rc=$?
  return "$rc"
}
# ctrl_hits <regex> [<line-exclude>] -> the sorted list of paths predicate 2 names.
ctrl_hits() {
  local re="$1" lx="${2:-}" out
  out="$( cd "$CTRL_ROOT" && git grep -nE -e "$re" -- . "$EXCLUDE" | { if [[ -n "$lx" ]]; then grep -vE "$lx"; else cat; fi; } | cut -d: -f1 | LC_ALL=C sort -u | tr '\n' ' ' )" || true
  printf '%s' "$out"
}
P2_HITS="$(ctrl_hits "$P2_RE" "$P2_LINE_EXCLUDE")"
P2_WANT="p-console-info.ts p-console-tpl.ts p-echo-bare.sh p-echo-dq.sh p-echo-sq.sh p-log-helper.sh p-logger.ts p-pino-key.ts p-print.py p-printf-fmt.sh p-stdout.ts "
cases=$((cases + 1))
if [[ "$P2_HITS" == "$P2_WANT" ]]; then
  ok "control: predicate 2 names exactly the 11 positive emit forms and not the env read (${P2_HITS% })"
else
  bad "control: predicate 2 named [$P2_HITS] want [$P2_WANT]"
fi
P1_HITS="$(ctrl_hits "$P1_RE")"
cases=$((cases + 1))
if [[ "$P1_HITS" == "p-tag.ts " ]]; then
  ok "control: predicate 1 names the tracked tag and not the quoted tag under knowledge-base/**/*.md"
else
  bad "control: predicate 1 named [$P1_HITS] want [p-tag.ts ]"
fi
# The negative alone: with every positive removed, both predicates read CLEAN (rc 1) -- the
# line-level env exclusion is what keeps predicate 2 green, and the control proves it fires.
git -C "$CTRL_ROOT" rm -q --cached -- 'p-*' >/dev/null
rm -f -- "$CTRL_ROOT"/p-*
git -C "$CTRL_ROOT" commit -q -m "negatives only"
n1_rc=0; ctrl_scan "control p1" -liE "$P1_RE" || n1_rc=$?
n2_rc=0; ctrl_scan "control p2" -lE "$P2_RE" "$P2_LINE_EXCLUDE" || n2_rc=$?
cases=$((cases + 1))
if [[ "$n1_rc" -eq 1 && "$n2_rc" -eq 1 ]]; then
  ok "control: with only the env read and the quoted learning tracked, both predicates read CLEAN (rc 1/1)"
else
  bad "control: negatives-only repo read p1=$n1_rc p2=$n2_rc (want 1/1)"
fi

# --- Accounting conservation (ADR-193 #3, #4) -----------------------------------------------
# Ordered BEFORE the floor: a neutered ok()/bad() deflates the verdict counters, so the floor
# below would ALSO trip and would report the misleading "rows were deleted". This says "a
# verdict was discarded" instead. Reported with `printf >&2` + `exit 1` DIRECTLY, never
# through bad(): a check that reports by calling the verdict helper increments the very counter
# the exit status reads, so neutering bad() silences the rows AND the check meant to notice the
# silence. Every row records exactly one verdict, so pass+fail MUST equal cases; because
# `cases` moves at the CALL SITE and not inside the verdict helpers, the identity is a real
# constraint rather than a tautology. The literal `[FATAL] accounting` is load-bearing --
# guard-vacuity-floor's ARM 10 builds its conservation population by grepping that exact string.
if [[ $((pass + fail)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: pass+fail (%d) != cases (%d).\n' "$((pass + fail))" "$cases" >&2
  if [[ $((pass + fail)) -lt "$cases" ]]; then
    printf '  A row was counted but its verdict was not recorded -- that is what a neutered ok()/bad() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "debug-probe-residue.test.sh: $pass passed, $fail failed ($cases rows)"
  exit 1
fi

# --- Anti-vacuity floor (ADR-193 #1) -------------------------------------------------------
# Reads the INDEPENDENT `cases` counter and reports with `printf >&2` + `exit 1` DIRECTLY.
# Exactly six rows exist (predicate 1, predicate 2, population, three controls); fewer means a
# row was deleted or skipped, and a green run here would be a coverage loss. The threshold sits
# on the line directly above its `if` so guard-vacuity-floor's backward slice-widening binds it.
MIN_CASES=6
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_CASES" >&2
  printf '  Rows were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  echo "debug-probe-residue.test.sh: $pass passed, $fail failed ($cases rows)"
  exit 1
fi

# --- Population floor -- LAST, after every finding is already on stdout --------------------
# The operand is the index size, not a counter this file increments, so it is not what the
# meta-guard classifies (the `cases` floor above is). It answers a different question: did the
# predicates run over a real tree at all? A `$ROOT` pointed at an empty or wrong checkout
# scans nothing, both predicates return the clean rc 1, and without this floor the suite
# would print three green rows over zero files.
if [[ "$population" -lt "$MIN_POPULATION" ]]; then
  printf '\n[FATAL] population floor: only %d tracked file(s) outside knowledge-base/ in %s, expected >= %d.\n' \
    "$population" "$ROOT" "$MIN_POPULATION" >&2
  printf '  The predicates ran over an empty or wrong tree; a green verdict here would be vacuous.\n' >&2
  echo "debug-probe-residue.test.sh: $pass passed, $fail failed ($cases rows)"
  exit 1
fi

echo "debug-probe-residue.test.sh: $pass passed, $fail failed ($cases rows)"
echo "debug-probe-residue.test.sh: population $population tracked files outside knowledge-base/ (floor $MIN_POPULATION)"
[[ "$fail" -eq 0 ]]
