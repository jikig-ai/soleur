---
title: "Merge Design Domain under Product Domain"
plan: "../../plans/2026-02-19-refactor-merge-design-domain-under-product-plan.md"
---

# Tasks

## Phase 1: Move Agent File

- [x] 1.1 Create `plugins/soleur/agents/product/design/` directory
- [x] 1.2 `git mv plugins/soleur/agents/design/ux-design-lead.md plugins/soleur/agents/product/design/ux-design-lead.md`
- [x] 1.3 Remove empty `plugins/soleur/agents/design/` directory

## Phase 2: Update References

- [x] 2.1 Update `plugins/soleur/README.md`: remove top-level Design section, add Design sub-section under Product
- [x] 2.2 Update `plugins/soleur/AGENTS.md`: update directory tree diagram
- [x] 2.3 Update `plugins/soleur/docs/_data/agents.js`: remove design from domain labels, CSS vars, and domain order
- [x] 2.4 Update `plugins/soleur/docs/css/style.css`: remove `--cat-design` variable
- [x] 2.5 Update `plugins/soleur/docs/pages/community.njk`: change `cat-design` to `cat-tools`

## Phase 3: Version Bump

- [x] 3.1 Bump `plugins/soleur/.claude-plugin/plugin.json` to 2.17.0, update description
- [x] 3.2 Update `plugins/soleur/CHANGELOG.md` with new entry
- [x] 3.3 Update `plugins/soleur/README.md` header badge if present
- [x] 3.4 Update root `README.md` if it mentions domain count
- [x] 3.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder

## Phase 4: Verify

- [x] 4.1 Verify `plugins/soleur/agents/design/` no longer exists
- [x] 4.2 Verify `plugins/soleur/agents/product/design/ux-design-lead.md` exists
- [x] 4.3 Grep for stale `agents/design/` references (excluding CHANGELOG history)
- [x] 4.4 Verify docs build succeeds
