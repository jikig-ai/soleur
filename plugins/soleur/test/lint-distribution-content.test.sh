#!/usr/bin/env bash

# Tests for scripts/lint-distribution-content.sh
# Run: bash plugins/soleur/test/lint-distribution-content.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
LINT_SCRIPT="$REPO_ROOT/scripts/lint-distribution-content.sh"

echo "=== lint-distribution-content Tests ==="
echo ""

# --- Helpers ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

write_fixture() {
  local name="$1"
  local body="$2"
  local path="$TMPDIR_BASE/$name.md"
  {
    echo "---"
    echo "title: \"$name\""
    echo "status: draft"
    echo "---"
    echo ""
    echo "$body"
  } > "$path"
  echo "$path"
}

# --- Tests ---

# Test 1: Clean file passes (exit 0)
clean=$(write_fixture "clean" "## Discord

Blog: https://soleur.ai/blog/x/?utm_source=discord")
set +e
bash "$LINT_SCRIPT" "$clean" >/dev/null 2>&1
exit_code=$?
set -e
assert_eq "0" "$exit_code" "clean file exits 0"

# Test 2: File with {{ in body fails (exit 1)
dirty_braces=$(write_fixture "dirty-braces" "## Discord

Blog: <{{ site.url }}blog/x/>")
set +e
stderr=$(bash "$LINT_SCRIPT" "$dirty_braces" 2>&1 >/dev/null)
exit_code=$?
set -e
assert_eq "1" "$exit_code" "file with {{ exits 1"
assert_contains "$stderr" "{{" "stderr reports offending marker"
assert_contains "$stderr" "$dirty_braces" "stderr includes file path"

# Test 3: File with {% tag %} in body fails
dirty_tag=$(write_fixture "dirty-tag" "## Discord

{% if foo %}bar{% endif %}")
set +e
bash "$LINT_SCRIPT" "$dirty_tag" >/dev/null 2>&1
exit_code=$?
set -e
assert_eq "1" "$exit_code" "file with {% tag exits 1"

# Test 4: File where Liquid-like braces appear only in frontmatter passes
frontmatter_only="$TMPDIR_BASE/frontmatter-braces.md"
{
  echo "---"
  echo "title: \"Frontmatter Braces\""
  echo "note: \"{{ ignored }}\""
  echo "---"
  echo ""
  echo "## Discord"
  echo ""
  echo "Clean body, no markers."
} > "$frontmatter_only"
set +e
bash "$LINT_SCRIPT" "$frontmatter_only" >/dev/null 2>&1
exit_code=$?
set -e
assert_eq "0" "$exit_code" "braces in frontmatter only exits 0 (body-scope)"

# Test 5: Multiple files — exit 1 if any is dirty, reports all offenders
set +e
stderr=$(bash "$LINT_SCRIPT" "$clean" "$dirty_braces" 2>&1 >/dev/null)
exit_code=$?
set -e
assert_eq "1" "$exit_code" "multi-file invocation with one dirty exits 1"
assert_contains "$stderr" "dirty-braces" "stderr references dirty file"

# Test 6: All clean files exit 0
set +e
bash "$LINT_SCRIPT" "$clean" "$frontmatter_only" >/dev/null 2>&1
exit_code=$?
set -e
assert_eq "0" "$exit_code" "multi-file invocation all-clean exits 0"

# Test 7: No arguments — exit 0 (nothing staged)
set +e
bash "$LINT_SCRIPT" >/dev/null 2>&1
exit_code=$?
set -e
assert_eq "0" "$exit_code" "no args exits 0 (nothing to lint)"

# Test 8: Missing file — error with non-zero exit
set +e
bash "$LINT_SCRIPT" "$TMPDIR_BASE/does-not-exist.md" >/dev/null 2>&1
exit_code=$?
set -e
[[ "$exit_code" != "0" ]] && { echo "  PASS: missing file exits non-zero"; PASS=$((PASS + 1)); } \
  || { echo "  FAIL: missing file should exit non-zero"; FAIL=$((FAIL + 1)); }

print_results
