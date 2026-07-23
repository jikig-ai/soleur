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

# --- Comment-stripped view of the asset. The YAML carries a documentation header that
# replicates every load-bearing token (`gh issue create`, `digest-scrub.sh`, …), so a
# whole-file grep false-passes against the comments even after the FUNCTIONAL construct is
# deleted. Strip full-line comments before the structural asserts below. ---
CODE="$(grep -vE '^[[:space:]]*#' "$WF")"

# Agent allowlist grants Write (the agent writes digest.md).
if printf '%s\n' "$CODE" | grep -E 'allowedTools' | grep -qE '\bWrite\b'; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL: --allowedTools must contain Write" >&2; fi

# The agent must NOT be granted a post capability. claude_args is a YAML folded block (>-) that
# can span multiple physical lines, so a single-line grep misses a `Bash(gh issue create:*)`
# continuation. Refute `gh issue create` across the WHOLE claude_args region (claude_args: → prompt:).
ARGS_REGION="$(awk '/claude_args:/{f=1} /^[[:space:]]*prompt:[[:space:]]*\|?[[:space:]]*$/{if(f) f=0} f' "$WF")"
if printf '%s\n' "$ARGS_REGION" | grep -qE 'gh issue create'; then
  fail=$((fail+1)); echo "FAIL: agent allowlist/args must NOT grant 'gh issue create' (prompt-injection bypass)" >&2
else pass=$((pass+1)); fi

# Exclusivity: EVERY `gh issue create` in the executable (comment-stripped) YAML must be a
# run-step command line (`gh issue create -R …`). Any other occurrence — in the prompt block,
# an allowlist continuation, etc. — means the model was handed the post capability.
create_lines="$(printf '%s\n' "$CODE" | grep -nE 'gh issue create' || true)"
if [[ -z "$create_lines" ]]; then
  fail=$((fail+1)); echo "FAIL: no 'gh issue create' post-step found in executable YAML" >&2
elif printf '%s\n' "$create_lines" | grep -qvE ':[[:space:]]+gh issue create -R '; then
  fail=$((fail+1)); echo "FAIL: a 'gh issue create' appears outside a run-step command line (post bypass):" >&2
  printf '%s\n' "$create_lines" | grep -vE ':[[:space:]]+gh issue create -R ' >&2
else pass=$((pass+1)); fi

# Scrub gate invoked as a post-step OUTSIDE the action — anchored to the functional invocation
# (the SCRUB var + the `bash "$SCRUB"` call), NOT the doc-header mention.
if printf '%s\n' "$CODE" | grep -qE 'bash[[:space:]]+"\$SCRUB"' && \
   printf '%s\n' "$CODE" | grep -qE 'SCRUB=.*digest-scrub\.sh'; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL: digest-scrub.sh must be invoked as a post-step (bash \"\$SCRUB\")" >&2; fi

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

# --- Failure self-report (staleness contract #6836): a FAILED digest run must not be a
# silent absence. The 2026-06-26 and 2026-07-20 runs failed and nobody was notified — the
# operator simply got no digest that week. An `if: failure()` step self-reports so a broken
# digest is loud, mirroring the delivery fix. ---
assert "self-reports on job failure (if: failure())" 'if:[[:space:]]*failure\(\)'
assert "failure self-report names the FAILED digest" 'digest run FAILED|Weekly digest.*FAIL'

# --- Containment: the asset must NEVER live under soleur's OWN .github/workflows/ — that would
# run it in PUBLIC Actions logs and leak the operator's private data. It is an inert asset that
# the provisioning script installs into the PRIVATE operator-digest repo. A future `git mv` into
# .github/workflows/ would silently re-arm the leak with no other CI signal; this guard catches it. ---
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
if compgen -G "${REPO_ROOT}/.github/workflows/operator-digest*" >/dev/null 2>&1; then
  fail=$((fail+1)); echo "FAIL: operator-digest workflow must NOT live under soleur/.github/workflows/ (public-logs leak)" >&2
else pass=$((pass+1)); fi

echo "=== operator-digest-workflow: ${pass} passed, ${fail} failed ===" >&2
[[ "$fail" == 0 ]]
