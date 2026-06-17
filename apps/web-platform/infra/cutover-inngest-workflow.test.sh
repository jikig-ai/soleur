#!/usr/bin/env bash
# Tests for .github/workflows/cutover-inngest.yml — the no-SSH cutover driver
# (#5450, AC5/Test-Scenario-5). The live workflow can only be exercised post-merge
# (a NEW workflow 404s on `gh workflow run --ref <feature-branch>`, R4), so these
# assert the YAML shape + the safety/poll invariants statically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/cutover-inngest.yml"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== cutover-inngest.yml workflow tests ==="

assert "workflow file exists" "[[ -f '$WF' ]]"

# YAML parses
assert "YAML parses (pyyaml)" "python3 -c 'import yaml,sys; yaml.safe_load(open(\"$WF\"))'"

# op input is a constrained choice (NOT a free string → no run-step injection)
assert "op input is type: choice" "grep -qE 'type:[[:space:]]*choice' '$WF'"
assert "choice includes enumerate" "grep -qE '^[[:space:]]+-[[:space:]]*enumerate$' '$WF'"
assert "choice includes rearm" "grep -qE '^[[:space:]]+-[[:space:]]*rearm$' '$WF'"
assert "choice includes verify-wiped-volume" "grep -qE '^[[:space:]]+-[[:space:]]*verify-wiped-volume$' '$WF'"

# op is passed via env, never interpolated into a run: command (injection-safe)
assert "op passed via env (OP: \${{ inputs.op }})" "grep -qE 'OP:[[:space:]]*\\\$\{\{[[:space:]]*inputs.op' '$WF'"
assert "no raw \${{ inputs.op }} inside a run shell ref" "! grep -qE '\\\$\{\{[[:space:]]*inputs.op[[:space:]]*\}\}\"?[[:space:]]*\$' <(grep -A200 'run:' '$WF')"

# least privilege + registration + serialization
assert "permissions: contents: read" "grep -qE 'contents:[[:space:]]*read' '$WF'"
assert "push registration trigger scoped to self" "grep -qE 'cutover-inngest.yml' '$WF'"
assert "shares deploy/restart concurrency group (state-slot serialization)" "grep -qE 'group:[[:space:]]*deploy-inngest-restart' '$WF'"
assert "timeout-minutes present (>= poll budget)" "grep -qE 'timeout-minutes:[[:space:]]*[0-9]+' '$WF'"
assert "no-op on the registration push (workflow_dispatch guard)" "grep -qE \"github.event_name == 'workflow_dispatch'\" '$WF'"

# every curl carries --max-time (no unbounded network call)
CURL_LINES=$(grep -c 'curl ' "$WF")
MAXTIME_LINES=$(grep -c -- '--max-time' "$WF")
assert "at least one curl present" "[[ '$CURL_LINES' -ge 3 ]]"
assert "every curl has --max-time (count parity)" "[[ '$CURL_LINES' -eq '$MAXTIME_LINES' ]]"

# HMAC + CF-Access on the webhook calls (mirrors restart-inngest-server.yml)
assert "HMAC X-Signature-256 header" "grep -qE 'X-Signature-256: sha256=' '$WF'"
assert "CF-Access client id header" "grep -qE 'CF-Access-Client-Id' '$WF'"
assert "uses WEBHOOK_DEPLOY_SECRET (no new secret)" "grep -qE 'WEBHOOK_DEPLOY_SECRET' '$WF'"

# the destructive verify polls the DEDICATED verify-status (not deploy-status), with a freshness guard
assert "polls inngest-verify-status (dedicated responder)" "grep -qE 'inngest-verify-status' '$WF'"
assert "verify webhook expects async 202" "grep -qE '!= \"202\"' '$WF'"
assert "freshness guard present (TRIGGER_TS - 60)" "grep -qE 'FRESH_FLOOR=\\\$\(\(TRIGGER_TS - 60\)\)' '$WF'"

# enumerate surfaces counts/ids only, never comment bodies (P2-sec-a)
assert "enumerate emits reminder_id list, not bodies" "grep -qE 'reminder_id\] \| join' '$WF'"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
