#!/usr/bin/env bash

# Tests for plugins/soleur/skills/schedule/SKILL.md --once flag.
# Run: bash plugins/soleur/test/schedule-skill-once.test.sh
#
# These are content-assertion tests. They catch deletion of load-bearing
# defenses, NOT semantic drift. The post-merge dogfood (TS-dogfood in the plan)
# is the real regression test for end-to-end behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
SKILL_FILE="$REPO_ROOT/plugins/soleur/skills/schedule/SKILL.md"

echo "=== schedule --once SKILL.md content tests ==="
echo ""

assert_file_exists "$SKILL_FILE" "SKILL.md exists"

SKILL_CONTENT="$(cat "$SKILL_FILE")"

# Extract the one-time YAML template block. SKILL.md frames the canonical
# template with HTML comment markers `<!-- once-template-begin -->` and
# `<!-- once-template-end -->`. Anchoring on these markers is more robust
# than "first yaml fence containing FIRE_DATE" — that heuristic silently
# picks the wrong block if SKILL.md ever adds another fence with FIRE_DATE
# (e.g., a doc example, a before/after snippet).
ONCE_BLOCK="$(awk '
  /<!-- once-template-begin -->/ { in_section=1; next }
  /<!-- once-template-end -->/ { in_section=0; next }
  in_section && /^```yaml$/ { in_yaml=1; next }
  in_section && /^```$/ && in_yaml { in_yaml=0; next }
  in_section && in_yaml { print }
' "$SKILL_FILE")"

if [[ -z "$ONCE_BLOCK" ]]; then
  echo "  FAIL: could not find one-time YAML template block (HTML markers <!-- once-template-begin --> / <!-- once-template-end --> missing or empty)"
  FAIL=$((FAIL + 1))
  # Continue running TS1-TS5 against an empty block; cascading failures make
  # the missing-block diagnosis explicit rather than masking it with a bail.
fi

# --- TS1: Token-revocation regression guard ---
# The `gh workflow disable` MUST be inside the agent prompt (last instruction),
# NOT a post-step. claude-code-action revokes the App token after its step, so
# a post-step disable would silently fail and the workflow re-fires every year.
echo "TS1: gh workflow disable is inside agent prompt (token-revocation regression guard)"

assert_contains "$ONCE_BLOCK" "gh workflow disable" \
  "one-time template references gh workflow disable"

assert_contains "$ONCE_BLOCK" "Final step" \
  "one-time template labels disable as the Final step inside the prompt"

# Verify no post-step appears after the claude-code-action step. Step entries
# at this level are indented exactly 6 spaces ("      - "). Sub-keys (env:,
# with:, prompt:) and prompt-body lines are indented deeper, so they do not
# match this pattern.
POST_STEP_COUNT=$(printf '%s\n' "$ONCE_BLOCK" | awk '
  /anthropics\/claude-code-action/ { found=1; next }
  found && /^      - / { count++ }
  END { print count+0 }
')
assert_eq "0" "$POST_STEP_COUNT" \
  "no step appears after claude-code-action (a post-step would defeat self-disable)"

echo ""

# --- TS2: Date guard is FIRST agent-prompt step (D3, primary cross-year defense) ---
echo "TS2: date guard [[ \"\$(date -u +%F)\" == \"\$FIRE_DATE\" ]] is FIRST agent-prompt step"

assert_contains "$ONCE_BLOCK" '[[ "$(date -u +%F)" == "$FIRE_DATE" ]]' \
  "literal date guard line present in one-time template"

# Date guard line must appear BEFORE the disable line inside the block.
DATE_GUARD_LINE=$( { printf '%s\n' "$ONCE_BLOCK" | grep -nF '[[ "$(date -u +%F)" == "$FIRE_DATE" ]]' || true; } | head -1 | cut -d: -f1)
DISABLE_LINE=$( { printf '%s\n' "$ONCE_BLOCK" | grep -nF 'gh workflow disable' || true; } | tail -1 | cut -d: -f1)

if [[ -n "$DATE_GUARD_LINE" && -n "$DISABLE_LINE" && "$DATE_GUARD_LINE" -lt "$DISABLE_LINE" ]]; then
  echo "  PASS: date guard appears before final disable (FIRST vs LAST ordering)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: date guard line ($DATE_GUARD_LINE) must precede disable line ($DISABLE_LINE)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- TS3: Stale-context preamble (D2) ---
# Each assertion anchors on the OPERATIVE line shape (the actual gh command or
# the actual shell condition), not just a stray token. A reviewer can't satisfy
# these by leaving the word "OPEN" in a comment after deleting the real check.
echo "TS3: stale-context preamble (issue OPEN, same repo, comment matches issue, observation on failure)"

assert_contains "$ONCE_BLOCK" 'gh issue view "$ISSUE_NUMBER" --json state,repository_url' \
  "preamble fetches issue state and repository_url via gh issue view"

assert_contains "$ONCE_BLOCK" 'must be OPEN' \
  "preamble asserts issue state must be OPEN"

assert_contains "$ONCE_BLOCK" 'isArchived' \
  "preamble checks repo is not archived"

assert_contains "$ONCE_BLOCK" 'state=$(gh workflow view' \
  "preamble runs idempotency check (state=$(gh workflow view ...))"

assert_contains "$ONCE_BLOCK" 'gh api "repos/${{ github.repository }}/issues/comments/$COMMENT_ID" --jq .issue_url' \
  "preamble fetches comment.issue_url with quoted COMMENT_ID"

assert_contains "$ONCE_BLOCK" 'observation comment' \
  "preamble posts observation comment on pre-flight failure"

echo ""

# --- TS5: D5 comment-author-pin + input-validation regex regression guard ---
# These assertions catch the highest-blast-radius regressions that TS1-TS4
# don't cover: deleting the D5 comment-pin defense, deleting input regex
# validators (re-opening shell injection), or widening --allowedTools.
echo "TS5: D5 comment-author-pin and input-validation defenses present"

# D5 author-pin and immutability — assert the equality checks (which subsume
# the env-var-name presence checks: a check referencing $EXPECTED_AUTHOR must
# imply the env var exists).
assert_contains "$ONCE_BLOCK" '"$actual_author" == "$EXPECTED_AUTHOR"' \
  "preamble asserts comment author equals EXPECTED_AUTHOR (D5 author-pin)"

assert_contains "$ONCE_BLOCK" 'created_at == updated_at' \
  "preamble asserts comment unedited (D5 immutability pin)"

assert_contains "$ONCE_BLOCK" 'EXPECTED_CREATED_AT' \
  "EXPECTED_CREATED_AT env var present in template"

# Tool-surface allowlist (regression vs recurring template)
assert_contains "$ONCE_BLOCK" '--allowedTools Bash,Read,Write,Edit,Glob,Grep' \
  "claude_args includes least-privilege --allowedTools allowlist"

# Input regex validators (load-bearing against shell/YAML injection)
assert_contains "$SKILL_CONTENT" '^[1-9][0-9]{0,8}$' \
  "Step 0c specifies --issue regex validator"

assert_contains "$SKILL_CONTENT" '^[1-9][0-9]{0,18}$' \
  "Step 0c specifies --comment regex validator"

assert_contains "$SKILL_CONTENT" '^[a-z][a-z0-9-]{0,49}$' \
  "Step 0c specifies --name regex validator"

assert_contains "$SKILL_CONTENT" '^\d{4}-\d{2}-\d{2}$' \
  "Step 0c specifies --at strict ISO regex validator"

# FIRE_DATE non-empty / format guard inside the prompt
assert_contains "$ONCE_BLOCK" '"$FIRE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
  "preamble guards against empty/malformed FIRE_DATE before equality check"

echo ""

# --- TS4: Disambiguation section (namespace conflation regression) ---
echo "TS4: disambiguation section present with examples for both skills"

assert_contains "$SKILL_CONTENT" "When to use this skill vs harness" \
  "disambiguation section header present"

# Count example bullets under each skill's examples block. We accept any line
# starting with "- " between an "Examples for ..." marker and the next "## "
# heading or "Examples for" marker.
SOLEUR_EXAMPLES=$(awk '
  /Examples for `soleur:schedule`/ { in_block=1; count=0; next }
  in_block && /^- / { count++ }
  in_block && /Examples for `harness/ { print count; exit }
  in_block && /^## / { print count; exit }
  END { if (in_block) print count }
' "$SKILL_FILE" | head -1)

HARNESS_EXAMPLES=$(awk '
  /Examples for `harness/ { in_block=1; count=0; next }
  in_block && /^- / { count++ }
  in_block && /^## / { print count; exit }
  END { if (in_block) print count }
' "$SKILL_FILE" | head -1)

SOLEUR_EXAMPLES=${SOLEUR_EXAMPLES:-0}
HARNESS_EXAMPLES=${HARNESS_EXAMPLES:-0}

if [[ "$SOLEUR_EXAMPLES" -ge 2 ]]; then
  echo "  PASS: at least 2 examples for soleur:schedule ($SOLEUR_EXAMPLES found)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: need >=2 examples for soleur:schedule, found $SOLEUR_EXAMPLES"
  FAIL=$((FAIL + 1))
fi

if [[ "$HARNESS_EXAMPLES" -ge 2 ]]; then
  echo "  PASS: at least 2 examples for harness schedule ($HARNESS_EXAMPLES found)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: need >=2 examples for harness schedule, found $HARNESS_EXAMPLES"
  FAIL=$((FAIL + 1))
fi

echo ""

print_results
