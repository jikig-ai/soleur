#!/usr/bin/env bash
# check-red-on-main.sh "<check-name>" --run-id <failing-run-id> [--report] [--repo owner/repo]
# check-red-on-main.sh --self-test
# check-red-on-main.sh --help
#
# WHY THIS EXISTS (#9402). A PR whose check is red because MAIN is red pays rerun cycles and
# autonomous-fix attempts for a failure it did not cause -- PR #9339 paid three reruns of
# `deploy-script-tests (1/4)` while that leg was red on main. "Confirmed pre-existing" was an
# agent judgment call with no mechanical probe; this script is the probe. It answers one
# question: did the newest completed main-branch run of the SAME workflow that exercised a job
# of the EXACT same name conclude it non-green?
#
# HOW IT DECIDES.
#   * The failing check's workflow is resolved through the run it failed in:
#     `gh api repos/{o}/{r}/actions/runs/<run-id>` -> .workflow_id. `gh pr checks`' `link` field
#     already carries `actions/runs/<run-id>`.
#   * Up to 5 completed main-branch runs of that workflow are listed, newest first
#     (`actions/workflows/<id>/runs?branch=main&status=completed&per_page=5`).
#   * In each run the job named EXACTLY <check-name> is looked up. Matrix suffixes like `(1/4)`
#     are part of the name -- the parent `deploy-script-tests` never answers for the leg, and a
#     prefix match would read a green parent as a green leg.
#   * skipped/absent jobs are NOT evidence: a path-filtered main push that never ran the job
#     says nothing, so the scan continues to older runs in the window.
#   * The FIRST run where the job reached a real conclusion decides:
#       red-on-main   -- conclusion in {failure, timed_out, cancelled}
#       green-on-main -- conclusion in {success, neutral}
#       no-evidence   -- no run in the window exercised the job -> NOT quarantined
#     `cancelled` is red by the same `!= 'success'` convention notify-main-failure uses; any
#     other conclusion (skipped, stale, action_required, still-running) is not evidence.
#
# EXIT CODES (the contract every caller branches on).
#   0  green-on-main   the check is healthy on main -- this PR's red is its own
#   1  red-on-main     same-named job is red on the newest exercising main run -> quarantine
#   2  no-evidence     no main run in the window exercised the job -> NOT quarantined
#   3  error           usage error, gh/jq missing, API failure, unparseable body.
#                      ERRORS NEVER QUARANTINE -- an unproven claim is worse than a rerun.
#
# Every invocation prints exactly one stdout marker as its LAST stdout line:
#   SOLEUR_RED_ON_MAIN verdict=<v> check="<name>" main_run=<id|none> main_conclusion=<c|none>
# with ` reason=<api|parse|missing-tool|usage>` appended on the error path. All diagnostics go
# to stderr so the marker is the only stdout line.
#
# --report (the only write path; dedupe is sentinel-keyed, mirroring main-health-monitor):
#   * red-on-main: list open `ci/main-broken` issues, find those carrying
#     `<!-- soleur:red-on-main check="<name>" -->` (oldest first), comment on the oldest; if
#     none, `gh label create ci/main-broken --force 2>/dev/null || true` then file with
#     --milestone "Post-MVP / Later" --label ci/main-broken --label meta/machinery --label
#     type/chore. A LIST FAILURE warns and files NOTHING -- never a duplicate on a transient
#     error (#1357 lesson: the rate-limit response is this query's own failure condition).
#   * green-on-main: comment-and-close EVERY open issue carrying OUR sentinel for that exact
#     check name -- never a human-filed tracker, never another check's sentinel (#7374's
#     out-of-scope-green lesson is what the sentinel encodes).
#   * no-evidence/error: no issue operations at all.
#
# `gh api` GET calls embed the query in the URL -- never `-f`/`--raw-field`, which flips the
# request to POST and 404s the actions runs endpoints (measured 2026-09-29, PR #9233). And
# `gh api` has no `--arg` (cli/cli#10263): two-stage `gh api URL | jq --arg` is the only
# sanctioned shape. `gh api` also has no `-R/--repo` flag, so --repo is embedded in the path.
set -uo pipefail

readonly MARKER="SOLEUR_RED_ON_MAIN"

usage() {
  cat <<'EOF'
usage: check-red-on-main.sh "<check-name>" --run-id <failing-run-id> [--report] [--repo owner/repo]
       check-red-on-main.sh --self-test
       check-red-on-main.sh --help

Answers whether the check that failed in run <failing-run-id> is ALSO failing on main: scans up
to 5 completed main-branch runs of the same workflow, newest first, for a job named EXACTLY
<check-name> (matrix suffixes included). Skipped/absent jobs are not evidence.

exit 0 green-on-main | 1 red-on-main (quarantine) | 2 no-evidence (not quarantined) | 3 error

Last stdout line, on every path except --help and --self-test:
  SOLEUR_RED_ON_MAIN verdict=<v> check="<name>" main_run=<id|none> main_conclusion=<c|none> [reason=<r>]

--report files/dedupes a `ci/main-broken` tracker keyed on the sentinel
`<!-- soleur:red-on-main check="<name>" -->` on red, and comments+closes sentinel-owned issues
on green. Errors and no-evidence never file and never close.
EOF
}

CHECK_OUT="-"; MAIN_RUN="none"; MAIN_CONCL="none"; REASON="none"

marker() { # <verdict> ; always the LAST stdout line
  if [[ "$1" == error ]]; then
    printf '%s verdict=error check="%s" main_run=%s main_conclusion=%s reason=%s\n' \
      "$MARKER" "$CHECK_OUT" "$MAIN_RUN" "$MAIN_CONCL" "$REASON"
  else
    printf '%s verdict=%s check="%s" main_run=%s main_conclusion=%s\n' \
      "$MARKER" "$1" "$CHECK_OUT" "$MAIN_RUN" "$MAIN_CONCL"
  fi
}

die3() { # <message> <reason-token>
  printf 'check-red-on-main: ERROR: %s\n' "$1" >&2
  REASON="$2"; marker error; exit 3
}

usage_error() {
  printf 'check-red-on-main: %s\n' "$1" >&2
  usage >&2
  REASON=usage; marker error; exit 3
}

# ── the pure classifier ─────────────────────────────────────────────────────────────────────
# job_verdict <check-name> -- reads ONE OR MORE concatenated jobs-page objects on stdin (the
# `gh api --paginate` output shape) and prints "<red|green|none> <conclusion-or->". `none`
# covers absent, skipped, stale, action_required, and still-running jobs alike: only a real
# conclusion is evidence.
job_verdict() {
  local name="$1" pair
  pair=$(jq -sr --arg n "$name" '
    [ .[] | .jobs[]? | select(.name == $n) ] as $m
    | if ($m | length) == 0 then "ABSENT -"
      else (($m[0].status // "-") + " " + ($m[0].conclusion // "-")) end') \
    || return 3
  case "$pair" in
    "completed failure"|"completed timed_out"|"completed cancelled") echo "red ${pair#* }" ;;
    "completed success"|"completed neutral")                       echo "green ${pair#* }" ;;
    *)                                                             echo "none ${pair#* }" ;;
  esac
}

self_test() {
  command -v jq >/dev/null 2>&1 || { echo "check-red-on-main: jq required for --self-test" >&2; exit 3; }
  local name='deploy-script-tests (1/4)' fails=0
  st() { # <want-verdict> <json-docs...>
    local want="$1"; shift
    local doc got=""
    for doc in "$@"; do got+="$doc"$'\n'; done
    got=$(printf '%s' "$got" | job_verdict "$name") || { echo "  self-test: job_verdict errored" >&2; fails=$((fails + 1)); return; }
    [[ "${got%% *}" == "$want" ]] || { echo "  self-test: want $want, got '$got'" >&2; fails=$((fails + 1)); }
  }
  st red   '{"jobs":[{"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"failure"}]}'
  st red   '{"jobs":[{"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"cancelled"}]}'
  st red   '{"jobs":[{"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"timed_out"}]}'
  st green '{"jobs":[{"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"success"}]}'
  st green '{"jobs":[{"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"neutral"}]}'
  st none  '{"jobs":[{"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"skipped"}]}'
  st none  '{"jobs":[{"name":"deploy-script-tests (1/4)","status":"in_progress","conclusion":null}]}'
  st none  '{"jobs":[{"name":"deploy-script-tests","status":"completed","conclusion":"failure"}]}'
  st none  '{"jobs":[{"name":"lint","status":"completed","conclusion":"failure"}]}'
  # two concatenated page objects (the --paginate output shape) must still find the job
  st red   '{"total_count":41,"jobs":[{"name":"lint","status":"completed","conclusion":"success"}]}' \
           '{"total_count":41,"jobs":[{"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"failure"}]}'
  if (( fails > 0 )); then
    printf 'SOLEUR_RED_ON_MAIN_SELFTEST failed (%s case(s))\n' "$fails" >&2; exit 3
  fi
  echo "SOLEUR_RED_ON_MAIN_SELFTEST ok"
  exit 0
}

# ── args ──────────────────────────────────────────────────────────────────────────────────────
CHECK=""; RUN_ID=""; REPORT=0; REPO=""; SELFTEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test) SELFTEST=1; shift ;;
    --help|-h)   usage; exit 0 ;;
    --run-id)
      [[ "${2-}" =~ ^[0-9]+$ ]] || usage_error "--run-id needs a numeric workflow-run id"
      RUN_ID="$2"; shift 2 ;;
    --report)  REPORT=1; shift ;;
    --repo)
      [[ "${2-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage_error "--repo needs owner/repo"
      REPO="$2"; shift 2 ;;
    -*) usage_error "unknown flag $1" ;;
    *)  [[ -z "$CHECK" ]] || usage_error "unexpected extra argument $1"; CHECK="$1"; shift ;;
  esac
done
(( SELFTEST == 1 )) && self_test
[[ -n "$CHECK" ]] || usage_error "<check-name> is required"
[[ "$CHECK" != *'"'* && "$CHECK" != *'-->'* && "$CHECK" != *$'\n'* && "$CHECK" != *$'\r'* ]] \
  || usage_error "check name cannot carry a double-quote, newline, or '-->' (sentinel/marker safety)"
[[ -n "$RUN_ID" ]] || usage_error "--run-id <failing-run-id> is required"
CHECK_OUT="$CHECK"

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "check-red-on-main: ERROR: $bin not found on PATH" >&2; REASON="missing-tool"; marker error; exit 3; }
done

WORK="$(mktemp -d)" || { echo "check-red-on-main: ERROR: mktemp failed" >&2; REASON=mktemp; marker error; exit 3; }
trap 'rm -rf "$WORK"' EXIT
trap 'REASON=interrupted; marker error; exit 130' INT TERM HUP

# gh api has no -R/--repo flag: --repo is embedded in the endpoint path instead.
if [[ -n "$REPO" ]]; then RP="repos/$REPO"; REPO_ARG=(--repo "$REPO"); else RP="repos/{owner}/{repo}"; REPO_ARG=(); fi

# ── resolve the workflow through the failing run ─────────────────────────────────────────────
gh api "$RP/actions/runs/$RUN_ID" > "$WORK/run.json" 2>"$WORK/gh-err" \
  || die3 "gh api actions/runs/$RUN_ID failed: $(head -c 200 "$WORK/gh-err" | tr '\n' ' ')" api
jq -e 'type == "object" and (.workflow_id | type) == "number"' "$WORK/run.json" >/dev/null 2>&1 \
  || die3 "unparseable actions/runs/$RUN_ID response (no numeric workflow_id)" parse
WFID=$(jq -r '.workflow_id' "$WORK/run.json")

# ── windowed scan of completed main runs, newest first ───────────────────────────────────────
gh api "$RP/actions/workflows/$WFID/runs?branch=main&status=completed&per_page=5" > "$WORK/wfruns.json" 2>"$WORK/gh-err" \
  || die3 "gh api workflows/$WFID/runs failed: $(head -c 200 "$WORK/gh-err" | tr '\n' ' ')" api
jq -e 'type == "object" and (.workflow_runs | type) == "array"' "$WORK/wfruns.json" >/dev/null 2>&1 \
  || die3 "unparseable workflow-runs response" parse
IDS_RAW=$(jq -r '[.workflow_runs[:5][] | .id | select(type == "number")] | .[]' "$WORK/wfruns.json") \
  || die3 "unparseable workflow-runs response" parse

OUTCOME=""
while IFS= read -r rid; do
  [[ -n "$rid" ]] || continue
  gh api --paginate "$RP/actions/runs/$rid/jobs?per_page=100" > "$WORK/jobs.json" 2>"$WORK/gh-err" \
    || die3 "gh api actions/runs/$rid/jobs failed: $(head -c 200 "$WORK/gh-err" | tr '\n' ' ')" api
  jv=$(job_verdict "$CHECK" < "$WORK/jobs.json") \
    || die3 "unparseable jobs response for main run $rid" parse
  case "${jv%% *}" in
    red|green) OUTCOME="${jv%% *}"; MAIN_RUN="$rid"; MAIN_CONCL="${jv#* }"; break ;;
    none) ;;
  esac
done <<<"$IDS_RAW"

case "$OUTCOME" in
  red)   VERDICT=red-on-main;   RC=1 ;;
  green) VERDICT=green-on-main; RC=0 ;;
  *)     VERDICT=no-evidence;   RC=2 ;;
esac

# ── --report: sentinel-keyed issue file/dedupe/close ─────────────────────────────────────────
report() {
  SENTINEL="<!-- soleur:red-on-main check=\"$CHECK\" -->"
  local rc=0 open_json
  # rc captured separately: `|| true` would collapse "no tracker" and "API error" into the same
  # empty string, and the filer would file a duplicate on a transient failure (#1357 lesson).
  open_json=$(gh issue list "${REPO_ARG[@]}" --label "ci/main-broken" --state open \
    --json number,body --limit 100) || rc=$?
  if [[ "$rc" -ne 0 ]] || ! jq -e 'type == "array"' <<<"$open_json" >/dev/null 2>&1; then
    echo "check-red-on-main: could not list ci/main-broken issues (rc=$rc) -- not filing or closing anything, to avoid acting on a transient error" >&2
    return 0
  fi

  if [[ "$VERDICT" == red-on-main ]]; then
    # OLDEST first: gh issue list returns created-DESC, so .[0] unsorted is the NEWEST -- an
    # older tracker would be orphaned and keep the file-new arm unreachable forever.
    local existing
    existing=$(jq -r --arg s "$SENTINEL" \
      '[.[] | select(.body | type == "string" and contains($s)) | .number] | sort | .[0] // empty' \
      <<<"$open_json" 2>/dev/null) || existing=""
    if [[ -n "$existing" ]]; then
      gh issue comment "$existing" "${REPO_ARG[@]}" --body \
        "Still red on main: check \`$CHECK\` concluded $MAIN_CONCL on main run $MAIN_RUN. (probe run: $RUN_ID)" \
        || echo "check-red-on-main: could not comment on #$existing" >&2
      echo "check-red-on-main: commented on existing sentinel tracker #$existing" >&2
      return 0
    fi
    gh label create "ci/main-broken" --force "${REPO_ARG[@]}" >/dev/null 2>&1 || true
    local url
    url=$(gh issue create "${REPO_ARG[@]}" \
      --title "Red on main: $CHECK" \
      --body "$(printf '%s\n' \
        "$SENTINEL" \
        "" \
        "Check \`$CHECK\` is failing on main." \
        "" \
        "- Newest exercising main run: $MAIN_RUN (conclusion: $MAIN_CONCL)" \
        "- Observed failing on PR-side run: $RUN_ID" \
        "" \
        "Filed by check-red-on-main.sh --report: this check is quarantined for PR rerun/fix" \
        "decisions while it is red on main. This tracker is auto-closed when the check goes" \
        "green on main again.")" \
      --label "ci/main-broken" --label "meta/machinery" --label "type/chore" \
      --milestone "Post-MVP / Later" 2>/dev/null) || url=""
    if [[ -n "$url" ]]; then
      echo "check-red-on-main: filed tracker $url" >&2
    else
      echo "check-red-on-main: issue create failed -- the red-on-main verdict stands but no tracker was filed" >&2
    fi
    return 0
  fi

  # green-on-main: comment-and-close ONLY issues carrying OUR sentinel for this check name --
  # every one of them, never a human-filed or other-sentinel tracker.
  local mine n
  mine=$(jq -r --arg s "$SENTINEL" \
    '[.[] | select(.body | type == "string" and contains($s)) | .number] | sort | .[]' \
    <<<"$open_json" 2>/dev/null) || mine=""
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    gh issue close "$n" "${REPO_ARG[@]}" --comment \
      "Check \`$CHECK\` is green on main again (run $MAIN_RUN, conclusion $MAIN_CONCL). Auto-closing." \
      || echo "check-red-on-main: could not close #$n" >&2
    echo "check-red-on-main: closed sentinel tracker #$n -- main is green again" >&2
  done <<<"$mine"
  return 0
}

if (( REPORT == 1 )) && [[ "$VERDICT" == red-on-main || "$VERDICT" == green-on-main ]]; then
  report
fi

marker "$VERDICT"
exit "$RC"
