#!/usr/bin/env bash

# Marker-existence gate; does NOT prove semantic correctness — see plan §Risks R3.
#
# Tests that the named-orchestration-lanes feature is consistently encoded
# across brainstorm/SKILL.md, brainstorm-domain-config.md, plan/SKILL.md,
# work/SKILL.md, and the parent audit spec (feat-claude-skills-audit/spec.md).
#
# Run: bash plugins/soleur/test/lane-frontmatter.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
BRAINSTORM_SKILL="$REPO_ROOT/plugins/soleur/skills/brainstorm/SKILL.md"
DOMAIN_CONFIG="$REPO_ROOT/plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md"
PLAN_SKILL="$REPO_ROOT/plugins/soleur/skills/plan/SKILL.md"
WORK_SKILL="$REPO_ROOT/plugins/soleur/skills/work/SKILL.md"
AUDIT_SPEC="$REPO_ROOT/knowledge-base/project/specs/feat-claude-skills-audit/spec.md"

echo "=== lane-frontmatter tests ==="
echo ""

assert_file_exists "$BRAINSTORM_SKILL" "brainstorm/SKILL.md exists"
assert_file_exists "$DOMAIN_CONFIG" "brainstorm-domain-config.md exists"
assert_file_exists "$PLAN_SKILL" "plan/SKILL.md exists"
assert_file_exists "$WORK_SKILL" "work/SKILL.md exists"
assert_file_exists "$AUDIT_SPEC" "feat-claude-skills-audit/spec.md exists"
echo ""

# --- Assertion 1: brainstorm-domain-config.md has Lane Inference + 3 lane tokens ---
echo "A1: brainstorm-domain-config.md has '## Lane Inference' and all 3 lane tokens"
DC=$(cat "$DOMAIN_CONFIG")
if grep -qE '^## Lane Inference$' "$DOMAIN_CONFIG"; then
  echo "  PASS: '## Lane Inference' heading present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: '## Lane Inference' heading not found in $DOMAIN_CONFIG"
  FAIL=$((FAIL + 1))
fi
assert_contains "$DC" "single-domain" "domain-config mentions 'single-domain'"
assert_contains "$DC" "cross-domain" "domain-config mentions 'cross-domain'"
assert_contains "$DC" "procedural" "domain-config mentions 'procedural'"
echo ""

# --- Assertion 2: brainstorm/SKILL.md has Phase 0.4 heading ---
echo "A2: brainstorm/SKILL.md has 'Phase 0.4: Lane Auto-Detect and Selection' heading"
if grep -qE '^### Phase 0\.4: Lane Auto-Detect and Selection$' "$BRAINSTORM_SKILL"; then
  echo "  PASS: Phase 0.4 heading present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Phase 0.4 heading not found in $BRAINSTORM_SKILL"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Assertion 3: brainstorm/SKILL.md Phase 0.5 Processing Instructions has step 0 reading LANE ---
# Marker shape: a numbered '0.' bullet that mentions LANE within the Phase 0.5 Processing
# Instructions block. Grep window: line range between '#### Processing Instructions' and
# the next '####' or '###' heading.
echo "A3: brainstorm/SKILL.md Phase 0.5 Processing Instructions has step 0 reading LANE"
PROC_BLOCK=$(awk '
  /^#### Processing Instructions$/ { in_block=1; next }
  in_block && /^####/ { in_block=0 }
  in_block && /^###[^#]/ { in_block=0 }
  in_block { print }
' "$BRAINSTORM_SKILL")
if printf '%s\n' "$PROC_BLOCK" | grep -qE '^0\.[[:space:]].*LANE'; then
  echo "  PASS: Phase 0.5 step 0 references LANE"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Phase 0.5 Processing Instructions step 0 (LANE-reading) not found"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Assertion 4: brainstorm/SKILL.md Phase 3.6 step 4 mentions lane: in spec.md frontmatter ---
echo "A4: brainstorm/SKILL.md Phase 3.6 prescribes 'lane:' in spec.md frontmatter"
P36_BLOCK=$(awk '
  /^### Phase 3\.6:/ { in_block=1; next }
  in_block && /^### / { in_block=0 }
  in_block { print }
' "$BRAINSTORM_SKILL")
if printf '%s\n' "$P36_BLOCK" | grep -qE 'lane:.*spec\.md|spec\.md.*lane:'; then
  echo "  PASS: Phase 3.6 mentions 'lane:' and spec.md together"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Phase 3.6 does not prescribe lane: in spec.md frontmatter"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Assertion 5: plan/SKILL.md Save Tasks section mentions lane: extraction from spec.md ---
echo "A5: plan/SKILL.md 'Save Tasks to Knowledge Base' section extracts lane: from spec.md"
SAVE_BLOCK=$(awk '
  /^## Save Tasks to Knowledge Base/ { in_block=1; next }
  in_block && /^## / { in_block=0 }
  in_block { print }
' "$PLAN_SKILL")
if printf '%s\n' "$SAVE_BLOCK" | grep -q "lane:" && printf '%s\n' "$SAVE_BLOCK" | grep -q "spec.md"; then
  echo "  PASS: plan/SKILL.md Save Tasks references lane: and spec.md"
  PASS=$((PASS + 1))
else
  echo "  FAIL: plan/SKILL.md Save Tasks does not extract lane: from spec.md"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Assertion 6: work/SKILL.md Phase 0 reads lane: AND announce includes lane conditionally ---
echo "A6: work/SKILL.md Phase 0 references 'lane:' and announces it conditionally"
P0_BLOCK=$(awk '
  /^### Phase 0:/ { in_block=1; next }
  in_block && /^### / { in_block=0 }
  in_block { print }
' "$WORK_SKILL")
if printf '%s\n' "$P0_BLOCK" | grep -q "lane:" && printf '%s\n' "$P0_BLOCK" | grep -qE 'lane=.*value|lane=<value>|append.*lane'; then
  echo "  PASS: work/SKILL.md Phase 0 reads lane: and conditionally announces it"
  PASS=$((PASS + 1))
else
  echo "  FAIL: work/SKILL.md Phase 0 missing lane: read or conditional announce"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Assertion 7: Parent audit spec FR4 says "three named lanes"; TR7 mentions "cross-domain" ---
echo "A7: feat-claude-skills-audit/spec.md FR4 = three-lane single-axis; TR7 = fail-closed cross-domain"
SPEC=$(cat "$AUDIT_SPEC")
assert_contains "$SPEC" "three" "audit spec mentions 'three' (lanes)"
# Pull the FR4 block and confirm it mentions all three canonical lane tokens together with
# the single-axis collapse note (catches a bare 'three named lanes' phrase that forgot to
# enumerate them).
FR4_BLOCK=$(awk '
  /^### FR4:/ { in_block=1; next }
  in_block && /^### / { in_block=0 }
  in_block { print }
' "$AUDIT_SPEC")
assert_contains "$FR4_BLOCK" "single-domain" "FR4 enumerates single-domain"
assert_contains "$FR4_BLOCK" "cross-domain" "FR4 enumerates cross-domain"
assert_contains "$FR4_BLOCK" "procedural" "FR4 enumerates procedural"
# TR7 must mention cross-domain (the fail-closed default).
TR7_BLOCK=$(awk '
  /^### TR7:/ { in_block=1; next }
  in_block && /^### / { in_block=0 }
  in_block { print }
' "$AUDIT_SPEC")
assert_contains "$TR7_BLOCK" "cross-domain" "TR7 specifies cross-domain fail-closed default"
echo ""

print_results
