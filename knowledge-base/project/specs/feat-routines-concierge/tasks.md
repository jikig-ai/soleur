---
feature: routines-concierge
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-16-feat-routines-concierge-authoring-tab-plan.md
issue: 5402
---

# Tasks — Routines management PR-2: Concierge authoring tab

## Phase 0 — Preconditions (verify, no code)
- [x] 0.1 Confirm leader-less `conversationId="new"` routes via `ws-handler.ts:2215` `dispatchSoleurGoForConversation` → `dispatchSoleurGo` → `buildSoleurGoSystemPrompt` (NOT `startAgentSession`); confirm `context.type` is not currently threaded.
- [x] 0.2 Confirm `validateConversationContext` accepts a type-only context (`{type:"routine-authoring"}`, no path); if it requires a path, plan the minimal relax (skip `isSafePath` when path absent).

## Phase 1 — RED (failing tests first)
- [x] 1.1 `test/components/routines/routines-surface.test.tsx`: Draft tab active (not disabled); intro state (2 cards + chips + composer hint); mounts chat with `initialContext.type==="routine-authoring"`; Routines/Recent Runs unaffected.
- [x] 1.2 `test/server/context-validation.test.ts`: `"routine-authoring"` (no path) passes; unknown type throws; `"kb-viewer"` still passes.
- [x] 1.3 `test/server/cc-dispatcher.routine-authoring-directive.test.ts`: `buildSoleurGoSystemPrompt` includes `ROUTINE_AUTHORING_DIRECTIVE` when the mode flag is set, excludes it otherwise; directive contains no gate-bypass phrasing; enumerates the 4 create edits.

## Phase 2 — GREEN
- [x] 2.1 Create `server/routine-authoring-directive.ts` (`ROUTINE_AUTHORING_DIRECTIVE`): 4-edit create-as-PR guidance (handler+cron literal / EXPECTED_CRON_FUNCTIONS / ROUTINE_METADATA / Inngest client registration); repo-connection conditioning; never-fabricate-un-merged-run; run/verify via gated `routine_run` + `routine_runs_list`; no gate-bypass language.
- [x] 2.2 `server/context-validation.ts`: whitelist `"routine-authoring"`; allow type-only context.
- [x] 2.3 `server/ws-handler.ts` + `server/cc-dispatcher.ts`: thread `context.type` → append directive in `buildSoleurGoSystemPrompt`.
- [x] 2.4 `components/routines/routines-surface.tsx`: third "Draft a routine" tab (active) + `DraftRoutineTab` intro overlay (mock 05) → mounts `<ChatSurface variant="sidebar" conversationId="new" initialContext={{type:"routine-authoring"}} />` in an `h-full min-h-0` container (valid props only).

## Phase 3 — Verify
- [x] 3.1 `./node_modules/.bin/tsc --noEmit` clean.
- [x] 3.2 Feature + touched-server tests green; relevant `test-webplat` slice green.
- [x] 3.3 soleur:qa (ship): Draft tab loads; run-verify shows gate → run-log read-back; create → PR (gated); no-repo path degrades gracefully.

## Exit
- [x] Review (soleur:review) → ship (soleur:ship). `Closes #5402`. No prd migration.
