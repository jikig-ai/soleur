# Learning: SEO meta description character counts and frontmatter coherence

## Problem

During implementation of Growth Audit SEO fixes (#1129, #1131, #1134), two planning errors were caught:

1. The deepen-plan subagent claimed a proposed meta description was 155 chars when it was actually 122 chars
2. The plan specified updating the Vision page H1 but omitted updating the `title` and `description` frontmatter fields that must remain semantically aligned

## Solution

1. **Character count:** Manually verified with `echo -n "text" | wc -c` during implementation. Extended the homepage meta description from 122 to 157 chars by listing specific departments.
2. **Frontmatter coherence:** Review agents caught the gap. Updated Vision page `title` ("Vision" → "Soleur Vision: Company-as-a-Service") and `description` (159 chars with matching keywords) in a follow-up commit.

## Key Insight

Meta description character counts must be verified programmatically, not claimed by LLM reasoning. When modifying a page's H1, all semantically related frontmatter fields (title, description) must be updated as a unit — they feed browser tabs, social meta tags, and search engine previews independently of the H1.

## Session Errors

1. **Plan char count miscalculation** — The deepen-plan subagent claimed 155 chars for a 122-char description. Recovery: manual `wc -c` verification and text extension during implementation. **Prevention:** Add programmatic char count verification to the deepen-plan skill when proposing meta descriptions.

2. **Incomplete frontmatter scope** — Plan specified Vision H1 change but not title/description frontmatter. Recovery: pattern-recognition review agent caught it. **Prevention:** Plan skill should enumerate all frontmatter fields that must change when modifying page headings.

3. **Pre-existing build failure (sitemap.njk dateToShort)** — Eleventy build fails on all branches due to missing `dateToShort` filter in sitemap.njk. Not introduced by this PR. **Prevention:** Pre-existing issue, should be tracked separately.

## Tags

category: content
module: marketing/docs-site
