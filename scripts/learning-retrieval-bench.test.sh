#!/usr/bin/env bash
# learning-retrieval-bench.test.sh — nothing ran `learning-retrieval-bench.sh --self-test` in CI, so
# its red state went unnoticed for 18 days (2026-09-20 .. 2026-10-08) and a caller's environment
# could change its result.
#
# PROPERTY. `--self-test` is HERMETIC: its verdict does not depend on the caller's environment, and
# it never reaches the network.
#   * An exported NO_PARAPHRASE=1 (the production kill switch) must not disable the Stage 2 rows;
#     without the reset in self_test() the run is 173 passed / 4 failed.
#   * An exported ANTHROPIC_API_KEY must not turn the Stage 2 rows into live API calls; without the
#     reset, kbsearch_rank passes its key gate and the real curl is invoked with the caller's key.
#
# ASSEMBLY. ONE run of the real script as a subprocess, under `env -i` plus an allowlist (no
# inherited GIT_*), with the hostile values set and CURL_BIN pointing at a recording stub this suite
# owns. One run is enough: the hostile environment is a superset of the clean one. The stub is
# exercised once by the suite itself (positive control: the count must read 1) and then truncated, so
# a zero count after the run means "no call reached it", not "the recorder cannot count". Stage 2
# and the api-key rows install their own local curl stubs, so any call that reaches THIS recorder is
# a leak by construction.
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

# ---- verdict helpers + instrument self-test --------------------------------------------------------
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
_sp=$PASS; _sf=$FAIL
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
if (( PASS != _sp + 1 )) || (( FAIL != _sf + 1 )); then
  echo "[FATAL] instrument self-test failed" >&2; exit 1
fi
PASS=$_sp; FAIL=$_sf

check() { # check <name> <rc-of-condition>
  if [[ "$2" == 0 ]]; then pass "$1"; else fail "$1"; fi
}

[[ -f "$SCRIPT" ]] || { echo "[FATAL] script under test not found: $SCRIPT" >&2; exit 2; }

# ---- the recording curl stub (this suite's own) ----------------------------------------------------
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
HOME_DIR="$TESTROOT/home"; mkdir -p "$HOME_DIR" "$TESTROOT/tmp"
# A synthetic key SHAPE (passes the script's own character check, matches no vendor pattern).
SYNTH_KEY="synthetic-selftest-leak-probe-key"
OUT="$TESTROOT/selftest.out"
env -i PATH="$PATH" HOME="$HOME_DIR" TMPDIR="$TESTROOT/tmp" LC_ALL=C \
  NO_PARAPHRASE=1 ANTHROPIC_API_KEY="$SYNTH_KEY" CURL_BIN="$REC" \
  bash "$SCRIPT" --self-test > "$OUT" 2>&1
RUN_RC=$?

check "self-test exits 0 under NO_PARAPHRASE=1 + an exported key + a hostile CURL_BIN" "$([[ "$RUN_RC" == 0 ]] && echo 0 || echo 1)"

SUMMARY="$(grep -E '^== summary: PASS=[0-9]+ +FAIL=[0-9]+ +TOTAL=[0-9]+ ==$' "$OUT" | tail -n 1)"
check "the summary line is present (the run reached its end)" "$([[ -n "$SUMMARY" ]] && echo 0 || echo 1)"

S_FAIL="$(printf '%s' "$SUMMARY" | sed -n 's/.* FAIL=\([0-9][0-9]*\) .*/\1/p')"
S_TOTAL="$(printf '%s' "$SUMMARY" | sed -n 's/.* TOTAL=\([0-9][0-9]*\) .*/\1/p')"
check "no row failed (FAIL=0)" "$([[ "$S_FAIL" == 0 ]] && echo 0 || echo 1)"

# The bench's own floor; read from the script so this suite cannot drift from it.
MIN_TOTAL="$(sed -n 's/^[[:space:]]*ST_MIN_ASSERTIONS=\([0-9][0-9]*\).*/\1/p' "$SCRIPT" | head -n 1)"
check "the bench's own assertion floor was found in the script" "$([[ -n "$MIN_TOTAL" ]] && echo 0 || echo 1)"
check "TOTAL reaches the bench's own floor (${S_TOTAL:-?} >= ${MIN_TOTAL:-?})" \
  "$([[ -n "$S_TOTAL" && -n "$MIN_TOTAL" && "$S_TOTAL" -ge "$MIN_TOTAL" ]] && echo 0 || echo 1)"

# The two rows the leaks silence or distort.
check "row present: Stage 2 union-of-paraphrases recovers target" \
  "$(grep -qF 'PASS: paraphrase-prepass: Stage 2 union-of-paraphrases recovers target' "$OUT" && echo 0 || echo 1)"
check "row present: api-key precondition (the key rows are not vacuous)" \
  "$(grep -qF 'PASS: api-key: precondition' "$OUT" && echo 0 || echo 1)"

# Zero reached the global recorder: Stage 2 and the key rows stub curl locally, so any call here leaked.
check "no call reached the global CURL_BIN (leaked calls: $(calls_count))" "$([[ "$(calls_count)" == 0 ]] && echo 0 || echo 1)"

# Floor on this suite's own assertions, reported with printf + exit (never through the helpers it guards).
TOTAL_CHECKS=$((PASS + FAIL))
if (( TOTAL_CHECKS < 9 )); then
  printf '[FAIL] only %s assertions ran (floor 9)\n' "$TOTAL_CHECKS" >&2
  exit 1
fi

printf '\n== %s passed, %s failed ==\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  echo "---- self-test output tail ----" >&2
  tail -n 15 "$OUT" >&2
  exit 1
fi
exit 0
