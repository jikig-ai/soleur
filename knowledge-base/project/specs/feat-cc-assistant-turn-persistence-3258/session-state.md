---
session: 2026-05-11
last_phase_completed: Phase 0 (work skill prereqs + plan Phase 0 findings)
next_phase: Phase 1.1 W2 RED+GREEN
---

# Session state — PR-A implementation

## What's done

- Brainstorm 2026-05-11 — `knowledge-base/project/brainstorms/2026-05-11-cc-soleur-go-transcript-hardening-brainstorm.md`
- Spec rev-2 — `knowledge-base/project/specs/feat-cc-assistant-turn-persistence-3258/spec.md`
- Plan rev-2 (post DHH + Kieran + Simplicity + GDPR audit synthesis) — `knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md`
- Issue #3258 closed as superseded by #3286; #3603 opened as hardening umbrella
- PR #3602 (draft) updated, branch pushed
- AC11 PASSED 2026-05-11 — DB-verified via Playwright + Supabase service-role on conversation `36df3694-9f0c-4e1e-905f-c0846b52749e`
- Plan Phase 0 prereqs resolved (below)

## Phase 0 findings

### 0.4 — User-Stop status string (corrected 2026-05-12)

**Initial finding was wrong** — re-reading `WorkflowEnd` at `soleur-go-runner.ts:617-638` reveals **7 statuses**:
- `completed` (with optional `summary`)
- `cost_ceiling` (with totalCostUsd, cap, workflow)
- `runner_runaway` (with elapsedMs, lastBlockKind, lastBlockToolName, reason)
- **`user_aborted`** ← this IS user-Stop; in W2 scope
- `idle_timeout`
- `plugin_load_failure` (with error)
- `internal_error` (with error)

The `cc-dispatcher.ts:738-739` comment refers to a DIFFERENT path: `runner.reapIdle()` and `runner.closeConversation()` close the Query without firing `onWorkflowEnded` — these are reaper/cleanup paths, not user-Stop. User-Stop fires `onWorkflowEnded({status: "user_aborted"})` and IS caught by W2.

**W2 scope (corrected):** flush on ALL non-`completed` statuses: `cost_ceiling | runner_runaway | user_aborted | idle_timeout | plugin_load_failure | internal_error`.

**Residual gap:** reaper/closeConversation paths that close Query without onWorkflowEnded leave the accumulator in-process. Documented as accepted residual alongside SIGKILL.

### 0.5 — DSAR export query

**No Art. 15 export endpoint exists in code.** Searched server + app for `art 15 | dsar | data-export | export.*personal | portability | gdpr`. Only finding is `apps/web-platform/server/account-delete.ts` (Art. 17 cascade delete — fully wired, includes `messages` via FK cascade).

Implication for PR-A: Art. 17 is safe (cascade FK unchanged, `usage` column from migration 040 deletes with parent conversation). Art. 15 gap is **pre-existing and orthogonal** — PR-A makes it BETTER by ensuring cc assistant turns are durable rather than ephemeral. File as **D-DSAR-art15** with broader scope than originally framed: "Implement DSAR Art. 15 export endpoint" — pre-PR-A planning assumed it existed, it doesn't.

Privacy Policy §8.1 promise ("users may request export") apparently fulfilled by manual operator action today; PR-C policy refresh should clarify.

### 0.6 — SDK ordering contract

`soleur-go-runner.ts:1682-1735` (`handleResultMessage`):
1. Update session_id, fire `onSessionIdCaptured` (lines 1690-1709)
2. Clear runaway + turnHardCap, reset `firstToolUseAt`, `lastBlockKind`, `lastBlockToolName`, `activeChapter` (lines 1714-1721)
3. Fire `onResult({ totalCostUsd: delta })` (line 1723) — try/catch with `reportSilentFallback`
4. Fire `onTextTurnEnd?.()` (line 1735) — try/catch with `reportSilentFallback`
5. Cost-cap check → may emit `onWorkflowEnded` (line ~1748)

**`onResult` → `onTextTurnEnd` ordering is guaranteed** within `handleResultMessage` (both fire synchronously, in order, in same function). `onWorkflowEnded` for cost-cap fires AFTER. `onWorkflowEnded` for `runner_runaway | idle_timeout | internal_error` fires from separate paths (e.g., `clearRunaway` callback, timer callbacks) that can interrupt before `handleResultMessage` runs.

**Implication for W4 race protection:** `pendingTurnUsage` race within a single dispatch is theoretical (no turn N+1 after `onWorkflowEnded`). But `turnIndex` tag is still defensive design and recommended by Kieran P0-3 + GDPR BLOCK 2. Keep.

## Plan amendments needed before W2 RED

- [ ] Update plan §1.1.4 "Repeat for each status in 0.4's enumerated list" to: "Repeat for `runner_runaway`, `idle_timeout`, `internal_error`. User-Stop is OUT OF W2 SCOPE — separate code path; documented as accepted residual."
- [ ] Add to plan's "Deferred items" section: **D-DSAR-art15** — Implement DSAR Art. 15 export endpoint (pre-existing gap surfaced during PR-A Phase 0.5; broader than original scope).

## Implementation scaffolding ready

Test pattern from `cc-dispatcher.test.ts:978-1100` (T1/T2/T3):
- `__setCcRunnerForTests(makeAssistantPersistenceStubRunner({ onDispatch }))` — inject mock runner
- Helper: `assistantInsertCalls(mockMessagesInsert)` — filter insert calls to role=assistant
- Helper: `mirrorCallsForOp(mockReportSilentFallback, op)` — filter Sentry mirror calls by op
- Mocks (vi.hoisted): `mockMessagesInsert`, `mockUpdateConversationFor`, `mockReportSilentFallback`, `mockFetchUserWorkspacePath`
- Default: `mockMessagesInsert.mockResolvedValue({ error: null })`, override per test for failure

W2 tests follow this pattern; events sequence:
```ts
events.onText("partial 1");
events.onText("partial 2");
events.onWorkflowEnded({ status: "runner_runaway", ... });
// W2 flushes accumulated text as status:"aborted" row
events.onTextTurnEnd?.();  // late call → W2 workflowEnded flag suppresses double-write
```

## Recommended next session

Two options:

### Option A — Continue PR-A as planned (4 workstreams in one PR)

Per plan rev-2. Realistic scope: 2-4 focused hours. Order: W2 → W4 → W8 → W1.

### Option B — Split per DHH's "ship small" framing

Split PR-A into PR-A1 (W2 + W8, ~50 LOC code + 4 tests, low complexity) and PR-A2 (W4 + W1, more complex with feature flag + RLS matrix). PR-A1 ships this week; PR-A2 follows. Same #3603 umbrella; both PRs reference it. This aligns with the "ship the fix; don't perform the fix" instinct DHH flagged and gets the most user-visible improvement (W8 align persistence to UI) into production fastest.

## Branch state

- Branch: `feat-cc-assistant-turn-persistence-3258`
- Worktree: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-cc-assistant-turn-persistence-3258/`
- PR: #3602 (draft), commits up to `4ef7dc97` (`plan: PR-A rev-2 — synthesize 4 reviews`)
- Clean working tree (rev-2 commit pushed)

## Resume prompt

```
/soleur:work knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md

Resume from Phase 1.1 W2 RED+GREEN. Phase 0 findings captured in session-state.md. Test scaffolding pattern at cc-dispatcher.test.ts:978-1100. WorkflowEnd statuses: runner_runaway | idle_timeout | internal_error (user-Stop OOS). SDK ordering: onResult → onTextTurnEnd guaranteed. Plan rev-2 + spec rev-2 already pushed.
```
