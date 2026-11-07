#!/usr/bin/env bash
# merge-queue-jump.sh (#11678) — move an urgent PR to the head of the merge queue
# via GraphQL `enqueuePullRequest(jump: true)`, the deliberate middle tier between
# waiting serially and `gh pr merge --admin` (which bypasses every required check).
# See runbook: knowledge-base/engineering/operations/runbooks/merge-queue-jump.md.
#
# Behaviour contract (from the plan — do not loosen without CLO sign-off):
#   * --reason "<text>" is REQUIRED: it is the deliberate-act record and doubles
#     as the attribution comment body posted on the PR after a successful jump.
#   * Non-TTY invocation REQUIRES --yes; without it the script refuses (scripts in
#     this repo run headless from skills/agents — `read` on no stdin must never
#     silently proceed).
#   * expectedHeadOid is pinned to the PR's CURRENT headRefOid, re-read AFTER
#     confirmation and immediately before the mutation (the probe→confirm→mutate
#     gap is minutes; a push in it must stale-head reject, not jump a wrong sha).
#   * A PR whose queue entry vanished because it MERGED exits 0, not error.
#   * Never-armed PRs are refused with a named reason; armed PRs (auto-merge set,
#     whether already enqueued or still in GitHub's enqueue lag) attempt the
#     mutation — for an armed-but-unqueued PR a jump ENQUEUES at the front.
#   * No dequeuePullRequest branch: a dequeue emits a removal event concurrent
#     watchers read as a real dequeue; the manual recipe lives in the runbook.
#
# Exit codes: 0 jumped (or already merged); 1 every refusal/failure;
#             3 the mutation succeeded but the attribution comment failed —
#               the jump IS live; record it by hand (see runbook).
#
# Auth: the operator's own `gh` auth (needs contents:write+pull-requests:write,
# i.e. the default `gh auth login` scopes — the same authority the web UI's
# "Jump the queue" toggle needs). Not a PAT issue — this is an interactive
# operator act, not workflow automation; if a workflow ever calls this, mint
# the soleur-infra App token per ADR-241/ADR-285, never GITHUB_TOKEN.

set -euo pipefail

die()  { echo "merge-queue-jump: $*" >&2; exit 1; }
note() { echo "merge-queue-jump: $*"; }

usage() {
  cat <<'EOF'
Usage: merge-queue-jump.sh <pr-number> --reason "<why this is urgent>" [--yes]

Jumps PR <pr-number> to the head of the main merge queue (GraphQL
enqueuePullRequest jump:true). The jump rebuilds every in-progress queue
entry — use only for the runbook's urgency bar (prod-down / security /
data-loss). Attribution: --reason is posted on the PR naming the actor.

  --reason TEXT   required; the one-line justification recorded on the PR
  --yes           required when stdin is not a TTY; skip the type-confirm
  -h, --help      this text
EOF
}

PR=""; REASON=""; YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --reason)  [[ $# -ge 2 ]] || die "--reason needs a value"; REASON="$2"; shift 2 ;;
    --yes)     YES=1; shift ;;
    *)         if [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]]; then PR="$1"; shift; else die "unrecognized argument: $1"; fi ;;
  esac
done

[[ "$PR" =~ ^[0-9]+$ ]] || die "usage: merge-queue-jump.sh <pr-number> --reason \"...\" [--yes]"
# A reason that is empty or all whitespace is not a reason.
[[ "$REASON" =~ [^[:space:]] ]] || die "--reason is required — it is the deliberate-act record posted on the PR"
if [[ ! -t 0 && "$YES" -ne 1 ]]; then
  die "non-interactive stdin requires --yes (deliberate-act gate refuses a bare read on no TTY)"
fi

command -v gh >/dev/null 2>&1 || die "gh not found"
command -v jq >/dev/null 2>&1 || die "jq not found"

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
  || die "could not resolve owner/name via gh repo view"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "unexpected repo shape"
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

PROBE='query($o:String!,$n:String!,$pr:Int!){
  repository(owner:$o,name:$n){
    mergeQueue(branch:"main"){ entries(first:1){ totalCount } }
    pullRequest(number:$pr){
      id state merged isInMergeQueue headRefOid baseRefName
      autoMergeRequest{ enabledAt }
    }
  }
}'

probe() {
  timeout 60 gh api graphql -F o="$OWNER" -F n="$NAME" -F pr="$PR" -f query="$PROBE" \
    --jq '{n:(.data.repository.mergeQueue.entries.totalCount),id:.data.repository.pullRequest.id,state:.data.repository.pullRequest.state,merged:.data.repository.pullRequest.merged,inq:.data.repository.pullRequest.isInMergeQueue,head:.data.repository.pullRequest.headRefOid,base:.data.repository.pullRequest.baseRefName,armed:(.data.repository.pullRequest.autoMergeRequest!=null)}'
}

FIRST="$(probe)" || die "probe failed — check gh auth scopes (contents+pull-requests write)"
[[ "$(jq -r '.id' <<<"$FIRST")" != "null" ]] || die "PR #$PR not found in $REPO"

merged="$(jq -r '.merged' <<<"$FIRST")"
state="$(jq -r '.state' <<<"$FIRST")"
armed="$(jq -r '.armed' <<<"$FIRST")"
inq="$(jq -r '.inq' <<<"$FIRST")"
prid="$(jq -r '.id' <<<"$FIRST")"
depth="$(jq -r '.n' <<<"$FIRST")"

[[ "$merged" == "true" ]] && { note "PR #$PR is already merged — nothing to jump."; exit 0; }
[[ "$state" == "OPEN" ]] || die "PR #$PR is $state — only open PRs can join the queue"
if [[ "$armed" != "true" && "$inq" != "true" ]]; then
  die "PR #$PR is not in the merge queue and has no auto-merge armed — 'gh pr merge $PR --squash --auto' first"
fi
[[ "$depth" =~ ^[0-9]+$ ]] || die "queue depth read failed"
[[ "$(jq -r '.base' <<<"$FIRST")" == "main" ]] || die "PR #$PR does not target main — the jump path is the main merge queue"

note "PR #$PR in $REPO state=$state inQueue=$inq armed=$armed; $depth entr$( [[ "$depth" == 1 ]] && echo y || echo ies ) in flight — a jump rebuilds ALL of them."

if [[ "$YES" -ne 1 ]]; then
  read -r -p "merge-queue-jump: type 'jump' to confirm: " ans || die "aborted (EOF on stdin)"
  [[ "$ans" == "jump" ]] || die "aborted — '$ans' is not 'jump'"
fi

# Re-read AFTER confirmation, immediately before the mutation: the probe→confirm
# gap is measured in human minutes; a push in it must stale-head reject.
SECOND="$(probe)" || die "re-probe failed before mutation"
head="$(jq -r '.head' <<<"$SECOND")"
merged2="$(jq -r '.merged' <<<"$SECOND")"
[[ "$merged2" == "true" ]] && { note "PR #$PR merged during confirmation — nothing to jump."; exit 0; }
inq2="$(jq -r '.inq' <<<"$SECOND")"; armed2="$(jq -r '.armed' <<<"$SECOND")"
[[ "$armed2" == "true" || "$inq2" == "true" ]] || die "PR #$PR left the queue during confirmation — refusing to jump"
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || die "could not pin expectedHeadOid — refusing to jump an unpinned head"

note "jumping PR #$PR at head ${head:0:10}…"
MUT='mutation($pr:ID!,$oid:GitObjectID!){
  enqueuePullRequest(input:{pullRequestId:$pr,expectedHeadOid:$oid,jump:true}){
    mergeQueueEntry{ position state } clientMutationId } }'

newpos="$(timeout 60 gh api graphql -F pr="$prid" -F oid="$head" -f query="$MUT" --jq '.data.enqueuePullRequest.mergeQueueEntry.position' 2>/dev/null)" \
  || die "enqueuePullRequest(jump:true) rejected — permission, stale head, or queue state changed; see runbook"
[[ "$newpos" =~ ^[0-9]+$ ]] \
  || die "enqueuePullRequest returned a non-entry payload (position='$newpos') — the jump did not land"

ACTOR="$(gh api user --jq .login 2>/dev/null || echo "unknown")"
if ! gh pr comment "$PR" -R "$REPO" --body "merge-queue jump requested by \`$ACTOR\` — $REASON" >/dev/null 2>&1 || [[ "$ACTOR" == "unknown" ]]; then
  echo "merge-queue-jump: JUMPED but attribution incomplete — record '$(git config user.name 2>/dev/null || echo operator): $REASON' on PR #$PR manually" >&2
  exit 3
fi
note "jumped PR #$PR (position $newpos); attribution posted as $ACTOR."
