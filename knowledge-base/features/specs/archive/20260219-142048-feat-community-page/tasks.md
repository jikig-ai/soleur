# Tasks: Community Hub Page

**Plan:** `knowledge-base/plans/2026-02-19-feat-community-hub-page-plan.md`
**Issue:** #149
**Branch:** feat-community-page

## Phase 1: Navigation Changes

- [ ] 1.1 Update `plugins/soleur/docs/_data/site.json` -- add "Community" to `nav` array, replace GitHub/Discord in `footerLinks` with Community link
- [ ] 1.2 Update `plugins/soleur/docs/_includes/base.njk` -- remove hardcoded GitHub/Discord `<li>` elements from header

## Phase 2: Community Page

- [ ] 2.1 Create `plugins/soleur/docs/pages/community.njk` with hero, connect cards, contributing, support, and code of conduct sections

## Phase 3: Verification

- [ ] 3.1 Run Eleventy build and confirm `pages/community.html` is generated with no errors
- [ ] 3.2 Verify page is included in sitemap
- [ ] 3.3 Visual check -- responsive at desktop, tablet (1024px), mobile (768px)

## Phase 4: Ship

- [ ] 4.1 Version bump (PATCH) -- `plugin.json`, `CHANGELOG.md`, `README.md`
- [ ] 4.2 Commit, push, and open PR
