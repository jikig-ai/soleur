---
plan: knowledge-base/project/plans/2026-05-11-chore-remove-flag-cc-soleur-go-plan.md
issue: 3270
branch: feat-one-shot-3270-remove-flag-cc-soleur-go
---

# Tasks — Remove FLAG_CC_SOLEUR_GO

Derived from `knowledge-base/project/plans/2026-05-11-chore-remove-flag-cc-soleur-go-plan.md`.
Apply phases in order — phase ordering is load-bearing per
`2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

## Phase 1 — Test reshape (RED, no source edits yet)

- 1.1 `git mv apps/web-platform/test/router-flag-stickiness.test.ts apps/web-platform/test/router-stickiness-invariant.test.ts`
- 1.2 In the renamed test file: drop the `resolveInitialRouting` import on line 4.
- 1.3 In the renamed test file: drop the two `it("resolveInitialRouting(true) ...")` and `it("resolveInitialRouting(false) ...")` blocks (originally lines 32-38).
- 1.4 In the renamed test file: rewrite the file-header doc comment (originally lines 9-29) to drop the `FLAG_CC_SOLEUR_GO` framing; document the load-bearing invariant: `parseConversationRouting` is the only routing decision for turn 2+, and a row with `active_workflow IS NULL` is invariably `{ kind: "legacy" }` regardless of any future flag/config state.
- 1.5 In the renamed test file: change `describe("router-flag-stickiness (Stage 2.3)", ...)` to `describe("router stickiness invariant (active_workflow → ConversationRouting)", ...)`.
- 1.6 In `apps/web-platform/lib/feature-flags/server.test.ts`: delete the `describe("command-center-soleur-go flag", ...)` block (lines 75-100).
- 1.7 In `apps/web-platform/lib/feature-flags/server.test.ts`: drop the two `delete process.env.FLAG_CC_SOLEUR_GO` lines (52, 64) and the two `"command-center-soleur-go": false` lines in the `toEqual` expectations within `getFeatureFlags` tests.
- 1.8 Confirm RED state — `bun test apps/web-platform/test/router-stickiness-invariant.test.ts` may still pass (the surviving tests use `parseConversationRouting`, which is unchanged). The actual RED is on `bun run typecheck` — it must report a TS2305 / TS6133 error for the now-orphan `resolveInitialRouting` export (Phase 2 will close it).

## Phase 2 — Source removal (GREEN; contract-changing edits)

- 2.1 In `apps/web-platform/server/conversation-routing.ts`: delete `resolveInitialRouting` (the function block at lines 67-76 plus its preceding comment block at lines 67-73).
- 2.2 In `apps/web-platform/server/conversation-routing.ts`: update the module header doc-comment (lines 1-25) to drop the line that says `resolveInitialRouting` is the only function taking the flag as input.
- 2.3 In `apps/web-platform/server/ws-handler.ts` (lines 975-1018): delete `const ccFlagEnabled = getFlag("command-center-soleur-go");`.
- 2.4 In `apps/web-platform/server/ws-handler.ts` (lines 992-1017): unwrap the `if (ccFlagEnabled) { ... }` block — keep the body (rate-limiter check) unconditional.
- 2.5 In `apps/web-platform/server/ws-handler.ts` (line 1018): replace `const initialRouting: ConversationRouting = resolveInitialRouting(ccFlagEnabled);` with `const initialRouting: ConversationRouting = { kind: "soleur_go_pending" };`.
- 2.6 In `apps/web-platform/server/ws-handler.ts` (import on line 48): remove `resolveInitialRouting,` from the `@/server/conversation-routing` import block.
- 2.7 In `apps/web-platform/server/ws-handler.ts` (import on line 63): run `grep -cE '\bgetFlag\(' apps/web-platform/server/ws-handler.ts` AFTER applying 2.3. If the count is zero, drop the `import { getFlag } from "@/lib/feature-flags/server";` line. If the count is ≥1, retain the import. Record the count in the PR body.
- 2.8 In `apps/web-platform/server/ws-handler.ts` (comment at lines 987-990): rewrite to remove the conditional framing — the cc rate limiter is now the universal post-`sessionThrottle` limiter for every new conversation, regardless of any flag.

## Phase 3 — Feature-flag registry edit

- 3.1 In `apps/web-platform/lib/feature-flags/server.ts`: delete the line `"command-center-soleur-go": "FLAG_CC_SOLEUR_GO",` from the `FLAG_VARS` map.
- 3.2 Confirm `bun run typecheck` passes — the union narrows from 3 to 2 members; no type-assertion fix-up needed.

## Phase 4 — Comment + ADR sweep (cosmetic)

- 4.1 In `apps/web-platform/server/cc-dispatcher.ts` lines 6-10: replace the `Stage 2.12 — bind real-SDK query() / Behind FLAG_CC_SOLEUR_GO=0 in prod...` block with a corrected note explaining `realSdkQueryFactory` is the always-on production cc-soleur-go SDK binding (post-#3270).
- 4.2 In `apps/web-platform/server/cc-dispatcher.ts` line 419: replace `realSdkQueryFactory — Stage 2.12 binding (replaces the prior stub that throw-mirrored to Sentry under FLAG_CC_SOLEUR_GO).` with `realSdkQueryFactory — Stage 2.12 binding (originally gated behind FLAG_CC_SOLEUR_GO; flag removed in #3270, this is now the unconditional production binding).`
- 4.3 In `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` lines 71-73: replace the paragraph with a single-line follow-up describing #3270 as Stage 8.

## Phase 5 — Verify

- 5.1 Run the canonical typecheck: `bun run typecheck` (or repo's canonical `tsc --noEmit` runner from `package.json`). MUST pass.
- 5.2 Run `bun test apps/web-platform/lib/feature-flags/server.test.ts` — MUST pass (5 remaining tests).
- 5.3 Run `bun test apps/web-platform/test/router-stickiness-invariant.test.ts` — MUST pass (3 remaining tests).
- 5.4 Run the full affected-suite: `bun test apps/web-platform/` (or the canonical project test script). MUST pass.
- 5.5 Class-wide grep — run `git grep -F FLAG_CC_SOLEUR_GO -- ':!knowledge-base/project/learnings/**' ':!knowledge-base/project/plans/**' ':!knowledge-base/project/specs/**' ':!**/archive/**'` and verify zero matches. If any match remains in a non-archive path, add the file to the edit set and re-run from Phase 4.
- 5.6 Run `git grep -nE 'resolveInitialRouting' --` and verify zero matches (no test-d.ts orphans).
- 5.7 Run `git grep -nE 'ccFlagEnabled' --` and verify zero matches.
- 5.8 Run `git status` — verify the test rename shows as `R` (renamed) not `D` + `??` (deleted + new).

## Phase 6 — PR

- 6.1 Push the branch: `git push -u origin feat-one-shot-3270-remove-flag-cc-soleur-go`.
- 6.2 Open the PR with title `chore: remove FLAG_CC_SOLEUR_GO (always-on in prod and dev)`.
- 6.3 PR body uses `Closes #3270` on its own line (NOT in title). Use `Ref #3263` and `Ref ADR-022` everywhere else.
- 6.4 Do NOT use `Closes` for any of the acknowledged code-review issues (#3374, #3372, #2191, #3369, #3243, #3242, #2955).
- 6.5 Run `/soleur:review` to spawn multi-agent review against the pushed branch (per `rf-before-spawning-review-agents-push-the`).
