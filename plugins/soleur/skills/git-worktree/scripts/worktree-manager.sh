#!/usr/bin/env bash

# Git Worktree Manager
# Handles creating, listing, switching, and cleaning up Git worktrees
# KISS principle: Simple, interactive, opinionated
#
# BARE REPO NOTE: This repo uses core.bare=true with extensions.worktreeConfig=true
# and repositoryformatversion=1. The per-worktree config (.git/config.worktree)
# holds core.bare=true ONLY for the bare root; linked worktrees inherit
# core.bare=false by default. On-disk files at the bare root are never updated
# by git -- they become stale after every merge. The IS_BARE flag (computed at
# init) guards all working-tree-dependent operations. If this script crashes with
# "must be run in a work tree", the on-disk copy is stale. Run from a worktree
# instead, or use: worktree-manager.sh sync-bare

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resolve this script's own directory so callers inside worktrees can reference it
# without knowing where plugins/ lives relative to their CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-confirm flag (--yes skips all interactive prompts)
YES_FLAG=false

# Get repo root and detect bare repo (single subprocess for both)
# IS_BARE: true when the parent/root repo is bare (affects fetch strategy, file sync)
# IS_IN_WORKTREE: true when running from inside a worktree (has a working tree)
# Must also detect when running from a worktree whose parent repo is bare,
# since git rev-parse --is-bare-repository returns false inside worktrees.
IS_BARE=false
IS_IN_WORKTREE=false
if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  IS_IN_WORKTREE=true
fi
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  IS_BARE=true
  _git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null)
  if [[ "$_git_dir" == */.git ]]; then
    GIT_ROOT="${_git_dir%/.git}"
  else
    GIT_ROOT="$_git_dir"
  fi
else
  GIT_ROOT=$(git rev-parse --show-toplevel)
  # Check if we're in a worktree of a bare repo
  _common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ -n "$_common_dir" ]] && git -C "$_common_dir" rev-parse --is-bare-repository 2>/dev/null | grep -q true; then
    IS_BARE=true
    # GIT_ROOT should point to the bare repo, not the worktree
    if [[ "$_common_dir" == */.git ]]; then
      GIT_ROOT="${_common_dir%/.git}"
    else
      GIT_ROOT="$_common_dir"
    fi
  fi
fi
WORKTREE_DIR="$GIT_ROOT/.worktrees"

# Exit with error if running at the bare repo root (no working tree available).
# Allows execution from worktrees of bare repos (IS_BARE=true but IS_IN_WORKTREE=true).
require_working_tree() {
  if [[ "$IS_BARE" == "true" && "$IS_IN_WORKTREE" != "true" ]]; then
    echo -e "${RED}Error: Cannot run from bare repo root (no working tree available).${NC}"
    echo -e "${YELLOW}Run from an existing worktree, or use: git worktree add .worktrees/<name> -b <branch> main${NC}"
    exit 1
  fi
}

# Ensure bare repo config uses per-worktree core.bare (defense-in-depth).
# Fixes TWO broken states that git worktree add creates on bare repos:
#   1. core.bare=true in shared config — bleeds into worktrees, breaks git commit/push
#   2. core.bare=false + core.worktree=<path> in shared config — "do not make sense" warning
# Both are caused by git worktree add writing to the shared config on bare repos.
# Fix: core.bare must ONLY exist in .git/config.worktree, never in .git/config.
# Called before AND after git worktree add (add re-corrupts the shared config).
# Safe for parallel sessions: all operations are idempotent.
ensure_bare_config() {
  local git_dir="$GIT_ROOT/.git"
  # Only relevant for bare repos (git dir IS the repo root)
  if [[ ! -d "$git_dir" ]]; then
    git_dir="$GIT_ROOT"
  fi

  local shared_config="$git_dir/config"
  local wt_config="$git_dir/config.worktree"
  local fixed=false

  # Ensure prerequisites for per-worktree config
  git config --file "$shared_config" core.repositoryformatversion 1
  git config --file "$shared_config" extensions.worktreeConfig true

  # Remove core.bare from shared config (any value — it belongs in per-worktree only)
  if git config --file "$shared_config" core.bare &>/dev/null; then
    echo -e "${BLUE}Fixing bare repo config: removing core.bare from shared config...${NC}"
    git config --file "$shared_config" --unset core.bare
    fixed=true
  fi

  # Remove stale core.worktree from shared config (leftover from worktree operations)
  if git config --file "$shared_config" core.worktree &>/dev/null; then
    echo -e "${BLUE}Fixing bare repo config: removing stale core.worktree from shared config...${NC}"
    git config --file "$shared_config" --unset core.worktree
    fixed=true
  fi

  # Ensure per-worktree config has core.bare=true for the bare root
  local current_bare
  current_bare=$(git config --file "$wt_config" core.bare 2>/dev/null || echo "")
  if [[ "$current_bare" != "true" ]]; then
    git config --file "$wt_config" core.bare true
    fixed=true
  fi

  if [[ "$fixed" == "true" ]]; then
    echo -e "${GREEN}Fixed: core.bare per-worktree only, no stale core.worktree${NC}"
  fi
}

# Ensure .worktrees is in .gitignore
ensure_gitignore() {
  if ! grep -q "^\.worktrees$" "$GIT_ROOT/.gitignore" 2>/dev/null; then
    echo ".worktrees" >> "$GIT_ROOT/.gitignore"
  fi
}

# Update a branch ref to latest remote, handling bare vs non-bare repos.
# In bare repos: uses fetch with refspec (no working tree needed).
# In non-bare repos: uses checkout + pull.
update_branch_ref() {
  local branch="$1"
  echo -e "${BLUE}Updating $branch...${NC}"
  if [[ "$IS_BARE" == "true" && "$IS_IN_WORKTREE" != "true" ]]; then
    # Bare repo root: no working tree, so use fetch with refspec
    if git fetch origin "$branch:$branch" 2>/dev/null; then
      echo -e "${GREEN}Updated $branch to latest (via fetch)${NC}"
    elif git fetch origin "$branch" 2>/dev/null; then
      echo -e "${YELLOW}Warning: Could not fast-forward local $branch -- using origin/$branch${NC}"
    fi
  else
    git checkout "$branch"
    git pull origin "$branch" || true
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

# Install dependencies in a newly created worktree
install_deps() {
  local worktree_path="$1"

  # --- Root-level dependency install ---
  if [[ -f "$worktree_path/package.json" ]] && [[ ! -d "$worktree_path/node_modules" ]]; then
    if ! command -v bun &>/dev/null; then
      echo -e "  ${YELLOW}Warning: bun not found -- install root dependencies manually${NC}" >&2
    else
      echo -e "${BLUE}Installing dependencies...${NC}"
      local install_output
      if install_output=$(bun install --frozen-lockfile --cwd "$worktree_path" 2>&1); then
        echo -e "  ${GREEN}Dependencies installed${NC}"
      else
        echo -e "  ${YELLOW}Warning: bun install failed -- run manually in the worktree${NC}" >&2
        echo "  $install_output" >&2
      fi
    fi
  fi

  # --- Subdirectory dependency install ---
  # Scan apps/*/ for package.json files and install per-directory.
  # Follows the same null-glob-safe pattern as copy_env_files().
  local app_dir
  for app_dir in "$worktree_path"/apps/*/; do
    [[ -d "$app_dir" ]] || continue
    [[ -f "$app_dir/package.json" ]] || continue
    [[ -d "$app_dir/node_modules" ]] && continue

    local app_name
    app_name=$(basename "$app_dir")

    local -a install_cmd=()
    if [[ -f "$app_dir/bun.lockb" ]] || [[ -f "$app_dir/bun.lock" ]]; then
      if command -v bun &>/dev/null; then
        install_cmd=(bun install --frozen-lockfile --cwd "$app_dir")
      else
        echo -e "  ${YELLOW}Warning: $app_name has bun lockfile but bun not found -- skip${NC}" >&2
        continue
      fi
    elif [[ -f "$app_dir/package-lock.json" ]]; then
      if command -v npm &>/dev/null; then
        install_cmd=(npm ci --prefix "$app_dir")
      else
        echo -e "  ${YELLOW}Warning: $app_name has package-lock.json but npm not found -- skip${NC}" >&2
        continue
      fi
    elif [[ -f "$app_dir/yarn.lock" ]]; then
      if command -v yarn &>/dev/null; then
        install_cmd=(yarn install --frozen-lockfile --cwd "$app_dir")
      else
        echo -e "  ${YELLOW}Warning: $app_name has yarn.lock but yarn not found -- skip${NC}" >&2
        continue
      fi
    else
      echo -e "  ${YELLOW}Warning: $app_name has package.json but no lockfile -- skip${NC}" >&2
      continue
    fi

    echo -e "${BLUE}Installing dependencies for $app_name...${NC}"
    local app_install_output
    if app_install_output=$("${install_cmd[@]}" 2>&1); then
      echo -e "  ${GREEN}$app_name dependencies installed${NC}"
    else
      echo -e "  ${YELLOW}Warning: $app_name install failed -- run manually${NC}" >&2
      echo "  $app_install_output" >&2
    fi
  done
}

# Create a new worktree
create_worktree() {
  ensure_bare_config
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
    local response="n"
    if [[ "$YES_FLAG" == "true" ]]; then
      response="y"
    else
      echo -e "Switch to it instead? (y/n)"
      read -r response
    fi
    if [[ "$response" == "y" ]]; then
      switch_worktree "$branch_name"
    fi
    return
  fi

  echo -e "${BLUE}Creating worktree: $branch_name${NC}"
  echo "  From: $from_branch"
  echo "  Path: $worktree_path"
  echo ""
  local response
  if [[ "$YES_FLAG" == "true" ]]; then
    response="y"
  else
    echo "Proceed? (y/n)"
    read -r response
  fi

  if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    return
  fi

  # Update base branch (bare-aware)
  update_branch_ref "$from_branch"

  # Create worktree
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # git worktree add on bare repos writes core.bare=false to shared config — fix it
  ensure_bare_config

  # Fast-fail: verify directory was created before expensive git checks
  if [[ ! -d "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree directory not created at $worktree_path${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    exit 1
  fi

  # Verify the worktree was actually created (git worktree add can silently fail on bare repos)
  local actual_toplevel
  if ! actual_toplevel=$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null); then
    echo -e "${RED}Error: Worktree creation failed — $worktree_path is not a valid git worktree${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi
  if [[ "$actual_toplevel" != "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree path mismatch — expected $worktree_path, got $actual_toplevel${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi

  # Copy environment files
  copy_env_files "$worktree_path"

  # Install dependencies
  install_deps "$worktree_path"

  echo -e "${GREEN}✓ Worktree created successfully!${NC}"
  echo ""
  echo "To switch to this worktree:"
  echo -e "${BLUE}cd $worktree_path${NC}"
  echo ""
}

# Create a worktree for a feature with spec directory
# Simplified version: no prompts, just creates everything
create_for_feature() {
  ensure_bare_config
  local name="$1"
  local from_branch="${2:-main}"

  if [[ -z "$name" ]]; then
    echo -e "${RED}Error: Feature name required${NC}"
    echo "Usage: worktree-manager.sh feature <name> [from-branch]"
    exit 1
  fi

  local branch_name="feat-$name"
  local worktree_path="$WORKTREE_DIR/$branch_name"
  local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$branch_name"

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

  # Update base branch (bare-aware)
  update_branch_ref "$from_branch"

  # Ensure directories exist
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  # Create worktree with new branch
  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # git worktree add on bare repos writes core.bare=false to shared config — fix it
  ensure_bare_config

  # Fast-fail: verify directory was created before expensive git checks
  if [[ ! -d "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree directory not created at $worktree_path${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    exit 1
  fi

  # Verify the worktree was actually created (git worktree add can silently fail on bare repos)
  local actual_toplevel
  if ! actual_toplevel=$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null); then
    echo -e "${RED}Error: Worktree creation failed — $worktree_path is not a valid git worktree${NC}"
    echo -e "${YELLOW}Hint: Try 'git worktree add $worktree_path -b $branch_name $from_branch' directly${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi
  if [[ "$actual_toplevel" != "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree path mismatch — expected $worktree_path, got $actual_toplevel${NC}"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path" 2>/dev/null || true
    exit 1
  fi

  # Create spec directory in main repo (shared across worktrees)
  if [[ -d "$GIT_ROOT/knowledge-base" ]]; then
    mkdir -p "$spec_dir"
    echo -e "${GREEN}Created spec directory: $spec_dir${NC}"
  fi

  # Copy environment files
  copy_env_files "$worktree_path"

  # Install dependencies
  install_deps "$worktree_path"

  echo ""
  echo -e "${GREEN}Feature setup complete!${NC}"
  echo ""
  echo "Next steps:"
  echo -e "  1. ${BLUE}cd $worktree_path${NC}"
  echo -e "  2. Create spec: ${BLUE}knowledge-base/project/specs/$branch_name/spec.md${NC}"
  echo -e "  3. Open draft PR: ${BLUE}bash $SCRIPT_DIR/worktree-manager.sh draft-pr${NC}"
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
    if [[ -d "$worktree_path" && -e "$worktree_path/.git" ]]; then
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
  if [[ "$IS_BARE" == "true" ]]; then
    echo -e "${YELLOW}Bare root (no working tree):${NC}"
    echo "  Path: $GIT_ROOT"
  else
    echo -e "${BLUE}Main repository:${NC}"
    local main_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo "  Branch: $main_branch"
    echo "  Path: $GIT_ROOT"
  fi
}

# Switch to a worktree
switch_worktree() {
  local worktree_name="$1"

  if [[ -z "$worktree_name" ]]; then
    if [[ "$YES_FLAG" == "true" ]]; then
      echo -e "${RED}Error: --yes requires a worktree name argument${NC}"
      exit 1
    fi
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
    if [[ -d "$worktree_path" && -e "$worktree_path/.git" ]]; then
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
  local response
  if [[ "$YES_FLAG" == "true" ]]; then
    response="y"
  else
    echo -e "Remove $found worktree(s)? (y/n)"
    read -r response
  fi

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

# Clean up orphan directories in .worktrees/ that aren't registered as git worktrees.
# These can be left behind by interrupted worktree creation, manual deletion of .git files,
# or other edge cases where the directory exists but git doesn't know about it.
cleanup_orphan_worktree_dirs() {
  local verbose="${1:-false}"
  [[ ! -d "$WORKTREE_DIR" ]] && return 0

  # Build set of registered worktree paths
  local -A registered_paths
  while IFS= read -r line; do
    if [[ "$line" == "worktree "* ]]; then
      registered_paths["${line#worktree }"]=1
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  local orphans_cleaned=0
  for dir in "$WORKTREE_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue
    # Normalize path (remove trailing slash)
    dir="${dir%/}"
    if [[ -z "${registered_paths[$dir]:-}" ]]; then
      # Not a registered worktree — check if it's safe to remove (no .git file = definitely orphaned)
      if [[ ! -f "$dir/.git" ]]; then
        rm -rf "$dir"
        orphans_cleaned=$((orphans_cleaned + 1))
        [[ "$verbose" == "true" ]] && echo -e "${BLUE}Removed orphan directory: $(basename "$dir")${NC}"
      else
        [[ "$verbose" == "true" ]] && echo -e "${YELLOW}(skip) orphan $(basename "$dir") - has .git file, run 'git worktree prune' first${NC}"
      fi
    fi
  done

  if [[ $orphans_cleaned -gt 0 ]]; then
    [[ "$verbose" == "true" ]] && echo -e "${GREEN}Cleaned $orphans_cleaned orphan directory(ies)${NC}"
  fi
}

# Clean up worktrees for merged branches (detects [gone] and merged-to-main)
cleanup_merged_worktrees() {
  # Fix bare repo config if broken (defense-in-depth on every session start)
  ensure_bare_config

  # Determine output mode: verbose if TTY, quiet otherwise
  local verbose=false
  [[ -t 1 ]] && verbose=true

  # Fetch to update remote tracking info
  local fetch_error
  if ! fetch_error=$(git fetch --prune 2>&1); then
    [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not fetch from remote: $fetch_error${NC}"
    return 0
  fi

  # Find stale branches using two complementary detection methods:
  # 1. [gone] tracking: remote branch was deleted (e.g., GitHub auto-delete after PR merge)
  # 2. Merged to main: branch is fully merged but remote still exists (e.g., auto-delete disabled)
  local gone_branches
  gone_branches=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads 2>/dev/null | grep '\[gone\]' | cut -d' ' -f1 || true)

  local merged_branches
  # git branch uses: * = current, + = checked out in another worktree
  # Strip all prefix markers and whitespace, then exclude main/master and current branch
  merged_branches=$(git branch --merged main 2>/dev/null \
    | sed 's/^[*+[:space:]]*//' \
    | grep -v -E '^(main|master)$' \
    || true)

  # Combine both lists, deduplicate
  local all_stale_branches
  all_stale_branches=$(printf '%s\n%s' "$gone_branches" "$merged_branches" | sort -u | sed '/^$/d' || true)

  if [[ -z "$all_stale_branches" ]]; then
    [[ "$verbose" == "true" ]] && echo -e "${GREEN}No merged branches to clean up${NC}"
    # Still check for orphan directories below
    cleanup_orphan_worktree_dirs "$verbose"
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

  for branch in $all_stale_branches; do
    local worktree_path="${branch_to_worktree[$branch]:-}"
    local safe_branch
    safe_branch=$(echo "$branch" | tr '/' '-')
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

    # Archive spec directory
    local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$safe_branch"
    if [[ -d "$spec_dir" ]]; then
      local archive_dir archive_name archive_path
      archive_dir="$(dirname "$spec_dir")/archive"
      archive_name="$(date +%Y-%m-%d-%H%M%S)-$safe_branch"
      archive_path="$archive_dir/$archive_name"

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
    archive_kb_files "$GIT_ROOT/knowledge-base/project/brainstorms" "$feature_slug" "brainstorm" "$verbose"
    archive_kb_files "$GIT_ROOT/knowledge-base/project/plans" "$feature_slug" "plan" "$verbose"

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

    # Delete remote branch if it still exists (prevents stale remote refs from accumulating)
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      if git push origin --delete "$branch" 2>/dev/null; then
        [[ "$verbose" == "true" ]] && echo -e "${BLUE}Deleted remote branch: $branch${NC}"
      fi
    fi

    # Delete local branch
    if ! git branch -D "$branch" 2>/dev/null; then
      [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not delete branch $branch${NC}"
    fi

    cleaned+=("$branch")
  done

  # Output summary
  if [[ ${#cleaned[@]} -gt 0 ]]; then
    echo -e "${GREEN}Cleaned ${#cleaned[@]} merged worktree(s): ${cleaned[*]}${NC}"

    # After cleanup, update main checkout so next worktree branches from latest
    # Skip entirely for bare repos -- there is no working tree to update
    if [[ "$IS_BARE" == "true" ]]; then
      # Bare repos have no working tree -- use fetch with refspec to update the
      # local main ref directly (plain "fetch origin main" only updates FETCH_HEAD
      # and origin/main, leaving local main stale for new worktree creation)
      if git fetch origin main:main 2>/dev/null; then
        echo -e "${GREEN}Updated main to latest${NC}"
      elif git fetch origin main 2>/dev/null; then
        # Fallback: non-fast-forward (e.g., force-push) -- at least update origin/main
        echo -e "${YELLOW}Warning: Could not fast-forward local main -- fetched origin/main only${NC}"
      fi
      # Auto-sync stale on-disk files so the next session reads current versions
      sync_bare_files
    else
      # Auto-reset stale index/working tree on main checkout.
      # Direct commits to main are prohibited (hook-enforced), so staged or
      # unstaged changes are always stale debris from index drift (e.g., fetch
      # moved HEAD but index was never updated). Reset to HEAD before pulling.
      if ! git -C "$GIT_ROOT" diff --quiet HEAD 2>/dev/null || ! git -C "$GIT_ROOT" diff --cached --quiet 2>/dev/null; then
        local stale_count
        stale_count=$(git -C "$GIT_ROOT" diff --cached --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "0")
        echo -e "${YELLOW}Resetting stale main checkout ($stale_count staged files)${NC}"
        git -C "$GIT_ROOT" reset --hard HEAD >/dev/null 2>&1
      fi
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

  # Clean up orphan directories in .worktrees/ that aren't registered as git worktrees
  cleanup_orphan_worktree_dirs "$verbose"

  # Always clean up stale Claude tmp files (RAM-backed, can be huge)
  cleanup_claude_tmp

  # Kill runaway processes that waste CPU (e.g., stuck gst-plugin-scanner)
  cleanup_runaway_processes

  return 0
}

# Clean up stale Claude Code temp files to reclaim RAM.
# Claude stores task output in /tmp/claude-<uid>/<project>/<session>/tasks/.
# These files sit on tmpfs (RAM-backed). Runaway task outputs can consume tens
# of GB and starve the system. This function identifies session directories that
# no longer correspond to a running Claude process and removes their task output.
cleanup_claude_tmp() {
  local uid
  uid=$(id -u)
  local claude_tmp="/tmp/claude-$uid"

  if [[ ! -d "$claude_tmp" ]]; then
    return 0
  fi

  # Collect session IDs from running Claude processes (--resume <id> or conversation ID)
  local active_sessions=()
  while IFS= read -r pid; do
    # Read /proc/<pid>/cmdline -- args are NUL-separated
    local cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
    # Extract --resume argument (session ID)
    local session_id
    session_id=$(echo "$cmdline" | grep -oP '(?<=--resume )[0-9a-f-]+' || true)
    if [[ -n "$session_id" ]]; then
      active_sessions+=("$session_id")
    fi
  done < <(pgrep -u "$uid" -x claude 2>/dev/null || true)

  local total_freed=0
  local files_removed=0

  # Walk each project directory
  for project_dir in "$claude_tmp"/*/; do
    [[ -d "$project_dir" ]] || continue

    for session_dir in "$project_dir"/*/; do
      [[ -d "$session_dir" ]] || continue
      local session_id
      session_id=$(basename "$session_dir")

      # Skip active sessions
      local is_active=false
      for active in "${active_sessions[@]+"${active_sessions[@]}"}"; do
        if [[ "$active" == "$session_id" ]]; then
          is_active=true
          break
        fi
      done
      if [[ "$is_active" == "true" ]]; then
        continue
      fi

      # Remove task output files from stale sessions
      local tasks_dir="$session_dir/tasks"
      if [[ -d "$tasks_dir" ]]; then
        for output_file in "$tasks_dir"/*.output; do
          [[ -f "$output_file" ]] || continue
          # Skip symlinks (they point to subagent logs and are tiny)
          [[ -L "$output_file" ]] && continue
          local size_kb
          size_kb=$(stat -c%s "$output_file" 2>/dev/null || echo 0)
          size_kb=$((size_kb / 1024))
          # Only remove files > 1 MB to avoid removing small, harmless files
          if [[ $size_kb -gt 1024 ]]; then
            local size_mb=$((size_kb / 1024))
            rm -f "$output_file"
            total_freed=$((total_freed + size_mb))
            files_removed=$((files_removed + 1))
          fi
        done
      fi

      # If the session directory is now empty (or only has empty subdirs), remove it
      if [[ -z "$(find "$session_dir" -type f 2>/dev/null | head -1)" ]]; then
        rm -rf "$session_dir" 2>/dev/null || true
      fi
    done

    # Remove project dir if empty
    if [[ -z "$(ls -A "$project_dir" 2>/dev/null)" ]]; then
      rmdir "$project_dir" 2>/dev/null || true
    fi
  done

  if [[ $files_removed -gt 0 ]]; then
    echo -e "${GREEN}Cleaned $files_removed stale Claude task output(s), freed ~${total_freed} MB${NC}"
  fi
}

# Kill runaway processes that waste CPU/memory during development sessions.
# Known offenders:
#   - gst-plugin-scanner: GStreamer media scanner spawned by GNOME's localsearch-3
#     (Tracker file indexer). Gets stuck in infinite CPU loops scanning dev repos.
#     Safe to kill -- GNOME re-indexes on next login if needed.
# Only targets processes owned by the current user and running longer than the
# CPU time threshold (avoids killing short-lived legitimate scans).
cleanup_runaway_processes() {
  local killed=0

  # gst-plugin-scanner: kill instances using >5 min of CPU time
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pid cputime
    pid=$(echo "$line" | awk '{print $1}')
    cputime=$(echo "$line" | awk '{print $2}')
    # cputime format: [DD-]HH:MM:SS or MM:SS -- extract minutes
    local minutes=0
    if [[ "$cputime" == *-* ]]; then
      # DD-HH:MM:SS format (days of CPU time -- definitely stuck)
      minutes=9999
    elif [[ "$cputime" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
      # HH:MM:SS
      minutes=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
    elif [[ "$cputime" =~ ^([0-9]+):([0-9]+)$ ]]; then
      # MM:SS
      minutes=${BASH_REMATCH[1]}
    fi

    if [[ $minutes -ge 5 ]]; then
      kill "$pid" 2>/dev/null && killed=$((killed + 1))
    fi
  done < <(ps -u "$(id -u)" -o pid=,cputime=,comm= 2>/dev/null | grep 'gst-plugin-scan' || true)

  # If we killed any gst-plugin-scanner, also stop localsearch to prevent respawn
  if [[ $killed -gt 0 ]]; then
    # Stop and mask the localsearch service so it doesn't respawn immediately
    systemctl --user stop localsearch-3.service 2>/dev/null || true
    systemctl --user mask localsearch-3.service 2>/dev/null || true
    echo -e "${GREEN}Killed $killed runaway gst-plugin-scanner process(es), masked localsearch-3${NC}"
  fi
}

# Create a draft PR for the current branch
# Idempotent: skips if a PR already exists
# All push/PR failures warn but do not block (returns 0)
create_draft_pr() {
  require_working_tree

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)

  # Guard: refuse to run on main/master
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo -e "${RED}Error: Cannot create draft PR on $branch${NC}"
    return 1
  fi

  # Check if PR already exists (idempotent)
  local existing_pr
  if ! existing_pr=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>&1); then
    echo -e "${YELLOW}Warning: Could not check for existing PR: $existing_pr${NC}"
    existing_pr=""
  fi

  if [[ -n "$existing_pr" ]]; then
    echo -e "${GREEN}Draft PR #$existing_pr already exists for $branch${NC}"
    return 0
  fi

  # Create empty initial commit
  git commit --allow-empty -m "chore: initialize $branch"

  # Push branch to remote (warn on failure, do not block)
  local push_error
  if ! push_error=$(git push -u origin "$branch" 2>&1); then
    echo -e "${YELLOW}Warning: Push failed. Work is committed locally.${NC}"
    echo "  $push_error"
    return 0
  fi

  # Create draft PR (warn on failure, do not block)
  local pr_body="Draft PR created automatically. Content will be added as work progresses."
  local pr_url
  if ! pr_url=$(gh pr create --draft --title "WIP: $branch" --body "$pr_body" 2>&1); then
    echo -e "${YELLOW}Warning: Draft PR creation failed. Branch is pushed to remote.${NC}"
    echo "  $pr_url"
    return 0
  fi

  echo -e "${GREEN}Draft PR created: $pr_url${NC}"
}

# Sync critical on-disk files from git HEAD in a bare repo.
# Bare repos have no working tree, so on-disk files become stale after merges.
# This extracts the latest versions from git and overwrites the stale copies.
sync_bare_files() {
  if [[ "$IS_BARE" != "true" ]]; then
    echo -e "${YELLOW}Not a bare repo -- sync-bare-files is only needed for bare repo roots${NC}"
    return 0
  fi

  echo -e "${BLUE}Syncing on-disk files from git HEAD...${NC}"

  # Extract all plugin-loadable trees from HEAD in one shot.
  # The old approach used a hardcoded whitelist that missed commands, skills,
  # agents, and docs -- causing stale files after every merge (#1188 regression).
  # git archive | tar -x overwrites in-place and adds new files atomically.
  local trees=(
    "plugins/"
    "CLAUDE.md"
    "AGENTS.md"
    "README.md"
    ".claude-plugin"
    ".claude/settings.json"
  )

  # Build archive args, skipping trees that don't exist in HEAD
  local archive_args=()
  for tree in "${trees[@]}"; do
    if git cat-file -e "HEAD:$tree" 2>/dev/null; then
      archive_args+=("$tree")
    fi
  done

  if [[ ${#archive_args[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No syncable trees found in HEAD${NC}"
    return 0
  fi

  # Extract directly into the bare repo root
  if ! git archive HEAD -- "${archive_args[@]}" | tar -xC "$GIT_ROOT" 2>/dev/null; then
    echo -e "${RED}Error: git archive extraction failed${NC}"
    return 1
  fi

  # Sync hook scripts from .claude/hooks/ and restore execute permissions
  local hook_files
  hook_files=$(git ls-tree --name-only HEAD .claude/hooks/ 2>/dev/null || true)
  if [[ -n "$hook_files" ]]; then
    mkdir -p "$GIT_ROOT/.claude/hooks"
    git archive HEAD -- .claude/hooks/ | tar -xC "$GIT_ROOT" 2>/dev/null || true
    chmod +x "$GIT_ROOT/.claude/hooks/"*.sh 2>/dev/null || true

    # Remove stale hook files that no longer exist in git HEAD
    for on_disk_hook in "$GIT_ROOT/.claude/hooks"/*; do
      [[ -f "$on_disk_hook" ]] || continue
      local hook_name
      hook_name=$(basename "$on_disk_hook")
      if ! git cat-file -e "HEAD:.claude/hooks/$hook_name" 2>/dev/null; then
        rm "$on_disk_hook"
        echo -e "${YELLOW}Removed stale hook: $hook_name${NC}"
      fi
    done
  fi

  # Restore execute permissions on scripts
  find "$GIT_ROOT/plugins/" -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
  chmod +x "$GIT_ROOT/plugins/soleur/hooks/"*.sh 2>/dev/null || true

  echo -e "${GREEN}Synced on-disk files from git HEAD${NC}"
}

# Main command handler
main() {
  local command="${1:-list}"

  case "$command" in
    create)
      create_worktree "${2:-}" "${3:-}"
      ;;
    feature|feat)
      create_for_feature "${2:-}" "${3:-}"
      ;;
    list|ls)
      list_worktrees
      ;;
    switch|go)
      switch_worktree "${2:-}"
      ;;
    copy-env|env)
      copy_env_to_worktree "${2:-}"
      ;;
    cleanup|clean)
      cleanup_worktrees
      ;;
    cleanup-merged)
      cleanup_merged_worktrees
      ;;
    cleanup-tmp)
      cleanup_claude_tmp
      ;;
    cleanup-procs)
      cleanup_runaway_processes
      ;;
    draft-pr)
      create_draft_pr
      ;;
    sync-bare-files|sync-bare|sync)
      sync_bare_files
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

Usage: worktree-manager.sh [--yes] <command> [options]

Global Flags:
  --yes                               Auto-confirm all prompts (for headless/scripted use)

Commands:
  create <branch-name> [from-branch]  Create new worktree (copies .env files automatically)
                                      (from-branch defaults to main)
  feature | feat <name> [from-branch] Create worktree for feature with spec directory
                                      (creates feat-<name> branch + knowledge-base/project/specs/feat-<name>/)
  list | ls                           List all worktrees
  switch | go [name]                  Switch to worktree
  copy-env | env [name]               Copy .env files from main repo to worktree
                                      (if name omitted, uses current worktree)
  cleanup | clean                     Clean up inactive worktrees
  cleanup-merged                      Clean up worktrees for merged branches
                                      (detects [gone] + merged-to-main branches,
                                      deletes stale remote branches, removes
                                      orphan directories, archives specs,
                                      cleans Claude tmp files, kills runaway procs)
  cleanup-tmp                         Remove stale Claude task output files
                                      (reclaims RAM from /tmp/claude-<uid>/)
  cleanup-procs                       Kill runaway processes wasting CPU
                                      (e.g., stuck gst-plugin-scanner)
  draft-pr                            Create empty commit, push, and open draft PR
                                      (idempotent: skips if PR already exists)
  sync-bare | sync-bare-files | sync  Sync stale on-disk files from git HEAD
                                      (bare repos only -- overwrites AGENTS.md,
                                      CLAUDE.md, hooks, settings, plugin manifest,
                                      and this script. Removes stale hooks.)
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

# Parse --yes flag from arguments before dispatching
args=()
for arg in "$@"; do
  if [[ "$arg" == "--yes" ]]; then
    YES_FLAG=true
  else
    args+=("$arg")
  fi
done

# Guard for testability: only run main() when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "${args[@]+"${args[@]}"}"
fi
