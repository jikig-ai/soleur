#!/usr/bin/env bash
# Suite for workspaces-plaintext-hold-9348.sh: drives every exit arm through a stub gh and a fixed clock.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/workspaces-plaintext-hold-9348.sh"
# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh. plugins/soleur/test/fixture-dir-operand-assert.test.sh
# compares every copy in the tree against that one with comments stripped — edit there, then
# re-sync here.
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

SUITE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/ft-hold-9348.XXXXXX")
assert_fixture_dir "$SUITE_TMP"
trap 'rm -rf "$SUITE_TMP"' EXIT

pass=0; failc=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { failc=$((failc + 1)); printf 'FAIL %s\n' "$1"; }

# Reporter self-test: each helper must move its own counter, or the verdict below means nothing.
ok "selftest-ok" >/dev/null; no "selftest-no" >/dev/null
if [ "$pass" -ne 1 ] || [ "$failc" -ne 1 ]; then
  printf 'INSTRUMENT FAIL: pass/fail=%s/%s after one call each\n' "$pass" "$failc" >&2
  exit 2
fi
pass=0; failc=0

# Stub gh. It accepts EXACTLY the two argv shapes the probe must send and answers 64 to anything
# else, so a wrong PR number, repo, workflow, branch, status filter, limit, json field list or any
# write verb turns the verdict into exit 3 instead of passing silently. Every call is logged.
BIN="$SUITE_TMP/bin"
mkdir -p "$BIN"
assert_fixture_dir "$BIN"
STUB="$BIN/gh"
assert_fixture_dir "$STUB"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
[ -n "${STUB_CALLS:-}" ] && printf '%s\n' "$*" >> "$STUB_CALLS"
case "$*" in
  "pr view 9348 --repo jikig-ai/soleur --json state,mergedAt,baseRefName")
    printf '%s' "${PR_OUT:-}"; exit "${PR_RC:-0}" ;;
  "run list --repo jikig-ai/soleur --workflow workspaces-plaintext-forget.yml --branch main --status success --limit 100 --json updatedAt")
    printf '%s' "${RUN_OUT:-}"; exit "${RUN_RC:-0}" ;;
esac
echo "stub gh: UNEXPECTED argv: $*" >&2
exit 64
STUBEOF
chmod +x "$STUB"

# A jq that is present but unrunnable, shadowing the ONE binary (never an emptied PATH).
NOJQ="$SUITE_TMP/nojq"
mkdir -p "$NOJQ"
assert_fixture_dir "$NOJQ"
printf '#!/bin/sh\nexit 127\n' > "$NOJQ/jq"
chmod +x "$NOJQ/jq"

CALLS="$SUITE_TMP/calls.log"
assert_fixture_dir "$CALLS"
DEADLINE=$(date -u -d '2026-10-15T00:00:00Z' +%s)
BEFORE=$(date -u -d '2026-10-05T12:00:00Z' +%s)
AFTER=$((DEADLINE + 3600))
OPEN='{"state":"OPEN","mergedAt":null,"baseRefName":"main"}'
MERGED='{"state":"MERGED","mergedAt":"2026-10-03T10:00:00Z","baseRefName":"main"}'

reset_calls() {
  assert_fixture_dir "$CALLS"
  : > "$CALLS"
}

# Every recorded call must be one of the two read-only shapes, and the stub must not have refused.
calls_clean() {
  [ -s "$CALLS" ] || return 0
  ! grep -qvxE 'pr view 9348 --repo jikig-ai/soleur --json state,mergedAt,baseRefName|run list --repo jikig-ai/soleur --workflow workspaces-plaintext-forget.yml --branch main --status success --limit 100 --json updatedAt' "$CALLS"
}

# case_ <name> <want-rc> <want-substring> [VAR=val ...]   (seams supplied: GH_BIN + the caller's NOW_EPOCH)
case_() {
  local name=$1 want=$2 sub=$3; shift 3
  local out rc
  reset_calls
  out=$(env GH_BIN="$STUB" STUB_CALLS="$CALLS" "$@" bash "$PROBE" 2>&1); rc=$?
  if [ "$rc" -eq "$want" ] && [[ "$out" == *"$sub"* ]] && calls_clean; then ok "$name"
  else no "$name (rc=$rc want=$want out=${out:0:160})"; fi
}

# clean_ <name> <want-rc> <want-substring> <path-prefix> [VAR=val ...]
# Runs the probe the way the sweeper does: env -i, no seams, gh found on PATH.
clean_() {
  local name=$1 want=$2 sub=$3 pp=$4; shift 4
  local out rc
  reset_calls
  out=$(env -i PATH="$pp:/usr/bin:/bin" HOME="$SUITE_TMP" STUB_CALLS="$CALLS" "$@" bash "$PROBE" 2>&1); rc=$?
  if [ "$rc" -eq "$want" ] && [[ "$out" == *"$sub"* ]] && calls_clean; then ok "$name"
  else no "$name (rc=$rc want=$want out=${out:0:160})"; fi
}

# Control: calls_clean must be able to REJECT. A calls_clean that always said yes would hide a write verb
# (or a wrong argv) the probe sent after the stub refused it.
assert_fixture_dir "$CALLS"
printf 'pr merge 9348\n' > "$CALLS"
if calls_clean; then
  printf 'INSTRUMENT FAIL: calls_clean accepted a write-verb call\n' >&2
  exit 2
fi
reset_calls

# Control: case_ must be able to FAIL. A case_ that always said yes would make every row below vacuous.
case_ control-must-fail 99 "x" PR_OUT="$MERGED" NOW_EPOCH="$AFTER" >/dev/null
if [ "$pass" -ne 0 ] || [ "$failc" -ne 1 ]; then
  printf 'INSTRUMENT FAIL: case_ did not reject a wrong expectation (pass/fail=%s/%s)\n' "$pass" "$failc" >&2
  exit 2
fi
pass=0; failc=0

# --- exit 0: only a MERGED #9348 into main with a mergedAt, at any clock reading
case_ merged-after            0 "PASS"             PR_OUT="$MERGED" NOW_EPOCH="$AFTER"
case_ merged-before           0 "PASS"             PR_OUT="$MERGED" NOW_EPOCH="$BEFORE"
case_ merged-null-mergedat    3 "CANNOT ESTABLISH" PR_OUT='{"state":"MERGED","mergedAt":null,"baseRefName":"main"}' NOW_EPOCH="$AFTER"
case_ merged-wrong-base       3 "CANNOT ESTABLISH" PR_OUT='{"state":"MERGED","mergedAt":"2026-10-03T10:00:00Z","baseRefName":"dev"}' NOW_EPOCH="$AFTER"
# --- exit 5
case_ closed-before           5 "WITHOUT merging"  PR_OUT='{"state":"CLOSED","mergedAt":null,"baseRefName":"main"}' NOW_EPOCH="$BEFORE"
case_ closed-after            5 "WITHOUT merging"  PR_OUT='{"state":"CLOSED","mergedAt":null,"baseRefName":"main"}' NOW_EPOCH="$AFTER"
case_ open-at-deadline        5 "2026-10-15"       PR_OUT="$OPEN" RUN_OUT='[]' NOW_EPOCH="$DEADLINE"
case_ deadline-beats-recent   5 "2026-10-15"       PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"2026-10-14T23:00:00Z"}]' NOW_EPOCH="$DEADLINE"
case_ deadline-beats-gh-fail  5 "2026-10-15"       PR_OUT="$OPEN" RUN_RC=1 NOW_EPOCH="$DEADLINE"
case_ forget-stale            5 ">48 h"            PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"2026-10-03T11:59:59Z"}]' NOW_EPOCH="$BEFORE"
case_ forget-earliest-wins    5 ">48 h"            PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"2026-10-05T10:00:00Z"},{"updatedAt":"2026-10-03T00:00:00Z"}]' NOW_EPOCH="$BEFORE"
case_ forget-earliest-wins-rv 5 ">48 h"            PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"2026-10-03T00:00:00Z"},{"updatedAt":"2026-10-05T10:00:00Z"}]' NOW_EPOCH="$BEFORE"
# --- exit 2
case_ one-second-before       2 "NOT YET"          PR_OUT="$OPEN" RUN_OUT='[]' NOW_EPOCH="$((DEADLINE - 1))"
case_ open-no-forget          2 "NOT YET"          PR_OUT="$OPEN" RUN_OUT='[]' NOW_EPOCH="$BEFORE"
case_ forget-recent           2 "<48 h"            PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"2026-10-05T00:00:00Z"}]' NOW_EPOCH="$BEFORE"
case_ forget-at-bound         2 "<48 h"            PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"2026-10-03T12:00:00Z"}]' NOW_EPOCH="$BEFORE"
# --- exit 3: every unusable input is "could not establish", never a verdict
case_ pr-view-fails           3 "CANNOT ESTABLISH" PR_RC=1 NOW_EPOCH="$BEFORE"
case_ pr-state-garbage        3 "CANNOT ESTABLISH" PR_OUT='not json' NOW_EPOCH="$BEFORE"
case_ pr-state-lowercase      3 "CANNOT ESTABLISH" PR_OUT='{"state":"merged","mergedAt":"2026-10-03T10:00:00Z","baseRefName":"main"}' NOW_EPOCH="$AFTER"
case_ pr-state-array          3 "CANNOT ESTABLISH" PR_OUT='[{"state":"MERGED"}]' NOW_EPOCH="$AFTER"
case_ pr-state-empty          3 "CANNOT ESTABLISH" PR_OUT='' NOW_EPOCH="$AFTER"
case_ run-list-fails          3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_RC=1 NOW_EPOCH="$BEFORE"
case_ run-list-garbage        3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='nope' NOW_EPOCH="$BEFORE"
case_ run-list-null           3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='null' NOW_EPOCH="$BEFORE"
case_ run-list-object         3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='{}' NOW_EPOCH="$BEFORE"
case_ forget-null-updatedat   3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":null}]' NOW_EPOCH="$BEFORE"
case_ forget-bad-date         3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"yesterday-ish"}]' NOW_EPOCH="$BEFORE"
case_ forget-relative-date    3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='[{"updatedAt":"3 days ago"}]' NOW_EPOCH="$BEFORE"
case_ clock-non-numeric       3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='[]' NOW_EPOCH="abc"
case_ jq-unrunnable           3 "CANNOT ESTABLISH" PATH="$NOJQ:$PATH" PR_OUT="$MERGED" NOW_EPOCH="$AFTER"
# --- the production shape: env -i, no seams, gh resolved from PATH (clock-independent outcomes only)
clean_ prod-shape-merged      0 "PASS"             "$BIN" PR_OUT="$MERGED"
clean_ prod-shape-closed      5 "WITHOUT merging"  "$BIN" PR_OUT='{"state":"CLOSED","mergedAt":null,"baseRefName":"main"}'
clean_ prod-shape-gh-absent   3 "CANNOT ESTABLISH" "$SUITE_TMP/empty-dir"

# Source pin: the probe never exits 1 (the sweeper reads 1 as FAIL / reopen).
if grep -vE '^[[:space:]]*#' "$PROBE" | grep -qE '\bexit 1\b'; then
  no "probe-never-exits-1 (an exit 1 appears)"
else ok "probe-never-exits-1"; fi

printf '\n%s passed, %s failed\n' "$pass" "$failc"
if [ "$pass" -lt 34 ]; then
  printf 'FAIL: ran only %s passing assertions (<34)\n' "$pass" >&2
  exit 1
fi
[ "$failc" -eq 0 ]
