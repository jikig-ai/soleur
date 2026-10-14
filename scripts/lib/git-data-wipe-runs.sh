#!/usr/bin/env bash
# git-data-wipe-runs.sh — what earlier runs of git-data-cutover.yml tell the wipe job (#10138, design W3 / section 5).
#
# SOURCED by .github/workflows/git-data-cutover.yml (job `wipe`), never executed; functions and constants only.
# `gh run list --json` does NOT return dispatch inputs or job outputs, so the only handle on an earlier run is its
# `displayTitle`, which the workflow's `run-name:` builds from `inputs.mode` (and, for the wipe modes, the volume id):
#     wipe modes   ^git-data (wipe|wipe_finish|wipe_check) [0-9]{1,12}$
#     other modes  ^git-data (proof|flip|rollback|unfreeze|redeploy)$
#     legacy       git-data cutover (#5274 / ADR-220 / ADR-239)   (the workflow name: every run before `run-name:` landed)
#
# API. Every function prints ONE token on stdout and signals with its return code; none of them exits, none prints a
# credential, and nothing is read as "fine" when it could not be read.
#
#   wipe_run_title_class <displayTitle>
#       prints: wipe | wipe_finish | wipe_check | other | legacy | wipe_other | unparseable        rc 0 always
#       `wipe_other` is ANY title starting `git-data wipe` that is not a full match (a refused dispatch whose free-text
#       volume_id made an off-pattern title): the guard ignores it. `other` covers the five non-wipe modes, rollback
#       included (wipe_last_rollback_epoch tells rollback apart by its exact title).
#
#   wipe_last_rollback_epoch <gh-run-list-json> <stamp-epoch>        the W3 interim guard (CTO F, decision-challenges)
#       The JSON is `gh run list --workflow git-data-cutover.yml --limit "$WIPE_RUNS_LIST_LIMIT"
#       --json databaseId,displayTitle,createdAt,conclusion,headBranch,event`. Only rows with headBranch main AND
#       event workflow_dispatch are read, and only those created at or after the stamp (>=: fail closed).
#       prints `ok` (rc 0) or one refusal word (rc 5):
#         wipe_precondition_rollback_after_stamp     a `git-data rollback` run, whatever its conclusion (a failed one may
#                                                    have changed the flag)
#         wipe_precondition_legacy_run_after_stamp   a legacy-titled run
#         wipe_precondition_run_title_unparseable    a title that is none of the known families
#         wipe_precondition_run_list_unreaching      the list is FULL (>= the limit) and its oldest row is newer than the
#                                                    stamp, so an older rollback could lie outside the window
#         wipe_precondition_run_list_unreadable      not JSON, not an array, or ANY row malformed (missing fields, a
#                                                    createdAt that is not YYYY-MM-DDTHH:MM:SSZ)
#       rc 2 with `wipe_runs_bad_args` when the stamp is not a non-negative integer.
#
#   wipe_origin_run_ok <gh-run-view-json> <volume_id> [detach|delete]   the wipe_finish origin-run check (CTO A)
#       The JSON is `gh run view <origin_run> --json displayTitle,headBranch,event,createdAt,workflowName,jobs`. The run
#       must be titled exactly `git-data wipe <volume_id>`, belong to THIS workflow (`workflowName` equal to
#       $WIPE_LEGACY_TITLE, which is the workflow's `name:`: a run-name is free text, any workflow on main can set one),
#       ran on main by workflow_dispatch, and the job named exactly `wipe` must
#       list EXACTLY ONE step named $WIPE_ORIGIN_DETACH_STEP (mode detach, the default) or $WIPE_ORIGIN_DELETE_STEP (mode
#       delete: the absent-volume branch) with conclusion `success`. Later steps are NOT constrained (a detach that was
#       accepted but unconfirmed, or a lost runner, is what this arm recovers from).
#       prints `ok` (rc 0) or one refusal word (rc 5): wipe_origin_run_unreadable | wipe_origin_run_title_mismatch |
#       wipe_origin_run_workflow_mismatch | wipe_origin_run_not_main | wipe_origin_run_not_dispatch | wipe_origin_run_gate_not_success.
#       rc 2 with `wipe_runs_bad_args` for a volume_id outside ^[0-9]{1,12}$ or an unknown mode word.
#
# NAMING CONTRACT WITH THE WORKFLOW. `gh run view --json jobs` exposes a step's `name`, not its `id`. The workflow's
# `wipe` job must therefore be named `wipe` (no `name:` override), and the step that writes the detach marker (W9a) must
# carry `name: wipe_detach_gate`, the step that writes the delete marker (W11a) `name: wipe_delete_gate`. A rename on
# one side makes every origin run read `wipe_origin_run_gate_not_success` (fail closed); the suite pins these names.
#
# jq regexes end in \z, not $: Oniguruma's `$` also matches before a trailing newline.
readonly WIPE_RUNS_LIST_LIMIT=100
readonly WIPE_LEGACY_TITLE='git-data cutover (#5274 / ADR-220 / ADR-239)'
readonly WIPE_ORIGIN_JOB=wipe
readonly WIPE_ORIGIN_DETACH_STEP=wipe_detach_gate
readonly WIPE_ORIGIN_DELETE_STEP=wipe_delete_gate

# The single title classifier, shared by the bash function and the list guard so the two cannot drift.
# shellcheck disable=SC2016  # a jq program, not shell: the $names are jq variables bound by --arg below
_WIPE_RUNS_JQ_DEFS='
  def tclass:
    if type != "string" then "unparseable"
    elif test("^git-data (wipe|wipe_finish|wipe_check) [0-9]{1,12}\\z") then capture("^git-data (?<m>wipe_finish|wipe_check|wipe) ").m
    elif test("^git-data (proof|flip|rollback|unfreeze|redeploy)\\z") then "other"
    elif . == $legacy then "legacy"
    elif startswith("git-data wipe") then "wipe_other"
    else "unparseable" end;
  def epoch:
    if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z")
    then (try fromdateiso8601 catch null) else null end;
'

# wipe_run_title_class <displayTitle>
wipe_run_title_class() {
  local out
  out="$(jq -rn --arg legacy "$WIPE_LEGACY_TITLE" --arg t "${1-}" "${_WIPE_RUNS_JQ_DEFS} \$t | tclass" 2>/dev/null)" || out=""
  case "$out" in
    wipe|wipe_finish|wipe_check|other|legacy|wipe_other|unparseable) printf '%s\n' "$out" ;;
    *) printf 'unparseable\n' ;;
  esac
  return 0
}

# shellcheck disable=SC2016  # a jq program
_WIPE_RUNS_JQ_GUARD='
  if type != "array" then "wipe_precondition_run_list_unreadable"
  elif any(.[]; (type != "object") or ((.displayTitle | type) != "string") or ((.headBranch | type) != "string")
                or ((.event | type) != "string") or ((.createdAt | epoch) == null))
  then "wipe_precondition_run_list_unreadable"
  else
    (map(.createdAt | epoch) | min) as $oldest
    | [ .[] | select(.headBranch == "main" and .event == "workflow_dispatch") | select((.createdAt | epoch) >= $stamp) | .displayTitle ] as $titles
    | if any($titles[]; . == "git-data rollback") then "wipe_precondition_rollback_after_stamp"
      elif any($titles[]; tclass == "legacy") then "wipe_precondition_legacy_run_after_stamp"
      elif any($titles[]; tclass == "unparseable") then "wipe_precondition_run_title_unparseable"
      elif (length >= $limit) and ($oldest > $stamp) then "wipe_precondition_run_list_unreaching"
      else "ok" end
  end'

# wipe_last_rollback_epoch <gh-run-list-json> <stamp-epoch>
wipe_last_rollback_epoch() {
  local body="${1-}" stamp="${2-}" out rc=0
  if ! [[ "$stamp" =~ ^[0-9]+$ ]]; then printf 'wipe_runs_bad_args\n'; return 2; fi
  out="$(jq -r --arg legacy "$WIPE_LEGACY_TITLE" --argjson stamp "$stamp" --argjson limit "$WIPE_RUNS_LIST_LIMIT" \
          "${_WIPE_RUNS_JQ_DEFS} ${_WIPE_RUNS_JQ_GUARD}" <<<"$body" 2>/dev/null)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then printf 'wipe_precondition_run_list_unreadable\n'; return 5; fi
  case "$out" in
    ok) printf 'ok\n'; return 0 ;;
    wipe_precondition_rollback_after_stamp|wipe_precondition_legacy_run_after_stamp|wipe_precondition_run_title_unparseable|wipe_precondition_run_list_unreaching|wipe_precondition_run_list_unreadable)
      printf '%s\n' "$out"; return 5 ;;
  esac
  printf 'wipe_precondition_run_list_unreadable\n'
  return 5
}

# shellcheck disable=SC2016  # a jq program
_WIPE_RUNS_JQ_ORIGIN='
  if (type != "object") or ((.displayTitle | type) != "string") or ((.workflowName | type) != "string") or ((.jobs | type) != "array") then "wipe_origin_run_unreadable"
  elif .displayTitle != ("git-data wipe " + $vid) then "wipe_origin_run_title_mismatch"
  elif .workflowName != $wf then "wipe_origin_run_workflow_mismatch"
  elif .headBranch != "main" then "wipe_origin_run_not_main"
  elif .event != "workflow_dispatch" then "wipe_origin_run_not_dispatch"
  else
    [ .jobs[] | select(type == "object" and .name == $job) ] as $js
    | if ($js | length) != 1 then "wipe_origin_run_gate_not_success"
      else
        [ ($js[0].steps // []) | if type == "array" then .[] else empty end | select(type == "object" and .name == $step) ] as $ss
        | if ($ss | length) == 1 and $ss[0].conclusion == "success" then "ok" else "wipe_origin_run_gate_not_success" end
      end
  end'

# wipe_origin_run_ok <gh-run-view-json> <volume_id> [detach|delete]
wipe_origin_run_ok() {
  local body="${1-}" vid="${2-}" gate="${3:-detach}" step out rc=0
  [[ "$vid" =~ ^[0-9]{1,12}$ ]] || { printf 'wipe_runs_bad_args\n'; return 2; }
  case "$gate" in
    detach) step="$WIPE_ORIGIN_DETACH_STEP" ;;
    delete) step="$WIPE_ORIGIN_DELETE_STEP" ;;
    *) printf 'wipe_runs_bad_args\n'; return 2 ;;
  esac
  out="$(jq -r --arg vid "$vid" --arg wf "$WIPE_LEGACY_TITLE" --arg job "$WIPE_ORIGIN_JOB" --arg step "$step" "$_WIPE_RUNS_JQ_ORIGIN" <<<"$body" 2>/dev/null)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then printf 'wipe_origin_run_unreadable\n'; return 5; fi
  case "$out" in
    ok) printf 'ok\n'; return 0 ;;
    wipe_origin_run_unreadable|wipe_origin_run_title_mismatch|wipe_origin_run_workflow_mismatch|wipe_origin_run_not_main|wipe_origin_run_not_dispatch|wipe_origin_run_gate_not_success)
      printf '%s\n' "$out"; return 5 ;;
  esac
  printf 'wipe_origin_run_unreadable\n'
  return 5
}
