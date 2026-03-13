---
title: "feat: align onboarding with Company-as-a-Service vision and fix business-validator"
type: feat
date: 2026-02-22
---

# Align Onboarding with Company-as-a-Service Vision

## Overview

Fix the disconnect between Soleur's website ("Build a Billion-Dollar Company. Alone.") and the onboarding surface. Update all user-facing artifacts to showcase all 5 business domains. Fix the business-validator and CPO agents to prevent misaligned assessments. Rewrite business-validation.md with the correct framing.

## Problem Statement

The website promises a Company-as-a-Service platform with every department. The onboarding (README, registry listing, Getting Started) describes a development workflow plugin. Non-engineering capabilities (23 agents across marketing, legal, ops, product) have zero onboarding surface. The business-validator is context-blind and produced a validation document treating multi-domain breadth as scope creep.

## Technical Approach

All changes ship in one commit. No deployment dependencies between sections.

### Agent Fixes (2 files)

#### Fix business-validator agent

**File:** `plugins/soleur/agents/product/business-validator.md`

**Change A -- Add Step 0.5: Read Project Identity** (insert between Step 0 and Gate 1)

Add one paragraph:

```markdown
### Step 0.5: Read Project Identity

Before starting the gates, read `knowledge-base/overview/brand-guide.md` if it exists -- extract the `## Identity` section (mission, positioning, target audience). If no brand guide exists, read `README.md` for positioning statements. If neither provides positioning context, proceed with a note: "No brand guide found. Vision alignment check will be skipped. Consider running the brand-architect workshop first." Keep the project's stated positioning in mind throughout all gates -- especially Gate 6, where a multi-domain platform's "minimum viable scope" may be its breadth, not a single feature.
```

**Change B -- Make Gate 6 vision-aware** (modify existing Gate 6)

Change question 1 from:
```
"What is the ONE core thing your product must do to test the value proposition?"
```
To:
```
"What is the core value proposition your MVP must demonstrate?"
```

Add after the existing Gate 6 questions:

```markdown
**If project identity was loaded in Step 0.5 and defines breadth as the value proposition:** The kill criterion shifts from "scope is too large" to "breadth lacks coherence -- domains do not connect to a unified value proposition." A platform that claims "every department" is not over-scoped if each domain serves the stated mission.
```

**Change C -- Add vision alignment check before Final Write**

Insert before the "### Final Write" section:

```markdown
### Vision Alignment Check

If project identity was loaded in Step 0.5, compare the assessment's conclusions against the stated positioning. If the assessment recommends reducing scope but the positioning defines breadth as the value proposition, flag the contradiction:

> NOTE: This assessment recommends scope reduction, but the brand guide defines multi-domain breadth as the core value proposition. Review whether the reduction aligns with stated product identity.

Present any contradictions to the user before writing. The user decides whether to adjust the assessment or the positioning.
```

#### Fix CPO agent

**File:** `plugins/soleur/agents/product/cpo.md`

In the Assess phase, after the bullet that reads business-validation.md, add:

```markdown
- If both `business-validation.md` and `brand-guide.md` exist, cross-reference the validation's framing against the brand's Identity and Positioning sections. If the validation treats stated product features as "scope creep" or contradicts the brand's positioning, flag: "Validation may be misaligned with current brand positioning (last updated: [date]). Consider revalidation." Recommend revalidation but allow the user to proceed.
```

### Content Alignment (6 files)

#### Fix plugin.json description

**File:** `plugins/soleur/.claude-plugin/plugin.json`

Change description to:
```
"A full AI organization across engineering, marketing, legal, operations, and product. 50 agents, 8 commands, and 46 skills that compound your company knowledge over time."
```

Update keywords:
```json
"keywords": ["soleur", "claude-code", "ai-agents", "company-as-a-service", "solo-founder", "orchestration"]
```

Note: Verify agent/skill/command counts from actual files at implementation time, not from hardcoded numbers.

#### Fix root README

**File:** `README.md`

Replace line 5 ("Currently: an orchestration engine for Claude Code -- agents, workflows, and compounding knowledge.") with:
```
50 agents across engineering, marketing, legal, operations, and product -- compounding your company knowledge with every session.
```

After the Workflow table, add a "Your AI Organization" section:

```markdown
## Your AI Organization

| Department | What It Does | Entry Point |
|-----------|-------------|-------------|
| Engineering | Code review, architecture, security, testing, deployment | `/soleur:plan`, `/soleur:work`, `/soleur:review` |
| Marketing | Brand identity, content strategy, SEO, community, pricing | `/soleur:brainstorm define our brand` |
| Legal | Terms, privacy policy, GDPR, compliance audits | `/legal-generate`, `/legal-audit` |
| Operations | Expense tracking, vendor research, tool provisioning | Ask about ops (routed via agents) |
| Product | Business validation, spec analysis, UX design | `/soleur:brainstorm validate our idea` |
```

Also update the root README version badge when bumping.

#### Fix Getting Started page

**File:** `plugins/soleur/docs/pages/getting-started.md`

**Change A -- Fix stale counts.** Replace hardcoded "**45 agents**" and "**45 skills**" with dynamic template variables: `**{{ stats.agents }} agents**` and `**{{ stats.skills }} skills**`. Preserve bold markdown formatting around the template variables.

**Change B -- Add non-engineering workflows.** After the existing "Common Workflows" section, add a "Beyond Engineering" section:

```html
<div class="commands-list">
  <div class="command-item">
    <code>Defining Your Brand</code>
    <p>/soleur:brainstorm define our brand identity &rarr; interactive workshop producing a brand guide</p>
  </div>
  <div class="command-item">
    <code>Generating Legal Documents</code>
    <p>/legal-generate &rarr; Terms, Privacy Policy, GDPR Policy, and more</p>
  </div>
  <div class="command-item">
    <code>Validating a Business Idea</code>
    <p>/soleur:brainstorm validate our business idea &rarr; 6-gate validation workshop</p>
  </div>
  <div class="command-item">
    <code>Tracking Expenses</code>
    <p>Ask about operational expenses &rarr; routed to ops-advisor agent</p>
  </div>
</div>
```

Note: Use actual entry points that exist. `/soleur:brainstorm` routes to brand-architect and business-validator workshops. `/legal-generate` is an existing skill. For ops, describe the agent routing since there is no dedicated ops command.

**Change C -- Fix Learn More descriptions.** Update "Specialized AI agents for engineering, research, and workflow" to "AI agents across engineering, marketing, legal, operations, and product."

#### Fix llms.txt

**File:** `plugins/soleur/docs/llms.txt.njk`

Replace line 9 with:
```
{{ site.name }} is a Company-as-a-Service platform with {{ stats.agents }} AI agents across engineering, marketing, legal, operations, and product. {{ stats.skills }} skills and {{ stats.commands }} commands that compound company knowledge over time. It orchestrates the full business lifecycle from idea validation to shipping and scaling.
```

#### Fix plugin README subtitle

**File:** `plugins/soleur/README.md`

Change line 3 to:
```
A full AI organization across engineering, marketing, legal, operations, and product. Every decision you make teaches the system. Every project gets better and faster than the last.
```

#### Fix AGENTS.md line 1

**File:** `AGENTS.md`

Change "This repository contains the Soleur Claude Code plugin -- an orchestration engine that provides agents, commands, skills, and a knowledge base for structured software development workflows." to remove the "software development workflows" framing. Replace with language that reflects the Company-as-a-Service scope:

```
This repository contains the Soleur Claude Code plugin -- an orchestration engine that provides agents, commands, skills, and a knowledge base across engineering, marketing, legal, operations, and product.
```

### Business Validation Rewrite (1 file)

**File:** `knowledge-base/overview/business-validation.md`

Manually rewrite the entire document with the correct framing:

- **Problem:** Solo founders managing an entire company alone, not developers wanting structured coding workflows
- **Customer:** Solo founders building companies with AI, not just developers using AI coding assistants
- **Competitive Landscape:** AI agent workforce platforms, not just Claude Code workflow plugins
- **Demand Evidence:** Same honest assessment (zero external users) but framed around what demand we seek
- **Business Model:** Through the Company-as-a-Service lens
- **Minimum Viable Scope:** 5 domains IS the minimum for "full AI organization" -- breadth is the thesis

Verdict will likely still be PIVOT (zero external users), but the recommendation should be "find 10 solo founders who want AI departments" not "shrink to 4 engineering commands."

Cross-reference every section against brand-guide.md before committing.

## Acceptance Criteria

- [x] `plugin.json` description says "company knowledge" and keywords include "company-as-a-service"
- [x] Root `README.md` has no "orchestration engine" hedging, shows all 5 domains in a table
- [x] Getting Started has dynamic counts (`{{ stats.agents }}`) and "Beyond Engineering" section with non-engineering workflows
- [x] `llms.txt` describes full platform, not just software development
- [x] Plugin `README.md` subtitle mentions all 5 domains
- [x] AGENTS.md line 1 reflects Company-as-a-Service scope
- [x] Business-validator reads brand guide before Gate 1, has vision-aware Gate 6, and checks alignment before final write
- [x] CPO cross-references validation against brand guide in Assess phase
- [x] `business-validation.md` evaluates Company-as-a-Service thesis correctly
- [ ] All changes pass CI (markdownlint, SEO validation, component tests)
- [ ] Agent description word count under 2500: `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w`

## Version Bump

PATCH bump (documentation and agent prompt fixes, no new components).

Files to update:
- `plugins/soleur/.claude-plugin/plugin.json` (version)
- `plugins/soleur/CHANGELOG.md`
- `plugins/soleur/README.md` (verify counts)
- `README.md` (version badge)
- `.github/ISSUE_TEMPLATE/bug_report.yml` (placeholder)

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-22-validate-soleur-brainstorm.md`
- Spec: `knowledge-base/specs/feat-validate-soleur/spec.md`
- Issue: #248
- Brand guide heading contract: `## Identity`, `## Voice`, `## Visual Direction`, `## Channel Notes`
