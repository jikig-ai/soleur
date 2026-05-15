---
title: "ADR-031 — cc-dispatcher extraction: cc-workflow-end-messages"
status: accepted
date: 2026-05-15
plan: knowledge-base/project/plans/2026-05-15-refactor-extract-cc-workflow-end-messages-plan.md
issue: 3243
supersedes: none
related: [ADR-022-sdk-as-router]
---

# ADR-031 — cc-dispatcher extraction: `cc-workflow-end-messages`

## Context

Issue #3243 tracks the decomposition of `apps/web-platform/server/cc-dispatcher.ts` (currently ~1.9k LoC) into small, single-purpose sibling modules. The status comment posted by PR #3802 (`apps/web-platform/scripts/3243-status-comment.md`) names `WORKFLOW_END_USER_MESSAGES` as the next smallest extractable unit — a pure data map plus a TypeScript exhaustiveness rail, ~15 LoC, zero behavior change.

Prior extractions establish the cadence: PR #3608 (`mirrorWithDebounce` → `observability.ts`), PR #3670 (cluster drain), PR #3802 (deferred-scope-out cluster). The #3243 AC asks for "one PR per extraction + one ADR per extraction"; this ADR records that decision boundary for the user-copy module.

## Decision

1. **Module boundary — data only.** `apps/web-platform/server/cc-workflow-end-messages.ts` owns user-facing copy for the runner's `WorkflowEnd` status variants and nothing else. No functions, no logger, no side effects. The module surface is a single `export const WORKFLOW_END_USER_MESSAGES: Record<WorkflowEndStatus, string>` plus a private compile-time exhaustiveness rail.

2. **Type source — runner, not `lib/types`.** The new module imports `type WorkflowEnd` from `./soleur-go-runner` and locally re-derives `type WorkflowEndStatus = WorkflowEnd["status"]`. It does **NOT** import `WorkflowEndStatus` from `@/lib/types`. Verification at plan-deepen time:

   | Source | Status set | Cardinality |
   |---|---|---|
   | `apps/web-platform/lib/types.ts:16-27` (`WORKFLOW_END_STATUSES`) | wire-protocol enum including `sandbox_denial`, `runner_crash` | 9 |
   | `apps/web-platform/server/soleur-go-runner.ts:631-652` (`WorkflowEnd` union) | actually-emitted runner terminal states | 7 |
   | `cc-dispatcher.ts:585-597` (extracted map keys) | aligned to runner | 7 |

   Using `@/lib/types` would fire this module's exhaustiveness rail immediately on the two missing keys (`sandbox_denial`, `runner_crash`), breaking the standalone typecheck. Mirroring `cc-dispatcher.ts:212`'s local re-derive preserves the runner-bound contract the dispatcher already encodes.

3. **Exhaustiveness rail — load-bearing safety property.** The rail (`const _workflowEndExhaustive: Record<WorkflowEndStatus, string> = WORKFLOW_END_USER_MESSAGES; void _workflowEndExhaustive;`) moves with the map. Adding a new variant to the runner's `WorkflowEnd` union without an accompanying user-facing copy entry produces a TypeScript error at this module's location at compile time — operators are forced to author the copy rather than silently shipping an `undefined` chat-surface string.

4. **Cadence — one extraction per PR, one ADR per extraction.** This PR uses `Ref #3243`, not `Closes #3243`; the parent decomposition issue stays open as a roadmap pointer. The next-next extraction named in the status comment is `cc-singletons.ts` (the `PendingPromptRegistry` reaper + `StartSessionRateLimiter` singleton).

## Consequences

**Positive.**
- Diff is maximally reviewable: the new module is data-only, the dispatcher edit is a -36-line block delete plus a single named import.
- The exhaustiveness rail now lives next to the data it constrains; future readers see the copy-authoring obligation in the same file.
- Re-establishes the per-extraction cadence after the multi-file drain in PR #3802.

**Negative / out of scope.**
- The `cc-dispatcher.ts:212` local re-derive (`export type WorkflowEndStatus = WorkflowEnd["status"]`) stays — still consumed by `TERMINAL_WORKFLOW_END_STATUSES`, `ABORT_FLUSH_STATUSES`, and `AbortFlushStatus`. Removing it would touch the abort-flush logic, which carries actual behavior risk; that's a separate ADR.
- The `lib/types.ts` vs. runner enum drift (9 wire-protocol values vs. 7 emitted) is real and pre-existing. This PR does not reconcile it; a follow-up `code-review`-labeled issue captures the choice (extend the runner to emit the missing two, or narrow the wire enum).

## Alternatives considered

- **Import `WorkflowEndStatus` from `@/lib/types` (plan v1).** Rejected at deepen time: would have caused the exhaustiveness rail to fire on `sandbox_denial`/`runner_crash` because the dispatcher map covers the 7-status runner union, not the 9-status wire enum. The TS error would have surfaced at standalone typecheck (Phase 1) and forced a mid-implementation pivot.
- **Re-export `WorkflowEndStatus` from `cc-dispatcher.ts`.** Rejected: would invert the dependency (new module imports from the dispatcher it is extracted out of). Local re-derive from `./soleur-go-runner` mirrors the dispatcher's own pattern at line 212 without creating a circular dep risk.
- **Bigger extraction (this map + the abort-flush set + terminal-status set).** Rejected for this PR: those sets carry behavior (the abort-flush set drives a write path at `agent-runner.ts:2044-2055`). Mixing data extraction with behavior extraction violates the "one extraction per PR" cadence and inflates review surface.

## References

- Issue #3243 — `cc-dispatcher.ts` decomposition roadmap (open).
- Status comment (`apps/web-platform/scripts/3243-status-comment.md`) — recommends this extraction by name at line 31.
- ADR-022 — SDK-as-router context for the cc-soleur-go cluster.
- Sibling-extraction precedents: PR #3608 (`mirrorWithDebounce`), PR #3670 (cluster drain), PR #3802 (deferred-scope-out drain).
- Plan: `knowledge-base/project/plans/2026-05-15-refactor-extract-cc-workflow-end-messages-plan.md` — Research Reconciliation table verifies issue-body claims against current code; Enhancement Summary documents the type-source pivot caught at deepen time.
- Learning: `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` — applied here (file is 1927 LoC, not 937 as the issue body claimed).

## Amendment — 2026-05-15 (#3827)

The pre-existing `lib/types.ts` vs. runner enum drift named in the original `Negative / out of scope` section above is resolved in the PR closing #3827. Decision: **narrow the wire enum** (Option b from the issue body), not extend the runner.

**Resolution.** `WORKFLOW_END_STATUSES` in `apps/web-platform/lib/types.ts` is reduced from 9 → 7 entries by removing `sandbox_denial` and `runner_crash`. The cardinality table from the original Decision section §2 now reads:

| Source | Status set | Cardinality |
|---|---|---|
| `apps/web-platform/lib/types.ts` (`WORKFLOW_END_STATUSES`) | wire-protocol enum, post-narrow | 7 |
| `apps/web-platform/server/soleur-go-runner.ts` (`WorkflowEnd` union) | runner-emitted terminal states | 7 |
| `cc-dispatcher.ts:212` re-derive + `cc-workflow-end-messages.ts:7` re-derive | runner-bound | 7 |

**Why option (b), not option (a).** Both removed statuses had ~2 months with zero production emit sites. `sandbox_denial` is already observable via the existing `feature: agent-sandbox` Sentry channel (cc-dispatcher.ts:1077, agent-runner.ts:2138 mirror + re-throw); option (a) would have duplicated, not added, that signal. `runner_crash` has no failure-mode semantic distinct from the existing `internal_error` / `runner_runaway` paths. Adding emit-site logic for either would be a feature add disguised as cleanup; option (b) is the YAGNI fix this ADR's `Negative / out of scope` section originally identified as "cheaper if vestigial."

**Source of truth flipped: runner now canonical.** The `WorkflowEnd["status"]` union in `soleur-go-runner.ts` is now the canonical authority; the `WORKFLOW_END_STATUSES` tuple in `lib/types.ts` mirrors it. The JSDoc comment on the tuple was updated to reflect this contract. The Zod schema (`lib/ws-zod-schemas.ts:381` `z.enum(WORKFLOW_END_STATUSES)`) and the consumers in `lib/chat-state-machine.ts` + `lib/types.ts:300` continue to derive from the tuple — narrowing propagates automatically.

**Compile-time re-drift gate.** A bidirectional `_AssertWorkflowEndStatusMatches` rail was added in `soleur-go-runner.ts` adjacent to the `WorkflowEnd` union. It uses the nested-ternary pattern from `lib/types.ts:94-110` (`_AssertKindsMatch`) and forces `WorkflowEnd["status"]` and `WorkflowEndStatus` to remain set-equal. Adding to either side without the other produces a TS error at the assert. This closes the gap left by the existing `_workflowEndExhaustive` (`cc-workflow-end-messages.ts:42`) and `_abortFlushExhaustive` (`cc-dispatcher.ts:247`) rails, which cover only the runner→consumer direction.

**Out of scope for this PR.** The duplicate ADR-031 filename collision (`ADR-031-sentry-as-iac.md` shares this number) is pre-existing and tracked separately. The `cc-dispatcher.ts:212` re-derive removal remains deferred per the original `Negative / out of scope` section. The historical `migrations/032_conversation_workflow_state.sql:48` column comment enumerating all 9 statuses is preserved per append-only migration convention; a forward-migration refresh is a separate concern.
