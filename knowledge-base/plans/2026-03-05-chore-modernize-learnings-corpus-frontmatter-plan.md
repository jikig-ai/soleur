---
title: "chore: modernize learnings corpus YAML frontmatter"
type: chore
date: 2026-03-05
semver: patch
---

# chore: modernize learnings corpus YAML frontmatter

## Overview

Backfill structured YAML frontmatter on 95 learnings files (85 missing frontmatter entirely + 10 with partial/inconsistent frontmatter) to match the constitution's required schema. This enables future automated analysis (Layer 2 CI sweep) via field-based queries.

## Problem Statement / Motivation

The issue (#424) identified during SpecFlow analysis for #397: approximately 69% of learnings files (95 of 138) lack the structured YAML frontmatter mandated by `constitution.md`:

> Learning files must include YAML frontmatter with `title`, `date`, `category`, and `tags` fields; optional fields include `symptoms`, `module`, and `synced_to`

Current state breakdown:
- **43 files** have YAML frontmatter (31%) -- but with inconsistent field sets (some use `symptom:` singular vs `symptoms:` plural, some use `component:` and `root_cause:` from the CORA schema)
- **85 files** use informal inline bold fields (`**Date:**`, `**Tags:**`) or no metadata at all
- **1 file** (`agent-prompt-sharp-edges-only.md`) lacks a date prefix in its filename

The compound-capture schema (`schema.yaml`) defines CORA-specific enums (Rails models, Turbo, Stimulus, etc.) that do not apply to Soleur's domain (Claude Code plugin, shell scripts, CI/CD, agents). The constitution's simpler required fields are the correct target.

## Proposed Solution

A one-time automated sweep using a bash script that:

1. **Extracts metadata** from each file's inline content (title from `# Heading`, date from filename or `**Date:**` field, tags from `## Tags` section or `**Tags:**` field)
2. **Generates YAML frontmatter** with the four required fields (`title`, `date`, `category`, `tags`)
3. **Adds optional fields** when extractable (`symptoms`, `module`, `synced_to`)
4. **Preserves existing frontmatter** for the 43 files that already have it, only adding missing required fields
5. **Fixes the filename** of `agent-prompt-sharp-edges-only.md` to include a date prefix

### Schema Decision: Constitution over CORA

The compound-capture `schema.yaml` was inherited from a Rails project (CORA) and contains Rails-specific enums (`rails_model`, `hotwire_turbo`, `missing_include`, etc.) that are meaningless for Soleur learnings about shell scripts, CI/CD workflows, and Claude Code agents.

**Target schema** (from constitution.md line 36):

```yaml
# Required
title: string       # Clear descriptive title
date: YYYY-MM-DD    # Date learning was captured
category: string    # Free-text category (e.g., "workflow-patterns", "agent-design", "ci-cd")
tags: [string]      # Searchable keywords, lowercase, hyphen-separated

# Optional
symptoms: [string]  # Observable symptoms
module: string      # Plugin area affected
synced_to: [string] # Definition files this learning was promoted to
```

**Non-goal:** Updating `schema.yaml` itself -- that schema serves CORA-specific projects. The constitution's field list is the authority for Soleur learnings.

### Category Taxonomy

Derive categories from existing usage patterns (43 files with frontmatter) rather than inventing new ones. Current categories observed:

- `workflow-patterns` -- git, PR, merge, ship workflows
- `agent-design` -- agent prompts, descriptions, disambiguation
- `ci-cd` -- GitHub Actions, release workflows
- `shell-scripting` -- bash gotchas, script patterns
- `plugin-architecture` -- skill/command/agent loader behavior
- `security` -- secrets, permissions, audit patterns
- `legal` -- GDPR, CLA, licensing patterns
- `infrastructure` -- MCP servers, external services
- `documentation` -- docs site, brand guide, constitution
- `ui-css` -- frontend, CSS, grid layout

## Technical Considerations

### Migration Script Architecture

A single bash script (`scripts/backfill-frontmatter.sh`) that:

1. Iterates all `knowledge-base/learnings/*.md` files
2. For each file, determines if frontmatter exists (`head -1` check for `---`)
3. **No frontmatter:** Parses inline metadata, generates frontmatter, prepends it
4. **Partial frontmatter:** Reads existing frontmatter, adds missing required fields
5. Uses `git mv` for the filename rename (preserves history)

### Edge Cases

- **Files with `**Date:**` inline format** -- extract date, remove redundant inline field
- **Files with `## Tags` section at bottom** -- extract tags, optionally remove section
- **Files with `**Tags:**` inline format** -- extract tags, remove redundant inline field
- **Files with no date anywhere** -- derive from filename prefix (`YYYY-MM-DD-slug.md`)
- **File without date prefix** (`agent-prompt-sharp-edges-only.md`) -- inspect git log for creation date, rename with `git mv`
- **Existing frontmatter with `symptom:` (singular)** -- normalize to `symptoms:` (plural, array)
- **Existing frontmatter with CORA-specific fields** (`problem_type`, `component`, `root_cause`, `resolution_type`, `severity`) -- preserve as-is (no data loss), these are informational extras

### Performance

138 files is trivially small. The script runs in under 5 seconds.

### Risk: Content Corruption

The script must never modify file content below the frontmatter block. Strategy:
- Read full file into variable
- Generate frontmatter string
- Write: frontmatter + original content (minus any extracted inline metadata)
- Verify line count delta matches expected frontmatter addition

## Acceptance Criteria

- [ ] All 138 learnings files have valid YAML frontmatter with `title`, `date`, `category`, `tags`
- [ ] `agent-prompt-sharp-edges-only.md` renamed with date prefix
- [ ] Existing frontmatter preserved (no field removal, no data loss)
- [ ] `symptom:` singular normalized to `symptoms:` array where present
- [ ] Category values are consistent (same category for similar topics)
- [ ] No content below frontmatter is modified
- [ ] `bun test` passes (if any test references learnings files)
- [ ] Markdownlint passes on all modified files

## Test Scenarios

- Given a file with no frontmatter and inline `**Date:** 2026-02-06` / `**Tags:** workflow, architecture`, when the script runs, then YAML frontmatter is prepended with correct `date`, `tags`, and the inline metadata lines are removed
- Given a file with existing complete frontmatter, when the script runs, then the file is unchanged
- Given a file with partial frontmatter (missing `category`), when the script runs, then `category` is added based on content analysis
- Given `agent-prompt-sharp-edges-only.md`, when the script runs, then it is renamed to `YYYY-MM-DD-agent-prompt-sharp-edges-only.md` with correct date from git history
- Given a file with `symptom: "single string"`, when the script runs, then it becomes `symptoms: ["single string"]`
- Given a file with CORA-specific fields (`problem_type`, `component`), when the script runs, then those fields are preserved alongside the new required fields

## Success Metrics

- 100% of learnings files pass YAML frontmatter validation (4 required fields present)
- Zero content corruption (diff shows only frontmatter additions/modifications, no body changes)
- Categories converge to 10-15 distinct values (not 80+ unique categories)

## Dependencies & Risks

- **No blockers** -- this task is independent (#424 states "Depends on: nothing")
- **Risk: Incorrect category assignment** -- Mitigated by manual review of the category mapping before committing
- **Risk: Duplicate content** -- If inline `**Date:**` is kept alongside frontmatter `date:`, information is redundant. Plan: remove inline metadata that duplicates frontmatter fields.

## Non-Goals

- Updating `schema.yaml` to match Soleur's domain (separate issue if needed)
- Adding `problem_type`, `component`, `root_cause`, `resolution_type`, or `severity` to files that don't have them -- these CORA-specific fields are optional
- Building a CI validation step (that's the "Layer 2 CI sweep" mentioned in #424, tracked separately)
- Reorganizing learnings into subdirectories by category

## References & Research

### Internal References

- Constitution field requirements: `knowledge-base/overview/constitution.md:36`
- Compound-capture schema: `plugins/soleur/skills/compound-capture/schema.yaml`
- Resolution template: `plugins/soleur/skills/compound-capture/assets/resolution-template.md`
- Issue: #424

### Files Affected

- 85 files in `knowledge-base/learnings/` -- new frontmatter added
- ~10 files in `knowledge-base/learnings/` -- existing frontmatter augmented
- 1 file renamed: `agent-prompt-sharp-edges-only.md`

## MVP

### `scripts/backfill-frontmatter.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
LEARNINGS_DIR="knowledge-base/learnings"
REQUIRED_FIELDS=("title" "date" "category" "tags")

# --- Main Loop ---
for file in "$LEARNINGS_DIR"/*.md; do
  filename=$(basename "$file")

  # Extract date from filename prefix
  date_from_filename=$(echo "$filename" | grep -oP '^\d{4}-\d{2}-\d{2}' || echo "")

  # Check if frontmatter exists
  if head -1 "$file" | grep -q '^---'; then
    # Augment existing frontmatter with missing required fields
    augment_frontmatter "$file" "$date_from_filename"
  else
    # Generate and prepend new frontmatter
    generate_frontmatter "$file" "$date_from_filename"
  fi
done
```

### Category Inference Logic

```bash
# Infer category from filename slug and content keywords
infer_category() {
  local file="$1"
  local slug="$2"

  # Pattern matching on filename slug
  case "$slug" in
    *worktree*|*merge*|*ship*|*pr-*|*commit*|*branch*)   echo "workflow-patterns" ;;
    *agent*|*prompt*|*disambiguation*)                     echo "agent-design" ;;
    *github-actions*|*ci-*|*release*|*workflow-security*)  echo "ci-cd" ;;
    *shell*|*bash*|*grep*|*sed*|*jq*|*pipefail*)          echo "shell-scripting" ;;
    *plugin*|*skill*|*command*|*loader*)                   echo "plugin-architecture" ;;
    *security*|*secret*|*api-key*|*audit*)                 echo "security" ;;
    *legal*|*gdpr*|*cla*|*license*|*privacy*)              echo "legal" ;;
    *mcp*|*pencil*|*terraform*|*discord*|*telegram*)       echo "infrastructure" ;;
    *docs*|*brand*|*constitution*|*css*|*landing*)          echo "documentation" ;;
    *marketing*|*seo*|*aeo*|*strategy*)                    echo "marketing" ;;
    *)                                                      echo "engineering" ;;
  esac
}
```
