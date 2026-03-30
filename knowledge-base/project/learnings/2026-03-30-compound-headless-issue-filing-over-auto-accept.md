---
title: Compound headless mode should file issues instead of auto-accepting or skipping
date: 2026-03-30
category: workflow
tags: [compound, compound-capture, headless-mode, pipeline, issue-filing]
---

# Learning: Compound headless mode should file issues instead of auto-accepting or skipping

## Problem

During one-shot pipeline execution, compound's Route Learning to Definition
phase (compound-capture Step 8) identified actionable improvements to skill
definitions but skipped them with "minor improvement, skipping in pipeline
mode." The headless mode behavior was set to "auto-accept the LLM-proposed
edit without prompting," but in practice the agent treated the gate as
skip-only because unreviewed edits to skill definitions are risky.

This created a lossy pipeline: the insight was identified, deemed actionable,
and then silently dropped.

## Solution

Changed the headless mode behavior for compound-capture Step 8.4 from
"auto-accept edits" to "file a GitHub issue with the proposal." In headless
mode, Step 8 now:

1. Auto-selects the highest-confidence component when multiple are detected
   (Step 8.2)
2. Writes the proposed edit to a temp file via `--body-file`
3. Creates a GitHub issue with `gh issue create` containing the before/after
   diff and rationale
4. Records the issue number in the learning's `synced_to` frontmatter field

Interactive mode is unchanged -- Accept/Skip/Edit via AskUserQuestion.

## Key Insight

When an LLM pipeline runs in headless mode, user-confirmation gates have
three behavioral options:

1. **Auto-accept** -- risky, applies unreviewed changes to production
   artifacts
2. **Skip** -- lossy, drops actionable insights that the pipeline identified
3. **Defer to tracking system** -- safe, creates a GitHub issue for later
   human review

Option 3 preserves both safety and completeness. The pipeline loses no
information, and a human reviews the proposal at their own pace. This
pattern applies to any headless gate where the action is consequential but
not urgent.

## Session Errors

1. **Pre-commit hook failure on pre-existing MD046 lint error** --
   compound-capture/SKILL.md had a pre-existing indented code block (line
   464) that failed the markdown-lint pre-commit hook, blocking the first
   commit attempt. Recovery: converted the indented code block to a fenced
   code block. **Prevention:** run `npx markdownlint-cli2` on the target
   file before attempting to commit when editing files that may have
   pre-existing lint issues.

2. **Plan line numbers mismatched actual file** -- the plan referenced
   "after line 295" but the target content was at line 289. Recovery: used
   semantic matching (section headers and content patterns) instead of line
   numbers. **Prevention:** plans should reference section names and content
   patterns, not exact line numbers, since prior edits shift line positions.

## Cross-References

- Headless mode convention: `knowledge-base/project/learnings/2026-03-03-headless-mode-skill-bypass-convention.md`
- compound-capture skill: `plugins/soleur/skills/compound-capture/SKILL.md` (Steps 8.2, 8.4)
- compound skill: `plugins/soleur/skills/compound/SKILL.md` (line 263, headless behavior)

## Tags

category: workflow
module: compound-pipeline
