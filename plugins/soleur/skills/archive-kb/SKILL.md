---
name: archive-kb
description: "This skill should be used when archiving completed knowledge-base artifacts (brainstorms, plans, specs) to their archive/ subdirectories with timestamp prefixes and git history preservation."
---

# Archive Knowledge-Base Artifacts

Archive brainstorms, plans, and spec directories for a completed feature branch.
The script generates timestamps internally and uses `git mv` to preserve history.

> **Superseded in part (ADR-173, #7399).** Archival's only real benefit was removing
> rows from `knowledge-base/INDEX.md`, and that is now done at index-generation time:
> inside a spec directory only `spec.md` and `tasks.md` are indexed. Do **not** build a
> gate that forces archival before merge — a spec directory is live working state until
> `ship` Phase 6 reads `decision-challenges.md` from it (ADR-084 §5), and one such gate
> has already been built and reverted for that reason.
>
> This script is unchanged and still works for brainstorms. Retiring its spec/plan
> discovery paths is tracked by **#7400**; until then it is neither enforced nor removed.
> Known discovery gaps: `derive_slug()` strips a `fix-` prefix and then probes
> `specs/feat-${slug}`, so `fix-*` spec dirs are unreachable; plans are matched by a
> `*<slug>*` glob, so a topic-named plan is missed and the run still reports success.

## Usage

Run the archive script from the repository root. It derives the feature slug
from the current branch name automatically:

    bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/archive-kb/scripts/archive-kb.sh

To preview what would be archived without making changes:

    bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/archive-kb/scripts/archive-kb.sh --dry-run

To archive a specific slug (override branch detection):

    bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/archive-kb/scripts/archive-kb.sh my-feature-slug

## What It Archives

The script discovers artifacts matching the feature slug:

| Directory | Match Pattern | Type |
|-----------|--------------|------|
| `knowledge-base/project/brainstorms/` | Filename contains slug | File glob |
| `knowledge-base/project/plans/` | Filename contains slug | File glob |
| `knowledge-base/project/specs/feat-<slug>/` | Exact directory name | Directory match |

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
