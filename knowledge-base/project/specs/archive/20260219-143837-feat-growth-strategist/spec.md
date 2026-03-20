# Spec: Growth Strategist Agent & Skill

**Date:** 2026-02-19
**Branch:** feat-growth-strategist
**Brainstorm:** `knowledge-base/brainstorms/2026-02-19-growth-strategist-brainstorm.md`

## Problem Statement

The existing `seo-aeo-analyst` agent provides technical SEO auditing (meta tags, structured data, sitemap validation) but has zero content strategy capability. There is no keyword research, no content gap analysis, no search intent alignment, and no AI agent consumability auditing beyond basic llms.txt checks. Sites can be technically perfect but invisible to search engines and AI models because the content doesn't match what people search for.

## Goals

- G1: Provide a reusable marketing agent that performs keyword research, content gap analysis, content planning, content auditing, and AI agent consumability analysis.
- G2: Complement (not replace) the existing `seo-aeo-analyst` agent -- technical SEO + content strategy as a complete stack.
- G3: Apply the tool to soleur.ai as the first test case, targeting both plugin users and thought leadership seekers.

## Non-Goals

- NG1: Replacing or modifying the existing `seo-aeo-analyst` agent.
- NG2: Integrating with paid SEO tools or APIs (Google Search Console API, Ahrefs, SEMrush).
- NG3: Automated content publishing or CMS integration.
- NG4: Generating full articles (agent produces outlines, recommendations, and structure -- not final copy).
- NG5: Framework-specific content generation (agent analyzes content strategy, not Eleventy templates).

## Functional Requirements

- FR1: Agent can audit existing site content for keyword alignment, readability, and search intent match.
- FR2: Agent can perform keyword research, gap analysis, and content planning in a single workflow, producing prioritized content plans with article outlines.
- FR3: Agent can audit content for AI agent consumability -- conversational readiness, FAQ structure, definition extractability, summary quality, citation-friendly structure.
- FR4: Skill provides sub-commands: `audit`, `plan`, `aeo`.
- FR5: Agent reads brand guide (if exists) to align content strategy with brand voice and positioning.
- FR6: Agent produces structured markdown output (not just prose) -- keyword tables, gap matrices, prioritized lists.

## Technical Requirements

- TR1: Agent markdown file at `plugins/soleur/agents/marketing/growth-strategist.md`.
- TR2: Skill SKILL.md at `plugins/soleur/skills/growth/SKILL.md`.
- TR3: Agent uses WebSearch tool for keyword research.
- TR4: Agent uses WebFetch tool for competitor content analysis.
- TR5: Skill sub-commands map to distinct agent invocations via Task tool.

## Success Criteria

- [ ] Agent can audit existing site pages and identify keyword alignment issues.
- [ ] Agent can research keywords, analyze gaps, and generate a prioritized content plan.
- [ ] Agent can audit content for AI agent consumability.
- [ ] All three sub-commands work independently and produce structured output.
- [ ] Skill is registered in skills.js SKILL_CATEGORIES and appears in docs.
- [ ] Applied successfully to soleur.ai as first test case.
