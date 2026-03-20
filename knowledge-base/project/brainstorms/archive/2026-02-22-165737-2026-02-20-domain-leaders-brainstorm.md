# Domain Leader Pattern Brainstorm

**Date:** 2026-02-20
**Issue:** #154
**Status:** Complete

## What We're Building

A **Domain Leader pattern** that adds domain-aware orchestration to the Soleur workflow. Each business domain (Engineering, Marketing, etc.) gets a leader agent that:

- Assesses current state within its domain
- Recommends actions and delegates to specialist agents
- Participates in the brainstorm/plan/work/review/ship workflow when its domain is relevant
- Manages Agent Teams for parallel work within its domain

**First two leaders:**

- **CTO** (Engineering) -- formalizes existing engineering orchestration (review, work, agent teams)
- **CMO** (Marketing) -- replaces `marketing-strategist`, orchestrates 11 marketing specialist agents

## Why This Approach

The Soleur workflow (brainstorm -> plan -> work -> review -> ship) is currently engineering-centric. Marketing has 12 agents but no coordinator. Rather than building a one-off CMO agent, we're designing a reusable Domain Leader pattern that any domain can implement.

**Alternatives considered:**

1. **Generic meta-agent** -- One parameterized agent for all domains. Rejected: premature abstraction for 2 domains, weaker prompts than domain-specific agents.
2. **CMO first, extract later** -- Build CMO, then retroactively extract a pattern. Rejected: risks divergence between CTO and CMO interfaces.
3. **No orchestrator** -- Keep agents independent. Rejected: 12 marketing agents with no coordination makes discovery hard and cross-domain features (launches) manual.

## Key Decisions

1. **Domain Leader Interface** -- All leaders share a contract: assess -> recommend -> delegate -> review. Domain-specific implementations keep agent prompts sharp.

2. **CMO replaces marketing-strategist** -- The existing `marketing-strategist` agent gets absorbed into the CMO. One leader that both strategizes AND orchestrates.

3. **Brand routing folds into CMO** -- The brainstorm command's brand keyword routing becomes part of CMO's domain detection, not a special case.

4. **Advisory authority only** -- Leaders recommend and flag concerns but do not block workflow phases. User decides what to act on.

5. **Workflow hooks** -- Each command (brainstorm, plan, work, review, ship) gets a domain detection phase that identifies relevant domains and offers to loop in their leaders.

6. **CTO + CMO only** -- Start with 2 leaders. CLO (Legal), COO (Operations), CPO (Product) get separate follow-up issues.

7. **Agent Teams integration** -- Leaders use Claude Code Agent Teams for parallel specialist work within their domain.

8. **Single workflow** -- No separate `/soleur:marketing:brainstorm` or `/soleur:engineering:plan`. The existing commands become domain-aware.

## Domain Leader Interface Contract

Every domain leader agent implements:

| Phase | Responsibility | Example (CMO) |
|-------|---------------|----------------|
| **Assess** | Evaluate current domain state | Check brand guide, SEO health, content gaps, community metrics |
| **Recommend** | Propose domain-specific actions | "Run content audit before launching; update landing page copy" |
| **Delegate** | Spawn specialist agents via Agent Teams | Task growth-strategist, Task seo-aeo-analyst, Task copywriter |
| **Review** | Validate specialist output against domain standards | Brand voice consistency, SEO compliance, content quality |

## CMO Scope

**Replaces:** `marketing-strategist` agent

**Orchestrates (11 agents):**

| Agent | Domain |
|-------|--------|
| analytics-analyst | Measurement |
| brand-architect | Brand |
| community-manager | Community |
| conversion-optimizer | CRO |
| copywriter | Copy |
| growth-strategist | Content Strategy |
| paid-media-strategist | Paid Media |
| pricing-strategist | Pricing |
| programmatic-seo-specialist | Programmatic SEO |
| retention-strategist | Retention |
| seo-aeo-analyst | Technical SEO/AEO |

**Entry points:**

- `/soleur:marketing` skill for standalone marketing work
- Auto-consulted via domain detection when features have marketing relevance

## CTO Scope

**Formalizes:** Existing engineering orchestration patterns

**Orchestrates:**

- Review agents (via `/soleur:review` pattern)
- Work agents (via `/soleur:work` Agent Teams)
- Research agents (git-history, repo-research, etc.)

**Entry point:**

- Auto-consulted via domain detection for engineering work (already implicit; CTO formalizes this)

## Workflow Integration Points

| Command | Domain Detection Trigger | Leader Action |
|---------|------------------------|---------------|
| brainstorm | Keywords in feature description | Leader joins exploration, adds domain-specific questions |
| plan | Feature touches domain concerns | Leader adds domain tasks to the plan |
| work | Plan includes domain tasks | Leader manages Agent Team for domain work |
| review | Changes touch domain artifacts | Leader runs domain-specific review agents |
| ship | Feature has domain deliverables | Leader validates domain readiness |

## Open Questions

1. **Detection granularity** -- How specific should keyword detection be? Too broad = false positives (every feature "needs marketing"). Too narrow = missed opportunities.

2. **Leader-to-leader communication** -- When CTO and CMO are both active on a feature, do they coordinate directly or through the user?

3. **Standalone vs integrated** -- Should `/soleur:marketing` also trigger the full workflow (brainstorm -> plan -> work -> ship) for pure marketing projects, or is it assessment + delegation only?

4. **Marketing subdomains** -- Should the 11 marketing agents be reorganized into subdirectories (cro/, content/, seo/) now that the CMO provides structure?

5. **Token budget** -- Adding CTO + CMO descriptions to the 44 existing agents. Need to keep descriptions lean (1-3 sentences + disambiguation).
