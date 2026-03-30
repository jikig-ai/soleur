---
title: Skill Description Word Budget Awareness
date: 2026-03-30
category: build-errors
tags: [build-errors, pre-commit, word-budget, skill-description]
module: plugin-system
component: skills, SKILL.md
problem_type: build-error
severity: low
---

# Skill Description Word Budget Awareness

## Problem

During the review skill update (GitHub issues instead of local todos), the pre-commit hook rejected the commit because the cumulative skill description word count exceeded the 1800-word budget. The triage skill's SKILL.md description had been updated with verbose phrasing (~40 words) as part of the same changeset, pushing the total to 1806 words -- 6 over the limit.

The error was not caught until `git commit` ran the pre-commit hook, requiring a fix-and-recommit cycle.

## Root Cause

When modifying skill descriptions across multiple SKILL.md files in a single changeset, there is no incremental feedback on the cumulative word count. The budget is a global constraint (1800 words across all skills), but edits happen locally in individual files. It is easy to add a few words to one description without realizing the budget is already near capacity.

## Solution

Trimmed the triage skill's SKILL.md description from ~40 words to ~20 words, bringing the total back under the 1800-word limit. The fix was straightforward -- the verbose phrasing was unnecessary and could be condensed without losing meaning.

## Key Insight

When modifying any SKILL.md description field, mentally estimate the word count impact on the cumulative budget. The 1800-word limit is shared across all skills in the plugin, so even small additions can exceed it if the budget is already tight. Before committing changes that touch SKILL.md files, run the word count check proactively rather than waiting for the pre-commit hook to catch the violation.

A quick pre-check command: `wc -w plugins/soleur/skills/*/SKILL.md | tail -1` shows the total word count across all skill descriptions (though the actual budget checker may count only the description field, not the full file).

## Session Errors

| Error | Impact | Prevention |
|---|---|---|
| Pre-commit hook rejected commit: skill description word budget exceeded (1806/1800) | Blocked commit, required trimming and recommit | Before committing SKILL.md changes, estimate cumulative word count impact. Run the pre-commit word budget check manually or use `wc -w` as a rough proxy. |

## Related

- AGENTS.md "Never bump version files in feature branches" -- another example of a global constraint that is easy to violate when editing locally
