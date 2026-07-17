#!/usr/bin/env bash
# Unit test for scripts/dogfood/grok-measure.sh --parse-only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/dogfood/grok-measure.sh"
FIXTURE="$ROOT/scripts/dogfood/fixtures/sample-stream.ndjson"
chmod +x "$SCRIPT"

out="$(bash "$SCRIPT" --parse-only <"$FIXTURE")"

echo "$out" | jq -e '.ttft_ms == 0' >/dev/null
echo "$out" | jq -e '.output_tokens == 40' >/dev/null
echo "$out" | jq -e '.input_tokens == 100' >/dev/null
echo "$out" | jq -e '.total_cost_usd == 0.0012' >/dev/null
echo "$out" | jq -e '.session_id == "sess-test"' >/dev/null
echo "$out" | jq -e '.text_chars == 11' >/dev/null
# 40 tokens over 50ms (second text at index 1) => 40 / 0.05 = 800 tok/s
echo "$out" | jq -e '.tok_per_sec == 800' >/dev/null

# TF substrate: enable flag defaults false
grep -q 'default.*=.*false' "$ROOT/apps/web-platform/infra/variables.tf"
grep -q 'enable_grok_dogfood' "$ROOT/apps/web-platform/infra/variables.tf"
grep -q 'hcloud_server" "grok_dogfood"' "$ROOT/apps/web-platform/infra/grok-dogfood.tf"
grep -q 'count = local.grok_dogfood_enabled' "$ROOT/apps/web-platform/infra/grok-dogfood.tf"
# config-driven model (not only hard-coded install)
grep -q 'default = "grok-4.5"' "$ROOT/apps/web-platform/infra/cloud-init-grok-dogfood.yml"
grep -q 'Phase 2 placeholder' "$ROOT/apps/web-platform/infra/cloud-init-grok-dogfood.yml"
# write_files runs before users — never owner: dogfood (cloud-init getpwnam footgun)
if grep -E '^[[:space:]]*owner:[[:space:]]*dogfood' \
  "$ROOT/apps/web-platform/infra/cloud-init-grok-dogfood.yml"; then
  echo "FAIL: cloud-init write_files must not set owner: dogfood (users module is later)" >&2
  exit 1
fi

echo "PASS grok-measure.test.sh"
