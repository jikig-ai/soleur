#!/usr/bin/env bash
# validate-blog-links.sh -- Two independent checks:
#   1. Blog date-slug <-> bulk-redirect parity (Guard 1, #3328): every
#      date-prefixed post must have an edge-301 entry in
#      seo-bulk-redirects.tf. Runs FIRST — it needs neither _site nor
#      distribution content, so neither early-exit may skip it.
#   2. Distribution content URLs against Eleventy build output.
# Usage: bash scripts/validate-blog-links.sh [site-dir]
# If site-dir not provided, builds the site first.
# Exit 0 = all checks pass, Exit 1 = one or more failures.
#
# CO-LOCATION NOTE: this script's link-check half reads _site/ at the repo
# root, which plugins/soleur/test/marketing-content-drift.test.ts also builds
# (via `npm run docs:build`, inside `bun test plugins/soleur/`). Both run in
# the "bun" TEST_GROUP in scripts/test-all.sh and in the test-bun job in
# .github/workflows/ci.yml. Under matrix sharding (separate runners) each
# runner builds its own _site/; inside a runner, suites execute sequentially
# and this script self-builds when no site-dir arg is passed, so there is no
# live race today — co-location is defense in depth against any future
# xargs-P / --max-pool-size attempt that would introduce one. DO NOT move
# this script to a different TEST_GROUP than the bun-side _site builders.

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

# --- Blog date-slug <-> bulk-redirect parity (Guard 1, #3328) ---
# Every date-prefixed post under docs/blog/ must have a matching key in
# local.blog_redirect_pairs in seo-bulk-redirects.tf, and every key must map to
# a live date-prefixed file. This is the coverage property the deleted
# _data/blogRedirects.js provided at build time (a stub per date-prefixed
# file), enforced here at CI time against the canonical edge-redirect source.
# This block depends only on BLOG_DIR + TF_FILE — it runs BEFORE the
# CONTENT_DIR/SITE_DIR gates below so those early-exits can never silently
# skip it (an exit-0 that bypassed parity would be a vacuous green).
# Anti-vacuity floor: the file side must contain >=1 member or the guard fails —
# a glob that silently matches nothing must not read as "all covered".
BLOG_DIR="$REPO_ROOT/plugins/soleur/docs/blog"
TF_FILE="$REPO_ROOT/apps/web-platform/infra/seo-bulk-redirects.tf"

# File side: date-prefixed basenames (same glob class as the deleted
# DATE_PREFIX_RE — YYYY-MM-DD-slug.md). Recursive (#8364): a dated post under
# a subdirectory used to escape the one-level glob entirely — find covers any
# depth. file_paths maps slug -> path relative to BLOG_DIR so the frontmatter
# and stale-key checks below stay correct for nested posts.
file_slugs=()
declare -A file_paths=()
while IFS= read -r md_file; do
  rel="${md_file#"$BLOG_DIR"/}"
  slug="$(basename "$md_file" .md)"
  file_slugs+=("$slug")
  file_paths["$slug"]="$rel"
done < <(find "$BLOG_DIR" -type f -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md' | sort)

if [[ ${#file_slugs[@]} -eq 0 ]]; then
  fail "parity: no date-prefixed blog files found under $BLOG_DIR (guard cannot be vacuous)"
else
  pass "parity: ${#file_slugs[@]} date-prefixed blog file(s) enumerated"
fi

# The canonical URL derivation has two layers, and both must hold for the
# value-side check (expected = filename minus date prefix) to be correct:
#   1. Directory default: blog.json's permalink template computes
#      blog/{{ page.fileSlug }}/index.html. A template change moves every
#      canonical blog URL — all 69 generated edge 301s would 301 to 404s
#      while this guard stayed green.
#   2. Per-file override: a `permalink:` key in a dated post's frontmatter
#      overrides the directory default for that post.
# Pin the template literal and refuse per-file overrides (frontmatter-scoped
# — a `permalink:` line inside the markdown body is not an override).
BLOG_JSON="$BLOG_DIR/blog.json"
if ! grep -qF '"permalink": "blog/{{ page.fileSlug }}/index.html"' "$BLOG_JSON"; then
  fail "parity: blog.json permalink template changed — canonical blog URLs no longer derive from fileSlug; update blog_redirect_pairs values"
fi
for slug in "${file_slugs[@]}"; do
  fm_body="$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$BLOG_DIR/${file_paths[$slug]}")"
  if printf '%s\n' "$fm_body" | grep -qiE '^permalink\s*:'; then
    fail "parity: $slug.md sets permalink: — canonical slug is no longer filename-derived; update its redirect target manually"
  fi
done

# Shape-expansion coverage: the pairs map only reaches Cloudflare through the
# 3-arm flatten in local.blog_redirect_items plus the dynamic "item" block on
# the list resource. A dropped arm un-serves a whole URL shape per pair and a
# deleted dynamic block un-serves every generated item — both invisible to
# the key/value checks below.
# shellcheck disable=SC2016  # ${date_slug} is literal tf text, not a bash var
for arm in \
  'source = "soleur.ai/blog/${date_slug}/"' \
  'source = "soleur.ai/blog/${date_slug}/index.html"' \
  'source = "soleur.ai/blog/${date_slug}"'; do
  grep -qF "$arm" "$TF_FILE" || fail "parity: blog_redirect_items missing expansion arm: $arm"
done
grep -qE 'dynamic "item"' "$TF_FILE" || fail 'parity: cloudflare_list dynamic "item" block missing — generated redirects would vanish'

# Map side: keys + values inside the blog_redirect_pairs block (region-scoped
# extraction — a quoted-key grep elsewhere could see unrelated attributes).
declare -A map_vals=()
while IFS=' ' read -r k v; do
  map_vals["$k"]="$v"
done < <(awk '/blog_redirect_pairs[[:space:]]*=[[:space:]]*\{/{inmap=1; next}
             inmap && /^[[:space:]]*\}/{inmap=0}
             inmap' "$TF_FILE" \
         | sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*=[[:space:]]*"([^"]+)".*/\1 \2/p')

# file -> map: every date-prefixed file has a redirect entry pointing at the
# canonical slug (filename minus the YYYY-MM-DD- prefix).
for slug in "${file_slugs[@]}"; do
  if [[ -z "${map_vals[$slug]:-}" ]]; then
    fail "parity: $slug.md has no blog_redirect_pairs entry — edge 301 would be missing"
  else
    expected="${slug#????-??-??-}"
    if [[ "${map_vals[$slug]}" == "$expected" ]]; then
      pass "parity: /blog/$slug/ -> ${map_vals[$slug]}"
    else
      fail "parity: $slug maps to '${map_vals[$slug]}', expected '$expected' (filename minus date prefix)"
    fi
  fi
done

# map -> file: every key maps to a live date-prefixed file (a stale key means
# the edge redirects a URL with no backing post). Lookup goes through
# file_paths so a nested post counts the same as a top-level one.
for key in "${!map_vals[@]}"; do
  if [[ -z "${file_paths[$key]:-}" ]]; then
    fail "parity: blog_redirect_pairs key '$key' is stale — no $key.md under docs/blog/"
  fi
done

# --- Distribution-content link check ---
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

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "All checks passed."
  exit 0
else
  echo "$FAILURES check(s) failed."
  exit 1
fi
