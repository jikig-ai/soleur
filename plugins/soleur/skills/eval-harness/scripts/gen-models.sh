#!/usr/bin/env bash
# Single-source the three current Claude model IDs into models.generated.json.
#
# The model IDs live in ONE place — the TypeScript registry under
# apps/web-platform/server/inngest/. promptfoo YAML cannot import TS, so this
# generator reads the IDs VERBATIM from the registry and emits a provider list
# the promptfooconfig.*.yaml files reference via `providers: file://models.generated.json`.
# No model literal is ever hardcoded in a config-class file, which also keeps the
# model-launch-review auto-fixer from rewriting a stale literal here.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
CONST="$ROOT/apps/web-platform/server/inngest/leader-prompts/constants.ts"
TIERS="$ROOT/apps/web-platform/server/inngest/model-tiers.ts"
OUT="$HERE/../models.generated.json"

extract() { # file, exported-const-name -> the claude-* literal
  grep -E "^export const $2" "$1" | grep -oE '"claude-[^"]+"' | tr -d '"' | head -1
}

SONNET="$(extract "$CONST" "SONNET_MODEL")"
HAIKU="$(extract "$CONST" "HAIKU_MODEL")"
OPUS="$(extract "$TIERS" "AUDIT_MODEL")"

for pair in "SONNET_MODEL:$SONNET" "HAIKU_MODEL:$HAIKU" "AUDIT_MODEL:$OPUS"; do
  if [[ -z "${pair#*:}" ]]; then
    echo "gen-models: failed to read ${pair%%:*} from the registry" >&2
    exit 1
  fi
done

cat > "$OUT" <<EOF
[
  "anthropic:messages:$OPUS",
  "anthropic:messages:$SONNET",
  "anthropic:messages:$HAIKU"
]
EOF

echo "gen-models: wrote $OUT"
