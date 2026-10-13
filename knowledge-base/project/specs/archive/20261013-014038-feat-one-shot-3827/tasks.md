---
title: "Tasks: reconcile lib/types vs runner WorkflowEndStatus enum drift (#3827)"
plan: knowledge-base/project/plans/2026-05-15-fix-workflow-end-status-enum-drift-plan.md
issue: 3827
branch: feat-one-shot-3827
lane: cross-domain
date: 2026-05-15
---

# Tasks — feat-one-shot-3827

Derived from `knowledge-base/project/plans/2026-05-15-fix-workflow-end-status-enum-drift-plan.md`.

## 1. Setup / Preconditions

- 1.1. Confirm worktree CWD: `pwd` must equal `.worktrees/feat-one-shot-3827`.
- 1.2. Confirm branch: `git branch --show-current` returns `feat-one-shot-3827`.
- 1.3. Phase 0 consumer audit grep (AC5):
  `rg '"sandbox_denial"|"runner_crash"' apps/web-platform/ --type ts`
  Expected hits: only `lib/types.ts:22-23` + `test/ws-protocol.test.ts:540-541`.
  Any other hit aborts the work phase.
- 1.4. Non-TS sweep (AC5.1): `rg "sandbox_denial|runner_crash" apps/web-platform/`
  Expected: also includes `supabase/migrations/032_conversation_workflow_state.sql:48`.
  Acknowledge in PR body; do NOT edit the historical migration.
- 1.5. Verify rolling-deploy fall-through: read `lib/ws-zod-schemas.ts` parse-failure
  handler and confirm it mirrors to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
  If not wired, file follow-up `code-review` issue; do NOT block this PR.

## 2. Core Implementation (RED → GREEN)

### 2.1. RED — failing test first
- 2.1.1. Edit `apps/web-platform/test/ws-protocol.test.ts` lines 532-551:
  - Rename test description: `with all 9 statuses` → `with all 7 statuses`.
  - Remove `"sandbox_denial"` and `"runner_crash"` from the `statuses` array.
  - Append a negative-case assertion: parsing
    `{ type: "workflow_ended", workflow: "plan", status: "sandbox_denial" }`
    MUST produce `r.ok === false`.
- 2.1.2. Run `cd apps/web-platform && bun test test/ws-protocol.test.ts` —
  negative assertion FAILS (Zod still accepts the 9-value tuple).

### 2.2. GREEN — narrow the wire enum
- 2.2.1. Edit `apps/web-platform/lib/types.ts` lines 22-23: remove
  `"sandbox_denial",` and `"runner_crash",` entries from
  `WORKFLOW_END_STATUSES`.
- 2.2.2. Update the JSDoc comment at lines 11-15 to the exact wording
  specified in the plan's "Files to Edit" #1 (runner is canonical, tuple
  mirrors, cardinality rail enforces).
- 2.2.3. Re-run `cd apps/web-platform && bun test test/ws-protocol.test.ts`
  — all 7 statuses pass + negative assertion now passes.

### 2.3. Cardinality rail
- 2.3.1. Edit `apps/web-platform/server/soleur-go-runner.ts`:
  - Add `import type { WorkflowEndStatus } from "@/lib/types";` (new import
    block since the runner doesn't import from `@/lib/types` today).
  - After the `WorkflowEnd` union (after line 652), insert the
    `_AssertWorkflowEndStatusMatches` nested-ternary rail and the
    `void _exhaustiveWorkflowEndStatusCheck` line (exact form per plan
    "Files to Edit" #3).
- 2.3.2. Run `cd apps/web-platform && bunx tsc --noEmit` — must pass.

### 2.4. ADR amendment
- 2.4.1. Edit
  `knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md`:
  - Append `## Amendment — 2026-05-15` section at the bottom.
  - Record: option (b) chosen; cardinality table now reads 7/7/7; the new
    bidirectional rail in `soleur-go-runner.ts` is the canonical
    enforcement; runner is the source of truth; `lib/types.ts` mirrors.
  - Do NOT rewrite the original Decision section (ADR-026 precedent for
    in-place amendment).

## 3. Verification

- 3.1. Full `apps/web-platform` vitest suite green:
  `cd apps/web-platform && bun run test` (AC4).
- 3.2. TypeScript clean: `cd apps/web-platform && bunx tsc --noEmit` (AC3).
- 3.3. Cardinality rail correctness verified by-inspection (AC1) — no
  "exercise then revert" choreography.
- 3.4. AC8 three-part external-consumer sweep (run at Phase 5, results
  go into PR body):
  - `gh search code "sandbox_denial OR runner_crash" --owner jikig-ai`
  - Sentry alert-rule scan (MCP or sentry-config-export.json grep)
  - Doppler config grep on `prd` config

## 4. Ship

- 4.1. Stage edits:
  `git add apps/web-platform/lib/types.ts apps/web-platform/server/soleur-go-runner.ts apps/web-platform/test/ws-protocol.test.ts knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md knowledge-base/project/plans/2026-05-15-fix-workflow-end-status-enum-drift-plan.md knowledge-base/project/specs/feat-one-shot-3827/`
- 4.2. Commit message must include `Closes #3827` and `Ref #3243`.
- 4.3. Push and mark PR #3838 ready for review.
- 4.4. Audit invariant before push: `git diff main..HEAD -- apps/web-platform/`
  shows ONLY the planned narrowing + assert + test changes — no
  drift-test residue, no migration edits.

## Out of Scope

- `cc-dispatcher.ts:213` re-derive removal (separate ADR, ADR-031 §Negative).
- `cc-singletons.ts` extraction (#3243 roadmap).
- Duplicate `ADR-031-*` filename collision (separate docs PR).
- Forward migration to refresh `migrations/032:48` column comment.
