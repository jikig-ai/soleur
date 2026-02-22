---
title: Model ID Update Patterns
category: configuration-fixes
tags: [model-ids, claude-api, find-and-replace, reference-files, verification]
module: skills
symptom: "Outdated Claude 3.x model IDs in reference files causing deprecation warnings"
root_cause: "Model IDs hardcoded across multiple reference files without centralized constant"
date: 2026-02-22
---

# Learning: Model ID Update Patterns

## Problem

Reference files across `plugins/soleur/skills/` contained outdated Claude 3/3.5 model IDs. Issue #219 listed 7 files, but the actual count was 9 -- two files were missed in the initial inventory.

## Key Insights

### 1. Issue inventories undercount -- always grep independently

The issue listed 7 affected files. A full `grep -rn "claude-3" plugins/soleur/skills/` found 8 files (module-template.rb was missing). Post-edit verification found a 9th (skill-creator/references/official-spec.md had a stale Claude 4.0 ID). Never trust an issue's file list as exhaustive -- always run your own search.

### 2. "Already updated" doesn't mean "up to date"

Lines 238-239 of `agent-execution-patterns.md` used `claude-sonnet-4-20250514` and `claude-opus-4-20250514`, which appeared to be current Claude 4.x IDs. They were actually stale Claude 4.0 model IDs -- the latest are `claude-sonnet-4-6` and `claude-opus-4-6`. Always verify model IDs against the official docs at https://platform.claude.com/docs/en/about-claude/models/overview.

### 3. replace_all is prefix-sensitive

Using `replace_all` for `anthropic/claude-3-5-sonnet-20241022` caught all instances with the `anthropic/` prefix but missed line 309 in config-template.rb which used `model: 'claude-3-5-sonnet-20241022'` (no provider prefix). Always run a post-edit grep to catch variant formats.

### 4. Current Claude model IDs (Feb 2026)

| Tier | API Alias | Dated ID | Pricing |
|------|-----------|----------|---------|
| Opus 4.6 | `claude-opus-4-6` | `claude-opus-4-6` | $5/1M input, $25/1M output |
| Sonnet 4.6 | `claude-sonnet-4-6` | `claude-sonnet-4-6` | $3/1M input, $15/1M output |
| Haiku 4.5 | `claude-haiku-4-5` | `claude-haiku-4-5-20251001` | $1/1M input, $5/1M output |

## Solution

1. Run `grep -rn "claude-3" plugins/soleur/skills/` to find ALL occurrences
2. Verify target IDs against official Anthropic model docs
3. Edit each file, using `replace_all` where same string appears multiple times
4. Run post-edit grep for BOTH old patterns AND variant formats
5. Fix any stragglers caught by verification

## Prevention

- When updating hardcoded values across a codebase, never trust a pre-compiled list -- always search independently
- Post-edit verification grep is mandatory, not optional
- Check for variant formats of the same string (with/without prefix, in comments vs code)

## Session Errors

1. `git pull` failed due to missing pull strategy -- use `git fetch + reset` instead
2. Initial plan used stale 4.0 IDs as targets -- caught by verifying against official docs during deepen-plan
3. `replace_all` missed one occurrence due to different prefix format -- caught by post-edit grep
