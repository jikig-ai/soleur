---
title: Quarterly Review Action Tasks
feature: feat-quarterly-review-action
date: 2026-02-21
---

# Tasks: Quarterly Review Action

## Phase 1: Implementation

- [x] 1.1 Create `.github/workflows/review-reminder.yml` with cron + workflow_dispatch triggers, permissions block
- [x] 1.2 Implement frontmatter scanning (recursive glob, sed-based `next_review` extraction, date comparison)
- [x] 1.3 Implement duplicate prevention (exact title match via `gh issue list`)
- [x] 1.4 Implement issue creation with generic template, source link, and `review-reminder` label

## Phase 2: Validation

- [x] 2.1 Test via `workflow_dispatch` with `date_override` simulating due and not-due states

## Phase 3: Ship

- [ ] 3.1 Code review
- [ ] 3.2 Compound learnings
- [ ] 3.3 Commit, push, PR
