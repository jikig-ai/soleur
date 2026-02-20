#!/usr/bin/env bash
# validate-seo.sh -- Check built Eleventy output for required SEO/AEO elements.
# Usage: bash validate-seo.sh <site-dir>
# Exit 0 = all checks pass, Exit 1 = one or more checks failed.

set -euo pipefail

SITE_DIR="${1:?Usage: validate-seo.sh <site-dir>}"
FAILURES=0

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS: $1"
}

# ── llms.txt ──────────────────────────────────────────────────────────────────

if [[ -f "$SITE_DIR/llms.txt" ]]; then
  pass "llms.txt exists"
else
  fail "llms.txt missing"
fi

# ── robots.txt AI bot access ──────────────────────────────────────────────────
# Limitation: checks only the line immediately after User-agent for Disallow.
# Multi-line stanzas with comments between directives may be misdetected.

if [[ -f "$SITE_DIR/robots.txt" ]]; then
  pass "robots.txt exists"
  for bot in GPTBot PerplexityBot ClaudeBot Google-Extended; do
    if grep -qi "User-agent: $bot" "$SITE_DIR/robots.txt" && \
       grep -A1 -i "User-agent: $bot" "$SITE_DIR/robots.txt" | grep -qiE "Disallow: /\s*$"; then
      fail "robots.txt blocks $bot"
    else
      pass "robots.txt does not block $bot"
    fi
  done
else
  fail "robots.txt missing"
fi

# ── sitemap.xml ───────────────────────────────────────────────────────────────

if [[ -f "$SITE_DIR/sitemap.xml" ]]; then
  pass "sitemap.xml exists"
  if grep -q '<lastmod>' "$SITE_DIR/sitemap.xml"; then
    pass "sitemap.xml contains lastmod dates"
  else
    fail "sitemap.xml missing lastmod dates"
  fi
else
  fail "sitemap.xml missing"
fi

# ── HTML pages ────────────────────────────────────────────────────────────────

html_files=()
while IFS= read -r -d '' f; do
  html_files+=("$f")
done < <(find "$SITE_DIR" -name '*.html' -not -name '404.html' -print0)

if [[ ${#html_files[@]} -eq 0 ]]; then
  fail "no HTML files found in $SITE_DIR"
else
  pass "found ${#html_files[@]} HTML page(s)"
fi

for f in "${html_files[@]}"; do
  page="${f#"$SITE_DIR"/}"

  # Canonical URL
  if grep -q 'rel="canonical"' "$f"; then
    pass "$page has canonical URL"
  else
    fail "$page missing canonical URL"
  fi

  # JSON-LD
  if grep -q 'application/ld+json' "$f"; then
    pass "$page has JSON-LD"
  else
    fail "$page missing JSON-LD structured data"
  fi

  # OG tags
  if grep -q 'property="og:title"' "$f"; then
    pass "$page has og:title"
  else
    fail "$page missing og:title"
  fi

  # Twitter card
  if grep -q 'name="twitter:card"' "$f"; then
    pass "$page has Twitter card"
  else
    fail "$page missing Twitter card meta tag"
  fi
done

# ── Homepage-specific: SoftwareApplication ────────────────────────────────────

if [[ -f "$SITE_DIR/index.html" ]]; then
  if grep -q '"SoftwareApplication"' "$SITE_DIR/index.html"; then
    pass "homepage has SoftwareApplication JSON-LD"
  else
    fail "homepage missing SoftwareApplication JSON-LD"
  fi
fi

# ── Changelog: build-time content ─────────────────────────────────────────────

if [[ -f "$SITE_DIR/pages/changelog.html" ]]; then
  if grep -q 'Loading changelog' "$SITE_DIR/pages/changelog.html"; then
    fail "changelog page still has client-side loading placeholder"
  else
    pass "changelog page has build-time content"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "All SEO checks passed."
  exit 0
else
  echo "$FAILURES check(s) failed."
  exit 1
fi
