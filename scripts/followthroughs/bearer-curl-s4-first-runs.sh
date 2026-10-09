#!/usr/bin/env bash
# Follow-through verification: the first real runs of the S4 credential conversions.
#
# PR #9893 (slice S4 of the argv-credential sweep, tracker #9597) moved the credentials of the
# push-triggered production-class workflows, composites and scripts off curl's (and openssl's, and
# git's) argument list. The suites drive their real bodies against a recording curl; only a real run
# proves them against the real vendors. Several of the converted files are exercised rarely or
# only by a manual dispatch, so this probe tracks each one's FIRST real run.
#
# PASS (0)    every tracked workflow has at least one completed run since the merge that concluded
#             `success`, and NO run since the merge printed a credential-refusal marker.
# FAIL (1)    a run since the merge printed a SOLEUR_CREDENTIAL_REFUSED line (a stored credential
#             was refused: its alphabet or a stray control byte), a rotation or storage problem the
#             suites cannot see. The marker, not the conclusion, is the failure: a dispatch-only
#             workflow may fail for reasons that have nothing to do with this change.
# NOT YET (2) some workflow has not run clean yet, and the wait budget (merge + 30 days) is open.
# ACTION REQUIRED (5)
#             the wait budget has run out and some workflow was never exercised clean. The tracker
#             is then closed by an operator after either a sanctioned read-only dispatch of that
#             workflow or an explicit acceptance comment on the tracker (this probe never closes it
#             in that state).
# CANNOT ESTABLISH (3) a gh call failed or returned an unexpected shape (the sweeper retries).
# NOT YET (2) also covers a PR that is not merged yet.
#
# Credential posture: needs GH_TOKEN (declared in the directive's secrets= clause) to read run
# lists and logs; it holds no vendor credential.
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
#
# RETIREMENT: when the tracker closes, delete this file; nothing else references it.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797): GH_TOKEN is in the environment and -x would print it.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe holds GH_TOKEN and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

PR=9893
WAIT_DAYS=30
# The converted workflows (a workflow name is the file's basename). Scheduled or push-triggered ones
# run on their own; the dispatch-only and event-driven ones wait for their first real use.
WORKFLOWS=(
  scheduled-inngest-health.yml
  apply-inngest-rls.yml
  apply-deploy-pipeline-fix.yml
  apply-web-platform-infra.yml
  web-platform-release.yml
  build-inngest-bootstrap-image.yml
  mint-inngest-bootstrap-tag.yml
  apply-github-infra.yml
  restart-inngest-server.yml
  deploy-inngest-image.yml
  workspaces-luks-cutover.yml
  git-data-cutover.yml
)
MARKER_RE='SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+ reason='
RUNS_PER_WORKFLOW=6

merged_at="$(gh pr view "$PR" --json mergedAt --jq '.mergedAt // empty' 2>/dev/null)" \
  || { echo "TRANSIENT: could not read PR #$PR" >&2; exit 3; }
[[ -n "$merged_at" ]] || { echo "NOT YET: PR #$PR is not merged yet" >&2; exit 2; }
# gh --jq takes no --arg, so the timestamp is interpolated: refuse anything but an ISO-8601 instant.
[[ "$merged_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$ ]] \
  || { echo "TRANSIENT: unexpected mergedAt shape" >&2; exit 3; }

deadline_epoch="$(date -u -d "$merged_at + $WAIT_DAYS days" +%s 2>/dev/null)" \
  || { echo "TRANSIENT: could not compute the wait deadline" >&2; exit 3; }
now_epoch="$(date -u +%s)"

LOG="$(mktemp -t bearer-curl-s4-first-runs.XXXXXXXX.log)" || { echo "TRANSIENT: mktemp failed" >&2; exit 3; }
trap 'rm -f "$LOG"' EXIT

refused=0
unexercised=()
for wf in "${WORKFLOWS[@]}"; do
  rows="$(gh run list --workflow "$wf" --status completed -L 50 \
    --json databaseId,conclusion,createdAt \
    --jq "[.[] | select(.createdAt > \"$merged_at\")] | sort_by(.createdAt) | .[:$RUNS_PER_WORKFLOW] | .[] | \"\(.databaseId) \(.conclusion)\"" \
    2>/dev/null)" || { echo "TRANSIENT: could not list runs of $wf" >&2; exit 3; }
  clean=0
  seen=0
  while read -r run_id conclusion; do
    [[ -n "${run_id:-}" ]] || continue
    [[ "$run_id" =~ ^[0-9]+$ ]] || { echo "TRANSIENT: unexpected run id for $wf" >&2; exit 3; }
    seen=$((seen + 1))
    gh run view "$run_id" --log > "$LOG" 2>/dev/null \
      || { echo "TRANSIENT: could not read the log of $wf run $run_id" >&2; exit 3; }
    markers="$(grep -cE "$MARKER_RE" "$LOG" || true)"
    if [[ "${markers:-0}" != "0" ]]; then
      echo "FAIL: $wf run $run_id printed $markers credential-refusal marker line(s)"
      refused=$((refused + 1))
    elif [[ "$conclusion" == "success" ]]; then
      clean=$((clean + 1))
    fi
  done <<< "$rows"
  if (( clean > 0 )); then
    echo "ok:   $wf has $clean clean successful run(s) since the merge ($merged_at)"
  else
    echo "wait: $wf has no clean successful run since the merge ($seen completed run(s) seen)"
    unexercised+=("$wf")
  fi
done

if (( refused > 0 )); then exit 1; fi
if (( ${#unexercised[@]} == 0 )); then
  echo "PASS: every tracked workflow ran clean since the merge, and no run printed a refusal marker"
  exit 0
fi
if (( now_epoch >= deadline_epoch )); then
  echo "ACTION REQUIRED: the ${WAIT_DAYS}-day wait budget since the merge is spent and these were never exercised clean: ${unexercised[*]}. Exercise each with a sanctioned read-only dispatch (a dispatch that writes needs its own approval) or accept it explicitly on the tracker, then close it and remove the follow-through label."
  exit 5
fi
echo "NOT YET: ${#unexercised[@]} workflow(s) have not run clean yet: ${unexercised[*]}"
exit 2
