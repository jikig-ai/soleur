---
title: "Billion-Dollar Solo Founder Stack pillar (P1.7)"
issue: 2712
brainstorm: knowledge-base/project/brainstorms/2026-04-22-billion-dollar-solo-founder-pillar-brainstorm.md
source_plan: knowledge-base/marketing/audits/soleur-ai/2026-04-21-content-plan.md
branch: feat-billion-dollar-solo-founder-pillar
pr: 2811
status: ready-for-plan
---

# Spec — Billion-Dollar Solo Founder Stack pillar (P1.7)

## Problem Statement

Soleur's brand positioning ("Build a Billion-Dollar Company. Alone.") is a direct
match for the "one-person billion-dollar company" thesis that moved from speculation
to evidence in 2026 (Medvi $1.8B projected; Amodei 70-80% / 2026 prediction quoted
in 15+ tier-1 outlets). The SERP for the head terms (`billion dollar solo founder`,
`one person unicorn`, `one person billion dollar company`) is owned entirely by
media publishers — no product has claimed the category-owner slot. Competitors
(Cofounder.co, n8n, MindStudio) are not filling it.

A shorter companion post (`/blog/one-person-billion-dollar-company/`, 2026-04-21)
exists but does not cover the "stack by function" breakdown, the 10-Q FAQ, or the
3,500-4,500-word depth needed to rank as a pillar. Soleur is invisible on head
terms it is literally about.

## Goals

- **G1** — Ship a 3,500-4,500-word pillar post ranking for head keywords above,
  living at `/blog/billion-dollar-solo-founder-stack/`.
- **G2** — Meet every line of the content plan's structural contract (quotable
  definition first 100 words, inline citations for every stat, pillar link in
  first 200 words, closing `/pricing/` CTA, `pillar:` frontmatter, 10-Q FAQ).
- **G3** — Preserve the existing 2026-04-21 companion post; add bidirectional
  pillar↔cluster linking.
- **G4** — Ship a matching OG image consistent with the existing blog visual
  family (generated via `gemini-imagegen`).
- **G5** — Pass the AEO dual-rubric scorecard (target: ≥80/B+) and existing
  SEO build-time checks.

## Non-Goals

- **NG1** — Refactor the existing companion post's prose (beyond adding the
  pillar-series link-up block).
- **NG2** — Ship the other P1 pillars (P1.1 Claude Code plugin pillar, P1.5 AI
  Agents vs SaaS, P1.6 Agentic Engineering expansion) — tracked separately.
- **NG3** — Build a dedicated `/guides/` or `/pillars/` route. Use the existing
  flat `/blog/*` structure.
- **NG4** — Add new internal link targets for P1.5 / P1.6 (not yet shipped);
  stub the link or defer until those pillars land.

## Functional Requirements

- **FR1** — Post lives at `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md`
  with Eleventy frontmatter (`title`, `seoTitle`, `date`, `description`,
  `ogImage`, `tags`, `pillar: billion-dollar-solo-founder`).
- **FR2** — Prose follows the content-plan outline §432 (10 sections: Definition,
  Medvi, Amodei, what makes it possible, stack-by-function, what the human does,
  how Soleur fits, counterpoint, FAQ, CTA).
- **FR3** — Every cited stat has an inline hyperlinked citation to the primary
  source (Wealthy Tent, Inc.com, PYMNTS, LinkedIn/Nicholas Thompson, therundown.ai,
  thiswithkrish.com, Entrepreneur, PrometAI, NxCode, Carta 2024, Anthropic 2026
  Agentic Coding Trends Report, Deloitte TMT 2026, CIO).
- **FR4** — Internal links in the copy: `/vision/`, `/pricing/`,
  `/blog/what-is-company-as-a-service/`, and the 2026-04-21 companion post.
- **FR5** — 10-Q FAQ section (Who has done it? Is it ethical? Do you still hire
  anyone? Claude API cost? Which model? Defensibility vs. 20-person team? +
  4 more per plan).
- **FR6** — Existing 2026-04-21 companion post gets a "Part of the
  Billion-Dollar Solo Founder series" link-up to the new pillar in the first
  200 words.
- **FR7** — OG image at `plugins/soleur/docs/images/blog/og-billion-dollar-solo-founder-stack.png`
  (1200x630), generated via `gemini-imagegen` and consistent with
  `og-one-person-billion-dollar-company.png` style.
- **FR8** — Pillar-series component renders the "Part of the X series" block
  when a post has `pillar:` frontmatter. Verify the component exists; if not,
  add it (Eleventy `_includes/` template).
- **FR9** — `blog.json` / sitemap / `llms.txt.njk` pick up the new post
  automatically (verify via Eleventy build).

## Technical Requirements

- **TR1** — Citation freshness: verify every cited URL resolves (200 OK) at
  ship time via `fact-checker` agent.
- **TR2** — AEO dual-rubric scorecard must score ≥80 (B+) per
  `plugins/soleur/skills/seo-aeo/references/dual-rubric-scorecard-template.md`.
- **TR3** — Eleventy build passes: `cd plugins/soleur/docs && npm run build`.
- **TR4** — `npx markdownlint-cli2 --fix plugins/soleur/docs/blog/<file>.md`
  passes clean. Rule `cq-prose-issue-ref-line-start` applies.
- **TR5** — Copy complies with the brand guide (`knowledge-base/marketing/brand-guide.md`)
  — especially §Trust-scaffolding (counterpoint section §8 mandatory).
- **TR6** — No fabricated citations. Every stat ties to a real source URL.
  Rule `cq-docs-cli-verification` class applies to cited tools/CLIs.

## Acceptance Criteria

- **AC1** — New pillar file exists with correct Eleventy frontmatter and renders
  at `/blog/billion-dollar-solo-founder-stack/` in a local Eleventy build.
- **AC2** — All 10 outline sections present, in order, with the specified
  internal links and citations.
- **AC3** — Existing 2026-04-21 companion post has the pillar-series link-up
  block in its first 200 words.
- **AC4** — OG image file exists, is 1200x630, and is referenced by the pillar's
  `ogImage` frontmatter.
- **AC5** — Dual-rubric AEO scorecard ≥80 (B+).
- **AC6** — Eleventy build passes; markdownlint clean; `fact-checker` verifies
  all citations resolve.
- **AC7** — `blog.json`, sitemap, and `llms.txt` list the new post after rebuild.
- **AC8** — PR references `Closes #2712` in body.

## Implementation Notes

- Delegate drafting to `copywriter` agent (per rule
  `wg-for-user-facing-pages-with-a-product-ux`).
- Delegate OG image generation to `gemini-imagegen` skill.
- Delegate citation verification to `fact-checker` agent.
- Delegate final AEO scoring to `seo-aeo-analyst` agent with the dual-rubric
  scorecard template.
- Pillar-series component: check if `_includes/pillar-series.njk` (or similar)
  exists. If not, add it as part of implementation.

## Related Issues

- Parent plan: `knowledge-base/marketing/audits/soleur-ai/2026-04-21-content-plan.md` P1.7
- Summary of plan: #2706
- Sibling pillars: P1.1 (Claude Code plugin), P1.5 (AI Agents vs SaaS),
  P1.6 (Agentic Engineering expansion) — tracked separately
