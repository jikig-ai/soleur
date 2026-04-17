#!/usr/bin/env bash
# Queries open deferred-scope-out issues, parses file paths from their bodies,
# groups issues by top-level directory ("code area"), and reports clusters
# sorted by size descending.
#
# Usage:
#   group-by-area.sh [--milestone <title>] [--top-n N] [--min-cluster-size M]
#                    [--format text|json] [--fixture <path>]
#
# --fixture is test-only: reads the issue JSON from a file instead of `gh`.

set -euo pipefail

MILESTONE="Post-MVP / Later"
TOP_N=0           # 0 = all clusters
MIN_CLUSTER_SIZE=3
FORMAT="text"
FIXTURE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --milestone)
      MILESTONE="$2"; shift 2 ;;
    --top-n)
      TOP_N="$2"; shift 2 ;;
    --min-cluster-size)
      MIN_CLUSTER_SIZE="$2"; shift 2 ;;
    --format)
      FORMAT="$2"; shift 2 ;;
    --fixture)
      FIXTURE="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2 ;;
  esac
done

# Fetch issue JSON (either live via gh or from a fixture file for tests).
if [[ -n "$FIXTURE" ]]; then
  [[ -f "$FIXTURE" ]] || { echo "Fixture not found: $FIXTURE" >&2; exit 2; }
  ISSUES_JSON="$(cat "$FIXTURE")"
else
  command -v gh >/dev/null 2>&1 || { echo "gh CLI not available" >&2; exit 2; }
  command -v jq >/dev/null 2>&1 || { echo "jq not available" >&2; exit 2; }

  # Validate milestone title exists before querying (fail fast).
  # gh milestone flags take the title, not numeric ID — rule cq-gh-issue-create-milestone-takes-title.
  if ! gh api "repos/:owner/:repo/milestones?state=open&per_page=100" \
        --jq '.[].title' 2>/dev/null | grep -Fxq "$MILESTONE"; then
    echo "Error: milestone title '$MILESTONE' not found (open milestones only)" >&2
    exit 2
  fi

  # Two-stage piping: gh --json ... | jq. Never single-stage `gh --jq` with
  # `--arg`, which silently drops flags (learning 2026-04-15).
  ISSUES_JSON="$(gh issue list \
    --label deferred-scope-out --state open \
    --milestone "$MILESTONE" \
    --json number,title,body,labels --limit 200)"
fi

# Regex of file extensions we consider "code paths" worth clustering on.
# Use a non-capturing group so jq's `scan` returns the full match, not just
# the captured extension.
EXT_RE='(?:ts|tsx|js|jsx|py|rb|go|md|sh|yml|yaml|sql|tf|njk)'

# Build a TSV of (area<TAB>number<TAB>title) from each issue.
# Area = top two path segments if both exist (e.g. apps/web-platform), else top segment.
# Pick the most-referenced file path per issue.
TSV="$(jq -r --arg ext "$EXT_RE" '
  .[] |
  . as $i |
  ($i.body // "") |
  [ scan("[A-Za-z0-9_./\\-]+\\.\($ext)\\b") ] as $paths |
  if ($paths | length) == 0 then empty else
    ($paths | group_by(.) | map({p: .[0], n: length}) |
      sort_by(-.n) | .[0].p) as $top |
    ($top | split("/")) as $parts |
    (if ($parts | length) >= 2 then
       "\($parts[0])/\($parts[1])"
     else
       $parts[0]
     end) as $area |
    "\($area)\t\($i.number)\t\($i.title)"
  end
' <<<"$ISSUES_JSON")"

# Group by area, build cluster JSON array.
CLUSTERS_JSON="$(
  if [[ -z "$TSV" ]]; then
    echo "[]"
  else
    printf '%s\n' "$TSV" \
      | awk -F'\t' '
          { areas[$1] = areas[$1] $2 "|" $3 "\n"; counts[$1]++ }
          END {
            for (a in areas) {
              printf "%s\t%d\t%s", a, counts[a], areas[a]
              print "\036"
            }
          }
        ' \
      | tr '\036' '\n' \
      | awk -F'\t' -v RS= '
          NF { n=split($3, rows, "\n"); printf "%s\t%d\t", $1, $2;
               for (i=1;i<=n;i++) if (rows[i] != "") printf "%s\n", rows[i];
               print "---END---"
             }
        ' \
      | python3 -c '
import sys, json
clusters = []
current = None
for line in sys.stdin:
    line = line.rstrip("\n")
    if line == "---END---":
        if current is not None:
            clusters.append(current)
            current = None
        continue
    if current is None:
        parts = line.split("\t", 2)
        area = parts[0]; count = int(parts[1])
        current = {"area": area, "count": count, "issues": []}
        if len(parts) == 3 and parts[2]:
            num, _, title = parts[2].partition("|")
            if num:
                current["issues"].append({"number": int(num), "title": title})
    else:
        num, _, title = line.partition("|")
        if num:
            current["issues"].append({"number": int(num), "title": title})
if current is not None:
    clusters.append(current)
clusters.sort(key=lambda c: -c["count"])
print(json.dumps(clusters))
' 2>/dev/null || echo "[]"
  fi
)"

# Filter by min-cluster-size.
FILTERED_JSON="$(jq --argjson m "$MIN_CLUSTER_SIZE" \
  '[.[] | select(.count >= $m)]' <<<"$CLUSTERS_JSON")"

# No cluster meets floor → clean exit 0 with message.
if [[ "$(jq 'length' <<<"$FILTERED_JSON")" -eq 0 ]]; then
  echo "No cleanup cluster available; backlog is distributed across too many areas (min-cluster-size=$MIN_CLUSTER_SIZE)."
  exit 0
fi

# Apply --top-n (0 = all).
if [[ "$TOP_N" -gt 0 ]]; then
  FILTERED_JSON="$(jq --argjson n "$TOP_N" '.[:$n]' <<<"$FILTERED_JSON")"
fi

if [[ "$FORMAT" == "json" ]]; then
  echo "$FILTERED_JSON"
  exit 0
fi

# Text format: one cluster per block, issues listed with numbers and titles.
# Also print ALL clusters for operator visibility, even beyond --top-n,
# by re-emitting the unfiltered-by-top-n list below the picked ones.
jq -r '
  .[] |
  "Cluster: \(.area)  [\(.count) issues]",
  (.issues[] | "  #\(.number): \(.title)"),
  ""
' <<<"$FILTERED_JSON"

# If --top-n trimmed results, also show the full cluster listing for context.
if [[ "$TOP_N" -gt 0 ]]; then
  ALL_JSON="$(jq --argjson m "$MIN_CLUSTER_SIZE" \
    '[.[] | select(.count >= $m)]' <<<"$CLUSTERS_JSON")"
  if [[ "$(jq 'length' <<<"$ALL_JSON")" -gt "$TOP_N" ]]; then
    echo "--- Other clusters (not selected by --top-n=$TOP_N) ---"
    jq -r --argjson n "$TOP_N" '
      .[$n:] |
      .[] | "  \(.area)  [\(.count) issues]"
    ' <<<"$ALL_JSON"
  fi
fi

# Lower-floor visibility: always report clusters below min-cluster-size too,
# so the operator can see why the skill won't pick them.
BELOW_JSON="$(jq --argjson m "$MIN_CLUSTER_SIZE" \
  '[.[] | select(.count < $m)]' <<<"$CLUSTERS_JSON")"
if [[ "$(jq 'length' <<<"$BELOW_JSON")" -gt 0 ]]; then
  echo "--- Below min-cluster-size=$MIN_CLUSTER_SIZE (not picked) ---"
  jq -r '.[] | "  \(.area)  [\(.count) issues]"' <<<"$BELOW_JSON"
fi
