# Tasks: fix-404-link-validation

## Phase 1: Fix social-distribute URL construction

### 1.1 Update Phase 3 in social-distribute SKILL.md

- [ ] Read `plugins/soleur/skills/social-distribute/SKILL.md`
- [ ] Update Phase 3 "Build Article URL" to strip `YYYY-MM-DD-` date prefix from the filename slug before constructing the URL (match Eleventy's `TemplateFileSlug._stripDateFromSlug` regex: `/\d{4}-\d{2}-\d{2}-(.*)/`)
- [ ] Add explicit note about Eleventy `page.fileSlug` date-stripping behavior with source reference to `TemplateFileSlug.js`
- [ ] Verify UTM campaign slug derivation also strips the date prefix (traces from the URL path)

## Phase 2: Fix existing broken URLs

### 2.1 Fix distribution content files

- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-16-soleur-vs-anthropic-cowork.md` (global replace both URL path and utm_campaign)
- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-17-soleur-vs-notion-custom-agents.md`
- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-19-soleur-vs-cursor.md`
- [ ] Fix URLs in `knowledge-base/marketing/distribution-content/2026-03-24-vibe-coding-vs-agentic-engineering.md`
- [ ] Verify no remaining date-prefixed blog URLs: `grep -r 'soleur\.ai/blog/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-' knowledge-base/marketing/distribution-content/`

## Phase 3: Add link validation script

### 3.1 Create validate-blog-links.sh

- [ ] Create `scripts/validate-blog-links.sh` following `validate-seo.sh` PASS/FAIL pattern
- [ ] Implement: build Eleventy site (or accept pre-built `_site` as argument), scan distribution content for `soleur.ai/blog/` URLs, verify each against `_site/` output
- [ ] Handle both bare and UTM-parameterized URLs (strip query params before path check)
- [ ] Use `$((var + 1))` not `((var++))` for arithmetic under `set -euo pipefail`
- [ ] Exit non-zero on any broken link

### 3.2 Add link validation to CI

- [ ] Add `run_suite "blog-link-validation" bash scripts/validate-blog-links.sh` to `scripts/test-all.sh`

### 3.3 Add link validation to content generator workflow

- [ ] Update `.github/workflows/scheduled-content-generator.yml` Step 4 to run `bash scripts/validate-blog-links.sh _site` after Eleventy build (reuse existing `_site` output)

## Phase 4: Documentation

### 4.1 Create learning document

- [ ] Create learning in `knowledge-base/project/learnings/` documenting the Eleventy `fileSlug` date-stripping behavior
- [ ] Include the exact regex from `TemplateFileSlug.js`: `/\d{4}-\d{2}-\d{2}-(.*)/`
- [ ] Document that `social-distribute` URL construction must match Eleventy permalink resolution
- [ ] Reference this plan and the affected files

## Phase 5: Testing

### 5.1 Verify fixes

- [ ] Run `npx @11ty/eleventy` and confirm all blog URLs in distribution content match build output
- [ ] Run `bash scripts/validate-blog-links.sh` against the fixed content and confirm all PASS
- [ ] Verify the vibe-coding article URL resolves correctly: `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/`
- [ ] Verify a non-date-prefixed article URL still works: `https://soleur.ai/blog/what-is-company-as-a-service/`
