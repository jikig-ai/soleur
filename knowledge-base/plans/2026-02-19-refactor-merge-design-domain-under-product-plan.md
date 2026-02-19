---
title: "Merge Design Domain under Product Domain"
type: refactor
date: 2026-02-19
---

# Merge Design Domain under Product Domain

## Overview

Move the top-level `agents/design/` domain under `agents/product/design/` to consolidate Design as a sub-domain of Product. This reduces top-level domains from 5 to 4 (Engineering, Marketing, Operations, Product) and renames `soleur:design:ux-design-lead` to `soleur:product:design:ux-design-lead`.

## Problem Statement

The Design domain currently exists as a standalone top-level domain with a single agent (`ux-design-lead`). Design is functionally part of the Product domain -- having it separate adds unnecessary directory structure and cognitive overhead for 1 agent. Issue #156 requests merging it under Product.

## Proposed Solution

Move `agents/design/ux-design-lead.md` to `agents/product/design/ux-design-lead.md` and update all references across the codebase.

## Acceptance Criteria

- [x] `plugins/soleur/agents/design/` directory removed
- [x] `plugins/soleur/agents/product/design/ux-design-lead.md` exists with identical content
- [x] Agent discovered as `soleur:product:design:ux-design-lead` (verified by directory structure)
- [x] README.md: Design section removed from top-level, ux-design-lead listed under Product > Design
- [x] docs `agents.js`: `design` removed from `DOMAIN_LABELS`, `domainOrder`; CSS var removed
- [x] docs `style.css`: `--cat-design` CSS variable repurposed or removed
- [x] docs `community.njk`: `cat-design` reference updated
- [x] AGENTS.md directory tree updated (no `design/` at top level, `design/` under `product/`)
- [x] CHANGELOG.md updated
- [x] plugin.json version bumped (minor: structural reorganization)
- [x] plugin.json description updated (agent count unchanged, domain count changes)
- [x] Root README.md -- no count changes needed (still 32 agents)

## Test Scenarios

- Given the plugin directory structure, when the agent loader walks `agents/`, then `ux-design-lead` is discovered under `product/design/`
- Given the docs site builds, when agents.js processes the directory, then `ux-design-lead` appears under Product domain with a Design sub-category
- Given a user references `soleur:design:ux-design-lead`, when they try to invoke it, then the new name `soleur:product:design:ux-design-lead` is what's discovered

## MVP

### Files to Modify

1. **`plugins/soleur/agents/product/design/ux-design-lead.md`** (create -- move from `agents/design/`)
2. **`plugins/soleur/agents/design/`** (delete directory)
3. **`plugins/soleur/README.md`**
   - Remove `### Design (1)` top-level section (lines ~127-131)
   - Update `### Product (1)` to `### Product (2)` and add `#### Design (1)` sub-section with ux-design-lead
4. **`plugins/soleur/AGENTS.md`**
   - Update directory tree: remove `design/` from top level, add `design/` under `product/`
5. **`plugins/soleur/docs/_data/agents.js`**
   - Remove `design` from `DOMAIN_LABELS` (line 6)
   - Remove `design` from `DOMAIN_CSS_VARS` (line 23)
   - Remove `"design"` from `domainOrder` array (line 140)
6. **`plugins/soleur/docs/css/style.css`**
   - Remove or keep `--cat-design` (it was only used for the design domain dot -- now product will use `--cat-tools`)
7. **`plugins/soleur/docs/pages/community.njk`**
   - Update `cat-design` reference to `cat-tools` (product domain color)
8. **`plugins/soleur/CHANGELOG.md`** -- add entry
9. **`plugins/soleur/.claude-plugin/plugin.json`** -- bump to 2.17.0, update description to "4 domains"
10. **Root `README.md`** -- verify counts (still 32 agents, no change needed unless it mentions 5 domains)
11. **`.github/ISSUE_TEMPLATE/bug_report.yml`** -- update version placeholder

### brainstorm.md reference (no change needed)

`commands/soleur/brainstorm.md:314` references "ux-design-lead agent" by name (not by path). No change needed since the agent name stays the same.

## References

- Issue: #156
- Prior domain restructure: CHANGELOG v2.0.0 (moved `agents/design/` to `agents/engineering/design/` for ddd-architect)
- Prior ux-design-lead creation: CHANGELOG v2.9.0 (created `agents/design/` for ux-design-lead)
