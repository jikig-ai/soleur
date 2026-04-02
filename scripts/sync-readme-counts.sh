#!/usr/bin/env bash
# sync-readme-counts.sh — Update hardcoded component counts in README files
# from the filesystem.
#
# Usage: bash scripts/sync-readme-counts.sh [--check]
#   --check   Exit 1 if any README is out of date (for CI validation)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/soleur"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
fi

DRIFT=false

# --- Count components ---

count_md_recursive() {
  find "$1" -type f -name "*.md" -not -name "AGENTS.md" -not -name "README.md" | wc -l | tr -d '[:space:]'
}

AGENTS=$(count_md_recursive "$PLUGIN_DIR/agents")
SKILLS=$(find "$PLUGIN_DIR/skills" -type f -name "SKILL.md" | wc -l | tr -d '[:space:]')
COMMANDS=$(find "$PLUGIN_DIR/commands" -type f -name "*.md" | wc -l | tr -d '[:space:]')

echo "Component counts: ${AGENTS} agents, ${COMMANDS} commands, ${SKILLS} skills"

# --- Helper: check or update a single pattern ---

check_or_update() {
  local label="$1" file="$2" current="$3" expected="$4" pattern="$5" replacement="$6" delimiter="${7:-|}"

  if [[ "$current" != "$expected" ]]; then
    if $CHECK_ONLY; then
      echo "DRIFT: $label"
      echo "  have: $current"
      echo "  want: $expected"
      DRIFT=true
    else
      sed -i "s${delimiter}${pattern}${delimiter}${replacement}${delimiter}" "$file"
      echo "Updated: $label"
    fi
  fi
}

# --- Update root README.md ---

ROOT_README="$REPO_ROOT/README.md"

# Intro line: "NN agents across engineering..."
CURRENT=$(grep -E '^[0-9]+ agents across' "$ROOT_README" || true)
EXPECTED="${AGENTS} agents across engineering, finance, marketing, legal, operations, product, sales, and support -- compounding your company knowledge with every session."
check_or_update "root README intro line" "$ROOT_README" "$CURRENT" "$EXPECTED" \
  '^[0-9]\+ agents across.*' "$EXPECTED"

# "What is Soleur?" line: "**NN agents**, **N commands**, and **NN skills**"
CURRENT=$(grep -oE '\*\*[0-9]+ agents\*\*, \*\*[0-9]+ commands\*\*, and \*\*[0-9]+ skills\*\*' "$ROOT_README" || true)
EXPECTED="**${AGENTS} agents**, **${COMMANDS} commands**, and **${SKILLS} skills**"
check_or_update "root README 'What is Soleur?' counts" "$ROOT_README" "$CURRENT" "$EXPECTED" \
  '\*\*[0-9]\+ agents\*\*, \*\*[0-9]\+ commands\*\*, and \*\*[0-9]\+ skills\*\*' "$EXPECTED"

# --- Update plugin README.md ---

PLUGIN_README="$PLUGIN_DIR/README.md"

# Component count table rows: "| Agents | NN |" etc.
for pair in "Agents:$AGENTS" "Commands:$COMMANDS" "Skills:$SKILLS"; do
  LABEL="${pair%%:*}"
  COUNT="${pair#*:}"
  CURRENT=$(grep -oE "\\| ${LABEL} \\| [0-9]+ \\|" "$PLUGIN_README" || true)
  EXPECTED="| ${LABEL} | ${COUNT} |"
  check_or_update "plugin README ${LABEL} count" "$PLUGIN_README" "$CURRENT" "$EXPECTED" \
    "| ${LABEL} | [0-9]\+ |" "| ${LABEL} | ${COUNT} |" "#"
done

# Domain section headers: "### Marketing (NN)"
for domain_dir in "$PLUGIN_DIR/agents"/*/; do
  domain_name=$(basename "$domain_dir")

  # Validate directory name to prevent sed metacharacter injection
  if [[ ! "$domain_name" =~ ^[a-z-]+$ ]]; then
    echo "ERROR: unexpected domain directory name: $domain_name" >&2
    exit 1
  fi

  domain_count=$(count_md_recursive "$domain_dir")

  # Capitalize first letter for matching header
  domain_label="$(echo "${domain_name:0:1}" | tr '[:lower:]' '[:upper:]')${domain_name:1}"

  CURRENT_HEADER=$(grep -oE "^### ${domain_label} \\([0-9]+\\)" "$PLUGIN_README" || true)
  EXPECTED_HEADER="### ${domain_label} (${domain_count})"

  if [[ -z "$CURRENT_HEADER" ]]; then
    if $CHECK_ONLY; then
      echo "WARNING: no header found for domain '${domain_label}' (${domain_count} agents)"
    fi
    continue
  fi

  check_or_update "plugin README ${domain_label} domain count" "$PLUGIN_README" \
    "$CURRENT_HEADER" "$EXPECTED_HEADER" \
    "^### ${domain_label} ([0-9]\+)" "### ${domain_label} (${domain_count})"
done

# --- Result ---

if $CHECK_ONLY && $DRIFT; then
  echo ""
  echo "README counts are out of date. Run: bash scripts/sync-readme-counts.sh"
  exit 1
fi

echo "All README counts are in sync."
