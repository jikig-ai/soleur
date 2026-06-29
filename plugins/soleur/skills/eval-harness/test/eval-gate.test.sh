#!/usr/bin/env bash
# Deterministic unit test for the eval-gate.cjs orchestrator — NO API.
# Covers the three code paths that never call promptfoo:
#   --check     gated-source lookup (true/false)
#   --dry-run   skill-arm-only API-cost disclosure (no API call)
#   no-op       candidate block == current block => {accept:true, "no gated-block change"}
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../../.." && pwd)"
GATE="$SKILL_DIR/scripts/eval-gate.cjs"
fails=0

pass() { echo "ok   [$1]"; }
fail() { echo "FAIL [$1]: $2"; fails=$((fails + 1)); }

jqget() { node -e 'const o=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(String(o[process.argv[1]]))' "$1"; }

cd "$REPO_ROOT"

# --- --check: a gated source returns gated:true + its target/block_id ---
out=$(node "$GATE" --check plugins/soleur/commands/go.md)
if [[ "$(echo "$out" | jqget gated)" == "true" && "$(echo "$out" | jqget target)" == "go-routing" && "$(echo "$out" | jqget block_id)" == "go-routing" ]]; then
  pass "--check gated source (go.md)"
else
  fail "--check gated source (go.md)" "got: $out"
fi

out=$(node "$GATE" --check plugins/soleur/agents/support/ticket-triage.md)
if [[ "$(echo "$out" | jqget gated)" == "true" && "$(echo "$out" | jqget target)" == "ticket-triage" ]]; then
  pass "--check gated source (ticket-triage.md)"
else
  fail "--check gated source (ticket-triage.md)" "got: $out"
fi

# --- --check: a non-gated file returns gated:false ---
out=$(node "$GATE" --check plugins/soleur/skills/eval-harness/README.md)
if [[ "$(echo "$out" | jqget gated)" == "false" ]]; then
  pass "--check non-gated file"
else
  fail "--check non-gated file" "got: $out"
fi

# --- --dry-run: prints estimate, dry_run:true, no API ---
out=$(node "$GATE" --dry-run --target go-routing --repeat 5)
if [[ "$(echo "$out" | jqget dry_run)" == "true" ]]; then
  calls=$(echo "$out" | jqget estimated_api_calls)
  # 2 (current+candidate) x 3 models x (7 corpus + 1 target) x 5 repeat = 240
  if [[ "$calls" == "240" ]]; then
    pass "--dry-run estimate (go-routing, repeat 5) = $calls"
  else
    fail "--dry-run estimate" "estimated_api_calls=$calls (want 240)"
  fi
else
  fail "--dry-run" "got: $out"
fi

# --- no-op: candidate-file == the source on disk (unchanged block) => accept, no API ---
out=$(node "$GATE" --target go-routing --candidate-file plugins/soleur/commands/go.md)
if [[ "$(echo "$out" | jqget accept)" == "true" && "$(echo "$out" | jqget reason)" == "no gated-block change" ]]; then
  pass "no-op (unchanged block) accepts without API"
else
  fail "no-op (unchanged block)" "got: $out"
fi

if [[ "$fails" -gt 0 ]]; then
  echo "eval-gate: $fails assertion(s) failed"
  exit 1
fi
echo "eval-gate: all assertions passed"
