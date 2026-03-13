# Tasks: Fix Stale knowledge-base/overview References

## Phase 1: Fix References

- [ ] 1.1 Update `knowledge-base/product/pricing-strategy.md` YAML frontmatter `depends_on` block (4 path replacements)
  - [ ] 1.1.1 `knowledge-base/overview/brand-guide.md` -> `knowledge-base/marketing/brand-guide.md`
  - [ ] 1.1.2 `knowledge-base/overview/marketing-strategy.md` -> `knowledge-base/marketing/marketing-strategy.md`
  - [ ] 1.1.3 `knowledge-base/overview/competitive-intelligence.md` -> `knowledge-base/product/competitive-intelligence.md`
  - [ ] 1.1.4 `knowledge-base/overview/business-validation.md` -> `knowledge-base/product/business-validation.md`
- [ ] 1.2 Update `knowledge-base/product/competitive-intelligence.md` source documents and cascade results sections (4 path replacements)
  - [ ] 1.2.1 `knowledge-base/overview/brand-guide.md` -> `knowledge-base/marketing/brand-guide.md`
  - [ ] 1.2.2 `knowledge-base/overview/business-validation.md` -> `knowledge-base/product/business-validation.md`
  - [ ] 1.2.3 `knowledge-base/overview/content-strategy.md` -> `knowledge-base/marketing/content-strategy.md`
  - [ ] 1.2.4 `knowledge-base/overview/pricing-strategy.md` -> `knowledge-base/product/pricing-strategy.md`

## Phase 2: Verification

- [ ] 2.1 Run `grep -r 'knowledge-base/overview/' knowledge-base/product/` and confirm zero matches
- [ ] 2.2 Verify each updated path points to an existing file
