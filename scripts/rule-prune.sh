#!/usr/bin/env bash
# Surfaces AGENTS.md rules with zero hits over N weeks as GitHub issues
# milestoned to "Post-MVP / Later". Does NOT edit AGENTS.md — a human
# reviews the issue and decides whether to prune.
#
# Reads knowledge-base/project/rule-metrics.json (written by
# scripts/rule-metrics-aggregate.sh). Default threshold is 8 weeks; override
# with --weeks=<n>. Idempotent via `gh issue list --search` title match.
#
# Flags:
#   --weeks=<n>   Threshold in weeks (default 8)
#   --dry-run     Print what would be filed; do not call gh
#
# Honors $RULE_METRICS_ROOT for tests.
set -euo pipefail

WEEKS=8
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --weeks=*)  WEEKS="${arg#--weeks=}" ;;
    --dry-run)  DRY_RUN=1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${RULE_METRICS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
METRICS="$ROOT/knowledge-base/project/rule-metrics.json"

[[ -f "$METRICS" ]] || { echo "ERROR: $METRICS not found — run scripts/rule-metrics-aggregate.sh first." >&2; exit 2; }

# Compute cutoff epoch. Use --weeks=0 to force-match all zero-hit rules.
cutoff_epoch=$(( $(date -u +%s) - WEEKS * 7 * 86400 ))

# Emit candidate tuples: id\tsection\tfirst_seen\trule_text_prefix
candidates=$(jq -r \
  --argjson cutoff "$cutoff_epoch" \
  '.rules
   | map(select(.hit_count == 0
        and (.first_seen == null
             or (.first_seen | fromdateiso8601) < $cutoff)))
   | .[]
   | [.id, .section, (.first_seen // "unknown"), .rule_text_prefix]
   | @tsv' \
  "$METRICS")

if [[ -z "$candidates" ]]; then
  echo "No prune candidates (hit_count=0 for >=${WEEKS}w)."
  exit 0
fi

candidate_count=$(printf '%s\n' "$candidates" | wc -l | tr -d ' ')

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Would file $candidate_count issue(s):"
  printf '%s\n' "$candidates" | while IFS=$'\t' read -r id section first_seen prefix; do
    echo "  - rule-prune: consider retiring $id (section=$section, first_seen=$first_seen)"
  done
  exit 0
fi

filed=0
skipped=0
printf '%s\n' "$candidates" | while IFS=$'\t' read -r id section first_seen prefix; do
  title="rule-prune: consider retiring $id"
  # Idempotency: does an open issue with this exact title already exist?
  existing=$(gh issue list --search "$title in:title" 2>/dev/null \
    | jq --arg t "$title" '[.[] | select(.title == $t)] | length' 2>/dev/null \
    || echo "0")
  if [[ "${existing:-0}" -gt 0 ]]; then
    echo "[skip] issue already exists: $title"
    continue
  fi

  # Build body in a tempfile — avoids multi-line CLI arg pitfalls.
  body_file=$(mktemp)
  {
    echo "- **Rule:** \`$id\`"
    echo "- **Text (first 50 chars):** $prefix"
    echo "- **Section:** $section"
    echo "- **hit_count:** 0 over >=${WEEKS} weeks"
    echo "- **First seen:** $first_seen"
    echo
    echo "### Reassessment criteria"
    echo
    echo "Re-run \`/soleur:sync rule-prune\` in 4 weeks. If \`hit_count\` is still 0 and"
    echo "no bypasses were recorded, propose removal in \`AGENTS.md\` via a normal PR."
    echo
    echo "### This issue does NOT authorize removal"
    echo
    echo "A human must edit \`AGENTS.md\` and open a PR. Rules protecting rare but"
    echo "catastrophic failures (e.g., \`hr-never-git-stash-in-worktrees\`) may have"
    echo "zero hits and still be load-bearing."
    echo
    echo "_Filed by \`scripts/rule-prune.sh --weeks=${WEEKS}\`. See plan #2210._"
  } > "$body_file"

  gh issue create \
    --title "$title" \
    --body-file "$body_file" \
    --milestone "Post-MVP / Later" >/dev/null \
    && echo "[filed] $title"
  rm -f "$body_file"
done

echo "Done. Candidates: $candidate_count."
