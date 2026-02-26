#!/bin/bash

# Git Worktree Manager
# Handles creating, listing, switching, and cleaning up Git worktrees
# KISS principle: Simple, interactive, opinionated

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get repo root
GIT_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR="$GIT_ROOT/.worktrees"

# Ensure .worktrees is in .gitignore
ensure_gitignore() {
  if ! grep -q "^\.worktrees$" "$GIT_ROOT/.gitignore" 2>/dev/null; then
    echo ".worktrees" >> "$GIT_ROOT/.gitignore"
  fi
}

# Copy .env files from main repo to worktree
copy_env_files() {
  local worktree_path="$1"

  echo -e "${BLUE}Copying environment files...${NC}"

  # Find all .env* files in root (excluding .env.example which should be in git)
  local env_files=()
  for f in "$GIT_ROOT"/.env*; do
    if [[ -f "$f" ]]; then
      local basename=$(basename "$f")
      # Skip .env.example (that's typically committed to git)
      if [[ "$basename" != ".env.example" ]]; then
        env_files+=("$basename")
      fi
    fi
  done

  if [[ ${#env_files[@]} -eq 0 ]]; then
    echo -e "  ${YELLOW}ℹ️  No .env files found in main repository${NC}"
    return
  fi

  local copied=0
  for env_file in "${env_files[@]}"; do
    local source="$GIT_ROOT/$env_file"
    local dest="$worktree_path/$env_file"

    if [[ -f "$dest" ]]; then
      echo -e "  ${YELLOW}⚠️  $env_file already exists, backing up to ${env_file}.backup${NC}"
      cp "$dest" "${dest}.backup"
    fi

    cp "$source" "$dest"
    echo -e "  ${GREEN}✓ Copied $env_file${NC}"
    copied=$((copied + 1))
  done

  echo -e "  ${GREEN}✓ Copied $copied environment file(s)${NC}"
}

# Create a new worktree
create_worktree() {
  local branch_name="$1"
  local from_branch="${2:-main}"

  if [[ -z "$branch_name" ]]; then
    echo -e "${RED}Error: Branch name required${NC}"
    exit 1
  fi

  local worktree_path="$WORKTREE_DIR/$branch_name"

  # Check if worktree already exists
  if [[ -d "$worktree_path" ]]; then
    echo -e "${YELLOW}Worktree already exists at: $worktree_path${NC}"
    echo -e "Switch to it instead? (y/n)"
    read -r response
    if [[ "$response" == "y" ]]; then
      switch_worktree "$branch_name"
    fi
    return
  fi

  echo -e "${BLUE}Creating worktree: $branch_name${NC}"
  echo "  From: $from_branch"
  echo "  Path: $worktree_path"
  echo ""
  echo "Proceed? (y/n)"
  read -r response

  if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    return
  fi

  # Update main branch
  echo -e "${BLUE}Updating $from_branch...${NC}"
  git checkout "$from_branch"
  git pull origin "$from_branch" || true

  # Create worktree
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # Copy environment files
  copy_env_files "$worktree_path"

  echo -e "${GREEN}✓ Worktree created successfully!${NC}"
  echo ""
  echo "To switch to this worktree:"
  echo -e "${BLUE}cd $worktree_path${NC}"
  echo ""
}

# Create a worktree for a feature with spec directory
# Simplified version: no prompts, just creates everything
create_for_feature() {
  local name="$1"
  local from_branch="${2:-main}"

  if [[ -z "$name" ]]; then
    echo -e "${RED}Error: Feature name required${NC}"
    echo "Usage: worktree-manager.sh feature <name> [from-branch]"
    exit 1
  fi

  local branch_name="feat-$name"
  local worktree_path="$WORKTREE_DIR/$branch_name"
  local spec_dir="$GIT_ROOT/knowledge-base/specs/$branch_name"

  # Check if worktree already exists
  if [[ -d "$worktree_path" ]]; then
    echo -e "${YELLOW}Worktree already exists: $worktree_path${NC}"
    echo -e "${BLUE}Spec directory: $spec_dir${NC}"
    return 0
  fi

  echo -e "${BLUE}Creating feature: $name${NC}"
  echo "  Branch: $branch_name"
  echo "  Worktree: $worktree_path"
  echo "  Spec dir: $spec_dir"
  echo ""

  # Update base branch before creating worktree
  echo -e "${BLUE}Updating $from_branch...${NC}"
  git checkout "$from_branch"
  git pull origin "$from_branch" || true

  # Ensure directories exist
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  # Create worktree with new branch
  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # Create spec directory in main repo (shared across worktrees)
  if [[ -d "$GIT_ROOT/knowledge-base" ]]; then
    mkdir -p "$spec_dir"
    echo -e "${GREEN}Created spec directory: $spec_dir${NC}"
  fi

  # Copy environment files
  copy_env_files "$worktree_path"

  echo ""
  echo -e "${GREEN}Feature setup complete!${NC}"
  echo ""
  echo "Next steps:"
  echo -e "  1. ${BLUE}cd $worktree_path${NC}"
  echo -e "  2. Create spec: ${BLUE}knowledge-base/specs/$branch_name/spec.md${NC}"
  echo ""
}

# List all worktrees
list_worktrees() {
  echo -e "${BLUE}Available worktrees:${NC}"
  echo ""

  if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo -e "${YELLOW}No worktrees found${NC}"
    return
  fi

  local count=0
  for worktree_path in "$WORKTREE_DIR"/*; do
    if [[ -d "$worktree_path" && -d "$worktree_path/.git" ]]; then
      count=$((count + 1))
      local worktree_name=$(basename "$worktree_path")
      local branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

      if [[ "$PWD" == "$worktree_path" ]]; then
        echo -e "${GREEN}✓ $worktree_name${NC} (current) → branch: $branch"
      else
        echo -e "  $worktree_name → branch: $branch"
      fi
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}No worktrees found${NC}"
  else
    echo ""
    echo -e "${BLUE}Total: $count worktree(s)${NC}"
  fi

  echo ""
  echo -e "${BLUE}Main repository:${NC}"
  local main_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  echo "  Branch: $main_branch"
  echo "  Path: $GIT_ROOT"
}

# Switch to a worktree
switch_worktree() {
  local worktree_name="$1"

  if [[ -z "$worktree_name" ]]; then
    list_worktrees
    echo -e "${BLUE}Switch to which worktree? (enter name)${NC}"
    read -r worktree_name
  fi

  local worktree_path="$WORKTREE_DIR/$worktree_name"

  if [[ ! -d "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree not found: $worktree_name${NC}"
    echo ""
    list_worktrees
    exit 1
  fi

  echo -e "${GREEN}Switching to worktree: $worktree_name${NC}"
  cd "$worktree_path"
  echo -e "${BLUE}Now in: $(pwd)${NC}"
}

# Copy env files to an existing worktree (or current directory if in a worktree)
copy_env_to_worktree() {
  local worktree_name="$1"
  local worktree_path

  if [[ -z "$worktree_name" ]]; then
    # Check if we're currently in a worktree
    local current_dir=$(pwd)
    if [[ "$current_dir" == "$WORKTREE_DIR"/* ]]; then
      worktree_path="$current_dir"
      worktree_name=$(basename "$worktree_path")
      echo -e "${BLUE}Detected current worktree: $worktree_name${NC}"
    else
      echo -e "${YELLOW}Usage: worktree-manager.sh copy-env [worktree-name]${NC}"
      echo "Or run from within a worktree to copy to current directory"
      list_worktrees
      return 1
    fi
  else
    worktree_path="$WORKTREE_DIR/$worktree_name"

    if [[ ! -d "$worktree_path" ]]; then
      echo -e "${RED}Error: Worktree not found: $worktree_name${NC}"
      list_worktrees
      return 1
    fi
  fi

  copy_env_files "$worktree_path"
  echo ""
}

# Clean up completed worktrees
cleanup_worktrees() {
  if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo -e "${YELLOW}No worktrees to clean up${NC}"
    return
  fi

  echo -e "${BLUE}Checking for completed worktrees...${NC}"
  echo ""

  local found=0
  local to_remove=()

  for worktree_path in "$WORKTREE_DIR"/*; do
    if [[ -d "$worktree_path" && -d "$worktree_path/.git" ]]; then
      local worktree_name=$(basename "$worktree_path")

      # Skip if current worktree
      if [[ "$PWD" == "$worktree_path" ]]; then
        echo -e "${YELLOW}(skip) $worktree_name - currently active${NC}"
        continue
      fi

      found=$((found + 1))
      to_remove+=("$worktree_path")
      echo -e "${YELLOW}• $worktree_name${NC}"
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo -e "${GREEN}No inactive worktrees to clean up${NC}"
    return
  fi

  echo ""
  echo -e "Remove $found worktree(s)? (y/n)"
  read -r response

  if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    return
  fi

  echo -e "${BLUE}Cleaning up worktrees...${NC}"
  for worktree_path in "${to_remove[@]}"; do
    local worktree_name=$(basename "$worktree_path")
    git worktree remove "$worktree_path" --force 2>/dev/null || true
    echo -e "${GREEN}✓ Removed: $worktree_name${NC}"
  done

  # Clean up empty directory if nothing left
  if [[ -z "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
    rmdir "$WORKTREE_DIR" 2>/dev/null || true
  fi

  echo -e "${GREEN}Cleanup complete!${NC}"
}

# Archive KB artifact files matching a slug from a flat directory
# Usage: archive_kb_files <dir> <slug> <label> <verbose>
archive_kb_files() {
  local dir="$1"
  local slug="$2"
  local label="$3"
  local verbose="$4"
  [[ -d "$dir" ]] || return 0
  local archive_dir="$dir/archive"
  mkdir -p "$archive_dir"
  for f in "$dir"/*"$slug"*; do
    [[ -f "$f" && "$f" != */archive/* ]] || continue
    local fname ts
    fname=$(basename "$f")
    ts="$(date +%Y-%m-%d-%H%M%S)"
    if ! mv "$f" "$archive_dir/$ts-$fname" 2>/dev/null; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not archive $label $fname${NC}"
    fi
  done
}

# Clean up worktrees for merged branches (detects [gone] status)
cleanup_merged_worktrees() {
  # Determine output mode: verbose if TTY, quiet otherwise
  local verbose=false
  [[ -t 1 ]] && verbose=true

  # Fetch to update remote tracking info
  local fetch_error
  if ! fetch_error=$(git fetch --prune 2>&1); then
    [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not fetch from remote: $fetch_error${NC}"
    return 0
  fi

  # Find branches with [gone] tracking (robust detection)
  local gone_branches
  gone_branches=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads 2>/dev/null | grep '\[gone\]' | cut -d' ' -f1)

  if [[ -z "$gone_branches" ]]; then
    [[ "$verbose" == "true" ]] && echo -e "${GREEN}No merged branches to clean up${NC}"
    return 0
  fi

  # Build a map of branch -> actual worktree path using git's porcelain output.
  # This is essential because branch names use slashes (feat/fix-x) but worktree
  # directories use hyphens (feat-fix-x), so we cannot construct paths from branch names.
  local -A branch_to_worktree
  local current_wt_path="" current_wt_branch=""
  while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
      current_wt_path="${line#worktree }"
    elif [[ "$line" == "branch refs/heads/"* ]]; then
      current_wt_branch="${line#branch refs/heads/}"
      branch_to_worktree["$current_wt_branch"]="$current_wt_path"
    elif [[ -z "$line" ]]; then
      current_wt_path=""
      current_wt_branch=""
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  local cleaned=()

  for branch in $gone_branches; do
    local worktree_path="${branch_to_worktree[$branch]:-}"
    local safe_branch
    safe_branch=$(echo "$branch" | tr '/' '-')
    local spec_dir="$GIT_ROOT/knowledge-base/specs/$safe_branch"
    local archive_dir="$GIT_ROOT/knowledge-base/specs/archive"

    # Skip if active worktree
    if [[ -n "$worktree_path" && "$PWD" == "$worktree_path"* ]]; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) $branch - currently active${NC}"
      continue
    fi

    # Skip if worktree has uncommitted changes (safety check)
    # Always print this warning since uncommitted changes need user attention
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
      local status
      status=$(git -C "$worktree_path" status --porcelain 2>/dev/null)
      if [[ -n "$status" ]]; then
        echo -e "${YELLOW}(skip) $branch - has uncommitted changes${NC}"
        continue
      fi
    fi

    # Archive spec directory if exists (timestamp prevents collisions)
    if [[ -d "$spec_dir" ]]; then
      local archive_name
      archive_name="$(date +%Y-%m-%d-%H%M%S)-$safe_branch"
      local archive_path="$archive_dir/$archive_name"

      mkdir -p "$archive_dir"
      if ! mv "$spec_dir" "$archive_path" 2>/dev/null; then
        [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not archive spec for $branch${NC}"
      fi
    fi

    # Extract feature slug by stripping all known branch prefixes
    local feature_slug="$safe_branch"
    feature_slug="${feature_slug#feat-}"
    feature_slug="${feature_slug#fix-}"
    feature_slug="${feature_slug#feature-}"

    # Archive brainstorms and plans matching the feature slug
    archive_kb_files "$GIT_ROOT/knowledge-base/brainstorms" "$feature_slug" "brainstorm" "$verbose"
    archive_kb_files "$GIT_ROOT/knowledge-base/plans" "$feature_slug" "plan" "$verbose"

    # Remove worktree if exists (use actual path from git, not constructed path)
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
      if ! git worktree remove "$worktree_path" 2>/dev/null; then
        # Retry with --force for edge cases (e.g., untracked files from interrupted archival)
        if ! git worktree remove "$worktree_path" --force 2>/dev/null; then
          [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not remove worktree for $branch${NC}"
          continue
        fi
      fi
    fi

    # Delete branch - force delete since [gone] means remote was deleted (PR merged or intentionally deleted)
    # Using -D because local main may be behind, causing -d to fail even for merged branches
    if ! git branch -D "$branch" 2>/dev/null; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not delete branch $branch${NC}"
    fi

    cleaned+=("$branch")
  done

  # Output summary
  if [[ ${#cleaned[@]} -gt 0 ]]; then
    echo -e "${GREEN}Cleaned ${#cleaned[@]} merged worktree(s): ${cleaned[*]}${NC}"

    # After cleanup, update main checkout so next worktree branches from latest
    # Only check tracked file changes (staged + unstaged) -- untracked files cannot
    # conflict with a fast-forward pull and should not block the update
    if ! git -C "$GIT_ROOT" diff --quiet HEAD 2>/dev/null || ! git -C "$GIT_ROOT" diff --cached --quiet 2>/dev/null; then
      echo -e "${YELLOW}Warning: Main checkout has uncommitted changes to tracked files -- skipping pull${NC}"
    else
      local current_branch
      current_branch=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
        git -C "$GIT_ROOT" checkout main 2>/dev/null || git -C "$GIT_ROOT" checkout master 2>/dev/null || true
      fi
      local pull_output
      if pull_output=$(git -C "$GIT_ROOT" pull --ff-only origin main 2>&1); then
        echo -e "${GREEN}Updated main to latest${NC}"
      else
        echo -e "${YELLOW}Warning: Could not pull latest main: $pull_output${NC}"
      fi
    fi
  fi

  return 0
}

# Main command handler
main() {
  local command="${1:-list}"

  case "$command" in
    create)
      create_worktree "$2" "$3"
      ;;
    feature|feat)
      create_for_feature "$2" "$3"
      ;;
    list|ls)
      list_worktrees
      ;;
    switch|go)
      switch_worktree "$2"
      ;;
    copy-env|env)
      copy_env_to_worktree "$2"
      ;;
    cleanup|clean)
      cleanup_worktrees
      ;;
    cleanup-merged)
      cleanup_merged_worktrees
      ;;
    help)
      show_help
      ;;
    *)
      echo -e "${RED}Unknown command: $command${NC}"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

show_help() {
  cat << EOF
Git Worktree Manager

Usage: worktree-manager.sh <command> [options]

Commands:
  create <branch-name> [from-branch]  Create new worktree (copies .env files automatically)
                                      (from-branch defaults to main)
  feature | feat <name> [from-branch] Create worktree for feature with spec directory
                                      (creates feat-<name> branch + knowledge-base/specs/feat-<name>/)
  list | ls                           List all worktrees
  switch | go [name]                  Switch to worktree
  copy-env | env [name]               Copy .env files from main repo to worktree
                                      (if name omitted, uses current worktree)
  cleanup | clean                     Clean up inactive worktrees
  cleanup-merged                      Clean up worktrees for merged branches
                                      (detects [gone] branches, archives specs)
  help                                Show this help message

Environment Files:
  - Automatically copies .env, .env.local, .env.test, etc. on create
  - Skips .env.example (should be in git)
  - Creates .backup files if destination already exists
  - Use 'copy-env' to refresh env files after main repo changes

Examples:
  worktree-manager.sh feature user-auth        # Creates feat-user-auth branch + spec dir
  worktree-manager.sh create feature-login
  worktree-manager.sh create feature-auth develop
  worktree-manager.sh switch feature-login
  worktree-manager.sh copy-env feature-login
  worktree-manager.sh copy-env                   # copies to current worktree
  worktree-manager.sh cleanup
  worktree-manager.sh list

EOF
}

# Run
main "$@"
