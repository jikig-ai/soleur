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

# Enumerate every `provider "cloudflare"` block across ALL *.tf files in this
# root — Terraform merges the whole directory as one configuration, so a block
# in any sibling file is live config (precedent: jikigai-com.tf once held a
# cloudflare provider block). Blocks are recorded by brace DEPTH, never a
# column-0 `}`: an indented opener, a `{` on the next line, or a `}` not at
# column 0 must still flush the record. Each record is "file|body".
BLOCKS=()
# Top-level *.tf of this root PLUS modules/**/*.tf — a wired child module is
# live plan-time config (git-data-userdata is sourced at git-data.tf:382).
# Sibling rehearsal roots are subdirs but NOT under modules/, so they stay
# out of scope.
for tf in "$SCRIPT_DIR"/*.tf "$SCRIPT_DIR"/modules/*/*.tf; do
  [[ -e "$tf" ]] || continue
  while IFS= read -r -d '' blk; do
    BLOCKS+=("$(basename "$tf")|$blk")
  done < <(
    awk '
      /^[[:space:]]*provider[[:space:]]+"cloudflare"/ { inblk=1; blk=""; depth=0 }
      inblk {
        blk = blk $0 "\n"
        # Strip HCL line comments before depth counting: a stray { or }
        # inside a comment must never suppress the record flush.
        line = $0
        sub(/#.*/, "", line)
        sub(/\/\/.*/, "", line)
        n = gsub(/\{/, "{", line)
        m = gsub(/\}/, "}", line)
        depth += n - m
        if (depth <= 0 && (n + m) > 0) { inblk=0; printf "%s\0", blk }
      }
    ' "$tf"
  )
done

NUM_BLOCKS=${#BLOCKS[@]}

# Census floor: a block count of zero must never read green — that is the
# guard's own dispatch path (Guard Contract mutation row 3).
assert "census: at least one provider \"cloudflare\" block enumerated" \
  "[[ '$NUM_BLOCKS' -ge 1 ]]"

# *.tf.json merges into the same root configuration but uses JSON syntax the
# HCL enumerator cannot see — fail closed rather than silently miss it.
JSON_TF="$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.tf.json' -print0 | xargs -0 grep -l '"cloudflare"' 2>/dev/null || true)"
assert "census: no *.tf.json declares cloudflare provider (out-of-window syntax — needs manual review)" \
  "[[ -z '$JSON_TF' ]]"

# Generator pin: provision-cloudflare.sh emits provider blocks for new tenant
# roots — it must emit the trio too, or every generated root starts unhardened.
REPO_ROOT="$(git rev-parse --show-toplevel)"
PROV_SH="$REPO_ROOT/plugins/soleur/skills/provision-cloudflare/scripts/provision-cloudflare.sh"
for key in $EXPECTED_KEYS; do
  assert "generator: provision-cloudflare.sh emits ${key}" \
    "grep -qE '${key}[[:space:]]*=' '$PROV_SH'"
done

if [[ "$NUM_BLOCKS" -ge 1 ]]; then
  for i in "${!BLOCKS[@]}"; do
    rec="${BLOCKS[$i]}"
    src="${rec%%|*}"
    blk="${rec#*|}"
    for key in $EXPECTED_KEYS; do
      eval "default_val=\$DEFAULT_${key}"
      # Extract the attribute value; whitespace-tolerant, order-agnostic.
      val="$(printf '%s' "$blk" | grep -oE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*[0-9]+" | head -1 | grep -oE '[0-9]+$' || true)"
      assert "block $((i + 1))/$NUM_BLOCKS ($src): ${key} present and > v4 default (${default_val})" \
        "[[ -n '$val' && '$val' -gt '$default_val' ]]"
    done
  done
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
