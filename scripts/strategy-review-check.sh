#!/usr/bin/env bash
# strategy-review-check.sh — Scan strategy documents for overdue reviews
# and create GitHub issues for documents past their review cadence.
#
# Scopes: knowledge-base/{product,marketing,sales}/ top-level strategy docs
# Excludes: audits/, analytics/, distribution-content/, archive/
#
# Environment:
#   GH_TOKEN       — GitHub token with issues:write
#   DATE_OVERRIDE  — Optional YYYY-MM-DD for testing
#   SERVER_URL     — GitHub server URL (from github.server_url)
#   REPO_NAME      — owner/repo (from github.repository)
set -euo pipefail

LABEL="scheduled-strategy-review"

# --- Date setup ---
if [[ -n "${DATE_OVERRIDE:-}" ]]; then
  if ! [[ "$DATE_OVERRIDE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "::error::DATE_OVERRIDE must be YYYY-MM-DD, got: $DATE_OVERRIDE"
    exit 1
  fi
  today="$DATE_OVERRIDE"
else
  today=$(date -u +%Y-%m-%d)
fi
echo "Using date: $today"
today_epoch=$(date -d "$today" +%s)

# --- Counters ---
created=0
skipped=0
up_to_date=0
errors=0

# --- Ensure label exists ---
gh label create "$LABEL" \
  --description "Strategy document review is overdue" \
  --color "0E8A16" 2>/dev/null || true

# --- Build file list (strategy docs only, exclude subdirectories) ---
strategy_files=()
for dir in knowledge-base/product knowledge-base/marketing knowledge-base/sales/battlecards; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r f; do
      strategy_files+=("$f")
    done < <(find "$dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
  fi
done

if [[ ${#strategy_files[@]} -eq 0 ]]; then
  echo "No strategy documents found."
  exit 0
fi

echo "Scanning ${#strategy_files[@]} strategy documents..."
echo ""

for file in "${strategy_files[@]}"; do
  # Extract review_cadence from YAML frontmatter
  review_cadence=$(sed -n '/^---$/,/^---$/{ /^review_cadence:/{ s/.*: *//; p; q; } }' "$file")

  if [[ -z "$review_cadence" ]]; then
    continue
  fi

  # Map cadence to days
  case "$review_cadence" in
    monthly)   cadence_days=30 ;;
    quarterly) cadence_days=90 ;;
    biannual)  cadence_days=180 ;;
    annual)    cadence_days=365 ;;
    *)
      echo "::warning::Skipping $file -- unknown review_cadence: $review_cadence"
      errors=$((errors + 1))
      continue
      ;;
  esac

  # Extract last_reviewed; missing means immediately stale
  last_reviewed=$(sed -n '/^---$/,/^---$/{ /^last_reviewed:/{ s/.*: *//; p; q; } }' "$file")

  if [[ -z "$last_reviewed" ]]; then
    days_until=-1
  else
    if ! last_epoch=$(date -d "$last_reviewed" +%s 2>/dev/null); then
      echo "::warning::Skipping $file -- invalid last_reviewed date: $last_reviewed"
      errors=$((errors + 1))
      continue
    fi
    next_due_epoch=$((last_epoch + cadence_days * 86400))
    days_until=$(( (next_due_epoch - today_epoch) / 86400 ))
  fi

  # Flag documents due within 7 days or already past due
  if [[ $days_until -gt 7 ]]; then
    up_to_date=$((up_to_date + 1))
    continue
  fi

  # Build deterministic title
  slug="${file#knowledge-base/}"
  slug="${slug%.md}"
  expected_title="Strategy Review: $slug"

  # Dedup: skip if open issue already exists
  match=$(gh issue list --label "$LABEL" --state open --json title --jq '.[].title' | grep -cxF "$expected_title" || true)
  if [[ "$match" -gt 0 ]]; then
    echo "Skipping $file -- open issue already exists"
    skipped=$((skipped + 1))
    continue
  fi

  # Extract owner from frontmatter
  owner=$(sed -n '/^---$/,/^---$/{ /^owner:/{ s/.*: *//; p; q; } }' "$file")

  # Compute review due date
  if [[ -n "$last_reviewed" ]]; then
    review_due=$(date -d "$last_reviewed + $cadence_days days" +%Y-%m-%d)
  else
    review_due="immediately (no last_reviewed set)"
  fi

  # Create issue
  repo_url="${SERVER_URL}/${REPO_NAME}"
  file_link="${repo_url}/blob/main/${file}"

  issue_body="## Strategy Review Due: ${slug}

**Review due:** ${review_due}
**Last reviewed:** ${last_reviewed:-never}
**Cadence:** ${review_cadence}
**Owner:** ${owner:-unassigned}
**Source:** [${file}](${file_link})

When complete:
- [ ] Review the document for accuracy and relevance
- [ ] Update \`last_reviewed\` to today's date in the YAML frontmatter
- [ ] Update \`last_updated\` if content was changed
- [ ] Check \`depends_on\` documents for upstream changes since last review
- [ ] Close this issue

_Auto-created by the [scheduled-strategy-review workflow](${repo_url}/actions/workflows/scheduled-strategy-review.yml)._"

  if gh issue create \
    --title "$expected_title" \
    --body "$issue_body" \
    --label "$LABEL"; then
    echo "Created issue: $expected_title"
    created=$((created + 1))
  else
    echo "::error::Failed to create issue for $file"
    errors=$((errors + 1))
  fi
done

echo ""
echo "Summary: created=$created, skipped=$skipped, up_to_date=$up_to_date, errors=$errors"

if [[ $errors -gt 0 ]]; then
  exit 1
fi
