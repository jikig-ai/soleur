# Tasks — Evergreen Freshness + Stat-Led Summary + Citations

Closes #3169, #3170, #3994, #4410. Plan:
`knowledge-base/project/plans/2026-06-01-mktg-evergreen-freshness-plan.md`

- [ ] T1 Add `_includes/page-freshness.njk` (stat-led summary + last-updated + byline).
- [ ] T2 Add CSS for `.page-summary` / `.page-meta` / `.page-definition` / `.page-citations`.
- [ ] T3 index.njk: `date`+`last_updated`+`pageSummary` frontmatter, include after hero.
- [ ] T4 about.njk: same.
- [ ] T5 vision.njk: same (technical register summary).
- [ ] T6 pricing.njk: same.
- [ ] T7 agents.njk: same (technical register; eleventyComputed page already).
- [ ] T8 skills.njk: same.
- [ ] T9 getting-started.njk: freshness block + plain definition + 3 citations (#4410).
- [ ] T10 Extend drift-guard test: per-page summary+meta+byline; getting-started defn+citations; checked>0.
- [ ] T11 Verify: eleventy build, validate-seo, bun test (drift/jsonld/validate-seo + full suite).
- [ ] T12 Commit (conventional, no `Closes #N`).
