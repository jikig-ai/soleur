---
title: Merge marketingskills into Soleur -- Full Marketing Department
date: 2026-02-20
status: decided
---

# Brainstorm: Merge marketingskills into Soleur

## What We're Building

A comprehensive AI marketing department within Soleur by adopting coreyhaines31/marketingskills (MIT license, 29 skills, 8.5K stars) and integrating them as fully lifecycle-aware agents. This includes a CMO agent as the orchestration layer that assesses marketing posture and delegates to specialized marketing agents -- analogous to how `/soleur:work` orchestrates engineering tasks.

The goal is to replace a full traditional marketing team: content strategy, SEO/AEO, CRO, paid ads, pricing, retention, referrals, launch strategy, and measurement.

## Why This Approach

### Approach chosen: Sharp-edges-only agents (Approach B)

Each new agent file is lean -- only instructions Claude would get wrong without them. Claude already knows marketing fundamentals. Agent files contain:

- Brand guide integration hooks (read `knowledge-base/overview/brand-guide.md`)
- Output format requirements (structured tables, knowledge-base output paths)
- Domain-specific gotchas extracted from marketingskills prompts
- Cross-references to related agents

This follows the growth-strategist pattern where sharp-edges-only reduced the prompt by 65% (370 to 130 lines) with no capability loss.

### Approaches rejected

**A: Full rewrite** -- Rewrites all 29 prompts comprehensively. Rejected because most marketing knowledge is already in the model. High effort, high maintenance, contradicts constitution ("sharp-edges-only prompt design").

**C: Domain super-agents** -- Merges into ~6 broad agents. Rejected because it violates single-responsibility and makes individual capabilities harder to invoke and test.

## Key Decisions

1. **CMO agent first** -- Build the orchestrator before the specialized agents. The CMO assesses marketing posture, creates strategy, and delegates to specialized agents. This mirrors #154.

2. **Agents, not skills** -- The adopted capabilities become agents under `agents/marketing/`, not skills. Agents recurse into subdirectories, integrate with the CMO via Task tool, and don't need manual `SKILL_CATEGORIES` registration.

3. **Subdomain organization** -- Group agents into marketing function subfolders:
   - `agents/marketing/cro/` -- page, signup-flow, onboarding, form, popup, paywall-upgrade
   - `agents/marketing/content/` -- copywriting, copy-editing, cold-email, email-sequence, social-content
   - `agents/marketing/seo/` -- programmatic-seo, competitor-alternatives, schema-markup (existing seo-aeo-analyst and growth-strategist absorb seo-audit, ai-seo, content-strategy)
   - `agents/marketing/paid/` -- paid-ads, ad-creative
   - `agents/marketing/measurement/` -- ab-test-setup, analytics-tracking
   - `agents/marketing/retention/` -- churn-prevention
   - `agents/marketing/growth/` -- free-tool-strategy, referral-program
   - `agents/marketing/strategy/` -- marketing-ideas, marketing-psychology, launch-strategy, pricing-strategy, product-marketing-context

4. **Merge high-overlap agents** -- Don't create duplicate agents. Instead, expand existing ones:
   - content-strategy capabilities merge into growth-strategist
   - seo-audit capabilities merge into seo-aeo-analyst
   - ai-seo capabilities merge into growth-strategist (AEO) + seo-aeo-analyst (technical)

5. **Full integration** -- Every agent gets: brand guide awareness, knowledge-base output, structured report format. No standalone prompts.

6. **Single release** -- One MINOR version bump with all agents + CMO.

7. **Sharp-edges-only prompts** -- Each agent file contains only what Claude gets wrong. No encyclopedic marketing knowledge. Focus on: output format, brand guide hooks, gotchas, cross-agent references.

## Open Questions

1. **CMO skill entry point** -- Should there be a `/soleur:marketing` skill (like `/soleur:work`) that invokes the CMO agent? Or does the CMO get invoked directly via the existing agent system?

2. **Existing skill fate** -- The `growth`, `seo-aeo`, and `content-writer` skills currently delegate to agents. Do they stay as user-facing entry points, or does the CMO replace them?

3. **Agent count impact** -- Adding ~22 new agents (29 minus 3 merged into existing, minus 4 we already have) brings total from ~35 to ~57. Is this too many? Does the subdomain organization mitigate the sprawl?

4. **Attribution** -- MIT license requires copyright notice. Where does it go? Agent file headers? A single NOTICE file?

## Source Material

- Overlap analysis: `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md`
- CMO agent exploration: issue #154
- marketingskills repo: https://github.com/coreyhaines31/marketingskills (MIT license)
- Growth-strategist sharp-edges learning: `knowledge-base/learnings/2026-02-19-growth-strategist-agent-skill-development.md`
