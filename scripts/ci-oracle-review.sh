#!/usr/bin/env bash
# ci-oracle-review.sh — the `oracle-review-required` job's driver (#10859, ADR-276 PR3b; ruling (a) of 2026-11-06).
#
# WHAT IT DECIDES. The oracle surface (RATCHET_ORACLE of scripts/ci-pr-affected-replay.py — the affected-index
# ratchet's own inputs) merges only after a bound owner-review act:
#   * pull_request — the merge-ref diff touches a BASE RATCHET_ORACLE member AND (author == deruelle OR an APPROVED
#     review by deruelle whose commit_id is the PR head SHA exists). GitHub bars self-approval, so the author arm is
#     the release valve for owner-authored oracle repairs. The classification list is extracted at run time from the
#     BASE commit's copy of the replay file (`git show <base>:scripts/ci-pr-affected-replay.py` imported by a pinned
#     python one-liner), so a PR cannot shrink the list that judges it; the DRIVER ITSELF is also base-sourced on
#     pull_request (a base without this file — every pre-PR3b base — runs the HEAD copy, still classified by the base
#     list).
#   * merge_group — no diff classification (the batch's diff is not the review surface). The queue members are
#     enumerated through the merge-queue-cla-verify machinery (the entries(first:100) query + the headCommit.oid
#     anchor binding, parity-pinned below), and EVERY member's queued head (headRefOid) must show its LATEST
#     `oracle-review-required` check-run (github-actions app 15368, highest check-run id wins) as
#     completed/success. Zero members, a truncated page, an unbindable anchor or a missing/red member context all
#     FAIL — never a vacuous pass.
#
# FAIL-CLOSED, ALWAYS: any gh api non-zero (one transient retry), a paginated member list, an unparseable reply, a
# missing/invalid input or an event outside pull_request/merge_group is a FAIL verdict naming the class.
#
# INPUTS ARE ENV ONLY (the workflow passes them through `env:`; nothing is interpolated into the script):
#   EVENT_NAME    github.event_name                          (pull_request | merge_group; anything else fails)
#   REPO          github.repository                          (owner/name)
#   GITHUB_SHA    the merge commit the pull_request checkout is at (runner-provided)
#   PR_NUMBER     github.event.pull_request.number           (pull_request)
#   PR_HEAD_SHA   github.event.pull_request.head.sha         (pull_request)
#   PR_AUTHOR     github.event.pull_request.user.login       (pull_request)
#   HEAD_REF      github.event.merge_group.head_ref          (merge_group)
#   HEAD_SHA      github.event.merge_group.head_sha          (merge_group)
#   BASE_REF      github.event.merge_group.base_ref          (merge_group; refs/heads/main)
#   GH_TOKEN      the job's GITHUB_TOKEN (contents: read, pull-requests: read, checks: read)
#   GITHUB_OUTPUT, GITHUB_STEP_SUMMARY, RUNNER_TEMP          (optional; RUNNER_TEMP falls back to $TMPDIR, then /tmp)
# CWD must be the repo checkout (actions/checkout; pull_request is at the MERGE ref, fetch-depth 2 suffices).
#
# OUTPUT: exactly one last line on stdout —
#   SOLEUR_ORACLE_REVIEW event=<e> oracle_diff=<0|1> author=<login|-> approved=<0|1> members=<n> verdict=<pass|fail> reason=<token>
# literals only (no paths, SHAs or review URLs — the ci-oracle-lane annotation contract). Failures also emit one
# `::error title=oracle-review-required::<text>` line and `reason=<token>` to GITHUB_OUTPUT. Exit 0 on pass, 1 on fail.
#
# VERDICT GRAMMAR (pinned by scripts/ci-oracle-review.test.sh):
#   event      ^[a-z_]+$          (unset renders `unset`)
#   oracle_diff^(0|1)$            pull_request only; merge_group always 0
#   author     ^[A-Za-z0-9-]+(\[bot\])?$|-  merge_group renders `-`
#   approved   ^(0|1)$
#   members    ^[0-9]+$           merge_group member count; pull_request 0
#   verdict    ^(pass|fail)$
#   reason     pass: not-oracle | author | approved | members-green
#              fail: event | input | shape | api | pagination | anchor | member-context | review-required | stale-approval
set -uo pipefail

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
export GIT_OPTIONAL_LOCKS=0

readonly ORACLE_CONTEXT="oracle-review-required"
readonly REQUIRED_REVIEWER="deruelle"
readonly ORACLE_REPLAY="scripts/ci-pr-affected-replay.py"

OUT="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# State that feeds the marker line. Every value is a literal, a number or a validated token.
# `members` inside the parity block below holds the enumerated JSON — the marker's members field
# reads `member_count` (a number on every path, including die() before the loop finishes).
event="${EVENT_NAME:-unset}"
oracle_diff=0
author="-"
approved=0
member_count=0
verdict=fail
reason=init

emit() {
  printf 'SOLEUR_ORACLE_REVIEW event=%s oracle_diff=%s author=%s approved=%s members=%s verdict=%s reason=%s\n' \
    "$event" "$oracle_diff" "$author" "$approved" "$member_count" "$verdict" "$reason"
}

finish() {   # finish <pass|fail> <reason-token>
  verdict="$1"
  reason="$2"
  emit
  [ "$verdict" = pass ] && exit 0
  printf 'reason=%s\n' "$reason" >> "$OUT"
  exit 1
}

# die <text> — the merge_group enumeration's failure path (parity copy below calls it with the same literal texts
# merge-queue-cla-verify.sh uses); the reason token is derived from the text class, never from event data.
die() {
  local msg="$*" tok=member-context
  case "$msg" in
    *paginated*|*"beyond first"*) tok=pagination ;;
    *"cannot bind"*|*"does not own"*|*"unverifiable"*|*"unbindable"*) tok=anchor ;;
    *"gh api failed"*|*"cannot read"*) tok=api ;;
  esac
  printf '::error title=oracle-review-required::%s\n' "$msg"
  finish fail "$tok"
}

# ---- base-sourced driver on pull_request ----------------------------------------------------------------------
# The re-exec lives in the ci.yml STEP (a PR editing this file cannot remove code it does not
# contain — the merge-queue-cla-synthetics.yml precedent). On pull_request the step extracts this
# driver from the base commit when the base carries it; a base without the file (pre-PR3b) and the
# merge_group arm run this HEAD copy. Residual (platform-inherent): the workflow definition itself
# is PR-mutable — bounded because ci.yml is RATCHET_ORACLE surface and this same check then gates it.

# gh_read <label> <gh api args...> : the reply lands in $REPLY_JSON. Not a command substitution, because die inside
# one would print into the captured variable and be swallowed. A gh failure is retried ONCE after a short pause (a
# transient 5xx must not eject a healthy PR from the queue), and a second failure is fatal and names the endpoint
# kind (never read as an empty answer): bounded, fail closed.
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
  die "gh api failed reading ${label}"
}

# ---- pull_request arm -----------------------------------------------------------------------------------------
pr_arm() {
  [[ "${REPO:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || finish fail input
  [[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]] || finish fail input
  [[ "${PR_HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || finish fail input
  [[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || finish fail input
  [[ "${PR_AUTHOR:-}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$ ]] || finish fail input
  author="$PR_AUTHOR"

  # The merge-ref shape: HEAD is GITHUB_SHA, has exactly two parents, HEAD^2 is the PR head. All 40-hex.
  local rl; rl="$(git rev-list --parents -n 1 HEAD 2>/dev/null)" || finish fail shape
  local -a parts; read -r -a parts <<< "$rl"
  [ "${#parts[@]}" -eq 3 ] || finish fail shape
  [[ "${parts[0]}" =~ ^[0-9a-f]{40}$ && "${parts[1]}" =~ ^[0-9a-f]{40}$ && "${parts[2]}" =~ ^[0-9a-f]{40}$ ]] || finish fail shape
  [ "${parts[0]}" = "$GITHUB_SHA" ] || finish fail shape
  [ "${parts[2]}" = "$PR_HEAD_SHA" ] || finish fail shape
  local base="${parts[1]}"

  local work=""
  for _tmpd in "${RUNNER_TEMP:-}" "${TMPDIR:-}" /tmp; do
    [ -n "$_tmpd" ] && [ -d "$_tmpd" ] || continue
    work="$(mktemp -d "$_tmpd/oracle-review.XXXXXX" 2>/dev/null)" && break
  done
  unset _tmpd
  [ -n "$work" ] || finish fail api
  # Owning trap for the mktemp dir above (lint-trap-ownership): the manual
  # rm -rf below covers the named exit paths; this covers a signal/errexit
  # death. ${work:-/nonexistent} stays silent once the local is out of scope.
  trap 'rm -rf -- "${work:-/nonexistent}"' EXIT

  git diff --name-only --no-renames "$base" HEAD -- > "$work/touched" 2> "$work/diff.err" || { rm -rf "$work"; finish fail api; }
  # The classification list is the BASE commit's RATCHET_ORACLE — never the PR tree's: a PR cannot shrink the list
  # that judges it. The extraction is a pinned one-liner (the suite pins it against the tuple in BOTH directions).
  git show "$base:$ORACLE_REPLAY" > "$work/replay-base.py" 2> "$work/show.err" || { rm -rf "$work"; finish fail api; }
  python3 - "$work/replay-base.py" > "$work/oracle.txt" 2> "$work/py.err" <<'PY' || { rm -rf "$work"; finish fail api; }
import importlib.util, sys
spec = importlib.util.spec_from_file_location("replay_base", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception:
    sys.exit(3)
oracle = getattr(mod, "RATCHET_ORACLE", None)
if not isinstance(oracle, (tuple, list)) or not oracle or not all(isinstance(p, str) and p for p in oracle):
    sys.exit(3)
for p in oracle:
    sys.stdout.write(p + "\n")
PY
  oracle_diff=0
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if grep -qxF -- "$p" "$work/touched"; then oracle_diff=1; break; fi
  done < "$work/oracle.txt"
  rm -rf "$work"

  [ "$oracle_diff" = 1 ] || finish pass not-oracle

  # Oracle diff: the author arm (GitHub bars self-approval), then the bound-approval arm.
  [ "$author" = "$REQUIRED_REVIEWER" ] && finish pass author

  gh_read "the reviews of PR #${PR_NUMBER}" --paginate "repos/${REPO}/pulls/${PR_NUMBER}/reviews"
  local reviews="$REPLY_JSON" bound any
  # --paginate concatenates one JSON array per page; slurp and flatten. An unparseable reply is fail-closed `api`.
  bound="$(jq -rs --arg who "$REQUIRED_REVIEWER" --arg sha "$PR_HEAD_SHA" \
    '[.[][] | select(.user.login == $who and .state == "APPROVED" and .commit_id == $sha)] | length' \
    <<<"$reviews" 2>/dev/null)" || finish fail api
  [[ "$bound" =~ ^[0-9]+$ ]] || finish fail api
  if [ "$bound" -ge 1 ]; then approved=1; finish pass approved; fi
  any="$(jq -rs --arg who "$REQUIRED_REVIEWER" \
    '[.[][] | select(.user.login == $who and .state == "APPROVED")] | length' \
    <<<"$reviews" 2>/dev/null)" || finish fail api
  [ "${any:-0}" -ge 1 ] && finish fail stale-approval
  finish fail review-required
}

# ---- merge_group arm ------------------------------------------------------------------------------------------
mg_arm() {
  [[ "${REPO:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || finish fail input
  [[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || finish fail input
  [[ "${BASE_REF:-}" == "refs/heads/main" ]] || finish fail input
  [[ "${HEAD_REF:-}" =~ ^refs/heads/gh-readonly-queue/main/pr-([0-9]+)-([0-9a-f]{40})$ ]] || finish fail input
  pr="${BASH_REMATCH[1]}"
  embedded="${BASH_REMATCH[2]}"

  # --- group membership enumeration (#11678, ADR-270 raise checklist) -----------
    # PARITY-PINNED COPY of scripts/merge-queue-cla-verify.sh:89-184 — the only permitted divergence is the context
    # list `cla-check cla-evidence` -> `oracle-review-required` (pinned byte-for-byte by scripts/ci-oracle-review.test.sh).
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
    for ctx in oracle-review-required; do
      verdict="$(jq -rs --arg n "$ctx" "$latest_program" <<<"$mruns")" \
        || die "cannot read the ${ctx} check-runs of member PR #${mpr}"
      verdict="$(printf '%s' "$verdict" | tr -cd 'A-Za-z0-9/_')"
      [[ "$verdict" == "completed/success" ]] \
        || die "${ctx} on member PR #${mpr} head is ${verdict:-unreadable}, not completed/success"
    done
    member_lines+=("pr${mpr}@${mhead:0:10}")
  done < <(jq -r '.[] | "\(.number) \(.head)"' <<<"$members")
  # --- END parity-pinned copy ---------------------------------------------------

  finish pass members-green
}

case "$event" in
  pull_request) pr_arm ;;
  merge_group)  mg_arm ;;
  *)            finish fail event ;;
esac
