# Learning: Skill Count Appears in 5+ Active Files

## Problem

When removing 2 skills from the plugin loader, the initial plan identified 3 files needing skill count updates (plugin.json, plugin README, root README). The deepen phase discovered 2 additional locations: `knowledge-base/overview/brand-guide.md` (2 occurrences in prose text) and `docs/_data/skills.js` (comment on line 7). Stale counts in the brand guide propagate into marketing copy and Discord posts via the content-writer and discord-content skills.

## Solution

When changing skill (or agent) counts, grep for the old count across the entire repo:

```bash
grep -rn '\bNN skills\b' . --include='*.md' --include='*.js' --include='*.json' --include='*.yml' | grep -v CHANGELOG.md | grep -v node_modules | grep -v knowledge-base/plans/
```

The canonical list of files containing skill counts:
1. `plugins/soleur/.claude-plugin/plugin.json` (description field)
2. `plugins/soleur/README.md` (components table)
3. `README.md` (root, "What is Soleur?" section)
4. `knowledge-base/overview/brand-guide.md` (positioning + do's sections)
5. `plugins/soleur/docs/_data/skills.js` (comment line)

Historical files (CHANGELOG, plans) should NOT be updated -- they are accurate records of past state.

## Key Insight

Count propagation is a common source of stale data. The deepen-plan phase caught these by running exhaustive greps, which the initial plan missed. Always grep for the old value rather than relying on a memorized file list.

## Tags

category: implementation-patterns
module: plugin-architecture
symptoms: stale-count, wrong-skill-count, brand-guide-stale
