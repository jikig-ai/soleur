---
title: "feat: Content generator queue exhaustion fallback via growth plan"
type: feat
date: 2026-03-16
semver: patch
---

# feat: Content generator queue exhaustion fallback via growth plan

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

### Allowed tools

The current workflow has `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Task`. The growth skill invokes the growth-strategist agent via Task tool, which needs WebSearch for keyword research. All required tools are already allowed.

### Queue mutation

The new topic gets appended to `seo-refresh-queue.md` with `generated_date` already set so it won't be picked again on the next run. This maintains idempotency -- the same topic is never generated twice.

### Growth plan topic scope

The growth plan topic should align with the project's brand positioning. The prompt should instruct the agent to use the brand guide (`knowledge-base/marketing/brand-guide.md`) and content strategy (`knowledge-base/marketing/content-strategy.md`) to scope the keyword research to relevant topics (e.g., "Company-as-a-Service", "solo founder AI tools", "agentic engineering").

### Timeout

The current timeout is 45 minutes. Adding growth plan + content-writer could push this close to the limit. The growth plan keyword research (WebSearch) adds ~5-10 minutes. If timeouts become an issue, the timeout can be bumped to 60 minutes in a follow-up.

### Failure modes

- **Growth plan returns no results:** Create the exhaustion issue (current behavior) and stop. The fallback is best-effort.
- **Growth plan returns results but content-writer fails (FAIL citations):** Create an issue documenting the failed topic and citations (existing STEP 2 behavior). The topic is NOT added to the queue.
- **Network failures during WebSearch:** Growth plan degrades gracefully per constitution.md ("Network and external service failures must degrade gracefully"). Falls back to creating the exhaustion issue.

## Non-Goals

- Automated topic curation pipeline (manual queue replenishment remains the primary path)
- Multi-topic generation per run (one topic per fallback invocation)
- Notification to the founder when fallback activates (the audit issue serves as the notification)
- Changes to the growth skill or content-writer skill (this modifies the workflow prompt only)

## Acceptance Criteria

- [ ] When all SEO refresh queue items have `generated_date`, the content generator runs `growth plan` to discover a new topic
- [ ] The discovered topic is passed to `content-writer --headless` for article generation
- [ ] The new topic is appended to `seo-refresh-queue.md` with `generated_date` set
- [ ] The audit GitHub issue notes the topic was auto-discovered (not from manual queue)
- [ ] If growth plan fails or returns no useful results, the workflow falls back to creating the exhaustion issue and stopping (current behavior preserved)
- [ ] No changes to the growth skill SKILL.md or content-writer SKILL.md

## Test Scenarios

- Given all queue items have `generated_date`, when the content generator runs, then it invokes `growth plan` to discover a new topic and generates an article from it
- Given growth plan returns no P1 results (e.g., WebSearch fails), when the content generator runs with exhausted queue, then it creates the existing exhaustion issue and stops
- Given growth plan succeeds but content-writer aborts due to FAIL citations, when the content generator runs, then it creates an issue documenting the failure and does NOT add the topic to the queue
- Given the queue has at least one item without `generated_date`, when the content generator runs, then it uses the existing queue item (fallback is NOT triggered)

## MVP

### `.github/workflows/scheduled-content-generator.yml` (prompt modification)

Replace the current STEP 1 queue-exhausted block:

```yaml
# Current (lines 66-70):
# If ALL items already have a generated_date, create a GitHub issue
# titled "[Scheduled] Content Generator - <today's date>"
# with label "scheduled-content-generator" and body
# "SEO refresh queue exhausted -- all items have been generated.
# Add more topics to the queue." Then stop.

# Proposed:
# If ALL items already have a generated_date:
#   STEP 1b — Discover new topic via growth plan:
#   Read knowledge-base/marketing/brand-guide.md for brand positioning context.
#   Read knowledge-base/marketing/content-strategy.md for content priorities.
#   Run /soleur:growth plan "topics for solo founders using AI to build companies"
#     --site https://soleur.ai --headless
#   Extract the top P1 content suggestion (topic title and target keywords).
#
#   If growth plan produced no usable P1 topic, create the exhaustion issue
#   and stop (existing fallback behavior).
#
#   STEP 1c — Record the discovered topic:
#   Append the topic to knowledge-base/marketing/seo-refresh-queue.md under
#   a "## Auto-Discovered Topics" section with generated_date set to today.
#
#   Continue to STEP 2 using the discovered topic and keywords.
```

## References

- Parent issue: #638 (FR9)
- Current issue: #641
- Workflow: `.github/workflows/scheduled-content-generator.yml`
- Growth skill: `plugins/soleur/skills/growth/SKILL.md`
- Content writer skill: `plugins/soleur/skills/content-writer/SKILL.md`
- SEO refresh queue: `knowledge-base/marketing/seo-refresh-queue.md`
- Learning: `knowledge-base/learnings/2026-03-16-scheduled-skill-wrapping-pattern.md`
