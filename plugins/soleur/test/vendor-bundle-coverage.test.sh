#!/usr/bin/env bash

# Guard 2 (#8122) — every schema-conforming vendored bundle must be enrolled
# in ALL THREE static/dynamic enforcement surfaces. A bundle that is vendored
# but unenrolled drifts silently: no lefthook pin-integrity, no PR-time
# upstream verify, no cron comparison.
#
# The enrollment predicate is THE SAME ONE the cron uses (ADR-219): a NOTICE
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
# Owns TS7's fixture dir on abnormal exit (ADR-129 rule (c)). Installed BEFORE sourcing
# test-helpers.sh, which composes a prior EXIT trap with its own sandbox cleanup; a trap set
# AFTER the source would replace that cleanup and leak the incident sandbox.
fixture_dir=""
trap 'rm -rf "${fixture_dir:-}"' EXIT
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

# Capture + herestring, not a pipe into grep -q: under pipefail the early exit can fail
# the producer (EPIPE rc 2 on CI) -> false "not covered". Ref #7005.
glob_item_contains() {
  local items
  items="$(grep -E '^[[:space:]]+-[[:space:]]' "$1" || true)"
  grep -qF -- "$2" <<<"$items"
}

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
if grep -qx "incident" <<<"$(printf '%s\n' "${NONCONFORMING[@]:-}")"; then
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

  # Scope to glob LIST ITEMS (`- "..."`) — the stanza's `run:` line also names
  # the NOTICE path (NOTICE_FILE=...) and must NOT satisfy this check: deleting
  # the glob while the run line remains has to go RED. Verified against the
  # test's own predicate: `grep -qF "$prefix/NOTICE"` alone matches both lines.
  if glob_item_contains "$LEFTHOOK" "$prefix/NOTICE"; then
    echo "  PASS: $slug NOTICE covered by a lefthook glob"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $prefix/NOTICE not covered by any lefthook glob (run: line does not count)"
    FAIL=$((FAIL + 1))
  fi

  if glob_item_contains "$LEFTHOOK" "$prefix/references/"; then
    echo "  PASS: $slug references/ covered by a lefthook glob"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $prefix/references/ not covered by any lefthook glob"
    FAIL=$((FAIL + 1))
  fi

  # The stanza must actually DO something: a `run:` line invoking
  # vendor-pin-integrity.sh that is wired to THIS bundle — either the bundle's
  # NOTICE is exported via NOTICE_FILE= (required for every non-default
  # bundle; without it the script validates the bundle's files against the
  # WRONG registry) or the script lives under the bundle's own skill dir
  # (the default bundle — its built-in NOTICE is that bundle's). `run: true`
  # or a dropped NOTICE_FILE fails here.
  run_lines="$(grep -E '^[[:space:]]+run:.*vendor-pin-integrity\.sh' "$LEFTHOOK" || true)"
  if grep -qF "NOTICE_FILE=\"$prefix/NOTICE\"" <<<"$run_lines" \
     || grep -qF "skills/$slug/scripts/vendor-pin-integrity.sh" <<<"$run_lines"; then
    echo "  PASS: $slug lefthook run: invokes vendor-pin-integrity.sh against its own NOTICE"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no run: line wires vendor-pin-integrity.sh to $slug's NOTICE"
    FAIL=$((FAIL + 1))
  fi

  # Two SEPARATE anchors, not a single prefix grep: the gate's literal
  # alternation lists each bundle's NOTICE file AND its references/ tree
  # independently, so an enrollment that anchors only the NOTICE (or only
  # references/) is under-anchored and must go RED here — a lone `$prefix/`
  # match cannot tell those apart.
  if grep -qF "$prefix/NOTICE" "$VERIFY"; then
    echo "  PASS: $slug NOTICE anchored in vendor-pin-verify.yml detect-changes"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $prefix/NOTICE absent from vendor-pin-verify.yml anchors"
    FAIL=$((FAIL + 1))
  fi
  if grep -qF "$prefix/references/" "$VERIFY"; then
    echo "  PASS: $slug references/ anchored in vendor-pin-verify.yml detect-changes"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $prefix/references/ absent from vendor-pin-verify.yml anchors"
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
# `${arr[@]:-}` expands an EMPTY array to one empty element — the loop would
# run once on slug="" and manufacture a phantom "correctly unenrolled" pass.
if ((${#NONCONFORMING[@]} == 0)); then
  echo "  FAIL: no non-conforming NOTICE found — incident/NOTICE missing or the walk broke"
  FAIL=$((FAIL + 1))
else
  for slug in "${NONCONFORMING[@]}"; do
    prefix="plugins/soleur/skills/$slug"
    if grep -qF "$prefix/NOTICE" "$LEFTHOOK" || grep -qF "$prefix/NOTICE" "$VERIFY"; then
      echo "  FAIL: $prefix/NOTICE is non-conforming but enrolled in lefthook/verify"
      FAIL=$((FAIL + 1))
    else
      echo "  PASS: $slug correctly unenrolled"
      PASS=$((PASS + 1))
    fi
  done
fi
echo ""

echo "TS7: glob_item_contains is size/timing-immune and item-scoped (#7005)"
fixture_dir="$(mktemp -d)"
big="$fixture_dir/big.yml"
decoy="$fixture_dir/decoy.yml"
needle="plugins/soleur/skills/needle-bundle/NOTICE"
awk -v n="$needle" 'BEGIN { printf "      - \"%s\"\n", n; for (i = 0; i < 6000; i++) printf "      - \"plugins/soleur/skills/filler-%05d/references/**\"\n", i }' > "$big"
printf '      run: NOTICE_FILE="%s" bash x.sh\n' "$needle" > "$decoy"
big_bytes=$(( $(wc -c < "$big") ))
# 262144 = 4x the 64 KiB pipe capacity: the old pipe shape is deterministically RED here
# (measured 30/30 false negatives at 354 KB). The floor keeps this row non-vacuous.
rc=0; { (( big_bytes >= 262144 )) && glob_item_contains "$big" "$needle"; } || rc=$?
assert_eq 0 "$rc" "needle on line 1 of a ${big_bytes}-byte (>= 262144) producer is found"
rc=0; glob_item_contains "$decoy" "$needle" || rc=$?
assert_eq 1 "$rc" "needle only on a run: line is not glob coverage"
rm -rf "$fixture_dir"
echo ""

print_results 23
