---
title: "one-shot pipeline dead step after review migration to GitHub issues"
category: integration-issues
module: one-shot-pipeline
date: 2026-04-02
tags: [pipeline, review, github-issues, skill-migration]
---

# Learning: one-shot pipeline dead step after review migration to GitHub issues

## Problem

PR #1329 migrated the `/review` skill from creating local `todos/*.md` files to creating GitHub issues with the `code-review` label. However, the one-shot pipeline (Step 5) still invoked `resolve-todo-parallel`, which only reads from `todos/*.md`. This made Step 5 a dead step -- it would find zero todos and exit immediately, silently skipping all code-review issue resolution.

## Solution

Replaced Step 5 in `plugins/soleur/skills/one-shot/SKILL.md` with inline GitHub-issue resolution logic that:

1. Fetches P1 code-review issues scoped to the current PR via `gh issue list --label code-review --search "PR #<number>"`
2. Spawns parallel `pr-comment-resolver` agents for each issue
3. Closes resolved issues after fixes are applied

Also added a legacy scope note to `plugins/soleur/skills/resolve-todo-parallel/SKILL.md` clarifying it only operates on local `todos/*.md` files.

## Key Insight

When a skill migration changes the output format (local files to GitHub issues), all downstream consumers in pipelines must be updated in the same PR or tracked as a follow-up issue. The review skill's issue template format also matters for downstream filtering -- `gh issue list --search` with full-text search is more robust than substring matching on markdown-formatted body text, since body content includes markdown syntax (`**Source:**`) that breaks plain-text pattern matching.

## Session Errors

### 1. Wrong path for setup-ralph-loop.sh

**What happened:** The agent tried to locate `setup-ralph-loop.sh` at `./plugins/soleur/skills/one-shot/scripts/` (inside the skill directory) but it actually lives at `./plugins/soleur/scripts/` (the plugin root scripts directory).

**Recovery:** Corrected the path to the plugin root scripts directory.

**Prevention:** Plugin-wide scripts live at `plugins/soleur/scripts/`, not inside individual skill directories under `plugins/soleur/skills/<name>/scripts/`. Skill-level `scripts/` directories are for skill-specific helpers only.

### 2. Plan prescribed incorrect filter format

**What happened:** The plan specified filtering GitHub issues by matching `Source: PR #<number>` in the issue body. However, the review template renders this as bold markdown: `**Source:** PR #<number>`. Plain-text substring matching against the body would fail because of the `**` markdown syntax. This was caught by review agents before merge.

**Recovery:** Switched to `gh issue list --search "PR #<number>"` which performs GitHub full-text search across issue titles and bodies, ignoring markdown formatting.

**Prevention:** When referencing template output in downstream filtering logic, read the actual template file to verify the exact output format (including markdown formatting characters) rather than paraphrasing from memory or plan descriptions. Full-text search (`--search`) is more resilient than exact substring matching when the source content contains markdown.

## Tags

category: integration-issues
module: one-shot-pipeline
