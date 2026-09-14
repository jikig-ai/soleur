#!/usr/bin/env bash

# Guard 2 (#8122) — every schema-conforming vendored bundle must be enrolled
# in ALL THREE static/dynamic enforcement surfaces. A bundle that is vendored
# but unenrolled drifts silently: no lefthook pin-integrity, no PR-time
# upstream verify, no cron comparison.
#
# The enrollment predicate is THE SAME ONE the cron uses (ADR-218): a NOTICE
# enrolls its skill iff the parser reads non-empty `upstream` AND
# `pinned-commit` from it. This suite derives the conforming set with the
# real parser — not a glob — so `incident/NOTICE` (prose attribution, no
# schema) can never enroll, and a NEW conforming NOTICE cannot land without
# coverage (it would turn this suite RED, which is the intended alarm).
#
# Mutation note: weakening the predicate below to mere file-existence makes
# incident/NOTICE "conforming" — and the per-bundle coverage assertions then
# fail on it, proving the suite measures enrollment, not file presence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
CRON="$REPO_ROOT/apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts"
LEFTHOOK="$REPO_ROOT/lefthook.yml"
VERIFY="$REPO_ROOT/.github/workflows/vendor-pin-verify.yml"
SKILLS_DIR="$REPO_ROOT/plugins/soleur/skills"

echo "=== vendor-bundle-coverage (Guard 2) tests ==="
echo ""

assert_file_exists "$PARSER" "shared NOTICE parser exists"
assert_file_exists "$CRON" "cron-content-vendor-drift.ts exists"
assert_file_exists "$LEFTHOOK" "lefthook.yml exists"
assert_file_exists "$VERIFY" "vendor-pin-verify.yml exists"
echo ""

# --- Enumerate + classify every skills/*/NOTICE via the shared predicate ---
echo "TS1: classify every skills/*/NOTICE with the schema predicate"
declare -a CONFORMING=()
declare -a NONCONFORMING=()
for notice in "$SKILLS_DIR"/*/NOTICE; do
  [[ -f "$notice" ]] || continue
  slug_dir="$(dirname "$notice")"
  slug="$(basename "$slug_dir")"
  upstream="$(NOTICE_FILE="$notice" bash "$PARSER" field upstream 2>/dev/null || true)"
  pinned="$(NOTICE_FILE="$notice" bash "$PARSER" field pinned-commit 2>/dev/null || true)"
  if [[ -n "$upstream" && -n "$pinned" ]]; then
    CONFORMING+=("$slug")
    echo "  conforming: $slug ($upstream)"
  else
    NONCONFORMING+=("$slug")
    echo "  skipped (non-conforming): $slug"
  fi
done
echo ""

# --- Anti-vacuity floor: at least the two known bundles ---
echo "TS2: at least 2 schema-conforming bundles discovered (anti-vacuity floor)"
if [[ ${#CONFORMING[@]} -ge 2 ]]; then
  echo "  PASS: ${#CONFORMING[@]} conforming bundles (${CONFORMING[*]})"
  PASS=$((PASS + 1))
else
  echo "  FAIL: only ${#CONFORMING[@]} conforming bundle(s) — expected >= 2"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- incident/NOTICE must NOT conform (schema exclusion) ---
echo "TS3: incident/NOTICE is excluded by the shared predicate"
if printf '%s\n' "${NONCONFORMING[@]:-}" | grep -qx "incident"; then
  echo "  PASS: incident/NOTICE classified non-conforming (skipped)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: incident/NOTICE either enrolled or missing — predicate must exclude it"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Per-bundle coverage in each enforcement surface ---
echo "TS4: every conforming bundle is enrolled in lefthook + vendor-pin-verify + cron discovery"
for slug in "${CONFORMING[@]}"; do
  prefix="plugins/soleur/skills/$slug"

  if grep -qF "$prefix/NOTICE" "$LEFTHOOK"; then
    echo "  PASS: $slug NOTICE covered by a lefthook glob"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $prefix/NOTICE not covered by any lefthook glob"
    FAIL=$((FAIL + 1))
  fi

  if grep -qF "$prefix/references/" "$LEFTHOOK"; then
    echo "  PASS: $slug references/ covered by a lefthook glob"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $prefix/references/ not covered by any lefthook glob"
    FAIL=$((FAIL + 1))
  fi

  if grep -qF "$prefix/" "$VERIFY"; then
    echo "  PASS: $slug covered by vendor-pin-verify.yml paths"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $prefix/ absent from vendor-pin-verify.yml paths"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

# --- Cron discovery is schema-keyed, not a hardcoded bundle list ---
echo "TS5: cron enumerates bundles via schema-keyed discovery"
assert_contains "$(cat "$CRON")" 'step.run("discover-bundles"' "cron runs discovery inside a step"
assert_contains "$(cat "$CRON")" "isSchemaConformingNotice" "cron applies the schema predicate"
assert_contains "$(cat "$CRON")" "SKILLS_DIR_REL" "cron walks the skills dir, not a bundle constant"
assert_contains "$(cat "$CRON")" "NOTICE_FILE" "cron passes per-bundle NOTICE_FILE to the parser"
echo ""

# --- Skipped NOTICEs must NOT appear in enforcement surfaces ---
echo "TS6: skipped (non-conforming) NOTICEs are not enrolled anywhere"
for slug in "${NONCONFORMING[@]:-}"; do
  prefix="plugins/soleur/skills/$slug"
  if grep -qF "$prefix/NOTICE" "$LEFTHOOK" || grep -qF "$prefix/NOTICE" "$VERIFY"; then
    echo "  FAIL: $prefix/NOTICE is non-conforming but enrolled in lefthook/verify"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $slug correctly unenrolled"
    PASS=$((PASS + 1))
  fi
done
echo ""

print_results
