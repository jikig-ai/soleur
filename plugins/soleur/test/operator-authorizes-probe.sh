#!/usr/bin/env bash
# operator-authorizes probe (Ref #12443): greps the four wiring sites so a reviewer can see at a glance that the
# fourth hold class is connected. bash + grep only: it never runs the evaluator, so it passes in the Check-10
# sandbox where `gh` and `jq` may be absent. exit 0 and print `operator-authorizes: wired` when all four hold;
# exit 1 naming each missing site otherwise.
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -P "$HERE/.." && pwd -P)"
EVAL="$ROOT/skills/ship/scripts/hold-gate-eval.sh"
TRD="$ROOT/skills/brainstorm-techniques/references/technical-ruling-delegation.md"
OH="$ROOT/skills/ship/references/operator-holds.md"
GO="$ROOT/commands/go.md"
miss=0
grep -q 'operatorauthorize' "$EVAL" && grep -q 'Say go and I run it:' "$EVAL" \
  || { echo "MISSING: evaluator recognizer/verdict in $EVAL"; miss=1; }
grep -q 'Say go and I run it: <the act> - only you can say go' "$TRD" \
  || { echo "MISSING: section 8.1c authorizes render in $TRD"; miss=1; }
grep -q 'Operator-authorizes: <an act the agent can run once the operator types a go>' "$OH" \
  || { echo "MISSING: section 1 authorizes contract in $OH"; miss=1; }
grep -q 'begin `Operator-reserved:` or `Operator-authorizes:`' "$GO" \
  || { echo "MISSING: Step 1.5 two-class set-aside in $GO"; miss=1; }
[ "$miss" -eq 0 ] && { echo 'operator-authorizes: wired'; exit 0; }
exit 1
