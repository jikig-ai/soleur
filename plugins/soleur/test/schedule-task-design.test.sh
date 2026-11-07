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

# The recurring block's values are the Step 0b substitution tokens, not literals.
for token in DESIGN_SERVICES DESIGN_NEXT DESIGN_REENTRY DESIGN_DEDUPE DESIGN_SOURCE_DEDUPE; do
  assert_contains "$RECURRING_BLOCK" "<${token}>" \
    "RECURRING header substitutes <${token}> from --design-* / Step 1"
done
# The once block's answers are derived from D1–D5 — pin distinguishing literals.
assert_contains "$ONCE_BLOCK" 'not a ticket source — fires once' \
  "ONCE header derives source_dedupe from D1–D5"
assert_contains "$ONCE_BLOCK" 'D3 date guard' \
  "ONCE header derives dedupe/trigger from the D3 guard"
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
assert_contains "$STEP1_BLOCK" 'MUST name something beyond' \
  "Step 1 requires the dedupe answer to name a mechanism beyond concurrency: group:"
assert_contains "$STEP1_BLOCK" 'not a ticket source' \
  "Step 1 collects a source-dedupe answer or an explicit 'not a ticket source'"
assert_contains "$STEP1_BLOCK" 'may be skipped when the corresponding `--design-*` flags' \
  "Step 1 items 7-11 are skippable only when --design-* flags carry answers"
assert_contains "$STEP1_BLOCK" 'single printable line' \
  "Step 1 design answers carry the single-line injection validation"
echo ""

# --- TD3: Step 0b documents the --design-* flag contract ---
echo "TD3: Step 0b documents the --design-* flags and the non-interactive hard error"

for flag in --design-services --design-next --design-reentry --design-dedupe --design-source-dedupe; do
  assert_contains "$SKILL_CONTENT" "$flag" \
    "Step 0b documents flag ${flag}"
done
assert_contains "$SKILL_CONTENT" 'ERROR: missing or invalid task-design answer for <question>' \
  "non-interactive missing/invalid design answer is a hard error with the recovery message"
assert_contains "$SKILL_CONTENT" '^[\x20-\x7e]{1,400}$' \
  "Step 0b pins the single-line regex for --design-* values"
assert_contains "$SKILL_CONTENT" 'run the task-design check below, then skip to Step 2' \
  "Step 0b fast path runs the design check BEFORE skipping to Step 2"
echo ""

# --- TD4: create-time-only scoping (P5 — no retrofit onto existing workflows) ---
echo "TD4: requirement is create-time only (no retrofit onto existing scheduled-*.yml)"

assert_contains "$SKILL_CONTENT" 'newly created' \
  "skill text scopes the task-design requirement to newly created tasks"
echo ""

# --- TD5: plan-side schema parity — all 4 schema copies carry the six keys ---
echo "TD5: plan-side '## Task Design' schema parity (gate reference + 3 template copies)"

GATE_FILE="$REPO_ROOT/plugins/soleur/skills/plan/references/task-design-gate.md"
TEMPLATES_FILE="$REPO_ROOT/plugins/soleur/skills/plan/references/plan-issue-templates.md"

assert_file_exists "$GATE_FILE" "canonical gate contract exists"
GATE_CONTENT="$(cat "$GATE_FILE")"
assert_contains "$GATE_CONTENT" 'CANONICAL' \
  "task-design-gate.md declares itself the canonical copy"
assert_contains "$GATE_CONTENT" 'non-`_`' \
  "detection covers non-underscore-prefixed Inngest function files"
assert_contains "$GATE_CONTENT" 'CHECK_REGISTRY' \
  "detection covers a new registered check via Files-to-Edit"
assert_contains "$GATE_CONTENT" 'UNFENCED' \
  "reject notes fence-blindness (a fenced quote is not the section)"
assert_contains "$GATE_CONTENT" '.github/workflows/*.yml' \
  "detection covers ANY new workflow file, not only scheduled-*"
assert_contains "$GATE_CONTENT" 'cron.schedule(' \
  "detection covers pg_cron migrations"
for key in "${SIX_KEYS[@]}"; do
  assert_contains "$GATE_CONTENT" "    ${key}:" \
    "gate canonical schema carries key '${key}:'"
done

# Exactly 3 `## Task Design` blocks in the templates file, each a verbatim schema copy —
# count-assert so deleting a key from ONE copy reds.
TD_COUNT="$(grep -c '^## Task Design' "$TEMPLATES_FILE" || true)"
assert_eq "$TD_COUNT" "3" "plan-issue-templates.md carries exactly 3 '## Task Design' blocks"
TEMPLATES_CONTENT="$(cat "$TEMPLATES_FILE")"
for key in "${SIX_KEYS[@]}"; do
  assert_eq "$(grep -cF "    ${key}:" "$TEMPLATES_FILE" || true)" "3" \
    "all 3 template schema copies carry key '${key}:'"
done
assert_eq "$(grep -cF 'task-design-gate.md' "$TEMPLATES_FILE" || true)" "3" \
  "all 3 template blocks point at the canonical contract"
assert_contains "$TEMPLATES_CONTENT" 'one `- task:` list item per created task' \
  "schema documents the one-item-per-created-task shape"
echo ""

# --- TD6: plan/deepen-plan/workflow gate wiring ---
echo "TD6: gate wiring (plan §2.9.3, deepen-plan §4.13, workflow.js taskDesign)"

PLAN_SKILL="$(cat "$REPO_ROOT/plugins/soleur/skills/plan/SKILL.md")"
DEEPEN_SKILL="$(cat "$REPO_ROOT/plugins/soleur/skills/deepen-plan/SKILL.md")"
WORKFLOW_JS="$(cat "$REPO_ROOT/plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js")"

assert_contains "$PLAN_SKILL" '#### 2.9.3. Task-Design Gate' \
  "plan skill carries the §2.9.3 Task-Design Gate"
assert_contains "$PLAN_SKILL" '[skill-enforced: plan Phase 2.9.3 + deepen-plan Phase 4.13]' \
  "§2.9.3 carries its enforcement marker, not just the heading"
assert_contains "$DEEPEN_SKILL" '### 4.13. Task-Design Halt' \
  "deepen-plan skill carries the §4.13 Task-Design Halt"
assert_contains "$DEEPEN_SKILL" 'rule=task-design-design-time-default' \
  "§4.13 pins the halt telemetry emission"
assert_contains "$WORKFLOW_JS" 'taskDesign: {' \
  "workflow.js GATES carries the taskDesign entry"
assert_contains "$WORKFLOW_JS" 'taskDesign: GATE_VERDICT' \
  "workflow.js verdict schema requires taskDesign"
assert_contains "$(cat "$REPO_ROOT/scripts/lib/test-affected-paths.sh")" \
  'AFFECTED_PLUGINS_SOLEUR_TEST_SCHEDULE_TASK_DESIGN_TEST_SH_PATHS' \
  "suite is registered in test-affected-paths.sh"
echo ""

print_results
