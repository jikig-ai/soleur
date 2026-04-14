#!/usr/bin/env bash

# Tests for facet extraction behavior in scripts/generate-kb-index.sh.
# Run: bash plugins/soleur/test/generate-kb-index.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GEN_SCRIPT="$REPO_ROOT/scripts/generate-kb-index.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/kb-facets"

echo "=== generate-kb-index facet extraction ==="
echo ""

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Build a synthetic KB root that mirrors the real directory layout
# (knowledge-base/project/learnings/*.md). The generator accepts an explicit
# KB_DIR env var so tests can point at this synthetic root.
setup_kb() {
  local kb="$TMPDIR_BASE/kb-$1"
  mkdir -p "$kb/project/learnings"
  shift
  for fixture in "$@"; do
    cp "$FIXTURE_DIR/$fixture" "$kb/project/learnings/"
  done
  echo "$kb"
}

run_generator() {
  local kb="$1"
  KB_DIR="$kb" bash "$GEN_SCRIPT" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# TS1 — Inline form (`tags: [a, b, c]`) extracts three separate entries
# ---------------------------------------------------------------------------
echo "--- TS1: inline form extraction ---"
kb=$(setup_kb ts1 inline.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
assert_contains "$tags_out" "eager-loading" "inline: eager-loading present"
assert_contains "$tags_out" "n+1" "inline: n+1 present (literal, not regex)"
assert_contains "$tags_out" "performance" "inline: performance present"
cats_out=$(cat "$kb/kb-categories.txt")
assert_eq "performance-issues" "$cats_out" "inline: single category emitted"

# ---------------------------------------------------------------------------
# TS2 — Block form extracts same content as inline
# ---------------------------------------------------------------------------
echo ""
echo "--- TS2: block form extraction ---"
kb=$(setup_kb ts2 block.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
assert_contains "$tags_out" "eager-loading" "block: eager-loading present"
assert_contains "$tags_out" "n+1" "block: n+1 present"
assert_contains "$tags_out" "performance" "block: performance present"
cats_out=$(cat "$kb/kb-categories.txt")
assert_eq "performance-issues" "$cats_out" "block: single category emitted"

# ---------------------------------------------------------------------------
# TS3 — Malformed fixtures skipped silently (no crash, exit 0)
# ---------------------------------------------------------------------------
echo ""
echo "--- TS3: malformed frontmatter handling ---"
kb=$(setup_kb ts3 no-frontmatter.md missing-tags.md empty-tags.md)
# Must not crash — generator exits 0 even with all-malformed input
if KB_DIR="$kb" bash "$GEN_SCRIPT" >/dev/null 2>&1; then
  echo "  PASS: generator exits 0 with malformed-only corpus"
  PASS=$((PASS + 1))
else
  echo "  FAIL: generator crashed on malformed corpus"
  FAIL=$((FAIL + 1))
fi
assert_file_exists "$kb/kb-tags.txt" "malformed: kb-tags.txt still emitted (empty ok)"
assert_file_exists "$kb/kb-categories.txt" "malformed: kb-categories.txt still emitted"
# no-frontmatter.md tags like "should-not-appear" must not leak
tags_out=$(cat "$kb/kb-tags.txt")
if ! grep -q 'should-not-appear' "$kb/kb-tags.txt"; then
  echo "  PASS: body-text tags do not leak into artifact"
  PASS=$((PASS + 1))
else
  echo "  FAIL: body-text tags leaked: $tags_out"
  FAIL=$((FAIL + 1))
fi
# empty-tags.md must not emit a literal "[]" string
if ! grep -q '^\[\]$' "$kb/kb-tags.txt"; then
  echo "  PASS: empty tags array does not emit literal []"
  PASS=$((PASS + 1))
else
  echo "  FAIL: empty tags emitted as []"
  FAIL=$((FAIL + 1))
fi
# missing-tags.md still emits its category
cats_out=$(cat "$kb/kb-categories.txt")
assert_contains "$cats_out" "workflow" "malformed: category from missing-tags fixture still captured"

# ---------------------------------------------------------------------------
# TS4 — Case-fold dedup produces single entry
# ---------------------------------------------------------------------------
echo ""
echo "--- TS4: case-fold dedup ---"
kb=$(setup_kb ts4 mixed-case.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
eager_count=$(grep -c '^eager-loading$' "$kb/kb-tags.txt" || true)
assert_eq "1" "$eager_count" "mixed-case: three variants collapse to single entry"
# Category should lowercase as well
cats_out=$(cat "$kb/kb-categories.txt")
assert_eq "performance-issues" "$cats_out" "mixed-case: category lowercased"

# ---------------------------------------------------------------------------
# TS5 — Missing artifact fallback (documented behavior in kb-search SKILL)
# ---------------------------------------------------------------------------
# The generator itself always emits artifacts when run, so TS5 asserts a
# sibling invariant: removing the artifact and re-running regenerates it
# deterministically. This gives kb-search a trivial "run the generator"
# recovery path, which is what the SKILL-level error message tells agents.
echo ""
echo "--- TS5: missing artifact regenerates deterministically ---"
kb=$(setup_kb ts5 inline.md)
run_generator "$kb"
first_sum=$(sha256sum "$kb/kb-tags.txt" | awk '{print $1}')
rm "$kb/kb-tags.txt" "$kb/kb-categories.txt"
assert_file_not_exists "$kb/kb-tags.txt" "TS5: artifact removed"
run_generator "$kb"
assert_file_exists "$kb/kb-tags.txt" "TS5: artifact regenerated"
second_sum=$(sha256sum "$kb/kb-tags.txt" | awk '{print $1}')
assert_eq "$first_sum" "$second_sum" "TS5: regeneration is deterministic"

# ---------------------------------------------------------------------------
# TR6 — Best-effort extraction on dirty values, graceful skip of junk
# ---------------------------------------------------------------------------
echo ""
echo "--- TR6: dirty tag values tolerated, clean siblings still captured ---"
kb=$(setup_kb dirty dirty.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
assert_contains "$tags_out" "clean-tag" "dirty: clean sibling tag still captured"
cats_out=$(cat "$kb/kb-categories.txt")
assert_contains "$cats_out" "messy-category" "dirty: category still emitted (lowercased)"

# ---------------------------------------------------------------------------
# Artifact invariants — sorted, unique, lowercase, no blank lines
# ---------------------------------------------------------------------------
echo ""
echo "--- Invariants: sorted + unique + lowercase ---"
kb=$(setup_kb inv inline.md block.md mixed-case.md)
run_generator "$kb"
# Sorted (LC_ALL=C sort should be idempotent)
if diff <(cat "$kb/kb-tags.txt") <(LC_ALL=C sort -u "$kb/kb-tags.txt") >/dev/null; then
  echo "  PASS: kb-tags.txt sorted + unique"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kb-tags.txt not sorted or not unique"
  FAIL=$((FAIL + 1))
fi
# Lowercase only
if ! grep -qE '[A-Z]' "$kb/kb-tags.txt"; then
  echo "  PASS: kb-tags.txt lowercase only"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kb-tags.txt contains uppercase"
  FAIL=$((FAIL + 1))
fi
# No blank lines
if ! grep -qE '^$' "$kb/kb-tags.txt"; then
  echo "  PASS: kb-tags.txt no blank lines"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kb-tags.txt contains blank lines"
  FAIL=$((FAIL + 1))
fi

print_results
