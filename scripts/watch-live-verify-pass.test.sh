#!/usr/bin/env bash
set -uo pipefail

# Tests for watch-live-verify-pass.sh — the deterministic daily watcher that
# records the FIRST qualifying live-verify CI PASS on the flip-tracker issue
# (5463). Mirrors the sentry-issue.test.sh mock-PATH pattern: a PATH-prepended
# mock `gh` that dispatches on argv and returns per-scenario fixtures written to
# a temp dir; no network. The single side effect under test is whether the
# script calls `gh issue comment` (records evidence) or not.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-live-verify-pass.sh"

PASS=0; FAIL=0; TOTAL=0
check() { TOTAL=$((TOTAL+1)); if [[ "$2" == "0" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }

# Run the SUT under a mock `gh`. Scenario fixtures are written to $MOCKD before
# the call: state / comments / runs / jobs / log. Any `gh issue comment` body is
# appended to $MOCKD/comment_calls so the test can assert record-or-not.
# Args: state_json comments_json runs_json jobs_json log_text
run_sut() {
  local mock_dir; mock_dir="$(mktemp -d)"
  printf '%s' "$1" > "$mock_dir/state"
  printf '%s' "$2" > "$mock_dir/comments"
  printf '%s' "$3" > "$mock_dir/runs"
  printf '%s' "$4" > "$mock_dir/jobs"
  printf '%s' "$5" > "$mock_dir/log"
  : > "$mock_dir/comment_calls"

  cat > "$mock_dir/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "issue view")
    if printf '%s ' "$@" | grep -q -- '--json state';    then cat "$MOCKD/state";    exit 0; fi
    if printf '%s ' "$@" | grep -q -- '--json comments'; then cat "$MOCKD/comments"; exit 0; fi ;;
  "run list") cat "$MOCKD/runs"; exit 0 ;;
  "run view")
    if printf '%s ' "$@" | grep -q -- '--json jobs'; then cat "$MOCKD/jobs"; exit 0; fi
    if printf '%s ' "$@" | grep -q -- '--log';        then cat "$MOCKD/log";  exit 0; fi ;;
  "issue comment")
    bf=""; while [[ $# -gt 0 ]]; do [[ "$1" == "--body-file" ]] && { bf="$2"; break; }; shift; done
    [[ -n "$bf" && -f "$bf" ]] && cat "$bf" >> "$MOCKD/comment_calls"
    echo "https://github.com/jikig-ai/soleur/issues/5463#issuecomment-mock"; exit 0 ;;
esac
echo "{}"; exit 0
MOCK
  chmod +x "$mock_dir/gh"

  ( export PATH="$mock_dir:$PATH"; export MOCKD="$mock_dir"; export GH_REPO="jikig-ai/soleur"
    unset GITHUB_STEP_SUMMARY
    bash "$SUT" >"$mock_dir/out" 2>"$mock_dir/err"; echo "rc=$?" >"$mock_dir/rc" )
  LAST_RC="$(sed 's/rc=//' "$mock_dir/rc" 2>/dev/null || echo 1)"
  LAST_COMMENTS="$(cat "$mock_dir/comment_calls" 2>/dev/null || true)"
  rm -rf "$mock_dir"
}

OPEN='{"state":"OPEN"}'
CLOSED='{"state":"CLOSED"}'
NO_COMMENTS='{"comments":[]}'
SENTINEL_COMMENT='{"comments":[{"body":"recorded earlier <!-- live-verify-pass-watch:recorded run=999 -->"}]}'
RUNS='[{"databaseId":111,"headSha":"abc1234567","url":"https://github.com/jikig-ai/soleur/actions/runs/111","status":"completed"}]'
JOBS_RAN='{"jobs":[{"name":"live-verify","databaseId":222,"steps":[{"name":"Run live-verify harness (report-only)","conclusion":"success"}]}]}'
JOBS_SKIPPED='{"jobs":[{"name":"live-verify","databaseId":222,"steps":[{"name":"Run live-verify harness (report-only)","conclusion":"skipped"}]}]}'
LOG_PASS='2026-06-18T08:00:00Z live-verify  RESULT: PASS — fresh conversation persisted and appeared in the rail'
LOG_FAIL='2026-06-18T08:00:00Z live-verify  RESULT: FAIL — conversation did NOT appear in the rail'

# (a) issue CLOSED → no comment, exit 0
run_sut "$CLOSED" "$NO_COMMENTS" "$RUNS" "$JOBS_RAN" "$LOG_PASS"
check "(a) CLOSED issue records nothing" "$([[ -z "$LAST_COMMENTS" && "$LAST_RC" == "0" ]] && echo 0 || echo 1)"

# (b) sentinel already present → no comment, exit 0 (idempotent)
run_sut "$OPEN" "$SENTINEL_COMMENT" "$RUNS" "$JOBS_RAN" "$LOG_PASS"
check "(b) existing sentinel records nothing" "$([[ -z "$LAST_COMMENTS" && "$LAST_RC" == "0" ]] && echo 0 || echo 1)"

# (c) qualifying PASS → exactly one comment carrying the run url + sentinel
run_sut "$OPEN" "$NO_COMMENTS" "$RUNS" "$JOBS_RAN" "$LOG_PASS"
has_url="$(printf '%s' "$LAST_COMMENTS" | grep -cF 'actions/runs/111')"
has_sentinel="$(printf '%s' "$LAST_COMMENTS" | grep -cF 'live-verify-pass-watch:recorded run=111')"
check "(c) qualifying PASS records one comment with run url"   "$([[ "$has_url" == "1" ]] && echo 0 || echo 1)"
check "(c) qualifying PASS comment carries record sentinel"    "$([[ "$has_sentinel" == "1" ]] && echo 0 || echo 1)"
check "(c) qualifying PASS exits 0"                            "$([[ "$LAST_RC" == "0" ]] && echo 0 || echo 1)"

# (d) qualifying run but RESULT: FAIL → no comment (single-purpose: PASS only)
run_sut "$OPEN" "$NO_COMMENTS" "$RUNS" "$JOBS_RAN" "$LOG_FAIL"
check "(d) qualifying FAIL records nothing" "$([[ -z "$LAST_COMMENTS" && "$LAST_RC" == "0" ]] && echo 0 || echo 1)"

# (e) harness step skipped (no qualifying merge) → no comment
run_sut "$OPEN" "$NO_COMMENTS" "$RUNS" "$JOBS_SKIPPED" "$LOG_PASS"
check "(e) all-skipped records nothing" "$([[ -z "$LAST_COMMENTS" && "$LAST_RC" == "0" ]] && echo 0 || echo 1)"

echo "watch-live-verify-pass.test.sh: $PASS/$TOTAL passed"
[[ "$FAIL" == "0" ]]
