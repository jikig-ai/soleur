#!/usr/bin/env bash
# Tests for .github/workflows/restart-inngest-server.yml — the self-trigger guard (#6425 AC7).
#
# The workflow carries a `push` trigger scoped to its own path. That trigger exists SOLELY to
# register the workflow in the Actions UI (a workflow_dispatch-only workflow can take 30+ min to
# appear). Without a job-level event guard, the registration trigger has a side effect: editing
# this file on main RESTARTS inngest-server in PRODUCTION.
#
# Asserted against the PARSED YAML rather than a grep, so a reformat, a comment mentioning the
# idiom, or a guard moved onto a different job cannot false-PASS the gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/restart-inngest-server.yml"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== restart-inngest-server.yml self-trigger guard tests (#6425) ==="

assert "workflow file exists" "[[ -f '$WF' ]]"
assert "YAML parses (pyyaml)" "python3 -c 'import yaml; yaml.safe_load(open(\"$WF\"))'"

# Probe the parsed shape. The comparison happens in python, which emits bare yes/no tokens —
# the job's `if` string contains both spaces and single quotes, so round-tripping it through a
# shell variable into `eval` mangles the quoting (and silently false-FAILS a correct workflow).
# `on` is YAML 1.1 truthy: pyyaml keys it as boolean True, not the string "on", so probe both
# spellings or this reads as "no triggers" and passes vacuously.
probe() {
  python3 - "$WF" "$1" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get("on", wf.get(True)) or {}
job = (wf.get("jobs") or {}).get("restart") or {}
checks = {
    "push": "push" in on,
    "dispatch": "workflow_dispatch" in on,
    "guard": "github.event_name == 'workflow_dispatch'" in str(job.get("if", "")),
}
print("yes" if checks[sys.argv[2]] else "no")
PY
}

# Precondition: the guard is only meaningful while BOTH triggers exist. If the push trigger is
# ever dropped the guard is moot — this states the premise instead of silently passing.
assert "workflow still carries the registration push trigger (guard premise)" \
  "[[ \$(probe push) == 'yes' ]]"
assert "workflow still carries workflow_dispatch (the real entry point)" \
  "[[ \$(probe dispatch) == 'yes' ]]"

# The guard itself. The restart job must no-op on every non-dispatch event.
assert "restart job is gated on workflow_dispatch (never fires on the registration push)" \
  "[[ \$(probe guard) == 'yes' ]]"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
