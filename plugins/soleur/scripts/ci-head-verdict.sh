#!/usr/bin/env bash
# ci-head-verdict.sh -- the ONE resolver every reader of a PR head's CI state goes through (ADR-276 S3, #9728).
#
#   ci-head-verdict.sh verdict <pr> [--repo OWNER/REPO]
#   ci-head-verdict.sh wait-ready-run <pr> --before-count K [--timeout SEC] [--repo OWNER/REPO]
#   ci-head-verdict.sh ready-count <pr> [--repo OWNER/REPO]
#
# WHY. With CI_DRAFT_LIGHT on, a draft PR's `test` context is RED BY DESIGN ("draft: full battery owed at ready",
# Option R). A reader that sees that red row on a PR that has since been marked ready misreads it as a failure
# (monitor, the Phase 7 poll, drain-prs triage, admin-merge --wait), and one that sees it with no ready run ever
# created misreads the silence as "still running" forever. The decision is TIME-BASED, so no reader needs a
# light-run detector: only a `ci.yml` pull_request run created at or after the PR's latest ready event speaks for a
# non-draft head. A run created at or after T was triggered by the ready event or a later push; the ci.yml
# `draft-light` step reads the PR LIVE and runs full for ACTION == ready_for_review and for a non-draft PR.
#
# APPLICABILITY. The mechanism exists only in a repo whose default-branch `.github/workflows/ci.yml` carries the
# `draft-light` job. Any other repo (a customer repo the plugin is installed in) never produces a ready run, so
# `verdict` answers n/a (reason no-draft-light) and `wait-ready-run` answers ok (reason not-applicable): its ship and
# merge flow is byte-identical to a world without this script. A 404 on that file is "not applicable"; any other
# read failure is an API error (exit 3), never a guess.
#
# `verdict` prints exactly one marker as the last stdout line and exits 0 (a decision was made) or 3 (it could not be):
#   SOLEUR_CI_HEAD_VERDICT state=<n/a|full-decided|pending-full|no-run|stalled|awaiting-approval> pr=<N> sha=<H> run=<id|none> reason=<token>
# The state set is CLOSED. On exit 3 the marker is `state=error` (reason names the cause): a state OUTSIDE the closed
# set, so a reader that whitelists the six states ignores it and keeps its own reading (a real red `test` stays red).
# Never answer a read failure with a member of the closed set: that would let an API hiccup read as a decision.
# Order of evaluation:
#   0. the repo does not carry the mechanism (see APPLICABILITY)                                    -> n/a
#   1. no ready event ever (never a draft: bot-opened PRs with synthetic rows and no pull_request run), or the PR is a
#      draft NOW                                                                              -> n/a
#   2. the newest `test` check run (github-actions app) at H is completed + success            -> full-decided (reason
#      green-test, regardless of T: under Option R a green `test` is never a light result)
#   3. list `workflows/ci.yml/runs?event=pull_request&head_sha=H` (NEVER a run's pull_requests[], empty for ~92% of
#      runs) and keep runs created at or after T; T is the latest ReadyForReviewEvent's server time. No skew
#      allowance: the ready run was measured 2 to 3 s AFTER T (S3 gate 4), and an allowance would adopt a DRAFT push's
#      light run created just before the ready call as "the ready run"
#   4. the newest kept run decides: not completed -> pending-full; completed success|failure|timed_out ->
#      full-decided (its own rows are authoritative, a failure is never hidden as PENDING); action_required ->
#      awaiting-approval; cancelled|skipped|stale|neutral|startup_failure|anything else -> no-run (fail closed);
#      no kept run -> no-run
#   5. pending-full and no-run become `stalled` once more than N=120 minutes have passed since T (above the declared
#      73-minute path plus a ~14-minute p90 queue wait; a run still in flight at N is not a healthy slow run)
# `run=` is the DECIDING run: a reader judging `test` must use that run's rows. A newer `test` row that belongs to a
# different run (a manual re-run of a pre-T run) is stale; the row's run id is the `/actions/runs/<id>/` segment of
# its details_url. Every time comes from the SERVER (the PR read's Date header, the timeline, the runs API), never
# the local clock.
#
# `wait-ready-run` is the arm-after-ready gate. The caller reads K with `ready-count` BEFORE `gh pr ready`; the wait
# polls (every 10 s plus the calls themselves, budget --timeout, default 300; give the calling tool a timeout above it)
# until the PR's ReadyForReviewEvent count exceeds K AND a live read says it is not a draft (read-after-write lag
# guard: the previous event is never taken as T), takes the newest event's server time as T, then polls for a
# pull_request run at H created at or after T. Last stdout line:
#   SOLEUR_CI_WAIT_READY_RUN result=<ok|fail> pr=<N> sha=<H|unknown> run=<id|none> reason=<run-created|not-applicable|no-ready-event|no-run|awaiting-approval|api-error>
# Exit 0 on ok, 1 on fail (FAIL CLOSED: the caller must NOT run `gh pr merge --auto`), 2 usage, 3 when the LAST poll
# could not read (api-error: the ready state is unknown, so re-run `verdict`; do NOT `gh pr ready --undo`).
#
# `ready-count` prints the number of ReadyForReviewEvents on the PR (the filtered nodes, NOT the timeline totalCount,
# which counts every event type) and exits 3 without a number when it cannot be counted.
#
# EXIT CODES: 0 decided/ok | 1 wait failed | 2 usage | 3 gh/jq/API error (verdict prints state=error reason=<cause>).
# PORTABILITY: bash, gh and jq only (jq does the time arithmetic; no GNU `date -d`), so it runs on a stock macOS host.
# TEST SEAMS: CI_HEAD_VERDICT_NOW (ISO-8601 UTC, replaces the server clock), CI_HEAD_VERDICT_POLL_SECONDS (default 10,
# the sleep between wait polls; the poll BUDGET is always counted in 10-second units).
#
# Every `gh pr ready` caller must use a non-GITHUB_TOKEN identity: measured on the S3 probe, GITHUB_TOKEN cannot
# ready a PR at all (markPullRequestReadyForReview: Resource not accessible by integration), so it can never produce
# the ready event or the ready run this script waits for.
set -uo pipefail

readonly MARKER="SOLEUR_CI_HEAD_VERDICT"
readonly WAIT_MARKER="SOLEUR_CI_WAIT_READY_RUN"
STALL_MINUTES=120
# shellcheck disable=SC2016  # GraphQL variables ($owner...) are not shell expansions
readonly READY_QUERY='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){timelineItems(last: 100, itemTypes: [READY_FOR_REVIEW_EVENT]){pageInfo{hasPreviousPage} nodes{... on ReadyForReviewEvent{createdAt}}}}}}'

usage() {
  cat <<'EOF'
usage: ci-head-verdict.sh verdict <pr> [--repo OWNER/REPO]
       ci-head-verdict.sh wait-ready-run <pr> --before-count K [--timeout SEC] [--repo OWNER/REPO]
       ci-head-verdict.sh ready-count <pr> [--repo OWNER/REPO]

verdict: last stdout line
  SOLEUR_CI_HEAD_VERDICT state=<n/a|full-decided|pending-full|no-run|stalled|awaiting-approval> pr=<N> sha=<H> run=<id|none> reason=<token>
  (exit 3: state=error, outside that set)
wait-ready-run: last stdout line
  SOLEUR_CI_WAIT_READY_RUN result=<ok|fail> pr=<N> sha=<H|unknown> run=<id|none> reason=<run-created|not-applicable|no-ready-event|no-run|awaiting-approval|api-error>
exit 0 ok | 1 wait failed (do NOT arm auto-merge) | 2 usage | 3 gh/jq/API error (ready state unknown: re-run verdict)
arm order: K=$(ready-count PR) && gh pr ready PR && wait-ready-run PR --before-count "$K"; arm only on exit 0
EOF
}

usage_error() { echo "ci-head-verdict: $1" >&2; usage >&2; exit 2; }

# ── args ──────────────────────────────────────────────────────────────────────────────────────
if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then usage; exit 0; fi
CMD="${1-}"
case "$CMD" in verdict|wait-ready-run|ready-count) shift ;; *) usage_error "unknown or missing subcommand '${CMD}'" ;; esac
PR="${1-}"
[[ "$PR" =~ ^[0-9]+$ ]] || usage_error "<pr> must be a number"
shift
BEFORE=""; TIMEOUT=300
while (( $# > 0 )); do
  case "$1" in
    --repo)
      [[ "${2-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+$ ]] || usage_error "--repo must be OWNER/REPO (not a URL)"
      export GH_REPO="$2"; shift 2 ;;
    --before-count)
      [[ "$CMD" == wait-ready-run && "${2-}" =~ ^[0-9]+$ ]] || usage_error "--before-count K (an integer) is for wait-ready-run only"
      BEFORE=$((10#$2)); shift 2 ;;
    --timeout)
      # shellcheck disable=SC2015  # A && B || usage_error is the guard idiom here
      [[ "$CMD" == wait-ready-run && "${2-}" =~ ^[0-9]+$ ]] && (( 10#$2 > 0 )) || usage_error "--timeout takes a positive integer and is for wait-ready-run only"
      TIMEOUT=$((10#$2)); shift 2 ;;
    *) usage_error "unknown argument '$1'" ;;
  esac
done
[[ "$CMD" != wait-ready-run || -n "$BEFORE" ]] || usage_error "wait-ready-run needs --before-count K (read it with ready-count BEFORE gh pr ready)"
POLL_SECONDS="${CI_HEAD_VERDICT_POLL_SECONDS:-10}"
[[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || usage_error "CI_HEAD_VERDICT_POLL_SECONDS must be ^[0-9]+\$"

SHA_OUT="unknown"
# fail_api <message> [reason]: a read the resolver could not make. `verdict` prints a marker whose state is `error` (NOT a
# member of the closed set: a reader that whitelists the six states then keeps its own reading, so a real red `test`
# is never softened by an API hiccup) and exits 3; ready-count prints no number.
fail_api() {
  local reason="${2:-api-error}"
  echo "ci-head-verdict: $1" >&2
  if [[ "$CMD" == verdict ]]; then
    printf '%s state=error pr=%s sha=%s run=none reason=%s\n' "$MARKER" "$PR" "$SHA_OUT" "$reason"
  fi
  exit 3
}

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || fail_api "$bin not found on PATH" missing-tool
done
WORK="$(mktemp -d)" || fail_api "mktemp failed" mktemp
trap 'rm -rf "$WORK"' EXIT

ERRMSG=""
# ── reads. Each returns 0 on a parsed answer, 1 with ERRMSG set otherwise. ─────────────────────
PR_DRAFT=""; PR_SHA=""; SERVER_DATE=""
read_pr() {
  gh api -i "repos/{owner}/{repo}/pulls/$PR" > "$WORK/pr.http" 2> "$WORK/err" \
    || { ERRMSG="reading PR $PR failed: $(head -c 200 "$WORK/err" | tr '\n' ' ')"; return 1; }
  awk 'b { print; next } /^\r?$/ { b = 1 }' "$WORK/pr.http" > "$WORK/pr.json"
  SERVER_DATE="$(awk 'b { exit } /^\r?$/ { b = 1; next } tolower($0) ~ /^date:/ { sub(/^[Dd][Aa][Tt][Ee]:[ \t]*/, ""); sub(/\r$/, ""); print; exit }' "$WORK/pr.http")"
  jq -e 'type == "object" and (.draft | type) == "boolean" and (.head.sha | type) == "string" and (.head.sha | test("^[0-9a-f]{40}$"))' \
    "$WORK/pr.json" >/dev/null 2>&1 || { ERRMSG="unparseable PR $PR body"; return 1; }
  PR_DRAFT="$(jq -r '.draft' "$WORK/pr.json")"
  PR_SHA="$(jq -r '.head.sha' "$WORK/pr.json")"
}

READY_COUNT=0; READY_T=""; READY_TRUNC="false"
read_ready() {
  gh api graphql -F owner='{owner}' -F name='{repo}' -F number="$PR" -f query="$READY_QUERY" > "$WORK/ready.json" 2> "$WORK/err" \
    || { ERRMSG="reading the ready-event timeline of PR $PR failed: $(head -c 200 "$WORK/err" | tr '\n' ' ')"; return 1; }
  jq -e '.data.repository.pullRequest.timelineItems
         | (.nodes | type) == "array" and all(.nodes[]; (.createdAt | type) == "string") and (.pageInfo.hasPreviousPage | type) == "boolean"' \
    "$WORK/ready.json" >/dev/null 2>&1 || { ERRMSG="unparseable ready-event timeline for PR $PR"; return 1; }
  READY_COUNT="$(jq -r '.data.repository.pullRequest.timelineItems.nodes | length' "$WORK/ready.json")"
  READY_T="$(jq -r '.data.repository.pullRequest.timelineItems.nodes | last | .createdAt // ""' "$WORK/ready.json")"
  READY_TRUNC="$(jq -r '.data.repository.pullRequest.timelineItems.pageInfo.hasPreviousPage' "$WORK/ready.json")"
}

# The newest `test` check run (github-actions app) at <sha>: TEST_STATUS / TEST_CONCLUSION / TEST_RUN (id or "").
TEST_STATUS=""; TEST_CONCLUSION=""; TEST_RUN=""
read_test_row() {
  gh api --paginate --slurp "repos/{owner}/{repo}/commits/$1/check-runs?check_name=test&per_page=100&filter=all" > "$WORK/checks.json" 2> "$WORK/err" \
    || { ERRMSG="reading check runs at $1 failed: $(head -c 200 "$WORK/err" | tr '\n' ' ')"; return 1; }
  jq -e 'type == "array" and all(.[]; type == "object" and (.check_runs | type) == "array")' "$WORK/checks.json" >/dev/null 2>&1 \
    || { ERRMSG="unparseable check-runs response at $1"; return 1; }
  jq -c --arg h "$1" '[.[].check_runs[] | select(.name == "test" and .app.id == 15368 and .head_sha == $h)]
                      | if length == 0 then null else max_by(.id | tonumber) end' "$WORK/checks.json" > "$WORK/testrow.json" \
    || { ERRMSG="unparseable check-runs response at $1"; return 1; }
  TEST_STATUS="$(jq -r '.status // ""' "$WORK/testrow.json")"
  TEST_CONCLUSION="$(jq -r '.conclusion // ""' "$WORK/testrow.json")"
  TEST_RUN="$(jq -r '(.details_url // "") | capture("/actions/runs/(?<id>[0-9]+)(/|$)") | .id' "$WORK/testrow.json" 2>/dev/null || true)"
}

# The newest ci.yml pull_request run at <sha> created at or after <floor-epoch>: RUN_ID / RUN_STATUS / RUN_CONCLUSION
# (RUN_ID empty when none). Looked up by head_sha, never through a run's pull_requests[].
RUN_ID=""; RUN_STATUS=""; RUN_CONCLUSION=""
read_newest_run() { # <sha> <floor-epoch>
  gh api --paginate --slurp "repos/{owner}/{repo}/actions/workflows/ci.yml/runs?event=pull_request&head_sha=$1&per_page=100" > "$WORK/runs.json" 2> "$WORK/err" \
    || { ERRMSG="listing ci.yml runs at $1 failed: $(head -c 200 "$WORK/err" | tr '\n' ' ')"; return 1; }
  jq -e 'type == "array" and all(.[]; type == "object" and (.workflow_runs | type) == "array")' "$WORK/runs.json" >/dev/null 2>&1 \
    || { ERRMSG="unparseable ci.yml run list at $1"; return 1; }
  jq -c --arg h "$1" --argjson floor "$2" '
      [ .[] | .workflow_runs[]? | select(.head_sha == $h and .event == "pull_request")
        | . + {ts: (.created_at | fromdateiso8601)} | select(.ts >= $floor) ]
      | sort_by([.ts, .id]) | last // null' "$WORK/runs.json" > "$WORK/newest.json" \
    || { ERRMSG="unparseable ci.yml run list at $1"; return 1; }
  RUN_ID="$(jq -r '(.id // "") | tostring' "$WORK/newest.json")"
  [[ -z "$RUN_ID" || "$RUN_ID" =~ ^[0-9]+$ ]] || { ERRMSG="non-numeric run id in the ci.yml run list at $1"; return 1; }
  RUN_STATUS="$(jq -r '.status // ""' "$WORK/newest.json")"
  RUN_CONCLUSION="$(jq -r '.conclusion // ""' "$WORK/newest.json")"
}

# Does this repo carry the mechanism? True when the DEFAULT branch's ci.yml has a `draft-light` job. APPLICABLE is
# 1/0; a 404 (no ci.yml) is 0, any other failure is an error (ERRMSG set, return 1).
APPLICABLE=""
read_applicable() {
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/{owner}/{repo}/contents/.github/workflows/ci.yml" > "$WORK/ci.yml" 2> "$WORK/err" || {
    if grep -qE 'HTTP 404|Not Found' "$WORK/err"; then APPLICABLE=0; return 0; fi
    ERRMSG="reading the default branch's ci.yml failed: $(head -c 200 "$WORK/err" | tr '\n' ' ')"; return 1
  }
  [[ -s "$WORK/ci.yml" ]] || { ERRMSG="empty ci.yml body"; return 1; }
  if grep -qE '^  draft-light:[[:space:]]*$' "$WORK/ci.yml"; then APPLICABLE=1; else APPLICABLE=0; fi
}

# <status> <conclusion> -> "<state> <reason>" (the closed mapping of rule 4)
classify_run() {
  case "$1" in
    completed) : ;;
    queued|in_progress|waiting|requested|pending) echo "pending-full run-in-progress"; return 0 ;;
    *) echo "no-run run-unknown-status"; return 0 ;;
  esac
  case "$2" in
    success)   echo "full-decided run-success" ;;
    failure)   echo "full-decided run-failure" ;;
    timed_out) echo "full-decided run-timed-out" ;;
    action_required) echo "awaiting-approval run-action-required" ;;
    cancelled|skipped|stale|neutral|startup_failure) echo "no-run run-${2//_/-}" ;;
    *) echo "no-run run-unknown-conclusion" ;;
  esac
}

# Epoch seconds from an ISO-8601 UTC time (2031-03-04T05:06:07Z) or an HTTP Date header (RFC 1123), via jq so the
# script runs without GNU `date -d`. Prints digits and returns 0, or returns 1.
epoch_of() {
  local out
  out="$(jq -rn --arg s "$1" 'if ($s | test("^[A-Za-z]{3}, ")) then ($s | strptime("%a, %d %b %Y %H:%M:%S GMT") | mktime) else ($s | fromdateiso8601) end' 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$out"
}

NOW_EPOCH=0
server_now() {
  local raw="${CI_HEAD_VERDICT_NOW:-$SERVER_DATE}"
  [[ -n "$raw" ]] || return 1
  epoch_of "$raw"
}

emit() { # <state> <run|""> <reason>
  printf '%s state=%s pr=%s sha=%s run=%s reason=%s\n' "$MARKER" "$1" "$PR" "$SHA_OUT" "${2:-none}" "$3"
  exit 0
}

# ── verdict ───────────────────────────────────────────────────────────────────────────────────
cmd_verdict() {
  local t_epoch st rs
  read_pr || fail_api "$ERRMSG"
  SHA_OUT="$PR_SHA"
  NOW_EPOCH=$(server_now) || fail_api "no usable server time (Date header absent or unparseable)" no-server-time
  read_ready || fail_api "$ERRMSG"
  (( READY_COUNT > 0 )) || emit n/a "" never-ready
  [[ "$PR_DRAFT" == true ]] && emit n/a "" draft
  read_applicable || fail_api "$ERRMSG"
  [[ "$APPLICABLE" == 1 ]] || emit n/a "" no-draft-light
  t_epoch=$(epoch_of "$READY_T") || fail_api "unparseable ready-event time '$READY_T'"

  read_test_row "$PR_SHA" || fail_api "$ERRMSG"
  if [[ "$TEST_STATUS" == completed && "$TEST_CONCLUSION" == success ]]; then
    emit full-decided "$TEST_RUN" green-test
  fi

  read_newest_run "$PR_SHA" "$t_epoch" || fail_api "$ERRMSG"
  if [[ -z "$RUN_ID" ]]; then
    st="no-run"; rs="no-run-after-ready"
  else
    read -r st rs <<<"$(classify_run "$RUN_STATUS" "$RUN_CONCLUSION")" || fail_api "run classification failed"
    [[ -n "$st" ]] || fail_api "run classification failed"
  fi
  if [[ "$st" == pending-full || "$st" == no-run ]] && (( NOW_EPOCH - t_epoch > STALL_MINUTES * 60 )); then
    st=stalled; rs="undecided-after-${STALL_MINUTES}m"
  fi
  emit "$st" "$RUN_ID" "$rs"
}

# ── ready-count ───────────────────────────────────────────────────────────────────────────────
cmd_ready_count() {
  read_ready || fail_api "$ERRMSG"
  [[ "$READY_TRUNC" != true ]] || fail_api "more ReadyForReviewEvents than one timeline page holds; cannot count" too-many-events
  printf '%s\n' "$READY_COUNT"
}

# ── wait-ready-run ────────────────────────────────────────────────────────────────────────────
WAIT_REASON="no-ready-event"; WAIT_RUN=""; WAIT_SHA="unknown"; WAIT_API_ERR=0
# One poll. 0 = a ready run exists; 1 = keep waiting (WAIT_REASON says what is missing; WAIT_API_ERR=1 when a READ
# failed, which is not the same as "not there yet"); 2 = terminal failure.
wait_once() {
  local t_epoch st rs
  WAIT_REASON="no-ready-event"; WAIT_RUN=""; WAIT_API_ERR=1
  read_pr || { echo "ci-head-verdict: $ERRMSG" >&2; return 1; }
  WAIT_SHA="$PR_SHA"
  read_ready || { echo "ci-head-verdict: $ERRMSG" >&2; return 1; }
  [[ "$READY_TRUNC" != true ]] || { echo "ci-head-verdict: too many ready events to count" >&2; return 1; }
  WAIT_API_ERR=0
  if [[ "$READY_COUNT" -gt "$BEFORE" && "$PR_DRAFT" == false ]]; then
    :
  else
    return 1
  fi
  t_epoch=$(epoch_of "$READY_T") || { echo "ci-head-verdict: unparseable ready-event time '$READY_T'" >&2; WAIT_API_ERR=1; return 1; }
  WAIT_REASON="no-run"
  read_newest_run "$PR_SHA" "$t_epoch" || { echo "ci-head-verdict: $ERRMSG" >&2; WAIT_API_ERR=1; return 1; }
  [[ -n "$RUN_ID" ]] || return 1
  WAIT_RUN="$RUN_ID"
  read -r st rs <<<"$(classify_run "$RUN_STATUS" "$RUN_CONCLUSION")"
  case "$st" in
    pending-full|full-decided) WAIT_REASON="run-created"; return 0 ;;
    awaiting-approval) WAIT_REASON="awaiting-approval"; return 2 ;;
    *) return 1 ;;
  esac
}

wait_marker() { # <ok|fail>
  printf '%s result=%s pr=%s sha=%s run=%s reason=%s\n' "$WAIT_MARKER" "$1" "$PR" "$WAIT_SHA" "${WAIT_RUN:-none}" "$WAIT_REASON"
}

cmd_wait() {
  local max=$(( (TIMEOUT + 9) / 10 )) poll rc prev=""
  (( max >= 1 )) || max=1
  # A repo without the mechanism has no ready run to wait for: arming is today's behaviour there.
  if ! read_applicable; then echo "ci-head-verdict: $ERRMSG" >&2; WAIT_REASON="api-error"; wait_marker fail; exit 3; fi
  if [[ "$APPLICABLE" != 1 ]]; then WAIT_REASON="not-applicable"; wait_marker ok; exit 0; fi
  for (( poll = 1; poll <= max; poll++ )); do
    wait_once; rc=$?
    case "$rc" in
      0) wait_marker ok; exit 0 ;;
      2) wait_marker fail; exit 1 ;;
    esac
    if [[ "$WAIT_REASON" != "$prev" ]]; then
      printf 'WAIT poll=%d/%d waiting-for=%s\n' "$poll" "$max" "$WAIT_REASON"
      prev="$WAIT_REASON"
    fi
    (( poll < max )) && sleep "$POLL_SECONDS"
  done
  # The last poll could not READ: the ready state is unknown, which is not "no ready event / no run".
  if (( WAIT_API_ERR == 1 )); then WAIT_REASON="api-error"; wait_marker fail; exit 3; fi
  wait_marker fail
  exit 1
}

case "$CMD" in
  verdict)        cmd_verdict ;;
  ready-count)    cmd_ready_count ;;
  wait-ready-run) cmd_wait ;;
esac
