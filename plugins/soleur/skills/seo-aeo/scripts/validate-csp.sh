#!/usr/bin/env bash
# validate-csp.sh -- Verify inline script SHA-256 hashes match the CSP meta tag.
# Usage: bash validate-csp.sh <site-dir>
# Exit 0 = all hashes match, Exit 1 = mismatch or missing CSP.

set -euo pipefail

SITE_DIR="${1:?Usage: validate-csp.sh <site-dir>}"
FAILURES=0

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS: $1"
}

INDEX="$SITE_DIR/index.html"

if [[ ! -f "$INDEX" ]]; then
  fail "index.html not found in $SITE_DIR"
  exit 1
fi

# ── Extract CSP meta tag ─────────────────────────────────────────────────────

CSP_LINE=$(grep -oP '<meta\s+http-equiv="Content-Security-Policy"\s+content="[^"]*"' "$INDEX" || true)

if [[ -z "$CSP_LINE" ]]; then
  fail "no Content-Security-Policy meta tag found in index.html"
  exit 1
fi

pass "CSP meta tag found"

# Extract script-src directive value
SCRIPT_SRC=$(echo "$CSP_LINE" | grep -oP "script-src\s+[^;]+" || true)

if [[ -z "$SCRIPT_SRC" ]]; then
  fail "no script-src directive in CSP"
  exit 1
fi

# Extract all sha256 hashes from the CSP
mapfile -t CSP_HASHES < <(echo "$SCRIPT_SRC" | grep -oP "'sha256-[A-Za-z0-9+/=]+'" | tr -d "'")

if [[ ${#CSP_HASHES[@]} -eq 0 ]]; then
  fail "no sha256 hashes found in script-src directive"
  exit 1
fi

pass "found ${#CSP_HASHES[@]} hash(es) in CSP script-src"

# ── Extract inline scripts and compute hashes ────────────────────────────────

# Use Python for reliable multi-line HTML extraction and hash computation
COMPUTED_HASHES=$(python3 -c "
import hashlib, base64, re, sys

with open('$INDEX', 'r') as f:
    content = f.read()

# Match inline <script> blocks, excluding type='application/ld+json' and src= scripts
scripts = re.findall(
    r'<script(?![^>]*(?:type=\"application/ld\+json\"|src=))[^>]*>(.*?)</script>',
    content,
    re.DOTALL
)

for script in scripts:
    h = hashlib.sha256(script.encode('utf-8')).digest()
    b64 = base64.b64encode(h).decode()
    print(f'sha256-{b64}')
")

mapfile -t INLINE_HASHES <<< "$COMPUTED_HASHES"

if [[ ${#INLINE_HASHES[@]} -eq 0 ]] || [[ -z "${INLINE_HASHES[0]}" ]]; then
  pass "no inline scripts found (nothing to validate)"
  echo ""
  echo "All CSP checks passed."
  exit 0
fi

pass "found ${#INLINE_HASHES[@]} inline script(s) in HTML"

# ── Verify every inline script hash is in the CSP ────────────────────────────

for computed in "${INLINE_HASHES[@]}"; do
  found=false
  for csp_hash in "${CSP_HASHES[@]}"; do
    if [[ "$computed" == "$csp_hash" ]]; then
      found=true
      break
    fi
  done
  if $found; then
    pass "inline script hash $computed matches CSP"
  else
    fail "inline script hash $computed NOT in CSP -- add '$computed' to script-src"
  fi
done

# ── Verify no orphan hashes in CSP ───────────────────────────────────────────

for csp_hash in "${CSP_HASHES[@]}"; do
  found=false
  for computed in "${INLINE_HASHES[@]}"; do
    if [[ "$csp_hash" == "$computed" ]]; then
      found=true
      break
    fi
  done
  if $found; then
    pass "CSP hash $csp_hash matches an inline script"
  else
    fail "orphan CSP hash $csp_hash matches no inline script -- remove from script-src"
  fi
done

# ── Prohibited directives check ──────────────────────────────────────────────

CSP_CONTENT=$(echo "$CSP_LINE" | grep -oP 'content="[^"]*"' | sed 's/content="//;s/"$//')

for directive in "strict-dynamic" "report-uri" "report-to" "frame-ancestors" "sandbox"; do
  if echo "$CSP_CONTENT" | grep -q "$directive"; then
    fail "CSP contains '$directive' which is unsupported in meta tags"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "All CSP checks passed."
  exit 0
else
  echo "$FAILURES CSP check(s) failed."
  exit 1
fi
