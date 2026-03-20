---
feature: integrate-one-shot-brainstorm
issue: "#64"
date: 2026-02-12
---

# Tasks: Integrate One Shot into Brainstorm

## Phase 1: Implementation

- [ ] 1.1 Add Phase 0.5 (Simplicity Gate) to `plugins/soleur/commands/soleur/brainstorm.md`
  - Add simplicity heuristics after the existing requirement clarity check
  - Present AskUserQuestion with one-shot, plan, brainstorm options
  - Handle one-shot selection by passing through to `/soleur:one-shot`

## Phase 2: Shipping

- [ ] 2.1 Bump version (PATCH) in plugin.json, CHANGELOG.md, README.md
- [ ] 2.2 Run code review on changes
- [ ] 2.3 Run `/soleur:compound` for learnings
- [ ] 2.4 Commit, push, and create PR referencing #64
