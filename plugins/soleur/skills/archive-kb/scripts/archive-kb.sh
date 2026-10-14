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

# Branch-diff discovery (#9803 follow-up): files ADDED or MODIFIED on this
# branch under the KB artifact roots are this feature's artifacts by commit
# provenance — no filename match needed. This is what catches a topic-named
# plan (`2026-10-08-fix-sandbox-hardening-cluster-plan.md` never matches the
# branch-derived slug) and a spec dir that is not `feat-<slug>` (the slug
# probe cannot reach `fix-*`/`chore-*` dirs). Spec FILES collapse to their
# spec DIR; archive/ paths are already archived and excluded. Unioned with
# the slug and untracked results — the three axes (name match, commit
# provenance, worktree state) cover what any one alone misses.
discover_branch_diff() {
  local base st f sub
  base=$(git merge-base HEAD origin/main 2>/dev/null | head -1) || return 0
  [[ -z "$base" ]] && return 0
  while IFS=$'\t' read -r st f; do
    case "$f" in
      */archive/*) ;;                                     # already archived
      # Spec files collapse to their DIR — but only on A rows (the branch
      # created the dir, so it is this feature's). An M row is a drive-by
      # edit to a sibling feature's live spec — collapsing it would archive
      # mid-flight work that is not ours.
      knowledge-base/project/specs/*/*)
        [[ "$st" == A* ]] || continue
        sub=${f#knowledge-base/project/specs/}
        printf 'knowledge-base/project/specs/%s\n' "${sub%%/*}" ;;
      knowledge-base/project/plans/*|knowledge-base/project/brainstorms/*)
        [[ -f "$f" ]] && printf '%s\n' "$f" ;;
    esac
  done < <(git diff --name-status --diff-filter=AM "$base"...HEAD -- \
      knowledge-base/project/plans \
      knowledge-base/project/brainstorms \
      knowledge-base/project/specs 2>/dev/null)
}
while IFS= read -r line; do
  [[ -n "$line" ]] && ARTIFACTS+=("$line")
done < <(discover_branch_diff | sort -u)

# Untracked-path discovery (#7383 residual): an UNCOMMITTED artifact is
# invisible to both axes above — the slug glob needs a filename match and
# branch-diff needs commit provenance, and a never-committed topic-named
# plan or non-`feat-*` spec dir has neither. `git status --porcelain` `??`
# rows are the only signal. `??` rows ONLY: staged/modified rows on tracked
# files are commit-provenance's job (a staged-but-never-committed file is
# #9172's class — noted, not fixed here). `--untracked-files=all` pins the
# `??` enumeration against `status.showUntrackedFiles` config (`no` would
# silently empty the axis; `normal` would collapse a fully-untracked dir to
# a bare `specs/` row the patterns below cannot reach). The `*/archive/*`
# exclusion and specs collapse mirror branch-diff: an untracked file inside
# `specs/<dir>/` emits `specs/<dir>`, while a lone ROOT-LEVEL file
# (`specs/.gitkeep`, `specs/notes.md`) has no second path component and does
# not fire. Plans/brainstorms root files DO fire — they are the artifacts.
discover_untracked() {
  local st f sub
  while IFS= read -r -d '' line; do
    st=${line:0:2}
    [[ "$st" == '??' ]] || continue
    f=${line:3}
    case "$f" in
      */archive/*) ;;                                     # already archived
      knowledge-base/project/specs/*/*)
        sub=${f#knowledge-base/project/specs/}
        sub=${sub%%/*}
        # Collapse to the dir ONLY when the dir is wholly untracked —
        # `??` carries no provenance, so a stray file inside a
        # partially-tracked spec dir (a sibling feature's live work, the
        # M-row rule's analog) must not pull the whole dir into the move.
        if git ls-files --error-unmatch -- "knowledge-base/project/specs/${sub}" >/dev/null 2>&1; then
          continue
        fi
        printf 'knowledge-base/project/specs/%s\n' "$sub" ;;
      knowledge-base/project/plans/*|knowledge-base/project/brainstorms/*)
        [[ -f "$f" ]] && printf '%s\n' "$f" ;;
    esac
  done < <(git status --porcelain -z --untracked-files=all -- \
      knowledge-base/project/plans \
      knowledge-base/project/brainstorms \
      knowledge-base/project/specs 2>/dev/null || true)
}
while IFS= read -r line; do
  [[ -n "$line" ]] && ARTIFACTS+=("$line")
done < <(discover_untracked | sort -u)

# Dedupe the union (an artifact reachable by more than one axis — e.g. an
# untracked slug-named file hits both the glob and `??` rows).
if [[ ${#ARTIFACTS[@]} -gt 0 ]]; then
  mapfile -t ARTIFACTS < <(printf '%s\n' "${ARTIFACTS[@]}" | sort -u)
fi

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
