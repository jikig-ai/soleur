#!/usr/bin/env bash
# sync-readme-counts.sh — Update hardcoded component counts in README files
# and knowledge-base docs from the filesystem.
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
DRIFT_DETAILS=()

# --- Defensive guards: verify component directories exist ---

for dir_name in agents skills commands; do
  if [[ ! -d "$PLUGIN_DIR/$dir_name" ]]; then
    echo "ERROR: required directory missing: $PLUGIN_DIR/$dir_name" >&2
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error::Required directory missing: plugins/soleur/$dir_name"
    fi
    exit 1
  fi
done

# --- Count components ---
# Aligned with docs/_data/stats.js: count ALL .md files (no exclusions)

count_md_recursive() {
  find "$1" -type f -name "*.md" | wc -l | tr -d '[:space:]'
}

AGENTS=$(count_md_recursive "$PLUGIN_DIR/agents")
SKILLS=$(find "$PLUGIN_DIR/skills" -type f -name "SKILL.md" | wc -l | tr -d '[:space:]')
COMMANDS=$(find "$PLUGIN_DIR/commands" -type f -name "*.md" | wc -l | tr -d '[:space:]')

# Zero-count guard: a zero count likely indicates a broken directory or path
for pair in "agents:$AGENTS" "skills:$SKILLS" "commands:$COMMANDS"; do
  label="${pair%%:*}"
  count="${pair#*:}"
  if [[ "$count" -eq 0 ]]; then
    echo "ERROR: $label count is 0 — directory may be empty or misconfigured: $PLUGIN_DIR/$label" >&2
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error::$label count is 0 — directory may be empty or misconfigured"
    fi
    exit 1
  fi
done

echo "Component counts: ${AGENTS} agents, ${COMMANDS} commands, ${SKILLS} skills"

# --- Build dynamic domain list for intro line ---
# Enumerates non-empty domain directories under agents/, matching stats.js logic

build_domain_list() {
  local domains=()
  for domain_dir in "$PLUGIN_DIR/agents"/*/; do
    [[ -d "$domain_dir" ]] || continue
    local name
    name=$(basename "$domain_dir")
    local count
    count=$(count_md_recursive "$domain_dir")
    if [[ "$count" -gt 0 ]]; then
      # Capitalize each hyphen-separated word: customer-success → Customer Success
      local capitalized=""
      IFS='-' read -ra parts <<< "$name"
      for i in "${!parts[@]}"; do
        local part="${parts[$i]}"
        part="$(echo "${part:0:1}" | tr '[:lower:]' '[:upper:]')${part:1}"
        if [[ $i -gt 0 ]]; then
          capitalized+=" "
        fi
        capitalized+="$part"
      done
      domains+=("$capitalized")
    fi
  done

  # Format as "a, b, c, and d"
  local len=${#domains[@]}
  if [[ $len -eq 0 ]]; then
    echo ""
  elif [[ $len -eq 1 ]]; then
    echo "${domains[0]}"
  elif [[ $len -eq 2 ]]; then
    echo "${domains[0]} and ${domains[1]}"
  else
    local result=""
    for ((i = 0; i < len - 1; i++)); do
      result+="${domains[$i]}, "
    done
    result+="and ${domains[$((len - 1))]}"
    echo "$result"
  fi
}

# Convert domain list to lowercase for the README intro line
DOMAIN_LIST=$(build_domain_list | tr '[:upper:]' '[:lower:]')

# --- Helper: check or update a single pattern ---

check_or_update() {
  local label="$1" file="$2" current="$3" expected="$4" pattern="$5" replacement="$6" delimiter="${7:-|}"

  if [[ "$current" != "$expected" ]]; then
    if $CHECK_ONLY; then
      DRIFT_DETAILS+=("$label|have: $current|want: $expected")
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
EXPECTED="${AGENTS} agents across ${DOMAIN_LIST} -- compounding your company knowledge with every session."
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

  # Capitalize each hyphen-separated word: customer-success → Customer Success
  domain_label=""
  IFS='-' read -ra parts <<< "$domain_name"
  for i in "${!parts[@]}"; do
    part="${parts[$i]}"
    part="$(echo "${part:0:1}" | tr '[:lower:]' '[:upper:]')${part:1}"
    if [[ $i -gt 0 ]]; then
      domain_label+=" "
    fi
    domain_label+="$part"
  done

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
  echo "=== README Count Drift Summary ==="
  echo ""
  for detail in "${DRIFT_DETAILS[@]}"; do
    IFS='|' read -r label have want <<< "$detail"
    echo "DRIFT: $label"
    echo "  $have"
    echo "  $want"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error::Drift in $label — $have; $want"
    fi
    echo ""
  done
  echo "Component counts are out of date. Run: bash scripts/sync-readme-counts.sh"
  exit 1
fi

echo "All component counts are in sync."
