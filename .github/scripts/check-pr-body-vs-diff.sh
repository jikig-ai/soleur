#!/usr/bin/env bash
# Detect PR descriptions that cite files not actually in the diff (#2905).
#
# Reads PR_NUMBER from env. Extracts file paths from the PR body (excluding
# fenced code blocks and URLs), compares to the diff's file list, and fails
# if fewer than 50% of cited paths appear in the diff.

set -uo pipefail

: "${PR_NUMBER:?PR_NUMBER env var required}"

# Body and diff
body=$(gh pr view "$PR_NUMBER" --json body --jq .body 2>/dev/null || echo "")
if [[ -z "$body" ]]; then
  echo "::warning::PR body is empty; skipping body-vs-diff check"
  exit 0
fi

diff_paths=$(gh pr diff "$PR_NUMBER" --name-only 2>/dev/null || echo "")
if [[ -z "$diff_paths" ]]; then
  echo "::warning::Could not fetch diff file list; skipping body-vs-diff check"
  exit 0
fi

# Strip fenced code blocks and URLs from body before extracting paths.
# - awk toggle on ``` lines
# - sed strips http(s) URLs that may contain .json/.md extensions
prose=$(echo "$body" \
  | awk '/^```/ {f = !f; next} !f {print}' \
  | sed -E 's@https?://[^[:space:]]+@@g')

# Extract file path candidates: tokens with at least one slash and a known
# extension. Anchors loosely; allow leading word boundary.
cited=$(echo "$prose" \
  | grep -oE '[A-Za-z0-9_./-]+\.(ts|tsx|js|jsx|md|njk|yml|yaml|json|sh|py)' \
  | grep -E '/' \
  | sort -u || true)

if [[ -z "$cited" ]]; then
  echo "PR body cites no file paths — body-vs-diff check is a no-op"
  exit 0
fi

cited_count=0
matched_count=0
orphans=()
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  cited_count=$((cited_count + 1))
  if echo "$diff_paths" | grep -Fxq "$path"; then
    matched_count=$((matched_count + 1))
  else
    orphans+=("$path")
  fi
done <<<"$cited"

if [[ "$cited_count" -eq 0 ]]; then
  exit 0
fi

# Compute matched percentage in integer math: matched*100 / cited
pct=$(( matched_count * 100 / cited_count ))
echo "Cited: $cited_count, matched in diff: $matched_count ($pct%)"

if [[ "$pct" -lt 50 ]]; then
  echo "::error::PR body cites files not in the diff (fewer than 50% matched)."
  echo "Orphan citations:"
  printf '  - %s\n' "${orphans[@]}"
  echo ""
  echo "Either update the body to describe the actual diff, or add the label"
  echo "'confirm:claude-config-change' to override. See #2905."
  exit 1
fi
exit 0
