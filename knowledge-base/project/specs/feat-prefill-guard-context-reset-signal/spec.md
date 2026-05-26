---
title: Prefill-guard context-reset signal (model + user)
date: 2026-05-07
issue: "#3269"
parent_pr: "#3263"
brand_survival_threshold: single-user incident
status: spec
---

# Spec: Prefill-guard context-reset signal

## Problem Statement

PR #3263 added a thread-shape prefill-guard at the SDK call boundary in `apps/web-platform/server/agent-prefill-guard.ts`. When the persisted Claude Agent SDK session ends with `assistant`, the guard drops `resume:` so the SDK starts a fresh server-side session — preventing an HTTP 400 ("model does not support assistant message prefill") from reaching the user's chat bubble.

**The trade-off introduced:** when the guard fires, the model has zero memory of prior turns and the user has no UI signal that prior context was reset. Two reviewers (agent-native-reviewer, user-impact-reviewer) flagged this independently as a real-but-out-of-scope concern for the P1 hotfix. Three symptoms:

1. **Silent context reset (model-side):** `args.systemPrompt` is unchanged when the guard fires. The model gets no signal — Concierge confidently answers the new prompt as if it were turn 1.
2. **Tool_use orphan:** if the persisted thread ended on `assistant: { tool_use { id: T } }`, the runner had a pending UI-side approval, and the guard dropped `resume:` — the new fresh session has no knowledge of T. User says "yes, do that" → wrong/missing action, trust breach.
3. **No UI signal:** user-side render is identical regardless of whether the guard fired.

Per `hr-weigh-every-decision-against-target-user-impact` (threshold = `single-user incident`), this fix is user-brand-critical: hallucinated continuation or orphaned-tool follow-ups are paid-trust-product churn vectors.

## Goals

- Inform the **model** when the guard fires, with a sharper directive when the trailing message contained a `tool_use` content block.
- Inform the **user** via a UI-visible inline notice driven by a new WS event variant.
- Preserve idempotency, preserve probe-failure semantics, do not regress existing prefill-guard tests.
- Establish the WS `lifecycle-notice` event family (reason discriminator) for future variants (idle-reaper, cost-cap-abort).

## Non-Goals

- **MCP `get_session_state` tool (option (c) from issue body)** — deferred behind the issue's >10/7d Sentry trigger; no native MCP server exists in `apps/web-platform/server/mcp/`, so this is a separate roadmap initiative.
- **Re-confirmation modal before first post-reset tool execution** — CLO-flagged hardening layer; deferred to a separate tracking issue (touches the tool-approval flow surface, doubles scope).
- **Privacy-policy disclosure update on on-disk JSONL persistence vs. dropped model memory** — CLO domain, separate legal-document tracking issue.
- **Notice copy editing** — final user-facing wording delegated to `copywriter` agent at plan-time.

## Functional Requirements

### FR1: System-prompt notice on guard fire

When `applyPrefillGuard` returns `safeResumeSessionId: undefined` because the persisted session ended with `assistant`, the helper also returns a `contextResetNotice` string. Both call sites (`cc-dispatcher.ts:479` and `agent-runner.ts:1157`) append it to `args.systemPrompt` for that single turn before passing options to the SDK.

The notice must (a) tell the model that prior conversation context was reset, (b) instruct it not to act on assumed prior context, and (c) when the trailing message contained a `tool_use` content block, include a sharper directive: do NOT execute any action without explicit re-confirmation including the action name. The `tool_use` branch is detected by inspecting `last.message.content[].type === "tool_use"`.

### FR2: WS `context_reset` event on guard fire

When the guard fires, the runner emits exactly one WS message via `sendToClient` of shape `{ type: "context_reset"; reason: "prefill-guard" | "tool_use_orphan"; conversationId: string }`. The reason discriminator distinguishes the trailing-assistant case from the trailing-tool_use case.

### FR3: Client-side inline notice

The web-platform client renders an inline system-style message in the conversation thread when a `context_reset` WS event is received. Working draft copy: "Context was reset — Soleur may not remember earlier turns. Please re-state your request if it referenced earlier in this conversation." Final copy via `copywriter` agent at plan-time.

### FR4: No emission on probe failure or empty history

When `getSessionMessages` throws (existing `prefill-guard-probe-failed` Sentry op) or returns zero messages (existing `prefill-guard-empty-history` Sentry op), the guard passes `resume:` through unchanged and MUST NOT emit a `context_reset` WS event or a system-prompt notice. Existing Sentry ops are sufficient signal; the user's session is intact in those branches.

## Technical Requirements

### TR1: Helper return-shape extension

`ApplyPrefillGuardResult` gains an optional `contextResetNotice: string | undefined` field. When `safeResumeSessionId === undefined` due to assistant-terminated history, `contextResetNotice` is populated. In all other branches (cold start, user-terminated history, empty history, probe failure), it is `undefined`. Document: `agent-prefill-guard.ts` JSDoc.

### TR2: Both call sites updated

`cc-dispatcher.ts` (~line 597 system-prompt assembly, ~line 479 guard call) and `agent-runner.ts` (~lines 883-1173 system-prompt assembly, ~line 1157 guard call) consume the `contextResetNotice` and append it to their respective `args.systemPrompt` accumulators. The append point is after the existing services-list section so the notice is not overwritten.

### TR3: WS variant + Zod parser

`apps/web-platform/lib/types.ts:189` adds the `context_reset` variant to the `WSMessage` discriminated union. `apps/web-platform/lib/ws-zod-schemas.ts` adds the matching Zod schema and the `_SchemaCovers` proof updates. `apps/web-platform/test/ws-known-types-guard.test.ts` accepts the new type via the established pattern.

### TR4: Runner-side WS emit

The `context_reset` event is emitted from the runner (same site that consumes the guard result), not relayed through `ws-handler.ts`. Precedent: `agent-runner.ts` already imports and uses `sendToClient` for other variants. Idempotency: emit exactly once per guard fire, not per SDK retry.

### TR5: Test scenarios (in addition to existing prefill-guard tests)

- `agent-prefill-guard.test.ts`: helper returns `contextResetNotice` populated when last message is assistant; returns `contextResetNotice: undefined` in cold-start, user-final, empty-history, and probe-failure branches.
- `agent-prefill-guard.test.ts`: helper returns the tool-aware notice variant when trailing message has `tool_use` content block.
- `cc-dispatcher-prefill-guard.test.ts`: system-prompt receives appended notice exactly when guard fires; not appended otherwise.
- New `agent-runner-prefill-guard.test.ts` (or addition to existing test file): same assertion on the legacy path.
- `ws-protocol.test.ts`: `context_reset` round-trips through Zod schema; both reason variants parse.
- WS emit test: runner fires `sendToClient` exactly once per guard fire; not on SDK retry; not on probe failure.

### TR6: ADR for WS lifecycle-notice family

Create an ADR via `/soleur:architecture` documenting the `lifecycle-notice` WS event category — reason discriminator, invariants (server-emit-only, idempotent, single-turn signal), and the precedent for future variants (idle-reaper, cost-cap-abort, container-restart). Land in same PR or as a precursor commit.

### TR7: Sentry-op continuity

Existing `op:prefill-guard` warn emit (when guard fires on assistant-terminated history) remains. Do NOT add a second Sentry emit for the new WS event — the WS emission is the user-side signal; the existing Sentry op is the operator-side signal. Avoids double-counting in the >10/7d trigger threshold.

## Test Scenarios (Acceptance Criteria)

- AC1: Guard fires on assistant-terminated history → `contextResetNotice` populated, system-prompt receives notice, WS `context_reset` event emitted exactly once with `reason: "prefill-guard"`.
- AC2: Guard fires on tool_use-trailing history → notice contains the sharper "do not execute without re-confirmation" directive, WS event emits with `reason: "tool_use_orphan"`.
- AC3: Guard does NOT fire (user-final history) → no system-prompt mutation, no WS event.
- AC4: Probe failure → no system-prompt mutation, no WS event, existing `prefill-guard-probe-failed` Sentry op fires.
- AC5: Empty history → no system-prompt mutation, no WS event, existing `prefill-guard-empty-history` Sentry op fires.
- AC6: Multi-turn replay does not accumulate the notice across turns (single-turn signal only).
- AC7: WS `context_reset` Zod-parses on both reason variants; round-trips through ws-known-types-guard.

## User-Brand Impact

**Artifact:** Concierge / agent-runner conversation continuity.

**Vector:** Silent context loss — user follow-up referencing prior turns or "yes, do that" referencing a proposed tool action; bot executes wrong action / no action / hallucinated continuation.

**Threshold:** `single-user incident`. CPO + user-impact-reviewer sign-off required at plan and review time.

## Cross-references

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-prefill-guard-context-reset-signal-brainstorm.md`
- Issue: #3269
- Parent PR: #3263
- Plan that acknowledged this as deliberate trade-off: `knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md` §"Sharp Edges"
- Helper: `apps/web-platform/server/agent-prefill-guard.ts`
- Call sites: `apps/web-platform/server/cc-dispatcher.ts:479,597`, `apps/web-platform/server/agent-runner.ts:1157,883-1173`
- WS taxonomy: `apps/web-platform/lib/types.ts:189`, `apps/web-platform/lib/ws-zod-schemas.ts`
