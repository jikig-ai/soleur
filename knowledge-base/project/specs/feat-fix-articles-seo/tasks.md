# Tasks: fix/articles-seo

Source plan: `knowledge-base/project/plans/2026-03-05-fix-articles-seo-metadata-plan.md`

## Phase 1: Core Fix

- [x] 1.1 Update `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` -- add instant redirect detection (`content="0"` meta-refresh) with `continue` to skip SEO checks for redirect-only pages
- [x] 1.2 Verify existing tests still pass after script change

## Phase 2: Testing

- [x] 2.1 Add test case in `plugins/soleur/test/validate-seo.test.ts` for instant redirect page exclusion
- [x] 2.2 Add negative test case for delayed meta-refresh page (content="5") -- verify it is NOT skipped
- [x] 2.3 Run full test suite: `bun test plugins/soleur/test/validate-seo.test.ts`

## Phase 3: Integration Verification

- [x] 3.1 Build docs locally: `npm install && npx @11ty/eleventy`
- [x] 3.2 Run validator against build output: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
- [x] 3.3 Confirm `pages/articles.html` shows as skipped redirect
- [x] 3.4 Confirm all other pages still pass all four SEO checks

## Phase 4: Ship

- [ ] 4.1 Run compound
- [ ] 4.2 Commit, push, create PR with `semver:patch` label
