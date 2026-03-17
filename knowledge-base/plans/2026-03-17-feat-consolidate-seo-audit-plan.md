---
title: "feat: consolidate SEO audit into weekly growth audit workflow"
type: feat
date: 2026-03-17
semver: patch
---

# Consolidate SEO Audit into Weekly Growth Audit Workflow

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

The growth audit workflow runs steps sequentially within a single `claude-code-action` invocation. Adding Step 2.5 between the AEO audit (Step 2) and the content plan (Step 3) keeps the content plan last, since it benefits from seeing all prior audits. The seo-aeo-analyst agent uses WebFetch to retrieve live pages (same as growth-strategist), so it needs `WebFetch` in `--allowedTools`. The current workflow already includes `WebSearch,WebFetch` -- no change needed.

### Agent capabilities

The `seo-aeo-analyst` agent (`.worktrees/feat-consolidate-seo-audit/plugins/soleur/agents/marketing/seo-aeo-analyst.md`) already defines a Step 3: Report output format with structured markdown (Critical Issues, Warnings, Passed Checks, Recommendations). The workflow prompt instructs it to save this report to the target path.

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

- [ ] `scheduled-growth-audit.yml` prompt includes a Step 2.5 that launches `seo-aeo-analyst` via Task tool
- [ ] Step 2.5 instructs the agent to save the report to `knowledge-base/marketing/audits/soleur-ai/<date>-seo-audit.md`
- [ ] Step 4 (GitHub Issue) references top SEO audit findings alongside the existing content and AEO summaries
- [ ] Timeout increased from 45 to 55 minutes
- [ ] No new workflow files are created
- [ ] No changes to `plugins/soleur/skills/seo-aeo/SKILL.md` or agent markdown files
- [ ] The `git add` in Step 5 already uses `knowledge-base/marketing/audits/soleur-ai/` (directory glob) so it picks up the new file without changes

## Test Scenarios

- Given the growth audit workflow is triggered, when the seo-aeo-analyst agent completes, then a file matching `YYYY-MM-DD-seo-audit.md` exists in `knowledge-base/marketing/audits/soleur-ai/`
- Given the growth audit workflow completes all 4 audit steps, when the GitHub Issue is created, then the issue body includes a section summarizing SEO audit findings
- Given the seo-aeo-analyst agent fails (timeout, WebFetch error), when the workflow continues, then the remaining steps (content plan, issue, commit) still execute and the issue notes the SEO audit failure
- Given no SEO issues are found, when the report is generated, then the report still persists with an empty Critical Issues section and populated Passed Checks section

## MVP

### `.github/workflows/scheduled-growth-audit.yml` (changes)

The prompt section gains a new Step 2.5 block between the existing Step 2 (AEO Audit) and Step 3 (Content Plan):

```yaml
            ## Step 2.5: Technical SEO Audit

            Launch the seo-aeo-analyst agent via the Task tool:

            Task seo-aeo-analyst: "Audit the documentation site at https://soleur.ai for
            technical SEO and AEO issues. Use WebFetch to retrieve pages. Check structured
            data (JSON-LD), meta tags, canonical URLs, OG tags, Twitter cards, sitemap,
            robots.txt AI bot access, llms.txt, E-E-A-T signals, heading hierarchy, and
            Core Web Vitals indicators. Produce a structured report with Critical Issues,
            Warnings, Passed Checks, and Recommendations sections. Do NOT make any changes."

            Save the report to:
            knowledge-base/marketing/audits/soleur-ai/<date>-seo-audit.md
```

The Step 4 (GitHub Issue) prompt gains an additional bullet:

```yaml
            - Top 3 technical SEO findings (or "clean" if no issues)
```

The `timeout-minutes` changes from 45 to 55.

## References

- Growth audit workflow: `.github/workflows/scheduled-growth-audit.yml`
- SEO fix workflow: `.github/workflows/scheduled-seo-aeo-audit.yml`
- seo-aeo-analyst agent: `plugins/soleur/agents/marketing/seo-aeo-analyst.md`
- seo-aeo skill: `plugins/soleur/skills/seo-aeo/SKILL.md`
- growth-strategist agent: `plugins/soleur/agents/marketing/growth-strategist.md`
- Existing audit reports: `knowledge-base/marketing/audits/soleur-ai/`
- Related brainstorm: `knowledge-base/brainstorms/2026-03-16-cmo-autonomous-execution-brainstorm.md`
- Learning on skill wrapping pattern: `knowledge-base/learnings/2026-03-16-scheduled-skill-wrapping-pattern.md`
- Commit that triggered this task: `e56b9e5` (docs: weekly growth audit 2026-03-16)
