# Brainstorm: Growth Strategist Agent & Skill

**Date:** 2026-02-19
**Status:** Captured
**Participants:** Jean, Claude

## What We're Building

A new marketing agent (`growth-strategist`) and skill (`/soleur:growth`) that handles content strategy, keyword research, content gap analysis, content planning, and AI agent consumability auditing. This fills the gap left by the existing `seo-aeo-analyst` agent, which focuses exclusively on technical SEO correctness (meta tags, structured data, sitemap validation) but has zero content strategy capability.

The tool serves two purposes:
1. **For Soleur users:** A reusable content strategy agent that any Soleur user can apply to their docs/marketing sites.
2. **For soleur.ai:** The first test case -- audit and improve our own site's discoverability for terms like "agentic company", "company as a service", "agentic engineering".

## Why This Approach

### The Gap in Current SEO/AEO Tooling

The `seo-aeo-analyst` agent (v2.15.0) was deliberately scoped to technical correctness:
- Meta tags present and valid
- JSON-LD structured data correct
- Sitemap with lastmod dates
- llms.txt exists
- CI validation via standalone bash script

What it does NOT do:
- Research what people actually search for
- Analyze whether page copy matches search intent
- Identify content gaps vs competitors
- Plan new content to capture organic traffic
- Ensure content is structured for AI agent consumption beyond llms.txt

This was the right call for v1 -- ship the infrastructure first. But infrastructure without strategy is like having a perfectly formatted page that nobody finds.

### Separate Agent, Not Extension

We chose a dedicated `growth-strategist` agent over extending `seo-aeo-analyst` because:
- **Different disciplines:** Technical SEO auditing is deterministic (pass/fail). Content strategy is creative, research-heavy, and ongoing.
- **Different workflows:** Auditing runs once and reports. Strategy requires iteration, research, planning.
- **Different outputs:** Audits produce reports. Strategy produces content plans, keyword maps, editorial calendars.
- **Naming for discovery:** Users searching for "content strategy" won't look under "seo-aeo".

### "Growth" Over "Content"

Named `growth-strategist` (not `content-strategist`) to allow future expansion beyond SEO content -- the growth framing can encompass distribution, channels, and other organic growth levers without renaming.

## Key Decisions

1. **New dedicated agent + skill** -- not an extension of the existing seo-aeo agent/skill.
2. **Agent name:** `growth-strategist`, living under `agents/marketing/`.
3. **Skill name:** `/soleur:growth` with sub-commands.
4. **Five core capabilities:**
   - **Keyword research:** Web search-based research of actual search terms, volume signals, related queries, competitor keywords.
   - **Content gap analysis:** Compare existing site content against target keywords and competitor sites to find missing topics.
   - **Content planning:** Generate content calendars, article outlines, page structures optimized for target search intent.
   - **Content audit:** Analyze existing page copy for keyword alignment, readability, search intent match, suggest rewrites.
   - **AI agent consumability:** Ensure content uses semantic HTML, structured data, machine-readable summaries, and conversational-ready formatting that AI models can extract, cite, and quote accurately.
5. **Target audiences for soleur.ai:** Both plugin users (devs searching for AI dev tools) AND thought leadership seekers (people exploring "agentic company" concepts).
6. **Search term strategy:** Mix of terms to own (e.g., "company as a service") and terms to validate with real search data (e.g., "agentic engineering", "AI company").
7. **Content scope for soleur.ai:** Full content strategy -- blog/articles section, concept explainer pages, use case guides, comparison pages.
8. **Build tool first, then apply** -- design the reusable agent/skill, then use it on soleur.ai as the first real test case.

## Relationship to Existing SEO/AEO Agent

| Aspect | seo-aeo-analyst (existing) | growth-strategist (new) |
|--------|---------------------------|------------------------|
| Focus | Technical correctness | Content strategy |
| Inputs | Built site HTML, config files | Site content, search data, brand guide, competitors |
| Outputs | Pass/fail audit report | Keyword maps, content plans, gap analyses, rewrites |
| Workflow | Run once, fix, validate | Iterative research and planning |
| CI Integration | Yes (validate-seo.sh) | No (strategy is not automatable in CI) |
| Web Search | No | Yes (keyword research) |

The two agents are complementary:
- Run `seo-aeo` to ensure technical foundation is correct
- Run `growth` to ensure content actually targets what people search for

## Potential Sub-commands

- `/soleur:growth audit` -- Analyze existing site content for keyword alignment and search intent
- `/soleur:growth research` -- Research keywords, search volume signals, related queries
- `/soleur:growth gaps` -- Identify content gaps vs target keywords and competitors
- `/soleur:growth plan` -- Generate content plan with article outlines and priorities
- `/soleur:growth aeo` -- Audit content for AI agent consumability (structured data, conversational readiness)

## Open Questions

1. **Keyword volume data:** Web search can estimate relevance but not exact search volume. Should we integrate with any free tools (Google Trends, AnswerThePublic) or rely purely on web search heuristics?
2. **Competitor analysis scope:** Should the agent analyze competitor sites directly (fetch and compare), or work from user-provided competitor URLs?
3. **Content generation:** Should the agent generate draft content, or stop at outlines and recommendations?
4. **Brand guide integration:** Should the agent read `brand-guide.md` to ensure content strategy aligns with brand voice and positioning?
5. **Metrics/tracking:** Should the agent recommend analytics setup (Search Console, etc.) or stay focused on content strategy?
6. **Eleventy-specific or framework-agnostic:** Should content planning assume Eleventy (like seo-aeo), or be framework-agnostic?
