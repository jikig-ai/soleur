# Post-Connect Sync Proposal -- Tasks

**Plan:** `knowledge-base/project/plans/2026-04-07-feat-post-connect-sync-proposal-plan.md`
**Issue:** #1772
**Branch:** feat-post-connect-sync-proposal

## Phase 1: Fast File Scanner and Database Migration

- [ ] 1.1 Create `apps/web-platform/server/project-scanner.ts`
  - [ ] 1.1.1 Implement `scanProjectHealth(workspacePath)` with `fs.existsSync` checks
  - [ ] 1.1.2 Define `ProjectHealthSnapshot` type inline (signals, recommendations, kbState)
  - [ ] 1.1.3 Implement categorization algorithm (Strong 6+/8, Developing 3-5/8, Gaps Found 0-2/8)
  - [ ] 1.1.4 Implement recommendation generation based on missing signals (brand-aligned copy)
  - [ ] 1.1.5 Add 5-second timeout safety net
  - [ ] 1.1.6 Write unit tests for each signal detection category
- [ ] 1.2 Create `supabase/migrations/016_project_health_snapshot.sql`
  - [ ] 1.2.1 `ALTER TABLE users ADD COLUMN health_snapshot jsonb`
  - [ ] 1.2.2 `ALTER TABLE conversations ADD COLUMN source text DEFAULT 'user'`
  - [ ] 1.2.3 `ALTER TABLE conversations ALTER COLUMN domain_leader DROP NOT NULL`
  - [ ] 1.2.4 Verify migration is idempotent (IF NOT EXISTS)
- [ ] 1.3 Modify `apps/web-platform/app/api/repo/setup/route.ts`
  - [ ] 1.3.1 Call `scanProjectHealth()` in `.then()` handler after provisioning
  - [ ] 1.3.2 Wrap scan in try/catch (failure sets null snapshot, does not block provisioning)
  - [ ] 1.3.3 Store `health_snapshot` in user record alongside `workspace_status: "ready"`
- [ ] 1.4 Modify `apps/web-platform/app/api/repo/status/route.ts`
  - [ ] 1.4.1 Add `health_snapshot` to SELECT and response payload

## Phase 2: Revamped Setting Up and Ready States

- [ ] 2.1 Modify `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - [ ] 2.1.1 Replace 3-second timer with batch-completion animation approach
  - [ ] 2.1.2 Steps 1-3 advance on 2s cadence during "cloning" status
  - [ ] 2.1.3 Steps 4-5 complete when status response includes `health_snapshot`
  - [ ] 2.1.4 Store `health_snapshot` from status response in component state
  - [ ] 2.1.5 Update step labels (brand-aligned): Cloning repository / Mapping project structure / Reading existing documentation / Learning your conventions / Briefing your team
- [ ] 2.2 Modify `apps/web-platform/components/connect-repo/setting-up-state.tsx`
  - [ ] 2.2.1 Accept step status driven by backend state (not timer)
- [ ] 2.3 Modify `apps/web-platform/components/connect-repo/ready-state.tsx`
  - [ ] 2.3.1 Accept `healthSnapshot: ProjectHealthSnapshot | null` prop
  - [ ] 2.3.2 Display health category badge, detected/missing signals, top 3 recommendations
  - [ ] 2.3.3 Show deep analysis status with Command Center link (when sync triggered)
  - [ ] 2.3.4 Graceful degradation to current design when snapshot is null
  - [ ] 2.3.5 CTAs: "Open Command Center" / "Review Knowledge Base"
  - [ ] 2.3.6 Write component tests with mock snapshot data

## Phase 3: Auto-Triggered Headless Agent Sync

- [ ] 3.1 Modify `apps/web-platform/app/api/repo/setup/route.ts` (sync trigger)
  - [ ] 3.1.1 Check BYOK API key availability before triggering sync
  - [ ] 3.1.2 Idempotency check: skip if active system sync conversation exists
  - [ ] 3.1.3 INSERT conversation with `source: 'system'`, `domain_leader: null`, `status: 'active'`
  - [ ] 3.1.4 Call `startAgentSession()` with `/soleur:sync --headless` prompt
  - [ ] 3.1.5 Set `maxBudgetUsd: 1.0` for system-initiated syncs
  - [ ] 3.1.6 Wrap in try/catch -- sync failure does not block provisioning
- [ ] 3.2 Modify `apps/web-platform/hooks/use-conversations.ts`
  - [ ] 3.2.1 Update `deriveTitle()` for `source === 'system'` -> "Project Analysis"
  - [ ] 3.2.2 Add visual indicator for system-initiated conversations

## Phase 4: KB Overview Page

- [ ] 4.1 Create `apps/web-platform/app/(dashboard)/dashboard/kb/overview/page.tsx`
  - [ ] 4.1.1 Client component (`"use client"`)
  - [ ] 4.1.2 Fetch health_snapshot via `/api/repo/status`
  - [ ] 4.1.3 Fetch KB tree via `/api/kb/tree` for coverage display
  - [ ] 4.1.4 Display full health report: signals, "Next Steps", "Knowledge Base Coverage"
  - [ ] 4.1.5 Category badge, last analyzed timestamp
  - [ ] 4.1.6 "Re-analyze" button (disabled, "Coming soon" tooltip) -- #1783
  - [ ] 4.1.7 Null snapshot fallback: "Connect a repo to see your project assessment"
- [ ] 4.2 Modify `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`
  - [ ] 4.2.1 Add "Overview" as first sidebar nav item
  - [ ] 4.2.2 Update `isContentView`: exclude `/dashboard/kb/overview` (renders full-width)
- [ ] 4.3 Modify `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx`
  - [ ] 4.3.1 Redirect to `/dashboard/kb/overview` when KB empty AND snapshot exists

## Pre-Ship Checklist

- [ ] 5.1 Verify CSRF structural test passes with new routes
- [ ] 5.2 E2E test: connect repo -> health snapshot -> sync conversation -> KB overview
- [ ] 5.3 Migration applies cleanly on fresh and existing databases
- [ ] 5.4 All Supabase calls use `{ data, error }` destructuring
- [ ] 5.5 Error messages to clients go through `error-sanitizer.ts`
- [ ] 5.6 Run `npm install` in worktree before builds
- [ ] 5.7 Reconcile with #1751 (Start Fresh onboarding) before merge

## Blocked / Requires Decision

- [ ] B1 Reconcile #1772 and #1751 post-connect UX overlap (CPO finding C3)
- [ ] B2 Re-milestone #1772 from "Post-MVP / Later" to Phase 3 + add roadmap row 3.16 (CPO finding C1)
- [ ] B3 Verify Phase 2 (Secure for Beta) completion status (CPO finding C2)
