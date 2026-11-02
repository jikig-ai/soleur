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
# sibling closing probes reserve 2 for it; the sweeper renders 1 as a FAIL comment every night). Exit 1 is NOT USED by this probe: it is unreachable by design (no code path chooses it; a `set -u` abort would exit 1, and the suite treats any exit 1 as a failure).
#   (a) at least MIN_PR (3) green pull_request units from 3 DISTINCT PRs, at least one touching `scripts/` or a suite file; a throwaway canary PR
#       (head branch `canary-*`), a fork PR (head repository is not this repository) and a PR whose file list touches an oracle input (ORACLE below, the
#       SUT's RATCHET_ORACLE) are excluded from every count, as is a pull_request run whose PR cannot be resolved (GitHub empties a run's own `pull_requests` once its PR merges, so
#       such a run is attributed by its head commit: `commits/<sha>/pulls` must return exactly ONE PR of this repository whose head ref is the run's branch; any other
#       answer leaves the run unattributed, excluded and counted in `pr_unattributed_runs`);
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
# PLUS always the newest 10 merge_group runs (the pause check and the defects), which are dispatched FIRST but stay deadline-bound like every read — a cut one is
# reported, never silent: a PASS certifies an ordered prefix of the LISTED runs plus the newest queue state, and the status line prints runs_listed, units_read and truncated=0|1. Reads run SOAK_PARALLEL (8) at a time under ONE
# wall deadline END = T0 + SOAK_BUDGET_S (270 s, 30 s under the sweeper's 300 s per-probe kill, #11215): the listing loop, the read dispatch, the per-PR facts loop and the
# baseline reads all gate against it, and each API read is capped at min(60 s, END - SECONDS - 5) so no in-flight read can carry the probe past the kill. SOAK_FACTS_BUDGET_S (180 s)
# is a SUB-allocation of the same deadline for the serial facts phase, which also stops TAIL (20 s) before END to reserve the verdict/baseline reads: past either bound the remaining
# runs or PRs are left unread THIS sweep (nothing persists between sweeps; truncated=1; a budget hit is NOT YET unless every criterion already holds on what was read, and is never
# CANNOT ESTABLISH: a read killed by the probe's own deadline cap returns the budget sentinel and is reported as a cut, not as a failed read). Measured on 2026-10-31: listing 26 pages
# 47 s, per-unit read ~3.2 s (jobs 2.1 + log 1.1), facts ~2.4 s/PR -- under the old two-epoch model (~480 s plus listing, calibrated to the sweeper's pre-#11215 15-minute shared
# ceiling) the probe was CANNOT ESTABLISH every sweep; under the deadline it fits in ~220 s. GitHub's 1,000-result cap on a run listing means that beyond 1,000 runs the listing is the NEWEST 1,000 and the oldest-250 prefix MOVES forward as runs accumulate:
# evidence does NOT latch across sweeps, and the one sweep that sees every criterion is what closes the tracker. The time arithmetic is in the runbook. A run whose
# conclusion is `cancelled` is skipped before any jobs read. RESTART FLOOR: a drain PR (label `s4-drain`) merged inside the window changes the baseline, the live set and the oracle, so
# only runs created after the LATER of the PR3a merge and the latest drain merge count (runbook, "The drain claim"; one issues read; the status line's `window opened=` is that floor, while
# age_days and the 30-day triggers stay anchored to the PR3a merge). Closing #10865 authorizes nothing: PR3b (#10859) stays held.
#
# Exit codes (sweep-followthroughs.sh contract): 0 PASS; 2 NOT YET (an unmet criterion; the sweeper comments and leaves the tracker open); 3 CANNOT ESTABLISH
# (a tool, GH_TOKEN or a read failed, or a job log carried no marker for a run that concluded success: the sweeper retries); 78 refused to run under xtrace
# while GH_TOKEN is set (#7797). Test seams (inert under the sweeper's env -i): SOAK_NOW_EPOCH, SOAK_MAX_PAGES, SOAK_MAX_UNITS, SOAK_PARALLEL (1..8), SOAK_BUDGET_S
# (1..300; the single wall deadline END=T0+BUDGET), SOAK_FACTS_BUDGET_S (1..300; a sub-allocation of the same deadline for the serial per-PR facts phase), SOAK_PROGRESS=1 (a heartbeat per 25 reads on stderr). The sweeper's GITHUB_TOKEN allows about 1,000 REST requests per hour per repository, shared: the probe reads
# rate_limit first and is CANNOT ESTABLISH (exit 3) when the planned reads (1.5 per run, half a lookup per run needing one, 3 per PR, 100 reserve; printed as `planned=`) do not fit,
# and an HTTP 403 or 429 stops further reads. A read that fails with a timeout, a 5xx or a network-class error (EOF, connection reset, TLS handshake or i/o timeout, dial tcp) is retried ONCE after 2 s, and only while the wall deadline is not
# spent; a 403, 429, 404 or 422 is never retried.
# Progress is on stderr (three phase lines, counts only); stdout is the status line, the verdict and a `quota:` line. NO API payload may travel on a jq argv (one argv entry
# is capped at 131072 bytes): pages go to jq on stdin. The rows live in
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

umask 077   # the work directory and the worker files hold API metadata and run next to GH_TOKEN

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
PAR="${SOAK_PARALLEL:-8}"          # concurrent run reads (cap 8)
BUDGET="${SOAK_BUDGET_S:-270}"     # the ONE wall deadline END=T0+BUDGET covering listing, reads, facts and the verdict tail (default 30 s under the sweeper's 300 s kill; cap 300)
FACTS_BUDGET="${SOAK_FACTS_BUDGET_S:-180}"   # a SUB-allocation of that deadline for the serial per-PR facts phase, measured from its start (cap 300): a PR's facts are a pull, up to 3 files pages and a timeline (up to 5 serial reads, about 2.4 s each measured 2026-10-28), checked against it before each PR -- and the facts phase also stops TAIL seconds before END. Under the single wall deadline this knob is near-vestigial; it is kept as the named seam through which the facts-cut rows drive the probe
T0=$SECONDS
END=$((T0 + BUDGET))               # the single wall deadline every phase gates against
TAIL=20                            # seconds before END reserved for the verdict and the baseline reads
LAUNCH_RSVD=12                     # a unit is launched only while at least this much wall remains (its own reads are then capped to fit)
for need in gh jq date sort mktemp rm sed awk comm paste cat head tail cut tr grep mv timeout pgrep sleep; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }
NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_NOW_EPOCH is not an epoch"; exit 3; }
[[ "$MAX_PAGES" =~ ^[1-9][0-9]*$ && "$MAX_UNITS" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_MAX_PAGES / SOAK_MAX_UNITS are not positive integers"; exit 3; }
[[ "$PAR" =~ ^[1-9][0-9]*$ && "$PAR" -le 8 ]] || { echo "CANNOT ESTABLISH: SOAK_PARALLEL is not an integer from 1 to 8"; exit 3; }
[[ "$BUDGET" =~ ^[1-9][0-9]*$ && "$BUDGET" -le 300 ]] || { echo "CANNOT ESTABLISH: SOAK_BUDGET_S is not an integer from 1 to 300"; exit 3; }
[[ "$FACTS_BUDGET" =~ ^[1-9][0-9]*$ && "$FACTS_BUDGET" -le 300 ]] || { echo "CANNOT ESTABLISH: SOAK_FACTS_BUDGET_S is not an integer from 1 to 300"; exit 3; }
HB=0; { [ "${SOAK_PROGRESS:-}" = 1 ] || [ -t 2 ]; } && HB=1   # the per-25 heartbeat is opt-in: the sweeper folds stderr into a public comment

WORK="$(mktemp -d)" || { echo "CANNOT ESTABLISH: mktemp failed"; exit 3; }
RL_FLAG="$WORK/rate-limited"; FAILED_FLAG="$WORK/worker-failed"
# the workers hold GH_TOKEN in their environment: a kill at the job timeout stops them (and what they spawned) instead of orphaning them
kill_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill "$1" 2>/dev/null; return 0; }
cleanup() { local p; for p in $(jobs -p 2>/dev/null); do kill_tree "$p"; done; wait 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 143' INT TERM HUP
note() { printf 'soak-progress: %s\n' "$*" >&2; }   # progress is stderr only: the sweeper reads the verdict from stdout and the exit code, and folds stderr into a public comment
fail_api() { local st=""; [ -s "$RL_FLAG" ] && st="; $(cat "$RL_FLAG")"; echo "CANNOT ESTABLISH: GitHub API read failed ($1$st)"; exit 3; }
# a transient failure: the 60 s timeout of the read itself (rc 124) or a 5xx / network-class error. An HTTP 403, 429, 404, 422 or any other 4xx is never transient.
transient_err() {   # <rc> <error file>
  [ "$1" -eq 124 ] || grep -qE 'HTTP 5[0-9][0-9]|EOF|connection reset|TLS handshake timeout|i/o timeout|dial tcp|Client.Timeout' "$2" 2>/dev/null
}
# one read: the request path is the LAST argument; one stalled connection must not stall the drain, and an HTTP 403 or 429 stops further launches. ONE retry after a fixed 2 s, only for a
# transient failure and only while no 403/429 has been seen. Returns 44 for HTTP 404 and 45 for HTTP 422 (never gh's own 1, 2, 4 or 8, nor timeout's 124-127 and 137), so a caller can
# tell an answered "not there" from a failed read.
# return 46 = the wall deadline is spent (no budget left for this read, or the probe's own deadline cap killed it): callers treat it as a
# budget cut, never as a failed read, so a deadline can never become CANNOT ESTABLISH.
gh_get() {
  local out rc=0 errf="$WORK/err.$BASHPID" st tries=0 rem cap
  while :; do
    rem=$((END - SECONDS - 5)); cap=60; (( rem < cap )) && cap=$rem   # recomputed per attempt: a retried read must not reuse a stale 60 s cap and run past END
    if (( cap < 1 )); then rc=46; break; fi
    rc=0; out="$(timeout "$cap" gh api "$@" 2>"$errf")" || rc=$?
    if [ "$rc" -eq 124 ] && (( cap < 60 )); then rc=46; fi   # killed by OUR cap, not a stall: a budget event (keyed on the FRESH cap of the attempt that timed out)
    if [ "$rc" -ne 0 ]; then
      st="$(grep -oE 'HTTP (403|429)' "$errf" 2>/dev/null | head -n 1)"
      [ -z "$st" ] || printf '%s\n' "$st" > "$RL_FLAG"
      if [ "$tries" -eq 0 ] && [ ! -e "$RL_FLAG" ] && (( SECONDS - T0 < BUDGET )) && transient_err "$rc" "$errf"; then tries=1; sleep 2; continue; fi
      if grep -q 'HTTP 404' "$errf" 2>/dev/null; then rc=44; elif grep -q 'HTTP 422' "$errf" 2>/dev/null; then rc=45; fi
    fi
    break
  done
  rm -f "$errf"
  [ "$rc" -ne 0 ] || printf '%s\n' "$out" || rc=$?
  return "$rc"
}
api() { gh_get "$1"; }
log_api() { gh_get --allow-escape-sequences "$1"; }
jq_detail() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9 _:,()-' '?' | LC_ALL=C cut -c1-160; }   # a public comment must carry no @name, #123, markup or control byte from a payload
UNITS="$WORK/units.tsv"; : > "$UNITS"
MARKER_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z SOLEUR_PR_AFFECTED_RATCHET exit=([012]) reason=([a-z0-9-]+) live=[0-9]+ baseline=[0-9]+$'
nots=()   # the unmet criteria, each reported as `NOT YET: <what>`

# --- the API quota: read first (the rate_limit read is free) --------------------------------------------------------------------------------------------
rl0="$(api "rate_limit")" || fail_api "rate_limit"
RL_REM="$(jq -r '.resources.core.remaining // empty' <<<"$rl0" 2>/dev/null)"; RL_USED0="$(jq -r '.resources.core.used // empty' <<<"$rl0" 2>/dev/null)"
RL_RESET="$(jq -r '.resources.core.reset // empty' <<<"$rl0" 2>/dev/null)"
[[ "$RL_REM" =~ ^[0-9]+$ && "$RL_USED0" =~ ^[0-9]+$ ]] || fail_api "rate_limit (parse)"
LISTCALLS=0

# --- the PR3a merge --------------------------------------------------------------------------------------------------------------
pr_json="$(api "repos/$REPO/pulls/$PR3A")" || fail_api "pull $PR3A"
merged_at="$(jq -r '.merged_at // empty' <<<"$pr_json" 2>/dev/null)" || fail_api "pull $PR3A (parse)"
[ -n "$merged_at" ] || { echo "NOT YET: PR $PR3A is not merged yet: the window has not opened"; exit 2; }
merge_sha="$(jq -r '.merge_commit_sha // empty' <<<"$pr_json" 2>/dev/null)" || fail_api "pull $PR3A (parse)"
merged_epoch="$(date -u -d "$merged_at" +%s 2>/dev/null)" || fail_api "merge time $merged_at"
age_days=$(( (NOW - merged_epoch) / 86400 ))
# --- the restart floor: the window counts from the LATER of the PR3a merge and the latest merged `s4-drain` PR (a drain PR changes the baseline, the live set and the oracle; until now the closer applied
# this by hand, #10949). One read of the (small) label list, REFUSED when it is a full page (100 = the URL's per_page: the latest merge could be off the page); `merged_at` is the floor from here on, so the run listing, the units and the status line all start there. age_days stays PR3a-based above.
floor_src="pr3a"   # which merge the floor came from, printed on the status line
drain_json="$(api "repos/$REPO/issues?labels=s4-drain&state=closed&sort=updated&direction=desc&per_page=100")" || fail_api "s4-drain pulls"
drain_at="$(jq -r 'if type != "array" then error("not an array") elif length >= 100 then error("full page") else ([.[] | select(.pull_request.merged_at != null) | .pull_request.merged_at] | max // "") end' <<<"$drain_json" 2>/dev/null)" || fail_api "s4-drain pulls (parse)"
[[ -z "$drain_at" || "$drain_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail_api "s4-drain pulls (parse)"
if [[ -n "$drain_at" ]]; then
  drain_epoch="$(date -u -d "$drain_at" +%s 2>/dev/null)" || fail_api "s4-drain pulls (parse)"
  if (( drain_epoch > merged_epoch )); then merged_at="$drain_at"; floor_src="s4-drain"; fi
fi

# --- read one job: sets RJ_EX, RJ_REASON, RJ_WALL, RJ_RAN (RJ_EX is 2 with reason no-marker when the job concluded without an emitted marker) ---------
# Called inside a read_unit worker subshell (fail_api's `exit` ends that worker; the main shell then reports its one fixed line and exits 3), never in a command substitution.
read_job() {   # <jobs json> <run id>
  local jobs="$1" run="$2" j jid conc started completed step log line t0 t1 rc=0
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
  log="$(log_api "repos/$REPO/actions/jobs/$jid/logs")" || { rc=$?; [ "$rc" -eq 46 ] && exit 46; fail_api "run $run job log"; }
  line="$(printf '%s\n' "$log" | sed 's/^\xef\xbb\xbf//' | tr -d '\r' | grep -aE "$MARKER_RE" | tail -n 1)"
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
    if (( SECONDS - T0 >= BUDGET )); then TRUNC=1; break; fi   # the wall deadline bounds the listing too
    LISTCALLS=$((LISTCALLS + 1))
    runs="$(api "$path")" || { rc=$?; [ "$rc" -eq 46 ] && { TRUNC=1; break; }; fail_api "ci.yml $ev runs (page $page)"; }
    jq -r --arg m "$merged_at" --arg ev "$ev" '.workflow_runs[]? | select(.created_at > $m)
         | [.id, $ev, .head_sha, ((.head_branch // "") | if . == "" then "-" else . end), .created_at, (.run_attempt // 1), ((.pull_requests[0].number // 0) | tostring), (.conclusion // ""),
            (if ((.head_repository.full_name // "") != (.repository.full_name // "")) then 1 else 0 end)] | @tsv' <<<"$runs" >> "$RUNS" 2>/dev/null \
      || fail_api "ci.yml $ev runs (parse)"
    n="$(jq -r '(.workflow_runs // []) | length' <<<"$runs" 2>/dev/null)" || fail_api "ci.yml $ev runs (parse)"
    [ "$n" -ge 100 ] || break
    if [ "$page" -ge "$MAX_PAGES" ]; then TRUNC=1; break; fi
    page=$((page + 1))
  done
done
awk -F'\t' '$1 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ || $7 !~ /^[0-9]+$/ { bad = 1 } END { exit bad }' "$RUNS" || fail_api "ci.yml runs (non-numeric run id, attempt or PR number)"
runs_listed="$(grep -c . "$RUNS")"
# a cancelled run spends no budget. The newest NEWEST_MG merge_group runs are dispatched FIRST (the pause check and the defects need the newest queue state), still
# deadline-bound like every read — an unread one is an unmet criterion, not a silent cut — then the oldest runs up to MAX_UNITS, oldest first.
awk -F'\t' '$8 != "cancelled"' "$RUNS" | sort -t$'\t' -k5,5 -s > "$WORK/readable.tsv"
readable_n="$(grep -c . "$WORK/readable.tsv")"
head -n "$MAX_UNITS" "$WORK/readable.tsv" > "$WORK/oldest.tsv"
awk -F'\t' '$2 == "merge_group"' "$WORK/readable.tsv" | tail -n "$NEWEST_MG" > "$WORK/extras.tsv"
e_n="$(grep -c . "$WORK/extras.tsv")"   # the newest-queue extras the pause check and the defects need; any left unread this sweep is an unmet criterion (A5)
# the NR==FNR anti-join idiom reads every row of file 2 as file 1 when file 1 is EMPTY (a sweep with no merge_group run
# would dispatch nothing at all), so the empty case takes the oldest list verbatim instead
if [ -s "$WORK/extras.tsv" ]; then
  awk -F'\t' 'NR == FNR { x[$1] = 1; next } !($1 in x)' "$WORK/extras.tsv" "$WORK/oldest.tsv" > "$WORK/oldest-rest.tsv"
else
  cat "$WORK/oldest.tsv" > "$WORK/oldest-rest.tsv"
fi
{ sed 's/^/E\t/' "$WORK/extras.tsv"; sed 's/^/O\t/' "$WORK/oldest-rest.tsv"; } > "$WORK/dispatch.tsv"
to_read="$(grep -c . "$WORK/dispatch.tsv")"
note "phase=listed seen=$runs_listed readable=$readable_n to_read=$to_read parallel=$PAR budget_s=$BUDGET elapsed_s=$((SECONDS - T0))"
# the quota guard: a shortfall is CANNOT ESTABLISH (the sweeper retries), never NOT YET (that would say a criterion is unmet) and never a smaller plan (that would change what a PASS certifies).
# Estimated from dispatch.tsv alone: 1.5 requests per run read (a jobs read, a log for a unit that ran, a rerun costs 4), half a commit lookup per run whose own PR is empty (res_cands), and 3 per
# PR (its pull, its files, its timeline). Measured 2026-10-28: a sweep of 156 units and 24 PRs spent 321 requests against planned=716 (~260 runs of ~81 PRs plan about 856); the old 2-per-run, 5-per-PR formula was calibrated to 4 PRs and
# would be above the whole hourly token quota at ~80, a permanent exit 3. The weights rest on two days of measurements: the `planned=` figure on the quota line is how they are shown wrong.
res_cands="$(awk -F'\t' '$3 == "pull_request" && $8 == 0 && $10 == 0 && $5 !~ /^canary-/' "$WORK/dispatch.tsv" | grep -c .)"
pr_est="$(awk -F'\t' '$3 == "pull_request" && $8 != 0 { print "n" $8 } $3 == "pull_request" && $8 == 0 && $10 == 0 && $5 !~ /^canary-/ { print "b" $5 }' "$WORK/dispatch.tsv" | sort -u | grep -c .)"
need=$(( (3 * to_read + 1) / 2 + (res_cands + 1) / 2 + 3 * pr_est + 100 ))
if (( RL_REM - LISTCALLS < need )); then
  at="unknown"; [[ "$RL_RESET" =~ ^[0-9]+$ ]] && at="$(date -u -d "@$RL_RESET" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  echo "CANNOT ESTABLISH: API quota (remaining=$RL_REM, need=$need, resets at $at)"; exit 3
fi

# --- read each run (a worker per run, at most PAR at a time): its job (latest attempt) and, for a rerun, attempt 1 too ------------------------------------------
# A worker prints its unit row, or the one CANNOT ESTABLISH line of its failure, to its own file; the main shell merges the rows in DISPATCH order and sorts them by
# creation time, so the result does not depend on completion order.
# Attribute a pull_request run whose own `pull_requests` is empty (GitHub empties it once the PR merges) to its PR through its head commit. Sets RES_PRN to the PR number, or to 0 when the commit
# does not identify exactly ONE PR of this repository on this branch (an empty answer, HTTP 404 or 422, two PRs, a foreign repository, another head ref): such a run is unattributed, never evidence
# and never an error. The PR's own head.sha is NOT compared: it is usually a later push than the run's. Any other failure ends the worker. Called in a worker, never in a command substitution.
resolve_pr() {   # <run id> <head sha> <head branch>
  local id="$1" sha="$2" branch="$3" body rc=0 n
  RES_PRN=0
  body="$(api "repos/$REPO/commits/$sha/pulls?per_page=2")" || { rc=$?; [ "$rc" -eq 46 ] && exit 46; }
  case "$rc" in 0) ;; 44|45) return 0 ;; *) fail_api "run $id commit pulls" ;; esac
  n="$(jq -r --arg repo "$REPO" --arg branch "$branch" 'if type != "array" then error("not an array")
      elif length == 1 and (.[0].head.repo.full_name // "") == $repo and (.[0].base.repo.full_name // "") == $repo and (.[0].head.ref // "") == $branch
        and ((.[0].number // 0) | type == "number" and . > 0 and . == floor) then .[0].number else 0 end' <<<"$body" 2>/dev/null)" || fail_api "run $id commit pulls (parse)"
  [[ "$n" =~ ^[0-9]+$ ]] || fail_api "run $id commit pulls (parse)"
  RES_PRN="$n"
}
read_unit() {   # <id> <event> <sha> <branch> <created> <attempt> <pr number> <fork>: runs in a worker subshell (fail_api's exit ends only the worker)
  local id="$1" ev="$2" sha="$3" branch="$4" created="$5" attempt="$6" prn="$7" fork="$8" jobs jobs1 ex reason wall cls first_ex rc=0
  jobs="$(api "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest")" || { rc=$?; [ "$rc" -eq 46 ] && exit 46; fail_api "run $id jobs"; }
  if [ "$(jq -r '(.total_count // 0) > ((.jobs // []) | length)' <<<"$jobs" 2>/dev/null)" != false ]; then fail_api "run $id jobs (truncated or unparseable)"; fi
  read_job "$jobs" "$id"
  [ "$RJ_RAN" = 1 ] || return 0   # the job did not run on this run (skipped, absent, cancelled early): not a unit
  ex="$RJ_EX"; reason="$RJ_REASON"; wall="$RJ_WALL"
  cls="plain"
  if [ "$attempt" -gt 1 ]; then
    # a rerun: attempt 1 is read too, and the pair decides (the latest attempt alone cannot tell a reproduced exit 2 from a first-seen one)
    jobs1="$(api "repos/$REPO/actions/runs/$id/attempts/1/jobs?per_page=100")" || { rc=$?; [ "$rc" -eq 46 ] && exit 46; fail_api "run $id attempt 1 jobs"; }
    read_job "$jobs1" "$id"
    first_ex="none"; [ "$RJ_RAN" = 1 ] && first_ex="$RJ_EX"
    if [ "$ex" = 2 ] && [ "$first_ex" = 2 ]; then cls="defect"
    elif [ "$ex" = 2 ]; then cls="unclassified"
    elif [ "$first_ex" = 2 ]; then cls="incident"
    fi
  elif [ "$ex" = 2 ]; then
    cls="unclassified"
  fi
  # a green plain unit of a run whose own pull_requests is empty (and is no fork, no canary): one lookup of its head commit decides which PR it belongs to
  if [ "$ev" = pull_request ] && [ "$prn" = 0 ] && [ "$fork" != 1 ] && [ "$ex" = 0 ] && [ "$cls" = plain ] && [[ "$branch" != canary-* ]] && [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    resolve_pr "$id" "$sha" "$branch"; prn="$RES_PRN"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$ev" "$sha" "$branch" "$created" "$prn" "$ex" "$reason" "$wall" "$cls" "$fork"
}
UD="$WORK/u"; mkdir -p "$UD"
seq_n=0; inflight=0; done_n=0; launched=0; o_launched=0; e_launched=0; BUDGET_CUT=0
beat() { done_n=$((done_n + 1)); if [ "$HB" = 1 ] && (( done_n % 25 == 0 )); then note "heartbeat read=$done_n/$to_read elapsed_s=$((SECONDS - T0))"; fi; }
launch_unit() {   # <seq> <id> <event> <sha> <branch> <created> <attempt> <pr number> <fork>
  local sq="$1"; shift
  printf '%s\n' "$1" > "$UD/$sq.id"
  { ( read_unit "$@" ) > "$UD/$sq.out" 2> /dev/null < /dev/null; wrc=$?; echo "$wrc" > "$UD/$sq.rc"; [ "$wrc" -eq 0 ] || [ "$wrc" -eq 46 ] || : > "$FAILED_FLAG"; } &
}
while IFS=$'\t' read -r kind id ev sha branch created attempt prn _ fork; do
  [ -n "$id" ] || continue
  while (( inflight >= PAR )); do wait -n || true; inflight=$((inflight - 1)); beat; done
  if [ -e "$FAILED_FLAG" ] || [ -e "$RL_FLAG" ]; then break; fi   # a failed read or an HTTP 403/429 stops further launches (the reads in flight finish)
  # every launch is deadline-bound: the newest-queue extras go FIRST (they are the pause check and the defects), the first oldest-first read is unconditional,
  # and a unit is launched only while LAUNCH_RSVD seconds remain, so its own deadline-capped reads can still fit
  if (( SECONDS - T0 >= BUDGET - LAUNCH_RSVD )) && ! { [ "$kind" = O ] && [ "$o_launched" -eq 0 ]; }; then BUDGET_CUT=1; break; fi
  [ "$kind" = O ] && o_launched=$((o_launched + 1)); [ "$kind" = E ] && e_launched=$((e_launched + 1))
  seq_n=$((seq_n + 1)); printf -v sq '%06d' "$seq_n"
  launch_unit "$sq" "$id" "$ev" "$sha" "$branch" "$created" "$attempt" "$prn" "$fork"
  inflight=$((inflight + 1)); launched=$((launched + 1))
done < "$WORK/dispatch.tsv"
while (( inflight > 0 )); do wait -n || true; inflight=$((inflight - 1)); beat; done
note "phase=read-done done=$launched partial=$(( launched < to_read ? 1 : 0 )) elapsed_s=$((SECONDS - T0))"
# the first failure IN DISPATCH ORDER is named, by its one fixed line only: worker stderr is discarded, so nothing from a payload reaches the public comment
cut_n=0; e_worker_cut=0; o_first_cut=0; hole_sq=""
for wrc_file in "$UD"/*.rc; do
  [ -e "$wrc_file" ] || break
  sq="${wrc_file##*/}"; sq=$((10#${sq%.rc}))   # the %06d dispatch sequence (E seqs are 1..e_launched)
  wrc_v="$(cat "$wrc_file")"
  if [ "$wrc_v" = 46 ]; then   # a deadline-cut worker produced no row: unread, never a failed read
    BUDGET_CUT=1; cut_n=$((cut_n + 1))
    if (( sq <= e_launched )); then e_worker_cut=1; elif (( o_first_cut == 0 )); then o_first_cut=$sq; fi
    continue
  fi
  if [ "$wrc_v" != 0 ]; then
    wline="$(head -n 1 "${wrc_file%.rc}.out")"
    case "$wline" in
      "CANNOT ESTABLISH: GitHub API read failed ("*) printf '%s\n' "$wline" ;;
      *) echo "CANNOT ESTABLISH: GitHub API read failed (run $(cat "${wrc_file%.rc}.id") read)" ;;
    esac
    exit 3
  fi
  (( o_first_cut > 0 && sq > e_launched )) && [ -z "$hole_sq" ] && hole_sq=$o_first_cut
done
# the newest-queue extras go first, so an unread one means the pause check and the newest-10 defect set lack data: an unmet
# criterion (never a silent stale-queue certification), whether the cut hit the launch or the worker
if (( e_worker_cut == 1 || e_launched < e_n )); then nots+=("the newest merge_group queue state was not read this sweep"); fi
# the launch loop breaks permanently at the first O cut, so a completed O row after a cut O seq can only come from a worker
# that hit the deadline on its FIRST read while later-dispatched workers still ran: an interior hole that could hide a defect
# or an unclassified unit while the "earliest prefix" claim still prints — NOT YET naming the hole
if [ -n "$hole_sq" ]; then
  nots+=("the read deadline left an interior hole (run $(cat "$UD/$(printf '%06d' "$hole_sq").id") was cut while a later-dispatched run completed): the read set is not an ordered prefix this sweep")
fi
cat "$UD"/*.out > "$UNITS" 2>/dev/null
units_read="$(grep -c . "$UNITS" 2>/dev/null)"
# truncated is a DISPATCH claim, never a produced-row count (a read run whose job did not run emits no row, so units_read
# undercounts the read set): the sweep is incomplete iff fewer rows were launched than readable, or a launched worker was cut
if (( launched < readable_n || cut_n > 0 )); then TRUNC=1; fi
sort -t$'\t' -k5,5 -k1,1n -s -o "$UNITS" "$UNITS" || fail_api "unit sort"

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
declare -A PR_DOCS PR_SCRIPTS PR_BOT PR_EXCLUDED PR_TL PR_CURDRAFT
ORACLE_JSON="$(printf '%s\n' "${ORACLE[@]}" | jq -R . | jq -s -c .)"
# An API payload NEVER travels on a jq argv: Linux caps ONE argv entry at 131072 bytes (MAX_ARG_STRLEN), and a files page with its patch bodies is 400 KB to 1.1 MB. Pages go to jq
# on stdin (a here-string or a pipe from a builtin printf is not an execve), each is projected to the one field the probe uses, and only small scalars are operands.
pr_facts() {   # <pr number>
  local n="$1" p files page page_files cnt proj rc=0
  [ -z "${PR_DOCS[$n]+x}" ] || return 0
  facts_prs=$((facts_prs + 1))
  p="$(api "repos/$REPO/pulls/$n")" || { rc=$?; [ "$rc" -eq 46 ] && return 46; fail_api "pull $n"; }
  files="[]"; page=1
  while :; do   # up to 3 pages of 100 files; a longer list is treated as oracle-touching and not docs-only
    if [ "$page" -eq 1 ]; then page_files="$(api "repos/$REPO/pulls/$n/files?per_page=100")" || { rc=$?; [ "$rc" -eq 46 ] && return 46; fail_api "pull $n files"; }
    else page_files="$(api "repos/$REPO/pulls/$n/files?per_page=100&page=$page")" || { rc=$?; [ "$rc" -eq 46 ] && return 46; fail_api "pull $n files (page $page)"; }; fi
    proj="$(jq -c 'if type == "array" then [.[] | {filename}] else error("files page is not an array: " + (tojson | .[0:200])) end' 2>&1 <<<"$page_files")" \
      || fail_api "pull $n files (parse): $(jq_detail "$proj")"
    files="$(printf '%s\n%s\n' "$files" "$proj" | jq -s -c 'add' 2>/dev/null)" || fail_api "pull $n files (parse)"
    cnt="$(jq -r 'length' <<<"$proj" 2>/dev/null)" || fail_api "pull $n files (parse)"
    [ "$cnt" -ge 100 ] || break
    [ "$page" -lt 3 ] || { files="$(jq -c '. + [{"filename":"(more than 300 files)"}]' <<<"$files")"; break; }
    page=$((page + 1))
  done
  PR_BOT[$n]="$(jq -r 'if ((.user.type // "") == "Bot") then 1 else 0 end' <<<"$p" 2>/dev/null)" || fail_api "pull $n (parse)"
  PR_CURDRAFT[$n]="$(jq '.draft // false' <<<"$p" 2>/dev/null)" || fail_api "pull $n (parse)"
  # excluded from every count: a throwaway canary, a fork (the head repository is not the base repository, or is gone), a PR touching an oracle input
  PR_EXCLUDED[$n]="$({ printf '%s\n' "$p"; printf '%s\n' "$files"; } | jq -s -r --argjson oracle "$ORACLE_JSON" '.[0] as $p | .[1] as $files | $p | if ((.head.ref // "") | startswith("canary-")) then 1
      elif ((.head.repo.full_name // "") != (.base.repo.full_name // "-")) then 1
      elif any($files[]; .filename as $f | any($oracle[]; . == $f) or $f == "(more than 300 files)") then 1 else 0 end' 2>/dev/null)" || fail_api "pull $n (parse)"
  # the doc allowlist of scripts/ci-pr-selection.sh (a knowledge-base markdown file or a root markdown file); the directory name is assembled so this probe does not
  # read as a knowledge-base consumer to the dropped-consumer census (scripts/test-affected-kb-consumers.test.sh follows a script the replay suite names)
  PR_DOCS[$n]="$(jq -r --arg kb "knowledge-""base" 'if length > 0 and all(.[]; (.filename | test("^" + $kb + "/.*\\.md$") or test("^[^/]+\\.md$"))) then 1 else 0 end' <<<"$files" 2>/dev/null)" || fail_api "pull $n files (parse)"
  PR_SCRIPTS[$n]="$(jq -r 'if any(.[]; .filename | test("^scripts/") or test("^plugins/soleur/test/") or test("\\.test\\.(sh|ts)$")) then 1 else 0 end' <<<"$files" 2>/dev/null)" || fail_api "pull $n files (parse)"
}
draft_at() {   # <pr number> <ISO time>: sets DRAFT to 1 when the PR was a draft at that time (timeline: convert_to_draft / ready_for_review toggles); the timeline is read once per PR
  local n="$1" t="$2" rc=0
  [ -n "${PR_TL[$n]+x}" ] || { PR_TL[$n]="$(api "repos/$REPO/issues/$n/timeline?per_page=100")" || { rc=$?; [ "$rc" -eq 46 ] && return 46; fail_api "timeline $n"; }; }
  DRAFT="$(jq -r --arg t "$t" --argjson cur "${PR_CURDRAFT[$n]}" '
      [.[]? | select(.event == "convert_to_draft" or .event == "ready_for_review") | {e: .event, at: .created_at}] | sort_by(.at) as $ev
      | (if ($ev | length) == 0 then $cur else ($ev[0].e == "ready_for_review") end) as $start
      | reduce ($ev[] | select(.at <= $t)) as $x ($start; $x.e == "convert_to_draft") | if . then 1 else 0 end' <<<"${PR_TL[$n]}" 2>/dev/null)" || fail_api "timeline $n (parse)"
}

# --- the counts -------------------------------------------------------------------------------------------------------------------------------
pr_units="$(awk -F'\t' '$2 == "pull_request"' "$GREEN")"
mg_n="$(awk -F'\t' '$2 == "merge_group" { print $3 }' "$GREEN" | sort -u | grep -c .)"
FACTS_CUT=0; facts_prs=0; TF0=$SECONDS; declare -A SEEN_KEY; distinct=0; any_scripts=0; docs_seen=0; draft_seen=0; bot_seen=0
while IFS=$'\t' read -r id ev sha branch created prn ex reason wall cls fork; do
  [ -n "$id" ] || continue
  [ "$prn" != 0 ] || continue        # a run whose PR could not be resolved (its own pull_requests is empty and its head commit named no single PR) cannot be read: not evidence
  [ "$fork" != 1 ] || continue       # a fork PR run
  if [ -z "${PR_DOCS[$prn]+x}" ] && { (( SECONDS - TF0 >= FACTS_BUDGET )) || (( SECONDS - T0 >= BUDGET - TAIL )); }; then FACTS_CUT=1; TRUNC=1; break; fi   # the facts loop is bounded by its own allowance AND by the wall deadline minus the verdict reserve
  pr_facts "$prn" || { rc=$?; [ "$rc" -eq 46 ] && { FACTS_CUT=1; TRUNC=1; break; }; fail_api "pull $prn facts"; }
  [ "${PR_EXCLUDED[$prn]}" != 1 ] || continue   # canary, fork or oracle-touching: excluded from every count
  [ "${PR_SCRIPTS[$prn]}" != 1 ] || any_scripts=1
  [ "${PR_DOCS[$prn]}" != 1 ] || docs_seen=1
  [ "${PR_BOT[$prn]}" != 1 ] || bot_seen=1
  if [ "$draft_seen" != 1 ]; then draft_at "$prn" "$created" || { rc=$?; [ "$rc" -eq 46 ] && { FACTS_CUT=1; TRUNC=1; break; }; fail_api "timeline $prn"; }; [ "$DRAFT" != 1 ] || draft_seen=1; fi
  [ -z "${SEEN_KEY[$prn]+x}" ] || continue
  SEEN_KEY[$prn]=1; distinct=$((distinct + 1))
done <<<"$pr_units"
# green pull_request rows that are no fork and no canary (the denominator of a live check that few of them stayed unattributed), and how many of those still name no PR
green_pr_rows="$(awk -F'\t' '$2 == "pull_request" && $11 != 1 && $4 !~ /^canary-/' "$GREEN" | grep -c .)"
unattr="$(awk -F'\t' '$2 == "pull_request" && $6 == 0 && $11 != 1 && $4 !~ /^canary-/' "$GREEN" | grep -c .)"
note "phase=facts-done prs=$facts_prs green_pr_rows=$green_pr_rows elapsed_s=$((SECONDS - T0))"
# the wall statistics see EVERY unit that ran after the restart and is not an incident (red and timed-out units included): a ceiling must see the tail
walls="$(awk -F'\t' -v r="${restart:-}" '$5 > r && $10 != "incident" { print $9 }' "$UNITS" | sort -n)"
n_w="$(printf '%s\n' "$walls" | grep -c .)"
p95=0; max=0
if [ "$n_w" -gt 0 ]; then
  rank=$(( (n_w * 95 + 99) / 100 )); p95="$(printf '%s\n' "$walls" | sed -n "${rank}p")"; max="$(printf '%s\n' "$walls" | tail -n 1)"
fi

# --- (h) the baseline has not grown since the PR3a merge (set comparison of the file at the merge commit and at the main tip) -------------------------------
raw_baseline() {   # <ref> <out file>: 0 read, 4 absent (HTTP 404), 46 the wall deadline cut the read, exits 3 on any other failure (an HTTP 422 included)
  local rc=0
  gh_get -H 'Accept: application/vnd.github.raw' "repos/$REPO/contents/$BASELINE?ref=$1" > "$2" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  [ "$rc" -eq 44 ] && return 4
  [ "$rc" -eq 46 ] && return 46
  fail_api "baseline at $1"
}
# the reads are attempted whenever wall remains, truncated sweep or not — TRUNC is the steady state, so gating on it let a PASS
# certify (h) unmeasured. Only a spent deadline skips them, and then the status line prints baseline_grown=unread rather than a
# 0 that would assert a check that never ran
grew=unread
: > "$WORK/bl.merge"; : > "$WORK/bl.tip"
if [ -z "$merge_sha" ]; then fail_api "pull $PR3A has no merge commit"; fi
if (( SECONDS - T0 >= BUDGET )); then
  nots+=("read budget ended before the baseline reads (SOAK_BUDGET_S=$BUDGET)"); TRUNC=1
else
  raw_baseline "$merge_sha" "$WORK/bl.merge"; rc=$?
  [ "$rc" -ne 4 ] || fail_api "the baseline is absent at the PR3a merge commit"
  if [ "$rc" -eq 0 ]; then
    raw_baseline main "$WORK/bl.tip"; rc=$?
    if [ "$rc" -eq 4 ]; then : > "$WORK/bl.tip"; rc=0; fi   # absent at the tip is the end state (PR5 deletes it)
    [ "$rc" -ne 0 ] || grew=0
  fi
  if [ "$rc" -eq 46 ]; then nots+=("read budget ended during the baseline reads (SOAK_BUDGET_S=$BUDGET)"); TRUNC=1; : > "$WORK/bl.merge"; : > "$WORK/bl.tip"; fi
fi
if [ "$grew" != unread ]; then
  sort -u "$WORK/bl.merge" > "$WORK/bl.merge.s"; sort -u "$WORK/bl.tip" > "$WORK/bl.tip.s"
  added="$(comm -13 "$WORK/bl.merge.s" "$WORK/bl.tip.s")"
  if [ -n "$added" ]; then
    grew="$(printf '%s\n' "$added" | grep -c .)"
    first3="$(printf '%s\n' "$added" | head -n 3 | cat -vT | sed 's/.*/"&"/' | paste -sd' ' -)"
    nots+=("baseline grew by $grew line(s) since the PR3a merge ($first3)")
  fi
fi
echo "window opened=$merged_at age_days=$age_days floor=$floor_src green_pr_units_distinct_prs=$distinct green_merge_group_shas=$mg_n scripts_pr=$any_scripts docs_only=$docs_seen draft=$draft_seen bot=$bot_seen wall_p95_s=$p95 wall_max_s=$max units=$n_w runs_listed=$runs_listed units_read=$units_read truncated=$TRUNC baseline_grown=$grew pr_unattributed_runs=$unattr"
# the quota this sweep spent (rate_limit is free to read); a failed read here never decides the verdict
rl1="$(api "rate_limit" 2>/dev/null)" || rl1=""
RL_USED1="$(jq -r '.resources.core.used // empty' <<<"$rl1" 2>/dev/null)"; RL_LIMIT="$(jq -r '.resources.core.limit // empty' <<<"$rl1" 2>/dev/null)"; RL_REM1="$(jq -r '.resources.core.remaining // empty' <<<"$rl1" 2>/dev/null)"
if [[ "$RL_USED1" =~ ^[0-9]+$ && "$RL_LIMIT" =~ ^[0-9]+$ && "$RL_REM1" =~ ^[0-9]+$ ]]; then echo "quota: used_delta=$((RL_USED1 - RL_USED0)) limit=$RL_LIMIT remaining=$RL_REM1 planned=$need"; else echo "quota: unreadable"; fi

if (( distinct < MIN_PR )); then
  unattr_note=""; (( distinct == 0 && unattr > 0 )) && unattr_note=" ($unattr runs could not be attributed to a PR)"
  nots+=("only $distinct distinct green pull_request PR(s) (need $MIN_PR)$unattr_note")
fi
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
# nothing persists between sweeps: a cut sweep leaves the rest unread THIS sweep, and a faster sweep reads further. A cut is NOT YET only while a criterion is unmet.
if (( FACTS_CUT == 1 && ${#nots[@]} > 0 )); then nots+=("read budget ended in the PR-facts phase (SOAK_FACTS_BUDGET_S=$FACTS_BUDGET): PRs after that point were not read this sweep"); fi
if (( BUDGET_CUT == 1 && ${#nots[@]} > 0 )); then nots+=("read budget ended after $((launched - cut_n)) of $to_read runs (SOAK_BUDGET_S=$BUDGET): runs after that point were not read this sweep"); fi
if (( ${#nots[@]} > 0 )); then
  printf 'NOT YET: %s\n' "${nots[@]}"
  exit 2
fi
echo "PASS: the window held: $distinct distinct PRs and $mg_n merge_group SHAs green, wall p95 ${p95}s max ${max}s, docs-only, draft and bot coverage as above, the baseline has not grown. It certifies the earliest prefix of the LISTED runs plus the newest queue state (units_read=$units_read truncated=$TRUNC); a listing is capped at 1,000 results, so the prefix moves between sweeps. The two wall ceilings are PROVISIONAL: the CTO agent re-rules them at this close (runbook, 'Ceilings are PROVISIONAL'). Closing #10865 does not authorize PR3b (#10859)."
exit 0
