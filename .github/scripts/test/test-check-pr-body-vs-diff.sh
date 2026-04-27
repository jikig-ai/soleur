#!/usr/bin/env bash
# Local fixture tests for the path-extraction logic in
# check-pr-body-vs-diff.sh (#2905). We can't drive the full SUT offline
# (it calls `gh pr view`/`gh pr diff`), but we can test the regex-stripping
# pipeline that produces the cited-paths list — the part most likely to
# regress.

set -uo pipefail

PASS=0
FAIL=0

# Replicates the prose-extraction pipeline from the SUT.
# When the SUT changes, update this fixture in the same PR.
extract_cited() {
  local body="$1"
  echo "$body" \
    | awk '/^```/ {f = !f; next} !f {print}' \
    | sed -E 's@https?://[^[:space:]]+@@g' \
    | grep -oE '[A-Za-z0-9_./-]+\.(ts|tsx|js|jsx|md|njk|yml|yaml|json|sh|py)' \
    | grep -E '/' \
    | sort -u || true
}

assert_contains() {
  local name="$1" body="$2" expected="$3"
  local got
  got=$(extract_cited "$body")
  if grep -Fxq "$expected" <<<"$got"; then
    echo "PASS [$name]"
    PASS=$((PASS + 1))
  else
    echo "FAIL [$name]: expected '$expected' in output"
    echo "  got: $got"
    FAIL=$((FAIL + 1))
  fi
}

assert_excludes() {
  local name="$1" body="$2" excluded="$3"
  local got
  got=$(extract_cited "$body")
  if grep -Fxq "$excluded" <<<"$got"; then
    echo "FAIL [$name]: did not expect '$excluded' in output"
    echo "  got: $got"
    FAIL=$((FAIL + 1))
  else
    echo "PASS [$name]"
    PASS=$((PASS + 1))
  fi
}

# Basic prose extraction
assert_contains "prose-path-ts" \
  "Updates apps/web-platform/server/foo.ts to fix things." \
  "apps/web-platform/server/foo.ts"

# Excludes paths inside fenced code blocks
BODY_WITH_FENCE=$'Real change in path/to/real.ts\n\n```yaml\nexample: ignored/in/fence.yml\n```\n\nMore prose.'
assert_contains "fenced-block-excludes-content" \
  "$BODY_WITH_FENCE" \
  "path/to/real.ts"
assert_excludes "fenced-block-strips-yml" \
  "$BODY_WITH_FENCE" \
  "ignored/in/fence.yml"

# Excludes URLs
assert_excludes "url-stripped" \
  "See https://example.com/path/url.json for context." \
  "example.com/path/url.json"

# Single token without slash is excluded
assert_excludes "no-slash-excluded" \
  "Updates package.json (root config)." \
  "package.json"

# Path with hyphens and dots
assert_contains "hyphens-allowed" \
  "Touches knowledge-base/overview/v-1.2.3.md somewhere." \
  "knowledge-base/overview/v-1.2.3.md"

# Multiple files, deduped+sorted
MULTI=$'Updates a/b.ts and c/d.md and a/b.ts again.'
GOT=$(extract_cited "$MULTI")
EXPECTED=$'a/b.ts\nc/d.md'
if [[ "$GOT" == "$EXPECTED" ]]; then
  echo "PASS [multi-dedup]"
  PASS=$((PASS + 1))
else
  echo "FAIL [multi-dedup]: got"
  printf '%s\n' "$GOT"
  echo "expected"
  printf '%s\n' "$EXPECTED"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
