# Spec: Persist Competitive Intelligence as Living Document

**Date:** 2026-03-02
**Branch:** feat-living-competitive-intel
**PR:** #352

## Problem Statement

The competitive-intelligence agent writes `knowledge-base/overview/competitive-intelligence.md` during scheduled GitHub Action runs, but the CI workspace is ephemeral. The file is discarded after the workflow completes. Other agents that read from `knowledge-base/overview/` (CPO, brand-architect, learnings-researcher) cannot access competitive intelligence from disk. Humans must search GitHub Issues to find the latest report.

## Goals

- G1: The competitive intelligence report persists as a living document in `knowledge-base/overview/competitive-intelligence.md`
- G2: The file is automatically updated each time the scheduled workflow runs
- G3: The update is pushed directly to main (no PR overhead — rulesets only block force-push/deletion)
- G4: GitHub Issues continue to be created as notification/audit trail

## Non-Goals

- Changing the agent's report format or content
- Adding new tiers to the scheduled scan
- Replacing GitHub Issues with the file (both coexist)
- Supporting manual edits to the file (new report always overwrites)

## Functional Requirements

- **FR1:** After the Claude step completes, check if `knowledge-base/overview/competitive-intelligence.md` exists in the workspace
- **FR2:** If the file exists and has changed, commit and push directly to main
- **FR3:** If main has diverged, retry with `git pull --rebase` (new report wins)
- **FR4:** If the file does not exist (agent failed), log a warning and skip — do not fail the workflow
- **FR5:** If file content is identical to main, skip with a notice — do not create an empty commit

## Technical Requirements

- **TR1:** Update workflow permissions to `contents: write` (was: `read`)
- **TR2:** Commit uses `github-actions[bot]` identity
- **TR3:** Step runs only when the Claude step succeeds (default behavior)

## Acceptance Criteria

- [ ] Workflow runs successfully and pushes the report to main
- [ ] `competitive-intelligence.md` exists on main after push
- [ ] GitHub Issue is still created (existing behavior preserved)
- [ ] Workflow handles missing file gracefully (warning, not failure)
- [ ] Workflow handles identical content gracefully (notice, not failure)
