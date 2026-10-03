#!/usr/bin/env bash
# Suite for scripts/codeql-main-alert-gate.sh and .github/workflows/codeql-main-alert-gate.yml
# (Guard 3 of knowledge-base/project/plans/2026-10-03-feat-adopt-merge-queue-advisory-codeql-plan.md,
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
# ROW MAP (plan Guard 3). Mutation rows are scenario cases r1..r15 (r12 = degraded-exit upsert);
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

# The assertion-count floor. Reported by printf + exit at the bottom, NOT through pass/fail, so a
# harness that stops counting cannot report its own shortfall as green.
FLOOR=240

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
    GH_REPO="$REPO_SLUG" SHA="$GOOD_SHA" DRY_RUN=false POLL_INTERVAL=0 MAX_POLLS=5 GITHUB_RUN_ID=424242 \
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
LBL_P2="type/security,priority/p2-medium,action-required"

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
  tn "c0 made no unpaginated fetch" grep -qF "UNPAGINATED" "$ST/calls.log"
  t "c0 scoped the alerts read to refs/heads/main" grep -qF "ref=refs/heads/main" "$ST/calls.log"
  t "c0 waited on the commit's check-runs" grep -qF "commits/$GOOD_SHA/check-runs" "$ST/calls.log"
  t "c0 read the analyses for the sha" grep -qF "code-scanning/analyses" "$ST/calls.log"
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
  tn "r4 made no unpaginated fetch" grep -qF "UNPAGINATED" "$ST/calls.log"

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
    jq -c --argjson n "$i" '[range(0;$n) as $k | {id:(500+$k),ref:"refs/heads/main",category:("/language:l\($k)")}]' <<<'null' >"$ST/analyses.$i.json"
  done
  run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r9 a count that never stabilises is non-zero" || fail "r9 unsettled non-zero"
  tn "r9 not green" out_has "verdict=GREEN"
  eq "r9 never read alerts" "$(count_calls 'code-scanning/alerts')" "0"
  t "r9 degraded body carries the reason code" body_has "analyses-unsettled"

  mk_case r9b; ov analyses-empty.json analyses.json; run_gate
  [[ "$GATE_RC" -ne 0 ]] && pass "r9b a count that stays zero is non-zero" || fail "r9b zero analyses non-zero"
  eq "r9b never read alerts" "$(count_calls 'code-scanning/alerts')" "0"

  mk_case r9c; jq -c '.[:1]' "$FIX/base/analyses.json" >"$ST/analyses.1.json"; cp "$FIX/base/analyses.json" "$ST/analyses.2.json"; run_gate
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
  eq "r12 labels are type/security, priority/p2-medium, action-required" "$(latest_labels)" "$LBL_P2"
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
# Row 13: dismissal evasion
# ---------------------------------------------------------------------------------------------
if want r13; then
  echo "== r13: critical/high alert dismissed by a login outside the allow-list =="
  mk_case r13; ov alerts-dismissed-stranger.json alerts-dismissed.json; run_gate
  eq "r13 exit 1" "$GATE_RC" "1"
  eq "r13 files one review issue" "$(ncreate)" "1"
  eq "r13 review issue title" "$(latest_title)" "sec: CodeQL alert #601 dismissed — review"
  eq "r13 review issue labels" "$(latest_labels)" "$LBL_P1"
  tn "r13 review body does not echo the dismisser login" body_has "synthetic-stranger"
  t "r13 read the dismissed alerts ref-scoped to main" grep -qF "state=dismissed" "$ST/calls.log"

  mk_case r13b; ov alerts-dismissed-owner.json alerts-dismissed.json; run_gate
  eq "r13b a dismissal by the allow-listed owner (case-insensitive) is green" "$GATE_RC" "0"
  eq "r13b files nothing" "$(ncreate)" "0"

  mk_case r13c; ov alerts-dismissed-stranger.json alerts-dismissed.json; ov issue-closed-review-601.json issues-closed.json; run_gate
  eq "r13c a CLOSED review issue means reviewed (green)" "$GATE_RC" "0"
  eq "r13c files nothing" "$(ncreate)" "0"

  mk_case r13d; ov alerts-dismissed-null-and-medium.json alerts-dismissed.json; run_gate
  eq "r13d exit 1 (null dismisser is outside the allow-list)" "$GATE_RC" "1"
  eq "r13d files only the high alert, never the medium one" "$(ncreate)" "1"
  eq "r13d title" "$(latest_title)" "sec: CodeQL alert #602 dismissed — review"

  mk_case r13e; ov alerts-dismissed-stranger.json alerts-dismissed.json; run_gate DISMISS_ALLOWLIST=deruelle,synthetic-stranger
  eq "r13e an allow-list override admits the dismisser" "$GATE_RC" "0"

  mk_case r13f; ov alerts-dismissed-stranger.json alerts-dismissed.json; run_gate DISMISS_ALLOWLIST='bad name;x'
  [[ "$GATE_RC" -ne 0 ]] && pass "r13f a malformed allow-list is rejected" || fail "r13f malformed allow-list rejected"
  [[ ! -s "$ST/calls.log" ]] && pass "r13f rejected before any API call" || fail "r13f rejected before any API call"
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

  mk_case h3d; ov alert-critical-untracked.json alerts-open.json
  jq -c '[{number:9109,title:"sec: CodeQL alert #101 dismissed — review",_author:"app/github-actions",_labels:["type/security"]}]' <<<'null' >"$ST/issues-open.json"
  run_gate
  eq "h3d an open dismissed-review issue is not a tracker for the open alert" "$GATE_RC" "1"
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
  eq "s1 every gh api call paginates" "$(grep -c 'timeout 60 gh api' "$scode")" "$(grep 'timeout 60 gh api' "$scode" | grep -c -- '--paginate')"
  eq "s1 every gh issue list is bounded by --limit" "$(grep -c 'gh issue list' "$scode")" "$(grep -c -- '--limit 200' "$scode")"
  t "s1 errexit and pipefail are set" grep -qE '^set -euo pipefail' "$scode"
  t "s1 the tracker list filters on the bot author" grep -qF -- "--author app/github-actions" "$scode"
  tn "s1 uses a character-class newline escape nowhere (not a newline in ERE)" grep -qF '[^\n]' "$scode"
  labels="$(grep -oE -- '--label [A-Za-z0-9/_-]+' "$scode" | sed 's/--label //' | sort -u | tr '\n' ' ')"
  # the four labels verified to exist in the repo (gh label list --limit 200, 2026-10-03)
  eq "s1 only existing labels are used" "$labels" "action-required priority/p1-high priority/p2-medium type/security "
fi

if want s2; then
  echo "== s2: static structure of the workflow =="
  t "s2 workflow exists" test -f "$WF"
  t "s2 triggers on push to main" grep -qE '^[[:space:]]+branches: \[main\]' "$WF"
  t "s2 has workflow_dispatch" grep -qE '^[[:space:]]*workflow_dispatch:' "$WF"
  t "s2 sha input is declared" grep -qE '^[[:space:]]+sha:' "$WF"
  t "s2 dry_run input is a boolean" grep -qE 'type: boolean' "$WF"
  t "s2 concurrency group" grep -qE 'group: codeql-main-alert-gate' "$WF"
  t "s2 never cancels a pending verdict" grep -qE 'cancel-in-progress: false' "$WF"
  t "s2 timeout-minutes 40" grep -qE 'timeout-minutes: 40' "$WF"
  t "s2 permissions contents: read" grep -qE '^[[:space:]]+contents: read' "$WF"
  t "s2 permissions security-events: read" grep -qE '^[[:space:]]+security-events: read' "$WF"
  t "s2 permissions issues: write" grep -qE '^[[:space:]]+issues: write' "$WF"
  t "s2 permissions checks: read" grep -qE '^[[:space:]]+checks: read' "$WF"
  eq "s2 no write permission other than issues" "$(grep -E '^[[:space:]]+[a-z-]+: write' "$WF" | grep -vc 'issues: write')" "0"
  tn "s2 no write-all" grep -q 'write-all' "$WF"
  eq "s2 every uses: is pinned to a 40-hex SHA" \
    "$(grep -cE '^[[:space:]-]+uses:' "$WF")" "$(grep -E '^[[:space:]-]+uses:' "$WF" | grep -cE '@[0-9a-f]{40}')"
  t "s2 checkout does not persist credentials" grep -qE 'persist-credentials: false' "$WF"
  t "s2 calls the script" grep -qF 'scripts/codeql-main-alert-gate.sh' "$WF"
  # no ${{ }} inside any run: block (env-var routing only)
  in_run="$(awk '
    /^[[:space:]]*(- )?run:/ { match($0,/^[[:space:]]*/); ind=RLENGTH; inrun=1; if ($0 ~ /\$\{\{/) bad++; next }
    inrun { match($0,/^[[:space:]]*/); if ($0 ~ /^[[:space:]]*$/) next; if (RLENGTH<=ind) { inrun=0 } else if ($0 ~ /\$\{\{/) bad++ }
    END { print bad+0 }' "$WF")"
  eq "s2 no expression syntax inside a run: block" "$in_run" "0"
  # not a dependency of any release/deploy chain
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
    GATE_NO_META=1 GATE_SUT="$m" GATE_ONLY="${GATE_MUT_ONLY:-c0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15,w1,h3,h4,s1}" bash "$SELF" >"$mutdir/m$mi.out" 2>&1 || mrc=$?
    [[ "$mrc" -ne 0 ]] && pass "mutant $mi ($label) lands and reds the suite" || fail "mutant $mi ($label) landed but the suite stayed GREEN"
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
if [[ -z "${GATE_ONLY:-}" && "$ASSERTS" -lt "$FLOOR" ]]; then
  printf '[RED] assertion floor not met: %d < %d (a case stopped running)\n' "$ASSERTS" "$FLOOR" >&2
  exit 1
fi
printf '[GREEN] codeql-main-alert-gate suite\n'
exit 0
