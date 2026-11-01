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
# The ref-embedded oid is minted when the group is (re)created and legitimately diverges from
# HEAD_SHA whenever the candidate is rebuilt (a shallower member landing, a re-enqueue, or a
# deeper member joining). Refusing the pairing ejects healthy entries — the authoritative
# binding is each entry's headCommit.oid == HEAD_SHA below; the embedded oid is provenance.
embedded="${BASH_REMATCH[2]}"

# gh_read <label> <gh api args...> : the reply lands in $REPLY_JSON. Not a command substitution,
# because die inside one would print into the captured variable and be swallowed. A gh failure is
# retried ONCE after a short pause (a transient 5xx must not eject a healthy PR from the queue), and
# a second failure is fatal and names the endpoint kind (never read as an empty answer): bounded,
# fail closed. Worst case (1 entries read + up to 3 member reads) x 2 attempts x (25 s + pause)
# fits inside the verify step's timeout-minutes: 4, which itself fires the failure-post — a
# job-level cancellation would not reach `if: failure()`.
# MQ_VERIFY_RETRY_DELAY (seconds, 0-99, matching the regex below) is a test seam; the workflow does not set it.
RETRY_DELAY=3
[[ "${MQ_VERIFY_RETRY_DELAY:-}" =~ ^[0-9]{1,2}$ ]] && RETRY_DELAY="$((10#$MQ_VERIFY_RETRY_DELAY))"
REPLY_JSON=""
gh_read() {
  local label="$1" attempt
  shift
  for attempt in 1 2; do
    if REPLY_JSON="$(timeout 25 gh api "$@")"; then return 0; fi
    [[ "$attempt" -eq 2 ]] || sleep "$RETRY_DELAY"
  done
  die "gh api failed reading ${label} for PR #${pr}"
}

# --- group membership enumeration (#11678, ADR-270 raise checklist) -----------
# The candidate HEAD_SHA is the cumulative merge commit built for the DEEPEST
# member of the group it verifies: with merge_method SQUASH each queue position
# dispatches its own merge_group run whose candidate contains every shallower
# member's changes. The members of THIS candidate are therefore the queue
# entries at positions <= the position of the entry whose candidate IS
# HEAD_SHA. The anchor is bound via headCommit.oid — never by name alone — so a
# mid-verify queue renumbering (jump insertion at position 1, member ejection)
# cannot silently rename the set being verified; if no listed entry owns
# HEAD_SHA, positions <= the named PR's entry position is the fallback, and if
# neither resolves the script dies (an unverifiable set is never a pass).
#
# Invariants, each fail-closed:
#   * entries(first:100) pagination fully consumed — hasNextPage=true dies
#     (a truncated page under-enumerates the member list silently)
#   * the member set is non-empty (a `0 checked` enumeration is a failure,
#     not a pass — the anti-vacuity row in the plan's Guard Contract)
#   * the named PR appears in the member set AND is its maximal position
#     (if head_ref ever names a non-deepest member, positions<= would
#     silently skip the group's tail — that is the under-enumeration hole)
MQ_QUERY='query($o:String!,$n:String!){
  repository(owner:$o,name:$n){
    mergeQueue(branch:"main"){ entries(first:100){
      pageInfo{ hasNextPage }
      nodes{ position headCommit{ oid } pullRequest{ number headRefOid } } } }
  }
}'
gh_read "merge queue entries" graphql -f query="$MQ_QUERY" -F o="${REPO%%/*}" -F n="${REPO##*/}"
entries="$REPLY_JSON"

[[ "$(jq -er '.data.repository.mergeQueue.entries.pageInfo.hasNextPage' <<<"$entries")" == "false" ]] \
  || die "merge queue entries list is paginated beyond first:100 — refusing a truncated member set"

# anchor: the entry whose candidate is HEAD_SHA. Fallback: the named PR's entry —
# allowed only when its own headCommit is absent or also HEAD_SHA; a named entry
# whose headCommit differs means the verified candidate belongs to a DEEPER entry
# and positions<=named would silently under-enumerate the tail.
anchor_pos="$(jq -er --arg sha "$HEAD_SHA" --argjson pr "$pr" '
  .data.repository.mergeQueue.entries.nodes
  | ([.[] | select(.headCommit.oid == $sha) | .position] | first)
    // ([.[] | select(.pullRequest.number == $pr)
         | if ((.headCommit.oid // "") != "" and .headCommit.oid != $sha)
           then "mismatch" else .position end] | first)
    // empty' <<<"$entries")" \
  || die "cannot bind merge_group candidate to queue membership for PR #${pr}"
[[ "$anchor_pos" != "mismatch" ]] \
  || die "named PR #${pr} does not own candidate ${HEAD_SHA} — head_ref names a non-deepest member, refusing partial verification"
anchor_kind="headCommit"
[[ "$(jq -er --arg sha "$HEAD_SHA" '[.data.repository.mergeQueue.entries.nodes[] | select(.headCommit.oid == $sha)] | length' <<<"$entries")" -ge 1 ]] \
  || anchor_kind="named-fallback"

# members: every entry at position <= anchor — each carries its OWN recorded
# queued head (headRefOid is the entry's head at enqueue; a pushed PR would
# have been dequeued, so it is the head the candidate contains)
members="$(jq -ec --argjson pos "$anchor_pos" '
  [.data.repository.mergeQueue.entries.nodes[]
   | select(.position <= $pos)
   | {number: .pullRequest.number, head: .pullRequest.headRefOid, pos: .position}]
  | sort_by(.pos)' <<<"$entries")" \
  || die "cannot enumerate queue members for candidate ${HEAD_SHA}"
member_count="$(jq -r 'length' <<<"$members")"
[[ "$member_count" -ge 1 ]] || die "zero queue members enumerated for candidate ${HEAD_SHA} — refusing a vacuous pass"
[[ "$member_count" == "$anchor_pos" ]] \
  || die "member set (${member_count}) is not contiguous with the anchor position (${anchor_pos}) — a gapped or null position would silently drop a member"

# the named PR must be a member and its position maximal (deepest member)
max_pos="$(jq -r '[.[].pos] | max' <<<"$members")"
named_pos="$(jq -r --argjson pr "$pr" '[.[] | select(.number == $pr) | .pos] | first // -1' <<<"$members")"
[[ "$named_pos" -ge 1 ]] || die "named PR #${pr} is absent from the enumerated member set — head_ref names a non-member"
[[ "$named_pos" == "$max_pos" ]] \
  || die "named PR #${pr} is at position ${named_pos} but the group runs deeper (max ${max_pos}) — refusing partial verification"

# `gh api --paginate` prints one JSON object per page, concatenated with no outer array, so the
# reply is slurped (-s) and every page's check_runs read.
# shellcheck disable=SC2016  # a jq program: $n is a jq variable, not a shell expansion
latest_program='[.[].check_runs[]? | select(.name == $n and .app.id == 15368)]
  | sort_by(.id)
  | last
  | if . == null then "missing" else "\(.status)/\(.conclusion)" end'

member_lines=()
while IFS=' ' read -r mpr mhead; do
  [[ -n "$mpr" ]] || die "blank member row enumerated — the member set is corrupt, refusing"
  [[ "$mhead" =~ ^[0-9a-f]{40}$ ]] || die "member PR #${mpr} head sha is not 40 lowercase hex characters"
  gh_read "the check-runs of member PR #${mpr}" --paginate \
    "repos/${REPO}/commits/${mhead}/check-runs?filter=all&per_page=100"
  mruns="$REPLY_JSON"
  for ctx in cla-check cla-evidence; do
    verdict="$(jq -rs --arg n "$ctx" "$latest_program" <<<"$mruns")" \
      || die "cannot read the ${ctx} check-runs of member PR #${mpr}"
    verdict="$(printf '%s' "$verdict" | tr -cd 'A-Za-z0-9/_')"
    [[ "$verdict" == "completed/success" ]] \
      || die "${ctx} on member PR #${mpr} head is ${verdict:-unreadable}, not completed/success"
  done
  member_lines+=("pr${mpr}@${mhead:0:10}")
done < <(jq -r '.[] | "\(.number) \(.head)"' <<<"$members")

echo "merge-queue-cla-verify=OK members=${member_count} anchor=${anchor_kind} embedded=${embedded} ${member_lines[*]}"
