#!/usr/bin/env bash
# validate-blog-links.sh -- Check distribution content URLs against Eleventy build output.
# Usage: bash scripts/validate-blog-links.sh [site-dir]
# If site-dir not provided, builds the site first.
# Exit 0 = all links valid, Exit 1 = one or more broken links.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${1:-}"
[[ -n "$SITE_DIR" && "$SITE_DIR" != /* ]] && SITE_DIR="$REPO_ROOT/$SITE_DIR"
CONTENT_DIR="$REPO_ROOT/knowledge-base/marketing/distribution-content"
FAILURES=0

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS: $1"
}

# Build site if no site-dir provided
if [[ -z "$SITE_DIR" ]]; then
  echo "Building site..."
  (cd "$REPO_ROOT" && npx --yes @11ty/eleventy --quiet)
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
  # Strip query parameters and domain, trim whitespace
  clean_url=$(echo "$url" | sed 's/?.*//' | sed -E 's|https?://soleur\.ai||' | xargs)
  [[ -z "$clean_url" ]] && continue
  urls+=("$clean_url")
done < <(grep -roEh 'https?://soleur\.ai/blog/[^ )"]+' "$CONTENT_DIR" || true)

if [[ ${#urls[@]} -eq 0 ]]; then
  echo "No blog URLs found in distribution content."
  exit 0
fi

# Deduplicate and check
declare -A seen
for url_path in "${urls[@]}"; do
  [[ -n "${seen[$url_path]:-}" ]] && continue
  seen[$url_path]=1

  # Ensure trailing slash for directory-style URLs
  [[ "$url_path" != */ ]] && url_path="${url_path}/"

  # Check if the path exists in _site/ (as index.html)
  site_path="$SITE_DIR${url_path}index.html"
  if [[ -f "$site_path" ]]; then
    pass "$url_path"
  else
    fail "$url_path -> expected $site_path"
  fi
done

# --- Redirect page validation ---
# For each date-prefixed blog file, verify a redirect page exists with meta-refresh
# Date-prefix glob must match regex in plugins/soleur/docs/_data/blogRedirects.js
BLOG_DIR="$REPO_ROOT/plugins/soleur/docs/blog"
for md_file in "$BLOG_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md; do
  [[ -f "$md_file" ]] || continue
  slug=$(basename "$md_file" .md)
  redirect_path="$SITE_DIR/blog/$slug/index.html"
  if [[ -f "$redirect_path" ]]; then
    if grep -q 'http-equiv="refresh"' "$redirect_path"; then
      pass "redirect: /blog/$slug/"
    else
      fail "redirect: /blog/$slug/ exists but missing meta-refresh"
    fi
  else
    fail "redirect: /blog/$slug/ missing (expected for date-prefixed file)"
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
