---
feature: feat-one-shot-mktg-schema-canonical-3171-3174
lane: single-domain
plan: knowledge-base/project/plans/2026-06-01-fix-docs-structured-data-canonical-signal-cleanup-plan.md
closes: [3174, 3173, 3172, 3171]
---

# Tasks — Docs-site structured-data & canonical-signal cleanup

Derived from the finalized (deepened) plan. PR body MUST contain `Closes #3174`,
`Closes #3173`, `Closes #3172`, `Closes #3171` — each on its own line, in the body not the title.

## Phase 1 — #3174 Person topical fields

- [ ] 1.1 Add `author.knowsAbout` topical-area array to `plugins/soleur/docs/_data/site.json`
      (≥4 noun-phrase topics, e.g. AI agents / Autonomous software engineering / Distributed
      systems / Developer tooling / Company-as-a-Service). Keep `author.credentials` for the
      visible author card.
- [ ] 1.2 Repoint `plugins/soleur/docs/_includes/blog-post.njk` line 36 `knowsAbout` from
      `site.author.credentials` → `site.author.knowsAbout` (keep `| jsonLdSafe | safe`).
- [ ] 1.3 Add `description` (= `site.author.bio`) and `knowsAbout` (= `site.author.knowsAbout`)
      to the `about.njk` ProfilePage Person node (~lines 145-161), both via `jsonLdSafe | safe`.
- [ ] 1.4 Extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (#2711 block) to assert
      `knowsAbout` is the topical array on BOTH Person emitters (blog-post + about ProfilePage),
      and that no `knowsAbout` entry is a role/bio sentence.

## Phase 2 — #3173 BlogPosting.image confirmation

- [ ] 2.1 Confirm `blog-post.njk:26` threads per-post `ogImage` (no change expected).
- [ ] 2.2 Add a drift-guard assertion: every blog post with `ogImage:` frontmatter renders that
      exact filename in `BlogPosting.image` (not `og-image.png`).
- [ ] 2.3 File a `domain/marketing` + `priority/p3-low` tracking issue for bespoke OG-image
      design on the 11 imageless posts; cite milestone `Phase 4: Validate + Scale`.

## Phase 3 — #3172 canonical-host audit (no source edits expected)

- [ ] 3.1 Run AC6 grep; confirm zero canonical-bearing `www.` refs in docs source.
- [ ] 3.2 Confirm built-output apex alignment via existing drift-guard apex-host assertions
      (`seo-aeo-drift-guard.test.ts:394-450` stay green).
- [ ] 3.3 Document the audit + #4577/#4584 prior-art in the PR body (premise was inverted;
      signals already apex-aligned).

## Phase 4 — #3171 FAQPage parity (gate coverage already confirmed)

- [ ] 4.1 No `validate-seo.sh` edit — `find … -name '*.html'` loop + FAQ gate (line 198) already
      cover pages + blog. Verify the gate stays green after build.
- [ ] 4.2 Add Q/A-text-parity drift-guard rows for `pricing`/`about`/`company-as-a-service`,
      reusing the HTML-entity normalization from the #2707 precedent (`seo-aeo-drift-guard.test.ts:137`).

## Phase 5 — Build, validate, ship

- [ ] 5.1 `npm run docs:build` (from `plugins/soleur/docs`) completes clean; `_site/` produced.
- [ ] 5.2 `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` exits 0.
- [ ] 5.3 `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts plugins/soleur/test/validate-seo.test.ts plugins/soleur/test/jsonld-escaping.test.ts` all green.
- [ ] 5.4 Extract every `<script type="application/ld+json">` from `_site/`, pipe through `jq .`
      (exit 0 — valid JSON for every Person/BlogPosting/FAQPage node).
- [ ] 5.5 Open PR with the four `Closes #N` lines + AC6 grep output + reconciliation summary.
