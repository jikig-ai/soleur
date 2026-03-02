# Spec: Persist Competitive Intelligence as Living Document

**Date:** 2026-03-02
**Branch:** feat-living-competitive-intel
**PR:** #352

## Problem Statement

The competitive-intelligence agent writes `knowledge-base/overview/competitive-intelligence.md` during scheduled GitHub Action runs, but the CI workspace is ephemeral. The file is discarded after the workflow completes. Other agents that read from `knowledge-base/overview/` (CPO, brand-architect, learnings-researcher) cannot access competitive intelligence from disk. Humans must search GitHub Issues to find the latest report.

## Goals

- G1: The competitive intelligence report persists as a living document in `knowledge-base/overview/competitive-intelligence.md`
- G2: The file is automatically updated each time the scheduled workflow runs
- G3: The update happens via PR (respecting branch protection), auto-merged without human intervention
- G4: GitHub Issues continue to be created as notification/audit trail

## Non-Goals

- Changing the agent's report format or content
- Adding new tiers to the scheduled scan
- Replacing GitHub Issues with the file (both coexist)
- Supporting manual edits to the file (new report always overwrites)

## Functional Requirements

- **FR1:** After the Claude step completes, check if `knowledge-base/overview/competitive-intelligence.md` exists in the workspace
- **FR2:** If the file exists, create a branch `ci/competitive-intel-YYYY-MM-DD`, commit the file, push, and open a PR
- **FR3:** Auto-merge the PR via `gh pr merge --squash --auto`
- **FR4:** If merge conflicts occur, resolve by accepting the new report (`--strategy-option theirs`) and force-push
- **FR5:** If the file does not exist (agent failed), log a warning and skip — do not fail the workflow

## Technical Requirements

- **TR1:** Update workflow permissions to `contents: write` and `pull-requests: write`
- **TR2:** All new actions pinned to commit SHAs (per existing security pattern)
- **TR3:** Commit message includes `[skip ci]` to avoid triggering other workflows
- **TR4:** Branch naming: `ci/competitive-intel-YYYY-MM-DD`
- **TR5:** The persist step runs only on `success()` of the Claude step

## Acceptance Criteria

- [ ] Workflow runs successfully and creates a PR with the report
- [ ] PR is auto-merged without human intervention
- [ ] `competitive-intelligence.md` exists on main after merge
- [ ] GitHub Issue is still created (existing behavior preserved)
- [ ] Workflow handles missing file gracefully (warning, not failure)
