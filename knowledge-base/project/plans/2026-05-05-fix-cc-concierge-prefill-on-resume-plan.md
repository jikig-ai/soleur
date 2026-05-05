---
title: "fix(cc-concierge): API 400 'model does not support assistant message prefill' on session resume"
date: 2026-05-05
status: ready-for-work
type: bug-fix
issue: 3250
sibling_issues: [3251, 3252, 3253]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md
bundle_spec: knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md
branch: feat-one-shot-fix-concierge-prefill-3250
---

# Fix Concierge API 400 "model does not support assistant message prefill" on session resume (#3250)

## Enhancement Summary

**Deepened on:** 2026-05-05

**Sections enhanced:** TL;DR, Hypotheses (H1 mechanism corroboration), Phase 1 RED, Phase 2 GREEN, Risks (R3 SDK surface drift), Sharp Edges, Cross-References.

**Research sources used:**
- WebSearch — industry-wide reports of the Claude 4.6+ prefill 400 (LiveKit, langchain, Microsoft agent-framework, Agno, CrewAI) and Anthropic's recommended remediation patterns.
- Anthropic Claude Agent SDK TypeScript [`sdk.d.ts`](apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts) — confirmed `getSessionMessages(sessionId, options?: { dir? })` is in the public surface (line 518) and returns `SessionMessage[]` with `type: "user" \| "assistant"` (line 2563).
- Anthropic claude-agent-sdk-typescript Issue #14 — `getSessionMessages` is the documented SDK answer for inspecting persisted sessions.
- Local repo: `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — confirmed mock scaffolding pattern and that `warnSilentFallback` is already mocked (line 74) in the existing factory test.
- Local learning: `knowledge-base/project/learnings/2026-02-22-model-id-update-patterns.md` — confirms `claude-sonnet-4-6` is the current Concierge model and Opus 4.7 is also affected by the prefill rejection.

### Key Improvements

1. **Mechanism corroboration**: Multiple peer frameworks (LiveKit #4907, Microsoft agent-framework #5008, langchain deepagents #1585, CrewAI #4798, Agno #7015) report this exact 400 from Claude 4.6+ models. The trigger pattern reported by Kilo-Org/cloud#1425 — "retry loop combined with partial assistant messages from failed LLM streams, where partial assistant content is stored in the session via Session.updatePart as the stream is consumed incrementally" — exactly matches H1 in this plan (runaway/wall-clock/abort mid-stream → partial assistant in persisted session). Hypothesis confirmed industry-wide; not a Soleur-specific bug.
2. **Anthropic-recommended remediation**: Anthropic's prescribed mitigations for this 400 are: (a) strip trailing assistant messages, (b) convert trailing assistant to user-role context, or (c) use `output_config.format`. This plan implements (a) at the SDK call boundary — the canonical and lowest-risk choice for our surface (no message-content rewriting; no API-format change).
3. **Test scaffold reuse**: `cc-dispatcher-real-factory.test.ts` already does `vi.mock("@/server/observability", () => ({ reportSilentFallback: ..., warnSilentFallback: vi.fn() }))` — the new test file imports the same hoisted mocks (extending with a captured `mockWarnSilentFallback` spy) and the same SDK + Supabase mock harness. Eliminates a Phase 1 risk of mock-drift breaking parallel tests.
4. **Affected-model widening**: The prefill 400 fires on `claude-sonnet-4-6`, `claude-opus-4-6`, `claude-opus-4-7`, and Claude Mythos Preview. The legacy runner audit (Phase 3) becomes more important — any Soleur surface using these models on a `resume:` path is exposed to the same trigger.
5. **SDK API stability annotation**: `getSessionMessages` is exported by the SDK at `sdk.d.ts:518` and was recently improved to handle parallel tool results correctly (per Anthropic SDK changelog). It is the documented stable surface for our use; no need for direct `.jsonl` parsing.

### New Considerations Discovered

- **Empty-history short-circuit refinement**: If `getSessionMessages` returns `[]` for a non-empty `resumeSessionId`, that's an unexpected state — the resumeSessionId we have is one the SDK previously emitted, so an empty list means the session file is missing or the `dir` argument is wrong. Treat empty history as suspicious and emit a `warnSilentFallback` with `op: "prefill-guard-empty-history"` (separate from the probe-failed op) so we can distinguish "session truly empty" from "session file lookup mis-configured." Plan body's Phase 1 scenario 3 currently passes through silently — refine to emit a third distinct warn op.
- **Race condition on cold-start probe**: If two cold-start `realSdkQueryFactory` invocations for the same `resumeSessionId` race (very unlikely in practice — `dispatchSoleurGo` serializes cold starts per conversation), both probes could see the same assistant-terminated state and both could drop `resume:`. Both decisions are safe (one starts a fresh session, the other becomes a no-op against the runner's per-conversation `activeQueries` Map). No mitigation needed; document for future readers.
- **Persisted session is per-cwd, not per-user**: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` keys on the workspace path. Cross-user resume is impossible — each user's workspace has a different cwd. The `dir: workspacePath` argument to `getSessionMessages` is also tenant-scoping by construction. No additional auth check needed at the guard; the SDK's path-based isolation is sufficient.
- **Avoid hard-coding the assistant-only check**: Future SDK SessionMessage variants may add `type: "system"` or `type: "tool_result"`. The guard SHOULD use `last.type === "assistant"` (positive match) rather than `last.type !== "user"` (negative match), so an unknown future type defaults to "pass-through" rather than "drop resume." Plan Phase 2 spec already reads `if (last && last.type === "assistant")` — keep that polarity.

## TL;DR

Soleur Concierge replies on resume sometimes 400 with:

> This model does not support assistant message prefill. The conversation must end with a user message.

The cc-soleur-go path passes `resume: <sessionId>` to the Agent SDK. The SDK reads the persisted session from `~/.claude/projects/<id>/<sessionId>.jsonl` and prepends it to the new turn. When the persisted thread's last message is `type: "assistant"` (turn ended mid-stream — server reap, container restart, wall-clock fire, abort), the SDK forwards an assistant-terminated thread to Anthropic. `claude-sonnet-4-6` (Concierge default) rejects with the prefill 400.

The fix is a **thread-shape guard at the SDK call boundary** in `realSdkQueryFactory`: before constructing `query({ options: { resume } })`, call `getSessionMessages(resumeSessionId)` and inspect the trailing message. If it is `type: "assistant"`, drop the `resume` option (the SDK will start a fresh server-side session) and emit a Sentry warn via `warnSilentFallback({ feature: "cc-concierge", op: "prefill-guard" })`. The runner's existing `state.sessionId` will rebind to the SDK's new `session_id` from the first streamed message — same path used today after a fresh start.

A regression test reproduces the failing thread shape against an in-memory `getSessionMessages` stub and proves the guard:
1. drops the `resume` option,
2. emits one `warnSilentFallback` with the expected feature/op tags,
3. preserves user-terminated threads unchanged.

## Issue context

- **Issue:** [#3250](https://github.com/jikig-ai/soleur/issues/3250) — P1, brand-load-bearing.
- **Brainstorm:** [`2026-05-05-cc-session-bugs-batch-brainstorm.md`](https://github.com/jikig-ai/soleur/blob/feat-cc-session-bugs-batch/knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md) (lives on `feat-cc-session-bugs-batch` branch).
- **Bundle spec:** [`feat-cc-session-bugs-batch/spec.md`](https://github.com/jikig-ai/soleur/blob/feat-cc-session-bugs-batch/knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md) — FR1 owns this bug, TR1 mandates the Sentry mirror.
- **Sibling issues** (out of scope here): #3251 routing visibility, #3252 read-only OS allowlist, #3253 PDF availability message.
- **Branch:** `feat-one-shot-fix-concierge-prefill-3250` off `main` (NOT off the bundle branch — keeps the P1 cycle short).

## User-Brand Impact

**If this lands broken, the user experiences:** A raw Anthropic 400 string rendered inside the Concierge response bubble on the very first follow-up message after any session restart, container redeploy, mid-stream abort, or wall-clock fire. The user reads "Soleur is broken." The Concierge is the first interactive surface a new user touches in `/soleur:go`.

**If this leaks, the user's data/workflow is exposed via:** No data exposure. The leak is a trust collapse on first use — every user who hits this in their first ten minutes is at risk of churn. There is no surfaced fallback path (the error renders verbatim into the bubble; no retry button, no recovery copy).

**Brand-survival threshold:** `single-user incident`.

This threshold is inherited from the bundle brainstorm. The Concierge surface is the brand-visible front door for `/soleur:go`. CPO sign-off required at plan time (this plan); `user-impact-reviewer` agent invoked at review time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (codebase as of HEAD) | Plan response |
|---|---|---|
| Concierge model is `claude-sonnet-4-6` at `agent-runner-query-options.ts:114` | Confirmed verbatim. Pinned default in `buildAgentQueryOptions` (line 114). No path overrides `args.model`. | Default model swap is **out of scope** per bundle spec non-goals. Fix lives at thread-shape boundary, not model. |
| Threading at `agent-runner-query-options.ts:164` + `soleur-go-runner.ts:1078,1101` | Confirmed. `resumeSessionId` reaches `buildAgentQueryOptions` from `realSdkQueryFactory` (cc-dispatcher.ts:543). The runner only pushes `user`-role messages (`pushUserMessage` line 1047, `respondToToolUse` line 1196) — it never constructs assistant messages. | The bad thread shape is NOT produced by the runner. It comes from the persisted-session file the SDK reads on `resume:`. Guard MUST inspect that persisted file. |
| "Hypothesis: resumeSessionId path reconstructs message history with trailing role: assistant" | Confirmed mechanism. The Agent SDK (`@anthropic-ai/claude-agent-sdk@<installed>`) exposes `getSessionMessages(sessionId, { dir })` returning `SessionMessage[]` typed `type: "user" \| "assistant"`. Persisted at `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`. | Guard implementation: call `getSessionMessages` from `realSdkQueryFactory` BEFORE the `sdkQuery({ options })` call, inspect the trailing entry. |
| Adjacent suspect: `respondToToolUse` at `soleur-go-runner.ts:1196-1231` | Confirmed user-only — pushes `tool_result` blocks under `role: "user"`. Cannot produce assistant-terminated input. | NOT the trigger. No fix needed here. |
| Adjacent suspect: consume loop at `soleur-go-runner.ts:1018` | Confirmed. The loop only reads `assistant` and `result` messages from the SDK; does not reflect them back. | NOT the trigger. |
| `cq-silent-fallback-must-mirror-to-sentry` says use `reportSilentFallback` | Confirmed. `apps/web-platform/server/observability.ts` exports both `reportSilentFallback` (error-level) and `warnSilentFallback` (warning-level, line 123). | Guard fires at warning level — recovered, expected-occasionally state — so use `warnSilentFallback`. |

## Hypotheses (ranked)

### H1 (primary): Persisted session ends with an `assistant` message; SDK forwards it as-is

**Mechanism.** The Agent SDK persists each turn to `~/.claude/projects/<encoded-workspace-cwd>/<sessionId>.jsonl`. Each line is a `SessionMessage = { type: "user" \| "assistant"; uuid; session_id; message; parent_tool_use_id }`. On `resume: <sessionId>`, the SDK reads this file and prepends every message to the new turn before calling Anthropic.

**Trigger conditions** (any one suffices):
- Container restart between turns (idle-reaper tore down the in-memory `Query`; persisted session survives on the SDK's `~/.claude/projects/` volume).
- Idle-reaper fired (`DEFAULT_IDLE_REAP_MS = 10min`) — the runner's `closeQuery` does not write a closing user message.
- Wall-clock runaway fired (`DEFAULT_WALL_CLOCK_TRIGGER_MS = 90s` per-block, or `DEFAULT_MAX_TURN_DURATION_MS = 10min` absolute) — `emitWorkflowEnded({ status: "runaway" })` aborts mid-assistant-stream.
- Cost cap fired (`emitWorkflowEnded({ status: "cost_ceiling" })`) — same: aborts mid-assistant.
- Network hiccup mid-tool-use that closes the query before a tool_result is delivered.

In every case the last appended SessionMessage is `type: "assistant"`. When the user resumes, the cc path passes `resume: <sessionId>`, the SDK reads the file, prepends `[…, assistant]`, then appends the new user prompt — at the API level this is `[…, user, assistant, user]` if the SDK appends correctly OR `[…, assistant]` (no append if the new prompt comes via streaming-input on a session that has not yet emitted the next "begin user turn" marker). Either way Anthropic's `messages.create` sees a tail that violates the user-terminated invariant and returns the prefill 400 for `claude-sonnet-4-6`.

**Likelihood:** High. Matches the issue body, matches the symptom (only fires "on resume after a tool-use turn"), matches the SDK contract.

#### Research Insights — Industry corroboration of H1

Multiple peer frameworks have reported this exact 400 against Claude 4.6+ models. The corroboration is precise enough to elevate H1 from "high likelihood" to "confirmed mechanism":

- **livekit/agents#4907 (2026)** — Surfaced as "Anthropic 400 Error on Claude 4.6 — Prefilling assistant messages is no longer supported." Same wire error, same cause (assistant-terminated message array).
- **microsoft/agent-framework#5008 (2026)** — Triggered when one agent's output (assistant role) is forwarded as input to a second agent. Anthropic API rejects because the conversation must end with a user message.
- **langchain-ai/deepagents#1585** — "Claude Opus 4.6 / Sonnet 4.6: 'This model does not support assistant message prefill' error." Confirms the 400 fires on **both** Sonnet 4.6 and Opus 4.6.
- **Kilo-Org/cloud#1425 — most precise mechanism statement found in the wild:** "the trigger is the retry loop combined with partial assistant messages from failed LLM streams, where partial assistant content is stored in the session via Session.updatePart as the stream is consumed incrementally." This *exactly* describes the failure mode for our cc-soleur-go path: runaway/wall-clock/abort mid-stream → partial assistant lands in `~/.claude/projects/<cwd>/<sid>.jsonl` → next resume passes that partial assistant to Anthropic.
- **agno-agi/agno#7015 — calls it a "breaking change"** from Anthropic, not a bug in any specific framework. Treat as a permanent API contract.
- **crewAIInc/crewAI#4798** — "Claude 4.6 models fail: consecutive assistant messages treated as prefill." Confirms behavior is consistent across orchestration frameworks.

**Anthropic's recommended remediation patterns** (from the migration guidance in the search results):

1. **Strip trailing assistant messages** before sending to the API when the model is Claude 4.6+. *This plan implements this approach at the SDK call boundary.*
2. Convert trailing assistant messages into user-role context. (Higher implementation cost; rewrites message content.)
3. Use `output_config.format` (Anthropic's recommended replacement for prefill-based structured output). (Not applicable here — we're not doing structured-output prefill; the assistant-terminated thread is incidental, not intentional.)

**Affected models** (per Anthropic Claude API docs): `claude-sonnet-4-6`, `claude-opus-4-6`, `claude-opus-4-7`, Claude Mythos Preview. The Concierge default at `agent-runner-query-options.ts:114` (`claude-sonnet-4-6`) is in this list. The legacy runner audit (Phase 3) MUST cover all four model IDs.

**References:**

- [Anthropic — Migrating to Claude 4 (covers prefill removal)](https://docs.anthropic.com/en/docs/about-claude/models/migrating-to-claude-4)
- [Anthropic — Working with sessions](https://platform.claude.com/docs/en/agent-sdk/sessions)
- [livekit/agents#4907 — primary peer report](https://github.com/livekit/agents/issues/4907)
- [Kilo-Org/cloud#1425 — most precise mechanism description](https://github.com/Kilo-Org/cloud/issues/1425)
- [anthropics/claude-agent-sdk-typescript#14 — `getSessionMessages` is the documented answer for reading persisted sessions](https://github.com/anthropics/claude-agent-sdk-typescript/issues/14)

### H2 (secondary): Resumed session contains an unmatched `tool_use` block

**Mechanism.** The persisted session ends with `assistant: { tool_use { id: T } }` and a matching `user: { tool_result { tool_use_id: T } }` is missing (the runner never delivered it because the user closed the tab). On resume + new user text message, Anthropic sees a tool_use without a satisfying tool_result and rejects.

**Distinguishability from H1:** Same final symptom (assistant-terminated thread). The guard's trailing-`assistant`-check covers BOTH cases — H2 is a strict subset of H1's input shape (assistant block with `tool_use` content). No separate handling needed.

**Likelihood:** Subset of H1. Treat as covered.

### H3 (rejected): A code path intentionally prefills

**Audit performed at plan time.**
- `grep -nE "role: ?\"assistant\"|role: 'assistant'" apps/web-platform/server` returns 0 hits.
- `grep -nE "role: ?\"assistant\"" apps/web-platform/lib` returns 8 hits, all in `chat-state-machine.ts` and `ws-client.ts` — these are **client-side React state for chat rendering**, not SDK input.
- `pushUserMessage` (`soleur-go-runner.ts:1047`) constructs only `role: "user"` SDKUserMessages.
- `respondToToolUse` (`soleur-go-runner.ts:1196`) constructs only `role: "user"` with a `tool_result` content block.

**Conclusion:** No code path intentionally prefills. The bundle spec's non-goal stands: model swap is NOT in scope. Fix the thread-shape guard.

## Implementation Phases

### Phase 1 — RED: regression test reproducing the failing thread shape

**File to create:** `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts`

**Test scenarios** (each as a separate `test()` block):

1. **`drops resume when persisted session ends with assistant message`**
   - Stub `getSessionMessages` to return `[{ type: "user" }, { type: "assistant" }]`.
   - Spy on `sdkQuery`. Invoke `realSdkQueryFactory` with `resumeSessionId: "abc"`.
   - Assert `sdkQuery` was called with `options.resume === undefined` (NOT `"abc"`).
   - Assert `warnSilentFallback` was called once with `{ feature: "cc-concierge", op: "prefill-guard" }` and `extra` containing `{ resumeSessionId: "abc", lastType: "assistant", historyLength: 2 }`.

2. **`preserves resume when persisted session ends with user message`**
   - Stub `getSessionMessages` to return `[{ type: "user" }, { type: "assistant" }, { type: "user" }]`.
   - Assert `sdkQuery` was called with `options.resume === "abc"` (unchanged).
   - Assert `warnSilentFallback` was NOT called.

3. **`emits distinct warn and preserves resume when persisted session history is empty`** *(refined per deepen-pass)*
   - Stub `getSessionMessages` to return `[]`.
   - Empty history for a non-empty `resumeSessionId` is a suspicious state (the resumeSessionId we have was emitted by the SDK in a prior turn; an empty list means the session file is missing or the `dir` argument is wrong). Pass `resume:` through unchanged BUT emit one `warnSilentFallback` with `op: "prefill-guard-empty-history"` so we can distinguish "session truly empty" from "session-file lookup mis-configured" in Sentry.
   - Assert `sdkQuery` called with `options.resume === "abc"`.
   - Assert `warnSilentFallback` was called ONCE with `{ feature: "cc-concierge", op: "prefill-guard-empty-history" }`.
   - Rationale: passing through is safe (Anthropic accepts an empty conversation + new user message); the warn provides the observability signal needed to detect a `dir`-arg drift in prod.

4. **`preserves resume when getSessionMessages throws`**
   - Stub `getSessionMessages` to reject with a synthetic Error.
   - The guard MUST NOT block the call. Pass `resume:` through unchanged.
   - Assert `sdkQuery` called with `options.resume === "abc"`.
   - Assert one `warnSilentFallback` was emitted with `{ feature: "cc-concierge", op: "prefill-guard-probe-failed" }` (separate op for distinguishability).

5. **`no-op when resumeSessionId is undefined`**
   - Invoke factory with `resumeSessionId: undefined`.
   - Assert `getSessionMessages` was NOT called (no probe on cold start).
   - Assert `warnSilentFallback` was NOT called.

6. **`uses the workspace cwd as the dir argument to getSessionMessages`** (drift-guard)
   - Assert `getSessionMessages` was called with `(resumeSessionId, { dir: <workspacePath> })`. The `~/.claude/projects/` lookup is keyed on the encoded cwd; passing the wrong dir returns an empty list silently (false negative — the persisted session exists but we don't see it).

**Mock infrastructure:**

The existing `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` already mocks `@anthropic-ai/claude-agent-sdk` and the `fetchUserWorkspacePath` / `getUserApiKey` / `getUserServiceTokens` deps. Reuse the same `mock.module` pattern there. Add a mock for `getSessionMessages` from the same module.

#### Research Insights — concrete test scaffold (verified against existing file)

The existing `cc-dispatcher-real-factory.test.ts` (verified at lines 20-94 of that file) declares its mocks via `vi.hoisted({ ... })` and registers them with `vi.mock(...)`. **Critically: line 74 already mocks `warnSilentFallback: vi.fn()`** — but as an inline `vi.fn()` *not* exposed via the hoisted object, so the existing factory tests cannot capture its calls. The new test file should hoist it explicitly:

```typescript
// apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockQuery,
  mockGetSessionMessages,        // NEW — captured spy for the guard's probe
  mockGetUserApiKey,
  mockGetUserServiceTokens,
  mockPatchWorkspacePermissions,
  mockReportSilentFallback,
  mockWarnSilentFallback,        // NEW — captured spy for guard fires
  mockBuildAgentEnv,
  mockBuildAgentSandboxConfig,
  mockSupabaseFrom,
} = vi.hoisted(() => ({
  mockQuery: vi.fn(),
  mockGetSessionMessages: vi.fn(),
  mockGetUserApiKey: vi.fn(),
  mockGetUserServiceTokens: vi.fn(),
  mockPatchWorkspacePermissions: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockBuildAgentSandboxConfig: vi.fn(),
  mockSupabaseFrom: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  getSessionMessages: mockGetSessionMessages,   // NEW — what the guard imports
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,   // captured (not anonymous)
}));

// (other mocks copied verbatim from cc-dispatcher-real-factory.test.ts:48-96)

import { realSdkQueryFactory } from "@/server/cc-dispatcher";
```

**Per-test assertions (scenario 1 worked example):**

```typescript
it("drops resume when persisted session ends with assistant message", async () => {
  mockGetSessionMessages.mockResolvedValueOnce([
    { type: "user", uuid: "u1", session_id: "s", message: {}, parent_tool_use_id: null },
    { type: "assistant", uuid: "a1", session_id: "s", message: {}, parent_tool_use_id: null },
  ]);

  await realSdkQueryFactory(makeArgs({ resumeSessionId: "s" }));

  // Probe was called with workspace cwd
  expect(mockGetSessionMessages).toHaveBeenCalledWith("s", { dir: WORKSPACE_PATH });

  // Resume was DROPPED before reaching the SDK
  expect(mockQuery).toHaveBeenCalledOnce();
  const opts = mockQuery.mock.calls[0][0].options;
  expect(opts.resume).toBeUndefined();

  // One Sentry warn under the canonical feature/op
  expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
  const [errArg, optsArg] = mockWarnSilentFallback.mock.calls[0];
  expect(errArg).toBeNull();
  expect(optsArg.feature).toBe("cc-concierge");
  expect(optsArg.op).toBe("prefill-guard");
  expect(optsArg.extra).toMatchObject({
    resumeSessionId: "s",
    lastType: "assistant",
    historyLength: 2,
  });
});
```

The `makeArgs` helper from `cc-dispatcher-real-factory.test.ts` (lines 156-170) takes `Partial<Parameters<typeof realSdkQueryFactory>[0]>` overrides — extend it to accept `resumeSessionId` and pass through.

**Drift-guard:** scenario 6 (the `dir: WORKSPACE_PATH` assertion) is the load-bearing test for plan Risk R2. Without it, an accidental `getSessionMessages(sessionId)` (no `dir`) call would silently return `[]` from the SDK's default lookup logic, the guard would see "user-terminated" (false negative), and the 400 would still fire in prod.

**Run:** `cd apps/web-platform && bun test test/cc-dispatcher-prefill-guard.test.ts` — all 6 must FAIL (no guard yet, so `getSessionMessages` is never called and `resume:` always passes through).

### Phase 2 — GREEN: implement the guard in `realSdkQueryFactory`

**File to edit:** `apps/web-platform/server/cc-dispatcher.ts`

**Change set:**

1. Add `getSessionMessages` to the import from `@anthropic-ai/claude-agent-sdk`. The existing import already brings `query as sdkQuery`; extend it.

2. Add `warnSilentFallback` to the import from `./observability` (the file already imports `reportSilentFallback`).

3. Inside `realSdkQueryFactory`, after the parallel `Promise.all([fetchUserWorkspacePath, getUserApiKey, getUserServiceTokens])` and after `patchWorkspacePermissions(workspacePath)`, BEFORE the `try { return sdkQuery(...) }` block, add:

   ```typescript
   // Thread-shape guard for #3250 — drop `resume:` when the persisted
   // session ends with an assistant message. `claude-sonnet-4-6`
   // (Concierge default at agent-runner-query-options.ts:114) rejects
   // assistant-terminated threads with a 400 prefill error. The persisted
   // session can end on `assistant` after any of: idle-reaper tear-down,
   // wall-clock runaway, cost-ceiling abort, container restart mid-turn.
   //
   // Probe failure is non-fatal: if `getSessionMessages` throws or returns
   // unexpected shape, pass `resume:` through unchanged (the SDK will
   // either succeed or surface its own error, which the runner's existing
   // catch handles). Mirror probe failure to Sentry under a distinct op
   // (`prefill-guard-probe-failed`) so we can distinguish probe outages
   // from genuine guard fires.
   let safeResumeSessionId: string | undefined = args.resumeSessionId;
   if (args.resumeSessionId) {
     try {
       const history = await getSessionMessages(args.resumeSessionId, {
         dir: workspacePath,
       });
       const last = history[history.length - 1];
       if (history.length === 0) {
         // Empty history for a known resumeSessionId is suspicious —
         // either the session file is missing, or `dir` lookup is wrong.
         // Pass resume through unchanged; Anthropic accepts an empty
         // conversation. Distinct op for Sentry filterability.
         warnSilentFallback(null, {
           feature: "cc-concierge",
           op: "prefill-guard-empty-history",
           message:
             "Persisted session has zero messages — possible dir-arg drift or missing session file",
           extra: {
             userId: args.userId,
             conversationId: args.conversationId,
             resumeSessionId: args.resumeSessionId,
             workspacePath,
           },
         });
       } else if (last && last.type === "assistant") {
         // Positive match (NOT `last.type !== "user"`) so a future SDK
         // SessionMessage variant (e.g., "system", "tool_result") falls
         // through to pass-through rather than a forced drop.
         warnSilentFallback(null, {
           feature: "cc-concierge",
           op: "prefill-guard",
           message:
             "Persisted session ends with assistant — dropping resume to prevent 400",
           extra: {
             userId: args.userId,
             conversationId: args.conversationId,
             resumeSessionId: args.resumeSessionId,
             lastType: last.type,
             historyLength: history.length,
           },
         });
         safeResumeSessionId = undefined;
       }
     } catch (err) {
       warnSilentFallback(err, {
         feature: "cc-concierge",
         op: "prefill-guard-probe-failed",
         extra: {
           userId: args.userId,
           conversationId: args.conversationId,
           resumeSessionId: args.resumeSessionId,
         },
       });
       // Fall through — pass resume: unchanged.
     }
   }
   ```

4. In the `sdkQuery({ options: buildAgentQueryOptions({ ... }) })` literal at line 535, change `resumeSessionId: args.resumeSessionId` to `resumeSessionId: safeResumeSessionId`.

5. Re-run the Phase 1 test file. All 6 must pass.

**Why no helper module:** This is a single 25-line block at one call site. Extracting a helper adds an indirection without saving a line of caller code. If we later add a second SDK call site that needs the same guard (legacy `agent-runner.ts startAgentSession` does NOT — Sonnet 4.6 issue is the model used by Concierge, but legacy domain-leader sessions also use Sonnet 4.6 today; see Risks below), we extract THEN. YAGNI for now.

### Phase 3 — REFACTOR: legacy runner audit

**File to read:** `apps/web-platform/server/agent-runner.ts`

The legacy `startAgentSession` also passes `resumeSessionId` through to `buildAgentQueryOptions`. The same model default applies (line 114 of `agent-runner-query-options.ts`). Therefore the same prefill 400 can fire on legacy domain-leader resume.

**Decision:** In Phase 3, audit whether legacy resume hits the same trigger conditions in production. The legacy runner's session lifecycle is different — it spawns a fresh CLI subprocess per message (per `soleur-go-runner.ts:11` comment) — so persisted sessions land in a different `~/.claude/projects/` subtree, and idle-reaper / wall-clock / cost-cap aborts behave differently. The empirical question: have we seen the prefill 400 on the legacy path?

**Acceptance:** If issue #3250 reports the symptom in a `/soleur:go` (cc) session and Sentry has zero matching `prefill` 400s on legacy domain-leader paths in the prior 90 days, defer the legacy guard with a tracking issue (file at the end of this plan). If Sentry shows ANY hit on legacy, fold the same guard into `startAgentSession` in this PR — extract `applyPrefillGuard(resumeSessionId, workspacePath, ctx)` to a sibling module shared by both call sites.

**Action item:** During Phase 3, run a Sentry query for `error.type=invalid_request_error message:*prefill*` over 90d. Capture the count + breakdown by feature tag in the PR description. The decision (defer vs. fold-in) is data-driven.

### Phase 4 — Verification & ship checklist

1. `bun test apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` — green.
2. `bun test apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — green (drift-guard for the factory shape).
3. `bun test apps/web-platform/test/agent-runner-query-options.test.ts` — green (drift-guard for the SDK options shape — the guard does NOT change this builder; it operates on `args` BEFORE the builder).
4. `cd apps/web-platform && bun run typecheck` — green.
5. `cd apps/web-platform && bun run build` — green (catches Next.js route-file gotchas; no route-file edits in this plan, so this is defensive).
6. Manual reproduction (optional, post-merge): trigger a wall-clock runaway in a dev session, send a follow-up. Pre-fix: 400. Post-fix: clean turn + Sentry warn at `feature=cc-concierge op=prefill-guard`.

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — add the thread-shape guard inside `realSdkQueryFactory` (Phase 2).

## Files to Create

- `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` — regression test (Phase 1).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Regression test `cc-dispatcher-prefill-guard.test.ts` exists, contains all 6 scenarios listed in Phase 1, and passes.
- [ ] `realSdkQueryFactory` no longer passes `resume:` to `sdkQuery` when the persisted session's trailing `SessionMessage.type === "assistant"`.
- [ ] When the guard fires, `warnSilentFallback` is called once with `{ feature: "cc-concierge", op: "prefill-guard" }` and `extra` containing `{ userId, conversationId, resumeSessionId, lastType, historyLength }` — verified by the test spy.
- [ ] Probe failures (`getSessionMessages` rejects or returns malformed shape) do NOT block the SDK call; they emit one `warnSilentFallback` with `op: "prefill-guard-probe-failed"` and pass `resume:` through unchanged.
- [ ] Empty `getSessionMessages` response for a non-empty `resumeSessionId` emits one `warnSilentFallback` with `op: "prefill-guard-empty-history"` and passes `resume:` through unchanged (observability hook for `dir`-arg drift detection).
- [ ] User-terminated threads pass through unchanged (test scenarios 2 and 5).
- [ ] The guard's assistant-detection uses positive match (`last.type === "assistant"`) — not negative match (`last.type !== "user"`) — so future SDK SessionMessage variants default to pass-through (test scenario 1 verifies the canonical case; codify the polarity in code review).
- [ ] `agent-runner-query-options.test.ts` and `cc-dispatcher-real-factory.test.ts` remain green (no drift in builder/factory shapes).
- [ ] Phase 3 Sentry audit performed; legacy guard either folded in (if hits found) or deferred via a new GitHub issue linked from the PR.
- [ ] CPO sign-off captured at plan time per `requires_cpo_signoff: true` (this plan's Domain Review section).
- [ ] Review pipeline includes `user-impact-reviewer` per `hr-weigh-every-decision-against-target-user-impact` and the bundle spec TR2.
- [ ] PR body uses `Closes #3250` (single-issue PR; standard close).
- [ ] Default Concierge model (`claude-sonnet-4-6`) is unchanged. Bundle spec non-goal honored.

### Post-merge (operator)

- [ ] After deploy, query Sentry for `feature:cc-concierge op:prefill-guard` over 24h. Non-zero hits confirm the guard is firing in prod (validates the hypothesis empirically).
- [ ] Query Sentry for `error.message:*prefill*` over the 24h window post-deploy. Should drop to ~zero from the cc-concierge surface.

## Test Scenarios

See Phase 1 — six scenarios cover: assistant-terminated → drop, user-terminated → preserve, empty → preserve, probe-throws → preserve + log probe-failed, no-resume → no-probe, dir-arg drift-guard.

## Domain Review

**Domains relevant:** Engineering, Product.

### Engineering (CTO lens, captured implicitly via repo research)

**Status:** reviewed (carried forward from brainstorm `## Domain Assessments` → Engineering).

**Assessment:** All four bugs are in the Command Center web app server/UI layer. #3250 is the architectural risk — the resume path reconstructs message history without enforcing user-terminated invariants. The right shape is a thread-shape guard at the boundary that emits a Sentry warn when it fires (per `cq-silent-fallback-must-mirror-to-sentry`).

**Plan response:** The plan implements exactly that — guard at the cc-dispatcher SDK boundary, `warnSilentFallback` on fire, probe-failure path explicit and observable. Drift-guards covered by reusing `cc-dispatcher-real-factory.test.ts` mock infrastructure. The legacy runner audit (Phase 3) is the architectural follow-through — confirm the guard isn't needed elsewhere or fold it in.

### Product (CPO lens, carried forward from brainstorm)

**Tier:** ADVISORY (modifies server-side behavior of an existing user-facing surface; no new UI).

**Status:** reviewed (carried forward from brainstorm — Product/UX leader assessment captured the trust-collapse framing inline).

**Assessment:** First-touch Concierge surface is brand-load-bearing. #3250 + #3251 together are a trust-collapse pattern. #3252 has both UX (interruption) and security (sandbox over-reach) framings — the security framing dominates if the fix is wrong.

**Plan response:** Threshold `single-user incident` inherited; CPO sign-off + `user-impact-reviewer` gates retained. No new copy or UI surface — when the guard fires the user sees a clean assistant turn (the SDK starts a fresh server-side session and replies normally), with no error rendered to the bubble. Brand-survival framing satisfied.

**Decision:** auto-accepted (pipeline) — no new UI surface; ADVISORY tier in pipeline mode auto-accepts per plan skill Phase 2.5 Step 2 rules. UX gate (wireframes / copywriter / spec-flow) NOT triggered — there is no UI to wireframe.

**Pencil available:** N/A.

**Brainstorm-recommended specialists:** None named for #3250 in the brainstorm's Capability Gaps section.

**Skipped specialists:** none.

## Open Code-Review Overlap

Three open code-review issues touch files this plan modifies:

- **#2955** (`arch: process-local state assumption needs ADR + startup guard`) — touches `cc-dispatcher.ts`. **Disposition: acknowledge.** Different concern (process-local state for `_runner` / `activeQueries`); orthogonal to the prefill-guard. Stays open. Re-evaluation criterion: when the runner is moved off-process or replicated, audit whether the guard's per-process Sentry rate-limit interacts with `mirrorWithDebounce`.
- **#3243** (`arch: decompose cc-dispatcher.ts into focused modules`) — touches `cc-dispatcher.ts`. **Disposition: acknowledge.** A 25-line addition inside `realSdkQueryFactory` does not move the decomposition needle; bundling would expand scope on a P1 fix. Stays open. The new helper (`applyPrefillGuard`) — if Phase 3 folds in legacy — would be a natural extraction target for #3243.
- **#3242** (`review: tool_use WS event lacks raw name field for agent consumers`) — touches the WS event shape, not the resume path. **Disposition: acknowledge.** Orthogonal concern. Stays open.

The remaining matches (#2962, #2955) are for `cc-dispatcher.ts` and a sibling helper-extraction concern; same disposition (acknowledge — orthogonal to prefill).

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Swap default model to one that supports prefill (e.g., `claude-opus-4-7`) | Bundle spec non-goal. The bug class isn't "model rejects prefill" — it's "we accidentally produce a prefill request." Hiding the bug under a permissive model leaves the malformed thread state intact for any model swap that re-narrows tolerance. |
| Pad the persisted session file on disk with a synthetic trailing `user` message | Fragile (writes into the SDK's owned storage; a future SDK version that adds checksums or a different on-disk format breaks silently). The SDK provides `getSessionMessages` for reading; the symmetric "writeSessionMessage" is intentionally not in the public surface. |
| Inspect every `SDKMessage` in the consume loop and abort the turn if we'd ever flip the trailing role to `assistant` | Wrong layer. The runner only emits `user` messages — the consume loop sees what came BACK from the SDK, not what we'd send next. The trigger is in the persisted-session file, not in the live stream. |
| Defer the fix and add a try/catch that maps the 400 to a friendly error | Breaks the brand-survival framing. Single-user incident threshold demands the user does not see "Soleur is broken" the first time. A friendly error is still an error in the bubble — and the conversation cannot recover without dropping the resume anyway. |
| Disable `persistSession` on the cc path entirely | Loses cross-restart conversation memory — the very feature the resume architecture (`2026-03-27-agent-sdk-session-resume-architecture.md`) was built to provide. Changes user-visible behavior far beyond the bug fix. |

## Risks

### R1 — Probe-call latency on every resumed turn

**Risk:** `getSessionMessages` reads from disk inside the SDK process. On a busy node with hundreds of sessions, this could add tens of ms to every cc-soleur-go cold dispatch.

**Mitigation:** The probe runs ONCE per `realSdkQueryFactory` invocation — that is, once per cold-Query construction, not once per turn. After the cold start, the runner reuses the same `Query` for all subsequent turns (per `soleur-go-runner.ts:11` comment). The factory is already async (DB fetches in parallel via `Promise.all`); add the probe AFTER `Promise.all` so it doesn't serialize against DB I/O. Net cost: one disk read on cold start. Acceptable.

**Verification:** Capture timing in the Phase 4 manual reproduction.

### R2 — `getSessionMessages` `dir` argument drift

**Risk:** The SDK looks up persisted sessions by encoded cwd inside `~/.claude/projects/<encoded(cwd)>/`. If we pass the wrong `dir`, the call returns `[]` silently — the guard sees an empty trailing entry and decides "user-terminated" (false negative — the persisted session DOES end on assistant, but we didn't see it).

**Mitigation:** Test scenario 6 explicitly asserts `getSessionMessages` was called with `(resumeSessionId, { dir: workspacePath })`. The factory already has `workspacePath` in scope from the `Promise.all` block. Drift-guard via the test.

### R3 — SDK API surface drift

**Risk:** `getSessionMessages` is in the SDK's public surface today (`sdk.d.ts:518`) but its stability is not declared. A future SDK version that renames or removes it would break the guard at build time.

**Mitigation:** TypeScript strict mode catches a removed export at `bun run build`. A renamed export would surface in the typecheck. The test scenario 4 (probe-throws) already covers runtime failure modes — even a behavioral change that turns the call into a no-op leaves the rest of the path intact. Trade-off: we accept the explicit dependency on `getSessionMessages` because the alternative (parsing `~/.claude/projects/<cwd>/<sid>.jsonl` directly) is strictly more brittle.

**Deepen-pass note:** Anthropic's [`claude-agent-sdk-typescript#14`](https://github.com/anthropics/claude-agent-sdk-typescript/issues/14) is the upstream feature request that introduced `getSessionMessages` as the supported API for inspecting persisted sessions. A recent SDK release fixed `getSessionMessages` dropping parallel tool results — meaning the upstream is actively maintaining and improving this surface. This is a stronger stability signal than "exported but undeclared." Probability of removal in the near term is low; probability of a breaking signature change is non-zero. The probe-throws test scenario (#4) is the durable mitigation regardless of how the surface evolves.

### R4 — The guard fires but the SDK still emits a 400 (residual cause)

**Risk:** Rare path where the persisted thread ends user-terminated but contains an unmatched `tool_use` deeper in history. The guard would not catch this.

**Mitigation:** Out of scope for the current cause. Capture as a tracking issue if the post-merge Sentry query (Acceptance Criteria post-merge) shows residual hits at `error.message:*prefill*` after the guard ships. Defer-not-decide: file the issue, do not extend this PR.

### R5 — Legacy runner has the same trigger but the guard doesn't cover it

**Risk:** `startAgentSession` in `agent-runner.ts` also passes `resume:` and uses Sonnet 4.6. Same prefill 400 mechanism could fire on domain-leader sessions.

**Mitigation:** Phase 3 audit. Decision is data-driven (Sentry 90d query). If hits found, fold the guard into a shared helper inside this PR. If not, file a tracking issue for the audit to recur in 30 days.

## Sharp Edges

- **The guard intentionally drops `resume:`, not the conversation history.** The SDK will start a fresh server-side session; the runner's `state.sessionId` rebinds to the new session_id from the first streamed message (same flow as a brand-new conversation). The user does NOT lose conversation context — the model starts a new session but the runner pushes the user's new prompt verbatim. Conversation memory degrades (the model does not see prior turns), but the alternative is a 400 in the bubble. This is a deliberate trade-off; document it in the PR description.

- **Do not extract the guard to a helper before Phase 3 decides legacy folding.** YAGNI: a single call site does not need a helper. If Phase 3 finds legacy hits, extract to `apps/web-platform/server/agent-prefill-guard.ts` exporting `applyPrefillGuard(args: { resumeSessionId, workspacePath, userId, conversationId }): Promise<{ safeResumeSessionId: string \| undefined }>`. Until then, inline.

- **`warnSilentFallback`, not `reportSilentFallback`.** This is a recovered, expected-occasionally state (every wall-clock fire / container restart will eventually trigger one on the next user message). Error level would flood Sentry with non-actionable noise. Warning is the right level per the `observability.ts` contract (line 117-122).

- **Probe-failure observability uses a distinct op (`prefill-guard-probe-failed`).** This is so a Sentry filter on `op:prefill-guard` reports actual guard fires, while `op:prefill-guard-probe-failed` reports SDK or filesystem outages. Mixing them would mask one with the other.

- **Three distinct ops, three distinct observability stories.** After the deepen-pass:
  - `op: "prefill-guard"` → guard activated, `resume:` was dropped (this is the success path firing — non-zero count = the bug class is being prevented in prod).
  - `op: "prefill-guard-probe-failed"` → `getSessionMessages` threw (SDK regression, FS outage, removed export). Diagnostic; should be near-zero in steady state.
  - `op: "prefill-guard-empty-history"` → probe returned `[]` for a non-empty `resumeSessionId`. Indicates either a brand-new session (benign) or `dir`-arg drift (bug). Watch the rate; a sudden spike means the guard is misconfigured.
  All three flow through `warnSilentFallback` (warn-level — none of these are user-blocking errors).

- **Positive-match polarity.** Use `last.type === "assistant"` (positive match), not `last.type !== "user"` (negative match). Positive match means: future SDK SessionMessage variants (e.g., `type: "system"` or `type: "tool_result"`) default to pass-through. Negative match would aggressively drop `resume:` for any non-user trailing entry — a regression that silently degrades context retention every time the SDK's persisted-message vocabulary widens.

- **Anthropic remediation pattern alignment.** This guard is Anthropic's officially recommended remediation pattern (a) — strip trailing assistant messages before the API call. We do NOT implement (b) "convert trailing assistant to user-role context" because it requires writing into a session storage we don't own (fragile per the Alternative Approaches table) and (c) "use `output_config.format`" doesn't apply (we're not doing structured-output prefill). Stick with (a).

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with concrete artifact and vector lines and a chosen threshold (`single-user incident`).

## Cross-References

- Issue #3250 — primary tracking issue for this PR.
- Bundle spec FR1 + TR1 + TR2 — owns the acceptance + observability + sign-off requirements.
- Brainstorm `## Domain Assessments` → Engineering and Product — carried forward into the Domain Review section above.
- Learning `2026-03-27-agent-sdk-session-resume-architecture.md` — the resume mechanism this guard hardens.
- Learning `2026-04-12-startAgentSession-catch-block-swallows-resume-errors.md` — established the message-replay-fallback pattern; the guard's "drop resume" branch is a defensive precursor that prevents the 400 from ever reaching the catch block.
- Learning `2026-04-12-missing-resume-session-on-existing-conversations.md` — confirms `resume_session` is wired end-to-end client-to-server today; rules out a "resume never sends" hypothesis.
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — observability contract.
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — sign-off contract.

### External references (deepen-pass)

- [Anthropic — Migrating to Claude 4 (covers prefill removal in 4.6+)](https://docs.anthropic.com/en/docs/about-claude/models/migrating-to-claude-4)
- [Anthropic — Claude Agent SDK: Working with sessions](https://platform.claude.com/docs/en/agent-sdk/sessions)
- [Anthropic — Claude Agent SDK TypeScript reference](https://platform.claude.com/docs/en/agent-sdk/typescript)
- [`anthropics/claude-agent-sdk-typescript#14` — `getSessionMessages` introduction](https://github.com/anthropics/claude-agent-sdk-typescript/issues/14)
- [`livekit/agents#4907` — peer report of the same 400 against Claude 4.6](https://github.com/livekit/agents/issues/4907)
- [`Kilo-Org/cloud#1425` — most precise external description of the persisted-partial-assistant trigger](https://github.com/Kilo-Org/cloud/issues/1425)
- [`microsoft/agent-framework#5008` — peer report against Claude 4.6 from the agent-framework cross-vendor harness](https://github.com/microsoft/agent-framework/issues/5008)
- [`langchain-ai/deepagents#1585` — confirms 400 fires on BOTH Sonnet 4.6 and Opus 4.6](https://github.com/langchain-ai/deepagents/issues/1585)
- [`crewAIInc/crewAI#4798` — additional peer corroboration](https://github.com/crewAIInc/crewAI/issues/4798)
- [`agno-agi/agno#7015` — frames the change as a permanent Anthropic API contract](https://github.com/agno-agi/agno/issues/7015)
