#!/usr/bin/env bash

# Tests for plugins/soleur/skills/schedule/SKILL.md task-design answers (#11015).
# Run: bash plugins/soleur/test/schedule-task-design.test.sh
#
# Content-assertion tests: they pin that every NEW autonomous task created via
# `soleur:schedule` carries written answers to the six task-design questions
# (trigger / services / next / human re-entry / dedupe / source dedupe) in the
# generated workflow's `# Task design:` header, that recurring mode collects
# the five non-derived answers, that flag invocations expose the --design-*
# contract, and that the requirement is create-time only (no retrofit onto
# existing scheduled-*.yml files).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
SKILL_FILE="$REPO_ROOT/plugins/soleur/skills/schedule/SKILL.md"

echo "=== schedule task-design content tests ==="
echo ""

assert_file_exists "$SKILL_FILE" "SKILL.md exists"

SKILL_CONTENT="$(cat "$SKILL_FILE")"

# --- Extract the two generated YAML templates ---
# Recurring (Step 3a): the first ```yaml fence after the Step 3a heading.
RECURRING_BLOCK="$(awk '
  /\*\*Step 3a: Generate the workflow file \(recurring mode\)\*\*/ { in_step=1; next }
  in_step && /^```yaml$/ { in_yaml=1; next }
  in_step && in_yaml && /^```$/ { in_yaml=0; in_step=0; next }
  in_step && in_yaml { print }
' "$SKILL_FILE")"

# One-time (Step 3b): between the canonical HTML markers.
ONCE_BLOCK="$(awk '
  /<!-- once-template-begin -->/ { in_section=1; next }
  /<!-- once-template-end -->/ { in_section=0; next }
  in_section && /^```yaml$/ { in_yaml=1; next }
  in_section && /^```$/ && in_yaml { in_yaml=0; next }
  in_section && in_yaml { print }
' "$SKILL_FILE")"

if [[ -z "$RECURRING_BLOCK" ]]; then
  echo "  FAIL: could not extract the Step 3a recurring YAML template"
  FAIL=$((FAIL + 1))
fi
if [[ -z "$ONCE_BLOCK" ]]; then
  echo "  FAIL: could not extract the Step 3b once YAML template"
  FAIL=$((FAIL + 1))
fi

SIX_KEYS=(trigger services next human_reentry dedupe source_dedupe)

# --- TD1: both templates carry the `# Task design:` header with all six keys ---
echo "TD1: both generated templates carry the '# Task design:' header + six field keys"

for block_name in RECURRING ONCE; do
  block_var="${block_name}_BLOCK"
  block="${!block_var}"
  assert_contains "$block" '# Task design:' \
    "${block_name} template stamps a '# Task design:' header comment"
  for key in "${SIX_KEYS[@]}"; do
    assert_contains "$block" "#   ${key}:" \
      "${block_name} template '# Task design:' block carries key '${key}:'"
  done
done
echo ""

# --- TD2: Step 1 collects the five non-derived answers (recurring mode) ---
echo "TD2: Step 1 collects the five non-derived task-design answers"

STEP1_BLOCK="$(awk '
  /\*\*Step 1: Collect inputs \(recurring mode only\)\*\*/ { in_step=1; next }
  in_step && /^\*\*Step 2:/ { in_step=0; next }
  in_step { print }
' "$SKILL_FILE")"

if [[ -z "$STEP1_BLOCK" ]]; then
  echo "  FAIL: could not extract the Step 1 collect-inputs section"
  FAIL=$((FAIL + 1))
fi

assert_contains "$STEP1_BLOCK" 'Services read/written' \
  "Step 1 collects the services answer"
assert_contains "$STEP1_BLOCK" 'Triggers next' \
  "Step 1 collects the what-it-triggers-next answer"
assert_contains "$STEP1_BLOCK" 'Human re-entry' \
  "Step 1 collects the human re-entry answer"
assert_contains "$STEP1_BLOCK" 'concurrency: group:' \
  "Step 1 requires the dedupe answer to name a mechanism beyond concurrency: group:"
assert_contains "$STEP1_BLOCK" 'not a ticket source' \
  "Step 1 collects a source-dedupe answer or an explicit 'not a ticket source'"
echo ""

# --- TD3: Step 0b documents the --design-* flag contract ---
echo "TD3: Step 0b documents the --design-* flags and the non-interactive hard error"

for flag in --design-services --design-next --design-reentry --design-dedupe --design-source-dedupe; do
  assert_contains "$SKILL_CONTENT" "$flag" \
    "Step 0b documents flag ${flag}"
done
assert_contains "$SKILL_CONTENT" 'hard error' \
  "a missing design answer in a non-interactive context is a hard error"
echo ""

# --- TD4: create-time-only scoping (P5 — no retrofit onto existing workflows) ---
echo "TD4: requirement is create-time only (no retrofit onto existing scheduled-*.yml)"

assert_contains "$SKILL_CONTENT" 'newly created' \
  "skill text scopes the task-design requirement to newly created tasks"
echo ""

print_results
