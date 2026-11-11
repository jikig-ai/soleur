#!/usr/bin/env bash
# Egress injector spike (#12517) discoverability probe: prints verdict=<GO|NO-GO|INCONCLUSIVE> from the committed
# results JSON. Exits 0 on GO or NO-GO (a completed measurement), 1 on INCONCLUSIVE, a missing file, or anything else.
# It confirms that a measurement completed, not which verdict it reached. Usage: print-verdict.sh [results.json]
#
# With no argument it reads the live spec directory's results, else the single archived copy (ship's archive step
# moves the spec directory to knowledge-base/project/specs/archive/<timestamp>-feat-agent-runtime-sandbox-eval/),
# and exits 2 when neither (or more than one archived copy) exists.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../../../../.." && pwd)"
specs="$repo_root/knowledge-base/project/specs"
name="feat-agent-runtime-sandbox-eval/injector-spike-results.json"

if [[ $# -ge 1 ]]; then
  results="$1"
elif [[ -e "$specs/$name" ]]; then
  results="$specs/$name"
else
  shopt -s nullglob
  archived=("$specs"/archive/*-"$name")
  shopt -u nullglob
  if [[ ${#archived[@]} -eq 1 ]]; then
    results="${archived[0]}"
  else
    echo "verdict=INCONCLUSIVE"
    echo "print-verdict: no results at $specs/$name and ${#archived[@]} archived copies (need exactly one); pass the path" >&2
    exit 2
  fi
fi

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
