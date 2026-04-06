#!/usr/bin/env bash
# rule-audit.sh -- Audit always-loaded governance rules for budget compliance
# and hook-enforced migration candidates.
#
# Usage: rule-audit.sh
#   No arguments. Reads environment variables for configuration.
#
# Environment variables:
#   GH_TOKEN   - GitHub token for issue creation (required in CI; optional locally)
#   GH_REPO    - GitHub repository in owner/repo format (required in CI; optional locally)
#   REPO_ROOT  - Override repository root (for testing; default: computed from script location)
#
# Exit codes:
#   0 - Audit complete (issue created, updated, or skipped)
#   1 - Required file missing or unrecoverable error
#
# Corresponding rules:
#   constitution.md "GitHub Actions workflows and shell scripts that create issues must include --milestone"
#   AGENTS.md "In GitHub Actions run: blocks, never indent heredoc body content"
#
# Related: #451, #422

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

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
  # Match lines like: - Some rule text [hook-enforced: guardrails.sh guardrails:block-commit-on-main]
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
  done || true  # grep exits 1 when no matches under pipefail
}

extract_hook_enforced "$AGENTS_MD" "AGENTS.md"
extract_hook_enforced "$CONSTITUTION_MD" "constitution.md"

AGENTS_HOOK_COUNT=$(grep -c '^AGENTS.md:' "$CANDIDATES_FILE" || true)
CONSTITUTION_HOOK_COUNT=$(grep -c '^constitution.md:' "$CANDIDATES_FILE" || true)
BROKEN_COUNT=$(wc -l < "$BROKEN_FILE" | tr -d ' ')

echo "Hook-enforced rules: AGENTS.md=$AGENTS_HOOK_COUNT, constitution.md=$CONSTITUTION_HOOK_COUNT"
echo "Broken hook references: $BROKEN_COUNT"

# --- Phase 2.5: Cross-Layer Duplicate Detection ---
# Compare AGENTS.md rules vs constitution.md rules using Jaccard word similarity.
# Pairs with score >= 0.6 after stopword removal are flagged as suspected duplicates.
# Related: #1304

detect_duplicates() {
  local duplicates_file="$TMPDIR_AUDIT/duplicates.txt"
  local all_rules="$TMPDIR_AUDIT/all_rules.tsv"

  # Extract rules as TAB-delimited: file\tlineno\ttext
  {
    grep -n '^- ' "$AGENTS_MD" 2>/dev/null \
      | sed 's/^\([0-9]*\):/AGENTS.md\t\1\t/' || true
    grep -n '^- ' "$CONSTITUTION_MD" 2>/dev/null \
      | sed 's/^\([0-9]*\):/constitution.md\t\1\t/' || true
  } > "$all_rules"

  # Single awk pass: tokenize all rules, compute pairwise Jaccard, emit matches.
  # Stopwords: articles, prepositions, pronouns, conjunctions.
  # Governance modals (never, always, must, should) are kept -- they carry polarity.
  awk -F'\t' '
  BEGIN {
    # Stopword set
    split("a an the is are was were be been to of in for on at by with from as " \
          "and or but if it its this that these those he she they them their " \
          "what which who whom do does did not", sw_arr)
    for (i in sw_arr) stopwords[sw_arr[i]] = 1
    n = 0
  }

  {
    file = $1; lineno = $2; text = $3
    # Strip leading "- "
    sub(/^- /, "", text)
    raw[n] = text
    files[n] = file
    lines[n] = lineno

    # Tokenize: lowercase, strip annotations, split on non-alnum
    t = tolower(text)
    gsub(/\[hook-enforced:[^\]]*\]/, "", t)
    gsub(/\[skill-enforced:[^\]]*\]/, "", t)
    gsub(/[^a-z0-9]/, " ", t)

    # Build unique word set, filtering stopwords
    delete words
    wcount = 0
    m = split(t, parts, " ")
    for (i = 1; i <= m; i++) {
      w = parts[i]
      if (w != "" && !(w in stopwords) && !(w in words)) {
        words[w] = 1
        wcount++
      }
    }

    # Store word set as space-separated string and count
    ws = ""
    for (w in words) ws = ws (ws == "" ? "" : " ") w
    wordsets[n] = ws
    wordcounts[n] = wcount
    n++
  }

  END {
    # Pairwise comparison: AGENTS.md rules vs constitution.md rules
    for (i = 0; i < n; i++) {
      if (files[i] != "AGENTS.md") continue
      if (wordcounts[i] < 4) continue

      # Build word set for rule i
      delete set_i
      split(wordsets[i], wi, " ")
      for (k in wi) set_i[wi[k]] = 1

      for (j = 0; j < n; j++) {
        if (files[j] != "constitution.md") continue
        if (wordcounts[j] < 4) continue

        # Compute intersection
        split(wordsets[j], wj, " ")
        common = 0
        for (k in wj) {
          if (wj[k] in set_i) common++
        }

        union = wordcounts[i] + wordcounts[j] - common
        if (union > 0) {
          score = int(common * 100 / union)
        } else {
          score = 0
        }

        if (score >= 60) {
          # Truncate display text to 60 chars, escape pipe for Markdown tables
          a_short = substr(raw[i], 1, 60)
          c_short = substr(raw[j], 1, 60)
          gsub(/\|/, "\\|", a_short)
          gsub(/\|/, "\\|", c_short)
          printf "%d\t%s\t%s\t%s\t%s\n", \
            score, lines[i], lines[j], a_short, c_short
        }
      }
    }
  }
  ' "$all_rules" | sort -t$'\t' -k1 -rn > "$duplicates_file"

  DUPLICATE_COUNT=$(wc -l < "$duplicates_file" | tr -d ' ')
  echo "Suspected cross-layer duplicates: $DUPLICATE_COUNT"
}

detect_duplicates

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
| Suspected duplicates | $DUPLICATE_COUNT |

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

# Append suspected duplicates section (file already sorted by detect_duplicates)
if [[ -s "$TMPDIR_AUDIT/duplicates.txt" ]]; then
  {
    echo ""
    echo "## Suspected Duplicates"
    echo ""
    echo "Rules in AGENTS.md and constitution.md with Jaccard word similarity >= 60%"
    echo "(after stopword removal). These may be candidates for consolidation."
    echo ""
    echo "| Similarity | AGENTS.md Line | constitution.md Line | Rule A (truncated) | Rule B (truncated) |"
    echo "|-----------|---------------|---------------------|--------------------|--------------------|"
    while IFS=$'\t' read -r score a_line c_line a_text c_text; do
      echo "| ${score}% | $a_line | $c_line | $a_text | $c_text |"
    done < "$TMPDIR_AUDIT/duplicates.txt"
  } >> "$ISSUE_BODY_FILE"
else
  {
    echo ""
    echo "## Suspected Duplicates"
    echo ""
    echo "*No cross-layer duplicates detected (Jaccard threshold: 60%).*"
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
