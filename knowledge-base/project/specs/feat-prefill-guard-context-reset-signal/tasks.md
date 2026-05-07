---
title: Tasks — Surface prefill-guard fires to model + user
date: 2026-05-07
issue: "#3269"
draft_pr: "#3419"
plan: knowledge-base/project/plans/2026-05-07-feat-prefill-guard-context-reset-signal-plan.md
spec: knowledge-base/project/specs/feat-prefill-guard-context-reset-signal/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks: feat-prefill-guard-context-reset-signal

## Phase 1: RED — failing tests first (`cq-write-failing-tests-before` applies)

- 1.1. Extend `apps/web-platform/test/agent-prefill-guard.test.ts` with the 5 helper-level scenarios from plan §5.1: helper returns `contextResetNotice` + `reason: 'prefill-guard'` on plain assistant-final; tool-aware variant on `tool_use` content array; generic variant on `content: string`; generic variant on `message: null/undefined/non-object` (no crash); `undefined` notice on cold-start, user-final, empty-history, probe-failure.
- 1.2. Extend `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` with the 7 dispatcher-side scenarios from plan §5.2 (system-prompt mutation, single WS emit per fire, both `reason` variants, no-mutation/no-emit on probe-fail/empty-history, multi-turn non-accumulation per AC6b).
- 1.3. Create `apps/web-platform/test/agent-runner-prefill-guard.test.ts` mirroring §5.2 scenario list for the legacy path.
- 1.4. Extend `apps/web-platform/test/ws-protocol.test.ts` with 4 Zod round-trip scenarios from §5.4 (both reasons parse, unknown reason rejects, missing conversationId rejects). Do NOT create a new file.
- 1.5. Extend `apps/web-platform/test/ws-known-types-guard.test.ts` to include `context_reset` in the known-types allowlist with both reason variants.
- 1.6. Create `apps/web-platform/test/chat-surface-context-reset.test.tsx` (RTL) with the 3 render scenarios from §5.6 — both `reason` copy strings render verbatim from `CONTEXT_RESET_COPY`; `data-message-type="context_reset"` attribute present. Tests import `CONTEXT_RESET_COPY` from the source, not inline literals.
- 1.7. Run the test suite — confirm all 1.1-1.6 scenarios FAIL (RED) before any production code changes.

## Phase 2: GREEN — helper extension (`agent-prefill-guard.ts`)

- 2.1. Read `apps/web-platform/server/agent-prefill-guard.ts` start-to-end so subsequent edits land cleanly.
- 2.2. Extend `ApplyPrefillGuardResult` with `contextResetNotice?: string` and `reason?: "prefill-guard" | "tool_use_orphan"` (both optional; populated only when `safeResumeSessionId === undefined` due to assistant-final history).
- 2.3. Add the typed runtime guard `function isToolUseTrailing(message: unknown): boolean` per plan §1.2 predicate chain. Cover `unknown` → object → `content` (string | array) → element with `type: "tool_use"`.
- 2.4. Build the two notice text variants (verbatim per plan §1.3):
  - generic: `"Prior conversation context was reset. Treat the user's next message as standalone; ask for clarification if it references earlier turns."`
  - tool-aware: `"Prior conversation context was reset. The previous turn proposed a tool action you no longer have context on. Do NOT execute any action without explicit re-confirmation by name — ask the user to restate which action they want to run."`
- 2.5. Update JSDoc on `ApplyPrefillGuardResult` to document `contextResetNotice` is single-turn (caller must not persist) and `reason` is the WS event discriminator source.
- 2.6. Run helper tests (1.1) — confirm GREEN.

## Phase 3: GREEN — wire `cc-dispatcher.ts` call site

- 3.1. Read `apps/web-platform/server/cc-dispatcher.ts` lines 470-610 to confirm structure.
- 3.2. At line 479 (existing `applyPrefillGuard` call), destructure `contextResetNotice` and `reason` from the result.
- 3.3. At line 597 (`systemPrompt: args.systemPrompt`) append the notice when present: `systemPrompt: contextResetNotice ? \`${args.systemPrompt}\n\n${contextResetNotice}\` : args.systemPrompt`.
- 3.4. After the guard call (line 479 area) and before the SDK call, when `reason && conversationId`, emit `sendToClient(userId, { type: "context_reset", reason, conversationId })` exactly once. Use a local `wsEmitted` boolean (defensive — helper isn't re-entered on SDK retry, but explicit single-emit is cheap).
- 3.5. The `applyPrefillGuard` call is wrapped in `Promise.all([...])` at cc-dispatcher.ts:477-486 — destructure the new return fields from the Promise.all result-array, not a sequential await.
- 3.6. Run dispatcher tests (1.2) — confirm GREEN.

## Phase 4: GREEN — wire `agent-runner.ts` call site

- 4.1. Read `apps/web-platform/server/agent-runner.ts` lines 1040-1170 (the accumulator's last `+=` site through the `query({` call) to identify the exact insertion line for the notice append.
- 4.2. At line 1157 (existing `applyPrefillGuard` call), destructure `contextResetNotice` + `reason`.
- 4.3. Insert the notice append AFTER all conditional accumulator branches (last verified at line 1047) and BEFORE the `query({` call (line 1166): `if (contextResetNotice) systemPrompt += \`\n\n${contextResetNotice}\`;`. Verify the chosen line is at column 0 (top-level statement scope), not inside the `query({})` object literal.
- 4.4. Add the WS emit identical to dispatcher: `if (reason) sendToClient(userId, { type: "context_reset", reason, conversationId })`. `conversationId` is verified always-present at agent-runner.ts:1157 (required `startAgentSession` parameter).
- 4.5. Run runner tests (1.3) — confirm GREEN.

## Phase 5: GREEN — WS taxonomy (4 exhaustiveness sites + reducer + render)

- 5.1. `apps/web-platform/lib/types.ts` — add the `ContextReset` variant to `WSMessage` near the `session_resumed`/`session_ended` cluster.
- 5.2. `apps/web-platform/lib/ws-zod-schemas.ts` — define `contextResetSchema = z.strictObject({ type: z.literal("context_reset"), reason: z.union([z.literal("prefill-guard"), z.literal("tool_use_orphan")]), conversationId: z.string() })` (mirror `fanoutTruncatedSchema` at lines 286-290 verbatim shape). Add to `flatTypeSchema` at line 431. The `_SchemaCovers` proof at lines 472-479 is **bidirectional** — both `_SchemaCoversForward` and `_SchemaCoversBackward` must compile.
- 5.3. `apps/web-platform/lib/ws-known-types.ts` — add `"context_reset"` to the `KNOWN_WS_MESSAGE_TYPES` Set literal (line 26). The `_forward`/`_backward` exhaustiveness rails at lines 76-77 will fail `tsc --noEmit` if omitted.
- 5.4. `apps/web-platform/lib/chat-state-machine.ts` — extend `applyStreamEvent` (line 277) with a `context_reset` case in the `switch (msg.type)`. This is the actual reducer site (TS exhaustive switch lives here, not in `ws-client.ts`). Append the message to the conversation's message stream; no other state mutation (single-shot lifecycle notice).
- 5.5. `apps/web-platform/lib/ws-client.ts` — in the `onmessage` switch (~line 175), confirm the `applyStreamEvent` call propagates `context_reset` automatically (since the reducer in 5.4 handles it). Add a `case "context_reset":` only if the dispatcher needs explicit branching beyond reducer forwarding.
- 5.6. Create `apps/web-platform/components/chat/chat-copy.ts` (or export from `chat-surface.tsx`) with the `CONTEXT_RESET_COPY` const per plan §4.5.
- 5.7. `apps/web-platform/components/chat/chat-surface.tsx` — add `case "context_reset":` rendering the inline rounded badge using the `workflow_ended` Tailwind precedent at lines 563-587 (`rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-3` outer; `text-sm text-soleur-text-primary` inner). Discriminator is `msg.type` (verbatim pattern at line 505 switch). Read copy via `CONTEXT_RESET_COPY[msg.reason]`. Use `data-message-type="context_reset"`.
- 5.8. Run WS protocol + RTL render + ws-known-types tests (1.4, 1.5, 1.6) — confirm GREEN.

## Phase 6: REFACTOR + verification

- 6.1. Run the full web-platform test suite. All tests pass (existing + new).
- 6.1a. **Three-pattern grep** per `cq-union-widening-grep-three-patterns`: run `rg "const _exhaustive: never" apps/web-platform/{lib,server,components}/`, `rg '\.type === "' apps/web-platform/{lib,server,components}/`, and `rg '\?\.type === "' apps/web-platform/{lib,server,components}/`. Any if-ladder hit not covered by an exhaustive switch must be widened in the same PR. Document zero-hit confirmation in PR body.
- 6.1b. **`vi.mock("../server/observability")` sweep** if Phase 2/3 introduces new imports from `@/server/observability`. Update each mock factory; missing exports crash with "is not a function" at first run.
- 6.2. Run `tsc --noEmit` for web-platform. No type errors. The bidirectional `_SchemaCovers` proof (`_SchemaCoversForward` + `_SchemaCoversBackward`), the `_forward`/`_backward` rails in `ws-known-types.ts`, and the `applyStreamEvent` exhaustive switch all fail compilation if the new variant is omitted from any of the 4 sites.
- 6.3. Manual QA: simulate a prefill-guard fire by injecting an assistant-final persisted session JSONL fixture; trigger Concierge follow-up; verify (i) inline notice renders with prefill-guard copy, (ii) model response acknowledges reset, (iii) Sentry shows ONE `op:prefill-guard` warn (no double-count from a stray WS-emit Sentry path).
- 6.4. Manual QA: repeat 6.3 with a tool_use-trailing fixture; verify tool-aware copy renders and model refuses any "yes do that" follow-up.
- 6.5. Capture screenshots for both `reason` variants. Attach to PR #3419 comment.

## Phase 7: Review + ship

- 7.1. Push branch (already pushed; verify with `git status`).
- 7.2. Run `skill: soleur:review` for multi-agent review (architecture-strategist, agent-native-reviewer, user-impact-reviewer per single-user-incident threshold, type-design-analyzer for the discriminated union widening).
- 7.3. Address review findings inline (default = fix-inline per `rf-review-finding-default-fix-inline`).
- 7.4. Mark PR #3419 ready for review. Body: `Closes #3269`. Add `## Changelog` per `plugins/soleur/AGENTS.md`.
- 7.5. Set semver label: `semver:minor` (new WS variant + new lifecycle-notice family is feature-shaped).
- 7.6. CPO sign-off recorded on PR (per `requires_cpo_signoff: true`).
- 7.7. `gh pr merge 3419 --squash --auto` and poll until MERGED per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
- 7.8. Post-merge: verify `web-platform-release` workflow succeeds. Watch Sentry `op:prefill-guard` for 7 days per #3269 re-evaluation criteria.
- 7.9. After merge, `cleanup-merged` removes the worktree.
