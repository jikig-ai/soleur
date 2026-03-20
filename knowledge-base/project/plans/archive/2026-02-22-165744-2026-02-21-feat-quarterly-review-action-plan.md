---
title: Scheduled GitHub Action for Quarterly Review Reminders
type: feat
date: 2026-02-21
issue: "#172"
parent_issue: "#165"
---

# Scheduled GitHub Action for Quarterly Review Reminders

## Overview

A GitHub Actions cron workflow that scans `knowledge-base/learnings/` for YAML frontmatter with `next_review` dates and auto-creates GitHub issues when a review is due. The immediate use case is the quarterly marketingskills overlap review (next: May 2026), but the workflow is generic -- any learning document with a `next_review` field gets a reminder.

## Problem Statement

Issue #165 established a quarterly monitoring cadence for the marketingskills plugin. The `next_review: 2026-05-20` date lives only in YAML frontmatter with no mechanism to surface it when due. Without automation, the review relies on someone remembering to check.

## Non-Goals

- Automating the review itself (the review is manual)
- Notification channels beyond GitHub Issues
- Overdue/stale date handling (if a date passes without review, a human closes or updates it)

## Proposed Solution

A single workflow file `.github/workflows/review-reminder.yml` that:

1. Runs monthly on a cron schedule (`0 0 1 * *`)
2. Supports `workflow_dispatch` with a `date_override` input for testing
3. Recursively scans `knowledge-base/learnings/**/*.md` for `next_review` frontmatter
4. Creates a GitHub issue for each file whose `next_review` date is within 7 days of today
5. Skips creation if an open issue with a matching title already exists (duplicate prevention)

## Technical Approach

### Workflow Structure

```yaml
name: Review Reminders

on:
  schedule:
    - cron: '0 0 1 * *'
  workflow_dispatch:
    inputs:
      date_override:
        description: 'Override today date (YYYY-MM-DD) for testing'
        required: false

permissions:
  issues: write
  contents: read
```

### Parsing Logic

Bash + `gh` CLI only. No Node.js, Python, or external dependencies.

```bash
# Extract next_review from frontmatter
next_review=$(sed -n '/^---$/,/^---$/{ /^next_review:/{ s/.*: *//; p; q; } }' "$file")

# Compare dates
today="${{ inputs.date_override }}"
if [[ -z "$today" ]]; then today=$(date -u +%Y-%m-%d); fi
days_until=$(( ($(date -d "$next_review" +%s) - $(date -d "$today" +%s)) / 86400 ))

# Simple two-branch logic
if [[ $days_until -ge 0 && $days_until -le 7 ]]; then
  # Due within 7 days -- create issue
fi
```

### Duplicate Prevention

Use deterministic title and exact match:

```bash
slug=$(basename "$file" .md)
expected_title="Review Reminder: $slug"
match=$(gh issue list --label review-reminder --state open --json title --jq ".[].title" | grep -cF "$expected_title")
if [[ "$match" -gt 0 ]]; then
  echo "Skipping $file -- open issue exists"
  continue
fi
```

### Issue Template

Generic -- no document-specific content. The source document contains the full review procedure.

```markdown
## Review Due: [title from frontmatter or filename]

**Review date:** YYYY-MM-DD
**Source:** [permalink to learning document]

When complete:
- [ ] Update `next_review` in the source document's YAML frontmatter
- [ ] Close this issue

_Auto-created by the review-reminder workflow._
```

## Acceptance Criteria

- [x] Workflow file exists at `.github/workflows/review-reminder.yml`
- [x] Monthly cron fires on the 1st of each month
- [x] `workflow_dispatch` trigger works with optional `date_override` input
- [x] Recursively scans `knowledge-base/learnings/**/*.md`
- [x] Creates issue when `next_review` is within 0-7 days
- [x] Skips creation when open issue with matching title already exists
- [x] Issue body includes source link and "update next_review" instruction
- [x] `review-reminder` label is created if it does not exist
- [x] No external dependencies (bash + `gh` CLI only)

## Test Scenarios

- Given a learning file with `next_review: 2026-05-20` and today is `2026-05-14`, when the workflow runs, then an issue titled "Review Reminder: 2026-02-20-marketingskills-overlap-analysis" is created with label `review-reminder`
- Given a learning file with `next_review: 2026-05-20` and today is `2026-04-01`, when the workflow runs, then no issue is created
- Given an open issue titled "Review Reminder: 2026-02-20-marketingskills-overlap-analysis" already exists, when the workflow runs and that file is due, then no duplicate is created

## References

- Overlap analysis: `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md`
- Parent issue: #165
- Feature issue: #172
- Existing workflow patterns: `.github/workflows/auto-release.yml`
