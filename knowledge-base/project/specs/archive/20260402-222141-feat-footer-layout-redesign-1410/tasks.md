# Tasks: Footer Layout Redesign

Source: `knowledge-base/project/plans/2026-04-02-feat-footer-layout-redesign-plan.md`
Issue: #1410

## Phase 1: Data Structure

- [x] 1.1 Split `footerLinks` array in `plugins/soleur/docs/_data/site.json` into `footerNav` (6 navigation links) and `footerLegal` (3 legal links)

## Phase 2: Template Update

- [x] 2.1 Update `plugins/soleur/docs/_includes/base.njk` footer section to render `site.footerNav` in existing `<ul class="footer-links">` and `site.footerLegal` in new `<ul class="footer-legal">`

## Phase 3: Styles

- [x] 3.1 Add `.footer-legal` and `.footer-legal a` styles in `plugins/soleur/docs/css/style.css` within the existing footer section of `@layer components`
- [x] 3.2 Verify mobile responsive behavior -- the existing `flex-direction: column` on `.footer-inner` at `max-width: 768px` should handle the new element without changes

## Phase 4: Documentation Cleanup

- [x] 4.1 Update `knowledge-base/project/learnings/docs-site/2026-02-19-adding-docs-pages-pattern.md` to reference `footerNav`/`footerLegal` instead of `footerLinks`

## Phase 5: Verification

- [x] 5.1 Run `npx @11ty/eleventy` to verify Eleventy build completes without errors
- [x] 5.2 Visual verification at desktop (1200px+), tablet (769-1024px), and mobile (below 768px) breakpoints
- [x] 5.3 Verify all 9 footer links render and point to correct URLs
