# Learning: Thin Router Over Migration for Command Simplification

## Problem

Soleur had 8 commands but users only regularly used 4 (brainstorm, one-shot, sync, help). The natural instinct was to "simplify" by migrating rarely-used commands to skills and consolidating the namespace. Initial brainstorm proposed migrating 6 commands to skills and creating a bare `/soleur` entry point.

Research during planning revealed two blockers:
1. **Plugin loader constraint**: Claude Code requires `namespace:name` format -- bare `/soleur` without a colon suffix is not supported by the plugin system.
2. **Migration risk**: Moving commands to skills changes frontmatter format (`argument-hint` vs third-person descriptions), directory structure, argument handling (`#$ARGUMENTS`), and breaks 50+ cross-references in other commands that invoke them via the Skill tool.

## Solution

Instead of migrating existing commands, add a single thin router command (`/soleur:go`) that classifies user intent and delegates to existing commands unchanged. Update the help output to surface the router as the primary entry point.

**Architecture**: 57-line command with 3-intent classification (explore, build, review), worktree context detection, and AskUserQuestion confirmation before delegation.

**Key insight**: The simplification users want is in the **experience** (fewer entry points to remember), not the **architecture** (fewer files). A router achieves the UX goal with zero migration risk.

Total changes: 2 files modified/created, 0 files migrated.

## Session Errors

1. **Bare `/soleur` assumption**: Brainstorm assumed bare namespace commands were possible. Plugin loader research during planning revealed this was not supported. Recovered by falling back to `/soleur:go`.
2. **`spec-templates` skill not found**: Glob for `plugins/soleur/skills/spec-templates/**/*` returned no results during spec generation. Recovered by reading an existing spec file to learn the format pattern.

## Key Insight

When simplifying a multi-command system, prefer adding a router over migrating existing components. Migration has hidden costs (cross-reference breakage, format differences, testing burden) that outweigh the cosmetic benefit of fewer files. The user experience improvement comes from the entry point, not the file count.

This generalizes: "add a facade, don't reorganize the internals" -- especially when the internals have accumulated cross-references that make reorganization fragile.

## Prevention

- Before proposing command-to-skill migration, audit cross-references with `grep -r "skill:.*command-name"` across all plugin files
- Test plugin loader constraints (bare namespace, nested skills) before designing around them
- Run SpecFlow analysis early to catch integration risks before committing to an approach

## Tags
category: implementation-patterns
module: plugin-commands
