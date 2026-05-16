#!/usr/bin/env bash
# Fail-loud self-test for skill-security-scan.
#
# Iterates references/test-fixtures/{malicious-*,clean-*}.skill.md and asserts
# deterministic verdicts:
#   - malicious-*.skill.md  → HIGH-RISK
#   - clean-*.skill.md      → LOW-RISK
#
# Exits 1 with diagnostic if any false-negative or false-positive is observed.
# Wired into CI per .github/workflows/skill-security-scan-corpus.yml.
#
# Flags:
#   --regenerate-manifest   recompute manifest SHAs from current rule-file
#                           contents BEFORE running fixtures. Used during
#                           rule-pack development. CI rejects this flag when
#                           env CI=true (per plan SpecFlow Gap 4).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SKILL_DIR/references/test-fixtures"
MANIFEST="$SKILL_DIR/references/rules/manifest.yaml"

REGENERATE=0
if [ "${1:-}" = "--regenerate-manifest" ]; then
  if [ "${CI:-false}" = "true" ]; then
    echo "ERROR: --regenerate-manifest is rejected in CI (CI=true). See SpecFlow Gap 4." >&2
    exit 2
  fi
  REGENERATE=1
fi

if [ "$REGENERATE" = "1" ]; then
  echo "regenerating manifest SHAs..." >&2
  tmp_manifest="$(mktemp)"
  awk -v skill_dir="$SKILL_DIR/references" '
    /^[[:space:]]*-[[:space:]]*path:/ {
      path = $0
      sub(/^[[:space:]]*-[[:space:]]*path:[[:space:]]*/, "", path)
      gsub(/[[:space:]]*$/, "", path)
      print
      cmd = "sha256sum \"" skill_dir "/" path "\" | cut -d\" \" -f1"
      cmd | getline sha
      close(cmd)
      print "    sha256: " sha
      next
    }
    /^[[:space:]]+sha256:/ { next }
    { print }
  ' "$MANIFEST" > "$tmp_manifest"
  mv "$tmp_manifest" "$MANIFEST"
  echo "manifest updated. commit it alongside the rule-pack edits." >&2
fi

failures=0

# Test malicious fixtures: must be HIGH-RISK.
for fx in "$FIXTURES"/malicious-*.skill.md; do
  [ -f "$fx" ] || continue
  fx_name="$(basename "$fx")"
  out="$(bash "$SCRIPT_DIR/run-scan.sh" < "$fx" 2>/dev/null || echo "")"
  verdict="$(echo "$out" | head -1 | grep -oE 'HIGH-RISK|REVIEW|LOW-RISK' || echo "UNKNOWN")"
  if [ "$verdict" != "HIGH-RISK" ]; then
    echo "FAIL: $fx_name expected HIGH-RISK, got $verdict" >&2
    failures=$((failures + 1))
  else
    echo "ok:   $fx_name → HIGH-RISK" >&2
  fi
done

# Test clean fixtures: must be LOW-RISK.
for fx in "$FIXTURES"/clean-*.skill.md; do
  [ -f "$fx" ] || continue
  fx_name="$(basename "$fx")"
  out="$(SKILL_SECURITY_SCAN_OFFLINE=1 bash "$SCRIPT_DIR/run-scan.sh" < "$fx" 2>/dev/null || echo "")"
  verdict="$(echo "$out" | head -1 | grep -oE 'HIGH-RISK|REVIEW|LOW-RISK' || echo "UNKNOWN")"
  if [ "$verdict" != "LOW-RISK" ]; then
    echo "FAIL: $fx_name expected LOW-RISK, got $verdict" >&2
    failures=$((failures + 1))
  else
    echo "ok:   $fx_name → LOW-RISK" >&2
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "self-test FAILED: $failures fixture(s) returned wrong verdict" >&2
  exit 1
fi

echo "self-test PASSED: all fixtures returned expected verdicts" >&2
exit 0
