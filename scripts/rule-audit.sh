#!/usr/bin/env bash
# rule-audit.sh -- Audit always-loaded governance rules for budget compliance
# and hook-enforced migration candidates.
#
# Usage: rule-audit.sh
#   No arguments. Reads environment variables for configuration.
#
# Environment variables:
#   GH_TOKEN  - GitHub token for issue creation (required in CI; optional locally)
#   GH_REPO   - GitHub repository in owner/repo format (required in CI; optional locally)
#
# Exit codes:
#   0 - Audit complete (issue created, updated, or skipped)
#   1 - Required file missing or unrecoverable error
#
# Corresponding rules:
#   AGENTS.md "Every gh issue create must include --milestone"
#   AGENTS.md "In GitHub Actions run: blocks, never indent heredoc body content"
#
# Related: #451, #422

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENTS_MD="$REPO_ROOT/AGENTS.md"
CONSTITUTION_MD="$REPO_ROOT/knowledge-base/project/constitution.md"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
THRESHOLD=300
TODAY=$(date -u +%Y-%m-%d)
ISSUE_TITLE="chore: rule audit findings ($TODAY)"
ISSUE_SEARCH="rule audit findings in:title"

# --- Preflight ---

if [[ ! -f "$AGENTS_MD" ]]; then
  echo "ERROR: AGENTS.md not found at $AGENTS_MD" >&2
  exit 1
fi

if [[ ! -f "$CONSTITUTION_MD" ]]; then
  echo "ERROR: constitution.md not found at $CONSTITUTION_MD" >&2
  exit 1
fi

# --- Phase 1: Count Rules ---

AGENTS_COUNT=$(grep -c '^- ' "$AGENTS_MD" || true)
CONSTITUTION_COUNT=$(grep -c '^- ' "$CONSTITUTION_MD" || true)
TOTAL=$((AGENTS_COUNT + CONSTITUTION_COUNT))

if [[ "$TOTAL" -gt "$THRESHOLD" ]]; then
  OVER="true"
  DELTA=$((TOTAL - THRESHOLD))
  BUDGET_STATUS="OVER by $DELTA"
else
  OVER="false"
  DELTA=$((THRESHOLD - TOTAL))
  BUDGET_STATUS="Under by $DELTA"
fi

echo "Rule budget: $TOTAL always-loaded rules (AGENTS.md: $AGENTS_COUNT, constitution.md: $CONSTITUTION_COUNT)"
echo "Threshold: $THRESHOLD | Status: $BUDGET_STATUS"

# --- Phase 2: Extract Hook-Enforced Rules ---

TMPDIR_AUDIT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_AUDIT"' EXIT

CANDIDATES_FILE="$TMPDIR_AUDIT/candidates.txt"
BROKEN_FILE="$TMPDIR_AUDIT/broken.txt"
touch "$CANDIDATES_FILE" "$BROKEN_FILE"

extract_hook_enforced() {
  local file="$1"
  local label="$2"
  # Match lines like: - Some rule text [hook-enforced: guardrails.sh Guard 1]
  # Skip template/placeholder references like [hook-enforced: <script> <guard>]
  grep -n '\[hook-enforced:' "$file" 2>/dev/null | grep -v '<script>' | while IFS= read -r line; do
    local lineno="${line%%:*}"
    local content="${line#*:}"
    # Extract the hook reference: script name (and optional guard label)
    local hook_ref
    hook_ref=$(echo "$content" | sed -n 's/.*\[hook-enforced: *\([^]]*\)\].*/\1/p')
    local script_name
    script_name=$(echo "$hook_ref" | awk '{print $1}')
    local script_path="$HOOKS_DIR/$script_name"

    if [[ -f "$script_path" ]]; then
      echo "$label:$lineno|$hook_ref|$content" >> "$CANDIDATES_FILE"
    else
      echo "$label:$lineno|$hook_ref|MISSING: $script_path" >> "$BROKEN_FILE"
    fi
  done
}

extract_hook_enforced "$AGENTS_MD" "AGENTS.md"
extract_hook_enforced "$CONSTITUTION_MD" "constitution.md"

AGENTS_HOOK_COUNT=$(grep -c '^AGENTS.md:' "$CANDIDATES_FILE" || true)
CONSTITUTION_HOOK_COUNT=$(grep -c '^constitution.md:' "$CANDIDATES_FILE" || true)
BROKEN_COUNT=$(wc -l < "$BROKEN_FILE" | tr -d ' ')

echo "Hook-enforced rules: AGENTS.md=$AGENTS_HOOK_COUNT, constitution.md=$CONSTITUTION_HOOK_COUNT"
echo "Broken hook references: $BROKEN_COUNT"

# --- Phase 3: Build Issue Body ---

ISSUE_BODY_FILE="$TMPDIR_AUDIT/issue-body.md"

cat > "$ISSUE_BODY_FILE" << BODY_EOF
## Rule Budget Report ($TODAY)

| Metric | Value |
|--------|-------|
| AGENTS.md rules | $AGENTS_COUNT |
| constitution.md rules | $CONSTITUTION_COUNT |
| **Total always-loaded** | **$TOTAL** |
| Threshold | $THRESHOLD |
| Status | $BUDGET_STATUS |

## Migration Candidates

Hook-enforced rules in AGENTS.md are candidates for migration to constitution.md.
They already have mechanical enforcement (Tier 1), so the AGENTS.md copy (Tier 2)
is redundant defense-in-depth. Moving them to constitution.md (Tier 3) preserves
documentation without per-turn context cost in the sharpest-edge tier.

BODY_EOF

if [[ "$AGENTS_HOOK_COUNT" -gt 0 ]]; then
  {
    echo "| Line | Hook Reference | Rule (truncated) |"
    echo "|------|---------------|-----------------|"
    grep '^AGENTS.md:' "$CANDIDATES_FILE" | while IFS='|' read -r loc hook_ref content; do
      lineno="${loc#AGENTS.md:}"
      # Truncate rule text to 80 chars
      rule_text=$(echo "$content" | sed 's/^- //' | cut -c1-80)
      echo "| $lineno | \`$hook_ref\` | $rule_text |"
    done
  } >> "$ISSUE_BODY_FILE"
else
  echo "*No AGENTS.md rules with hook enforcement found.*" >> "$ISSUE_BODY_FILE"
fi

if [[ "$BROKEN_COUNT" -gt 0 ]]; then
  {
    echo ""
    echo "## Broken Hook References"
    echo ""
    echo "These rules reference hook scripts that no longer exist:"
    echo ""
    echo "| Location | Hook Reference | Status |"
    echo "|----------|---------------|--------|"
    while IFS='|' read -r loc hook_ref status; do
      echo "| $loc | \`$hook_ref\` | $status |"
    done < "$BROKEN_FILE"
  } >> "$ISSUE_BODY_FILE"
fi

cat >> "$ISSUE_BODY_FILE" << 'TIER_EOF'

## Enforcement Tier Model

| Tier | Layer | Context Cost | When to Use |
|------|-------|-------------|-------------|
| 1 | PreToolUse hooks | Zero | Mechanical enforcement |
| 2 | AGENTS.md | Always loaded | Sharp edges |
| 3 | constitution.md | Always loaded | Conventions and judgment |
| 4 | Agent descriptions | On reference | Domain-specific guidance |
| 5 | Skill instructions | On invocation | Workflow-specific procedures |

**Migration direction:** Rules should live at the cheapest tier that provides
adequate enforcement. When a rule gains hook enforcement (Tier 1), its prose
version can migrate from Tier 2 → Tier 3.

---

*Generated by `scripts/rule-audit.sh` ([#451](https://github.com/jikig-ai/soleur/issues/451))*
TIER_EOF

echo "Issue body written to $ISSUE_BODY_FILE"

# --- Phase 4: Create or Update Issue ---

# Skip gh operations if GH_TOKEN is not set (local testing without issue creation)
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN not set -- skipping issue creation (dry run)."
  echo "--- Issue body preview ---"
  cat "$ISSUE_BODY_FILE"
  exit 0
fi

GH_REPO="${GH_REPO:-}"
REPO_FLAG=""
if [[ -n "$GH_REPO" ]]; then
  REPO_FLAG="--repo $GH_REPO"
fi

# Title-based dedup: check for existing open issue
EXISTING=""
gh_with_retry() {
  local attempt=1
  while [[ $attempt -le 2 ]]; do
    if "$@" 2>/dev/null; then
      return 0
    fi
    if [[ $attempt -eq 1 ]]; then
      echo "gh command failed, retrying in 60s..." >&2
      sleep 60
    fi
    attempt=$((attempt + 1))
  done
  echo "gh command failed after 2 attempts" >&2
  return 1
}

EXISTING=$(gh issue list $REPO_FLAG --state open \
  --search "$ISSUE_SEARCH" \
  --json number --jq '.[0].number // empty' 2>/dev/null || true)

if [[ -n "$EXISTING" ]]; then
  echo "Existing open issue found: #$EXISTING -- adding comment."
  gh_with_retry gh issue comment "$EXISTING" $REPO_FLAG \
    --body-file "$ISSUE_BODY_FILE"
  echo "Comment added to #$EXISTING."
else
  echo "No existing open issue -- creating new issue."
  gh_with_retry gh issue create $REPO_FLAG \
    --title "$ISSUE_TITLE" \
    --body-file "$ISSUE_BODY_FILE" \
    --milestone "Post-MVP / Later"
  echo "Issue created: $ISSUE_TITLE"
fi
