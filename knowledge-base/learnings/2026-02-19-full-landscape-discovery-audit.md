# Learning: Full Landscape Discovery Audit -- 75 Components vs Community

## Problem
After building the functional-discovery agent (#155), we had no baseline understanding of how our 33 agents and 42 skills compare to the broader community ecosystem. Without this audit, we risk:
- Building features that already exist as mature community tools
- Missing complementary tools that could layer alongside ours
- Not knowing which of our components are truly unique vs commoditized

## Solution
Ran 5 parallel functional-discovery agents across all components, querying 3 registries (api.claude-plugins.dev, claudepluginhub.com, Anthropic official marketplace).

### Key Findings

**Zero replacements recommended.** Our differentiation is real -- lifecycle integration, Eleventy specificity, multi-reviewer patterns, and domain knowledge management are not replicated in the community.

### HIGH RISK overlaps (evaluate but don't replace)

| Our Component | Community Alternative | Stars | Why We Keep Ours |
|---|---|---|---|
| pr-comment-resolver | davila7/gh-address-comments | 16.6K | Ours integrates with Soleur review workflow |
| code-simplicity-reviewer | Anthropic code-simplifier (Tier 1) | Official | Ours is a reviewer agent, theirs is a transformation tool |
| dhh-rails-reviewer | kieranklaassen/dhh-rails-style | 4.9K | Same upstream -- we ARE this community |
| security-sentinel | Anthropic semgrep + coderabbit + Trail of Bits | Official | Ours is opinionated for our stack |
| framework-docs-researcher | Context7 MCP (already installed) | N/A | Context7 is complementary, not replacement |
| brainstorming (skill) | obra/superpowers (Tier 1) | 16.8K | Ours outputs to knowledge-base/, integrates with /plan |
| seo-aeo (skill) | Multiple (seo-review 66K, seo-geo 329) | Various | Ours is Eleventy-specific + AEO dual focus |

### Already community-shared (we ARE the source)

- every-style-editor, file-todos, gemini-imagegen (EveryInc/compound-engineering-plugin upstream)
- dhh-rails-style, dspy-ruby, rclone (shared upstream)
- frontend-design (IS the Anthropic official skill, Tier 1)

### Completely unique (zero community overlap)

**Agents (9):** agent-finder, functional-discovery, learnings-researcher, data-migration-expert, deployment-verification-agent, community-manager, ops-advisor, ops-research, ux-design-lead, spec-flow-analyzer

**Skills (14):** compound-docs, deploy-docs, release-docs, deepen-plan, heal-skill, ship, triage, resolve-parallel, resolve-pr-parallel, resolve-todo-parallel, agent-native-audit, docs-site, spec-templates, atdd-developer, reproduce-bug

### Underserved community niches we own

1. **Knowledge management** -- No community tool captures learnings from solved problems
2. **Operations management** -- ops-advisor/ops-research have zero alternatives
3. **Community strategy** -- Community tools are API connectors; ours does engagement strategy
4. **Multi-reviewer patterns** -- plan-review's parallel diverse reviewers is unique
5. **Lifecycle orchestration** -- ship, work, compound flow has no equivalent

### Actionable Recommendations

1. Layer semgrep alongside security-sentinel (SAST vs architectural review)
2. Study seo-geo (329 stars) for GEO/AEO methodology using Princeton research
3. Monitor marketingskills (8.2K stars) as growth space gets crowded
4. No retirements needed

## Key Insight
Running functional-discovery at scale (75 components x 3 registries) confirms that lifecycle integration and domain-specific tooling are the moats. Individual features (SEO audit, code review, brainstorming) are commoditized -- what makes Soleur unique is how they compose into a coherent workflow.

## Tags
category: discovery
module: functional-discovery
symptoms: community-overlap, landscape-audit
