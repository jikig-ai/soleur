#!/usr/bin/env bash
# codeql-main-alert-gate.sh -- turn the CodeQL result of a commit pushed to main into a loud,
# deduplicated signal (issue #9454; plan 2026-10-03-feat-adopt-merge-queue-advisory-codeql).
#
# WHY. CodeQL is advisory once the merge queue is on (it cannot report a status on merge_group,
# github/codeql-action#1537), so a critical/high alert that lands on main is no longer blocked
# before the merge. This gate runs on the push, AFTER the merge, so it cannot block: it pages.
# Page-and-continue, never auto-revert.
#
# WHAT "NEW" MEANS. An alert is new when no OPEN, bot-authored issue titled with the prefix
# `sec: CodeQL alert #<N>` exists. The tracker is the state: no watermark, no cache. A CLOSED
# tracker is not a dedupe signal for an OPEN alert. The list is bot-scoped (--author) so a public
# stranger cannot poison the dedupe by opening an issue titled for an upcoming alert number, and
# it is a `gh issue list` read (bounded by --limit), never a free-text search.
#
# VERDICT. RED iff this run filed at least one issue, or any error occurred. A re-run on an
# already-tracked alert is green: the issue is the durable page, the red run is the push-time
# signal. Degraded exits (cap hit, no Analyze check-runs, any API error) upsert ONE
# `codeql-gate-degraded` issue so a red run on a queue-made push (no human actor) is not invisible.
#
# ACCEPTING A RISK. Do it by DISMISSING the alert in code scanning. Closing the tracking issue does
# not accept anything: the alert is still open, so the next push to main files a new issue. A
# dismissal removes the alert from the open set this gate reads; the gate does not audit who
# dismissed it (insider dismissal is an accepted residual, ADR-269).
#
# FAIL CLOSED. Every `gh` call is `timeout 60 gh ...` with its exit status read explicitly; there
# is no `|| true` on a data fetch. A fetch error is a RED run, never "no alerts".
#
# NO ALERT-CONTROLLED TEXT. The alert message, rule description and file path are controlled by a
# PR author. Nothing from them reaches an annotation or an issue. Only the alert number (validated
# integer), the rule id (validated against \A[A-Za-z0-9_./-]{1,100}\z, else `invalid-rule-id`),
# the severity (normalised to critical|high) and a URL built from the number are used.
#
# INPUTS (environment only):
#   GH_REPO            owner/repo (required)
#   SHA                the pushed commit, 40 lowercase hex (required)
#   DRY_RUN            true|false (default false): no `gh issue create` / comment; still exits 1
#   POLL_INTERVAL      seconds between polls (default 30)
#   MAX_POLLS          polls of PHASE 1, the Analyze check-runs wait (default 50 = about 25 minutes at 30 seconds)
#   SETTLE_POLLS       polls of PHASE 2, the analyses-settle wait (default 8 = about 4 minutes); its OWN budget, so a
#                      slow phase 1 cannot starve it
#   DEADLINE_SECONDS   wall-clock budget for the whole run (default 1800 = 30 minutes). The workflow job is killed at
#                      40 minutes and a kill never reaches `degrade`, so the script must always finish (and file the
#                      degraded issue) first: 1800 s + one in-flight `timeout 60` call + the degraded upsert (two more
#                      `timeout 60` calls) stays under 40 minutes. The poll counts alone cannot promise that: 58 polls of
#                      30 s sleep plus up to 60 s per slow call is far longer than 40 minutes.
#   GITHUB_RUN_ID     optional; linked from the degraded issue when numeric
#
# The defaults above are production (the workflow sets none of them); the suite pins them.
#
# EXIT: 0 green; 1 RED (filed an issue, or degraded, or any error after the inputs were accepted);
#       2 input rejected (no API call), including an unset or empty GH_REPO.

set -euo pipefail

GH_REPO="${GH_REPO-}"
SHA="${SHA-}"
DRY_RUN="${DRY_RUN-false}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
MAX_POLLS="${MAX_POLLS:-50}"
SETTLE_POLLS="${SETTLE_POLLS:-8}"
DEADLINE_SECONDS="${DEADLINE_SECONDS:-1800}"
GITHUB_RUN_ID="${GITHUB_RUN_ID-}"

TRACKER_PREFIX='sec: CodeQL alert #'
DEGRADED_TITLE='codeql-gate-degraded'
LABELS_P1=(--label type/security --label priority/p1-high --label action-required)
# The degraded issue is a finding about the gate's OWN machinery (ADR-216). type/security stays because
# list_issues (the dedupe read) is scoped to it. action-required is PRESENT: a push made by the merge queue has no
# human actor, so a red run notifies nobody and this labelled issue is the only page; the operator digest harvests
# action-required (and keeps action-required + meta/machinery together). Precedent: scheduled-actions-queue-health.yml.
LABELS_P2=(--label meta/machinery --label type/security --label priority/p2-medium --label action-required)

# Messages passed here are fixed text or validated integers, never alert-controlled text.
annotate_error() { printf '::error title=codeql-main-alert-gate::%s\n' "$1" >&2; }
reject_input() { annotate_error "input rejected: $1"; exit 2; }

# ---- input validation: before any API call, before any temp file ------------------------------
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || reject_input "GH_REPO is not owner/repo"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || reject_input "SHA is not 40 lowercase hex characters"
[[ "$DRY_RUN" == "true" || "$DRY_RUN" == "false" ]] || reject_input "DRY_RUN is not true or false"
[[ "$POLL_INTERVAL" =~ ^[0-9]{1,4}$ ]] || reject_input "POLL_INTERVAL is not a small integer"
[[ "$MAX_POLLS" =~ ^[1-9][0-9]{0,3}$ ]] || reject_input "MAX_POLLS is not a positive integer"
[[ "$SETTLE_POLLS" =~ ^[1-9][0-9]{0,3}$ ]] || reject_input "SETTLE_POLLS is not a positive integer"
[[ "$DEADLINE_SECONDS" =~ ^[1-9][0-9]{0,5}$ ]] || reject_input "DEADLINE_SECONDS is not a positive integer"
[[ -z "$GITHUB_RUN_ID" || "$GITHUB_RUN_ID" =~ ^[0-9]{1,20}$ ]] || GITHUB_RUN_ID=""

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

WORK="$(mktemp -d)" || { annotate_error "mktemp failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

REPO_URL="https://github.com/${GH_REPO}"
FILED=0
POLLS=0
DEGRADING=0
# The wall clock starts here, after input validation. SECONDS is bash's own elapsed-time counter; it is reset so an
# inherited value cannot shorten the budget.
SECONDS=0

# sanitize <text>: keep a conservative character set, one line, at most 200 characters.
sanitize() {
  local s=""
  s="$(printf '%s' "${1-}" | tr -cd 'A-Za-z0-9 ._/:=,#-')" || s=""
  printf '%s' "${s:0:200}"
}

# list_issues <outfile>: OPEN bot-authored type/security issues, bounded by --limit.
list_issues() {
  local out="$1" rc=0
  assert_fixture_dir "$out"; assert_fixture_dir "$WORK"
  timeout 60 gh issue list --label type/security --author app/github-actions --state open --limit 200 --json 'number,title' \
    >"$out" 2>"$WORK/err" || rc=$?
  return "$rc"
}

# upsert_degraded <reason-code>: create or comment on the single codeql-gate-degraded issue.
upsert_degraded() {
  local code="$1" rc=0 existing="" body="$WORK/degraded-body.md"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN: would upsert the ${DEGRADED_TITLE} issue (${code})"
    return 0
  fi
  list_issues "$WORK/degraded-open.json" || return 1
  existing="$(jq -r --arg t "$DEGRADED_TITLE" '[.[] | select(.title == $t)][0].number // empty' "$WORK/degraded-open.json")" || return 1
  {
    printf 'The CodeQL alert gate could not reach a verdict for a push to main.\n\n'
    printf 'Reason code: %s\n' "$code"
    printf 'Commit: %s\n' "$SHA"
    if [[ -n "$GITHUB_RUN_ID" ]]; then printf 'Run: %s/actions/runs/%s\n' "$REPO_URL" "$GITHUB_RUN_ID"; fi
    printf '\nThe daily CodeQL alert sweep remains the backstop. Close this issue once a re-run of the gate is green.\n'
  } >"$body" || return 1
  if [[ -n "$existing" && "$existing" =~ ^[0-9]+$ ]]; then
    timeout 60 gh issue comment "$existing" --body-file "$body" >/dev/null 2>"$WORK/err" || rc=$?
  else
    timeout 60 gh issue create --title "$DEGRADED_TITLE" --body-file "$body" "${LABELS_P2[@]}" >/dev/null 2>"$WORK/err" || rc=$?
  fi
  return "$rc"
}

# degrade <reason-code> <fixed message>: record the degraded issue, then exit RED.
degrade() {
  local code="$1" msg="$2" urc=0
  annotate_error "degraded (${code}): ${msg}"
  if [[ "$DEGRADING" -eq 0 ]]; then
    DEGRADING=1
    upsert_degraded "$code" || urc=$?
    if [[ "$urc" -ne 0 ]]; then annotate_error "could not record the ${DEGRADED_TITLE} issue (rc=${urc})"; fi
  fi
  printf 'codeql-main-alert-gate: verdict=RED degraded=%s\n' "$code"
  exit 1
}

# fetch_pages <label> <outfile> <endpoint>: a paginated read; any failure is a degraded exit.
fetch_pages() {
  local label="$1" out="$2" endpoint="$3" rc=0 detail=""
  assert_fixture_dir "$out"; assert_fixture_dir "$WORK"
  timeout 60 gh api --paginate "$endpoint" >"$out" 2>"$WORK/err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    detail="$(sanitize "$(head -c 300 "$WORK/err" 2>/dev/null)")"
    degrade "api-error" "API request for ${label} failed (rc=${rc}) ${detail}"
  fi
}

# fetch_page <label> <outfile> <endpoint>: ONE page, no pagination; any failure is a degraded exit.
fetch_page() {
  local label="$1" out="$2" endpoint="$3" rc=0 detail=""
  assert_fixture_dir "$out"; assert_fixture_dir "$WORK"
  timeout 60 gh api "$endpoint" >"$out" 2>"$WORK/err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    detail="$(sanitize "$(head -c 300 "$WORK/err" 2>/dev/null)")"
    degrade "api-error" "API request for ${label} failed (rc=${rc}) ${detail}"
  fi
}

# POLLS counts the fetches of the CURRENT phase (reset at each phase start); the cap is spent when <budget> fetches are done.
cap_spent() { [[ "$POLLS" -ge "$1" ]]; }
# out_of_time: another poll (its pause included) would not fit in the wall-clock budget.
out_of_time() { [[ $((SECONDS + POLL_INTERVAL)) -ge "$DEADLINE_SECONDS" ]]; }
pause() { sleep "$POLL_INTERVAL"; }

# ---- phase 1: wait for every Analyze (*) check-run of the commit ------------------------------
echo "waiting for the Analyze (*) check-runs of ${SHA}"
POLLS=0
while true; do
  POLLS=$((POLLS + 1))
  fetch_pages "check-runs" "$WORK/check-runs.json" "repos/${GH_REPO}/commits/${SHA}/check-runs?per_page=100"
  jrc=0
  jq -r -s '
    if all(.[]; type == "object" and ((.check_runs | type) == "array")) then
      [ .[] | .check_runs[] ]
      | map(select((.name | type) == "string" and (.name | startswith("Analyze (")) and .app.slug == "github-actions"))
      | group_by(.name) | map(max_by(.id))
      | "\(length) \(map(select(.status != "completed")) | length) \(map(select(.status == "completed" and .conclusion == "success")) | length)"
    else error("unexpected check-runs shape") end
  ' "$WORK/check-runs.json" >"$WORK/check-runs.sum" 2>"$WORK/err" || jrc=$?
  [[ "$jrc" -eq 0 ]] || degrade "parse-error" "the check-runs response could not be parsed"
  read -r n_runs n_incomplete n_ok <"$WORK/check-runs.sum" || degrade "parse-error" "the check-runs summary was empty"
  if [[ "$n_runs" -gt 0 && "$n_incomplete" -eq 0 ]]; then
    if [[ "$n_ok" -eq "$n_runs" ]]; then break; fi
    degrade "analyze-not-success" "an Analyze check-run completed without success"
  fi
  if cap_spent "$MAX_POLLS"; then
    if [[ "$n_runs" -eq 0 ]]; then
      degrade "no-analyze-check-runs" "no Analyze check-runs appeared for the commit within the cap"
    fi
    degrade "analyze-timeout" "an Analyze check-run was still running at the cap"
  fi
  if out_of_time; then degrade "deadline-exceeded" "the wall-clock deadline passed while waiting for the Analyze check-runs"; fi
  pause
done

# ---- phase 2: THIS commit's analyses must be ingested (count >= 1 and unchanged across two polls) --
# The analyses endpoint IGNORES the sha= filter when ref= is set (measured: the whole main history, 8,926
# analyses over 90 pages, ~30 s), so the history is never paginated. One page (per_page=100, newest
# first) is read and filtered to this commit in jq. A commit older than ~30 pushes (3 analyses per
# push) is not on the page and degrades at the cap; the push-triggered gate always reads a fresh one.
prev=""
POLLS=0
while true; do
  POLLS=$((POLLS + 1))
  fetch_page "analyses" "$WORK/analyses.json" "repos/${GH_REPO}/code-scanning/analyses?ref=refs/heads/main&sort=created&direction=desc&per_page=100"
  jrc=0
  jq -r --arg sha "$SHA" 'if type == "array" then [.[] | select(.commit_sha == $sha)] | length else error("unexpected analyses shape") end' \
    "$WORK/analyses.json" >"$WORK/analyses.count" 2>"$WORK/err" || jrc=$?
  [[ "$jrc" -eq 0 ]] || degrade "parse-error" "the analyses response could not be parsed"
  read -r count <"$WORK/analyses.count" || degrade "parse-error" "the analyses count was empty"
  if [[ "$count" -gt 0 && "$count" == "$prev" ]]; then break; fi
  prev="$count"
  if cap_spent "$SETTLE_POLLS"; then degrade "analyses-unsettled" "this commit's analyses were not ingested and stable within the cap"; fi
  if out_of_time; then degrade "deadline-exceeded" "the wall-clock deadline passed while waiting for the analyses to settle"; fi
  pause
done

# ---- phase 3: open critical/high alerts on refs/heads/main ------------------------------------
fetch_pages "open alerts" "$WORK/alerts-open.json" "repos/${GH_REPO}/code-scanning/alerts?state=open&ref=refs/heads/main&per_page=100"
jrc=0
jq -r -s '
  if all(.[]; type == "array") then
    (add // [])
    | map(select(
        ((.rule.security_severity_level // "" | tostring | ascii_downcase) as $s | $s == "critical" or $s == "high")
        and ((.most_recent_instance.ref // "refs/heads/main") == "refs/heads/main")
        and ((.number | type) == "number") and (.number > 0) and (.number == (.number | floor))))
    | map({number: .number,
           sev: (.rule.security_severity_level | tostring | ascii_downcase),
           rule: ((.rule.id // "") | if (type == "string" and test("\\A[A-Za-z0-9_./-]{1,100}\\z")) then . else "invalid-rule-id" end)})
    | unique_by(.number) | .[] | "\(.number)\t\(.sev)\t\(.rule)"
  else error("unexpected alerts shape") end
' "$WORK/alerts-open.json" >"$WORK/candidates.tsv" 2>"$WORK/err" || jrc=$?
[[ "$jrc" -eq 0 ]] || degrade "parse-error" "the open alerts response could not be parsed"

mapfile -t CANDIDATES <"$WORK/candidates.tsv"
echo "open critical/high candidates: ${#CANDIDATES[@]}"

# file_issue <title> <body-file> <label-args...>: create, or announce it in a dry run.
file_issue() {
  local title="$1" body="$2" rc=0
  shift 2
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN: would file: ${title}"
    return 0
  fi
  timeout 60 gh issue create --title "$title" --body-file "$body" "$@" >/dev/null 2>"$WORK/err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then degrade "issue-create-failed" "creating a tracking issue failed (rc=${rc})"; fi
  echo "filed: ${title}"
}

TRACKED=0
if [[ "${#CANDIDATES[@]}" -gt 0 ]]; then
  list_issues "$WORK/issues-open.json" || degrade "api-error" "listing the open tracking issues failed"
  jq -e 'type == "array"' "$WORK/issues-open.json" >/dev/null 2>&1 || degrade "parse-error" "the tracking issue list could not be parsed"
  if [[ "$(jq 'length' "$WORK/issues-open.json")" -ge 200 ]]; then
    echo "::warning title=codeql-main-alert-gate::the open tracking-issue list reached its 200 row bound; a duplicate issue is possible"
  fi
  for row in "${CANDIDATES[@]}"; do
    IFS=$'\t' read -r num sev rule <<<"$row"
    hits=""
    hits="$(jq -r --arg p "${TRACKER_PREFIX}${num}" '
      [.[] | .title | select(type == "string") | select(startswith($p))
       | .[($p | length):] | select(test("\\A[0-9]") | not)] | length' "$WORK/issues-open.json")" \
      || degrade "parse-error" "the tracking issue list could not be searched"
    if [[ "$hits" -gt 0 ]]; then
      echo "alert #${num} is already tracked"
      TRACKED=$((TRACKED + 1))
      continue
    fi
    body="$WORK/body-${num}.md"
    {
      printf 'CodeQL alert #%s (severity: %s, rule: %s) is open on main and has no tracking issue.\n\n' "$num" "$sev" "$rule"
      printf 'Alert: %s/security/code-scanning/%s\n\n' "$REPO_URL" "$num"
      printf 'Filed by codeql-main-alert-gate (scripts/codeql-main-alert-gate.sh).\n'
    } >"$body"
    file_issue "${TRACKER_PREFIX}${num} — ${rule}" "$body" "${LABELS_P1[@]}"
    FILED=$((FILED + 1))
  done
fi

printf 'codeql-main-alert-gate: candidates=%d tracked=%d filed=%d dry_run=%s\n' \
  "${#CANDIDATES[@]}" "$TRACKED" "$FILED" "$DRY_RUN"
if [[ "$FILED" -gt 0 ]]; then
  annotate_error "RED: ${FILED} critical/high CodeQL finding(s) had no tracking issue; see the type/security issues labelled action-required"
  echo "codeql-main-alert-gate: verdict=RED"
  exit 1
fi
echo "codeql-main-alert-gate: verdict=GREEN"
exit 0
