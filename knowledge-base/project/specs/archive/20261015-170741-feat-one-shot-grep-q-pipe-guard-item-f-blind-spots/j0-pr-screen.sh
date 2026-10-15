#!/usr/bin/env bash
# Open-PR screen (Phase 0.3): added lines of every open PR in a newly read file class, run through the widened pattern.
set -u
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git -C "$H" rev-parse --show-toplevel)" || exit 9
PROTO="$H/j0-pattern-prototype.sh"
# shellcheck disable=SC1090
eval "$(sed -n '/^TOK=/,/^NEW=/p' "$PROTO")"
for n in $(gh pr list --state open -L 100 --json number --jq '.[].number'); do
  files=$(gh pr diff "$n" --name-only 2>/dev/null | grep -E '\.(ts|tsx|mjs|cjs|py|md)$|^knowledge-base/.*\.(sh|bash|bats|yml|yaml|tf|template|js)$' || true)
  [ -n "$files" ] || continue
  hits=$(gh pr diff "$n" 2>/dev/null | awk '/^\+\+\+ /{f=$2; next} /^\+/ && !/^\+\+\+/{print f ":" substr($0,2)}' | grep -E '\.(ts|tsx|mjs|cjs|py|md):|knowledge-base/' | grep -E -- "$NEW" | grep -vE ':[[:space:]]*(#|//|\*)' || true)
  echo "PR $n newly-read-class files: $(printf '%s\n' "$files" | grep -c .) added-line hits: $(printf '%s' "$hits" | grep -c . || true)"
  [ -n "$hits" ] && printf '%s\n' "$hits" | cut -c1-200
done
echo SCREEN-DONE
