---
title: "fix: Broken blog URLs in distribution content due to Eleventy fileSlug date-stripping"
type: fix
date: 2026-03-24
---

# fix: Broken blog URLs in distribution content due to Eleventy fileSlug date-stripping

## Overview

All blog articles generated since 2026-03-16 have broken 404 URLs in their distribution content (Discord, X, LinkedIn, Bluesky posts). The `social-distribute` skill constructs article URLs by naively stripping the `plugins/soleur/docs/` prefix and `.md` extension from the blog file path, but Eleventy's `page.fileSlug` strips the `YYYY-MM-DD-` date prefix from filenames. This means `plugins/soleur/docs/blog/2026-03-24-vibe-coding-vs-agentic-engineering.md` produces the URL `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` in distribution content, but the actual live URL is `/blog/vibe-coding-vs-agentic-engineering/`.

**Impact:** 4 articles affected. 3 already published with broken links to Discord, X, LinkedIn, Bluesky. 1 scheduled (vibe-coding article) with broken links queued for publishing today.

## Problem Statement

### Root Cause

Two skills are involved:

1. **`content-writer` skill** (`plugins/soleur/skills/content-writer/SKILL.md:56`): Generates blog files with date-prefixed filenames: `plugins/soleur/docs/blog/YYYY-MM-DD-<slug>.md`. This is correct for Eleventy -- date-prefixed filenames allow Eleventy to extract the date for sorting/filtering.

2. **`social-distribute` skill** (`plugins/soleur/skills/social-distribute/SKILL.md:86-92`): Phase 3 "Build Article URL" constructs the URL by stripping `plugins/soleur/docs/` and replacing `.md` with `/`. For a file named `2026-03-24-vibe-coding-vs-agentic-engineering.md`, this produces `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`.

3. **Eleventy permalink config** (`plugins/soleur/docs/blog/blog.json:4`): Uses `"permalink": "blog/{{ page.fileSlug }}/index.html"`. Eleventy's `page.fileSlug` strips the `YYYY-MM-DD-` date prefix from filenames, producing `/blog/vibe-coding-vs-agentic-engineering/`.

The mismatch: `social-distribute` assumes the URL path matches the filename, but Eleventy strips the date prefix.

### Affected Files

| Distribution Content File | Status | Correct URL |
|---------------------------|--------|-------------|
| `2026-03-16-soleur-vs-anthropic-cowork.md` | published | `/blog/soleur-vs-anthropic-cowork/` |
| `2026-03-17-soleur-vs-notion-custom-agents.md` | published | `/blog/soleur-vs-notion-custom-agents/` |
| `2026-03-19-soleur-vs-cursor.md` | published | `/blog/soleur-vs-cursor/` |
| `2026-03-24-vibe-coding-vs-agentic-engineering.md` | scheduled | `/blog/vibe-coding-vs-agentic-engineering/` |

### Why It Wasn't Caught

1. The `scheduled-content-generator.yml` workflow runs `npx @11ty/eleventy` as a build validation step (Step 4), but only checks that the build succeeds -- it does not validate that URLs in distribution content match actual build output paths.
2. No link validation exists in the social-distribute skill or content-publisher pipeline.
3. Older articles (case studies, pillar pages) don't have date-prefixed filenames, so the bug only manifests with the newer content-writer output format.

## Proposed Solution

### Fix 1: Fix URL construction in `social-distribute` (skill)

Update Phase 3 "Build Article URL" in `plugins/soleur/skills/social-distribute/SKILL.md` to strip the `YYYY-MM-DD-` date prefix from the filename slug before constructing the URL, matching Eleventy's `page.fileSlug` behavior.

Current logic (Phase 3, lines 86-91):

```
- Strip `plugins/soleur/docs/` prefix from the path
- Replace `.md` extension with `/`
- Prepend `site.url`
```

New logic:

```
- Strip `plugins/soleur/docs/` prefix from the path
- Replace `.md` extension with `/`
- Strip YYYY-MM-DD- date prefix from the filename portion (regex: /\d{4}-\d{2}-\d{2}-/)
- Prepend `site.url`
```

### Fix 2: Fix broken URLs in existing distribution content files

Update all 4 affected distribution content files to replace the broken URLs with correct ones:

- `2026-03-16-soleur-vs-anthropic-cowork.md`: replace `/blog/2026-03-16-soleur-vs-anthropic-cowork/` with `/blog/soleur-vs-anthropic-cowork/`
- `2026-03-17-soleur-vs-notion-custom-agents.md`: replace `/blog/2026-03-17-soleur-vs-notion-custom-agents/` with `/blog/soleur-vs-notion-custom-agents/`
- `2026-03-19-soleur-vs-cursor.md`: replace `/blog/2026-03-19-soleur-vs-cursor/` with `/blog/soleur-vs-cursor/`
- `2026-03-24-vibe-coding-vs-agentic-engineering.md`: replace `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` with `/blog/vibe-coding-vs-agentic-engineering/`

### Fix 3: Add link validation script

Create `scripts/validate-blog-links.sh` that:

1. Builds the Eleventy site (`npx @11ty/eleventy`)
2. Scans all distribution content files in `knowledge-base/marketing/distribution-content/` for `soleur.ai/blog/` URLs
3. For each URL found, strips the domain and query parameters, then checks if the corresponding path exists in `_site/`
4. Reports PASS/FAIL for each URL
5. Exits non-zero if any link is broken

### Fix 4: Add link validation to content generation workflow

Update `scheduled-content-generator.yml` Step 4 (Validate) to also run the link validation script after the Eleventy build, ensuring broken links are caught before the PR is created.

### Fix 5: Add link validation to CI

Add `validate-blog-links.sh` as a CI check in the test pipeline so broken links are caught on every PR that modifies blog or distribution content.

### Fix 6: Add link validation to `social-distribute` skill

Add a validation step to `social-distribute` Phase 3 that builds the site (or checks the build output if already built) and verifies the constructed URL resolves to an actual page before proceeding with content generation.

## Acceptance Criteria

- [ ] `social-distribute` skill constructs correct URLs for date-prefixed blog filenames (`plugins/soleur/skills/social-distribute/SKILL.md`)
- [ ] All 4 existing distribution content files have corrected URLs (`knowledge-base/marketing/distribution-content/2026-03-{16,17,19,24}-*.md`)
- [ ] `scripts/validate-blog-links.sh` exists and validates distribution content URLs against Eleventy build output
- [ ] `scheduled-content-generator.yml` runs link validation before creating the PR
- [ ] CI runs link validation on PRs that modify blog or distribution content
- [ ] A learning document captures the Eleventy `fileSlug` date-stripping behavior

## Test Scenarios

- Given a blog file named `plugins/soleur/docs/blog/2026-03-24-test-article.md`, when `social-distribute` constructs the URL, then it produces `https://soleur.ai/blog/test-article/` (without date prefix)
- Given a blog file named `plugins/soleur/docs/blog/what-is-company-as-a-service.md` (no date prefix), when `social-distribute` constructs the URL, then it produces `https://soleur.ai/blog/what-is-company-as-a-service/` (unchanged)
- Given a distribution content file with URL `https://soleur.ai/blog/2026-03-24-fake-article/`, when `validate-blog-links.sh` runs against the Eleventy build output, then it reports FAIL for that URL
- Given a distribution content file with URL `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/`, when `validate-blog-links.sh` runs, then it reports PASS
- Given a CI run on a PR that modifies distribution content, when the link validation step runs, then broken links cause CI failure

## Domain Review

**Domains relevant:** Marketing, Engineering

### Marketing

**Status:** reviewed
**Assessment:** Three distribution content files were already published with 404 links to Discord, X, LinkedIn, and Bluesky. These broken links damage click-through rates and brand credibility. The immediate fix (correcting URLs in distribution files) addresses future clicks from Discord (persistent messages) but cannot fix already-posted tweets/LinkedIn posts that link to 404 pages. Consider posting corrected content as reply/follow-up on X and LinkedIn for the affected articles if engagement metrics warrant it.

### Engineering

**Status:** reviewed
**Assessment:** The root cause is a mismatch between how `social-distribute` constructs URLs (filesystem path-based) and how Eleventy resolves them (`page.fileSlug` strips date prefix). The fix is straightforward: strip `YYYY-MM-DD-` from the slug during URL construction. The prevention strategy (link validation script in CI and content generator workflow) catches this class of bug structurally. No architectural concerns -- all changes are to skill instructions and bash scripts.

## References

- `plugins/soleur/skills/social-distribute/SKILL.md:86-92` -- Phase 3 URL construction (bug location)
- `plugins/soleur/skills/content-writer/SKILL.md:56` -- Default output path with date prefix
- `plugins/soleur/docs/blog/blog.json:4` -- Eleventy permalink using `page.fileSlug`
- `.github/workflows/scheduled-content-generator.yml` -- Content generation workflow
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` -- Existing SEO validation script (pattern to follow)
- `knowledge-base/project/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md` -- Related Eleventy learning
