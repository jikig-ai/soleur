---
title: "fix: QA skill auto-start dev server"
type: fix
date: 2026-03-28
---

# fix: QA skill should auto-start dev server before skipping browser scenarios

Closes #1230

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

### Phase 1: Add Dev Server Lifecycle to SKILL.md

Modify `plugins/soleur/skills/qa/SKILL.md` to add a new step between the current Step 1 (Read Plan) and Step 2 (Detect Environment).

**New Step 1.5: Ensure Dev Server is Running**

Insert after Step 1 and before the current Step 2 (renumber if needed). The logic:

1. **Check if server is already running:**

   ```bash
   curl -sf --max-time 3 http://localhost:3000/ >/dev/null 2>&1 && echo "RUNNING" || echo "NOT_RUNNING"
   ```

   If `RUNNING`, skip to Step 2 (no action needed). Set `QA_STARTED_SERVER=false`.

2. **If NOT_RUNNING, detect the dev command:**
   - Walk up from the worktree root to find the closest `package.json` with a `scripts.dev` field
   - Primary: check `apps/web-platform/package.json` (the main app in this repo)
   - Fallback: check root `package.json`
   - Extract the dev command: `jq -r '.scripts.dev // empty' <path>/package.json`
   - If no dev command found, report: "No dev script found in package.json -- cannot auto-start server" and skip browser scenarios (do not block the pipeline)

3. **Detect port:**
   - Default: 3000
   - Parse from dev command if it contains `--port <N>` or `-p <N>`
   - Try 3000, then 3001 if 3000 is occupied

4. **Start the server:**
   - Check if Doppler is configured: `doppler secrets --only-names -p soleur -c dev 2>/dev/null | head -1`
   - If Doppler is available: `doppler run -p soleur -c dev -- <dev-command> --port <port> &`
   - If Doppler is not available: `<dev-command> --port <port> &`
   - Capture the background PID: `QA_SERVER_PID=$!`
   - Set `QA_STARTED_SERVER=true`

5. **Wait for server to respond (30s timeout):**

   ```bash
   for i in $(seq 1 30); do
     curl -sf --max-time 2 http://localhost:<port>/ >/dev/null 2>&1 && break
     sleep 1
   done
   ```

   If the server does not respond within 30 seconds:
   - Kill the background process
   - Capture and report the last 20 lines of server output as the failure reason
   - Report: "Dev server failed to start within 30s. Last output: ..."
   - Skip browser scenarios (do not block the pipeline entirely -- API verify steps may still run)

### Phase 2: Add Cleanup Step

Add a new Step 5.5 (after the pass/fail gate, before the skill returns):

**Step 5.5: Cleanup Dev Server**

- If `QA_STARTED_SERVER=true` and `QA_SERVER_PID` is set:
  - Kill the server process: `kill $QA_SERVER_PID 2>/dev/null`
  - Wait briefly for cleanup: `wait $QA_SERVER_PID 2>/dev/null`
  - Report: "Stopped auto-started dev server (PID <pid>)"
- If `QA_STARTED_SERVER=false`: no action needed

**Important:** The cleanup must run regardless of whether scenarios passed or failed. Place it after the pass/fail gate output but before returning control.

### Phase 3: Update Graceful Degradation Table

Update the `## Graceful Degradation` table to reflect the new behavior:

| Missing Prerequisite | Behavior |
|---------------------|----------|
| Dev server not running | Auto-start via package.json dev script; if startup fails, report reason and skip browser scenarios |
| No dev script in package.json | Warn and skip browser scenarios (API verification still runs) |
| Dev server startup timeout | Report last 20 lines of server output and skip browser scenarios |

### Phase 4: Update Prerequisites Section

Change the Prerequisites section from:

```markdown
- Local development server running (e.g., `npm run dev`, `bin/dev`)
```

To:

```markdown
- Local development server running OR a `dev` script in the project's `package.json` (auto-started if not running)
```

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/qa/SKILL.md` | Add Step 1.5 (auto-start), Step 5.5 (cleanup), update Prerequisites, update Graceful Degradation table |

## Acceptance Criteria

- [ ] QA skill attempts to start dev server before skipping browser scenarios
- [ ] Server process is cleaned up after QA completes (both pass and fail paths)
- [ ] If server startup fails (missing env vars, port conflict), QA reports the failure reason instead of silently skipping
- [ ] If package.json has no dev script, QA warns and skips browser scenarios without blocking the pipeline
- [ ] API verification steps still run even when browser scenarios are skipped due to server issues
- [ ] If dev server is already running, no auto-start is attempted (no-op path)
- [ ] Graceful Degradation table is updated to reflect auto-start behavior

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
