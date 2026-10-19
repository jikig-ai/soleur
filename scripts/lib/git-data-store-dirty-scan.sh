#!/usr/bin/env bash
# git-data-store-dirty-scan.sh — has the LUKS store ever been offered a write? (#10175)
#
# SOURCED by .github/workflows/apply-web-platform-infra.yml (job git_data_host_replace, step "Rotate
# precondition — store never written (cutover run records)") and by git-data-cutover.yml (the wipe job's W3 step, separated variant, with GDSD_SELF_RUN_ID), never executed. A git-data-host-rotate
# destroys the LUKS volume. After the first real flip that volume may hold the ONLY copy of replicated
# repositories, and the old emptiness check (one boot-time row, served_repos=0) cannot see them. This
# library answers the question from the cutover workflow's own run records, so no prd credential is needed
# (ADR-239 keeps one out of the apply workflow): the store is DIRTY once any run of git-data-cutover.yml
# executed the flag-write step, whatever that step concluded, because a failed or cancelled write may
# still have landed. A rollback does not make it clean: rollback is flag-off only and the data stays on LUKS.
# The flag value and the GIT_DATA_LUKS_CUTOVER_AT stamp are deliberately NOT inputs (the stamp survives a
# rollback, so it decides nothing).
#
# API (no function calls exit or fail: they run inside $(...), and every failure is an explicit check):
#   git_data_store_dirty_job_verdict <jobs-json> [preseam]   prints ONE token, returns 0 iff `clean`:
#       clean | dirty | unreadable
#   git_data_store_dirty_list                       prints "<run id><TAB><status><TAB><run_attempt><TAB><created_at>" for
#       every run of the cutover workflow, newest first, and the expected total on the LAST line as
#       "total<TAB><n>". Returns non-zero (printing nothing useful) when any page could not be read.
#   git_data_store_dirty_scan [PINS]                reads git_data_store_dirty_list's output on stdin and
#       prints ONE line: store_clean | store_dirty <id> | cutover_in_flight <id> | scan_unreadable [<id>|pinned_run_missing].
#       PINS is a space-separated run-id list that must all be listed as completed; omitted OR EMPTY, it is
#       GDSD_PINNED_RUNS (the workflow passes nothing, and a test pins that), and a test passes the literal
#       --no-pins to model an arbitrary history without the completeness proof.
#       GDSD_SELF_RUN_ID (optional, numeric) names the CALLER'S OWN run: it is excluded for its current attempt only
#       (earlier attempts are still read), so a scan run from inside a wipe-family dispatch does not block itself.
#       Returns 0 iff store_clean. Every attempt of every run is read: `gh run view` lists only the latest
#       attempt, and a re-run that skips the write step must not hide the first attempt's write.
#
# GDSD_WORKFLOW_FILE and GDSD_WRITE_STEP are matched byte for byte against git-data-cutover.yml by
# plugins/soleur/test/terraform-target-parity.test.ts (a rename on one side reds a test, not a flip).
readonly GDSD_WORKFLOW_FILE="git-data-cutover.yml"
readonly GDSD_JOB_NAME="cutover"
# The step is written `name: Write GIT_DATA_STORE_ENABLED (via the #8573 seam)` in git-data-cutover.yml, and YAML
# reads ` #` as the start of a comment, so the name GitHub records, and the API returns for every run, is the
# truncated text below (measured on run 37823216637, 2026-10-08). The parity test pins this constant against the
# PARSED workflow, so a fix of the YAML (quoting the name) reds a test instead of silently making every
# recorded run's step "absent". Do not "correct" this to the full text without migrating that pin.
readonly GDSD_WRITE_STEP="Write GIT_DATA_STORE_ENABLED (via the"
# PROOF THAT THE HISTORY IS COMPLETE (review 2026-10-13, CTO F-A). Run records can be deleted (by retention or by
# hand) and `total_count` shrinks with the rows, so the count cross-check alone cannot see a deleted flip. Two
# post-seam runs are pinned: both must still be listed as `completed`, or the scan refuses with
# `scan_unreadable pinned_run_missing`. Deletion is oldest-first under retention, so a listed pin means nothing newer
# has expired, and runs from before the seam could not write the flag, so their deletion is harmless.
# MEASURED 2026-10-13: this repository's run list still shows runs 196 days old although the artifact-and-log
# retention setting reads 90 days, so the real expiry horizon is not known; the guard does not rely on it.
# A SECOND, measured horizon: GitHub strips a job's step list at about 170 days (a 174-day-old run is listed with no
# steps). A step-less job of a run created after the seam reads unreadable (row 3 below), so the oldest pin
# (36685251588, created 2026-09-30) turns the guard CLOSED at about 2027-03-18 even if no run is deleted. Pre-seam
# runs with no steps read clean (they could not write the flag). NOTE the scan reads EVERY listed run, so moving the
# pins is not enough by itself once ANY post-seam run (not only a pin) has lost its step list: that run reads
# `scan_unreadable <id>` until its record is deleted or the owner attests it (runbook: "Re-baselining the pinned runs";
# the policy for stripped post-seam records is tracked in #10216, which carries a 2026-12-01 calendar item, well inside
# both horizons).
readonly GDSD_PINNED_RUNS="36685251588 37823216637"
# The pin-age warning threshold, days: the scan prints `::warning::` once the oldest pin is older than this.
readonly GDSD_PIN_WARN_DAYS=120

# The write step does not exist in runs created before the seam landed (the read-only-proof era, merged
# 2026-09-30T02:18:17Z in the real-modes PR): such a run could not write the flag, so an ABSENT step there
# is clean by construction, and an absent step in a LATER run is still a rename (unreadable). That claim is
# verified against the recorded runs, not enforced by code (a pre-seam dry-run script could set the flag, and no
# non-dry pre-seam run exists in the record).
readonly GDSD_SEAM_ADDED_AT="2026-09-30T02:18:17Z"

# Rows, evaluated in order (input by here-string, never bare stdin):
#   1 not an object, or .jobs not an array                                    -> unreadable
#   2 no job named exactly $job                                               -> clean when $preseam, else unreadable
#     (a post-seam run always lists the job, skipped or not; a missing one is a rename, a caller wrapper or a
#     renamed job, never evidence that the store is clean)
#   3 the job has no steps: concluded skipped/cancelled (never ran, approval
#     rejected, cancelled while queued), or the run predates the seam (it could
#     not write the flag; step lists of old runs are stripped)                -> clean
#   4 the job has no steps and any other conclusion (null: queued/waiting)    -> unreadable
#   5 the job ran and the write step is absent: clean when $preseam is true    -> clean / unreadable
#     (the run predates the step), otherwise a rename
#   6 the write step concluded skipped                                        -> clean
#   7 the write step carries ANY other conclusion, null included             -> dirty
# shellcheck disable=SC2016  # a jq program, not shell: the $names are jq variables bound by --arg below
_GDSD_JQ='
  if (type != "object") or ((.jobs | type) != "array") then "unreadable"
  else
    ([.jobs[] | select(type == "object" and .name == $job)] | .[0]) as $j
    | if $j == null then (if $preseam then "clean" else "unreadable" end)
      else
        (($j.steps // []) | if type == "array" then . else [] end) as $steps
        | if ($steps | length) == 0 then
            (if $preseam or (($j.conclusion // "") == "skipped" or ($j.conclusion // "") == "cancelled") then "clean" else "unreadable" end)
          else
            ([$steps[] | select(type == "object" and .name == $step)] | .[0]) as $w
            | if $w == null then (if $preseam then "clean" else "unreadable" end)
              elif ($w.conclusion // "") == "skipped" then "clean"
              else "dirty" end
          end
      end
  end'

# git_data_store_dirty_job_verdict <jobs-json> [preseam]   (preseam = the literal word `preseam` for a run
# created before GDSD_SEAM_ADDED_AT)
git_data_store_dirty_job_verdict() {
  local body="${1-}" pre=false out rc=0
  [[ "${2-}" == preseam ]] && pre=true
  out="$(jq -r --arg job "$GDSD_JOB_NAME" --arg step "$GDSD_WRITE_STEP" --argjson preseam "$pre" "$_GDSD_JQ" <<<"$body" 2>/dev/null)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo unreadable; return 1; fi
  case "$out" in
    clean) echo clean; return 0 ;;
    dirty|unreadable) echo "$out"; return 1 ;;
  esac
  echo unreadable
  return 1
}

git_data_store_dirty_list() {
  local repo="${GITHUB_REPOSITORY:-}" base total rows
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  base="repos/${repo}/actions/workflows/${GDSD_WORKFLOW_FILE}/runs"
  total="$(gh api "${base}?per_page=1" --jq '.total_count' </dev/null 2>/dev/null)" || return 1
  [[ "$total" =~ ^[0-9]+$ ]] || return 1
  rows="$(gh api --paginate "${base}?per_page=100" \
            --jq '.workflow_runs[] | [.id, .status, .run_attempt, .created_at] | @tsv' </dev/null 2>/dev/null)" || return 1
  [[ -z "$rows" ]] || printf '%s\n' "$rows"
  printf 'total\t%s\n' "$total"
}

git_data_store_dirty_scan() {
  local pins="${1:-$GDSD_PINNED_RUNS}" pin oldest="" age_s line
  # A blank or whitespace-only argument is the same as none: it must never reach an empty pin list.
  [[ -n "${pins//[[:space:]]/}" ]] || pins="$GDSD_PINNED_RUNS"
  [[ "${1-}" == --no-pins ]] && pins=""
  local rid status attempt created n last body tok rc expect="" seen=0 pre
  # The caller's OWN run id, opt-in (A1, ADR-239 Amendment 2026-10-15): the separated wipe scans from inside a run of
  # this workflow, which is in_progress by construction and would read as cutover_in_flight on every dispatch. Only
  # that run's CURRENT attempt is skipped. No validation of the value is needed: the comparison is against a run id the
  # loop below proves numeric, so a non-numeric value can never match (a mutant that removed such a check survived,
  # and was EQUIVALENT).
  local self="${GDSD_SELF_RUN_ID-}"
  local -a lines=()
  while IFS=$'\t' read -r rid status attempt created; do
    [[ -n "$rid" ]] || continue
    if [[ "$rid" == total ]]; then expect="$status"; continue; fi
    lines+=("${rid}"$'\t'"${status}"$'\t'"${attempt}"$'\t'"${created}")
  done
  # The collected count must equal the API's own total: a truncated or filtered listing reads as "clean".
  if ! [[ "$expect" =~ ^[0-9]+$ ]] || [[ "${#lines[@]}" -ne "$expect" ]]; then
    echo "scan_unreadable"; return 1
  fi
  # Proof the history is complete: every pinned run must still be listed, completed. An empty listing fails
  # here too whenever a pin exists.
  for pin in $pins; do
    [[ "$pin" =~ ^[0-9]+$ ]] || { echo "scan_unreadable pinned_run_missing"; return 1; }
    pre=""
    for line in "${lines[@]}"; do
      IFS=$'\t' read -r rid status attempt created <<<"$line"
      if [[ "$rid" == "$pin" && "$status" == completed ]]; then pre="$created"; break; fi
    done
    [[ -n "$pre" ]] || { echo "scan_unreadable pinned_run_missing"; return 1; }
    if [[ -z "$oldest" || "$pre" < "$oldest" ]]; then oldest="$pre"; fi
  done
  # Early warning, to the log (stderr, so it never joins the one-line verdict): the oldest pin nears expiry.
  if [[ -n "$oldest" ]] && age_s="$(( $(date -u +%s) - $(date -u -d "$oldest" +%s 2>/dev/null || echo "$(date -u +%s)") ))"; then
    if (( age_s > GDSD_PIN_WARN_DAYS * 86400 )); then
      echo "::warning::the oldest pinned cutover run is $(( age_s / 86400 )) days old; run records can be deleted and step lists are stripped at about 170 days, and the rotate guard then fails closed. Re-baseline the pins (runbook: Re-baselining the pinned runs, tracker #10216)." >&2
    fi
  fi
  for line in "${lines[@]}"; do
    IFS=$'\t' read -r rid status attempt created <<<"$line"
    if ! [[ "$rid" =~ ^[0-9]+$ && "$attempt" =~ ^[0-9]+$ && "$attempt" -ge 1 ]]; then echo "scan_unreadable"; return 1; fi
    # created_at is an ISO-8601 UTC stamp, so a string comparison is a time comparison; an unparseable
    # one is never read as "before the seam".
    pre=""
    if [[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && "$created" < "$GDSD_SEAM_ADDED_AT" ]]; then pre=preseam; fi
    seen=$((seen + 1))
    case "$status" in
      in_progress)
        # The caller's own run: its `cutover` job is skipped for the wipe family, so only its EARLIER attempts
        # (a re-run keeps the id) can hold a write. Any other in-progress run still blocks.
        if [[ -n "$self" && "$rid" == "$self" ]]; then last=$((attempt - 1))
        else echo "cutover_in_flight $rid"; return 1; fi ;;
      completed) last="$attempt" ;;
      # queued/waiting/pending/requested: the latest attempt executed nothing yet (the shared
      # git-data-state group means it cannot overlap this job), but earlier attempts of a re-run did run.
      queued|waiting|pending|requested) last=$((attempt - 1)) ;;
      *) echo "scan_unreadable $rid"; return 1 ;;
    esac
    for ((n = 1; n <= last; n++)); do
      rc=0
      body="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${rid}/attempts/${n}/jobs?per_page=100" </dev/null 2>/dev/null)" || rc=$?
      # Never `continue` past a run that could not be read: skipping it is how an older write hid.
      if [[ "$rc" -ne 0 || -z "$body" ]]; then echo "scan_unreadable $rid"; return 1; fi
      tok="$(git_data_store_dirty_job_verdict "$body" "$pre")" || true
      case "$tok" in
        clean) : ;;
        dirty) echo "store_dirty $rid"; return 1 ;;
        unreadable|*) echo "scan_unreadable $rid"; return 1 ;;
      esac
    done
  done
  echo store_clean
  return 0
}
