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
# Rule of thumb this encodes: SILENCE MUST NEVER BE THE HEALTHY SIGNAL. But "emit every poll
# unconditionally" over-corrects into the opposite failure — a 35-minute CI run at a 120s cadence
# is ~17 identical lines, and the Monitor tool auto-stops a watch that produces too many events, so
# over-emitting eventually reproduces silence by another route.
#
# The contract is therefore: emit on CHANGE, and emit a HEARTBEAT every --heartbeat-every polls
# even when nothing changed. Change tells the operator what moved; the heartbeat proves the watch
# is alive. Neither alone is sufficient — change-only is what went silent for 50 minutes, and
# every-poll is what gets throttled.
#
# Usage:
#   monitor-pr-checks.sh <pr-number> [--interval SECONDS] [--max-polls N]
#                        [--heartbeat-every N] [--repo OWNER/REPO]
#
# Emits one line per poll:
#   [OPEN|BLOCKED|automerge=true] 73/78 pass · 0 fail · 0 cancel · 2 pending → test-scripts,...
# and exactly one terminal line:
#   MERGED — ... | CLOSED WITHOUT MERGE — ... | CHECKS SETTLED — ... | TIMEOUT — ...
#
# Exit 0 on a merge or an all-green settle; 1 on a red/closed terminal; 2 on timeout;
# 3 on usage error. The caller's Monitor watch ends when this exits.
set -uo pipefail

PR=""; INTERVAL=120; MAX_POLLS=60; HEARTBEAT_EVERY=5; REPO_ARG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)  INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --max-polls) MAX_POLLS="${2:?--max-polls needs a value}"; shift 2 ;;
    --heartbeat-every) HEARTBEAT_EVERY="${2:?--heartbeat-every needs a value}"; shift 2 ;;
    --repo)      REPO_ARG=(--repo "${2:?--repo needs a value}"); shift 2 ;;
    -h|--help)   sed -n '41,58p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "monitor-pr-checks: unknown flag $1" >&2; exit 3 ;;
    *)           if [[ -n "$PR" ]]; then echo "monitor-pr-checks: unexpected argument $1" >&2; exit 3; fi
                 PR="$1"; shift ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "monitor-pr-checks: <pr-number> is required and must be numeric" >&2; exit 3; }
[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -ge 10 ]] || { echo "monitor-pr-checks: --interval must be an integer >= 10" >&2; exit 3; }
[[ "$MAX_POLLS" =~ ^[0-9]+$ && "$MAX_POLLS" -ge 1 ]] || { echo "monitor-pr-checks: --max-polls must be an integer >= 1" >&2; exit 3; }
[[ "$HEARTBEAT_EVERY" =~ ^[0-9]+$ && "$HEARTBEAT_EVERY" -ge 1 ]] || { echo "monitor-pr-checks: --heartbeat-every must be an integer >= 1" >&2; exit 3; }

n=0; prev_sig=""
while :; do
  n=$((n + 1))

  # `|| true` on BOTH probes and a literal fallback: a transient gh/network failure must not kill
  # the loop. A monitor that dies on one bad request is the silent failure one level up.
  view="$(gh pr view "$PR" "${REPO_ARG[@]}" --json state,mergeStateStatus,autoMergeRequest \
           --jq '"\(.state)|\(.mergeStateStatus)|\(.autoMergeRequest != null)"' 2>/dev/null || true)"
  probe_ok=1
  [[ -n "$view" ]] || { view="UNKNOWN|UNKNOWN|false"; probe_ok=0; }
  IFS='|' read -r state mergestate automerge <<<"$view"

  checks="$(gh pr checks "$PR" "${REPO_ARG[@]}" --json name,bucket 2>/dev/null || true)"
  [[ -n "$checks" ]] || { checks='[]'; probe_ok=0; }

  tot=$(jq  'length'                                        <<<"$checks" 2>/dev/null || echo 0)
  pass=$(jq '[.[]|select(.bucket=="pass")]|length'          <<<"$checks" 2>/dev/null || echo 0)
  fail=$(jq '[.[]|select(.bucket=="fail")]|length'          <<<"$checks" 2>/dev/null || echo 0)
  cancel=$(jq '[.[]|select(.bucket=="cancel")]|length'      <<<"$checks" 2>/dev/null || echo 0)
  pend=$(jq '[.[]|select(.bucket=="pending")]|length'       <<<"$checks" 2>/dev/null || echo 0)
  # `skipping` IS a documented gh bucket (pass|fail|pending|skipping|cancel) and it is part of the
  # array length. Counting it in `tot` but in none of the tallies made the pass fraction
  # unreachable on any PR with a path-filtered job: `1/3 pass` printed next to `ALL GREEN`.
  skip=$(jq '[.[]|select(.bucket=="skipping")]|length'      <<<"$checks" 2>/dev/null || echo 0)
  # The denominator is what CAN pass. Skipped checks are reported separately rather than folded in.
  gradable=$(( tot - skip ))
  waiting=$(jq -r '[.[]|select(.bucket=="pending")|.name]|join(",")' <<<"$checks" 2>/dev/null | cut -c1-90)
  red=$(jq -r '[.[]|select(.bucket=="fail" or .bucket=="cancel")|"\(.bucket):\(.name)"]|join(" ")' <<<"$checks" 2>/dev/null | cut -c1-160)

  # ── THE EMISSION DECISION, before any terminal branch. Emit when the observable state CHANGED,
  # and otherwise every HEARTBEAT_EVERY polls so a long quiet stretch still proves liveness. The
  # first poll always emits (prev is empty), so the operator sees a baseline immediately.
  # `waiting` and `red` are IN the signature: a re-run that swaps which check is pending, or a
  # different check failing at the same count, changes nothing numeric but changes what the
  # operator is waiting on. probe_ok is in it so repeated outages are not collapsed.
  sig="${probe_ok}|${state}|${mergestate}|${automerge}|${pass}|${tot}|${skip}|${fail}|${cancel}|${pend}|${waiting}|${red}"
  if [[ "$sig" != "${prev_sig:-}" ]]; then
    why=""
  elif [[ $(( n % HEARTBEAT_EVERY )) -eq 0 ]]; then
    why=" · unchanged, still watching"
  else
    why="SKIP"
  fi
  if [[ "$why" != "SKIP" ]]; then
    if [[ "$probe_ok" != "1" ]]; then
      # DEGRADED INPUT MUST NOT RENDER AS MEASURED INPUT. The fallbacks below are literals, not
      # readings; printing them in the same shape as real counts is the "a zero that does not say
      # what it means" class this repo fixed twice on the observability side.
      printf '[gh probe FAILED — state unknown] (poll %s/%s)%s\n' "$n" "$MAX_POLLS" "$why"
    else
      printf '[%s|%s|automerge=%s] %s/%s pass · %s fail · %s cancel · %s pending%s skipped · (poll %s/%s)%s%s%s\n' \
        "$state" "$mergestate" "$automerge" "$pass" "$gradable" "$fail" "$cancel" "$pend" \
        " · $skip" "$n" "$MAX_POLLS" \
        "${waiting:+ → }" "$waiting" "$why"
    fi
    [[ -n "$red" ]] && printf '    NON-PASS: %s\n' "$red"
  fi
  prev_sig="$sig"

  case "$state" in
    MERGED) printf 'MERGED — PR #%s landed (%s/%s pass, %s fail, %s cancel).\n' "$PR" "$pass" "$tot" "$fail" "$cancel"; exit 0 ;;
    CLOSED) printf 'CLOSED WITHOUT MERGE — PR #%s.\n' "$PR"; exit 1 ;;
  esac

  # Auto-merge silently switching off is a state the operator must hear about: the PR then sits
  # green and unmerged forever, which reads exactly like "still waiting".
  # `mergestate != DRAFT` is load-bearing: `gh pr view --json state` returns OPEN for a draft
  # (isDraft is a separate field this never queried), so without it a green DRAFT exited rc=0
  # telling the operator to merge a PR GitHub will refuse. Reachable mid-watch too — converting
  # back to draft disarms auto-merge, which is exactly this branch's condition.
  if [[ "$automerge" == "false" && "$state" == "OPEN" && "$mergestate" != "DRAFT" \
        && "$tot" -gt 0 && "$pend" -eq 0 && "$fail" -eq 0 && "$cancel" -eq 0 ]]; then
    printf 'CHECKS SETTLED, ALL GREEN, AUTO-MERGE NOT ARMED — PR #%s needs an explicit merge.\n' "$PR"; exit 0
  fi

  if [[ "$tot" -gt 0 && "$pend" -eq 0 ]]; then
    if [[ "$fail" -gt 0 || "$cancel" -gt 0 ]]; then
      # UNSTABLE/CLEAN + auto-merge armed means the failing check is NOT required — GitHub still
      # considers the PR mergeable and auto-merge is expected to land it. Exiting rc=1 there is a
      # false red that stops the operator watching a PR that is about to merge anyway.
      if [[ "$automerge" == "true" && ( "$mergestate" == "UNSTABLE" || "$mergestate" == "CLEAN" ) ]]; then
        printf 'NON-REQUIRED CHECK FAILED — PR #%s: %s · mergeState=%s, auto-merge still expected to land it; continuing to watch.\n' "$PR" "$red" "$mergestate"
      else
        printf 'CHECKS SETTLED WITH NON-PASS — PR #%s: %s\n' "$PR" "$red"; exit 1
      fi
    fi
    # Green but still OPEN with auto-merge armed: keep watching for the merge itself, but say so
    # rather than looping silently.
    # BEHIND and DIRTY are both "green, but a human has to do something", and both are reachable
    # WHILE auto-merge is armed — auto-merge does not resync a stale branch and cannot resolve a
    # conflict. FOUND BY DOGFOODING: the first cut handled BEHIND and not DIRTY, so watching a real
    # PR that went green-then-DIRTY kept polling a state that needed action. The bug was in the
    # branch the operator would read as "still working".
    case "$mergestate" in
      BEHIND)  printf 'CHECKS GREEN BUT BEHIND — PR #%s needs a sync before it can merge (auto-merge does not resync).\n' "$PR"; exit 1 ;;
      DIRTY)   printf 'CHECKS GREEN BUT DIRTY — PR #%s has a merge conflict; auto-merge cannot resolve it.\n' "$PR"; exit 1 ;;
      DRAFT)   printf 'CHECKS GREEN BUT DRAFT — PR #%s cannot merge until it is marked ready.\n' "$PR"; exit 1 ;;
      # BLOCKED with nothing pending means branch protection is unsatisfied by something OUTSIDE
      # the check list — a missing required review, a required context that never posts, a merge
      # queue. Auto-merge sits there indefinitely. It renders identically to CLEAN, which lands in
      # seconds: same line, opposite futures. That is the defect class this script exists to close,
      # and it is the sibling of the DIRTY miss found by dogfooding.
      BLOCKED) printf 'CHECKS GREEN BUT BLOCKED — PR #%s is held by branch protection outside the check list (a required review, an unposted required context, or a merge queue). Auto-merge will not resolve it.\n' "$PR"; exit 1 ;;
    esac
  fi

  if [[ "$n" -ge "$MAX_POLLS" ]]; then
    # The TIMEOUT line must not fabricate counts either — it was the last place a total gh outage
    # still rendered `0/0 pass, 0 pending` as if measured.
    if [[ "$probe_ok" != "1" ]]; then
      printf 'TIMEOUT — PR #%s: the gh probe FAILED on the final poll, so no state was measured (%s polls, %ss apart). This is an unreachable GitHub, not a quiet PR.\n' \
        "$PR" "$n" "$INTERVAL"; exit 2
    fi
    printf 'TIMEOUT — PR #%s still %s after %s polls (%ss apart); last: %s/%s pass, %s skipped, %s pending.\n' \
      "$PR" "$state" "$n" "$INTERVAL" "$pass" "$gradable" "$skip" "$pend"; exit 2
  fi
  sleep "$INTERVAL"
done
