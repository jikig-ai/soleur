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

## Phase 5 — Emit + agent channel (tool-result-handler pattern) — DONE
- [x] 5.1 `narrate-tool.ts`: `narrate({message})` + `summarize({summary})` PURE validate-and-return (length caps); explicit auto-approve tier in `tool-tiers.ts` (cc-path auto-approve list documented, no review gate).
- [x] 5.2 `cc-dispatcher.ts` `emitNarration()` — wired in `onToolUse` (block.input carries args), keyed on `mcp__soleur_platform__narrate`/`__summarize`, BEFORE the Bash/posture branch (supersedes the plan's `onToolResult` note per resume STATUS): narrate→redact(formatAssistantText+probe drop-on-trip)→frame; summarize→drop-if-aborted(`state.isAborted()`)→assertWriteScope seam→redact ONCE→same string to insert + buffered frame. Also: always-build `soleur_platform` MCP server (was c4Enabled-gated); register FQNs in allowlist + registered-tool-names.
- [x] 5.3 `insert-turn-summary.ts`: redact INSIDE helper; `getFreshTenantClient(founderId)`; FULL column set — `conversation_id`, `workspace_id=founderId`, `template_id='default_legacy'`, `user_id=founderId`, `role='assistant'`, `message_kind='turn_summary'`, redacted `content`.
- [x] 5.4 `NARRATION_PROMPT_DIRECTIVE` appended to the cc-router `effectiveSystemPrompt` (the actual producer; plan said prompt-assembly/constants but deepen-plan confirmed single-leader cc-router): narrate-at-milestones + summarize-once-on-success + cross-tenant prohibition.

## Phase 6 — Render + hydrate — DONE (read/render committed earlier; reconnect wired here)
- [x] 6.1 `chat-surface.tsx`: `turn_summary` case + live line; reconnect "Still working…" placeholder wired (`liveNarration ?? "Still working…"` during streaming — spec-flow Finding 4).
- [x] 6.2 `turn-summary-bubble.tsx` (committed earlier): PLAIN TEXT, NOT MarkdownRenderer; emerald + accent rail. Inert-HTML test added Phase 8.
- [x] 6.3 `ws-client.ts` (committed earlier): dispatch both frames; hydrate `message_kind='turn_summary'`; both-path teardown.
- [x] 6.4 `api-messages.ts` (committed earlier): `message_kind` in history `.select`.
- [ ] 6.5 Wireframe: Frame 07 caption / reconnect-mid-turn frame — DEFERRED (`.pen` polish; not an eng AC; non-blocking).

## Phase 7 — Compliance docs (lockstep) — DONE
- [x] 7.1 PA-2 amended in `article-30-register.md` (b)+(g) TOMs (14)-(16) + Art-22 negative determination; no new PA.
- [x] 7.2 privacy-policy §4.7, gdpr-policy §3.12 (new), data-protection-disclosure §2.3(i), compliance-posture #5370 entry; Art-22 negative determination; 3 SHA pins repinned (legal-doc-shas.ts). CLO-attestation = post-merge operator AC. Eleventy public mirrors NOT synced (non-T&C body-equivalence deferred per check-tc-document-sha.sh; separate remediation PR).

## Phase 8 — Tests — DONE
- [x] 8.1 `cc-dispatcher-turn-summary-emit.test.ts` (insert + redact + abort=0 + assertWriteScope seam + same-string-both-sinks).
- [x] 8.2 `reasoning-narration-frame.test.ts` (not buffered; ws-client teardown per arm).
- [x] 8.3 `turn-summary-bubble.test.tsx` (in `test/components/`).
- [x] 8.4 DSAR: `dsar-turn-summary.test.ts` — un-redacted subject export + mig-001 conversation-delete cascade.
- [x] 8.5 `tsc --noEmit` + `vitest run` green.
- [~] 8.6 Full NOT-NULL/CHECK/RLS column contract verified structurally against the live constraint defs (migrations 082/105/059/053) + pinned in `insert-turn-summary.test.ts`. Live rollback-tx insert rides the plan's post-merge DEV verification (migration 105 applies on merge via `web-platform-release.yml#migrate`; the post-merge DSAR DEV probe exercises a real `turn_summary` row).
- [x] 8.7 turn-summary-bubble inert-HTML test; same-redacted-string-to-both-sinks test; narrate redaction-drop test; narrate-tool length-cap + tier test.

## Phase 9 — Tripwire — DONE
- [x] 9.1 Filed #5384 (multi-tenant cross-tenant-prose structural control). Net-flow: Closing #5370 / Filing #5384 / Net 0.
