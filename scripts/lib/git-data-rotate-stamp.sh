#!/usr/bin/env bash
# git-data-rotate-stamp.sh — read the d6 rotate stamp off apply-web-platform-infra.yml run records (#10166).
#
# SOURCED by .github/workflows/git-data-cutover.yml (step flip_preconditions), never executed. It decides
# whether a run of apply-web-platform-infra.yml discharges the flip's d6_replace_stale precondition: only
# a git-data-host-rotate run whose git_data_host_replace job SUCCEEDED with the last-step marker
# (GDRS_MARKER_STEP) succeeded does. The marker's own `if:` in the apply workflow is the single place the
# target / plan_only decision is made; this library never re-derives it from dispatch inputs (which
# `gh run view --json jobs` does not expose). Trust boundary: the library comes from the dispatched ref's
# checkout, the same boundary as scripts/lib/bearer-curl.sh, held by the main-restricted reviewer environment.
#
# Why not the old confirm-token step: `Validate dispatch inputs (rotate confirm token)` is unconditional
# (census G5c) and concludes success on EVERY target (it prints `rotate confirm: n/a` on every non-rotate
# target and passes silently on a rotate), so a plain replace or a plan-only rotate satisfied the gate
# without any rotation.
#
# API (the library never calls fail/exit: it runs inside $(...), and every failure is an explicit check):
#   git_data_rotate_run_verdict <jobs-json>   prints ONE token, returns 0 iff `stamped`:
#       stamped | skip | in_flight | rotate_failed | unreadable
#   git_data_d6_scan                          reads "<run id><TAB><run status>" lines on stdin, newest
#       first, and prints ONE line: d6_stamped <id> | d6_last_rotate_failed <id> | d6_rotate_in_flight <id>
#       | d6_run_unreadable [<id>] | d6_replace_stale. Returns 0 iff d6_stamped. The id is absent only when
#       the input line itself was not a numeric run id.
#
# The four names below are matched byte for byte against the apply workflow by
# plugins/soleur/test/terraform-target-parity.test.ts. The em dash is U+2014.
readonly GDRS_JOB_NAME="git_data_host_replace"
readonly GDRS_PRECONDITION_STEP="Rotate precondition — served store measured empty"
readonly GDRS_APPLY_STEP="Terraform apply (git-data-host -replace) — post-apply backstop"
readonly GDRS_MARKER_STEP="Rotate completed (d6 marker)"

# One jq program, input by here-string (never bare stdin, so a caller's id stream is never consumed).
# A step is "absent" (not in the job's list at all: a rename, or the step never existed), "skipped", or
# carries its conclusion; a step that IS listed but has no conclusion yet is "unknown" (it was running
# when the job was cancelled or timed out), and "unknown" is NOT "absent": it means the step began.
# Rows, evaluated in order:
#   1 not an object, or .jobs not an array                                         -> unreadable
#   2 no job named exactly $job, or the job was skipped                            -> skip
#   3 job conclusion empty or null (running, queued, waiting for approval)         -> in_flight
#   4 job success AND the marker step success (self-sufficient: a drift in the     -> stamped
#     precondition/apply step names can never reject a real stamp)
#   5 precondition step absent or skipped (a plain replace, or never reached)      -> skip
#   6 apply step SKIPPED (plan-only, or refused before apply: nothing mutated)     -> skip
#   7 job success without a marker success (a pre-marker legacy success)           -> skip
#   8 anything else (the apply failed, was cancelled mid-flight, never reported a  -> rotate_failed
#     conclusion, or is ABSENT under a drifted name, on a job that did not succeed)
# Row 6 keys on an explicit `skipped`, never on absence: an absent apply step under a rotate whose
# precondition succeeded is a rename (the run recorded before PR #10155 carries the old name), and a name
# drift must fail toward "uncertain", not toward "nothing happened".
# Row 3 runs before the attempt rows on purpose: a job still running or waiting has no usable steps, so a
# plain replace waiting for approval also reads in_flight and blocks the flip (fails closed, transiently).
# Row 8 includes a green marker inside a failed job (a failed post-job step): closed, and surprising on purpose.
# shellcheck disable=SC2016  # a jq program, not shell: the $names are jq variables bound by --arg below
_GDRS_JQ='
  if (type != "object") or ((.jobs | type) != "array") then "unreadable"
  else
    ([.jobs[] | select(type == "object" and .name == $job)] | .[0]) as $j
    | if $j == null then "skip"
      elif ($j.conclusion // "") == "skipped" then "skip"
      elif ($j.conclusion // "") == "" then "in_flight"
      else
        (($j.steps // []) | if type == "array" then . else [] end) as $steps
        | def sc($n): ([$steps[] | select(type == "object" and .name == $n)] | .[0])
                      | if . == null then "absent" else (.conclusion // "unknown") end;
          if $j.conclusion == "success" and sc($marker) == "success" then "stamped"
          elif (sc($pre) == "absent" or sc($pre) == "skipped") then "skip"
          elif sc($apply) == "skipped" then "skip"
          elif $j.conclusion == "success" then "skip"
          else "rotate_failed" end
      end
  end'

git_data_rotate_run_verdict() {
  local body="${1-}" out rc=0
  out="$(jq -r --arg job "$GDRS_JOB_NAME" --arg pre "$GDRS_PRECONDITION_STEP" \
            --arg apply "$GDRS_APPLY_STEP" --arg marker "$GDRS_MARKER_STEP" \
            "$_GDRS_JQ" <<<"$body" 2>/dev/null)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then echo unreadable; return 1; fi
  case "$out" in
    stamped) echo stamped; return 0 ;;
    skip|in_flight|rotate_failed|unreadable) echo "$out"; return 1 ;;
  esac
  echo unreadable
  return 1
}

git_data_d6_scan() {
  local rid status body tok rc
  # The ids are read on fd 3. That alone does NOT protect them: `3<&0` duplicates the descriptor and the
  # two share one file offset, so a child that reads stdin would still eat the rest of the list. What
  # protects the stream is `</dev/null` on every command the loop runs (the gh call below).
  while IFS=$'\t' read -r -u 3 rid status; do
    [[ -n "$rid" ]] || continue
    # The ids come from `gh run list --jq` (databaseId, always numeric); anything else is not a run id and
    # is never echoed back or handed to gh.
    if ! [[ "$rid" =~ ^[0-9]+$ ]]; then echo "d6_run_unreadable"; return 1; fi
    rc=0
    body="$(gh run view "$rid" --json jobs </dev/null 2>/dev/null)" || rc=$?
    # Never `continue` past a run that could not be read: skipping it is how an older success masked a failure.
    if [[ "$rc" -ne 0 || -z "$body" ]]; then echo "d6_run_unreadable $rid"; return 1; fi
    # A run that has not completed and does not list the job yet (queued with no jobs, or jobs created
    # without ours) cannot be attributed to a target: in flight, never skipped in favour of an older stamp.
    if [[ "$status" != completed ]] \
       && jq -e --arg job "$GDRS_JOB_NAME" \
            '(.jobs | type) == "array" and ([.jobs[] | select(type == "object" and .name == $job)] | length) == 0' \
            <<<"$body" >/dev/null 2>&1; then
      echo "d6_rotate_in_flight $rid"; return 1
    fi
    tok="$(git_data_rotate_run_verdict "$body")" || true
    case "$tok" in
      stamped) echo "d6_stamped $rid"; return 0 ;;
      skip) continue ;;
      rotate_failed) echo "d6_last_rotate_failed $rid"; return 1 ;;
      in_flight) echo "d6_rotate_in_flight $rid"; return 1 ;;
      # `unreadable`, and any token this loop does not know (including an empty one): fail closed.
      unreadable|*) echo "d6_run_unreadable $rid"; return 1 ;;
    esac
  done 3<&0
  echo d6_replace_stale
  return 1
}
