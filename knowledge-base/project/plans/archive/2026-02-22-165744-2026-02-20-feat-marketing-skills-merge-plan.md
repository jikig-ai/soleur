---
title: Merge marketingskills into Soleur -- Full AI Marketing Department
type: feat
date: 2026-02-20
issue: "#174"
version_bump: MINOR
---

# Merge marketingskills into Soleur

## Overview

Adopt capabilities from coreyhaines31/marketingskills (MIT, 8.5K stars, 29 skills) by consolidating them into 8 new focused agents, expanding 2 existing agents, and placing them flat under `agents/marketing/`. Total: 8 new agent files, 2 expanded. Post-merge: 42 agents, 42 skills.

## Problem Statement

Soleur covers ~25% of marketing functions (content strategy, SEO/AEO, brand, community). The remaining 75% (CRO, paid ads, pricing, retention, referrals, launch strategy, measurement) has zero coverage.

## Proposed Solution

Consolidate 29 external skills into 8 focused agents with broader scope each. Claude already knows marketing fundamentals -- each agent uses sharp-edges-only prompts (only what Claude gets wrong). No CMO orchestrator (deferred to #154 when usage patterns emerge).

## Consolidated Agent Map

| New Agent | Absorbs From marketingskills | Subdomain |
|---|---|---|
| **marketing-strategist** | marketing-ideas, marketing-psychology, launch-strategy, product-marketing-context | strategy |
| **pricing-strategist** | pricing-strategy | strategy |
| **copywriter** | copywriting, copy-editing, cold-email, email-sequence, social-content | content |
| **conversion-optimizer** | page-cro, signup-flow-cro, onboarding-cro, form-cro, popup-cro, paywall-upgrade-cro | cro |
| **paid-media-strategist** | paid-ads, ad-creative | paid |
| **analytics-analyst** | ab-test-setup, analytics-tracking | measurement |
| **retention-strategist** | churn-prevention, referral-program, free-tool-strategy | retention + growth |
| **programmatic-seo-specialist** | programmatic-seo, competitor-alternatives | seo |

| Expanded Agent | Absorbs From marketingskills |
|---|---|
| **growth-strategist** (existing) | content-strategy, ai-seo |
| **seo-aeo-analyst** (existing) | seo-audit, schema-markup |

**Total:** 8 new + 2 expanded = 10 agents touched. All live flat under `agents/marketing/` (no subdomain folders -- 12 agents in one folder is manageable).

## Agent Template (minimal)

```markdown
---
name: <agent-name>
description: "<Third-person description with example blocks>"
model: inherit
---

<One paragraph: what this agent does, what it covers, when to use it>

## Sharp Edges

<Only the instructions Claude would get wrong without them.
Brand guide: check for knowledge-base/overview/brand-guide.md, read Voice + Identity if present.
Output: structured tables, matrices, prioritized lists -- not prose.>
```

No boilerplate sections. Brand guide integration is a one-liner in sharp edges. Cross-references emerge from usage.

## Implementation

1. Create `plugins/soleur/NOTICE` with MIT attribution
2. Create 8 new agent markdown files in `agents/marketing/`
3. Expand growth-strategist.md (content pillar/cluster planning, SAP AEO framework)
4. Expand seo-aeo-analyst.md (E-E-A-T signals, Core Web Vitals, JS schema warning)
5. Update plugin.json, CHANGELOG.md, README.md (MINOR version bump)
6. Update root README.md (version badge, agent count 34 -> 42)
7. Update .github/ISSUE_TEMPLATE/bug_report.yml placeholder

## Acceptance Criteria

- [ ] 8 new agent files created in `agents/marketing/`
- [ ] growth-strategist expanded with content-strategy + ai-seo capabilities
- [ ] seo-aeo-analyst expanded with seo-audit + schema-markup capabilities
- [ ] Every agent has proper YAML frontmatter (name, description with examples, model: inherit)
- [ ] NOTICE file with MIT attribution
- [ ] Version bump (MINOR) across plugin.json + CHANGELOG + README triad
- [ ] Agent count updated in all locations

## Test Scenarios

- Given conversion-optimizer is invoked for a signup form, when it runs, then it reads brand guide and produces CRO recommendations covering the specific conversion surface
- Given copywriter is invoked for an email sequence, when it runs, then it produces brand-aligned copy with structure for each email in the sequence
- Given growth-strategist is invoked with content planning, when it includes new content pillar/cluster and searchable/shareable capabilities from the expansion
- Given `bun test` is run, when all markdown files are checked, then no frontmatter or lint errors

## Non-Goals

- CMO orchestrator agent (deferred to #154)
- User-facing skills for each agent (invoke agents directly)
- Automated social posting or ad buying (analysis and strategy only)
- Subdomain folders (12 agents is flat-manageable)

## Version Bump

MINOR bump. 8 new agents added, 2 expanded.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-20-marketing-skills-merge-brainstorm.md`
- Spec: `knowledge-base/specs/feat-marketing-skills-merge/spec.md`
- Overlap analysis: `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md`
- CMO exploration (deferred): #154
- marketingskills repo: https://github.com/coreyhaines31/marketingskills (MIT)
- Issue: #174
