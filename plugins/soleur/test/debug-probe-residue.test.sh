#!/usr/bin/env bash
# Guard 4 (#8288, ADR-230): no temporary debug probe survives in Soleur's own tracked tree.
#
# PROPERTY. No tracked file outside `knowledge-base/**/*.md` contains a real `[DEBUG-<hex4>]`
# tag (either case) or EMITS a `SOLEUR_[A-Z_]*DEBUG` marker. The first is the removable probe
# class; the second is a probe spelled with the permanent-marker prefix, which the marker drift
# guard's SENTINEL_RE does not see at the realistic injection site (a log call). ADR-230 holds
# the two-class table; this file enforces the tree-wide consequence.
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
# ANTI-VACUITY (ADR-193). Three rows, one independent `cases` counter moved at each call site
# (never inside ok()/bad(), never inside `$( ... )`), a conservation check, `MIN_CASES=3`
# in the shape `scripts/guard-vacuity-floor.test.sh` derives, and a population floor. Every
# floor reports with `printf >&2` + `exit 1` directly, never through the verdict helpers.
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

# The D4 predicate, tracked-files form. `-i` because a hand-typed uppercase tag is the
# realistic leak; `-l` because the finding is the PATH; `-E` for the `{4}` quantifier. The
# exclusion is the markdown under knowledge-base/ only -- a learning may quote a real tag from
# a session -- and NOT the whole directory: executables are tracked under knowledge-base/ too.
P1_RE='\[DEBUG-[0-9a-f]{4}\]'
# The emit call-form only. The bare token `SOLEUR_[A-Z_]*DEBUG` is red on today's tree:
# `apps/web-platform/server/permission-log.ts` READS `process.env.SOLEUR_DEBUG_PERMISSION_LAYER`,
# a legitimate env flag, and its test names it too. Reading a flag is not emitting a marker.
# The predicate therefore anchors on the emit sites -- `echo "`, `printf <any>`, and a
# `console.<level>(` opened with any of the three JS quote characters -- immediately followed
# by the token. Case-sensitive: the permanent class is upper-case by definition.
P2_RE='(echo "|printf .|console\.(log|debug|warn|error)\(["'"'"'`])SOLEUR_[A-Z_]*DEBUG'
EXCLUDE=':!knowledge-base/**/*.md'

# Runs one predicate. Prints every hit on stdout, prefixed, and returns 0 (residue), 1 (clean)
# or dies on a tool error. Captured with the exit decided explicitly: under `set -e` a bare
# `x=$(git grep ...)` would abort the suite on the CLEAN answer.
scan() { # <label> <grep-flags> <regex>
  local label="$1" flags="$2" re="$3" hits rc=0
  hits="$(git grep "$flags" -e "$re" -- . "$EXCLUDE")" || rc=$?
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
scan "predicate 2" -lE "$P2_RE" || p2_rc=$?
cases=$((cases + 1))
if [[ "$p2_rc" -eq 1 ]]; then
  ok "predicate 2: no tracked file emits a SOLEUR_*DEBUG marker via echo/printf/console.<level> (env READS of such a flag are not emits and are not matched)"
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
# Exactly three rows exist (predicate 1, predicate 2, population); fewer means a row was
# deleted or skipped, and a green run here would be a coverage loss. The threshold sits on the
# line directly above its `if` so guard-vacuity-floor's backward slice-widening binds it.
MIN_CASES=3
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
