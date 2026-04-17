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

usage() {
  cat <<'EOF'
Usage: group-by-area.sh [--milestone <title>] [--top-n N]
                        [--min-cluster-size M] [--format text|json]
                        [--fixture <path>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --milestone)         MILESTONE="$2";        shift 2 ;;
    --top-n)             TOP_N="$2";            shift 2 ;;
    --min-cluster-size)  MIN_CLUSTER_SIZE="$2"; shift 2 ;;
    --format)            FORMAT="$2";           shift 2 ;;
    --fixture)           FIXTURE="$2";          shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Validate numeric args before they reach jq --argjson or bash arithmetic.
[[ "$TOP_N" =~ ^[0-9]+$ ]] \
  || { echo "Error: --top-n must be a non-negative integer (got: $TOP_N)" >&2; exit 2; }
[[ "$MIN_CLUSTER_SIZE" =~ ^[0-9]+$ ]] \
  || { echo "Error: --min-cluster-size must be a non-negative integer (got: $MIN_CLUSTER_SIZE)" >&2; exit 2; }
[[ "$FORMAT" == "text" || "$FORMAT" == "json" ]] \
  || { echo "Error: --format must be 'text' or 'json' (got: $FORMAT)" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "jq not available" >&2; exit 2; }

# Fetch issue JSON (either live via gh or from a fixture file for tests).
if [[ -n "$FIXTURE" ]]; then
  [[ -f "$FIXTURE" ]] || { echo "Fixture not found: $FIXTURE" >&2; exit 2; }
  ISSUES_JSON="$(cat "$FIXTURE")"
else
  command -v gh >/dev/null 2>&1 || { echo "gh CLI not available" >&2; exit 2; }

  # Validate milestone title exists before querying (fail fast).
  # gh milestone flags take the title, not numeric ID — rule
  # cq-gh-issue-create-milestone-takes-title.
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

# Single pure-jq pipeline: parse file paths from each issue body, pick the
# most-referenced path per issue, derive its "area" (top-two path segments or
# top-one if the path has only one segment), group issues by area, sort by
# count desc. Uses a non-capturing extension regex so `scan` returns full
# matches, not captured extensions.
CLUSTERS_JSON="$(jq '
  [ .[] as $i
    | ($i.body // "")
    | [ scan("[A-Za-z0-9_./\\-]+\\.(?:ts|tsx|js|jsx|py|rb|go|md|sh|yml|yaml|sql|tf|njk)\\b") ]
      as $paths
    | select(($paths | length) > 0)
    | ($paths | group_by(.) | max_by(length) | .[0]) as $top
    | ($top | split("/")) as $parts
    | ( if ($parts | length) >= 2
        then "\($parts[0])/\($parts[1])"
        else $parts[0]
        end ) as $area
    | { area: $area, issue: { number: $i.number, title: $i.title } }
  ]
  | group_by(.area)
  | map({ area: .[0].area, count: length, issues: (map(.issue)) })
  | sort_by(-.count)
' <<<"$ISSUES_JSON")"

# Partition clusters into picked / other / below based on --top-n and
# --min-cluster-size. Produces a single object the rest of the script reads.
PARTITIONED="$(jq --argjson m "$MIN_CLUSTER_SIZE" --argjson n "$TOP_N" '
  [ .[] | select(.count >= $m) ] as $meets
  | {
      picked: (if $n > 0 then $meets[:$n] else $meets end),
      other:  (if $n > 0 then $meets[$n:] else []     end),
      below:  [ .[] | select(.count <  $m) ]
    }
' <<<"$CLUSTERS_JSON")"

# No cluster meets floor → clean exit 0 with message.
if [[ "$(jq '.picked | length' <<<"$PARTITIONED")" -eq 0 ]]; then
  echo "No cleanup cluster available; backlog is distributed across too many areas (min-cluster-size=$MIN_CLUSTER_SIZE)."
  exit 0
fi

if [[ "$FORMAT" == "json" ]]; then
  jq '.picked' <<<"$PARTITIONED"
  exit 0
fi

# Text format: picked clusters in detail, then other clusters (summary) and
# below-floor clusters (why they weren't picked) for operator context.
jq -r '
  .picked[] |
  "Cluster: \(.area)  [\(.count) issues]",
  (.issues[] | "  #\(.number): \(.title)"),
  ""
' <<<"$PARTITIONED"

if [[ "$(jq '.other | length' <<<"$PARTITIONED")" -gt 0 ]]; then
  echo "--- Other clusters (not selected by --top-n=$TOP_N) ---"
  jq -r '.other[] | "  \(.area)  [\(.count) issues]"' <<<"$PARTITIONED"
fi

if [[ "$(jq '.below | length' <<<"$PARTITIONED")" -gt 0 ]]; then
  echo "--- Below min-cluster-size=$MIN_CLUSTER_SIZE (not picked) ---"
  jq -r '.below[] | "  \(.area)  [\(.count) issues]"' <<<"$PARTITIONED"
fi
