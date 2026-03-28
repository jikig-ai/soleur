# Tasks: QA Auto-Start Dev Server

Source: `knowledge-base/project/plans/2026-03-28-fix-qa-auto-start-dev-server-plan.md`

## Phase 1: Add Dev Server Lifecycle

- [ ] 1.1 Read `plugins/soleur/skills/qa/SKILL.md`
- [ ] 1.2 Add new Step 1.5: Ensure Dev Server is Running
  - [ ] 1.2.1 Add server reachability check (curl localhost:3000)
  - [ ] 1.2.2 Add dev command detection from package.json
  - [ ] 1.2.3 Add port detection logic (default 3000, fallback 3001)
  - [ ] 1.2.4 Add Doppler-aware server startup (doppler run or bare command)
  - [ ] 1.2.5 Add 30-second startup polling with timeout
  - [ ] 1.2.6 Add failure reporting with last 20 lines of server output

## Phase 2: Add Cleanup Step

- [ ] 2.1 Add Step 5.5: Cleanup Dev Server (kill auto-started process)
- [ ] 2.2 Ensure cleanup runs on both pass and fail paths

## Phase 3: Update Graceful Degradation Table

- [ ] 3.1 Update "Dev server not running" row to reflect auto-start behavior
- [ ] 3.2 Add "No dev script in package.json" row
- [ ] 3.3 Add "Dev server startup timeout" row

## Phase 4: Update Prerequisites

- [ ] 4.1 Change prerequisite from "Local development server running" to "running OR auto-startable via package.json"

## Phase 5: Validation

- [ ] 5.1 Run `npx markdownlint --fix` on modified SKILL.md
- [ ] 5.2 Verify the SKILL.md reads correctly end-to-end
- [ ] 5.3 Verify step numbering is consistent after insertion
