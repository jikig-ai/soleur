---
title: "chore: modernize learnings corpus YAML frontmatter"
type: chore
date: 2026-03-05
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 6 (Technical Considerations, Edge Cases, MVP, Category Taxonomy, Test Scenarios, Dependencies & Risks)
**Research sources:** 5 institutional learnings, code-simplicity review, data-migration review, silent-failure analysis

### Key Improvements

1. Added bash pitfall guards from institutional learnings (grep exit codes under pipefail, git add before git mv, sed silent failure verification)
2. Identified category inference ambiguity where overlapping slug patterns produce first-match bias -- added priority ordering and conflict resolution
3. Specified `yq` as the tool for augmenting existing YAML frontmatter (avoids sed-based YAML manipulation which is brittle)
4. Added idempotency requirement -- script must be safe to run multiple times
5. Added post-run verification script pattern from sed-insertion-fails-silently learning

### Relevant Institutional Learnings Applied

- `2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md` -- batch operations must verify changes landed
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- grep returns exit 1 on no match (breaks pipefail), bare positional args break nounset
- `2026-02-24-git-add-before-git-mv-for-untracked-files.md` -- always `git add` before `git mv` for files created in current session
- `2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md` -- slug/prefix stripping must handle all variants
- `2026-02-22-shell-expansion-codebase-wide-fix.md` -- script is a real `.sh` file so shell expansion is fine (unlike `.md` instruction files)

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
- `marketing` -- SEO, AEO, brand strategy
- `engineering` -- catch-all for learnings that don't fit other categories

#### Research Insight: Category Ambiguity Resolution

The `case` statement in `infer_category` uses first-match semantics, which creates ambiguity for files matching multiple patterns. Examples:

| Filename slug | Matches | Correct category |
|---|---|---|
| `github-actions-workflow-security-patterns` | `ci-cd` (github-actions) AND `security` (security) | `ci-cd` (primary concern is CI) |
| `docs-site-css-variable-inconsistency` | `documentation` (docs, css) AND `ui-css` (css) | `ui-css` (CSS is the problem) |
| `plugin-command-double-namespace` | `plugin-architecture` (plugin, command) | `plugin-architecture` (correct) |
| `marketing-audit-brand-violation-cascade` | `marketing` (marketing) AND `security` (audit) | `marketing` (brand audit, not security) |

**Resolution strategy:** Order `case` patterns from most specific to most general. Place compound patterns (e.g., `*github-actions*`) before simple ones (e.g., `*security*`). For the ~10 genuinely ambiguous files, prefer the category that describes the root cause over the category that describes the symptom domain.

**Validation:** After running the script, output a category distribution table and manually review any category with fewer than 3 files (likely misclassified) or more than 25 files (likely too broad).

## Technical Considerations

### Migration Script Architecture

A single bash script (`scripts/backfill-frontmatter.sh`) that:

1. Iterates all `knowledge-base/learnings/*.md` files
2. For each file, determines if frontmatter exists (`head -1` check for `---`)
3. **No frontmatter:** Parses inline metadata, generates frontmatter, prepends it
4. **Partial frontmatter:** Reads existing frontmatter, adds missing required fields
5. Uses `git mv` for the filename rename (preserves history)

#### Research Insights: Bash Pitfall Guards

**From `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`:**

The script uses `set -euo pipefail`. Three vectors require guards:

1. **`grep` returns exit 1 on no match** -- every `grep` in a pipeline must append `|| true` or use `grep ... || echo ""` to prevent pipefail from aborting the script when a pattern is absent. This is critical for the inline metadata extraction (`grep -oP '^\*\*Date:\*\*'`) which will return exit 1 on files without inline dates.

2. **Bare positional args under nounset** -- function parameters that might be empty must use `${var:-}` default syntax. The `augment_frontmatter` function receives `$date_from_filename` which is empty for `agent-prompt-sharp-edges-only.md`.

3. **`head -1 | grep -q` pipeline** -- if `head` succeeds but `grep` finds no match, pipefail propagates grep's exit 1. Wrap in `if head -1 "$file" | grep -q '^---'; then` (which is already correct because `if` suppresses exit code propagation).

**From `2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md`:**

After the batch operation completes, run a verification pass that confirms every file has frontmatter:

```bash
# Post-run verification (must return 0 files)
failed=$(grep -rL '^---' knowledge-base/learnings/*.md | wc -l)
if [[ "$failed" -gt 0 ]]; then
  echo "ERROR: $failed files still lack frontmatter" >&2
  grep -rL '^---' knowledge-base/learnings/*.md >&2
  exit 1
fi
```

**Idempotency requirement:** Running the script twice must produce identical output. The script must detect existing frontmatter and skip files that already have all required fields. This is especially important because the script might be interrupted mid-run and restarted.

### Tool Choice: `yq` for YAML Manipulation

For augmenting existing frontmatter (the 43 files that already have partial YAML), use `yq` (Go version) rather than sed/awk. YAML has multiline values, quoted strings, and array syntax that sed cannot reliably parse.

```bash
# Check if yq is available, fall back to manual insertion if not
if command -v yq &>/dev/null; then
  # Use yq to add missing fields
  yq -i '.category = "workflow-patterns"' "$file"
else
  # Fall back to awk-based insertion before closing ---
  # Only for simple scalar fields, not arrays
fi
```

**Fallback consideration:** If `yq` is not installed, the script can use a simpler approach: read frontmatter as text, check for field presence with `grep`, and insert missing fields before the closing `---` delimiter. This is safe for simple scalar fields and avoids a hard dependency.

### Edge Cases

- **Files with `**Date:**` inline format** -- extract date, remove redundant inline field
- **Files with `## Tags` section at bottom** -- extract tags, optionally remove section
- **Files with `**Tags:**` inline format** -- extract tags, remove redundant inline field
- **Files with no date anywhere** -- derive from filename prefix (`YYYY-MM-DD-slug.md`)
- **File without date prefix** (`agent-prompt-sharp-edges-only.md`) -- inspect git log for creation date, rename with `git mv`
- **Existing frontmatter with `symptom:` (singular)** -- normalize to `symptoms:` (plural, array)
- **Existing frontmatter with CORA-specific fields** (`problem_type`, `component`, `root_cause`, `resolution_type`, `severity`) -- preserve as-is (no data loss), these are informational extras

#### Research Insights: Additional Edge Cases

- **`git add` before `git mv`** (from `2026-02-24-git-add-before-git-mv-for-untracked-files.md`): `agent-prompt-sharp-edges-only.md` might be untracked if it was created in the current session. Always run `git add` before `git mv` -- it is a no-op on already-tracked files.

- **Inline metadata with varied formatting:** Some files use `**Date:** 2026-02-06` (with space), others might use `**Date:**2026-02-06` (no space), or `**Date**: 2026-02-06` (colon outside bold). The extraction regex must account for these variants.

- **Title extraction from headings with prefixes:** Some files use `# Learning: Title Here`, others use `# Learnings: Title Here` (plural), others use `# Troubleshooting: Title`. Strip these common prefixes when generating the `title` field.

- **Tags as inline text vs YAML array:** Files with `**Tags:** workflow, architecture, simplification` use comma-separated text. Convert to YAML array format: `tags: [workflow, architecture, simplification]`. Normalize to lowercase, hyphen-separated.

- **Empty or whitespace-only tag values:** Some `## Tags` sections might have no content or just category labels. Default to extracting keywords from the filename slug.

- **Files with existing `synced_to` in frontmatter:** Preserve this field exactly -- it is managed by compound-capture and must not be modified.

### Performance

138 files is trivially small. The script runs in under 5 seconds.

### Risk: Content Corruption

The script must never modify file content below the frontmatter block. Strategy:
- Read full file into variable
- Generate frontmatter string
- Write: frontmatter + original content (minus any extracted inline metadata)
- Verify line count delta matches expected frontmatter addition

#### Research Insight: Verification Pattern

After writing each file, compute a content hash of the body (everything after frontmatter) and compare to the original body hash. This catches any accidental modification:

```bash
# Before modification
original_body_hash=$(tail -n +"$body_start_line" "$file" | md5sum | cut -d' ' -f1)

# After modification
new_body_hash=$(tail -n +"$new_body_start_line" "$file" | md5sum | cut -d' ' -f1)

if [[ "$original_body_hash" != "$new_body_hash" ]]; then
  echo "ERROR: Body content changed in $file" >&2
  exit 1
fi
```

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
- Given the script is run twice in succession, when the second run completes, then all files are identical to the first run (idempotency)
- Given a file with `synced_to: [constitution]` in existing frontmatter, when the script augments it, then `synced_to` is preserved unchanged
- Given a file whose body contains `---` (e.g., horizontal rules), when the script runs, then only the first `---`...`---` block is treated as frontmatter
- Given a file with title `# Learning: Title Here`, when the script generates frontmatter, then `title` is `Title Here` (prefix stripped)
- Given all 138 files processed, when the post-run verification runs, then zero files lack frontmatter (grep -rL check)

## Success Metrics

- 100% of learnings files pass YAML frontmatter validation (4 required fields present)
- Zero content corruption (diff shows only frontmatter additions/modifications, no body changes)
- Categories converge to 10-15 distinct values (not 80+ unique categories)

## Dependencies & Risks

- **No blockers** -- this task is independent (#424 states "Depends on: nothing")
- **Risk: Incorrect category assignment** -- Mitigated by manual review of the category mapping before committing
- **Risk: Duplicate content** -- If inline `**Date:**` is kept alongside frontmatter `date:`, information is redundant. Plan: remove inline metadata that duplicates frontmatter fields.
- **Risk: `grep -oP` requires GNU grep** -- macOS ships BSD grep which lacks `-P` (PCRE). Use `grep -oE` with POSIX ERE instead, or document GNU grep as a prerequisite. Since this runs on Linux (verified by environment), `-oP` is safe, but note the portability concern in script comments.
- **Risk: Horizontal rules parsed as frontmatter delimiters** -- Files containing `---` as markdown horizontal rules could be misidentified as frontmatter boundaries. The frontmatter check must verify `---` is the very first line of the file, and the closing `---` must appear within the first 20 lines (frontmatter blocks are short).
- **Risk: Parallel worktree conflicts** -- If another worktree also modifies learnings files, merge conflicts will occur. Since this is a bulk metadata-only change, conflicts are trivially resolvable (accept both changes).

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
PROCESSED=0
SKIPPED=0
AUGMENTED=0
CREATED=0

# --- Helper Functions ---

extract_title() {
  local file="$1"
  # Get first # heading, strip common prefixes (Learning:, Learnings:, Troubleshooting:)
  local raw_title
  raw_title=$(grep -m1 '^# ' "$file" | sed 's/^# //' | sed -E 's/^(Learning|Learnings|Troubleshooting): ?//' || echo "")
  echo "$raw_title"
}

extract_date_from_filename() {
  local filename="$1"
  # POSIX ERE instead of PCRE for portability (grep -oP is GNU-only)
  echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo ""
}

extract_inline_tags() {
  local file="$1"
  # Check for **Tags:** inline format (with or without space after colon)
  local tags
  tags=$(grep -oE '\*\*Tags:\*\*\s*(.+)' "$file" | sed 's/\*\*Tags:\*\*\s*//' || true)
  if [[ -z "$tags" ]]; then
    # Check for ## Tags section -- grab next non-empty line
    tags=$(awk '/^## Tags/{getline; while(/^$/) getline; print; exit}' "$file" || true)
  fi
  # Normalize: lowercase, trim whitespace, convert to YAML array
  echo "$tags" | tr '[:upper:]' '[:lower:]' | sed 's/,\s*/,/g'
}

has_frontmatter() {
  local file="$1"
  [[ "$(head -1 "$file")" == "---" ]]
}

frontmatter_has_field() {
  local file="$1"
  local field="$2"
  # Extract frontmatter (between first two ---) and check for field
  awk '/^---/{c++; if(c==2) exit} c==1' "$file" | grep -q "^${field}:" || return 1
}

generate_frontmatter() {
  local file="$1"
  local date_val="${2:-}"
  local title category tags

  title=$(extract_title "$file")
  category=$(infer_category "$file" "$(basename "$file" .md)")
  tags=$(extract_inline_tags "$file")

  # Build frontmatter block
  local fm="---"
  fm+=$'\n'"title: \"$title\""
  fm+=$'\n'"date: ${date_val:-unknown}"
  fm+=$'\n'"category: $category"
  if [[ -n "$tags" ]]; then
    fm+=$'\n'"tags: [${tags}]"
  else
    # Derive tags from filename slug
    local slug_tags
    slug_tags=$(basename "$file" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' | tr '-' ', ')
    fm+=$'\n'"tags: [${slug_tags}]"
  fi
  fm+=$'\n'"---"

  # Compute body hash before modification
  local original_body
  original_body=$(cat "$file")
  local original_hash
  original_hash=$(echo "$original_body" | md5sum | cut -d' ' -f1)

  # Prepend frontmatter, preserve original content
  echo -e "${fm}\n" | cat - "$file" > "$file.tmp" && mv "$file.tmp" "$file"

  ((CREATED++))
}

augment_frontmatter() {
  local file="$1"
  local date_val="${2:-}"
  local modified=false

  for field in title date category tags; do
    if frontmatter_has_field "$file" "$field"; then
      continue
    fi
    # Insert missing field before closing ---
    case "$field" in
      title)
        local title
        title=$(extract_title "$file")
        sed -i "0,/^---$/!{0,/^---$/{s/^---$/title: \"$title\"\n---/}}" "$file"
        modified=true
        ;;
      date)
        sed -i "0,/^---$/!{0,/^---$/{s/^---$/date: ${date_val:-unknown}\n---/}}" "$file"
        modified=true
        ;;
      category)
        local category
        category=$(infer_category "$file" "$(basename "$file" .md)")
        sed -i "0,/^---$/!{0,/^---$/{s/^---$/category: $category\n---/}}" "$file"
        modified=true
        ;;
      tags)
        local tags
        tags=$(extract_inline_tags "$file")
        if [[ -n "$tags" ]]; then
          sed -i "0,/^---$/!{0,/^---$/{s/^---$/tags: [$tags]\n---/}}" "$file"
          modified=true
        fi
        ;;
    esac
  done

  # Normalize symptom: (singular) to symptoms: (array)
  if frontmatter_has_field "$file" "symptom"; then
    local symptom_val
    symptom_val=$(awk '/^---/{c++; if(c==2) exit} c==1 && /^symptom:/' "$file" | sed 's/^symptom: //')
    sed -i "s/^symptom: .*/symptoms:\n  - $symptom_val/" "$file"
    modified=true
  fi

  if [[ "$modified" == "true" ]]; then
    ((AUGMENTED++))
  else
    ((SKIPPED++))
  fi
}

# --- Category Inference (ordered from most specific to most general) ---

infer_category() {
  local file="$1"
  local slug="$2"

  # Most specific patterns first to avoid ambiguity
  case "$slug" in
    # Compound patterns (most specific)
    *github-actions*|*gha-*|*claude-code-action*)          echo "ci-cd" ;;
    *worktree*|*merge-pr*|*ship*|*cleanup-merged*)          echo "workflow-patterns" ;;
    *agent-description*|*agent-prompt*|*disambiguation*)    echo "agent-design" ;;

    # Domain-specific patterns
    *gdpr*|*cla-*|*license*|*privacy*|*legal-*)             echo "legal" ;;
    *marketing*|*seo-*|*aeo-*|*brand-*)                     echo "marketing" ;;
    *mcp*|*pencil*|*terraform*|*discord*|*telegram*)        echo "infrastructure" ;;
    *docs-site*|*landing-page*|*css-*)                      echo "ui-css" ;;

    # General patterns
    *ci-*|*release*|*version-bump*|*workflow-security*)     echo "ci-cd" ;;
    *worktree*|*merge*|*pr-*|*commit*|*branch*|*git-*)     echo "workflow-patterns" ;;
    *agent*|*prompt*|*subagent*|*domain-leader*)            echo "agent-design" ;;
    *shell*|*bash*|*grep*|*sed*|*jq*|*pipefail*|*shebang*) echo "shell-scripting" ;;
    *plugin*|*skill*|*command*|*loader*)                    echo "plugin-architecture" ;;
    *security*|*secret*|*api-key*)                          echo "security" ;;
    *docs*|*brand*|*constitution*)                          echo "documentation" ;;
    *strategy*|*pricing*|*competitive*)                     echo "marketing" ;;

    # Catch-all
    *)                                                      echo "engineering" ;;
  esac
}

# --- Pre-flight: rename file without date prefix ---

rename_dateless_file() {
  local file="$1"
  local creation_date
  creation_date=$(git log --follow --diff-filter=A --format='%as' -- "$file" | tail -1)
  if [[ -z "$creation_date" ]]; then
    creation_date="2026-02-13"  # fallback: approximate from git history
  fi
  local new_name="knowledge-base/learnings/${creation_date}-$(basename "$file")"
  git add "$file"  # ensure tracked before git mv
  git mv "$file" "$new_name"
  echo "Renamed: $file -> $new_name"
}

# --- Main ---

# Handle dateless file first
dateless_file="$LEARNINGS_DIR/agent-prompt-sharp-edges-only.md"
if [[ -f "$dateless_file" ]]; then
  rename_dateless_file "$dateless_file"
fi

# Process all files
for file in "$LEARNINGS_DIR"/*.md; do
  filename=$(basename "$file")
  date_from_filename=$(extract_date_from_filename "$filename")

  if has_frontmatter "$file"; then
    augment_frontmatter "$file" "$date_from_filename"
  else
    generate_frontmatter "$file" "$date_from_filename"
  fi

  ((PROCESSED++))
done

# --- Post-run Verification ---
echo "Processed: $PROCESSED | Created: $CREATED | Augmented: $AUGMENTED | Skipped: $SKIPPED"

failed=$(grep -rL '^---' "$LEARNINGS_DIR"/*.md | wc -l || true)
if [[ "$failed" -gt 0 ]]; then
  echo "ERROR: $failed files still lack frontmatter:" >&2
  grep -rL '^---' "$LEARNINGS_DIR"/*.md >&2
  exit 1
fi

# Category distribution report
echo ""
echo "Category distribution:"
for f in "$LEARNINGS_DIR"/*.md; do
  awk '/^---/{c++; if(c==2) exit} c==1 && /^category:/{print $2}' "$f"
done | sort | uniq -c | sort -rn

echo ""
echo "All files have valid frontmatter."
```

### Verification Script (optional, `scripts/verify-frontmatter.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Validate all learnings have required frontmatter fields
LEARNINGS_DIR="knowledge-base/learnings"
ERRORS=0

for file in "$LEARNINGS_DIR"/*.md; do
  for field in title date category tags; do
    if ! awk '/^---/{c++; if(c==2) exit} c==1' "$file" | grep -q "^${field}:"; then
      echo "MISSING $field in $file" >&2
      ((ERRORS++))
    fi
  done
done

if [[ "$ERRORS" -gt 0 ]]; then
  echo "FAIL: $ERRORS missing fields across all files" >&2
  exit 1
fi

echo "PASS: All files have required frontmatter fields"
```
