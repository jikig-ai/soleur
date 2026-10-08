#!/usr/bin/env bash
# ci-demand-census.sh - the committed measurement authority for hosted-runner job-minutes
# (ADR-276 Decision 7; S1 of the demand plan, #9727).
#
# USAGE
#   ci-demand-census.sh --start <YYYY-MM-DDTHH:MM:SSZ> --end <YYYY-MM-DDTHH:MM:SSZ> [--workflow <file>] [--summary]
#   ci-demand-census.sh --fixture <DIR> [--workflow <file>] [--summary]
#   ci-demand-census.sh --help          (usage and the output schema, on stdout, exit 0)
#
# Live mode needs `gh` with a logged-in developer shell (`gh auth login`), `timeout` and `jq`; fixture
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
#     grep -E '^(REPO|WINDOW|TOTAL|RUNS|JOBS|WORKFLOW)|^STEM\tsecret-scan' "$out"   # the issue-comment subset
#     wc -c <"$out"      # a GitHub comment holds at most 65536 characters: keep this under 60000, else post the grep subset
#   To cost one workflow only: add `--workflow secret-scan.yml` (the Phase-7 call). C1 still runs over every run
#   of the window, jobs are fetched for that workflow's completed runs only, and every figure then describes
#   that workflow alone.
#
# OUTPUT (stdout, nothing else): KEY=value lines, then tab-separated tables.
#   REPO WINDOW_START WINDOW_END FETCHED_AT   (fixture mode prints REPO=fixture and WINDOW=fixture)
#   WORKFLOW_FILTER                           (only with --workflow)
#   TOTAL_JOB_MINUTES TOTAL_JOB_SECONDS RUNS_COMPLETED RUNS_NOT_COMPLETED RUNS_RERUN
#   JOBS_COUNTED JOBS_SKIPPED JOBS_RUNNERLESS JOBS_UNTIMED
#   BY_WORKFLOW <workflow> <event> <runs> <jobs> <minutes>
#   STEM <workflow> <event> <stem> <runs_ran> <runs_skipped> <runs_runnerless> <jobs> <minutes> <minutes_per_run>
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
#     `cancelled` (the gate worked); runs_runnerless = every other run (runner-less, queue-cancelled,
#     mixed or untimed). A superseded run whose parent job was queue-cancelled makes its dependents
#     conclude skipped, so a stem with no counted job in a run that holds a cancelled job is counted as
#     runner-less, not as a gate-skip; the gate-skip share is therefore not inflated by superseded
#     runs. A run whose cancelled jobs are unrelated to the gate can still be classed runner-less: the
#     conservative direction.
#
# BIAS (a re-measure of a closed window will not reproduce an earlier figure to the digit)
#   - runs still in flight are excluded (stderr WARN, RUNS_NOT_COMPLETED > 0): a lower bound;
#   - `filter=latest` omits earlier attempts of re-run jobs, so a re-run run is counted by its last
#     attempt only; RUNS_RERUN says how many completed runs have run_attempt > 1. A re-run can bias the
#     figure in EITHER direction (the last attempt may be shorter or longer than the first, and the
#     earlier attempts' minutes are not in the figure at all);
#   - a job's minutes are attributed to its run's creation time, so a re-run weeks later is credited
#     to the original window.
#   Measure only a CLOSED window: end must be in the past, and the window may span at most 12 hours.
#
# FETCH SHAPE. The runs listing is capped at 1000 results while total_count keeps the true number
#   (verified live: page 11 of 100 returns nothing), so a window is fetched in one-hour sub-windows
#   [a, a+3599] (the last one shortened to end-1), each run through `gh api --paginate`; the inclusive
#   `created=a..b` bounds therefore partition the exclusive window exactly. Only these fields of each run
#   are kept on disk: id, status, event, path, created_at, run_attempt (actor and commit data are
#   dropped at fetch time). About 155 jobs calls per hour of window, sequential: expect about 15 minutes
#   per 6 h window. Each call has a timeout; a failed call is retried twice (linearly longer sleeps) and
#   then aborts naming the run (no resume, no `|| true`); if gh's stderr looks like a rate limit
#   (HTTP 403/429) the abort message says so. Progress goes to stderr. The fetched directory is kept
#   under ${TMPDIR:-/var/tmp}; its path and the delete command are on stderr. Live mode is for a
#   developer shell: it refuses GITHUB_ACTIONS=true, because about 930 calls per six hours would spend
#   the repo-wide GITHUB_TOKEN budget every other workflow shares.
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
#       inside its own sub-window. In live mode C1 runs over every sub-window before any jobs call.
#   C2  every completed run (of the --workflow, when given) has a jobs file whose UNIQUE job count (jobs
#       are de-duplicated by id) equals its total_count, whose documents all agree on total_count, whose
#       jobs all carry that run's own run_id, and whose runner_id values are numbers or null (a run with
#       total_count 0 and an empty list is legitimate, the file must still exist); accumulated across
#       ALL runs before the verdict, so the message names every shortfall.
#   non-vacuity  zero completed runs or zero counted jobs is refused, never reported as 0.
#
# EXIT CODES: 0 ok; 2 usage, validation, missing dependency, CI refusal, unreadable input (not
#   JSON, wrong shape, a jq failure) or API/I/O error (a gh call that failed or timed out three times,
#   a relative TMPDIR); 3 self-check failure (exit 3 always means "do not trust a total, there is none").
#
# TRUST. Job names, workflow paths and events of fork-PR runs are attacker-chosen, so the STEM rows are
#   a cost measurement, not an attestation. Every string that reaches the output is stripped of control
#   characters (tab and newline included), Unicode line and bidi separators, zero-width and format
#   characters, backtick, < and >, and length-capped at 120; every output line starts with a fixed token;
#   nothing is built by eval, bash -c or string-splicing into a jq program (values reach jq through
#   --arg); run ids are validated numeric before they build a path or a URL.
#
# KNOBS (environment)
#   GH_REPO               owner/name to measure (default: the current repository, via `gh repo view`)
#   CENSUS_SUBWINDOW_S    sub-window length in seconds (default 3600; 60..43200). Lower it when C1 reports
#                         a sub-window at the 1000-result cap.
#   CENSUS_RETRY_SLEEP    seconds slept after a failed gh call, times the attempt number (default 10; the
#                         suite sets 0)
#   CENSUS_GH_TIMEOUT     seconds before one gh call is killed and counted as failed (default 180)
#   TMPDIR                scratch and fetch root; must be an absolute path (default /var/tmp)
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
assert_fixture_dir "$TMPDIR"
export TMPDIR

FETCH_DIR=""
SCRATCH=""
cleanup() {
  if [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ]; then
    # cannot fire: TMPDIR was validated before this trap existed (kept so the rm is guarded by construction)
    assert_fixture_dir "$SCRATCH"
    rm -rf "$SCRATCH"
  fi
  # last stderr line of a live run: how to delete the fetched data
  if [ -n "$FETCH_DIR" ]; then printf 'census: remove fetched data with: rm -rf %s\n' "$FETCH_DIR" >&2; fi
  return 0
}
trap cleanup EXIT

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
Exit codes: 0 ok; 2 usage/validation/I-O error; 3 self-check failure (no total is printed).

Output (stdout): KEY=value lines, then tab-separated tables.
  REPO=  WINDOW_START=  WINDOW_END=  FETCHED_AT=      (fixture mode: REPO=fixture, WINDOW=fixture)
  WORKFLOW_FILTER=<file>                              (only with --workflow)
  TOTAL_JOB_MINUTES=<one decimal>  TOTAL_JOB_SECONDS=<integer>  (the seconds figure is authoritative)
  RUNS_COMPLETED=  RUNS_NOT_COMPLETED=  RUNS_RERUN=
  JOBS_COUNTED=  JOBS_SKIPPED=  JOBS_RUNNERLESS=  JOBS_UNTIMED=
  BY_WORKFLOW <TAB> workflow <TAB> event <TAB> runs <TAB> jobs <TAB> minutes
  STEM <TAB> workflow <TAB> event <TAB> stem <TAB> runs_ran <TAB> runs_skipped <TAB> runs_runnerless <TAB> jobs <TAB> minutes <TAB> minutes_per_run
Printed minutes are rounded per row, so table rows are not additive; read the KEY lines.
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
START=""; END=""; FIXDIR=""; WORKFLOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --start)    [ $# -ge 2 ] || usage; START="$2"; shift 2 ;;
    --end)      [ $# -ge 2 ] || usage; END="$2"; shift 2 ;;
    --fixture)  [ $# -ge 2 ] || usage; FIXDIR="$2"; shift 2 ;;
    --workflow) [ $# -ge 2 ] || usage; WORKFLOW="$2"; shift 2 ;;
    --summary)  shift ;;
    -h|--help)  usage 0 ;;
    *) printf 'census: unknown argument: %s\n' "$(tame "$1")" >&2; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || die 2 "jq is required"

if [ -n "$WORKFLOW" ]; then
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
  SUBW="${CENSUS_SUBWINDOW_S:-3600}"
  [[ "$SUBW" =~ ^[0-9]+$ ]] && [ "$SUBW" -ge 60 ] && [ "$SUBW" -le 43200 ] || die 2 "CENSUS_SUBWINDOW_S must be an integer from 60 to 43200 seconds: $(tame "$SUBW")"
  RETRY_SLEEP="${CENSUS_RETRY_SLEEP:-10}"
  [[ "$RETRY_SLEEP" =~ ^[0-9]{1,4}$ ]] || die 2 "CENSUS_RETRY_SLEEP must be a whole number of seconds: $(tame "$RETRY_SLEEP")"
  GH_TIMEOUT="${CENSUS_GH_TIMEOUT:-180}"
  [[ "$GH_TIMEOUT" =~ ^[1-9][0-9]{0,4}$ ]] || die 2 "CENSUS_GH_TIMEOUT must be a positive whole number of seconds: $(tame "$GH_TIMEOUT")"
  command -v gh >/dev/null 2>&1 || die 2 "gh is required in live mode"
  command -v timeout >/dev/null 2>&1 || die 2 "timeout (coreutils) is required in live mode"
  REPO="${GH_REPO:-}"
  if [ -z "$REPO" ]; then
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) || die 2 "could not resolve the repository (set GH_REPO=owner/name)"
  fi
  [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die 2 "repository must look like owner/name: $(tame "$REPO")"
  # a segment made only of dots (".", "..") is a path component, not a name
  [[ "${REPO%%/*}" =~ ^\.+$ || "${REPO#*/}" =~ ^\.+$ ]] && die 2 "repository must look like owner/name: $(tame "$REPO")"
fi

# ── jq definitions shared by the run selection and the aggregator ────────────
# san: untrusted text to printable output: C0/C1 controls (U+0085 included), DEL, U+2028/2029, the
# bidi controls U+202A-202E and U+2066-2069, U+200B-200F, U+061C, U+FEFF, backtick, < and > become ?
JQ_DEFS='
def san: tostring | explode
  | map(if (. < 32 or (. >= 127 and . <= 159) or . == 8232 or . == 8233 or (. >= 8234 and . <= 8238)
            or (. >= 8294 and . <= 8297) or (. >= 8203 and . <= 8207) or . == 1564 or . == 65279
            or . == 96 or . == 60 or . == 62) then 63 else . end)
  | implode | .[0:120];
def wfkey: (.path // "unknown") | tostring | sub("@.*$"; "") | sub("^\\.github/workflows/"; "") | san;
def evkey: (.event // "unknown") | san;
def stemof: (.name // "unknown") | tostring | . as $n
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
    timeout "$GH_TIMEOUT" gh api --paginate "$ep" >"$out" 2>"$gerr"; rc=$?
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
  printf 'census: data dir: %s\n' "$FETCH_DIR" >&2
  local a="$S_EPOCH" b n=0 ta tb
  while [ "$a" -lt "$E_EPOCH" ]; do
    b=$((a + SUBW - 1)); [ "$b" -ge "$E_EPOCH" ] && b=$((E_EPOCH - 1))
    n=$((n + 1)); ta=$(iso "$a"); tb=$(iso "$b")
    gh_get "repos/$REPO/actions/runs?created=$ta..$tb&per_page=100" "$SCRATCH/raw-runs.json" "runs $ta..$tb"
    # keep only the fields the aggregator reads: actor logins and commit author data never reach the disk
    jq -c '{total_count: .total_count, workflow_runs: [(.workflow_runs // [])[]? | objects | {id, status, event, path, created_at, run_attempt}]}' \
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
    gh_get "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest" "$FETCH_DIR/jobs-$id.json" "run $id"
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
    while IFS=$'\t' read -r wn wlo whi || [ -n "$wn" ]; do
      k=$((k + 1))
      [ "$wn" = "$k" ] && [[ "$wlo" =~ $isoshape ]] && [[ "$whi" =~ $isoshape ]] \
        || die 2 "windows.tsv line $k is malformed (want: <n> TAB <from> TAB <to>, numbered from 1)"
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
      die 3 "SELF-CHECK NON-VACUITY FAILED: the listing holds no completed run of workflow $(tame "$WORKFLOW"); refusing to report 0 job-minutes"
    fi
    die 3 "SELF-CHECK NON-VACUITY FAILED: the listing holds no completed run; refusing to report 0 job-minutes"
  fi
}

# ── the aggregator both modes share ──────────────────────────────────────────
aggregate() { # <dir> <header>
  local dir="$1" header="$2" f id row kind rid detail
  local -a missing=() fewer=() more=() disagree=() foreign=() badrunner=()

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
         jobs: ($j | map({name, conclusion, runner_id, started_at, completed_at}))}' "$f") \
      || die 2 "jobs file is not valid JSON: jobs-$id.json"
    printf '%s\n' "$row" >>"$SCRATCH/jobs.ndjson" || die 2 "could not write the jobs scratch file"
  done
  local probs
  probs=$(jq -r '
      (select(.err != null) | "ERR\t\(.rid)\t\(.err)"),
      (select(.err == null and .disagree) | "DISAGREE\t\(.rid)\t\(.totals)"),
      (select(.err == null and .foreign > 0) | "FOREIGN\t\(.rid)\t\(.foreign) job(s)"),
      (select(.err == null and .badrunner > 0) | "RUNNERID\t\(.rid)\t\(.badrunner) job(s)"),
      (select(.err == null and (.disagree | not) and .n < .total) | "FEWER\t\(.rid)\ttotal_count=\(.total), jobs=\(.n)"),
      (select(.err == null and (.disagree | not) and .n > .total) | "MORE\t\(.rid)\ttotal_count=\(.total), jobs=\(.n)")' "$SCRATCH/jobs.ndjson") \
    || die 2 "could not summarise the jobs files"
  local bad=""
  while IFS=$'\t' read -r kind rid detail; do
    case "$kind" in
      ERR)      bad="$bad jobs-$rid.json ($detail)" ;;
      DISAGREE) disagree+=("$rid ($detail)") ;;
      FOREIGN)  foreign+=("$rid ($detail)") ;;
      RUNNERID) badrunner+=("$rid ($detail)") ;;
      FEWER)    fewer+=("$rid ($detail)") ;;
      MORE)     more+=("$rid ($detail)") ;;
    esac
  done <<<"$probs"
  [ -z "$bad" ] || die 2 "unreadable jobs file(s):$(printf '%s' "$bad" | cut -c1-300)"
  if [ "${#missing[@]}" -gt 0 ] || [ "${#fewer[@]}" -gt 0 ] || [ "${#more[@]}" -gt 0 ] || [ "${#disagree[@]}" -gt 0 ] \
    || [ "${#foreign[@]}" -gt 0 ] || [ "${#badrunner[@]}" -gt 0 ]; then
    [ "${#missing[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: jobs file missing for completed run(s): %s\n' "${missing[*]}" >&2
    [ "${#fewer[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: jobs truncated (fewer jobs than total_count) for run(s): %s\n' "${fewer[*]}" >&2
    [ "${#more[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: more jobs than total_count (a foreign or repeated page?) for run(s): %s\n' "${more[*]}" >&2
    [ "${#disagree[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: the documents of a jobs file disagree on total_count for run(s): %s\n' "${disagree[*]}" >&2
    [ "${#foreign[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: jobs carrying another run_id than the file name (a replayed or wrong-run file) for run(s): %s\n' "${foreign[*]}" >&2
    [ "${#badrunner[@]}" -eq 0 ] || printf 'census: SELF-CHECK C2 FAILED: runner_id is neither a number nor null for run(s): %s\n' "${badrunner[*]}" >&2
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
    | $header,
      "TOTAL_JOB_MINUTES=\(min1($tot))",
      "TOTAL_JOB_SECONDS=\($tot)",
      "RUNS_COMPLETED=\($done | length)",
      "RUNS_NOT_COMPLETED=\(($all | length) - ($done | length))",
      "RUNS_RERUN=\($nre)",
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
  cat "$SCRATCH/out.txt"
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
