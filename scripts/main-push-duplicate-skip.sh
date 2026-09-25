#!/usr/bin/env bash
# main-push-duplicate-skip.sh <workflow-file> <merge-sha> [required-job-prefix ...]
#
# Prints exactly one line:  duplicate=true  OR  duplicate=false   (exit 0 always).
#
# Emits true ONLY when a push run of the named workflow would byte-identically
# re-run what already ran green on the merged PR's head:
#   1. a merged PR's merge_commit_sha == the push SHA  (association is real)
#   2. tree(PR head) == tree(merge commit)            (squash of up-to-date ⇒
#      equal; stale-base, merge-order and drift all prove false)
#   3. THIS workflow's latest completed pull_request run at that head == success
#      (the check actually ran on that tree — a paths-filtered or cancelled
#      latest run is not coverage)
#   4. every required-job prefix resolves to >=1 job, ALL conclusion==success
#      (a SKIPPED heavy job is not coverage — e.g. the tenant suite, the vendor
#      blob verify)
# Every API failure, empty lookup, or ambiguity emits duplicate=false — the
# caller runs the workflow. Skipping on ambiguity is never allowed.
#
# Scope: the caller's event gate (push vs PR/dispatch) lives in the workflow;
# this script is event-agnostic.
set -uo pipefail   # NOT -e: every error path must emit false, not die mid-proof

emit() { echo "duplicate=$1"; }

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY unset}"
WF="$1"; SHA="$2"; shift 2

# 1. PR association. `pulls` also returns commits a PR merely contains; bind on
#    merge_commit_sha == SHA so a stacked/rebase-range PR cannot match.
prs="$(gh api "repos/${REPO}/commits/${SHA}/pulls" 2>/dev/null)" || { emit false; exit 0; }
head="$(jq -r --arg sha "$SHA" \
  '[.[] | select(.merged_at != null and .merge_commit_sha == $sha)][0].head.sha // empty' \
  <<<"$prs")"
[ -n "$head" ] || { emit false; exit 0; }

# 2. Tree identity — the load-bearing proof.
head_tree="$(gh api "repos/${REPO}/git/commits/${head}" --jq .tree.sha 2>/dev/null)" || { emit false; exit 0; }
merge_tree="$(gh api "repos/${REPO}/git/commits/${SHA}" --jq .tree.sha 2>/dev/null)" || { emit false; exit 0; }
[ -n "$head_tree" ] && [ "$head_tree" = "$merge_tree" ] || { emit false; exit 0; }

# 3. This workflow's own latest completed pull_request run at the head must be green.
run_id="$(gh api "repos/${REPO}/actions/workflows/${WF}/runs?head_sha=${head}&event=pull_request&per_page=10" \
  --jq '[.workflow_runs[] | select(.status=="completed")] | .[0] | select(.conclusion=="success") | .id // empty' \
  2>/dev/null)" || { emit false; exit 0; }
[ -n "$run_id" ] || { emit false; exit 0; }

# 4. Required jobs must have EXECUTED successfully (skipped != coverage).
#    Match is exact-or-"<prefix> <shard-suffix>" ('deploy-script-tests' matches
#    'deploy-script-tests (1/4)' but NOT 'deploy-script-tests-done').
for prefix in "$@"; do
  ok="$(gh api "repos/${REPO}/actions/runs/${run_id}/jobs?per_page=100" \
    --arg p "$prefix" \
    --jq '[.jobs[] | select(.name == $p or (.name | startswith($p + " ")))  ] | if length==0 then "missing" elif all(.[]; .conclusion=="success") then "ok" else "bad" end' \
    2>/dev/null)" || { emit false; exit 0; }
  [ "$ok" = "ok" ] || { emit false; exit 0; }
done
emit true
