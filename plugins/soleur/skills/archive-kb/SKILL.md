---
name: archive-kb
description: "This skill should be used when archiving completed knowledge-base artifacts (brainstorms, plans, specs) to their archive/ subdirectories with timestamp prefixes. It handles git history preservation automatically and avoids command substitution prompts."
---

# Archive Knowledge-Base Artifacts

Archive brainstorms, plans, and spec directories for a completed feature branch.
The script generates timestamps internally and uses `git mv` to preserve history.

## Usage

Run the archive script from the repository root. It derives the feature slug
from the current branch name automatically:

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh

To preview what would be archived without making changes:

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run

To archive a specific slug (override branch detection):

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh my-feature-slug

## What It Archives

The script discovers artifacts matching the feature slug in three locations:

| Directory | Match Pattern | Type |
|-----------|--------------|------|
| `knowledge-base/brainstorms/` | Filename contains slug | File glob |
| `knowledge-base/plans/` | Filename contains slug | File glob |
| `knowledge-base/specs/feat-<slug>/` | Exact directory name | Directory match |

All `archive/` subdirectories are excluded from discovery.

## When to Use

- During the compound skill's archival step (Step E in compound-capture)
- After completing a feature when brainstorm/plan artifacts should be archived
- During the ship workflow to archive feature artifacts before merge

## Notes

- The script calls `git add` before `git mv` to handle untracked files
- A single timestamp is generated per invocation for consistency
- Exit code 0 for success (including "no artifacts found")
- Exit code 1 for errors (not in git repo, invalid arguments)
- Spec directories are moved as a whole via `git mv` on the directory
