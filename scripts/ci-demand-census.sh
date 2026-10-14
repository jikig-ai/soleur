#!/usr/bin/env bash
# ci-demand-census.sh - the committed measurement authority for hosted-runner job-minutes
# (ADR-276 Decision 7; S1 of the demand plan, #9727).
#
# USAGE
#   ci-demand-census.sh --start <YYYY-MM-DDTHH:MM:SSZ> --end <YYYY-MM-DDTHH:MM:SSZ> [--workflow <file>] [--summary]
#   ci-demand-census.sh --fixture <DIR> [--workflow <file>] [--summary]
#   ci-demand-census.sh --help          (usage and the output schema, on stdout, exit 0)
#
# Live mode needs `gh` with a logged-in developer shell (`gh auth login`), GNU `timeout` (with --foreground) and `jq`; fixture
# mode needs only `jq` and never touches the network. Both modes run ONE aggregator over the same
# directory layout (runs-<n>.json, one per sub-window, and jobs-<run_id>.json), so the offline
# suite exercises exactly the code a live run uses. Only GETs are issued (`gh api -f` would silently
# become a POST, so no -f/-F/-X is ever passed). `--summary` is accepted as the explicit selector;
# the output is always the same summary. `date -d` is GNU-only: run this on Linux (not stock macOS).
#
# WINDOW. [--start, --end) : --start inclusive, --end EXCLUSIVE, so two adjacent censuses (one ends
#   where the next starts) never count a run twice. A run belongs to the window its created_at is in.
#
# RECIPE (the last six full hours; redirect stdout to a file, then take the lines an issue comment needs)
#     end=$(date -u -d '-1 hour' +%Y-%m-%dT%H:00:00Z); start=$(date -u -d '-7 hours' +%Y-%m-%dT%H:00:00Z)
#     out=/var/tmp/ci-census-$(date -u +%Y%m%dT%H%M%SZ).txt
#     bash scripts/ci-demand-census.sh --start "$start" --end "$end" --summary >"$out"
#     grep -E '^(REPO|WINDOW|TOTAL|RUNS|JOBS|WORKFLOW)|^STEM'$'\t''secret-scan' "$out"
#     wc -c <"$out"      # a GitHub comment holds at most 65536 characters: keep this under 60000, else post the grep subset
#   The grep line is the issue-comment subset (the key lines and the secret-scan STEM rows; a literal tab is
#   needed, `\t` in an ERE is the letter t). Paste it inside a fenced text block: the fence is why the
#   sanitiser strips backtick, and a name such as @user or #123 would otherwise become a mention or a link.
#   To cost one workflow only: add `--workflow secret-scan.yml` (the Phase-7 call; the form
#   `.github/workflows/secret-scan.yml` is accepted and the prefix stripped; an empty value or one starting
#   with `-` is refused). C1 still runs over every run of the window, jobs are fetched for that workflow's
#   completed runs only, and every figure then describes that workflow alone.
#   LONGER SPANS. One census covers at most 12 hours. To cover more, run consecutive NON-OVERLAPPING windows
#   (each at most 12 hours, --end exclusive, so one ends where the next starts) and combine them by SUMMING
#   TOTAL_JOB_SECONDS and each runs_*/RUNS_*/JOBS_* column, then recompute every minutes and per-run figure
#   from those summed seconds and runs. Printed (rounded) minutes and per-run rows are NOT additive.
#
# OUTPUT (stdout, nothing else): KEY=value lines, then tab-separated tables.
#   REPO WINDOW_START WINDOW_END FETCHED_AT   (fixture mode prints REPO=fixture and WINDOW=fixture)
#   WORKFLOW_FILTER                           (only with --workflow)
#   TOTAL_JOB_MINUTES TOTAL_JOB_SECONDS RUNS_COMPLETED RUNS_NOT_COMPLETED RUNS_RERUN RUNS_NOJOBS
#   JOBS_COUNTED JOBS_SKIPPED JOBS_RUNNERLESS JOBS_UNTIMED
#   BY_WORKFLOW <workflow> <event> <runs> <jobs> <minutes>
#   STEM <workflow> <event> <stem> <runs_ran> <runs_skipped> <runs_runnerless> <jobs> <minutes> <minutes_per_run>
#   RUNS_NOJOBS is the number of completed runs whose jobs file holds zero jobs (a startup failure, or a re-run
#   caught before its new jobs exist: the two look the same). Such a run is legitimate input, so it is not
#   refused, but it is in RUNS_COMPLETED and in every minutes_per_run denominator, and this line says how many.
#   In both tables <jobs> means COUNTED jobs only (the jobs whose seconds are in <minutes>), not every job of
#   the runs; the skipped, runner-less and untimed jobs appear only in the JOBS_* key lines.
# The CI per-family minutes per run are simply the `ci.yml` STEM rows (test-scripts, test-webplat,
# shard-totality-mutations, test-scripts-heavy, e2e; the light set is the sum of the rest): no family
# list lives in this script to drift.
# ROUNDING. TOTAL_JOB_SECONDS is the exact integer; every printed minutes figure is rounded half-up from
#   integer seconds by integer arithmetic (one decimal for totals, two for minutes_per_run). Each row is
#   rounded independently, so the printed rows are NOT additive (the rows of a table can differ from the
#   total by a few tenths): the KEY lines (TOTAL_JOB_SECONDS first) are authoritative.
#
# DEFINITIONS (the parent plan deferred these to this file)
#   Denominator: completed runs in the runs listing for the window. minutes_per_run divides by the
#     completed runs of that workflow and event; a run still in flight is excluded everywhere.
#   Counted job: conclusion != "skipped", runner_id > 0 (null and 0 are runner-less: queue-cancelled
#     or never started), both started_at and completed_at set, and completed_at not before started_at.
#     Minutes are the raw difference in integer seconds divided by 60, once (not billing-rounded);
#     fractional-second timestamps (13:04:05.123Z) are truncated to the second. Every job lands in
#     exactly one class, so JOBS_COUNTED + JOBS_SKIPPED + JOBS_RUNNERLESS + JOBS_UNTIMED = jobs of the
#     completed runs. Class precedence: skipped, then runner-less, then untimed, then counted. A job
#     whose completed_at lies BEFORE its started_at is untimed (it never enters as negative minutes). A
#     runner_id that is neither a number nor null is refused (exit 3), not guessed at.
#   Workflow key: the run's `path` with any `@ref` suffix and the `.github/workflows/` prefix removed
#     (dynamic runs such as `Code Quality: PR #9653` are named per PR, so grouping is by path).
#   Stem: the job name with its trailing parenthesised matrix suffix removed (`test-scripts (3/8)`
#     becomes `test-scripts`; nested parentheses are handled; a name that is only a suffix keeps itself;
#     an empty stem becomes `unknown`).
#   STEM run classes (per run that has the stem): runs_ran = at least one counted job of the stem;
#     runs_skipped = every job of the stem concluded skipped AND no job of that run concluded
#     `cancelled`; runs_runnerless = every other run (runner-less, queue-cancelled, mixed or untimed).
#     A superseded run whose parent job was queue-cancelled makes its dependents conclude skipped, so a
#     stem with no counted job in a run that holds a cancelled job is counted as runner-less, not as a
#     skip. Reading the skip share (runs_skipped over all three columns), two biases pull in opposite
#     directions, and the jobs API cannot tell them apart (a skipped job carries no reason):
#       - a run holding ANY cancelled job (also one unrelated to the gate: a fail-fast sibling, a timeout,
#         a manual cancel) moves its all-skipped stems from runs_skipped to runs_runnerless, so the skip
#         share is a LOWER bound for gate skips;
#       - a stem skipped because an UPSTREAM job FAILED (a `needs:` dependency, no cancelled job in the
#         run) is counted as runs_skipped although the gate did not work, so the skip share may include
#         upstream-failure skips. Only a run holding a cancelled job moves a stem to runs_runnerless.
#
# BIAS (a re-measure of a closed window will not reproduce an earlier figure to the digit)
#   - runs still in flight are excluded (stderr WARN, RUNS_NOT_COMPLETED > 0): a lower bound;
#   - `jobs?filter=latest` returns every job of the run labelled with the NEW run_attempt (read-only probe on
#     run 36325677861, a partial re-run: filter=latest listed all its jobs with the new attempt, filter=all
#     listed both attempts), so a re-run run is counted by its last attempt only. The jobs that were carried
#     over from attempt 1 (not re-run) ARE in the figure, relabelled to the new attempt and still carrying
#     their attempt-1 timestamps; only the minutes of the jobs that were RE-RUN lose their attempt-1 run.
#     RUNS_RERUN says how many completed runs have run_attempt > 1 AS OF THE LISTING TIME (a re-run started
#     after the listing is not in it; if the re-run is still in progress when the jobs are fetched, or its
#     attempt differs from the listing's, the census exits 3 instead, see C2). A re-run can bias the figure in
#     EITHER direction (the last attempt of a re-run job may be shorter or longer than the first);
#   - a job's minutes are attributed to its run's creation time, so a re-run weeks later is credited
#     to the original window.
#   Measure only a CLOSED window: end must be in the past, and the window may span at most 12 hours.
#
# FETCH SHAPE. The runs listing is capped at 1000 results while total_count keeps the true number
#   (verified live: page 11 of 100 returns nothing), so a window is fetched in one-hour sub-windows
#   [a, a+3599] (the last one shortened to end-1), each run through `gh api --paginate`; the inclusive
#   `created=a..b` bounds therefore partition the exclusive window exactly. Only the fields the aggregator
#   reads are kept on disk: for a run id, status, event, path, created_at, run_attempt; for a job id, run_id,
#   name, status, conclusion, started_at, completed_at, runner_id, run_attempt (actor, commit, branch, runner
#   name, labels and steps are dropped at fetch time). About 155 jobs calls per hour of window, sequential:
#   an ESTIMATE, not a measurement, of about 15 minutes per 6 h window. Each call has a timeout; a failed call is retried twice (linearly longer sleeps) and
#   then aborts naming the run (no resume, no `|| true`); if gh's stderr looks like a rate limit
#   (HTTP 403/429) the abort message says so. Progress goes to stderr. The fetched directory is kept
#   under ${TMPDIR:-/var/tmp}; its path and the delete command are on stderr. Live mode is for a
#   developer shell: it refuses GITHUB_ACTIONS=true, because about 930 calls per six hours would spend
#   the repo-wide GITHUB_TOKEN budget every other workflow shares; FIXTURE mode (offline, no network) is
#   allowed anywhere, CI included. SIGINT and SIGTERM stop the run at once when they are delivered to the
#   PROCESS GROUP (a terminal's Ctrl-C, or `kill -- -PGID`; gh runs under `timeout --foreground`, so the signal
#   reaches it too), and still remove the scratch directory; a bare `kill <pid>` (the script alone) waits for the
#   current gh call or retry sleep to return (at most the larger of CENSUS_GH_TIMEOUT and twice CENSUS_RETRY_SLEEP
#   seconds), because bash defers a trap while it waits for a foreground child. A run started in the background
#   with `&` or `nohup` inherits SIGINT and SIGHUP as ignored, and the traps cannot undo that: stop such a run
#   with SIGTERM. SIGHUP ends the run with 129 after the same cleanup. A second signal during the cleanup is
#   ignored, so the cleanup always finishes.
#
# SELF-CHECKS (a total is printed only if all pass; otherwise exit 3, reason on stderr, no
#   TOTAL_JOB_MINUTES line)
#   C1  per sub-window, the unique run ids fetched equal total_count, every document of the listing
#       reports the same total_count, and the sub-window holds fewer than 1000 runs (the cap, a
#       displaced run and a truncated pagination all fail here; a pure duplicate whose unique count equals
#       total_count is de-duplicated, not failed). The runs-<n>.json numbering must be contiguous from 1.
#       Every live fetch also writes windows.tsv (`<n> TAB <from> TAB <to>` per sub-window); when that
#       manifest is in the directory (a live fetch, or a fixture that carries one) the listings must be
#       exactly runs-1..runs-K (a deleted last listing is a gap too) and each run's created_at must lie
#       inside its own sub-window. The manifest must tile exactly: every line is well formed (no leading
#       whitespace), from <= to, and each window starts one second after the previous one ends, so a
#       manifest that makes every run "fit" (two identical full-day windows, a gap) is refused. In live
#       mode C1 runs over every sub-window before any jobs call.
#   C2  every completed run (of the --workflow, when given) has a jobs file whose UNIQUE job count (jobs
#       are de-duplicated by id) equals its total_count, whose documents all agree on total_count, whose
#       jobs all carry that run's own run_id, and whose runner_id values are numbers or null (a run with
#       total_count 0 and an empty list is legitimate, the file must still exist); no job id may appear in
#       two different jobs files; no job of a completed run may still be in flight (status other than
#       `completed`: a re-run in progress, named by run id; a job with no status at all is reported separately
#       as "no status"); and where both the listing and a job carry run_attempt they must be equal (a re-run
#       that finished after the listing), a run_attempt that is not a number being refused with exit 2.
#       Accumulated across ALL runs before the verdict, so the message names every shortfall.
#   non-vacuity  zero completed runs or zero counted jobs is refused, never reported as 0.
#
# EXIT CODES (every exit the script can produce; there is no exit 1 path, every failure maps to 2 or 3):
#   0    ok, the summary was printed
#   2    usage, validation, missing dependency (jq; gh and a timeout that supports --foreground in live mode), CI refusal of live mode,
#        unreadable input (not JSON, wrong shape, a jq failure, a malformed windows.tsv), or an API/I-O error
#        (a gh call that failed or timed out three times, a TMPDIR that is relative or holds whitespace or
#        control characters, a failed write)
#   3    self-check failure (C1, C2 or non-vacuity): exit 3 always means "do not trust a total, there is none"
#   129  hangup (SIGHUP), 130 interrupted by SIGINT (Ctrl-C), 143 terminated by SIGTERM; all after the cleanup
#        (scratch directory removed, the fetched-data hint printed) and without a total
#
# TRUST. Job names, workflow paths and events of fork-PR runs are attacker-chosen, so the STEM rows are
#   a cost measurement, not an attestation. In every string that reaches the output each of these
#   characters is replaced by one `?`, and nothing else is: the Unicode categories Cc (C0 and C1 controls,
#   DEL; tab and newline included), Cf (format characters: zero-width, bidi controls, tag characters),
#   Zl and Zp (U+2028, U+2029) and Co (private use, all three planes); the Default_Ignorable_Code_Point
#   members that no category covers on every Unicode version, listed explicitly: U+00AD, U+034F,
#   U+115F-1160, U+17B4-17B5, U+180B-180F (Mongolian free variation selectors), U+2060-206F (U+2065 is
#   unassigned), U+3164, U+FE00-FE0F, U+FFA0, U+FFF0-FFF8 (unassigned) and U+E0000-E0FFF (tag block, variation
#   selectors supplement and the reserved code points between); U+2800 (braille blank), U+FFFC (object
#   replacement); backtick, < and >. Space separators (Zs: U+00A0, U+2000-200A, U+3000 ...) are visible as
#   spaces and survive, as do ordinary letters, digits and punctuation of any script. Other unassigned code
#   points (Cn) are NOT swept: an old Unicode table in jq would blank a newly assigned letter. The result is length-capped at 120
#   characters. Text echoed on stderr is cut to printable ASCII (every other byte becomes ?) and 200
#   bytes. Every output line starts with a fixed token; nothing is built by eval, bash -c or
#   string-splicing into a jq program (values reach jq through --arg); run ids are validated numeric
#   before they build a path or a URL.
#
# KNOBS (environment)
#   GH_REPO               owner/name to measure (default: the current repository, via `gh repo view`)
#   CENSUS_SUBWINDOW_S    sub-window length in seconds, decimal (default 3600; 60..43200; a leading zero
#                         is read as decimal, 0900 is 900). Lower it when C1 reports a sub-window at the
#                         1000-result cap.
#   CENSUS_RETRY_SLEEP    seconds slept after a failed gh call, times the attempt number (default 10; at
#                         most 4 digits, decimal; the suite sets 0)
#   CENSUS_GH_TIMEOUT     seconds before one gh call is killed and counted as failed (default 180)
#   TMPDIR                scratch and fetch root; must be an absolute path without whitespace or control
#                         characters (default /var/tmp)
set -uo pipefail

# Canonical fixture-dir guard (copied byte-for-byte from plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh pins every copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# TMPDIR is validated BEFORE the EXIT trap exists, so a bad value can never turn a finished run (output
# already printed) into an exit 2 from inside the trap.
TMPDIR="${TMPDIR:-/var/tmp}"
case "$TMPDIR" in
  /*) : ;;
  *) printf 'census: TMPDIR must be an absolute path; refusing before anything ran\n' >&2; exit 2 ;;
esac
case "$TMPDIR" in
  *[[:space:]]*|*[[:cntrl:]]*) printf 'census: TMPDIR must not contain whitespace or control characters; refusing before anything ran\n' >&2; exit 2 ;;
esac
assert_fixture_dir "$TMPDIR"
export TMPDIR

FETCH_DIR=""
SCRATCH=""
cleanup() {
  # a second signal (a wrapper such as `timeout` re-sends the one it got to its group) must not cut the cleanup short
  trap '' INT TERM HUP
  if [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ]; then
    # cannot fire: TMPDIR was validated before this trap existed (kept so the rm is guarded by construction)
    assert_fixture_dir "$SCRATCH"
    rm -rf "$SCRATCH"
  fi
  # last stderr line of a live run: how to delete the fetched data
  if [ -n "$FETCH_DIR" ]; then printf 'census: remove fetched data with: rm -rf %q\n' "$FETCH_DIR" >&2; fi
  return 0
}
trap cleanup EXIT
# Ctrl-C, kill and hangup: leave through the EXIT trap (scratch removed, hint printed) with the shell's own codes
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

die() { # <rc> <message>
  printf 'census: %s\n' "$2" >&2
  exit "$1"
}
usage_line() {
  printf 'usage: %s --start <YYYY-MM-DDTHH:MM:SSZ> --end <YYYY-MM-DDTHH:MM:SSZ> [--workflow <file>] [--summary]\n       %s --fixture <DIR> [--workflow <file>] [--summary]\n       %s --help\n' "$0" "$0" "$0"
}
usage() { # <rc>: 0 prints usage + the output schema on stdout, anything else prints the usage on stderr
  if [ "${1:-2}" -eq 0 ]; then
    usage_line
    cat <<'EOF'

Window: [--start, --end), --end exclusive, at most 12 hours, --end in the past. Live mode needs gh.
Exit codes: 0 ok; 2 usage/validation/dependency/I-O error; 3 self-check failure (no total is printed);
129/130/143 interrupted by SIGHUP/SIGINT/SIGTERM (cleaned up, no total). Exit status 1 is never used.

Output (stdout): KEY=value lines, then tab-separated tables.
  REPO=  WINDOW_START=  WINDOW_END=  FETCHED_AT=      (fixture mode: REPO=fixture, WINDOW=fixture)
  WORKFLOW_FILTER=<file>                              (only with --workflow)
  TOTAL_JOB_MINUTES=<one decimal>  TOTAL_JOB_SECONDS=<integer>  (the seconds figure is authoritative)
  RUNS_COMPLETED=  RUNS_NOT_COMPLETED=  RUNS_RERUN=  RUNS_NOJOBS=
  JOBS_COUNTED=  JOBS_SKIPPED=  JOBS_RUNNERLESS=  JOBS_UNTIMED=
  BY_WORKFLOW <TAB> workflow <TAB> event <TAB> runs <TAB> jobs <TAB> minutes
  STEM <TAB> workflow <TAB> event <TAB> stem <TAB> runs_ran <TAB> runs_skipped <TAB> runs_runnerless <TAB> jobs <TAB> minutes <TAB> minutes_per_run
Printed minutes are rounded per row, so table rows are not additive; read the KEY lines.
<jobs> in both tables counts COUNTED jobs only. Longer spans: sum TOTAL_JOB_SECONDS and the runs columns of consecutive windows.
See the header of this script for the definitions, the recipe and the knobs.
EOF
  else
    usage_line >&2
  fi
  exit "${1:-2}"
}
# printable-ASCII rendition of untrusted text for stderr: non-printable bytes, backtick, < and > become ?
tame() { printf '%s' "$1" | head -c 200 | LC_ALL=C tr -c '[:print:]' '?' | LC_ALL=C tr '`<>' '???'; }

# ── arguments ────────────────────────────────────────────────────────────────
START=""; END=""; FIXDIR=""; WORKFLOW=""; WF_GIVEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --start)    [ $# -ge 2 ] || usage; START="$2"; shift 2 ;;
    --end)      [ $# -ge 2 ] || usage; END="$2"; shift 2 ;;
    --fixture)  [ $# -ge 2 ] || usage; FIXDIR="$2"; shift 2 ;;
    --workflow) [ $# -ge 2 ] || usage; WORKFLOW="$2"; WF_GIVEN=1; shift 2 ;;
    --summary)  shift ;;
    -h|--help)  usage 0 ;;
    *) printf 'census: unknown argument: %s\n' "$(tame "$1")" >&2; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || die 2 "jq is required"

if [ "$WF_GIVEN" -eq 1 ]; then
  # a flag swallowed as the value is a typo, and an empty value must not silently mean "every workflow"
  case "$WORKFLOW" in
    -*) die 2 "--workflow needs a workflow file name such as secret-scan.yml, not a flag: $(tame "$WORKFLOW")" ;;
  esac
  WORKFLOW="${WORKFLOW#.github/workflows/}"
  [ -n "$WORKFLOW" ] || die 2 "--workflow needs a workflow file name such as secret-scan.yml (an empty value is refused, it would silently mean every workflow)"
  [[ "$WORKFLOW" =~ ^[A-Za-z0-9._/-]{1,100}$ ]] || die 2 "--workflow must be a workflow file name such as secret-scan.yml: $(tame "$WORKFLOW")"
fi

LIVE=0
if [ -n "$FIXDIR" ]; then
  { [ -z "$START" ] && [ -z "$END" ]; } || die 2 "--fixture cannot be combined with --start/--end"
  [ -d "$FIXDIR" ] || die 2 "fixture directory not found: $(tame "$FIXDIR")"
elif [ -n "$START" ] || [ -n "$END" ]; then
  LIVE=1
else
  usage
fi

SCRATCH=$(mktemp -d "${TMPDIR}/ci-demand-census-scratch.XXXXXXXX") || die 2 "mktemp -d failed"

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# ── live-mode validation (before any gh call) ────────────────────────────────
S_EPOCH=0; E_EPOCH=0; REPO=""; SUBW=3600; RETRY_SLEEP=10; GH_TIMEOUT=180
if [ "$LIVE" -eq 1 ]; then
  [ -n "$START" ] && [ -n "$END" ] || die 2 "live mode needs both --start and --end"
  shape='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
  # a "+02:00" offset puts a raw "+" in the query string and silently shifts the window
  [[ "$START" =~ $shape ]] || die 2 "--start must look like 2026-10-07T13:04:00Z (UTC, trailing Z): $(tame "$START")"
  [[ "$END" =~ $shape ]] || die 2 "--end must look like 2026-10-07T19:04:00Z (UTC, trailing Z): $(tame "$END")"
  S_EPOCH=$(date -u -d "$START" +%s 2>/dev/null) || die 2 "--start is not a real date: $START"
  E_EPOCH=$(date -u -d "$END" +%s 2>/dev/null) || die 2 "--end is not a real date: $END"
  [ "$(iso "$S_EPOCH")" = "$START" ] || die 2 "--start is not a real date: $START"
  [ "$(iso "$E_EPOCH")" = "$END" ] || die 2 "--end is not a real date: $END"
  [ "$S_EPOCH" -lt "$E_EPOCH" ] || die 2 "--start must be before --end"
  # bounded work: a typo such as --start 2025-... would otherwise issue thousands of calls
  [ $((E_EPOCH - S_EPOCH)) -le 43200 ] || die 2 "window is longer than 12 hours; run the census in 12-hour pieces"
  [ "$E_EPOCH" -le "$(date -u +%s)" ] || die 2 "--end is in the future: an open window is not reproducible, use a closed one (see the header recipe)"
  [ "${GITHUB_ACTIONS:-}" != "true" ] || die 2 "live mode is refused in GitHub Actions: about 930 calls per six hours would spend the shared GITHUB_TOKEN budget; run it from a developer shell"
  # decimal only: validated as digits, then normalised with 10# (a leading 0 must not be read as octal by $(( ))), then bounded
  SUBW_RAW="${CENSUS_SUBWINDOW_S:-3600}"
  [[ "$SUBW_RAW" =~ ^[0-9]{1,6}$ ]] && SUBW=$((10#$SUBW_RAW)) && [ "$SUBW" -ge 60 ] && [ "$SUBW" -le 43200 ] \
    || die 2 "CENSUS_SUBWINDOW_S must be an integer from 60 to 43200 seconds: $(tame "$SUBW_RAW")"
  RETRY_RAW="${CENSUS_RETRY_SLEEP:-10}"
  [[ "$RETRY_RAW" =~ ^[0-9]{1,4}$ ]] && RETRY_SLEEP=$((10#$RETRY_RAW)) \
    || die 2 "CENSUS_RETRY_SLEEP must be a whole number of seconds: $(tame "$RETRY_RAW")"
  GH_TIMEOUT="${CENSUS_GH_TIMEOUT:-180}"
  [[ "$GH_TIMEOUT" =~ ^[1-9][0-9]{0,4}$ ]] || die 2 "CENSUS_GH_TIMEOUT must be a positive whole number of seconds: $(tame "$GH_TIMEOUT")"
  command -v gh >/dev/null 2>&1 || die 2 "gh is required in live mode"
  command -v timeout >/dev/null 2>&1 || die 2 "timeout (coreutils) is required in live mode"
  # the gh calls run under `timeout --foreground` (GNU coreutils); a timeout that rejects the option would fail every call identically
  timeout --foreground 1 "${BASH:-bash}" -c : >/dev/null 2>&1 || die 2 "a timeout that supports --foreground (GNU coreutils) is required in live mode; this timeout rejects it"
  REPO="${GH_REPO:-}"
  if [ -z "$REPO" ]; then
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) || die 2 "could not resolve the repository (set GH_REPO=owner/name)"
  fi
  [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die 2 "repository must look like owner/name: $(tame "$REPO")"
  # a segment made only of dots (".", "..") is a path component, not a name
  [[ "${REPO%%/*}" =~ ^\.+$ || "${REPO#*/}" =~ ^\.+$ ]] && die 2 "repository must look like owner/name: $(tame "$REPO")"
fi

# ── jq definitions shared by the run selection and the aggregator ────────────
# san: untrusted text to printable output. Each of these characters becomes ONE "?": the categories Cc, Cf,
# Zl, Zp and Co, and (listed explicitly, because Unicode versions disagree on their category and a
# Default_Ignorable_Code_Point is invisible whatever its category) U+00AD, U+034F, U+115F-1160, U+17B4-17B5,
# U+180B-180F, U+2060-206F, U+2800, U+3164, U+FE00-FE0F, U+FFA0, U+FFF0-FFF8, U+FFFC and U+E0000-E0FFF (the
# tag block, the variation selectors supplement and the reserved code points between), plus backtick, < and >.
# Then the 120-character cap. (The header TRUST paragraph lists the same set.) Space separators (Zs: U+00A0,
# U+2000-200A, U+3000 ...) are visible as spaces and survive.
JQ_DEFS='
def san: tostring
  | gsub("[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}\\p{Co}\\x{FE00}-\\x{FE0F}\\x{2800}\\x{3164}\\x{FFA0}\\x{115F}-\\x{1160}\\x{17B4}-\\x{17B5}\\x{00AD}\\x{034F}\\x{180B}-\\x{180F}\\x{2060}-\\x{206F}\\x{FFF0}-\\x{FFF8}\\x{FFFC}\\x{E0000}-\\x{E0FFF}`<>]"; "?")
  | .[0:120];
def wfkey: (.path // "unknown") | tostring | sub("@.*$"; "") | sub("^\\.github/workflows/"; "") | san;
def evkey: (.event // "unknown") | san;
def stemof: (.name // "unknown") | tostring | .[0:400] | . as $n
  | (sub("\\s*(?<p>\\((?:[^()]|\\g<p>)*\\))$"; "")) as $s | (if $s == "" then $n else $s end) | san
  | if . == "" then "unknown" else . end;
def ts: if type == "string" then sub("\\.[0-9]+Z$"; "Z") else . end;
def secs: ((.completed_at | ts | fromdateiso8601) - (.started_at | ts | fromdateiso8601));
def cls: if .conclusion == "skipped" then "skipped"
  elif (((.runner_id | type) == "number") and .runner_id > 0 | not) then "runnerless"
  elif (.started_at == null or .completed_at == null) then "untimed"
  elif secs < 0 then "untimed"
  else "counted" end;
def rhu($n; $d): if $n < 0 then -((((-$n) * 2 + $d) / ($d * 2)) | floor) else ((($n * 2 + $d) / ($d * 2)) | floor) end;
def dec($v; $dg): pow(10; $dg) as $p | ($v | if . < 0 then -. else . end) as $a
  | (if $v < 0 then "-" else "" end)
    + (($a / $p | floor | tostring) + "." + (($a % $p | tostring) | (([range(0; $dg - length)] | map("0") | join("")) + .)));
def min1($s): dec(rhu($s * 10; 60); 1);
def minrun($s; $r): dec(rhu($s * 100; 60 * $r); 2);
'

# ── C1: one runs listing file (a sub-window) against its own total_count ─────
# returns 0 ok, 1 self-check failure (message printed); exits 2 on an unreadable file
c1_check() { # <file>
  local f="$1" info docs objs totals uniqn base
  base=$(tame "$(basename "$f")")
  info=$(jq -s -r '[length,
      ([.[] | objects] | length),
      ([.[] | objects | (.total_count? | if type == "number" and . == floor and . >= 0 then . else "none" end)] | unique | map(tostring) | join(",")),
      ([.[] | objects | (.workflow_runs // [])[]? | objects | .id | select(. != null)] | unique | length)] | @tsv' "$f" 2>/dev/null) \
    || die 2 "runs file is not valid JSON: $base"
  IFS=$'\t' read -r docs objs totals uniqn <<<"$info"
  [ "$docs" != "0" ] || die 2 "runs file is empty: $base"
  [ "$docs" = "$objs" ] || die 2 "runs file holds a document that is not an object: $base"
  case ",$totals," in *,none,*) die 2 "runs file has no numeric total_count in every document: $base" ;; esac
  case "$totals" in
    *,*)
      printf 'census: SELF-CHECK C1 FAILED: %s: the listing documents disagree on total_count (%s); the pagination is inconsistent, run again\n' "$base" "$totals" >&2
      return 1 ;;
  esac
  if [ "$totals" != "$uniqn" ]; then
    printf 'census: SELF-CHECK C1 FAILED: %s: the listing reports total_count=%s but %s unique runs were fetched (the runs listing is capped at 1000 results and pagination can truncate); narrow the window (a shorter --start/--end, or a smaller CENSUS_SUBWINDOW_S) and run again\n' \
      "$base" "$totals" "$uniqn" >&2
    return 1
  fi
  if [ "$totals" -ge 1000 ]; then
    printf 'census: SELF-CHECK C1 FAILED: %s: this sub-window holds %s runs, at or over the 1000-result cap; narrow it by setting CENSUS_SUBWINDOW_S to a smaller value (seconds, default 3600) or by using a shorter --start/--end, and run again\n' \
      "$base" "$totals" >&2
    return 1
  fi
  return 0
}

# every run of a sub-window listing must have been created inside that sub-window (the windows.tsv manifest)
window_check() { # <file> <from> <to> <label>
  local out
  out=$(jq -s -r --arg lo "$2" --arg hi "$3" '
      ($lo | fromdateiso8601) as $a | ($hi | fromdateiso8601) as $b
      | [.[] | objects | (.workflow_runs // [])[]? | objects
         | (try (.created_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null) as $e
         | select($e == null or $e < $a or $e > $b) | (.id | tostring)] | .[0:10] | join(" ")' "$1") \
    || die 2 "could not check the creation times of $4"
  if [ -n "$out" ]; then
    printf 'census: SELF-CHECK C1 FAILED: %s: run(s) %s were created outside the sub-window %s..%s (or have no created_at); the listing does not match the window it was asked for\n' \
      "$4" "$(tame "$out")" "$2" "$3" >&2
    return 1
  fi
  return 0
}

# ── live fetch: sub-windows, C1 before any jobs call, then jobs per completed run ─
gh_get() { # <endpoint> <outfile> <label>   (3 attempts, then exit 2 naming the label)
  local ep="$1" out="$2" label="$3" attempt=1 gerr="$SCRATCH/gh-stderr.txt" rc hint
  assert_fixture_dir "$out"
  while :; do
    # --foreground: gh stays in this process group, so the terminal's Ctrl-C (SIGINT) reaches it too
    timeout --foreground "$GH_TIMEOUT" gh api --paginate "$ep" >"$out" 2>"$gerr"; rc=$?
    if [ "$rc" -eq 0 ]; then return 0; fi
    if [ "$attempt" -ge 3 ]; then
      hint=""
      if [ "$rc" -eq 124 ]; then hint=" (timed out after ${GH_TIMEOUT}s)"; fi
      if grep -qiE 'rate limit|HTTP (403|429)' "$gerr" 2>/dev/null; then
        hint="$hint (looks like a GitHub rate limit; wait for the reset, then run again)"
      fi
      die 2 "gh api failed for $label after 3 attempts$hint: $(tame "$(cat "$gerr" 2>/dev/null)")"
    fi
    printf 'census: gh api failed for %s (attempt %d of 3), retrying\n' "$label" "$attempt" >&2
    sleep $((RETRY_SLEEP * attempt))
    attempt=$((attempt + 1))
  done
}

fetch_runs_live() {
  FETCH_DIR=$(mktemp -d "${TMPDIR}/ci-demand-census.XXXXXXXX") || die 2 "mktemp -d failed"
  printf 'census: data dir: %q\n' "$FETCH_DIR" >&2
  local a="$S_EPOCH" b n=0 ta tb
  while [ "$a" -lt "$E_EPOCH" ]; do
    b=$((a + SUBW - 1)); [ "$b" -ge "$E_EPOCH" ] && b=$((E_EPOCH - 1))
    n=$((n + 1)); ta=$(iso "$a"); tb=$(iso "$b")
    gh_get "repos/$REPO/actions/runs?created=$ta..$tb&per_page=100" "$SCRATCH/raw-runs.json" "runs $ta..$tb"
    # keep only the fields the aggregator reads: actor logins and commit author data never reach the disk
    jq -c -s '.[] | {total_count: .total_count, workflow_runs: [(.workflow_runs // [])[]? | objects | {id, status, event, path, created_at, run_attempt}]}' \
      "$SCRATCH/raw-runs.json" >"$FETCH_DIR/runs-$n.json" || die 2 "could not read the runs listing for $ta..$tb"
    rm -f "$SCRATCH/raw-runs.json"
    c1_check "$FETCH_DIR/runs-$n.json" || exit 3
    printf '%s\t%s\t%s\n' "$n" "$ta" "$tb" >>"$FETCH_DIR/windows.tsv" || die 2 "could not write windows.tsv"
    a=$((b + 1))
  done
}

fetch_jobs_live() { # needs IDS (set by select_runs)
  local id i=0 total="${#IDS[@]}"
  for id in "${IDS[@]}"; do
    i=$((i + 1))
    gh_get "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest" "$SCRATCH/raw-jobs.json" "run $id"
    # keep only the fields the aggregator reads (runner name, labels, branch, steps and URLs never reach the disk)
    jq -c -s '.[] | {total_count: .total_count, jobs: [(.jobs // [])[]? | objects | {id, run_id, name, status, conclusion, started_at, completed_at, runner_id, run_attempt}]}' \
      "$SCRATCH/raw-jobs.json" >"$FETCH_DIR/jobs-$id.json" || die 2 "could not read the jobs listing for run $id"
    rm -f "$SCRATCH/raw-jobs.json"
    if [ $((i % 50)) -eq 0 ]; then printf 'census: jobs fetched for %d of %s runs\n' "$i" "$total" >&2; fi
  done
}

# ── run selection: C1 over every listing, then the completed-run id list, ONCE ─
IDS=()
select_runs() { # <dir>
  local dir="$1" f i n k count maxn=0 want id idlist c1fail=0 wn wlo whi nwin=0
  local isoshape='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
  local -a runs_files=() gaps=() extras=() WLO=() WHI=()
  local -A have=()
  shopt -s nullglob
  runs_files=("$dir"/runs-*.json)
  shopt -u nullglob
  count="${#runs_files[@]}"
  [ "$count" -gt 0 ] || die 2 "no runs-*.json found in $(tame "$dir")"
  for f in "${runs_files[@]}"; do
    [[ "$(basename "$f")" =~ ^runs-([1-9][0-9]*)\.json$ ]] \
      || die 2 "unexpected runs file name (want runs-<n>.json, n a positive integer): $(tame "$(basename "$f")")"
    n="${BASH_REMATCH[1]}"
    have[$n]=1
    if [ "${#n}" -gt 6 ]; then maxn=999999; elif [ "$n" -gt "$maxn" ]; then maxn="$n"; fi
  done
  # windows.tsv (written by every live fetch): one "<n> TAB <from> TAB <to>" line per sub-window. When it
  # is present the listings must be exactly runs-1..runs-<K> and every run must lie in its own window.
  if [ -f "$dir/windows.tsv" ]; then
    k=0
    local line wre prev_hi_epoch=0 lo_epoch hi_epoch
    # the whole raw line is matched (a read with IFS=tab would silently drop a leading tab or blank field)
    wre="^([0-9]+)"$'\t'"([0-9T:Z-]+)"$'\t'"([0-9T:Z-]+)$"
    while IFS= read -r line || [ -n "$line" ]; do
      k=$((k + 1))
      [[ "$line" =~ $wre ]] || die 2 "windows.tsv line $k is malformed (want: <n> TAB <from> TAB <to>, numbered from 1, no leading whitespace)"
      wn="${BASH_REMATCH[1]}"; wlo="${BASH_REMATCH[2]}"; whi="${BASH_REMATCH[3]}"
      { [ "$wn" = "$k" ] && [[ "$wlo" =~ $isoshape ]] && [[ "$whi" =~ $isoshape ]]; } \
        || die 2 "windows.tsv line $k is malformed (want: <n> TAB <from> TAB <to>, numbered from 1, no leading whitespace)"
      lo_epoch=$(date -u -d "$wlo" +%s 2>/dev/null) && hi_epoch=$(date -u -d "$whi" +%s 2>/dev/null) \
        && [ "$(iso "$lo_epoch")" = "$wlo" ] && [ "$(iso "$hi_epoch")" = "$whi" ] \
        || die 2 "windows.tsv line $k holds a date that does not exist: $(tame "$wlo") $(tame "$whi")"
      [ "$lo_epoch" -le "$hi_epoch" ] || die 2 "windows.tsv line $k ends before it starts"
      if [ "$k" -gt 1 ] && [ "$lo_epoch" -ne $((prev_hi_epoch + 1)) ]; then
        die 2 "windows.tsv line $k does not start one second after line $((k - 1)) ends: the windows must tile exactly (no gap, no overlap)"
      fi
      prev_hi_epoch="$hi_epoch"
      WLO[k]="$wlo"; WHI[k]="$whi"
    done <"$dir/windows.tsv"
    nwin="$k"
    [ "$nwin" -gt 0 ] || die 2 "windows.tsv is empty"
  fi
  want="$maxn"; if [ "$nwin" -gt 0 ]; then want="$nwin"; fi
  if [ "$maxn" -ne "$want" ] || [ "$count" -ne "$want" ]; then
    for ((i = 1; i <= want && i <= count + 20; i++)); do
      [ -n "${have[$i]:-}" ] || gaps+=("runs-$i.json")
    done
    for f in "${runs_files[@]}"; do
      n=$(basename "$f"); n="${n#runs-}"; n="${n%.json}"
      if [ "${#n}" -gt 6 ] || [ "$n" -gt "$want" ]; then extras+=("$(tame "$(basename "$f")")"); fi
    done
    printf 'census: SELF-CHECK C1 FAILED: the sub-window listings must be exactly runs-1.json..runs-%s.json (numbered contiguously from 1, matching windows.tsv when present); missing: %s; beyond that: %s\n' \
      "$want" "${gaps[*]:-none}" "${extras[*]:-none}" >&2
    exit 3
  fi

  : >"$SCRATCH/runs.ndjson"
  for ((i = 1; i <= count; i++)); do
    f="$dir/runs-$i.json"
    c1_check "$f" || c1fail=1
    if [ "$nwin" -gt 0 ]; then window_check "$f" "${WLO[$i]}" "${WHI[$i]}" "runs-$i.json" || c1fail=1; fi
    jq -c -s --argjson w "$i" '.[] | objects | (.workflow_runs // [])[]? | objects | {id, status, event, path, created_at, run_attempt, win: $w}' "$f" >>"$SCRATCH/runs.ndjson" \
      || die 2 "could not read $(tame "$(basename "$f")")"
  done
  [ "$c1fail" -eq 0 ] || exit 3

  # the selected runs: de-duplicated by id, and only the --workflow when one was given
  jq -c -s --arg wf "$WORKFLOW" "$JQ_DEFS"'unique_by(.id) | map(select($wf == "" or (wfkey == $wf))) | .[]' "$SCRATCH/runs.ndjson" >"$SCRATCH/sel.ndjson" \
    || die 2 "could not select the runs"
  idlist=$(jq -r -s 'map(select(.status == "completed")) | .[] | .id | tostring' "$SCRATCH/sel.ndjson") \
    || die 2 "could not list the completed runs"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [[ "$id" =~ ^[0-9]+$ ]] || die 2 "refusing a non-numeric run id: $(tame "$id")"
    IDS+=("$id")
  done <<<"$idlist"
  if [ "${#IDS[@]}" -eq 0 ]; then
    if [ -n "$WORKFLOW" ]; then
      die 3 "SELF-CHECK NON-VACUITY FAILED: the listing holds no completed run of workflow $(tame "$WORKFLOW") (check the name against the WORKFLOW rows of a full census); refusing to report 0 job-minutes"
    fi
    die 3 "SELF-CHECK NON-VACUITY FAILED: the listing holds no completed run; refusing to report 0 job-minutes"
  fi
}

# ── the aggregator both modes share ──────────────────────────────────────────
aggregate() { # <dir> <header>
  local dir="$1" header="$2" f id row kind rid detail dups
  local -a badla=() missing=() fewer=() more=() disagree=() foreign=() badrunner=() inflight=() nostatus=() attempt=() dupid=()

  : >"$SCRATCH/jobs.ndjson"
  for id in "${IDS[@]}"; do
    f="$dir/jobs-$id.json"
    if [ ! -f "$f" ]; then missing+=("$id"); continue; fi
    row=$(jq -s -c --arg rid "$id" '
      [.[] | objects] as $d
      | [$d[] | (.jobs // [])[]? | objects] as $all
      | ($all | unique_by(.id)) as $j
      | [$d[] | (.total_count? | if type == "number" and . == floor and . >= 0 then . else "none" end)] as $tc
      | ($tc | unique) as $ts
      | {rid: $rid,
         err: (if length == 0 then "empty"
               elif ($d | length) != length then "document that is not an object"
               elif ($ts | any(. == "none")) then "no numeric total_count"
               elif ($all | any((.id | type) != "number")) then "job without a numeric id"
               else null end),
         disagree: (($ts | length) > 1), totals: ($tc | map(tostring) | join("/")),
         total: $ts[0], n: ($j | length),
         foreign: ($all | map(select((.run_id | tostring) != $rid)) | length),
         badrunner: ($all | map(select(.runner_id != null and ((.runner_id | type) != "number"))) | length),
         nostatus: ($j | map(select(.status == null)) | length),
         inflight: ($j | map(select(.status != null and .status != "completed")) | length),
         attempts: ($j | map(.run_attempt | select(. != null) | if type == "number" then tostring else error("non-numeric run_attempt") end) | unique),
         ids: ($j | map(.id)),
         jobs: ($j | map({name, conclusion, runner_id, started_at, completed_at}))}' "$f") \
      || die 2 "jobs file is not valid JSON, or a job has a non-numeric run_attempt: jobs-$id.json"
    printf '%s\n' "$row" >>"$SCRATCH/jobs.ndjson" || die 2 "could not write the jobs scratch file"
  done
  local probs
  # slurped (-s): jq's exit status is that of the LAST input only, so a runtime error on an earlier row of a
  # multi-input stream would exit 0 and silently drop that row's findings
  probs=$(jq -s -r --slurpfile R "$SCRATCH/sel.ndjson" '
      (reduce $R[] as $r ({}; .[($r.id | tostring)] = $r.run_attempt)) as $ra
      | .[] | ((select(.err != null) | "ERR\t\(.rid)\t\(.err)"),
      (select(.err == null and .disagree) | "DISAGREE\t\(.rid)\t\(.totals)"),
      (select(.err == null and .foreign > 0) | "FOREIGN\t\(.rid)\t\(.foreign) job(s)"),
      (select(.err == null and .badrunner > 0) | "RUNNERID\t\(.rid)\t\(.badrunner) job(s)"),
      (select(.err == null and .nostatus > 0) | "NOSTATUS\t\(.rid)\t\(.nostatus) job(s)"),
      (select(.err == null and .inflight > 0) | "INFLIGHT\t\(.rid)\t\(.inflight) job(s) not completed"),
      (.rid as $id | ($ra[$id] | if . == null then null elif type == "number" then tostring else "NaN" end) as $la
       | (select(.err == null and $la == "NaN") | "BADLISTATTEMPT\t\($id)\tnot a number"),
         (select(.err == null and $la != null and $la != "NaN" and (.attempts | any(. != $la))) | "ATTEMPT\t\($id)\tlisting attempt \($la), jobs attempt \(.attempts | join("/"))")),
      (select(.err == null and (.disagree | not) and .n < .total) | "FEWER\t\(.rid)\ttotal_count=\(.total), jobs=\(.n)"),
      (select(.err == null and (.disagree | not) and .n > .total) | "MORE\t\(.rid)\ttotal_count=\(.total), jobs=\(.n)"))' "$SCRATCH/jobs.ndjson") \
    || die 2 "could not summarise the jobs files"
  local bad=""
  while IFS=$'\t' read -r kind rid detail; do
    case "$kind" in
      ERR)      bad="$bad jobs-$rid.json ($detail)" ;;
      DISAGREE) disagree+=("$rid ($detail)") ;;
      FOREIGN)  foreign+=("$rid ($detail)") ;;
      RUNNERID) badrunner+=("$rid ($detail)") ;;
      NOSTATUS) nostatus+=("$rid ($detail)") ;;
      INFLIGHT) inflight+=("$rid ($detail)") ;;
      BADLISTATTEMPT) badla+=("$rid") ;;
      ATTEMPT)  attempt+=("$(tame "$rid ($detail)")") ;;
      FEWER)    fewer+=("$rid ($detail)") ;;
      MORE)     more+=("$rid ($detail)") ;;
    esac
  done <<<"$probs"
  [ -z "$bad" ] || die 2 "unreadable jobs file(s):$(printf '%s' "$bad" | cut -c1-300)"
  [ "${#badla[@]}" -eq 0 ] || die 2 "the runs listing carries a run_attempt that is not a number, for run(s): ${badla[*]}"
  # a job id must belong to exactly one jobs file (jobs are de-duplicated within a file only)
  dups=$(jq -s -r '[.[] | select(.err == null) | .rid as $r | .ids[] | {id: ., rid: $r}]
      | group_by(.id) | map(select(length > 1)) | .[0:10][] | "\(.[0].id) (runs \(map(.rid) | unique | join("/")))"' "$SCRATCH/jobs.ndjson") \
    || die 2 "could not check the job ids across the jobs files"
  while IFS= read -r detail; do
    [ -z "$detail" ] || dupid+=("$detail")
  done <<<"$dups"
  if [ "${#missing[@]}" -gt 0 ] || [ "${#fewer[@]}" -gt 0 ] || [ "${#more[@]}" -gt 0 ] || [ "${#disagree[@]}" -gt 0 ] \
    || [ "${#foreign[@]}" -gt 0 ] || [ "${#badrunner[@]}" -gt 0 ] || [ "${#nostatus[@]}" -gt 0 ] || [ "${#inflight[@]}" -gt 0 ] || [ "${#attempt[@]}" -gt 0 ] \
    || [ "${#dupid[@]}" -gt 0 ]; then
    [ "${#missing[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: jobs file missing for completed run(s): %s\n' "${missing[*]}" >&2
    [ "${#fewer[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: jobs truncated (fewer jobs than total_count) for run(s): %s\n' "${fewer[*]}" >&2
    [ "${#more[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: more jobs than total_count (a foreign or repeated page?) for run(s): %s\n' "${more[*]}" >&2
    [ "${#disagree[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: the documents of a jobs file disagree on total_count for run(s): %s\n' "${disagree[*]}" >&2
    [ "${#foreign[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: jobs carrying another run_id than the file name (a replayed or wrong-run file) for run(s): %s\n' "${foreign[*]}" >&2
    [ "${#badrunner[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: runner_id is neither a number nor null for run(s): %s\n' "${badrunner[*]}" >&2
    [ "${#nostatus[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: a job has no status (not an API response, or edited), so it cannot be known to be completed, for run(s): %s\n' "${nostatus[*]}" >&2
    [ "${#inflight[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: a job is still in flight in a completed run (a re-run in progress?), measure again once it ends, for run(s): %s\n' "${inflight[*]}" >&2
    [ "${#attempt[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: the run_attempt of the jobs differs from the listing (a re-run since the listing), measure again, for run(s): %s\n' "${attempt[*]}" >&2
    [ "${#dupid[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: the same job id appears in more than one jobs file (a replayed or copied file), job id(s): %s\n' "${dupid[*]}" >&2
    exit 3
  fi

  # aggregate into a file first: nothing is printed unless the non-vacuity check passes too
  jq -n -r --slurpfile R "$SCRATCH/sel.ndjson" --slurpfile J "$SCRATCH/jobs.ndjson" --arg header "$header" "$JQ_DEFS"'
    $R as $all
    | ($all | map(select(.status == "completed"))) as $done
    | (reduce $J[] as $j ({}; .[$j.rid] = $j.jobs)) as $jm
    | [$done[] | . as $r | ($jm[($r.id | tostring)] // [])[]
        | cls as $c
        | {wf: ($r | wfkey), ev: ($r | evkey), stem: stemof, cls: $c, cn: (.conclusion == "cancelled"),
           sec: (if $c == "counted" then secs else 0 end), rid: ($r.id | tostring)}] as $jobs
    | (reduce ($jobs[] | select(.cn) | .rid) as $x ({}; .[$x] = true)) as $cancelled
    | ($jobs | map(select(.cls == "counted"))) as $counted
    | ($counted | map(.sec) | add // 0) as $tot
    | ($done | map({wf: wfkey, ev: evkey}) | group_by([.wf, .ev]) | map({k: [.[0].wf, .[0].ev], runs: length})) as $groups
    | ($jobs | map(select(.cls == "skipped")) | length) as $nsk
    | ($jobs | map(select(.cls == "runnerless")) | length) as $nrl
    | ($jobs | map(select(.cls == "untimed")) | length) as $nun
    | ($done | map(select(((.run_attempt | numbers) // 1) > 1)) | length) as $nre
    | ($J | map(select(.n == 0)) | length) as $nnj
    | $header,
      "TOTAL_JOB_MINUTES=\(min1($tot))",
      "TOTAL_JOB_SECONDS=\($tot)",
      "RUNS_COMPLETED=\($done | length)",
      "RUNS_NOT_COMPLETED=\(($all | length) - ($done | length))",
      "RUNS_RERUN=\($nre)",
      "RUNS_NOJOBS=\($nnj)",
      "JOBS_COUNTED=\($counted | length)",
      "JOBS_SKIPPED=\($nsk)",
      "JOBS_RUNNERLESS=\($nrl)",
      "JOBS_UNTIMED=\($nun)",
      ( $groups | sort_by(.k)[] | . as $g
        | ($counted | map(select([.wf, .ev] == $g.k))) as $c
        | ["BY_WORKFLOW", $g.k[0], $g.k[1], ($g.runs | tostring), ($c | length | tostring), min1($c | map(.sec) | add // 0)] | join("\t") ),
      ( $jobs | group_by([.wf, .ev, .stem]) | sort_by([.[0].wf, .[0].ev, .[0].stem])[] | . as $g | $g[0] as $f
        | ($g | group_by(.rid) | map(if any(.[]; .cls == "counted") then "ran"
            elif (all(.[]; .cls == "skipped") and ($cancelled[.[0].rid] | not)) then "skipped"
            else "runnerless" end)) as $kinds
        | ($g | map(select(.cls == "counted"))) as $c
        | (($c | map(.sec) | add // 0)) as $s
        | ($groups | map(select(.k == [$f.wf, $f.ev]))[0].runs) as $runs
        | ["STEM", $f.wf, $f.ev, $f.stem,
           ($kinds | map(select(. == "ran")) | length | tostring),
           ($kinds | map(select(. == "skipped")) | length | tostring),
           ($kinds | map(select(. == "runnerless")) | length | tostring),
           ($c | length | tostring), min1($s), minrun($s; $runs)] | join("\t") )
  ' >"$SCRATCH/out.txt" || die 2 "aggregation failed (unexpected input shape)"

  local counted notdone
  counted=$(sed -n 's/^JOBS_COUNTED=//p' "$SCRATCH/out.txt")
  [ "${counted:-0}" -gt 0 ] || die 3 "SELF-CHECK NON-VACUITY FAILED: no job was counted (every job skipped, runner-less or untimed); refusing to report 0 job-minutes"
  notdone=$(sed -n 's/^RUNS_NOT_COMPLETED=//p' "$SCRATCH/out.txt")
  if [ "${notdone:-0}" -gt 0 ]; then
    printf 'census: WARN: %s run(s) not yet completed are excluded, so TOTAL_JOB_MINUTES is a lower bound\n' "$notdone" >&2
  fi
  cat "$SCRATCH/out.txt" || exit 2
}

# ── main ─────────────────────────────────────────────────────────────────────
wf_line=""
if [ -n "$WORKFLOW" ]; then wf_line=$(printf '\nWORKFLOW_FILTER=%s' "$WORKFLOW"); fi
if [ "$LIVE" -eq 1 ]; then
  fetch_runs_live
  select_runs "$FETCH_DIR"
  fetch_jobs_live
  aggregate "$FETCH_DIR" "$(printf 'REPO=%s\nWINDOW_START=%s\nWINDOW_END=%s\nFETCHED_AT=%s' "$REPO" "$START" "$END" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")$wf_line"
else
  select_runs "$FIXDIR"
  aggregate "$FIXDIR" "$(printf 'REPO=fixture\nWINDOW=fixture')$wf_line"
fi
