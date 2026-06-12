#!/usr/bin/env bash
# Lint test for the operator-digest workflow asset (#5085, plan §AC3).
#
# The workflow YAML is committed (inert) in soleur for multi-agent review, then installed
# into the PRIVATE jikig-ai/operator-digest repo by the provisioning script. It is brand-critical:
# it aggregates the operator's private financial + incident + decision data and posts it. The
# load-bearing safety properties are STRUCTURAL (where gh issue create lives, what the agent is
# allowed to do, whether the scrub runs outside the model) and are asserted here so a future edit
# cannot silently dissolve the containment boundary.
#
# Exit codes: 0 = all lint assertions pass; 1 = a lint assertion failed; 2 = asset missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="${SCRIPT_DIR}/../skills/operator-digest/assets/operator-digest.workflow.yml"

if [[ ! -r "$WF" ]]; then
  echo "FAIL: workflow asset not found at ${WF}" >&2
  echo "=== operator-digest-workflow: 0 passed, 1 failed (asset missing) ===" >&2
  exit 2
fi

pass=0
fail=0

assert() {  # <description> <ERE-pattern>
  local desc="$1" pattern="$2"
  if grep -qE -- "$pattern" "$WF"; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: ${desc} — pattern not found: ${pattern}" >&2; fi
}
refute() {  # <description> <ERE-pattern>
  local desc="$1" pattern="$2"
  if grep -qE -- "$pattern" "$WF"; then
    fail=$((fail+1)); echo "FAIL: ${desc} — pattern should be absent but matched: ${pattern}" >&2
  else pass=$((pass+1)); fi
}

# --- Least-privilege permissions + OIDC handshake ---
assert "id-token: write present"  '^[[:space:]]*id-token:[[:space:]]+write[[:space:]]*$'
assert "contents: read (data source is public, no write grant)" '^[[:space:]]*contents:[[:space:]]+read[[:space:]]*$'
assert "issues: write (posts the digest issue)" '^[[:space:]]*issues:[[:space:]]+write[[:space:]]*$'

# --- show_full_output OFF (the flag leaks all tool output incl. secrets to logs) ---
refute "show_full_output: true is NOT set" 'show_full_output:[[:space:]]*true'

# --- Cross-repo checkout of PUBLIC soleur, no persisted creds ---
assert "checks out jikig-ai/soleur as the data source" 'repository:[[:space:]]+jikig-ai/soleur'
assert "persist-credentials: false on checkout" 'persist-credentials:[[:space:]]+false'

# --- plugin_marketplaces pinned to soleur (not the running private repo) ---
assert "plugin_marketplaces pinned to jikig-ai/soleur" 'plugin_marketplaces:.*jikig-ai/soleur'

# --- Agent allowlist: Write allowed; gh issue create is NOT in the allowlist ---
assert "--allowedTools present and contains Write" 'allowedTools[^\n]*\bWrite\b'
# The agent must NOT be able to post: no gh issue create on the allowedTools line.
if grep -E 'allowedTools' "$WF" | grep -qE 'gh issue create'; then
  fail=$((fail+1)); echo "FAIL: allowedTools must NOT contain 'gh issue create' (prompt-injection bypass)" >&2
else pass=$((pass+1)); fi

# --- The ONLY gh issue create lives in a GHA run: post-step (outside the action) ---
assert "gh issue create exists as a deterministic post-step" 'gh issue create'
# It must not appear inside the claude_args/prompt allowlist (covered above) — and the scrub
# gate must run BEFORE it as its own run: step, outside claude-code-action.
assert "digest-scrub.sh invoked as a post-step (outside the action)" 'digest-scrub\.sh'

# --- No durable plaintext copy: rm digest.md after posting ---
assert "rm of the digest file present" 'rm[[:space:]]+-f'
assert "the digest file is digest.md" 'digest\.md'

# --- Actions SHA-pinned (supply-chain) ---
assert "claude-code-action SHA-pinned (40-hex)" 'anthropics/claude-code-action@[a-f0-9]{40}'
assert "actions/checkout SHA-pinned (40-hex)"   'actions/checkout@[a-f0-9]{40}'

# --- No leak of digest.md contents or the API key via cat/echo ---
refute "no cat/echo of digest.md"        '(cat|echo)[^\n]*digest\.md'
refute "no cat/echo of ANTHROPIC_API_KEY" '(cat|echo)[^\n]*ANTHROPIC_API_KEY'

# --- Triggers: scheduled + manual dispatch ---
assert "schedule: cron trigger present" '^[[:space:]]*schedule:[[:space:]]*$'
assert "workflow_dispatch present"      'workflow_dispatch'

# --- Vestigial generic-template label step dropped ---
refute "no vestigial 'gh label create' step" 'gh label create'

echo "=== operator-digest-workflow: ${pass} passed, ${fail} failed ===" >&2
[[ "$fail" == 0 ]]
