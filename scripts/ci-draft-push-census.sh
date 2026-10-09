#!/usr/bin/env bash
# ci-draft-push-census.sh - the committed measurement authority for entry gate 6 of the draft-light stage
# (ADR-276 Decision 4; S3 of the hosted-runner demand plan, #9728): how many pushes does a draft PR get?
#
# USAGE
#   ci-draft-push-census.sh --end <YYYY-MM-DD> [--days N] [--repo OWNER/NAME] [--rows FILE]
#   ci-draft-push-census.sh --fixture DIR --end <YYYY-MM-DD> [--days N] [--rows FILE]
#   ci-draft-push-census.sh --help
#
# Live mode needs `gh` with a logged-in developer shell, GNU `date`, GNU `timeout` and `jq`; fixture mode needs only
# `jq` and `date` and never touches the network. Both modes run ONE aggregator over the same directory layout
# (prs.json, runs-<YYYY-MM-DD>.json), so the offline suite exercises exactly the code a live run uses. Live mode
# issues reads only (the GraphQL call is a POST of a read-only query) and refuses GITHUB_ACTIONS=true: about 90
# calls would spend the repo-wide GITHUB_TOKEN budget every other workflow shares.
#
# PERIOD. The N days (default 30) ending at the UTC day boundary --end, exclusive: [END-N days 00:00Z, END 00:00Z).
#   --end must be a past or current UTC day (a closed period). --days is 1 to 90.
#
# DEFINITIONS (fixed by the plan; the verdict table below is applied mechanically)
#   Draft window: rebuilt from ReadyForReviewEvent / ConvertToDraftEvent. A PR whose first event is a ready event was a
#     draft at open (window opens at createdAt); one whose first event is a convert was ready at open; a PR with no event
#     is a draft at open only if it is a draft now. A window still open at the end of the events closes at the PR's
#     closedAt (closed while draft); with no closedAt it is right-censored and out of the cohort.
#   Cohort: PRs with at least one QUALIFYING window: opened at or after the period start AND closed before the period
#     end (no right-censored open drafts, no windows clipped at either edge).
#   Draft push: a distinct head_sha whose FIRST ci.yml pull_request run was created inside a qualifying window of the
#     PR. Runs are joined to PRs by head_branch against the PR's branch, NEVER by the run's pull_requests[] array
#     (empty for about 92% of real runs). A branch name claimed by more than one PR is excluded and counted.
#   Draft run: a run row (any SHA) created inside a qualifying window. Failed push: a draft push whose first run
#     concluded `failure`.
#   POLICY_FLOOR_MEAN = (pushes - failed pushes) / cohort PRs: the lowest mean the (unenforced) policy "no draft push
#     before a local --affected run passes" could leave if it removed EVERY CI-failed push. It is a stated substitute
#     for a post-policy measurement that cannot be taken while the policy is enforced nowhere.
#
# VERDICT (integer cross-multiplication: 2.75 = 11/4, so `x * 4 >= 11 * N`; the LOWER of the distinct-SHA and the run
#   basis decides, and a float compare of a rounded mean is never used)
#   FAIL            lower-basis mean below 2.75. Monotone: the policy only removes pushes. Branch A: stop rule.
#   PASS            mean at or above 2.75 AND POLICY_FLOOR_MEAN at or above 2.75. Branch B: full implementation.
#   INDETERMINATE   mean at or above 2.75, floor below it. Branch C: hold.
#   REFUSED         (exit 3, no mean on stdout) a slice does not reconcile to the API total_count, a slice file is
#                   missing or holds another day's run, unmapped runs exceed 5% (unmapped * 20 > runs), the cohort is
#                   empty, a PR timeline was truncated, or a timestamp is malformed. Fix the instrument; never decide on it.
#
# OUTPUT (stdout, nothing else): KEY=value lines, then SPLIT rows (tab separated: bucket, PRs, pushes, mean).
#   REPO WINDOW_START WINDOW_END DAYS COHORT_PRS DRAFT_PUSHES DRAFT_RUNS MEAN_PUSHES_DISTINCT_SHA MEAN_RUNS MEDIAN
#   FAILED_PUSHES FAILED_PUSH_SHARE POLICY_FLOOR_MEAN POLICY_FLOOR_ASSUMPTION READY_TRANSITIONS BOT_READY_TRANSITIONS
#   UNMAPPED_RUNS EXCLUDED_BRANCH_COLLISIONS SLICES_RECONCILED VERDICT
#   READY_TRANSITIONS counts every ReadyForReviewEvent in the period over all listed PRs (the dark-window cost input);
#   BOT_READY_TRANSITIONS counts those on bot-authored PRs (they run no CI today and would gain one full run per human
#   ready click). SPLIT divides the cohort into thirds of the period by PR creation day.
#   --rows FILE writes one tab-separated line per cohort PR: number, windows, pushes, runs, failed.
#   Exit codes: 0 verdict printed, 2 usage/environment/fetch error, 3 REFUSED.
#
# RECIPE (the plan's Phase 1 command; redirect, then attach to the issue)
#   env -u GITHUB_ACTIONS bash scripts/ci-draft-push-census.sh --end <UTC-day> --days 30 --rows rows.tsv > summary.txt
#   Live fetch: one GraphQL search per UTC day for the period plus 14 days before it (PRs created earlier own runs inside
#   the period), 100 timeline events per PR; one runs call per day (paginated, written to a file, never aggregated with
#   --jq). The fetched directory is kept under ${TMPDIR:-/var/tmp}; its path is on stderr.
set -uo pipefail
export LC_ALL=C

usage() { sed -n '2,/^set -uo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { printf 'census: %s\n' "$*" >&2; exit 2; }

END="" DAYS_N=30 REPO="jikig-ai/soleur" FIXTURE="" ROWS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --end|--days|--repo|--fixture|--rows)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --end) END="$2" ;; --days) DAYS_N="$2" ;; --repo) REPO="$2" ;; --fixture) FIXTURE="$2" ;; --rows) ROWS="$2" ;;
      esac
      shift 2 ;;
    --summary) shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v date >/dev/null 2>&1 || die "date is required"
[[ "$END" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--end must be a UTC day YYYY-MM-DD (got '${END}')"
[[ "$DAYS_N" =~ ^[0-9]+$ ]] && [ "$DAYS_N" -ge 1 ] && [ "$DAYS_N" -le 90 ] || die "--days must be an integer from 1 to 90 (got '${DAYS_N}')"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "--repo must be OWNER/NAME"
END_S=$(date -u -d "${END} 00:00:00" +%s 2>/dev/null) || die "--end is not a valid date: ${END}"
TODAY_S=$(date -u -d "$(date -u +%F) 00:00:00" +%s)
[ "$END_S" -le $((TODAY_S + 86400)) ] || die "--end ${END} is in the future: the period must be closed"

DAYS=()
for ((i = DAYS_N; i >= 1; i--)); do DAYS+=("$(date -u -d "${END} 00:00:00 UTC -${i} days" +%F)"); done
START="${DAYS[0]}T00:00:00Z"
ENDTS="${END}T00:00:00Z"

DIR="" LIVE=0
if [ -n "$FIXTURE" ]; then
  [ -d "$FIXTURE" ] || die "fixture directory not found: ${FIXTURE}"
  DIR="$FIXTURE"
else
  LIVE=1
  [ "${GITHUB_ACTIONS:-}" != "true" ] || die "live mode refuses GITHUB_ACTIONS=true (it would spend the shared GITHUB_TOKEN budget); run it from a developer shell, or use --fixture"
  command -v gh >/dev/null 2>&1 || die "gh is required in live mode"
  command -v timeout >/dev/null 2>&1 || die "timeout is required in live mode"
  DIR=$(mktemp -d "${TMPDIR:-/var/tmp}/ci-draft-push-census.XXXXXXXX") || die "mktemp -d failed"
  printf 'census: data dir: %s (delete with: rm -rf %q)\n' "$DIR" "$DIR" >&2
fi

GH_TO="${CENSUS_GH_TIMEOUT:-120}"
RETRY_SLEEP="${CENSUS_RETRY_SLEEP:-5}"
ghcall() { # <outfile> <gh args...>: bounded, retried twice, aborts naming the call
  local out="$1" a rc msg
  shift
  for a in 1 2 3; do
    rc=0
    timeout --foreground "$GH_TO" gh "$@" >"$out" 2>"${out}.err" || rc=$?
    if [ "$rc" -eq 0 ]; then rm -f "${out}.err"; return 0; fi
    msg=$(head -c 300 "${out}.err" 2>/dev/null | tr '\n' ' ')
    printf 'census: gh call failed (attempt %d of 3, rc %d): %s\n' "$a" "$rc" "$msg" >&2
    [ "$a" -lt 3 ] && sleep $((a * RETRY_SLEEP))
  done
  case "$msg" in *403*|*429*|*rate*limit*) printf 'census: this looks like a rate limit (HTTP 403/429)\n' >&2 ;; esac
  return 1
}

if [ "$LIVE" -eq 1 ]; then
  PRQ='query($searchQuery: String!, $cursor: String) { search(query: $searchQuery, type: ISSUE, first: 50, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { ... on PullRequest { number headRefName createdAt closedAt isDraft author { __typename } timelineItems(first: 100, itemTypes: [READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT]) { totalCount nodes { __typename ... on ReadyForReviewEvent { createdAt } ... on ConvertToDraftEvent { createdAt } } } } } } }'
  : >"${DIR}/prs.ndjson"
  FIRST_PR_DAY=$(date -u -d "${DAYS[0]} 00:00:00 UTC -14 days" +%F)
  d="$FIRST_PR_DAY"
  while [ "$(date -u -d "$d" +%s)" -lt "$END_S" ]; do
    cursor=""
    while :; do
      printf 'census: PRs created %s\n' "$d" >&2
      args=(api graphql -f "query=${PRQ}" -f "searchQuery=repo:${REPO} is:pr created:${d}..${d}")
      [ -z "$cursor" ] || args+=(-f "cursor=${cursor}")
      ghcall "${DIR}/pr-page.json" "${args[@]}" || die "could not fetch the PRs created on ${d}"
      jq -c '.data.search.nodes[]? | select(.number != null) | {number, branch: .headRefName, createdAt, closedAt, isDraft,
             isBot: ((.author.__typename // "") == "Bot"), timelineTotal: (.timelineItems.totalCount // 0),
             events: [(.timelineItems.nodes // [])[] | {type: .__typename, at: .createdAt}]}' "${DIR}/pr-page.json" >>"${DIR}/prs.ndjson" \
        || die "could not read the PR page for ${d}"
      more=$(jq -r '.data.search.pageInfo.hasNextPage // false' "${DIR}/pr-page.json") || die "could not read the PR page info for ${d}"
      [ "$more" = "true" ] || break
      cursor=$(jq -r '.data.search.pageInfo.endCursor // empty' "${DIR}/pr-page.json") || die "could not read the PR cursor for ${d}"
      [ -n "$cursor" ] || die "a PR page said it has more but gave no cursor (${d})"
    done
    d=$(date -u -d "${d} 00:00:00 UTC +1 day" +%F)
  done
  jq -s '.' "${DIR}/prs.ndjson" >"${DIR}/prs.json" || die "could not assemble prs.json"
  rm -f "${DIR}/prs.ndjson" "${DIR}/pr-page.json"
  for d in "${DAYS[@]}"; do
    printf 'census: runs created %s\n' "$d" >&2
    ghcall "${DIR}/runs-raw-${d}.json" api --paginate \
      "repos/${REPO}/actions/workflows/ci.yml/runs?event=pull_request&created=${d}T00:00:00Z..${d}T23:59:59Z&per_page=100" \
      || die "could not fetch the runs created on ${d}"
    jq -c '{total_count, workflow_runs: [(.workflow_runs // [])[] | {id, head_sha, head_branch, created_at, event, run_attempt, conclusion}]}' \
      "${DIR}/runs-raw-${d}.json" >"${DIR}/runs-${d}.json" || die "could not read the runs listing of ${d}"
    rm -f "${DIR}/runs-raw-${d}.json"
  done
fi

[ -f "${DIR}/prs.json" ] || die "prs.json not found in ${DIR}"

# One aggregator for both modes. Any REFUSED condition is raised as error("REFUSED: ...") and mapped to exit 3 below.
read -r -d '' AGG <<'JQ'
def f2: ((. * 100 + 0.5) | floor) as $c | "\(($c / 100) | floor).\(("0" + (($c % 100) | tostring))[-2:])";
def tsok: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
def inwin($t): any(.[]; $t >= .open and $t < .close);
. as $dayDocs
| ($prs[0]) as $allprs
| if ($allprs | type) != "array" then error("REFUSED: prs.json is not an array") else . end
| ([$allprs[] | (.createdAt, (.closedAt // empty), (.events[]?.at)) | select(tsok | not)] | length) as $badts
| if $badts > 0 then error("REFUSED: \($badts) malformed timestamp(s) in prs.json") else . end
| ([$allprs[] | select((.timelineTotal // 0) > ((.events // []) | length))] | length) as $trunc
| if $trunc > 0 then error("REFUSED: \($trunc) PR timeline(s) truncated (more events than were fetched)") else . end
| ($dayDocs | map(
    . as $doc
    | ($doc.pages // []) as $pages
    | if ($pages | length) == 0 then error("REFUSED: slice \($doc.day) is empty (no listing page)") else . end
    | ([$pages[].workflow_runs[]? | select(.event == "pull_request")]) as $rows
    | (($pages[0].total_count) // -1) as $tc
    | if ($rows | length) != $tc then error("REFUSED: slice \($doc.day) does not reconcile: \($rows | length) rows against total_count \($tc)") else . end
    | if any($rows[]; (.created_at | tsok | not) or (.created_at[0:10] != $doc.day)) then error("REFUSED: slice \($doc.day) holds a run outside its slice or with a malformed created_at") else . end
    | $rows[])) as $nested
| ($nested | flatten) as $runs
| if ($runs | length) == 0 then error("REFUSED: the period holds no runs") else . end
| ($allprs | group_by(.branch) | map(select(length > 1)) ) as $dups
| ($dups | length) as $ncoll
| ($dups | map(.[0].branch)) as $collbranches
| ($allprs | map(.branch)) as $allbranches
| ([$runs[] | .head_branch as $hb | select(($hb == null) or ($hb == "") or (($allbranches | any(. == $hb)) | not))] | length) as $unmapped
| if ($unmapped * 20) > ($runs | length) then error("REFUSED: \($unmapped) of \($runs | length) runs are unmapped (above 5%); the join is broken or the PR listing is incomplete") else . end
| ($allprs | map(
    . as $p
    | ((.events // []) | sort_by(.at)) as $ev
    | (if ($ev | length) > 0 then ($ev[0].type == "ReadyForReviewEvent") else (.isDraft == true) end) as $draft0
    | (reduce $ev[] as $e ({cur: (if $draft0 then $p.createdAt else null end), wins: []};
        if $e.type == "ReadyForReviewEvent" and .cur != null then .wins += [{open: .cur, close: $e.at}] | .cur = null
        elif $e.type == "ConvertToDraftEvent" and .cur == null then .cur = $e.at
        else . end)) as $st
    | ($st.wins + (if $st.cur != null and ($p.closedAt != null) then [{open: $st.cur, close: $p.closedAt}] else [] end)) as $wins
    | $p + {wins: ($wins | map(select(.open >= $start and .close < $end)))})) as $withwins
| ($withwins | map(select((.wins | length) > 0 and ((.branch as $b | ($collbranches | any(. == $b)) | not))))) as $cohort
| if ($cohort | length) == 0 then error("REFUSED: the cohort is empty (no closed draft window opened inside the period)") else . end
| ($cohort | map(
    . as $p
    | ($runs | map(select(.head_branch == $p.branch))) as $mine
    | ($mine | map(select(.created_at as $t | $p.wins | inwin($t)))) as $druns
    | ($druns | group_by(.head_sha) | map(sort_by([.created_at, .id])[0])) as $first
    | {number: $p.number, createdAt: $p.createdAt, windows: ($p.wins | length), pushes: ($first | length), runs: ($druns | length),
       failed: ($first | map(select(.conclusion == "failure")) | length)})) as $rows
| ($rows | length) as $n
| ($rows | map(.pushes) | add) as $P
| ($rows | map(.runs) | add) as $R
| ($rows | map(.failed) | add) as $F
| (if $P < $R then $P else $R end) as $base
| (($rows | map(.pushes) | sort) as $s | if ($s | length) % 2 == 1 then $s[($s | length) / 2 | floor] else (($s[($s | length) / 2 - 1] + $s[($s | length) / 2]) / 2) end) as $median
| ([$allprs[] | .isBot as $bot | (.events // [])[] | select(.type == "ReadyForReviewEvent" and .at >= $start and .at < $end) | $bot]) as $readys
| (if ($base * 4) < (11 * $n) then "FAIL" elif (($P - $F) * 4) >= (11 * $n) then "PASS" else "INDETERMINATE" end) as $verdict
| ($dayDocs | length) as $ndays
| ($start[0:10] | strptime("%Y-%m-%d") | mktime) as $start_s
| ($rows | map(. + {bucket: (([0, ((((.createdAt[0:10] | strptime("%Y-%m-%d") | mktime) - $start_s) / 86400 | floor) * 3 / $ndays | floor)] | max) + 1)})) as $bucketed
| [
    "REPO=\($repo)",
    "WINDOW_START=\($start)",
    "WINDOW_END=\($end)",
    "DAYS=\($ndays)",
    "COHORT_PRS=\($n)",
    "DRAFT_PUSHES=\($P)",
    "DRAFT_RUNS=\($R)",
    "MEAN_PUSHES_DISTINCT_SHA=\($P / $n | f2)",
    "MEAN_RUNS=\($R / $n | f2)",
    "MEDIAN=\($median | f2)",
    "FAILED_PUSHES=\($F)",
    "FAILED_PUSH_SHARE=\(if $P == 0 then "n/a" else ($F / $P | f2) end)",
    "POLICY_FLOOR_MEAN=\(($P - $F) / $n | f2)",
    "POLICY_FLOOR_ASSUMPTION=assumes the unenforced policy removes EVERY CI-failed push (distinct-SHA basis); a stated substitute for a post-policy measurement",
    "READY_TRANSITIONS=\($readys | length)",
    "BOT_READY_TRANSITIONS=\($readys | map(select(.)) | length)",
    "UNMAPPED_RUNS=\($unmapped)",
    "EXCLUDED_BRANCH_COLLISIONS=\($ncoll)",
    "SLICES_RECONCILED=\($ndays)",
    "VERDICT=\($verdict)"
  ] + [range(1; 4) as $b
       | ($bucketed | map(select(.bucket == $b))) as $in
       | "SPLIT\t\($b)\t\($in | length)\t\($in | map(.pushes) | add // 0)\t\(if ($in | length) == 0 then "n/a" else (($in | map(.pushes) | add) / ($in | length) | f2) end)"]
  | {lines: ., rows: ($rows | sort_by(.number) | map("\(.number)\t\(.windows)\t\(.pushes)\t\(.runs)\t\(.failed)"))}
JQ

# per-day documents -> one slurped stream for the aggregator
DAYDOCS=$(mktemp "${TMPDIR:-/var/tmp}/ci-draft-push-census-days.XXXXXXXX") || die "mktemp failed"
RESULT=$(mktemp "${TMPDIR:-/var/tmp}/ci-draft-push-census-out.XXXXXXXX") || die "mktemp failed"
AGGERR=$(mktemp "${TMPDIR:-/var/tmp}/ci-draft-push-census-err.XXXXXXXX") || die "mktemp failed"
cleanup() { rm -f "$DAYDOCS" "$RESULT" "$AGGERR"; }
trap cleanup EXIT
for d in "${DAYS[@]}"; do
  f="${DIR}/runs-${d}.json"
  if [ ! -s "$f" ]; then
    printf 'census: REFUSED: slice file for %s is missing or empty (%s)\n' "$d" "$f" >&2
    exit 3
  fi
  jq -s -c --arg day "$d" '{day: $day, pages: .}' "$f" >>"$DAYDOCS" || die "could not read the slice file ${f}"
done

rc=0
jq -n -c --slurpfile prs "${DIR}/prs.json" --arg start "$START" --arg end "$ENDTS" --arg repo "$([ "$LIVE" -eq 1 ] && echo "$REPO" || echo fixture)" \
  "[inputs] | ${AGG}" "$DAYDOCS" >"$RESULT" 2>"$AGGERR" || rc=$?
if [ "$rc" -ne 0 ]; then
  msg=$(sed -n 's/^jq: error (at [^)]*): //p' "$AGGERR" | head -1)
  case "$msg" in
    REFUSED:*) printf 'census: %s\n' "$msg" >&2; exit 3 ;;
    *) printf 'census: the aggregator failed (rc %d): %s\n' "$rc" "$(head -c 400 "$AGGERR")" >&2; exit 2 ;;
  esac
fi

jq -r '.lines[]' "$RESULT" || die "could not print the result"
if [ -n "$ROWS" ]; then
  jq -r '.rows[]' "$RESULT" >"$ROWS" || die "could not write ${ROWS}"
fi
exit 0
