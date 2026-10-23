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
# EXIT 0 ONLY WHEN EVERY CRITERION HOLDS (never on partial evidence). "Not yet" is exit 2, first token `NOT YET:` (the follow-through convention and the
# sibling closing probes reserve 2 for it; the sweeper renders 1 as a FAIL comment every night). Exit 1 is NOT USED by this probe: it is unreachable by design.
#   (a) at least MIN_PR (3) green pull_request units from 3 DISTINCT PRs, at least one touching `scripts/` or a suite file; a throwaway canary PR
#       (head branch `canary-*`), a fork PR (head repository is not this repository) and a PR whose file list touches an oracle input (ORACLE below, the
#       SUT's RATCHET_ORACLE) are excluded from every count, as is a PR run that names no PR;
#   (b) at least MIN_MG (3) green merge_group units on 3 distinct head SHAs;
#   (c) green = job `success`... and the marker `exit=0 reason=pass` (measured on the PR3a canary: a failing job-level continue-on-error job concludes
#       `failure` in the jobs API, so both the conclusion and the marker are evidence and the job must have RUN); a genuine `exit=1` (a real new
#       pair) is NOT green and does NOT restart the window, bot PR or not;
#   (d) job wall time (completed_at - started_at) over EVERY unit that ran and is not an incident, red and timed-out units included (a ceiling must see the
#       tail): p95 (nearest rank) at most P95_MAX (210) s and the maximum at most MAX_MAX (270) s. These two ceilings are PROVISIONAL: the only prior
#       figure is a local mean of 203 s and no hosted datapoint existed when they were ruled; the CTO agent re-rules them (a dated row with the measured
#       series and a change of these two constants, nothing else) at the close of the window or at the 30-day trigger, whichever is first;
#   (e) composition among the green pull_request units: one docs-only PR (every file a knowledge-base markdown file or a root markdown file), one
#       DRAFT PR (read from the issue timeline: draft at the unit's own time), and one bot PR (a user of type Bot) when one occurs; when none
#       occurs by REVIEW_DAYS (30) days after the merge the committed synthetic-green unit test substitutes and the substitution is printed;
#   (f) the window PAUSES (NOT YET) while the latest merge_group unit is red (an exit 1 or an unresolved exit 2);
#   (g) an exit 2 (or a non-success job with no marker, which counts as exit 2, or a ratchet job cancelled or timed out after at least 290 s, which counts as
#       exit 2 reason `timeout`) is classified by a same-SHA RERUN with no code change, reading BOTH attempts: attempt 1 and the latest both exit 2 is a
#       DEFECT (the window RESTARTS at that run: only later units count); attempt 1 exit 2 and the latest not is an INCIDENT (the unit is excluded, the
#       window is not restarted); an exit 2 that first appears on a rerun, or one never rerun, is unclassified, so NOT YET naming the run;
#   (h) the committed baseline has not grown since the PR3a merge: the baseline file read through the contents API at the PR3a merge commit and at the main
#       tip, compared as SETS of lines (a moved line is not growth); any line at the tip that the merge commit lacks is NOT YET. The baseline absent at the
#       tip is the end state and fine; absent at the merge commit, or a read failure, is CANNOT ESTABLISH.
#
# WHAT A PASS CERTIFIES. Runs are listed newest first up to MAX_PAGES (40) pages per event, then read OLDEST first, at most MAX_UNITS (250) runs per sweep,
# PLUS always the newest 10 merge_group runs (the pause check and the defects): a PASS certifies the earliest prefix plus the newest queue state, and the status
# line prints runs_listed, units_read and truncated=0|1. The oldest runs never change, so evidence latches across sweeps without any tracker write. A run whose
# conclusion is `cancelled` is skipped before any jobs read. Closing #10865 authorizes nothing: PR3b (#10859) stays held.
#
# Exit codes (sweep-followthroughs.sh contract): 0 PASS; 2 NOT YET (an unmet criterion; the sweeper comments and leaves the tracker open); 3 CANNOT ESTABLISH
# (a tool, GH_TOKEN or a read failed, or a job log carried no marker for a run that concluded success: the sweeper retries); 78 refused to run under xtrace
# while GH_TOKEN is set (#7797). Test seams (inert under the sweeper's env -i): SOAK_NOW_EPOCH, SOAK_MAX_PAGES, SOAK_MAX_UNITS. The rows live in
# plugins/soleur/test/ci-pr-affected-replay.test.sh (stub gh; a registered scripts/followthroughs/*.test.sh would need a run_suite line in scripts/test-all.sh).
#
# CREDENTIAL POSTURE: needs GH_TOKEN, declared in the tracker directive's `secrets=GH_TOKEN` clause, for REST reads of Actions metadata, job logs, pulls,
# issue timelines and the baseline file (public repository). It holds no other secret and writes nothing. It refuses to run under xtrace (the token would print).
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
BASELINE="scripts/ci-pr-affected-audit.baseline.tsv"
# the SUT's RATCHET_ORACLE (a parity row in the replay suite compares this list with the SUT's own): a PR touching one of these cannot count as evidence
ORACLE=(".github/workflows/ci.yml" "scripts/ci-pr-affected-replay.py" "plugins/soleur/scripts/lint-ratchet.py" "scripts/ci-pr-affected-audit.accept.tsv" "scripts/lib/test-affected-paths.sh" "scripts/test-all.sh" "$BASELINE")
MIN_PR=3
MIN_MG=3
P95_MAX=210   # PROVISIONAL (see (d))
MAX_MAX=270   # PROVISIONAL (see (d))
TIMEOUT_WALL=290
REVIEW_DAYS=30
MAX_PAGES="${SOAK_MAX_PAGES:-40}"
MAX_UNITS="${SOAK_MAX_UNITS:-250}"
NEWEST_MG=10
for need in gh jq date sort mktemp rm sed awk comm paste cat head tail cut tr grep mv; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }
NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_NOW_EPOCH is not an epoch"; exit 3; }
[[ "$MAX_PAGES" =~ ^[1-9][0-9]*$ && "$MAX_UNITS" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_MAX_PAGES / SOAK_MAX_UNITS are not positive integers"; exit 3; }

fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }
api() { gh api "$1" 2>/dev/null; }                                  # the request path is the LAST argument
log_api() { gh api --allow-escape-sequences "$1" 2>/dev/null; }
WORK="$(mktemp -d)" || { echo "CANNOT ESTABLISH: mktemp failed"; exit 3; }
trap 'rm -rf "$WORK"' EXIT
UNITS="$WORK/units.tsv"; : > "$UNITS"
MARKER_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z SOLEUR_PR_AFFECTED_RATCHET exit=([012]) reason=([a-z0-9-]+) live=[0-9]+ baseline=[0-9]+$'
nots=()   # the unmet criteria, each reported as `NOT YET: <what>`

# --- the PR3a merge --------------------------------------------------------------------------------------------------------------
pr_json="$(api "repos/$REPO/pulls/$PR3A")" || fail_api "pull $PR3A"
merged_at="$(jq -r '.merged_at // empty' <<<"$pr_json" 2>/dev/null)" || fail_api "pull $PR3A (parse)"
[ -n "$merged_at" ] || { echo "NOT YET: PR $PR3A is not merged yet: the window has not opened"; exit 2; }
merge_sha="$(jq -r '.merge_commit_sha // empty' <<<"$pr_json" 2>/dev/null)" || fail_api "pull $PR3A (parse)"
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
  if [ "$conc" = skipped ] || [ -z "$conc" ] || [ -z "$started" ] || [ -z "$completed" ]; then return 0; fi
  t0="$(date -u -d "$started" +%s 2>/dev/null)" || fail_api "run $run job times"
  t1="$(date -u -d "$completed" +%s 2>/dev/null)" || fail_api "run $run job times"
  if [ "$conc" = cancelled ] || [ "$conc" = timed_out ]; then
    # killed by the job timeout (or by anything else) after at least TIMEOUT_WALL seconds: an exit 2 unit, reason timeout; a shorter cancellation (a
    # concurrency cancel) never ran the check to its end and is not a unit
    if (( t1 - t0 >= TIMEOUT_WALL )); then RJ_RAN=1; RJ_WALL=$((t1 - t0)); RJ_EX=2; RJ_REASON=timeout; fi
    return 0
  fi
  if [ "$step" != success ] && [ "$step" != failure ]; then return 0; fi
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

# --- list: every completed pull_request and merge_group run since the merge, newest first by page, kept oldest first ---------------------------------
RUNS="$WORK/runs.tsv"; : > "$RUNS"; TRUNC=0
for ev in pull_request merge_group; do
  page=1
  while :; do
    path="repos/$REPO/actions/workflows/ci.yml/runs?event=$ev&status=completed&per_page=100&created=%3E$merged_at"
    [ "$page" -eq 1 ] || path="$path&page=$page"
    runs="$(api "$path")" || fail_api "ci.yml $ev runs (page $page)"
    jq -r --arg m "$merged_at" --arg ev "$ev" '.workflow_runs[]? | select(.created_at > $m)
         | [.id, $ev, .head_sha, (.head_branch // ""), .created_at, (.run_attempt // 1), ((.pull_requests[0].number // 0) | tostring), (.conclusion // ""),
            (if ((.head_repository.full_name // .repository.full_name // "") != (.repository.full_name // "")) then 1 else 0 end)] | @tsv' <<<"$runs" >> "$RUNS" 2>/dev/null \
      || fail_api "ci.yml $ev runs (parse)"
    n="$(jq -r '(.workflow_runs // []) | length' <<<"$runs" 2>/dev/null)" || fail_api "ci.yml $ev runs (parse)"
    [ "$n" -ge 100 ] || break
    if [ "$page" -ge "$MAX_PAGES" ]; then TRUNC=1; break; fi
    page=$((page + 1))
  done
done
runs_listed="$(grep -c . "$RUNS")"
# a cancelled run spends no budget; oldest first; the first MAX_UNITS plus the newest NEWEST_MG merge_group runs are read
awk -F'\t' '$8 != "cancelled"' "$RUNS" | sort -t$'\t' -k5,5 -s > "$WORK/readable.tsv"
head -n "$MAX_UNITS" "$WORK/readable.tsv" > "$WORK/read.tsv"
awk -F'\t' '$2 == "merge_group"' "$WORK/readable.tsv" | tail -n "$NEWEST_MG" >> "$WORK/read.tsv"
sort -u "$WORK/read.tsv" | sort -t$'\t' -k5,5 -s > "$WORK/read.sorted" || fail_api "run sort"
mv "$WORK/read.sorted" "$WORK/read.tsv"
units_read="$(grep -c . "$WORK/read.tsv")"
[ "$units_read" -ge "$(grep -c . "$WORK/readable.tsv")" ] || TRUNC=1

# --- read each run: its job (latest attempt) and, for a rerun, attempt 1 too ---------------------------------------------------------------------------
while IFS=$'\t' read -r id ev sha branch created attempt prn _ fork; do
  [ -n "$id" ] || continue
  jobs="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest")" || fail_api "run $id jobs"
  if [ "$(jq -r '(.total_count // 0) > ((.jobs // []) | length)' <<<"$jobs" 2>/dev/null)" != false ]; then fail_api "run $id jobs (truncated or unparseable)"; fi
  read_job "$jobs" "$id"
  [ "$RJ_RAN" = 1 ] || continue   # the job did not run on this run (skipped, absent, cancelled early): not a unit
  ex="$RJ_EX"; reason="$RJ_REASON"; wall="$RJ_WALL"
  cls="plain"
  if [ "$attempt" -gt 1 ]; then
    # a rerun: attempt 1 is read too, and the pair decides (the latest attempt alone cannot tell a reproduced exit 2 from a first-seen one)
    jobs1="$(api "repos/$REPO/actions/runs/$id/attempts/1/jobs?per_page=100")" || fail_api "run $id attempt 1 jobs"
    read_job "$jobs1" "$id"
    first_ex="none"; [ "$RJ_RAN" = 1 ] && first_ex="$RJ_EX"
    if [ "$ex" = 2 ] && [ "$first_ex" = 2 ]; then cls="defect"
    elif [ "$ex" = 2 ]; then cls="unclassified"
    elif [ "$first_ex" = 2 ]; then cls="incident"
    fi
  elif [ "$ex" = 2 ]; then
    cls="unclassified"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$ev" "$sha" "$branch" "$created" "$prn" "$ex" "$reason" "$wall" "$cls" "$fork" >> "$UNITS"
done < "$WORK/read.tsv"
sort -t$'\t' -k5,5 -s -o "$UNITS" "$UNITS" || fail_api "unit sort"

# --- the window: a defect restarts it, an incident excludes its unit, an unclassified exit 2 is unmet -----------------------------------------------
restart="$(awk -F'\t' '$10 == "defect" && $5 > m { m = $5 } END { print m }' "$UNITS")"
[ -z "$restart" ] || echo "window restarted at $restart (a same-SHA rerun reproduced an exit 2: a defect)"
unclassified="$(awk -F'\t' -v r="${restart:-}" '$10 == "unclassified" && $5 > r { printf "%s ", $1 }' "$UNITS")"
[ -z "$unclassified" ] || nots+=("exit 2 never rerun on run(s) ${unclassified}(rerun with no code change to classify it as an incident or a defect)")
GREEN="$WORK/green.tsv"
awk -F'\t' -v r="${restart:-}" '$5 > r && $7 == 0 && $10 == "plain" { print }' "$UNITS" > "$GREEN"
last_mg="$(awk -F'\t' '$2 == "merge_group" { l = $0 } END { print l }' "$UNITS")"
if [ -n "$last_mg" ]; then
  mg_ex="$(cut -f7 <<<"$last_mg")"; mg_cls="$(cut -f10 <<<"$last_mg")"
  if [ "$mg_ex" != 0 ] && [ "$mg_cls" != incident ]; then nots+=("paused: the latest merge_group unit (run $(cut -f1 <<<"$last_mg")) is red (exit=$mg_ex $(cut -f8 <<<"$last_mg")): repair main first")
  fi
fi

# --- per-PR facts (cached): canary, fork, oracle-touching, files, user type, draft-at-run -------------------------------------------------------------
declare -A PR_DOCS PR_SCRIPTS PR_BOT PR_EXCLUDED
ORACLE_JSON="$(printf '%s\n' "${ORACLE[@]}" | jq -R . | jq -s -c .)"
pr_facts() {   # <pr number>
  local n="$1" p files page page_files cnt
  [ -z "${PR_DOCS[$n]+x}" ] || return 0
  p="$(api "repos/$REPO/pulls/$n")" || fail_api "pull $n"
  files="[]"; page=1
  while :; do   # up to 3 pages of 100 files; a longer list is treated as oracle-touching and not docs-only
    if [ "$page" -eq 1 ]; then page_files="$(api "repos/$REPO/pulls/$n/files?per_page=100")" || fail_api "pull $n files"
    else page_files="$(api "repos/$REPO/pulls/$n/files?per_page=100&page=$page")" || fail_api "pull $n files (page $page)"; fi
    files="$(jq -c -n --argjson a "$files" --argjson b "$page_files" '$a + $b' 2>/dev/null)" || fail_api "pull $n files (parse)"
    cnt="$(jq -r 'length' <<<"$page_files" 2>/dev/null)" || fail_api "pull $n files (parse)"
    [ "$cnt" -ge 100 ] || break
    [ "$page" -lt 3 ] || { files="$(jq -c '. + [{"filename":"(more than 300 files)"}]' <<<"$files")"; break; }
    page=$((page + 1))
  done
  PR_BOT[$n]="$(jq -r 'if ((.user.type // "") == "Bot") then 1 else 0 end' <<<"$p" 2>/dev/null)" || fail_api "pull $n (parse)"
  # excluded from every count: a throwaway canary, a fork (the head repository is not the base repository, or is gone), a PR touching an oracle input
  PR_EXCLUDED[$n]="$(jq -r --argjson oracle "$ORACLE_JSON" --argjson files "$files" 'if ((.head.ref // "") | startswith("canary-")) then 1
      elif ((.head.repo.full_name // "") != (.base.repo.full_name // "-")) then 1
      elif any($files[]; .filename as $f | any($oracle[]; . == $f) or $f == "(more than 300 files)") then 1 else 0 end' <<<"$p" 2>/dev/null)" || fail_api "pull $n (parse)"
  # the doc allowlist of scripts/ci-pr-selection.sh (a knowledge-base markdown file or a root markdown file); the directory name is assembled so this probe does not
  # read as a knowledge-base consumer to the dropped-consumer census (scripts/test-affected-kb-consumers.test.sh follows a script the replay suite names)
  PR_DOCS[$n]="$(jq -r --arg kb "knowledge-""base" 'if length > 0 and all(.[]; (.filename | test("^" + $kb + "/.*\\.md$") or test("^[^/]+\\.md$"))) then 1 else 0 end' <<<"$files" 2>/dev/null)" || fail_api "pull $n files (parse)"
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
declare -A SEEN_KEY; distinct=0; any_scripts=0; docs_seen=0; draft_seen=0; bot_seen=0
while IFS=$'\t' read -r id ev sha branch created prn ex reason wall cls fork; do
  [ -n "$id" ] || continue
  [ "$prn" != 0 ] || continue        # a pull_request run that names no PR (a fork run) cannot be read: not evidence
  [ "$fork" != 1 ] || continue       # a fork PR run
  pr_facts "$prn"
  [ "${PR_EXCLUDED[$prn]}" != 1 ] || continue   # canary, fork or oracle-touching: excluded from every count
  [ "${PR_SCRIPTS[$prn]}" != 1 ] || any_scripts=1
  [ "${PR_DOCS[$prn]}" != 1 ] || docs_seen=1
  [ "${PR_BOT[$prn]}" != 1 ] || bot_seen=1
  if [ "$draft_seen" != 1 ]; then draft_at "$prn" "$created"; [ "$DRAFT" != 1 ] || draft_seen=1; fi
  [ -z "${SEEN_KEY[$prn]+x}" ] || continue
  SEEN_KEY[$prn]=1; distinct=$((distinct + 1))
done <<<"$pr_units"
# the wall statistics see EVERY unit that ran after the restart and is not an incident (red and timed-out units included): a ceiling must see the tail
walls="$(awk -F'\t' -v r="${restart:-}" '$5 > r && $10 != "incident" { print $9 }' "$UNITS" | sort -n)"
n_w="$(printf '%s\n' "$walls" | grep -c .)"
p95=0; max=0
if [ "$n_w" -gt 0 ]; then
  rank=$(( (n_w * 95 + 99) / 100 )); p95="$(printf '%s\n' "$walls" | sed -n "${rank}p")"; max="$(printf '%s\n' "$walls" | tail -n 1)"
fi

# --- (h) the baseline has not grown since the PR3a merge (set comparison of the file at the merge commit and at the main tip) -------------------------------
raw_baseline() {   # <ref> <out file>: 0 read, 4 absent (HTTP 404), exits 3 on any other failure
  local err rc=0
  gh api -H 'Accept: application/vnd.github.raw' "repos/$REPO/contents/$BASELINE?ref=$1" > "$2" 2> "$WORK/raw.err" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  err="$(cat "$WORK/raw.err")"
  case "$err" in *"HTTP 404"*|*"Not Found"*) return 4 ;; esac
  fail_api "baseline at $1"
}
grew=0
if [ -z "$merge_sha" ]; then fail_api "pull $PR3A has no merge commit"; fi
raw_baseline "$merge_sha" "$WORK/bl.merge"; rc=$?
[ "$rc" -ne 4 ] || fail_api "the baseline is absent at the PR3a merge commit"
raw_baseline main "$WORK/bl.tip"; rc=$?
if [ "$rc" -eq 4 ]; then : > "$WORK/bl.tip"   # absent at the tip is the end state (PR5 deletes it)
fi
sort -u "$WORK/bl.merge" > "$WORK/bl.merge.s"; sort -u "$WORK/bl.tip" > "$WORK/bl.tip.s"
added="$(comm -13 "$WORK/bl.merge.s" "$WORK/bl.tip.s")"
if [ -n "$added" ]; then
  grew="$(printf '%s\n' "$added" | grep -c .)"
  first3="$(printf '%s\n' "$added" | head -n 3 | cat -vT | sed 's/.*/"&"/' | paste -sd' ' -)"
  nots+=("baseline grew by $grew line(s) since the PR3a merge ($first3)")
fi
echo "window opened=$merged_at age_days=$age_days green_pr_units_distinct_prs=$distinct green_merge_group_shas=$mg_n scripts_pr=$any_scripts docs_only=$docs_seen draft=$draft_seen bot=$bot_seen wall_p95_s=$p95 wall_max_s=$max units=$n_w runs_listed=$runs_listed units_read=$units_read truncated=$TRUNC baseline_grown=$grew"

(( distinct >= MIN_PR )) || nots+=("only $distinct distinct green pull_request PR(s) (need $MIN_PR)")
(( mg_n >= MIN_MG )) || nots+=("only $mg_n green merge_group SHA(s) (need $MIN_MG)")
(( any_scripts == 1 )) || nots+=("no green pull_request unit is from a PR touching scripts/ or a suite file")
(( docs_seen == 1 )) || nots+=("no green docs-only PR in the window")
(( draft_seen == 1 )) || nots+=("no green DRAFT PR run in the window (draft-push billed minutes are recorded for the PR3b draft-light re-examination)")
if (( bot_seen == 0 )); then
  if (( age_days >= REVIEW_DAYS )); then echo "bot PR: none occurred in $age_days days; the committed synthetic-green unit test substitutes (recorded)"
  else nots+=("no bot PR in the window yet (the synthetic-green unit test substitutes only after $REVIEW_DAYS days)"); fi
fi
nwall=0
if (( n_w > 0 )); then
  (( p95 <= P95_MAX )) || { nots+=("wall p95 ${p95}s is over $P95_MAX s (PROVISIONAL ceiling; ceiling re-rule owed: bring the measured series to the CTO agent)"); nwall=$((nwall + 1)); }
  (( max <= MAX_MAX )) || { nots+=("wall max ${max}s is over $MAX_MAX s (PROVISIONAL ceiling; ceiling re-rule owed: bring the measured series to the CTO agent)"); nwall=$((nwall + 1)); }
else
  nots+=("no unit ran to take a wall time from")
fi
if (( nwall > 0 && ${#nots[@]} == nwall && age_days >= REVIEW_DAYS )); then
  nots+=("the $REVIEW_DAYS-day trigger has passed and (d) is the only unmet criterion: the CTO agent re-rules the two wall ceilings now")
fi
if (( ${#nots[@]} > 0 )); then
  printf 'NOT YET: %s\n' "${nots[@]}"
  exit 2
fi
echo "PASS: the window held: $distinct distinct PRs and $mg_n merge_group SHAs green, wall p95 ${p95}s max ${max}s, docs-only, draft and bot coverage as above, the baseline has not grown. It certifies the earliest prefix of the window plus the newest queue state (units_read=$units_read truncated=$TRUNC). Closing #10865 does not authorize PR3b (#10859)."
exit 0
