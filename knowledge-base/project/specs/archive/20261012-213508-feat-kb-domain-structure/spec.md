# Feature: Knowledge-Base Domain Structure

## Problem Statement

The `knowledge-base/` directory mixes project-level infrastructure with domain-specific content. `overview/` conflates strategy docs (brand-guide, pricing, competitive-intelligence) with project docs (constitution, components). Domain leaders read/write to scattered locations instead of their own domain folder. Navigation is unclear — finding a marketing doc requires knowing it lives in `overview/` or `audits/` rather than `marketing/`.

## Goals

- Align knowledge-base directory structure with the canonical 8-department taxonomy
- Give each domain leader a clear read/write home directory
- Separate project-level docs (`constitution.md`, `components/`) from domain content
- Group shared feature artifacts (specs, plans, brainstorms, learnings) under `features/`

## Non-Goals

- Splitting specs/plans/brainstorms/learnings by domain (they stay feature-organized)
- Changing the `feat-<name>` spec convention (path updates only)
- Changing file content or frontmatter (pure path reorganization)

## Functional Requirements

### FR1: Domain directories

Create directories for all 8 canonical departments: engineering, finance, legal, marketing, operations, product, sales, support. Move existing domain content into the appropriate folder.

### FR2: Features grouping

Move specs/, plans/, brainstorms/, learnings/ under a new `features/` parent directory.

### FR3: Project directory

Rename `overview/` to `project/`. Keep only project-level docs: constitution.md, README.md, components/.

### FR4: Path reference updates

Update all hardcoded path references in agents (~20), skills (~6), scripts (2), GitHub Actions workflows (3), and commands (1).

## Technical Requirements

### TR1: Git history preservation

All file moves must use `git mv`. Single atomic commit for the structural change so it can be reverted with `git revert`.

### TR2: Archiving compatibility

Update `compound-capture`, `worktree-manager.sh cleanup-merged`, and the `archive-kb` script to use `features/` prefix for specs, plans, brainstorms paths.

### TR3: Learnings researcher routing

Update the hardcoded routing table in `learnings-researcher.md` to use `knowledge-base/features/learnings/` paths.

### TR4: CI workflow paths

Update hardcoded `git add` and `mkdir -p` paths in `scheduled-content-publisher.yml`, `scheduled-community-monitor.yml`, and `scheduled-competitive-analysis.yml`.

### TR5: Sync command

Update `sync.md` to create the new directory structure (`features/{learnings,brainstorms,specs,plans}`, `project/components`, domain dirs).

### TR6: Post-move verification

Run `grep -r` for all old path patterns to confirm zero stale references after migration.
