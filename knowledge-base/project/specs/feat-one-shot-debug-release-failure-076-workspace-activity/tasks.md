---
title: "Tasks: debug release failure 076_workspace_activity"
date: 2026-05-27
plan: knowledge-base/project/plans/2026-05-27-debug-release-failure-076-workspace-activity-plan.md
---

# Tasks

## Phase 1: Create Learning Document

- [x] 1.1 Create `knowledge-base/project/learnings/bug-fixes/2026-05-27-release-failure-076-workspace-activity-dollar-quote-and-jti-sentinel.md`
  - [x] 1.1.1 YAML frontmatter with title, date, category, tags, symptoms, module
  - [x] 1.1.2 Problem section: three consecutive release failures, timeline table
  - [x] 1.1.3 Root Cause 1: dollar-quote collision in pg_cron DO block
  - [x] 1.1.4 Root Cause 2: JTI deny policy count sentinel drift (21 -> 23)
  - [x] 1.1.5 Contributing factor: migration-number collision at prefix 076
  - [x] 1.1.6 Prevention patterns section
  - [x] 1.1.7 Fix references: PR #4547, PR #4548

## Phase 2: Commit and Push

- [x] 2.1 Stage learning document
- [x] 2.2 Commit with conventional message
- [ ] 2.3 Push to branch
