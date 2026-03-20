---
title: "fix: add SEO metadata to articles redirect page"
type: fix
date: 2026-03-05
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 3 (Implementation, Risks, Test Scenarios)
**Research performed:** SEO redirect best practices, grep pattern edge case analysis

### Key Improvements

1. Tightened grep pattern to only match instant redirects (`content="0"`) -- delayed meta-refresh pages with visible content are still validated
2. Added SEO context: Google treats `content="0"` meta-refresh as a permanent 301 redirect, passing full link equity to the destination
3. Added test scenario for delayed meta-refresh pages (ensures they are NOT skipped)

# Fix: Articles Page Missing SEO Metadata

## Problem

The `deploy-docs` CI workflow fails at step "Validate SEO" because `pages/articles.html` is missing four required SEO elements:

1. Canonical URL (`rel="canonical"`)
2. JSON-LD structured data (`application/ld+json`)
3. `og:title` meta tag
4. Twitter card meta tag

**Root cause:** `plugins/soleur/docs/pages/articles.njk` was introduced in commit 563c4b3 (#437) as a bare HTML meta-refresh redirect to `/blog/`. It does not use `layout: base.njk`, which is where all SEO metadata (canonical, OG, Twitter, JSON-LD) is injected for every other page.

The SEO validation script (`validate-seo.sh`) scans every `.html` file in `_site/` except `404.html`. Since `articles.njk` outputs to `_site/pages/articles.html`, it is checked and fails.

**Failed run:** <https://github.com/jikig-ai/soleur/actions/runs/22686585447>

## Analysis

### Current State

```njk
---
permalink: pages/articles.html
eleventyExcludeFromCollections: true
---
<!DOCTYPE html>
<html><head><meta http-equiv="refresh" content="0;url=/blog/"></head></html>
```

This is a redirect-only page. It has no visible content -- it immediately redirects visitors to `/blog/`. The `eleventyExcludeFromCollections: true` already keeps it out of the sitemap. However, the SEO validator still scans it because it is an `.html` file in the build output.

### Approach Options

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **A. Exclude from validator** | Add `-not -name 'articles.html'` to the `find` command in `validate-seo.sh` | Minimal change, no template work | Hard-coded exclusion, brittle if more redirects are added |
| **B. Add SEO metadata to the redirect page** | Use `layout: base.njk` or inline the required tags | Page passes all checks | Unnecessary metadata on a page no one sees |
| **C. Pattern-based exclusion** | Skip validation for pages containing `meta http-equiv="refresh"` | Self-documenting, handles future redirects automatically | Slightly more complex script change |

### Recommended: Option C (pattern-based exclusion)

Option C is the correct choice because:

- It is self-documenting -- the script skips pages that are redirects by nature, not by name
- It handles future redirect pages automatically without script changes
- It aligns with the SEO validation's purpose: redirect pages have no content to index and search engines follow the redirect
- It avoids adding unnecessary SEO metadata to a page that immediately redirects

The `validate-seo.sh` loop should detect instant meta-refresh redirects (`content="0"`) and skip the four checks for that page, logging a `PASS` message instead.

### Research Insights: SEO and Meta-Refresh Redirects

Google treats instant meta-refresh (`content="0"`) as equivalent to a permanent 301 redirect -- link equity passes to the destination URL. The redirect page itself is not indexed; the destination is canonical. This means SEO metadata on the redirect page is genuinely unnecessary, not just an optimization.

Delayed meta-refresh redirects (`content="5"` or higher) are treated as weaker signals and may result in the source page being indexed. Pages with delayed refresh AND visible content should still be validated for SEO metadata.

**References:**
- [Google: Redirects and Search](https://developers.google.com/search/docs/crawling-indexing/301-redirects) -- treats instant meta-refresh as permanent redirect
- [Conductor: Are meta refresh redirects bad for SEO?](https://www.conductor.com/academy/redirects/faq/html-meta-redirect-bad-seo/) -- instant refresh passes authority

### Fallback: Option A

If Option C is rejected for any reason, Option A (exclude by name) is acceptable as a quick fix. It mirrors the existing `404.html` exclusion pattern.

## Implementation

### Task 1: Update validate-seo.sh to skip redirect pages

**File:** `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`

In the HTML pages loop (line 72), add a redirect detection check before the four SEO validations:

```bash
for f in "${html_files[@]}"; do
  page="${f#"$SITE_DIR"/}"

  # Skip instant meta-refresh redirects (content="0;url=...")
  # Only matches content="0" (instant) -- delayed refreshes (content="5") still get validated
  if grep -qiE 'meta http-equiv="refresh" content="0[;"]' "$f"; then
    pass "$page is a redirect (skipped SEO checks)"
    continue
  fi

  # ... existing canonical, JSON-LD, og:title, twitter card checks ...
done
```

**Pattern rationale:** The regex `meta http-equiv="refresh" content="0[;"]` matches only instant redirects where `content` starts with `"0"` followed by either `;` (redirect URL) or `"` (bare refresh). This avoids false positives on delayed meta-refresh pages (`content="5;url=..."`) that may contain visible, indexable content requiring SEO metadata. The `-i` flag handles case variations in HTML attributes.

This preserves the page count in the "found N HTML page(s)" message but excludes instant redirects from the four mandatory checks.

### Task 2: Add test cases for redirect page handling

**File:** `plugins/soleur/test/validate-seo.test.ts`

Add two tests: one for instant redirect (skipped) and one for delayed redirect (still validated):

```typescript
test("passes when an instant redirect page is present (meta refresh content=0)", async () => {
  setupSite();
  writeFileSync(
    `${TMP_DIR}/pages/articles.html`,
    '<!DOCTYPE html>\n<html><head><meta http-equiv="refresh" content="0;url=/blog/"></head></html>'
  );
  const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
  const exitCode = await proc.exited;
  const stdout = await new Response(proc.stdout).text();
  expect(exitCode).toBe(0);
  expect(stdout).toContain("is a redirect (skipped SEO checks)");
});

test("fails when a delayed redirect page lacks SEO metadata (meta refresh content=5)", async () => {
  setupSite();
  writeFileSync(
    `${TMP_DIR}/pages/slow-redirect.html`,
    '<!DOCTYPE html>\n<html><head><meta http-equiv="refresh" content="5;url=/blog/"></head><body><p>Redirecting...</p></body></html>'
  );
  const proc = Bun.spawn(["bash", SCRIPT, TMP_DIR], { stdout: "pipe", stderr: "pipe" });
  const exitCode = await proc.exited;
  const stdout = await new Response(proc.stdout).text();
  expect(exitCode).toBe(1);
  expect(stdout).toContain("slow-redirect.html missing canonical URL");
});
```

### Task 3: Verify the fix locally

Build the docs site and run the validator:

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/fix-articles-seo
npm install && npx @11ty/eleventy
bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site
```

Confirm:
- Exit code is 0
- Output shows `PASS: pages/articles.html is a redirect (skipped SEO checks)`
- All other pages still pass their four checks

### Task 4: Run existing test suite

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/fix-articles-seo
bun test plugins/soleur/test/validate-seo.test.ts
```

Confirm all tests pass, including the new redirect test.

## Non-Goals

- Refactoring articles.njk to use `layout: base.njk` (it is a redirect, not a content page)
- Fixing the wildcard User-agent limitation in validate-seo.sh (tracked separately)
- Adding more redirect pages -- this fix handles future redirects automatically

## Test Scenarios

### Given/When/Then

**Scenario 1: Redirect page skipped during validation**
- Given: `_site/pages/articles.html` contains `meta http-equiv="refresh"`
- When: `validate-seo.sh` runs
- Then: The page is logged as "redirect (skipped SEO checks)" and the script exits 0

**Scenario 2: Non-redirect pages still validated**
- Given: `_site/pages/changelog.html` does not contain `meta http-equiv="refresh"`
- When: `validate-seo.sh` runs
- Then: All four SEO checks (canonical, JSON-LD, og:title, twitter:card) are applied

**Scenario 3: CI deploy-docs passes**
- Given: The fix is merged to main
- When: deploy-docs workflow triggers
- Then: Step "Validate SEO" passes, deployment completes

**Scenario 4: Future redirect pages auto-handled**
- Given: A new redirect page `_site/pages/old-page.html` is added with `meta http-equiv="refresh" content="0;url=/new-page/"`
- When: `validate-seo.sh` runs
- Then: The new redirect is also skipped automatically

**Scenario 5: Delayed meta-refresh pages are still validated**
- Given: `_site/pages/slow-redirect.html` contains `meta http-equiv="refresh" content="5;url=/blog/"` and visible content
- When: `validate-seo.sh` runs
- Then: All four SEO checks are applied (page is NOT skipped because the redirect is delayed)

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` | Add redirect detection with `continue` in HTML loop |
| `plugins/soleur/test/validate-seo.test.ts` | Add test for redirect page exclusion |

## Risks

- **Low (mitigated by pattern tightening):** The original broad pattern `grep -qi 'meta http-equiv="refresh"'` would match delayed meta-refresh pages (e.g., `content="5"`) that have visible content and need SEO metadata. The tightened pattern `content="0[;"]` only matches instant redirects, eliminating this false positive.
- **Negligible:** A page could have `content="0"` meta-refresh alongside visible content. This is a degenerate case -- instant redirects leave no time for users to see content. The CI log shows every skipped page for manual review.
- **Mitigation:** The script logs `PASS: ... is a redirect (skipped SEO checks)` for each skipped page, making exclusions visible in CI output.

## PR Labels

- `semver:patch` -- bug fix, no new features
