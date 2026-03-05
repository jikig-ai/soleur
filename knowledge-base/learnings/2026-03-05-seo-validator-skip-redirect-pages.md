# Learning: SEO validator should skip instant meta-refresh redirect pages

## Problem

Deploy-docs CI failed at the "Validate SEO" step because `pages/articles.html` — an instant meta-refresh redirect — lacked canonical URL, JSON-LD, og:title, and Twitter card metadata. The page contains only `<meta http-equiv="refresh" content="0;url=/blog/">` and immediately sends users to `/blog/`.

## Solution

Added pattern-based redirect detection to `validate-seo.sh`: grep for `meta http-equiv="refresh" content="0[;"]` before the 4 SEO checks. When a match is found, the validation prints a PASS message and continues to the next file. Delayed redirects (content="5"+) are still validated per normal rules. Added positive test case (instant redirect passes) and negative test case (delayed redirect still requires SEO metadata).

## Key Insight

When CI validation fails on a new page, first check whether the page is actually indexable content. Redirect-only pages (instant meta-refresh with `content="0"`) don't need SEO metadata — Google treats `content="0"` as equivalent to a 301 redirect and doesn't index the redirect page itself. The fix belongs in the validator's scope, not the template.

Validator rules should be content-aware: instant redirects skip SEO checks (they're not indexable), but delayed redirects (which users see briefly) should still have metadata for accessibility and social sharing.

## Tags

category: build-errors
module: seo-aeo
symptoms: deploy-docs workflow fails on redirect pages lacking SEO metadata
