---
name: release-docs
description: "This skill should be used when updating documentation metadata after adding or removing plugin components. It updates plugin.json description and README.md counts, then verifies the Eleventy build produces correct output."
---

# Release Documentation

Update documentation metadata and verify the docs site builds correctly after plugin component changes.

## Overview

The documentation site auto-generates agent and skill catalog pages from source file frontmatter via Eleventy. This skill handles the metadata files that still need manual updates.

**What is automated (no action needed):**

- Agent catalog page (`pages/agents.html`) -- built from `agents/**/*.md` frontmatter
- Skill catalog page (`pages/skills.html`) -- built from `skills/*/SKILL.md` frontmatter
- Stats on landing page -- counted from file system at build time

**What still needs manual updates:**

- `plugins/soleur/.claude-plugin/plugin.json` description with counts
- `knowledge-base/marketing/brand-guide.md` agent/skill counts (if it exists)

## Step 1: Sync README Counts

Run the automated sync script to update counts in both `README.md` and `plugins/soleur/README.md`:

```bash
bash scripts/sync-readme-counts.sh
```

This updates: root README intro line, root README "What is Soleur?" counts, plugin README component count table, and plugin README domain section headers.

## Step 2: Update plugin.json

Update `plugins/soleur/.claude-plugin/plugin.json` description with correct counts (not covered by the sync script).

## Step 3: Update Skill Category Mapping (if needed)

If skills were added, removed, or recategorized, update the category mapping in:

```
plugins/soleur/docs/_data/skills.js
```

The `SKILL_CATEGORIES` object maps each skill name to its display category. New skills must be added here or they will appear as "Uncategorized" in the catalog.

## Step 4: Verify Build

```bash
# Run the Eleventy build
npx @11ty/eleventy
```

After the build completes, verify counts by using Grep to count occurrences of `component-card` in `_site/pages/agents.html` and `_site/pages/skills.html`.

Verify JSON files are well-formed:

```bash
cat plugins/soleur/.claude-plugin/plugin.json | jq .
```

## Step 5: Report Changes

Provide a summary of what was updated:

```
## Documentation Release Summary

### Component Counts
- Agents: X (previously Y)
- Commands: X (previously Y)
- Skills: X (previously Y)

### Files Updated
- plugin.json - Updated counts
- README.md - Updated component lists
- _data/skills.js - Updated category mapping (if applicable)
```

## Post-Release

After successful release:

1. Suggest updating CHANGELOG.md with documentation changes
2. Remind to commit with message: `docs: Update documentation metadata to match plugin components`
3. Remind to push changes -- the deploy workflow will rebuild the site automatically
