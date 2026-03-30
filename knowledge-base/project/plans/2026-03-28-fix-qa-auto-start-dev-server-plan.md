---
title: "fix: QA skill auto-start dev server"
type: fix
date: 2026-03-28
---

# fix: QA skill should auto-start dev server before skipping browser scenarios

Closes #1230

## Enhancement Summary

**Deepened on:** 2026-03-28
**Sections enhanced:** Implementation Plan (simplified from 4 phases to 1 atomic edit)
**Review agents used:** code-simplicity-reviewer, learnings-researcher

### Key Improvements

1. Collapsed 4 phases into 1 atomic edit — this is a single-file, single-commit change
2. Instructions written as intent for the AI agent, not prescriptive bash — Claude can derive `curl`, `jq`, `kill` implementations
3. Dropped temp log file complexity — unnecessary cleanup burden for a QA context

### Research Insights

- **Pipeline continuation:** The one-shot pipeline learned (2026-03-03) that conclusive-sounding output stalls pipelines. The QA skill must output clear continuation signals, not terminal phrases like "QA complete."
- **Insights learning (2026-03-28):** QA/review being skipped when dev server wasn't running was one of the top 6 friction points across 100 sessions. This fix directly addresses it.
- **Port config:** Verified `apps/web-platform/server/index.ts:15` uses `PORT` env var defaulting to 3000.
- **Dev command:** Verified `apps/web-platform/package.json` uses `tsx server/index.ts` as the dev command.

## Problem

The `/soleur:qa` skill currently lists "Local development server running" as a prerequisite and fails browser scenarios with "Server not reachable" when the dev server is not running. This violates the AGENTS.md hard rule: "Exhaust all automated options before suggesting manual steps." In practice, QA gets skipped entirely during one-shot pipelines because no one is around to start the server.

**Discovered during:** #1041 one-shot pipeline -- QA was skipped entirely with "Dev server not running" and the founder had to flag it.

## Current Behavior

1. QA skill checks if dev server is running (implicit -- browser scenarios fail when it is not)
2. Browser scenarios fail with "Server not reachable"
3. QA report shows failures or the pipeline skips browser testing
4. The `## Graceful Degradation` table says: `Dev server not running | Fail browser scenarios with "Server not reachable"`

## Expected Behavior

1. QA skill detects whether the dev server is running before executing browser scenarios
2. If not running, detect the project's dev command from the nearest `package.json`
3. Start the server via `doppler run` (if Doppler is configured) or bare dev command
4. Wait for server to respond (poll with timeout)
5. Run browser scenarios against the started server
6. Kill the server process after QA completes (cleanup)
7. If startup fails (missing env vars, port conflict, command not found), report the specific failure reason instead of silently skipping

## Implementation Plan

Single atomic edit to `plugins/soleur/skills/qa/SKILL.md`. Four changes in one pass:

### Edit 1: Add Step 1.5 "Ensure Dev Server is Running"

Insert between Step 1 (Read Plan) and Step 2 (Detect Environment). Intent-based instructions for the agent:

1. Check if the dev server is already reachable at `http://localhost:3000` (curl with 3s timeout). If reachable, skip to Step 2.
2. If not reachable, find the dev command from `apps/web-platform/package.json` `scripts.dev` field. If no dev script exists, warn and skip browser scenarios (API verify steps still run).
3. Start the server in the background via `doppler run -p soleur -c dev -- <dev-command> &` (fall back to bare command if Doppler is unavailable). Record the PID.
4. Poll until the server responds or 30 seconds elapse. If timeout, kill the process, report the failure reason, and skip browser scenarios.

### Edit 2: Add Step 5.5 "Cleanup Dev Server"

After the pass/fail gate (Step 5), before the skill returns. One instruction: if a dev server was started in Step 1.5, kill the process by PID. This runs regardless of pass/fail.

### Edit 3: Update Graceful Degradation table

Replace the "Dev server not running" row. Add two new rows:

| Missing Prerequisite | Behavior |
|---------------------|----------|
| Dev server not running | Auto-start via package.json dev script; if startup fails, report reason and skip browser scenarios |
| No dev script in package.json | Warn and skip browser scenarios (API verification still runs) |
| Dev server startup timeout (30s) | Report failure reason and skip browser scenarios |

### Edit 4: Update Prerequisites section

Change "Local development server running" to note auto-start capability:
"Local development server running OR a `dev` script in `package.json` (auto-started if not running)"

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/qa/SKILL.md` | Add Step 1.5 (auto-start), Step 5.5 (cleanup), update Prerequisites, update Graceful Degradation table |

## Acceptance Criteria

- [x] QA skill attempts to start dev server before skipping browser scenarios
- [x] Server process is cleaned up after QA completes (both pass and fail paths)
- [x] If server startup fails (missing env vars, port conflict), QA reports the failure reason instead of silently skipping
- [x] If package.json has no dev script, QA warns and skips browser scenarios without blocking the pipeline
- [x] API verification steps still run even when browser scenarios are skipped due to server issues
- [x] If dev server is already running, no auto-start is attempted (no-op path)
- [x] Graceful Degradation table is updated to reflect auto-start behavior

## Test Scenarios

### Scenario 1: Dev server not running, auto-start succeeds

- Given: dev server is not running, `apps/web-platform/package.json` has a `dev` script
- When: QA skill is invoked with a plan containing browser scenarios
- Then: server is auto-started, browser scenarios execute, server is killed after QA

### Scenario 2: Dev server already running

- Given: dev server is already running on port 3000
- When: QA skill is invoked
- Then: no auto-start is attempted, browser scenarios execute normally, no cleanup kill

### Scenario 3: Dev server startup fails

- Given: dev server fails to start (e.g., missing env vars)
- When: QA skill is invoked
- Then: failure reason is reported with last 20 lines of output, browser scenarios are skipped, API verify steps still run

### Scenario 4: No dev script in package.json

- Given: no `dev` script exists in any discoverable package.json
- When: QA skill is invoked with browser scenarios
- Then: warning is displayed, browser scenarios are skipped, API verify steps still run

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling/skill improvement.

## Context

- The QA skill is invoked by `/soleur:one-shot` at step 5.5 and can also be invoked directly
- The web-platform app uses `tsx server/index.ts` as its dev command
- Doppler project is `soleur`, config is `dev`
- The AGENTS.md "Review & Feedback" section already states: "Never skip QA/review phases before merging, even if the dev server isn't running. If the dev server is needed, start it first."
- This fix makes the QA skill comply with that rule automatically

## References

- Issue: #1230
- Related learning: `knowledge-base/project/learnings/2026-03-28-insights-driven-workflow-improvements.md`
- QA skill: `plugins/soleur/skills/qa/SKILL.md`
- One-shot invocation: `plugins/soleur/skills/one-shot/SKILL.md` line 108
