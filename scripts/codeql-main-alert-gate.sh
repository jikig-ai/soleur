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
#   DISMISS_ALLOWLIST  comma-separated logins whose dismissals are trusted (default: deruelle)
#   POLL_INTERVAL      seconds between polls (default 30)
#   MAX_POLLS          total polls across both waits (default 50 = 25 minutes at 30 seconds)
#   GITHUB_RUN_ID     optional; linked from the degraded issue when numeric
#
# EXIT: 0 green; 1 RED (filed an issue, or degraded, or any error); 2 input rejected (no API call).

set -euo pipefail

GH_REPO="${GH_REPO:?GH_REPO must be set to owner/repo}"
SHA="${SHA-}"
DRY_RUN="${DRY_RUN-false}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
MAX_POLLS="${MAX_POLLS:-50}"
DISMISS_ALLOWLIST="${DISMISS_ALLOWLIST:-deruelle}"
GITHUB_RUN_ID="${GITHUB_RUN_ID-}"

TRACKER_PREFIX='sec: CodeQL alert #'
DEGRADED_TITLE='codeql-gate-degraded'
LABELS_P1=(--label type/security --label priority/p1-high --label action-required)
LABELS_P2=(--label type/security --label priority/p2-medium --label action-required)

# Messages passed here are fixed text or validated integers, never alert-controlled text.
annotate_error() { printf '::error title=codeql-main-alert-gate::%s\n' "$1" >&2; }
reject_input() { annotate_error "input rejected: $1"; exit 2; }

# ---- input validation: before any API call, before any temp file ------------------------------
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || reject_input "GH_REPO is not owner/repo"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || reject_input "SHA is not 40 lowercase hex characters"
[[ "$DRY_RUN" == "true" || "$DRY_RUN" == "false" ]] || reject_input "DRY_RUN is not true or false"
[[ "$POLL_INTERVAL" =~ ^[0-9]{1,4}$ ]] || reject_input "POLL_INTERVAL is not a small integer"
[[ "$MAX_POLLS" =~ ^[1-9][0-9]{0,3}$ ]] || reject_input "MAX_POLLS is not a positive integer"
[[ "$DISMISS_ALLOWLIST" =~ ^[A-Za-z0-9-]+(,[A-Za-z0-9-]+)*$ ]] || reject_input "DISMISS_ALLOWLIST is not a comma-separated login list"
[[ -z "$GITHUB_RUN_ID" || "$GITHUB_RUN_ID" =~ ^[0-9]{1,20}$ ]] || GITHUB_RUN_ID=""

WORK="$(mktemp -d)" || { annotate_error "mktemp failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

REPO_URL="https://github.com/${GH_REPO}"
FILED=0
REVIEW_FILED=0
POLLS=0
DEGRADING=0

# sanitize <text>: keep a conservative character set, one line, at most 200 characters.
sanitize() {
  local s=""
  s="$(printf '%s' "${1-}" | tr -cd 'A-Za-z0-9 ._/:=,#-')" || s=""
  printf '%s' "${s:0:200}"
}

# list_issues <open|closed> <outfile>: bot-authored type/security issues, bounded by --limit.
list_issues() {
  local state="$1" out="$2" rc=0
  local args=(--label type/security --author app/github-actions --state "$state" --limit 200 --json 'number,title')
  if [[ "$state" == "closed" ]]; then args+=(--search "dismissed in:title"); fi
  timeout 60 gh issue list "${args[@]}" >"$out" 2>"$WORK/err" || rc=$?
  return "$rc"
}

# upsert_degraded <reason-code>: create or comment on the single codeql-gate-degraded issue.
upsert_degraded() {
  local code="$1" rc=0 existing="" body="$WORK/degraded-body.md"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN: would upsert the ${DEGRADED_TITLE} issue (${code})"
    return 0
  fi
  list_issues open "$WORK/degraded-open.json" || return 1
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
  timeout 60 gh api --paginate "$endpoint" >"$out" 2>"$WORK/err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    detail="$(sanitize "$(head -c 300 "$WORK/err" 2>/dev/null)")"
    degrade "api-error" "API request for ${label} failed (rc=${rc}) ${detail}"
  fi
}

# POLLS counts fetches across BOTH waits (one shared budget); the cap is spent when MAX_POLLS fetches are done.
cap_spent() { [[ "$POLLS" -ge "$MAX_POLLS" ]]; }
pause() { sleep "$POLL_INTERVAL"; }

# ---- phase 1: wait for every Analyze (*) check-run of the commit ------------------------------
echo "waiting for the Analyze (*) check-runs of ${SHA}"
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
  if cap_spent; then
    if [[ "$n_runs" -eq 0 ]]; then
      degrade "no-analyze-check-runs" "no Analyze check-runs appeared for the commit within the cap"
    fi
    degrade "analyze-timeout" "an Analyze check-run was still running at the cap"
  fi
  pause
done

# ---- phase 2: the analyses must be ingested (count non-zero and unchanged across two polls) ----
prev=""
while true; do
  POLLS=$((POLLS + 1))
  fetch_pages "analyses" "$WORK/analyses.json" "repos/${GH_REPO}/code-scanning/analyses?ref=refs/heads/main&sha=${SHA}&per_page=100"
  jrc=0
  jq -r -s 'if all(.[]; type == "array") then (add // []) | length else error("unexpected analyses shape") end' \
    "$WORK/analyses.json" >"$WORK/analyses.count" 2>"$WORK/err" || jrc=$?
  [[ "$jrc" -eq 0 ]] || degrade "parse-error" "the analyses response could not be parsed"
  read -r count <"$WORK/analyses.count" || degrade "parse-error" "the analyses count was empty"
  if [[ "$count" -gt 0 && "$count" == "$prev" ]]; then break; fi
  prev="$count"
  if cap_spent; then degrade "analyses-unsettled" "the analyses count did not settle within the cap"; fi
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

# ---- phase 4: dismissed critical/high alerts by a login outside the allow-list ----------------
fetch_pages "dismissed alerts" "$WORK/alerts-dismissed.json" "repos/${GH_REPO}/code-scanning/alerts?state=dismissed&ref=refs/heads/main&per_page=100"
allow_json=""
allow_json="$(printf '%s' "$DISMISS_ALLOWLIST" | jq -R -c 'split(",") | map(ascii_downcase)')" || degrade "parse-error" "the allow-list could not be encoded"
jrc=0
jq -r -s --argjson allow "$allow_json" '
  if all(.[]; type == "array") then
    (add // [])
    | map(select(
        ((.state // "dismissed") == "dismissed")
        and ((.rule.security_severity_level // "" | tostring | ascii_downcase) as $s | $s == "critical" or $s == "high")
        and ((.most_recent_instance.ref // "refs/heads/main") == "refs/heads/main")
        and ((.number | type) == "number") and (.number > 0) and (.number == (.number | floor))
        and (((.dismissed_by.login // "") | tostring | ascii_downcase) as $l | any($allow[]; . == $l) | not)))
    | map({number: .number, sev: (.rule.security_severity_level | tostring | ascii_downcase)})
    | unique_by(.number) | .[] | "\(.number)\t\(.sev)"
  else error("unexpected dismissed-alerts shape") end
' "$WORK/alerts-dismissed.json" >"$WORK/review.tsv" 2>"$WORK/err" || jrc=$?
[[ "$jrc" -eq 0 ]] || degrade "parse-error" "the dismissed alerts response could not be parsed"

mapfile -t CANDIDATES <"$WORK/candidates.tsv"
mapfile -t REVIEWS <"$WORK/review.tsv"
echo "open critical/high candidates: ${#CANDIDATES[@]}; dismissed outside the allow-list: ${#REVIEWS[@]}"

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
  list_issues open "$WORK/issues-open.json" || degrade "api-error" "listing the open tracking issues failed"
  jq -e 'type == "array"' "$WORK/issues-open.json" >/dev/null 2>&1 || degrade "parse-error" "the tracking issue list could not be parsed"
  if [[ "$(jq 'length' "$WORK/issues-open.json")" -ge 200 ]]; then
    echo "::warning title=codeql-main-alert-gate::the open tracking-issue list reached its 200 row bound; a duplicate issue is possible"
  fi
  for row in "${CANDIDATES[@]}"; do
    IFS=$'\t' read -r num sev rule <<<"$row"
    hits=""
    hits="$(jq -r --arg p "${TRACKER_PREFIX}${num}" --arg d " dismissed — review" '
      [.[] | .title | select(type == "string") | select(startswith($p))
       | .[($p | length):] | select((test("\\A[0-9]") | not) and (startswith($d) | not))] | length' "$WORK/issues-open.json")" \
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

if [[ "${#REVIEWS[@]}" -gt 0 ]]; then
  list_issues open "$WORK/review-open.json" || degrade "api-error" "listing the open tracking issues failed"
  list_issues closed "$WORK/review-closed.json" || degrade "api-error" "listing the closed review issues failed"
  for row in "${REVIEWS[@]}"; do
    IFS=$'\t' read -r num sev <<<"$row"
    title="${TRACKER_PREFIX}${num} dismissed — review"
    hits=""
    hits="$(jq -r -s --arg t "$title" '[.[] | .[] | select(.title == $t)] | length' "$WORK/review-open.json" "$WORK/review-closed.json")" \
      || degrade "parse-error" "the review issue lists could not be searched"
    if [[ "$hits" -gt 0 ]]; then
      echo "dismissal of alert #${num} was already reviewed"
      continue
    fi
    body="$WORK/review-body-${num}.md"
    {
      printf 'CodeQL alert #%s (severity: %s) was dismissed by an account outside the allow-list. Review the dismissal.\n\n' "$num" "$sev"
      printf 'Alert: %s/security/code-scanning/%s\n\n' "$REPO_URL" "$num"
      printf 'Filed by codeql-main-alert-gate (scripts/codeql-main-alert-gate.sh).\n'
    } >"$body"
    file_issue "$title" "$body" "${LABELS_P1[@]}"
    FILED=$((FILED + 1))
    REVIEW_FILED=$((REVIEW_FILED + 1))
  done
fi

printf 'codeql-main-alert-gate: candidates=%d tracked=%d filed=%d review=%d dry_run=%s\n' \
  "${#CANDIDATES[@]}" "$TRACKED" "$FILED" "$REVIEW_FILED" "$DRY_RUN"
if [[ "$FILED" -gt 0 ]]; then
  annotate_error "RED: ${FILED} critical/high CodeQL finding(s) had no tracking issue; see the type/security issues labelled action-required"
  echo "codeql-main-alert-gate: verdict=RED"
  exit 1
fi
echo "codeql-main-alert-gate: verdict=GREEN"
exit 0
