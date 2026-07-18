#!/usr/bin/env bash
# Grok fidelity CI gate (Phase F #6325).
#
# Validates:
#   1. AGENTS always-loaded byte budget (lint-agents-rule-budget.py — CI test-scripts shard)
#   2. Agent compat artifacts (sync-grok-agent-compat --check)
#   3. Static + live grok inspect contract (bun tests)
#   4. Golden-path /go routing under Grok harness fixture
#
# Before `git push` under Grok Build — do not wait for CI test-scripts to fail.
#
# Usage: bash plugins/soleur/scripts/grok-fidelity-gate.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLUGIN_ROOT="$REPO_ROOT/plugins/soleur"

cd "$REPO_ROOT"

if [[ "${GROK_FIDELITY_SKIP_BUDGET:-}" != "1" ]]; then
  echo "==> AGENTS rule-budget lint (B_ALWAYS <= 23000)"
  python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
else
  echo "==> AGENTS rule-budget lint (skipped — grok-pre-push-gate already ran test-all)"
fi

# Root package.json provides shared deps (e.g. yaml for agent-registry imports).
bun install --frozen-lockfile

cd "$PLUGIN_ROOT"

echo "==> sync-grok-agent-compat --check"
bun run scripts/sync-grok-agent-compat.ts --check

echo "==> grok inspect contract + golden-path + lifecycle fidelity eval"
bun test test/grok-inspect-contract.test.ts test/go-routing-golden-path.test.ts test/workflow-fidelity.test.ts test/pr-merge-poll.test.ts

if command -v grok >/dev/null 2>&1; then
  echo "==> live grok inspect contract (CLI on PATH)"
  INSPECT_OUT="$(mktemp)"
  trap 'rm -f "$INSPECT_OUT"' EXIT
  (cd "$REPO_ROOT" && grok inspect >"$INSPECT_OUT")
  bun -e "
    import { readFileSync } from 'fs';
    import { parseGrokInspectOutput, validateGrokInspectParsed } from './lib/grok-inspect-contract.ts';
    const out = readFileSync(process.argv[1], 'utf-8');
    const parsed = parseGrokInspectOutput(out);
    const violations = validateGrokInspectParsed(parsed);
    if (violations.length) {
      console.error('grok inspect contract violations:');
      for (const v of violations) console.error('  -', v);
      process.exit(1);
    }
    console.log('grok inspect contract OK:', parsed.soleurProjectAgentCount, 'project agents,', parsed.soleurPluginSkillCount, 'plugin skills');
  " "$INSPECT_OUT"
else
  echo "WARNING: grok CLI not on PATH — static artifact tests ran; live inspect skipped"
  exit 1
fi

echo "grok-fidelity-gate: PASS"