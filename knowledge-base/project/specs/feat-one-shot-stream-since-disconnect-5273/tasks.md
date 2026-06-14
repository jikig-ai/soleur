---
title: "Tasks: stream-since-disconnect event-replay buffer (#5273)"
plan: knowledge-base/project/plans/2026-06-14-feat-stream-since-disconnect-replay-buffer-plan.md
issue: 5273
branch: feat-one-shot-stream-since-disconnect-5273
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — stream-since-disconnect replay buffer

> Derived from the finalized (deepened) plan. `single-user incident` threshold — the correctness
> floor is "never lie; fall back to honest v1 resume on any replay failure." Run tests via
> `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` and typecheck via
> `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`, NOT `bun test`).

## Phase 0 — ADR + preconditions

- [ ] 0.1 Write `knowledge-base/engineering/architecture/decisions/ADR-059-stream-since-disconnect-replay-buffer.md`:
  cite/extend AP-013 → ADR-027; mirror `TtlDedupMap` (`observability.ts:413-458`); record reattach
  seam (`:2500`, not `resume_session`), frame-keyed binding, `nextSeq`-counter-outlives-`clear`,
  ack-cursor, per-conv ring cap + per-buffer byte cap + global map cap + TTL backstop; Alternatives
  (Supabase-persist / Redis rejected). No ADR-042/046 miscite.
- [ ] 0.2 Verify preconditions (grep, not memory): `WSMessage` at `lib/types.ts:250`; rail at
  `ws-zod-schemas.ts:611-615`; `DISCONNECT_GRACE_MS` `ws-handler.ts:195`; `sendToClient` is the sole
  emit seam (`grep -rn "\.ws\.send(" apps/web-platform/server/`); runner = vitest, no root workspaces.

## Phase 1 — Type-union widening (contract first)

- [ ] 1.1 Add wire `seq?: number` to the buffered family (`stream_start`, `stream`, `tool_use`,
  `tool_progress`, `usage_update`, `stream_end`, `session_ended` — NOT `error`).
- [ ] 1.2 Add `resume_stream` (client→server, `ackSeq?: z.number().int().nonnegative()`) +
  `stream_replay{status:"incomplete"}` (per-status sub-union, NO begin/end) to `lib/types.ts` + zod.
- [ ] 1.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; fix every `_SchemaCovers*` /
  `never`-switch rail the new VARIANTS break. Grep for the `seq?` field consumer (no rail fires on a
  new optional field): `ws-client.ts:901` cost handler + `lastRenderedSeq`.

## Phase 2 — Server buffer module + write hook

- [ ] 2.1 `apps/web-platform/server/stream-replay-buffer.ts` mirroring `TtlDedupMap`: internal
  `BufferedFrame = StreamEvent-family & {seq:number}` (no `.seq!`); `frames`/`counters`/`lastActivity`
  maps; `stamp` (per-conv ring + byte cap + global map LRU cap, Sentry `op:buffer-overflow` on
  active-turn evict); `replayFrom` (`incomplete` on cursor-evict OR map-evict); `resetTurn` (frames
  only); `clear` (frames + lastActivity, NOT counters); `clearAll`/`reset` seam; TTL backstop via
  amortized sweep-on-write or existing reaper (no new timer).
- [ ] 2.2 Write hook at `sendToClient` (`ws-handler.ts:583`, before `JSON.stringify` `:586`): key on
  frame's `conversationId` (fallback `session.conversationId`); stamp only when session registered.
- [ ] 2.3 Wire `resetTurn` at turn-start; `clear` at abort (`agent-session-registry.ts:122`),
  grace-expiry (`:2571`), turn-end (with terminal-`session_ended` retention-until-grace exception),
  close, SIGTERM (`index.ts:234`).

## Phase 3 — Server reattach + replay (NOT resume_session)

- [ ] 3.1 Add `resume_stream` handler at the `pendingDisconnects`-cancel seam (`ws-handler.ts:2500-2506`),
  NOT `resume_session` (aborts live agent at `:1588`). Gate replay AFTER `user_id` (`:1613-1623`) AND
  repo-scope (`:1626-1632`) checks, keyed on verified `conv.id`; live-conversation match guard;
  `replayFrom(conv.id, clamp(ackSeq))`; emit frames verbatim on complete; `stream_replay{incomplete}`
  + `warnSilentFallback op:cursor-evicted` on miss; `reportSilentFallback op:ownership-mismatch` on fail.
- [ ] 3.2 Test the deterministic grace race + trailing-emit-after-clear window.
- [ ] 3.3 Encode the INVARIANT AC: a frame from the still-running agent AFTER reconnect is rendered.

## Phase 4 — Client ack cursor + dedup

- [ ] 4.1 Track `lastRenderedSeq`; send `resume_stream{ackSeq}` on transient reconnect (`ws-client.ts:680`).
- [ ] 4.2 Per-`seq` dedup at the `usage_update` handler (`ws-client.ts:901`): drop
  `seq <= lastRenderedSeq` before the additive accumulation (no cost double-count).
- [ ] 4.3 On `incomplete`: v1 honest history refetch; reconcile cost to authoritative (overwrite, not
  `prev ??`) at `seedCostData` (`:1216`).
- [ ] 4.4 Re-evaluate #3280 disposition (fold minimal slice if forced, else Acknowledge).

## Phase 5 — Agent-native parity (tracking issue only, post-merge)

- [ ] 5.1 Post-merge `gh issue create` V2 Agent/MCP stream-replay parity (labels: `type/feature`,
  `domain/engineering`, `app:web-platform`). No code phase.

## Phase 6 — Tests + green suite

- [ ] 6.1 Unit: stamp/seq/ring-cap/global-map-cap/byte-cap; `clear` preserves `counters` (stamp→clear→stamp
  continues, not 0); `BufferedFrame` forbids unstamped.
- [ ] 6.2 Integration (mock WS, LLM out of assertion path): invariant (live frame after reconnect);
  frame-keyed buffer; cost dedup; flapping; grace race; trailing-emit; ownership + cross-repo; ackSeq
  abuse clamp; turn-completed-while-gone + (e)∩(f); incomplete cost reconcile; stream/stream_end
  ordering; error-frame not-buffered/sanitized; SIGTERM clearAll + 1001.
- [ ] 6.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/stream-replay-buffer.test.ts`
  + full `tsc --noEmit` green.
- [ ] 6.4 PR body: `Ref #5240` + `Ref #5273` (NOT `Closes #5240`).
