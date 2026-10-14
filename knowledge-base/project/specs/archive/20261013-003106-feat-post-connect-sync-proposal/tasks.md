# Post-Connect Sync Proposal -- Tasks

**Plan:** `knowledge-base/project/plans/2026-04-07-feat-post-connect-sync-proposal-plan.md`
**Issue:** #1772
**Branch:** feat-post-connect-sync-proposal
**Updated:** 2026-04-10 (plan review applied: Phase 4 deferred, TDD reorder, schema simplification)

## Phase 1: Fast File Scanner and Database Migration

- [x] 1.0 Write unit tests for `project-scanner.ts` FIRST (TDD gate) [Updated 2026-04-10]
  - [x] 1.0.1 Test: repo with all 8 signals → category "strong"
  - [x] 1.0.2 Test: repo with 4 signals → category "developing"
  - [x] 1.0.3 Test: repo with 1 signal → category "gaps-found"
  - [x] 1.0.4 Test: empty repo → "gaps-found" with generic recommendation
  - [x] 1.0.5 Test: `kbExists` true when `knowledge-base/` present
  - [x] 1.0.6 Test: recommendations array has exactly 3 entries, sorted by priority
- [x] 1.1 Create `apps/web-platform/server/project-scanner.ts`
  - [x] 1.1.1 Implement `scanProjectHealth(workspacePath)` with `fs.existsSync` checks
  - [x] 1.1.2 Define `ProjectHealthSnapshot` type inline (signals, recommendations, kbExists) [Updated 2026-04-10: dropped `version`, flattened `kbState` to `kbExists: boolean`]
  - [x] 1.1.3 Implement categorization algorithm (Strong 6+/8, Developing 3-5/8, Gaps Found 0-2/8)
  - [x] 1.1.4 Implement recommendation generation based on missing signals (brand-aligned copy)
  - [x] 1.1.5 Add 5-second timeout safety net
- [x] 1.2 Create `supabase/migrations/017_project_health_snapshot.sql`
  - [x] 1.2.1 `ALTER TABLE users ADD COLUMN IF NOT EXISTS health_snapshot jsonb`
  - [x] 1.2.2 Add restrictive RLS policy preventing client UPDATE of `health_snapshot` [Updated 2026-04-10: RLS security fix — existing "Users can update own profile" allows UPDATE on ALL columns]
  - [x] 1.2.3 Verify migration is idempotent (IF NOT EXISTS)
  - Note: migration number updated to 017 after merging main (016 taken by github_username) [Updated 2026-04-10]
- [x] 1.3 Modify `apps/web-platform/app/api/repo/setup/route.ts`
  - [x] 1.3.1 Call `scanProjectHealth()` in `.then()` handler after provisioning
  - [x] 1.3.2 Wrap scan in try/catch (failure sets null snapshot, does not block provisioning)
  - [x] 1.3.3 Store `health_snapshot` in user record alongside `workspace_status: "ready"`
- [x] 1.4 Modify `apps/web-platform/app/api/repo/status/route.ts`
  - [x] 1.4.1 Add `health_snapshot` to SELECT and response payload
- [x] 1.5 Integration test for provisioning flow with scanner [Updated 2026-04-10: was missing from tasks despite being in ACs]

## Phase 2: Revamped Setting Up and Ready States

- [x] 2.0 Write component tests for ready-state FIRST (TDD gate) [Updated 2026-04-10]
  - [x] 2.0.1 Test: renders health snapshot with category badge, signals, recommendations
  - [x] 2.0.2 Test: graceful degradation when snapshot is null
  - [x] 2.0.3 Test: shows deep analysis status when sync conversation exists
- [x] 2.1 Modify `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - [x] 2.1.1 Replace 3-second timer with operation label approach [Updated 2026-04-10: simplified from 5-step choreography to single animated label]
  - [x] 2.1.2 Show current operation label ("Cloning repository" → "Scanning project" → "Preparing your team") during provisioning
  - [x] 2.1.3 Transition to Ready state when status response includes `health_snapshot`
  - [x] 2.1.4 Store `health_snapshot` from status response in component state
  - Note: state machine uses `link_github` (not `github_resolve`) — renamed on this branch [Updated 2026-04-10]
- [x] 2.2 Modify `apps/web-platform/components/connect-repo/setting-up-state.tsx`
  - [x] 2.2.1 Accept current operation label from parent (driven by backend state, not timer)
  - [x] 2.2.2 Show single animated label with indeterminate progress bar
- [x] 2.3 Modify `apps/web-platform/components/connect-repo/ready-state.tsx`
  - [x] 2.3.1 Accept `healthSnapshot: ProjectHealthSnapshot | null` prop
  - [x] 2.3.2 Display health category badge, detected/missing signals, top 3 recommendations
  - [x] 2.3.3 Show deep analysis status with Command Center link (when sync triggered)
  - [x] 2.3.4 Graceful degradation to current design when snapshot is null
  - [x] 2.3.5 CTAs: "Open Command Center" / "Review Knowledge Base"

## Phase 3: Auto-Triggered Headless Agent Sync

- [x] 3.1 Modify `apps/web-platform/app/api/repo/setup/route.ts` (sync trigger)
  - [x] 3.1.1 INSERT conversation with `domain_leader: 'system'`, `status: 'active'` [Updated 2026-04-10: use sentinel value instead of new `source` column]
  - [x] 3.1.2 Call `startAgentSession()` with `/soleur:sync --headless` prompt
  - [x] 3.1.3 Attach `.catch()` to returned promise — NOT try/catch (fire-and-forget async, unhandled rejection crashes Node) [Updated 2026-04-10]
  - [x] 3.1.4 Set `maxBudgetUsd: 1.0` for system-initiated syncs
  - Note: BYOK check is redundant — `startAgentSession()` calls `getUserApiKey()` internally and rejects if no key. The `.catch()` absorbs this. [Updated 2026-04-10]
  - Note: idempotency check removed — provisioning triggers once per user, guarded by `repo_status`. [Updated 2026-04-10]
- [x] 3.2 Modify `apps/web-platform/hooks/use-conversations.ts`
  - [x] 3.2.1 In `enriched` mapping (~line 115), set title to "Project Analysis" when `conversation.domain_leader === 'system'` [Updated 2026-04-10: `deriveTitle()` takes (messages, conversationId) — no access to conversation object. Title must be set in enrichment, not deriveTitle]
  - [x] 3.2.2 Add visual indicator for system-initiated conversations (system badge)

## ~~Phase 4: KB Overview Page~~ — Deferred [Updated 2026-04-10]

Phase 4 cut per plan review consensus. Ready state already displays health snapshot. Ship Phases 1-3, measure engagement, build persistent overview if warranted.

Deferral issue: #1808

## Pre-Ship Checklist

- [x] 5.1 Verify CSRF structural test passes with new routes
- [x] 5.2 E2E test: connect repo -> health snapshot -> sync conversation in Command Center
- [x] 5.3 Migration applies cleanly on fresh and existing databases
- [x] 5.4 All Supabase calls use `{ data, error }` destructuring
- [x] 5.5 Error messages to clients go through `error-sanitizer.ts`
- [x] 5.6 Run `npm install` in worktree before builds
- [x] 5.7 ~~Reconcile with #1751 (Start Fresh onboarding) before merge~~ — Not needed: #1751 closed [2026-04-10]

## Blocked / Requires Decision

- [x] B1 ~~Reconcile #1772 and #1751 post-connect UX overlap (CPO finding C3)~~ — Resolved: #1751 closed, foundation card UI removed [2026-04-10]
- [x] B2 ~~Re-milestone #1772 from "Post-MVP / Later" to Phase 3 + add roadmap row 3.16 (CPO finding C1)~~ — Resolved: milestoned to Phase 3, roadmap row 3.16 exists [2026-04-10]
- [x] B3 ~~Verify Phase 2 (Secure for Beta) completion status (CPO finding C2)~~ — Resolved: P2 complete, all 20 issues closed [2026-04-10]
