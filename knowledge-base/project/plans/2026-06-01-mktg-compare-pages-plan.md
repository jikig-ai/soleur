# Plan — Marketing Comparison + Disambiguation Pages (#4408, #4409, #3177)

Date: 2026-06-01
Branch: `feat-one-shot-mktg-compare-pages-3177-4408-4409`

## Goal

Ship three net-new content surfaces for the Soleur Eleventy marketing site, closing
three P1 content/AEO gaps from the 2026-05-25 and 2026-05-04 content plans:

- **#4408** — `/compare/soleur-vs-cursor/` standalone comparison landing page
- **#4409** — `/compare/soleur-vs-devin/` standalone comparison landing page
- **#3177** — `/blog/claude-code-plugin-vs-skill-vs-mcp/` disambiguation post

## Surface decisions

- **`/compare/` pages are new `pages/*.njk` files with explicit `permalink:`** —
  there is no `/compare/` collection convention. `pages/compare-soleur-vs-cursor.njk`
  → `permalink: compare/soleur-vs-cursor/index.html`, and likewise for devin. The
  trailing-slash directory URL means `sitemap.njk` (iterates `collections.all`,
  emits only `entry.url.endsWith("/")`) auto-includes them — no manual nav/sitemap edit.
- **#3177 is a blog post** (`plugins/soleur/docs/blog/2026-06-01-claude-code-plugin-vs-skill-vs-mcp.md`)
  picked up by `blog.json` (`permalink: blog/{{ page.fileSlug }}/index.html`,
  `layout: blog-post.njk`). It inherits BlogPosting JSON-LD, author card, and
  knowsAbout from `blog-post.njk` — so the #2711/#3173/#3174 guards stay green.
- **Compare-page layout** uses `layout: base.njk` with a `.page-hero` hero +
  `<section class="content"><div class="container"><div class="prose">…` body.
  `.prose` gives table styling (`.prose table/th/td`); `.faq-list`/`.faq-item`/
  `.faq-question`/`.faq-answer` are global. NO new CSS, NO raw hex, NO non-zero
  border-radius — reuse existing classes only (anti-slop).

## FAQ ↔ FAQPage JSON-LD parity (the #2707/#3171 drift-guard)

Every visible `<details class="faq-item"><summary class="faq-question">QTEXT</summary>`
MUST have a matching FAQPage `mainEntity[].name` that is **character-identical** to
QTEXT after `.trim()`. To stay safe:

- Questions contain NO apostrophes / quotes / ampersands / nested markup (avoids
  `&#39;`/`&quot;`/`&amp;` entity drift between the autoescaped visible summary and
  the JSON-LD string). Plain ASCII question text only.
- Visible summary text and the JSON-LD `name` come from the same source string.

## Content (fair + truthful)

Soleur = Company-as-a-Service / multi-department AI org with a compounding knowledge
base. Cursor = AI code editor / agent platform (engineering domain). Devin = autonomous
SWE agent in a sandbox. Each compare page: 1-sentence summary near top, side-by-side
table, "When to pick X" + "When to pick Soleur", ≥2 verified external citations,
trust scaffolding (human-in-the-loop), FAQ + FAQPage JSON-LD. Cursor page cross-links
the existing `/blog/soleur-vs-cursor/` post (and vice-versa is already covered by the
CaaS compare-strip). #3177 links the Claude Code plugin pillar
(`/blog/best-claude-code-plugins-2026/`) + a sibling
(`/blog/skill-libraries-vs-workflow-plugins/`).

## Citations (verified 200 on 2026-06-01)

- Cursor: `https://cursor.com/pricing`, `https://www.cnbc.com/2026/02/24/cursor-announces-major-update-as-ai-coding-agent-battle-heats-up.html` ($1B ARR / $29.3B valuation), `https://cursor.com/blog/agent-computer-use`
- Devin: `https://cognition.ai/blog/devin-2`, `https://cognition.ai/`, `https://www.cnbc.com/2026/02/24/cursor-announces-major-update-as-ai-coding-agent-battle-heats-up.html` (price-arc context); Devin $500→$20 anchor cites Cognition's Devin 2 announcement.
- Plugin/Skill/MCP: `https://docs.claude.com/en/docs/claude-code/plugins`, `https://docs.claude.com/en/docs/agents-and-tools/agent-skills`, `https://modelcontextprotocol.io/`, `https://docs.claude.com/en/docs/claude-code/mcp`

## Tests (extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts`)

New `describe` block "#4408/#4409/#3177 new comparison + disambiguation surfaces":
1. Each new page builds + renders a non-empty `<title>` and `<meta name="description">`.
2. Each page with a visible FAQ has a FAQPage JSON-LD whose `mainEntity` names ==
   visible `<summary>` text (reuse the #3171 parity shape — `.trim()` only, decode
   only `&#39;`/`&quot;`, NO tag-strip, NO `&amp;` decode).
3. The plugin-vs-skill-vs-mcp post renders the disambiguation `<table>` with the
   Plugin / Skill / MCP rows.
4. Vacuity guards: `checked === expected count`.

CodeQL test-code constraints honored: no `.replace(/<[^>]+>/g,"")`, no
`.replace(/&amp;/g,"&")`, all `.test()` validation regexes anchored or replaced by
`html.includes("literal")`.

## Verification

`npx @11ty/eleventy --output=/tmp/site-prF` (3 new pages present) →
`validate-seo.sh /tmp/site-prF` → `bun test plugins/soleur/test/` green →
CodeQL self-check grep clean → anti-slop scan clean on changed njk.
