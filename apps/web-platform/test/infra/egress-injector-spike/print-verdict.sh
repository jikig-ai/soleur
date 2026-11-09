#!/usr/bin/env bash
# Egress injector spike (#12517) discoverability probe: prints verdict=<GO|NO-GO|INCONCLUSIVE> from the committed
# results JSON. Exits 0 on GO or NO-GO (a completed measurement), 1 on INCONCLUSIVE, a missing file, or anything else.
# It confirms that a measurement completed, not which verdict it reached. Usage: print-verdict.sh [results.json]
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../../../../.." && pwd)"
results="${1:-$repo_root/knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/injector-spike-results.json}"

if [[ ! -s "$results" ]]; then
  echo "verdict=INCONCLUSIVE"
  echo "print-verdict: no results at $results" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "verdict=INCONCLUSIVE"
  echo "print-verdict: node not found" >&2
  exit 1
fi

node "$here/verdict.mjs" "$results"
rc=$?
exit "$rc"
