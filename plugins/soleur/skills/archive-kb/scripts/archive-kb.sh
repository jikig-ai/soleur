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

  # Brainstorms and plans
  local file_dirs=(
    "knowledge-base/project/brainstorms"
    "knowledge-base/project/plans"
  )
  for dir in "${file_dirs[@]}"; do
    for f in "$dir"/*"${slug}"*; do
      [[ -f "$f" && "$f" != */archive/* ]] && artifacts+=("$f")
    done
  done

  # Specs
  if [[ -d "knowledge-base/project/specs/feat-${slug}" ]]; then
    artifacts+=("knowledge-base/project/specs/feat-${slug}")
  fi

  shopt -u nullglob

  printf '%s\n' "${artifacts[@]}"
}

ARTIFACTS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ARTIFACTS+=("$line")
done < <(discover_artifacts "$SLUG")

# A PARTIAL run must not read as a complete one (#8416).
#
# `discover_artifacts` derives ONE slug per run, and a feature's plan and spec
# routinely carry DIFFERENT slugs -- the plan is named for its topic, the spec
# for its branch. The plan glob (`*${slug}*`) then matches nothing, the spec
# probe matches, and the run prints `Archived 1 artifact(s)` and exits 0 with
# the plan silently left behind. SKILL.md has documented that gap in prose since
# it was first hit; it was hit again on #8325, which is the signal that prose was
# not the fix (`wg-when-a-workflow-gap-causes-a-mistake-fix`).
#
# This deliberately adds NO new discovery: #7400 tracks retiring the spec/plan
# discovery paths entirely, so widening them would build on a mechanism slated
# for removal. It only makes the ASYMMETRY audible -- one class found, the other
# silent -- which is the state a reader mistakes for completeness. The operand is
# the classes DISCOVERED, never a count, because a count cannot distinguish "the
# feature has no plan" from "the plan is named something else".
_found_class() {
  local want="$1" a
  for a in "${ARTIFACTS[@]}"; do
    [[ "$a" == knowledge-base/project/"${want}"/* ]] && return 0
  done
  return 1
}
if [[ ${#ARTIFACTS[@]} -gt 0 ]]; then
  _have_plan=no; _have_spec=no
  _found_class plans && _have_plan=yes
  _found_class specs && _have_spec=yes
  if [[ "$_have_plan" != "$_have_spec" ]]; then
    if [[ "$_have_plan" == no ]]; then
      _found="spec"; _missing="plan"; _hint="knowledge-base/project/plans/"
    else
      _found="plan"; _missing="spec"; _hint="knowledge-base/project/specs/feat-<slug>/"
    fi
    echo "WARNING: found a ${_found} for slug \"${SLUG}\" but NO ${_missing}." >&2
    echo "         A feature's plan and spec often carry different slugs, so this run may be" >&2
    echo "         incomplete. Check ${_hint} and re-run with the other slug if one exists." >&2
  fi
fi

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
