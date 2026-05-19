#!/usr/bin/env bash
set -euo pipefail

# Parity test for the change-class regex set: DOCS_RE / CODE_RE / INFRA_RE.
# These three regex strings are inlined in TWO places (per #3493 plan):
#   1. .claude/hooks/session-rules-loader.sh — the live SessionStart hook.
#   2. tools/migration/classify-rules.sh     — the one-shot migration tool.
#
# A drift between the two means the live hook's classification can differ
# from what the migration's TSV says, silently mis-routing rules. The plan
# explicitly promises "the two are tested for parity in Phase 6.5" — this
# script is that test. See `knowledge-base/project/learnings/
# 2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`.

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/.claude/hooks/session-rules-loader.sh"
CLASSIFIER="$REPO_ROOT/tools/migration/classify-rules.sh"

extract_regex() {
  local file="$1" name="$2"
  # Match `<NAME>='...'` (bash single-quoted assignment) on its own line.
  grep -oE "^${name}='[^']+'" "$file" | head -1 | sed -E "s/^${name}='([^']+)'$/\1/"
}

fail=0
for re_name in DOCS_RE CODE_RE INFRA_RE; do
  hook_re="$(extract_regex "$HOOK" "$re_name" || echo "")"
  classifier_re="$(extract_regex "$CLASSIFIER" "$re_name" || echo "")"
  if [[ -z "$hook_re" || -z "$classifier_re" ]]; then
    echo "FAIL: $re_name not found in one of: $HOOK, $CLASSIFIER"
    fail=1
    continue
  fi
  if [[ "$hook_re" != "$classifier_re" ]]; then
    echo "FAIL: $re_name differs between hook and classifier"
    echo "  hook:       $hook_re"
    echo "  classifier: $classifier_re"
    fail=1
  else
    echo "PASS: $re_name matches across both files"
  fi
done

if (( fail == 1 )); then
  echo ""
  echo "Classifier regex drift detected. Update both files in lockstep."
  exit 1
fi
echo ""
echo "All 3 change-class regexes are in parity."
exit 0
