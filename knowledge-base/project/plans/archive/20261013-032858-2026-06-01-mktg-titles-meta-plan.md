# Plan — Marketing docs SEO: titles + meta descriptions (#4405, #4406, #4407)

Date: 2026-06-01
Branch: feat-one-shot-mktg-titles-meta-4405-4406-4407
Source audit: `knowledge-base/marketing/audits/soleur-ai/2026-05-25-content-audit.md` (C1/C3/C4, R1/R2/R5)

## Rendering facts (from `plugins/soleur/docs/_includes/base.njk`)

- `<title>` = `{% if seoTitle %}{{ seoTitle }}{% elif title == site.name %}{{ site.name }} - {{ site.tagline }}{% elif 'Soleur' in title %}{{ title }}{% else %}{{ title }} - {{ site.name }}{% endif %}`
  - A per-page `seoTitle` is the authoritative override. Pages set it to control the exact `<title>`.
- `<meta name="description">` = `{{ description or site.description }}`
  - Always non-empty: a page with no `description` frontmatter falls back to `site.description`.
  - Therefore #4407's "no meta description on any page" finding (a stale WebFetch artifact) is FALSE for the built output — every canonical page already renders a non-empty meta description.

## Verification of #4407 (built-output audit)

Built once with `npx @11ty/eleventy --output=/tmp/site-prC` (canonical config input). Every
canonical (non-redirect) HTML page renders a non-empty `<meta name="description">`. The only
HTML files lacking one are `<meta http-equiv="refresh">` redirect stubs (`pages/*.html`,
dated `blog/YYYY-MM-DD-*` aliases) and the `articles/` collection wrapper — none are real
routes. Conclusion: no per-page `description` additions are required; #4407 is satisfied by
the existing fallback chain. Value-add is (a) confirming the audit-named pages carry bespoke
descriptions and (b) a drift-guard so a future regression that drops the fallback is caught.

## Changes

1. `/getting-started/` (#4405 / R1, R2): add `seoTitle` = "Get Started with Soleur — Install
   Your AI Organization in Two Commands"; replace `description` with the R2 copy.
2. `/blog/` (#4406 / R5): replace `seoTitle` with the R5 category-keyword title; replace
   `description` with the R5 founder-attributed meta.
3. No other page frontmatter changes — every other sampled page already carries a bespoke
   `seoTitle` (where needed) and `description`.

## Tests (`plugins/soleur/test/seo-aeo-drift-guard.test.ts`)

- Drift-guard: `/getting-started/` and `/blog/` `<title>` are NOT brand-only — each contains a
  non-brand keyword token (asserted by stripping "Soleur"/"Blog"/separators and requiring a
  meaningful remainder, plus pinning a specific keyword).
- Drift-guard: every canonical (non-redirect) sampled/evergreen page renders a non-empty
  `<meta name="description">` within a SERP-ish length envelope; loop carries a
  `checked === expected` vacuity guard.

## CodeQL constraints honored

Attribute-capture regexes only (`<meta name="description" content="([^"]*)"`); no
single-pass tag-strip; no `&amp;`→`&` decode; any `.test()` validation regex fully anchored.
