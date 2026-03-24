# Tasks: fix-404-link-validation

## Phase 1: Fix social-distribute URL construction

### 1.1 Update Phase 3 in social-distribute SKILL.md

- [ ] Read `plugins/soleur/skills/social-distribute/SKILL.md`
- [ ] Update Phase 3 "Build Article URL" to strip `YYYY-MM-DD-` date prefix from the filename slug before constructing the URL
- [ ] Add explicit note about Eleventy `page.fileSlug` date-stripping behavior

## Phase 2: Fix existing broken URLs

### 2.1 Fix distribution content files

- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-16-soleur-vs-anthropic-cowork.md`
- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-17-soleur-vs-notion-custom-agents.md`
- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-19-soleur-vs-cursor.md`
- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-24-vibe-coding-vs-agentic-engineering.md`

## Phase 3: Add link validation script

### 3.1 Create validate-blog-links.sh

- [ ] Create `scripts/validate-blog-links.sh`
- [ ] Implement: build Eleventy site, scan distribution content for `soleur.ai/blog/` URLs, verify each against `_site/` output
- [ ] Handle both bare and UTM-parameterized URLs
- [ ] Exit non-zero on any broken link

### 3.2 Add link validation to CI

- [ ] Add `validate-blog-links.sh` to `scripts/test-all.sh` or as a dedicated CI step
- [ ] Ensure it only runs when blog or distribution content is modified (optional optimization)

### 3.3 Add link validation to content generator workflow

- [ ] Update `.github/workflows/scheduled-content-generator.yml` Step 4 to run `validate-blog-links.sh` after Eleventy build

## Phase 4: Add validation to social-distribute skill

### 4.1 Add URL verification step to social-distribute

- [ ] Add a validation step in Phase 3 of `social-distribute` SKILL.md that verifies the constructed URL resolves (build check or URL pattern check)

## Phase 5: Documentation

### 5.1 Create learning document

- [ ] Create learning in `knowledge-base/project/learnings/` documenting the Eleventy `fileSlug` date-stripping behavior and the URL construction mismatch
- [ ] Reference this plan and the affected files

## Phase 6: Testing

### 6.1 Verify fixes

- [ ] Run `npx @11ty/eleventy` and confirm all blog URLs in distribution content match build output
- [ ] Run `validate-blog-links.sh` against the fixed content and confirm all PASS
- [ ] Verify the vibe-coding article URL resolves correctly: `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/`
