#!/usr/bin/env bash
# Static-contract test for the operator-digest skill (SKILL.md, #5085, plan §Phase 1 / AC1).
#
# The skill is the load-bearing synthesizer (LLM-as-script): there is no TS/bash
# synthesizer to unit-test, so the only mechanically-verifiable surface is the
# SKILL.md contract itself. This test asserts the prose carries every guardrail the
# plan makes load-bearing, so a future edit cannot silently drop one:
#   - frontmatter: third-person `description` (the components.test.ts voice/budget
#     gates cover word-count + char-limit; this asserts presence + third person here too).
#   - body names all FOUR data sources.
#   - L2 control: incident section built from frontmatter/title/status ONLY, never the PIR body.
#   - the agent WRITES digest.md and does NOT post (the gated post-step is the only poster).
#   - even an all-empty week still posts (deterministic fallback, never blank).
#   - each digest references the prior week's issue (in-band liveness loop).
#
# Exit codes: 0 = all contract assertions pass; 1 = a contract assertion failed; 2 = SKILL.md missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="${SCRIPT_DIR}/../skills/operator-digest/SKILL.md"

if [[ ! -r "$SKILL" ]]; then
  echo "FAIL: SKILL.md not found at ${SKILL}" >&2
  echo "=== operator-digest-skill: 0 passed, 1 failed (SKILL.md missing) ===" >&2
  exit 2
fi

pass=0
fail=0

# assert_grep <PCRE-or-ERE-flags> <description> <pattern>
# Uses grep -iqE (case-insensitive ERE) over the whole file unless overridden.
assert() {
  local desc="$1" pattern="$2"
  if grep -iqE -- "$pattern" "$SKILL"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL: ${desc} — pattern not found: ${pattern}" >&2
  fi
}

# refute <description> <pattern> — must NOT be present.
refute() {
  local desc="$1" pattern="$2"
  if grep -iqE -- "$pattern" "$SKILL"; then
    fail=$((fail+1))
    echo "FAIL: ${desc} — pattern should be absent but matched: ${pattern}" >&2
  else
    pass=$((pass+1))
  fi
}

# --- Frontmatter: third-person description ---
assert "frontmatter name is operator-digest" '^name:[[:space:]]+operator-digest[[:space:]]*$'
assert "description is third-person (starts with 'This skill')" '^description:[[:space:]]*"?This skill'

# Description char limit (≤1024) — mirror the components.test.ts SKILL_DESCRIPTION_CHAR_LIMIT gate.
desc_line="$(grep -m1 -E '^description:' "$SKILL" || true)"
desc_val="${desc_line#description:}"
desc_len="${#desc_val}"
if (( desc_len <= 1024 )); then
  pass=$((pass+1))
else
  fail=$((fail+1))
  echo "FAIL: description exceeds 1024 chars (${desc_len})" >&2
fi

# --- Body names all FOUR data sources ---
assert "source 1: merged PRs (gh pr list)"       'gh pr list'
assert "source 2: expenses/money ledger"         'expenses\.md'
assert "source 3: post-mortems / PIRs"           'post-mortem'
assert "source 4: action-required issues"        'action-required'

# --- L2 control: incident from frontmatter/title/status ONLY, never body ---
# Order-independent: a correct reword ("status, frontmatter, title") must not falsely fail.
for kw in frontmatter title status; do
  assert "incident control names '${kw}'" "$kw"
done
assert "incident never reads the PIR body"       'never.*body|not.*the.*body|never the body'

# --- Write-not-post contract ---
assert "writes digest.md"                        'digest\.md'
assert "does NOT post (agent stops)"             'do NOT post|does not post|without posting|STOP'

# --- Deterministic fallback: even an all-empty week posts, never blank ---
assert "even an all-empty week still posts"      'empty.*(week|still).*post|even an all-empty week|all-empty week still posts'
assert "fallback section is never blank"         'never blank|never leave.*blank|not blank'

# --- In-band liveness: reference the prior week's issue ---
assert "references the prior week's issue"       'prior week|last week'

# --- Negative: the agent must not be told to create issues itself ---
refute "agent is not instructed to 'gh issue create'" 'gh issue create'

echo "=== operator-digest-skill: ${pass} passed, ${fail} failed ===" >&2
[[ "$fail" == 0 ]]
