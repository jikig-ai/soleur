# Tasks: Remove duplicate newsletter signup from homepage

## Phase 1: Implementation

- [ ] 1.1 Remove newsletter include from `plugins/soleur/docs/index.njk` (lines 218-220: comment, set location, include)

## Phase 2: Verification (worktree-safe -- no Eleventy build needed)

- [ ] 2.1 Verify `index.njk` no longer includes newsletter-form: `grep -c 'newsletter-form' plugins/soleur/docs/index.njk` (expected: 0)
- [ ] 2.2 Verify `base.njk` still includes footer newsletter: `grep -c 'newsletter-form' plugins/soleur/docs/_includes/base.njk` (expected: 2)
- [ ] 2.3 Verify `newsletter-form.njk` partial still exists

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR referencing PR #525 pattern
