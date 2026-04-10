---
title: "feat: post-connect sync proposal and project status report"
type: feat
date: 2026-04-07
---

# feat: Post-Connect Sync Proposal and Project Status Report

## Overview

After connecting a project in the web platform, automatically scan the repo during provisioning, trigger a headless KB sync, and display a project health status report with actionable recommendations. Replaces the fake "Setting Up" animation steps with real operations and the bare "Ready" screen with an informative health snapshot.

**Issue:** #1772
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-07-post-connect-sync-proposal-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-post-connect-sync-proposal/spec.md`
**Branch:** `feat-post-connect-sync-proposal`
**Draft PR:** #1771

## Problem Statement

The current post-connect experience has two value gaps:

1. **Fake progress:** The "Setting Up" animation (`connect-repo/page.tsx:40-46`) cycles through five steps ("Scanning project structure", "Detecting knowledge base", etc.) on a 3-second timer. None correspond to real backend operations -- the backend only runs `git clone` and scaffolds empty KB directories.

2. **Empty landing:** The Ready state (`ready-state.tsx`) shows repo name, "60+ agents ready", and an "Open Dashboard" button. The KB page shows "Nothing Here Yet." Users who just connected their most important project see zero intelligence about it.

This is the most critical onboarding moment. Users who see intelligence about their project immediately are more likely to continue using the platform. Users who see an empty screen have no signal that the product delivers value.

## Proposed Solution

A hybrid approach combining speed with depth:

| Layer | What | Where | When | Duration |
|-------|------|-------|------|----------|
| Fast scan | Server-side file-presence checks | `server/workspace.ts` | During provisioning | ~2-5s |
| Health snapshot | JSON stored on user record | `017_*.sql` migration | After fast scan | Instant |
| Ready state | Display health snapshot + recommendations | `ready-state.tsx` revamp | On provisioning complete | Immediate |
| Agent sync | Headless `/soleur:sync` | `agent-runner.ts` | After provisioning complete | 1-5 min async |
| ~~KB overview~~ | ~~Persistent health report page~~ | ~~`/dashboard/kb/overview`~~ | ~~Always available~~ | Deferred [Updated 2026-04-10] |
| Notification | Conversation status update | Supabase Realtime | On sync complete | Realtime |

## Technical Approach

### Architecture

```text
connect-repo/page.tsx          server/workspace.ts           agent-runner.ts
       |                              |                            |
  [Setting Up]                  provisionWithRepo()                |
  "Cloning repository" ───────> git clone                          |
  "Scanning project" ─────────> scanProjectHealth() [NEW]          |
  "Preparing your team" ──────> UPDATE users SET health_snapshot   |
       |                        INSERT conversations [NEW] ───────> startAgentSession()
       |                              |                         /soleur:sync --headless
  [Ready State]                  return workspace_path              |
  display health_snapshot             |                   .catch() logs to Sentry
  link to Command Center              |                        [runs async]
                                      |                   UPDATE conversations
                                      |                   SET status='completed'
                                      |                        [Realtime push]
```

### Implementation Phases

#### Phase 1: Fast File Scanner and Database Migration

Build the server-side scanner and store results.

**New file: `apps/web-platform/server/project-scanner.ts`**

- Export `scanProjectHealth(workspacePath: string): ProjectHealthSnapshot`
- Synchronous file-presence checks using `fs.existsSync` and `fs.readdirSync`
- Detect: package managers, test files, CI config, linting, Docker, README, CLAUDE.md, KB state
- Categorize project as: "Strong", "Developing", or "Gaps Found"
- Categorization algorithm: count detected signals across all categories. Strong = 6+ of 8 core signals detected. Developing = 3-5 detected. Gaps Found = 0-2 detected. Core signals: package manager, tests, CI, linting, README, CLAUDE.md, docs directory, KB
- Generate top 3 recommendations based on missing signals
- Return typed `ProjectHealthSnapshot` JSON (target: under 2KB)
- Must complete in under 5 seconds for repos up to 100k files

**Type: `ProjectHealthSnapshot` (inline in `project-scanner.ts`, extract when a second consumer needs it)**

```typescript
export interface ProjectHealthSnapshot {
  scannedAt: string
  category: "strong" | "developing" | "gaps-found"
  signals: {
    detected: { id: string; label: string }[]
    missing: { id: string; label: string }[]
  }
  recommendations: string[]  // Top 3, pre-sorted by priority. Brand-aligned copy.
  kbExists: boolean
}
```

Simplified from initial design per review feedback: dropped `meta` field (nothing consumes it), dropped signal `category` (UI shows flat lists), dropped `Recommendation` interface (always exactly 3 strings in priority order). [Updated 2026-04-10] Dropped `version: 1` (speculative forward-compatibility, one consumer). Flattened `kbState.sections` to `kbExists: boolean` (KB viewer already shows section detail, snapshot copy goes stale after sync).

**Migration: `supabase/migrations/017_project_health_snapshot.sql`**

```sql
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS health_snapshot jsonb DEFAULT NULL;

-- RLS fix: 001_initial_schema.sql has "Users can update own profile" allowing UPDATE
-- on ALL columns. Restrict health_snapshot to server-only writes.
-- Column-level REVOKE is silently ignored when table-level GRANT exists (learning #13).
-- Instead, add a restrictive RLS policy that prevents client UPDATE of health_snapshot.
CREATE POLICY "Prevent client health_snapshot update" ON public.users
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (
    -- Block if the client is trying to change health_snapshot.
    -- Service role bypasses RLS, so server writes are unaffected.
    (health_snapshot IS NOT DISTINCT FROM (SELECT health_snapshot FROM public.users WHERE id = auth.uid()))
  );

-- System-initiated conversations use domain_leader = 'system' as a sentinel.
-- No new columns needed -- reuses existing schema. [Updated 2026-04-10]
-- health_snapshot: Server-only column, protected by restrictive RLS policy.
```

**Modify: `apps/web-platform/app/api/repo/setup/route.ts`** (single insertion point -- NOT workspace.ts)

- In the existing `.then()` handler (line 101-119), after `provisionWorkspaceWithRepo` resolves, call `scanProjectHealth(workspacePath)`
- The scanner runs in the route handler, not inside `provisionWorkspaceWithRepo`, because: (a) the route already has the Supabase service client for the DB write, (b) keeps `workspace.ts` focused on provisioning, (c) avoids double-scan risk
- **Scan failure must not block provisioning:** Wrap `scanProjectHealth()` in try/catch. If scan throws or times out (5s), set `health_snapshot: null` and continue with `repo_status: "ready"`. Log the scan error via Sentry. The user still gets a connected repo -- just without the health snapshot.
- Store `health_snapshot` JSON in user record alongside `workspace_status: "ready"`

**No changes to `apps/web-platform/server/workspace.ts`** -- provisioning function remains focused on clone + scaffold.

**Modify: `apps/web-platform/app/api/repo/status/route.ts`**

- Add `health_snapshot` to the response payload (already queried from users table)
- Frontend polls this endpoint every 2s, so the snapshot becomes available automatically

#### Phase 2: Revamped Setting Up and Ready States

Replace fake animation with real progress and show health snapshot on completion.

**Modify: `apps/web-platform/app/(auth)/connect-repo/page.tsx`**

- **Simplified animation approach [Updated 2026-04-10]:** Show current operation label during provisioning. When `repo_status === "ready"` AND `health_snapshot` is present in status response, transition to Ready state. No multi-step choreography — a single animated label reflecting the current backend operation is sufficient. The existing gold gradient progress bar can show indeterminate progress.
- Store `health_snapshot` from status response in component state
- **Operation labels** (per brand voice review): "Cloning repository" → "Scanning project" → "Preparing your team" → complete

**Modify: `apps/web-platform/components/connect-repo/setting-up-state.tsx`**

- Accept current operation label from parent (driven by backend state, not timer)
- Show single animated label with indeterminate progress bar
- Keep existing visual design (gold gradient progress bar)

**Modify: `apps/web-platform/components/connect-repo/ready-state.tsx`**

- Accept `healthSnapshot: ProjectHealthSnapshot | null` prop
- **When healthSnapshot is present:** Display project name, repo link, health category badge ("Strong" / "Developing" / "Gaps Found"), detected signals (green checkmarks), missing signals (amber suggestions), top 3 recommendations from snapshot, deep analysis status: "Deep analysis in progress" with link to Command Center
- **When healthSnapshot is null (scan failed or timed out):** Graceful degradation to current Ready state (repo name + agent count + "Open Command Center" button). No crash.
- CTAs: "Open Command Center" / "Review Knowledge Base"
- Recommendation copy uses brand-aligned framing (organization as executor, not founder): e.g., "No test coverage detected. The team can scaffold [test framework] tests to catch regressions before they ship."

**Modify: `apps/web-platform/components/connect-repo/types.ts`**

- Add `healthSnapshot` to relevant types

#### Phase 3: Auto-Triggered Headless Agent Sync

Create a conversation and start a headless sync session after provisioning.

**Modify: `apps/web-platform/app/api/repo/setup/route.ts`**

- After storing health snapshot, INSERT a new conversation row: [Updated 2026-04-10]
  - `user_id`: current user
  - `domain_leader`: `"system"` (sentinel value — no new column needed, reuses existing schema)
  - `status`: "active"
  - `session_id`: generated UUID
  - Call `startAgentSession()` with prompt: `/soleur:sync --headless`
  - **Fire-and-forget with `.catch()`:** The returned promise MUST have `.catch()` attached — `try/catch` only catches synchronous errors, and an unhandled rejection crashes the Node server (learning #9). [Updated 2026-04-10]
  - This runs asynchronously -- the provisioning response returns immediately
  - The conversation appears in Command Center with "active" status
- **BYOK key check:** `startAgentSession()` already calls `getUserApiKey(userId)` internally and rejects if no key exists. The `.catch()` handler absorbs this gracefully — no separate pre-check needed. [Updated 2026-04-10]
- **Idempotency:** Not needed — sync triggers once during provisioning, which is itself idempotent (runs once per user, guarded by `repo_status`). [Updated 2026-04-10]
- **Error handling:** `.catch()` on the `startAgentSession()` promise logs to Sentry and continues. Provisioning still succeeds — the user gets a connected repo with health snapshot but no async sync. The sync can be triggered manually later.

**Modify: `apps/web-platform/hooks/use-conversations.ts`** [Updated 2026-04-10]

- `deriveTitle()` takes `(messages, conversationId)` — it has no access to the conversation object. Title derivation for system conversations must happen in the `enriched` mapping (line ~115) where the full conversation row is available, not in `deriveTitle()`.
- When `conversation.domain_leader === 'system'`, set title to "Project Analysis" in the enrichment step.
- System-initiated conversations render with a distinct visual indicator (e.g., system badge or robot icon)

**Modify: `apps/web-platform/lib/types.ts`** [Updated 2026-04-10]

- No `Conversation` interface change needed — `domain_leader` already exists as `string`. The `"system"` sentinel is a convention, not a type change.

**Considerations for agent-runner.ts:**

- `startAgentSession()` already handles workspace setup, git sync, and Claude SDK invocation
- The system prompt needs to include the headless flag so `/soleur:sync` auto-accepts findings
- Session completes by updating conversation status to "completed" (existing pattern)
- On failure, conversation status becomes "failed" with error in last message
- **Token budget:** Set `maxBudgetUsd: 1.0` for system-initiated syncs (lower than interactive sessions' $5 default). Monitor via Sentry.

**No changes to `/soleur:sync` command itself:**

- The sync command already supports `--headless` via `$ARGUMENTS` (learning #14)
- Headless mode auto-accepts high-confidence findings and skips low-confidence ones
- Safety constraints still run in headless mode

#### ~~Phase 4: KB Overview Page~~ — Deferred [Updated 2026-04-10]

Cut per plan review consensus: Phase 2 Ready state already displays the health snapshot. Building a second persistent surface for the same data before measuring whether users engage with the Ready state data is premature. Deferred to a separate issue — ship Phases 1-3, measure engagement, then decide.

**Deferral issue:** #1808

**No changes to KB layout or KB page in this feature.**

**Command Center notification (no dedicated phase -- zero additional work):**

- `hooks/use-conversations.ts` already subscribes to `postgres_changes` on `conversations` table
- When the sync conversation status changes from "active" to "completed", the Command Center updates automatically via existing Realtime subscription
- No new subscriptions, no new components needed

## Alternative Approaches Considered

| Approach | Considered | Rejected Because |
|----------|-----------|-----------------|
| Client-side scanning via API | Parse file tree from GitHub API | Slow (API rate limits), requires token management, doesn't work for non-GitHub repos |
| Separate scanning microservice | Dedicated scanner with queue | Overengineered for file-presence checks. Scanner is <100 lines of synchronous code |
| Numeric health score (0-100) | Quantify project health | Per spec non-goal: categorized labels only. Numeric scores invite gaming and false precision |
| Periodic auto-refresh via webhook | Re-scan on git push | Deferred per spec non-goal. Can be added later via GitHub webhook |
| Separate `health_snapshots` table | Normalize snapshot storage | Overkill for a single JSON blob per user. Column on users table is simpler |
| WebSocket for scan progress | Real-time scan step updates | HTTP polling already runs every 2s. Adding WebSocket for a 2-5s operation adds complexity for no UX benefit |

## Acceptance Criteria

### Functional Requirements

- [ ] Fast scan runs during provisioning after repo clone, producing a `ProjectHealthSnapshot`
- [ ] Scanner detects: package managers, test files, CI config, linting, Docker, README, CLAUDE.md, KB state
- [ ] Health snapshot stored as JSON column on users table via Supabase migration
- [ ] "Setting Up" shows current operation label during provisioning, transitions to Ready state when status returns "ready" with health snapshot [Updated 2026-04-10]
- [ ] Given no BYOK API key configured, when provisioning completes, then sync conversation `.catch()` absorbs the error and Ready state omits deep analysis status [Updated 2026-04-10]
- [ ] Ready state displays health snapshot: detected signals, missing signals, top 3 recommendations
- [ ] Agent sync conversation auto-created after provisioning completes
- [ ] Agent sync runs headless (`/soleur:sync --headless`) in the background
- [ ] Agent sync conversation appears in Command Center with "active" status
- [ ] When agent sync completes, conversation status updates to "completed" via Supabase Realtime
- ~~[ ] `/dashboard/kb/overview` page shows full health report~~ — Deferred (Phase 4 cut) [Updated 2026-04-10]
- ~~[ ] KB overview shows KB completeness~~ — Deferred (Phase 4 cut) [Updated 2026-04-10]
- ~~[ ] KB page redirects to overview when KB is empty~~ — Deferred (Phase 4 cut) [Updated 2026-04-10]

### Non-Functional Requirements

- [ ] Fast scan completes in under 5 seconds for repos up to 100k files
- [ ] Health snapshot JSON payload under 2KB
- [ ] No new external dependencies for the fast scanner (uses Node.js `fs` only)
- [ ] `health_snapshot` column is server-only-writable (restrictive RLS policy prevents client UPDATE — see migration) [Updated 2026-04-10]
- [ ] New POST routes include CSRF protection (`validateOrigin` + `rejectCsrf`)
- [ ] All Supabase calls destructure `{ data, error }` and handle errors explicitly
- ~~[ ] KB overview page uses same responsive layout~~ — Deferred (Phase 4 cut) [Updated 2026-04-10]
- [ ] Migration is idempotent (`IF NOT EXISTS`)

### Quality Gates

- [ ] Unit tests for `project-scanner.ts` (signal detection for each category)
- [ ] Integration test for provisioning flow with scanner
- [ ] Component tests for revamped Ready state with health snapshot data
- [ ] E2E test: connect repo -> verify health snapshot displayed -> verify sync conversation created
- [ ] CSRF structural test passes with new routes
- [ ] Migration applies cleanly on fresh and existing databases

## Domain Review

**Domains relevant:** Product, Marketing, Support

### Marketing

**Status:** reviewed
**Assessment:** Highest-leverage marketing moment -- turns "AI that already knows your business" from abstract promise into concrete first-session experience. Status report output is inherently shareable for build-in-public content. Copy quality is critical. Risk: sync output quality varies by project size. Recommendation: engage copywriter for all onboarding copy.

### Support

**Status:** reviewed
**Assessment:** Eliminates the "blank slate" problem -- largest source of "I installed it, now what?" confusion. Needs support runbooks before shipping: sync failure triage guide, onboarding friction playbook, and sync FAQ. `/soleur:sync` vs `/soleur:bootstrap` scope boundary must be clarified.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead, copywriter
**Skipped specialists:** none
**Pencil available:** yes

#### Spec-Flow Findings (Critical Gaps Addressed)

1. **G1 — No intermediate repo_status states:** Resolved with batch-completion animation approach. Steps advance on cadence during "cloning", complete when "ready" + health_snapshot arrives. No intermediate DB writes needed.
2. **G6 — BYOK key dependency:** Resolved by gating sync on key availability. If no key, skip sync silently. Ready state shows fast-scan snapshot without "Deep analysis in progress."
3. **G4/G5 — System conversation identity:** Resolved with `domain_leader = 'system'` sentinel (no new column). System conversations render as "Project Analysis" with distinct badge. Title set in enrichment mapping, not `deriveTitle()`. [Updated 2026-04-10]
4. **G8 — Duplicate sync conversations:** Resolved with idempotency check before creating sync conversation.
5. **G11 — Schema version:** Added `version: 1` to ProjectHealthSnapshot type.
6. **G13 — KB overview rendering:** Resolved as client component (inside "use client" layout).
7. ~~**G15 — isContentView for overview:**~~ N/A — Phase 4 deferred. [Updated 2026-04-10]
8. **G16 — Categorization algorithm:** Defined: Strong (6+/8 signals), Developing (3-5/8), Gaps Found (0-2/8).
9. **G18 — Null snapshot fallback:** Ready state degrades gracefully to current design when snapshot is null.
10. **G20/G21 — Scan failure:** Scan failure does not block provisioning. Sets null snapshot, logs to Sentry.
11. ~~**G14 — Re-analyze button:**~~ N/A — Phase 4 deferred. [Updated 2026-04-10]

#### CPO Findings

1. **C1 — Milestone mismatch:** ~~#1772 milestoned to "Post-MVP / Later" but brainstorm says P3.~~ **Resolved [Updated 2026-04-10]:** Re-milestoned to Phase 3, roadmap row 3.16 added.
2. **C2 — Phase 2 sequencing:** ~~P2 (Secure for Beta) not completed.~~ **Resolved [Updated 2026-04-10]:** P2 complete — all 20 issues closed, milestone closed. No longer a gate.
3. **C3 — Overlap with #1751 (Start Fresh onboarding):** ~~Both features modify the post-connect experience.~~ **Resolved [Updated 2026-04-10]:** #1751 closed. Foundation card UI removed from dashboard. No post-connect UX overlap remains.
4. **C6 — Token budget:** Set `maxBudgetUsd: 1.0` for system-initiated syncs. Added to Phase 3.

#### Copywriter Findings

1. **Health categories revised:** "Strong" / "Developing" / "Gaps Found" (declarative, not passive)
2. **Recommendation copy reframed:** Organization as executor ("The team can scaffold..."), not founder as executor ("Add tests..."). Removed "AI assistants" (brand violation), "consider" (hedging), and "your team" (implies human team).
3. **Setting Up labels revised:** "Cloning repository" / "Mapping project structure" / "Reading existing documentation" / "Learning your conventions" / "Briefing your team"
4. **CTAs revised:** "Open Command Center" / "Review Knowledge Base"
5. **Status messages revised:** "Deep analysis in progress" (no ellipsis) / "Analysis complete"
6. **Section labels revised:** "Next Steps" (not "Recommendations"), "Knowledge Base Coverage" (not "KB Completeness")

#### UX Wireframes

Design file: `knowledge-base/product/design/post-connect-sync/post-connect-sync-wireframes.pen`

Exported screenshots:

- `screenshots/01-ready-state-health-snapshot.png` — Health snapshot card with category badge, two-column signal inventory, three numbered recommendations, deep analysis status, and dual CTA buttons
- `screenshots/02-kb-overview-page.png` — Two-panel layout with sidebar nav, expandable signal inventory by category, priority-badged recommendations, KB coverage section
- `screenshots/03-setting-up-animation.png` — Five-step progress with gold gradient bar, real operation labels, contextual subtitles

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a repo with `package.json`, `tsconfig.json`, `.github/workflows/`, `README.md`, and `knowledge-base/`, when fast scan runs, then snapshot category is "strong" and all five signals are detected
- Given a repo with only `package.json` and no tests/CI/docs, when fast scan runs, then snapshot category is "gaps-found" and recommendations include "Add tests" and "Set up CI/CD"
- Given a repo with `knowledge-base/`, when fast scan runs, then `kbExists` is true [Updated 2026-04-10]
- Given provisioning completes, when status polling returns "ready", then response includes `health_snapshot` with valid `ProjectHealthSnapshot` shape
- Given a health snapshot with 3 detected and 4 missing signals, when Ready state renders, then 3 green checkmarks and 4 amber suggestions are visible
- Given provisioning completes, when the user navigates to Command Center, then a sync conversation with status "active" is listed
- Given a sync conversation completes, when Realtime pushes the update, then conversation status badge changes to "completed" without page refresh
- ~~Given an empty KB, redirect to `/dashboard/kb/overview`~~ — Phase 4 deferred [Updated 2026-04-10]

### Edge Cases

- Given a repo with zero recognizable files (e.g., binary-only), when fast scan runs, then category is "gaps-found" with generic "Add documentation" recommendation
- Given provisioning fails at clone step, when setup route catches the error, then no health snapshot or sync conversation is created, and `repo_status` is "error"
- Given agent sync fails mid-run, when conversation status updates to "failed", then Command Center shows failure status and Ready state still shows fast-scan snapshot [Updated 2026-04-10]
- Given a repo already has a populated KB, when fast scan detects `knowledge-base/`, then `kbExists` is true and recommendations reference existing content [Updated 2026-04-10]
- Given health snapshot is null (scan failed), when Ready state renders, then it degrades gracefully to current design (no crash) [Updated 2026-04-10]

### Integration Verification

- **Browser:** Navigate to `/connect-repo`, select a test repo, complete setup flow, verify Ready state shows health signals and recommendations
- **Browser:** After setup, navigate to `/dashboard`, verify sync conversation appears in Command Center
- ~~**Browser:** Navigate to `/dashboard/kb/overview`~~ — Phase 4 deferred [Updated 2026-04-10]
- **API verify:** `curl -s localhost:3000/api/repo/status -H "Cookie: $SESSION" | jq '.healthSnapshot.category'` expects `"developing"` or `"strong"` or `"gaps-found"`

## Dependencies and Prerequisites

| Dependency | Status | Notes |
|-----------|--------|-------|
| Command Center (#1759) | Merged | Conversation inbox infrastructure is live |
| Connect-repo flow | Stable | Provisioning pipeline in `workspace.ts` and `setup/route.ts` |
| `/soleur:sync` headless mode | Available | `--headless` flag convention documented in learning #14 |
| Supabase Realtime on conversations | Live | `use-conversations.ts` subscribes to `postgres_changes` |
| Agent session infrastructure | Stable | `agent-runner.ts` `startAgentSession()` handles workspace + Claude SDK |

**No blockers identified.** All dependencies are merged and stable.

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Fast scan exceeds 5s on large repos | Low | Medium | Use `fs.existsSync` (not `glob`), check only top-level patterns, set a 5s timeout |
| Headless sync produces low-quality KB entries | Medium | Medium | Auto-accept only high-confidence findings. User reviews in KB viewer afterward |
| Agent sync consumes excessive tokens | Medium | High | Set a token budget per sync session. Monitor via Sentry/logs |
| Migration conflicts with concurrent PRs | Low | Low | Use `IF NOT EXISTS`. Column addition is non-breaking |
| Health snapshot schema evolves | Medium | Low | JSON column is schema-flexible. Add `version` field later if migration needed. [Updated 2026-04-10] |
| BYOK key not configured | Medium | Low | `startAgentSession()` rejects internally, `.catch()` absorbs. Ready state shows fast-scan snapshot only. [Updated 2026-04-10] |
| ~~Overlap with #1751 (Start Fresh onboarding)~~ | ~~Medium~~ | ~~High~~ | **Resolved [Updated 2026-04-10]:** #1751 closed, foundation card UI removed. No overlap. |
| Supabase Realtime misses conversation update | Low | Medium | Existing client-side re-validation pattern handles this. Polling fallback on dashboard load |

## Institutional Learnings to Apply

These learnings from `knowledge-base/project/learnings/` directly apply to this implementation:

1. **Supabase silent errors** (`2026-03-20`): Always destructure `{ data, error }` from every Supabase call
2. **CSRF coverage** (`2026-03-20`): New POST routes need `validateOrigin` + `rejectCsrf`. Structural test enforces this
3. **Headless mode convention** (`2026-03-03`): Use `--headless` flag in `$ARGUMENTS`, strip before processing
4. **Promise leak prevention** (`2026-03-20`): Long-lived promises (sync session) need AbortSignal cancellation with `timer.unref()`
5. **RLS whitelist model** (`2026-03-20`): `health_snapshot` column needs restrictive RLS policy — `001_initial_schema.sql` has "Users can update own profile" allowing UPDATE on ALL columns. Column-level REVOKE is a no-op with table-level GRANT (learning #13). [Updated 2026-04-10]
6. **Middleware path matching** (`2026-03-20`): New dashboard routes use `pathname === p || pathname.startsWith(p + "/")`
7. **Error sanitization** (`2026-03-20`): All error messages to clients go through `error-sanitizer.ts`
8. **Trigger/fallback parity** (`2026-03-20`): If using DB triggers for status transitions, application fallback must mirror trigger logic
9. **Fire-and-forget `.catch()` required** (`2026-03-20`): `startAgentSession()` called without `.catch()` crashes entire Node server on rejection. Critical for the auto-triggered sync in Phase 3. [Updated 2026-04-10]
10. **WS session race abort** (`2026-03-27`): Concurrent `start_session` creates race; must abort previous session before replacing conversationId. Applies to idempotency check in Phase 3. [Updated 2026-04-10]
11. ~~**KB viewer React context layout** (`2026-04-07`):~~ N/A — Phase 4 deferred. [Updated 2026-04-10]
12. **Supabase module-scope crash** (`2026-04-05`): `createClient()` at module scope crashes when env vars absent. Use lazy getter returning `SupabaseClient | null`. Applies to `project-scanner.ts` if it uses Supabase. [Updated 2026-04-10]
13. **Disconnect null constraint violation** (`2026-04-06`): Disconnect handler set columns to null violating NOT NULL/CHECK constraints. Schema and code must agree on nullable columns. Applies to `domain_leader DROP NOT NULL` in migration. [Updated 2026-04-10]
14. **Connect-repo state rename** (`2026-04-08`): `github_resolve` state renamed to `link_github`, `GitHubResolveState` → `LinkGitHubState`. Plan Phase 2 modifications to `connect-repo/page.tsx` must use updated state names. [Updated 2026-04-10]

## Future Considerations

- **Periodic auto-refresh:** Re-scan on git push via GitHub webhook (deferred per spec non-goal, tracked separately)
- **Re-analyze button:** KB overview page includes a "Re-analyze" button that triggers a fresh scan + sync
- **Health trends:** Track snapshot history to show project health trajectory over time
- **Custom scan configs:** Per-project signal configuration (deferred per spec non-goal)
- **Multi-project support:** When users can connect multiple repos, scanner runs per-project

## References and Research

### Internal References

- Provisioning pipeline: `apps/web-platform/server/workspace.ts:117-236`
- Setup API route: `apps/web-platform/app/api/repo/setup/route.ts:1-142`
- Status polling: `apps/web-platform/app/api/repo/status/route.ts:1-61`
- Fake setup steps: `apps/web-platform/app/(auth)/connect-repo/page.tsx:343` (setTimeout transition) [Updated 2026-04-10]
- Ready state component: `apps/web-platform/components/connect-repo/ready-state.tsx`
- Setting up component: `apps/web-platform/components/connect-repo/setting-up-state.tsx`
- Command Center: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
- Realtime subscription: `apps/web-platform/hooks/use-conversations.ts:141`
- Agent sessions: `apps/web-platform/server/agent-runner.ts`
- ~~KB tree API: `apps/web-platform/app/api/kb/tree/route.ts`~~ — Phase 4 deferred [Updated 2026-04-10]
- ~~KB layout: `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`~~ — Phase 4 deferred [Updated 2026-04-10]
- Sync command: `plugins/soleur/commands/sync.md`

### Related Work

- Command Center: #1759 (merged)
- Start Fresh onboarding: #1751 (closed — no overlap) [Updated 2026-04-10]
- Issue: #1772
- Draft PR: #1771
