#!/usr/bin/env bash
# Tests for redact-linear-urls.sh — the load-bearing redaction primitive
# for the /soleur:linear-fetch skill. This is the only enforcement layer
# inside the skill (the CI grep is the durable backstop outside it).
#
# Brand-survival threshold: single-user incident (see plan
# knowledge-base/project/plans/2026-05-12-feat-linear-issue-image-context-plan.md).
# A regression here means a uploads.linear.app signed URL can leak into a
# committed artifact on a public-GitHub repo.
#
# Test fixtures use the synthesized non-routable string
# `uploads.linear.app/TEST-FIXTURE-NOT-REAL.png` per cq-test-fixtures-synthesized-only.
# Never use real Linear CDN URLs in test fixtures.
#
# Run via:  bash plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/redact-linear-urls.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

if [[ ! -x "$SCRIPT" ]] && [[ ! -r "$SCRIPT" ]]; then
  echo "ERROR: script not found at $SCRIPT" >&2
  exit 2
fi

# Helper: pipe $1 through the script, capture stdout and stderr separately.
# Sets globals OUT and ERR. Stderr-count must be an integer; we strip
# trailing whitespace.
run_redact() {
  local input="$1"
  local err_file
  err_file="$(mktemp)"
  OUT="$(printf '%s' "$input" | bash "$SCRIPT" 2>"$err_file")"
  ERR="$(cat "$err_file" | tr -d '[:space:]')"
  rm -f "$err_file"
}

# ------------------------------------------------------------------------
# Fixture 1: raw URL alone.
# ------------------------------------------------------------------------
echo "Test 1: raw URL"
run_redact "https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png"
[[ "$OUT" == "[linear-image: REDACTED]" ]] && pass "stdout" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 2: markdown image syntax ![alt](URL).
# ------------------------------------------------------------------------
echo "Test 2: markdown image"
run_redact 'before ![alt text](https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png) after'
[[ "$OUT" == "before ![alt text]([linear-image: REDACTED]) after" ]] && pass "stdout" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 3: HTML img tag with double-quoted src.
# ------------------------------------------------------------------------
echo "Test 3: HTML img tag (double quotes)"
run_redact '<img src="https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png" alt="x">'
[[ "$OUT" == '<img src="[linear-image: REDACTED]" alt="x">' ]] && pass "stdout" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 4: HTML img tag with single-quoted src.
# ------------------------------------------------------------------------
echo "Test 4: HTML img tag (single quotes)"
run_redact "<img src='https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png' alt='x'>"
expected="<img src='[linear-image: REDACTED]' alt='x'>"
[[ "$OUT" == "$expected" ]] && pass "stdout" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 5: markdown autolink <URL> — leading/trailing angle brackets.
# ------------------------------------------------------------------------
echo "Test 5: markdown autolink"
run_redact 'See <https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png> for details'
[[ "$OUT" == "See <[linear-image: REDACTED]> for details" ]] && pass "stdout" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 6: URL-encoded path (e.g., %20 for space, %2F for slash).
# ------------------------------------------------------------------------
echo "Test 6: URL-encoded path"
run_redact 'https://uploads.linear.app/folder%2Fimage%20name.png'
[[ "$OUT" == "[linear-image: REDACTED]" ]] && pass "stdout" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 7: five URLs across three lines — count must equal 5.
# ------------------------------------------------------------------------
echo "Test 7: five URLs across three lines"
multi=$'line1 https://uploads.linear.app/a.png https://uploads.linear.app/b.png\nline2 https://uploads.linear.app/c.png\nline3 https://uploads.linear.app/d.png https://uploads.linear.app/e.png'
run_redact "$multi"
# Each URL becomes [linear-image: REDACTED]
if ! printf '%s' "$OUT" | grep -q 'uploads.linear.app'; then pass "no CDN URL remains"; else fail "URL still present in: '$OUT'"; fi
[[ "$ERR" == "5" ]] && pass "count=5" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 8: zero URLs — input passes through unchanged with count=0.
# ------------------------------------------------------------------------
echo "Test 8: zero URLs"
run_redact "This text contains no Linear URLs, just SOL-39 as a reference."
[[ "$OUT" == "This text contains no Linear URLs, just SOL-39 as a reference." ]] && pass "stdout unchanged" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "0" ]] && pass "count=0" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 9: URL followed by closing bracket — markdown link-reference shape.
# The trailing `]` must NOT be consumed by the URL match.
# ------------------------------------------------------------------------
echo "Test 9: URL followed by ]"
run_redact '[![image][1]] caption: [1]: https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png'
# Either the URL is at end (no closing bracket on this line) → eat to end
# OR there's a closing bracket → bracket survives.
# Our chosen class excludes `]`, so any `]` must remain.
case "$OUT" in
  *uploads.linear.app*) fail "URL still present in: '$OUT'" ;;
  *) pass "no CDN URL remains" ;;
esac
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Fixture 10: URL followed by closing paren — markdown link shape.
# The trailing `)` must NOT be consumed.
# ------------------------------------------------------------------------
echo "Test 10: URL followed by )"
run_redact '(see [here](https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png))'
[[ "$OUT" == "(see [here]([linear-image: REDACTED]))" ]] && pass "stdout (paren preserved)" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "1" ]] && pass "count=1" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Negative-space check: a public Linear issue URL (NOT a CDN URL) MUST NOT
# be redacted. The skill's redaction is strict to `uploads.linear.app`.
# ------------------------------------------------------------------------
echo "Negative-space: public linear.app/team/issue URL"
run_redact 'See https://linear.app/jikig-ai/issue/SOL-39/title-here for context'
[[ "$OUT" == "See https://linear.app/jikig-ai/issue/SOL-39/title-here for context" ]] && pass "public URL preserved" || fail "stdout (got: '$OUT')"
[[ "$ERR" == "0" ]] && pass "count=0 (no CDN URLs)" || fail "count (got: '$ERR')"

# ------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
