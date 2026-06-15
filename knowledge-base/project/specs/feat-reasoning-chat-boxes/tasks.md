---
feature: feat-reasoning-chat-boxes
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-15-feat-reasoning-narration-plan.md
issue: 5370
---

# Tasks: Reasoning Narration — Live Status Line + Persisted Turn Summary

> Contract-before-consumer order. Run `soleur:deepen-plan` BEFORE `/work` (single-user-incident + ultrathink). Deepen-plan must resolve the Phase 5 emit-channel/leaderId plumbing (Kieran P1-1) before implementation.

> **STATUS (2026-06-15, in progress):** Phases 0–4 + Phase 6 read/render path DONE, committed, pushed, tsc green, touched suites green (9 commits beyond main on `feat-reasoning-chat-boxes`). The full wire/schema/replay/reducer/persistence-read/render CONTRACT is in place and **inert-safe** (nothing emits the frames yet, so no behavior change on deploy). REMAINING: **Phase 5 (emit — the producer)**, **Phase 7 (4 legal docs + PA-2)**, **Phase 8 (dedicated test files)**. Phase 5 has a structural prerequisite: the `soleur_platform` MCP server in `cc-dispatcher.ts:1538` is currently built ONLY when `c4Enabled` — narrate/summarize must be registered unconditionally (always-build the server, merge C4 tools when enabled). Emit in `onToolUse` (block.input carries the message/summary), keyed on `mcp__soleur_platform__narrate`/`__summarize`; summarize reads the dispatch abort-state (`consumeForAbort`/`_aborted`, cc-dispatcher ~536) to drop on aborted/stopping. Phase 6 reconnect "Still working…" placeholder was deferred (needs a narration-seen-this-turn signal — wire with emit).

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

## Phase 5 — Emit + agent channel (tool-result-handler pattern)
- [ ] 5.1 `narrate-tool.ts`: `narrate({message})` + `summarize({summary})` as PURE validate-and-return factories (capture only userId; length-cap args); explicit tier in `tool-tiers.ts` + `permission-callback.ts` (document cc-path is auto-approve, no review gate).
- [ ] 5.2 `cc-dispatcher.ts` `emitNarration()` in `onToolResult` (`:2602`), BRANCH BEFORE `:2608` guard: narrate→redact(formatAssistantText+probe drop-on-trip)→frame; summarize→drop-if-aborted(read dispatch state)→redact ONCE→same string to insert + buffered frame.
- [ ] 5.3 `insert-turn-summary.ts`: redact INSIDE helper; `getFreshTenantClient(founderId)`; FULL column set — `conversation_id`, `workspace_id=founderId` (solo-pin), `template_id='default_legacy'`, `user_id=founderId`, `role='assistant'`, `message_kind='turn_summary'`, redacted `content`.
- [ ] 5.4 `prompt-assembly.ts` + `constants.ts`: narration directive + cross-tenant prohibition; orchestrator-only `summarize`.

## Phase 6 — Render + hydrate
- [ ] 6.1 `chat-surface.tsx`: `turn_summary` case → `<TurnSummaryBubble>`; live line near Working badge; reconnect "Still working…" placeholder.
- [ ] 6.2 `turn-summary-bubble.tsx` (NEW): PLAIN TEXT (`<p whitespace-pre-wrap>` + `formatAssistantText`), NOT MarkdownRenderer; emerald checkmark + accent rail. Test: inert `<script>`/`<img onerror>`.
- [ ] 6.3 `ws-client.ts`: dispatch both frames; hydrate `message_kind='turn_summary'` (unknown kind THROWS, no MarkdownRenderer fallthrough); both-path teardown.
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
- [ ] 8.6 Insert against real-Postgres/rollback-tx (not mock) — catches 23502/RLS on the full column set.
- [ ] 8.7 turn-summary-bubble inert-HTML test; same-redacted-string-to-both-sinks test; narrate redaction test.

## Phase 9 — Tripwire (file at /work)
- [ ] 9.1 File follow-up issue: multi-tenant cross-tenant-prose structural control (when a 2nd human tenant shares the surface, directive-only control is inadequate).
