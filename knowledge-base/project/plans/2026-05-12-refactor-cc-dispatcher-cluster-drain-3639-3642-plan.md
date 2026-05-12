---
title: "refactor: cc-dispatcher cluster drain — extract state class + dedup map + discriminated PersistMode + shared test harness + op-slug constants"
type: refactor
date: 2026-05-12
branch: feat-one-shot-drain-pr-a2-review-3639-3642
issues: ["#3639", "#3640", "#3641", "#3642"]
parent: "#3603"
pr: "#3670"
classification: refactor-only
lane: single-domain
tags: [cc-soleur-go, refactor, code-review, cluster-drain, observability]
requires_cpo_signoff: false
brand_survival_threshold: aggregate-pattern
deepened_on: 2026-05-12
---

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Research Reconciliation (3 new corrections), all five issue ACs, Implementation Phases (Phase 1 + Phase 3 + Phase 5 + Phase 7), Risks, Sharp Edges, Test Strategy.

**Live-citation verification:** All 12 PR/issue numbers (`#2467`, `#2468`, `#2469`, `#2486`, `#3603`, `#3638`, `#3639`, `#3640`, `#3641`, `#3642`, `#3662`, `#3670`) resolved via `gh pr view --json state,title` and `gh issue view --json state,title`. All five GitHub labels (`code-review`, `domain/engineering`, `priority/p2-medium`, `priority/p3-low`, `type/chore`) confirmed via `gh label list --limit 200`. AGENTS.md rule `hr-type-widening-cross-consumer-grep` confirmed active in `AGENTS.core.md`. Vitest `expect.poll` API confirmed in installed `node_modules/vitest/dist/chunks/global.d.MAmajcmJ.d.ts` at `vitest@3.2.4`.

### Key Improvements

1. **Seam-rename scope corrected.** The plan originally claimed `__resetP0DedupForTests` has two call sites (both in `cc-dispatcher.test.ts`). Live grep against `apps/web-platform/` shows **three call sites + one definition**: `cc-dispatcher.test.ts:128 + 155`, `cc-dispatcher-cross-tenant.integration.test.ts:69 + 159`, definition at `observability.ts:314`. The seam rename therefore touches the integration test (a write to a file the plan otherwise leaves untouched per the Research Reconciliation finding). Plan now explicitly carves this out.
2. **F6 reader scope tightened.** Live `grep -nE "typeof m\.usage\.(input_tokens|output_tokens|cost_usd|completed_actions) === ['\"]number['\"]"` against `apps/web-platform/` returns **only 2 matches** — both at `lib/ws-client.ts:1013 + 1016`. The message-bubble.tsx branches use the `usage && typeof usage.input_tokens === "number"` shape (variable-name `usage`, not `m.usage`) at lines 341-346 — also F6 readers, just with a different grep pattern. Plan adopts an **OR-grep over both shapes** as the canonical AC.
3. **Harness consumer set enumerated.** 7 sibling `cc-dispatcher-*.test.ts` files were probed at plan-time for the 6 mock surfaces of cc-dispatcher.test.ts. Result: `cc-dispatcher-cost.test.ts` is the only sibling that mocks ≥ 3 of the same modules (5/6) and is the natural second harness consumer. The other 5 unit-test siblings mock only `@/server/observability` (1/6) and are out-of-scope — migrating them to the harness would be churn without payoff. Integration test (`cross-tenant`) has zero mocks per the existing Research Reconciliation. Plan updates AC-3641-consumers from "≥ 3 mocks overlap" to a concrete list: `cc-dispatcher.test.ts` + `cc-dispatcher-cost.test.ts`.
4. **Vitest expect.poll signature pinned.** Type def at `node_modules/vitest/dist/chunks/global.d.MAmajcmJ.d.ts:63` confirms `poll<T>(actual: () => T, options?: { interval?: number; timeout?: number; message?: string })`. Runtime guards at `@vitest/expect/dist/index.js:1583 + 1617` reject `.resolves` / `.rejects` chaining with `SyntaxError`. Predicate must return a value (not throw). Plan's snippet refined accordingly with options (`{ timeout: 200 }`) so a wall-clock-bounded poll is explicit, not relying on the implicit 1000 ms default.
5. **#3642 op-slug literal sites enumerated.** Live grep returned 9 occurrences across `cc-dispatcher.ts` (5 production sites) + `observability.ts:238` (registry comment) + `cc-dispatcher.test.ts` (3 test-assertion sites). Plan tightens AC-3642-test-callers to enumerate the three test lines (1479, 1487, 1672 + 1674) explicitly.

### New Considerations Discovered

- **Integration-test pull-in for seam rename.** Adding `cc-dispatcher-cross-tenant.integration.test.ts` to `Files to Edit` for the F5 seam rename only. The integration test continues to be untouched for the harness extraction (per the existing Research Reconciliation).
- **`agent-runner.ts:1856` legacy aggregator is NOT a F6 reader.** Live grep returned `const inputDelta = message.usage?.input_tokens ?? 0;` at that line. This is the legacy agent-runner's per-turn cost aggregator, not a reader of the hydrated `Message.usage` — it reads from the SDK message stream, which has a different schema. Plan explicitly scope-outs this site.
- **Vitest 3.2.4 default poll interval is 50ms, default timeout is 1000ms.** Two negative-assertion settles in T-W4-orphan and T-W4-reset-symmetry should bound the wall-clock with `{ timeout: 200 }` to keep the test suite snappy — the negative assertions settle in microtasks today (no real wall-clock cost), so 200 ms is generous headroom.
- **F6 `variant` placement decision crystallized.** Two candidate shapes: (a) top-level `Message.variant`, or (b) nested `usage.variant`. Top-level is simpler for the reader switch but requires every test fixture to add `variant`. Nested keeps fixture surface stable but requires the discriminator field to be set even when `usage` is `null`. Recommendation: **top-level `Message.variant`**, with `variant: "legacy"` as the implicit default for fixtures lacking it (via a helper or by widening the type as `variant?: "legacy" | "cc"` and treating `undefined` as `"legacy"`). Plan captures this in the deepened AC-3640-F6-type.



# refactor: cc-dispatcher cluster drain (PR-A2 review #3639 + #3640 + #3641 + #3642)

## Overview

Drain the four open `code-review` findings filed against `apps/web-platform/server/cc-dispatcher.ts` + `apps/web-platform/server/observability.ts` from PR-A2 (parent #3603) into a single focused refactor PR. All four findings touch the same two files plus their tests; this is the cluster-drain pattern from PR #2486 (one PR, multiple closures) applied to PR-A2's residue.

**Refactor-only.** Zero behavior changes. All 4058 unit tests + the dev integration test must stay green at every phase boundary.

**Closes:** #3639 (F1 + F3 extraction), #3640 (F2 + F4 + F6 discriminated union), #3641 (F5 + drift × 3 + test-design), #3642 (F7 op-slug constants).

**Out of scope:** #3638 (PR-C-coordinated legal/Sentry work). PR-C is now merged (#3662), but #3638 is a separate concern — userId hashing in Sentry payloads + Art. 17 erasure hooks — that does not touch the two cc-dispatcher files in this scope. Stays open for its own cycle.

## Research Reconciliation — Spec vs. Codebase

Three claims in the issue bodies / argument prose required correction against repository state:

| Claim (from arguments) | Reality (verified at plan-time) | Plan response |
| --- | --- | --- |
| **#3640 F6 coordination gate:** "PR-C already touches this column for the Privacy Policy refresh. If PR-C is still open, sequence the F6 migration so it doesn't conflict." | PR-C (#3662) merged 2026-05-12. Its file list contains zero schema files (`docs/legal/*.md`, `plugins/soleur/docs/pages/legal/*.md`, `knowledge-base/legal/audits/*.md`, `knowledge-base/legal/compliance-posture.md`, `knowledge-base/project/plans/2026-05-12-feat-pr-c-legal-refresh-dsar-audit-plan.md`, `knowledge-base/project/specs/feat-cc-transcript-hardening-prc-3603/tasks.md`). **No `messages.variant` column exists in any migration** (`grep -rn "variant" apps/web-platform/supabase/migrations/` confirms). | F6 is **NOT a DB-migration concern**. The `variant` discriminator is a **TypeScript-only widening** on the in-memory `Message` interface, derived at hydration time from `leader_id === CC_ROUTER_LEADER_ID`. No migration, no backfill, no PR-C coordination. F6 lands in this PR. |
| **#3640 F6 readers:** "no `in` checks remaining on `Message.usage` in readers (once F6 lands)" | Current readers (`message-bubble.tsx:332`, `ws-client.ts:1011-1022`) do NOT use `in` checks today — they use `typeof m.usage.input_tokens === "number"` field-typeof checks. | Plan replaces `typeof === "number"` field-presence branching (not `in` literally) with a `variant`-discriminated switch. Acceptance criterion rewritten to match: "no `typeof m.usage.<field> === 'number'` field-presence branches remain on reader paths once F6 lands." |
| **#3641 integration-test harness overlap:** "PR-A2 integration test (~500 lines bespoke harness)" — implied that both unit + integration import the new harness. | `cc-dispatcher-cross-tenant.integration.test.ts` contains **zero `vi.mock` / `vi.hoisted`** calls. It is a real Supabase integration test behind `SUPABASE_DEV_INTEGRATION=1`. There is no mock-harness overlap to deduplicate. | Plan scopes the shared harness extraction to **unit-test consumers only**: `cc-dispatcher.test.ts` plus any other `cc-dispatcher-*.test.ts` files that re-hoist the same mock set (verified at plan-time: `cc-dispatcher-cost.test.ts`, `cc-dispatcher-real-factory.test.ts`, `cc-dispatcher-session-id-writer.test.ts`, `cc-dispatcher-prefill-guard.test.ts`, `cc-dispatcher-concierge-context.test.ts`, `cc-dispatcher-bash-gate.test.ts` are candidates). Integration test stays untouched. |

## Files to Edit

Production:

- `apps/web-platform/server/cc-dispatcher.ts` (#3639 F1 + F3 call-site, #3640 F2 + F4, #3641 type-rail move + seam rename + seam relocation, #3642 F7)
- `apps/web-platform/server/observability.ts` (#3639 F3 extraction site, #3641 seam rename, #3642 registry comment refresh)
- `apps/web-platform/lib/types.ts` (#3640 F6: widen `Message.usage` to discriminated union keyed by `variant`)
- `apps/web-platform/lib/ws-client.ts` (#3640 F6: replace `typeof === "number"` branches with `variant`-discriminated switch at hydration)
- `apps/web-platform/components/chat/message-bubble.tsx` (#3640 F6: replace `typeof === "number"` branches with `variant`-discriminated switch in `renderAbortedAssistant`)
- `apps/web-platform/lib/api-messages.ts` (#3640 F6: at hydration, set `variant = leader_id === CC_ROUTER_LEADER_ID ? "cc" : "legacy"` on every Message row)

Tests:

- `apps/web-platform/test/cc-dispatcher.test.ts` (#3641 all 4 fixes: harness import, seam rename call-site, setTimeout → expect.poll, T-W1-invariant-7 relaxation; #3642 test-assertion sites at lines 1479, 1487, 1672, 1674 migrated to `CC_OP_SLUGS.*`)
- `apps/web-platform/test/cc-dispatcher-cost.test.ts` (#3641 harness consumer — mocks 5/6 of the same modules as cc-dispatcher.test.ts per Phase 1 baseline; second-largest hoist block in the cc-dispatcher-*.test.ts family)
- `apps/web-platform/test/cc-dispatcher-cross-tenant.integration.test.ts` (#3641 **seam rename only** — call sites at lines 69 + 159 import `__resetP0DedupForTests`. NOT a harness consumer per the existing Research Reconciliation; the rename is the only edit. No other behavior touched.)

Out-of-scope tests (verified Phase 1 baselines):

- `cc-dispatcher-bash-gate.test.ts`, `cc-dispatcher-concierge-context.test.ts`, `cc-dispatcher-prefill-guard.test.ts`, `cc-dispatcher-real-factory.test.ts`, `cc-dispatcher-session-id-writer.test.ts` — each mocks only `@/server/observability` (1/6 overlap), so harness migration would be churn. Stay on bespoke hoists.

## Files to Create

- `apps/web-platform/test/helpers/cc-dispatcher-harness.ts` (#3641 shared unit-test mock factory)

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each body for the planned file paths.

Matches against `apps/web-platform/server/cc-dispatcher.ts`:

- **#3638** — "review: hash userId in Sentry mirror payload + Art. 17 erasure hooks for breach-attempt events (#3603 PR-A2 H6/H7)". **Disposition: acknowledge.** #3638 is intentionally out of this batch per the argument block. It's a separate concern (userId hashing in Sentry payloads + erasure hooks) that intersects observability boundaries but does not require re-touching the structural refactors in this PR. Stays open; will be re-drained after this PR merges if the file overlap surfaces during ship.
- **#3639, #3640, #3641, #3642** — these are the four issues being closed by this PR. Fold in (this is the PR itself).

No other open `code-review` issues match these file paths.

## User-Brand Impact

**If this lands broken, the user experiences:**
A broken cc-soleur-go chat reload — assistant transcripts fail to render, or render with `NaN tokens` on aborted-row hydration (F6 reader regression), or duplicate/missing assistant rows (F1 reset-symmetry regression). User-facing artifact: the cc-soleur-go chat thread on `/dashboard/chat` and the KB-Concierge sidebar.

**If this leaks, the user's data is exposed via:**
Not applicable. This PR is a structural refactor — no new persistence sites, no new RLS surfaces, no new wire shapes. The cross-tenant write-boundary sentinel (`assertWriteScope`) and the RLS + FK chain remain unchanged. Any drift on those would surface in the existing `cc-dispatcher-cross-tenant.integration.test.ts` matrix.

**Brand-survival threshold:** **aggregate pattern.** Refactor-only on internal server code; the brand-survival surface (cross-tenant transcript leak, transcript loss on abort) was framed and signed off in PR-A2 (#3603 `single-user incident` threshold). This drain inherits that threshold for the *underlying* invariants but the *structural changes* in this PR are aggregate-quality (code smell, drift potential, test maintainability). No per-PR sign-off required. CPO sign-off carry-forward is via the PR-A2 brainstorm + the unchanged W1/W2/W3/W4 invariants.

## Acceptance Criteria

### Pre-merge (PR)

#### Common

- **AC-Common-1:** All 4058 unit tests pass via `bun test` from `apps/web-platform/`. Zero new test files; zero new test cases not paired with a closed issue.
- **AC-Common-2:** `bun run typecheck` (or `tsc --noEmit`) passes. No `// @ts-ignore` / `// @ts-expect-error` additions on the touched files.
- **AC-Common-3:** PR body contains literal lines `Closes #3639`, `Closes #3640`, `Closes #3641`, `Closes #3642` (one per line). Pattern referenced: PR #2486 cluster-drain pattern.
- **AC-Common-4:** No behavior change visible to end-users on `/dashboard/chat`. Operator verification: open a cc-router thread, exchange 3+ messages, reload tab, confirm both bubbles render from DB; trigger a Stop mid-turn, reload, confirm the abort row renders with its `usage` chip if `CC_PERSIST_USAGE=true`.

#### #3639 — TurnPersistenceState + TtlDedupMap

- **AC-3639-F1:** `dispatchSoleurGo` no longer holds the four mutable per-turn cells in lexical scope. They are private fields of a `TurnPersistenceState` class instantiated once per `dispatchSoleurGo` invocation. Verified by `grep -n "let latestAssistantText\|let assistantTurnPersisted\|let currentTurnIndex\|let pendingTurnUsage" apps/web-platform/server/cc-dispatcher.ts` returning zero matches.
- **AC-3639-F1-methods:** The class exposes exactly the methods named in the issue body — `captureUsage(idx, cost)`, `snapshotAndBumpTurn()`, `flushAbort(end)`, `flushComplete()` — and a `reset()` that clears all four fields. Reset-symmetry is asserted by `T-W4-reset-symmetry` (modified to call the class method directly rather than poke closure state).
- **AC-3639-F3:** `class TtlDedupMap<K extends string>(ttlMs, sweepInterval, maxSize?)` exists in `observability.ts` exposing `tryClaim(key, now): boolean` and `reset()`. Optional `maxSize` for insertion-order eviction (used by P0 dedup; debounce dedup omits it to match current behavior).
- **AC-3639-F3-wrappers:** `mirrorWithDebounce` body is ≤ 12 LoC (selecting key + sink), `mirrorP0Deduped` body is ≤ 20 LoC (key + Pino + Sentry sinks; the level + payload shaping is the irreducible part). Both internally delegate to a `TtlDedupMap` instance.
- **AC-3639-test-wrapper:** `cc-dispatcher.test.ts`'s in-file TTL re-implementation at lines ~49-59 is replaced by `new TtlDedupMap(MIRROR_DEBOUNCE_MS, Infinity)` constructed from the imported real class.

#### #3640 — PersistMode + Message.usage variant

- **AC-3640-F2:** `AssistantPersistMode = "complete" | "aborted"` and the `AssistantPersistOpts` interface are deleted. Replaced by `type PersistMode = { kind: "complete"; usage: { costUsd: number } | null } | { kind: "aborted"; usage: { costUsd: number } | null }`. `saveAssistantMessage` signature is `(mode: PersistMode) => Promise<void>`.
- **AC-3640-F4:** `saveAssistantMessage` orchestrator body is ≤ 20 LoC. Two helpers extracted at module scope: `buildRow(mode, text, conversationId)` and `mirrorInsertError(error, mode, userId, conversationId, fullText)`. Switch over `mode.kind` is exhaustive — exhaustiveness rail (`const _exhaustive: never = mode`) added.
- **AC-3640-F6-type:** Top-level `Message.variant: "legacy" | "cc"` (recommended shape per deepen-plan analysis — nested-on-usage discriminator requires the field to exist when `usage` is `null`, breaking the test-fixture-stable invariant). Field is **required** in the final shape but the migration tactic is `variant?: "legacy" | "cc"` to allow fixtures to omit it (readers default `undefined` to `"legacy"` — backward-compatible against the existing test-fixture corpus). If deepen-plan or work-time agents find a cleaner shape, document the rationale in a Risks subsection.
- **AC-3640-F6-hydration:** `apps/web-platform/lib/api-messages.ts` sets `variant = row.leader_id === CC_ROUTER_LEADER_ID ? "cc" : "legacy"` on every Message it returns. No new DB column. Verified by `grep -n "variant" apps/web-platform/lib/api-messages.ts` showing the assignment + a comment pinning the derivation rule (cites `cc-router-id.ts` and migration 040).
- **AC-3640-F6-readers:** Two complementary greps return zero matches after the change:
  - `grep -nE "typeof m\.usage\.(input_tokens|output_tokens|cost_usd|completed_actions) === ['\"]number['\"]" apps/web-platform/{lib,components,server}/` (baseline: 2 hits at `lib/ws-client.ts:1013 + 1016`).
  - `grep -nE "typeof usage\.(input_tokens|output_tokens|cost_usd|completed_actions) === ['\"]number['\"]" apps/web-platform/{lib,components,server}/` (baseline: 3 hits at `components/chat/message-bubble.tsx:341 + 342 + 346`).
  - All reader branches use `m.variant === "cc"` / `m.variant === "legacy"` (or the helper-typed `usage.variant` if the deepen-plan recommendation is overridden in favor of nested discriminator).
  - **Scope-out:** `apps/web-platform/server/agent-runner.ts:1856` (`message.usage?.input_tokens ?? 0`) is the legacy SDK-message aggregator, NOT a reader of the hydrated `Message.usage`. Out of F6 scope.

#### #3641 — shared harness + expect.poll + seam renames

- **AC-3641-harness:** `apps/web-platform/test/helpers/cc-dispatcher-harness.ts` exists exporting `buildDispatcherMocks({ withRealMirror?: boolean, withRealP0?: boolean })`. The returned object exposes named spies (`mockReportSilentFallback`, `mockMessagesInsert`, `mockMirrorP0Deduped`, etc.) plus a `vi.mock`-compatible factory closure that callers wire via `vi.mock("@/server/observability", () => factory())`.
- **AC-3641-consumers:** Two unit-test files import the harness post-Phase 1 enumeration: `cc-dispatcher.test.ts` (7-mock hoist block today, full match) AND `cc-dispatcher-cost.test.ts` (5/6 mock surfaces overlap). All five other `cc-dispatcher-*.test.ts` siblings mock only `@/server/observability` (1/6 overlap) and stay on bespoke hoists — migrating them would be churn without payoff. Integration test (`cross-tenant`) stays untouched per the existing Research Reconciliation row.
- **AC-3641-seam-rename:** `__resetP0DedupForTests` → `__resetMirrorP0DedupForTests` in `observability.ts:314`. Updated at all three call sites enumerated by Phase 1 grep: `cc-dispatcher.test.ts:128 + 155` AND `cc-dispatcher-cross-tenant.integration.test.ts:69 + 159`. Old name deleted (no alias) — refactor-only PR, no deprecation period needed. The integration-test edit is scoped strictly to the rename (no other behavioral change in that file).
- **AC-3641-type-rail-move:** `PersistMode` (post-#3640 rename) lives at module scope in `cc-dispatcher.ts` adjacent to `ABORT_FLUSH_STATUSES` (around line 137), NOT inside `dispatchSoleurGo`. Verified by `grep -n "^type PersistMode" apps/web-platform/server/cc-dispatcher.ts` returning a top-level match.
- **AC-3641-seam-relocation:** `__setAssertWriteScopeForTests` + `__resetAssertWriteScopeForTests` move from lines ~195-230 to the existing bottom-of-file test-seam block (current location of `__resetDispatcherForTests`, `__resetCcPersistUsageObservationForTests`).
- **AC-3641-no-settle-timeouts:** `grep -nE "setTimeout\([^,]+, *[0-9]+\)" apps/web-platform/test/cc-dispatcher.test.ts` returns zero matches. The two negative-assertion settles in `T-W4-orphan` and `T-W4-reset-symmetry` use `await expect.poll(() => fn(), { interval: 5, timeout: 200 }).toBe(...)`. **Vitest 3.2.4 API constraints (verified at `node_modules/vitest/dist/chunks/global.d.MAmajcmJ.d.ts:63`):**
  - Predicate must return a value; throwing in the predicate aborts the poll.
  - `.resolves` / `.rejects` chaining is not supported (`@vitest/expect/dist/index.js:1583 + 1617`).
  - Defaults: `interval=50ms`, `timeout=1000ms`. Plan tightens both: `interval=5ms` (microtask-fast settle), `timeout=200ms` (generous wall-clock cap for a negative assertion that ought to settle within microtasks).
- **AC-3641-T-W1-invariant-7:** Test `T-W1-invariant-7` uses `expect(scopeSpy).toHaveBeenCalledTimes(n)` with `n >= 3` (not `=== 3`) AND retains the `expect(call).toEqual([userId, conversationId])` loop as the load-bearing assertion. The class method now wraps the previous three call sites (user-INSERT + complete + aborted) and may emit additional internal calls.

#### #3642 — op-slug constants

- **AC-3642-constants:** Module-scope `const CC_OP_SLUGS = { saveAssistant: "save-assistant-message-failed", saveAssistantAborted: "save-assistant-message-aborted-failed", usageOrphanDropped: "usage_orphan_dropped", ccPersistUsageOn: "cc-persist-usage-on", persistUserMessage: "persist-user-message" } as const;` lives at the top of `cc-dispatcher.ts` (adjacent to `ABORT_FLUSH_STATUSES` and the post-#3641 module-scope `PersistMode`).
- **AC-3642-w4-orphan:** The W4 orphan branch uses `new Error(CC_OP_SLUGS.usageOrphanDropped)` AND `op: CC_OP_SLUGS.usageOrphanDropped` so the Error message and `ctx.op` cannot drift.
- **AC-3642-no-literals:** `grep -E "\"(save-assistant-message-failed|save-assistant-message-aborted-failed|usage_orphan_dropped|cc-persist-usage-on|persist-user-message)\"" apps/web-platform/server/cc-dispatcher.ts` returns zero matches (the constants in `CC_OP_SLUGS` are the single source).
- **AC-3642-test-callers:** Four test-assertion sites in `cc-dispatcher.test.ts` (lines 1479, 1487, 1672, 1674 per Phase 1 grep — `mirrorCallsForOp(..., "save-assistant-message-failed")` × 2 and `expect((errArg as Error)?.message).toBe("usage_orphan_dropped")` + `op: "usage_orphan_dropped"` ctx assertion) MUST reference the same imported `CC_OP_SLUGS.*` rather than re-typing the string literal — otherwise the test could pass against a renamed slug while production silently drifts. The `it(...)` description strings at lines 1442 and 1634 may keep human-readable slug names (they document intent, not coupling).
- **AC-3642-registry-comment:** `observability.ts:161-170` registry comment is updated to reference `CC_OP_SLUGS.*` instead of free-text slug examples.

### Post-merge (operator)

None. This PR is refactor-only; no migrations, no flags, no operator actions. `gh issue list --label code-review --state open` count drops by exactly four (#3639, #3640, #3641, #3642 transition to CLOSED via the `Closes #N` PR-body trailers).

## Implementation Phases

**Sequencing rationale:** #3640 F2/F4 must precede #3641's type-rail move (the renamed type is what gets relocated). #3639 F3 (TtlDedupMap) must precede the test-harness TTL-wrapper consolidation. #3639 F1 (TurnPersistenceState) must land in the same PR as the #3641 T-W1-invariant-7 relaxation (the class wraps the three call sites). #3642 F7 (op-slug constants) is independent; sequenced last so it can adopt the post-rename names in one pass.

### Phase 1 — Plan-time greps + harness consumer scoping

**Baselines captured at deepen-plan (2026-05-12). Re-run before opening the PR for the "before" column. Expected values below; deviation → halt and reconcile.**

- [ ] `grep -rn "__resetP0DedupForTests" apps/web-platform/` — **expected: 5 hits** (definition at `observability.ts:314`; consumers at `cc-dispatcher.test.ts:128 + 155` and `cc-dispatcher-cross-tenant.integration.test.ts:69 + 159`).
- [ ] `for f in apps/web-platform/test/cc-dispatcher-*.test.ts; do printf "%s\n  hoist: %s\n  vi.mock(observability): %s\n  vi.mock(supabase): %s\n  vi.mock(cost-writer): %s\n  vi.mock(kb-document-resolver): %s\n  vi.mock(conversation-writer): %s\n" "$(basename "$f")" "$(grep -c "vi\.hoisted" "$f")" "$(grep -c "vi\.mock(\"@/server/observability\"" "$f")" "$(grep -c "vi\.mock(\"@/lib/supabase/service\"" "$f")" "$(grep -c "vi\.mock(\"@/server/cost-writer\"" "$f")" "$(grep -c "vi\.mock(\"@/server/kb-document-resolver\"" "$f")" "$(grep -c "vi\.mock(\"@/server/conversation-writer\"" "$f")"; done` — **expected: cc-dispatcher.test.ts (7/6 hoist + all 6 mocks); cc-dispatcher-cost.test.ts (1/1 hoist + 5/6 mocks); 5 other siblings (≤ 2/6 mocks); integration test (0 hoists, 0 mocks).**
- [ ] `grep -rnE "\\b(save-assistant-message-failed|save-assistant-message-aborted-failed|usage_orphan_dropped|cc-persist-usage-on|persist-user-message)\\b" apps/web-platform/` — **expected: 9 hits** (5 production sites in `cc-dispatcher.ts:236, 1074, 1214, 1215, 1341, 1342`; 1 doc-comment site in `observability.ts:238`; 3 test-assertion sites in `cc-dispatcher.test.ts:1479, 1487, 1672, 1674` — 4 individual matches but 3 distinct slugs).
- [ ] `grep -rnE "typeof m\\.usage\\.(input_tokens|output_tokens|cost_usd|completed_actions) === ['\"]number['\"]" apps/web-platform/{lib,components,server}/` — **expected: 2 hits** (`ws-client.ts:1013 + 1016`). Plus `grep -rnE "typeof usage\\.(input_tokens|output_tokens|cost_usd|completed_actions) === ['\"]number['\"]" apps/web-platform/{lib,components,server}/` — **expected: 3 hits** (`message-bubble.tsx:341 + 342 + 346`). Combined baseline: **5 reader sites**, must reach 0 post-Phase 5.
- [ ] `grep -nE "setTimeout\\([^,]+, *[0-9]+\\)" apps/web-platform/test/cc-dispatcher.test.ts` — **expected: 2 hits** (T-W4-orphan + T-W4-reset-symmetry settles). Must reach 0 post-Phase 7.
- [ ] Record the baselines in the PR body as a "before" table.

### Phase 2 — #3642 F7 op-slug constants (independent, lands first to feed downstream phases)

- [x] Add `const CC_OP_SLUGS = { ... } as const;` at the top of `apps/web-platform/server/cc-dispatcher.ts` (after `ABORT_FLUSH_STATUSES`).
- [x] Replace every inline slug literal in `cc-dispatcher.ts` (5 call sites identified by Phase 1 grep) with `CC_OP_SLUGS.<key>`. Includes:
  - `saveAssistantMessage` — `opSlug` ternary at ~1213.
  - W4 orphan — `new Error(...)` at ~1341 + `op: ...` at ~1342.
  - `_observeCcPersistUsageFirstTrue` — `op: "cc-persist-usage-on"` at ~236.
  - User-INSERT failure mirror — `op: "persist-user-message"` at ~1074.
- [x] Update `observability.ts` registry comment (lines 161-170) to reference `CC_OP_SLUGS.*` rather than free-text examples.
- [x] Update test-file references to import + use `CC_OP_SLUGS.saveAssistant` / `CC_OP_SLUGS.usageOrphanDropped` in lieu of literals.
- [x] Run unit tests. Expected: green (string-identical post-substitution).
- [x] Commit: `refactor(cc-dispatcher): hoist op-slug literals to CC_OP_SLUGS — closes #3642 (F7)`.

### Phase 3 — #3639 F3 TtlDedupMap extraction

- [x] Add `class TtlDedupMap<K extends string>` to `observability.ts`. Generic over key type; constructor `(ttlMs: number, sweepInterval: number, maxSize?: number)`. Methods: `tryClaim(key: K, now: number): boolean` (returns `true` if claimed = first call within TTL, `false` if deduped), `reset(): void`. Internal `Map<K, number>` + write counter + amortized sweep mirroring current `mirrorWithDebounce` / `mirrorP0Deduped` semantics. Insertion-order eviction when `maxSize` is set (matches current P0 behavior).
- [x] Refactor `mirrorWithDebounce` body to `if (!_mirrorDebounce.tryClaim(key, now)) return; reportSilentFallback(err, ctx);` — body ≤ 12 LoC. Construct one module-scope `_mirrorDebounce = new TtlDedupMap<string>(MIRROR_DEBOUNCE_MS, MIRROR_SWEEP_INTERVAL)`.
- [x] Refactor `mirrorP0Deduped` body to use `_p0Dedup = new TtlDedupMap<string>(P0_DEDUP_TTL_MS, P0_SWEEP_INTERVAL, P0_DEDUP_MAX_SIZE)`. Pino + Sentry emit stay as-is (the irreducible level + payload shaping per AC-3639-F3-wrappers).
- [x] Update `__resetMirrorDebounceForTests` + (still-named) `__resetP0DedupForTests` to call `instance.reset()` instead of poking the old `Map` directly.
- [x] In `cc-dispatcher.test.ts`, delete the inline TTL re-implementation (lines ~49-59). Import `TtlDedupMap` + `MIRROR_DEBOUNCE_MS` and construct one instance in the `mirrorWithDebounce` mock factory. The 3-call-→-1-mirror assertion stays in lockstep with production automatically.
- [x] Run unit tests + `observability-mirror-debounce.test.ts`. Expected: green.
- [x] Commit: `refactor(observability): extract TtlDedupMap, drop inline test re-impl — partial #3639 (F3)`.

### Phase 4 — #3640 F2 + F4 discriminated PersistMode + helper extraction

- [x] Replace the `dispatchSoleurGo`-local `AssistantPersistMode` + `AssistantPersistOpts` with a module-scope `type PersistMode = { kind: "complete"; usage: { costUsd: number } | null } | { kind: "aborted"; usage: { costUsd: number } | null }`. Place adjacent to `ABORT_FLUSH_STATUSES` for #3641 type-rail move (Phase 6 below verifies placement).
- [x] Rewrite `saveAssistantMessage` signature to `async function saveAssistantMessage(mode: PersistMode): Promise<void>`.
- [x] Extract `buildRow(mode: PersistMode, text: string, conversationId: string): Record<string, unknown>` at module scope. Encodes the `status` + `usage` shaping per `mode.kind`.
- [x] Extract `mirrorInsertError(error: unknown, mode: PersistMode, userId: string, conversationId: string, fullText: string): void` at module scope. Routes through `mirrorWithDebounce` with the slug picked by `switch (mode.kind)`.
- [x] Body of `saveAssistantMessage` becomes ≤ 20 LoC: write-boundary check → snapshot accumulator → flag read → `const row = buildRow(...)` → `await insert(row)` → on error `mirrorInsertError(...)`.
- [x] Add exhaustiveness rail: `const _exhaustive: never = mode;` after the switch (compile-time pin against future `PersistMode` variants like `"timed_out"`).
- [x] Update the two call sites in `onTextTurnEnd` (~1283) and `onWorkflowEnded` (~1329) to pass `{ kind: "complete", usage: ... }` / `{ kind: "aborted", usage: ... }`.
- [x] Run unit tests. Expected: green.
- [x] Commit: `refactor(cc-dispatcher): discriminated PersistMode + buildRow/mirrorInsertError helpers — partial #3640 (F2 + F4)`.

### Phase 5 — #3640 F6 Message.usage variant union

- [ ] Widen `Message` in `apps/web-platform/lib/types.ts:412` with `variant?: "legacy" | "cc"` (optional during transition; readers default `undefined` → `"legacy"` for fixture-stable backward compatibility). Discriminator lives at the **top level on `Message`**, not nested on `usage` (deepen-plan recommendation: nested would require the discriminator when `usage` is `null`, breaking fixture stability). Rough shape:
  ```ts
  export interface Message {
    // ...existing fields...
    /** #3640 F6 — discriminates usage shape. Derived at hydration from
     *  `leader_id === CC_ROUTER_LEADER_ID` per `cc-router-id.ts`. Persisted
     *  rows have no `variant` column; this is a TS-only widening.
     *  Optional during the F6 transition window — readers treat
     *  `undefined` as `"legacy"` so existing test fixtures don't churn. */
    variant?: "legacy" | "cc";
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cost_usd?: number | null;
      completed_actions?: Array<{
        tool_name: string;
        input_summary: string;
        result_summary: string;
      }>;
    } | null;
  }
  ```
  The `usage` shape itself is unchanged at the type level (legacy fields stay optional). The discriminator-driven reader switch is what enforces the narrowing — `m.variant === "cc"` readers must only access `usage.cost_usd`; `m.variant === "legacy"` (default) readers may access the full snapshot.
- [ ] Update `lib/api-messages.ts` hydration to derive `variant = row.leader_id === CC_ROUTER_LEADER_ID ? "cc" : "legacy"` and assign on every row. Cite migration 040 + `cc-router-id.ts` in a header comment.
- [ ] Rewrite `ws-client.ts:1010-1025` `usage:` ternary to switch on `m.variant`. Legacy branch keeps the existing field passthrough; cc branch keeps only `cost_usd`.
- [ ] Rewrite `message-bubble.tsx:330-350` `renderAbortedAssistant` token-sum + cost-label logic to switch on `usage.variant`. Legacy computes `input_tokens + output_tokens`; cc skips token sum (returns `null`, which already renders gracefully).
- [ ] Run `bun run typecheck`. Every consumer that broke is added to the `Files to Edit` list inline (per `hr-type-widening-cross-consumer-grep`).
- [ ] Run unit tests. Expected: green (the on-the-wire shape didn't change — only the in-memory branch shape).
- [ ] Commit: `refactor(types): discriminate Message.usage by variant — closes #3640 (F2 + F4 + F6)`.

### Phase 6 — #3639 F1 TurnPersistenceState + #3641 T-W1-invariant-7 relaxation (paired)

- [ ] Add `class TurnPersistenceState` at module scope in `cc-dispatcher.ts` (adjacent to `ABORT_FLUSH_STATUSES`). Private fields: `accumulatedAssistantText: string`, `workflowEnded: boolean`, `currentTurnIndex: number`, `pendingTurnUsage: { turnIndex: number; costUsd: number } | null`.
- [ ] Public methods (issue body verbatim):
  - `captureUsage(idx: number, costUsd: number): void` — sets `pendingTurnUsage` tagged with `idx`.
  - `snapshotAndBumpTurn(): { text: string; usage: { costUsd: number } | null }` — used by `onTextTurnEnd` complete path. Returns `text` + matched usage; clears `accumulatedAssistantText`; clears `pendingTurnUsage`; bumps `currentTurnIndex`.
  - `flushAbort(end: WorkflowEnd): { text: string; usage: { costUsd: number } | null } | { orphanedUsage: true } | null` — used by `onWorkflowEnded`. Three branches: text present (return `{ text, usage }` + sets `workflowEnded = true`); text absent + usage pending (return `{ orphanedUsage: true }`, caller fires P0 mirror); neither (return `null`).
  - `flushComplete(): boolean` — returns `workflowEnded` so the late-`onTextTurnEnd` no-op stays explicit.
  - `appendText(text: string): void` — replace (per W8 REPLACE semantic at chat-state-machine.ts:477). Single-writer for the `accumulatedAssistantText` cell.
  - `reset(): void` — clears all four fields. Reset-symmetry is a class invariant (asserted by the modified `T-W4-reset-symmetry`).
- [ ] Replace the four `let` declarations (lines 1136-1150) with `const state = new TurnPersistenceState();`. Rewrite `onText`, `onTextTurnEnd`, `onWorkflowEnded`, `onResult` to call class methods.
- [ ] In `cc-dispatcher.test.ts`, `T-W1-invariant-7`: relax `expect(scopeSpy).toHaveBeenCalledTimes(3)` → `expect(scopeSpy.mock.calls.length).toBeGreaterThanOrEqual(3)`. Keep the per-call argument-equality loop as the load-bearing assertion. Comment cites #3639 F1 as the rationale.
- [ ] Run unit tests. Expected: green. If `T-W4-reset-symmetry` breaks because it pokes closure state directly, port it to call `state.reset()` and assert against the public `flushComplete()` accessor (or add a `__getStateForTests()` seam to the bottom-of-file block).
- [ ] Commit: `refactor(cc-dispatcher): extract TurnPersistenceState + relax T-W1-invariant-7 — closes #3639 (F1 + F3)`.

### Phase 7 — #3641 shared harness + seam rename + seam relocation + expect.poll

- [ ] Author `apps/web-platform/test/helpers/cc-dispatcher-harness.ts` exporting `buildDispatcherMocks({ withRealMirror = false, withRealP0 = false } = {})`. Returns an object with named spies + a `mocks` block suitable for `vi.mock("@/server/observability", () => ...)`. Use the existing `cc-dispatcher.test.ts` hoist block as the template; the harness function is invoked inside the caller's `vi.hoisted(...)` because `vi.mock` is hoisted at parse time.
  - **Important:** because `vi.hoisted` runs synchronously before the rest of the module, the harness must export a builder function that the caller calls *inside* its own `vi.hoisted(() => buildDispatcherMocks(...))` block. The harness itself does not call `vi.hoisted`; it provides the factory the hoist returns.
- [ ] Migrate `cc-dispatcher.test.ts` to use the harness. Replace the 7 hoisted mocks at top + the inline TTL wrapper (already removed in Phase 3). Verify the file shrinks by ~80 LoC.
- [ ] Migrate `cc-dispatcher-cost.test.ts` to use the harness (5/6 mock overlap per Phase 1 baseline). All five other `cc-dispatcher-*.test.ts` siblings stay on bespoke hoists (1/6 overlap each — not worth churning).
- [ ] Rename `__resetP0DedupForTests` → `__resetMirrorP0DedupForTests` in `observability.ts:314`. Update all three call sites: `cc-dispatcher.test.ts:128 + 155` AND `cc-dispatcher-cross-tenant.integration.test.ts:69 + 159`. The integration-test edit is **rename-only** (zero other behavioral changes) — preserves the Research Reconciliation's "integration test stays untouched for harness extraction" claim.
- [ ] Move `__setAssertWriteScopeForTests` + `__resetAssertWriteScopeForTests` from `cc-dispatcher.ts:202 + 218` to the existing bottom-of-file test-seam block (location of `__resetDispatcherForTests`, `__resetCcPersistUsageObservationForTests`). The relocation is a verbatim move — no signature change.
- [ ] Replace the two `setTimeout(_, 10)` settles in `T-W4-orphan` and `T-W4-reset-symmetry`:
  ```ts
  // before (existing pattern at T-W4-orphan + T-W4-reset-symmetry):
  await new Promise((r) => setTimeout(r, 10));
  expect(mockMessagesInsert).not.toHaveBeenCalled();
  // after (vitest 3.2.4 expect.poll, signature verified at
  //  node_modules/vitest/dist/chunks/global.d.MAmajcmJ.d.ts:63):
  await expect
    .poll(() => mockMessagesInsert.mock.calls.length, { interval: 5, timeout: 200 })
    .toBe(0);
  // Constraints:
  //  - Predicate MUST return a value (throwing aborts the poll).
  //  - `.resolves` / `.rejects` are unsupported (@vitest/expect:1583,1617).
  //  - Defaults: interval=50ms, timeout=1000ms. Tightened to interval=5ms
  //    (microtask-fast settle) + timeout=200ms (generous wall-clock cap).
  ```
- [ ] Verify `grep -nE "setTimeout\([^,]+, *[0-9]+\)" apps/web-platform/test/cc-dispatcher.test.ts` returns zero matches.
- [ ] Run unit tests. Expected: green.
- [ ] Commit: `refactor(test): shared cc-dispatcher harness + expect.poll + seam renames — closes #3641 (F5 + drift × 3 + test-design)`.

### Phase 8 — Verification + PR-body refresh

- [ ] Run `bun test` from `apps/web-platform/`. Expected: 4058 passes (baseline preserved).
- [ ] Run `bun run typecheck`. Expected: clean.
- [ ] Optionally run `SUPABASE_DEV_INTEGRATION=1 doppler run -p soleur -c dev -- bun test test/cc-dispatcher-cross-tenant.integration.test.ts` if Doppler dev creds are available. Expected: green (no production changes to the integration test's invariants).
- [ ] Replay the Phase 1 baseline greps to fill in the PR body "after" column.
- [ ] Rewrite the PR body (currently auto-generated WIP placeholder) with: Summary, Closes block (`Closes #3639` × 4), per-issue resolution table mapping AC → commit SHA, "before/after" grep table, mention of PR #2486 as the cluster-drain precedent, test plan checklist.
- [ ] Mark PR ready for review.

## Risks

- **F6 cross-consumer blast radius.** Widening `Message` is type-level — `hr-type-widening-cross-consumer-grep` applies. Phase 5 includes a `bun run typecheck` step explicitly to enumerate every consumer that breaks. Likely candidates beyond the named ones: any test fixture that constructs a literal `Message` object (sidebars, recents, mock conversation rows). Mitigation: every `Files to Edit` addition surfaced by `tsc` is added inline in Phase 5; the commit doesn't ship until typecheck is clean.
- **F1 reset-symmetry regression.** The class invariant subsumes a previously-implicit guarantee that the four `let` cells move together. Risk: a method that mutates only 3 of 4 fields silently breaks `T-W4-reset-symmetry`. Mitigation: `reset()` is the only path that touches all four; every mutator method is paired with a one-line invariant comment in code.
- **#3641 harness builder + vi.hoisted ordering.** `vi.hoisted(fn)` is hoisted ABOVE module imports. The harness file is itself a module; importing it requires the import to be parsed before the hoist runs. Vitest handles this by treating `vi.hoisted` as a special form, but the harness must NOT itself call `vi.hoisted` — only export a plain function the caller invokes inside its own hoist block. Mitigation: this is captured explicitly in Phase 7's bullet; if vitest complains, the fallback is to inline the factory's body into the test file's hoist call (one `import { buildDispatcherMocks } from ...` + one call returning the mocks).
- **#3642 test-caller drift.** If the test file's string-literal assertions on slugs aren't migrated to `CC_OP_SLUGS.*`, a future slug rename would pass the test (literal stays in the test) while production silently emits the new value. Mitigation: AC-3642-test-callers explicitly requires the migration.
- **Refactor-only invariant.** Every commit in this PR must leave the test suite green. Any commit that needs to break a test is a behavior change in disguise — abort and re-scope. Phase boundaries are commit boundaries.
- **F6 `variant` field placement (top-level vs. nested-on-usage).** Deepen-plan recommends top-level `Message.variant?: "legacy" | "cc"` with `undefined → "legacy"` default for fixture stability. Alternative (nested `usage.variant`) requires the discriminator field to exist when `usage` is `null`, which would force every test fixture to either set `usage: null` to `usage: { variant: "legacy" }` (changing semantics) or be widened with a helper. The chosen shape is the lower-churn option, but `tsc --noEmit` in Phase 5 may surface consumer call-sites that exercise narrow types and prefer the nested shape. Decision rule: if Phase 5's typecheck diff exceeds ~30 LoC of consumer-side widening, escalate to a brainstorm-class re-evaluation rather than push through.
- **Seam-rename touches integration test.** The `__resetP0DedupForTests` → `__resetMirrorP0DedupForTests` rename touches `cc-dispatcher-cross-tenant.integration.test.ts:69 + 159` even though the harness extraction does NOT. This is a deliberate scope creep of 2 lines in the integration test — verified at deepen-plan to be a verbatim find-and-replace with no test-logic impact. If a future deepen-plan or work-time agent thinks the integration test should adopt the harness, file a separate issue rather than expanding this PR.

## Test Strategy

No new test files. No new test cases. All four findings are refactor-only; existing tests already pin the behavior the refactor preserves. The plan's only test edits are:

- `cc-dispatcher.test.ts`: setTimeout → expect.poll (× 2), `T-W1-invariant-7` relaxation, harness import, seam rename call-site, inline TTL-wrapper deletion.
- Sibling `cc-dispatcher-*.test.ts` files (per Phase 1 enumeration): harness import migration where applicable.

The integration test `cc-dispatcher-cross-tenant.integration.test.ts` is read-only in this PR (per the Research Reconciliation finding above).

## Domain Review

**Domains relevant:** none beyond Engineering.

This is a refactor-only PR against internal server code (cc-soleur-go dispatcher + observability + types). No new persistence sites, no new wire shapes, no new user-facing surfaces, no schema changes, no auth/RLS edits, no external service contracts, no legal/marketing copy. The Engineering surface (CTO) is the only stakeholder; the existing PR-A2 brainstorm + CPO/CLO/CTO sign-off for the underlying invariants carries forward unchanged.

Product/UX Gate: **NONE.** No user-facing surface changes; brand-survival threshold downgraded to `aggregate pattern` per the User-Brand Impact section.

GDPR / Compliance Gate: skipped per `/soleur:gdpr-gate` canonical regex — touched files do not include `apps/web-platform/supabase/migrations/`, `*.sql`, `apps/web-platform/app/api/`, or any auth-flow surface. The four (a)-(d) widening triggers also do not fire:
- (a) No new LLM/external-API processing.
- (b) Brand-survival threshold is `aggregate pattern`, not `single-user incident`.
- (c) No new cron/workflow reading from `knowledge-base/`.
- (d) No new artifact distribution surface.

## Sharp Edges

- **`vi.hoisted` + harness builder ordering.** Captured in Risks above. If the test-time import order causes a "cannot access X before initialization" error, fall back to inlining the factory body — do NOT call `vi.hoisted` inside the harness module.
- **Type-rail move order (Phase 4 → Phase 6).** `PersistMode` is renamed (#3640 F2) before it is moved to module scope (#3641 type-rail). Phase 4 places the renamed type module-scope already; Phase 6 + Phase 7 are no-ops for the placement.
- **F6 `variant` derivation is hydration-only.** Never persist a `variant` column. The discriminator is computed from `leader_id` at hydration in `api-messages.ts` (and at construction time for newly-built `Message` instances). A schema column would require a backfill + a PR-C coordination cycle, both unnecessary.
- **Test seam rename has no deprecation period.** `__resetP0DedupForTests` is deleted (not aliased) by Phase 7. Any out-of-tree consumer (skill, hook, plugin) that imports it will break at typecheck time. Plan-time grep (Phase 1) limits scope to the in-tree call sites; if a future plugin reference appears it must update at the same SHA.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is populated above; fill any deepen-plan-introduced subsections before requesting `/work`. Verified at deepen-plan: section present, threshold `aggregate pattern`, non-empty body — gate passes.
- **Vitest `expect.poll` predicate-throw semantics.** A predicate that throws (e.g., `mockMessagesInsert.mock.calls[0][0].id`) when the array is empty aborts the poll — not the same as "predicate returned a non-matching value". The negative-assertion replacements (`mock.calls.length === 0`) cannot throw, so this is safe; but if a future test asserts on a property of the first call, gate the predicate with a length check or use `mock.calls.length === N && mock.calls[0][0].id === EXPECTED` instead of indexing first.
- **`vi.mock` factory-import constraint.** `vi.mock` is hoisted ABOVE module imports. The harness file's top-level `import { ... } from "vitest"` is fine because the harness is a module the test imports; vitest's hoist rewriter handles this correctly as long as the harness itself does NOT call `vi.hoisted`. If a future contributor adds `vi.hoisted` inside the harness, the consumer test will fail with "cannot access X before initialization" — the harness must remain a pure factory module.

## References

- Parent issue: #3603 (PR-A2 transcript-persistence hardening).
- Predecessor PR-A2: merged 2026-05-12 09:41 UTC (referenced from #3603 body).
- Cluster-drain pattern: PR #2486 (`refactor(kb): extract workspace helper + shared test mocks + ETag support`) — one PR closing #2467 + #2468 + #2469. Learning: `knowledge-base/project/learnings/2026-04-17-kb-route-helper-extraction-cluster-drain.md`.
- Draft PR: #3670 (`feat-one-shot-drain-pr-a2-review-3639-3642`).
- Related but out-of-scope: #3638 (Sentry userId hashing + Art. 17 erasure hooks).
