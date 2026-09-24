#!/usr/bin/env bash
# cancel-superseded-pr-runs.sh — cancel this PR's still-queued / still-running workflow
# runs whose head SHA is no longer the PR head. Invoked by
# .github/workflows/cancel-superseded-pr-runs.yml on pull_request synchronize/reopened.
# Why, and what it deliberately never touches: ADR-216, addendum 2026-09-24.
#
# MODES
#   select   pure, no network. Reads a JSON array of workflow-run objects on stdin and
#            prints one TSV row per run: decision, id, reason, event, name, sha7.
#            Env: HEAD_SHA HEAD_REF HEAD_REPO PR_NUMBER SELF_RUN_ID SELF_CREATED_AT
#            DEFAULT_BRANCH, and CSPR_LEDGER (default scripts/pr-fanout-ledger.txt).
#            Rules are first-match-wins; each carries its number in SELECT_JQ.
#   run      (default) context reads -> list -> head check -> select -> cancel.
#            Env: REPO PR_NUMBER EVENT_HEAD_SHA HEAD_REF HEAD_REPO DEFAULT_BRANCH
#            SELF_RUN_ID (GH_TOKEN for gh). Optional: CSPR_DRY_RUN=1 (print would-cancel
#            rows, POST nothing), CSPR_HEAD_RETRY_SLEEP (seconds between head reads, 5),
#            CSPR_FORCE_DELAY (seconds before the force-cancel pass, 45).
#
# ONLY WORKFLOWS THAT RE-RUN ON A PUSH ARE REAPED. A pull_request / pull_request_target
# run is cancellable only when its workflow file is a row of scripts/pr-fanout-ledger.txt,
# the inventory of workflows that fire on `synchronize` (enforced by
# plugins/soleur/test/pr-fanout-ledger.test.sh). A workflow triggered only by opened /
# ready_for_review / closed (board-status-sync.yml) is never re-run on the new head, so
# cancelling its run would lose it. No readable ledger -> exit 2, nothing cancelled.
#
# ORDER IS LOAD-BEARING. The live PR head is read AFTER the listing and only the pure
# `select` separates that read from the cancel loop, so a push that lands during the
# listing (A->B->A included) is caught. The head must EQUAL the event head: the pulls
# endpoint can lag, and a lagging read of an OLDER sha used as the head would protect the
# old sha and cancel the new head's runs. Runs created after this run (a newer push listed
# while the pulls endpoint still lagged) are skipped by rule 11. Residual: a push that
# lands between the head read and a POST is not seen; the reaper for that push replaces
# this one (per-PR concurrency) within seconds.
#
# CANCEL IS GRACEFUL FIRST: POST .../cancel, so `if: always()` steps keep the chance to run.
# SECOND PASS (force-cancel, #8669 follow-up): a graceful cancel returns 202 but leaves a run
# `queued` when its only unfinished job is an `if: always()` aggregator still waiting for a
# runner (measured on the first live reap: 2 of 3 cancelled runs still queued after 60 s,
# each 0 in_progress / 1 queued / 2 completed). After CSPR_FORCE_DELAY seconds, each target
# of THIS run's graceful cancels is re-read, and force-cancelled ONLY when the run is still
# `queued` AND none of its jobs is `in_progress` (nothing is executing, so no mutex is held
# and no always() step is mid-flight). A run with any in_progress job, or whose jobs cannot
# be read, is never force-cancelled.
# A pull_request_target run (secrets, outside writes) is re-read immediately before its
# POST and cancelled only if it has not started.
#
# EXIT: 0 done (including "head moved, nothing to do"); 1 a GitHub read, list call or
#       cancel failed; 2 bad context / usage / unreadable ledger; 78 refused under xtrace.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
SHA_RE='^[0-9a-f]{40}$'
NUM_RE='^[0-9]+$'
PFX='cancel-superseded-pr-runs:'

# First match wins. Every output field is sentinel-mapped to "-" when empty, because
# `IFS=$'\t' read` collapses runs of tabs and would shift later fields left. The status
# set leaves out `action_required` on purpose (a run waiting for approval is not using a
# runner and is the approver's to discard).
# shellcheck disable=SC2016  # jq program, not shell
SELECT_JQ='
def iso: type == "string" and test($iso_re);
def sha: type == "string" and test($sha_re);
def pr_event: IN("pull_request", "pull_request_target");
def nz: if . == null or . == "" then "-" else tostring end;
def wf_name: sub("@.*$"; "") | split("/") | last;
(($self_created | iso) and ($head_sha | sha)) as $ctx_ok
| .[]
| ((.path // "") | if type == "string" then . else "" end) as $path
| (.head_branch // "") as $branch
| (if ($ctx_ok | not) then ["skip", "bad-context"]                                    # 0
   elif ((.id | type) != "number" or (.id | . != floor or . < 1)
         or (.head_sha | sha | not) or (.created_at | iso | not)
         or (.event | type) != "string" or (.status | type) != "string")
     then ["skip", "malformed"]                                                        # 1
   elif .id == $self_id then ["skip", "self"]                                          # 2
   elif (.event | pr_event or . == "dynamic" | not) then ["skip", "event"]             # 3
   elif ($branch | IN($default_branch, "refs/heads/" + $default_branch))
     then ["skip", "default-branch"]                                                   # 4
   elif .event == "dynamic"
        and (($path | startswith("dynamic/github-code-scanning/"))
             or ($path | startswith("dynamic/github-code-quality/")) | not)
     then ["skip", "dynamic-path"]                                                     # 5
   elif .event == "dynamic" and $branch != ("refs/pull/" + $pr + "/head")
     then ["skip", "branch"]                                                           # 6
   elif (.event | pr_event) and $branch != $head_ref then ["skip", "branch"]           # 7
   elif (.event | pr_event) and ((.head_repository.full_name? // "") != $head_repo)
     then ["skip", "repo"]                                                             # 8
   elif (.event | pr_event)
        and ((.pull_requests // []) | if type == "array"
               then any(.[]; (.number? // null) == ($pr | tonumber)) else false end | not)
     then ["skip", "other-pr"]                                                         # 8b
   elif (.event | pr_event)
        and (($path | startswith(".github/workflows/") | not)
             or ($path | wf_name | IN($reapable[]) | not))
     then ["skip", "not-reaped-workflow"]                                              # 8c
   elif (.status | IN("queued", "in_progress", "waiting", "pending", "requested") | not)
     then ["skip", "status"]                                                           # 9
   elif .event == "pull_request_target" and .status == "in_progress"
     then ["skip", "privileged-in-progress"]                                           # 9b
   elif .head_sha == $head_sha then ["skip", "current-head"]                           # 10
   elif .created_at >= $self_created then ["skip", "too-new"]                          # 11
   else ["cancel", "superseded"]                                                       # 12
   end) as $d
| [$d[0], (.id | nz), $d[1], (.event | nz), (.name | nz), ((.head_sha // "") | tostring | .[0:7] | nz)]
| @tsv
'

err() { printf '::error::%s %s\n' "$PFX" "$*"; }
warn() { printf '::warning::%s %s\n' "$PFX" "$*"; }

# One sanitiser for every API-derived string before it reaches stdout, an annotation or
# the step summary: no control bytes (a forged line or terminal escape), no U+0085 /
# U+2028 / U+2029, no `::` anywhere (a forged workflow command), no backtick (a broken
# markdown code span).
sanitize() {
  local s="${1-}"
  s="$(LC_ALL=C; printf '%s' "${s//[[:cntrl:]]/ }")"
  s="${s//$'\xc2\x85'/ }"
  s="${s//$'\xe2\x80\xa8'/ }"
  s="${s//$'\xe2\x80\xa9'/ }"
  while [[ "$s" == *::* ]]; do s="${s//::/: :}"; done
  s="${s//\`/\'}"
  printf '%s' "$s"
}

# load_reapable — JSON array of the workflow basenames listed in the fan-out ledger.
load_reapable() {
  local ledger="${CSPR_LEDGER:-scripts/pr-fanout-ledger.txt}" names
  if [[ ! -r "$ledger" ]]; then err "fan-out ledger $ledger is not readable; nothing cancelled"; return 2; fi
  names="$(awk -F '\t' '!/^#/ && $1 ~ /^[A-Za-z0-9._-]+\.ya?ml$/ { print $1 }' "$ledger")"
  if [[ -z "$names" ]]; then err "fan-out ledger $ledger lists no workflows; nothing cancelled"; return 2; fi
  printf '%s\n' "$names" | jq -R . | jq -sc .
}

do_select() {
  local v reapable
  for v in HEAD_REF HEAD_REPO PR_NUMBER SELF_RUN_ID DEFAULT_BRANCH; do
    if [[ -z "${!v:-}" ]]; then err "select: $v is empty"; return 2; fi
  done
  [[ "$PR_NUMBER" =~ $NUM_RE ]] || { err "select: PR_NUMBER is not numeric"; return 2; }
  [[ "$SELF_RUN_ID" =~ $NUM_RE ]] || { err "select: SELF_RUN_ID is not numeric"; return 2; }
  reapable="$(load_reapable)" || return 2
  # A malformed HEAD_SHA or SELF_CREATED_AT is NOT refused here: rule 0 turns it into
  # `skip bad-context` for every run, the offline-tested fail-closed path.
  jq -r \
    --arg head_sha "${HEAD_SHA:-}" \
    --arg head_ref "$HEAD_REF" \
    --arg head_repo "$HEAD_REPO" \
    --arg pr "$PR_NUMBER" \
    --argjson self_id "$SELF_RUN_ID" \
    --arg self_created "${SELF_CREATED_AT:-}" \
    --arg default_branch "$DEFAULT_BRANCH" \
    --arg iso_re "$ISO_RE" \
    --arg sha_re "$SHA_RE" \
    --argjson reapable "$reapable" \
    "$SELECT_JQ"
}

# http_code <stdout-file> <stderr-file> — the status code from `gh api -i`'s first line,
# else from stderr's `(HTTP NNN)`, else empty.
http_code() {
  local first="" errtxt=""
  if [[ -s "$1" ]]; then IFS= read -r first < "$1" || true; fi
  first="${first%$'\r'}"
  if [[ "$first" =~ ^HTTP/[0-9.]+\ ([0-9]{3}) ]]; then printf '%s' "${BASH_REMATCH[1]}"; return 0; fi
  if [[ -s "$2" ]]; then errtxt="$(<"$2")"; fi
  if [[ "$errtxt" =~ \(HTTP\ ([0-9]{3})\) ]]; then printf '%s' "${BASH_REMATCH[1]}"; return 0; fi
  return 0
}

# failure_kind <code> <text> — `rate-limited`, `refused` or `other`.
failure_kind() {
  local code="$1" text="$2"
  if [[ "$code" == "429" ]]; then printf 'rate-limited'; return 0; fi
  if [[ "$code" == "403" ]]; then
    if [[ "${text,,}" == *"rate limit"* ]]; then printf 'rate-limited'; return 0; fi
    if [[ "$text" == *"Resource not accessible by integration"* ]]; then printf 'refused'; return 0; fi
  fi
  printf 'other'
}

do_run() {
  local v
  for v in REPO PR_NUMBER EVENT_HEAD_SHA HEAD_REF HEAD_REPO DEFAULT_BRANCH SELF_RUN_ID; do
    if [[ -z "${!v:-}" ]]; then err "$v is empty"; exit 2; fi
  done
  [[ "$PR_NUMBER" =~ $NUM_RE ]] || { err "PR_NUMBER is not numeric"; exit 2; }
  [[ "$SELF_RUN_ID" =~ $NUM_RE ]] || { err "SELF_RUN_ID is not numeric"; exit 2; }
  [[ "$EVENT_HEAD_SHA" =~ $SHA_RE ]] || { err "EVENT_HEAD_SHA is not a 40-hex sha"; exit 2; }
  [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { err "REPO is not owner/name"; exit 2; }
  local sleep_s="${CSPR_HEAD_RETRY_SLEEP:-5}"
  [[ "$sleep_s" =~ $NUM_RE ]] || { err "CSPR_HEAD_RETRY_SLEEP is not numeric"; exit 2; }
  local dry="${CSPR_DRY_RUN:-0}"
  local force_delay="${CSPR_FORCE_DELAY:-45}"
  [[ "$force_delay" =~ $NUM_RE ]] || { err "CSPR_FORCE_DELAY is not numeric"; exit 2; }
  load_reapable > /dev/null || exit 2

  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  local out="$TMPD/out" errf="$TMPD/err"

  # --- 1. context reads -------------------------------------------------------------
  local pr_created self_created
  if ! gh api "repos/$REPO/pulls/$PR_NUMBER" --jq .created_at > "$out" 2> "$errf"; then
    err "reading PR #$PR_NUMBER failed: $(sanitize "$(<"$errf")")"; exit 1
  fi
  pr_created="$(<"$out")"
  [[ "$pr_created" =~ $ISO_RE ]] || { err "PR created_at is not ISO-8601: $(sanitize "$pr_created")"; exit 2; }
  if ! gh api "repos/$REPO/actions/runs/$SELF_RUN_ID" --jq .created_at > "$out" 2> "$errf"; then
    err "reading this run ($SELF_RUN_ID) failed: $(sanitize "$(<"$errf")")"; exit 1
  fi
  self_created="$(<"$out")"
  # Rule 11's input. A literal `null` must never reach the lexicographic compare.
  [[ "$self_created" =~ $ISO_RE ]] || { err "this run's created_at is not ISO-8601: $(sanitize "$self_created")"; exit 2; }

  # --- 2. list: one call per branch key, NO status= filter (a mistyped status enum
  #        returns 0 runs with no 422; status is filtered by select rule 9) ----------
  local since="${pr_created:0:10}" branch enc listfile="$TMPD/runs.ndjson" code kind
  : > "$listfile"
  for branch in "$HEAD_REF" "refs/pull/$PR_NUMBER/head"; do
    enc="$(jq -rn --arg b "$branch" '$b | @uri')"
    if ! gh api --paginate "repos/$REPO/actions/runs?branch=$enc&created=%3E%3D$since&per_page=100" \
         --jq '.workflow_runs[]' > "$out" 2> "$errf"; then
      code="$(http_code "$out" "$errf")"
      kind="$(failure_kind "$code" "$(<"$errf")")"
      [[ "$kind" == "rate-limited" ]] || kind="list"
      err "listing runs for branch $(sanitize "$branch") failed:$kind (HTTP ${code:-?}); nothing cancelled: $(sanitize "$(<"$errf")")"
      exit 1
    fi
    cat "$out" >> "$listfile"
  done
  local runs="$TMPD/runs.json" listed
  jq -s 'unique_by(.id)' < "$listfile" > "$runs"
  listed="$(jq 'length' < "$runs")"

  # --- 3. head check (guard A) — AFTER the listing, immediately before select+cancel --
  local live="" i matched=0
  for i in 1 2 3; do
    if ! gh api "repos/$REPO/pulls/$PR_NUMBER" --jq .head.sha > "$out" 2> "$errf"; then
      err "reading PR #$PR_NUMBER head failed: $(sanitize "$(<"$errf")")"; exit 1
    fi
    live="$(<"$out")"
    [[ "$live" =~ $SHA_RE ]] || { err "live PR head is not a 40-hex sha: $(sanitize "$live")"; exit 2; }
    if [[ "$live" == "$EVENT_HEAD_SHA" ]]; then matched=1; break; fi
    if (( i < 3 )); then sleep "$sleep_s"; fi
  done
  if (( matched == 0 )); then
    printf '%s pr=#%s event-head=%s live-head=%s — head is not this run'"'"'s; the run for the newer head reaps\n' \
      "$PFX" "$PR_NUMBER" "${EVENT_HEAD_SHA:0:7}" "${live:0:7}"
    exit 0
  fi

  # --- 4. select ---------------------------------------------------------------------
  local rows="$TMPD/rows.tsv"
  HEAD_SHA="$live" SELF_CREATED_AT="$self_created" do_select < "$runs" > "$rows"

  # --- 5. cancel (graceful only) -------------------------------------------------------
  local cancelled=0 skipped=0 failed=0 would=0 decision id reason event name sha7 text st
  local -A reasons=()
  local -a cancelled_lines=() cancelled_ids=()
  skip_as() { skipped=$((skipped + 1)); reasons[$1]=$(( ${reasons[$1]:-0} + 1 )); }
  while IFS=$'\t' read -r decision id reason event name sha7; do
    if [[ "$decision" != "cancel" ]]; then skip_as "$reason"; continue; fi
    [[ "$id" =~ $NUM_RE ]] || { err "select emitted a non-numeric id for a cancel row"; exit 2; }
    if [[ "$event" == "pull_request_target" ]]; then
      # Rule 9b read the listing snapshot; the run may have started since. Re-read.
      st=""
      if gh api "repos/$REPO/actions/runs/$id" --jq .status > "$out" 2> "$errf" < /dev/null; then st="$(<"$out")"; fi
      case "$st" in
        queued|waiting|pending|requested) ;;
        *) skip_as "privileged-in-progress"; continue ;;
      esac
    fi
    if [[ "$dry" == "1" ]]; then
      printf 'would-cancel %s %s %s %s\n' "$id" "$(sanitize "$event")" "$(sanitize "$name")" "$(sanitize "$sha7")"
      would=$((would + 1)); continue
    fi
    if gh api -i -X POST "repos/$REPO/actions/runs/$id/cancel" > "$out" 2> "$errf" < /dev/null; then
      cancelled=$((cancelled + 1)); cancelled_ids+=("$id")
      cancelled_lines+=("$id	$(sanitize "$name")	$(sanitize "$event")	$(sanitize "$sha7")")
      continue
    fi
    code="$(http_code "$out" "$errf")"
    text="$(<"$errf") $(<"$out")"
    case "$code" in
      409|404) skip_as "gone" ;;
      *)
        kind="$(failure_kind "$code" "$text")"
        if [[ "$kind" == "refused" && "$event" == "dynamic" ]]; then
          skip_as "refused"
          warn "cancel of dynamic run $id refused (HTTP 403): the token cannot cancel this run class"
        else
          [[ "$kind" == "other" ]] && kind="http-${code:-unknown}"
          failed=$((failed + 1)); reasons["failed:$kind"]=$(( ${reasons["failed:$kind"]:-0} + 1 ))
          err "cancel of run $id ($(sanitize "$event")) failed:$kind (HTTP ${code:-?}): $(sanitize "$(<"$errf")")"
        fi ;;
    esac
  done < "$rows"

  # --- 5b. force-cancel pass: only this run's graceful-cancel targets that are still
  #         `queued` with ZERO in_progress jobs -------------------------------------------
  local forced=0 fid inprog
  if (( ${#cancelled_ids[@]} > 0 )); then
    sleep "$force_delay"
    for fid in "${cancelled_ids[@]}"; do
      st=""
      if gh api "repos/$REPO/actions/runs/$fid" --jq .status > "$out" 2> "$errf" < /dev/null; then st="$(<"$out")"; fi
      [[ "$st" == "queued" ]] || continue
      if ! gh api --paginate "repos/$REPO/actions/runs/$fid/jobs?per_page=100" --jq '.jobs[].status' > "$out" 2> "$errf" < /dev/null; then
        reasons[force-skipped-unreadable]=$(( ${reasons[force-skipped-unreadable]:-0} + 1 )); continue
      fi
      # A run with no readable jobs is not provably idle: never force it.
      if [[ ! -s "$out" ]]; then reasons[force-skipped-unreadable]=$(( ${reasons[force-skipped-unreadable]:-0} + 1 )); continue; fi
      inprog="$(grep -cxF in_progress "$out" || true)"
      if [[ "$inprog" != "0" ]]; then
        reasons[force-skipped-in-progress]=$(( ${reasons[force-skipped-in-progress]:-0} + 1 )); continue
      fi
      if gh api -i -X POST "repos/$REPO/actions/runs/$fid/force-cancel" > "$out" 2> "$errf" < /dev/null; then
        forced=$((forced + 1))
        continue
      fi
      code="$(http_code "$out" "$errf")"
      case "$code" in
        409|404) reasons[force-gone]=$(( ${reasons[force-gone]:-0} + 1 )) ;;
        *) warn "force-cancel of run $fid failed (HTTP ${code:-?}): $(sanitize "$(<"$errf")")"
           reasons[force-failed]=$(( ${reasons[force-failed]:-0} + 1 )) ;;
      esac
    done
  fi

  # --- 6. summary ----------------------------------------------------------------------
  local rl="?" reason_list=""
  if gh api rate_limit --jq .resources.core.remaining > "$out" 2> /dev/null; then rl="$(<"$out")"; fi
  [[ "$rl" =~ $NUM_RE ]] || rl="?"
  if (( ${#reasons[@]} > 0 )); then
    reason_list="$(for k in "${!reasons[@]}"; do printf '%s:%s\n' "$k" "${reasons[$k]}"; done | LC_ALL=C sort | paste -sd, -)"
  fi
  local line="$PFX pr=#$PR_NUMBER head=${live:0:7} listed=$listed cancelled=$cancelled force_cancelled=$forced skipped=$skipped failed=$failed"
  [[ "$dry" == "1" ]] && line+=" would_cancel=$would"
  line+=" reasons=${reason_list:--} ratelimit_remaining=$rl"
  printf '%s\n' "$line"
  local c
  for c in "${cancelled_lines[@]}"; do printf '  cancelled %s\n' "$c"; done
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      printf '%s\n\n' "$line"
      for c in "${cancelled_lines[@]}"; do
        IFS=$'\t' read -r id name event sha7 <<< "$c"
        # shellcheck disable=SC2016  # literal backticks: markdown code spans
        printf -- '- cancelled run %s `%s` (%s) on `%s`\n' "$id" "$name" "$event" "$sha7"
      done
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  (( failed == 0 )) || exit 1
  exit 0
}

case "${1:-run}" in
  select) do_select ;;
  run) do_run ;;
  *) err "usage: $0 [select|run]"; exit 2 ;;
esac
