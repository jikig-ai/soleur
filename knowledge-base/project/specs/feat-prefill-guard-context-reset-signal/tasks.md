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
- 3.5. If `conversationId` unavailable: skip emit + `reportSilentFallback(null, { feature: "cc-concierge", op: "prefill-guard-conversationid-missing", extra: { userId, conversationId } })`. Do NOT empty-string fallback.
- 3.6. Run dispatcher tests (1.2) — confirm GREEN.

## Phase 4: GREEN — wire `agent-runner.ts` call site

- 4.1. Read `apps/web-platform/server/agent-runner.ts` lines 1040-1170 (the accumulator's last `+=` site through the `query({` call) to identify the exact insertion line for the notice append.
- 4.2. At line 1157 (existing `applyPrefillGuard` call), destructure `contextResetNotice` + `reason`.
- 4.3. Insert the notice append AFTER all conditional accumulator branches (last verified at line 1047) and BEFORE the `query({` call (line 1166): `if (contextResetNotice) systemPrompt += \`\n\n${contextResetNotice}\`;`. Verify the chosen line is at column 0 (top-level statement scope), not inside the `query({})` object literal.
- 4.4. Add the WS emit + conversationId fallback per plan §3.3, identical pattern to dispatcher (`feature: "agent-runner"`).
- 4.5. Run runner tests (1.3) — confirm GREEN.

## Phase 5: GREEN — WS taxonomy (types + Zod + client + render)

- 5.1. `apps/web-platform/lib/types.ts` — add the `ContextReset` variant to `WSMessage` near the `session_resumed`/`session_ended` cluster.
- 5.2. `apps/web-platform/lib/ws-zod-schemas.ts` — define `contextResetSchema` (z.object with `type: z.literal("context_reset")`, `reason: z.union([z.literal("prefill-guard"), z.literal("tool_use_orphan")])`, `conversationId: z.string()`). Add to the discriminated-union in `wsMessageSchema`. Update the `_SchemaCovers` proof.
- 5.3. `apps/web-platform/lib/ws-client.ts` — in the `onmessage` switch (lines 511-651), add a `case "context_reset":` that propagates the message to the chat-surface store via the same path `workflow_ended` uses (NOT the `fanout_truncated` no-op path).
- 5.4. Create `apps/web-platform/components/chat/chat-copy.ts` (or export from `chat-surface.tsx`) with the `CONTEXT_RESET_COPY` const per plan §4.5.
- 5.5. `apps/web-platform/components/chat/chat-surface.tsx` — add `case "context_reset":` rendering the inline rounded badge using `workflow_ended` Tailwind classes at lines 563-587 as precedent. Read copy via `CONTEXT_RESET_COPY[message.reason]`. Use `data-message-type="context_reset"`.
- 5.6. Run WS protocol + RTL render + ws-known-types tests (1.4, 1.5, 1.6) — confirm GREEN.

## Phase 6: REFACTOR + verification

- 6.1. Run the full web-platform test suite. All tests pass (existing + new).
- 6.2. Run `tsc --noEmit` for web-platform. No type errors. Pay attention to `_SchemaCovers` proof — it will fail compilation if the new variant is omitted from the Zod union.
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
