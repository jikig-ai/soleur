#!/usr/bin/env bash
# ratchet-observation-window-10865.sh — follow-through probe for #10865: the observation window of the ADVISORY `affected-index-ratchet` job
# (S4 index completion PR3a, #10851; tracker #10448; ADR-276 amendment). Closing #10865 records that the window passed. It does NOT authorize
# PR3b (#10859, which makes the context required): that stays held for the budget owner.
#
# READ-ONLY. It lists the `pull_request` and `merge_group` runs of ci.yml created after the PR3a merge (PR3a's own runs do not count), proves the
# job RAN from the jobs JSON (a job that was skipped, or whose ratchet step did not conclude success or failure, did not run), and reads the
# job log for the EMITTED marker line, never the echoed `run:` source: the job log is `<ISO-8601Z timestamp> <text>` per line, and the marker is
#   <timestamp> SOLEUR_PR_AFFECTED_RATCHET exit=<0|1|2> reason=<token> live=<n> baseline=<n>
# end-anchored. The workflow's own source is echoed into the log too (as indented, colourised text that never starts right after the timestamp),
# so an unanchored pattern would count it on every healthy run. A job log can start with a byte-order mark: it is stripped.
#
# EXIT 0 ONLY WHEN EVERY CRITERION HOLDS (never on partial evidence). This is a CLOSING probe, so "not yet" is exit 1 (the sweeper comments and
# leaves the tracker open); exit 2 is NOT used. Any criterion unmet or an unclassified exit 2 is 1.
#   (a) at least MIN_PR (3) green pull_request units from 3 DISTINCT PRs, at least one touching `scripts/` or a suite file; a throwaway canary PR
#       (head branch `canary-*`) is excluded from the distinct count;
#   (b) at least MIN_MG (3) green merge_group units on 3 distinct head SHAs;
#   (c) green = job `success`... and the marker `exit=0 reason=pass` (the jobs-API conclusion of a failing job-level continue-on-error job is
#       unsettled in-repo until the canary is read, so the marker is the evidence and the job must have RUN); a genuine `exit=1` (a real new
#       pair) is NOT green and does NOT restart the window;
#   (d) job wall time over the green units (completed_at - started_at): p95 (nearest rank) at most P95_MAX (210) s and the maximum at most
#       MAX_MAX (270) s;
#   (e) composition among the green pull_request units: one docs-only PR (every file a knowledge-base markdown file or a root markdown file), one
#       DRAFT PR (read from the issue timeline: draft at the unit's own time), and one bot PR (a user of type Bot) when one occurs; when none
#       occurs by REVIEW_DAYS (30) days after the merge the committed synthetic-green unit test substitutes and the substitution is printed;
#   (f) the window PAUSES (exit 1) while the latest merge_group unit is red (an exit 1 or an unresolved exit 2);
#   (g) an exit 2 (or a non-success job with no marker, which counts as exit 2) is classified by a same-SHA RERUN with no code change: a rerun
#       that passes is an INCIDENT (the unit is excluded, the window is not restarted); a rerun that reproduces is a DEFECT (the window RESTARTS
#       at that run: only later units count); an exit 2 never rerun is unclassified, so exit 1 naming the run.
#
# Exit codes (sweep-followthroughs.sh contract): 0 PASS; 1 FAIL (criteria not met); 3 CANNOT ESTABLISH (a tool, GH_TOKEN or a read failed, or a
# job log carried no marker for a run that concluded success: the sweeper retries); 78 refused to run under xtrace while GH_TOKEN is set (#7797).
# Test seams (inert under the sweeper's env -i): SOAK_NOW_EPOCH. The rows live in plugins/soleur/test/ci-pr-affected-replay.test.sh
# (stub gh; a registered scripts/followthroughs/*.test.sh would need a run_suite line in scripts/test-all.sh).
#
# CREDENTIAL POSTURE: needs GH_TOKEN, declared in the tracker directive's `secrets=GH_TOKEN` clause, for REST reads of Actions metadata, job logs, pulls
# and issue timelines (public repository). It holds no other secret and writes nothing. It refuses to run under xtrace (the token would print).
#
# RETIREMENT: when #10865 closes, delete this file and its rows in plugins/soleur/test/ci-pr-affected-replay.test.sh (the section
# "ratchet observation window"), and the directive on #10865. References: scripts/followthroughs/ratchet-observation-window-10865.sh in
# knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md (the observation log) and in ADR-276's PR3a amendment.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe holds GH_TOKEN and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

REPO="jikig-ai/soleur"
PR3A=10851
JOB="affected-index-ratchet"
STEP="Ratchet the audit against the committed baseline"
MIN_PR=3
MIN_MG=3
P95_MAX=210
MAX_MAX=270
REVIEW_DAYS=30
MAX_RUNS=60
for need in gh jq date sort mktemp rm sed awk; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }
NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_NOW_EPOCH is not an epoch"; exit 3; }

fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }
api() { gh api "$1" 2>/dev/null; }                                  # the request path is the LAST argument
log_api() { gh api --allow-escape-sequences "$1" 2>/dev/null; }
WORK="$(mktemp -d)" || { echo "CANNOT ESTABLISH: mktemp failed"; exit 3; }
trap 'rm -rf "$WORK"' EXIT
UNITS="$WORK/units.tsv"; : > "$UNITS"
MARKER_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z SOLEUR_PR_AFFECTED_RATCHET exit=([012]) reason=([a-z0-9-]+) live=[0-9]+ baseline=[0-9]+$'

# --- the PR3a merge --------------------------------------------------------------------------------------------------------------
pr_json="$(api "repos/$REPO/pulls/$PR3A")" || fail_api "pull $PR3A"
merged_at="$(jq -r '.merged_at // empty' <<<"$pr_json" 2>/dev/null)" || fail_api "pull $PR3A (parse)"
[ -n "$merged_at" ] || { echo "FAIL: PR $PR3A is not merged yet: the window has not opened"; exit 1; }
merged_epoch="$(date -u -d "$merged_at" +%s 2>/dev/null)" || fail_api "merge time $merged_at"
age_days=$(( (NOW - merged_epoch) / 86400 ))

# --- read one job: sets RJ_EX, RJ_REASON, RJ_WALL, RJ_RAN (RJ_EX is 2 with reason no-marker when the job concluded without an emitted marker) ---------
# Called in the main shell, never in a command substitution: fail_api's `exit` must end the probe.
read_job() {   # <jobs json> <run id>
  local jobs="$1" run="$2" j jid conc started completed step log line t0 t1
  RJ_EX=none; RJ_REASON=none; RJ_WALL=0; RJ_RAN=0
  j="$(jq -c --arg n "$JOB" '[.jobs[]? | select(.name == $n)] | .[0] // empty' <<<"$jobs" 2>/dev/null)" || fail_api "run $run jobs (parse)"
  [ -n "$j" ] || return 0
  jid="$(jq -r '.id' <<<"$j")"; conc="$(jq -r '.conclusion // ""' <<<"$j")"
  started="$(jq -r '.started_at // ""' <<<"$j")"; completed="$(jq -r '.completed_at // ""' <<<"$j")"
  step="$(jq -r --arg s "$STEP" '[.steps[]? | select(.name == $s) | .conclusion][0] // ""' <<<"$j")"
  if [ "$conc" = skipped ] || [ -z "$conc" ] || { [ "$step" != success ] && [ "$step" != failure ]; } || [ -z "$started" ] || [ -z "$completed" ]; then return 0; fi
  t0="$(date -u -d "$started" +%s 2>/dev/null)" && t1="$(date -u -d "$completed" +%s 2>/dev/null)" || fail_api "run $run job times"
  RJ_RAN=1; RJ_WALL=$((t1 - t0))
  log="$(log_api "repos/$REPO/actions/jobs/$jid/logs")" || fail_api "run $run job log"
  line="$(printf '%s\n' "$log" | sed 's/^\xef\xbb\xbf//' | tr -d '\r' | grep -E "$MARKER_RE" | tail -n 1)"
  if [ -z "$line" ]; then
    [ "$conc" != success ] || fail_api "run $run job log: a successful ratchet job printed no emitted marker line"
    RJ_EX=2; RJ_REASON=no-marker; return 0   # a non-success run with no annotation counts as exit 2
  fi
  [[ "$line" =~ $MARKER_RE ]] || fail_api "run $run marker (parse)"
  RJ_EX="${BASH_REMATCH[1]}"; RJ_REASON="${BASH_REMATCH[2]}"
}

# --- the units: every completed pull_request and merge_group run since the merge, oldest first ---------------------------------------------
for ev in pull_request merge_group; do
  runs="$(api "repos/$REPO/actions/workflows/ci.yml/runs?event=$ev&status=completed&per_page=100&created=%3E$merged_at")" || fail_api "ci.yml $ev runs"
  rows="$(jq -r --argjson cap "$MAX_RUNS" '[.workflow_runs[]? | select(.created_at > "'"$merged_at"'")] | sort_by(.created_at) | reverse | .[0:$cap] | reverse | .[]
           | [.id, .head_sha, (.head_branch // ""), .created_at, (.run_attempt // 1), ((.pull_requests[0].number // 0) | tostring)] | @tsv' <<<"$runs" 2>/dev/null)" \
    || fail_api "ci.yml $ev runs (parse)"
  while IFS=$'\t' read -r id sha branch created attempt prn; do
    [ -n "$id" ] || continue
    jobs="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest")" || fail_api "run $id jobs"
    if [ "$(jq -r '(.total_count // 0) > ((.jobs // []) | length)' <<<"$jobs" 2>/dev/null)" != false ]; then fail_api "run $id jobs (truncated or unparseable)"; fi
    read_job "$jobs" "$id"
    [ "$RJ_RAN" = 1 ] || continue   # the job did not run on this run (skipped, absent): not a unit
    ex="$RJ_EX"; reason="$RJ_REASON"; wall="$RJ_WALL"
    cls="plain"
    if [ "$ex" = 2 ] && [ "$attempt" -gt 1 ]; then
      cls="defect"   # classified by the SAME-SHA rerun: the latest attempt (read above) reproduced the exit 2
    elif [ "$attempt" -gt 1 ]; then
      # attempt 1 was the first reading: an exit 2 there that the rerun did not reproduce is an incident
      jobs1="$(api "repos/$REPO/actions/runs/$id/attempts/1/jobs?per_page=100")" || fail_api "run $id attempt 1 jobs"
      read_job "$jobs1" "$id"
      if [ "$RJ_RAN" = 1 ] && [ "$RJ_EX" = 2 ]; then cls="incident"; fi
    elif [ "$ex" = 2 ]; then
      cls="unclassified"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$ev" "$sha" "$branch" "$created" "$prn" "$ex" "$reason" "$wall" "$cls" >> "$UNITS"
  done <<<"$rows"
done
sort -t$'\t' -k5,5 -o "$UNITS" "$UNITS" || fail_api "unit sort"

# --- the window: a defect restarts it, an incident excludes its unit, an unclassified exit 2 is unmet -----------------------------------------------
fails=()
restart="$(awk -F'\t' '$10 == "defect" && $5 > m { m = $5 } END { print m }' "$UNITS")"
[ -z "$restart" ] || echo "window restarted at $restart (a same-SHA rerun reproduced an exit 2: a defect)"
unclassified="$(awk -F'\t' -v r="${restart:-}" '$10 == "unclassified" && $5 > r { printf "%s ", $1 }' "$UNITS")"
[ -z "$unclassified" ] || fails+=("exit 2 never rerun on run(s) ${unclassified}(rerun with no code change to classify it as an incident or a defect)")
GREEN="$WORK/green.tsv"
awk -F'\t' -v r="${restart:-}" '$5 > r && $7 == 0 && $10 == "plain" { print }' "$UNITS" > "$GREEN"
last_mg="$(awk -F'\t' '$2 == "merge_group" { l = $0 } END { print l }' "$UNITS")"
if [ -n "$last_mg" ]; then
  mg_ex="$(cut -f7 <<<"$last_mg")"; mg_cls="$(cut -f10 <<<"$last_mg")"
  if [ "$mg_ex" != 0 ] && [ "$mg_cls" != incident ]; then fails+=("paused: the latest merge_group unit (run $(cut -f1 <<<"$last_mg")) is red (exit=$mg_ex $(cut -f8 <<<"$last_mg")): repair main first")
  fi
fi

# --- per-PR facts (cached): canary, files, user type, draft-at-run ------------------------------------------------------------------------------
declare -A PR_DOCS PR_SCRIPTS PR_BOT PR_CANARY
pr_facts() {   # <pr number>
  local n="$1" p files tl
  [ -z "${PR_DOCS[$n]+x}" ] || return 0
  p="$(api "repos/$REPO/pulls/$n")" || fail_api "pull $n"
  files="$(api "repos/$REPO/pulls/$n/files?per_page=100")" || fail_api "pull $n files"
  PR_BOT[$n]="$(jq -r 'if ((.user.type // "") == "Bot") then 1 else 0 end' <<<"$p" 2>/dev/null)" || fail_api "pull $n (parse)"
  PR_CANARY[$n]="$(jq -r 'if ((.head.ref // "") | startswith("canary-")) then 1 else 0 end' <<<"$p" 2>/dev/null)" || fail_api "pull $n (parse)"
  PR_DOCS[$n]="$(jq -r 'if length > 0 and all(.[]; (.filename | test("^knowledge-base/.*\\.md$") or test("^[^/]+\\.md$"))) then 1 else 0 end' <<<"$files" 2>/dev/null)" || fail_api "pull $n files (parse)"
  PR_SCRIPTS[$n]="$(jq -r 'if any(.[]; .filename | test("^scripts/") or test("^plugins/soleur/test/") or test("\\.test\\.(sh|ts)$")) then 1 else 0 end' <<<"$files" 2>/dev/null)" || fail_api "pull $n files (parse)"
}
draft_at() {   # <pr number> <ISO time>: sets DRAFT to 1 when the PR was a draft at that time (timeline: convert_to_draft / ready_for_review toggles)
  local n="$1" t="$2" tl cur curdraft
  tl="$(api "repos/$REPO/issues/$n/timeline?per_page=100")" || fail_api "timeline $n"
  cur="$(api "repos/$REPO/pulls/$n")" || fail_api "pull $n"
  curdraft="$(jq '.draft // false' <<<"$cur" 2>/dev/null)" || fail_api "pull $n (parse)"
  DRAFT="$(jq -r --arg t "$t" --argjson cur "$curdraft" '
      [.[]? | select(.event == "convert_to_draft" or .event == "ready_for_review") | {e: .event, at: .created_at}] | sort_by(.at) as $ev
      | (if ($ev | length) == 0 then $cur else ($ev[0].e == "ready_for_review") end) as $start
      | reduce ($ev[] | select(.at <= $t)) as $x ($start; $x.e == "convert_to_draft") | if . then 1 else 0 end' <<<"$tl" 2>/dev/null)" || fail_api "timeline $n (parse)"
}

# --- the counts -------------------------------------------------------------------------------------------------------------------------------
pr_units="$(awk -F'\t' '$2 == "pull_request"' "$GREEN")"
mg_n="$(awk -F'\t' '$2 == "merge_group" { print $3 }' "$GREEN" | sort -u | grep -c .)"
declare -A SEEN_KEY; distinct=0; any_scripts=0; docs_seen=0; draft_seen=0; bot_seen=0; bot_bad=0
while IFS=$'\t' read -r id ev sha branch created prn ex reason wall cls; do
  [ -n "$id" ] || continue
  key="$prn"; [ "$prn" != 0 ] || key="branch:$branch"
  if [ "$prn" != 0 ]; then
    pr_facts "$prn"
    [ "${PR_CANARY[$prn]}" != 1 ] || continue   # the throwaway canary is excluded from the distinct count
    [ "${PR_SCRIPTS[$prn]}" != 1 ] || any_scripts=1
    [ "${PR_DOCS[$prn]}" != 1 ] || docs_seen=1
    [ "${PR_BOT[$prn]}" != 1 ] || bot_seen=1
    if [ "$draft_seen" != 1 ]; then draft_at "$prn" "$created"; [ "$DRAFT" != 1 ] || draft_seen=1; fi
  fi
  [ -z "${SEEN_KEY[$key]+x}" ] || continue
  SEEN_KEY[$key]=1; distinct=$((distinct + 1))
done <<<"$pr_units"
# a bot PR unit that was NOT green (an exit 1 or 2 on a bot PR) is a failure of the bot criterion
while IFS=$'\t' read -r id ev sha branch created prn ex reason wall cls; do
  [ -n "$id" ] && [ "$ev" = pull_request ] && [ "$prn" != 0 ] && [ "$ex" != 0 ] && [ "$cls" != incident ] || continue
  pr_facts "$prn"; [ "${PR_BOT[$prn]}" != 1 ] || { bot_seen=1; bot_bad=1; }
done < <(awk -F'\t' -v r="${restart:-}" '$5 > r' "$UNITS")
walls="$(cut -f9 "$GREEN" | sort -n)"
n_g="$(printf '%s\n' "$walls" | grep -c .)"
p95=0; max=0
if [ "$n_g" -gt 0 ]; then
  rank=$(( (n_g * 95 + 99) / 100 )); p95="$(printf '%s\n' "$walls" | sed -n "${rank}p")"; max="$(printf '%s\n' "$walls" | tail -n 1)"
fi
echo "window opened=$merged_at age_days=$age_days green_pr_units_distinct_prs=$distinct green_merge_group_shas=$mg_n scripts_pr=$any_scripts docs_only=$docs_seen draft=$draft_seen bot=$bot_seen wall_p95_s=$p95 wall_max_s=$max units=$n_g"

(( distinct >= MIN_PR )) || fails+=("only $distinct distinct green pull_request PR(s) (need $MIN_PR)")
(( mg_n >= MIN_MG )) || fails+=("only $mg_n green merge_group SHA(s) (need $MIN_MG)")
(( any_scripts == 1 )) || fails+=("no green pull_request unit is from a PR touching scripts/ or a suite file")
(( docs_seen == 1 )) || fails+=("no green docs-only PR in the window")
(( draft_seen == 1 )) || fails+=("no green DRAFT PR run in the window (draft-push billed minutes are recorded for the PR3b draft-light re-examination)")
if (( bot_bad == 1 )); then fails+=("a bot PR unit was red")
elif (( bot_seen == 0 )); then
  if (( age_days >= REVIEW_DAYS )); then echo "bot PR: none occurred in $age_days days; the committed synthetic-green unit test substitutes (recorded)"
  else fails+=("no bot PR in the window yet (the synthetic-green unit test substitutes only after $REVIEW_DAYS days)"); fi
fi
if (( n_g > 0 )); then
  (( p95 <= P95_MAX )) || fails+=("wall p95 ${p95}s is over $P95_MAX s")
  (( max <= MAX_MAX )) || fails+=("wall max ${max}s is over $MAX_MAX s")
else
  fails+=("no green unit to take a wall time from")
fi
if (( ${#fails[@]} > 0 )); then
  printf 'FAIL: %s\n' "${fails[@]}"
  exit 1
fi
echo "PASS: the window held: $distinct distinct PRs and $mg_n merge_group SHAs green, wall p95 ${p95}s max ${max}s, docs-only, draft and bot coverage as above. Closing #10865 does not authorize PR3b (#10859)."
exit 0
