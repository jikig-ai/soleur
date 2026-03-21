---
title: "feat: Content generator queue exhaustion fallback via growth plan"
type: feat
date: 2026-03-16
semver: patch
deepened: 2026-03-16
---

# feat: Content generator queue exhaustion fallback via growth plan

## Enhancement Summary

**Deepened on:** 2026-03-16
**Sections enhanced:** 4 (Technical Considerations, MVP, Acceptance Criteria, Test Scenarios)
**Review perspectives applied:** SpecFlow analysis, code simplicity, architecture/defense-in-depth

### Key Improvements

1. Identified that growth skill `plan` sub-command has no `--headless` flag -- prompt must handle this via inline instructions rather than a flag
2. Flagged turn budget risk (`--max-turns 40`) on the fallback path which chains two skill invocations
3. Simplified MVP by removing redundant brand-guide/content-strategy pre-reads (growth-strategist already reads brand guide internally)
4. Added queue format specification for the auto-discovered topics section

### New Considerations Discovered

- Growth plan `--site` flag triggers external site fetch via WebFetch, adding latency for marginal value in topic discovery -- recommend omitting
- The fallback path adds ~15-20 turns (growth plan Task + content-writer Task + fact-checker sub-Task), pushing close to the 40-turn limit

## Overview

When `scheduled-content-generator.yml` exhausts the SEO refresh queue (all items have `generated_date`), it currently creates a GitHub issue and stops. This plan adds a fallback path that discovers a new keyword opportunity via `/soleur:growth plan`, generates an article from the top result, adds the new topic to the SEO refresh queue, and continues with the normal content pipeline (social-distribute, build validation, commit).

Deferred from #638 (FR9). The SEO refresh queue has 19+ items (10+ weeks at 2/week cadence), so this fallback is not needed until late May 2026 at the earliest.

## Problem Statement

The content generator workflow is fire-and-forget. Once the SEO refresh queue is consumed, the entire twice-weekly content pipeline goes idle. A solo operator may not notice for weeks. The fallback ensures continuous content production without manual topic curation.

## Proposed Solution

Modify STEP 1 of `scheduled-content-generator.yml` to add a conditional branch between "queue exhausted" and "stop":

1. Detect queue exhaustion (current logic -- all items have `generated_date`)
2. Instead of creating an issue and stopping, run `/soleur:growth plan <brand positioning topic>` to discover new keyword opportunities via WebSearch
3. Parse the growth plan output for the highest-priority P1 content suggestion (topic + target keywords)
4. Pass the discovered topic + keywords to `/soleur:content-writer --headless --keywords <keywords>` (existing STEP 2)
5. After article generation, append the new topic to `knowledge-base/marketing/seo-refresh-queue.md` under a new `## Priority 2: Auto-Discovered Topics` section with `generated_date` set
6. Continue with existing STEP 3-6 (social-distribute, build validation, queue annotation, audit issue)

The audit issue (STEP 6) notes that the topic was auto-discovered via growth plan, not sourced from the manual queue.

## Technical Considerations

### Growth plan output parsing

The growth-strategist agent returns a prioritized content plan with P1/P2/P3 items. The workflow prompt must instruct the agent to extract the top P1 item's topic and keywords. Since this runs inside a claude-code-action LLM prompt, the "parsing" is natural language extraction -- no structured JSON parsing needed.

### Growth plan has no `--headless` flag

The growth skill's `plan` sub-command does not support `--headless`. Its final step is "Present the agent's report to the user" (SKILL.md step 4). In the CI context, there is no interactive user, but this is not a blocker -- the LLM prompt instructs the agent what to do with the output (extract the top P1 topic), which implicitly replaces the "present to user" step. Do NOT add `--headless` to the growth plan invocation; instead, instruct the agent inline to extract the result and proceed.

### Allowed tools

The current workflow has `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Task`. The growth skill invokes the growth-strategist agent via Task tool, which needs WebSearch for keyword research. All required tools are already allowed.

### Queue mutation and format

The new topic gets appended to `seo-refresh-queue.md` with `generated_date` already set so it won't be picked again on the next run. This maintains idempotency -- the same topic is never generated twice.

The auto-discovered topic should be appended as a simple list item under a new `## Auto-Discovered Topics` section at the end of the file (before the `_Updated:` footer), using this format:

```markdown
## Auto-Discovered Topics

| Topic | Target Keywords | Source | Generated Date |
|-------|----------------|--------|---------------|
| <topic title> | <kw1>, <kw2>, <kw3> | growth plan (auto-discovered) | 2026-MM-DD |
```

### Growth plan topic scope

The growth plan topic should align with the project's brand positioning. The growth-strategist agent already reads the brand guide internally (SKILL.md "Brand Guide Integration" section), so the prompt does NOT need to pre-read brand-guide.md or content-strategy.md -- that would be redundant. Instead, pass a focused topic string that scopes the keyword research: `"Company-as-a-Service content for solo founders building with AI"`.

### Turn budget

The current workflow uses `--max-turns 40`. The fallback path chains two skill invocations (growth plan via Task + content-writer via Task with fact-checker sub-Task), adding ~15-20 turns. Bump `--max-turns` to 50 on this change to provide headroom. The normal queue path (no fallback) uses fewer turns and is unaffected by the increase.

### Timeout

The current timeout is 45 minutes. Adding growth plan + content-writer could push this close to the limit. The growth plan keyword research (WebSearch) adds ~5-10 minutes. Bump `timeout-minutes` to 60 alongside the max-turns increase.

### Failure modes

- **Growth plan returns no results:** Create the exhaustion issue (current behavior) and stop. The fallback is best-effort.
- **Growth plan returns results but content-writer fails (FAIL citations):** Create an issue documenting the failed topic and citations (existing STEP 2 behavior). The topic is NOT added to the queue.
- **Network failures during WebSearch:** Growth plan degrades gracefully per constitution.md ("Network and external service failures must degrade gracefully"). Falls back to creating the exhaustion issue.
- **Turn limit exceeded:** If the agent runs out of turns mid-fallback, the workflow step fails and Discord notification fires (existing failure handler). No partial state is committed since the `git add -A && git commit` block only runs at the end.

### Defense-in-depth

The fallback path flows through the same content-writer pipeline as the normal queue path, inheriting all its safety gates (fact-checker citation verification, headless FAIL-claim auto-fix, build validation). No additional guards are needed per the `env-var-post-guard` learning -- the irreversible action (publishing) is downstream in the content-publisher workflow, which has its own channel-specific post guards.

## Non-Goals

- Automated topic curation pipeline (manual queue replenishment remains the primary path)
- Multi-topic generation per run (one topic per fallback invocation)
- Notification to the founder when fallback activates (the audit issue serves as the notification)
- Changes to the growth skill or content-writer skill (this modifies the workflow prompt only)

## Acceptance Criteria

- [x] When all SEO refresh queue items have `generated_date`, the content generator runs `growth plan` to discover a new topic
- [x] The discovered topic is passed to `content-writer --headless` for article generation
- [x] The new topic is appended to `seo-refresh-queue.md` under `## Auto-Discovered Topics` with `generated_date` set, using the table format specified in Technical Considerations
- [x] The audit GitHub issue notes the topic source (auto-discovered vs. SEO refresh queue)
- [x] If growth plan fails or returns no useful results, the workflow falls back to creating the exhaustion issue and stopping (current behavior preserved)
- [x] `timeout-minutes` bumped from 45 to 60
- [x] `--max-turns` bumped from 40 to 50
- [x] No changes to the growth skill SKILL.md or content-writer SKILL.md
- [x] No `--headless` flag passed to growth plan (it doesn't support it)

## Test Scenarios

- Given all queue items have `generated_date`, when the content generator runs, then it invokes `growth plan` to discover a new topic and generates an article from it
- Given growth plan returns no P1 results (e.g., WebSearch fails), when the content generator runs with exhausted queue, then it creates the existing exhaustion issue and stops
- Given growth plan succeeds but content-writer aborts due to FAIL citations, when the content generator runs, then it creates an issue documenting the failure and does NOT add the topic to the queue
- Given the queue has at least one item without `generated_date`, when the content generator runs, then it uses the existing queue item (fallback is NOT triggered)
- Given the fallback path exceeds the turn limit, when the agent runs out of turns, then no partial state is committed and the Discord failure notification fires

## MVP

### `.github/workflows/scheduled-content-generator.yml` changes

**1. Bump limits (lines 28, 54):**

- `timeout-minutes: 45` -> `timeout-minutes: 60`
- `--max-turns 40` -> `--max-turns 50`

**2. Replace STEP 1 queue-exhausted block (lines 66-70 of the prompt):**

Current:

```
If ALL items already have a generated_date, create a GitHub issue
titled "[Scheduled] Content Generator - <today's date in YYYY-MM-DD format>"
with the label "scheduled-content-generator" and body
"SEO refresh queue exhausted -- all items have been generated.
Add more topics to the queue." Then stop.
```

Proposed:

```
If ALL items already have a generated_date:

  STEP 1b — Discover new topic via growth plan:
  Run /soleur:growth plan "Company-as-a-Service content for solo founders building with AI"
  From the growth plan output, extract the single highest-priority P1
  content suggestion: its topic title and target keywords.

  If growth plan produced no usable P1 topic (e.g., WebSearch failed
  or no relevant results), create a GitHub issue titled
  "[Scheduled] Content Generator - <today's date in YYYY-MM-DD format>"
  with the label "scheduled-content-generator" and body
  "SEO refresh queue exhausted and growth plan fallback produced no
  usable topic. Add more topics to the queue manually." Then stop.

  Use the discovered topic and keywords for STEP 2 below.

  NOTE: After STEP 4 validation succeeds (and before STEP 6), also
  append the discovered topic to
  knowledge-base/marketing/seo-refresh-queue.md. Add a
  "## Auto-Discovered Topics" section (if it doesn't exist) with a
  table row: | <topic> | <keywords> | growth plan (auto-discovered) | <today's date> |
```

**3. Update STEP 6 audit issue (line 103-110 of the prompt):**

Add to the audit issue body: `- Topic source: auto-discovered via growth plan` (when fallback was used) or `- Topic source: SEO refresh queue` (when normal path was used).

## References

- Parent issue: #638 (FR9)
- Current issue: #641
- Workflow: `.github/workflows/scheduled-content-generator.yml`
- Growth skill: `plugins/soleur/skills/growth/SKILL.md`
- Content writer skill: `plugins/soleur/skills/content-writer/SKILL.md`
- SEO refresh queue: `knowledge-base/marketing/seo-refresh-queue.md`
- Learning: `knowledge-base/project/learnings/2026-03-16-scheduled-skill-wrapping-pattern.md`
