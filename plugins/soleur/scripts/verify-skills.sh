#!/usr/bin/env bash
set -euo pipefail

# Skill Verification
# Validates all SKILL.md files: name match, description length, duplicates, word count.
# Run from any directory -- resolves plugin root from script location.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/skills"

errors=0
skill_count=0
total_words=0
names=()

for skill_dir in "$SKILLS_DIR"/*/; do
  skill_file="$skill_dir/SKILL.md"
  [[ -f "$skill_file" ]] || continue
  skill_count=$((skill_count + 1))
  dir_name=$(basename "$skill_dir")

  # Extract name from frontmatter
  name=$(sed -n '/^---$/,/^---$/{ /^---$/d; p }' "$skill_file" | grep '^name:' | head -1 | sed 's/^name: *//' | tr -d '"')
  if [[ -z "$name" ]]; then
    echo "[error] $dir_name: missing name in frontmatter" >&2
    errors=$((errors + 1))
    continue
  fi

  # Check name matches directory
  if [[ "$name" != "$dir_name" ]]; then
    echo "[error] $dir_name: name '$name' does not match directory" >&2
    errors=$((errors + 1))
  fi

  # Extract description
  desc=$(sed -n '/^---$/,/^---$/{ /^---$/d; p }' "$skill_file" | grep '^description:' | head -1 | sed 's/^description: *//' | tr -d '"')
  desc_len=${#desc}
  if [[ "$desc_len" -gt 1024 ]]; then
    echo "[error] $dir_name: description exceeds 1024 chars ($desc_len)" >&2
    errors=$((errors + 1))
  fi

  # Word count
  word_count=$(echo "$desc" | wc -w | tr -d ' ')
  total_words=$((total_words + word_count))

  names+=("$name")
done

# Check duplicates
dupes=$(printf '%s\n' "${names[@]}" | sort | uniq -d || true)
if [[ -n "$dupes" ]]; then
  echo "[error] duplicate skill names: $dupes" >&2
  errors=$((errors + 1))
fi

echo "[info] $skill_count skills, $total_words description words, $errors errors"
if [[ "$errors" -gt 0 ]]; then
  exit 1
fi
echo "[ok] all skills verified"
