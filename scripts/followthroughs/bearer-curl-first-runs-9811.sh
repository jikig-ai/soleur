#!/usr/bin/env bash
# Follow-through verification: the first scheduled runs after PR #9811 merged.
#
# PR #9811 (slice S3 of the argv-credential sweep, tracker #9597) moved the credentials of ten
# workflows and two composite actions off curl's argument list and onto its stdin config, through
# scripts/lib/bearer-curl.sh. The suites prove the call sites against a recording curl; only a real
# scheduled run proves them against the real vendors. This probe PASSES when, for each converted
# workflow that runs on a schedule, the first completed scheduled run after the merge concluded
# `success` and printed no credential-refusal marker. A refusal marker means the library rejected a
# stored credential (its alphabet or a stray control byte) -- a rotation or storage problem the
# suites cannot see.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS (every scheduled workflow ran clean since the merge)
#   1 = FAIL (a scheduled run failed, or printed a refusal marker)
#   * = TRANSIENT (not merged yet, a workflow has not run yet, or the GitHub API failed)
#
# Needs GH_TOKEN (declared in the directive's secrets= clause).
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797): GH_TOKEN is in the environment and -x would print it.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe holds GH_TOKEN and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

PR=9811
# The converted workflows that run on a schedule. The others are dispatch or pull_request triggered
# and are covered by the suites.
WORKFLOWS=(scheduled-inngest-health.yml scheduled-prod-version-drift.yml kb-drift-walker.yml rule-audit.yml)
MARKER_RE='SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+ reason='

merged_at="$(gh pr view "$PR" --json mergedAt --jq '.mergedAt // empty' 2>/dev/null)" \
  || { echo "TRANSIENT: could not read PR #$PR" >&2; exit 2; }
[[ -n "$merged_at" ]] || { echo "TRANSIENT: PR #$PR is not merged yet" >&2; exit 2; }
# gh --jq takes no --arg, so the timestamp is interpolated: refuse anything but an ISO-8601 instant.
[[ "$merged_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$ ]] \
  || { echo "TRANSIENT: unexpected mergedAt shape" >&2; exit 2; }

LOG="$(mktemp -t bearer-curl-first-runs.XXXXXXXX.log)" || { echo "TRANSIENT: mktemp failed" >&2; exit 2; }
trap 'rm -f "$LOG"' EXIT

failed=0
waiting=0
for wf in "${WORKFLOWS[@]}"; do
  row="$(gh run list --workflow "$wf" --event schedule --status completed -L 100 \
    --json databaseId,conclusion,createdAt \
    --jq "[.[] | select(.createdAt > \"$merged_at\")] | sort_by(.createdAt) | first // empty | \"\(.databaseId) \(.conclusion)\"" \
    2>/dev/null)" || { echo "TRANSIENT: could not list runs of $wf" >&2; exit 2; }
  if [[ -z "$row" ]]; then
    echo "wait: $wf has no completed scheduled run since the merge ($merged_at)"
    waiting=$((waiting + 1))
    continue
  fi
  run_id="${row%% *}"
  conclusion="${row##* }"
  [[ "$run_id" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: unexpected run id for $wf" >&2; exit 2; }
  if [[ "$conclusion" != "success" ]]; then
    echo "FAIL: $wf run $run_id concluded '$conclusion'"
    failed=$((failed + 1))
    continue
  fi
  gh run view "$run_id" --log > "$LOG" 2>/dev/null \
    || { echo "TRANSIENT: could not read the log of $wf run $run_id" >&2; exit 2; }
  markers="$(grep -cE "$MARKER_RE" "$LOG" || true)"
  if [[ "${markers:-0}" != "0" ]]; then
    echo "FAIL: $wf run $run_id printed $markers credential-refusal marker line(s)"
    failed=$((failed + 1))
    continue
  fi
  echo "ok:   $wf run $run_id succeeded with no refusal marker"
done

if (( failed > 0 )); then exit 1; fi
if (( waiting > 0 )); then echo "TRANSIENT: $waiting workflow(s) have not run yet" >&2; exit 2; fi
echo "PASS: every scheduled converted workflow ran clean since the merge"
exit 0
