#!/usr/bin/env bash
# learning-retrieval-bench.test.sh — nothing ran `learning-retrieval-bench.sh --self-test` in CI, so
# its red state went unnoticed for 18 days (2026-09-20 .. 2026-10-08) and a caller's environment
# could change its result.
#
# PROPERTY. `--self-test` is HERMETIC: its verdict does not depend on the caller's environment and it
# never reaches the network. "The caller's environment" is the set of inputs the script reads:
#   * NO_PARAPHRASE=1 (the production kill switch) must not disable the Stage 2 rows; unreset, the
#     run is 173 passed / 4 failed.
#   * An exported ANTHROPIC_API_KEY must not turn the Stage 2 rows into live API calls; unreset,
#     kbsearch_rank passes its key gate and invokes the real curl with the caller's key.
#   * A caller's CURL_BIN must not be what a row calls.
#   * An inherited GIT_DIR / GIT_INDEX_FILE (a git hook exports them) must not redirect the script's
#     git calls or its fixture repositories: unscrubbed, the run dies with rc=128.
#   * LEARNINGS_ROOT / INDEX_PATH / OUTPUT_DIR / KB_DIR pointing nowhere must not matter.
#   * A TMPDIR holding a quote, a dollar sign or a backtick must not break the generated curl stubs
#     (they interpolate paths into a script body; unquoted, six rows fail).
#
# ASSEMBLY. ONE run of the real script as a subprocess from the repo root, under `env -i` plus an
# allowlist, with every hostile value above set at once. One run is enough: the hostile environment is
# a superset of the clean one. The run is judged on independent things: the exit code, a summary line
# with FAIL=0, a literal assertion-count floor that does not come from the script under test, and named
# rows that the leaks would silence or distort. A recording stub is passed as CURL_BIN: it is a SECOND
# layer only. self_test() overwrites CURL_BIN with its own fail-closed stub, so while that stub exists
# nothing can reach this recorder; the runtime leak guard is the in-script row "hermeticity: no row
# invoked the fail-closed default CURL_BIN", which this suite pins by name. The recorder takes over if
# that default is ever removed, and the suite proves it can count (positive control) so a zero is a
# measurement.
#
# AUTHORING (work/SKILL.md): never `producer | grep -q` under pipefail (grep a file or use [[ == ]]);
# rc is captured on its own line; verdict helpers are defined before any assertion and proven by an
# instrument self-test; scratch is mktemp-based with an owning EXIT trap.

# shellcheck disable=SC2016  # recorder stub body is single-quoted on purpose
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${LEARNING_RETRIEVAL_BENCH_SCRIPT:-$REPO_ROOT/scripts/learning-retrieval-bench.sh}"
export TMPDIR="${TMPDIR:-/var/tmp}"
TESTROOT="$(mktemp -d -t lrb-selftest.XXXXXXXX)" || exit 2

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
assert_fixture_dir "$TESTROOT"
# shellcheck disable=SC2329  # invoked through the EXIT trap
cleanup() { rm -rf -- "$TESTROOT"; }
trap cleanup EXIT INT TERM HUP

# The script resolves its repository from the working directory; a caller's cwd must not matter here.
cd "$REPO_ROOT" || exit 2

# ---- verdict helpers + instrument self-test --------------------------------------------------------
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
check() { # check <name> <rc-of-condition>
  if [[ "$2" == 0 ]]; then pass "$1"; else fail "$1"; fi
}
# Drive the verdict helpers once each: a helper that no longer moves its counters (or `check` routing a
# failure to pass) would otherwise report green with nothing asserted.
_sp=$PASS; _sf=$FAIL
check "instrument self-test (expected pass)" 0 >/dev/null 2>&1
check "instrument self-test (expected fail)" 1 >/dev/null 2>&1
if (( PASS != _sp + 1 )) || (( FAIL != _sf + 1 )); then
  echo "[FATAL] instrument self-test failed: check() does not route pass/fail to the right counter" >&2; exit 1
fi
PASS=$_sp; FAIL=$_sf

[[ -f "$SCRIPT" ]] || { echo "[FATAL] script under test not found: $SCRIPT" >&2; exit 2; }

# ---- the recording curl stub (second layer; see ASSEMBLY) ------------------------------------------
CALLS="$TESTROOT/curl-calls"
REC="$TESTROOT/curl-recorder"
: > "$CALLS"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "call" >> "'"$CALLS"'"' 'exit 7' > "$REC"
chmod +x "$REC"

calls_count() { wc -l < "$CALLS" | tr -d ' '; }

# Positive control: the recorder counts. Without this a zero below could mean "cannot count".
"$REC" --probe >/dev/null 2>&1
check "recorder positive control: one invocation is counted as 1" "$([[ "$(calls_count)" == 1 ]] && echo 0 || echo 1)"
: > "$CALLS"

# ---- the one run: real script, hostile environment -------------------------------------------------
HOME_DIR="$TESTROOT/home"; mkdir -p "$HOME_DIR"
# A TMPDIR with a space, a double quote, a dollar sign and a backtick: the generated curl stubs must
# survive it. Created as a real directory so mktemp inside the script works.
WEIRD_TMP="$TESTROOT/"'we ird"$x`y'
mkdir -p "$WEIRD_TMP"
# A synthetic key SHAPE (passes the script's own character check, matches no vendor pattern).
SYNTH_KEY="synthetic-selftest-leak-probe-key"
NOWHERE="$TESTROOT/does-not-exist"
OUT="$TESTROOT/selftest.out"
env -i PATH="$PATH" HOME="$HOME_DIR" TMPDIR="$WEIRD_TMP" LC_ALL=C \
  NO_PARAPHRASE=1 ANTHROPIC_API_KEY="$SYNTH_KEY" CURL_BIN="$REC" \
  GIT_DIR="$NOWHERE/git" GIT_INDEX_FILE="$NOWHERE/index" \
  LEARNINGS_ROOT="$NOWHERE/learnings" INDEX_PATH="$NOWHERE/INDEX.md" OUTPUT_DIR="$NOWHERE/out" KB_DIR="$NOWHERE/kb" \
  bash "$SCRIPT" --self-test > "$OUT" 2>&1
RUN_RC=$?

check "self-test exits 0 under every hostile input at once" "$([[ "$RUN_RC" == 0 ]] && echo 0 || echo 1)"

SUMMARY="$(grep -E '^== summary: PASS=[0-9]+ +FAIL=[0-9]+ +TOTAL=[0-9]+ ==$' "$OUT" | tail -n 1)"
check "the summary line is present (the run reached its end)" "$([[ -n "$SUMMARY" ]] && echo 0 || echo 1)"

S_FAIL="$(printf '%s' "$SUMMARY" | sed -n 's/.* FAIL=\([0-9][0-9]*\) .*/\1/p')"
S_TOTAL="$(printf '%s' "$SUMMARY" | sed -n 's/.* TOTAL=\([0-9][0-9]*\) .*/\1/p')"
check "no row failed (FAIL=0)" "$([[ "$S_FAIL" == 0 ]] && echo 0 || echo 1)"

# A literal floor owned by THIS suite. The script's own floor (ST_MIN_ASSERTIONS) lives in the file under
# test, so a lowered floor and a deleted section travel together; this one does not. Deleting a whole
# self-test section (the api-key guard alone is 100+ assertions) takes TOTAL far below it.
MIN_SELFTEST_TOTAL=170
check "TOTAL reaches this suite's independent floor (${S_TOTAL:-?} >= ${MIN_SELFTEST_TOTAL})" \
  "$([[ -n "$S_TOTAL" && "$S_TOTAL" -ge "$MIN_SELFTEST_TOTAL" ]] && echo 0 || echo 1)"

# The rows the leaks silence or distort, and the in-script runtime leak guard.
check "row present: Stage 2 union-of-paraphrases recovers target" \
  "$(grep -qF 'PASS: paraphrase-prepass: Stage 2 union-of-paraphrases recovers target' "$OUT" && echo 0 || echo 1)"
check "row present: api-key precondition (the key rows are not vacuous)" \
  "$(grep -qF 'PASS: api-key: precondition' "$OUT" && echo 0 || echo 1)"
check "row present: api-key guard must-pass (the key section ran to its end)" \
  "$(grep -qF 'PASS: api-key guard must-pass: the key is delivered intact on stdin' "$OUT" && echo 0 || echo 1)"
check "row present: the in-script hermeticity leak guard" \
  "$(grep -qF 'PASS: hermeticity: no row invoked the fail-closed default CURL_BIN' "$OUT" && echo 0 || echo 1)"

# Second layer: zero reached the wrapper's recorder (it takes over if the script's own default is removed).
check "no call reached the wrapper's recorder (calls: $(calls_count))" "$([[ "$(calls_count)" == 0 ]] && echo 0 || echo 1)"

# Floor on this suite's own assertions, reported with printf + exit (never through the helpers it guards).
MIN_CASES=10
TOTAL_CHECKS=$((PASS + FAIL))
if (( TOTAL_CHECKS < MIN_CASES )); then
  printf '[FAIL] only %s assertions ran (floor %s)\n' "$TOTAL_CHECKS" "$MIN_CASES" >&2
  exit 1
fi

printf '\n== %s passed, %s failed ==\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  echo "---- self-test output tail ----" >&2
  tail -n 15 "$OUT" >&2
  exit 1
fi
exit 0
