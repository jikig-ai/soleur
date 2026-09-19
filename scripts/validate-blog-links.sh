#!/usr/bin/env bash
# validate-blog-links.sh -- Check distribution content URLs against Eleventy build output.
# Usage: bash scripts/validate-blog-links.sh [site-dir]
# If site-dir not provided, builds the site first.
# Exit 0 = all links valid, Exit 1 = one or more broken links.
#
# CO-LOCATION INVARIANT: this script reads _site/ which is also built by
# plugins/soleur/test/seo-aeo-drift-guard.test.ts (running inside `bun test
# plugins/soleur/`). Both run in the "bun" TEST_GROUP in scripts/test-all.sh
# and in the test-bun job in .github/workflows/ci.yml. Under matrix sharding
# (separate runners), there is no _site/ race because each runner builds its
# own _site/; co-location is a perf optimization (build once, reuse) plus
# defense in depth against any future xargs-P / --max-pool-size attempt that
# would re-introduce the race inside one runner. DO NOT move this script
# to a different TEST_GROUP than the bun-side builders.

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

# --- Blog date-slug <-> bulk-redirect parity (Guard 1, #3328) ---
# Every date-prefixed post under docs/blog/ must have a matching key in
# local.blog_redirect_pairs in seo-bulk-redirects.tf, and every key must map to
# a live date-prefixed file. This is the coverage property the deleted
# _data/blogRedirects.js provided at build time (a stub per date-prefixed
# file), enforced here at CI time against the canonical edge-redirect source.
# Anti-vacuity floor: the file side must contain >=1 member or the guard fails —
# a glob that silently matches nothing must not read as "all covered".
BLOG_DIR="$REPO_ROOT/plugins/soleur/docs/blog"
TF_FILE="$REPO_ROOT/apps/web-platform/infra/seo-bulk-redirects.tf"

# File side: date-prefixed basenames (same glob class as the deleted
# DATE_PREFIX_RE — YYYY-MM-DD-slug.md).
file_slugs=()
for md_file in "$BLOG_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md; do
  [[ -f "$md_file" ]] || continue
  file_slugs+=("$(basename "$md_file" .md)")
done

if [[ ${#file_slugs[@]} -eq 0 ]]; then
  fail "parity: no date-prefixed blog files found under $BLOG_DIR (guard cannot be vacuous)"
else
  pass "parity: ${#file_slugs[@]} date-prefixed blog file(s) enumerated"
fi

# Map side: keys + values inside the blog_redirect_pairs block (region-scoped
# extraction — a quoted-key grep elsewhere could see unrelated attributes).
declare -A map_vals=()
while IFS=' ' read -r k v; do
  [[ -n "$k" ]] && map_vals["$k"]="$v"
done < <(awk '/blog_redirect_pairs[[:space:]]*=[[:space:]]*\{/{inmap=1; next}
             inmap && /^[[:space:]]*\}/{inmap=0}
             inmap' "$TF_FILE" \
         | sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*=[[:space:]]*"([^"]+)".*/\1 \2/p')

declare -A file_set=()
for slug in "${file_slugs[@]}"; do file_set["$slug"]=1; done

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
# the edge redirects a URL with no backing post).
for key in "${!map_vals[@]}"; do
  if [[ -z "${file_set[$key]:-}" ]]; then
    fail "parity: blog_redirect_pairs key '$key' is stale — no $key.md under docs/blog/"
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
