# Tasks: Remove CaaS Hero Badge

## Phase 1: Core Changes

- [ ] 1.1 Delete `.hero-badge` div from `plugins/soleur/docs/index.njk` (lines 10-13)
- [ ] 1.2 Change hero top padding from `--space-12` to `--space-10` in `plugins/soleur/docs/css/style.css` (line 407)
- [ ] 1.3 Delete `.landing-hero .hero-badge` CSS rule block (lines 410-420)
- [ ] 1.4 Delete `.hero-badge-dot` CSS rule block (lines 421-427)

## Phase 2: Version Bump

- [ ] 2.1 Bump PATCH version in `plugins/soleur/plugin.json`
- [ ] 2.2 Add changelog entry in `plugins/soleur/CHANGELOG.md`
- [ ] 2.3 Update version in `plugins/soleur/README.md`
- [ ] 2.4 Update version badge in root `README.md`
- [ ] 2.5 Update version placeholder in `.github/ISSUE_TEMPLATE/bug_report.yml`

## Phase 3: Verification

- [ ] 3.1 Verify `index.njk` frontmatter `description` still contains CaaS reference (SEO preserved)
- [ ] 3.2 Grep for `hero-badge` across docs -- should return zero matches
- [ ] 3.3 Visual check at mobile, tablet, and desktop breakpoints (hero spacing)
