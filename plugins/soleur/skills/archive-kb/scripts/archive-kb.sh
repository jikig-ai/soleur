#!/usr/bin/env bash
set -euo pipefail

# Archive knowledge-base artifacts for a feature branch.
# Moves brainstorms, plans, and specs to archive/ subdirectories
# with timestamped prefixes, preserving git history.
#
# Usage: archive-kb.sh [--dry-run] [slug]
#   --dry-run  Show what would be archived without executing
#   slug       Feature slug (default: derived from current branch)

readonly SCRIPT_NAME="archive-kb.sh"

# --- Argument Parsing ---

DRY_RUN=false
EXPLICIT_SLUG=""

usage() {
  echo "Usage: ${SCRIPT_NAME} [--dry-run] [slug]" >&2
  echo "  --dry-run  Show what would be archived without executing" >&2
  echo "  slug       Feature slug (default: derived from current branch)" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    -*)
      echo "Error: Unknown flag: $1" >&2
      usage
      ;;
    *)
      if [[ -n "$EXPLICIT_SLUG" ]]; then
        echo "Error: Multiple slug arguments provided" >&2
        usage
      fi
      EXPLICIT_SLUG="$1"
      shift
      ;;
  esac
done

# --- Environment Checks ---

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Not inside a git repository" >&2
  exit 1
fi

if [[ ! -d "knowledge-base" ]]; then
  echo "No knowledge-base directory found"
  exit 0
fi

# --- Slug Derivation ---

derive_slug() {
  local branch safe slug
  branch=$(git rev-parse --abbrev-ref HEAD)
  # Normalize slashes to hyphens
  safe=$(echo "$branch" | tr '/' '-')
  slug="$safe"
  # Strip prefixes in sequence (order matters: feature- before feat-)
  slug="${slug#feature-}"
  slug="${slug#feat-}"
  slug="${slug#fix-}"
  echo "$slug"
}

if [[ -n "$EXPLICIT_SLUG" ]]; then
  SLUG="$EXPLICIT_SLUG"
else
  SLUG=$(derive_slug)
fi

if [[ -z "$SLUG" ]]; then
  echo "Error: Could not derive feature slug from branch name" >&2
  exit 1
fi

# --- Discovery ---

discover_artifacts() {
  local slug="$1"
  local artifacts=()

  # Enable nullglob so empty globs expand to nothing
  shopt -s nullglob

  # Brainstorms: files matching *slug* excluding archive/
  for f in knowledge-base/brainstorms/*"${slug}"*; do
    [[ -f "$f" && "$f" != */archive/* ]] && artifacts+=("$f")
  done

  # Plans: files matching *slug* excluding archive/
  for f in knowledge-base/plans/*"${slug}"*; do
    [[ -f "$f" && "$f" != */archive/* ]] && artifacts+=("$f")
  done

  # Specs: exact directory match feat-<slug>
  if [[ -d "knowledge-base/specs/feat-${slug}" ]]; then
    artifacts+=("knowledge-base/specs/feat-${slug}")
  fi

  shopt -u nullglob

  printf '%s\n' "${artifacts[@]}"
}

ARTIFACTS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ARTIFACTS+=("$line")
done < <(discover_artifacts "$SLUG")

# --- No artifacts case ---

if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
  echo "No artifacts found for slug \"${SLUG}\""
  exit 0
fi

# --- Timestamp (generated once for consistency) ---

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Dry-run mode ---

print_archive_path() {
  local artifact="$1"
  local ts="$2"
  local name dest_dir
  name=$(basename "$artifact")
  dest_dir=$(dirname "$artifact")
  echo "  ${artifact} -> ${dest_dir}/archive/${ts}-${name}"
}

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run -- would archive ${#ARTIFACTS[@]} artifact(s) for slug \"${SLUG}\":"
  for artifact in "${ARTIFACTS[@]}"; do
    print_archive_path "$artifact" "$TIMESTAMP"
  done
  exit 0
fi

# --- Archival Execution ---

archive_artifact() {
  local artifact="$1"
  local ts="$2"
  local name dest_dir archive_dir
  name=$(basename "$artifact")
  dest_dir=$(dirname "$artifact")
  archive_dir="${dest_dir}/archive"

  mkdir -p "$archive_dir"
  # git add handles both untracked files and already-tracked files (no-op)
  git add "$artifact"
  git mv "$artifact" "${archive_dir}/${ts}-${name}"
  echo "  ${archive_dir}/${ts}-${name}"
}

echo "Archived ${#ARTIFACTS[@]} artifact(s) for slug \"${SLUG}\":"

for artifact in "${ARTIFACTS[@]}"; do
  archive_artifact "$artifact" "$TIMESTAMP"
done
