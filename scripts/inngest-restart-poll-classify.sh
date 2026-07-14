#!/usr/bin/env bash
# inngest-restart-poll-classify.sh — pure decision functions for the restart-verify
# poll loop in .github/workflows/restart-inngest-server.yml (#6407, code-review Finding B).
# SOURCED by that workflow's "Verify restart completion" step (via $GITHUB_WORKSPACE)
# AND by scripts/inngest-restart-poll-classify.test.sh. No network, no side effects:
# inputs are already-fetched values and each function echoes exactly one token. The
# workflow keeps the curl I/O and the side effects (::notice/::error, jq echo, exit,
# only_lock_contention flag) in the step; only the classification/adjudication logic
# lives here so it is deterministically unit-testable. Behavior-preserving extraction —
# the poll loop was verified correct by architecture-strategist before extraction.

# classify_restart_frame — per-poll verdict for one deploy-status frame. Mirrors the
# workflow's `case "$EXIT_CODE"` block (the freshness guard, the exit_code sentinels,
# and the lock_contention/terminal split) EXACTLY. Echoes one of:
#   success          exit_code==0, component==inngest, start_ts>=fresh_floor  (loop: exit 0)
#   predates         a fresh-floor miss for component==inngest (exit 0 OR failure) (loop: wait)
#   other_component  component!=inngest (exit 0 OR failure)                    (loop: wait)
#   still_running    exit_code==-1                                            (loop: wait)
#   no_prior         exit_code==-2                                            (loop: wait)
#   corrupt          exit_code==-3                                            (loop: wait)
#   lock_contention  failure + inngest + fresh + reason==lock_contention      (loop: set flag, keep polling)
#   terminal_fail    failure + inngest + fresh + reason!=lock_contention      (loop: exit 1)
# The `*)` default (which the workflow's `.exit_code // -99` sentinel falls into) is the
# failure branch — preserved here.
#   $1 = exit_code   $2 = component   $3 = start_ts   $4 = fresh_floor   $5 = reason
classify_restart_frame() {
  local exit_code="$1" component="$2" start_ts="$3" fresh_floor="$4" reason="$5"
  case "$exit_code" in
    0)
      if [ "$component" = "inngest" ]; then
        if [ "$start_ts" -lt "$fresh_floor" ]; then
          echo "predates"
        else
          echo "success"
        fi
      else
        echo "other_component"
      fi
      ;;
    -1) echo "still_running" ;;
    -2) echo "no_prior" ;;
    -3) echo "corrupt" ;;
    *)
      if [ "$component" = "inngest" ]; then
        if [ "$start_ts" -lt "$fresh_floor" ]; then
          echo "predates"
        elif [ "$reason" = "lock_contention" ]; then
          echo "lock_contention"
        else
          echo "terminal_fail"
        fi
      else
        echo "other_component"
      fi
      ;;
  esac
}

# deploy_status_confirms_fresh_inngest — budget-expiry adjudicator #1 (mirrors the
# workflow's final deploy-status re-read, EXACTLY). Echoes "yes" iff the re-read is a
# 200 + valid JSON whose .component==inngest, .exit_code==0, and .start_ts (numeric,
# defaulting to 0 on a non-numeric read via the `-eq self` guard) >= fresh_floor.
# Else "no".
#   $1 = final_http_code   $2 = final_body (JSON string)   $3 = fresh_floor
deploy_status_confirms_fresh_inngest() {
  local final_http_code="$1" final_body="$2" fresh_floor="$3"
  if [ "$final_http_code" = "200" ] && echo "$final_body" | jq -e . >/dev/null 2>&1; then
    local f_exit f_component f_start
    f_exit=$(echo "$final_body" | jq -r '.exit_code // -99')
    f_component=$(echo "$final_body" | jq -r '.component // "unknown"')
    f_start=$(echo "$final_body" | jq -r '.start_ts // 0')
    [ "$f_start" -eq "$f_start" ] 2>/dev/null || f_start=0
    if [ "$f_component" = "inngest" ] && [ "$f_exit" = "0" ] && [ "$f_start" -ge "$fresh_floor" ]; then
      echo "yes"
      return 0
    fi
  fi
  echo "no"
}

# liveness_confirms_healthy — budget-expiry adjudicator #2 (mirrors the workflow's
# /hooks/inngest-liveness re-read, EXACTLY). Echoes "yes" iff a 200 + a JSON object
# whose .functions is a NON-EMPTY array. The non-empty requirement is load-bearing: a
# cold-start empty registry must NOT confirm a superseded restart as current. Else "no".
#   $1 = live_http_code   $2 = live_body (JSON string)
liveness_confirms_healthy() {
  local live_http_code="$1" live_body="$2"
  if [ "$live_http_code" = "200" ] && echo "$live_body" | jq -e 'type == "object" and (.functions | type == "array") and (.functions | length > 0)' >/dev/null 2>&1; then
    echo "yes"
  else
    echo "no"
  fi
}
