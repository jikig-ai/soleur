---
title: "Tasks — refactor: cc-dispatcher cluster drain (PR-A2 review #3639 + #3640 + #3641 + #3642)"
plan: knowledge-base/project/plans/2026-05-12-refactor-cc-dispatcher-cluster-drain-3639-3642-plan.md
branch: feat-one-shot-drain-pr-a2-review-3639-3642
issues: ["#3639", "#3640", "#3641", "#3642"]
pr: "#3670"
lane: single-domain
---

# Tasks

## 1. Setup — plan-time greps + baselines

- [ ] 1.1 Grep call sites for the `__resetP0DedupForTests` → `__resetMirrorP0DedupForTests` rename.
- [ ] 1.2 Quantify hoist-block overlap across sibling `cc-dispatcher-*.test.ts` files to scope harness consumers.
- [ ] 1.3 Baseline counts: inline op-slug literals; `typeof === "number"` field-presence branches; `setTimeout(_, N)` settle calls.
- [ ] 1.4 Record baselines in the PR body "before" column.

## 2. #3642 F7 — hoist op-slug constants (independent, lands first)

- [ ] 2.1 Add `const CC_OP_SLUGS = { ... } as const;` at module scope in `cc-dispatcher.ts`.
- [ ] 2.2 Replace 5 inline slug literals (`saveAssistantMessage`, W4 orphan Error + ctx.op, `_observeCcPersistUsageFirstTrue`, user-INSERT mirror).
- [ ] 2.3 Update `observability.ts:161-170` registry comment to reference `CC_OP_SLUGS.*`.
- [ ] 2.4 Migrate test-file slug-literal assertions to import + use `CC_OP_SLUGS.*`.
- [ ] 2.5 Run `bun test` (apps/web-platform) — expect 4058 passes.
- [ ] 2.6 Commit: `refactor(cc-dispatcher): hoist op-slug literals to CC_OP_SLUGS — closes #3642 (F7)`.

## 3. #3639 F3 — extract TtlDedupMap

- [ ] 3.1 Author `class TtlDedupMap<K extends string>` in `observability.ts` (constructor `(ttlMs, sweepInterval, maxSize?)`, methods `tryClaim` + `reset`).
- [ ] 3.2 Refactor `mirrorWithDebounce` body to ≤ 12 LoC using a module-scope `TtlDedupMap` instance.
- [ ] 3.3 Refactor `mirrorP0Deduped` body to ≤ 20 LoC using `TtlDedupMap` (with `maxSize` set for insertion-order eviction).
- [ ] 3.4 Update both `__reset*ForTests` seams to call `instance.reset()`.
- [ ] 3.5 Replace `cc-dispatcher.test.ts:49-59` inline TTL re-impl with `new TtlDedupMap(MIRROR_DEBOUNCE_MS, Infinity)`.
- [ ] 3.6 Run `bun test` — expect green (incl. `observability-mirror-debounce.test.ts`).
- [ ] 3.7 Commit: `refactor(observability): extract TtlDedupMap, drop inline test re-impl — partial #3639 (F3)`.

## 4. #3640 F2 + F4 — discriminated PersistMode + helper extraction

- [ ] 4.1 Replace `AssistantPersistMode` + `AssistantPersistOpts` with module-scope `type PersistMode = { kind: "complete"; usage: ... } | { kind: "aborted"; usage: ... }`.
- [ ] 4.2 Rewrite `saveAssistantMessage` signature to `(mode: PersistMode) => Promise<void>`.
- [ ] 4.3 Extract `buildRow(mode, text, conversationId)` at module scope.
- [ ] 4.4 Extract `mirrorInsertError(error, mode, userId, conversationId, fullText)` at module scope.
- [ ] 4.5 Add `const _exhaustive: never = mode;` exhaustiveness rail after the switch.
- [ ] 4.6 Trim `saveAssistantMessage` orchestrator to ≤ 20 LoC.
- [ ] 4.7 Update two call sites (`onTextTurnEnd` ~1283, `onWorkflowEnded` ~1329) to pass `{ kind, usage }`.
- [ ] 4.8 Run `bun test` — expect green.
- [ ] 4.9 Commit: `refactor(cc-dispatcher): discriminated PersistMode + buildRow/mirrorInsertError helpers — partial #3640 (F2 + F4)`.

## 5. #3640 F6 — Message.usage variant union (TS-only, no migration)

- [ ] 5.1 Widen `Message` in `lib/types.ts` with `variant: "legacy" | "cc"` + tagged `usage?` union (`LegacyUsage` / `CcUsage`).
- [ ] 5.2 Update `lib/api-messages.ts` hydration: `variant = row.leader_id === CC_ROUTER_LEADER_ID ? "cc" : "legacy"` on every Message returned.
- [ ] 5.3 Rewrite `ws-client.ts:1010-1025` `usage:` ternary to switch on `m.variant`.
- [ ] 5.4 Rewrite `message-bubble.tsx:330-350` `renderAbortedAssistant` token-sum + cost-label to switch on `usage.variant`.
- [ ] 5.5 Run `bun run typecheck` — enumerate every consumer that breaks; add each to `Files to Edit` inline.
- [ ] 5.6 Iterate Steps 5.3-5.5 until typecheck is clean.
- [ ] 5.7 Run `bun test` — expect green.
- [ ] 5.8 Commit: `refactor(types): discriminate Message.usage by variant — closes #3640 (F2 + F4 + F6)`.

## 6. #3639 F1 + #3641 T-W1-invariant-7 — TurnPersistenceState extraction (paired)

- [ ] 6.1 Author `class TurnPersistenceState` at module scope in `cc-dispatcher.ts` with private fields + 6 public methods (`appendText`, `captureUsage`, `snapshotAndBumpTurn`, `flushAbort`, `flushComplete`, `reset`).
- [ ] 6.2 Replace the four `let` declarations (cc-dispatcher.ts:1136-1150) with `const state = new TurnPersistenceState();`.
- [ ] 6.3 Rewrite `onText` / `onTextTurnEnd` / `onWorkflowEnded` / `onResult` to call class methods.
- [ ] 6.4 Relax `T-W1-invariant-7`: `toHaveBeenCalledTimes(3)` → `toBeGreaterThanOrEqual(3)`. Keep the per-call argument-equality loop.
- [ ] 6.5 Port `T-W4-reset-symmetry` to call `state.reset()` and assert against the public accessor (add `__getStateForTests` seam if needed).
- [ ] 6.6 Run `bun test` — expect green.
- [ ] 6.7 Commit: `refactor(cc-dispatcher): extract TurnPersistenceState + relax T-W1-invariant-7 — closes #3639 (F1 + F3)`.

## 7. #3641 — shared harness + seam renames + seam relocation + expect.poll

- [ ] 7.1 Author `test/helpers/cc-dispatcher-harness.ts` exporting `buildDispatcherMocks({ withRealMirror?, withRealP0? })`.
- [ ] 7.2 Migrate `cc-dispatcher.test.ts` 7-mock hoist block to the harness.
- [ ] 7.3 Migrate `cc-dispatcher-cost.test.ts` to the harness (5/6 mock overlap per deepen-plan baseline). Other 5 sibling test files stay on bespoke hoists (1/6 overlap each).
- [ ] 7.4 Rename `__resetP0DedupForTests` → `__resetMirrorP0DedupForTests` in `observability.ts:314` + update **3 call sites**: `cc-dispatcher.test.ts:128 + 155` AND `cc-dispatcher-cross-tenant.integration.test.ts:69 + 159` (integration test edit is rename-only).
- [ ] 7.5 Move `__setAssertWriteScopeForTests` + `__resetAssertWriteScopeForTests` from cc-dispatcher.ts:~195-230 to the bottom-of-file test-seam block.
- [ ] 7.6 Replace the two `setTimeout(_, 10)` settles in `T-W4-orphan` + `T-W4-reset-symmetry` with `await expect.poll(() => mockMessagesInsert.mock.calls.length, { interval: 5, timeout: 200 }).toBe(0)` (vitest 3.2.4 signature; predicate must not throw; no `.resolves`/`.rejects` chaining).
- [ ] 7.7 Verify `grep -nE "setTimeout\([^,]+, *[0-9]+\)" apps/web-platform/test/cc-dispatcher.test.ts` returns zero.
- [ ] 7.8 Run `bun test` — expect green.
- [ ] 7.9 Commit: `refactor(test): shared cc-dispatcher harness + expect.poll + seam renames — closes #3641 (F5 + drift × 3 + test-design)`.

## 8. Verification + PR body refresh

- [ ] 8.1 Run `bun test` from `apps/web-platform/` — expect 4058 passes.
- [ ] 8.2 Run `bun run typecheck` — expect clean.
- [ ] 8.3 Optional: run dev integration test under `SUPABASE_DEV_INTEGRATION=1` if Doppler dev creds available.
- [ ] 8.4 Replay Phase 1 baseline greps for the PR body "after" column.
- [ ] 8.5 Rewrite PR body (Summary, four `Closes #N` lines, per-AC commit-SHA map, before/after grep table, test plan, PR #2486 cluster-drain reference).
- [ ] 8.6 Mark PR #3670 ready for review.
