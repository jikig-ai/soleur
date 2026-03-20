---
title: "feat: Add dedicated archival skill for knowledge-base artifacts"
type: feat
date: 2026-02-24
version_bump: MINOR
---

# feat: Add Dedicated Archival Skill for Knowledge-Base Artifacts

## Enhancement Summary

**Deepened on:** 2026-02-24
**Sections enhanced:** 6 (Technical Approach, Slug Derivation, Consumer Updates, Test Scenarios, Risks, Edge Cases)
**Research sources:** 5 institutional learnings, codebase analysis of worktree-manager.sh and 4 consumer skills

### Key Improvements

1. Detailed slug derivation logic with all 4 prefix variants and `tr '/' '-'` normalization, informed by the archiving-slug-extraction learning that prevented 92 silent failures
2. Concrete script pseudocode with exact function signatures, error handling, and edge case coverage
3. Consumer update strategy refined: compound-capture Step E needs the most careful replacement; brainstorm/plan need only their "Managing" footer sections updated
4. Added spec directory handling for `feat-<slug>` naming (not just file globs)

### New Considerations Discovered

- The `!` code fence permission flow in skills fails silently -- the SKILL.md must NOT use `!` fences for the script invocation; use plain `bash` code blocks or prose instructions instead
- Spec directories use a `feat-<slug>` naming convention (not just slug glob), requiring exact-match directory detection alongside glob-based file discovery
- The compound learnings archival path (`knowledge-base/learnings/archive/`) takes an explicit file path (not slug), so extending the script to handle it would require a different interface (a `--file` flag for single-file archival)

## Overview

Create an `archive-kb` skill with a bash script that moves knowledge-base artifacts (brainstorms, plans, specs) to their `archive/` subdirectories with timestamp prefixes. The script encapsulates `date`, `git add`, and `git mv` into a single deterministic command, eliminating `$()` command substitution from all SKILL.md files that reference archival.

## Problem Statement

The current archival approach in compound-capture, compound, brainstorm, plan, and ship skills instructs Claude to generate a timestamp and then use it in `git mv` commands. This creates two problems:

1. **Command substitution safety prompt**: Using `$(date +%Y%m%d-%H%M%S)` in Bash triggers Claude Code's "Command contains $() command substitution" permission dialog, blocking automated workflows like one-shot and ship pipelines.
2. **Fragile duplication**: Six different skills contain near-identical archival instructions with angle-bracket placeholders (`<timestamp>`, `<slug>`). Each independently implements the "generate timestamp, then use it" two-step pattern. When archival logic changes (e.g., adding `git add` before `git mv` for untracked files -- see CHANGELOG v2.20.0), all six must be updated.

The worktree-manager.sh script already solves this for spec directories during `cleanup-merged`, but its `archive_kb_files()` function uses `mv` (not `git mv`) because it runs outside the git working tree context.

### Research Insights: Command Substitution History

This problem has recurred 4 times across the project (learning: `command-substitution-in-plugin-markdown`):
- v2.23.15: one-shot command
- v2.23.18: 4 commands, 9 skills, AGENTS.md
- v2.26.1: merge-pr skill, community-manager agent, 2 reference files
- v3.0.6: help command

Each fix caught known files but missed others because the search scope was too narrow. The script approach eliminates the problem at its root -- `$()` moves inside the script, out of the markdown entirely.

## Proposed Solution

Create an `archive-kb` skill containing:

1. **`scripts/archive-kb.sh`** -- A bash script that:
   - Accepts a feature slug (or derives it from the current branch name)
   - Discovers artifacts matching the slug in `knowledge-base/{brainstorms,plans}/` and `knowledge-base/specs/feat-<slug>/`
   - Excludes `archive/` paths
   - Generates a `YYYYMMDD-HHMMSS` timestamp internally (no `$()` exposed to Claude)
   - Runs `git add` + `git mv` for each artifact to its `archive/` subdirectory with the timestamp prefix
   - Outputs a structured report of what was moved
   - Supports `--dry-run` for preview without action
   - Supports `--list` to only discover and list artifacts (no archival)

2. **`SKILL.md`** -- Minimal skill instructions that tell Claude when and how to invoke the script. No archival logic in the markdown itself.

3. **Updates to consumer skills** -- Replace inline archival instructions in compound-capture, compound, brainstorm, and plan with a reference to the archive-kb script.

## Technical Approach

### Script Design: `scripts/archive-kb.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: archive-kb.sh [--dry-run] [--list] [slug]
# If slug is omitted, derives from current git branch.
# Discovers and archives knowledge-base artifacts matching the slug.
```

### Slug Derivation (Critical -- Learning Applied)

The slug extraction logic must handle all 4 branch prefix variants. From learning `archiving-slug-extraction-must-match-branch-conventions`: a single-prefix extraction (`${branch#feat-}`) caused 92 artifacts to silently fail archival.

**Algorithm:**

1. Get current branch: `git rev-parse --abbrev-ref HEAD`
2. Normalize slashes to hyphens: `tr '/' '-'` (after this, `feat/foo` becomes `feat-foo`)
3. Strip prefixes in sequence:
   - `feat-` (catches both `feat/` after normalization and literal `feat-`)
   - `fix-` (catches both `fix/` after normalization and literal `fix-`)
   - `feature-` (catches `feature/` after normalization)

**Why sequential stripping is safe after `tr`:** From the learning's second insight -- `tr '/' '-'` collapses all slash-based prefixes into hyphen-based ones. After `tr`, there are only 3 distinct prefixes to strip: `feat-`, `fix-`, and `feature-`. The `${var#prefix}` parameter expansion only strips the first match, so the order is safe.

```text
# Pseudocode for slug derivation:
branch = git rev-parse --abbrev-ref HEAD
safe = echo branch | tr '/' '-'
slug = safe
slug = strip prefix "feat-" from slug
slug = strip prefix "fix-" from slug
slug = strip prefix "feature-" from slug

# If explicit slug argument provided, use that instead
```

### Discovery Logic

Three independent discovery paths, all excluding `archive/` subdirectories:

| Directory | Pattern | Match Type |
|-----------|---------|------------|
| `knowledge-base/brainstorms/` | `*<slug>*` glob | Filename contains slug |
| `knowledge-base/plans/` | `*<slug>*` glob | Filename contains slug |
| `knowledge-base/specs/` | `feat-<slug>` exact dir | Directory name matches exactly |

**Implementation detail:** Use bash glob expansion with a loop, filtering out `*/archive/*` paths. For specs, use `test -d` on the exact path rather than glob matching.

```text
# Pseudocode for discovery:
artifacts = []

for f in knowledge-base/brainstorms/*SLUG*; do
  if f is a file AND f does not contain /archive/; then
    append f to artifacts
  end
done

for f in knowledge-base/plans/*SLUG*; do
  if f is a file AND f does not contain /archive/; then
    append f to artifacts
  end
done

if knowledge-base/specs/feat-SLUG is a directory; then
  append knowledge-base/specs/feat-SLUG to artifacts
end
```

### Archival Execution

For each discovered artifact:

```text
# Generate timestamp ONCE for the entire invocation
timestamp = date +%Y%m%d-%H%M%S

for each artifact:
  dir = parent directory of artifact (brainstorms, plans, or specs)
  mkdir -p dir/archive
  git add artifact          # no-op if already tracked (learning: git-add-before-git-mv)
  basename = filename or dirname of artifact
  git mv artifact dir/archive/TIMESTAMP-basename
  print "Archived: dir/archive/TIMESTAMP-basename"
done
```

**Edge case -- spec directories:** `git mv` works on directories, moving the entire directory tree. `git add` on a directory stages all untracked files within it. Both operations are safe for the `knowledge-base/specs/feat-<slug>/` directory case.

### Output Format

Structured output suitable for inclusion in compound's consolidation report:

```text
# On success with artifacts:
Archived 3 artifact(s) for slug "archive-skill":
  knowledge-base/brainstorms/archive/20260224-143000-archive-skill-brainstorm.md
  knowledge-base/plans/archive/20260224-143000-feat-archive-skill-plan.md
  knowledge-base/specs/archive/20260224-143000-feat-archive-skill/

# On success with no artifacts:
No artifacts found for slug "archive-skill"

# On --dry-run:
Dry run -- would archive 3 artifact(s) for slug "archive-skill":
  knowledge-base/brainstorms/archive-skill-brainstorm.md -> archive/20260224-143000-archive-skill-brainstorm.md
  knowledge-base/plans/feat-archive-skill-plan.md -> archive/20260224-143000-feat-archive-skill-plan.md
  knowledge-base/specs/feat-archive-skill/ -> archive/20260224-143000-feat-archive-skill/

# On --list:
Found 3 artifact(s) for slug "archive-skill":
  knowledge-base/brainstorms/archive-skill-brainstorm.md
  knowledge-base/plans/feat-archive-skill-plan.md
  knowledge-base/specs/feat-archive-skill/
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (including "no artifacts found" -- not an error) |
| 1 | Error (git command failed, invalid arguments) |

### Modes

| Flag | Behavior |
|------|----------|
| (none) | Discover + archive |
| `--dry-run` | Discover + print what would be archived, no `git mv` |
| `--list` | Discover only, print matching artifacts |

### SKILL.md Design

Minimal routing skill. Critical: do NOT use `!` code fences (learning: `skill-code-fence-permission-flow` -- `!` fences fail silently on permission denial). Use plain prose instructions that Claude executes via the Bash tool.

```markdown
---
name: archive-kb
description: This skill should be used when archiving completed knowledge-base
  artifacts (brainstorms, plans, specs) to their archive/ subdirectories with
  timestamp prefixes. It handles git history preservation automatically and
  avoids command substitution prompts.
---

# archive-kb Skill

**Purpose:** Archive knowledge-base artifacts (brainstorms, plans, specs) for
a completed feature, preserving git history with timestamped filenames.

## Usage

Run the archive script from the repository root. It derives the feature slug
from the current branch name:

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh

To preview what would be archived without making changes:

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run

To list matching artifacts without archiving:

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --list

To archive a specific slug (override branch detection):

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh <slug>
```

No `$()` or shell variable expansion anywhere in the SKILL.md.

### Consumer Skill Updates

Replace archival instructions in these files:

| File | Section to Update | Current Size | New Size |
|------|-------------------|-------------|----------|
| `skills/compound-capture/SKILL.md` | Step E: Archival (lines 413-470) | ~57 lines | ~10 lines |
| `skills/compound/SKILL.md` | Managing Learnings: Archive section (line 181) | ~3 lines | ~3 lines (reworded) |
| `skills/brainstorm/SKILL.md` | Managing Brainstorm Documents: Archive section (line 279-280) | ~3 lines | ~3 lines (reworded) |
| `skills/plan/SKILL.md` | Managing Plan Documents: Archive section (line 392) | ~3 lines | ~3 lines (reworded) |
| `skills/ship/SKILL.md` | Phase 2 (delegates to compound) | No change | No change |

**Compound-capture Step E** is the primary consumer -- it has the most archival logic (30+ lines of mkdir, git add, git mv instructions). The replacement:

```markdown
### Auto-Consolidation Step E: Archival

Archive ALL discovered artifacts regardless of how many proposals were accepted or skipped.

Run the archival script from the repository root:

    bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh

The script discovers artifacts matching the current branch's feature slug, creates archive directories, and moves each artifact with a timestamped prefix using `git mv`.
```

**Brainstorm, plan, and compound** have shorter archival sections (1-3 lines each) that reference `git mv` inline. These change from:

```text
Move completed or superseded brainstorms to `knowledge-base/brainstorms/archive/`:
`mkdir -p knowledge-base/brainstorms/archive && git add ... && git mv ...`
```

To:

```text
Archive completed brainstorms by running:
`bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`
This moves matching artifacts to `knowledge-base/brainstorms/archive/` with timestamp prefixes.
```

**Note on compound learnings archival**: The `compound/SKILL.md` has a separate learnings archival path (`knowledge-base/learnings/archive/`) that handles individual learning files by explicit path (not slug). This is a different operation and should remain inline for now. The archive-kb script could be extended with a `--file <path>` flag for single-file archival in a follow-up.

## Non-Goals

- **Archiving learnings**: Individual learning archival in compound is a different workflow (explicit file path, not slug-based). Out of scope.
- **Unarchiving/restoring**: No `--restore` flag. If needed, `git revert` or manual `git mv` suffices.
- **CI integration**: The script runs locally during compound/ship flows. No GitHub Actions integration.
- **Removing worktree-manager's `archive_kb_files()`**: That function uses `mv` (not `git mv`) for a different context (post-merge cleanup outside the git working tree). It stays.
- **`!` code fence execution**: The SKILL.md uses plain prose instructions, not `!` fences, to avoid the silent permission failure documented in the `skill-code-fence-permission-flow` learning.

## Acceptance Criteria

- [x] `scripts/archive-kb.sh` exists at `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` and is executable (`chmod +x`)
- [x] Script discovers artifacts matching a slug in brainstorms/, plans/, and specs/
- [x] Script excludes `archive/` paths from discovery
- [x] Script generates timestamp internally (no `$()` in SKILL.md or caller instructions)
- [x] Script uses `git add` before `git mv` for each artifact (handles untracked files)
- [x] Script supports `--dry-run` and `--list` flags
- [x] Script derives slug from current branch when no argument provided, handling all 4 prefix variants (`feat/`, `feat-`, `fix/`, `fix-`)
- [x] Script handles spec directories (not just files) via `git mv` on directories
- [x] SKILL.md has proper frontmatter (`name`, `description` in third person)
- [x] SKILL.md uses NO `$()`, `${VAR}`, `$VAR`, or `!` code fences
- [x] compound-capture SKILL.md Step E updated to invoke the script
- [x] compound SKILL.md archival section updated
- [x] brainstorm SKILL.md archival section updated
- [x] plan SKILL.md archival section updated
- [x] No `$()` appears in any updated SKILL.md archival instructions
- [x] `bun test` passes (no regressions)
- [x] Skill registered in `docs/_data/skills.js` SKILL_CATEGORIES

## Test Scenarios

### Core Functionality

- Given a feature branch `feat/archive-skill` with a matching brainstorm file, when `archive-kb.sh` runs, then the brainstorm is moved to `knowledge-base/brainstorms/archive/YYYYMMDD-HHMMSS-<original-name>.md` and git tracks the move
- Given a feature branch `feat/archive-skill` with a matching spec directory `knowledge-base/specs/feat-archive-skill/`, when `archive-kb.sh` runs, then the entire directory is moved to `knowledge-base/specs/archive/YYYYMMDD-HHMMSS-feat-archive-skill/`
- Given artifacts in both brainstorms/ and specs/, when the script runs, then both are archived in a single invocation with the same timestamp

### Slug Derivation

- Given branch name `feat/my-feature`, when slug is derived, then the result is `my-feature` (slash normalized to hyphen, then `feat-` stripped)
- Given branch name `feat-my-feature`, when slug is derived, then the result is `my-feature`
- Given branch name `fix/bug-123`, when slug is derived, then the result is `bug-123`
- Given branch name `fix-bug-123`, when slug is derived, then the result is `bug-123`
- Given an explicit slug argument `my-slug`, when the branch name is `feat/different`, then the script uses `my-slug`

### Modes

- Given `--dry-run` flag, when artifacts exist, then the script prints what would be archived but does not execute `git mv`
- Given `--list` flag, when artifacts exist, then the script prints discovered paths without archiving
- Given no matching artifacts for the current slug, when `archive-kb.sh` runs, then it exits 0 with a "no artifacts found" message

### Edge Cases

- Given an untracked brainstorm file (created this session, never committed), when `archive-kb.sh` runs, then `git add` is called before `git mv` (preventing "not under version control" error)
- Given an empty `knowledge-base/brainstorms/` directory, when the script runs, then it skips brainstorms silently (no error from empty glob)
- Given the `knowledge-base/` directory does not exist, when the script runs, then it exits 0 with a "no knowledge-base directory found" message
- Given the user is not in a git repository, when the script runs, then it exits 1 with a clear error message

## Dependencies & Risks

- **Low risk**: This is a new skill with a script. No existing behavior changes until consumer skills are updated.
- **Consumer updates are the riskiest part**: Editing 4 SKILL.md files to replace inline instructions. Each must be verified to not break the surrounding workflow context. Mitigation: read each full SKILL.md before editing, verify the surrounding text makes sense after the replacement.
- **Glob expansion with no matches**: In bash with `set -u` (nounset), globs that match nothing can cause unbound variable errors. Mitigation: use `shopt -s nullglob` inside the discovery function or check glob results with a conditional.
- **Constitution rule compliance**:
  - "Operations that modify the knowledge-base or move files must use `git mv`" -- the script complies.
  - "Shell scripts must use `#!/usr/bin/env bash` shebang and declare `set -euo pipefail`" -- the script complies.
  - "Never use shell variable expansion in bash code blocks within skill .md files" -- the SKILL.md contains no variable expansion.
  - "Shell scripts use snake_case for function names and local variables, SCREAMING_SNAKE_CASE for global constants" -- the script will follow this.
  - "Shell functions must declare all variables with `local`; error messages go to stderr" -- the script will follow this.
  - "Shell scripts use `[[ ]]` double-bracket tests and validate required arguments early" -- the script will follow this.

### Research Insight: nullglob Pitfall

When `set -euo pipefail` is active and a glob like `knowledge-base/brainstorms/*slug*` matches nothing, bash will pass the literal glob string to the loop. The script must handle this by either:
1. Enabling `shopt -s nullglob` before the glob and `shopt -u nullglob` after, or
2. Checking `[[ -e "$f" ]]` inside the loop to skip non-existent paths

Option 1 (`nullglob`) is cleaner. The scope should be limited to avoid surprising behavior in other parts of the script.

## Rollback Plan

If the script has issues after merge:
1. Revert the consumer SKILL.md changes (restoring inline instructions)
2. Delete the `skills/archive-kb/` directory
3. The old inline pattern still works (just triggers safety prompts)

Single `git revert` on the merge commit restores everything.

## References

### Codebase

- Ship skill's "No command substitution" pattern: `plugins/soleur/skills/ship/SKILL.md:10`
- Compound-capture archival Step E: `plugins/soleur/skills/compound-capture/SKILL.md:413-448`
- Worktree-manager's `archive_kb_files()`: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:340-357`
- CHANGELOG entry about `git add` before `git mv`: `plugins/soleur/CHANGELOG.md:45`
- Constitution "No command substitution" rule: `knowledge-base/overview/constitution.md:31`

### Institutional Learnings Applied

- `2026-02-22-command-substitution-in-plugin-markdown.md` -- Root cause analysis of recurring `$()` permission prompts; informed the "move to script" approach
- `2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md` -- All 4 prefix variants must be handled; single-prefix extraction caused 92 silent failures
- `2026-02-22-shell-expansion-codebase-wide-fix.md` -- Replacement strategies for `$()` in plugin markdown; informed SKILL.md design
- `2026-02-24-git-add-before-git-mv-for-untracked-files.md` -- `git add` must precede `git mv` to handle untracked files
- `2026-02-22-skill-code-fence-permission-flow.md` -- `!` code fences fail silently on permission denial; informed SKILL.md to use plain instructions
- `2026-02-22-cleanup-merged-path-mismatch.md` -- Never construct filesystem paths from git ref names; informed the `tr '/' '-'` normalization approach
