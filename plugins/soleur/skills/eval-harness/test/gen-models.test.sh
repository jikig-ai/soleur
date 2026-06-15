#!/usr/bin/env bash
# Deterministic test for scripts/gen-models.sh: the generated models.generated.json
# must contain exactly the three current model IDs read VERBATIM from the TS registry
# (single source of truth), each wrapped in the `anthropic:messages:` provider prefix.
# No hardcoded model literals here — every expected value is re-derived from the registry.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
ROOT="$(git -C "$SKILL_DIR" rev-parse --show-toplevel)"
CONST="$ROOT/apps/web-platform/server/inngest/leader-prompts/constants.ts"
TIERS="$ROOT/apps/web-platform/server/inngest/model-tiers.ts"
GEN="$SKILL_DIR/scripts/gen-models.sh"
OUT="$SKILL_DIR/models.generated.json"
fails=0

# Re-derive the expected IDs from the registry (mirrors gen-models.sh extraction).
extract() { grep -E "^export const $2" "$1" | grep -oE '"claude-[^"]+"' | tr -d '"' | head -1; }
SONNET=$(extract "$CONST" "SONNET_MODEL")
HAIKU=$(extract "$CONST" "HAIKU_MODEL")
OPUS=$(extract "$TIERS" "AUDIT_MODEL")

for v in "$SONNET" "$HAIKU" "$OPUS"; do
  if [[ -z "$v" ]]; then echo "FAIL: could not read a model ID from the registry"; exit 1; fi
done

# Run the generator.
bash "$GEN"

if [[ ! -f "$OUT" ]]; then
  echo "FAIL: $OUT was not produced"; exit 1
fi

check() {
  local needle="anthropic:messages:$1"
  if node -e 'const a=require(process.argv[1]); process.exit(a.includes(process.argv[2])?0:1)' "$OUT" "$needle"; then
    echo "ok   present: $needle"
  else
    echo "FAIL missing: $needle"
    fails=$((fails + 1))
  fi
}
check "$OPUS"
check "$SONNET"
check "$HAIKU"

# Exactly three providers, no extras, no hardcoded literals leaked.
COUNT=$(node -e 'const a=require(process.argv[1]); process.stdout.write(String(a.length))' "$OUT")
if [[ "$COUNT" != "3" ]]; then
  echo "FAIL: expected 3 providers, got $COUNT"
  fails=$((fails + 1))
fi

if [[ "$fails" -gt 0 ]]; then
  echo "gen-models: $fails assertion(s) failed"
  exit 1
fi
echo "gen-models: all assertions passed"
