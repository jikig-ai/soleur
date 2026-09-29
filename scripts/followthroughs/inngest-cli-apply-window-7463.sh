#!/usr/bin/env bash
# Follow-through verification for the #7463 apply-window tracker: after PR-A
# (#9201) bumped the committed CLI pin v1.19.4 -> v1.45.1, did the operator-gated
# live flip actually happen and stay healthy?
#
# The pin merge is host-inert by design — `terraform plan` renders the
# hcloud_server.inngest user_data diff but nothing applies it until a human
# dispatches `apply-web-platform-infra.yml` with `-f apply_target=inngest-host-replace`.
# That dispatch runs the `inngest_host_replace` job, which destroys and recreates
# the dedicated host; first boot downloads, sha256-verifies and runs the pinned
# tarball. This probe cannot observe the binary's `--version` (no host credential
# — and must not ask for one), so the predicate is the PAIR the window prescribes:
#
#   - an apply-web-platform-infra.yml run on main, event=workflow_dispatch, CREATED
#     STRICTLY AFTER the #9201 merge commit (anchored via the PR API, not
#     hardcoded), whose `inngest_host_replace` job ran to conclusion=success; AND
#   - the newest `scheduled-inngest-health.yml` run on main created after that
#     apply completed with conclusion=success — the post-replace health evidence
#     the apply-window sequence requires.
#
# Exit semantics (sweep-followthroughs.sh contract; followthrough-convention.md):
#   0 = PASS              both halves observed — the flip ran and the host reports
#                         healthy after it. Sweeper may close the tracker.
#   1 = FAIL              an inngest_host_replace job ran post-merge and FAILED or
#                         was cancelled, or the first post-replace health run
#                         failed — the window needs a human, not another sweep.
#   2 = NOT YET           no post-merge replace dispatch has reached a completed
#                         inngest_host_replace job, or no health run post-dates it
#                         yet. The normal state — the apply window is
#                         operator-scheduled and may sit for days.
#   3 = CANNOT ESTABLISH  a GitHub API read failed or returned a shape this probe
#                         does not recognise.
#   78 = refused to run under xtrace with GH_TOKEN set (#7797).
#
# Credential posture: the workflow token only (`secrets=GH_TOKEN`); the probe
# reads run/job metadata only.

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
APPLY_WF="apply-web-platform-infra.yml"
HEALTH_WF="scheduled-inngest-health.yml"

# Anchor: PR #9201's merge timestamp. Fail-closed if it cannot be read or the PR
# is not merged (a pre-merge probe should wait, not guess).
merged_at="$(gh api "repos/$REPO/pulls/9201" --jq .merged_at 2>/dev/null || true)"
if [[ -z "$merged_at" || "$merged_at" == "null" ]]; then
  echo "CANNOT-ESTABLISH: could not read PR #9201's merged_at" >&2
  exit 3
fi
echo "anchor: PR #9201 merged_at=$merged_at"

# Newest-first dispatch runs on main after the anchor. createdAt is re-checked
# client-side — never trust the filter alone (same discipline as
# git-data-boot-poll-8178.sh).
runs="$(gh api "repos/$REPO/actions/workflows/$APPLY_WF/runs?event=workflow_dispatch&branch=main&per_page=15" \
  --jq ".workflow_runs[] | select(.created_at > \"$merged_at\") | [.databaseId, .created_at, .conclusion] | @tsv" 2>/dev/null || true)"
if [[ -z "$runs" ]]; then
  echo "NOT-YET: no post-merge apply dispatches on main" >&2
  exit 2
fi

replace_run_id=""
replace_at=""
while IFS=$'\t' read -r rid created _concl; do
  [[ -n "$rid" ]] || continue
  jobs="$(gh api "repos/$REPO/actions/runs/$rid/jobs?per_page=100" \
    --jq '.jobs[] | select(.name | test("inngest.host.replace"; "i")) | .conclusion' 2>/dev/null || true)"
  [[ -n "$jobs" ]] || continue   # this dispatch was a different apply_target
  replace_run_id="$rid"; replace_at="$created"
  if printf '%s\n' "$jobs" | grep -qx 'success'; then
    echo "found successful inngest_host_replace job in run $rid ($created)"
  else
    echo "FAIL: inngest_host_replace job in run $rid concluded '${jobs//$'\n'/,}' — the apply window needs a human" >&2
    exit 1
  fi
  break
done <<< "$runs"

if [[ -z "$replace_run_id" ]]; then
  echo "NOT-YET: post-merge dispatches exist but none reached an inngest_host_replace job" >&2
  exit 2
fi

# Second half: the newest health run created AFTER the replace dispatch.
health="$(gh api "repos/$REPO/actions/workflows/$HEALTH_WF/runs?branch=main&per_page=10" \
  --jq ".workflow_runs[] | select(.created_at > \"$replace_at\") | [.databaseId, .created_at, .conclusion] | @tsv" 2>/dev/null | head -1 || true)"
if [[ -z "$health" ]]; then
  echo "NOT-YET: replace ran ($replace_run_id) but no health run post-dates it yet" >&2
  exit 2
fi
IFS=$'\t' read -r hid hcreated hconcl <<< "$health"
case "$hconcl" in
  success)
    echo "PASS: inngest-host-replace applied (run $replace_run_id) and scheduled-inngest-health is green after it (run $hid, $hcreated)"
    exit 0
    ;;
  null|""|in_progress|queued)
    echo "NOT-YET: health run $hid still in flight ($hcreated)" >&2
    exit 2
    ;;
  *)
    echo "FAIL: post-replace health run $hid concluded '$hconcl' ($hcreated)" >&2
    exit 1
    ;;
esac
