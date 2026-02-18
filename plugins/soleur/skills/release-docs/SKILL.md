---
name: release-docs
description: This skill should be used when updating documentation metadata after adding or removing plugin components. It updates plugin.json description, marketplace.json, and README.md counts, then verifies the Eleventy build produces correct output. Triggers on "update docs", "release documentation", "sync docs site", "regenerate docs", "documentation release".
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
- `.claude-plugin/marketplace.json` description with counts
- `plugins/soleur/README.md` component tables and counts

## Step 1: Inventory Current Components

Count all current components:

```bash
echo "Agents: $(find plugins/soleur/agents -name '*.md' -not -name 'README.md' | wc -l)"
echo "Commands: $(find plugins/soleur/commands -name '*.md' -not -name 'README.md' | wc -l)"
echo "Skills: $(find plugins/soleur/skills -name 'SKILL.md' | wc -l)"
```

## Step 2: Update Metadata Files

Ensure counts are consistent across:

1. **`plugins/soleur/.claude-plugin/plugin.json`**
   - Update `description` with correct counts

2. **`.claude-plugin/marketplace.json`**
   - Update plugin `description` with correct counts

3. **`plugins/soleur/README.md`**
   - Update intro paragraph with counts
   - Update component lists and tables

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

# Verify counts in output
echo "Agent cards: $(grep -c 'component-card' _site/pages/agents.html)"
echo "Skill cards: $(grep -c 'component-card' _site/pages/skills.html)"

# Verify JSON files
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
- marketplace.json - Updated description
- README.md - Updated component lists
- _data/skills.js - Updated category mapping (if applicable)
```

## Post-Release

After successful release:
1. Suggest updating CHANGELOG.md with documentation changes
2. Remind to commit with message: `docs: Update documentation metadata to match plugin components`
3. Remind to push changes -- the deploy workflow will rebuild the site automatically
