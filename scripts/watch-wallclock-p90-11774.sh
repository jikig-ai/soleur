#!/usr/bin/env bash
# watch-wallclock-p90-11774.sh — weekly required-check wall-clock p50/p90 probe
# and regression ratchet (#11774, epic #11556 Lever E item 1).
#
# Samples the last SAMPLE (default 30) completed, conclusion=success ci.yml runs
# per surface — pull_request and merge_group. ONE
# repos/{r}/actions/workflows/ci.yml/runs list call per surface returns run id,
# check_suite_id, head_sha, and created_at inline (no per-run actions/runs/$id
# fetch); then per run, ONE
# repos/{r}/commits/{head_sha}/check-runs call covers every required context
# across all workflows (ci.yml, secret-scan, pr-quality-guards, cla*, tenant,
# vendor-pin, sentry-destroy). For each required name — the population is every
# non-comment row of scripts/required-checks.txt, DERIVED, never enumerated — it
# keeps the check run belonging to the sampled run (own check_suite.id match
# first, else nearest started_at to the run's created_at, but never a check run
# that completed BEFORE the run was created — that belongs to an earlier trigger
# batch on the same sha), and records:
#   latency_s  = completed_at - run.created_at   (queue + runner + every
#                serialized predecessor + execution — the wall clock a PR or
#                merge-queue entry actually experiences; the runbook's cohort
#                model, the metric the epic's 20/15-min goals are about)
#   duration_s = completed_at - started_at       (execution-only diagnostic)
# Skipped/failed/missing-timestamp check runs are excluded and the row's n shows
# the surviving sample size. Success-only sampling keeps the p50/p90 an honest
# green-path figure (fast failures would skew it low; a timeout-cancelled check
# is censored data, never counted at the cap — learning 2026-10-14).
#
# Aggregation: nearest-rank p50/p90 of latency_s per (check, surface) plus p90
# duration_s as a diagnostic column. Bounds come from the committed
# scripts/required-check-wallclock-bounds.tsv — breach iff p90 > bound x
# (1+margin). A required context with NO bound row is itself a finding (the
# untracked-member class: adding a required check forces a bound row in the same
# change). A required context with zero qualifying samples on a surface that
# otherwise measured is an unmeasured finding, never a silent drop.
#
# Report home: ONE watch-owned standing tracker issue
#   `ci-wallclock-p90: required-check wall-clock report`
# find-or-file by exact title + bot author. The tracker carries the
# `ci/wallclock-p90` label — created idempotently, set at create time, and
# re-added on every weekly body rewrite — because the operator digest's §6
# read finds the tracker by that label (a raw recent-issues list would lose a
# standing tracker below its --limit window within days on this repo). The
# body is rewritten in place every run with the full table — the standing
# report the weekly operator digest's checks-pipeline section reads — and the
# tracker NEVER auto-closes (the deliberate divergence from shard-balance-watch,
# whose tracker resolves: this one is a standing report, not an episode
# tracker). Drift comments post
# only when the flagged-set identity changes — sentinel
# `<!-- wallclock-p90-watch:v1 drift=<sha1> -->` hashed over (type, check,
# surface) triples, magnitude-free, so a persistent episode does not repost.
#
# Aggregate-only (ADR-057): every emitted number is an aggregate percentile or
# count — no per-PR, per-run, or per-actor field anywhere in the report or
# comments.
#
# SELF-DISABLE: deleting .github/workflows/wallclock-p90-watch.yml retires the
# task; the standing tracker stays as the last report. Residual risk, shared
# with the sibling watches: a silently dropped scheduled run has no dead-man
# alarm — check `gh run list --workflow wallclock-p90-watch.yml --event
# schedule`.
#
# Modes:
#   (default)      measure, verdict, manage the standing tracker
#   --dry-run      measure + print the report/would-be comment; post nothing
#                  (exit code still carries the verdict)
#   --print-report print the derived population + raw aggregated rows + flagged
#                  set; no tracker reads or writes at all
# Env: GH_REPO (workflow-injected). WATCH_SAMPLE / WATCH_REQUIRED /
# WATCH_BOUNDS are the fixture seams (synthetic population/bounds/sample-size
# inputs; defaults are the committed population table and bounds TSV).
# Exit: 0 ok / missing-data (zero qualifying samples is a reported state, never
#       a ratchet failure — issue-required semantics);
#       1 bound breach, unbound/unmeasured required context, or tracker write
#       failure — the workflow goes red and offenders are named;
#       2 usage;
#       3 cannot-establish (gh API failure, empty derived population, missing or
#         malformed bounds TSV — distinct from missing data: the probe itself is
#         broken and must not read as green);
#       78 refusing to run under xtrace (#7797 — the workflow binds a token).
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

TRACKER_TITLE='ci-wallclock-p90: required-check wall-clock report'
SENTINEL_PREFIX='<!-- wallclock-p90-watch:v1 '
SAMPLE="${WATCH_SAMPLE:-30}"
REQ_FILE="${WATCH_REQUIRED:-scripts/required-checks.txt}"
BOUNDS="${WATCH_BOUNDS:-scripts/required-check-wallclock-bounds.tsv}"
GOAL_PR_S=1200   # epic #11556: pull_request p90 <= 20 min
GOAL_MQ_S=900    # epic #11556: merge_group  p90 <= 15 min
GH_REPO="${GH_REPO:-jikig-ai/soleur}"
DRY_RUN=0; PRINT_REPORT=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  --print-report) PRINT_REPORT=1 ;;
  *) echo "usage: ${0##*/} [--dry-run|--print-report]" >&2; exit 2 ;;
esac

for t in gh jq python3 sha1sum awk; do
  command -v "$t" >/dev/null 2>&1 || { echo "::error::required tool '$t' is not on PATH" >&2; exit 3; }
done

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/watch-wallclock-p90.XXXXXXXX")" || { echo "::error::cannot create scratch dir" >&2; exit 3; }
trap 'rm -rf "$WORK"' EXIT

# ---- (0) population: every non-comment row of the required-checks table ------
[[ -f "$REQ_FILE" ]] || { echo "::error::required-checks population missing: $REQ_FILE" >&2; exit 3; }
mapfile -t REQNAMES < <(awk '{ sub(/^[[:space:]]+/,""); sub(/[[:space:]]+$/,"");
  if ($0 != "" && substr($0,1,1) != "#") print }' "$REQ_FILE")
[[ "${#REQNAMES[@]}" -gt 0 ]] || {
  echo "::error::$REQ_FILE derived an EMPTY required-check population — cannot establish the measured set; never a verdict" >&2; exit 3; }
declare -A REQSET; for n in "${REQNAMES[@]}"; do REQSET["$n"]=1; done
printf '%s\n' "${REQNAMES[@]}" | jq -Rn '[inputs]' > "$WORK/reqnames.json" || {
  echo "::error::could not build the required-name array" >&2; exit 3; }
echo "required-check population: ${#REQNAMES[@]} names (derived from $REQ_FILE)"

# ---- (0b) bounds table -------------------------------------------------------
[[ -f "$BOUNDS" ]] || { echo "::error::bounds TSV missing: $BOUNDS" >&2; exit 3; }
declare -A BPR BMQ BM
while IFS=$'\t' read -r bn f1 f2 f3 f4; do
  [[ -z "${bn//[[:space:]]/}" || "$bn" == \#* ]] && continue
  if [[ -n "${f4:-}" || -z "${f1:-}" || -z "${f2:-}" || -z "${f3:-}" ]]; then
    echo "::error::malformed bounds row (needs exactly 4 columns): $bn" >&2; exit 3; fi
  if [[ ! "$f1" =~ ^[0-9]+$ || ! "$f2" =~ ^[0-9]+$ || ! "$f3" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "::error::malformed bounds row (unparsable number): $bn" >&2; exit 3; fi
  BPR["$bn"]=$f1; BMQ["$bn"]=$f2; BM["$bn"]=$f3
done < "$BOUNDS"
for bn in "${!BPR[@]}"; do
  [[ -n "${REQSET[$bn]:-}" ]] || echo "::warning::bounds row for '$bn' has no required-checks.txt row — stale bound" >&2
done
echo "bound rows: ${#BPR[@]}"

# ---- (1) sample + extract per-run check timings ------------------------------
: > "$WORK/samples.tsv"
declare -A SURF_TOTAL; SURF_TOTAL[pull_request]=0; SURF_TOTAL[merge_group]=0
runs_seen=0; fetch_fail=0
for ev in pull_request merge_group; do
  # ONE list call per surface: the workflow-runs endpoint returns id,
  # check_suite_id, head_sha, and created_at inline — no per-run
  # actions/runs/$id fetch. per_page caps at 100; --paginate only when the
  # sample window needs more than one page (the 30-run default does not).
  page_size="$SAMPLE"; [[ "$page_size" -gt 100 ]] && page_size=100
  paginate=(); [[ "$SAMPLE" -gt 100 ]] && paginate=(--paginate)
  runs="$(gh api ${paginate[@]+"${paginate[@]}"} \
      "repos/$GH_REPO/actions/workflows/ci.yml/runs?event=$ev&status=success&per_page=$page_size" \
      --jq '.workflow_runs[] | [.id, (.check_suite_id // 0), .head_sha, .created_at] | @tsv' \
      2>"$WORK/err")" || {
    echo "::error::workflow-runs list ($ev) failed: $(tail -1 "$WORK/err")" >&2; exit 3; }
  runs="$(head -n "$SAMPLE" <<<"$runs")"
  if [[ -z "$runs" ]]; then
    echo "::warning::no green $ev ci.yml runs in the window — surface contributes no samples" >&2
    continue
  fi
  while IFS=$'\t' read -r rid csid sha created; do
    [[ -n "$rid" ]] || continue
    runs_seen=$((runs_seen + 1))
    checks="$(gh api --paginate "repos/$GH_REPO/commits/$sha/check-runs?per_page=100" 2>"$WORK/err")" || {
      echo "::warning::check-runs for run $rid unreadable — skipped ($(tail -1 "$WORK/err"))" >&2
      fetch_fail=$((fetch_fail + 1)); continue; }
    # Per required name: prefer the check run in the sampled run's OWN check
    # suite; else the resolvable candidate nearest to the run's creation.
    # Resolvable = completed AFTER the run was created (an earlier completion
    # belongs to a stale suite on the same sha — drop, never misattribute).
    printf '%s' "$checks" | jq -sr \
        --argjson req "$(cat "$WORK/reqnames.json")" \
        --argjson suite "${csid:-0}" --arg ev "$ev" --arg c0 "$created" '
      def abs: if . < 0 then -. else . end;
      ([.[].check_runs[]?]) as $all
      | ($c0 | fromdateiso8601) as $t0
      | $req[] as $name
      | ([ $all[] | select(.name == $name and .conclusion == "success"
                           and .started_at != null and .completed_at != null
                           and ((.completed_at | fromdateiso8601) > $t0)) ]) as $cand
      | ([ $cand[] | select(.check_suite.id == $suite) ]) as $own
      | (if ($own | length) > 0 then $own[0]
         elif ($cand | length) > 0
           then ($cand | min_by(((.started_at | fromdateiso8601) - $t0) | abs))
         else null end) as $p
      | select($p != null)
      | "\($name)\t\($ev)\t\((($p.completed_at | fromdateiso8601) - $t0) | floor)\t\((($p.completed_at | fromdateiso8601) - ($p.started_at | fromdateiso8601)) | floor)"
    ' >> "$WORK/samples.tsv" || {
      echo "::warning::check-runs payload for run $rid unparseable — skipped" >&2
      fetch_fail=$((fetch_fail + 1)); continue; }
  done <<<"$runs"
done
total_samples="$(awk 'END{print NR}' "$WORK/samples.tsv")"
while IFS=$'\t' read -r _ sv _lat _dur; do
  SURF_TOTAL[$sv]=$(( ${SURF_TOTAL[$sv]:-0} + 1 ))
done < "$WORK/samples.tsv"
echo "sampled runs: $runs_seen (fetch failures: $fetch_fail); qualifying samples: $total_samples"
if [[ "$runs_seen" -gt 0 && "$fetch_fail" -eq "$runs_seen" ]]; then
  echo "::error::every per-run check-runs fetch failed — cannot establish a measurement" >&2; exit 3
fi

# ---- (2) aggregate: nearest-rank p50/p90 per (check, surface) ----------------
if ! python3 - "$WORK/samples.tsv" "$WORK/rows.tsv" <<'PY'; then
import sys, math
samples = {}
for line in open(sys.argv[1]):
    p = line.rstrip("\n").split("\t")
    if len(p) != 4:
        continue
    samples.setdefault((p[0], p[1]), []).append((int(float(p[2])), int(float(p[3]))))
def pct(vals, q):
    v = sorted(vals)
    return v[max(0, math.ceil(q * len(v)) - 1)]
with open(sys.argv[2], "w") as out:
    for (name, surf), pairs in samples.items():
        lat = [a for a, _ in pairs]; dur = [b for _, b in pairs]
        out.write(f"{name}\t{surf}\t{len(lat)}\t{pct(lat,.5)}\t{pct(lat,.9)}\t{pct(dur,.9)}\n")
PY
  echo "::error::aggregation failed" >&2; exit 3
fi

declare -A ROW
while IFS=$'\t' read -r rn rs rc rp50 rp90 rd90; do
  ROW["$rn|$rs"]="$rc	$rp50	$rp90	$rd90"
done < "$WORK/rows.tsv"

# ---- (3) threshold ------------------------------------------------------------
# One stable line per finding: type<TAB>check<TAB>surface<TAB>magnitude-text.
# The sentinel hashes the FIRST THREE fields only — magnitudes slide with the
# sample window and would defeat dedupe during a persistent episode.
findings=()
for n in "${REQNAMES[@]}"; do
  unbound=0
  if [[ -z "${BPR[$n]+x}" ]]; then
    unbound=1
    findings+=("unbound	$n	-	no row in scripts/required-check-wallclock-bounds.tsv")
  fi
  for ev in pull_request merge_group; do
    row="${ROW[$n|$ev]:-}"
    n_samp=0; [[ -n "$row" ]] && n_samp="${row%%	*}"
    if [[ "${SURF_TOTAL[$ev]:-0}" -gt 0 && "$n_samp" -eq 0 ]]; then
      findings+=("unmeasured	$n	$ev	no qualifying sample in the sampled window")
    fi
    [[ "$n_samp" -gt 0 && "$unbound" -eq 0 ]] || continue
    p90=""; IFS=$'\t' read -r _rc _p50 p90 _d90 <<<"$row"
    if [[ "$ev" == pull_request ]]; then b="${BPR[$n]}"; else b="${BMQ[$n]}"; fi
    if awk -v p="$p90" -v b="$b" -v m="${BM[$n]}" 'BEGIN{exit !(p > b * (1 + m))}'; then
      findings+=("breach	$n	$ev	p90=${p90}s bound=${b}s margin=${BM[$n]}")
      echo "::error::wallclock p90 breach: '$n' ($ev) p90=${p90}s > bound ${b}s x (1+${BM[$n]})" >&2
    fi
  done
done
echo "flagged findings: ${#findings[@]}"

# ---- (4) compose the standing report body ------------------------------------
sentinel_id() { printf '%s\n' "${findings[@]:+${findings[@]}}" | sed '/^$/d' \
  | cut -f1-3 | LC_ALL=C sort | sha1sum | cut -d' ' -f1; }
set_sha=""; [[ "${#findings[@]}" -gt 0 ]] && set_sha="$(sentinel_id)"
sentinel="${SENTINEL_PREFIX}drift=${set_sha} -->"

fline() {
  local t n s mag; IFS=$'\t' read -r t n s mag <<<"$1"
  case "$t" in
    breach)     printf -- "- breach: \`%s\` (\`%s\`) — %s\n" "$n" "$s" "$mag" ;;
    unbound)    printf -- "- unbound: \`%s\` — %s\n" "$n" "$mag" ;;
    unmeasured) printf -- "- unmeasured: \`%s\` (\`%s\`) — %s\n" "$n" "$s" "$mag" ;;
  esac
}

{
  printf '### wallclock-p90-watch: required-check wall-clock report\n\n'
  # Staleness signal for the digest's §6 read: a dead watch leaves this line
  # (and the issue's updatedAt) a full week+ stale.
  printf 'Report refreshed: %s\n\n' "$(date -u +%FT%TZ)"
  printf 'Standing report for #11774 (epic #11556, Lever E). The weekly workflow\n'
  printf 'rewrites this body in place; a drift comment posts only when the\n'
  printf 'flagged-set sentinel hash changes. This tracker never auto-closes.\n\n'
  printf 'Sample: last %s green `pull_request` + %s green `merge_group` `ci.yml` runs\n' \
    "$SAMPLE" "$SAMPLE"
  printf '(conclusion=success only; %s qualifying samples this window).\n' "$total_samples"
  if [[ "$total_samples" -eq 0 ]]; then
    printf '**No qualifying samples in the sampled window — no measurement this\n'
    printf 'week. This is reported, not a ratchet failure.**\n'
  fi
  printf 'Metric: `p50`/`p90` of latency (check.completed_at − run.created_at = queue\n'
  printf '+ runner + execution); `p90 dur` is the execution-only diagnostic.\n'
  printf 'Bounds: `scripts/required-check-wallclock-bounds.tsv`; breach iff\n'
  printf 'p90 > bound × (1 + margin). Epic goal: PR p90 ≤ %ss / merge-queue p90 ≤ %ss.\n\n' \
    "$GOAL_PR_S" "$GOAL_MQ_S"
  printf '| required check | surface | n | p50 (s) | p90 (s) | p90 dur (s) | bound (s) | goal (s) |\n'
  printf '|---|---|---|---|---|---|---|---|\n'
  for n in "${REQNAMES[@]}"; do
    for ev in pull_request merge_group; do
      row="${ROW[$n|$ev]:-}"
      if [[ "$ev" == pull_request ]]; then goal=$GOAL_PR_S; else goal=$GOAL_MQ_S; fi
      bound="—"; [[ -n "${BPR[$n]+x}" ]] && { [[ "$ev" == pull_request ]] && bound="${BPR[$n]}" || bound="${BMQ[$n]}"; }
      if [[ -n "$row" ]]; then
        IFS=$'\t' read -r rc rp50 rp90 rd90 <<<"$row"
        printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' "$n" "$ev" "$rc" "$rp50" "$rp90" "$rd90" "$bound" "$goal"
      else
        printf '| %s | %s | 0 | — | — | — | %s | %s |\n' "$n" "$ev" "$bound" "$goal"
      fi
    done
  done
  printf '\n**Findings**\n\n'
  if [[ "${#findings[@]}" -gt 0 ]]; then
    for f in "${findings[@]}"; do fline "$f"; done
  else
    printf '_None._\n'
  fi
  printf '\n%s\n' "$sentinel"
} > "$WORK/body.md"
cat "$WORK/body.md"

if [[ "$PRINT_REPORT" -eq 1 ]]; then
  printf '\nderived required-check population (%s names):\n' "${#REQNAMES[@]}"
  printf '%s\n' "${REQNAMES[@]}"
  printf '\naggregated rows (check / surface / n / p50 / p90 / p90dur):\n'
  cat "$WORK/rows.tsv"
  printf '\nflagged set:\n'
  printf '%s\n' "${findings[@]:+${findings[@]}}"
  exit 0
fi

# ---- (5) compose the would-be drift comment ------------------------------------
{
  if [[ "${#findings[@]}" -gt 0 ]]; then
    printf '### wallclock-p90-watch: drift findings\n\n'
    printf 'The flagged-set identity changed — the standing table lives in the issue\n'
    printf 'body (rewritten every run). Offenders:\n\n'
    for f in "${findings[@]}"; do fline "$f"; done
  else
    printf '### wallclock-p90-watch: all clear\n\n'
    printf 'The flagged set emptied — no breaches, unbound, or unmeasured required\n'
    printf 'contexts in the sampled window.\n'
  fi
  printf '\n%s\n' "$sentinel"
} > "$WORK/comment.md"

verdict=0; [[ "${#findings[@]}" -gt 0 ]] && verdict=1

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '\n--- would-be comment ---\n'
  cat "$WORK/comment.md"
  echo "dry-run: nothing posted, no sentinel spent (verdict exit $verdict)"
  exit "$verdict"
fi

# ---- (6) tracker lifecycle ------------------------------------------------------
# Find-or-file the ONE open watch-owned tracker by exact title. Client-side
# title+author filtering, same as the sibling watches: a same-title issue filed
# by anyone else on this public repo is never adopted.
ilist="$(gh issue list -R "$GH_REPO" --state open \
    --search "in:title \"$TRACKER_TITLE\"" --limit 20 --json number,title,author 2>"$WORK/err")" || {
  echo "::error::tracker find failed: $(tail -1 "$WORK/err")" >&2; exit 3; }
mapfile -t tracker_ids < <(printf '%s' "$ilist" | jq -r --arg t "$TRACKER_TITLE" '
    def bot: . == "github-actions" or . == "app/github-actions" or . == "github-actions[bot]";
    [.[] | select(.title == $t and ((.author.login // "") | bot)) | .number]
    | sort | .[]' 2>/dev/null)
tracker="${tracker_ids[0]:-}"
if [[ "${#tracker_ids[@]}" -gt 1 ]]; then
  echo "::warning::${#tracker_ids[@]} open watch-authored issues titled '$TRACKER_TITLE' (${tracker_ids[*]}) — acting on #${tracker}; the watch owns exactly one tracker, close the duplicates manually" >&2
fi
[[ "$tracker" =~ ^[0-9]+$ ]] || tracker=""

last_sha=""
if [[ -n "$tracker" ]]; then
  ijson="$(gh issue view "$tracker" --json body,author,comments 2>"$WORK/err")" || {
    echo "::error::could not read tracker #${tracker}" >&2; exit 3; }
  last_sha="$(printf '%s' "$ijson" | jq -r --arg p "${SENTINEL_PREFIX}drift=" '
      def bot: . == "github-actions" or . == "app/github-actions" or . == "github-actions[bot]";
      . as $i
      | ([(if (($i.author.login // "") | bot) then ($i.body // "") else "" end)]
         + [$i.comments[] | select(((.author.login // "") | bot)
             and ((.body // "") | contains($p))) | .body])
      | map(select(contains($p))) | last // ""
      | (capture($p + "(?<h>[0-9a-f]{40})") | .h) // ""' 2>/dev/null)" || {
    echo "::error::could not evaluate the sentinel state of #${tracker}" >&2; exit 3; }
fi

# The `ci/wallclock-p90` label is the digest §6 read's selector — create it
# idempotently before the upsert so both the create and the re-add paths can
# attach it (a repo-level label deletion self-heals on the next run).
gh label create ci/wallclock-p90 -R "$GH_REPO" --color 0e8a16 \
    --description "standing tracker for the wallclock-p90 weekly watch" >/dev/null 2>"$WORK/err" || true

if [[ -z "$tracker" ]]; then
  gh issue create -R "$GH_REPO" --title "$TRACKER_TITLE" --label ci/wallclock-p90 \
      --body-file - <"$WORK/body.md" >"$WORK/created" 2>"$WORK/err" || {
    echo "::error::tracker create failed" >&2; exit 1; }
  echo "filed standing tracker: $(tail -1 "$WORK/created")"
  exit "$verdict"
fi

# The standing report: rewrite the body every run, whatever the verdict. The
# --add-label re-attaches the selector if a human stripped it (self-heal).
gh issue edit "$tracker" -R "$GH_REPO" --add-label ci/wallclock-p90 \
    --body-file - <"$WORK/body.md" >/dev/null 2>"$WORK/err" || {
  echo "::error::report-body rewrite on #${tracker} failed" >&2; exit 1; }
echo "rewrote report body on tracker #${tracker}"

if [[ "$last_sha" == "$set_sha" ]]; then
  echo "unchanged flagged set on tracker #${tracker} (drift=${set_sha:-<empty>}) — no repost"
  exit "$verdict"
fi
gh issue comment "$tracker" --body-file - <"$WORK/comment.md" >/dev/null 2>"$WORK/err" || {
  echo "::error::posting the drift comment on #${tracker} failed" >&2; exit 1; }
echo "posted drift comment on #${tracker} (drift=${set_sha:-<empty>})"
exit "$verdict"
