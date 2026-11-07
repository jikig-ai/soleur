#!/usr/bin/env bash
# scripts/lib/umbrella-member.sh — the ONE canonical member() verdict arbiter
# for the umbrella jobs (#12089 fold; dedup fix is #12276 nit 2). Sourced —
# never executed — by the `aggregate` step of every umbrella job, via:
#
#   source "${GITHUB_WORKSPACE:?}/scripts/lib/umbrella-member.sh" || { ...; exit 1; }
#
# Umbrella census (scripts/lint-umbrella-aggregate.sh pins it, incl. the
# source-line presence and the absence of an inline member() body in the
# workflow run blocks):
#   ci.yml                 guards-ruleset, guards-advisory
#   pr-quality-guards.yml  quality-guards, quality-advisory
#   secret-scan.yml        secret-guards
#
# Contract: member <name> <scope> <id-csv> <conclusion-csv> <outcome-csv>.
# Per member: any failed/cancelled step FAILs the member; all-skipped on an
# event the member covers (scope `*` = every event this workflow fires on, and
# every member here is unconditional) FAILs it too — a member may never report
# a skip as a pass. `outcome` is printed where it differs from `conclusion`
# (continue-on-error honesty; no member here carries it, but the aggregate
# stays truthful if one is added). Reads $EVENT_NAME from the step env at call
# time. Callers run it under `set -uo pipefail` as `member ... || failed=1`.
member() {
  local mname="$1" scope="$2" ids="$3" concs="$4" outs="$5"
  local -a ida ca oa
  IFS=',' read -ra ida <<<"$ids"
  IFS=',' read -ra ca <<<"$concs"
  IFS=',' read -ra oa <<<"$outs"
  local any_fail=0 any_run=0 detail="" i c o
  for i in "${!ida[@]}"; do
    c="${ca[$i]:-unknown}"; o="${oa[$i]:-$c}"
    [ -z "$o" ] && o="$c"
    if [ "$o" != "$c" ]; then detail+=" ${ida[$i]}=${c}(${o})"; else detail+=" ${ida[$i]}=${c}"; fi
    case "$c" in
      success) any_run=1 ;;
      skipped) ;;
      *) any_fail=1 ;;  # failure, cancelled, or unreadable — all fail closed
    esac
  done
  if [ "$any_fail" -eq 1 ]; then
    printf 'FAIL  %-30s%s\n' "$mname" "$detail"; return 1
  fi
  if [ "$any_run" -eq 1 ]; then
    printf 'PASS  %-30s%s\n' "$mname" "$detail"; return 0
  fi
  if [ "$scope" = "*" ] || [[ ",$scope," == *",$EVENT_NAME,"* ]]; then
    printf 'FAIL  %-30s%s  (owed a verdict on %s; every member step skipped)\n' "$mname" "$detail" "$EVENT_NAME"
    return 1
  fi
  printf 'SKIP  %-30s%s  (out of scope on %s)\n' "$mname" "$detail" "$EVENT_NAME"
}
