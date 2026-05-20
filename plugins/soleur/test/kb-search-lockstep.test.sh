#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
TOKEN="stage-2-paraphrase-union-v1"
fail=0
for f in "$REPO_ROOT/plugins/soleur/skills/kb-search/SKILL.md" "$REPO_ROOT/scripts/learning-retrieval-bench.sh"; do
  if ! grep -Fq "$TOKEN" "$f"; then
    echo "kb-search-lockstep: WARN — $TOKEN missing from $f" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] || exit 1
echo "kb-search-lockstep: ok"
