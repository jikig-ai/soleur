#!/usr/bin/env bash
# Verification half of .github/workflows/merge-queue-cla-synthetics.yml (#9454).
#
# `cla-check` and `cla-evidence` are required by the CLA Required ruleset but are produced by
# pull_request_target / issue_comment workflows that cannot run on a merge_group event. The
# synthetics workflow therefore re-reports them on the merge-queue candidate, and it must do
# so ONLY when the real results on the PR head are green. This script is that proof; it
# exits 0 only then, and the workflow's posting step runs after it. Every other outcome
# (bad input, gh failure, missing or red or still-running context) exits non-zero.
#
# Inputs (environment; the workflow routes event data through env vars, never inline):
#   GH_TOKEN   token for gh (the job's GITHUB_TOKEN; needs checks:read, pull-requests:read)
#   REPO       owner/name
#   HEAD_REF   github.event.merge_group.head_ref, refs/heads/gh-readonly-queue/main/pr-<N>-<sha>
#   HEAD_SHA   github.event.merge_group.head_sha (the candidate commit), 40 hex
#   BASE_REF   github.event.merge_group.base_ref, must be refs/heads/main
#
# Checks, in order, each failing closed:
#   1. strict shapes for REPO, HEAD_SHA, BASE_REF and HEAD_REF (PR number parsed from HEAD_REF),
#      all validated BEFORE any API call; unvalidated event text is never echoed
#   2. the PR exists, targets main, and exposes a 40-hex head sha
#   3. on that head, the LATEST check-run per name (highest id) of cla-check and of cla-evidence,
#      from the github-actions app (integration 15368, the identity the ruleset matches), is
#      completed/success. The PR-event workflows leave several runs per name; an old red followed
#      by a newer green passes and the reverse fails. The newest run is the highest id, NOT the
#      latest started_at: a queued re-run has started_at null and would sort OLDEST, letting a
#      stale success mask a re-run still pending (plugins/soleur/scripts/admin-merge-ready.sh
#      documents the same choice). Bot PRs carry the composite action's synthetic runs under the
#      same app.
#
# On ANY failure the script also appends one fixed-text `reason=<message>` line to
# $GITHUB_OUTPUT (when set) so the workflow's failure-post step can name the reason on the
# failing check-runs it posts. The message is the die() text only (never event data).
#
# No "PR head is a parent of the candidate" check, by design: with merge_method SQUASH the candidate
# is a single-parent squash commit (parent = previous candidate; measured on pr-5798), so it can never
# pass, and a push to a queued PR dequeues it, so the head cannot change after the real checks.
#
# Entry-gate premise (GitHub docs, "Managing a merge queue"): a PR can be added to the queue only
# after passing all required branch protection checks. This script does not rely on it; it
# re-reads the real results.
#
# The script is READ-ONLY: it never posts. Run it from a checkout of the DEFAULT branch, never
# from the candidate, because the posting step holds a checks:write token.
set -euo pipefail

die() {
  echo "::error::merge-queue-cla-verify: $*"
  [[ -z "${GITHUB_OUTPUT:-}" ]] || printf 'reason=%s\n' "$*" >> "$GITHUB_OUTPUT"
  exit 1
}

# Validate every input before touching the API. Messages are fixed text: event data
# (head_ref) can carry newlines, so it is never echoed back.
[[ -n "${REPO:-}" ]] || die "REPO is empty"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "REPO is not owner/name"
[[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || die "head_sha is not 40 lowercase hex characters"
[[ "${BASE_REF:-}" == "refs/heads/main" ]] || die "merge_group base_ref is not refs/heads/main"
[[ "${HEAD_REF:-}" =~ ^refs/heads/gh-readonly-queue/main/pr-([0-9]+)-([0-9a-f]{40})$ ]] \
  || die "head_ref does not match refs/heads/gh-readonly-queue/main/pr-<N>-<40 hex>"
pr="${BASH_REMATCH[1]}"

# gh_read <label> <gh api args...> : the reply lands in $REPLY_JSON. Not a command substitution,
# because die inside one would print into the captured variable and be swallowed. A gh failure is
# retried ONCE after a short pause (a transient 5xx must not eject a healthy PR from the queue), and
# a second failure is fatal and names the endpoint kind (never read as an empty answer): bounded,
# fail closed. Worst case 2 x (60 s + pause) per read, inside the workflow's 5-minute job budget.
# MQ_VERIFY_RETRY_DELAY (seconds, 0-60) is a test seam; the workflow does not set it.
RETRY_DELAY=3
[[ "${MQ_VERIFY_RETRY_DELAY:-}" =~ ^[0-9]{1,2}$ ]] && RETRY_DELAY="$((10#$MQ_VERIFY_RETRY_DELAY))"
REPLY_JSON=""
gh_read() {
  local label="$1" attempt
  shift
  for attempt in 1 2; do
    if REPLY_JSON="$(timeout 60 gh api "$@")"; then return 0; fi
    [[ "$attempt" -eq 2 ]] || sleep "$RETRY_DELAY"
  done
  die "gh api failed reading ${label} for PR #${pr}"
}

gh_read "the PR" "repos/${REPO}/pulls/${pr}"
pr_json="$REPLY_JSON"
pr_head="$(jq -er '.head.sha' <<<"$pr_json")" || die "PR #${pr} reply has no head sha"
[[ "$pr_head" =~ ^[0-9a-f]{40}$ ]] || die "PR #${pr} head sha is not 40 lowercase hex characters"
pr_base="$(jq -er '.base.ref' <<<"$pr_json")" || die "PR #${pr} reply has no base ref"
[[ "$pr_base" == "main" ]] || die "PR #${pr} base is not main"

# `gh api --paginate` prints one JSON object per page, concatenated with no outer array, so the
# reply is slurped (-s) and every page's check_runs read.
gh_read "the PR head check-runs" --paginate "repos/${REPO}/commits/${pr_head}/check-runs?filter=all&per_page=100"
runs="$REPLY_JSON"

# shellcheck disable=SC2016  # a jq program: $n is a jq variable, not a shell expansion
latest_program='[.[].check_runs[]? | select(.name == $n and .app.id == 15368)]
  | sort_by(.id)
  | last
  | if . == null then "missing" else "\(.status)/\(.conclusion)" end'

for ctx in cla-check cla-evidence; do
  verdict="$(jq -rs --arg n "$ctx" "$latest_program" <<<"$runs")" \
    || die "cannot read the ${ctx} check-runs of PR #${pr}"
  verdict="$(printf '%s' "$verdict" | tr -cd 'A-Za-z0-9/_')"
  [[ "$verdict" == "completed/success" ]] \
    || die "${ctx} on PR #${pr} head is ${verdict:-unreadable}, not completed/success"
done

echo "merge-queue-cla-verify=OK pr=${pr} head=${pr_head}"
