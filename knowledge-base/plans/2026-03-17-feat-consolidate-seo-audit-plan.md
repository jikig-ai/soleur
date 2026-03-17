---
title: "feat: consolidate SEO audit into weekly growth audit workflow"
type: feat
date: 2026-03-17
semver: patch
---

# Consolidate SEO Audit into Weekly Growth Audit Workflow

## Enhancement Summary

**Deepened on:** 2026-03-17
**Sections enhanced:** 3 (Technical Considerations, Acceptance Criteria, MVP)
**Sources applied:** 3 learnings (linearize-multi-step-llm-prompts, scheduled-skill-wrapping-pattern, github-actions-workflow-dispatch-permissions), workflow source analysis

### Key Improvements

1. **Step renumbering** -- replaced fragile "Step 2.5" fractional numbering with clean sequential numbers (1-6), per the linearize-multi-step-llm-prompts learning
2. **Turn budget** -- identified that `--max-turns 45` is insufficient for 4 agent invocations; added requirement to increase to 55
3. **Date expansion pattern** -- corrected `<date>` placeholder to `$(date +%Y-%m-%d)` to match existing workflow pattern (shell-expanded before LLM receives prompt)
4. **Failure continuation instruction** -- added explicit prompt-level guard for agent failure, acknowledging it is best-effort (not programmatic)
5. **Edge cases documented** -- Eleventy prerequisite bypass, concurrent workflow overlap, report deduplication on same-day re-runs

## Overview

The weekly growth audit workflow (`scheduled-growth-audit.yml`) produces three date-stamped reports (content-audit, aeo-audit, content-plan) but does not include a technical SEO audit. A separate `scheduled-seo-aeo-audit.yml` workflow exists but only applies fixes -- it does not persist an audit report. The `seo-aeo` skill's `audit` sub-command outputs inline without saving to disk. This plan adds a technical SEO audit step to the existing growth audit workflow and persists the report with the same naming convention.

## Problem Statement

The CMO's weekly growth audit gives a comprehensive content and AEO picture but has a blind spot: technical SEO health (structured data, meta tags, sitemap, robots.txt, Core Web Vitals indicators) is not captured in the audit reports. The `scheduled-seo-aeo-audit.yml` workflow runs `seo-aeo fix` (auto-applies fixes) but never produces a human-readable report in the knowledge base. The result is that the Monday audit issue summary has no technical SEO section, and there's no historical record of technical SEO health over time.

## Non-goals

- Do not create a new workflow. Consolidate into `scheduled-growth-audit.yml`.
- Do not remove or modify `scheduled-seo-aeo-audit.yml`. That workflow applies fixes; this one captures the audit report. They serve different purposes (report vs. remediation).
- Do not modify the `seo-aeo` skill's SKILL.md to add file persistence to the `audit` sub-command. The workflow prompt can instruct the agent to save output to a specific path without changing skill infrastructure.
- Do not change the agents (`seo-aeo-analyst`, `growth-strategist`). The existing agent capabilities are sufficient.

## Proposed Solution

Add a new step (Step 2.5) to the `scheduled-growth-audit.yml` workflow prompt that launches the `seo-aeo-analyst` agent via the Task tool, instructs it to produce a technical SEO audit report, and saves it to `knowledge-base/marketing/audits/soleur-ai/<date>-seo-audit.md`. Update the GitHub Issue summary (Step 4) to include SEO audit findings.

### Why this approach

- **Follows existing pattern.** Steps 1-3 already launch agents via Task tool and save reports. Step 2.5 uses the same pattern.
- **No skill changes.** The workflow prompt directly instructs the agent. The seo-aeo skill is not invoked -- the seo-aeo-analyst agent is used directly, same as growth-strategist is used directly (not via the growth skill).
- **Single commit.** All four reports are committed together in Step 5.
- **Minimal diff.** One new prompt block + minor update to the issue summary prompt.

## Technical Considerations

### Workflow execution order

The growth audit workflow runs steps sequentially within a single `claude-code-action` invocation. Adding the SEO audit between the AEO audit and the content plan keeps the content plan last, since it benefits from seeing all prior audits. The seo-aeo-analyst agent uses WebFetch to retrieve live pages (same as growth-strategist), so it needs `WebFetch` in `--allowedTools`. The current workflow already includes `WebSearch,WebFetch` -- no change needed.

### Research Insights

**Step renumbering (from linearize-multi-step-llm-prompts learning):** Using "Step 2.5" as a fractional step number is fragile -- LLM agents parsing sequential prompts may not reliably preserve fractional ordering. Renumber: the new SEO audit becomes Step 3, existing content plan becomes Step 4, existing GitHub Issue becomes Step 5, and existing persist step becomes Step 6. This follows the linearization principle: every instruction at the position where it executes, with clean sequential numbering.

**Date expansion:** The existing workflow prompt uses `$(date +%Y-%m-%d)` for date placeholders in file paths. This is shell-expanded by GitHub Actions before `claude-code-action` receives the prompt, so the agent sees a literal date like `2026-03-17`. The new step must use the same `$(date +%Y-%m-%d)` pattern, NOT `<date>` or `today's date`.

**Turn budget:** The workflow currently uses `--max-turns 45`. Each Task tool invocation of a subagent consumes turns from the parent's budget. The existing 3 agents (content audit, AEO audit, content plan) each use approximately 8-12 turns. Adding a 4th agent without increasing `--max-turns` risks hitting the limit before Step 6 (persist). Increase `--max-turns` from 45 to 55 alongside the `timeout-minutes` increase.

**Failure isolation:** The prompt runs as a single sequential LLM turn within `claude-code-action`. There is no mechanism for step-level error isolation -- if the seo-aeo-analyst agent fails (WebFetch timeout, API error), the LLM may halt or skip subsequent steps. Mitigation: add explicit instruction after the Task invocation: "If the SEO audit agent fails or returns an error, note the failure and continue to Step 4." This is a prompt-level guard, not a programmatic one -- the test scenario for graceful degradation is best-effort.

### Agent capabilities

The `seo-aeo-analyst` agent (`plugins/soleur/agents/marketing/seo-aeo-analyst.md`) already defines a Step 3: Report output format with structured markdown (Critical Issues, Warnings, Passed Checks, Recommendations). The workflow prompt instructs it to save this report to the target path.

### Timeout

Current timeout is 45 minutes for 3 agent steps. Adding a 4th agent step may push execution time. The seo-aeo-analyst is lighter than the growth-strategist (it checks technical signals, not content quality). Increase timeout to 55 minutes as a safety margin.

### Interaction with `scheduled-seo-aeo-audit.yml`

The SEO fix workflow runs at 10:00 UTC (one hour after the growth audit at 09:00 UTC). This means the growth audit captures the SEO state BEFORE fixes are applied, and the fix workflow applies corrections afterward. This is the correct order -- the audit report documents what needs fixing, and the fix workflow remediates. No sequencing change needed.

### Existing report naming convention

Current reports follow `YYYY-MM-DD-<type>-audit.md` pattern:
- `2026-03-16-aeo-audit.md`
- `2026-03-16-content-audit.md`
- `2026-03-16-content-plan.md`

The new report will be: `2026-03-16-seo-audit.md`

## Acceptance Criteria

- [ ] `scheduled-growth-audit.yml` prompt includes a new Step 3 (Technical SEO Audit) that launches `seo-aeo-analyst` via Task tool
- [ ] Existing steps renumbered sequentially: Content Audit (1), AEO Audit (2), SEO Audit (3), Content Plan (4), GitHub Issue (5), Persist (6)
- [ ] Step 3 instructs the agent to save the report to `knowledge-base/marketing/audits/soleur-ai/$(date +%Y-%m-%d)-seo-audit.md`
- [ ] Step 3 includes a failure continuation instruction ("If the SEO audit agent fails, note the failure and continue to Step 4")
- [ ] Step 5 (GitHub Issue) references top SEO audit findings alongside the existing content and AEO summaries
- [ ] `timeout-minutes` increased from 45 to 55
- [ ] `--max-turns` increased from 45 to 55
- [ ] No new workflow files are created
- [ ] No changes to `plugins/soleur/skills/seo-aeo/SKILL.md` or agent markdown files
- [ ] The `git add` in Step 6 already uses `knowledge-base/marketing/audits/soleur-ai/` (directory glob) so it picks up the new file without changes

## Test Scenarios

- Given the growth audit workflow is triggered via `workflow_dispatch`, when the seo-aeo-analyst agent completes, then a file matching `YYYY-MM-DD-seo-audit.md` exists in `knowledge-base/marketing/audits/soleur-ai/`
- Given the growth audit workflow completes all 4 audit steps, when the GitHub Issue is created, then the issue body includes a section summarizing SEO audit findings
- Given the seo-aeo-analyst agent fails (timeout, WebFetch error), when the workflow continues, then the remaining steps (content plan, issue, commit) still execute and the issue notes the SEO audit failure (best-effort -- depends on LLM following the failure continuation instruction)
- Given no SEO issues are found, when the report is generated, then the report still persists with an empty Critical Issues section and populated Passed Checks section
- Given the workflow runs on a Monday via cron schedule, when all steps complete, then exactly 4 files are committed (content-audit, aeo-audit, seo-audit, content-plan) with the same date prefix

## MVP

### `.github/workflows/scheduled-growth-audit.yml` (changes)

**Change 1: Renumber existing steps.** Current Step 3 (Content Plan) becomes Step 4, current Step 4 (GitHub Issue) becomes Step 5, current Step 5 (Persist) becomes Step 6.

**Change 2: Insert new Step 3** between the existing AEO Audit (Step 2) and the renamed Content Plan (Step 4):

```yaml
            ## Step 3: Technical SEO Audit

            Launch the seo-aeo-analyst agent via the Task tool:

            Task seo-aeo-analyst: "Audit the documentation site at https://soleur.ai for
            technical SEO and AEO issues. Use WebFetch to retrieve pages. Check structured
            data (JSON-LD), meta tags, canonical URLs, OG tags, Twitter cards, sitemap,
            robots.txt AI bot access, llms.txt, E-E-A-T signals, heading hierarchy, and
            Core Web Vitals indicators. Produce a structured report with Critical Issues,
            Warnings, Passed Checks, and Recommendations sections. Do NOT make any changes."

            Save the report to:
            knowledge-base/marketing/audits/soleur-ai/$(date +%Y-%m-%d)-seo-audit.md

            If the SEO audit agent fails or returns an error, note the failure and
            continue to Step 4.
```

**Change 3:** The renamed Step 5 (GitHub Issue) prompt gains an additional bullet:

```yaml
            - Top 3 technical SEO findings (or "clean" if no issues)
```

**Change 4:** `timeout-minutes` changes from 45 to 55.

**Change 5:** `--max-turns` in `claude_args` changes from 45 to 55.

### Research Insights (implementation details)

**Edge case -- seo-aeo-analyst and the Eleventy prerequisite:** The seo-aeo-analyst agent's parent skill (seo-aeo) has a Phase 0 prerequisite that checks for `eleventy.config.js`. However, this prerequisite is only enforced by the skill's SKILL.md, not by the agent itself. Since the workflow invokes the agent directly via Task tool (not the skill), the prerequisite check is bypassed. This is intentional -- the agent audits the live site via WebFetch, not the local build. No issue here.

**Edge case -- concurrent workflow runs:** The growth audit (09:00 UTC) and the SEO fix workflow (10:00 UTC) both write to main. If the growth audit runs long (45+ minutes), it could overlap with the SEO fix workflow. Both use `git push origin main || { git pull --rebase origin main && git push origin main; }` which handles this via rebase-on-conflict. The concurrency groups are different (`scheduled-growth-audit` vs `schedule-seo-aeo-audit`) so they can run in parallel. No change needed -- the existing conflict resolution pattern handles this.

**Edge case -- report deduplication:** If the growth audit workflow is manually triggered twice on the same day, the second run overwrites the first run's `seo-audit.md` file (same date-prefixed filename). This matches the existing behavior for content-audit and aeo-audit. No special handling needed.

## References

- Growth audit workflow: `.github/workflows/scheduled-growth-audit.yml`
- SEO fix workflow: `.github/workflows/scheduled-seo-aeo-audit.yml`
- seo-aeo-analyst agent: `plugins/soleur/agents/marketing/seo-aeo-analyst.md`
- seo-aeo skill: `plugins/soleur/skills/seo-aeo/SKILL.md`
- growth-strategist agent: `plugins/soleur/agents/marketing/growth-strategist.md`
- Existing audit reports: `knowledge-base/marketing/audits/soleur-ai/`
- Related brainstorm: `knowledge-base/brainstorms/2026-03-16-cmo-autonomous-execution-brainstorm.md`
- Learning -- skill wrapping pattern: `knowledge-base/learnings/2026-03-16-scheduled-skill-wrapping-pattern.md`
- Learning -- linearize multi-step LLM prompts: `knowledge-base/learnings/2026-03-16-linearize-multi-step-llm-prompts.md`
- Learning -- workflow dispatch permissions: `knowledge-base/learnings/2026-03-16-github-actions-workflow-dispatch-permissions.md`
- Commit that triggered this task: `e56b9e5` (docs: weekly growth audit 2026-03-16)
