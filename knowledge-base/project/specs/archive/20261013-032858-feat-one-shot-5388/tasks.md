# Tasks — fix #5388 c4 unregistered-tool mirror false-positive

Plan: `knowledge-base/project/plans/2026-06-15-fix-c4-unregistered-tool-mirror-false-positive-plan.md`
Lane: single-domain · Branch: feat-one-shot-5388 · Issue: #5388

## Phase 1 — RED: failing predicate tests

- [x] 1.1 In `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts`, add a `describe("edit_c4_diagram registration (#5388)")` block.
  - [x] 1.1.1 Import `EDIT_C4_DIAGRAM_TOOL` from `../server/c4-concierge-tools`; assert the FQN literal equals `mcp__soleur_platform__${EDIT_C4_DIAGRAM_TOOL}`.
  - [x] 1.1.2 AC1: `shouldMirrorUnregisteredPlatformToolUse(c4Fqn, [NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN, c4Fqn])` ⇒ `false`.
  - [x] 1.1.3 AC2: `shouldMirrorUnregisteredPlatformToolUse(c4Fqn, [NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN])` ⇒ `true`.
  - [x] 1.1.4 AC3: keep/confirm narrate + summarize cases return `false`.

## Phase 2 — GREEN: per-dispatch registered-tool set

- [x] 2.1 Extract the c4-eligibility resolution inlined in `realSdkQueryFactory` (`cc-dispatcher.ts:1724-1748`: installation id + owner/repo + `getRuntimeFlag(C4_VISUALIZER_FLAG, …)`) into a shared helper (e.g. `resolveC4Eligible(userId)` / `resolveRegisteredPlatformToolNames(userId)`). Resolve the FULL precondition set, not just the flag.
- [x] 2.2 Point `realSdkQueryFactory`'s c4-tool build decision at the shared helper (single source of truth).
- [x] 2.3 In the `dispatchSoleurGo` per-dispatch scope (near `:2615`/`:2643`), add `registeredPlatformToolNames` cell seeded `[NARRATE_TOOL_FQN, SUMMARIZE_TOOL_FQN]` + fire-and-forget resolve that appends the c4 FQN when eligible (warm + cold reachable).
- [x] 2.4 Fail-closed try/catch → leave c4 FQN out + `reportSilentFallback({ feature: "cc-dispatcher", op: "c4-registered-resolve", extra: { userId, conversationId } })` (AC5).

## Phase 3 — GREEN: swap predicate arg at call site

- [x] 3.1 At `cc-dispatcher.ts:2852`, replace `CC_REGISTERED_PLATFORM_TOOL_NAMES` with the per-dispatch `registeredPlatformToolNames` cell.
- [x] 3.2 Retain `CC_REGISTERED_PLATFORM_TOOL_NAMES` as the base list; update its doc-comment to note c4 is appended per-dispatch.
- [x] 3.3 Add cold+warm-reachability comment at the resolve site (mirror the `:2603` setBashAutonomous warm-query note) + the onToolUse ordering assumption.

## Phase 4 — Verify

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC6).
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-mcp-tier-allowlist.test.ts` (AC7).
- [x] 4.3 `git grep -n "CC_REGISTERED_PLATFORM_TOOL_NAMES" apps/web-platform/server/cc-dispatcher.ts` — no orphaned direct read at the call site (AC8).
