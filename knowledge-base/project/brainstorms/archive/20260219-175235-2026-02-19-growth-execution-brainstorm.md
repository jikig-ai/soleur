# Brainstorm: Growth Execution Capabilities

**Date:** 2026-02-19
**Issue:** #153
**Status:** Decided

## What We're Building

Two execution capabilities that close the gap between growth-strategist analysis and applied changes:

1. **`growth fix` sub-command** -- Applies audit findings (keyword injection, AEO fixes, copy rewrites) to existing site pages programmatically. Follows the `seo-aeo fix` pattern: self-contained audit + fix in one pass.

2. **`content-writer` skill** (new, standalone) -- Generates full publication-ready article drafts from a topic, optional outline, and optional keywords. Requires brand guide. Independent of growth-strategist output format.

## Why This Approach

The growth-strategist agent (v2.16.0) produces high-quality analysis but stops at recommendations. Live testing on soleur.ai (PR #152) showed 10 audit issues, 9 rewrite suggestions, a 14-article content plan, and an AEO score of 1.6/10 -- all requiring manual execution.

The `seo-aeo` skill already solved this exact problem for technical SEO with its audit/fix/validate flow. We replicate that pattern for content-level concerns.

Content writing is a separate skill because:
- It serves contexts beyond growth strategy (changelogs, docs articles, brand announcements)
- It has a different prerequisite model (hard brand guide requirement vs optional)
- Clean separation: growth-strategist analyzes, content-writer creates

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | `growth fix` on existing skill + separate `content-writer` skill | Consolidation principle for fix; reusability for writing |
| Fix workflow | Self-contained (audit + fix in one pass) | Matches seo-aeo pattern, simpler UX |
| Content output | Full publication-ready drafts | Follows discord-content pattern with review gate |
| Blog scaffolding | Delegate to docs-site skill | Content-writer writes content, not infrastructure |
| Growth plan integration | Independent (topic + optional outline + keywords) | More reusable, not coupled to growth output format |
| Brand guide | Required for content-writer, optional for growth fix | Content needs voice consistency; fixes work on existing voice |
| Agent architecture | Single growth-strategist agent with mode-switching | "Split when it hurts" principle from learnings |

## Component Design

### Component 1: `growth fix`

**Changes to existing files:**
- `agents/marketing/growth-strategist.md` -- Add "Execute (when requested)" step that applies rewrite suggestions via Edit tool
- `skills/growth/SKILL.md` -- Add `growth fix <url-or-path>` sub-command; remove "no files written" constraint

**Behavior:**
1. Agent audits the target (same as `growth audit`)
2. For each issue found, applies the fix using Edit tool
3. Fixes: keyword injection in headings/body, FAQ section generation, definition paragraphs, meta description rewrites
4. Brand guide alignment check on rewrites (if brand guide exists)
5. Builds site to verify changes compile
6. Reports what was changed

**Boundary:** Only modifies existing page content. Does not create new pages.

### Component 2: `content-writer` skill

**New files:**
- `skills/content-writer/SKILL.md` -- Skill definition

**No new agent needed** -- content generation is the skill's direct responsibility, not domain analysis requiring a specialized agent.

**Interface:**
- `content-writer <topic>` -- Write article on topic
- `content-writer <topic> --outline "..."` -- Write with provided outline
- `content-writer <topic> --keywords "k1, k2, k3"` -- Target specific keywords
- `content-writer <topic> --path blog/posts/` -- Specify output location

**Prerequisites:**
- Brand guide must exist (`knowledge-base/overview/brand-guide.md`)
- Blog infrastructure must exist (if not, directs user to `docs-site` skill)

**Pipeline (follows discord-content pattern):**
1. Read brand guide Voice and Channel Notes sections
2. Generate full article with Eleventy frontmatter, JSON-LD Article structured data
3. Generate FAQ schema if topic warrants it
4. Inline brand voice check against Do's and Don'ts
5. Present draft to user for approval (Accept / Edit / Reject)
6. Write to disk on approval

## Learnings Applied

- **Brand guide contract pattern** -- Use exact heading names (`## Voice`, `## Channel Notes`) for section extraction
- **Inline validation beats separate reviewers** -- Validate brand voice within the skill, don't spawn a separate agent
- **Eleventy gotchas** -- Passthrough copy from project root, no variables in frontmatter YAML, use computed data for dynamic values
- **Sequential blocker pattern** -- Encode prerequisite checks (brand guide exists, blog dir exists, site builds) before execution
- **Parallel subagent mismatch** -- If parallelizing later, provide compact reference lists not full brand guide

## What We're NOT Building (YAGNI)

- No `growth validate` sub-command (unclear what content validation checks programmatically)
- No parallel article generation (one at a time; add later if needed)
- No blog scaffolding in content-writer (delegates to docs-site)
- No growth-plan-aware parsing in content-writer (independent interface)
- No separate agent for content writing (skill handles it directly)

## Open Questions

None remaining. All architectural decisions resolved.
