---
title: "Skills page category consolidation from 8 to 4"
category: ui-bugs
tags:
  - documentation
  - information-architecture
  - skills-page
  - category-design
  - ux
module: docs-site
created: 2026-02-17
severity: low
synced_to:
  - plugins/soleur/skills/release-docs/SKILL.md
---

# Learning: Too many categories fragment navigation on catalog pages

## Problem

The Skills docs page had 8 categories (Development Tools, Browser & Testing, Content & Workflow, Review & Planning, Git & DevOps, Resolution & Automation, Documentation & Release, Image Generation) with pill nav links for each. Several categories held only 1-4 items, creating visual imbalance and forcing users to scan many small sections. The plugin README had an even worse split -- 10 sub-headings for 37 skills.

Meanwhile, the Agents page had already been consolidated to 6 categories (one per domain) ordered alphabetically, creating an inconsistency between the two reference pages.

## Solution

Consolidated 8 categories into 4 broader groups:

| Category | Count | Absorbed from |
|----------|-------|---------------|
| Content & Release | 12 | Content & Workflow + Documentation & Release + Image Generation |
| Development | 10 | Development Tools (unchanged) |
| Review & Planning | 4 | Review & Planning (unchanged) |
| Workflow | 11 | Browser & Testing + Git & DevOps + Resolution & Automation |

All 4 categories ordered alphabetically to match the Agents page convention.

Also updated:
- Plugin README skill tables (same 4 categories)
- release-docs SKILL.md (category reference on line 89)
- Added 2 skills missing from README (brainstorming, spec-templates)

## Key Insight

When a catalog page has more than ~5 top-level categories, consolidate until each group has meaningful weight (5+ items). A category with 1 item (Image Generation) signals over-fragmentation. The grouping principle: merge by user intent (what am I trying to do?) not by implementation detail (what tool type is this?). Keep category names and ordering consistent across all reference surfaces (docs page, README, release tooling).

## Prevention

- When adding a new skill, check if it fits an existing category before creating a new one
- The release-docs skill references the canonical category list -- update it if categories ever change
- Run a category audit whenever the skill count crosses a multiple of 10

## Cross-references

- [2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md](../2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md) -- earlier agents page consolidation
- [2026-02-13-static-docs-site-from-brand-guide.md](../2026-02-13-static-docs-site-from-brand-guide.md) -- docs site build pattern
- [2026-02-12-overview-docs-stale-after-restructure.md](../2026-02-12-overview-docs-stale-after-restructure.md) -- keeping docs in sync after restructures
- PR #121: https://github.com/jikig-ai/soleur/pull/121

## Tags

category: ui-bugs
module: docs-site
symptoms: too many pill nav categories, visual imbalance, 1-item categories, inconsistent grouping between pages
