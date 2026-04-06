#!/usr/bin/env bash
set -euo pipefail

# Lint: scheduled workflows that create PRs via GITHUB_TOKEN must post
# synthetic check-runs for ALL required checks.
#
# Bot PRs created via GITHUB_TOKEN do not trigger CI (GitHub prevents
# infinite loops). Without synthetic check-runs for every required check,
# auto-merge is permanently blocked.
#
# Workflows where `gh pr create` only appears inside claude-code-action
# prompt blocks are exempt -- the App token (app/claude) triggers real CI.
#
# Refs: #826, #1468

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="${WORKFLOW_DIR:-.github/workflows}"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/required-checks.txt}"
PATTERN="scheduled-*.yml"

# --- Load required checks from config ---

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "FAIL: Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

required_checks=()
while IFS= read -r line; do
  # Strip comments and whitespace
  line="${line%%#*}"
  line="$(echo "$line" | tr -d '[:space:]')"
  [[ -z "$line" ]] && continue
  required_checks+=("$line")
done < "$CONFIG_FILE"

if [[ ${#required_checks[@]} -eq 0 ]]; then
  echo "FAIL: No required checks found in $CONFIG_FILE" >&2
  exit 1
fi

echo "Required synthetic checks: ${required_checks[*]}"
echo "---"

# --- Helper: check if file has gh pr create in a shell run: block ---
# Returns 0 (true) if gh pr create appears in a YAML run: block,
# returns 1 (false) if it only appears in prompt: blocks or similar.

has_shell_pr_create() {
  local file="$1"
  local in_run=false
  local run_indent=0

  while IFS= read -r wfline; do
    # Detect `run:` lines -- YAML shell steps
    if [[ "$wfline" =~ ^([[:space:]]*)run:[[:space:]]?\|?[[:space:]]*$ ]] || \
       [[ "$wfline" =~ ^([[:space:]]*)run:[[:space:]]+[^\|] ]]; then
      in_run=true
      # Capture indentation level of the run: key
      local prefix="${BASH_REMATCH[1]}"
      run_indent=${#prefix}
      continue
    fi

    if $in_run; then
      # Check if we've left the run: block (a new YAML key at same or lesser indent)
      if [[ "$wfline" =~ ^([[:space:]]*)[a-zA-Z_-]+: ]]; then
        local key_prefix="${BASH_REMATCH[1]}"
        if [[ ${#key_prefix} -le $run_indent ]]; then
          in_run=false
          continue
        fi
      fi

      if [[ "$wfline" == *"gh pr create"* ]]; then
        return 0
      fi
    fi
  done < "$file"

  return 1
}

# --- Scan workflows ---

failures=0
checked=0
skipped=0

for file in "$WORKFLOW_DIR"/$PATTERN; do
  [[ -f "$file" ]] || continue

  # Only check files that create PRs (anywhere in the file)
  grep -q "gh pr create" "$file" || continue

  # Check if gh pr create appears in a shell run: block
  if ! has_shell_pr_create "$file"; then
    # gh pr create only in prompt: blocks (App token handles CI)
    skipped=$((skipped + 1))
    echo "skip: $file (PR creation via claude-code-action App token)"
    continue
  fi

  checked=$((checked + 1))
  file_failures=()

  for check_name in "${required_checks[@]}"; do
    # Look for synthetic check-run creation patterns:
    # 1. Checks API: -f name=<check>
    # 2. Statuses API: -f context="<check>" or -f context=<check>
    if ! grep -qE "\-f name=${check_name}([[:space:]]|$)" "$file" && \
       ! grep -qE "\-f context=${check_name}([[:space:]]|$)" "$file" && \
       ! grep -qE "\-f context=\"${check_name}\"" "$file"; then
      file_failures+=("$check_name")
    fi
  done

  if [[ ${#file_failures[@]} -gt 0 ]]; then
    echo "FAIL: $file is missing synthetic check-runs for: ${file_failures[*]}"
    failures=$((failures + 1))
  else
    echo "ok: $file (all ${#required_checks[@]} synthetics present)"
  fi
done

echo "---"

if [[ "$checked" -eq 0 && "$skipped" -gt 0 ]]; then
  echo "All $skipped PR-creating workflow(s) use App tokens (no synthetics needed)."
  exit 0
fi

if [[ "$checked" -eq 0 ]]; then
  echo "No scheduled workflows with shell-based PR creation found."
  exit 0
fi

if [[ "$failures" -gt 0 ]]; then
  echo ""
  echo "$failures of $checked workflow(s) are missing synthetic check-runs."
  echo "Bot PRs from these workflows will deadlock on the CI Required ruleset."
  echo ""
  echo "Fix: add synthetic check-run posts for all required checks after 'gh pr create'."
  echo "See scheduled-weekly-analytics.yml for the correct pattern."
  echo "Required checks are defined in: $CONFIG_FILE"
  echo "Ref: #1468"
  exit 1
fi

echo "All $checked GITHUB_TOKEN workflow(s) post complete synthetic check-runs."
if [[ "$skipped" -gt 0 ]]; then
  echo "($skipped additional workflow(s) skipped -- PR creation via App token)"
fi
exit 0
