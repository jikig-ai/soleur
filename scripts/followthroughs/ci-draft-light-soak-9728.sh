#!/usr/bin/env bash
# ci-draft-light-soak-9728.sh — post-merge soak probe for #9728 (ADR-276 S3, draft PRs run a light CI set).
#
# TRACKER: #9728 itself. The lead adds this directive line to its body (label `follow-through`), with `earliest`
# set to the S3 merge time plus one day; GH_TOKEN is the only secret the probe needs and the sweeper workflow
# already forwards it, so no workflow change is required:
#   <!-- soleur:followthrough script=scripts/followthroughs/ci-draft-light-soak-9728.sh earliest=<merge+1d> secrets=GH_TOKEN -->
#
# Is the light draft set safe and does it pay? Checks, in the order they decide:
#  (a) STALL, every sweep: any OPEN non-draft PR whose verdict (plugins/soleur/scripts/ci-head-verdict.sh
#      `verdict <pr>`, closed state set n/a|full-decided|pending-full|no-run|stalled|awaiting-approval) is `stalled`
#      (N=75 minutes with no deciding CI run after the ready event) is a FAIL naming the PR. `n/a` and `full-decided`
#      are never flagged. A resolver error, a missing verdict line, a PR mismatch or a state outside the closed set
#      is CANNOT ESTABLISH: an unreadable PR is never read as healthy. Draft PRs are not consulted.
#  (c) DETECTIVE ACTIVATION CHECK, every sweep: a repository variable is a setting, and no code path can refuse a
#      `gh variable set`, so the order is checked after the fact. A LIGHT RUN is a ci.yml `pull_request` run whose four
#      gated jobs (test-webplat, test-scripts, test-scripts-heavy, shard-totality-mutations) were all skipped (the jobs
#      API, never an annotation: the annotation could fail to emit and would blind the probe). A light run observed with
#      no `S3-ACTIVATED` on record, created before the first one, or with no trusted `S3-CONFIRMED` comment posted
#      BEFORE that activation, is a FAIL. Only comments by an OWNER, MEMBER or COLLABORATOR count.
#  (d) LIVE INVARIANTS, every sweep: every observed light run has a FAILING `test` job (Option R: a draft aggregator
#      is red by design), and no light run was created while its PR was a non-draft (the PR's state at the run's
#      creation is rebuilt from its ReadyForReview and ConvertToDraft events, the run joined by head SHA and head
#      branch through GraphQL, never through the run's `pull_requests[]`, which is empty for most runs). Once
#      activated, no merge_group entry (queue branch gh-readonly-queue/<base>/pr-<N>-<sha>) may follow a PR head whose
#      NEWEST pull_request run was a light run.
#  (b) DARK DEADLINE: the `ready_for_review` type is ungated, so while the variable is unset every readied PR pays an
#      extra full run. More than 1 day after the S3 PR merged with no trusted `S3-ACTIVATED` marker is a FAIL.
#  (e) EXIT: exit 2 NOT YET until 7 days after the activation; then exit 0 needs ALL of: at least 20 DISTINCT head SHAs
#      observed light since the activation (a soak with no draft pushes proves nothing; re-runs of one head are one
#      push), no stalled PR, no merge_group entry behind a light head (both checked above on every sweep), and an
#      `S3-EXIT-CENSUS: https://github.com/...` comment from a trusted author holding the before/after minutes (the
#      sweeper closes the tracker itself on exit 0, so a pass without the census would close the stage without its
#      evidence). 30 days after activation with fewer than 20 distinct light pushes is a FAIL: the lever is not lighting.
# ACTIVATION is read from the tracker, not from the repository variable: the sweeper's GITHUB_TOKEN cannot read Actions
# variables (the S2 probe, ci-push-dedupe-soak-9512.sh, documents the same). The activating agent posts, as plain lines
# under the operator's own identity (a bot-posted marker has no OWNER/MEMBER/COLLABORATOR association and is ignored):
#   S3-CONFIRMED: <https://github.com/... comment url | "quoted operator statement">     BEFORE setting the variable
#   S3-ACTIVATED: <UTC ISO time, the variable's updated_at>                              after setting it
#   S3-DEACTIVATED: <UTC ISO time>                                                       after deleting it (stop rule)
#   S3-EXIT-CENSUS: https://github.com/...                                               the exit census comment
# The marker's own timestamp orders ACTIVATED against DEACTIVATED; the comment's created_at orders CONFIRMED against
# ACTIVATED. A light run created after a recorded deactivation is a FAIL (the variable removal did not take effect).
#
# SAMPLE (bounds API use, the sweeper token allows ~1000 requests/hour/repo shared by every probe): the newest MAX_RUNS
# (100) completed success/failure pull_request runs since the merge (cancelled runs leave skipped jobs and are not
# observations), only IDLE_RUNS (40) while nothing is active; the newest MG_MAX (30) merge_group runs since the
# activation; at most 100 open PRs. A violation is a persistent flow (every draft push is light), not a one-off, so a
# bounded sample sees it within a sweep.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS    1 = FAIL (a stalled PR, an unrecorded or unconfirmed activation, a light run whose test did not fail
#               or that ran on a non-draft PR, a merge_group entry behind a light head, the dark deadline, or a soak
#               that never lit)
#   2 = NOT YET (not merged, not activated, deactivated, too few days or light pushes, or the exit census is missing)
#   3 = CANNOT ESTABLISH (gh/jq/timeout/GH_TOKEN/resolver missing, or a GitHub API read failed: the sweeper retries)
#   78 = refused to run under xtrace while GH_TOKEN is set (#7797)
#
# RETIREMENT: when #9728's tracker closes, delete this file, its .test.sh, the run_suite line in scripts/test-all.sh,
# the rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv, and the CODEOWNERS lines.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
S3_PR=9885
TRACKER=9728
MIN_PUSHES=20
MIN_DAYS=7
DEADLINE_DAYS=30
DARK_DAYS=1
STALL_MIN=75         # the resolver's threshold, quoted in the FAIL text only
MAX_RUNS=100
IDLE_RUNS=40
MG_MAX=30
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# test seam (the sweeper runs this under env -i, so it is inert in production)
VERDICT_CMD="${CI_HEAD_VERDICT_CMD:-$HERE/../../plugins/soleur/scripts/ci-head-verdict.sh}"

for need in gh jq timeout; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }
[ -r "$VERDICT_CMD" ] || { echo "CANNOT ESTABLISH: the verdict resolver $VERDICT_CMD is not readable"; exit 3; }

NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_NOW_EPOCH is not an epoch"; exit 3; }

fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }
api() { gh api "$@" 2>/dev/null; }

# --- the S3 PR merge time ------------------------------------------------------------------------------------------------
merged_at="$(api "repos/$REPO/pulls/$S3_PR" --jq '.merged_at // empty')" || fail_api "pull $S3_PR"
[ -n "$merged_at" ] || { echo "NOT YET: PR $S3_PR is not merged"; exit 2; }
merged_epoch="$(date -u -d "$merged_at" +%s 2>/dev/null)" || fail_api "merge time $merged_at"

# --- the tracker: markers, trusted authors only (one JSON object per comment: its time and its body) --------------------------
comments="$(api --paginate "repos/$REPO/issues/$TRACKER/comments?per_page=100" \
            --jq '.[] | select((.author_association // "") | IN("OWNER", "MEMBER", "COLLABORATOR")) | {t: (.created_at // ""), b: (.body // "")} | tojson')" \
  || fail_api "tracker $TRACKER comments"
trusted="$(jq -r '.b' <<<"$comments" 2>/dev/null | tr -d '\r')"
TS_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
first_on="$(printf '%s\n' "$trusted" | grep -oE "^S3-ACTIVATED: $TS_RE\$" | sed 's/^S3-ACTIVATED: //' | sort | head -n 1)"
last_on="$(printf '%s\n' "$trusted" | grep -oE "^S3-ACTIVATED: $TS_RE\$" | sed 's/^S3-ACTIVATED: //' | sort | tail -n 1)"
last_off="$(printf '%s\n' "$trusted" | grep -oE "^S3-DEACTIVATED: $TS_RE\$" | sed 's/^S3-DEACTIVATED: //' | sort | tail -n 1)"
census_marked="$(printf '%s\n' "$trusted" | grep -cE '^S3-EXIT-CENSUS: https://github\.com/[^ ]+$')"
# the earliest trusted S3-CONFIRMED comment (a github URL, or a quoted statement of at least 3 characters), by created_at
CONF_RE='^S3-CONFIRMED: (https://github\.com/[^ ]+|"[^"]{3,}")$'
conf_iso="$(jq -r --arg re "$CONF_RE" 'select(.b | split("\n") | map(rtrimstr("\r")) | any(test($re))) | .t' <<<"$comments" 2>/dev/null | sort | head -n 1)"
conf_epoch=""
[ -n "$conf_iso" ] && { conf_epoch="$(date -u -d "$conf_iso" +%s 2>/dev/null)" || fail_api "confirmation time $conf_iso"; }
has_on=0; active=0; deactivated=0; first_on_epoch=0; act_epoch=0; off_epoch=0
if [ -n "$first_on" ]; then
  has_on=1
  first_on_epoch="$(date -u -d "$first_on" +%s 2>/dev/null)" || fail_api "activation time $first_on"
  act_epoch="$(date -u -d "$last_on" +%s 2>/dev/null)" || fail_api "activation time $last_on"
  if [ -n "$last_off" ]; then off_epoch="$(date -u -d "$last_off" +%s 2>/dev/null)" || fail_api "deactivation time $last_off"; fi
  if [ "$act_epoch" -gt "$off_epoch" ]; then active=1; else deactivated=1; fi
fi

# --- (a) the open non-draft PRs and their verdicts ---------------------------------------------------------------------------
open_prs="$(api "repos/$REPO/pulls?state=open&per_page=100" --jq '[.[] | select(.draft != true) | .number] | .[]')" || fail_api "open pull requests"
npr=0; stalled_list=""
for pr in $open_prs; do
  [[ "$pr" =~ ^[0-9]+$ ]] || fail_api "open PR number $pr"
  vout="$(timeout 120 bash "$VERDICT_CMD" verdict "$pr" 2>/dev/null)" || fail_api "verdict for PR $pr"
  vline="$(grep -m1 '^SOLEUR_CI_HEAD_VERDICT ' <<<"$vout")" || vline=""
  [ -n "$vline" ] || fail_api "verdict for PR $pr (no verdict line)"
  vstate="$(sed -n 's/.* state=\([^ ]*\).*/\1/p' <<<"$vline")"
  vpr="$(sed -n 's/.* pr=\([0-9]*\).*/\1/p' <<<"$vline")"
  [ "$vpr" = "$pr" ] || fail_api "verdict for PR $pr (the line names PR '$vpr')"
  npr=$((npr + 1))
  case "$vstate" in
    n/a|full-decided|pending-full|no-run|awaiting-approval) : ;;
    stalled) stalled_list="$stalled_list #$pr" ;;
    *) fail_api "verdict for PR $pr (state '$vstate' is outside the closed set)" ;;
  esac
done

# --- the sample: completed success/failure pull_request runs since the merge (newest first) -------------------------------------
cap="$MAX_RUNS"; (( active )) || cap="$IDLE_RUNS"
runs_json="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=pull_request&status=completed&per_page=100&created=%3E$merged_at" \
              --jq "[.workflow_runs[] | select(.conclusion == \"success\" or .conclusion == \"failure\") | {id, head_sha, head_branch, created: (.created_at | fromdateiso8601)}] | .[0:$cap]")" \
  || fail_api "ci.yml pull_request runs"
[ -n "$runs_json" ] || fail_api "ci.yml pull_request runs (empty body)"

declare -A SHAPE=()   # run id -> "<light true|false><TAB><test conclusion>"
jobs_shape() {        # <run id>: fills SHAPE[<id>] from the jobs API (the latest attempt)
  local id="$1" jj
  [ -n "${SHAPE[$id]:-}" ] && return 0
  jj="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest")" || fail_api "run $id jobs"
  SHAPE[$id]="$(jq -r '. as $d
      | (["test-webplat", "test-scripts", "test-scripts-heavy", "shard-totality-mutations"]
         | all(. as $n | $d | [.jobs[]? | select(.name | test("^" + $n + "( |$)"))] | (length > 0 and all(.conclusion == "skipped")))) as $light
      | ([$d.jobs[]? | select(.name == "test") | .conclusion] | .[0] // "absent") as $t
      | "\($light)\t\($t)"' <<<"$jj" 2>/dev/null)" || fail_api "run $id jobs (parse)"
  [ -n "${SHAPE[$id]}" ] || fail_api "run $id jobs (empty parse)"
}

# the PR state at a run's creation, rebuilt from the PR's ready/convert events (one GraphQL read per distinct head SHA)
GQL_Q='query($owner:String!,$name:String!,$sha:GitObjectID!){repository(owner:$owner,name:$name){object(oid:$sha){... on Commit{associatedPullRequests(first:5){nodes{number isDraft headRefName timelineItems(first:50,itemTypes:[READY_FOR_REVIEW_EVENT,CONVERT_TO_DRAFT_EVENT]){pageInfo{hasNextPage} nodes{__typename ... on ReadyForReviewEvent{createdAt} ... on ConvertToDraftEvent{createdAt}}}}}}}}}'
declare -A GQL=()
PR_STATE=""
pr_state() {          # <sha> <branch> <created epoch> -> sets PR_STATE: draft | ready | unknown | none (no subshell: the cache and the exit must survive)
  local sha="$1" br="$2" c="$3"
  if [ -z "${GQL[$sha]:-}" ]; then
    GQL[$sha]="$(api graphql -f query="$GQL_Q" -f owner="${REPO%%/*}" -f name="${REPO##*/}" -f sha="$sha")" || fail_api "PR join for $sha"
    jq -e '.data.repository' >/dev/null 2>&1 <<<"${GQL[$sha]}" || fail_api "PR join for $sha (no repository in the response)"
  fi
  PR_STATE="$(jq -r --argjson c "$c" --arg br "$br" '
      (.data.repository.object.associatedPullRequests.nodes // [])
      | map(select(.headRefName == $br))
      | map(. as $p
            | ($p.timelineItems.nodes | map({k: .__typename, t: (.createdAt | fromdateiso8601)}) | sort_by(.t)) as $ev
            | if $p.timelineItems.pageInfo.hasNextPage then "unknown"
              else ([$ev[] | select(.t <= $c)] | .[-1:] | .[0]) as $last
                | if $last != null then (if $last.k == "ReadyForReviewEvent" then "ready" else "draft" end)
                  elif ($ev | length) > 0 then (if $ev[0].k == "ReadyForReviewEvent" then "draft" else "ready" end)
                  else (if $p.isDraft then "draft" else "ready" end) end
              end)
      | if length == 0 then "none" elif any(. == "ready") then "ready" elif any(. == "unknown") then "unknown" else "draft" end' <<<"${GQL[$sha]}" 2>/dev/null)" \
    || fail_api "PR join for $sha (parse)"
  [ -n "$PR_STATE" ] || fail_api "PR join for $sha (empty parse)"
}

sampled=0; light_any=0; light_runs=0; unjoined=0
early=0; early_list=""; late=0; late_list=""; bad_test=0; bad_test_list=""; bad_ready=0; bad_ready_list=""
declare -A LSHA=()
while IFS=$'\t' read -r id sha branch created; do
  [ -n "$id" ] || continue
  sampled=$((sampled + 1))
  [[ "$created" =~ ^[0-9]+$ ]] || fail_api "run $id created"
  jobs_shape "$id"
  is_light="${SHAPE[$id]%%$'\t'*}"; tconc="${SHAPE[$id]#*$'\t'}"
  [ "$is_light" = "true" ] || continue
  light_any=$((light_any + 1))
  if [ "$tconc" != "failure" ]; then bad_test=$((bad_test + 1)); bad_test_list="$bad_test_list run=$id(test=$tconc)"; fi
  if (( ! has_on )) || [ "$created" -lt "$first_on_epoch" ]; then
    early=$((early + 1)); early_list="$early_list run=$id sha=${sha:0:10}"
  elif (( deactivated )) && [ "$created" -gt "$off_epoch" ]; then
    late=$((late + 1)); late_list="$late_list run=$id sha=${sha:0:10}"
  elif (( active )) && [ "$created" -ge "$act_epoch" ]; then
    light_runs=$((light_runs + 1)); LSHA[$sha]=1
  fi
  pr_state "$sha" "$branch" "$created"
  case "$PR_STATE" in
    ready) bad_ready=$((bad_ready + 1)); bad_ready_list="$bad_ready_list run=$id sha=${sha:0:10}" ;;
    none|unknown) unjoined=$((unjoined + 1)) ;;
  esac
done < <(jq -r '.[] | [.id, .head_sha, .head_branch, .created] | @tsv' <<<"$runs_json")
light_pushes="${#LSHA[@]}"

# --- merge_group entries since the activation: was the PR head's NEWEST pull_request run light? ---------------------------------
mg_checked=0; mg_norun=0; mg_light_list=""
if (( active )); then
  mg_json="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=merge_group&status=completed&per_page=100&created=%3E$last_on" \
              --jq "[.workflow_runs[] | {id, head_branch}] | .[0:$MG_MAX]")" || fail_api "ci.yml merge_group runs"
  [ -n "$mg_json" ] || fail_api "ci.yml merge_group runs (empty body)"
  QUEUE_RE='^gh-readonly-queue/.+/pr-([0-9]+)-[0-9a-f]+$'
  declare -A SEEN_PR=()
  while read -r qbranch; do
    [[ "$qbranch" =~ $QUEUE_RE ]] || continue
    qpr="${BASH_REMATCH[1]}"
    [ -n "${SEEN_PR[$qpr]:-}" ] && continue
    SEEN_PR[$qpr]=1
    qsha="$(api "repos/$REPO/pulls/$qpr" --jq '.head.sha // empty')" || fail_api "queue PR $qpr"
    [ -n "$qsha" ] || fail_api "queue PR $qpr (no head sha)"
    qrun="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=pull_request&head_sha=$qsha&per_page=1" --jq '.workflow_runs[0].id // empty')" \
      || fail_api "newest pull_request run at $qsha"
    mg_checked=$((mg_checked + 1))
    [ -n "$qrun" ] || { mg_norun=$((mg_norun + 1)); continue; }
    jobs_shape "$qrun"
    [ "${SHAPE[$qrun]%%$'\t'*}" = "true" ] && mg_light_list="$mg_light_list #$qpr"
  done < <(jq -r '.[] | .head_branch' <<<"$mg_json")
fi

# --- the verdicts, FAIL before NOT YET -----------------------------------------------------------------------------------------
if [ -n "$stalled_list" ]; then
  echo "FAIL: open ready PR(s) stalled (no deciding CI run $STALL_MIN minutes after the ready event):$stalled_list; recover each with 'gh pr ready --undo <pr>' then 'gh pr ready <pr>' under a user token (never a re-run of the draft run), or unset CI_DRAFT_LIGHT ('gh variable delete CI_DRAFT_LIGHT') and apply the ADR-276 S3 stop rule"
  exit 1
fi
if (( light_any > 0 )); then
  if (( ! has_on )); then
    echo "FAIL: $light_any light run(s) observed with no activation on record (no trusted S3-ACTIVATED comment on #$TRACKER; an org-level variable, or an activation nobody recorded?): unset CI_DRAFT_LIGHT or record it:$early_list"
    exit 1
  fi
  if (( early > 0 )); then
    echo "FAIL: $early light run(s) predate the first recorded activation on #$TRACKER:$early_list"
    exit 1
  fi
  if [ -z "$conf_epoch" ]; then
    echo "FAIL: light runs observed but #$TRACKER has no trusted 'S3-CONFIRMED: <https://github.com/... url | \"quoted statement\">' comment: the activation needed the CTO confirmation or a recorded operator statement (unset CI_DRAFT_LIGHT until it is posted)"
    exit 1
  fi
  if [ "$conf_epoch" -gt "$first_on_epoch" ]; then
    echo "FAIL: the S3-CONFIRMED comment ($conf_iso) was posted after the activation ($first_on): confirmation must precede 'gh variable set'; deactivate, post S3-DEACTIVATED, confirm, and activate again"
    exit 1
  fi
fi
if (( late > 0 )); then
  echo "FAIL: $late light run(s) created after the deactivation recorded at $last_off: the variable is still on (or an org-level copy exists):$late_list"
  exit 1
fi
if (( bad_test > 0 )); then
  echo "FAIL: $bad_test light run(s) whose \`test\` did not fail (Option R: a light run must be red):$bad_test_list; unset CI_DRAFT_LIGHT ('gh variable delete CI_DRAFT_LIGHT') and apply the ADR-276 S3 stop rule"
  exit 1
fi
if (( bad_ready > 0 )); then
  echo "FAIL: $bad_ready light run(s) were created while their PR was not a draft (a ready head must always run the full battery):$bad_ready_list; unset CI_DRAFT_LIGHT and apply the ADR-276 S3 stop rule"
  exit 1
fi
if [ -n "$mg_light_list" ]; then
  echo "FAIL: merge_group entr(ies) for PR(s)$mg_light_list followed a head whose newest pull_request run was a light run (a heavy family went unrun before the queue): unset CI_DRAFT_LIGHT and apply the ADR-276 S3 stop rule"
  exit 1
fi
if (( ! has_on )); then
  if (( NOW - merged_epoch > DARK_DAYS * 86400 )); then
    echo "FAIL: more than $DARK_DAYS day since PR $S3_PR merged and no S3-ACTIVATED marker is on record on #$TRACKER: every readied PR pays an extra full run while the variable is unset; activate, or revert the ready_for_review type (ADR-276 S3 dark-window bound)"
    exit 1
  fi
  echo "NOT YET: not activated (no trusted S3-ACTIVATED comment on #$TRACKER); $sampled recent run(s) sampled, 0 light, $npr open PR(s) checked"
  exit 2
fi
if (( deactivated )); then
  echo "NOT YET: deactivated at $last_off (S3-DEACTIVATED is later than S3-ACTIVATED $last_on); re-activate with a fresh S3-CONFIRMED/S3-ACTIVATED pair, or close the stage by its stop rule"
  exit 2
fi

# --- active: counts and age ----------------------------------------------------------------------------------------------------
age_days=$(( (NOW - act_epoch) / 86400 ))
echo "activated=$last_on sampled=$sampled light_runs=$light_runs light_pushes=$light_pushes age_days=$age_days unjoined=$unjoined stalled=0 open_prs_checked=$npr mg_checked=$mg_checked mg_without_pr_run=$mg_norun"
if (( light_pushes < MIN_PUSHES || age_days < MIN_DAYS )); then
  if (( age_days >= DEADLINE_DAYS )); then
    echo "FAIL: $age_days days since activation and only $light_pushes distinct draft push(es) observed light (need >= $MIN_PUSHES): the lever is not lighting; read the draft-light job's step conclusions and the ci-draft-light annotations in recent pull_request runs"
    exit 1
  fi
  echo "NOT YET: $light_pushes distinct draft push(es) observed light over $age_days day(s) (need >= $MIN_PUSHES over >= $MIN_DAYS days)"
  exit 2
fi
if (( census_marked == 0 )); then
  echo "NOT YET: criteria hold ($light_pushes distinct light pushes, $age_days days, no stall, no light queue entry) but tracker #$TRACKER has no 'S3-EXIT-CENSUS: https://github.com/...' comment from an owner, member or collaborator; attach the exit census (before/after draft CI minutes per push)"
  exit 2
fi
echo "PASS: $light_pushes distinct draft push(es) observed light over $age_days days, every light run red, no stalled PR, no merge_group entry behind a light head, exit census attached on #$TRACKER"
exit 0
