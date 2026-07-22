#!/usr/bin/env bash
# classify-rules.sh — one-shot rule classifier for the AGENTS.md sidecar split (#3493).
#
# Reads the registry file (default: AGENTS.md), classifies every rule into one of:
#   core      Hard Rules + Workflow Gates + [compliance-tier] + pdr-* + cm-*
#   docs-only Code Quality rules whose body matches eleventy/agents-md/markdown
#   rest      everything else (CQ runtime/TS/React/Postgres + Review & Feedback)
#
# Writes:
#   tools/migration/rule-classification.tsv (TAB-separated, one row per rule)
#
# Prints:
#   - per-class byte sums
#   - self-consistency gate verdict
#   - 5-PR spot-check savings table (requires `gh` + network; skipped on failure)
#
# Usage: bash tools/migration/classify-rules.sh [registry-path]
set -euo pipefail

REGISTRY="${1:-AGENTS.md}"
OUT_TSV="tools/migration/rule-classification.tsv"

if [[ ! -f "$REGISTRY" ]]; then
  echo "registry not found: $REGISTRY" >&2
  exit 2
fi

# Per-rule extraction. A rule is a single bullet line `- ... [id: <slug>] ...`.
# Bodies in this registry are always single-line (per cq-agents-md-why-single-line).
# Section is the last `## <Heading>` line seen above the rule.

awk -v out="$OUT_TSV" '
BEGIN {
  print "rule_id\tsection\tproposed_class\trationale\tbyte_count\tfirst_50_chars" > out
}
/^## / {
  section = substr($0, 4)
  next
}
/^- .*\[id: [a-z0-9-]+\]/ {
  line = $0
  match(line, /\[id: [a-z0-9-]+\]/)
  id_with_brackets = substr(line, RSTART, RLENGTH)
  id = substr(id_with_brackets, 6, length(id_with_brackets) - 6)

  has_compliance = (line ~ /\[compliance-tier\]/) ? 1 : 0
  prefix = substr(id, 1, index(id, "-") - 1)

  # Classification
  klass = "rest"
  rationale = "default"

  if (section == "Hard Rules") {
    klass = "core"; rationale = "Hard Rules → core"
  } else if (section == "Workflow Gates") {
    klass = "core"; rationale = "Workflow Gates → core"
  } else if (section == "Passive Domain Routing") {
    klass = "core"; rationale = "pdr → core"
  } else if (section == "Communication") {
    klass = "core"; rationale = "cm → core"
  } else if (has_compliance) {
    klass = "core"; rationale = "[compliance-tier] → core"
  } else if (section == "Code Quality") {
    if (line ~ /eleventy|Eleventy|AGENTS\.md|agents-md|\.njk|critical-css|screenshot-gate/) {
      klass = "docs-only"; rationale = "CQ eleventy/agents-md → docs-only"
    } else {
      klass = "rest"; rationale = "CQ runtime/TS/Postgres → rest"
    }
  } else if (section == "Review & Feedback") {
    klass = "rest"; rationale = "Review & Feedback → rest"
  } else {
    klass = "rest"; rationale = "unclassified section → rest"
  }

  bytes = length(line) + 1   # +1 for trailing newline
  preview = substr(line, 3, 50)
  gsub(/\t/, " ", preview)
  print id "\t" section "\t" klass "\t" rationale "\t" bytes "\t" preview >> out
  totals[klass] += bytes
  counts[klass] += 1
  grand_total += bytes
  grand_count += 1
}
END {
  printf "\n=== Classification summary ===\n"
  printf "  core      %5d bytes / %2d rules\n", totals["core"]+0,      counts["core"]+0
  printf "  docs-only %5d bytes / %2d rules\n", totals["docs-only"]+0, counts["docs-only"]+0
  printf "  rest      %5d bytes / %2d rules\n", totals["rest"]+0,      counts["rest"]+0
  printf "  TOTAL     %5d bytes / %2d rules\n", grand_total+0,          grand_count+0
  # HISTORICAL: the budgets below are the #3493 migration point-in-time targets,
  # not current thresholds. This is a one-shot tool that has already run and is
  # wired into no gate. The live authority is scripts/lint-agents-rule-budget.py,
  # enforced across consumers by scripts/lint-agents-compound-sync.sh -- do NOT
  # "sync" these numbers to it, and do not read them as drift (#6461).
  printf "\n=== Self-consistency gate (migration-time targets) ===\n"
  core_ok      = (totals["core"]+0      <= 18000) ? "PASS" : "FAIL"
  docs_rest_ok = ((totals["docs-only"]+0 + totals["rest"]+0) <= 12000) ? "PASS" : "FAIL"
  total_ok     = (grand_total+0 >= 22000 && grand_total+0 <= 28000) ? "PASS" : "FAIL"
  printf "  core ≤ 18000:                  %s (%d)\n", core_ok,      totals["core"]+0
  printf "  docs-only + rest ≤ 12000:      %s (%d)\n", docs_rest_ok, totals["docs-only"]+0 + totals["rest"]+0
  printf "  grand_total ∈ [22000, 28000]:  %s (%d)\n", total_ok,     grand_total+0
}
' "$REGISTRY"

echo ""
echo "=== TSV written: $OUT_TSV ==="
echo ""
echo "=== 5-PR spot-check (predicted load size per class) ==="
if ! command -v gh >/dev/null 2>&1; then
  echo "  gh not installed — skipping spot-check"
  exit 0
fi

# Classify a list of changed file paths against the same heuristics used by the loader hook.
# Same regexes as Phase 4 session-rules-loader.sh — single source of truth lives in this script
# (the loader inlines its own copy for tree-shaking; the two are tested for parity in Phase 6.5).
# Single source of truth — mirrored verbatim in
# `.claude/hooks/session-rules-loader.sh` and asserted by
# `tests/scripts/test_classifier_regex_parity.sh`. Update both files in
# lockstep or the parity test fails.
DOCS_RE='\.(md|markdown|txt|njk|html)$|^\.github/.*\.md$'
CODE_RE='\.(ts|tsx|js|jsx|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|rb)$'
INFRA_RE='\.tf$|^apps/[^/]+/infra/|\.github/workflows/|/?Dockerfile|/migrations/.*\.sql$'

classify_files() {
  local files="$1"
  local has_docs=0 has_code=0 has_infra=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ "$path" =~ $DOCS_RE  ]]; then has_docs=1;  fi
    if [[ "$path" =~ $CODE_RE  ]]; then has_code=1;  fi
    if [[ "$path" =~ $INFRA_RE ]]; then has_infra=1; fi
  done <<< "$files"
  local sum=$(( has_docs + has_code + has_infra ))
  if (( sum == 0 )); then echo "mixed"; return; fi
  if (( sum > 1 )); then echo "mixed"; return; fi
  if (( has_docs == 1 )); then echo "docs-only"; return; fi
  echo "rest"
}

printf "%-6s %-12s %s\n" "PR#" "predicted" "first 3 files"
gh pr list --base main --state merged --limit 5 --json number,files 2>/dev/null \
  | jq -r '.[] | [.number, (.files | map(.path) | join("\n"))] | @tsv' \
  | while IFS=$'\t' read -r prnum files; do
      kind=$(classify_files "$files")
      preview=$(echo "$files" | head -3 | tr '\n' ' ')
      printf "%-6s %-12s %s\n" "#$prnum" "$kind" "$preview"
    done
