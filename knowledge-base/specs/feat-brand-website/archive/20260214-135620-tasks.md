# Tasks: Brand Website (Solar Forge)

**Plan:** `knowledge-base/plans/2026-02-14-feat-brand-website-solar-forge-plan.md`
**Issue:** #88
**Branch:** feat-brand-website

## Phase A: Landing Page and CSS Rewrite

- [ ] A.1 Download font woff2 files (Cormorant Garamond 500, Inter 400, Inter 700) into `plugins/soleur/docs/fonts/`
- [ ] A.2 Export favicon (32x32 png) and OG image (1200x630) from .pen logo variations into `plugins/soleur/docs/images/`
- [ ] A.3 Rewrite `plugins/soleur/docs/css/style.css` with Solar Forge brand tokens, @font-face, landing page styles, responsive rules
- [ ] A.4 Rewrite `plugins/soleur/docs/index.html` with Solar Forge landing page (generate from .pen, manually adjust)
- [ ] A.5 Delete `plugins/soleur/docs/js/main.js` and `js/` directory
- [ ] A.6 Verify landing page renders correctly locally

## Phase B: Propagate to Remaining Pages + Ship

- [ ] B.1 Update all 7 remaining pages (6 docs + 404): remove theme toggle, remove theme script, add favicon, add og:image, unify footer
- [ ] B.2 PATCH bump version (plugin.json + CHANGELOG.md + README.md)
- [ ] B.3 Update version badges in all HTML files + root README badge + bug_report.yml
- [ ] B.4 Commit, push, create PR referencing #88
