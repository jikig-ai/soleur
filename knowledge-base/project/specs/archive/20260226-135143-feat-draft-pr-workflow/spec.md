# Spec: Draft PR Workflow

**Issue:** #304
**Branch:** `feat-draft-pr-workflow`
**Brainstorm:** [2026-02-25-draft-pr-workflow-brainstorm.md](../../brainstorms/2026-02-25-draft-pr-workflow-brainstorm.md)

## Problem Statement

Brainstorm and plan phases produce markdown artifacts (brainstorm docs, specs, plans, tasks) that exist only on local disk. No commits or pushes happen until the `work` and `ship` phases. This creates two problems:

1. A hardware failure, session crash, or power loss destroys all uncommitted artifacts from brainstorm and plan phases.
2. Cross-device handoff is impossible because the branch and PR don't exist on remote until `ship` Phase 7.

## Goals

- G1: Every workflow phase that produces artifacts commits them at phase completion
- G2: A draft PR exists on remote from the moment a feature branch/worktree is created
- G3: Pushes happen at skill boundaries for remote recoverability
- G4: The `ship` skill adapts to detect and update existing draft PRs instead of creating new ones
- G5: Network failures degrade gracefully — warn and continue, local commits still protect

## Non-Goals

- Changing the `worktree-manager.sh` script to create PRs (PR logic stays in orchestration layer)
- Adding draft PR creation to the `work` skill (it inherits from brainstorm/one-shot)
- Modifying the "commit is the gate" shipping sequence (review → compound → commit → push → merge)
- Creating a session manager abstraction (YAGNI)
- Skipping CI on draft PRs (accepted noise)

## Functional Requirements

- **FR1:** A shared `draft-pr.sh` script creates an empty commit, pushes, and opens a draft PR
- **FR2:** Brainstorm Phase 3 calls `draft-pr.sh` after worktree creation
- **FR3:** Brainstorm Phase 3.5 commits the brainstorm document
- **FR4:** Brainstorm Phase 3.6 commits spec + issue artifacts, then pushes
- **FR5:** Plan Phase 5 commits the plan markdown
- **FR6:** Plan post-phase commits tasks.md, then pushes
- **FR7:** One-shot Step 0b calls `draft-pr.sh` after branch creation
- **FR8:** Ship Phase 7 detects existing draft PR and uses `gh pr edit` + `gh pr ready` instead of `gh pr create`
- **FR9:** All push/PR failures print warnings but do not block the workflow

## Technical Requirements

- **TR1:** `draft-pr.sh` must be idempotent — safe to call if PR already exists
- **TR2:** `draft-pr.sh` must handle the case where the remote branch already exists
- **TR3:** Ship must detect draft PRs by branch name (`gh pr list --head <branch>`)
- **TR4:** Phase commits use conventional messages (e.g., `docs: capture brainstorm for <feature>`)
- **TR5:** No changes to `worktree-manager.sh` — it remains a pure git utility
