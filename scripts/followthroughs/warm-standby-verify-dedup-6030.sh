#!/usr/bin/env bash
# Follow-through: warm_standby verify-poll de-duplication (deferred-scope-out,
# contested-design, from PR #6030 multi-agent review — code-quality P2 +
# pattern-recognition P2-2 converged).
#
# Closes automatically when warm_standby is migrated onto the shared
# apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh (ending the
# two-divergent-copies drift hazard). Until then the tracker stays open.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS      (warm_standby sources the shared script → migration done → close)
#   1 = FAIL      (warm_standby still carries its inline verify-poll copy)
#   * = TRANSIENT (workflow/job not found → retry next sweep, never false-close)
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
set -uo pipefail

# soleur:followthrough-stub v1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"

[[ -f "$WF" ]] || { echo "TRANSIENT: workflow not found at $WF" >&2; exit 2; }

# Isolate the warm_standby job block ONLY: from `^  warm_standby:` to the next
# 2-space-indented job key. Scoped so the pre-existing occurrences of the shared
# script name in the web_2_recreate job (L1319) + comments do NOT false-match
# and vacuously auto-close the tracker (per the CONCUR-gate caveat).
BLOCK="$(awk '
  /^  warm_standby:[[:space:]]*$/ { inblk=1; next }
  inblk && /^  [A-Za-z0-9_]+:[[:space:]]*$/ { inblk=0 }
  inblk { print }
' "$WF")"
[[ -n "$BLOCK" ]] || { echo "TRANSIENT: warm_standby job block not found (renamed/removed?)" >&2; exit 2; }

if printf '%s\n' "$BLOCK" | grep -q 'deploy-status-fanout-verify\.sh'; then
  echo "PASS: warm_standby now sources deploy-status-fanout-verify.sh — verify-poll duplication resolved."
  exit 0
fi
echo "FAIL: warm_standby still carries its inline verify-poll copy (not yet migrated onto the shared script)." >&2
exit 1
