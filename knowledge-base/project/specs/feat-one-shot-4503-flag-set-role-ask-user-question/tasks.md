---
title: "Tasks: flag-set-role AskUserQuestion for operator ack"
plan: knowledge-base/project/plans/2026-05-26-improve-flag-set-role-ask-user-question-plan.md
branch: feat-one-shot-4503-flag-set-role-ask-user-question
---

# Tasks

## Phase 1: Add `--confirmed` flag to `flip.sh`

- [x] 1.1 Initialize `CONFIRMED=0` alongside `DRY_RUN=0` (line 39)
- [x] 1.2 Add `--confirmed) CONFIRMED=1; shift ;;` case before `--*)` catch-all (line 51)
- [x] 1.3 Replace interactive prompt block (lines 249-252) with `CONFIRMED` guard
- [x] 1.4 Update `usage()` function to include `--confirmed`
- [x] 1.5 Update script header comment (line 7) to document `--confirmed`

## Phase 2: Update SKILL.md

- [x] 2.1 Add `--confirmed` to Arguments section (line 30)
- [x] 2.2 Update Procedure section Step 6 with agent-driven flow (dry-run, AskUserQuestion, --confirmed)
- [x] 2.3 Update Procedure code block to show both `--dry-run` and `--confirmed` forms

## Verification

- [x] 3.1 AC1: `grep -c 'read -p' flip.sh` returns 1
- [x] 3.2 AC2: `grep -A2 'CONFIRMED -eq 0' flip.sh | grep -c 'read -p'` returns 1
- [x] 3.3 AC3: `grep -n 'CONFIRMED' flip.sh` shows exactly 3 occurrences
- [x] 3.4 AC4: `grep -c 'AskUserQuestion' SKILL.md` returns >= 1
- [x] 3.5 AC5: `grep -c '\-\-confirmed' SKILL.md` returns >= 2
