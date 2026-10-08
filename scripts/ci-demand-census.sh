#!/usr/bin/env bash
# ci-demand-census.sh - the committed measurement authority for hosted-runner job-minutes
# (ADR-276 Decision 7; S1 of the demand plan, #9727).
#
# USAGE
#   ci-demand-census.sh --start <YYYY-MM-DDTHH:MM:SSZ> --end <YYYY-MM-DDTHH:MM:SSZ> [--summary]
#   ci-demand-census.sh --fixture <DIR> [--summary]
#
# Live mode needs `gh` with a logged-in developer shell (`gh auth login`) and `jq`; fixture mode
# needs only `jq` and never touches the network. Both modes run ONE aggregator over the same
# directory layout (runs-<n>.json, one per sub-window, and jobs-<run_id>.json), so the offline
# suite exercises exactly the code a live run uses. Only GETs are issued (`gh api -f` would silently
# become a POST, so no -f/-F/-X is ever passed). `--summary` is accepted as the explicit selector;
# the output is always the same summary.
#
# OUTPUT (stdout, nothing else): KEY=value lines, then tab-separated tables.
#   REPO WINDOW_START WINDOW_END FETCHED_AT   (fixture mode prints REPO=fixture and WINDOW=fixture)
#   TOTAL_JOB_MINUTES RUNS_COMPLETED RUNS_NOT_COMPLETED JOBS_COUNTED JOBS_SKIPPED JOBS_RUNNERLESS JOBS_UNTIMED
#   BY_WORKFLOW <workflow> <event> <runs> <jobs> <minutes>
#   STEM <workflow> <event> <stem> <runs_ran> <runs_skipped> <runs_runnerless> <jobs> <minutes> <minutes_per_run>
# The CI per-family minutes per run are simply the `ci.yml` STEM rows (test-scripts, test-webplat,
# shard-totality-mutations, test-scripts-heavy, e2e; the light set is the sum of the rest): no family
# list lives in this script to drift.
#
# DEFINITIONS (the parent plan deferred these to this file)
#   Denominator: completed runs in the runs listing for the window. minutes_per_run divides by the
#     completed runs of that workflow and event; a run still in flight is excluded everywhere.
#   Counted job: conclusion != "skipped", runner_id > 0 (null and 0 are runner-less: queue-cancelled
#     or never started), and both started_at and completed_at set. Minutes are the raw difference in
#     integer seconds divided by 60, once (not billing-rounded). Every job lands in exactly one class,
#     so JOBS_COUNTED + JOBS_SKIPPED + JOBS_RUNNERLESS + JOBS_UNTIMED = jobs of the completed runs.
#     Class precedence: skipped, then runner-less, then untimed, then counted.
#   Workflow key: the run's `path` with any `@ref` suffix and the `.github/workflows/` prefix removed
#     (dynamic runs such as `Code Quality: PR #9653` are named per PR, so grouping is by path).
#   Stem: the job name with its trailing parenthesised matrix suffix removed (`test-scripts (3/8)`
#     becomes `test-scripts`; nested parentheses are handled).
#   STEM run classes: runs_ran = runs with at least one counted job of the stem; runs_skipped = runs
#     whose jobs of the stem all concluded skipped (the gate worked); runs_runnerless = every other run
#     that has the stem but no counted job of it (runner-less, queue-cancelled, mixed or untimed). A
#     queue-cancelled or superseded run is therefore never reported as gate-skipped.
#
# LOWER BOUNDS (a re-measure of a closed window will not reproduce an earlier figure to the digit)
#   - runs still in flight are excluded (stderr WARN, RUNS_NOT_COMPLETED > 0);
#   - `filter=latest` omits earlier attempts of re-run jobs;
#   - a job's minutes are attributed to its run's creation time, so a re-run weeks later is credited
#     to the original window.
#   Measure only a CLOSED window: end must be in the past, and the window may span at most 48 hours. Recipe for the last six full hours:
#     end=$(date -u -d '-1 hour' +%Y-%m-%dT%H:00:00Z); start=$(date -u -d '-7 hours' +%Y-%m-%dT%H:00:00Z)
#     bash scripts/ci-demand-census.sh --start "$start" --end "$end" --summary
#
# FETCH SHAPE. The runs listing is capped at 1000 results while total_count keeps the true number
#   (verified live: page 11 of 100 returns nothing), so a window is fetched in one-hour sub-windows,
#   each run through `gh api --paginate`; the sub-window ends are shifted by one second so the
#   inclusive `created=a..b` bounds partition cleanly. About 930 jobs calls per six hours, sequential;
#   a failed call is retried twice and then aborts naming the run (no resume, no `|| true`). Progress
#   goes to stderr. The fetched directory is kept under ${TMPDIR:-/var/tmp}; its path and the delete
#   command are on stderr. Live mode is for a developer shell: it refuses GITHUB_ACTIONS=true, because
#   about 930 calls would spend the repo-wide GITHUB_TOKEN budget every other workflow shares.
#
# SELF-CHECKS (a total is printed only if all pass; otherwise exit 3, reason on stderr, no
#   TOTAL_JOB_MINUTES line)
#   C1  per sub-window, the unique run ids fetched equal the first page's total_count (the 1000-result
#       cap, a displaced run and a truncated pagination all fail here; a pure duplicate whose unique
#       count equals total_count is de-duplicated, not failed). In live mode C1 runs before any jobs call.
#   C2  every completed run has a jobs file whose job count equals its total_count (a run with
#       total_count 0 and an empty list is legitimate, the file must still exist); accumulated across
#       ALL runs before the verdict, so the message names every shortfall.
#   non-vacuity  zero completed runs or zero counted jobs is refused, never reported as 0.
#
# EXIT CODES: 0 ok; 2 usage, validation, missing dependency, CI refusal, unreadable input or API/I/O
#   error; 3 self-check failure (exit 3 always means "do not trust a total, there is none").
#
# TRUST. Job names, workflow paths and events of fork-PR runs are attacker-chosen, so the STEM rows are
#   a cost measurement, not an attestation. Every string that reaches the output is stripped of control
#   characters (tab and newline included), Unicode line separators, and length-capped; every output line
#   starts with a fixed token; nothing is built by eval, bash -c or string-splicing into a jq program
#   (values reach jq through --arg); run ids are validated numeric before they build a path or a URL.
#   Knobs: CENSUS_RETRY_SLEEP (seconds between retries, default 2; the suite sets 0).
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

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

FETCH_DIR=""
SCRATCH=""
cleanup() {
  if [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ]; then
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
usage() {
  printf 'usage: %s --start <YYYY-MM-DDTHH:MM:SSZ> --end <YYYY-MM-DDTHH:MM:SSZ> [--summary]\n       %s --fixture <DIR> [--summary]\n' "$0" "$0" >&2
  exit "${1:-2}"
}
# printable-ASCII rendition of untrusted text for stderr
tame() { printf '%s' "$1" | head -c 200 | tr -c '[:print:]' '?'; }

# ── arguments ────────────────────────────────────────────────────────────────
START=""; END=""; FIXDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --start)   [ $# -ge 2 ] || usage; START="$2"; shift 2 ;;
    --end)     [ $# -ge 2 ] || usage; END="$2"; shift 2 ;;
    --fixture) [ $# -ge 2 ] || usage; FIXDIR="$2"; shift 2 ;;
    --summary) shift ;;
    -h|--help) usage 0 ;;
    *) printf 'census: unknown argument: %s\n' "$(tame "$1")" >&2; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || die 2 "jq is required"

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
S_EPOCH=0; E_EPOCH=0; REPO=""
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
  [ $((E_EPOCH - S_EPOCH)) -le 172800 ] || die 2 "window is longer than 48 hours; run the census in 48-hour pieces"
  [ "$E_EPOCH" -le "$(date -u +%s)" ] || die 2 "--end is in the future: an open window is not reproducible, use a closed one (see the header recipe)"
  [ "${GITHUB_ACTIONS:-}" != "true" ] || die 2 "live mode is refused in GitHub Actions: about 930 calls per six hours would spend the shared GITHUB_TOKEN budget; run it from a developer shell"
  command -v gh >/dev/null 2>&1 || die 2 "gh is required in live mode"
  REPO="${GH_REPO:-}"
  if [ -z "$REPO" ]; then
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) || die 2 "could not resolve the repository (set GH_REPO=owner/name)"
  fi
  [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die 2 "repository must look like owner/name: $(tame "$REPO")"
fi

# ── C1: one runs listing file (a sub-window) against its own total_count ─────
# returns 0 ok, 1 self-check failure (message printed); exits 2 on an unreadable file
c1_check() { # <file>
  local f="$1" info docs total uniq
  info=$(jq -s -r '[length, (((.[0] | objects | .total_count?) // null) | if type == "number" then . else "none" end),
      ([.[] | objects | (.workflow_runs // [])[]? | objects | .id | select(. != null)] | unique | length)] | @tsv' "$f" 2>/dev/null) \
    || die 2 "runs file is not valid JSON: $(tame "$(basename "$f")")"
  IFS=$'\t' read -r docs total uniq <<<"$info"
  [ "$docs" != "0" ] || die 2 "runs file is empty: $(tame "$(basename "$f")")"
  [ "$total" != "none" ] || die 2 "runs file has no numeric total_count: $(tame "$(basename "$f")")"
  if [ "$total" != "$uniq" ]; then
    printf 'census: SELF-CHECK C1 FAILED: %s: the listing reports total_count=%s but %s unique runs were fetched (the runs listing is capped at 1000 results and pagination can truncate); narrow the window and run again\n' \
      "$(tame "$(basename "$f")")" "$total" "$uniq" >&2
    return 1
  fi
  if [ "$total" -ge 1000 ]; then
    printf 'census: SELF-CHECK C1 FAILED: %s: this sub-window holds %s runs, at or over the 1000-result cap; narrow the window and run again\n' \
      "$(tame "$(basename "$f")")" "$total" >&2
    return 1
  fi
  return 0
}

# ── live fetch: sub-windows, C1 before any jobs call, then jobs per completed run ─
gh_get() { # <endpoint> <outfile> <label>   (3 attempts, then exit 2 naming the label)
  local ep="$1" out="$2" label="$3" attempt=1 gerr="$SCRATCH/gh-stderr.txt"
  assert_fixture_dir "$out"
  while :; do
    if gh api --paginate "$ep" >"$out" 2>"$gerr"; then return 0; fi
    if [ "$attempt" -ge 3 ]; then
      die 2 "gh api failed for $label after 3 attempts: $(tame "$(cat "$gerr" 2>/dev/null)")"
    fi
    printf 'census: gh api failed for %s (attempt %d of 3), retrying\n' "$label" "$attempt" >&2
    sleep "${CENSUS_RETRY_SLEEP:-2}"
    attempt=$((attempt + 1))
  done
}

fetch_live() {
  FETCH_DIR=$(mktemp -d "${TMPDIR}/ci-demand-census.XXXXXXXX") || die 2 "mktemp -d failed"
  printf 'census: data dir: %s\n' "$FETCH_DIR" >&2
  local a="$S_EPOCH" b n=0 ta tb
  while [ "$a" -le "$E_EPOCH" ]; do
    b=$((a + 3599)); [ "$b" -gt "$E_EPOCH" ] && b="$E_EPOCH"
    n=$((n + 1)); ta=$(iso "$a"); tb=$(iso "$b")
    gh_get "repos/$REPO/actions/runs?created=$ta..$tb&per_page=100" "$FETCH_DIR/runs-$n.json" "runs $ta..$tb"
    c1_check "$FETCH_DIR/runs-$n.json" || exit 3
    a=$((b + 1))
  done
  # every sub-window passed C1; only now do jobs calls start (completed runs only)
  local ids id i=0 total
  ids=$(jq -s -r '[.[] | objects | (.workflow_runs // [])[]? | objects | select(.status == "completed") | .id | tostring] | unique | .[]' \
    "$FETCH_DIR"/runs-*.json) || die 2 "could not list the completed runs"
  total=$(grep -c . <<<"$ids" || true)
  # every id is validated before the first jobs call: nothing non-numeric ever builds a URL
  while IFS= read -r id; do
    [ -z "$id" ] || [[ "$id" =~ ^[0-9]+$ ]] || die 2 "refusing a non-numeric run id: $(tame "$id")"
  done <<<"$ids"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    i=$((i + 1))
    gh_get "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest" "$FETCH_DIR/jobs-$id.json" "run $id"
    if [ $((i % 50)) -eq 0 ]; then printf 'census: jobs fetched for %d of %s runs\n' "$i" "$total" >&2; fi
  done <<<"$ids"
}

# ── the aggregator both modes share ──────────────────────────────────────────
aggregate() { # <dir> <header>
  local dir="$1" header="$2" f c1fail=0 id row
  local -a runs_files=() ids=() missing=() trunc=()
  shopt -s nullglob
  runs_files=("$dir"/runs-*.json)
  shopt -u nullglob
  [ "${#runs_files[@]}" -gt 0 ] || die 2 "no runs-*.json found in $(tame "$dir")"

  : >"$SCRATCH/runs.ndjson"
  for f in "${runs_files[@]}"; do
    c1_check "$f" || c1fail=1
    jq -c -s '.[] | objects | (.workflow_runs // [])[]? | objects | {id, status, event, path}' "$f" >>"$SCRATCH/runs.ndjson" \
      || die 2 "could not read $(tame "$(basename "$f")")"
  done
  [ "$c1fail" -eq 0 ] || exit 3

  # completed runs only, de-duplicated by id
  local idlist
  idlist=$(jq -s -r 'unique_by(.id) | .[] | select(.status == "completed") | .id | tostring' "$SCRATCH/runs.ndjson") \
    || die 2 "could not list the completed runs"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [[ "$id" =~ ^[0-9]+$ ]] || die 2 "refusing a non-numeric run id: $(tame "$id")"
    ids+=("$id")
  done <<<"$idlist"
  [ "${#ids[@]}" -gt 0 ] || die 3 "SELF-CHECK NON-VACUITY FAILED: the listing holds no completed run; refusing to report 0 job-minutes"

  # C2 over EVERY completed run, accumulated before the verdict
  : >"$SCRATCH/jobs.ndjson"
  for id in "${ids[@]}"; do
    f="$dir/jobs-$id.json"
    if [ ! -f "$f" ]; then missing+=("$id"); continue; fi
    row=$(jq -s -c --arg rid "$id" '
      [.[] | objects | (.jobs // [])[]? | objects] as $j
      | ((.[0] | objects | .total_count?) // null) as $t
      | {rid: $rid,
         err: (if length == 0 then "empty" elif ($t | type) != "number" then "no total_count" else null end),
         short: (($t | type) == "number" and $t != ($j | length)), total: $t, n: ($j | length),
         jobs: ($j | map({name, conclusion, runner_id, started_at, completed_at}))}' "$f") \
      || die 2 "jobs file is not valid JSON: jobs-$id.json"
    printf '%s\n' "$row" >>"$SCRATCH/jobs.ndjson"
  done
  local bad
  bad=$(jq -r 'select(.err != null) | "jobs-\(.rid).json (\(.err))"' "$SCRATCH/jobs.ndjson" | head -3 | paste -sd' ' -)
  [ -z "$bad" ] || die 2 "unreadable jobs file(s): $bad"
  while IFS= read -r row; do [ -n "$row" ] && trunc+=("$row"); done < <(jq -r 'select(.short) | "\(.rid) (total_count=\(.total), jobs=\(.n))"' "$SCRATCH/jobs.ndjson")
  if [ "${#missing[@]}" -gt 0 ] || [ "${#trunc[@]}" -gt 0 ]; then
    [ "${#missing[@]}" -gt 0 ] && printf 'census: SELF-CHECK C2 FAILED: jobs file missing for completed run(s): %s\n' "${missing[*]}" >&2
    [ "${#trunc[@]}" -gt 0 ] && printf 'census: SELF-CHECK C2 FAILED: jobs truncated (fewer jobs than total_count) for run(s): %s\n' "${trunc[*]}" >&2
    exit 3
  fi

  # aggregate into a file first: nothing is printed unless the non-vacuity check passes too
  jq -n -r --slurpfile R "$SCRATCH/runs.ndjson" --slurpfile J "$SCRATCH/jobs.ndjson" --arg header "$header" '
    def san: tostring | explode | map(if (. < 32 or (. >= 127 and . <= 159) or . == 8232 or . == 8233) then 63 else . end) | implode | .[0:120];
    def fix($d): pow(10; $d) as $p | (. * $p | round) as $r
      | (($r / $p | floor | tostring) + "." + (($r % $p) | tostring | (([range(0; $d - length)] | map("0") | join("")) + .)));
    def wfkey: (.path // "unknown") | tostring | sub("@.*$"; "") | sub("^\\.github/workflows/"; "") | san;
    def evkey: (.event // "unknown") | san;
    def stemof: (.name // "unknown") | tostring | . as $n
      | (sub("\\s*(?<p>\\((?:[^()]|\\g<p>)*\\))$"; "")) as $s | (if $s == "" then $n else $s end) | san;
    def cls: if .conclusion == "skipped" then "skipped"
      elif (((.runner_id | type) == "number") and .runner_id > 0 | not) then "runnerless"
      elif (.started_at == null or .completed_at == null) then "untimed"
      else "counted" end;
    def secs: (.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601);
    ($R | unique_by(.id)) as $all
    | ($all | map(select(.status == "completed"))) as $done
    | (reduce $J[] as $j ({}; .[$j.rid] = $j.jobs)) as $jm
    | [$done[] | . as $r | ($jm[($r.id | tostring)] // [])[]
        | {wf: ($r | wfkey), ev: ($r | evkey), stem: stemof, cls: cls, sec: (if cls == "counted" then secs else 0 end), rid: ($r.id | tostring)}] as $jobs
    | ($jobs | map(select(.cls == "counted"))) as $counted
    | ($counted | map(.sec) | add // 0) as $tot
    | ($done | map({wf: wfkey, ev: evkey}) | group_by([.wf, .ev]) | map({k: [.[0].wf, .[0].ev], runs: length})) as $groups
    | ($jobs | map(select(.cls == "skipped")) | length) as $nsk
    | ($jobs | map(select(.cls == "runnerless")) | length) as $nrl
    | ($jobs | map(select(.cls == "untimed")) | length) as $nun
    | $header,
      "TOTAL_JOB_MINUTES=\($tot / 60 | fix(1))",
      "RUNS_COMPLETED=\($done | length)",
      "RUNS_NOT_COMPLETED=\(($all | length) - ($done | length))",
      "JOBS_COUNTED=\($counted | length)",
      "JOBS_SKIPPED=\($nsk)",
      "JOBS_RUNNERLESS=\($nrl)",
      "JOBS_UNTIMED=\($nun)",
      ( $groups | sort_by(.k)[] | . as $g
        | ($counted | map(select([.wf, .ev] == $g.k))) as $c
        | ["BY_WORKFLOW", $g.k[0], $g.k[1], ($g.runs | tostring), ($c | length | tostring), (($c | map(.sec) | add // 0) / 60 | fix(1))] | join("\t") ),
      ( $jobs | group_by([.wf, .ev, .stem]) | sort_by([.[0].wf, .[0].ev, .[0].stem])[] | . as $g | $g[0] as $f
        | ($g | group_by(.rid) | map(if any(.[]; .cls == "counted") then "ran" elif all(.[]; .cls == "skipped") then "skipped" else "runnerless" end)) as $kinds
        | ($g | map(select(.cls == "counted"))) as $c
        | (($c | map(.sec) | add // 0)) as $s
        | ($groups | map(select(.k == [$f.wf, $f.ev]))[0].runs) as $runs
        | ["STEM", $f.wf, $f.ev, $f.stem,
           ($kinds | map(select(. == "ran")) | length | tostring),
           ($kinds | map(select(. == "skipped")) | length | tostring),
           ($kinds | map(select(. == "runnerless")) | length | tostring),
           ($c | length | tostring), ($s / 60 | fix(1)), ($s / 60 / $runs | fix(2))] | join("\t") )
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
if [ "$LIVE" -eq 1 ]; then
  fetch_live
  aggregate "$FETCH_DIR" "$(printf 'REPO=%s\nWINDOW_START=%s\nWINDOW_END=%s\nFETCHED_AT=%s' "$REPO" "$START" "$END" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
else
  aggregate "$FIXDIR" "$(printf 'REPO=fixture\nWINDOW=fixture')"
fi
