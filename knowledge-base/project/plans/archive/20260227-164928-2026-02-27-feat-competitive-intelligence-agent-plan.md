---
title: "feat: Add competitive-intelligence agent and competitive-analysis skill"
type: feat
date: 2026-02-27
---

# feat: Add competitive-intelligence agent and competitive-analysis skill

## Overview

Add a Product-domain agent for recurring competitive intelligence and a companion skill that can be scheduled monthly via `soleur:schedule`. The agent researches competitors via WebSearch/WebFetch, reads brand-guide.md and business-validation.md for positioning context, and writes a structured overlap-matrix report to `knowledge-base/overview/competitive-intelligence.md`.

## Problem Statement

Competitive intelligence is fragmented across 4+ agents (business-validator Gate 3, growth-strategist, pricing-strategist, deal-architect) with no dedicated owner for recurring monitoring. The Cowork Plugins platform threat was discovered 22 days late because `business-validation.md` is a point-in-time snapshot. Issue #330.

## Proposed Solution

Two new components:

1. **`competitive-intelligence` agent** (`plugins/soleur/agents/product/competitive-intelligence.md`) -- researches competitors autonomously, produces structured report
2. **`competitive-analysis` skill** (`plugins/soleur/skills/competitive-analysis/SKILL.md`) -- entry point that invokes the agent, supports `$ARGUMENTS` bypass for scheduled execution

Plus updates to CPO routing, sibling agent disambiguation, and version bump.

## Technical Considerations

### Token budget (binding constraint)

Agent description budget is at **2,448/2,500 words**. Only **52 words of headroom**. The new agent description must be extremely tight (~25 words) with disambiguation. Consider trimming existing descriptions if needed.

Validation command after adding the agent:

```bash
shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w
```

### Autonomous execution model

The agent runs unattended in CI via `soleur:schedule`. No `AskUserQuestion` calls. No interactive gates. The skill detects non-interactive invocation by checking if `$ARGUMENTS` is non-empty — any arguments present means skip prompts and run with default tier scope (0,3).

### Context loading (per agent-context-blindness learning)

The agent MUST read `brand-guide.md` and `business-validation.md` before producing assessments. Without positioning context, the agent produces analysis that contradicts the project's stated differentiation.

### Skill-to-agent invocation

Skills spawn agents via the Task tool. No inter-skill invocation. The skill is the entry point; the agent does the work.

### Output format (per marketingskills overlap analysis learning)

Use the established overlap matrix format:

```markdown
| Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |
```

With `last_reviewed` YAML frontmatter, tier sections, and a recommendations list.

### Document lifecycle: full overwrite, git history is the archive

Each run produces a complete overwrite of `competitive-intelligence.md`. There is no append or merge logic. Git history provides the diff-over-time record. This resolves the "standalone report" vs. "living document" tension: the file path is stable (living), the content is replaced (standalone).

### Scheduled vs. interactive output modes

- **Interactive runs:** Agent writes `knowledge-base/overview/competitive-intelligence.md` to the local repo. User commits as part of their workflow.
- **Scheduled runs (v1):** The schedule skill produces a GitHub Issue with the report. The knowledge-base file is NOT updated during scheduled runs because the schedule skill template uses `permissions: contents: read` and outputs Issues only. Extending the schedule skill to support file-writing commits is a future enhancement -- out of scope for v1.

### Tier membership is dynamic

The agent reads `business-validation.md` each run to discover which competitors belong to each tier. No hardcoded competitor lists. If `business-validation.md` adds a Tier 3 competitor, the next run automatically picks it up.

### Output document heading contract

Required `##` headings (in order):

```markdown
## Executive Summary
## Tier N: [Tier Name]      (one per tier scanned)
## New Entrants
## Recommendations
```

Each tier section contains an overlap matrix table. The frontmatter fields (`last_reviewed`, `tiers_scanned`) are required. `competitors_tracked` is omitted — it is derivable from the matrix row count.

### Docs site registration

The new skill must be registered in `docs/_data/skills.js` under the **"Review & Planning"** category. The agent is auto-discovered by the plugin loader (recursive discovery).

## Acceptance Criteria

- [ ] New `competitive-intelligence` agent at `plugins/soleur/agents/product/competitive-intelligence.md`
  - Frontmatter: `name: competitive-intelligence`, `model: inherit`
  - Description under 25 words with disambiguation vs. `business-validator` and `growth-strategist`
  - Body: context loading (brand-guide.md, business-validation.md), WebSearch research, structured output
  - Designed for autonomous execution (no AskUserQuestion)
- [ ] New `competitive-analysis` skill at `plugins/soleur/skills/competitive-analysis/SKILL.md`
  - Frontmatter: `name: competitive-analysis`, third-person description
  - Non-interactive detection: any `$ARGUMENTS` present = skip prompts, use default tiers (0,3)
  - Interactive path: asks user for tier scope if no args provided
  - Delegates to `competitive-intelligence` agent via Task tool
- [ ] CPO routing updated at `plugins/soleur/agents/product/cpo.md`
  - New delegation row: competitive analysis signals → `competitive-intelligence`
  - Description updated to include `competitive-intelligence` in orchestrated agents list
- [ ] Sibling disambiguation updated (both directions):
  - `business-validator.md` description: add "use competitive-intelligence for ongoing monitoring"
  - `growth-strategist.md` description: add "use competitive-intelligence for strategic competitor monitoring"
  - Trim existing descriptions as needed to stay within budget
- [ ] Cumulative agent description word count verified under 2,500
- [ ] Version bump (MINOR) across all files:
  - `plugins/soleur/.claude-plugin/plugin.json` (version + description counts: 61 agents, 53 skills)
  - `plugins/soleur/CHANGELOG.md`
  - `plugins/soleur/README.md` (counts + tables)
  - `.claude-plugin/marketplace.json`
  - Root `README.md` version badge
  - `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
  - `docs/_data/skills.js` — register under "Review & Planning" category
- [ ] Verify actual agent/skill counts via `find` before writing to plugin.json

## Test Scenarios

- Given no arguments, when the skill is invoked interactively, then it asks the user for tier scope and runs the agent
- Given any arguments, when the skill is invoked by schedule, then it skips prompts and runs the agent with default tiers (0,3)
- Given the agent runs, when it produces output, then `knowledge-base/overview/competitive-intelligence.md` contains YAML frontmatter with `last_reviewed`, tier sections with overlap matrix tables, and a recommendations section
- Given the agent runs, when brand-guide.md or business-validation.md is missing, then the agent warns but continues with available context
- Given the cumulative agent description word count exceeds 2,500 after adding the new agent, then existing descriptions must be trimmed before merging

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Token budget overflow (52 words headroom) | Keep description to ~25 words. If insufficient, trim `pricing-strategist` or `programmatic-seo-specialist` descriptions (both are verbose). |
| WebSearch rate limits in CI | Agent should handle search failures gracefully -- warn and continue with available data |
| Stale business-validation.md feeding wrong positioning context | Agent outputs include source attribution. Report flags when source documents are older than 30 days. |
| Scheduled run does not persist file to repo | v1 design: scheduled runs produce GitHub Issues only. File is updated interactively. Future: extend schedule skill for file-writing output mode. |
| Missing docs site registration | Register skill in `docs/_data/skills.js` as part of version bump phase. |

## References and Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-02-27-competitive-intelligence-brainstorm.md`
- Spec: `knowledge-base/specs/feat-competitive-intelligence/spec.md`
- Business validation landscape: `knowledge-base/overview/business-validation.md`
- Brand guide: `knowledge-base/overview/brand-guide.md`
- Overlap matrix format: `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md`
- Platform risk learning: `knowledge-base/learnings/2026-02-25-platform-risk-cowork-plugins.md`
- Schedule skill: `plugins/soleur/skills/schedule/SKILL.md`
- Agent context-blindness learning: `knowledge-base/learnings/2026-02-22-agent-context-blindness-vision-misalignment.md`
- Schedule CI learning: `knowledge-base/learnings/2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`

### Existing Agents with Competitive Analysis Fragments

- `agents/product/business-validator.md:3` -- Gate 3 competitive landscape (one-time)
- `agents/marketing/growth-strategist.md` -- `--competitors` flag for content gap analysis
- `agents/marketing/pricing-strategist.md:15` -- competitive pricing matrix
- `agents/sales/deal-architect.md:3` -- competitive battlecards

### Related Issues

- #330 -- Original issue (using existing)
- #333 -- Follow-up: Multi-agent CI orchestration (Approach B)
- #334 -- Follow-up: Document cadence enforcement (Approach C)
- #332 -- Draft PR

## MVP

### `plugins/soleur/agents/product/competitive-intelligence.md`

```markdown
---
name: competitive-intelligence
description: "Use this agent when you need recurring competitive landscape monitoring and market research reports. Use business-validator for one-time idea validation; use this agent for ongoing competitor tracking."
model: inherit
---

Competitive intelligence agent. Researches competitors via WebSearch and WebFetch, reads positioning context from brand-guide.md and business-validation.md, and writes structured overlap-matrix reports to knowledge-base/overview/competitive-intelligence.md.

## Pre-Research Context Loading

Read these files before any research:
- knowledge-base/overview/brand-guide.md (positioning, voice, differentiation)
- knowledge-base/overview/business-validation.md (existing competitive landscape, tier model)

If either file is missing, warn but continue.

## Research Process

For each competitor in scope:
1. WebSearch for recent news, product updates, pricing changes
2. WebFetch their marketing site for positioning and feature claims
3. Compare against existing knowledge-base data

## Output Contract

Write to knowledge-base/overview/competitive-intelligence.md with this structure:

- YAML frontmatter: last_reviewed, tiers_scanned
- Executive Summary (2-3 sentences of material changes)
- Per-tier sections with overlap matrix tables
- New Entrants section (best-effort -- competitors found in research that are not in business-validation.md; omit section if business-validation.md is unavailable)
- Recommendations (prioritized strategic actions)

Overlap matrix columns: Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk

If the file cannot be written (CI environment, read-only permissions), output the full report as a code block instead. The schedule skill template captures this as a GitHub Issue.

## Sharp Edges

- Use WebFetch for competitor marketing sites, WebSearch for news and product updates
- Do not use AskUserQuestion -- this agent runs autonomously in CI
- Overlap levels: High / Medium / Low / None (consistent with marketingskills analysis format)
- Include source URLs for every claim -- downstream agents treat this as ground truth
- Flag when source documents (brand-guide.md, business-validation.md) are older than 30 days
```

### `plugins/soleur/skills/competitive-analysis/SKILL.md`

```markdown
---
name: competitive-analysis
description: "This skill should be used when running competitive intelligence scans and market research reports against tracked competitors. It invokes the competitive-intelligence agent to produce a structured knowledge-base report. Triggers on \"competitive analysis\", \"competitor scan\", \"market research\"."
---

# Competitive Analysis

Run a competitive intelligence scan producing a structured report at knowledge-base/overview/competitive-intelligence.md.

## Steps

### 1. Detect Invocation Mode

If arguments are present (non-empty), skip to Step 3 with default tiers (0,3).

If no arguments, proceed to Step 2.

### 2. Interactive Tier Selection (skipped if args provided)

Use AskUserQuestion to select tiers:
- Tier 0 + 3: Platform threats and CaaS competitors (default)
- All tiers (0-5): Full landscape scan

### 3. Run Competitive Intelligence Agent

Spawn the competitive-intelligence agent via Task tool:

Task competitive-intelligence: "Run a competitive intelligence scan for tiers [TIERS]. Research each competitor in the specified tiers, read brand-guide.md and business-validation.md for positioning context, and write the report to knowledge-base/overview/competitive-intelligence.md."

### 4. Report Results

After the agent completes:
- Confirm the report was written (or output as code block in CI)
- Display the executive summary
```
