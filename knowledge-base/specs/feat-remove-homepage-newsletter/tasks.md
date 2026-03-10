# Tasks: Remove duplicate newsletter signup from homepage

## Phase 1: Implementation

- [ ] 1.1 Remove newsletter include from `plugins/soleur/docs/index.njk` (lines 218-220: comment, set location, include)

## Phase 2: Verification

- [ ] 2.1 Run Eleventy build: `cd plugins/soleur/docs && npx @11ty/eleventy --quiet`
- [ ] 2.2 Verify homepage has exactly 1 newsletter form: `grep -c 'newsletter-form' _site/index.html` (expected: 1)
- [ ] 2.3 Verify footer newsletter still renders on homepage (visual check or grep for `newsletter-footer`)
- [ ] 2.4 Verify non-homepage pages unaffected: `grep -c 'newsletter-form' _site/pages/getting-started/index.html` (expected: 1)

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR referencing PR #525 pattern
