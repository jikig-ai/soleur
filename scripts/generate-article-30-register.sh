#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (bare-repo-safe)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../plugins/soleur/scripts/resolve-git-root.sh"

if [[ "$IS_BARE" == "true" ]]; then
  echo "Error: Cannot generate Article 30 register from bare repo root." >&2
  echo "Run from a worktree: cd .worktrees/<name> && bash ../../scripts/generate-article-30-register.sh" >&2
  exit 1
fi

# Navigate to repo root so the script works from any directory
cd "$GIT_ROOT"

TEMPLATE="knowledge-base/project/specs/archive/20260221-044654-feat-cnil-article-30/article-30-register-template.md"
OUTPUT="article-30-register.md"
TODAY=$(date +%Y-%m-%d)

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Error: Template not found at $TEMPLATE" >&2
  echo "Are you running this from the soleur repository?" >&2
  exit 1
fi

sed "s/\[DATE\]/$TODAY/g" "$TEMPLATE" > "$OUTPUT"

echo ""
echo "Article 30 register generated: $(pwd)/$OUTPUT"
echo ""
echo "IMPORTANT: This file is gitignored and must NOT be committed."
echo "Store it in one of these private locations:"
echo "  - Private Notion page"
echo "  - Password-protected cloud folder (Google Drive, Dropbox)"
echo "  - Private GitHub repository"
echo "  - Internal document management system"
echo ""
echo "The register must be producible on CNIL request during an inspection."
