# Plan — Evergreen Page Freshness + Stat-Led Summary + /getting-started/ Citations

Date: 2026-06-01
Branch: feat-one-shot-mktg-evergreen-freshness-3169-3170-3994-4410
Closes: #3169, #3170, #3994, #4410

## Problem

Four P1 AEO issues converge on the evergreen marketing pages of the Eleventy
docs site (`plugins/soleur/docs/`):

- **#3169** — no stat-led summary paragraph below the hero (AEO citation target).
- **#3170** — no visible "last updated" + author byline (E-E-A-T freshness).
- **#3994** — same two gaps, framed against the AEO Presence ≥55% exit gate;
  wants `last_updated` frontmatter rendered + a stat-led `<p>` under each H1.
- **#4410** — `/getting-started/` specifically needs a 2-line plain-language
  Soleur definition at the top + 2–3 external citations.

## Canonical evergreen page set

From #3169/#3170/#3994 (homepage + the 5 cited pages):

1. `index.njk` (homepage, `/`)
2. `pages/about.njk` (`/about/`)
3. `pages/vision.njk` (`/vision/`)
4. `pages/pricing.njk` (`/pricing/`)
5. `pages/agents.njk` (`/agents/`)
6. `pages/skills.njk` (`/skills/`)

`/getting-started/` (`pages/getting-started.njk`) gets the freshness block too
(it's evergreen) PLUS the #4410-specific definition + citations.

## What already exists (reconciled — do NOT duplicate)

- `site.author` (name/role/bio/image/sameAs) already in `site.json` — reuse for byline.
- `base.njk` already emits `WebPage.dateModified` from `page.date` (JSON-LD).
- Blog posts already have an `author-card` + per-entry `card-byline`; evergreen
  pages do **not**. No existing `last_updated` / page-level byline / stat-led
  summary on the 6 evergreen pages.
- `/agents/` and `/skills/` already have a descriptive sub-hero `<p>` but no
  single stat-dense extraction-target sentence and no freshness line.
- `/getting-started/` already cites Claude Code plugins docs + links MCP/Claude
  in body prose, but has no top-of-page plain definition and no explicit
  Apache-2.0 / Claude Code docs / MCP spec citation cluster near the top.

## Approach (DRY, frontmatter-driven)

### New shared include: `_includes/page-freshness.njk`
Renders, in order:
1. `<p class="page-summary">…</p>` — stat-led summary. Text from per-page
   frontmatter `pageSummary` (lets register vary per #3169); falls back to a
   sensible default built from `stats.*`.
2. `<p class="page-meta">` with a visible "Last updated <time datetime=…>" +
   "By <a>Jean Deruelle</a>" byline. Date from frontmatter `last_updated`.

Included by the 6 evergreen page templates + getting-started, placed
immediately after the hero `<section>` (below the H1 → "below the hero").

**Fixture safety:** the include reads only `site.author.name` (present in the
jsonld-escaping fixture stub) and per-page frontmatter. It is included ONLY by
real page templates, never by `base.njk`/`blog-post.njk`, so the fixture's
`index.njk`/`test-post.njk` never reach it. No new `site.*` field → no fixture
stub edit needed. Summary text lives in per-page frontmatter (not `site.*`).

### dateModified alignment
Set frontmatter `date: 2026-06-01` AND `last_updated: 2026-06-01` on each page.
`date` feeds the existing `page.date` → JSON-LD `dateModified` + sitemap lastmod;
`last_updated` feeds the visible line. Same value → consistent freshness signal.

### #4410 /getting-started/
- Add a `<p class="page-definition">` 2-line plain definition directly under H1.
- Add a citations cluster (`.page-citations`) with 3 real external links,
  verified to resolve:
  - Apache-2.0: https://www.apache.org/licenses/LICENSE-2.0
  - Claude Code docs: https://docs.claude.com/en/docs/claude-code
  - MCP spec: https://modelcontextprotocol.io

### CSS
Add `.page-summary`, `.page-meta`, `.page-definition`, `.page-citations` to
`docs/css/style.css`. These render below the fold (after hero) so NOT required
in the critical-CSS inline block, but `.page-meta`/`.page-summary` sit just
below `.page-hero` — keep them lightweight; no above-fold critical addition.

## Tests — `test/seo-aeo-drift-guard.test.ts` (extend)

New describe block asserting, for every evergreen built page:
- exactly one `<p class="page-summary">` rendered, non-empty, length ≥ ~80 chars.
- one `<p class="page-meta">` containing "Last updated", a `<time datetime=`
  attribute, and the byline "Jean Deruelle".
- summary appears AFTER the page H1 (below-hero ordering).
- `checked > 0` counter guards against vacuous skip-all.

For `/getting-started/`:
- `<p class="page-definition">` present.
- ≥2 external citations (count distinct external hrefs in `.page-citations`),
  including apache.org + modelcontextprotocol.io + docs.claude.com.

**CodeQL-safe:** no `.replace(/<[^>]+>/g,"")` tag-strip, no `&amp;→&` decode.
Summaries are plain text → `.trim()` only; decode only `&#39;`/`&quot;` if ever
needed. Count hrefs via attribute regex, not text extraction.

## Verification
- `npx @11ty/eleventy --output=/tmp/site-prB` exits 0.
- `validate-seo.sh /tmp/site-prB` exits 0.
- `bun test` drift-guard + jsonld-escaping + validate-seo all green.
- full `plugins/soleur/test/` green.
