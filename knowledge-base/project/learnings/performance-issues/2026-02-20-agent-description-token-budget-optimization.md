---
title: Agent description token budget optimization
category: performance-issues
module: plugin-loader
tags: [agents, frontmatter, token-budget, system-prompt, descriptions]
symptoms: ["Large cumulative agent descriptions will impact performance (~15.8k tokens > 15.0k)"]
---

# Agent Description Token Budget Optimization

## Problem

Claude Code warned: "Large cumulative agent descriptions will impact performance (~15.8k tokens > 15.0k)". All 44 agent description frontmatter fields contained verbose `<example>` blocks with context, user/assistant dialogue, and `<commentary>` blocks -- mandated by a constitution rule. These descriptions are injected into the system prompt on every conversation turn, consuming context window space, increasing latency, and diluting model attention.

## Root Cause

The constitution rule "Agent descriptions must include at least one `<example>` block" was well-intentioned for routing accuracy but ignored the cumulative cost. With 36 agents at ~400 words each, the total reached ~15.8k tokens -- exceeding the recommended 15k threshold. Adding 8 more marketing agents would have pushed it further.

The description field's job is **routing** (deciding when to invoke an agent), not providing full instructions. Full instructions belong in the agent body (after `---`), which is only loaded on invocation.

## Solution

1. **Stripped all `<example>` blocks** from every agent description -- reduced from ~15.8k to ~2.1k tokens
2. **Added one-line disambiguation sentences** to 30 agents across 11 sibling groups -- increased to ~2.9k tokens total (82% reduction from original)
3. **Updated constitution rule** to prohibit examples in descriptions and mandate disambiguation for sibling agents
4. **Fixed cleanup artifacts** -- trailing `\n\n`, trailing `Examples:` text left by the stripping script

### Disambiguation pattern

```
"[Core routing description]. Use [sibling] for [its scope]; use this agent for [this scope]."
```

### Sibling groups disambiguated

- Research: best-practices vs framework-docs vs learnings vs repo vs git-history
- Data review: data-integrity-guardian vs data-migration-expert vs deployment-verification
- Rails: dhh vs kieran reviewers
- SEO/Growth: growth-strategist vs seo-aeo-analyst vs programmatic-seo vs copywriter
- Marketing: marketing-strategist vs conversion-optimizer vs retention-strategist
- Infra: infra-security vs terraform-architect
- Ops: ops-advisor vs ops-research
- Legal: legal-document-generator vs legal-compliance-auditor
- Discovery: agent-finder vs functional-discovery
- Architecture: architecture-strategist vs ddd-architect
- Code quality: code-quality-analyst vs pattern-recognition-specialist

## Key Insight

Agent descriptions must be optimized for **routing**, not **instruction**. The system prompt carries all descriptions on every turn, so cumulative cost matters. Disambiguation sentences (~15 words) are more token-efficient than example blocks (~150 words) and equally effective for routing accuracy.

## Prevention

- Constitution updated: descriptions must be 1-3 sentences, no examples, disambiguation required for siblings
- Skill-creator skill updated: enforces description length constraints when creating new agents
- Any new agent or community agent integration must check cumulative description token count
