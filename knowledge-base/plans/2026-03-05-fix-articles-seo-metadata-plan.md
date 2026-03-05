---
title: "fix: add SEO metadata to articles redirect page"
type: fix
date: 2026-03-05
semver: patch
---

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

The `validate-seo.sh` loop should detect `meta http-equiv="refresh"` and skip the four checks for that page, logging a `SKIP` message instead.

### Fallback: Option A

If Option C is rejected for any reason, Option A (exclude by name) is acceptable as a quick fix. It mirrors the existing `404.html` exclusion pattern.

## Implementation

### Task 1: Update validate-seo.sh to skip redirect pages

**File:** `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`

In the HTML pages loop (line 72), add a redirect detection check before the four SEO validations:

```bash
for f in "${html_files[@]}"; do
  page="${f#"$SITE_DIR"/}"

  # Skip redirect-only pages (meta http-equiv="refresh")
  if grep -qi 'meta http-equiv="refresh"' "$f"; then
    pass "$page is a redirect (skipped SEO checks)"
    continue
  fi

  # ... existing canonical, JSON-LD, og:title, twitter card checks ...
done
```

This preserves the page count in the "found N HTML page(s)" message but excludes redirects from the four mandatory checks.

### Task 2: Add test case for redirect page exclusion

**File:** `plugins/soleur/test/validate-seo.test.ts`

Add a test that creates a redirect page and verifies the script passes:

```typescript
test("passes when a redirect page is present (meta refresh)", async () => {
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
- Given: A new redirect page `_site/pages/old-page.html` is added with `meta http-equiv="refresh"`
- When: `validate-seo.sh` runs
- Then: The new redirect is also skipped automatically

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` | Add redirect detection with `continue` in HTML loop |
| `plugins/soleur/test/validate-seo.test.ts` | Add test for redirect page exclusion |

## Risks

- **Low:** `grep -qi 'meta http-equiv="refresh"'` could match a page that has a refresh tag but also has visible content. This is unlikely in practice -- meta-refresh redirects are a well-established pattern for redirect-only pages.
- **Mitigation:** The script logs `SKIP` for each redirect, making skipped pages visible in CI output for review.

## PR Labels

- `semver:patch` -- bug fix, no new features
