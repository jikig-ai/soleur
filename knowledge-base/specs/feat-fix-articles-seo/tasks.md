# Tasks: fix/articles-seo

Source plan: `knowledge-base/plans/2026-03-05-fix-articles-seo-metadata-plan.md`

## Phase 1: Core Fix

- [ ] 1.1 Update `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` -- add redirect detection (`meta http-equiv="refresh"`) with `continue` to skip SEO checks for redirect-only pages
- [ ] 1.2 Verify existing tests still pass after script change

## Phase 2: Testing

- [ ] 2.1 Add test case in `plugins/soleur/test/validate-seo.test.ts` for redirect page exclusion
- [ ] 2.2 Run full test suite: `bun test plugins/soleur/test/validate-seo.test.ts`

## Phase 3: Integration Verification

- [ ] 3.1 Build docs locally: `npm install && npx @11ty/eleventy`
- [ ] 3.2 Run validator against build output: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [ ] 3.3 Confirm `pages/articles.html` shows as skipped redirect
- [ ] 3.4 Confirm all other pages still pass all four SEO checks

## Phase 4: Ship

- [ ] 4.1 Run compound
- [ ] 4.2 Commit, push, create PR with `semver:patch` label
