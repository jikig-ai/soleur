# Marketing Audit Tasks

**Plan:** `knowledge-base/plans/2026-02-21-feat-marketing-audit-plan.md`
**Issue:** #193

## Brand Guide and Voice Fixes

- [ ] 1. Update brand guide counts (31/40 -> 45/45) and tone spectrum example
- [ ] 2. Grep for all prohibited terms, fix all hits (README, index.njk, llms.txt, help.md, overview/README.md, changelog.njk)
- [ ] 3. Add "plugin" boundary exception rule to brand guide
- [ ] 4. Update stale counts in all 7 legal documents
- [ ] 5. Verify grep returns zero violations after fixes

## Root README Restructure

- [ ] 6. Rewrite README: remove vision section, table of contents; add website badge, "Learn More" links; rewrite opening as declarative brand statement

## Website Improvements

- [ ] 7. Create /vision page from moved README content, rewritten in brand voice
- [ ] 8. Add vision page to site.json nav and footerLinks
- [ ] 9. Add "Why Soleur" section to getting-started page
- [ ] 10. Fix index.njk "AI-powered" violation
- [ ] 11. Run local Eleventy build to verify

## GitHub Metadata

- [ ] 12. Set homepage URL, update description, optimize topics
- [ ] 13. Update plugin.json homepage to soleur.ai

## Cleanup

- [ ] 14. Create analytics research issue, comment on #188
- [ ] 15. Version bump (PATCH), commit, push, PR
