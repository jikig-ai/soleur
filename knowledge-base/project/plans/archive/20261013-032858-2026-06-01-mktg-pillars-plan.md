---
date: 2026-06-01
owner: CMO
status: in-progress
issues: [3175, 3176, 2561, 2560, 2559]
---

# One-Shot Marketing Pillars + Clusters + Glossary

Close five content issues by shipping net-new pillar/cluster/glossary pages for the
Soleur Eleventy marketing site (`plugins/soleur/docs/`). High-editorial-stakes long-form
content — every external stat must trace to a citation that returns HTTP 200.

## Current state (verified against branch)

- `#3175 /company-as-a-service/` — **already shipped** at `pages/company-as-a-service.njk`
  (~3,000 words, quotable definition, FAQPage JSON-LD w/ 5 Q parity, links to
  departments/vision/pricing, compare strip). This page already closes the D-homepage and
  F-compare inbound links to `/company-as-a-service/`. No rewrite needed; the new tests
  pin its invariants so it cannot regress.
- The disambiguation post `/blog/claude-code-plugin-vs-skill-vs-mcp/` lives on sibling
  branch `76d5e7ea` (not yet in this branch's main). It links to
  `/blog/best-claude-code-plugins-2026/` (existing post) and `/company-as-a-service/` —
  both already resolve. It does NOT link to the new plugins pillar, so the pillar slug is
  free to be the clean head-term URL `/claude-code-plugins/`.

## Pages to ship (net-new)

| Issue | Route | Type | Words | Pillar link target |
|-------|-------|------|-------|--------------------|
| 3176 | `/ai-agents-for-solo-founders/` | `pages/*.njk` permalink | ~3,000 | self (pillar) |
| 2561 | `/agentic-engineering/` | `pages/*.njk` permalink | ~3,000 | self (pillar) |
| 2561 | `/glossary/` | `pages/*.njk` permalink | ~1,500 (10 terms) | reference |
| 2560 | `/ai-cto/` | `pages/*.njk` permalink | ~2,000 | /pricing/ |
| 2560 | `/ai-cmo/` | `pages/*.njk` permalink | ~2,000 | /pricing/ |
| 2560 | `/solo-founder-ai-stack/` | `pages/*.njk` permalink | ~2,200 | /pricing/ |
| 2559 | `/claude-code-plugins/` | `pages/*.njk` permalink | ~3,500 | self (pillar) |

Rationale for top-level `pages/*.njk` with `permalink: <slug>/`: matches
`company-as-a-service.njk` convention; clean head-term URLs the issues require. Cluster
role pages (ai-cto/ai-cmo/solo-founder-ai-stack) are top-level too so they own the role
query and link back to `/pricing/` as pillar.

## Conventions to follow (from existing pages)

- Layout: `layout: base.njk`. Frontmatter: `title`, `seoTitle`, `description` (120–160
  chars for SERP), `permalink`, `ogImage` (reuse an existing og image), optional `ogType`.
- Structure: `<article class="content-page">` > `<header class="content-page-header">`
  (`.section-label`, `<h1>`, `.hero-tagline`, `.blog-post-meta` byline) >
  `<div class="content-page-body">`.
- Stat-led summary paragraph + quotable 1–2 sentence definition at first mention.
- Tables: `<table class="pricing-table">` (cost comparison), plain `<table>` for others.
- FAQ: `<div class="faq-list">` of `<details class="faq-item">` with
  `<summary class="faq-question">` + `<p class="faq-answer">`. Mirror EVERY question into a
  FAQPage JSON-LD block whose `name` is CHARACTER-IDENTICAL to the summary text. Keep
  question text free of apostrophes/ampersands to avoid escaping drift.
- Two JSON-LD blocks: `Article` (use `| jsonLdSafe | safe` on interpolations) + `FAQPage`.
- Stats: `{{ stats.agents }}`, `{{ stats.skills }}`, `{{ stats.departments }}` — never
  hardcode exact counts in prose (use "60+" soft floors).
- `{{ site.url }}` has NO trailing slash. Internal links: `{{ site.url }}/agents/` etc.
- No raw hex, no non-zero border-radius, no inline styles — reuse existing CSS classes only.

## Glossary + nav/footer

`/glossary/` ships ~10 terms: Company-as-a-Service, agentic engineering, AI agent, MCP,
Claude Code plugin, skill, knowledge base, human-in-the-loop, vibe coding, context
engineering. Each: 1-sentence quotable answer + 2–3 sentence expansion + 1 external
citation. Add `/glossary/` to `site.json` `footerColumns` Resources so it is linked
sitewide via the footer auto-include.

## Citations (all verified 200 unless noted)

- Anthropic plugins docs/news, Claude Code docs (plugins/mcp/skills/hooks/sub-agents/
  slash-commands), modelcontextprotocol.io, github anthropics/claude-plugins-official +
  claude-code + skills, MCP servers repo — all 200.
- Karpathy tweet (vibe coding), Addy Osmani 70% post, arXiv 2505.19443, LangChain "what is
  an agent", Anthropic "building effective agents" — all 200.
- Carta solo founders report, Every.to one-person-billion, a16z economic case, Inc.com
  Amodei (bot-walled to curl but already cited site-wide in base.njk/CaaS — KEEP only
  where already established; prefer Every.to + TechCrunch one-person-unicorn which are 200).
- Comp: Built In CTO ($224,550 avg base / $280,985 total), Built In CMO ($225,908 /
  $293,575), PayScale CTO + CMO + Marketing Director — all 200. **BLS is bot-walled (403 to
  curl AND WebFetch) → NOT cited.** Levels.fyi compare (200), Firecrawl plugins review
  (200), claudemarketplaces.com (200), CNBC Cursor $1B (200), TechCrunch Lovable $330M (200).

## Tests

Extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with one describe block covering:
(a) each new page builds with non-empty title + meta description; (b) FAQ↔FAQPage parity
on every new page with a visible FAQ (count + character-identical names, vacuity guard
`checked > 0`); (c) `/company-as-a-service/` exists + contains the quotable definition
(closes D/F inbound links); (d) `/glossary/` renders ≥8 term definitions; (e) the plugins
pillar exists and the disambiguation-linked `/blog/best-claude-code-plugins-2026/`
resolves. CodeQL hygiene: no tag-strip regex, no `&amp;`→`&`, no unanchored `.test()`;
prefer `html.includes(...)` and `.trim()`.

## Verify

`npx @11ty/eleventy --output=/tmp/site-prE` exit 0 + each page present; validate-seo.sh
exit 0; bun test the three SEO test files + full `plugins/soleur/test/`; CodeQL self-check
grep clean; anti-slop on changed njk/css; built-site grep for the new internal links.
