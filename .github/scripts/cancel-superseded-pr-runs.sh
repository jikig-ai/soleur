#!/usr/bin/env bash
# cancel-superseded-pr-runs.sh — cancel this PR's still-queued / still-running workflow
# runs whose head SHA is no longer the PR head. Invoked by
# .github/workflows/cancel-superseded-pr-runs.yml on pull_request synchronize/reopened.
#
# WHY. A superseded run holds a hosted runner and, for tenant-integration.yml, the
# per-ref `dev-supabase-<ref>` group slot plus the cross-ref dev-suite DB mutex, while
# the new head's required checks queue behind it. Per-workflow `cancel-in-progress`
# cannot reach this class: CodeQL default setup has no YAML file, cla*.yml run on
# pull_request_target, constraint-gates.yml is template-parity-locked, and
# tenant-integration.yml / vendor-pin-verify.yml keep `cancel-in-progress: false` on
# purpose (#5585 R3) because a group-keyed cancel also fires on a SAME-SHA re-trigger.
# This script keys on head_sha instead, so it never cancels a same-SHA run.
# Decision record: ADR-216, addendum 2026-09-24.
#
# MODES
#   select   pure, no network. Reads a JSON array of workflow-run objects on stdin and
#            prints one TSV row per run: decision, id, reason, event, name, sha7.
#            Context comes from env: HEAD_SHA HEAD_REF HEAD_REPO PR_NUMBER SELF_RUN_ID
#            SELF_CREATED_AT DEFAULT_BRANCH. Rules are first-match-wins (see SELECT_JQ).
#   run      (default) list -> head check -> select -> cancel. Env: REPO PR_NUMBER
#            EVENT_HEAD_SHA HEAD_REF HEAD_REPO DEFAULT_BRANCH SELF_RUN_ID (GH_TOKEN for gh).
#            Optional: CSPR_DRY_RUN=1 (print would-cancel rows, POST nothing),
#            CSPR_HEAD_RETRY_SLEEP (seconds between head reads, default 5).
#
# ORDER IS LOAD-BEARING. The live PR head is read AFTER the listing and only the pure
# `select` separates that read from the cancel loop, so a push that lands during the
# listing (A->B->A included) is caught. The head must EQUAL the event head: the pulls
# endpoint can lag, and a lagging read of an OLDER sha used as the head would protect
# the old sha and cancel the new head's runs. Runs created after this run (a newer push
# listed while the pulls endpoint still lagged) are skipped by rule 11.
#
# CANCEL IS GRACEFUL ONLY: POST .../cancel, never .../force-cancel. A graceful cancel
# still runs `if: always()` steps (tenant-integration's `Release dev-suite mutex`).
#
# EXIT: 0 done (including "head moved, nothing to do"); 1 a list call or a cancel failed;
#       2 bad context / usage.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
SHA_RE='^[0-9a-f]{40}$'
NUM_RE='^[0-9]+$'
PFX='cancel-superseded-pr-runs:'

# First match wins. Every field is sentinel-mapped to "-" when empty, because
# `IFS=$'\t' read` collapses runs of tabs and would shift later fields left.
# shellcheck disable=SC2016  # jq program, not shell
SELECT_JQ='
def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
def pr_event: IN("pull_request", "pull_request_target");
def nz: if . == null or . == "" then "-" else tostring end;
(($self_created | iso) and ($head_sha | test("^[0-9a-f]{40}$"))) as $ctx_ok
| .[]
| ((.path // "") | if type == "string" then . else "" end) as $path
| (.head_branch // "") as $branch
| (if ($ctx_ok | not) then ["skip", "bad-context"]
   elif ((.id | type) != "number" or (.head_sha | type) != "string"
         or (.created_at | iso | not) or (.event | type) != "string"
         or (.status | type) != "string") then ["skip", "malformed"]
   elif .id == $self_id then ["skip", "self"]
   elif (.event | IN("pull_request", "pull_request_target", "dynamic") | not) then ["skip", "event"]
   elif ($branch | IN($default_branch, "refs/heads/" + $default_branch)) then ["skip", "default-branch"]
   elif .event == "dynamic"
        and (($path | startswith("dynamic/github-code-scanning/"))
             or ($path | startswith("dynamic/github-code-quality/")) | not) then ["skip", "dynamic-path"]
   elif .event == "dynamic" and $branch != ("refs/pull/" + $pr + "/head") then ["skip", "branch"]
   elif (.event | pr_event) and $branch != $head_ref then ["skip", "branch"]
   elif (.event | pr_event) and ((.head_repository.full_name? // "") != $head_repo) then ["skip", "repo"]
   elif (.status | IN("queued", "in_progress", "waiting", "pending", "requested") | not) then ["skip", "status"]
   elif .event == "pull_request_target" and .status == "in_progress" then ["skip", "privileged-in-progress"]
   elif .head_sha == $head_sha then ["skip", "current-head"]
   elif .created_at >= $self_created then ["skip", "too-new"]
   else ["cancel", "superseded"]
   end) as $d
| [$d[0], (.id | nz), $d[1], (.event | nz), (.name | nz), ((.head_sha // "") | tostring | .[0:7] | nz)]
| @tsv
'

err() { printf '::error::%s %s\n' "$PFX" "$*"; }
warn() { printf '::warning::%s %s\n' "$PFX" "$*"; }

# One sanitiser for every API-derived string before it reaches stdout, an annotation or
# the step summary: no CR/LF/U+2028/U+2029 (a forged line), no `::` (a forged command).
sanitize() {
  local s="${1-}"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\xe2\x80\xa8'/ }"
  s="${s//$'\xe2\x80\xa9'/ }"
  s="${s//::/: :}"
  s="${s//\`/\'}"
  printf '%s' "$s"
}

do_select() {
  local v
  for v in HEAD_SHA HEAD_REF HEAD_REPO PR_NUMBER SELF_RUN_ID DEFAULT_BRANCH; do
    if [[ -z "${!v:-}" ]]; then err "select: $v is empty"; return 2; fi
  done
  [[ "$PR_NUMBER" =~ $NUM_RE ]] || { err "select: PR_NUMBER is not numeric"; return 2; }
  [[ "$SELF_RUN_ID" =~ $NUM_RE ]] || { err "select: SELF_RUN_ID is not numeric"; return 2; }
  # SELF_CREATED_AT / HEAD_SHA are NOT refused here: rule 0 turns a bad value into
  # `skip bad-context` for every run, which is the offline-tested fail-closed path.
  jq -r \
    --arg head_sha "$HEAD_SHA" \
    --arg head_ref "$HEAD_REF" \
    --arg head_repo "$HEAD_REPO" \
    --arg pr "$PR_NUMBER" \
    --argjson self_id "$SELF_RUN_ID" \
    --arg self_created "${SELF_CREATED_AT:-}" \
    --arg default_branch "$DEFAULT_BRANCH" \
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

# failure_kind <code> <text> — `rate-limited` or `refused` or `other`.
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
  # Guard B's input. A literal `null` must never reach the lexicographic compare.
  [[ "$self_created" =~ $ISO_RE ]] || { err "this run's created_at is not ISO-8601: $(sanitize "$self_created")"; exit 2; }

  # --- 2. list: one call per branch key, NO status= filter (a mistyped status enum
  #        returns 0 runs with no 422; status is filtered by select rule 9) ----------
  local since="${pr_created:0:10}" branch enc n listfile="$TMPD/runs.ndjson" code kind
  : > "$listfile"
  for branch in "$HEAD_REF" "refs/pull/$PR_NUMBER/head"; do
    enc="$(jq -rn --arg b "$branch" '$b | @uri')"
    if ! gh api --paginate "repos/$REPO/actions/runs?branch=$enc&created=%3E%3D$since&per_page=100" \
         --jq '.workflow_runs[]' > "$out" 2> "$errf"; then
      code="$(http_code "$out" "$errf")"
      kind="$(failure_kind "$code" "$(<"$errf")")"
      [[ "$kind" == "rate-limited" ]] || kind="list"
      err "listing runs for branch $(sanitize "$branch") failed (HTTP ${code:-?}) failed:$kind; nothing cancelled: $(sanitize "$(<"$errf")")"
      exit 1
    fi
    n=0
    if [[ -s "$out" ]]; then n="$(jq -s 'length' < "$out")"; fi
    if (( n >= 1000 )); then warn "listing for branch $(sanitize "$branch") returned $n runs; the API caps at 1000, listing may be truncated"; fi
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
  local cancelled=0 skipped=0 failed=0 would=0 decision id reason event name sha7 text
  local -A reasons=()
  local -a cancelled_lines=()
  while IFS=$'\t' read -r decision id reason event name sha7; do
    if [[ "$decision" != "cancel" ]]; then
      skipped=$((skipped + 1)); reasons[$reason]=$(( ${reasons[$reason]:-0} + 1 )); continue
    fi
    [[ "$id" =~ $NUM_RE ]] || { err "select emitted a non-numeric id for a cancel row"; exit 2; }
    if [[ "$dry" == "1" ]]; then
      printf 'would-cancel %s %s %s %s\n' "$id" "$(sanitize "$event")" "$(sanitize "$name")" "$(sanitize "$sha7")"
      would=$((would + 1)); continue
    fi
    code=""
    if gh api -i -X POST "repos/$REPO/actions/runs/$id/cancel" > "$out" 2> "$errf"; then
      cancelled=$((cancelled + 1))
      cancelled_lines+=("$id	$(sanitize "$name")	$(sanitize "$event")	$(sanitize "$sha7")")
      continue
    fi
    code="$(http_code "$out" "$errf")"
    text="$(<"$errf") $(<"$out")"
    case "$code" in
      202) cancelled=$((cancelled + 1))
           cancelled_lines+=("$id	$(sanitize "$name")	$(sanitize "$event")	$(sanitize "$sha7")") ;;
      409|404) skipped=$((skipped + 1)); reasons[gone]=$(( ${reasons[gone]:-0} + 1 )) ;;
      *)
        kind="$(failure_kind "$code" "$text")"
        if [[ "$kind" == "refused" && "$event" == "dynamic" ]]; then
          skipped=$((skipped + 1)); reasons[refused]=$(( ${reasons[refused]:-0} + 1 ))
          warn "cancel of dynamic run $id refused (HTTP 403): the token cannot cancel this run class"
        else
          [[ "$kind" == "other" ]] && kind="http-${code:-unknown}"
          failed=$((failed + 1)); reasons["failed:$kind"]=$(( ${reasons["failed:$kind"]:-0} + 1 ))
          err "cancel of run $id ($(sanitize "$event")) failed:$kind (HTTP ${code:-?}): $(sanitize "$(<"$errf")")"
        fi ;;
    esac
  done < "$rows"

  # --- 6. summary ----------------------------------------------------------------------
  local rl="?" k reason_list=""
  if gh api rate_limit --jq .resources.core.remaining > "$out" 2> /dev/null; then rl="$(<"$out")"; fi
  [[ "$rl" =~ $NUM_RE ]] || rl="?"
  for k in "${!reasons[@]}"; do reason_list+="${reason_list:+,}$k:${reasons[$k]}"; done
  reason_list="$(printf '%s' "$reason_list" | tr ',' '\n' | LC_ALL=C sort | paste -sd, -)"
  local line="$PFX pr=#$PR_NUMBER head=${live:0:7} listed=$listed cancelled=$cancelled skipped=$skipped failed=$failed"
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
