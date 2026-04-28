#!/usr/bin/env bash
# validate-csp.sh -- Verify inline script SHA-256 hashes match the CSP meta tag.
# Usage: bash validate-csp.sh <site-dir>
# Exit 0 = all hashes match, Exit 1 = mismatch or missing CSP.
#
# Scans all HTML pages in the site directory. Each page with a CSP meta tag
# has its inline scripts extracted and hashed, then compared against the
# hashes declared in the CSP script-src directive.
#
# Depends on: python3 (for reliable multi-line HTML parsing and SHA-256 hashing)

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

# ── Collect HTML files ───────────────────────────────────────────────────────

html_files=()
while IFS= read -r -d '' f; do
  html_files+=("$f")
done < <(find "$SITE_DIR" -name '*.html' -not -name '404.html' -print0)

if [[ ${#html_files[@]} -eq 0 ]]; then
  fail "no HTML files found in $SITE_DIR"
  exit 1
fi

pass "found ${#html_files[@]} HTML page(s)"

# ── Validate each page ──────────────────────────────────────────────────────

PAGES_WITH_CSP=0

for html_file in "${html_files[@]}"; do
  page="${html_file#"$SITE_DIR"/}"

  # Skip instant meta-refresh redirects
  if grep -qiE 'meta http-equiv="refresh" content="0[;"]' "$html_file"; then
    continue
  fi

  # Use Python for all HTML parsing: extract CSP hashes, inline script hashes, AND
  # detect inline event-handler attributes (`onload=`, `onclick=`, etc.) that the
  # CSP would block but no static gate previously caught — see PR #2966 / learning
  # at knowledge-base/project/learnings/best-practices/ for the silent-failure class.
  # Passing the file path via sys.argv[1] avoids shell injection.
  RESULT=$(python3 -c "
import hashlib, base64, re, sys
from html.parser import HTMLParser

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Extract CSP meta tag
csp_match = re.search(
    r'<meta\s+http-equiv=\"Content-Security-Policy\"\s+content=\"([^\"]*)\"',
    content
)
if not csp_match:
    print('NO_CSP')
    sys.exit(0)

csp_content = csp_match.group(1)

# Extract script-src directive
src_match = re.search(r'script-src\s+([^;]+)', csp_content)
if not src_match:
    print('NO_SCRIPT_SRC')
    sys.exit(0)

script_src = src_match.group(1)

# Extract sha256 hashes from CSP
csp_hashes = set(re.findall(r\"'(sha256-[A-Za-z0-9+/=]+)'\", script_src))

# Detect whether the CSP allows inline event handlers.
allows_unsafe_inline = bool(re.search(r\"'unsafe-inline'\", script_src))
allows_unsafe_hashes = bool(re.search(r\"'unsafe-hashes'\", script_src))

# Extract inline scripts (excluding ld+json and src= scripts)
scripts = re.findall(
    r'<script(?![^>]*(?:type=\"application/ld\+json\"|src=))[^>]*>(.*?)</script>',
    content,
    re.DOTALL
)

# Compute hashes
computed_hashes = set()
for script in scripts:
    h = hashlib.sha256(script.encode('utf-8')).digest()
    b64 = base64.b64encode(h).decode()
    computed_hashes.add(f'sha256-{b64}')

# Output: CSP_HASHES|COMPUTED_HASHES (pipe-separated sets, comma-separated within)
print(','.join(sorted(csp_hashes)) + '|' + ','.join(sorted(computed_hashes)))

# Check for prohibited directives in meta tags
prohibited = ['strict-dynamic', 'report-uri', 'report-to', 'frame-ancestors', 'sandbox']
found_prohibited = [d for d in prohibited if re.search(r'(^|;\s*)' + d + r'(\s|;|$)', csp_content)]
if found_prohibited:
    print('PROHIBITED:' + ','.join(found_prohibited))

# Inline event-handler scan. Use html.parser so we naturally skip <script>
# content and HTML comments — both contained false-positives in earlier regex
# attempts (e.g., 'window.onload =' inside a <script>, or 'onload=' inside a
# <!-- comment -->).
class EventHandlerFinder(HTMLParser):
    def __init__(self):
        super().__init__()
        self.violations = []
    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name and name.lower().startswith('on') and len(name) > 2 and name[2:].isalpha():
                line, col = self.getpos()
                self.violations.append((line, tag, name, (value or '')[:80]))
    handle_startendtag = handle_starttag

if not (allows_unsafe_inline or allows_unsafe_hashes):
    finder = EventHandlerFinder()
    try:
        finder.feed(content)
    except Exception as e:
        print(f'INLINE_HANDLER_PARSE_ERROR:{e}')
    for line, tag, attr, value in finder.violations:
        # One violation per line. Bash splits on newlines.
        print(f'INLINE_HANDLER:{line}:{tag}:{attr}={value}')
" "$html_file" || true)

  # Skip pages without CSP
  if [[ "$RESULT" == "NO_CSP" ]]; then
    continue
  fi

  if [[ "$RESULT" == "NO_SCRIPT_SRC" ]]; then
    fail "$page: CSP meta tag found but no script-src directive"
    continue
  fi

  PAGES_WITH_CSP=$((PAGES_WITH_CSP + 1))

  # Parse Python output
  HASH_LINE=$(echo "$RESULT" | head -1)
  CSP_HASHES_STR="${HASH_LINE%%|*}"
  COMPUTED_HASHES_STR="${HASH_LINE#*|}"

  # Check for prohibited directives
  PROHIBITED_LINE=$(echo "$RESULT" | grep '^PROHIBITED:' || true)
  if [[ -n "$PROHIBITED_LINE" ]]; then
    directives="${PROHIBITED_LINE#PROHIBITED:}"
    fail "$page: CSP contains unsupported meta tag directive(s): $directives"
  fi

  # Check for inline event-handler attributes that CSP would silently block.
  # See PR #2966 — `<link onload="...">` was blocked by `script-src` lacking
  # `'unsafe-inline'`/`'unsafe-hashes'`, and the swap never fired in production.
  while IFS= read -r handler_line; do
    [[ -z "$handler_line" ]] && continue
    detail="${handler_line#INLINE_HANDLER:}"
    fail "$page: inline event-handler attribute '$detail' is silently blocked by script-src (no 'unsafe-inline'/'unsafe-hashes'). Move the handler into a hashed <script> block, or add 'unsafe-hashes' + a hash."
  done < <(echo "$RESULT" | grep '^INLINE_HANDLER:' || true)

  PARSE_ERR=$(echo "$RESULT" | grep '^INLINE_HANDLER_PARSE_ERROR:' || true)
  if [[ -n "$PARSE_ERR" ]]; then
    fail "$page: inline-handler parse error: ${PARSE_ERR#INLINE_HANDLER_PARSE_ERROR:}"
  fi

  # Convert to arrays
  IFS=',' read -ra csp_hashes <<< "$CSP_HASHES_STR"
  IFS=',' read -ra computed_hashes <<< "$COMPUTED_HASHES_STR"

  # Skip if no inline scripts on this page
  if [[ ${#computed_hashes[@]} -eq 0 ]] || [[ -z "${computed_hashes[0]}" ]]; then
    continue
  fi

  # Verify every inline script hash is in the CSP
  for computed in "${computed_hashes[@]}"; do
    [[ -z "$computed" ]] && continue
    found=false
    for csp_hash in "${csp_hashes[@]}"; do
      if [[ "$computed" == "$csp_hash" ]]; then
        found=true
        break
      fi
    done
    if $found; then
      pass "$page: inline script hash $computed matches CSP"
    else
      fail "$page: inline script hash $computed NOT in CSP -- add '$computed' to script-src"
    fi
  done

  # Verify no orphan hashes in CSP
  for csp_hash in "${csp_hashes[@]}"; do
    [[ -z "$csp_hash" ]] && continue
    found=false
    for computed in "${computed_hashes[@]}"; do
      if [[ "$csp_hash" == "$computed" ]]; then
        found=true
        break
      fi
    done
    if ! $found; then
      fail "$page: orphan CSP hash $csp_hash matches no inline script -- remove from script-src"
    fi
  done
done

if [[ $PAGES_WITH_CSP -eq 0 ]]; then
  fail "no pages with CSP meta tag found in $SITE_DIR"
else
  pass "validated CSP on $PAGES_WITH_CSP page(s)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "All CSP checks passed."
  exit 0
else
  echo "$FAILURES CSP check(s) failed."
  exit 1
fi
