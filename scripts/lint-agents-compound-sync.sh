#!/usr/bin/env bash
# Guard: the rule-count threshold in AGENTS.md (`cq-agents-md-why-single-line`)
# and in plugins/soleur/skills/compound/SKILL.md step 8 MUST stay in sync —
# they encode the same contract. Editing one without the other silently
# de-syncs the warn. This script fails the commit if they disagree.
#
# Source rule: AGENTS.md `cq-agents-md-why-single-line` (PR #2754, issue #2686).
set -euo pipefail

AGENTS_THRESHOLD=$(grep -oE '>[0-9]+ rules' AGENTS.md | head -1 | grep -oE '[0-9]+')
COMPOUND_THRESHOLD=$(grep -oE 'A > [0-9]+' plugins/soleur/skills/compound/SKILL.md | head -1 | grep -oE '[0-9]+')

if [[ -z "$AGENTS_THRESHOLD" || -z "$COMPOUND_THRESHOLD" ]]; then
  echo "lint-agents-compound-sync: could not extract threshold from one or both files" >&2
  echo "  AGENTS.md: '$AGENTS_THRESHOLD'" >&2
  echo "  plugins/soleur/skills/compound/SKILL.md: '$COMPOUND_THRESHOLD'" >&2
  exit 1
fi

if [[ "$AGENTS_THRESHOLD" != "$COMPOUND_THRESHOLD" ]]; then
  echo "lint-agents-compound-sync: threshold out of sync" >&2
  echo "  AGENTS.md cq-agents-md-why-single-line: $AGENTS_THRESHOLD" >&2
  echo "  plugins/soleur/skills/compound/SKILL.md step 8: $COMPOUND_THRESHOLD" >&2
  exit 1
fi

echo "lint-agents-compound-sync: OK (threshold=$AGENTS_THRESHOLD)"
exit 0
