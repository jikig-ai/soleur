#!/usr/bin/env bash
# Follow-through: #7376 — run-registered-suites.sh parallel flake.
#
# PR #7423 shipped the INSTRUMENT half only (diagnostics on RED + two defects provable by
# reading). It deliberately used `Ref`, not `Closes`: H2 (capacity) and H4 (polling deadline)
# remain UNKNOWN, so the flake is not proven fixed.
#
# DEPENDENCY trigger, not an event-grep. The tempting probe — "has the monitor produced an
# attributed diagnostic yet?" — is wrong for this contract: exit 0 CLOSES the issue, and an
# attributed occurrence means there is work to do, not that the work is done. #7376 is resolved
# exactly when its fix PR lands, and that fix is tracked by #7432 (removing the JOBS=1 stopgap
# is only possible once the flake is actually fixed and soaked).
#
# Exit: 0 = PASS (#7432 closed → the fix landed → close this)
#       2 = TRANSIENT (not yet, or gh unavailable — never FAIL, there is nothing to "fail")
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
set -uo pipefail

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: GH_TOKEN unset — cannot query the dependency" >&2
  exit 2
fi

state=$(gh issue view 7432 --json state --jq .state 2>/dev/null || echo "")
if [[ -z "$state" ]]; then
  echo "TRANSIENT: could not read #7432 state" >&2
  exit 2
fi

if [[ "$state" == "CLOSED" ]]; then
  echo "PASS: #7432 is CLOSED — the JOBS=1 stopgap follow-up landed, so the flake fix is in." >&2
  exit 0
fi

echo "TRANSIENT: #7432 is $state — the flake fix has not landed yet." >&2
exit 2
