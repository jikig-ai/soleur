---
title: "fix: Broken blog URLs in distribution content due to Eleventy fileSlug date-stripping"
type: fix
date: 2026-03-24
---

# fix: Broken blog URLs in distribution content due to Eleventy fileSlug date-stripping

## Enhancement Summary

**Deepened on:** 2026-03-24
**Sections enhanced:** 6
**Research sources:** Eleventy source code (`TemplateFileSlug.js`), Context7 Eleventy docs, existing learnings (5 relevant), `validate-seo.sh` pattern analysis, `content-publisher.sh` pattern analysis

### Key Improvements

1. Exact regex from Eleventy source code for date-stripping -- eliminates guesswork
2. Concrete bash implementation for `validate-blog-links.sh` based on existing `validate-seo.sh` patterns
3. Edge cases identified: non-standard date formats, nested blog directories, index files
4. UTM campaign slug also needs fixing (uses same broken path as the URL)

### New Considerations Discovered

- The UTM `utm_campaign` parameter also contains the date prefix (e.g., `utm_campaign=2026-03-24-vibe-coding-vs-agentic-engineering`), which should be stripped to match the URL slug for analytics consistency
- Eleventy's `_stripDateFromSlug` only matches dates at the START of the slug -- `my-2026-03-24-post` would NOT be stripped. The regex is anchored: `/\d{4}-\d{2}-\d{2}-(.*)/`
- The `validate-blog-links.sh` script must run from repo root (per learning: `2026-03-15-eleventy-build-must-run-from-repo-root.md`)
- Fix 6 (build site during social-distribute) is overengineered -- a regex-based URL construction fix (Fix 1) plus CI validation (Fix 5) provides the same safety without requiring a full Eleventy build during content generation

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

### Research Insights: Eleventy Source Code

The exact stripping logic lives in `node_modules/@11ty/eleventy/src/TemplateFileSlug.js`:

```javascript
/** Removes dates in the format of YYYY-MM-DD from a given slug string candidate. */
_stripDateFromSlug(slug) {
  let reg = slug.match(/\d{4}-\d{2}-\d{2}-(.*)/);
  if (reg) {
    return reg[1];
  }
  return slug;
}
```

Key behaviors:

- Only matches `YYYY-MM-DD-` at the START of the slug (the regex is not anchored with `^` but `match()` returns the first match, and since it captures `(.*)`, it greedily consumes the rest)
- Returns the slug unchanged if no date prefix is found (safe for non-dated filenames like `what-is-company-as-a-service.md`)
- Applied to both `page.fileSlug` (via `getSlug()`) and `page.filePathStem` (via `getFullPathWithoutExtension()`)

### Affected Files

| Distribution Content File | Status | Broken URL | Correct URL |
|---------------------------|--------|------------|-------------|
| `2026-03-16-soleur-vs-anthropic-cowork.md` | published | `/blog/2026-03-16-soleur-vs-anthropic-cowork/` | `/blog/soleur-vs-anthropic-cowork/` |
| `2026-03-17-soleur-vs-notion-custom-agents.md` | published | `/blog/2026-03-17-soleur-vs-notion-custom-agents/` | `/blog/soleur-vs-notion-custom-agents/` |
| `2026-03-19-soleur-vs-cursor.md` | published | `/blog/2026-03-19-soleur-vs-cursor/` | `/blog/soleur-vs-cursor/` |
| `2026-03-24-vibe-coding-vs-agentic-engineering.md` | scheduled | `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` | `/blog/vibe-coding-vs-agentic-engineering/` |

### Why It Wasn't Caught

1. The `scheduled-content-generator.yml` workflow runs `npx @11ty/eleventy` as a build validation step (Step 4), but only checks that the build succeeds -- it does not validate that URLs in distribution content match actual build output paths.
2. No link validation exists in the social-distribute skill or content-publisher pipeline.
3. Older articles (case studies, pillar pages) don't have date-prefixed filenames, so the bug only manifests with the newer content-writer output format.

## Proposed Solution

### Fix 1: Fix URL construction in `social-distribute` (skill)

Update Phase 3 "Build Article URL" in `plugins/soleur/skills/social-distribute/SKILL.md` to strip the `YYYY-MM-DD-` date prefix from the filename slug before constructing the URL, matching Eleventy's `page.fileSlug` behavior.

Current logic (Phase 3, lines 86-91):

```text
- Strip `plugins/soleur/docs/` prefix from the path
- Replace `.md` extension with `/`
- Prepend `site.url`
```

New logic:

```text
- Strip `plugins/soleur/docs/` prefix from the path
- Replace `.md` extension with `/`
- Strip YYYY-MM-DD- date prefix from the filename portion
  (match Eleventy's TemplateFileSlug._stripDateFromSlug: regex /\d{4}-\d{2}-\d{2}-(.*)/)
  Example: blog/2026-03-24-vibe-coding-vs-agentic-engineering/ -> blog/vibe-coding-vs-agentic-engineering/
- Prepend `site.url`
```

Also update the UTM campaign slug derivation (Phase 3, lines 93-94) to strip the date prefix from the campaign slug. Currently the campaign slug is derived from the URL path, so if the URL is fixed, the campaign slug is also fixed. Verify this by tracing the derivation logic.

#### Research Insights

**Exact regex to use:** The social-distribute skill instructs an LLM, not a bash script, so the instruction should say:

> "Strip any leading `YYYY-MM-DD-` date prefix from the filename portion of the path. For example, `blog/2026-03-24-my-article/` becomes `blog/my-article/`. If no date prefix exists, leave the path unchanged."

This mirrors Eleventy's behavior and handles the no-date-prefix case (older articles) correctly.

**Edge case -- non-standard dates:** Eleventy's regex matches ANY `\d{4}-\d{2}-\d{2}-` pattern, including invalid dates like `9999-99-99-`. The social-distribute fix should match the same regex, not validate dates. Matching Eleventy's behavior exactly prevents future mismatches.

### Fix 2: Fix broken URLs in existing distribution content files

Update all 4 affected distribution content files to replace the broken URLs with correct ones:

- `2026-03-16-soleur-vs-anthropic-cowork.md`: replace `/blog/2026-03-16-soleur-vs-anthropic-cowork/` with `/blog/soleur-vs-anthropic-cowork/`
- `2026-03-17-soleur-vs-notion-custom-agents.md`: replace `/blog/2026-03-17-soleur-vs-notion-custom-agents/` with `/blog/soleur-vs-notion-custom-agents/`
- `2026-03-19-soleur-vs-cursor.md`: replace `/blog/2026-03-19-soleur-vs-cursor/` with `/blog/soleur-vs-cursor/`
- `2026-03-24-vibe-coding-vs-agentic-engineering.md`: replace `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/` with `/blog/vibe-coding-vs-agentic-engineering/`

#### Research Insights

**Scope of replacement:** Each distribution content file contains the broken URL in multiple places (Discord section, X/Twitter section, IndieHackers section, Reddit section, HN section, LinkedIn Personal, LinkedIn Company, Bluesky). Use a global find-and-replace within each file -- the date prefix appears in both the URL path and the UTM campaign parameter.

**Bash approach for bulk fix:**

```bash
for file in knowledge-base/marketing/distribution-content/2026-03-{16,17,19,24}-*.md; do
  sed -i 's|/blog/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-|/blog/|g' "$file"
  # Also fix utm_campaign parameter
  sed -i 's|utm_campaign=[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-|utm_campaign=|g' "$file"
done
```

**Verification:** After replacement, grep for any remaining date-prefixed blog URLs:

```bash
grep -r 'soleur\.ai/blog/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-' knowledge-base/marketing/distribution-content/
# Should return nothing
```

### Fix 3: Add link validation script

Create `scripts/validate-blog-links.sh` that:

1. Builds the Eleventy site (`npx @11ty/eleventy`)
2. Scans all distribution content files in `knowledge-base/marketing/distribution-content/` for `soleur.ai/blog/` URLs
3. For each URL found, strips the domain and query parameters, then checks if the corresponding path exists in `_site/`
4. Reports PASS/FAIL for each URL
5. Exits non-zero if any link is broken

#### Research Insights

**Pattern to follow:** `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` uses the same PASS/FAIL reporting pattern with a `FAILURES` counter and `fail()`/`pass()` helper functions. Reuse this pattern for consistency.

**Implementation sketch:**

```bash
#!/usr/bin/env bash
# validate-blog-links.sh -- Check distribution content URLs against Eleventy build output.
# Usage: bash validate-blog-links.sh [site-dir]
# If site-dir not provided, builds the site first.
# Exit 0 = all links valid, Exit 1 = one or more broken links.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${1:-}"
CONTENT_DIR="$REPO_ROOT/knowledge-base/marketing/distribution-content"
FAILURES=0

fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# Build site if no site-dir provided
if [[ -z "$SITE_DIR" ]]; then
  echo "Building site..."
  npx @11ty/eleventy --quiet 2>/dev/null
  SITE_DIR="$REPO_ROOT/_site"
fi

if [[ ! -d "$SITE_DIR" ]]; then
  echo "ERROR: Site directory not found: $SITE_DIR"
  exit 1
fi

if [[ ! -d "$CONTENT_DIR" ]]; then
  echo "No distribution content directory found. Nothing to validate."
  exit 0
fi

# Extract all soleur.ai/blog/ URLs from distribution content
urls=()
while IFS= read -r url; do
  # Strip query parameters and trailing whitespace
  clean_url=$(echo "$url" | sed 's/?.*//' | sed 's|https\?://soleur\.ai||' | xargs)
  [[ -z "$clean_url" ]] && continue
  urls+=("$clean_url")
done < <(grep -roh 'https\?://soleur\.ai/blog/[^ )\]"]*' "$CONTENT_DIR" | sort -u)

if [[ ${#urls[@]} -eq 0 ]]; then
  echo "No blog URLs found in distribution content."
  exit 0
fi

# Deduplicate
declare -A seen
for url_path in "${urls[@]}"; do
  [[ -n "${seen[$url_path]:-}" ]] && continue
  seen[$url_path]=1

  # Check if the path exists in _site/ (as index.html)
  site_path="$SITE_DIR${url_path}index.html"
  if [[ -f "$site_path" ]]; then
    pass "$url_path"
  else
    fail "$url_path -> $site_path not found"
  fi
done

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "All blog links valid."
  exit 0
else
  echo "$FAILURES link(s) broken."
  exit 1
fi
```

**Key patterns from learnings:**

- Must run from repo root (learning: `2026-03-15-eleventy-build-must-run-from-repo-root.md`)
- Use `$((var + 1))` not `((var++))` for arithmetic under `set -euo pipefail` (learning: `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`, session error #2)
- Guard `grep` with `|| true` in pipelines under `pipefail` (same learning, session error #3)

### Fix 4: Add link validation to content generation workflow

Update `scheduled-content-generator.yml` Step 4 (Validate) to also run the link validation script after the Eleventy build, ensuring broken links are caught before the PR is created.

#### Research Insights

The current Step 4 prompt says:

```text
STEP 4 — Validate:
Build the site to verify the new article renders correctly:
npx @11ty/eleventy
If the build fails, do NOT commit.
```

Add after the build:

```text
Then validate all distribution content URLs against the build output:
bash scripts/validate-blog-links.sh _site
If any links are broken, do NOT commit. Create a GitHub issue documenting the broken links and stop.
```

This reuses the `_site` output from the Eleventy build that already ran, avoiding a duplicate build.

### Fix 5: Add link validation to CI

Add `validate-blog-links.sh` as a CI check in the test pipeline so broken links are caught on every PR that modifies blog or distribution content.

#### Research Insights

**Integration point:** Add to `scripts/test-all.sh` as a new `run_suite` entry. The script needs Node.js (for Eleventy build), which is available in CI via the `setup-node` action. The Eleventy build is fast (~0.7 seconds) so the CI overhead is minimal.

```bash
# In scripts/test-all.sh, add:
run_suite "blog-link-validation" bash scripts/validate-blog-links.sh
```

**Alternative:** Could be a separate CI job that only runs when `plugins/soleur/docs/blog/` or `knowledge-base/marketing/distribution-content/` files are modified. But given the 0.7-second build time, running on every PR is simpler and catches all regressions.

### ~~Fix 6: Add link validation to `social-distribute` skill~~ [REMOVED]

~~Add a validation step to `social-distribute` Phase 3 that builds the site and verifies the URL.~~

**Removed after review:** Running a full Eleventy build during `social-distribute` execution is overengineered. The root cause fix (Fix 1: correct URL construction) eliminates the need for runtime validation. CI validation (Fix 5) catches any future regressions. Adding a build step to a content generation skill adds latency and complexity for no additional safety.

## Acceptance Criteria

- [x] `social-distribute` skill constructs correct URLs for date-prefixed blog filenames (`plugins/soleur/skills/social-distribute/SKILL.md`)
- [x] All 4 existing distribution content files have corrected URLs (`knowledge-base/marketing/distribution-content/2026-03-{16,17,19,24}-*.md`)
- [x] `scripts/validate-blog-links.sh` exists and validates distribution content URLs against Eleventy build output
- [x] `scheduled-content-generator.yml` runs link validation before creating the PR
- [x] CI runs link validation on PRs that modify blog or distribution content
- [x] A learning document captures the Eleventy `fileSlug` date-stripping behavior and the exact regex from `TemplateFileSlug.js`

## Test Scenarios

- Given a blog file named `plugins/soleur/docs/blog/2026-03-24-test-article.md`, when `social-distribute` constructs the URL, then it produces `https://soleur.ai/blog/test-article/` (without date prefix)
- Given a blog file named `plugins/soleur/docs/blog/what-is-company-as-a-service.md` (no date prefix), when `social-distribute` constructs the URL, then it produces `https://soleur.ai/blog/what-is-company-as-a-service/` (unchanged)
- Given a distribution content file with URL `https://soleur.ai/blog/2026-03-24-fake-article/`, when `validate-blog-links.sh` runs against the Eleventy build output, then it reports FAIL for that URL
- Given a distribution content file with URL `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/`, when `validate-blog-links.sh` runs, then it reports PASS
- Given a CI run on a PR that modifies distribution content, when the link validation step runs, then broken links cause CI failure
- Given a blog file named `plugins/soleur/docs/blog/9999-99-99-edge-case.md` (invalid date but valid regex), when `social-distribute` constructs the URL, then it produces `https://soleur.ai/blog/edge-case/` (matches Eleventy behavior)
- Given `validate-blog-links.sh` is run without a pre-built `_site` directory, when it executes, then it builds the site first and validates successfully

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
- `node_modules/@11ty/eleventy/src/TemplateFileSlug.js:33-38` -- Eleventy source: `_stripDateFromSlug` regex
- `.github/workflows/scheduled-content-generator.yml` -- Content generation workflow
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` -- Existing SEO validation script (pattern to follow)
- `knowledge-base/project/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md` -- Related Eleventy learning
- `knowledge-base/project/learnings/2026-03-15-eleventy-build-must-run-from-repo-root.md` -- Build must run from repo root
- `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` -- Bash arithmetic and grep pitfalls under `set -euo pipefail`
- `knowledge-base/project/learnings/2026-03-05-seo-validator-skip-redirect-pages.md` -- SEO validator patterns
- `knowledge-base/project/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md` -- Blog post frontmatter conventions
- [Eleventy page.fileSlug documentation](https://www.11ty.dev/docs/data-eleventy-supplied)
- [Eleventy date extraction from filenames](https://www.11ty.dev/docs/dates)
