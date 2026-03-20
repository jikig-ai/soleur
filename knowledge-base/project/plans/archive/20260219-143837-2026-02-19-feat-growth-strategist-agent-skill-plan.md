---
title: feat: add growth-strategist agent and /soleur:growth skill
type: feat
date: 2026-02-19
---

# feat: add growth-strategist agent and /soleur:growth skill

## Overview

Add a `growth-strategist` marketing agent and `/soleur:growth` skill for content strategy -- keyword research, content auditing, content planning, and AI agent consumability analysis. Complements the existing `seo-aeo-analyst` (technical correctness) with content strategy.

## Problem Statement

The v2.15.0 SEO/AEO feature shipped technical infrastructure (meta tags, JSON-LD, sitemap, llms.txt, CI validation) but zero content strategy. Sites can be technically perfect but invisible because page copy doesn't match what people search for.

## Proposed Solution

Follow the same pattern as `seo-aeo-analyst` + `/soleur:seo-aeo`:

- **Agent:** `plugins/soleur/agents/marketing/growth-strategist.md`
- **Skill:** `plugins/soleur/skills/growth/SKILL.md`

Three sub-commands: `audit`, `plan`, `aeo`.

**Boundary with seo-aeo-analyst:** Do not check JSON-LD, meta tags, sitemaps, or llms.txt format -- those belong to the existing agent. Growth handles content-level analysis only.

## Sub-commands

### `audit <url-or-path>`

Analyze existing site content for keyword alignment, search intent match, and readability. Suggests rewrites with rationale. Uses WebFetch for URLs, Read/Glob for local paths. Reads brand guide (`knowledge-base/overview/brand-guide.md`) if present for voice alignment. For large sites, sample top 10-15 pages by importance.

### `plan <topic> [--site <url-or-path>] [--competitors url1,url2]`

Self-contained sub-command that performs keyword research (via WebSearch), gap analysis against existing content and competitors, and produces a prioritized content plan with article outlines. Merges the research, gaps, and planning workflows into one step. If `--site` is provided, includes gap analysis. If `--competitors` are provided, fetches and compares.

Output must include: keyword research findings (with intent classification), content gaps identified, and prioritized content pieces (P1/P2/P3) with outlines and target keywords.

### `aeo <url-or-path>`

Content-level AI agent consumability audit. Checks conversational readiness, FAQ structure quality, definition extractability, summary quality, and citation-friendly paragraph structure. Does NOT check technical AEO (JSON-LD, llms.txt, schema.org) -- that belongs to `seo-aeo-analyst`.

## Agent Design (Sharp Edges Only)

The agent prompt contains ONLY what Claude would get wrong without it:

1. **Information requirements per capability** -- What each sub-command output must contain (not exact table schemas -- let the LLM adapt format to the input).
2. **Brand guide integration path** -- Where to find it, which sections to use for voice/positioning.
3. **AEO content-level checks** -- The specific criteria that differentiate from technical AEO (conversational readiness, FAQ answer quality, citation-friendly structure).
4. **Search intent taxonomy labels** -- Informational, navigational, commercial, transactional.
5. **Exclusion rule** -- One sentence listing what belongs to seo-aeo-analyst.

Skip: general SEO knowledge, content strategy principles, readability analysis, article structure, error handling (Claude handles these).

## Implementation Phases

### Phase 1: Agent

Create `plugins/soleur/agents/marketing/growth-strategist.md`:
- Frontmatter: `name`, `description` with 2 `<example>` blocks, `model: inherit`
- Opening paragraph: third-person summary (extracted by docs data file)
- Body: information requirements, brand guide integration, AEO checks, exclusion rule

### Phase 2: Skill

Create `plugins/soleur/skills/growth/SKILL.md`:
- Frontmatter: `name: growth`, third-person `description` with triggers
- Sub-command table (audit, plan, aeo)
- Each sub-command: input parsing, agent delegation via Task tool
- Brand guide soft-check: if `knowledge-base/overview/brand-guide.md` exists, pass to agent
- Important Guidelines section

### Phase 3: Registration

- Add `"growth": "Content & Release"` to `plugins/soleur/docs/_data/skills.js` SKILL_CATEGORIES
- Update `plugins/soleur/README.md`: add agent to Marketing table, skill to Content & Release table, update component counts
- Version bump (MINOR) across all three files:
  - `plugins/soleur/.claude-plugin/plugin.json` (version + description counts)
  - `plugins/soleur/CHANGELOG.md`
  - `plugins/soleur/README.md`
- Check: root README version badge, `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder, `grep -r "vX.Y.Z" plugins/soleur/docs/` for hardcoded versions

### Phase 4: Verification

- `bun test` -- no regressions
- `npx @11ty/eleventy` -- docs build succeeds, new agent and skill appear
- Validate agent and skill YAML frontmatter

### Phase 5: Live Test on soleur.ai

Apply the tool to soleur.ai as the first real test case:
- Run `growth audit https://soleur.ai` -- verify content audit output
- Run `growth plan "agentic company" --site https://soleur.ai` -- verify keyword research + gap analysis + content plan
- Run `growth aeo https://soleur.ai` -- verify AI consumability audit
- Review outputs for quality and usefulness

## Acceptance Criteria

- [x] Agent and skill files exist with valid frontmatter and follow existing patterns
- [x] Three sub-commands work independently and produce structured output
- [x] Agent reads brand guide when available
- [x] No overlap with existing seo-aeo-analyst checks
- [x] Registered in skills.js, README, plugin.json
- [x] Version bumped (MINOR) across plugin.json, CHANGELOG.md, README.md
- [x] `bun test` passes, docs build succeeds
- [x] Successfully applied to soleur.ai with useful output

## Non-Goals (v1)

- Auto-detection of site content from CWD
- Output file persistence (results are inline)
- Multi-language keyword research
- Integration with paid SEO tools or analytics platforms

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-19-growth-strategist-brainstorm.md`
- Spec: `knowledge-base/specs/feat-growth-strategist/spec.md`
- Issue: #148
- Pattern to follow: `plugins/soleur/agents/marketing/seo-aeo-analyst.md` + `plugins/soleur/skills/seo-aeo/SKILL.md`
