#!/usr/bin/env bash
# The canonical PR check/merge poll loop for the Monitor tool.
#
# WHY THIS IS A SCRIPT AND NOT A PROSE INSTRUCTION
#
# `pollInstructions()` in plugins/soleur/lib/harness.ts already says to use
# "state-change + heartbeat shell loops", and AGENTS.rules.md carries TWO
# hook-enforced rules about arming a Monitor at all
# (hr-dispatch-async-must-arm-watch, hr-monitor-not-run-in-background-for-polling).
# All three were satisfied, in the same session, by a hand-rolled loop that emitted
# NOTHING for 50 minutes because every one of its `echo`s was behind a terminal-state
# branch. The operator had to ask "why is the monitor not showing progress?".
#
# The rules mandate that a monitor be ARMED. None of them constrains what it EMITS.
# An armed-but-silent monitor satisfies every gate while producing exactly the outcome
# hr-dispatch-async-must-arm-watch names in its own rationale: "Unwatched async work is
# silent, not pending."
#
# THE ASYMMETRY THAT MAKES THIS EASY TO GET WRONG
#
# The Monitor tool's own docs warn about one direction only:
#
#     "if this process crashed right now, would my filter emit anything?"
#
# That catches a filter that greps only the success marker. It does NOT catch the
# inverse, which is what actually happened here: every TERMINAL state was covered
# (merged, failed, cancelled, timed out) and the HEALTHY IN-PROGRESS state was not.
# A correct monitor and a dead monitor then look identical to the operator, and the
# longer the job runs the more it looks like something is stuck.
#
# Rule of thumb this encodes: a monitor must emit on every poll, not on every EVENT.
# Progress IS the event when the thing you are watching takes tens of minutes.
#
# Usage:
#   monitor-pr-checks.sh <pr-number> [--interval SECONDS] [--max-polls N] [--repo OWNER/REPO]
#
# Emits one line per poll:
#   [OPEN|BLOCKED|automerge=true] 73/78 pass · 0 fail · 0 cancel · 2 pending → test-scripts,...
# and exactly one terminal line:
#   MERGED — ... | CLOSED WITHOUT MERGE — ... | CHECKS SETTLED — ... | TIMEOUT — ...
#
# Exit 0 on a merge or an all-green settle; 1 on a red/closed terminal; 2 on timeout;
# 3 on usage error. The caller's Monitor watch ends when this exits.
set -uo pipefail

PR=""; INTERVAL=120; MAX_POLLS=60; REPO_ARG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)  INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --max-polls) MAX_POLLS="${2:?--max-polls needs a value}"; shift 2 ;;
    --repo)      REPO_ARG=(--repo "${2:?--repo needs a value}"); shift 2 ;;
    -h|--help)   sed -n '1,40p' "$0"; exit 0 ;;
    -*)          echo "monitor-pr-checks: unknown flag $1" >&2; exit 3 ;;
    *)           if [[ -n "$PR" ]]; then echo "monitor-pr-checks: unexpected argument $1" >&2; exit 3; fi
                 PR="$1"; shift ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "monitor-pr-checks: <pr-number> is required and must be numeric" >&2; exit 3; }
[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -ge 10 ]] || { echo "monitor-pr-checks: --interval must be an integer >= 10" >&2; exit 3; }
[[ "$MAX_POLLS" =~ ^[0-9]+$ && "$MAX_POLLS" -ge 1 ]] || { echo "monitor-pr-checks: --max-polls must be an integer >= 1" >&2; exit 3; }

n=0
while :; do
  n=$((n + 1))

  # `|| true` on BOTH probes and a literal fallback: a transient gh/network failure must not kill
  # the loop. A monitor that dies on one bad request is the silent failure one level up.
  view="$(gh pr view "$PR" "${REPO_ARG[@]}" --json state,mergeStateStatus,autoMergeRequest \
           --jq '"\(.state)|\(.mergeStateStatus)|\(.autoMergeRequest != null)"' 2>/dev/null || true)"
  [[ -n "$view" ]] || view="UNKNOWN|UNKNOWN|false"
  IFS='|' read -r state mergestate automerge <<<"$view"

  checks="$(gh pr checks "$PR" "${REPO_ARG[@]}" --json name,bucket 2>/dev/null || true)"
  [[ -n "$checks" ]] || checks='[]'

  tot=$(jq  'length'                                        <<<"$checks" 2>/dev/null || echo 0)
  pass=$(jq '[.[]|select(.bucket=="pass")]|length'          <<<"$checks" 2>/dev/null || echo 0)
  fail=$(jq '[.[]|select(.bucket=="fail")]|length'          <<<"$checks" 2>/dev/null || echo 0)
  cancel=$(jq '[.[]|select(.bucket=="cancel")]|length'      <<<"$checks" 2>/dev/null || echo 0)
  pend=$(jq '[.[]|select(.bucket=="pending")]|length'       <<<"$checks" 2>/dev/null || echo 0)
  waiting=$(jq -r '[.[]|select(.bucket=="pending")|.name]|join(",")' <<<"$checks" 2>/dev/null | cut -c1-90)
  red=$(jq -r '[.[]|select(.bucket=="fail" or .bucket=="cancel")|"\(.bucket):\(.name)"]|join(" ")' <<<"$checks" 2>/dev/null | cut -c1-160)

  # ── THE HEARTBEAT. Unconditional, before any terminal branch. This is the whole point of the
  # script: the healthy path emits too, so silence can only ever mean the monitor is dead.
  printf '[%s|%s|automerge=%s] %s/%s pass · %s fail · %s cancel · %s pending%s%s\n' \
    "$state" "$mergestate" "$automerge" "$pass" "$tot" "$fail" "$cancel" "$pend" \
    "${waiting:+ → }" "$waiting"
  [[ -n "$red" ]] && printf '    NON-PASS: %s\n' "$red"

  case "$state" in
    MERGED) printf 'MERGED — PR #%s landed (%s/%s pass, %s fail, %s cancel).\n' "$PR" "$pass" "$tot" "$fail" "$cancel"; exit 0 ;;
    CLOSED) printf 'CLOSED WITHOUT MERGE — PR #%s.\n' "$PR"; exit 1 ;;
  esac

  # Auto-merge silently switching off is a state the operator must hear about: the PR then sits
  # green and unmerged forever, which reads exactly like "still waiting".
  if [[ "$automerge" == "false" && "$state" == "OPEN" && "$tot" -gt 0 && "$pend" -eq 0 && "$fail" -eq 0 && "$cancel" -eq 0 ]]; then
    printf 'CHECKS SETTLED, ALL GREEN, AUTO-MERGE NOT ARMED — PR #%s needs an explicit merge.\n' "$PR"; exit 0
  fi

  if [[ "$tot" -gt 0 && "$pend" -eq 0 ]]; then
    if [[ "$fail" -gt 0 || "$cancel" -gt 0 ]]; then
      printf 'CHECKS SETTLED WITH NON-PASS — PR #%s: %s\n' "$PR" "$red"; exit 1
    fi
    # Green but still OPEN with auto-merge armed: keep watching for the merge itself, but say so
    # rather than looping silently.
    if [[ "$mergestate" == "BEHIND" ]]; then
      printf 'CHECKS GREEN BUT BEHIND — PR #%s needs a sync before it can merge.\n' "$PR"; exit 1
    fi
  fi

  if [[ "$n" -ge "$MAX_POLLS" ]]; then
    printf 'TIMEOUT — PR #%s still %s after %s polls (%ss apart); last: %s/%s pass, %s pending.\n' \
      "$PR" "$state" "$n" "$INTERVAL" "$pass" "$tot" "$pend"; exit 2
  fi
  sleep "$INTERVAL"
done
