---
name: FAQ HTML / FAQPage JSON-LD parity drift on Eleventy templates
description: When a Nunjucks page emits both a visible HTML answer and a mirrored FAQPage JSON-LD acceptedAnswer.text, any divergence — interpolated stat vs hardcoded integer, or HTML entity vs JSON-escaped codepoint — breaks Google's rich-result parity check. Neither `eleventy --dryrun` nor schema validators catch it; the parity is character-for-character.
type: learning
date: 2026-04-18
category: integration-issues
tags: [faqpage, eleventy, nunjucks, json-ld, aeo, seo, structured-data, rich-results]
---

# FAQ HTML / FAQPage JSON-LD parity drift on Eleventy templates

## Problem

PR #2589 (drain of the 2026-04-18 AEO audit, closing #2553) added a FAQPage block to `plugins/soleur/docs/pages/about.njk`. Two drift classes slipped through initial implementation and were caught only by the post-commit `code-quality-analyst` review on commit `0c2982a9`:

1. **Stats drift (P1).** Visible HTML rendered `"grown to 65 AI agents across 8 business departments"` via `{{ stats.agents }}` / `{{ stats.departments }}`. The mirrored `acceptedAnswer.text` inside `<script type="application/ld+json">` hardcoded `"grown to 60+ AI agents across 8 business departments"`. The integer literal diverged (`65` vs `60+`) the moment the data file changed — violating Google's Rich Results FAQ parity requirement that `acceptedAnswer.text` match the on-page answer.
2. **Apostrophe encoding drift (P2).** Same commit, different Question. HTML used `Anthropic&rsquo;s` (renders as U+2019 RIGHT SINGLE QUOTATION MARK, the site convention for rendered prose — `index.njk` uses the same entity). JSON-LD used ASCII `Anthropic's` (U+0027) because HTML entities are invalid inside a JSON string literal. Both glyphs read as "Anthropic's" to a human; Google compares codepoints, not glyphs.

Both defects shipped past local build, `eleventy --dryrun`, and the first wave of review agents. The JSON-LD parsed as valid schema.org, the HTML rendered cleanly — the divergence only surfaces when a crawler diffs the two surfaces.

## Root cause

Three facts converge into one trap:

- **Google's FAQPage parity is character-exact.** Per <https://developers.google.com/search/docs/appearance/structured-data/faqpage>, `acceptedAnswer.text` must match the answer visible on the page. Close-enough fails rich-result eligibility silently — the page stays indexed, just without the FAQ enhancement.
- **Nunjucks interpolates inside `<script type="application/ld+json">`.** Eleventy does not special-case the script tag; `{{ stats.agents }}` works identically in HTML and in a JSON-LD block. The template has the tool to keep both surfaces in sync — but the author has to reach for it.
- **HTML entities and JSON string literals have asymmetric encoding rules.** `&rsquo;` is valid HTML and invalid JSON. A `U+2019` codepoint is valid in both (directly in HTML, as `\u2019` in JSON). The author has to pick a lane; "use entity in HTML, use ASCII in JSON" feels locally correct in each file but produces cross-surface drift.

The precedent being followed (`index.njk`) *also* hardcodes "60+" in its JSON-LD. That drift predates this PR, went undetected on main, and modeled the wrong pattern for the fresh `about.njk` block. Pipeline mode trusts the precedent.

## Solution (this PR #2589 / commit `0c2982a9`)

Both surfaces now use the same source of truth.

### Stats drift — interpolate in both surfaces

Before (JSON-LD, hardcoded):

```nunjucks
"text": "Since January 2026, Soleur has grown to 60+ AI agents across 8 business departments..."
```

After (JSON-LD, interpolated — matches HTML):

```nunjucks
"text": "Since January 2026, Soleur has grown to {{ stats.agents }} AI agents across {{ stats.departments }} business departments..."
```

Nunjucks renders the same integer into both the visible `<p>` and the JSON-LD string at build time; the data file is now the single source of truth for the stat everywhere on the page.

### Apostrophe drift — normalize HTML to ASCII

Before (HTML used entity, JSON-LD used ASCII):

```html
<p>Yes -- Soleur packages Anthropic&rsquo;s Claude Code plugin spec...</p>
<script type="application/ld+json">
{ "acceptedAnswer": { "text": "Yes -- Soleur packages Anthropic's Claude Code plugin spec..." } }
</script>
```

After (both surfaces use ASCII `'`):

```html
<p>Yes -- Soleur packages Anthropic's Claude Code plugin spec...</p>
<script type="application/ld+json">
{ "acceptedAnswer": { "text": "Yes -- Soleur packages Anthropic's Claude Code plugin spec..." } }
</script>
```

ASCII is simpler than the alternative (`\u2019` in JSON, `&rsquo;` in HTML) and keeps the Question block readable at a glance. Typography purity loses to crawler parity.

## Prevention

**When adding a FAQPage JSON-LD block paired with a visible HTML answer on an Eleventy/Nunjucks page:**

1. **Interpolate every template variable in both surfaces.** If the HTML uses `{{ stats.X }}`, the JSON-LD `acceptedAnswer.text` must use the same expression — not a hardcoded integer, not a "close enough" rounded form. Nunjucks renders inside `<script type="application/ld+json">`; use it.
2. **Normalize apostrophes and quotes to ASCII across both surfaces.** Or, if typography matters, use the literal codepoint (U+2019) in both places — never an HTML entity in one and ASCII in the other. Codepoint comparison is how crawlers diff.
3. **Diff the rendered page, not the template.** `npx @11ty/eleventy --dryrun` produces the final HTML and embedded JSON-LD. Compare Question 1's visible answer against Question 1's `acceptedAnswer.text` character-for-character before declaring the block done. The fastest spot-check: copy both strings into `diff <(echo ...) <(echo ...)` and look for a single byte of divergence.
4. **Don't follow hardcoded-stat precedents without questioning them.** `index.njk`'s JSON-LD has the same hardcoded "60+" drift this PR originally reproduced. Pre-existing drift on main is a bug-in-waiting, not a pattern — file a tracking issue when spotted, don't propagate it.

## Session Errors

- **FAQPage JSON-LD stats drift from Nunjucks-interpolated HTML** — HTML rendered `{{ stats.agents }}` (65), JSON-LD hardcoded `60+`. Caught by `code-quality-analyst` review as P1. Fixed in commit `0c2982a9` by swapping the hardcoded integers for the same template expressions. **Prevention:** When writing a fresh FAQPage block, mirror every `{{ ... }}` expression from the HTML answer into the `acceptedAnswer.text` verbatim — do not inline the current rendered value. Added as a Sharp Edge on `plugins/soleur/skills/review/SKILL.md` so the reviewer flags any Question where HTML and JSON-LD text diverge character-for-character.
- **FAQPage apostrophe encoding drift between HTML entity and ASCII** — HTML used `Anthropic&rsquo;s`, JSON-LD used `Anthropic's`. Caught as P2 in the same review. Fixed by normalizing HTML to ASCII. **Prevention:** same Sharp Edge covers this class — string-for-string HTML vs JSON-LD compare catches both the entity/ASCII split and the codepoint split in one pass.

No further deviations — deviation-analyst sweep of the implementation + review phases found no additional hard-rule violations beyond the two above.

## References

- PR #2589 (this PR, WIP at write-time: <https://github.com/jikig-ai/soleur/pull/2589>)
- Issue #2553 (parent AEO audit ticket, one of four P0s being drained on this branch)
- Audit: `knowledge-base/marketing/audits/soleur-ai/2026-04-18-aeo-audit.md` (source of the FAQPage requirement on `/about/`)
- Fix commit: `0c2982a9` — `review: interpolate stats + normalize apostrophe on /about/ FAQ (P1+P2)`
- Pre-existing drift: `plugins/soleur/docs/pages/index.njk` hardcodes `"60+"` in JSON-LD while `{{ stats.agents }}` renders in the HTML surface. Out of scope for #2553 — file a separate tracking issue if remediating.
- Upstream spec: <https://developers.google.com/search/docs/appearance/structured-data/faqpage> (parity requirement)
- Related precedent: `knowledge-base/project/learnings/2026-03-26-case-study-three-location-citation-consistency.md` (same class of multi-surface sync discipline)
