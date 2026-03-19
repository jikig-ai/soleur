---
title: Create Article 30 Processing Register from Template
type: feat
date: 2026-02-21
issue: "#202"
version-bump: PATCH
deepened: 2026-02-21
---

# Create Article 30 Processing Register from Template

## Overview

Create a shell script that generates the GDPR Article 30 processing register from the existing template, filling in dates automatically. Add `.gitignore` protection to prevent accidental commits. The generated register is a private document -- the script and safeguards live in the repo, but the output does not.

## Problem Statement

Per the GDPR Article 30 compliance audit (#187, resolved in #200), Jikigai must maintain an internal record of processing activities. The template exists at `knowledge-base/specs/archive/20260221-044654-feat-cnil-article-30/article-30-register-template.md` but no tooling exists to:

1. Generate the register with actual dates filled in
2. Prevent accidental commits of the private register
3. Guide personnel on private storage requirements

## Proposed Solution

Minimal approach -- three changes:

1. **Shell script** (`scripts/generate-article-30-register.sh`) that copies the template, fills `[DATE]` placeholders with today's date, and writes to a gitignored output path
2. **`.gitignore` entry** for the output file pattern (`article-30-register*.md` and `knowledge-base/private/`)
3. **Instructions in script header** for private storage (no separate docs file needed)

## Non-Goals

- Encrypted storage or vault integration -- overkill for a single markdown document
- A new skill or agent -- this is a one-time generation, a shell script suffices
- Automated private repo creation -- user decides where to store it
- Modifying existing legal documents -- PR #200 already added Article 30 references

## Acceptance Criteria

- [x] Script generates register from template with current date filled in
- [x] Output file is gitignored (cannot be accidentally committed)
- [x] Script prints clear instructions for private storage after generation
- [x] Running script twice overwrites cleanly (idempotent)

## Test Scenarios

- Given the template exists, when running the script, then a register file is created with today's date replacing all `[DATE]` placeholders
- Given the register was already generated, when running the script again, then it overwrites without error
- Given a user runs `git add -A`, when the register exists locally, then `git status` does NOT show the register file (gitignore works)
- Given the script is run, when it completes, then it prints private storage instructions to stdout

## MVP

### scripts/generate-article-30-register.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Navigate to repo root so the script works from any directory
cd "$(git rev-parse --show-toplevel)"

TEMPLATE="knowledge-base/specs/archive/20260221-044654-feat-cnil-article-30/article-30-register-template.md"
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
```

### Research Insights

- Script uses `cd "$(git rev-parse --show-toplevel)"` to work from any directory (worktrees, subdirectories)
- Uses `echo` instead of heredoc for the output message so the output path can include `$(pwd)` for clarity
- The `.gitignore` pattern is scoped to the repo root only since gitignore patterns without `/` match anywhere -- but `article-30-register*.md` is specific enough to avoid false positives

### .gitignore addition

```gitignore
# Article 30 register (private -- do not commit)
article-30-register*.md
knowledge-base/private/
```

## References

- Template: `knowledge-base/specs/archive/20260221-044654-feat-cnil-article-30/article-30-register-template.md`
- Compliance audit: #187
- Compliance fixes: #200
- Learning: `knowledge-base/learnings/2026-02-21-gdpr-article-30-compliance-audit-pattern.md`
