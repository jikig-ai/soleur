#!/usr/bin/env bash
# Suite for scripts/codeql-main-alert-gate.sh (its workflow wiring is asserted by the sibling suite
# codeql-main-alert-gate-workflow-wiring.test.sh, which PARSES the YAML instead of grepping it)
# (Guard 3 of knowledge-base/project/plans/archive/20261004-150011-2026-10-03-feat-adopt-merge-queue-advisory-codeql-plan.md,
# issue #9454).
#
# PROPERTY UNDER TEST. For a push to main, every open critical/high CodeQL alert on refs/heads/main
# that has no OPEN, bot-authored `sec: CodeQL alert #N` tracking issue yields exactly one such issue
# and a non-zero exit; already-tracked alerts yield neither; no error path exits 0.
#
# HOW THE SEAM IS BUILT. `gh` is a PATH shim (fixtures/codeql-main-alert-gate/shim/gh) that records
# every call and REFUSES request shapes it was not written for. It replays the real CLI's
# fidelity points (concatenated `--paginate` pages with no outer array, `gh issue list` capped at
# 30 rows without --limit, --author/--label filtering) so a parser or a bound that is wrong against
# the real CLI is wrong here too (harness row H4). Fixtures are SYNTHESIZED (cq-test-fixtures-
# synthesized-only): invented alert numbers, an example-org/example-repo slug, no captured payloads.
#
# ROW MAP (plan Guard 3). Mutation rows are scenario cases r1..r15 (r12 = degraded-exit upsert; r13, the
# dismissal-evasion row, was removed with that machinery: insider dismissal is an accepted residual);
# new rows (review #9455): d1 pins the production poll defaults (30 s, 50 / 8 polls, 1800 s deadline) by running the
# script with NOTHING overridden against a counting sleep stub; d2 wall-clock deadline (a slow API degrades before the
# deadline, and a pause that would not fit is never taken); d3 phase 2 has its own poll budget; x1 unset or empty GH_REPO
# exits 2 like every other rejected input; sx a hostile gh stderr (newline + forged ::error::, markdown, @mention) does not
# survive sanitize(); w5 non-Analyze check-runs are ignored; h5 a duplicate alert number across pages files one issue; vc
# the verdict helpers t, tn and eq each carry a positive control (they must record a failure when handed one).
# harness rows: H1 vacuous harness (a green with zero recorded gh calls is RED, and a stub that
# always exits 0 must red this suite), H2 (the suite mutated to ignore the SUT exit status must
# red on row 3), H3 must-PASS non-canonical inputs, H4 shim replays the real paginate/limit shape.
#
# Knobs (tests only): GATE_ONLY=r1,r3  run only those case ids; GATE_NO_META=1 skip the self-
# referential meta cases (children set it); GATE_SUT=<path> run against another script copy;
# GATE_TEST_DIR=<dir> locate fixtures here (used when the suite itself is mutated);
# GATE_MUTANTS=1 also run the SUT mutation battery (slow; proves each mutation lands and reds).
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="${GATE_TEST_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT="${GATE_SUT:-$ROOT/scripts/codeql-main-alert-gate.sh}"
WF="$ROOT/.github/workflows/codeql-main-alert-gate.yml"
FIX="$SCRIPT_DIR/fixtures/codeql-main-alert-gate"
SELF="$SCRIPT_DIR/codeql-main-alert-gate.test.sh"
[[ -n "${GATE_TEST_DIR:-}" ]] && SELF="${BASH_SOURCE[0]}"

# The EXACT assertion count of a green run (-ne, not -lt; re-derive it from a green run). Reported by printf + exit at the bottom, NOT through pass/fail, so a
# harness that stops counting cannot report its own shortfall as green.
FLOOR=361
# Exact number of SUT mutants in fixtures/mutants.sh (GATE_MUTANTS=1 adds one assertion per mutant).
MUTANT_FLOOR=50

ASSERTS=0 passes=0 fails=0 FAILED=()
pass() { passes=$((passes + 1)); ASSERTS=$((ASSERTS + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); ASSERTS=$((ASSERTS + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# Instrument self-test: both verdict helpers must record before anything is trusted.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"; _iv_a="$ASSERTS"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) || "$ASSERTS" -ne $((_iv_a + 2)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); ASSERTS=0

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

assert_fixture_dir "$FIX"
[[ -d "$FIX/base" && -x "$FIX/shim/gh" ]] || { printf '[FATAL] fixture tree incomplete under %s\n' "$FIX" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq is required" >&2; exit 2; }

SANDBOX="$(mktemp -d)" || { echo "[FATAL] mktemp -d failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

GOOD_SHA="0123456789abcdef0123456789abcdef01234567"
REPO_SLUG="example-org/example-repo"

# t <desc> <cmd...>: pass when the command exits 0.   tn: pass when it exits non-zero.
t()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
tn() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got <$2> want <$3>)"; fi; }

# Positive controls for the three verdict-owning helpers. pass/fail have an instrument self-test above; t, tn and eq
# did not, so a helper neutered to a no-op (or to always-pass) kept the whole suite green. Each helper is driven once
# with an input that MUST pass and once with one that MUST fail, the counters are read, and the counters are unwound
# so the controls never enter the assertion total. A shortfall is reported with printf + exit, not through pass/fail.
verdict_helper_controls() {
  local p_orig="$passes" f_orig="$fails" p0="$passes" f0="$fails" a0="$ASSERTS" n0="${#FAILED[@]}" bad=""
  { t "vc" true; } >/dev/null 2>&1;                [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad t-pass"
  p0="$passes"; f0="$fails"
  { t "vc" false; } >/dev/null 2>&1;               [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad t-fail"
  p0="$passes"; f0="$fails"
  { tn "vc" false; } >/dev/null 2>&1;              [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad tn-pass"
  p0="$passes"; f0="$fails"
  { tn "vc" true; } >/dev/null 2>&1;               [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad tn-fail"
  p0="$passes"; f0="$fails"
  { eq "vc" "same" "same"; } >/dev/null 2>&1;      [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad eq-pass"
  p0="$passes"; f0="$fails"
  { eq "vc" "one" "two"; } >/dev/null 2>&1;        [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad eq-fail"
  passes="$p_orig"; fails="$f_orig"; ASSERTS="$a0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ -n "$bad" ]]; then
    printf '[FATAL] verdict helper positive control: a helper did not record the verdict it was handed:%s\n' "$bad" >&2
    exit 1
  fi
}
verdict_helper_controls

want() { [[ -z "${GATE_ONLY:-}" ]] || [[ ",${GATE_ONLY}," == *",$1,"* ]]; }

CASE="" ST="" GATE_RC=0
mk_case() { # <name>: a fresh mutable copy of the base scenario plus the gh shim on PATH
  CASE="$1"; ST="$SANDBOX/$1"; assert_fixture_dir "$ST"
  mkdir -p "$ST/bin" "$ST/tmp" || exit 2
  cp "$FIX"/base/*.json "$ST/" || exit 2
  cp "$FIX/shim/gh" "$ST/bin/gh" || exit 2
  chmod +x "$ST/bin/gh" || exit 2
}
ov() { cp "$FIX/scenarios/$1" "$ST/$2" || { echo "[FATAL] overlay $1 failed" >&2; exit 2; }; }

run_gate() { # [VAR=value ...]: run the SUT in the current case, record its exit status in GATE_RC
  local rc=0
  : >"$ST/calls.log"
  env -i PATH="$ST/bin:$PATH" HOME="$ST" TMPDIR="$ST/tmp" GATE_STATE="$ST" GH_TOKEN=synthetic-token \
    GH_REPO="$REPO_SLUG" SHA="$GOOD_SHA" DRY_RUN=false POLL_INTERVAL=0 MAX_POLLS=5 SETTLE_POLLS=5 GITHUB_RUN_ID=424242 \
    "$@" bash "$SUT" >"$ST/out.txt" 2>&1 || rc=$?
  GATE_RC=$rc # H2-RC-CAPTURE
  # H1: a green verdict with zero recorded gh calls means the harness (or the SUT) did nothing.
  if [[ "$GATE_RC" -eq 0 && ! -s "$ST/calls.log" ]]; then
    fail "H1 vacuous harness: case $CASE exited 0 with zero recorded gh calls"
  fi
}

count_calls() { local n=0; n="$(grep -cF -- "$1" "$ST/calls.log" 2>/dev/null)" || true; printf '%s' "${n:-0}"; }
ncreate() { count_calls "ISSUE-CREATE"; }
ncomment() { count_calls "ISSUE-COMMENT"; }
latest_title() { local f; f="$(ls "$ST"/created.*.title 2>/dev/null | sort -V | tail -n 1)" || true; [[ -n "$f" ]] && cat "$f"; }
latest_body() { local f; f="$(ls "$ST"/created.*.body 2>/dev/null | sort -V | tail -n 1)" || true; [[ -n "$f" ]] && printf '%s' "$f"; }
latest_labels() { local f; f="$(ls "$ST"/created.*.labels 2>/dev/null | sort -V | tail -n 1)" || true; [[ -n "$f" ]] && cat "$f"; }
out_has() { grep -qF -- "$1" "$ST/out.txt"; }
body_has() { local b; b="$(latest_body)"; [[ -n "$b" ]] && grep -qF -- "$1" "$b"; }

LBL_P1="type/security,priority/p1-high,action-required"
LBL_P2="meta/machinery,type/security,priority/p2-medium,action-required"

# ---------------------------------------------------------------------------------------------
# Instrument checks on the shim itself (it is the seam every row stands on).
# ---------------------------------------------------------------------------------------------
if want shim; then
  echo "== shim fidelity (H4) =="
  mk_case shim
  ov alerts-open-page2.json alerts-open.json
  s_all="$(PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh api --paginate "repos/x/y/code-scanning/alerts?state=open")"
  s_one="$(PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh api "repos/x/y/code-scanning/alerts?state=open")"
  eq "shim: --paginate replays two concatenated top-level arrays" "$(printf '%s' "$s_all" | jq -s 'length')" "2"
  eq "shim: without --paginate only the first page is served" "$(printf '%s' "$s_one" | jq -s 'length')" "1"
  jq -c '[range(0;40) as $i | {number:(1000+$i),title:("sec: CodeQL alert #\(1000+$i) — x"),_author:"app/github-actions",_labels:["type/security"]}]' \
    >"$ST/issues-open.json" <<<'null'
  eq "shim: gh issue list without --limit is capped at 30 rows" \
    "$(PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh issue list --label type/security --author app/github-actions --state open --json number,title | jq 'length')" "30"
  eq "shim: gh issue list --limit 200 returns all 40 rows" \
    "$(PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh issue list --label type/security --author app/github-actions --state open --limit 200 --json number,title | jq 'length')" "40"
  eq "shim: --author filters out other authors" \
    "$(PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh issue list --label type/security --author someone-else --state open --limit 200 --json number,title | jq 'length')" "0"
  eq "shim: the analyses endpoint IGNORES sha= like the real API (same multi-commit body for two shas)" \
    "$(PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh api "repos/x/y/code-scanning/analyses?ref=refs/heads/main&sha=$GOOD_SHA" | jq -c 'map(.commit_sha) | unique | length')" \
    "$(PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh api "repos/x/y/code-scanning/analyses?ref=refs/heads/main&sha=2222222222222222222222222222222222222222" | jq -c 'map(.commit_sha) | unique | length')"
  tn "shim: a dismissed-alerts endpoint is no longer served" env PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh api --paginate "repos/x/y/code-scanning/alerts?state=dismissed"
  tn "shim: gh search is refused" env PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh search issues foo
  tn "shim: an unexpected endpoint is refused" env PATH="$ST/bin:$PATH" GATE_STATE="$ST" gh api --paginate repos/x/y/other
fi

# ---------------------------------------------------------------------------------------------
# Baseline and row 1/2: new vs tracked
# ---------------------------------------------------------------------------------------------
if want c0; then
  echo "== c0: clean main (all Analyze runs green, no alerts) =="
  mk_case c0; run_gate
  eq "c0 exit 0" "$GATE_RC" "0"
  eq "c0 creates nothing" "$(ncreate)" "0"
  t "c0 reports a GREEN verdict" out_has "verdict=GREEN"
  t "c0 read the open alerts ref-scoped to main" grep -qF "state=open" "$ST/calls.log"
  t "c0 paginated the alerts read" grep -qE 'gh api --paginate .*code-scanning/alerts' "$ST/calls.log"
  tn "c0 made no unpaginated fetch of a paginated read (only the one analyses page is single)" grep -qE 'UNPAGINATED (check-runs|alerts-open)' "$ST/calls.log"
  t "c0 scoped the alerts read itself to refs/heads/main (not just the analyses read)" grep -qE 'code-scanning/alerts\?.*ref=refs/heads/main' "$ST/calls.log"
  t "c0 waited on the commit's check-runs" grep -qF "commits/$GOOD_SHA/check-runs" "$ST/calls.log"
  t "c0 read the analyses scoped to main, newest first, one page of 100" grep -qF "code-scanning/analyses?ref=refs/heads/main&sort=created&direction=desc&per_page=100" "$ST/calls.log"
  eq "c0 read the analyses exactly twice (count then stable count), never the whole history" "$(count_calls 'code-scanning/analyses')" "2"
  tn "c0 never paginated the analyses history" grep -qE 'gh api --paginate .*code-scanning/analyses' "$ST/calls.log"
  tn "c0 never used gh search" grep -qE '^gh search' "$ST/calls.log"
fi

if want r1; then
  echo "== r1: critical alert with no tracking issue (queued-PR case: created_at is old) =="
  mk_case r1; ov alert-critical-untracked.json alerts-open.json; run_gate
  eq "r1 exit 1" "$GATE_RC" "1"
  eq "r1 files exactly one issue" "$(ncreate)" "1"
  eq "r1 title is the shared sec: convention" "$(latest_title)" "sec: CodeQL alert #101 — js/sql-injection"
  eq "r1 labels are exactly the three existing labels" "$(latest_labels)" "$LBL_P1"
  t "r1 body carries the URL built from the alert number" body_has "https://github.com/$REPO_SLUG/security/code-scanning/101"
  t "r1 body names the severity" body_has "critical"
  tn "r1 body omits the alert message" body_has "Synthetic message"
  tn "r1 body omits the file path" body_has "src/synthetic/a.ts"
  tn "r1 body omits the rule description" body_has "Synthetic SQL injection"
  t "r1 verdict RED" out_has "verdict=RED"
  t "r1 body was passed with --body-file" grep -qF -- "--body-file" "$ST/calls.log"
fi

if want r2; then
  echo "== r2: standing backlog (alert already has an open bot-authored tracker) =="
  mk_case r2; ov alert-critical-untracked.json alerts-open.json; ov issue-tracked-101.json issues-open.json; run_gate
  eq "r2 exit 0" "$GATE_RC" "0"
  eq "r2 files nothing" "$(ncreate)" "0"
  t "r2 verdict GREEN" out_has "verdict=GREEN"
  # idempotence: first run files, second run on the same state is green
  mk_case r2b; ov alert-critical-untracked.json alerts-open.json; run_gate
  eq "r2b first run RED" "$GATE_RC" "1"
  run_gate
  eq "r2b second run on the same alert is GREEN" "$GATE_RC" "0"
  eq "r2b second run files nothing" "$(ncreate)" "0"
fi

# ---------------------------------------------------------------------------------------------
# Row 3: API failure is never "no alerts"
# ---------------------------------------------------------------------------------------------
if want r3; then
  echo "== r3: alerts endpoint returns HTTP 500 =="
  mk_case r3; echo 1 >"$ST/alerts-open.rc"; echo "gh: HTTP 500 (synthetic)" >"$ST/alerts-open.err"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3 exit non-zero" || fail "r3 exit non-zero (got $GATE_RC)"
  tn "r3 never reports GREEN" out_has "verdict=GREEN"
  tn "r3 never says no alerts" grep -qi "no open" "$ST/out.txt"
  t "r3 names the failing endpoint in an annotation" grep -qE '^::error title=codeql-main-alert-gate::.*alerts' "$ST/out.txt"
  eq "r3 upserts one degraded issue" "$(ncreate)" "1"
  eq "r3 degraded issue title" "$(latest_title)" "codeql-gate-degraded"

  mk_case r3b; echo 124 >"$ST/alerts-open.rc"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3b a timeout (rc 124) on the alerts read is non-zero" || fail "r3b timeout non-zero"

  mk_case r3c; echo 1 >"$ST/check-runs.rc"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3c check-runs API failure is non-zero" || fail "r3c check-runs failure non-zero"
  eq "r3c did not read alerts after the failed wait" "$(count_calls 'code-scanning/alerts')" "0"

  mk_case r3d; echo 1 >"$ST/analyses.rc"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3d analyses API failure is non-zero" || fail "r3d analyses failure non-zero"

  mk_case r3e; ov alert-critical-untracked.json alerts-open.json; echo 1 >"$ST/issues-open.rc"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3e tracker-list failure is non-zero" || fail "r3e tracker-list failure non-zero"
  eq "r3e files nothing blindly when the dedupe list failed" "$(ncreate)" "0"

  mk_case r3f; ov alert-critical-untracked.json alerts-open.json; echo 1 >"$ST/issue-create.rc"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3f issue-create failure is non-zero" || fail "r3f issue-create failure non-zero"
  tn "r3f never reports GREEN" out_has "verdict=GREEN"

  mk_case r3g; ov alert-critical-untracked.json alerts-open.json; echo 'not json' >"$ST/alerts-open.json"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3g a malformed alerts body is non-zero" || fail "r3g malformed body non-zero"

  mk_case r3h; echo '{"message":"Bad credentials"}' >"$ST/alerts-open.json"; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r3h an error object where pages were expected is non-zero" || fail "r3h error object non-zero"
fi

# ---------------------------------------------------------------------------------------------
# Row 4: pagination
# ---------------------------------------------------------------------------------------------
if want r4; then
  echo "== r4: qualifying alert on page 2 of the alerts read =="
  mk_case r4; ov alerts-open-page2.json alerts-open.json; run_gate
  eq "r4 exit 1" "$GATE_RC" "1"
  eq "r4 files one issue for the page-2 alert" "$(ncreate)" "1"
  eq "r4 title is the page-2 alert" "$(latest_title)" "sec: CodeQL alert #202 — py/command-line-injection"
  tn "r4 made no unpaginated fetch of a paginated read" grep -qE 'UNPAGINATED (check-runs|alerts-open)' "$ST/calls.log"

  mk_case r4b; ov check-runs-page2-failure.json check-runs.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r4b a failing Analyze run on check-runs page 2 is seen" || fail "r4b page-2 failure seen"
fi

# ---------------------------------------------------------------------------------------------
# Row 5/6/11 and the wait semantics
# ---------------------------------------------------------------------------------------------
if want r5; then
  echo "== r5: an Analyze check-run stays in_progress past the cap =="
  mk_case r5; ov check-runs-in-progress.json check-runs.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r5 exit non-zero" || fail "r5 exit non-zero (got $GATE_RC)"
  tn "r5 not green" out_has "verdict=GREEN"
  eq "r5 polled exactly MAX_POLLS times" "$(count_calls 'check-runs')" "5"
  eq "r5 never read alerts" "$(count_calls 'code-scanning/alerts')" "0"
  eq "r5 upserts one degraded issue" "$(ncreate)" "1"
  t "r5 degraded body carries the reason code" body_has "analyze-timeout"
fi

if want r6; then
  echo "== r6: zero Analyze check-runs (vacuous-green guard) =="
  mk_case r6; ov check-runs-zero.json check-runs.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r6 exit non-zero" || fail "r6 exit non-zero (got $GATE_RC)"
  tn "r6 not green" out_has "verdict=GREEN"
  eq "r6 upserts one degraded issue" "$(ncreate)" "1"
  t "r6 degraded body carries the reason code" body_has "no-analyze-check-runs"
fi

if want r11; then
  echo "== r11: all Analyze runs completed but one concluded failure =="
  mk_case r11; ov check-runs-one-failure.json check-runs.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r11 exit non-zero" || fail "r11 exit non-zero (got $GATE_RC)"
  tn "r11 not green" out_has "verdict=GREEN"
  eq "r11 does not keep polling a settled failure" "$(count_calls 'check-runs')" "1"
  t "r11 degraded body carries the reason code" body_has "analyze-not-success"
fi

if want w1; then
  echo "== w1: wait semantics (sequence, latest run per name, foreign app ignored) =="
  mk_case w1; ov check-runs-in-progress.json check-runs.1.json; cp "$FIX/base/check-runs.json" "$ST/check-runs.2.json"; run_gate
  eq "w1 completes once the run finishes on poll 2" "$GATE_RC" "0"
  eq "w1 polled check-runs exactly twice" "$(count_calls 'check-runs')" "2"

  mk_case w2; ov check-runs-old-red-new-green.json check-runs.json; run_gate
  eq "w2 an old red followed by a newer green passes (latest per name)" "$GATE_RC" "0"

  mk_case w3; ov check-runs-old-green-new-red.json check-runs.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "w3 an old green followed by a newer red fails (latest per name)" || fail "w3 old green new red must fail"

  mk_case w4; run_gate
  eq "w4 a failing Analyze run from a foreign app is ignored (base fixture)" "$GATE_RC" "0"
fi

# ---------------------------------------------------------------------------------------------
# Row 7: closed tracker is not a dedupe signal
# ---------------------------------------------------------------------------------------------
if want r7; then
  echo "== r7: tracker exists but is CLOSED while the alert is open =="
  mk_case r7; ov alert-critical-untracked.json alerts-open.json; ov issue-closed-101.json issues-closed.json; run_gate
  eq "r7 exit 1" "$GATE_RC" "1"
  eq "r7 files a new issue" "$(ncreate)" "1"
  tn "r7 never listed closed issues for the open-alert dedupe" grep -qF -- "--state closed" "$ST/calls.log"
  tn "r7 never listed state all for the open-alert dedupe" grep -qF -- "--state all" "$ST/calls.log"
fi

# ---------------------------------------------------------------------------------------------
# Row 8: dry run
# ---------------------------------------------------------------------------------------------
if want r8; then
  echo "== r8: dry_run=true with a qualifying alert =="
  mk_case r8; ov alert-critical-untracked.json alerts-open.json; run_gate DRY_RUN=true
  eq "r8 exit 1" "$GATE_RC" "1"
  eq "r8 no gh issue create" "$(ncreate)" "0"
  tn "r8 no create call recorded at all" grep -qF "gh issue create" "$ST/calls.log"
  t "r8 says it is a dry run" out_has "DRY RUN"

  mk_case r8b; ov alert-critical-untracked.json alerts-open.json; ov issue-tracked-101.json issues-open.json; run_gate DRY_RUN=true
  eq "r8b dry run on a tracked alert is green" "$GATE_RC" "0"

  mk_case r8c; ov check-runs-zero.json check-runs.json; run_gate DRY_RUN=true
  [[ "$GATE_RC" -ne 0 ]] && pass "r8c dry run still exits non-zero on a degraded exit" || fail "r8c dry degraded non-zero"
  eq "r8c dry run files no degraded issue" "$(ncreate)" "0"
  eq "r8c dry run comments nothing" "$(ncomment)" "0"
fi

# ---------------------------------------------------------------------------------------------
# Row 9: analyses never settle
# ---------------------------------------------------------------------------------------------
if want r9; then
  echo "== r9: analyses count keeps changing / stays zero =="
  mk_case r9
  for i in 1 2 3 4 5 6 7 8; do
    jq -c --argjson n "$i" --arg s "$GOOD_SHA" '[range(0;$n) as $k | {id:(500+$k),ref:"refs/heads/main",commit_sha:$s,category:("/language:l\($k)")}]' <<<'null' >"$ST/analyses.$i.json"
  done
  run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r9 a count that never stabilises is non-zero" || fail "r9 unsettled non-zero"
  tn "r9 not green" out_has "verdict=GREEN"
  eq "r9 never read alerts" "$(count_calls 'code-scanning/alerts')" "0"
  t "r9 degraded body carries the reason code" body_has "analyses-unsettled"

  mk_case r9b; ov analyses-empty.json analyses.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r9b a count that stays zero is non-zero" || fail "r9b zero analyses non-zero"
  eq "r9b never read alerts" "$(count_calls 'code-scanning/alerts')" "0"

  # The real endpoint IGNORES sha=: the body is a multi-commit page. Only this commit's rows count.
  mk_case r9d; ov analyses-other-commits-only.json analyses.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r9d analyses of OTHER commits only (stable, non-empty) is not settled" || fail "r9d other-commits-only non-zero"
  tn "r9d not green" out_has "verdict=GREEN"
  eq "r9d never read alerts" "$(count_calls 'code-scanning/alerts')" "0"
  eq "r9d polled the phase-2 cap (SETTLE_POLLS=5: its own budget, not what phase 1 left over)" "$(count_calls 'code-scanning/analyses')" "5"
  t "r9d degraded body carries the reason code" body_has "analyses-unsettled"

  mk_case r9e
  jq -c --arg s "$GOOD_SHA" 'map(select(.commit_sha == $s))' "$FIX/base/analyses.json" >"$ST/g.json"
  jq -c '. + [{id:700,ref:"refs/heads/main",commit_sha:"2222222222222222222222222222222222222222",category:"/language:x"}]' "$ST/g.json" >"$ST/analyses.1.json"
  jq -c '. + [{id:701,ref:"refs/heads/main",commit_sha:"2222222222222222222222222222222222222222",category:"/language:x"},{id:702,ref:"refs/heads/main",commit_sha:"2222222222222222222222222222222222222222",category:"/language:y"}]' "$ST/g.json" >"$ST/analyses.2.json"
  run_gate
  eq "r9e this commit's count is stable while other commits' rows keep arriving: settles" "$GATE_RC" "0"
  eq "r9e settled on the second analyses poll (a global count would still be moving)" "$(count_calls 'code-scanning/analyses')" "2"

  mk_case r9c; jq -c --arg s "$GOOD_SHA" '[(map(select(.commit_sha == $s)) | .[:1][]), (map(select(.commit_sha != $s))[])]' "$FIX/base/analyses.json" >"$ST/analyses.1.json"; cp "$FIX/base/analyses.json" "$ST/analyses.2.json"; run_gate
  eq "r9c settles once the count is non-zero and unchanged across two polls" "$GATE_RC" "0"
  eq "r9c polled analyses three times (1, then 3, 3)" "$(count_calls 'code-scanning/analyses')" "3"
fi

# ---------------------------------------------------------------------------------------------
# Row 10: alert-controlled text never reaches an annotation or an issue
# ---------------------------------------------------------------------------------------------
if want r10; then
  echo "== r10: newline + forged annotation, markdown and @mention in alert text =="
  mk_case r10; ov alert-injection.json alerts-open.json; run_gate
  eq "r10 exit 1" "$GATE_RC" "1"
  eq "r10 files exactly one issue" "$(ncreate)" "1"
  eq "r10 a non-matching rule id is replaced by invalid-rule-id" "$(latest_title)" "sec: CodeQL alert #301 — invalid-rule-id"
  tn "r10 no forged text in any log line" grep -q "forged" "$ST/out.txt"
  tn "r10 no log line starts with a forged workflow command" grep -qE '^::error::forged' "$ST/out.txt"
  tn "r10 body carries no forged text" body_has "forged"
  tn "r10 body carries no @mention" body_has "@"
  tn "r10 body carries no markdown link" body_has "]("
  tn "r10 body carries no foreign URL" body_has "evil.example"
  tn "r10 title carries no forged text" grep -q "forged" "$ST/created.1.title"
  eq "r10 body is only the number, rule id, severity and the derived URL (no other URL)" \
    "$(grep -c 'https\?://' "$ST/created.1.body")" "1"

  mk_case r10b
  jq -c '.[0].rule.id = "js/ok-rule.v2"' "$FIX/scenarios/alert-critical-untracked.json" >"$ST/alerts-open.json"; run_gate
  eq "r10b a valid rule id is used verbatim" "$(latest_title)" "sec: CodeQL alert #101 — js/ok-rule.v2"

  mk_case r10c
  jq -c --arg id "$(printf 'a%.0s' $(seq 1 101))" '.[0].rule.id = $id' "$FIX/scenarios/alert-critical-untracked.json" >"$ST/alerts-open.json"; run_gate
  eq "r10c a 101-character rule id is replaced" "$(latest_title)" "sec: CodeQL alert #101 — invalid-rule-id"

  mk_case r10d
  jq -c '.[0].rule.id = "js/ok\n"' "$FIX/scenarios/alert-critical-untracked.json" >"$ST/alerts-open.json"; run_gate
  eq "r10d a rule id with a trailing newline is replaced (anchors are not line anchors)" "$(latest_title)" "sec: CodeQL alert #101 — invalid-rule-id"

  mk_case r10e
  jq -c '.[0].rule.id = "js/with space"' "$FIX/scenarios/alert-critical-untracked.json" >"$ST/alerts-open.json"; run_gate
  eq "r10e a rule id with a space is replaced" "$(latest_title)" "sec: CodeQL alert #101 — invalid-rule-id"

  mk_case r10f
  jq -c '.[0].number = "7\n::error::forged-number"' "$FIX/scenarios/alert-critical-untracked.json" >"$ST/alerts-open.json"; run_gate
  tn "r10f a non-numeric alert number is never echoed" grep -q "forged" "$ST/out.txt"
  eq "r10f a non-numeric alert number files nothing" "$(ncreate)" "0"
fi

# ---------------------------------------------------------------------------------------------
# Row 12: degraded exits upsert one issue
# ---------------------------------------------------------------------------------------------
if want r12; then
  echo "== r12: degraded exit -> exactly one codeql-gate-degraded issue, deduplicated =="
  mk_case r12; ov check-runs-zero.json check-runs.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r12 first degraded run exits non-zero" || fail "r12 first degraded non-zero"
  eq "r12 first run creates one issue" "$(ncreate)" "1"
  eq "r12 title is exactly codeql-gate-degraded" "$(latest_title)" "codeql-gate-degraded"
  eq "r12 labels: meta/machinery (ADR-216), type/security (dedupe scope), priority/p2-medium, action-required (the only page for a queue-made push)" "$(latest_labels)" "$LBL_P2"
  t "r12 body names the commit" body_has "$GOOD_SHA"
  t "r12 body links the run by id" body_has "https://github.com/$REPO_SLUG/actions/runs/424242"
  run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r12 second degraded run exits non-zero" || fail "r12 second degraded non-zero"
  eq "r12 second run creates no second issue" "$(ncreate)" "0"
  eq "r12 second run updates the existing issue with a comment" "$(ncomment)" "1"

  mk_case r12b; ov check-runs-zero.json check-runs.json; ov issue-poison-degraded.json issues-open.json; run_gate
  eq "r12b a non-bot issue with the degraded title is not a dedupe signal" "$(ncreate)" "1"
fi

# ---------------------------------------------------------------------------------------------
# Row 14: poisoned tracker
# ---------------------------------------------------------------------------------------------
if want r14; then
  echo "== r14: open issue titled for the alert but authored by a non-bot =="
  mk_case r14; ov alert-critical-untracked.json alerts-open.json; ov issue-poison-101.json issues-open.json; run_gate
  eq "r14 exit 1" "$GATE_RC" "1"
  eq "r14 the alert is untracked: a new issue is filed" "$(ncreate)" "1"
  t "r14 the dedupe list was bot-scoped" grep -qF -- "--author app/github-actions" "$ST/calls.log"
  t "r14 the dedupe list was label-scoped" grep -qF -- "--label type/security" "$ST/calls.log"
fi

# ---------------------------------------------------------------------------------------------
# Row 15: input validation
# ---------------------------------------------------------------------------------------------
if want r15; then
  echo "== r15: input validation happens before any API call =="
  bad_inputs=(
    "SHA=abc"
    "SHA="
    "SHA=0123456789ABCDEF0123456789ABCDEF01234567"
    "SHA=0123456789abcdef0123456789abcdef012345678"
    "SHA=0123456789abcdef0123456789abcdef0123456g"
    "SHA=0123456789abcdef0123456789abcdef01234567"$'\n'"::error::forged"
    "SHA=0123456789abcdef0123456789abcdef01234567"$'\n'
    "DRY_RUN=yes"
    "DRY_RUN="
    "GH_REPO=not-a-slug"
    "GH_REPO=a/b/c"
    "POLL_INTERVAL=abc"
    "MAX_POLLS=0"
    "MAX_POLLS=x1"
    "SETTLE_POLLS=0"
    "SETTLE_POLLS=x1"
    "DEADLINE_SECONDS=0"
    "DEADLINE_SECONDS=abc"
  )
  i=0
  for bi in "${bad_inputs[@]}"; do
    i=$((i + 1)); mk_case "r15-$i"; ov alert-critical-untracked.json alerts-open.json
    run_gate "$bi"
    [[ "$GATE_RC" -ne 0 ]] && pass "r15.$i rejected (non-zero)" || fail "r15.$i rejected (non-zero) for input $i"
    [[ ! -s "$ST/calls.log" ]] && pass "r15.$i rejected before any gh call" || fail "r15.$i no gh call for input $i"
    eq "r15.$i files nothing" "$(ncreate)" "0"
    tn "r15.$i never echoes the forged input back as a command" grep -qE '^::error::forged' "$ST/out.txt"
  done
  mk_case r15-ok; run_gate SHA="$GOOD_SHA" DRY_RUN=true
  eq "r15 a valid sha with dry_run=true is accepted" "$GATE_RC" "0"
fi

# ---------------------------------------------------------------------------------------------
# H3 / H4: must-PASS non-canonical inputs and the real CLI's list/pagination shape
# ---------------------------------------------------------------------------------------------
if want h3; then
  echo "== h3: capitalised severity files; medium/low/null/PR-ref alerts never file =="
  mk_case h3; ov alerts-open-mixed.json alerts-open.json; run_gate
  eq "h3 exit 1" "$GATE_RC" "1"
  eq "h3 files exactly one issue (the capitalised High alert)" "$(ncreate)" "1"
  eq "h3 title" "$(latest_title)" "sec: CodeQL alert #401 — js/capital-high"
  tn "h3 body severity is normalised (no capital H leaks)" body_has "High"

  mk_case h3b; ov alerts-open-mixed.json alerts-open.json
  jq -c '[{number:9401,title:"sec: CodeQL alert #401 — js/capital-high",_author:"app/github-actions",_labels:["type/security"]}]' <<<'null' >"$ST/issues-open.json"
  run_gate
  eq "h3b with the High alert tracked the whole mixed set is green" "$GATE_RC" "0"
  eq "h3b files nothing (medium, low, null-severity and PR-ref alerts never qualify)" "$(ncreate)" "0"

  mk_case h3c; ov alerts-open-same-prefix.json alerts-open.json; ov issue-tracked-12-only.json issues-open.json; run_gate
  eq "h3c a tracker for #12 does not track #1 (exact prefix, not substring)" "$GATE_RC" "1"
  eq "h3c files the #1 issue" "$(ncreate)" "1"
fi

if want h4; then
  echo "== h4: bounded tracker list (the real CLI caps at 30 rows without --limit) =="
  mk_case h4; ov alert-critical-untracked.json alerts-open.json
  jq -c '[range(0;34) as $i | {number:(7000+$i),title:("sec: CodeQL alert #\(8000+$i) — filler"),_author:"app/github-actions",_labels:["type/security"]}]
         + [{number:9101,title:"sec: CodeQL alert #101 — js/sql-injection",_author:"app/github-actions",_labels:["type/security"]}]
         + [range(0;5) as $i | {number:(7100+$i),title:("sec: CodeQL alert #\(8100+$i) — filler"),_author:"app/github-actions",_labels:["type/security"]}]' \
    <<<'null' >"$ST/issues-open.json"
  run_gate
  eq "h4 the tracker at row 35 of 40 is found (green)" "$GATE_RC" "0"
  eq "h4 files nothing" "$(ncreate)" "0"
  eq "h4 every gh issue list call carries --limit 200" \
    "$(grep -c '^gh issue list' "$ST/calls.log")" "$(grep '^gh issue list' "$ST/calls.log" | grep -c -- '--limit 200')"
  tn "h4 no gh search call" grep -qE '^gh search' "$ST/calls.log"
fi

# ---------------------------------------------------------------------------------------------
# Review #9455 rows: production defaults, wall-clock deadline, phase budgets, exit codes, sanitize,
# check-run name match, duplicate alert numbers
# ---------------------------------------------------------------------------------------------
gen_analyses_growing() { # <n>: analyses.1..n.json, the k-th holding k rows for this commit (never settles before n+1)
  local i
  for i in $(seq 1 "$1"); do
    jq -c --argjson n "$i" --arg s "$GOOD_SHA" '[range(0;$n) as $k | {id:(500+$k),ref:"refs/heads/main",commit_sha:$s,category:("/language:l\($k)")}]' <<<'null' >"$ST/analyses.$i.json" || exit 2
  done
}
sleep_stub() { # a counting sleep on PATH: nothing sleeps, every argv is logged to sleeps.log
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$GATE_STATE/sleeps.log"\n' >"$ST/bin/sleep" || exit 2
  chmod +x "$ST/bin/sleep" || exit 2
  : >"$ST/sleeps.log"
}
# shellcheck disable=SC2120,SC2119 # the VAR=value arguments are optional; most callers pass none
run_gate_clean() { # [VAR=value ...]: the SUT with ONLY the required inputs, so every default is production
  local rc=0
  : >"$ST/calls.log"
  env -i PATH="$ST/bin:$PATH" HOME="$ST" TMPDIR="$ST/tmp" GATE_STATE="$ST" GH_TOKEN=synthetic-token \
    GH_REPO="$REPO_SLUG" SHA="$GOOD_SHA" "$@" bash "$SUT" >"$ST/out.txt" 2>&1 || rc=$?
  GATE_RC=$rc
  if [[ ! -s "$ST/calls.log" ]]; then fail "case $CASE (clean env) recorded zero gh calls"; fi
}
sleeps_n() { local n=0; n="$(grep -c . "$ST/sleeps.log" 2>/dev/null)" || true; printf '%s' "${n:-0}"; }
sleeps_distinct() { sort -u "$ST/sleeps.log" | tr '\n' ' '; }

if want d1; then
  echo "== d1: the production defaults are 30 s, 50 phase-1 polls, 8 phase-2 polls, 1800 s =="
  dcode="$SANDBOX/d1.code"; grep -vE '^[[:space:]]*#' "$SUT" >"$dcode"
  t "d1 POLL_INTERVAL default literal is 30" grep -qxF 'POLL_INTERVAL="${POLL_INTERVAL:-30}"' "$dcode"
  t "d1 MAX_POLLS default literal is 50" grep -qxF 'MAX_POLLS="${MAX_POLLS:-50}"' "$dcode"
  t "d1 SETTLE_POLLS default literal is 8" grep -qxF 'SETTLE_POLLS="${SETTLE_POLLS:-8}"' "$dcode"
  t "d1 DEADLINE_SECONDS default literal is 1800" grep -qxF 'DEADLINE_SECONDS="${DEADLINE_SECONDS:-1800}"' "$dcode"

  mk_case d1a; sleep_stub; ov check-runs-in-progress.json check-runs.json; run_gate_clean
  eq "d1a an Analyze run that never completes exits 1 at the default cap" "$GATE_RC" "1"
  eq "d1a polled check-runs exactly 50 times (default MAX_POLLS)" "$(count_calls 'check-runs')" "50"
  eq "d1a slept between polls 49 times (never after the last)" "$(sleeps_n)" "49"
  eq "d1a every sleep was exactly 30 seconds (default POLL_INTERVAL)" "$(sleeps_distinct)" "30 "
  t "d1a degraded with analyze-timeout (the poll cap, not the deadline: the sleeps were stubbed)" body_has "analyze-timeout"

  mk_case d1b; sleep_stub; gen_analyses_growing 8; run_gate_clean
  eq "d1b analyses that never settle exit 1 at the default phase-2 cap" "$GATE_RC" "1"
  eq "d1b polled analyses exactly 8 times (default SETTLE_POLLS)" "$(count_calls 'code-scanning/analyses')" "8"
  eq "d1b slept 7 times, every one 30 seconds" "$(sleeps_n) $(sleeps_distinct)" "7 30 "
  t "d1b degraded with analyses-unsettled" body_has "analyses-unsettled"

  mk_case d1c; sleep_stub; run_gate_clean
  eq "d1c a clean commit is green on the defaults" "$GATE_RC" "0"
  eq "d1c a clean commit sleeps once (the settle interval), 30 seconds" "$(sleeps_n) $(sleeps_distinct)" "1 30 "
fi

if want d2; then
  echo "== d2: the wall-clock deadline (the script degrades before the job's 40-minute kill) =="
  mk_case d2a; ov check-runs-in-progress.json check-runs.json; echo 1 >"$ST/check-runs.delay"
  t0=$SECONDS; run_gate DEADLINE_SECONDS=3 POLL_INTERVAL=0 MAX_POLLS=50; el=$((SECONDS - t0))
  eq "d2a a slow API exits 1 (degraded) at the deadline" "$GATE_RC" "1"
  t "d2a degraded with deadline-exceeded" body_has "deadline-exceeded"
  eq "d2a filed exactly one degraded issue" "$(ncreate)" "1"
  [[ "$(count_calls 'check-runs')" -ge 2 && "$(count_calls 'check-runs')" -le 5 ]] && pass "d2a stopped after a handful of polls, far below MAX_POLLS=50" || fail "d2a polls stopped by the deadline (got $(count_calls 'check-runs'))"
  [[ "$el" -le 12 ]] && pass "d2a returned within the deadline plus slack (${el}s)" || fail "d2a returned within the deadline plus slack (took ${el}s)"
  t "d2a the annotation names the phase" grep -qF "waiting for the Analyze check-runs" "$ST/out.txt"

  mk_case d2b; gen_analyses_growing 8; echo 1 >"$ST/analyses.delay"
  run_gate DEADLINE_SECONDS=3 POLL_INTERVAL=0 SETTLE_POLLS=50
  eq "d2b the deadline also bounds phase 2" "$GATE_RC" "1"
  t "d2b degraded with deadline-exceeded" body_has "deadline-exceeded"
  t "d2b the annotation names the phase" grep -qF "waiting for the analyses to settle" "$ST/out.txt"

  mk_case d2c; sleep_stub; ov check-runs-in-progress.json check-runs.json
  run_gate DEADLINE_SECONDS=30 POLL_INTERVAL=30
  eq "d2c a pause that would not fit the budget is never taken (exit 1)" "$GATE_RC" "1"
  eq "d2c polled once and did not sleep" "$(count_calls 'check-runs') $(sleeps_n)" "1 0"
  t "d2c degraded with deadline-exceeded" body_has "deadline-exceeded"

  mk_case d2d; run_gate DEADLINE_SECONDS=600
  eq "d2d a fast run well inside the deadline is unaffected (green)" "$GATE_RC" "0"
fi

if want d3; then
  echo "== d3: phase 2 has its own poll budget, separate from phase 1 =="
  mk_case d3a; gen_analyses_growing 4
  for i in 1 2 3 4; do cp "$FIX/scenarios/check-runs-in-progress.json" "$ST/check-runs.$i.json" || exit 2; done
  cp "$FIX/base/check-runs.json" "$ST/check-runs.5.json" || exit 2
  jq -c '.' "$ST/analyses.4.json" >"$ST/analyses.5.json" || exit 2
  run_gate
  eq "d3a phase 1 spent its whole budget (5 of 5), phase 2 then settled on its 5th poll: green" "$GATE_RC" "0"
  eq "d3a check-runs polled 5 times" "$(count_calls 'check-runs')" "5"
  eq "d3a analyses polled 5 times (a shared budget would have degraded at the first)" "$(count_calls 'code-scanning/analyses')" "5"

  mk_case d3b; gen_analyses_growing 8
  for i in 1 2 3 4; do cp "$FIX/scenarios/check-runs-in-progress.json" "$ST/check-runs.$i.json" || exit 2; done
  cp "$FIX/base/check-runs.json" "$ST/check-runs.5.json" || exit 2
  run_gate
  eq "d3b analyses that keep growing degrade after exactly SETTLE_POLLS polls" "$GATE_RC" "1"
  eq "d3b ten polls were made in all (5 + 5), twice MAX_POLLS" "$(( $(count_calls 'check-runs') + $(count_calls 'code-scanning/analyses') ))" "10"
  t "d3b degraded with analyses-unsettled" body_has "analyses-unsettled"

  mk_case d3c; gen_analyses_growing 8
  run_gate SETTLE_POLLS=2
  eq "d3c SETTLE_POLLS=2 caps phase 2 at two polls although MAX_POLLS=5" "$(count_calls 'code-scanning/analyses')" "2"
  eq "d3c and degrades" "$GATE_RC" "1"
fi

if want x1; then
  echo "== x1: an unset or empty GH_REPO is a rejected input (exit 2, no API call), as the header says =="
  mk_case x1a; : >"$ST/calls.log"; rc=0
  env -i PATH="$ST/bin:$PATH" HOME="$ST" TMPDIR="$ST/tmp" GATE_STATE="$ST" GH_TOKEN=synthetic-token SHA="$GOOD_SHA" bash "$SUT" >"$ST/out.txt" 2>&1 || rc=$?
  eq "x1a unset GH_REPO exits exactly 2" "$rc" "2"
  eq "x1a unset GH_REPO made no gh call" "$(wc -c <"$ST/calls.log" | tr -d ' ')" "0"
  t "x1a unset GH_REPO is reported as a rejected input" grep -qF "input rejected: GH_REPO" "$ST/out.txt"
  mk_case x1b; run_gate GH_REPO=
  eq "x1b empty GH_REPO exits exactly 2" "$GATE_RC" "2"
  mk_case x1c; run_gate DEADLINE_SECONDS=0
  eq "x1c DEADLINE_SECONDS=0 exits exactly 2" "$GATE_RC" "2"
  t "x1 the header documents exit 2 for a rejected input including GH_REPO" grep -qF "2 input rejected (no API call), including an unset or empty GH_REPO" "$SUT"
fi

if want sx; then
  echo "== sx: sanitize() on a hostile gh stderr (newline + forged workflow command, markdown, @mention) =="
  mk_case sx
  {
    printf 'gh: HTTP 500 synthetic\n::error::forged-annotation\n::set-output name=x::forged\n'
    printf '[click](http://evil.example/p) @octocat `tick` <script>alert</script>\n'
    for _ in $(seq 1 60); do printf 'zzzzzzzzzz'; done
  } >"$ST/check-runs.err"
  echo 1 >"$ST/check-runs.rc"
  run_gate
  eq "sx the gate degrades (exit 1)" "$GATE_RC" "1"
  tn "sx no output line starts with the forged ::error:: command" grep -qE '^::error::forged' "$ST/out.txt"
  tn "sx no output line starts with a forged ::set-output command" grep -qE '^::set-output' "$ST/out.txt"
  eq "sx every workflow-command line is the script's own annotation" "$(grep -E '^::' "$ST/out.txt" | grep -cvE '^::error title=codeql-main-alert-gate::')" "0"
  grep -F 'degraded (api-error)' "$ST/out.txt" >"$ST/ann.txt" || : >"$ST/ann.txt"
  t "sx the annotation was emitted and kept the legitimate status text" grep -qF "HTTP 500 synthetic" "$ST/ann.txt"
  # The script's own fixed text carries parentheses; the stderr-derived DETAIL is everything after "(rc=N) ".
  sed -E 's/^.*\(rc=[0-9]+\) //' "$ST/ann.txt" >"$ST/detail.txt"
  t "sx the stderr-derived detail was isolated" test -s "$ST/detail.txt"
  tn "sx no markdown or mention metacharacter survives in the stderr-derived detail" grep -qE '[][@()<>`]' "$ST/detail.txt"
  [[ "$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$ST/ann.txt")" -le 400 ]] && pass "sx the annotation detail is bounded (200 characters)" || fail "sx the annotation detail is bounded (200 characters)"
  tn "sx the degraded issue body carries none of the stderr" grep -qE 'evil|octocat|forged' "$ST/created.1.body"
fi

if want w5; then
  echo "== w5: only Analyze (*) check-runs gate the wait =="
  mk_case w5; ov check-runs-non-analyze-noise.json check-runs.json; run_gate
  eq "w5 in-flight non-Analyze runs (build, Analyzer (x), analyze (lowercase), CodeQL / Analyze (x), bare Analyze) never block the wait" "$GATE_RC" "0"
  eq "w5 settled on the first check-runs poll" "$(count_calls 'check-runs')" "1"
fi

if want h5; then
  echo "== h5: the same alert number on two pages (offset pagination can repeat a row) files ONE issue =="
  mk_case h5; { cat "$FIX/scenarios/alert-critical-untracked.json"; cat "$FIX/scenarios/alert-critical-untracked.json"; } >"$ST/alerts-open.json"; run_gate
  eq "h5 exit 1" "$GATE_RC" "1"
  eq "h5 exactly one issue for the duplicated number" "$(ncreate)" "1"
  t "h5 one candidate" out_has "open critical/high candidates: 1"
fi

if want z1; then
  echo "== z1: numeric inputs are digits only; a leading zero is decimal (08 is eight), never octal =="
  mk_case z1a; sleep_stub; ov check-runs-in-progress.json check-runs.json
  run_gate POLL_INTERVAL=08 MAX_POLLS=3 DEADLINE_SECONDS=600
  eq "z1a POLL_INTERVAL=08 with check-runs running exits 1 (degraded), never 0" "$GATE_RC" "1"
  tn "z1a no octal arithmetic error leaked (value too great for base)" grep -qF "value too great" "$ST/out.txt"
  tn "z1a never prints verdict=GREEN while check-runs are still running" out_has "verdict=GREEN"
  eq "z1a polled phase 1 exactly MAX_POLLS (3) times: the loop was not aborted" "$(count_calls 'check-runs')" "3"
  eq "z1a slept 2 times, each exactly 8 seconds (the normalised value)" "$(sleeps_n) $(sleeps_distinct)" "2 8 "
  t "z1a degraded with analyze-timeout (the poll cap)" body_has "analyze-timeout"

  mk_case z1b; sleep_stub; run_gate POLL_INTERVAL=09 DEADLINE_SECONDS=0600 MAX_POLLS=0005 SETTLE_POLLS=05
  eq "z1b POLL_INTERVAL=09 DEADLINE_SECONDS=0600 MAX_POLLS=0005 SETTLE_POLLS=05 are accepted" "$GATE_RC" "0"
  eq "z1b the settle pause was exactly 9 seconds" "$(sleeps_n) $(sleeps_distinct)" "1 9 "

  mk_case z1c; gen_analyses_growing 8; run_gate SETTLE_POLLS=08
  eq "z1c SETTLE_POLLS=08 caps phase 2 at eight polls" "$(count_calls 'code-scanning/analyses')" "8"
  t "z1c degraded with analyses-unsettled" body_has "analyses-unsettled"

  zi=0
  for zbad in "POLL_INTERVAL=-1" "POLL_INTERVAL=1.5" "POLL_INTERVAL=00099999" "MAX_POLLS=000" "SETTLE_POLLS=0000" "DEADLINE_SECONDS=00" "DEADLINE_SECONDS=1e3" "MAX_POLLS=99999"; do
    zi=$((zi + 1)); mk_case "z1d-$zi"; run_gate "$zbad"
    eq "z1d $zbad is rejected (exit 2)" "$GATE_RC" "2"
    if [[ ! -s "$ST/calls.log" ]]; then pass "z1d $zbad rejected before any gh call"; else fail "z1d $zbad rejected before any gh call"; fi
  done
fi

if want z2; then
  echo "== z2: the wall-clock deadline also bounds phase 3 (the alerts read and the issue-filing loop) =="
  mk_case z2a; ov alert-critical-untracked.json alerts-open.json; echo 6 >"$ST/alerts-open.delay"
  run_gate DEADLINE_SECONDS=5 POLL_INTERVAL=0
  eq "z2a a slow alerts read that passes the deadline exits 1" "$GATE_RC" "1"
  t "z2a degraded with deadline-exceeded" body_has "deadline-exceeded"
  eq "z2a the only issue filed is the degraded one (no tracker was created past the deadline)" "$(ncreate) $(latest_title)" "1 codeql-gate-degraded"
  t "z2a the annotation names phase 3" grep -qF "before every tracking issue was filed" "$ST/out.txt"
  eq "z2a the deadline stopped the run BEFORE the tracking-issue list read (the only list call is the degraded upsert's)" "$(count_calls 'gh issue list')" "1"

  mk_case z2b; jq -c '[.[0], (.[0] | .number = 102)]' "$FIX/scenarios/alert-critical-untracked.json" >"$ST/alerts-open.json" || exit 2
  echo 6 >"$ST/issue-create.delay"
  run_gate DEADLINE_SECONDS=5 POLL_INTERVAL=0
  eq "z2b a slow first create that passes the deadline stops the loop (exit 1)" "$GATE_RC" "1"
  t "z2b degraded with deadline-exceeded" out_has "degraded=deadline-exceeded"
  eq "z2b exactly two issues were created: the first tracker, then the degraded one (the second tracker was NOT)" "$(ncreate)" "2"
  t "z2b the first create was a tracker" grep -qF "filed: sec: CodeQL alert #101" "$ST/out.txt"
  tn "z2b the second candidate was not filed" grep -qF "filed: sec: CodeQL alert #102" "$ST/out.txt"

  mk_case z2c; ov alert-critical-untracked.json alerts-open.json; run_gate DEADLINE_SECONDS=600 POLL_INTERVAL=0
  eq "z2c a fast phase 3 well inside the deadline still files its tracker" "$(ncreate) $(latest_title)" "1 sec: CodeQL alert #101 — js/sql-injection"
fi

if want z3; then
  echo "== z3: the header does not over-claim the deadline =="
  tn "z3 the header no longer claims the script ALWAYS degrades before the 40-minute kill" grep -qE 'always (degrades|exits|finish)|must always finish' "$SUT"
  t "z3 the header lists what the deadline does not bound (RESIDUAL)" grep -qF "RESIDUAL" "$SUT"
  t "z3 the header says phase 3 is bounded" grep -qF "phase 3" "$SUT"
fi

# ---------------------------------------------------------------------------------------------
# Static structure of the script and the workflow
# ---------------------------------------------------------------------------------------------
strip_comments() { grep -vE '^[[:space:]]*#' "$1"; }

if want s1; then
  echo "== s1: static structure of the script =="
  t "s1 script exists" test -f "$SUT"
  t "s1 script passes bash -n" bash -n "$SUT"
  scode="$SANDBOX/sut.code"; strip_comments "$SUT" >"$scode"
  bare="$(grep -cE '(^|[^A-Za-z0-9_./-])gh (api|issue|search)\b' "$scode")" || true
  withto="$(grep -cE 'timeout 60 gh (api|issue|search)\b' "$scode")" || true
  eq "s1 every gh invocation is preceded by timeout 60" "$bare" "$withto"
  [[ "${withto:-0}" -ge 5 ]] && pass "s1 at least five bounded gh call sites exist" || fail "s1 at least five bounded gh call sites exist (got ${withto:-0})"
  eq "s1 no || true anywhere in code" "$(grep -c '|| true' "$scode")" "0"
  eq "s1 no gh search" "$(grep -c 'gh search' "$scode")" "0"
  eq "s1 no GitHub expression syntax" "$(grep -c '\${{' "$scode")" "0"
  eq "s1 every gh api call paginates except the ONE analyses page read" "$(grep 'timeout 60 gh api' "$scode" | grep -vc -- '--paginate')" "1"
  t "s1 the single-page read is the analyses fetch_page" grep -qE 'fetch_page "analyses"' "$scode"
  tn "s1 no dismissal machinery (DISMISS_ALLOWLIST, state=dismissed) remains in code" grep -qE 'DISMISS_ALLOWLIST|state=dismissed|--search' "$scode"
  eq "s1 every gh issue list is bounded by --limit" "$(grep -c 'gh issue list' "$scode")" "$(grep -c -- '--limit 200' "$scode")"
  t "s1 errexit and pipefail are set" grep -qE '^set -euo pipefail' "$scode"
  tn "s1 no :? parameter expansion (an unset GH_REPO must exit 2 via reject_input, not 1 via bash)" grep -qF ':?' "$scode"
  t "s1 the tracker list filters on the bot author" grep -qF -- "--author app/github-actions" "$scode"
  tn "s1 uses a character-class newline escape nowhere (not a newline in ERE)" grep -qF '[^\n]' "$scode"
  labels="$(grep -oE -- '--label [A-Za-z0-9/_-]+' "$scode" | sed 's/--label //' | sort -u | tr '\n' ' ')"
  # the labels verified to exist in the repo (gh label list --limit 200: 2026-10-03, meta/machinery 2026-10-04)
  eq "s1 only existing labels are used" "$labels" "action-required meta/machinery priority/p1-high priority/p2-medium type/security "
fi

if want s2; then
  echo "== s2: the gate stays out of every release/deploy chain (workflow wiring: see the wiring suite) =="
  # The structural properties of the workflow (triggers, permissions, env routing, timeout, no continue-on-error,
  # no `|| true`, SHA pins) are asserted by codeql-main-alert-gate-workflow-wiring.test.sh, which parses the YAML.
  # Greps over the file text here would pass against a renamed trigger or a deleted env block.
  t "s2 workflow exists" test -f "$WF"
  t "s2 the structured wiring suite exists" test -f "$SCRIPT_DIR/codeql-main-alert-gate-workflow-wiring.test.sh"
  # Comment lines may name the gate (docs, watcher headers); executable lines in any other file must not.
  # Explicit globs, not a tree walk: this suite's verdict is scoped to the surfaces below.
  refs=("$ROOT"/.github/workflows/*.yml "$ROOT"/.github/actions/*/action.yml "$ROOT"/.github/scripts/*.sh "$ROOT"/plugins/soleur/scripts/*.sh)
  others="$(grep -HnF 'codeql-main-alert-gate' "${refs[@]}" 2>/dev/null | grep -vF 'codeql-main-alert-gate.yml:' | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
  eq "s2 no executable line outside the gate itself references it" "$others" ""
  keyed="$(grep -HnE '(needs|workflow_run|workflows)[^#]*codeql-main-alert-gate' "${refs[@]}" 2>/dev/null || true)"
  eq "s2 no needs/workflow_run reference to the gate" "$keyed" ""
  t "s2 the reference surfaces were actually enumerated" test "${#refs[@]}" -gt 50
fi

# ---------------------------------------------------------------------------------------------
# Meta cases: the suite tested against a stub and against a mutated copy of itself
# ---------------------------------------------------------------------------------------------
if [[ -z "${GATE_NO_META:-}" ]] && want meta; then
  echo "== meta: H1 (always-green stub) and H2 (suite ignores the exit status) must be RED =="
  stub="$SANDBOX/always-green.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$stub"; chmod +x "$stub"
  mrc=0
  GATE_NO_META=1 GATE_ONLY=c0,r1,r2 GATE_SUT="$stub" bash "$SELF" >"$SANDBOX/meta-h1.out" 2>&1 || mrc=$?
  [[ "$mrc" -ne 0 ]] && pass "H1 an always-exit-0 stub reds the suite" || fail "H1 an always-exit-0 stub reds the suite"
  t "H1 the vacuous-harness assertion fired" grep -qF "H1 vacuous harness" "$SANDBOX/meta-h1.out"

  mut_suite="$SANDBOX/suite-h2.test.sh"
  sed 's/^  GATE_RC=\$rc # H2-RC-CAPTURE$/  GATE_RC=0 # H2-RC-CAPTURE/' "$SELF" >"$mut_suite"
  tn "H2 the suite mutation landed (diff against the pristine suite)" cmp -s "$SELF" "$mut_suite"
  mrc=0
  GATE_NO_META=1 GATE_ONLY=r3 GATE_TEST_DIR="$SCRIPT_DIR" bash "$mut_suite" >"$SANDBOX/meta-h2.out" 2>&1 || mrc=$?
  [[ "$mrc" -ne 0 ]] && pass "H2 a suite that ignores the SUT exit status reds on row 3" || fail "H2 a suite that ignores the SUT exit status reds on row 3"

  # H5: the verdict helpers t, tn and eq are backstopped by verdict_helper_controls(). A suite whose helper is neutered
  # (or always-passes) must die at start-up; with GATE_ONLY naming no case, nothing else can red it, so the red below
  # is the controls and nothing else. The unmutated copy is the positive control (it must be GREEN the same way).
  mrc=0
  GATE_NO_META=1 GATE_ONLY=none GATE_TEST_DIR="$SCRIPT_DIR" bash "$SELF" >"$SANDBOX/meta-h5-ok.out" 2>&1 || mrc=$?
  eq "H5 control: the unmutated suite with no case selected is GREEN" "$mrc" "0"
  hi=0
  for spec in 't|^t\(\)  \{.*$|t() { :; }' \
              't|^t\(\)  \{.*$|t() { pass "$1"; }' \
              'tn|^tn\(\) \{.*$|tn() { :; }' \
              'tn|^tn\(\) \{.*$|tn() { pass "$1"; }' \
              'eq|^eq\(\) \{.*$|eq() { :; }' \
              'eq|^eq\(\) \{.*$|eq() { fail "$1"; }'; do
    IFS='|' read -r hname hpat hrep <<<"$spec"
    hi=$((hi + 1)); mut_h="$SANDBOX/suite-h5-$hi.test.sh"
    sed -E "s/${hpat}/${hrep}/" "$SELF" >"$mut_h"
    tn "H5.$hi the $hname helper mutation landed (diff against the pristine suite)" cmp -s "$SELF" "$mut_h"
    mrc=0
    GATE_NO_META=1 GATE_ONLY=none GATE_TEST_DIR="$SCRIPT_DIR" bash "$mut_h" >"$SANDBOX/meta-h5-$hi.out" 2>&1 || mrc=$?
    [[ "$mrc" -ne 0 ]] && pass "H5.$hi a suite with a neutered $hname helper reds" || fail "H5.$hi a suite with a neutered $hname helper reds"
    t "H5.$hi it reds on the positive control, not by accident" grep -qF "verdict helper positive control" "$SANDBOX/meta-h5-$hi.out"
  done
fi

# ---------------------------------------------------------------------------------------------
# Optional: SUT mutation battery (slow). Each mutation must LAND (differ from the pristine copy)
# and must RED the suite.
# ---------------------------------------------------------------------------------------------
if [[ -n "${GATE_MUTANTS:-}" && -z "${GATE_NO_META:-}" ]]; then
  echo "== mutants: SUT mutation battery =="
  mutdir="$SANDBOX/mutants"; mkdir -p "$mutdir" || exit 2
  mi=0
  mutate() { # <label> <sed-expression>
    local label="$1" expr="$2" mrc=0
    mi=$((mi + 1))
    local m="$mutdir/m$mi.sh"
    sed -E "$expr" "$SUT" >"$m" || { fail "mutant $mi ($label): sed failed"; return; }
    if cmp -s "$SUT" "$m"; then fail "mutant $mi ($label): mutation did NOT land"; return; fi
    GATE_NO_META=1 GATE_SUT="$m" GATE_ONLY="${GATE_MUT_ONLY:-c0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r14,r15,w1,h3,h4,s1}" bash "$SELF" >"$mutdir/m$mi.out" 2>&1 || mrc=$?
    # A kill must be a REAL assertion going red (a "  FAIL:" line), not an instrument crash or a bash syntax error in the copy.
    if [[ "$mrc" -ne 0 ]] && grep -q '^  FAIL: ' "$mutdir/m$mi.out"; then pass "mutant $mi ($label) lands and reds the suite"
    else fail "mutant $mi ($label) landed but the suite stayed GREEN (or died without a failing assertion)"; fi
  }
  # shellcheck disable=SC1090
  [[ -f "$FIX/mutants.sh" ]] && source "$FIX/mutants.sh"
fi

# ---------------------------------------------------------------------------------------------
# Verdict. The floor is reported with printf + exit, outside the pass/fail helpers.
# ---------------------------------------------------------------------------------------------
printf '\nassertions=%d passes=%d fails=%d floor=%d\n' "$ASSERTS" "$passes" "$fails" "$FLOOR"
if [[ "$fails" -gt 0 ]]; then
  printf '[RED] %d assertion(s) failed:\n' "$fails" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
WANT_ASSERTS="$FLOOR"
# With GATE_MUTANTS=1 every SUT mutant adds exactly one assertion (it lands and reds, or it fails): MUTANT_FLOOR of them.
[[ -n "${GATE_MUTANTS:-}" && -z "${GATE_NO_META:-}" ]] && WANT_ASSERTS=$((FLOOR + MUTANT_FLOOR))
if [[ -z "${GATE_ONLY:-}" && "$ASSERTS" -ne "$WANT_ASSERTS" ]]; then
  printf '[RED] assertion count %d != the exact floor %d (a case stopped running, or one was added without re-deriving the floor)\n' "$ASSERTS" "$WANT_ASSERTS" >&2
  exit 1
fi
printf '[GREEN] codeql-main-alert-gate suite\n'
exit 0
