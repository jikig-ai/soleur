#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL="$REPO_ROOT/plugins/soleur/skills/kb-search/SKILL.md"
BENCH="$REPO_ROOT/scripts/learning-retrieval-bench.sh"
TOKEN="stage-2-paraphrase-union-v1"
fail=0

# Assertion 1: shared shape-token in both files.
for f in "$SKILL" "$BENCH"; do
  if ! grep -Fq "$TOKEN" "$f"; then
    echo "kb-search-lockstep: WARN — $TOKEN missing from $f" >&2
    fail=1
  fi
done

# Assertion 2: SENSITIVE_QUERY_REGEX byte-equality across SKILL.md and bench.
# The bench's regex is the source of truth (executable); SKILL.md must quote
# the same bytes so the documented guard matches the runtime guard. Extract
# the bench's regex literal and grep -F it against SKILL.md.
bench_regex=$(awk "/^SENSITIVE_QUERY_REGEX=/"' { sub(/^SENSITIVE_QUERY_REGEX=./,""); sub(/.$/,""); print; exit }' "$BENCH")
if [ -z "$bench_regex" ]; then
  echo "kb-search-lockstep: WARN — could not extract SENSITIVE_QUERY_REGEX from $BENCH" >&2
  fail=1
elif ! grep -Fq "$bench_regex" "$SKILL"; then
  echo "kb-search-lockstep: WARN — SENSITIVE_QUERY_REGEX byte-diverged between SKILL.md and bench" >&2
  echo "  bench: $bench_regex" >&2
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "kb-search-lockstep: ok"
