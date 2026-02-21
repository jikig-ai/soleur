---
title: GitHub Actions Workflow Security Patterns
category: integration-issues
tags:
  - github-actions
  - security
  - ci-cd
module: infrastructure
date: 2026-02-21
synced_to: [security-sentinel]
---

# Learning: GitHub Actions Workflow Security Patterns

## Problem

When writing a GitHub Actions cron workflow that creates issues via `gh` CLI, several security and correctness patterns were missed in the initial implementation and caught during review.

## Solution

Four patterns to apply when writing GitHub Actions workflows:

1. **Pin actions to commit SHAs, not mutable tags.** `actions/checkout@v4` is a mutable tag. Use `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` to prevent supply-chain attacks.

2. **Validate `workflow_dispatch` inputs with regex.** `date -d` accepts natural language ("last year", "next month"), not just ISO dates. Add `[[ "$INPUT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]` before using date inputs.

3. **Use `grep -cxF` (not `grep -cF`) for exact title dedup.** `-F` disables regex but still does substring matching. `-x` adds whole-line matching. Without it, "session-hygiene" matches "session-hygiene-advanced".

4. **Check `gh issue create` exit code explicitly.** Wrap in `if gh issue create ...; then ... else exit 1; fi` so API failures don't produce a green checkmark with zero issues created.

## Key Insight

GitHub Actions workflows have a unique security surface: mutable action tags, permissive input parsing, and silent failures. The security-reminder hook in this repo catches the risky-input patterns but not the pinning or exit-code issues. Review agents caught all four.

## Related

- Workflow file: `.github/workflows/review-reminder.yml`
- Issue: #172
