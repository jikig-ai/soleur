#!/usr/bin/env bash
# apply-delivery-gap.sh -- make a silently cancelled, path-filtered production apply run loud
# (issue #9454 tracker; CTO ruling of 2026-10-22 on #10033 and #8167; plan
# knowledge-base/project/plans/2026-10-23-feat-apply-delivery-gap-follower-plan.md).
#
# WHY. Both apply workflows share ONE concurrency group (the apply group; the R2 state backend has no lock, so that
# group is the sole serializer). A group keeps one pending run, so a second push evicts the first: the evicted run is
# CANCELLED, usually with zero jobs, and nothing pages. The merge queue raises the push rate. This follower runs after
# every completed run of either workflow, reconciles from the Actions API alone and files ONE deduplicated
# `apply-delivery-gap` issue naming each push that never reached production.
#
# DETECTION ONLY. No apply, no dispatch, no state or host read, no secrets. A filed gap is a GREEN run (the issue is
# the page); only a failed or partial read is red, and a blind follower pages a human through a distinct degraded issue.
#
# STATELESS. Every run is a full reconcile of the last WINDOW_DAYS days; nothing is read back from a previous body.
#
# DELIVERED (all legs, same workflow W): a run of W that completed with `success`, on main, created at or after the
# candidate, whose head is the candidate or a git descendant (compare status identical|ahead), AND whose job named
# `apply` concluded `success` (a skipped apply is not delivery: a kill-switched push, a plan-only or other dispatch
# target all end `success` without applying). For the infra workflow the `apply` job must also show its SSH-provisioned
# Terraform step (INFRA_SSH_STEP) as `success`: that job ends green with that stage skipped. A success of the OTHER
# workflow never counts.
#
# OUTPUT HYGIENE. No value from jq reaches echo, printf, an annotation or the issue body unless it passed a validator
# (^[0-9a-f]{40}$, ^[0-9]+$, an ISO timestamp, or membership in a closed enum). Branch names, titles, actors and commit
# messages are never printed; a message is read into a bash variable only for the kill-switch `=~` match.
#
# MODES. `--self-test` (first, before any env validation): three pure checks, prints apply_delivery_gap_self_test=ok.
# `--fixture-dir <abs dir>`: <dir>/bin/gh (a shim) is put first on PATH and `now` is read from <dir>/now; the test-only
# APPLY_DELIVERY_GAP_PAGE_SIZE / APPLY_DELIVERY_GAP_MAX_PAGES overrides are honoured ONLY there. No other input.
#
# ENV: GH_REPO (owner/repo, required), GH_TOKEN (live), TRIGGER_RUN_ID (digits, the run that fired the follower),
#      GITHUB_RUN_ID (digits, linked from issue text).
# EXIT: 0 reconcile complete; 1 any read/write failure (::error::apply_delivery_gap_<reason> is the LAST line);
#       2 rejected input.

set -euo pipefail

# Live volume (2026-10): infra has about 10 runs/day, so 100 runs span about 10.5 days; 10 pages is 1000 runs.
WINDOW_DAYS=7
PAGE_SIZE=100
MAX_PAGES=10
READ_BUDGET=150
WAITING_CAP_MIN=60
ISSUE_LIMIT=500

LABEL='apply-delivery-gap'
DEGRADED_LABEL='apply-delivery-gap-degraded'
TITLE='infra: apply delivery gap - trigger-file change not applied'
DEGRADED_TITLE='infra: apply delivery gap follower degraded'
AGED_MARKER='<!-- apply-delivery-gap:aged-out -->'
RUNBOOK='knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md'
# The infra workflow's `apply` job can end `success` with its SSH-provisioned stage SKIPPED (the bridge or the host was not
# reachable), so for infra a delivery also needs this step (copied verbatim from the workflow; the suite greps the live
# file for it) to have concluded `success`. The deploy-fix workflow has no such skip and requires no step.
INFRA_SSH_STEP='Terraform apply (SSH-provisioned resources, over the bridge)'

# key|workflow file|display name (must equal the workflow `name:`)|kill-switch function|stale cap in minutes
# (cap > the workflow's `apply` job timeout: deploy-fix 90 min + a web-1-swap queue, infra 53 min).
WATCHED=(
  "deploy-fix|apply-deploy-pipeline-fix.yml|Apply deploy-pipeline-fix|ks_deploy_fix|150"
  "infra|apply-web-platform-infra.yml|Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)|ks_infra|120"
)

MODE=live
FIXTURE=""
WORK=""
NOW_EPOCH=0
NOW_ISO=""
READS=0
FAILING=0
FAIL_FIRST=""
API_OUT=""
CLASS=""
declare -A CMP=()
declare -A JOBOK=()

# ---- pure helpers (also exercised by --self-test) --------------------------------------------------------------
# Each regex is the kill-switch line of the SAME workflow's preflight, copied verbatim.
ks_deploy_fix() { [[ "${1-}" =~ (^|$'\n')\[skip-deploy-fix-apply\]($|$'\n') ]]; }
ks_infra() { [[ "${1-}" =~ (^|$'\n')\[skip-web-platform-apply\]($|$'\n') ]]; }
descendant_status() { case "${1-}" in identical|ahead) return 0 ;; *) return 1 ;; esac; }
class_for_total() { if [[ "${1-}" == "0" ]]; then printf 'evicted-before-start'; else printf 'cancelled-mid-run'; fi; }
# jobs_have_apply_success [required step name]: stdin is a jobs response. Fail closed: a required step that is absent
# from steps[] (or whose conclusion is not `success`) means not delivered.
jobs_have_apply_success() {
  jq -e --arg step "${1-}" '(.jobs // []) | any(.name == "apply" and .conclusion == "success"
    and ($step == "" or ((.steps // []) | any(.name == $step and .conclusion == "success"))))' >/dev/null
}

self_test() {
  local bad=0 nl=$'\n' j
  ks_deploy_fix "a${nl}[skip-deploy-fix-apply]${nl}b" || bad=1
  ks_deploy_fix "[skip-deploy-fix-apply]" || bad=1
  ks_deploy_fix "x [skip-deploy-fix-apply] y" && bad=1
  ks_deploy_fix "[skip-deploy-fix-apply]"$'\r'"${nl}x" && bad=1
  ks_deploy_fix "[skip-web-platform-apply]" && bad=1
  ks_infra "a${nl}[skip-web-platform-apply]${nl}b" || bad=1
  ks_infra "x [skip-web-platform-apply]" && bad=1
  ks_infra "[skip-deploy-fix-apply]" && bad=1
  descendant_status identical || bad=1
  descendant_status ahead || bad=1
  descendant_status behind && bad=1
  descendant_status diverged && bad=1
  [[ "$(class_for_total 0)" == "evicted-before-start" ]] || bad=1
  [[ "$(class_for_total 3)" == "cancelled-mid-run" ]] || bad=1
  j='{"jobs":[{"name":"preflight","conclusion":"success"},{"name":"apply","conclusion":"success"}]}'
  printf '%s' "$j" | jobs_have_apply_success || bad=1
  j='{"jobs":[{"name":"apply","conclusion":"skipped"},{"name":"notify-apply-failure","conclusion":"success"}]}'
  printf '%s' "$j" | jobs_have_apply_success && bad=1
  j='{"jobs":[{"name":"apply","conclusion":"success","steps":[{"name":"'"$INFRA_SSH_STEP"'","conclusion":"success"}]}]}'
  printf '%s' "$j" | jobs_have_apply_success "$INFRA_SSH_STEP" || bad=1
  printf '%s' "$j" | jobs_have_apply_success || bad=1
  j='{"jobs":[{"name":"apply","conclusion":"success","steps":[{"name":"'"$INFRA_SSH_STEP"'","conclusion":"skipped"}]}]}'
  printf '%s' "$j" | jobs_have_apply_success "$INFRA_SSH_STEP" && bad=1
  j='{"jobs":[{"name":"apply","conclusion":"success"}]}'
  printf '%s' "$j" | jobs_have_apply_success "$INFRA_SSH_STEP" && bad=1
  if [[ "$bad" -ne 0 ]]; then
    printf '::error::apply_delivery_gap_self_test_failed\n'
    exit 1
  fi
  printf 'apply_delivery_gap_self_test=ok\n'
}

# ---- argv: --self-test is dispatched FIRST, before any env validation -------------------------------------------
reject_input() {
  printf 'input rejected: %s\n' "$1"
  printf '::error::apply_delivery_gap_bad_input\n'
  exit 2
}

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir contains ..; refusing\n' >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir is a synthetic-fs path; refusing\n' >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *) printf 'FATAL: fixture dir is RELATIVE; refusing\n' >&2; exit 2 ;;
  esac
}

if [[ "${1-}" == "--self-test" ]]; then
  [[ $# -eq 1 ]] || reject_input "--self-test takes no other argument"
  self_test
  exit 0
fi

while (($#)); do
  case "$1" in
    --fixture-dir)
      [[ $# -ge 2 ]] || reject_input "--fixture-dir needs a directory"
      FIXTURE="$2"; shift 2 ;;
    *) reject_input "unknown argument" ;;
  esac
done

unset GH_HOST GH_ENTERPRISE_TOKEN GH_DEBUG GITHUB_API_URL
GH_REPO="${GH_REPO-}"
TRIGGER_RUN_ID="${TRIGGER_RUN_ID-}"
GITHUB_RUN_ID="${GITHUB_RUN_ID-}"
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || reject_input "GH_REPO is not owner/repo"
[[ -z "$TRIGGER_RUN_ID" || "$TRIGGER_RUN_ID" =~ ^[0-9]{1,20}$ ]] || reject_input "TRIGGER_RUN_ID is not digits"
[[ -z "$GITHUB_RUN_ID" || "$GITHUB_RUN_ID" =~ ^[0-9]{1,20}$ ]] || reject_input "GITHUB_RUN_ID is not digits"

if [[ -n "$FIXTURE" ]]; then
  assert_fixture_dir "$FIXTURE"
  [[ -x "$FIXTURE/bin/gh" && -f "$FIXTURE/now" ]] || reject_input "fixture dir lacks bin/gh or now"
  MODE=fixture
  PATH="$FIXTURE/bin:$PATH"
  if [[ "${APPLY_DELIVERY_GAP_PAGE_SIZE-}" =~ ^[1-9][0-9]{0,3}$ ]]; then PAGE_SIZE="$APPLY_DELIVERY_GAP_PAGE_SIZE"; fi
  if [[ "${APPLY_DELIVERY_GAP_MAX_PAGES-}" =~ ^[1-9][0-9]{0,2}$ ]]; then MAX_PAGES="$APPLY_DELIVERY_GAP_MAX_PAGES"; fi
fi

WORK="$(mktemp -d)" || { printf '::error::apply_delivery_gap_bad_input\n'; exit 2; }
trap 'rm -rf "$WORK"' EXIT

pause() { if [[ "$MODE" != "fixture" ]]; then sleep "$1"; fi; }

iso_epoch() { jq -rn --arg t "$1" '$t | fromdateiso8601'; }
epoch_iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

if [[ "$MODE" == "fixture" ]]; then
  _now="$(tr -d '\n' <"$FIXTURE/now")"
  [[ "$_now" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || reject_input "fixture now is not an ISO timestamp"
  NOW_EPOCH="$(iso_epoch "$_now")"
else
  NOW_EPOCH="$(date -u +%s)"
fi
NOW_ISO="$(epoch_iso "$NOW_EPOCH")"
CUTOFF=$((NOW_EPOCH - WINDOW_DAYS * 86400))
RUN_URL=""
if [[ -n "$GITHUB_RUN_ID" ]]; then RUN_URL="https://github.com/${GH_REPO}/actions/runs/${GITHUB_RUN_ID}"; fi

# ---- the single read chokepoint and the fail-loud exit ---------------------------------------------------------
# api_get <reason> <allow404:0|1> <gh args...>: result file in $API_OUT. stderr is classified (anchored on the HTTP
# status) and never echoed. Transient failures (5xx, 429, 403 rate limit, no status at all, timeout) are retried up
# to 3 attempts; 404 and 422 never. A 404 with allow404=1 returns 44. Anything else is fail_loud <reason>.
api_get() {
  local reason="$1" allow404="$2" attempt=1 rc http err
  shift 2
  while :; do
    rc=0
    timeout 60 gh "$@" >"$WORK/api.out" 2>"$WORK/api.err" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      API_OUT="$WORK/api.out"
      return 0
    fi
    err="$(<"$WORK/api.err")"
    http=""
    if [[ "$err" =~ \(HTTP\ ([0-9]{3})\)[[:space:]]*$ ]]; then http="${BASH_REMATCH[1]}"; fi
    if [[ "$http" == "404" && "$allow404" == "1" ]]; then return 44; fi
    if [[ "$rc" -eq 124 || -z "$http" || "$http" =~ ^5[0-9][0-9]$ || "$http" == "429" ]] \
      || [[ "$http" == "403" && "${err,,}" == *"rate limit"* ]]; then
      if [[ "$attempt" -lt 3 ]]; then
        pause $((attempt * 2))
        attempt=$((attempt + 1))
        continue
      fi
    fi
    fail_loud "$reason"
    return 1
  done
}

# gh_write <reason> <gh args...>: a write call, retried once after 10 s. "already exists" on a label is success.
gh_write() {
  local reason="$1" attempt=1 rc err
  shift
  while :; do
    rc=0
    timeout 60 gh "$@" >"$WORK/w.out" 2>"$WORK/w.err" || rc=$?
    if [[ "$rc" -eq 0 ]]; then return 0; fi
    err="$(<"$WORK/w.err")"
    if [[ "$1" == "label" && "${err,,}" == *"already exists"* ]]; then return 0; fi
    if [[ "$attempt" -lt 2 ]]; then
      pause 10
      attempt=$((attempt + 1))
      continue
    fi
    fail_loud "$reason"
    return 1
  done
}

# fail_loud <reason>: read-class reasons first try to page a human through the degraded issue, then the named error
# annotation is the LAST output line and the run exits 1. It never reports "no gap" and never touches the gap issue.
fail_loud() {
  local reason="$1"
  if [[ "$FAILING" -eq 1 ]]; then
    printf '::error::apply_delivery_gap_%s\n' "$FAIL_FIRST"
    printf '::error::apply_delivery_gap_degraded_upsert_failed\n'
    exit 1
  fi
  FAILING=1
  FAIL_FIRST="$reason"
  case "$reason" in
    runs_list_failed|run_window_truncated|malformed_response|trigger_run_not_visible|jobs_read_failed|compare_failed|api_budget_exceeded)
      degraded_upsert "$reason" ;;
  esac
  printf '::error::apply_delivery_gap_%s\n' "$reason"
  exit 1
}

budget_tick() {
  READS=$((READS + 1))
  if [[ "$READS" -gt "$READ_BUDGET" ]]; then fail_loud api_budget_exceeded; fi
}

# ---- issues -------------------------------------------------------------------------------------------------
BOT_ISSUES="$WORK/bot-issues.json"

# OPEN bot-authored issues, both author spellings (gh versions differ on `app/github-actions` versus
# `github-actions[bot]`; measured 2026-10-23 on gh 2.103.0: only the second matched), bounded by --limit.
list_bot_issues() {
  local a n=0
  printf '[]' >"$BOT_ISSUES"
  for a in 'app/github-actions' 'github-actions[bot]'; do
    api_get issue_list_failed 0 issue list --author "$a" --state open --limit "$ISSUE_LIMIT" --json number,title,labels,author
    jq -e 'type == "array"' "$API_OUT" >/dev/null 2>/dev/null || fail_loud issue_list_failed
    n=$((n + $(jq 'length' "$API_OUT")))
    jq -s '(.[0] + .[1]) | unique_by(.number)' "$BOT_ISSUES" "$API_OUT" >"$BOT_ISSUES.new" && mv "$BOT_ISSUES.new" "$BOT_ISSUES"
  done
  if [[ "$n" -ge "$ISSUE_LIMIT" ]]; then
    printf '::warning::apply_delivery_gap_issue_list_may_be_truncated\n'
  fi
}

# issue_numbers <title>: ascending open numbers of bot-authored issues with exactly this title.
issue_numbers() {
  jq -r --arg t "$1" '
    [ .[] | select((.author.is_bot // false) == true
                   and ((.author.login // "") | IN("app/github-actions", "github-actions[bot]", "github-actions"))
                   and (.title == $t))
          | .number ] | sort | .[] | tostring' "$BOT_ISSUES"
}

ensure_label() { # name color description
  gh_write label_failed label create "$1" --color "$2" --description "$3"
}

degraded_upsert() {
  local reason="$1" nums d body="$WORK/degraded-body.md"
  list_bot_issues
  nums="$(issue_numbers "$DEGRADED_TITLE")"
  d="${nums%%$'\n'*}"
  {
    printf 'The apply delivery gap follower could not complete a reconcile.\n\n'
    printf 'Reason: apply_delivery_gap_%s\n' "$reason"
    if [[ -n "$RUN_URL" ]]; then printf 'Run: %s\n' "$RUN_URL"; fi
  } >"$body"
  if [[ -n "$d" ]]; then
    gh_write degraded_upsert_failed issue comment "$d" --body "$(<"$body")"
  else
    ensure_label "$DEGRADED_LABEL" d93f0b 'The apply delivery gap follower could not complete a reconcile'
    gh_write degraded_upsert_failed issue create --title "$DEGRADED_TITLE" --body-file "$body" \
      --label "$DEGRADED_LABEL" --label action-required
  fi
}

# ---- runs: read, validate, normalise -------------------------------------------------------------------------
WORKFLOWS_READ=0

read_runs() { # key file
  local key="$1" file="$2" p=1 cnt older res
  local raw="$WORK/raw.$key.json"
  printf '[]' >"$raw"
  while [[ "$p" -le "$MAX_PAGES" ]]; do
    api_get runs_list_failed 0 api "repos/${GH_REPO}/actions/workflows/${file}/runs?per_page=${PAGE_SIZE}&page=${p}"
    jq -e '(.workflow_runs | type) == "array"' "$API_OUT" >/dev/null 2>/dev/null || fail_loud malformed_response
    cnt="$(jq '.workflow_runs | length' "$API_OUT")"
    older="$(jq --argjson c "$CUTOFF" '[.workflow_runs[] | ((.created_at // "") | (try fromdateiso8601 catch null)) | select(. != null and . < $c)] | length' "$API_OUT")"
    jq -s '.[0] + .[1].workflow_runs' "$raw" "$API_OUT" >"$raw.new" && mv "$raw.new" "$raw"
    if [[ "$cnt" -lt "$PAGE_SIZE" ]]; then break; fi
    if [[ "$older" -eq "$cnt" ]]; then break; fi
    if [[ "$p" -eq "$MAX_PAGES" ]]; then fail_loud run_window_truncated; fi
    p=$((p + 1))
  done
  # Strict validation applies only to runs that matter (candidate-shaped, in-window successes, in-flight); a
  # malformed irrelevant record is skipped with one aggregate warning. Closed enums on status and conclusion.
  res="$(jq -c --argjson cutoff "$CUTOFF" '
    def ep: (try fromdateiso8601 catch null);
    def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    def inflight: IN("queued", "pending", "requested", "waiting", "in_progress");
    [ .[] | . as $r
      | { id: ($r.id), event: (($r.event // "") | tostring), branch: (($r.head_branch // "") | tostring),
          status: (($r.status // "") | tostring), conclusion: (($r.conclusion // "") | tostring),
          sha: (($r.head_sha // "") | tostring), created: (($r.created_at // "") | tostring),
          started: (($r.run_started_at // "") | tostring), updated: (($r.updated_at // "") | tostring) }
      | .idok = ((.id | type) == "number" and (.id == (.id | floor)) and .id > 0)
      | .shaok = (.sha | test("^[0-9a-f]{40}$"))
      | .crok = (.created | iso)
      | .ce = (if .crok then (.created | ep) else null end)
      | .matters = ((.status | inflight) or (.status == "completed" and (.conclusion | IN("cancelled", "success"))))
      | .inwin = (.ce == null or .ce >= $cutoff)
      | .valid = (.idok and .shaok and .crok)
    ] as $all
    | { malformed: [ $all[] | select(.matters and .inwin and (.valid | not)) ] | length,
        skipped: [ $all[] | select((.valid | not) and ((.matters and .inwin) | not)) ] | length,
        runs: ( [ $all[] | select(.valid)
                  | .ue = (if (.updated | iso) then (.updated | ep) else .ce end)
                  | .se = (if (.started | iso) then (.started | ep) else .ce end)
                  | del(.idok, .shaok, .crok, .matters, .inwin, .valid) ]
                | group_by(.id) | map(.[0]) | sort_by([.ce, .id]) | reverse ) }' "$raw")" || fail_loud malformed_response
  if [[ "$(jq '.malformed' <<<"$res")" -gt 0 ]]; then fail_loud malformed_response; fi
  if [[ "$(jq '.skipped' <<<"$res")" -gt 0 ]]; then printf '::warning::apply_delivery_gap_skipped_malformed_records workflow=%s\n' "$key"; fi
  jq -c '.runs' <<<"$res" >"$WORK/n.$key.json"
  WORKFLOWS_READ=$((WORKFLOWS_READ + 1))
}

trigger_visible() {
  local f
  if [[ -z "$TRIGGER_RUN_ID" ]]; then return 0; fi
  for f in "$WORK"/n.*.json; do
    if jq -e --argjson id "$TRIGGER_RUN_ID" 'any(.[]; .id == $id and .status == "completed")' "$f" >/dev/null; then return 0; fi
  done
  return 1
}

# ---- delivery ----------------------------------------------------------------------------------------------
# is_descendant <candidate sha> <run sha>: equality, else the compare API (identical|ahead). 404 = not a descendant.
is_descendant() {
  local s="$1" r="$2" k status rc
  if [[ "$s" == "$r" ]]; then return 0; fi
  k="${s}...${r}"
  if [[ -z "${CMP[$k]+x}" ]]; then
    budget_tick
    rc=0
    api_get compare_failed 1 api "repos/${GH_REPO}/compare/${s}...${r}?per_page=1" || rc=$?
    if [[ "$rc" -eq 44 ]]; then
      printf '::warning::apply_delivery_gap_compare_unresolvable sha=%s\n' "${s:0:7}"
      CMP[$k]="unresolvable"
    else
      status="$(jq -r '.status // ""' "$API_OUT")"
      case "$status" in
        identical|ahead|behind|diverged) CMP[$k]="$status" ;;
        *) fail_loud malformed_response ;;
      esac
    fi
  fi
  descendant_status "${CMP[$k]}"
}

# apply_job_ok <run id> [required step]: the run's job named `apply` concluded success and, when a step name is given, that
# step did too (memoised per run id; jobs read only after ancestry; the steps[] come from the same response).
apply_job_ok() {
  local id="$1" step="${2-}" ok=1
  if [[ -z "${JOBOK[$id]+x}" ]]; then
    budget_tick
    api_get jobs_read_failed 0 api "repos/${GH_REPO}/actions/runs/${id}/jobs?per_page=100"
    jq -e '(.total_count | type) == "number" and (.jobs | type) == "array"' "$API_OUT" >/dev/null 2>/dev/null || fail_loud malformed_response
    if jobs_have_apply_success "$step" <"$API_OUT"; then ok=0; fi
    JOBOK[$id]="$ok"
  fi
  [[ "${JOBOK[$id]}" == "0" ]]
}

# classify_run <run id>: sets CLASS from the run's job count (a global, not a command substitution: fail_loud must be
# able to exit the whole script).
classify_run() {
  local id="$1" total
  budget_tick
  api_get jobs_read_failed 0 api "repos/${GH_REPO}/actions/runs/${id}/jobs?per_page=1"
  total="$(jq -r 'if (.total_count | type) == "number" and .total_count == (.total_count | floor) and .total_count >= 0 then .total_count else "bad" end' "$API_OUT")" || total="bad"
  [[ "$total" =~ ^[0-9]+$ ]] || fail_loud malformed_response
  CLASS="$(class_for_total "$total")"
}

mins_between() { # <from epoch> <to epoch> -> whole minutes, clamped to >= 0
  local d=$(($2 - $1))
  if [[ "$d" -lt 0 ]]; then d=0; fi
  printf '%s' $((d / 60))
}

# ---- main reconcile ------------------------------------------------------------------------------------------
ROWS="$WORK/rows.tsv"        # key \t id \t sha \t class \t minutes \t later-id \t later-label \t created-epoch
DELIVERED="$WORK/delivered.tsv"  # key \t sha \t run id \t minutes
: >"$ROWS"; : >"$DELIVERED"
N_CAND=0; N_DROPPED=0; N_DEFERRED=0; N_DELIVERED=0; N_ROWS=0; N_MID=0; N_INFLIGHT=0

reconcile_workflow() { # key file ks-function cap
  local key="$1" ks="$3" cap="$4" nf="$WORK/n.$1.json" raw="$WORK/raw.$1.json"
  local cands id sha ce ue msg state rid rsha rue dmin class later lid llabel runs infl req=""
  if [[ "$key" == "infra" ]]; then req="$INFRA_SSH_STEP"; fi
  cands="$(jq -c --argjson cutoff "$CUTOFF" '
    [ .[] | select(.event == "push" and .branch == "main" and .status == "completed" and .conclusion == "cancelled" and .ce >= $cutoff) ]
    | group_by(.sha) | map(min_by(.ce)) | sort_by([.ce, .id]) | .[]' "$nf")"
  [[ -n "$cands" ]] || return 0
  while IFS= read -r c; do
    id="$(jq -r '.id' <<<"$c")"; sha="$(jq -r '.sha' <<<"$c")"; ce="$(jq -r '.ce' <<<"$c")"; ue="$(jq -r '.ue' <<<"$c")"
    N_CAND=$((N_CAND + 1))
    msg="$(jq -r --argjson id "$id" '[.[] | select(.id == $id)][0] | ((.head_commit.message // "") | tostring)' "$raw")"
    if "$ks" "$msg"; then
      N_DROPPED=$((N_DROPPED + 1))
      printf 'dropped killswitch workflow=%s sha=%s\n' "$key" "${sha:0:7}"
      continue
    fi
    state=undelivered; rid=""; dmin=0
    # (a) delivered: first qualifying run (created order) that passes every leg wins
    runs="$(jq -r --argjson ce "$ce" '
      [ .[] | select(.status == "completed" and .conclusion == "success" and .branch == "main" and .ce >= $ce) ]
      | sort_by([.ce, .id]) | .[] | [.id, .sha, .ue] | @tsv' "$nf")"
    if [[ -n "$runs" ]]; then
      while IFS=$'\t' read -r rid rsha rue; do
        if is_descendant "$sha" "$rsha" && apply_job_ok "$rid" "$req"; then
          state=delivered; dmin="$(mins_between "$ue" "$rue")"
          break
        fi
      done <<<"$runs"
    fi
    if [[ "$state" == "delivered" ]]; then
      N_DELIVERED=$((N_DELIVERED + 1))
      printf '%s\t%s\t%s\t%s\n' "$key" "$sha" "$rid" "$dmin" >>"$DELIVERED"
      continue
    fi
    # (b) deferred: a non-stale in-flight run at the candidate or a descendant
    infl="$(jq -r --argjson ce "$ce" --argjson now "$NOW_EPOCH" --argjson cap "$cap" --argjson wcap "$WAITING_CAP_MIN" '
      [ .[] | select((.status | IN("queued", "pending", "requested", "waiting", "in_progress")) and .branch == "main" and .ce >= $ce)
            | select(((if .status == "waiting" then ($now - .ce) > ($wcap * 60)
                       elif .status == "in_progress" then ($now - .se) > ($cap * 60)
                       else ($now - .ce) > ($cap * 60) end)) | not) ]
      | sort_by([.ce, .id]) | .[] | [.id, .sha] | @tsv' "$nf")"
    if [[ -n "$infl" ]]; then
      while IFS=$'\t' read -r rid rsha; do
        if is_descendant "$sha" "$rsha"; then state=deferred; break; fi
      done <<<"$infl"
    fi
    if [[ "$state" == "deferred" ]]; then
      N_DEFERRED=$((N_DEFERRED + 1))
      printf '::notice::apply_delivery_gap_deferred workflow=%s sha=%s\n' "$key" "${sha:0:7}"
      continue
    fi
    # (c) undelivered: a row
    classify_run "$id"
    class="$CLASS"
    later="$(jq -r --argjson id "$id" --argjson ce "$ce" '
      def en: if IN("success", "failure", "cancelled", "skipped", "neutral", "timed_out", "action_required", "startup_failure", "stale",
                    "queued", "in_progress", "waiting", "pending", "requested") then . else "unknown" end;
      [ .[] | select(.id != $id and .ce >= $ce) ] | sort_by([.ce, .id]) | last
      | if . == null then "" else [.id, ((if .status == "completed" then .conclusion else .status end) | en)] | @tsv end' "$nf")"
    lid=""; llabel=""
    if [[ -n "$later" ]]; then IFS=$'\t' read -r lid llabel <<<"$later"; fi
    # an empty field is written as the sentinel `-`: tab is IFS whitespace, so adjacent tabs would collapse on read
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$id" "$sha" "$class" "$(mins_between "$ue" "$NOW_EPOCH")" "${lid:--}" "${llabel:--}" "$ce" >>"$ROWS"
    N_ROWS=$((N_ROWS + 1))
    if [[ "$class" == "cancelled-mid-run" ]]; then N_MID=$((N_MID + 1)); fi
    printf '::notice title=apply-delivery-gap::row workflow=%s sha=%s class=%s\n' "$key" "$sha" "$class"
  done <<<"$cands"
}

# non-stale in-flight runs of EITHER workflow (any branch): a completion of one of them re-fires the follower.
count_inflight() {
  local row key cap f total=0 n
  for row in "${WATCHED[@]}"; do
    IFS='|' read -r key _ _ _ cap <<<"$row"
    f="$WORK/n.$key.json"
    n="$(jq --argjson now "$NOW_EPOCH" --argjson cap "$cap" --argjson wcap "$WAITING_CAP_MIN" --argjson cutoff "$CUTOFF" '
      [ .[] | select((.status | IN("queued", "pending", "requested", "waiting", "in_progress")) and .ce >= $cutoff)
            | select(((if .status == "waiting" then ($now - .ce) > ($wcap * 60)
                       elif .status == "in_progress" then ($now - .se) > ($cap * 60)
                       else ($now - .ce) > ($cap * 60) end)) | not) ] | length' "$f")"
    total=$((total + n))
  done
  N_INFLIGHT="$total"
}

watched_field() { # key field-index (1-based)
  local row k
  for row in "${WATCHED[@]}"; do
    IFS='|' read -r k _ <<<"$row"
    if [[ "$k" == "$1" ]]; then
      IFS='|' read -r -a f <<<"$row"
      printf '%s' "${f[$(($2 - 1))]}"
      return 0
    fi
  done
  return 1
}

# shellcheck disable=SC2016 # backticks in the printf formats are literal markdown
render_body() {
  local body="$WORK/body.md" shown total row_key id sha class mins lid llabel ce wf key cmd sname row
  sort -t$'\t' -k8,8nr -k2,2nr "$ROWS" >"$WORK/rows.sorted"
  head -n 40 "$WORK/rows.sorted" >"$WORK/rows.shown"
  total="$(wc -l <"$ROWS")"
  shown="$(wc -l <"$WORK/rows.shown")"
  {
    printf '## Do this\n\n'
    printf 'A dispatch from main applies the current head of main, which covers every listed push of that workflow. Run the printed command(s):\n\n```\n'
    for row in "${WATCHED[@]}"; do
      IFS='|' read -r key wf _ <<<"$row"
      sname="$(awk -F'\t' -v k="$key" '$1 == k { print substr($3, 1, 7); exit }' "$WORK/rows.sorted")"
      if [[ -z "$sname" ]]; then continue; fi
      if [[ "$key" == "infra" ]]; then
        cmd="gh workflow run ${wf} --ref main -f apply_target=manual-rerun -f reason='apply-delivery-gap ${sname}'"
      else
        cmd="gh workflow run ${wf} --ref main -f reason='apply-delivery-gap ${sname}'"
      fi
      printf '%s\n' "$cmd"
    done
    printf '```\n\n'
    printf -- '- The issue resolves itself when the next reconcile sees the push delivered.\n'
    if [[ "$N_MID" -gt 0 ]]; then
      printf -- '- For any `cancelled-mid-run` row: do NOT dispatch before reading the run - state is possibly partial.\n'
    fi
    printf -- '- Closing this issue is not an acknowledgement - a new one is filed while rows remain.\n'
    printf -- '- Comment, do not edit - the body is rewritten on every refresh.\n\n'
    printf '## Undelivered pushes\n\n'
    printf '| Workflow | Push SHA | Run | Class | Minutes since cancel | Latest later run (any outcome; not proof of delivery) |\n|---|---|---|---|---|---|\n'
    while IFS=$'\t' read -r row_key id sha class mins lid llabel ce; do
      if [[ "$lid" == "-" ]]; then lid=""; fi
      if [[ -n "$lid" ]]; then
        printf '| %s | `%s` | [%s](https://github.com/%s/actions/runs/%s) | %s | %s | [%s](https://github.com/%s/actions/runs/%s) %s |\n' \
          "$(watched_field "$row_key" 3)" "$sha" "$id" "$GH_REPO" "$id" "$class" "$mins" "$lid" "$GH_REPO" "$lid" "$llabel"
      else
        printf '| %s | `%s` | [%s](https://github.com/%s/actions/runs/%s) | %s | %s | none |\n' \
          "$(watched_field "$row_key" 3)" "$sha" "$id" "$GH_REPO" "$id" "$class" "$mins"
      fi
    done <"$WORK/rows.shown"
    if [[ "$total" -gt "$shown" ]]; then
      printf '\n+%s more undelivered pushes not shown; see the run log notices.\n' "$((total - shown))"
    fi
    printf '\n---\n\n'
    printf 'Last reconciled %s' "$NOW_ISO"
    if [[ -n "$RUN_URL" ]]; then printf ' by %s' "$RUN_URL"; fi
    printf '. Window: last %s days. Minutes are approximate.\n\n' "$WINDOW_DAYS"
    printf -- '- A row listed for more than 60 minutes warrants escalation.\n'
    printf -- '- A push carrying its own workflow skip marker never appears here.\n'
    if [[ "$N_DROPPED" -gt 0 ]]; then
      printf -- '- Dropped by kill switch (not a gap): %s\n' "$N_DROPPED"
    fi
    printf -- '- Runbook: `%s`. The 12 h scheduled drift check remains the backstop.\n' "$RUNBOOK"
  } >"$body"
  if [[ "$(wc -c <"$body")" -ge 60000 ]]; then fail_loud issue_write_failed; fi
}

emit_close_comment() { # -> stdout
  local key sha rid mins
  printf 'Every cancelled push in the window now has a delivering run:\n'
  while IFS=$'\t' read -r key sha rid mins; do
    printf -- '- %s %s delivered by run %s, %s minutes from cancel to delivery\n' "$key" "${sha:0:7}" "$rid" "$mins"
  done <"$DELIVERED"
}

ISSUE_ACTION=none

reconcile_issue() {
  local nums gap extras e dnums d labels lbls body="$WORK/body.md" p0=0 closed_comment
  list_bot_issues
  nums="$(issue_numbers "$TITLE")"
  gap="${nums%%$'\n'*}"
  if [[ -n "$gap" ]]; then
    extras="$(tail -n +2 <<<"$nums")"
    if [[ -n "$extras" ]]; then
      while IFS= read -r e; do
        gh_write issue_write_failed issue close "$e" --reason "not planned" --comment "Duplicate of #${gap}: the follower keeps one open apply delivery gap issue."
      done <<<"$extras"
    fi
  fi
  if [[ "$N_ROWS" -gt 0 ]]; then
    render_body
    if [[ "$N_MID" -gt 0 ]]; then p0=1; fi
    ensure_label "$LABEL" b60205 'A push to main that matched an apply workflow was cancelled and never applied'
    if [[ -z "$gap" ]]; then
      labels=(--label "$LABEL" --label action-required --label priority/p1-high)
      if [[ "$p0" -eq 1 ]]; then labels+=(--label priority/p0-critical); fi
      gh_write issue_write_failed issue create --title "$TITLE" --body-file "$body" "${labels[@]}"
      ISSUE_ACTION=created
    else
      lbls="${LABEL},action-required"
      if [[ "$p0" -eq 1 ]]; then lbls="${lbls},priority/p0-critical"; fi
      gh_write issue_write_failed issue edit "$gap" --body-file "$body" --add-label "$lbls"
      ISSUE_ACTION=edited
    fi
  elif [[ -n "$gap" ]]; then
    if [[ "$N_INFLIGHT" -gt 0 ]]; then
      printf 'issue left open: a non-stale apply run is in flight\n'
    elif [[ "$N_DELIVERED" -ge 1 ]]; then
      closed_comment="$(emit_close_comment)"
      gh_write issue_write_failed issue close "$gap" --reason completed --comment "$closed_comment"
      ISSUE_ACTION=closed
    else
      api_get issue_list_failed 0 issue view "$gap" --json comments
      if jq -e --arg m "$AGED_MARKER" 'any((.comments // [])[]; (.body // "") | contains($m))' "$API_OUT" >/dev/null; then
        printf 'issue left open: the aged-out comment is already present\n'
      else
        gh_write issue_write_failed issue comment "$gap" --body "${AGED_MARKER}
No cancelled push remains inside the ${WINDOW_DAYS}-day window and none was seen delivered. Verify delivery (see the runbook) and close this issue by hand."
        ISSUE_ACTION=aged-out-comment
      fi
    fi
  fi
  # a complete reconcile closes the degraded issue
  dnums="$(issue_numbers "$DEGRADED_TITLE")"
  if [[ -n "$dnums" ]]; then
    while IFS= read -r d; do
      gh_write issue_write_failed issue close "$d" --reason completed --comment "A full reconcile completed; the follower is healthy again."
    done <<<"$dnums"
  fi
}

main() {
  local row key file ks cap attempt=1
  while :; do
    WORKFLOWS_READ=0
    for row in "${WATCHED[@]}"; do
      IFS='|' read -r key file _ _ _ <<<"$row"
      read_runs "$key" "$file"
    done
    if trigger_visible; then break; fi
    if [[ "$attempt" -ge 3 ]]; then fail_loud trigger_run_not_visible; fi
    attempt=$((attempt + 1))
    pause 5
  done
  for row in "${WATCHED[@]}"; do
    IFS='|' read -r key file _ ks cap <<<"$row"
    reconcile_workflow "$key" "$file" "$ks" "$cap"
  done
  count_inflight
  reconcile_issue
  printf '::notice::apply_delivery_gap_summary mode=%s workflows_read=%s candidates=%s rows=%s deferred=%s delivered=%s dropped=%s mid_run=%s inflight=%s issue=%s\n' \
    "$MODE" "$WORKFLOWS_READ" "$N_CAND" "$N_ROWS" "$N_DEFERRED" "$N_DELIVERED" "$N_DROPPED" "$N_MID" "$N_INFLIGHT" "$ISSUE_ACTION"
}

main
