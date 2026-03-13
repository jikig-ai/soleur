---
title: "GitHub Actions Audit: Run History Over Reading YAML"
category: implementation-patterns
tags: [github-actions, ci-cd, maintenance, audit]
date: 2026-02-21
last_reviewed: 2026-02-21
review_cadence: quarterly
---

# GitHub Actions Audit Methodology

## Problem

GitHub Actions workflows accumulate over time. Some get added speculatively (e.g., Claude Code @mention handler), others become redundant as newer workflows absorb their functionality (e.g., release-announce.yml made redundant by auto-release.yml's built-in Discord step). Reading the YAML alone doesn't tell you if a workflow is actually used.

## Solution

Audit using actual run history, not just YAML definitions:

```bash
# 1. Overall run distribution (shows which workflows dominate)
gh run list --limit 100 --json name --jq '.[].name' | sort | uniq -c | sort -rn

# 2. Per-workflow drill-down for suspected unused workflows
gh run list --workflow=<name>.yml --limit 10 --json conclusion,createdAt

# 3. Check for "always skipped" pattern (workflow triggers but condition never matches)
gh run list --workflow=<name>.yml --limit 10 --json conclusion --jq '.[].conclusion'
```

### Removal indicators

- **Always skipped**: Workflow triggers fire but the `if:` condition never matches (e.g., `claude.yml` waiting for @claude mentions nobody makes)
- **Superseded**: Another workflow already handles the same job (e.g., `release-announce.yml` for Discord when `auto-release.yml` posts directly)
- **Zero runs**: Workflow exists but has never triggered (check if it's new or genuinely dead)

### After removal

- Update stale comments in remaining workflows that reference deleted files
- Leave changelog/learnings references alone (they're historical context)

## Key Insight

Run history is the source of truth for workflow usage. A workflow can look useful in YAML but be permanently skipped or redundant in practice. The `gh run list --workflow=<name>.yml` command is the fastest diagnostic.
