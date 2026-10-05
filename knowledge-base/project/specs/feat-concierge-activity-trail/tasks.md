# Tasks — feat-concierge-activity-trail

Derived from `knowledge-base/project/plans/2026-10-05-feat-chat-working-status-trail-plan.md` (post-panel, operator-confirmed rebind).

## Phase 1 — PR1: WS boundary repair (hotfix)

- [ ] 1.1 Delete `apps/web-platform/lib/ws-known-types.ts` and its import in `lib/ws-client.ts` (~line 26 import, ~:833 pre-check call)
- [ ] 1.2 In `ws-client.ts` parse-failure path: split ops — discriminator-miss (`type` matched no schema variant) → `op: ws-unknown-event`; shape-miss → `op: ws-zod-parse-failure`
- [ ] 1.3 Delete `test/ws-known-types-guard.test.ts`; create `test/ws-boundary.test.ts`: bogus type → `ws-unknown-event` breadcrumb + no dispatch; valid `reasoning_narration` → `set_live_narration`
- [ ] 1.4 File `soleur:incident` PIR for the ~4-month silent frame-drop, naming all 7 dropped paths (`reasoning_narration`, `turn_summary`, `command_stream`, `stream_replay`, `resume_stream`, `autonomous_disclosure`, `autonomous_posture`, `revocation_notice`, `abort_turn`, `autonomous_disclosure_response`); link in PR body
- [ ] 1.5 Verify `_SchemaCovers` compile rail still holds; `tsc --noEmit` clean; PR body names rollback (revert)

## Phase 2 — PR2: consolidated status box + activity trail

- [ ] 2.1 `chat-state-machine.ts`: add `activity?: ActivityEntry[]` + `interrupted?: boolean` to `ChatTextMessage` (it lives here, not lib/types.ts); `startedAt` on entries + chip entries
- [ ] 2.2 Append logic: on `tool_use`/`reasoning_narration`, push previous live entry → `activity[]` (consecutive-dedup, `MAX_ACTIVITY_ENTRIES` cap); seed `activity[]` from pruned `tool_use_chip` labels at bubble creation
- [ ] 2.3 `sweepTransitional` helper (shared): on `clear_streams` + `enter_stopping` sweep `thinking`/`tool_use`/`streaming` → `state: undefined` + `interrupted: true`, strip `retrying`/`livenessRearms`
- [ ] 2.4 `findInterruptedBubble(leader)` rebind — checked BEFORE every transitional entry path (chip branch, `tool_use`, `tool_progress`, `stream`, `command_stream`, `stream_start`): clear flag, resume state, trail continues
- [ ] 2.5 Re-key `activeStreams` → `Map<leaderId, messageId>` + `findIndex` reads (~10 sites + ~150 test constructions); add `type === "text"` guards on `tool_use`/`stream_end`/gate sweeps; collapse `spawnIndex` → `Set<spawnId>`
- [ ] 2.6 `message-bubble.tsx`: render live line (`liveNarration`, aria-live) + `<ActivityTrail>` inside box; `interrupted` neutral chip (no Working pill/✓/amber); elapsed in `aria-hidden` node ticking at render
- [ ] 2.7 `activity-trail.tsx` (new): dimmed priors (≥4.5:1 `--text-muted`, NOT .pen opacities), latest highlighted, ≤5 + "…and N more step(s)" singular-aware; trail renders only when bubble live-ish (transitional or `interrupted`) — no `stripTrail`
- [ ] 2.8 `chat-surface.tsx`: delete standalone `live-narration` slot; fold `awaitingUserInput` suppression (badge+live-line suppressed, trail visible, border neutral, newest row normal weight); update `mocks/use-websocket.ts` + 5 test files referencing the slot/`liveNarration`
- [ ] 2.9 `session_ended` copy: full reason→copy map + non-echoing fallback; `user_aborted` → "Stopped — send a new message to continue."
- [ ] 2.10 Fold `toolsUsed` accumulation into `activity[]` (done-state "Used:" chips read dedup'd trail — one accumulator)
- [ ] 2.11 `server/tool-labels.ts`: `mapBashVerb` widening per Sentry 124542794 distribution; git-subcommand allowlist → business nouns; U+2026 normalization; label shape test (gerund + banned tokens); re-check `doppler` label

## Phase 3 — Tests + verification

- [ ] 3.1 `test/activity-trail.test.tsx` — render/dedup/cap/singular/dim/aria
- [ ] 3.2 `test/chat-state-machine-activity.test.ts` — append, push-prev, seed, cap, sweep arms, rebind before chip branch, id-key reads, `type==="text"` guards, memo stability on non-tip messages
- [ ] 3.3 Update `chat-surface-awaiting-input.test.tsx` (slot removed, suppression folded), `reasoning-narration-frame.test.ts`, `cc-turn-end-wire.test.ts`, `chat-reducer.test.ts`, `chat-state-machine-connection.test.ts`
- [ ] 3.4 Browser QA (soleur:qa): one box → trail grows → navigate away + return mid-turn → one Working box → turn ends → Done card; screenshots
- [ ] 3.5 Post-PR1 rollout observation (7-day window): `ws-unknown-event` trend, narration cadence (feeds `NARRATION_PROMPT_DIRECTIVE` decision), `stream_replay`/autonomous surfaces never-run paths
