# Spec: Merge Conflict Targeted Fixes

**Issue:** #395
**Branch:** feat-merge-conflict-fixes
**Date:** 2026-03-03

## Problem Statement

The codebase has three overlapping merge conflict resolution codepaths with inconsistent strategies (AGENTS.md mandates rebase, skills use merge) and missing preventive mechanisms (no pre-push sync, no conflict marker detection, no worktree refresh).

## Goals

- G1: Eliminate the rebase/merge contradiction across AGENTS.md, constitution.md, and the pre-merge hook
- G2: Detect and resolve conflicts *before* PR creation, not after
- G3: Prevent accidentally committing unresolved conflict markers
- G4: Provide a mechanism to keep long-lived worktrees current with main

## Non-Goals

- Building a full autonomous merge conflict resolution pipeline (deferred — #412 eliminated the primary need)
- Extracting a shared conflict resolution utility (deferred — not enough code to justify)
- Changing the squash-merge PR strategy
- Modifying `/merge-pr` conflict resolution logic

## Functional Requirements

- **FR1:** AGENTS.md hard rule updated from "rebase on origin/main" to "merge origin/main" with matching constitution.md update
- **FR2:** `pre-merge-rebase.sh` hook updated to use `git merge origin/main` instead of `git rebase origin/main`, renamed to `pre-merge-sync.sh`
- **FR3:** `/ship` SKILL.md gains a new Phase 5.5 (pre-push sync) that: fetches origin/main, checks for divergence, merges if needed, attempts Claude-assisted conflict resolution, falls back to structured summary on low confidence
- **FR4:** `guardrails.sh` gains a new guard that intercepts `git commit` and checks staged files for conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
- **FR5:** `worktree-manager.sh` gains a `refresh` subcommand that fetches origin/main and merges into the current branch

## Technical Requirements

- **TR1:** The pre-push sync in `/ship` must reuse the per-file conflict resolution strategies from `/merge-pr` Phase 3.1 (CHANGELOG: merge both sides, README: accept feature branch, else: Claude-assisted)
- **TR2:** The conflict marker hook must check staged content only (`git diff --cached`), not the working tree
- **TR3:** The worktree refresh command must verify clean working tree before merging and abort with a message if dirty
- **TR4:** Hook rename (`pre-merge-rebase.sh` to `pre-merge-sync.sh`) must update `.claude/settings.json` hook registration
- **TR5:** All git commands in hooks must redirect stdout/stderr to avoid corrupting JSON output (documented learning)
