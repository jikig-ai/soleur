#!/usr/bin/env bash
# Tests scripts/lint-workflow-issue-write-scope.py.
#
# The lint exists because registry-host-replace-dispatch.yml's refusal artifact could not post —
# no `issues: write` — and `|| true` reported that as success. Every fixture below is SYNTHESIZED
# (cq-test-fixtures-synthesized-only); none is copied from a live workflow.
#
# The two that matter most are the FALSE-POSITIVE arms, because a permissions lint that
# over-reports gets "fixed" by widening token scope — the opposite of what it is for:
#   * a workflow authenticating with a GitHub App / PAT token needs no workflow-scoped grant;
#   * a PR comment is served from the `/issues/{n}/comments` REST path but is governed by
#     `pull-requests: write`. The first draft flagged a correct workflow on exactly that.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$ROOT/scripts/lint-workflow-issue-write-scope.py"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -r "$SUT" ]] || { echo "  FAIL: SUT not readable at $SUT"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1; }
command -v python3 >/dev/null || { echo "  SKIP: python3 unavailable — the lint did NOT run."; echo "=== Results: 0/0 passed, 0 failed (DECLINED: no python3) ==="; exit 0; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

mkwf() { # <name> <body>
  mkdir -p "$TMP/wf"
  printf '%s\n' "$2" > "$TMP/wf/$1"
}
run_lint() { python3 "$SUT" "$TMP/wf" >"$TMP/out" 2>"$TMP/err"; RC=$?; }
reset() { rm -rf "$TMP/wf"; mkdir -p "$TMP/wf"; }

# --- CONTROL: a tracker-writing workflow WITH the scope -> clean --------------------------
reset
mkwf ok.yml 'name: ok
permissions:
  contents: read
  issues: write
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue comment 1 --body hi'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "control: a tracker-writing workflow that declares issues:write is clean"
else
  fail "control: expected rc=0, got $RC: $(head -1 "$TMP/err")"
fi

# --- THE DEFECT: writes with the workflow token, no scope -> RED --------------------------
reset
mkwf bad.yml 'name: bad
permissions:
  actions: write
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue comment 7556 --body hi || true'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q 'bad.yml' "$TMP/err"; then
  pass "synthesized red: a gh issue write with no issues:write is REFUSED, and the file is named"
else
  fail "the defect that shipped was not caught: rc=$RC"
fi

# --- JOB-LEVEL permissions satisfy it (a per-job grant is as valid as top-level) ----------
reset
mkwf joblevel.yml 'name: joblevel
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    permissions:
      issues: write
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue create --title t --body b'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "a JOB-level issues:write satisfies the requirement (no push toward widening top-level scope)"
else
  fail "job-level grant was not honoured — this would push authors to widen scope: rc=$RC"
fi

# --- FALSE-POSITIVE ARM 1: App/PAT token carries its own grants ----------------------------
reset
mkwf apptoken.yml 'name: apptoken
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ steps.app.outputs.token }}
        run: gh issue comment 1 --body hi'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "false-positive arm: an App-token workflow is NOT flagged (hr-github-app-auth-not-pat)"
else
  fail "flagged an App-token workflow, which needs no workflow-scoped grant: rc=$RC"
fi

# --- FALSE-POSITIVE ARM 2: a PR comment rides the /issues/ path but needs pull-requests ----
# This is the one the first draft got wrong against a real, correct workflow.
reset
mkwf prcomment.yml 'name: prcomment
permissions:
  contents: read
  pull-requests: write
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh api -X POST "repos/o/r/issues/$PR/comments" -f body=hi'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "false-positive arm: a PR comment via the /issues/ path is covered by pull-requests:write"
else
  fail "flagged a correct PR-commenting workflow — acting on this widens token scope for no defect: rc=$RC"
fi

# ...but pull-requests:write must NOT excuse a `gh issue` verb, which only addresses issues.
reset
mkwf prwrong.yml 'name: prwrong
permissions:
  contents: read
  pull-requests: write
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue comment 7556 --body hi'
run_lint
if [[ "$RC" -eq 1 ]]; then
  pass "pull-requests:write does NOT excuse a gh issue verb (it cannot address a PR)"
else
  fail "pull-requests:write was accepted for a gh issue write — the original defect would pass: rc=$RC"
fi

# --- READS are not writes ------------------------------------------------------------------
reset
mkwf readonly.yml 'name: readonly
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue view 7556 --json state'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "a gh issue VIEW is not a write and is not flagged"
else
  fail "flagged a read-only gh issue view: rc=$RC"
fi

# --- the graphql form is caught too --------------------------------------------------------
reset
mkwf gql.yml 'name: gql
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh api graphql -f query="mutation { addComment(input: {}) { clientMutationId } }"'
run_lint
if [[ "$RC" -eq 1 ]]; then
  pass "the graphql addComment form is caught (it bypasses the gh issue surface entirely)"
else
  fail "the graphql mutation form slipped through — that is the exact API the failure came from: rc=$RC"
fi

# --- THE REST FORM MUST FIRE. Previously unpinned in the flagging direction: the only API
# fixture was prcomment.yml, which asserts rc=0, so neutering API_WRITE entirely stayed green.
reset
mkwf apibad.yml 'name: apibad
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh api -X POST "repos/o/r/issues/7556/comments" -f body=hi'
run_lint
if [[ "$RC" -eq 1 ]]; then
  pass "a mutating gh api against /issues/ with no scope is REFUSED"
else
  fail "the REST write form was not flagged — API_WRITE is unpinned: rc=$RC"
fi

# ...and in the OTHER argument order, which is the order this repo actually writes (cla-evidence).
# The original `[^\n]*(--method…)[^\n]*issues` required method-BEFORE-path, so this slipped through.
reset
mkwf apiorder.yml 'name: apiorder
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh api "repos/o/r/issues/7556/comments" -X POST -f body=hi'
run_lint
if [[ "$RC" -eq 1 ]]; then
  pass "method-AFTER-path is caught too (argument order must not decide detection)"
else
  fail "path-then-method slipped through — the ordering fail-open is back: rc=$RC"
fi

# --- BOTH API FORMS + pull-requests:write must stay QUIET. The list-equality carve-out flagged
# this, because two matches equal neither singleton — a false positive that reads as "widen scope".
reset
mkwf prboth.yml 'name: prboth
permissions:
  contents: read
  pull-requests: write
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh api -X POST "repos/o/r/issues/$PR/comments" -f body=hi
          gh api graphql -f query="mutation { addComment(input: {}) { clientMutationId } }"'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "a PR workflow using BOTH api forms is excused by pull-requests:write (no false positive)"
else
  fail "flagged a correct PR workflow using both API forms — widens scope for no defect: rc=$RC"
fi

# --- THE OFFENDER IS NOT ALONE, AND IT IS NOT FIRST. Every other fixture dir holds exactly one
# file, so a truncated walk (`[:1]`, or `first`) was invisible. Here the clean file sorts first.
reset
mkwf a-clean.yml 'name: aclean
permissions:
  contents: read
  issues: write
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue comment 1 --body hi'
mkwf z-bad.yml 'name: zbad
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue comment 7556 --body hi'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q 'z-bad.yml' "$TMP/err"; then
  pass "an offender that sorts SECOND is still found (the walk is not truncated)"
else
  fail "only the first file was examined — the loop is unproven: rc=$RC"
fi

# --- NO EXPLICIT TOKEN. `gh` falls back to the workflow token inside Actions, so this is in
# scope. Every other fixture declares a token env, leaving that documented branch unexercised.
reset
mkwf notoken.yml 'name: notoken
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: gh issue comment 7556 --body hi'
run_lint
if [[ "$RC" -eq 1 ]]; then
  pass "a write with NO explicit token is in scope (gh falls back to the workflow token)"
else
  fail "the implicit-token branch is unpinned — a bare gh issue write escapes: rc=$RC"
fi

# --- A PAT is the other half of hr-github-app-auth-not-pat; only the App form was covered.
reset
mkwf pat.yml 'name: pat
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.MY_RELEASE_PAT }}
        run: gh issue comment 1 --body hi'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "a PAT-authenticated workflow is NOT flagged (it carries its own grants)"
else
  fail "flagged a PAT workflow — only the App-token half of the carve-out was proven: rc=$RC"
fi

# --- WRITE VERBS BEYOND `comment`. Narrowing WRITE_CALL to (comment) survived every fixture.
reset
mkwf close.yml 'name: close
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue close 7556 --reason completed'
run_lint
if [[ "$RC" -eq 1 ]]; then
  pass "a non-comment write verb (close) is caught — the vocabulary is not just 'comment'"
else
  fail "only 'comment' is pinned; the rest of the write vocabulary is decoration: rc=$RC"
fi

# --- .yaml IS ALSO A WORKFLOW EXTENSION. Dropping that glob survived (the repo has none today),
# which makes it a silent bypass the moment one lands.
reset
mkwf bad.yaml 'name: badyaml
permissions:
  contents: read
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh issue comment 7556 --body hi'
run_lint
if [[ "$RC" -eq 1 ]]; then
  pass "a .yaml (not .yml) workflow is scanned too"
else
  fail "the .yaml glob is unpinned — dropping it is a silent bypass: rc=$RC"
fi

# --- an empty or wrong directory must ERROR, never silently pass -------------------------------
python3 "$SUT" "$TMP/does-not-exist" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  pass "a missing workflows directory exits 2 (usage) rather than reporting a clean scan"
else
  fail "a missing directory did not error — the lint could pass by scanning nothing"
fi

# The EMPTY-but-existing half, which is the branch that specifically guards "passed by scanning
# nothing". The comment above claimed both halves; only the missing-directory one was tested.
reset
run_lint
if [[ "$RC" -eq 2 ]]; then
  pass "an EMPTY workflows directory exits 2 rather than reporting a clean scan"
else
  fail "an empty directory reported a clean scan — the scanned==0 guard is unpinned: rc=$RC"
fi

# A decode failure is a PARSE error (2), not a violation (1) — and it must not swallow the
# findings accumulated before it.
reset
printf 'name: ok\npermissions:\n  issues: write\n' > "$TMP/wf/aaa.yml"
printf '\xff\xfe\x00\x01binary' > "$TMP/wf/zzz.yml"
run_lint
if [[ "$RC" -eq 2 ]]; then
  pass "a non-UTF8 workflow exits 2 (parse error), not 1 (which reads as a violation)"
else
  fail "a binary file did not produce the documented parse-error code: rc=$RC"
fi

# Extra arguments must be rejected, not silently ignored.
python3 "$SUT" "$TMP/wf" "$TMP/wf" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  pass "a second path argument is rejected rather than silently ignored"
else
  fail "extra argv was ignored — a typo'd path would be invisible"
fi

# --- HARNESS CANARY + a floor that does NOT dispatch through the helper it guards ----------
_cp=$PASS; _cf=$FAIL
pass "canary: a true condition registers as PASS"
fail "canary: a false condition MUST register as FAIL (this line is EXPECTED)"
if [[ "$PASS" -ne $((_cp + 1)) || "$FAIL" -ne $((_cf + 1)) ]]; then
  echo "  FATAL: the assertion helpers are not counting — every verdict above is void." >&2
  exit 2
fi
FAIL=$((FAIL - 1))

# THE FINAL GATE NEEDS ITS OWN GUARD, and it is the one thing neither check above covers.
# The canary proves pass()/fail() still COUNT; the floor proves enough assertions RAN. Nothing
# proved the line that converts a non-zero FAIL into a non-zero EXIT. Measured: replacing the
# bare `[[ "$FAIL" -eq 0 ]]` tail with `true` left the suite printing its own FAIL lines and
# exiting 0 — CI reads that as green. So route the verdict through ONE function, prove that
# function discriminates in BOTH directions, and then use the same function as the exit status.
verdict_ok() { [[ "$1" -eq 0 ]]; }
if verdict_ok 0 && ! verdict_ok 1; then
  pass "the exit verdict discriminates: FAIL=0 succeeds, FAIL=1 does not"
else
  echo "  FATAL: the exit verdict does not discriminate — a failing suite could exit 0." >&2
  exit 2
fi

# LITERAL, on the line directly above the test. scripts/guard-vacuity-floor.test.sh widens its
# mutant slice BACKWARD only over contiguous simple assignments, so a threshold computed further
# up does not bind and the floor is scored "not constructible" — counted as UNCOVERED by ADR-193
# rather than as passing. `scripts/` is a COVERED directory, so this must bind from the start.
FAIL_FLOOR_MIN=22
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$FAIL_FLOOR_MIN" ]]; then
  echo "  FATAL: anti-vacuity — ran $TOTAL assertions, expected >= $FAIL_FLOOR_MIN. Fix the extraction, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
verdict_ok "$FAIL"
