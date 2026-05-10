#!/usr/bin/env bash

# Tests for plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh.
# Run: bash plugins/soleur/test/notice-frontmatter.test.sh
#
# Subcommands under test:
#   field <name>      — print frontmatter scalar value (upstream, pinned-commit,
#                       last-verified, registry).
#   days-stale        — integer days since last-verified. Future date / parse
#                       fail / missing frontmatter all return 999 (treat as
#                       stale immediately). Always exits 0.
#   lifted-files      — one `<path>:<blob-sha>` per line.
#
# NOTICE_FILE env var overrides the default NOTICE path so tests can swap in
# fixtures without touching the live skill NOTICE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
LIVE_NOTICE="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/NOTICE"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/vendor-drift"

echo "=== notice-frontmatter tests ==="
echo ""

assert_file_exists "$PARSER" "notice-frontmatter.sh exists"
assert_file_exists "$LIVE_NOTICE" "live NOTICE exists (frontmatter source of truth)"

# --- TS1: field upstream against live NOTICE ---
echo "TS1: field upstream returns the canonical upstream"
OUT=$(bash "$PARSER" field upstream)
assert_eq "github.com/goSprinto/compliance-skills" "$OUT" "field upstream is correct"
echo ""

# --- TS2: field pinned-commit ---
echo "TS2: field pinned-commit returns the 40-char SHA"
OUT=$(bash "$PARSER" field pinned-commit)
assert_eq "7b58d68461cb1fc033a063e34cc9de63d0b4144b" "$OUT" "field pinned-commit is correct"
echo ""

# --- TS3: field last-verified ---
echo "TS3: field last-verified returns ISO date"
OUT=$(bash "$PARSER" field last-verified)
assert_eq "2026-05-10" "$OUT" "field last-verified is correct"
echo ""

# --- TS4: lifted-files emits 5 path:sha lines ---
# lifted-files emits LOCAL blob SHAs (consumed by lefthook integrity gate);
# upstream-files emits UPSTREAM blob SHAs (consumed by drift workflow).
echo "TS4a: lifted-files prints 5 entries in <path>:<local-blob-sha> form"
OUT=$(bash "$PARSER" lifted-files)
LINE_COUNT=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
assert_eq "5" "$LINE_COUNT" "lifted-files emits 5 lines"
assert_contains "$OUT" "references/fields.md:68675dd747fcbc74bb84c99eaa14983c9c5a6b24" "fields.md local-sha line present"
assert_contains "$OUT" "references/leakage-vectors.md:8d1d7fc44183e866e128707c3e91e7b63ce835fd" "leakage-vectors.md local-sha line present"
assert_contains "$OUT" "references/layers/api-layer.md:802fc866e320bebeecae2f8e53658253853ab5f9" "api-layer.md local-sha line present"
assert_contains "$OUT" "references/layers/data-in-transit.md:2ce203e9c041c1b1992ff9f7f636fdd63a667a44" "data-in-transit.md local-sha line present"
assert_contains "$OUT" "references/layers/data-lifecycle.md:29357a020bfa0e61f91dd529070fe3eb7cd251da" "data-lifecycle.md local-sha line present"
echo ""

echo "TS4b: upstream-files prints 5 entries in <upstream-path>:<upstream-blob-sha> form"
OUT=$(bash "$PARSER" upstream-files)
LINE_COUNT=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
assert_eq "5" "$LINE_COUNT" "upstream-files emits 5 lines"
assert_contains "$OUT" "pii-detector/patterns/fields.md:c1bb748fe00a53b283efe66ec937fa39437d2efc" "fields.md upstream line present"
assert_contains "$OUT" "pii-detector/rules/leakage-vectors.md:15a46e529e789930149f4b9bce875bfe5c53e478" "leakage-vectors.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/api-layer.md:9d3202175c1d0225f60a912c489dbdacf4df491c" "api-layer.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/data-in-transit.md:6c9eeabf17d1f0ed5660f5eb54d91587c81214ef" "data-in-transit.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/data-lifecycle.md:a073ef24a0527c2c3a6d738b65ea3ef9d6194abe" "data-lifecycle.md upstream line present"
echo ""

# --- TS5: days-stale against live NOTICE prints non-negative integer ---
echo "TS5: days-stale prints a non-negative integer for the live NOTICE"
OUT=$(bash "$PARSER" days-stale)
if [[ "$OUT" =~ ^[0-9]+$ ]]; then
  echo "  PASS: days-stale prints integer ($OUT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: days-stale did not print integer (got: '$OUT')"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- TS6: missing NOTICE → 999 (stale-immediately fallback) ---
echo "TS6: missing NOTICE returns 999 from days-stale"
TMP_MISSING="$(mktemp)"
rm -f "$TMP_MISSING"  # ensure absent
OUT=$(NOTICE_FILE="$TMP_MISSING" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 when NOTICE is missing"
echo ""

# --- TS7: malformed-YAML NOTICE → 999 ---
echo "TS7: malformed-YAML NOTICE returns 999 from days-stale"
TMP_MALFORMED="$(mktemp)"
cat > "$TMP_MALFORMED" <<'EOF'
---
upstream: github.com/goSprinto/compliance-skills
pinned-commit
last-verified 2026-05-10
EOF
OUT=$(NOTICE_FILE="$TMP_MALFORMED" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 on malformed frontmatter (no closing ---, missing colons)"
rm -f "$TMP_MALFORMED"
echo ""

# --- TS8: future-dated NOTICE → 999 (per SpecFlow P1.5) ---
echo "TS8: future-dated NOTICE returns 999 from days-stale"
FUTURE_FIXTURE="$FIXTURES_DIR/notice-future-dated.frontmatter"
assert_file_exists "$FUTURE_FIXTURE" "notice-future-dated.frontmatter fixture exists"
OUT=$(NOTICE_FILE="$FUTURE_FIXTURE" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 when last-verified is in the future"
echo ""

# --- TS9: missing frontmatter (no opening ---) → 999 ---
echo "TS9: NOTICE without frontmatter returns 999 from days-stale"
TMP_NOFM="$(mktemp)"
cat > "$TMP_NOFM" <<'EOF'
# NOTICE

This file has no frontmatter, only markdown body.
EOF
OUT=$(NOTICE_FILE="$TMP_NOFM" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 when frontmatter is absent"
rm -f "$TMP_NOFM"
echo ""

# --- TS10: parser exit code is 0 even on failure paths (advisory contract) ---
echo "TS10: parser exits 0 on missing/malformed input (advisory contract preserved)"
TMP_GONE="$(mktemp)"
rm -f "$TMP_GONE"
set +e
NOTICE_FILE="$TMP_GONE" bash "$PARSER" days-stale >/dev/null 2>&1
RC=$?
set -e
assert_eq "0" "$RC" "exit 0 when NOTICE missing (so subshell-exec from gdpr-gate.sh stays advisory)"
echo ""

# --- TS11: timing — p95 < 50ms across 100 invocations of days-stale ---
echo "TS11: p95 < 50ms over 100 invocations of days-stale"
TIMINGS_FILE="$(mktemp)"
for _ in $(seq 1 100); do
  # Capture wall-clock ms via /usr/bin/time -f "%e" (seconds with 2 decimal
  # places). Multiply by 1000, round to integer.
  SECS=$( { /usr/bin/time -f "%e" bash "$PARSER" days-stale >/dev/null ; } 2>&1 )
  printf '%s\n' "$SECS"
done > "$TIMINGS_FILE"
# Convert to integer milliseconds, sort, pick p95 (95th percentile = 95th of
# 100 sorted ascending).
P95_MS=$(awk '{printf "%d\n", $1*1000}' "$TIMINGS_FILE" | sort -n | awk 'NR==95')
echo "  p95: ${P95_MS}ms (over 100 runs)"
if (( P95_MS < 50 )); then
  echo "  PASS: p95 < 50ms"
  PASS=$((PASS + 1))
else
  echo "  FAIL: p95 >= 50ms (TR2 budget breached)"
  FAIL=$((FAIL + 1))
fi
rm -f "$TIMINGS_FILE"
echo ""

print_results
