---
feature: feat-reasoning-chat-boxes
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-15-feat-reasoning-narration-plan.md
issue: 5370
---

# Tasks: Reasoning Narration — Live Status Line + Persisted Turn Summary

> Contract-before-consumer order. Run `soleur:deepen-plan` BEFORE `/work` (single-user-incident + ultrathink). Deepen-plan must resolve the Phase 5 emit-channel/leaderId plumbing (Kieran P1-1) before implementation.

## Phase 0 — Preconditions (grep, no code)
- [ ] 0.1 Read `conversations-tools.ts`, `tool-tiers.ts`, `permission-callback.ts`; confirm `cc-dispatcher.ts:741` `assertWriteScope` is a no-op + emit sites + `CC_ROUTER_LEADER_ID`.
- [ ] 0.2 Read `ws-client.ts:219-293` (`ChatState` + actions, `onclose:1228`).
- [ ] 0.3 Read `dsar-export.ts:419` allowlist + `dsar-export-allowlist.ts:13-17` cross-doc gate; `insert-draft-card.ts:65-71` tenant-client pattern.
- [ ] 0.4 Read `prompt-assembly.ts` + `constants.ts` (directive site).

## Phase 1 — DB contract + DSAR classification
- [ ] 1.1 `105_turn_summary_message_kind.sql`: `ADD COLUMN IF NOT EXISTS message_kind text` + DO-block CHECK guard; no `CONCURRENTLY`.
- [ ] 1.2 `105_turn_summary_message_kind.down.sql`.
- [ ] 1.3 **[CRITICAL]** `dsar-export.ts`: add `message_kind` to `MESSAGE_NON_REDACT_ALLOWLIST`.

## Phase 2 — Wire contract (types + zod)
- [ ] 2.1 `lib/types.ts`: 2 WSMessage members + `ChatTurnSummaryMessage` + `liveNarration: string|null` on ws-client `ChatState`.
- [ ] 2.2 `lib/ws-zod-schemas.ts`: 2 schemas + `flatTypeSchema` registration.
- [ ] 2.3 `tsc --noEmit` → fix every exhaustiveness rail the compiler reports.

## Phase 3 — Replay buffer (turn_summary only)
- [ ] 3.1 4 lockstep edits for `turn_summary` in `stream-replay-buffer.ts`; `reasoning_narration` NOT added. No `ws-handler.ts` edit.

## Phase 4 — Reducers
- [ ] 4.1 ws-client `ChatState`: set `liveNarration` on `reasoning_narration`; clear on `clear_streams`/`enter_stopping`/`timeout`→error/`onclose`/`connection_change`.
- [ ] 4.2 `chat-state-machine.ts`: `turn_summary` appends `ChatTurnSummaryMessage`.

## Phase 5 — Emit + agent channel
- [ ] 5.1 `narrate-tool.ts`: `narrate({message})` + `summarize({summary})`; register in `tool-tiers.ts` + `permission-callback.ts`.
- [ ] 5.2 `cc-dispatcher.ts` `emitNarration()`: narrate→frame; summarize→drop-if-aborted, redact-at-construction (drop-on-trip + Sentry), insert, emit buffered frame.
- [ ] 5.3 `insert-turn-summary.ts`: `getFreshTenantClient(founderId)`, `user_id=founderId`, `message_kind='turn_summary'`, redacted `content`.
- [ ] 5.4 `prompt-assembly.ts` + `constants.ts`: narration directive + cross-tenant prohibition; orchestrator-only `summarize`.

## Phase 6 — Render + hydrate
- [ ] 6.1 `chat-surface.tsx`: `turn_summary` case → `<TurnSummaryBubble>`; live line near Working badge; reconnect "Still working…" placeholder.
- [ ] 6.2 `turn-summary-bubble.tsx` (NEW): emerald checkmark + accent rail; `formatAssistantText`.
- [ ] 6.3 `ws-client.ts`: dispatch both frames; hydrate `message_kind='turn_summary'`; both-path teardown.
- [ ] 6.4 `api-messages.ts`: add `message_kind` to history `.select` (`:139-151`).
- [ ] 6.5 Wireframe: correct Frame 07 caption; add reconnect-mid-turn frame (or cross-ref `reconnect-resume-states.pen`).

## Phase 7 — Compliance docs (lockstep)
- [ ] 7.1 Amend PA-2 in `article-30-register.md` (b)+(g); no new PA.
- [ ] 7.2 Update privacy-policy, GDPR policy, Data Protection Disclosure, compliance-posture; record Art-22 negative determination; CLO-attestation.

## Phase 8 — Tests
- [ ] 8.1 `turn-summary-emit.test.ts` (insert + redact + abort=0 + tenant-client + seam).
- [ ] 8.2 `reasoning-narration-frame.test.ts` (not buffered; ws-client teardown per arm).
- [ ] 8.3 `turn-summary-bubble.test.tsx` (in `test/components/`).
- [ ] 8.4 DSAR: un-redacted export + conversation-delete cascade.
- [ ] 8.5 `tsc --noEmit` + `vitest run` green.
