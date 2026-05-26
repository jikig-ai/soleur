---
title: "Extract cc-workflow-end-messages.ts from cc-dispatcher.ts (next sibling step for #3243)"
date: 2026-05-15
type: refactor
issue: 3243
related_prs: [3608, 3670, 3802]
adr: knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# Refactor: extract `cc-workflow-end-messages.ts` from `cc-dispatcher.ts`

## Enhancement Summary

**Deepened on:** 2026-05-15
**Sections enhanced:** Research Reconciliation (type-source row corrected), Phase 1 (type import flipped), ADR-031 decision (type-source rationale rewritten), Risks (type-source-mismatch entry rewritten as a Risk-now-resolved), Test Strategy (compile-time gate evidence pinned).

### Key Improvements

1. **Type-source correction — load-bearing.** The original plan recommended importing `WorkflowEndStatus` from `@/lib/types` ("strictly fewer deps than the source site"). Deepen-pass verification against `lib/types.ts:16-27` AND `soleur-go-runner.ts:631-652` proved this is **wrong**: `lib/types.ts` `WORKFLOW_END_STATUSES` has **9** values (`completed`, `user_aborted`, `cost_ceiling`, `idle_timeout`, `plugin_load_failure`, `sandbox_denial`, `runner_crash`, `runner_runaway`, `internal_error`) while the runner's `WorkflowEnd` union (the actual emitter feeding the dispatcher's `onWorkflowEnded` callback at `cc-dispatcher.ts:1598`) has **7** statuses — missing `sandbox_denial` and `runner_crash`. The map at `cc-dispatcher.ts:585-597` has 7 keys aligned to the runner's union, NOT the wider `lib/types.ts` enum. Importing `WorkflowEndStatus` from `@/lib/types` would make the new module's `_workflowEndExhaustive` rail fire immediately for two missing keys, breaking the Phase 1 standalone typecheck before the dispatcher edit lands.

2. **Corrected type source: `./soleur-go-runner` via `WorkflowEnd["status"]`.** The new module imports `type WorkflowEnd` from `./soleur-go-runner` and locally re-derives `type WorkflowEndStatus = WorkflowEnd["status"]` — structurally identical to the local re-derive at `cc-dispatcher.ts:212`. Same dep shape the dispatcher already has, no widening, no shrinking. The "two different `WorkflowEndStatus` definitions in the codebase" finding is now scoped out of this PR (separate cleanup — see Risks).

3. **Catches the paraphrase-without-verification class.** This deepen-pass correction is the textbook application of `2026-04-22-ts-sql-normalizer-parity...` (paraphrase issue-body claims must be grepped) and `2026-05-13-plan-verify-reducer-case-arms-with-grep-not-read-first-n.md` (grep > Read-first-N for enumerating cases). Plan v1 assumed structural equality of two same-named types; plan v2 verified it and found drift. Without deepen-pass, Phase 1's standalone typecheck would have been the catch — still pre-merge, but with a mid-implementation pivot that the plan should have predicted.

### New Considerations Discovered

- The `lib/types.ts` enum (9 values) and the runner's union (7 values) are themselves **drifted from each other** — `sandbox_denial` and `runner_crash` live in the wire-protocol enum but the runner never emits them. This is pre-existing and out of scope here, but worth a follow-up issue (the wire schema accepts statuses the runner cannot produce → dead-code-shaped contract). Filed as a deferred-scope-out concern for a future cleanup; do NOT fold into this PR.
- The exhaustiveness rail's value is now **explicit**: it pins the new module to the runner's union shape. If a future commit adds `sandbox_denial` to the runner's `WorkflowEnd` (closing the lib/types-vs-runner drift), the rail fires here and forces the operator to author user-facing copy. That's the correct design — copy should not be silently empty for a new terminal state.

## Overview

Pull the pure user-copy data map `WORKFLOW_END_USER_MESSAGES` (and its compile-time `_workflowEndExhaustive` rail) out of `apps/web-platform/server/cc-dispatcher.ts` into a new sibling module `apps/web-platform/server/cc-workflow-end-messages.ts`. This is the next sibling-extraction step for #3243, recommended by name in the #3243 status comment posted by PR #3802 (`apps/web-platform/scripts/3243-status-comment.md:31`).

**Why this unit, why now.** It is the smallest remaining unit named in the status comment — ~15 LoC of pure data + one type-level exhaustiveness check, zero behavior. Re-establishes the "one PR per extraction + one ADR per extraction" cadence the #3243 AC asks for, with a maximally reviewable diff. The reaper-interval + rate-limiter extraction (`cc-singletons.ts`) is the recommended next-next step after this lands clean.

**What is NOT in scope.** No behavior change. No changes to call sites (lines 1662 and 1670 keep reading from `WORKFLOW_END_USER_MESSAGES[end.status]` — just from a new import). No widening or narrowing of the user-copy strings. No new tests beyond relocating the existing exhaustiveness snapshot to live next to the new module.

## Research Reconciliation — Spec vs. Codebase

Per AGENTS.md plan-skill Phase 1.7, the issue body's snapshot claims are revalidated against current code. The `2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` learning is the direct input.

| Claim source | Claim | Codebase reality (verified at plan time) | Plan response |
|---|---|---|---|
| #3243 issue body | `cc-dispatcher.ts` is 937 lines | `wc -l apps/web-platform/server/cc-dispatcher.ts` → **1927** | Plan tracks current state. Issue stays open as roadmap pointer; PR uses `Ref #3243`, not `Closes #3243`. |
| #3243 issue body | "Extract `mirrorWithDebounce` first — smallest, most self-contained" | Already shipped in PR #3608, consolidated in PR #3670. `cc-dispatcher.ts:64` imports it from `./observability`. | Skip — already done. Status comment by PR #3802 names `cc-workflow-end-messages.ts` as the new smallest remaining unit. This PR executes that recommendation. |
| #3243 status comment | `WORKFLOW_END_USER_MESSAGES` is "a pure data map plus a TypeScript exhaustiveness rail — ~15 LoC, no behavior change, near-zero risk" | Verified: `cc-dispatcher.ts:585-604` — 13 LoC for the const, 4 LoC for the rail. No imports, no side-effects, no functions. | Extraction is safe at the aggregate-pattern brand-survival threshold. |
| Implicit assumption | Test consumer at `test/cc-dispatcher.test.ts:730-769` is the only test surface | Verified via `git grep -n "WORKFLOW_END_USER_MESSAGES"` — one production consumer file (cc-dispatcher.ts), one test file (cc-dispatcher.test.ts). | Relocate the test block to a new `test/cc-workflow-end-messages.test.ts` (precedent: sibling extraction `cc-cost-caps.ts` ↔ `cc-cost-caps.test.ts`). |
| Implicit assumption (plan v1) | `WorkflowEndStatus` has a single source of truth and the two definitions are structurally identical | **Disproved at deepen-time.** Verified by `Read apps/web-platform/lib/types.ts:16-27` (9 statuses, includes `sandbox_denial` + `runner_crash`) vs `Read apps/web-platform/server/soleur-go-runner.ts:631-652` (`WorkflowEnd` union has 7 statuses, NO `sandbox_denial`/`runner_crash`). The map at `cc-dispatcher.ts:585-597` has 7 keys aligned to the runner's union, NOT the wider `lib/types.ts` enum. The two `WorkflowEndStatus` names are **drifted**, not structurally identical. | **Plan v2 type source: `./soleur-go-runner`'s `WorkflowEnd["status"]`** — same dep shape as the source site's local re-derive at `cc-dispatcher.ts:212`. Importing from `@/lib/types` would have caused the new module's `_workflowEndExhaustive` rail to fire immediately on `sandbox_denial`/`runner_crash` (no map entry), breaking Phase 1 standalone typecheck. The lib/types-vs-runner drift is real and pre-existing — filed as a follow-up scope-out (`Risks` section); explicitly OUT of scope for this PR. The local re-derive in `cc-dispatcher.ts:212` is unchanged (still needed by `TERMINAL_WORKFLOW_END_STATUSES`, `ABORT_FLUSH_STATUSES`, `AbortFlushStatus`). |

## User-Brand Impact

**If this lands broken, the user experiences:** the cc-soleur-go workflow-end WS path (`dispatchSoleurGo` → `onWorkflowEnded`) emits an undefined or wrong-keyed string in the WS `dispatcher_message` payload at `cc-dispatcher.ts:1662` and `:1670`. End-user impact would be a missing or garbled terminal copy line on the chat surface for non-`completed` workflow ends (`cost_ceiling`, `runner_runaway`, `user_aborted`, `idle_timeout`, `plugin_load_failure`, `internal_error`).

**If this leaks, the user's data is exposed via:** N/A — no user-data surface. The map is static string literals; no PII flows through.

**Brand-survival threshold:** aggregate pattern. This is a pure refactor with no behavior delta; risk is bounded to the consumer-import wiring being inconsistent, which TypeScript catches at compile time (the exhaustiveness rail is preserved, just relocated). No single user is broken in a way the diff doesn't manifest as a build failure on CI.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/server/cc-workflow-end-messages.ts` exists and exports `WORKFLOW_END_USER_MESSAGES: Record<WorkflowEndStatus, string>` with the seven entries currently at `cc-dispatcher.ts:586-596`, byte-identical strings.
- [ ] The compile-time exhaustiveness rail (`_workflowEndExhaustive` const + `void _workflowEndExhaustive`) is preserved in the new module, referencing the relocated map.
- [ ] `apps/web-platform/server/cc-dispatcher.ts` removes lines 569-604 (the JSDoc, the map, the rail) and replaces them with a single named import `import { WORKFLOW_END_USER_MESSAGES } from "./cc-workflow-end-messages";` placed in the existing relative-import cluster near the top of the file.
- [ ] The two call sites at the current `cc-dispatcher.ts:1662` and `:1670` continue to read `WORKFLOW_END_USER_MESSAGES[end.status]` — diff at those lines is byte-identical post-extraction.
- [ ] `apps/web-platform/test/cc-workflow-end-messages.test.ts` exists, contains the relocated test block (currently `test/cc-dispatcher.test.ts:723-769`), and imports the map from `@/server/cc-workflow-end-messages` (NOT via dynamic `import()` — direct `import { WORKFLOW_END_USER_MESSAGES } from "@/server/cc-workflow-end-messages"` matches the sibling-extraction precedent at `test/cc-cost-caps.test.ts:9`).
- [ ] `apps/web-platform/test/cc-dispatcher.test.ts` has its `WORKFLOW_END_USER_MESSAGES` test block removed (single-test-per-module convention).
- [ ] `cd apps/web-platform && bun run typecheck` exits 0 (the exhaustiveness rail is the load-bearing check — any drift between the map and `WorkflowEndStatus` produces a TS error at the new module's location).
- [ ] `cd apps/web-platform && bun run test:ci -- cc-workflow-end-messages` exits 0 (new test file green).
- [ ] `cd apps/web-platform && bun run test:ci -- cc-dispatcher` exits 0 (existing dispatcher tests still green; the moved block's removal does not affect siblings).
- [ ] Full `cd apps/web-platform && bun run test:ci` is green for everything except the pre-existing component-test flake class documented in `2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` (kb-chat-sidebar, chat-surface, error-states — ECONNREFUSED on localhost:3000 under full-suite concurrency, pass in isolation). PR body must explicitly call out the flake class to prevent review-time false-blame.
- [ ] `git grep -n "WORKFLOW_END_USER_MESSAGES"` shows exactly four match files: the new module (definition + rail), `cc-dispatcher.ts` (one import + two consumer reads at lines now shifted up by ~36 lines), the new test, and `apps/web-platform/scripts/3243-status-comment.md` (historical reference — do not touch).
- [ ] ADR-031 (`knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md`) exists, follows the ADR-030 frontmatter shape (title / status: accepted / date / plan / issue / supersedes / related), is one page, and documents the **decoupling-from-runner** decision (new module depends on `lib/types.ts` `WorkflowEndStatus`, not on the runner-derived alias in `cc-dispatcher.ts:212`).
- [ ] PR body contains `Ref #3243` (NOT `Closes #3243`) — multiple extractions still pending per the #3243 status comment.
- [ ] PR body includes the "Research Reconciliation — Spec vs. Codebase" table above so reviewers see the drift-against-issue-body explicitly.

### Post-merge (operator)

- [ ] Post a status comment update on #3243 naming the next-next extraction: **`cc-singletons.ts`** for `PendingPromptRegistry` + reaper + `StartSessionRateLimiter` singleton (per the status-comment recommendation order). Use the same `apps/web-platform/scripts/3243-status-comment.md`-style refresh prose so the issue stays a navigable roadmap pointer. Automation: `gh issue comment 3243 --body-file <(...)`.
- [ ] File a follow-up `code-review`-labeled issue for the **lib/types-vs-runner `WorkflowEndStatus` enum drift** uncovered at deepen-time: `WORKFLOW_END_STATUSES` in `apps/web-platform/lib/types.ts:16-26` lists 9 statuses (includes `sandbox_denial`, `runner_crash`); `WorkflowEnd` in `apps/web-platform/server/soleur-go-runner.ts:631-652` is a 7-status union. Body proposes two resolutions (runner emits the missing two, or wire enum drops them) and tags `Ref #3243`. Verify the `code-review` label exists via `gh label list --limit 200 \| grep -E "^code-review\b"` before `gh issue create`.
- [ ] Verify on `main` that `bun run typecheck` + `bun run test:ci` are still green by tailing the relevant GH Actions runs; close out the PR-body acknowledgment of the pre-existing flake if any flake regressions appear that this PR could have introduced (none expected — the diff is data-shape-preserving).

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — remove lines 569-604 (JSDoc block at 569-584, `WORKFLOW_END_USER_MESSAGES` const at 585-597, exhaustiveness rail at 599-604). Add a single named import `import { WORKFLOW_END_USER_MESSAGES } from "./cc-workflow-end-messages";` in the relative-import cluster near line 44-67 (placement next to `./cc-cost-caps` is the cleanest — same extraction class).
- `apps/web-platform/test/cc-dispatcher.test.ts` — remove the `WORKFLOW_END_USER_MESSAGES` test block at lines 723-769 (the header comment at 723-728 and the `it(...)` at 730-769). Verify the surrounding `describe` block stays grammatical after removal.

## Files to Create

- `apps/web-platform/server/cc-workflow-end-messages.ts` — new module containing the JSDoc + map + exhaustiveness rail. Imports `WorkflowEndStatus` from `@/lib/types` (not from the runner). The module is data-only; no functions, no logger, no side effects.
- `apps/web-platform/test/cc-workflow-end-messages.test.ts` — new test file. Single `describe("WORKFLOW_END_USER_MESSAGES")` block containing the relocated test. Static import (not dynamic `import()`) — matches `test/cc-cost-caps.test.ts:9` convention. Asserts: (a) actual keys match the expected `WorkflowEndStatus` variant set, (b) `completed` is the empty string, (c) `runner_runaway`/`cost_ceiling`/`internal_error` carry the documented user-facing substrings, (d) defense-in-depth: no entry leaks the `Workflow ended (...)` template.
- `knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md` — one-page ADR. Status: accepted. Records (a) the boundary (`cc-workflow-end-messages.ts` owns user-facing copy for the runner's `WorkflowEnd` status variants), (b) the type-source decision — import `WorkflowEnd` from `./soleur-go-runner` and locally re-derive `WorkflowEndStatus = WorkflowEnd["status"]`, mirroring `cc-dispatcher.ts:212`. Explicitly NOT `@/lib/types` `WorkflowEndStatus`, which is wider (9 wire-protocol values including `sandbox_denial` + `runner_crash`) than the runner's actual `WorkflowEnd` union (7 values). The drift between `lib/types.ts` and the runner is real and pre-existing; this PR scopes out the cleanup and references a follow-up issue. (c) Exhaustiveness-rail preservation as the load-bearing safety property — adding a new variant to the runner's `WorkflowEnd` union without a map entry produces a TS error at the new module. (d) Cadence — "one extraction per PR, one ADR per extraction" per the #3243 AC. Related ADRs section cites the cc-soleur-go cluster (ADR-022 SDK-as-router) for context.

## Implementation Phases

### Phase 1 — Create the new module

1. Create `apps/web-platform/server/cc-workflow-end-messages.ts` with this exact surface (the JSDoc block from `cc-dispatcher.ts:569-584` is moved verbatim, attribution comment added pointing back to `cc-dispatcher.ts` and the #3243 status comment):

```ts
// apps/web-platform/server/cc-workflow-end-messages.ts
//
// User-facing copy for each `WorkflowEndStatus`. Extracted from
// `cc-dispatcher.ts` per the #3243 status comment recommendation
// (`apps/web-platform/scripts/3243-status-comment.md`). See ADR-031.
//
// Type source: `./soleur-go-runner`'s `WorkflowEnd["status"]` —
// matches the local re-derive at `cc-dispatcher.ts:212`. NOT
// `@/lib/types` `WorkflowEndStatus`, which has 9 wire-protocol
// values (`sandbox_denial`, `runner_crash` included) the runner's
// `WorkflowEnd` union does not currently emit. Importing from
// `@/lib/types` would fire the rail below on two missing keys.
// The lib/types-vs-runner enum drift is real and tracked
// separately — out of scope for this pure extraction.

import type { WorkflowEnd } from "./soleur-go-runner";

type WorkflowEndStatus = WorkflowEnd["status"];

/**
 * <... JSDoc currently at cc-dispatcher.ts:569-584, verbatim ...>
 */
export const WORKFLOW_END_USER_MESSAGES: Record<WorkflowEndStatus, string> = {
  completed: "",
  cost_ceiling:
    "This conversation reached the per-workflow cost cap. Start a new conversation to continue.",
  runner_runaway:
    "The agent went idle without finishing. Try sending another message to nudge it forward.",
  user_aborted: "Conversation stopped at your request.",
  idle_timeout:
    "This conversation was idle for too long and was closed. Start a new conversation to continue.",
  plugin_load_failure:
    "The agent could not start because a plugin failed to load. Try again shortly.",
  internal_error: "Something went wrong on our side. Try sending the message again.",
};

// Compile-time exhaustiveness rail. If a new variant lands in
// `WorkflowEndStatus` without an entry above, this assertion will
// fail (the type narrows to `never` for the missing key).
const _workflowEndExhaustive: Record<WorkflowEndStatus, string> =
  WORKFLOW_END_USER_MESSAGES;
void _workflowEndExhaustive;
```

2. Run `cd apps/web-platform && bun run typecheck` before touching `cc-dispatcher.ts`. The new module compiles standalone — confirms `./soleur-go-runner` exports `WorkflowEnd`, the locally-re-derived `WorkflowEndStatus = WorkflowEnd["status"]` is the 7-status union the map covers, and the seven map keys exhaustively cover the union. Expected outcome: clean typecheck on the new module alone. If the rail fires here, it means the runner's `WorkflowEnd` union has been widened on `main` since this plan was deepened (e.g., `sandbox_denial` was finally implemented); the correct response is to add the new key's user-facing copy to the map in this PR, NOT to pivot the type source. The deepen-pass `Enhancement Summary` documents the type-source decision so future readers see why `@/lib/types` is NOT used here.

### Phase 2 — Wire the dispatcher to the new module

1. In `apps/web-platform/server/cc-dispatcher.ts`, delete lines 569-604 (the JSDoc + map + rail).
2. In the relative-import cluster (around line 44-67, next to `./cc-cost-caps`), add: `import { WORKFLOW_END_USER_MESSAGES } from "./cc-workflow-end-messages";`.
3. Verify the two consumer lines (currently `cc-dispatcher.ts:1662` and `:1670`) are byte-identical post-edit — the only change at those lines is that their line numbers shift down by ~36 lines.
4. Run `cd apps/web-platform && bun run typecheck`. Two checks must both pass: (a) `cc-dispatcher.ts` consumer reads compile (proves the import resolves), (b) the new module's exhaustiveness rail still holds. The rail at `cc-dispatcher.ts:602-604` is removed in this phase — it now lives in the new module.

### Phase 3 — Relocate the test

1. Create `apps/web-platform/test/cc-workflow-end-messages.test.ts`. Use the sibling extraction `apps/web-platform/test/cc-cost-caps.test.ts` as the structural template (top-level `import` from `@/server/...`, single `describe(...)` block).
2. Copy the test block from `test/cc-dispatcher.test.ts:723-769` into the new file, with two surface changes:
   - The dynamic `await import("@/server/cc-dispatcher")` becomes a top-level `import { WORKFLOW_END_USER_MESSAGES } from "@/server/cc-workflow-end-messages";` (the dynamic-import shape was only there because the original block lived inside an existing dispatcher test file; the relocation removes the need).
   - The `it(...)` block stays semantically identical: same `expectedKeys` array, same key-set equality assertion, same per-key substring assertions, same `not.toContain("Workflow ended (")` defense-in-depth.
3. Delete the corresponding block from `test/cc-dispatcher.test.ts:723-769`. Verify the surrounding `describe` is still grammatical (open the file post-edit; if the deletion leaves a stray comment-header for a sibling test, leave the header alone — it documents the adjacent test that follows).
4. Run `cd apps/web-platform && bun run test:ci -- cc-workflow-end-messages` (new test green), then `bun run test:ci -- cc-dispatcher` (existing siblings still green).

### Phase 4 — ADR

1. Create `knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md` matching the frontmatter shape of ADR-030 (title / status / date / plan / issue / supersedes / related). One page, with the four `## Decision` bullets the AC enumerates (boundary, type-source, exhaustiveness preservation, cadence).
2. Cite the #3243 status comment (`apps/web-platform/scripts/3243-status-comment.md`) and PR #3802's drain learning (`knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md`) as research inputs.

### Phase 5 — Full-suite regression gate

1. Run `cd apps/web-platform && bun run test:ci`. Expected: green except for the pre-existing component-test flake class (kb-chat-sidebar, chat-surface, error-states under full-suite concurrency). Document the flake class in the PR body so reviewers don't false-blame this PR.
2. Run `cd apps/web-platform && bun run typecheck` one final time as the load-bearing gate.

### Phase 6 — PR body + post-merge follow-up

1. PR body MUST include `Ref #3243` (NOT `Closes #3243`). The status comment recommends `cc-singletons.ts` as the next-next extraction; the PR body must NOT auto-close #3243 because the multi-PR roadmap is still active.
2. PR body includes the Research Reconciliation table from this plan, the User-Brand Impact section's threshold call-out, and the pre-existing flake-class acknowledgment.
3. Post-merge: post a status-comment refresh on #3243 naming `cc-singletons.ts` as the next concrete extraction (per the status-comment cadence established in PR #3802).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure refactor / aggregate-pattern brand-survival threshold. No product, legal, security, or operations surface changes. No new user-facing copy (all strings preserved byte-identical). No type-shape change at any consumer boundary (`WorkflowEndStatus` from `@/lib/types` is structurally identical to the existing `cc-dispatcher.ts:212` local re-derive).

## Test Strategy

Test runner: `vitest` via `cd apps/web-platform && bun run test:ci` (verified at `apps/web-platform/package.json` — `"test:ci": "vitest run"`).

- **New module test** (`test/cc-workflow-end-messages.test.ts`): relocated exhaustive-snapshot test, structurally identical to the source at `test/cc-dispatcher.test.ts:723-769`. Asserts shape + content + defense-in-depth. Single `describe` block, single `it` block.
- **Compile-time gate** (`bun run typecheck`): the load-bearing safety property. The exhaustiveness rail at the new module's bottom is the canonical enforcer — any new `WorkflowEndStatus` variant without an entry surfaces here at compile time. If the runtime test snapshot ever drifts from the union, the typecheck catches it first.
- **Existing dispatcher tests** (`test/cc-dispatcher.test.ts`): must remain green after the test-block relocation. Run the full file (`bun run test:ci -- cc-dispatcher`) to confirm.
- **Full suite** (`bun run test:ci`): green modulo the pre-existing component-test flake class. Capture the run output in the PR body's "Test run" section.

## Risks

- **Type-source mismatch — RESOLVED at deepen-time.** Plan v1 recommended importing `WorkflowEndStatus` from `@/lib/types`. Deepen-pass verification of `lib/types.ts:16-27` (9 statuses) vs `soleur-go-runner.ts:631-652` (7 statuses) proved the two definitions are drifted, not structurally identical. Plan v2 imports `WorkflowEnd` from `./soleur-go-runner` and locally re-derives `WorkflowEndStatus = WorkflowEnd["status"]`, matching `cc-dispatcher.ts:212`. No standalone-typecheck failure expected at Phase 1.
- **Lib/types.ts-vs-runner enum drift (pre-existing, out of scope).** `lib/types.ts` `WORKFLOW_END_STATUSES` declares `sandbox_denial` and `runner_crash` as wire-protocol values; the runner's `WorkflowEnd` union does not produce them. This drift exists today regardless of this PR and is the reason this PR cannot use `@/lib/types` as the type source. **Disposition**: file a follow-up issue post-merge under label `code-review` to reconcile the two (either the runner adds the two terminal-state emits, or the wire enum drops them). Tag the issue with `Ref #3243` so it joins the cc-dispatcher decomposition roadmap. This PR explicitly does NOT touch the drift — touching it would break the "one extraction per PR" cadence and expand the diff into runner-state-machine territory.
- **Dynamic-import-to-static-import shift risk.** The original test used `await import("@/server/cc-dispatcher")` — the relocation switches to a top-level static import. Vitest handles both identically; the dynamic form was a quirk of the test living inside an unrelated dispatcher test file. No risk to the assertion semantics.
- **Pre-existing component-test flake class.** Full-suite vitest under concurrency surfaces ECONNREFUSED localhost:3000 flakes in kb-chat-sidebar / chat-surface / error-states (documented in `2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md`). **Mitigation**: PR body acknowledges these are NOT introduced by this PR — they pre-exist on `main`. Reviewers cross-reference against the source learning. Out of scope to fix in this PR.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The threshold is set above as `aggregate pattern`.
- When the test relocation removes the block from `test/cc-dispatcher.test.ts:723-769`, double-check the adjacent `// dispatchSoleurGo onToolUse label routing (#3235)` header at line 771 is preserved — that's the next test's header, not the deleted test's. Off-by-one boundary error here would orphan the next test's documentation.
- The `cc-dispatcher.ts:212` local re-derive of `WorkflowEndStatus` (`type WorkflowEndStatus = WorkflowEnd["status"];`) is intentionally LEFT IN PLACE. It is still needed by `TERMINAL_WORKFLOW_END_STATUSES` (line 213), `ABORT_FLUSH_STATUSES` (line 231), and `AbortFlushStatus = Exclude<WorkflowEndStatus, "completed">` (line 245). Deleting it is out of scope for this PR — that's a separate cleanup that touches the abort-flush logic, which has more behavior risk.
- When updating the post-merge status comment on #3243, follow the existing `apps/web-platform/scripts/3243-status-comment.md` prose style. Specifically, name `cc-singletons.ts` (PendingPromptRegistry + reaper + StartSessionRateLimiter) as the next concrete extraction, and re-state the "issue stays open as roadmap pointer" framing so the multi-PR roadmap remains navigable.

## References

- Issue #3243 (parent decomposition roadmap; stays open).
- Status comment authored by PR #3802: `apps/web-platform/scripts/3243-status-comment.md` (recommends this extraction by name at line 31).
- Learning: `knowledge-base/project/learnings/2026-05-15-drain-plan-must-revalidate-issue-state-against-codebase.md` (the snapshot-vs-current revalidation triad; this plan applies it).
- Sibling-extraction precedents: PR #3608 (`mirrorWithDebounce` → `observability.ts`), PR #3670 (cc-dispatcher cluster drain), and the existing `cc-cost-caps.ts` ↔ `cc-cost-caps.test.ts` pair as the structural template for the new module + new test.
- ADR-022 (SDK-as-router) — context for the cc-soleur-go cluster the dispatcher serves.
