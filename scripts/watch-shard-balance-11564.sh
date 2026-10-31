#!/usr/bin/env bash
# watch-shard-balance-11564.sh — weekly ADVISORY drift probe for the shard
# manifests (#11564, epic #11556). Samples suite-timings artifacts from the last
# SAMPLE green merge_group ci.yml runs, asks
# scripts/regenerate-shard-manifest.py --drift-report (the measurement
# authority — it alone implements the verdict exclusions and per-group artifact
# filters) for fresh floor-row medians and leg-balance rows, then thresholds the
# findings and manages ONE watch-owned tracker issue:
#   `ci-shard-balance-watch: manifest drift findings`
# carrying the sentinel `<!-- shard-balance-watch:v1 drift=<sha1-of-set> -->`.
# A comment posts only when the flagged-set hash changes; an emptied set posts
# a resolution comment and closes the tracker (the watch owns this tracker —
# the no-close convention binds trackers it does not own).
#
# Why merge_group and not --runs over main pushes: push-dedupe elides the
# shards job on push events, so push runs routinely carry no suite-timings-*
# artifacts; merge_group is the canonical as-merged full-matrix run and
# artifacts live 14 days.
#
# SELF-DISABLE: deleting .github/workflows/shard-balance-watch.yml retires the
# task; the tracker close on all-clear is the last act the watcher performs.
#
# Modes:
#   (default)      measure, threshold, manage the tracker
#   --dry-run      measure + print the would-be comment, post/close nothing
#   --print-report print the raw --drift-report rows and the flagged set; no
#                  tracker reads or writes at all
# Env: GH_TOKEN + GH_REPO (workflow-injected). WATCH_DRIFT_GROUP /
# WATCH_DURATIONS / WATCH_MANIFEST are the fixture seam (synthetic committed
# tables; default = the group's committed tables, light+heavy loop).
# Exit: 0 ok/nothing to post; 1 tracker write failed; 2 usage;
#       3 cannot establish (gh failure, zero artifact-bearing runs, or the
#       generator refused); 78 refusing to run under xtrace.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

TRACKER_TITLE='ci-shard-balance-watch: manifest drift findings'
SENTINEL_PREFIX='<!-- shard-balance-watch:v1 '
FLOOR_DRIFT_BOUND_MS=300000
LEG_DRIFT_RATIO=1.30
SAMPLE=5
GEN="${WATCH_GEN:-scripts/regenerate-shard-manifest.py}"
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
[[ -f "$GEN" ]] || { echo "::error::generator missing: $GEN" >&2; exit 3; }

WORK="$(mktemp -d "${TMPDIR:-/var/tmp}/watch-shard-balance.XXXXXXXX")" || { echo "::error::cannot create scratch dir" >&2; exit 3; }
trap 'rm -rf "$WORK"' EXIT

# ---- (1) sample: last SAMPLE green merge_group runs --------------------------
runs="$(gh run list --workflow ci.yml --event merge_group --status success -L "$SAMPLE" --json databaseId --jq '.[].databaseId' 2>"$WORK/err")" || {
  echo "::error::gh run list failed: $(tail -1 "$WORK/err")" >&2; exit 3; }
[[ -n "$runs" ]] || { echo "::error::no green merge_group ci.yml runs returned" >&2; exit 3; }
echo "sampled runs: $(printf '%s' "$runs" | tr '\n' ' ')"

# ---- (2) download each run's suite-timings artifacts --------------------------
run_dirs=()
for rid in $runs; do
  d="$WORK/runs/$rid"; mkdir -p "$d"
  if gh run download "$rid" -R "$GH_REPO" -p 'suite-timings-scripts-*' -D "$d" 2>"$WORK/err"; then
    if find "$d" -name 'suite-timings.tsv' -print -quit | grep -q .; then
      run_dirs+=("$d")
    else
      echo "::warning::run $rid downloaded no suite-timings.tsv — skipped" >&2
    fi
  else
    echo "::warning::run $rid: gh run download failed — skipped ($(tail -1 "$WORK/err"))" >&2
  fi
done
if [[ "${#run_dirs[@]}" -eq 0 ]]; then
  echo "::error::zero suite-timings artifacts across every sampled run — cannot establish a measurement (retention expiry or upstream rename); never a green all-clear" >&2
  exit 3
fi
echo "artifact-bearing runs: ${#run_dirs[@]}"

# ---- (3) measure --------------------------------------------------------------
gargs=(--drift-report)
[[ -n "${WATCH_DRIFT_GROUP:-}" ]] && gargs+=(--group "$WATCH_DRIFT_GROUP")
[[ -n "${WATCH_DURATIONS:-}" ]] && gargs+=(--durations "$WATCH_DURATIONS")
[[ -n "${WATCH_MANIFEST:-}" ]] && gargs+=(--manifest "$WATCH_MANIFEST")
for d in "${run_dirs[@]}"; do gargs+=(--timings-dir "$d"); done
report="$(python3 "$GEN" "${gargs[@]}" 2>"$WORK/err")" || {
  echo "::error::--drift-report refused: $(tail -1 "$WORK/err")" >&2; exit 3; }

# ---- (4) threshold ------------------------------------------------------------
# Flagged findings: over-bound floor rows + leg-balance breaches. Each finding
# is one stable line in the sentinel-hashed set.
findings=(); unmeasured_lines=()
: > "$WORK/legs.txt"
while IFS= read -r line; do
  case "$line" in
    DRIFT_ROW\ *)
      read -r _ g label committed fresh ts <<<"$line"
      if (( fresh >= FLOOR_DRIFT_BOUND_MS )); then
        findings+=("floor-row $g $label committed=${committed}ms median=${fresh}ms timed=${ts}")
      fi ;;
    LEG_PREDICTED\ *|LEG_OBSERVED\ *) printf '%s\n' "$line" >> "$WORK/legs.txt" ;;
    BOUND_PERFECT\ *) bound_light="${line##* }" ;;
    FLOOR_UNMEASURED\ *) unmeasured_lines+=("$line") ;;
  esac
done <<<"$report"

# Leg-balance: observed max/BOUND (light) and predicted max/mean per group.
while IFS= read -r flag; do
  [[ -n "$flag" ]] && findings+=("$flag")
done < <(awk -v ratio="$LEG_DRIFT_RATIO" '
  /^LEG_PREDICTED/ { g=$2; s[$2"\t"$3]=$4 }
  /^LEG_OBSERVED/  { o[$2"\t"$3]=$4 }
  END {
    for (k in s) { split(k,a,"\t"); tot[a[1]]+=s[k]; if (s[k]>mx[a[1]]) mx[a[1]]=s[k] }
    for (g in mx) { n=0; for (k in s) { split(k,a,"\t"); if (a[1]==g) n++ }
      mean=tot[g]/n; if (mean>0 && mx[g]/mean > ratio)
        printf "leg-predicted %s max=%dms mean=%dms\n", g, mx[g], mean }
    for (k in o) { split(k,a,"\t"); tot[a[1]]+=o[k]; if (o[k]>mxo) mxo=o[k] }
  }' "$WORK/legs.txt" 2>/dev/null)
if [[ -n "${bound_light:-}" && "${bound_light:-0}" -gt 0 ]]; then
  obs_max="$(awk '/^LEG_OBSERVED/{if($4>m)m=$4} END{print m+0}' "$WORK/legs.txt")"
  if awk -v m="$obs_max" -v b="$bound_light" -v r="$LEG_DRIFT_RATIO" \
       'BEGIN{exit !(m/b > r)}'; then
    findings+=("leg-observed light max=${obs_max}ms bound=${bound_light}ms")
  fi
fi

echo "flagged findings: ${#findings[@]}"
if [[ "$PRINT_REPORT" -eq 1 ]]; then
  printf '%s\n' "$report"
  printf '%s\n' "${findings[@]:+${findings[@]}}"
  exit 0
fi

# ---- (5) compose the would-be comment -----------------------------------------
set_sha=""
if [[ "${#findings[@]}" -gt 0 ]]; then
  set_sha="$(printf '%s\n' "${findings[@]}" | LC_ALL=C sort | sha1sum | cut -d' ' -f1)"
fi
sentinel="${SENTINEL_PREFIX}drift=${set_sha} -->"
{
  printf '### shard-balance-watch: manifest drift findings\n\n'
  printf 'Sample: last %s green `merge_group` `ci.yml` runs (%s artifact-bearing).\n' "$SAMPLE" "${#run_dirs[@]}"
  printf 'Bounds: floor rows >= %sms (5 min); leg ratio > %s.\n\n' "$FLOOR_DRIFT_BOUND_MS" "$LEG_DRIFT_RATIO"
  if [[ "${#findings[@]}" -gt 0 ]]; then
    printf '%s\n' "${findings[@]}" | sed 's/^/- /'
  else
    printf '_No findings._\n'
  fi
  printf '\n'
  for l in ${unmeasured_lines[@]+"${unmeasured_lines[@]}"}; do
    g="${l#FLOOR_UNMEASURED }"; g="${g%% *}"; c="${l##* }"
    printf '_info: %s floor row(s) in %s measured in no sampled run._\n' "$c" "$g"
  done
} > "$WORK/comment.md"
cat "$WORK/comment.md"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '\n%s\n' "$sentinel"
  echo "dry-run: nothing posted, no sentinel spent"
  exit 0
fi

# ---- (6) tracker lifecycle ----------------------------------------------------
# Find-or-file the ONE open watch-owned tracker by exact title. Filtering is
# client-side so a mocked/partial `gh` reply can never read as a tracker id.
ilist="$(gh issue list -R "$GH_REPO" --state open \
    --search "in:title \"$TRACKER_TITLE\"" --limit 20 --json number,title 2>"$WORK/err")" || {
  echo "::error::tracker find failed: $(tail -1 "$WORK/err")" >&2; exit 3; }
tracker="$(printf '%s' "$ilist" | jq -r --arg t "$TRACKER_TITLE" \
    '[.[] | select(.title==$t)][0].number // empty' 2>/dev/null)" || tracker=""
[[ "$tracker" =~ ^[0-9]+$ ]] || tracker=""

last_sha=""
if [[ -n "$tracker" ]]; then
  ijson="$(gh issue view "$tracker" --json comments 2>"$WORK/err")" || {
    echo "::error::could not read tracker #${tracker} comments" >&2; exit 3; }
  last_sha="$(printf '%s' "$ijson" | jq -r --arg p "${SENTINEL_PREFIX}drift=" '
      [.comments[] | select(((.author.login // "") == "github-actions" or (.author.login // "") == "github-actions[bot]")
        and ((.body // "") | contains($p))) | .body]
      | last // "" | (capture("drift=(?<h>[0-9a-f]{40})") | .h) // ""' 2>/dev/null)" || {
    echo "::error::could not evaluate the comments of #${tracker}" >&2; exit 3; }
fi

if [[ "${#findings[@]}" -eq 0 ]]; then
  if [[ -n "$tracker" ]]; then
    printf 'All-clear: no floor-row or leg-balance drift in the sampled runs. Closing this tracker; it re-opens automatically if drift returns.\n' \
      | gh issue comment "$tracker" --body-file - >/dev/null 2>"$WORK/err" \
      && gh issue close "$tracker" >/dev/null 2>>"$WORK/err" || {
        echo "::error::resolution post/close on #${tracker} failed" >&2; exit 1; }
    echo "resolved: posted the all-clear and closed tracker #${tracker}"
  else
    echo "no findings and no open tracker — nothing to do"
  fi
  exit 0
fi

payload="$(cat "$WORK/comment.md"; printf '\n%s' "$sentinel")"
if [[ -z "$tracker" ]]; then
  printf '%s' "$payload" | gh issue create -R "$GH_REPO" --title "$TRACKER_TITLE" \
      --body-file - >"$WORK/created" 2>"$WORK/err" || {
    echo "::error::tracker create failed" >&2; exit 1; }
  echo "filed tracker: $(tail -1 "$WORK/created")"
  exit 0
fi
if [[ "$last_sha" == "$set_sha" ]]; then
  echo "unchanged flagged set on tracker #${tracker} (drift=${set_sha}) — no repost"
  exit 0
fi
printf '%s' "$payload" | gh issue comment "$tracker" --body-file - >/dev/null 2>"$WORK/err" || {
  echo "::error::posting findings on #${tracker} failed" >&2; exit 1; }
echo "posted updated findings on #${tracker} (drift=${set_sha})"
exit 0
