---
date: 2026-06-01
branch: feat-one-shot-mktg-homepage-copy-3165-3166-3167-3168-3996
issues: [3165, 3166, 3167, 3168, 3996]
audits:
  - knowledge-base/marketing/audits/soleur-ai/2026-05-04-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-05-18-content-audit.md
owner: CMO
---

# Marketing homepage / about / pricing copy fixes — plan

Five content issues across three Eleventy pages (`plugins/soleur/docs/index.njk`,
`pages/about.njk`, `pages/pricing.njk`). Preserve PR-A (about.njk knowsAbout
JSON-LD) and PR-B (freshness frontmatter + `page-freshness.njk` include) work.

## #3168 — memory-first deck-line under homepage H1
Add a subhead under the H1 surfacing the memory-first hook. Audit (2026-05-04
§Homepage rewrite #2) recommended copy: "The Company-as-a-Service platform that
already knows your business. Build a billion-dollar company — alone." The
existing `hero-tagline` line ("…platform for solo founders. Build a
billion-dollar company — alone.") is the deck-line slot; replace its text with
the memory-first variant (keeps the closing punch line, surfaces memory hook).

## #3167 — full entity H1 on /about/
`<h1>About</h1>` → `<h1>About Soleur and its founder, Jean Deruelle</h1>`
(2026-05-04 §/about/ rewrite #1). Keep the existing sub `<p>`.

## #3166 — define "Concurrent Conversations" inline on /pricing/
Add a one-line definition above the pricing tier grid (the Plans section
`section-subtitle` area) explaining what a concurrent conversation is and that
the per-plan number is a parallelism cap, not an access gate. Reuse the FAQ
answer's framing. Use existing `.section-subtitle` / a new caption paragraph
reusing existing classes — no new raw-hex / rounded CSS.

## #3165 — "66 AI agents" hard prose count → "60+" soft floor
CRITICAL FINDING: there is NO literal hardcoded "66" in source today — every
count is `{{ stats.agents }}`, which now renders **67** (drift already happened:
audit said 66, build emits 67). The brand-guide §Numbers soft-floor rule (cited
as the issue source) says: exact counts ONLY in stat strips / tables /
structured-data; **soft floors ("60+") in narrative prose**. So the fix is to
replace `{{ stats.agents }}` (and prose `{{ stats.skills }}`) with `60+` in
PROSE only, leaving structural stat-strip/table interpolations as-is.

PROSE → `60+` (soft floor):
- index.njk:16 hero-sub, :169 FAQ answer, :209 JSON-LD FAQ answer (keep in sync
  with visible), :267 final-CTA paragraph
- pricing.njk:142 H2 "X specialists", :215 Plans subhead prose
- about.njk:27 bio, :33 bio (agents + skills), :74 FAQ answer, :110 JSON-LD FAQ

KEEP (structural exact counts):
- index.njk:46 stat-strip value; :50 skills stat value
- pricing.njk:19 hero-stat strip
- All `{{ stats.departments }}` (8 is structurally stable per audit)

## #3996 — promote Cursor/Copilot comparison out of `<details>`
The comparison currently lives ONLY as a homepage FAQ `<details class="faq-item">`
("How does Soleur differ from Cursor or GitHub Copilot?"). Promote it into a
standalone, non-collapsed `<section class="landing-section">` with an H2
("Soleur vs. Cursor and GitHub Copilot") rendered as scannable prose, placed
above the FAQ section so it is above-the-fold-ish and crawlable. Add a hero
jump-link (`#soleur-vs-copilots`).

IMPORTANT — FAQ/JSON-LD parity guard (#2707/#3171 test): the homepage FAQPage
JSON-LD `mainEntity` count must equal the visible `<details class="faq-item">`
count. If we REMOVE the comparison from the FAQ, we must also drop its JSON-LD
entry to keep parity. Decision: KEEP the FAQ `<details>` entry (parity intact,
deep answer still collapsed for FAQ-rich-result eligibility) AND add the new
promoted section with its own prose. The promoted section is NOT a
`<details>` — satisfying the "not inside <details>" test — while the FAQ entry
remains for schema.org FAQPage eligibility. New section reuses existing
`.landing-section` / `.section-title` / `.section-desc` classes (no new CSS).

## Tests (seo-aeo-drift-guard.test.ts)
(a) homepage renders a deck-line/subhead under H1 with the memory hook
(b) /about/ H1 is the full entity H1 (contains "Jean Deruelle", not bare "About")
(c) /pricing/ contains an inline "concurrent conversation" definition near table
(d) no hardcoded "66 AI agents" prose on homepage/pricing/about built HTML
    (and assert prose no longer interpolates the exact agent count → presence of
    "60+" soft floor in the hero-sub)
(e) the Cursor/Copilot comparison content exists OUTSIDE any `<details>` on the
    homepage (a promoted section)
All skip-loops get `checked > 0` / `=== count` vacuity guards.

## CodeQL / anti-slop constraints
- No `.replace(/<[^>]+>/g,"")` tag-strip, no `&amp;`→`&` decode, no unanchored
  `.test()` for validation — prefer `html.includes("literal")`.
- New njk section: reuse existing classes, no raw hex, no non-zero border-radius.

## Verify
- `npx @11ty/eleventy --output=/tmp/site-prD` exit 0
- `validate-seo.sh /tmp/site-prD` exit 0
- `bun test` drift-guard + jsonld-escaping + validate-seo green, full suite green
- CodeQL self-check grep clean; tier1 anti-slop scan clean on added lines
