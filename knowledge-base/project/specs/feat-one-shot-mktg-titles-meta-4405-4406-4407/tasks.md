# Tasks — mktg titles + meta (#4405, #4406, #4407)

- [x] Read base.njk to find title/description render + fallback chain
- [x] Read audit R1/R2/R5 exact rewrite copy
- [x] Build site, verify which built pages actually lack `<meta name="description">` (only redirect stubs do)
- [x] #4405: add `seoTitle` (R1) + R2 `description` to `pages/getting-started.njk`
- [x] #4406: replace `seoTitle` + `description` (R5) on `pages/blog.njk`
- [x] #4407: confirm no per-page `description` additions needed (fallback covers all canonical pages)
- [x] Add drift-guard: /getting-started/ + /blog/ titles are not brand-only
- [x] Add drift-guard: every canonical sampled page renders non-empty meta description (with vacuity guard)
- [x] Build (exit 0), validate-seo (exit 0), bun test suite green
- [x] CodeQL self-check grep prints clean
- [x] Commit (conventional, no Closes #N)
