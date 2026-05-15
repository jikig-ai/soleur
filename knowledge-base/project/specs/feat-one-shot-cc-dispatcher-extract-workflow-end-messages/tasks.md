---
title: "Tasks — Extract cc-workflow-end-messages.ts from cc-dispatcher.ts"
plan: knowledge-base/project/plans/2026-05-15-refactor-extract-cc-workflow-end-messages-plan.md
issue: 3243
lane: single-domain
---

# Tasks — feat-one-shot-cc-dispatcher-extract-workflow-end-messages

Plan: `knowledge-base/project/plans/2026-05-15-refactor-extract-cc-workflow-end-messages-plan.md`

## Phase 1 — New module (Setup)

- [ ] 1.1 Create `apps/web-platform/server/cc-workflow-end-messages.ts` per Phase 1 of the plan: JSDoc moved verbatim; `import type { WorkflowEnd } from "./soleur-go-runner";` (NOT `@/lib/types` — see plan Enhancement Summary point 1 + corresponding row in Research Reconciliation); local `type WorkflowEndStatus = WorkflowEnd["status"];`; exported `WORKFLOW_END_USER_MESSAGES` map with the seven entries byte-identical to `cc-dispatcher.ts:586-596`; `_workflowEndExhaustive` rail preserved.
- [ ] 1.2 Run `cd apps/web-platform && bun run typecheck` standalone. Expected: clean. The rail enforces that `WORKFLOW_END_USER_MESSAGES`'s seven keys exhaustively cover the runner's 7-status `WorkflowEnd` union. If the rail fires, the runner's union has been widened on `main` since deepen — add the new key's user-facing copy in this PR rather than pivoting the type source.

## Phase 2 — Dispatcher wiring (Core)

- [ ] 2.1 Edit `apps/web-platform/server/cc-dispatcher.ts`: remove lines 569-604 (JSDoc + `WORKFLOW_END_USER_MESSAGES` const + `_workflowEndExhaustive` rail).
- [ ] 2.2 Add `import { WORKFLOW_END_USER_MESSAGES } from "./cc-workflow-end-messages";` to the relative-import cluster (next to `./cc-cost-caps` at line 44).
- [ ] 2.3 Verify the two consumer reads at the (now-shifted) `cc-dispatcher.ts` `onWorkflowEnded` site — `WORKFLOW_END_USER_MESSAGES[end.status]` — are byte-identical post-edit.
- [ ] 2.4 Run `cd apps/web-platform && bun run typecheck`. Both the dispatcher consumer reads and the new module's rail must compile cleanly.

## Phase 3 — Test relocation (Testing)

- [ ] 3.1 Create `apps/web-platform/test/cc-workflow-end-messages.test.ts`. Top-level `import { WORKFLOW_END_USER_MESSAGES } from "@/server/cc-workflow-end-messages";`. Single `describe("WORKFLOW_END_USER_MESSAGES")` with the relocated `it(...)` block from `test/cc-dispatcher.test.ts:730-769`. Use `test/cc-cost-caps.test.ts:9` as the structural template.
- [ ] 3.2 Remove the test block at `test/cc-dispatcher.test.ts:723-769` (header comment 723-728 + `it(...)` 730-769). Verify the next test's header at line 771 (`// dispatchSoleurGo onToolUse label routing (#3235)`) is preserved — off-by-one boundary check.
- [ ] 3.3 Run `cd apps/web-platform && bun run test:ci -- cc-workflow-end-messages` — new test file green.
- [ ] 3.4 Run `cd apps/web-platform && bun run test:ci -- cc-dispatcher` — existing dispatcher tests still green.

## Phase 4 — ADR (Docs)

- [ ] 4.1 Create `knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md`. Frontmatter follows ADR-030 shape: `title`, `status: accepted`, `date: 2026-05-15`, `plan`, `issue: 3243`, `supersedes: none`, `related: [ADR-022-sdk-as-router]`.
- [ ] 4.2 Body covers the four decisions: (a) module boundary (data-only, no behavior), (b) type-source — `@/lib/types` `WorkflowEndStatus`, not the runner-derived alias, (c) exhaustiveness-rail preservation as the load-bearing safety property, (d) "one extraction per PR + one ADR per extraction" cadence per the #3243 AC.

## Phase 5 — Full-suite regression (Verify)

- [ ] 5.1 Run `cd apps/web-platform && bun run test:ci`. Expected: green modulo pre-existing component-test flake class (kb-chat-sidebar, chat-surface, error-states — documented in `2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md`).
- [ ] 5.2 Run `cd apps/web-platform && bun run typecheck` final pass.
- [ ] 5.3 `git grep -n "WORKFLOW_END_USER_MESSAGES"` returns exactly four match files: new module, new test, `cc-dispatcher.ts` (import + 2 consumer reads), `apps/web-platform/scripts/3243-status-comment.md` (historical reference).

## Phase 6 — PR + post-merge (Ship)

- [ ] 6.1 PR body MUST contain `Ref #3243` (NOT `Closes #3243`).
- [ ] 6.2 PR body includes the Research Reconciliation table from the plan + the User-Brand Impact threshold + the pre-existing flake class acknowledgment.
- [ ] 6.3 Post-merge: `gh issue comment 3243 --body-file <file>` with a status refresh naming `cc-singletons.ts` (PendingPromptRegistry + reaper + StartSessionRateLimiter) as the next concrete extraction. Match the existing `apps/web-platform/scripts/3243-status-comment.md` prose style.
- [ ] 6.4 Post-merge: file a follow-up `code-review` issue for the lib/types-vs-runner enum drift (`WORKFLOW_END_STATUSES` has 9 values; `WorkflowEnd` union has 7). Body: cite `lib/types.ts:16-27` and `soleur-go-runner.ts:631-652`, propose two resolutions (runner emits the missing two, or wire enum drops them), tag `Ref #3243`. Verify label `code-review` exists via `gh label list --limit 200 | grep code-review` before creating.
- [ ] 6.5 Verify on `main` post-merge that GH Actions `typecheck` + `test:ci` are still green.

## Out of scope

- The `cc-dispatcher.ts:212` local re-derive of `WorkflowEndStatus = WorkflowEnd["status"]` stays — still consumed by `TERMINAL_WORKFLOW_END_STATUSES`, `ABORT_FLUSH_STATUSES`, `AbortFlushStatus`. Deletion is a separate cleanup.
- `cc-singletons.ts` extraction (next-next step) — separate PR.
- Component-test flake fix (kb-chat-sidebar et al.) — repo-level work item, not introduced by this PR.
- Lib/types-vs-runner `WorkflowEndStatus` enum drift (9 vs 7 values) — pre-existing, file follow-up issue (task 6.4), do not touch in this PR.
