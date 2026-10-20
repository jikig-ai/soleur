#!/usr/bin/env bash
# Drift guard: every `provider "cloudflare"` block in main.tf must carry the
# v4 retry-policy trio set ABOVE the v4 defaults, so the Cloudflare API 5xx
# retry budget cannot silently re-shallow to ~7s/request (#10643).
#
# Why this suite exists: `terraform validate` refuses unknown attribute NAMES
# but accepts a dropped optional attribute silently — only a content guard
# pins presence + above-default values. See the plan's Guard Contract
# (knowledge-base/project/plans/2026-10-20-fix-apply-web-platform-infra-cf-504-retry-plan.md).
#
# v4 spellings are load-bearing: `retries`, `min_backoff`, `max_backoff`.
# The v5 provider renames the knob to `max_retries` — the schema-probe AC in
# the plan pins this suite's expected-name set to the locked 4.52.7 schema.
# A v5 migration must update BOTH the blocks and this suite's expected list.
#
# Auto-registered by run-registered-suites.sh's filesystem glob (ADR-252).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_TF="$SCRIPT_DIR/main.tf"

PASS=0
FAIL=0
TOTAL=0

assert() {
  local description="$1"
  local condition="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$condition"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        condition: $condition"
  fi
}

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# Expected retry-policy attributes and their v4 defaults. A block counts as
# hardened only when every attribute is present AND strictly above default.
EXPECTED_KEYS="retries min_backoff max_backoff"
DEFAULT_retries=3
DEFAULT_min_backoff=1
DEFAULT_max_backoff=30

# Enumerate every top-level `provider "cloudflare" { ... }` block. Providers
# are top-level blocks: the closing `}` sits at column 0. awk emits one
# NUL-separated record per block body.
BLOCKS=()
while IFS= read -r -d '' blk; do
  BLOCKS+=("$blk")
done < <(
  awk '
    /^provider "cloudflare"[[:space:]]*\{/ { inblk=1; blk=""; next }
    inblk && /^\}/ { inblk=0; printf "%s\0", blk; next }
    inblk { blk = blk $0 "\n" }
  ' "$MAIN_TF" || true
)

NUM_BLOCKS=${#BLOCKS[@]}

# Census floor: a block count of zero must never read green — that is the
# guard's own dispatch path (Guard Contract mutation row 3).
assert "census: at least one provider \"cloudflare\" block enumerated" \
  "[[ '$NUM_BLOCKS' -ge 1 ]]"

if [[ "$NUM_BLOCKS" -ge 1 ]]; then
  for i in "${!BLOCKS[@]}"; do
    blk="${BLOCKS[$i]}"
    for key in $EXPECTED_KEYS; do
      eval "default_val=\$DEFAULT_$key"
      # Extract the attribute value; whitespace-tolerant, order-agnostic.
      val="$(printf '%s' "$blk" | grep -oE "^[[:space:]]*$key[[:space:]]*=[[:space:]]*[0-9]+" | head -1 | grep -oE '[0-9]+$' || true)"
      assert "block $((i + 1))/$NUM_BLOCKS: $key present and > v4 default ($default_val)" \
        "[[ -n '$val' && '$val' -gt '$default_val' ]]"
    done
  done
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
