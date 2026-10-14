---
title: "feat: stream-since-disconnect event-replay buffer for backend agent sessions"
date: 2026-06-14
issue: 5273
umbrella_issue: 5240
branch: feat-one-shot-stream-since-disconnect-5273
type: feature
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
detail_level: a-lot
---

# feat: stream-since-disconnect event-replay buffer ✨ (#5273)

## Overview

When a SOLEUR backend agent session (the user-facing chat where leaders run real work) loses
its WebSocket mid-turn, the client today re-fetches only **persisted** history on reconnect.
Stream events emitted **during** the gap — assistant text deltas, `tool_use` labels,
`tool_progress` heartbeats, `usage_update` cost ticks — are never persisted until turn-end, so
they are **lost**. The reconnecting user sees a frozen bubble that silently "jumps" to the final
state (or stalls) instead of resuming the live stream.

This feature adds a **server-side, in-memory, per-conversation ring buffer** that captures every
server→client WS frame as it is emitted, tagged with a monotonic per-conversation `seq`. On
reconnect the client sends the last `seq` it rendered (an **ack cursor**); the server **replays**
every buffered frame with `seq > ackSeq`, then resumes live streaming. The buffer is transient
(cleared on turn-end, abort, or grace-period expiry), bounded (ring with a hard cap), and
introduces **no DB schema change**.

This is the highest-value follow-up identified in the #5240 brainstorm (decision #6), gated on v1
(#5256, MERGED 2026-06-14) which made reconnect *honest*; this makes the common brief-drop case
*seamless*.

**Why "A LOT" detail:** `single-user incident` brand-survival threshold + a discriminated-union
widening (`WSMessage`) + multiple concurrency races (grace-window vs reattach, flapping
disconnect, multi-tab, abort-before-replace) + an unbounded-memory failure mode. These are
substance-level risks that style-only plan review cannot catch; deepen-plan + domain agents run.

## Enhancement Summary

**Deepened on:** 2026-06-14
**Sections enhanced:** Overview, Premise Validation, Research Reconciliation, Implementation
Phases 0-6, Acceptance Criteria, Risks, Sharp Edges, Observability.
**Agents used:** architecture-strategist, data-integrity-guardian, security-sentinel,
code-simplicity-reviewer, spec-flow-analyzer, observability-coverage-reviewer, type-design-analyzer,
+ Explore (WS-resume protocol research).

### Key improvements (from multi-agent review — ALL applied below)
1. **P0 (spec-flow) — replay must NOT route through `resume_session`.** That handler calls
   `abortActiveSession(userId, session)` at its first line (`ws-handler.ts:1588`), which kills the
   still-running agent and marks the conversation `completed`. Routing replay there re-introduces
   the abort the 30s grace window exists to avoid → "replayFrom returned frames" is a PROXY; the
   invariant "user sees the live in-flight turn continue" fails. **Replay is now a non-destructive
   reattach at the `pendingDisconnects`-cancel seam (`ws-handler.ts:2500-2506`)** via a new
   `resume_stream` control frame — NOT the `resume_session` path.
2. **P0 (architecture/data-integrity/security) — buffer key mismatch.** `sendToClient` is keyed by
   `userId` (one socket per user); the buffer is keyed by `conversationId`. The write hook now keys
   on the **frame's** `conversationId` (threaded explicitly into the stamp call), never blindly on
   `session.conversationId` — closes same-user cross-conversation contamination.
3. **P0 (data-integrity) — cost double-count.** The `usage_update` handler is at `ws-client.ts:901`
   (`(prev?.totalCostUsd ?? 0) + msg.totalCostUsd`), NOT in the reducer; it is unconditionally
   additive with no seq guard. Dedup must be added THERE, dropping frames with `seq <= lastRenderedSeq`.
4. **P0 (architecture) — pattern is NOT novel.** `TtlDedupMap` (`observability.ts:413-458`) is a
   near-exact lifecycle twin (ttlMs / sweepInterval / maxSize / oldest-eviction / reset seam), and
   **AP-013 → ADR-027 (process-local state for runner sessions)** is the governing principle.
   ADR-059 cites/extends AP-013/ADR-027 and mirrors `TtlDedupMap`; the mis-cited ADR-042/046 are removed.
5. **P1 — global Map-cardinality cap** added (not just the per-conversation ring): mirror
   `TtlDedupMap.maxSize`; LRU-evict whole buffers, emit `incomplete` for evicted conversations.
6. **P1 — `nextSeq` survives `clear`.** Monotonic-across-turns only held for `resetTurn`; `clear`
   (abort/grace/turn-end) deletes the Map entry and rewinds `nextSeq` to 0 → a resumed conversation
   could replay already-rendered frames. The monotonic counter now lives in a separate
   `Map<conversationId, nextSeq>` that outlives `clear`.
7. **Simplification — drop `stream_replay{begin/end}`; keep only `incomplete`.** Per-`seq` dedup
   (`seq <= lastRenderedSeq`) makes the replay window redundant and removes a dangling-window race.
8. **Type-design — `stream_replay` becomes a per-status discriminated sub-union; internal
   `BufferedFrame = StreamEvent-family & { seq: number }` (required seq)** while the wire union keeps
   `seq?` for back-compat — eliminates `seq!` non-null assertions in the buffer module.
9. **Observability — ownership-mismatch + buffer-overflow each get their own `reportSilentFallback`
   mirror**; discoverability_test becomes a real no-SSH data-pull.
10. **Phase 5 (MCP parity) demoted to a tracking issue** (its default outcome anyway).

## Premise Validation

Checked at plan time:
- **#5240 (umbrella, "Design durable session/workspace resume + reconnect")** — OPEN. It is the
  parent design issue with multiple follow-ups (#5273 is one); it correctly stays open. Use
  `Ref #5240`, NOT `Closes`.
- **#5256 (v1 PR, FR1/FR4 verified rebind + honest status)** — **MERGED 2026-06-14T14:26:12Z**.
  This satisfies #5273's re-evaluation criterion ("pick up once v1 (#5240) merges"). Premise holds.
- **Mechanism vs ADR corpus** — `grep` of `knowledge-base/engineering/architecture/decisions/`
  for `ring buffer|event.replay|stream.since|ack cursor|reattach|DISCONNECT_GRACE` returned zero
  hits for the *exact* replay-buffer name, BUT the deepen-plan architecture review found the
  **governing precedent**: **AP-013 "Process-local state for runner sessions" → ADR-027**
  (`principles-register.md:21`; `ADR-027-process-local-state-for-runners.md`) is the tier principle,
  and **`TtlDedupMap` (`observability.ts:413-458`)** is a near-exact lifecycle twin (a bounded,
  TTL-swept, oldest-eviction, class-based, process-local cache with a test-reset seam). The buffer
  is therefore an *extension* of an established pattern, not novel. **ADR-059 (Phase 0) cites/extends
  AP-013/ADR-027 and mirrors `TtlDedupMap`.** (Correction: the earlier draft mis-cited ADR-042
  [Anthropic-SDK-in-Inngest] and ADR-046 [Inngest one-shot scheduler] as in-process-state precedents
  — they are not; removed.)
- **Cited seams verified in code** (all confirmed against worktree HEAD): `sendToClient`
  (`ws-handler.ts:583`), `DISCONNECT_GRACE_MS=30_000` (`ws-handler.ts:195`), `pendingDisconnects`
  keyed `${userId}:${conversationId}` (`ws-handler.ts:299-300, 2567-2578`), reconnect-cancel
  (`ws-handler.ts:2500-2506`), `resume_session` (`ws-handler.ts:1584`), `WSMessage`
  (`lib/types.ts:250`), exhaustiveness rail (`lib/ws-zod-schemas.ts:611-615`).

No external premises beyond the above to validate.

## Research Reconciliation — Spec vs. Codebase

The brainstorm left four Open Questions; code research resolved most. Reconciliation:

| Brainstorm claim / open question | Codebase reality (file:line) | Plan response |
|---|---|---|
| OQ1: "Binding scope conversation vs user-level — resolve at plan/ADR time" | `pendingDisconnects` is **already conversation-scoped** (`${userId}:${conversationId}`, `ws-handler.ts:2577`); `ClientSession.conversationId` present when active (`:213`). Buffer key is therefore `(conversationId, seq)`, NOT userId-scoped. | Resolved: buffer keyed by `conversationId`. Recorded in ADR (Phase 0). |
| "In-memory ring buffer; no DB schema change" | No `seq`/`sequence` field exists on any `WSMessage` variant today (`lib/types.ts:250-450`); ordering relies on TCP. | Plan **adds** a server-stamped `seq?: number` to the streaming `WSMessage` family + a new `stream_replay` boundary frame. No DB column. |
| "Ack cursor must survive multiple re-attaches (flapping)" | Reconnect-cancel clears the pending-abort timer (`ws-handler.ts:2500-2506`) but does **not** today carry an ack cursor — the client has no `seq` to ack. | Plan adds a new `resume_stream{ackSeq?: number}` client→server frame (NOT on `resume_session`) and server replay-from-cursor. Cursor is client-supplied each reconnect → survives flapping by construction. |
| OQ3: "Grace-window / abort race — define deterministic either/or" | Grace timer set on disconnect (`:2567`); cancelled on reconnect re-auth (`:2500`). The race is: reconnect arriving **after** `abortSession` fires. | Plan defines: reconnect **before** grace expiry → cancel abort (`:2500`), **reattach without abort** + replay buffer + resume live. Reconnect **after** → buffer already cleared by abort path → fall through to honest v1 resume. No new lie. |
| **[P0 spec-flow] Where does replay attach?** Draft v1 said the `resume_session` handler. | `resume_session` calls `abortActiveSession(userId, session)` at its **first line** (`ws-handler.ts:1588`), killing the still-running agent + marking the conversation `completed`. | **Replay attaches at the `pendingDisconnects`-cancel seam (`ws-handler.ts:2500-2506`)** via a new non-destructive `resume_stream` control frame — NOT `resume_session`. The grace window keeps the agent alive; reattach must NOT abort it. The acceptance criterion is phrased as the INVARIANT ("a frame emitted by the still-running agent *after* reconnect is rendered by the client"), not the proxy ("replayFrom returned frames"). |
| **[P0 arch/security] Buffer key (`conversationId`) vs emit seam (`userId`)** | `sendToClient(userId, msg)` (`:583`) resolves the single per-user socket; a backgrounded run on conv A can emit while the socket is bound to conv B (`activeSessions` keyed `${userId}:${conversationId}:${leaderId}`). | Write hook keys the buffer on the **frame's** `conversationId` (threaded explicitly into the stamp call; `usage_update` and others already carry `conversationId`), falling back to `session.conversationId` ONLY when the frame lacks one. Never blindly `session.conversationId`. Stamp before `JSON.stringify` at `:586`. |
| **[P0 data-integrity] `usage_update` dedup location** | The handler is at `ws-client.ts:901` (`(prev?.totalCostUsd ?? 0) + msg.totalCostUsd`) — unconditionally additive, NOT in the reducer (`chat-state-machine.ts`). No seq/id guard. Server-side persist (`cost-writer.ts:309`) happens at emit time, NOT on replay (replay re-emits the frame only) → server safe. | Client dedup added at `ws-client.ts:901`: drop `usage_update` frames with `seq <= lastRenderedSeq` BEFORE the additive accumulation. Test: replayed usage does not move `totalCostUsd`. |
| **[P1 data-integrity] `nextSeq` rewind on `clear`** | Draft claimed monotonic-across-turns; true for `resetTurn` but `clear` (abort/grace/turn-end/close) deletes the whole `Map` entry → a resumed conversation restarts `nextSeq` at 0, and a client holding `lastRenderedSeq=5` would replay new `seq 0..10` frames as if unseen. | The monotonic counter lives in a **separate `Map<conversationId, nextSeq>` that outlives `clear`** (frames cleared; counter persists). Never rewind for a conversationId that may be resumed. |
| OQ4 / brainstorm CPO: "turn-completed-while-gone" | `session_ended{reason:"turn_complete"}` emitted at turn end (`agent-runner.ts:2128`); buffer would hold it. | In scope: if the buffered tail contains a terminal `session_ended`, replay delivers it → client renders "ended while you were away — here's the result" via existing state machine. No separate signal needed. |
| Stream-text protocol semantics | Cumulative-snapshot, **replace-not-append** (learning `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`). | Replay preserves emission order; client's existing replace semantics make replayed partials idempotent. Buffer stores frames verbatim. |
| Workspace-durability hypothesis (issue #5240 leading theory) | FALSE — persistent Hetzner volume, single instance (v1 brainstorm headline). | Out of scope here; no re-clone. Buffer is purely the **stream** gap, orthogonal to workspace binding (fixed in #5256). |

## User-Brand Impact

**If this lands broken, the user experiences:** a reconnecting chat that either (a) duplicates
already-rendered assistant text / tool cards (replay overlap not deduped → split-brain bubbles), or
(b) replays a stale tail over a turn that already completed, or (c) leaks server memory until OOM
(unbounded buffer never cleared) taking down the single backend instance for ALL conversations.

**If this leaks, the user's workflow/conversation content is exposed via:** the in-memory buffer
holds verbatim assistant output + tool I/O (already-redacted at the emit boundary per
`message-bubble`/server sanitization). Cross-user leak is only possible if the buffer key
(`conversationId`) is ever resolved against the wrong session — the replay path MUST re-verify the
reconnecting session's authenticated `userId` owns the `conversationId` before replaying (defense
in depth atop RLS), exactly the pattern in `2026-04-11-deferred-ws-conversation-creation`.

**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work` begins (the v1
brainstorm CPO already framed the trust model; confirm CPO carry-forward or invoke CPO domain
leader). `user-impact-reviewer` will be invoked at review-time (review/SKILL.md conditional block).

## Open Code-Review Overlap

5 open code-review issues touch files this plan edits. Dispositions:

- **#3280 — refactor useWebSocket history-fetch into reducer-driven state machine** (`lib/ws-client.ts`).
  **Fold in (partial) — re-evaluate at /work.** This plan adds a reconnect ack-cursor + replay
  branch to the exact `ws-client.ts` reconnect/history-fetch path #3280 targets. If the replay
  branch is cleanly expressible without the full reducer refactor, **Acknowledge** and leave #3280
  open (the refactor is larger than this feature warrants — YAGNI). If the replay logic forces
  touching the history-fetch state, fold the minimal slice and note `Ref #3280` (not `Closes`,
  since the full refactor is broader). Decide at /work Phase 4 once the branch shape is known.
- **#3374 — emit `slot_reclaimed` WS frame so agent clients react in-band** (`ws-handler.ts`,
  `ws-client.ts`, `ws-zod-schemas.ts`). **Acknowledge.** Different concern (ledger-divergence
  recovery frame). This plan widens the same union + zod schema, so the implementer should be aware
  of #3374's proposed frame to avoid a `seq`/discriminator collision, but #3374 is not folded.
- **#3242 — `tool_use` WS event lacks raw `name` field for agent consumers** (`agent-runner.ts`,
  `lib/types.ts`, `ws-zod-schemas.ts`). **Acknowledge.** Adjacent (same emit site + union), but a
  distinct field addition. If `/work` is already editing the `tool_use` variant for `seq`, the
  implementer MAY fold #3242's `name` field in the same diff (cheap, `Closes #3242`); otherwise
  leave open. Decide inline.
- **#3374 / #2191 — `clearSessionTimers` helper + refresh-timer jitter** (`ws-handler.ts`).
  **Acknowledge.** Timer-lifecycle refactor; orthogonal to buffer. Not folded.
- **#3374 noted twice above** (spans 3 files); single disposition stands.

## Implementation Phases

### Phase 0 — Architecture decision + preconditions (no code)

0.1 **Write ADR** `knowledge-base/engineering/architecture/decisions/ADR-059-stream-since-disconnect-replay-buffer.md`
(next free number; `ls` decisions dir confirms ADR-058 is highest). Decisions to record:
- **Buffer tier:** in-memory, per-conversation, on the single backend instance (justified by v1
  finding: single `hcloud_server.web`, no horizontal scaling → a reconnect always lands on the same
  process). **Extends AP-013 → ADR-027 (process-local state for runner sessions)** and **mirrors
  `TtlDedupMap` (`observability.ts:413-458`)** for lifecycle discipline (ttlMs / sweepInterval /
  maxSize / oldest-eviction / `reset()` test seam). **Alternatives considered:** (a) persist to
  Supabase (rejected — adds Art. 30 surface per CLO, TTL management, write amplification on the hot
  stream path; YAGNI at single-instance); (b) Redis (rejected — new infra dependency vs the
  established in-process pattern of AP-013/ADR-027).
- **Reattach seam:** the `pendingDisconnects`-cancel branch (`ws-handler.ts:2500-2506`), via a new
  **non-destructive `resume_stream` control frame** — NOT `resume_session` (which aborts the live
  agent at `:1588`). The grace window keeps the agent running; reattach must preserve it.
- **Binding authority:** the **frame's** `conversationId` at the write hook; `session.conversationId`
  fallback only when the frame lacks one (resolved per Research Reconciliation).
- **`seq` authority:** server-stamped monotonic counter per `conversationId`, stored in a
  **separate `Map<conversationId, nextSeq>` that outlives `clear`** (never rewinds for a resumable
  conversation). `resetTurn` clears frames but not the counter.
- **Ack-cursor contract:** client-supplied `ackSeq` on `resume_stream`; server replays `seq > ackSeq`.
  Client dedups defensively by `seq <= lastRenderedSeq` (so no replay window/bracket frames needed).
- **Caps / TTL:** per-conversation ring cap `STREAM_REPLAY_BUFFER_MAX_FRAMES` (default 2000) +
  per-buffer byte cap; **global Map-cardinality cap `STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS`**
  (LRU-evict oldest whole buffer → its next reconnect gets `incomplete`); `STREAM_REPLAY_BUFFER_TTL_MS`
  (default = `DISCONNECT_GRACE_MS` + margin) as a leak **backstop** (primary cleanup is the `clear`
  paths). Document CLO TTL hygiene (≤ conversation retention, same EU substrate; effective lifetime
  = sweep cadence + TTL, not nominal) per brainstorm decision #8.
- **Failure mode on cap overflow / cursor-too-old / map-evicted:** server signals `stream_replay{
  status: "incomplete" }`; client falls back to v1 honest resume (persisted-history refetch). Replay
  is best-effort; correctness floor is "never lie."

0.2 **Preconditions to verify at /work Phase 0 (grep against installed code, not memory):**
- `grep -nE "export type WSMessage" apps/web-platform/lib/types.ts` → confirm `:250`.
- Read `lib/ws-zod-schemas.ts:611-615` exhaustiveness rail before widening.
- `grep -n "DISCONNECT_GRACE_MS" apps/web-platform/server/ws-handler.ts` → confirm `:195`.
- Confirm `sendToClient` is the **sole** server→client emit path:
  `grep -rn "\.ws\.send(\|session\.ws\.send" apps/web-platform/server/` — if any emit site bypasses
  `sendToClient`, the buffer-write hook there must be added too (per
  `hr-write-boundary-sentinel-sweep-all-write-sites`).
- Confirm test runner: `apps/web-platform/package.json` → `"test": "vitest"`, vitest include
  globs `test/**/*.test.ts`; root has **no** `workspaces` field.

### Phase 1 — Type-union widening (RED-first, contract before consumers)

`lib/types.ts` (`:250` `WSMessage`) and `lib/ws-zod-schemas.ts`:
1. Add optional `seq?: number` to the **buffered streaming family** — the rule is "frames the
   client re-applies on replay", not a hand-picked count. Minimal start set:
   `stream_start`, `stream`, `tool_use`, `tool_progress`, `usage_update`, `stream_end`,
   `session_ended`. **Drop `error` from the buffered set** unless a replay-idempotency story is
   shown (a replayed `error` could re-fire a toast). Optional on the **wire** for back-compat with
   already-rendered clients; see the required-seq narrowing at the buffer boundary in Phase 2.1.
2. Add a new **per-status discriminated sub-union** `stream_replay` (NOT a single shape with all
   fields optional). Drop `begin`/`end` (per-`seq` dedup makes the replay window redundant and
   removes the dangling-window race); keep only the fallback signal:
   ```ts
   | { type: "stream_replay"; conversationId: string; status: "incomplete" }
   ```
   (If a happy-path bracket is later shown necessary, add `begin`/`end` as their own sub-union
   members with per-status required fields — but start without them.)
3. Add `ackSeq?: number` to a new **`resume_stream`** client→server frame
   (`{ type: "resume_stream"; conversationId: string; ackSeq?: number }`) — NOT `resume_session`.
   Zod: `ackSeq` is a non-negative integer (`z.number().int().nonnegative()`), clamped; replay
   treats it as a lower bound only.
4. Update the Zod discriminated-union schema for the field, the new `resume_stream` + `stream_replay`
   variants. The `_SchemaCoversForward/_SchemaCoversBackward` rail (`ws-zod-schemas.ts:611-615`) and
   the `default: const _exhaustive: never` switches (`ws-client.ts:950-954`,
   `chat-state-machine.ts:373-375`) will fail `tsc` until consumers match — **let the compiler
   enumerate the rails** for the new VARIANTS (per
   `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails`; no fixed site count).
5. **The `seq?`-on-existing-variants field triggers NO rail** (adding an optional field changes no
   control flow). So per `cq-union-widening-grep-three-patterns`, grep is load-bearing for the
   field's consumer (`ws-client.ts:901` cost handler + `lastRenderedSeq` tracking): run `tsc` for
   the variants, grep for the field. Confirmed-today consumers are exhaustive switches, not
   if-ladders (`chat-state-machine.ts:396`, `ws-client.ts:679`), but re-grep at /work per
   `2026-04-18-discriminated-union-widening-if-ladders`.

### Phase 2 — Server: ring buffer module + write hook

2.1 New module `apps/web-platform/server/stream-replay-buffer.ts` — **mirror `TtlDedupMap`
(`observability.ts:413-458`)** for cap/sweep/reset shape:
- Internal frame type **`type BufferedFrame = StreamEvent-family & { seq: number }`** (required seq;
  reuse the `StreamEvent` `Extract<WSMessage, …>` at `chat-state-machine.ts:314`). This makes "every
  buffered frame carries seq" a compiler invariant and eliminates `seq!` non-null assertions.
- `class StreamReplayBuffer`: `frames: Map<conversationId, BufferedFrame[]>` (the ring),
  **`counters: Map<conversationId, number>` (the monotonic `nextSeq`, OUTLIVES `clear`)**,
  `lastActivity: Map<conversationId, number>`.
- `stamp(conversationId, msg): BufferedFrame` — `seq = (counters.get(cid) ?? 0); counters.set(cid,
  seq+1)`; pushes to ring (evict oldest when `> STREAM_REPLAY_BUFFER_MAX_FRAMES` OR per-buffer byte
  cap exceeded → mirror Sentry `op:buffer-overflow` if evicting during an active turn); enforces the
  **global `STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS`** cap (LRU-evict oldest whole buffer); updates
  `lastActivity`.
- `replayFrom(conversationId, ackSeq): { frames: BufferedFrame[]; status: "complete" | "incomplete" }`
  — frames with `seq > ackSeq`; `incomplete` if cursor evicted (`ackSeq < oldestBufferedSeq - 1`) OR
  the whole buffer was map-evicted.
- `resetTurn(conversationId)` — turn-start; clears FRAMES only, keeps the `counters` entry.
- `clear(conversationId)` — abort/turn-end/grace-expiry/close; clears frames **and** `lastActivity`
  but **NOT `counters`** (so a resumed conversation never rewinds `nextSeq`).
- `clearAll()` / `reset()` — SIGTERM drain + test seam (align naming to `agent-session-registry.ts`
  `__test_only__` convention).
- TTL backstop: follow `TtlDedupMap`'s **amortized sweep-on-write** (no new timer) OR ride the
  existing reaper (`index.ts:112`) — do NOT add a new timer family. Frame this as a leak BACKSTOP;
  the `clear` paths + ring cap are the primary memory bound.

2.2 Wire the write hook at the single seam `sendToClient` (`ws-handler.ts:583`): BEFORE
`JSON.stringify(message)` at `:586`, if `message.type` is in the buffered family, derive the target
conversation from **`message.conversationId` when present, else `session.conversationId`** (NEVER
blindly `session.conversationId` — a backgrounded conv-A frame must not land in conv-B's buffer),
and call `buffer.stamp(targetConvId, message)` (assigns `seq` onto the object that is then
serialized). The stamp happens regardless of send success so a frame emitted to a momentarily-dead
socket is still buffered (the whole point). Per `2026-03-20-websocket-first-message-auth-toctou-race`,
only stamp once the session is registered. Phase 0.2 grep confirms `sendToClient` is the sole emit
seam (`hr-write-boundary-sentinel-sweep-all-write-sites`).

2.3 Wire `resetTurn` at turn-start (the agent-runner turn boundary) and `clear` at: `abortSession`
(`agent-session-registry.ts:122` — keys on the ABORTED conversation, which may differ from a
resumed one), grace-expiry (`ws-handler.ts:2571`), turn-end, close, and SIGTERM (`index.ts:234`
alongside `abortAllSessions()`). **Terminal-frame retention exception (scenario e):** do NOT
`clear` a terminal `session_ended` at turn-end if the socket is disconnected — retain it until the
grace timer fires, so a user who was gone at turn-end gets the "ended while away" frame replayed.
If `clear` already ran (a new `start_session`/`resetTurn` intervened), honest fallback fires — not a
lie, documented as the expected (e)∩(f) interaction.

### Phase 3 — Server: non-destructive reattach + replay (NOT resume_session)

3.1 Add a **`resume_stream` handler** distinct from `resume_session`. `resume_session` aborts the
live agent at its first line (`abortActiveSession`, `ws-handler.ts:1588`) — routing replay there
would kill the in-flight turn the feature exists to preserve. Instead, handle `resume_stream` at /
adjacent to the `pendingDisconnects`-cancel seam (`ws-handler.ts:2500-2506`), which is where a
reconnecting socket re-binds WITHOUT aborting the still-running agent. The handler:
- **Ownership + repo-scope re-verify:** gate replay on the SAME guards the resume path uses — the
  conversation-row fetch with `.eq("user_id", userId)` (`:1613-1623`) AND the repo-scope check
  (`:1626-1632`). Place `replayFrom` strictly AFTER both, keyed on the verified `conv.id` (never the
  raw client-supplied `msg.conversationId`). On mismatch: emit honest fallback + mirror
  `reportSilentFallback(undefined, {feature:"stream-replay", op:"ownership-mismatch", extra:{conversationId, userIdHash}})`
  (P1 — potential cross-user attempt). Reuse the canonical guards; do not add a divergent second check.
- **Live-conversation match:** confirm the `resume_stream.conversationId` matches the conversation
  the reconnecting socket is bound to (single-session-per-userId: a second tab could have taken the
  slot) — only replay the resumed conversation's buffer; never interleave two conversations.
- Call `buffer.replayFrom(conv.id, clamp(ackSeq ?? -1))`.
- `status === "complete"`: emit each buffered frame verbatim (preserving order + stamped `seq`).
  No `begin`/`end` brackets — the client dedups by `seq <= lastRenderedSeq`. Then live frames flow
  from the still-running agent (the reattach did NOT abort it).
- `status === "incomplete"`: emit `stream_replay{status:"incomplete"}` → client does v1 honest
  history refetch. Mirror `reportSilentFallback(undefined, {feature:"stream-replay",
  op:"cursor-evicted", extra:{conversationId, ackSeq}})` — use `warnSilentFallback` (warning level)
  if cursor-evicted is treated as expected/informational, reserving error-level `reportSilentFallback`
  for `ownership-mismatch` (observability-coverage finding).

3.2 **Race resolution (OQ3, deterministic):** reconnect BEFORE grace expiry → `pendingDisconnects`
cancel (`:2500`) keeps the agent alive → `resume_stream` reattaches + replays + live frames resume.
Reconnect AFTER grace → `abortSession` already fired → `clear` ran (frames gone, but `counters`
preserved) → `replayFrom` returns `incomplete` → honest fallback. **Trailing-emit window
(architecture P2-2):** the runner's abort branch in `agent-runner.ts` may emit a final frame AFTER
`abortSession` returned and `clear` ran; that frame re-stamps into a freshly-empty buffer. Add a
Phase 6 test for "frame emitted after `clear` during abort" (same hazard class as
`2026-03-27-ws-session-race-abort-before-replace`).

3.3 **Acceptance criterion phrased as the INVARIANT, not the proxy:** "after a reconnect within the
grace window, a frame emitted by the STILL-RUNNING agent *after* the reconnect is rendered by the
client" — NOT merely "replayFrom returned frames" (spec-flow P0).

### Phase 4 — Client: ack cursor + replay rendering

`lib/ws-client.ts` and `lib/chat-state-machine.ts`:
- Track the highest `seq` rendered per conversation (`lastRenderedSeq`). On a transient reconnect
  (the `auth_ok` path at `ws-client.ts:680` does NOT auto-resume today — add the `resume_stream`
  send here for the same-conversation brief-drop case, distinct from the explicit `resumeSession()`
  at `:1346`), send `resume_stream{conversationId, ackSeq: lastRenderedSeq}`.
- **Per-frame dedup (replaces the dropped replay window):** drop any replayed frame with
  `seq <= lastRenderedSeq` BEFORE applying it. Critically, the `usage_update` handler is at
  **`ws-client.ts:901`** (`(prev?.totalCostUsd ?? 0) + msg.totalCostUsd` — unconditionally additive,
  NOT in the reducer) — add the `seq <= lastRenderedSeq` guard THERE so replayed cost is not
  double-counted (data-integrity P0). Stream text is replace-not-append (`chat-state-machine.ts:552`)
  so replayed partials are idempotent; tool/subagent cards already dedup on id (`:706, :875-886`).
- **Stream/stream_end ordering caveat (data-integrity P2):** a replayed `stream` arriving AFTER its
  `stream_end` (which does `activeStreams.delete(leaderId)` at `:596`) would append a NEW bubble.
  Buffer-emission-order preserves `stream`→`stream_end`, so this holds; add a test for the
  multi-leader interleave case.
- On `stream_replay{status:"incomplete"}`: trigger the v1 honest history refetch. **Cost
  reconciliation (data-integrity P2):** the history refetch calls `seedCostData` →
  `setUsageData(prev => prev ?? costData)` (`ws-client.ts:1216`); because `prev` is non-null from
  pre-disconnect partials, the authoritative persisted cost is discarded. On the `incomplete` path,
  RECONCILE to the persisted authoritative value (overwrite, not `prev ??`). Test it.
- This is the **#3280 overlap touch-point** (refactor useWebSocket history-fetch into reducer).
  **Re-evaluate #3280 disposition here:** if the `resume_stream` branch is expressible without the
  full reducer refactor, Acknowledge and leave #3280 open (YAGNI); if it forces touching the
  history-fetch state, fold the minimal slice (`Ref #3280`).

### Phase 5 — Agent-native parity (MCP) — **tracking issue only**

(Demoted from a build phase per code-simplicity review — its default outcome was a tracking issue.)
The replay capability is server-internal protocol plumbing with no new operator UI action. A backend
agent consuming the WS stream could benefit from the same replay-on-reconnect, but the web client is
the shipping surface and agent mid-turn reconnect support is unconfirmed. **File a V2 tracking issue**
("Agent/MCP transport stream-since-disconnect parity") referencing this PR; do NOT spend a `/work`
phase auditing `conversations-tools.ts`. Recorded in `## Files to Edit` as a `gh issue create`
post-merge step, not a code phase.

### Phase 6 — Tests (vitest; `test/**/*.test.ts`)

Test path: `apps/web-platform/test/server/stream-replay-buffer.test.ts` (matches vitest include
glob; node project). Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/stream-replay-buffer.test.ts`.
Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

Unit (buffer module):
- stamp assigns monotonic `seq`; ring evicts oldest at per-conversation cap; **global Map cap evicts
  oldest whole buffer (LRU)**; per-buffer byte cap evicts; `replayFrom(ackSeq)` returns `seq > ackSeq`;
  `incomplete` when cursor evicted OR buffer map-evicted; `resetTurn` clears frames but `counters`
  (`nextSeq`) persists; **`clear` clears frames but NOT `counters`** (resume-after-clear must not
  rewind — craft: stamp to seq 10, `clear`, stamp again → seq continues at 11, not 0); `clearAll`
  empties the map; `BufferedFrame` type forbids unstamped frames (no `.seq!` sites — AC).

Integration (mock WS — keep the LLM out of the assertion path per
`2026-04-19-llm-sdk-security-tests-need-deterministic-invocation`):
- **INVARIANT (not proxy):** disconnect mid-turn, reconnect within grace via `resume_stream`,
  assert (a) replayed frames `seq > ackSeq` in order AND (b) a frame emitted by the STILL-RUNNING
  agent AFTER reconnect is rendered (i.e. the agent was not aborted) (spec-flow P0).
- frame-keyed buffer: a backgrounded conv-A frame emitted while the socket is bound to conv-B lands
  in conv-A's buffer, not conv-B's (data-integrity P1 / security P0-2).
- cost dedup: replayed `usage_update` with `seq <= lastRenderedSeq` does NOT move `totalCostUsd`
  (data-integrity P0).
- flapping: three reconnects in 90s each cancel the abort timer; advancing `ackSeq` replays only the
  new tail; agent survives all three.
- grace race: reconnect-after-abort → frames cleared (counters preserved) → `incomplete` → honest
  fallback + `reportSilentFallback op:cursor-evicted`.
- trailing-emit: frame emitted AFTER `clear` during abort (architecture P2-2).
- ownership: `resume_stream` for a `conversationId` the `userId` does not own → no replay +
  `reportSilentFallback op:ownership-mismatch`; cross-repo stale cursor blocked by the `:1626` gate.
- ackSeq abuse: negative/huge client `ackSeq` clamped, no throw/under/over-replay.
- turn-completed-while-gone (e): terminal `session_ended` retained until grace → replay delivers it;
  AND the (e)∩(f) case where a new `start_session` intervened → honest fallback (not a lie).
- incomplete-path cost reconcile: history refetch overwrites stale partial cost to authoritative
  persisted value (data-integrity P2).
- stream/stream_end ordering: replayed `stream`→`stream_end` for one leader does not double-render;
  multi-leader interleave does not orphan a bubble.
- error frame NOT buffered (or, if buffered, replayed form equals the sanitized form — security P0-3).
- SIGTERM: `clearAll` empties buffers, clients closed with 1001.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] ADR-059 created: cites/extends **AP-013 → ADR-027**, mirrors **`TtlDedupMap`**; records
      reattach-seam / frame-keyed-binding / seq-counter-outlives-clear / ack-cursor / per-conv-ring-cap
      + global-map-cap + TTL-backstop; Alternatives (persist / Redis rejected). No ADR-042/046 miscite.
- [ ] `WSMessage` adds optional wire `seq?: number` to the buffered family (NOT `error`); new
      `resume_stream` (client→server, `ackSeq?` non-neg int) + `stream_replay{status:"incomplete"}`
      (per-status sub-union, no begin/end); zod + `_SchemaCovers*` rail + `never` switches pass
      `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`).
- [ ] `stream-replay-buffer.ts`: internal `BufferedFrame` (required `seq`, **no `.seq!` sites**);
      `frames`/`counters`/`lastActivity` maps; `clear` preserves `counters`; per-conv ring cap +
      per-buffer byte cap + **global `STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS` cap**; `replayFrom`
      returns `incomplete` on cursor-evict OR map-evict.
- [ ] Write hook at `sendToClient` (`ws-handler.ts:583`, before `JSON.stringify` at `:586`) keys the
      buffer on the **frame's** `conversationId` (fallback `session.conversationId`); Phase 0.2 grep
      confirms `sendToClient` is the sole emit seam (or all bypass sites hooked).
- [ ] **`resume_stream` handler at the `pendingDisconnects`-cancel seam (`:2500-2506`) — NOT
      `resume_session`** (which aborts the live agent at `:1588`). Gates replay AFTER the existing
      `user_id` (`:1613-1623`) AND repo-scope (`:1626-1632`) checks, keyed on verified `conv.id`;
      live-conversation match guard; `incomplete` + mirror on cursor-evict; `reportSilentFallback
      op:ownership-mismatch` on ownership fail.
- [ ] **Invariant AC (not proxy):** a frame emitted by the still-running agent AFTER a within-grace
      reconnect is rendered (agent was not aborted).
- [ ] `clear` wired at abort (`agent-session-registry.ts:122`), grace-expiry (`:2571`), turn-end
      (with terminal-`session_ended` retention-until-grace exception), close, SIGTERM (`clearAll`).
- [ ] Client: tracks `lastRenderedSeq`; sends `resume_stream` on transient reconnect (`ws-client.ts:680`
      path); **dedups replayed frames by `seq <= lastRenderedSeq` at the `usage_update` handler
      `ws-client.ts:901`** (no cost double-count); reconciles cost to authoritative on `incomplete`;
      falls back honestly on `incomplete`.
- [ ] All Phase 6 tests pass via `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/stream-replay-buffer.test.ts`.
- [ ] PR body uses `Ref #5240` and `Ref #5273` (NOT `Closes #5240` — umbrella stays open).
- [ ] `## Observability` schema fields all non-placeholder; each of cursor-evicted / ownership-mismatch
      / buffer-overflow has its own mirror; discoverability test is a no-SSH data-pull.

### Post-merge (operator)
- [ ] `gh issue create` the V2 Agent/MCP-parity tracking issue (Phase 5), label `type/feature` +
      `domain/engineering` + `app:web-platform` (verified-existing labels), referencing this PR.
      Automatable via `gh` CLI — not operator-manual.
- [ ] No infra/secret/vendor steps. The `web-platform-release.yml` pipeline restarts the container on
      merge to `main` touching `apps/web-platform/**` (path-filtered), which IS the deploy.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — carried forward from the
2026-06-14 durable-session-resume brainstorm `## Domain Assessments`.

### Engineering (CTO)
**Status:** reviewed (carry-forward + deepen-plan architecture pass)
**Assessment:** In-process buffer justified by single-instance topology and **AP-013 → ADR-027**;
mirrors **`TtlDedupMap`** (not novel). `sendToClient` is the single seam but is `userId`-keyed —
the write hook keys on the FRAME's `conversationId` (deepen P0). Replay attaches at the
non-destructive reattach seam (`:2500`), NOT `resume_session` (which aborts the live agent — deepen
P0). Watch: global Map-cardinality cap (not just per-conv ring), `nextSeq` surviving `clear`,
stamping order vs cumulative-partial replace. All resolved in the rewritten phases above.

### Product (CPO)
**Status:** reviewed (carry-forward); `requires_cpo_signoff: true` — plan-time sign-off pending.
**Assessment:** #5 (this) ranks just below honest UX (#6, shipped in v1). Correctness floor is
"never lie": on any replay failure, fall back to v1 honest resume — never duplicate or stale-render.
CPO-surfaced edge cases (multi-tab, turn-completed-while-gone, flapping ack cursor, grace-window
race) are all enumerated in Phase 6 tests.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** NOT a legal blocker for v1 operator-self-use. The buffer is a transient replay
cache of already-retained, already-redacted conversation-class data on the same EU substrate
(Hetzner hel1) → no new Art. 30 entry **provided** TTL ≤ conversation retention (enforced by
`STREAM_REPLAY_BUFFER_TTL_MS`, documented in ADR-059). Re-evaluation trigger (unchanged from v1):
first arms-length GitHub-App install where a third party's regulated-data repo lands here → add
Art. 30 PA entry. No persisted buffer in this plan → trigger not reached.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no new user-facing page, modal, or interactive surface. Reconnect is automatic;
the only visible change is that the live stream resumes seamlessly instead of jumping. The v1
reconnect/resume states already have a committed wireframe
(`knowledge-base/product/design/chat/reconnect-resume-states.pen`); no new `.pen` required.
**Pencil available:** N/A (no UI surface)

#### Findings
No new UI files in `## Files to Create`/`## Files to Edit` (all changes are server modules, the WS
type contract, and client transport/reducer plumbing — no `components/**/*.tsx`, `app/**/page.tsx`,
or `app/**/layout.tsx`). Product/UX Gate is NONE; mechanical UI-surface override does not fire.

## Infrastructure (IaC)

No new infrastructure. No server, systemd unit, cron, secret, vendor account, DNS, TLS, or firewall
rule introduced. The three new env vars (`STREAM_REPLAY_BUFFER_MAX_FRAMES`,
`STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS`, `STREAM_REPLAY_BUFFER_TTL_MS`) have safe in-code defaults
and need no Doppler provisioning unless an operator wants to override (documented in `.env.example`
only). Phase 2.8 gate: **skipped** (pure code change against already-provisioned runtime).

## Observability

```yaml
liveness_signal:
  what: "count of resume_stream reattaches that replayed frames vs returned incomplete"
  cadence: "per resume_stream reconnect"
  alert_target: "Sentry threshold alert on op:cursor-evicted rate (a spike = buffer cap too low / TTL too short)"
  configured_in: "structured pino log at the resume_stream handler + Sentry op tags"
error_reporting:
  destination: "Sentry: warnSilentFallback(... op:'cursor-evicted') [warning, expected]; reportSilentFallback(... op:'ownership-mismatch'|'buffer-overflow') [error]"
  fail_loud: true
failure_modes:
  - mode: "cursor evicted (ackSeq older than oldest buffered frame) or buffer map-evicted"
    detection: "replayFrom returns status:incomplete"
    alert_route: "Sentry op:cursor-evicted (warning); client falls back to honest history refetch"
  - mode: "ownership/repo-scope mismatch (session userId/repo != conversation)"
    detection: "resume_stream handler ownership re-verify fails at the :1620/:1630 guards"
    alert_route: "Sentry op:ownership-mismatch (error, P1 — potential cross-user attempt); no replay"
  - mode: "buffer growth (per-conv ring cap, per-buffer byte cap, or global map-cardinality cap)"
    detection: "stamp() evicts oldest frame/buffer at a cap"
    alert_route: "Sentry op:buffer-overflow (error) if a ring/byte cap evicts during an active turn"
logs:
  where: "container stdout -> Better Stack (pino structured); Sentry breadcrumbs"
  retention: "Better Stack default; buffer itself in-memory only, effective lifetime = sweep cadence + TTL <= conversation retention"
discoverability_test:
  command: "sentry-cli issues list --query 'op:cursor-evicted' --stats-period 24h (or the Better Stack query API) after a forced reconnect in DEV"
  expected_output: "JSON listing the op:stream-replay events with conversationId tag; no ssh required. Local complement: vitest run asserts the emitted frame sequence."
```

## Files to Create
- `apps/web-platform/server/stream-replay-buffer.ts` — buffer module (mirrors `TtlDedupMap`).
- `apps/web-platform/test/server/stream-replay-buffer.test.ts` — unit + integration tests.
- `knowledge-base/engineering/architecture/decisions/ADR-059-stream-since-disconnect-replay-buffer.md`.

## Files to Edit
- `apps/web-platform/lib/types.ts` (`WSMessage` `:250` — add wire `seq?` on buffered family, new
  `resume_stream` + `stream_replay{status:"incomplete"}` variants).
- `apps/web-platform/lib/ws-zod-schemas.ts` (zod union + `_SchemaCovers*` rail `:611-615`).
- `apps/web-platform/server/ws-handler.ts` (frame-keyed write hook at `sendToClient` `:583/:586`;
  new `resume_stream` handler at the `pendingDisconnects`-cancel seam `:2500-2506` reusing the
  ownership `:1613-1623` + repo-scope `:1626-1632` guards; `clear` at grace-expiry `:2571`).
- `apps/web-platform/server/agent-session-registry.ts` (`clear` on `abortSession` `:122` — keyed on
  the aborted conversation).
- `apps/web-platform/server/index.ts` (`clearAll` in SIGTERM `:234`; TTL backstop via amortized
  sweep-on-write or the existing reaper `:112` — no new timer).
- `apps/web-platform/lib/ws-client.ts` (track `lastRenderedSeq`; send `resume_stream` on transient
  reconnect at `:680`; per-`seq` dedup at the `usage_update` handler `:901`; cost reconcile on
  `incomplete` at `seedCostData` `:1216`).
- `apps/web-platform/lib/chat-state-machine.ts` (exhaustiveness rails for new variant if reached;
  `StreamEvent` extract reuse for `BufferedFrame`).
- `apps/web-platform/.env.example` (`STREAM_REPLAY_BUFFER_MAX_FRAMES`,
  `STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS`, `STREAM_REPLAY_BUFFER_TTL_MS`).
- `apps/web-platform/test/ws-streaming-state.test.ts` (if exhaustiveness rail touches it).
- **Post-merge:** `gh issue create` V2 Agent/MCP-parity tracking issue (Phase 5).

## Risks & Mitigations

- **Unbounded memory (the headline failure):** single backend instance — a leaked buffer OOMs ALL
  conversations. The per-conversation ring cap is NOT enough — a burst of distinct short
  conversations holds N × MAX_FRAMES simultaneously (security P1-1, architecture P2-3). Mitigation:
  per-conv ring cap (frames) + **per-buffer byte cap** (a `stream` frame is a large cumulative
  snapshot) + **global `STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS` Map-cardinality cap** (LRU-evict) +
  `clear` on every teardown path (abort/grace/turn-end/close/SIGTERM) + TTL backstop. Precedent:
  `TtlDedupMap.maxSize` (`observability.ts:420,436`) caps map size exactly this way;
  `2026-03-20-review-gate-promise-leak-abort-timeout` (unbounded accumulation on disconnect).
- **Cost double-count on replay (P0):** the `usage_update` handler is at `ws-client.ts:901`
  (`(prev?.totalCostUsd ?? 0) + msg.totalCostUsd`), NOT the reducer, and is unconditionally additive.
  Mitigation: drop replayed frames with `seq <= lastRenderedSeq` AT THAT HANDLER. Server-side cost
  persist (`cost-writer.ts:309`) happens at emit time, NOT on replay → server safe (replay re-emits
  the frame only, never re-invokes the cost RPCs).
- **Replay overlap / split-brain bubbles:** stream text is cumulative replace-not-append
  (`2026-04-13-...`), idempotent on re-apply; tool/subagent cards dedup on id (`:706, :875-886`).
  Caveat: a replayed `stream` arriving after its `stream_end` (`:596` deletes `activeStreams`)
  appends a NEW bubble — buffer-emission-order preserves `stream`→`stream_end`, so it holds; tested.
- **`seq` rewind on `clear` (P1):** `resetTurn` AND `clear` both clear frames, but the monotonic
  `nextSeq` lives in a separate `counters` Map that `clear` does NOT touch — so a resumed
  conversation never rewinds and a stale prior cursor can never match a new frame.
- **readyState TOCTOU on the write hook:** stamp before `JSON.stringify`; per
  `2026-03-20-websocket-first-message-auth-toctou-race`, only stamp once the session is registered.
- **Error-frame redaction is a call-site contract, not a boundary (security P0-3):** `sendToClient`
  does a bare `JSON.stringify`; sanitization happens per call site. Buffering durably persists +
  replays frames, widening the blast radius of any unsanitized field (e.g. `cc-dispatcher.ts:2775`
  `runnerRunaway*` diagnostic fields). Mitigation: keep `error` OUT of the buffered set, or test
  that a replayed `error` equals the sanitized form (`2026-03-20-websocket-error-sanitization-cwe-209`).
- **Pattern precedent (NOT novel):** extends **AP-013 → ADR-027** and mirrors **`TtlDedupMap`
  (`observability.ts:413-458`)** — bounded, TTL-swept, oldest-eviction, class-based, process-local,
  with a reset seam. Adopt its eviction/sweep/reset shape verbatim.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the
  threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- WSMessage widening: **do not prescribe a fixed exhaustiveness-site count** — run `tsc --noEmit`
  and let the compiler enumerate rails (`2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails`);
  audit if-ladders in `chat-state-machine.ts`, not just switches (`2026-04-18-...`).
- Test commands MUST be `cd apps/web-platform && ./node_modules/.bin/{vitest run,tsc --noEmit}` —
  NOT `npm run -w apps/web-platform ...` (root has no `workspaces` field) and NOT bare `bun test`
  (`bunfig.toml` ignores all paths; runner is vitest).
- Test FILE PATH must satisfy vitest `include` (`test/**/*.test.ts`) — a co-located
  `server/*.test.ts` would be silently skipped; use `test/server/stream-replay-buffer.test.ts`.
- `Ref #5240` not `Closes` — the umbrella is a multi-follow-up design issue (#5273, #2-physical,
  #4-in-flight remain). Auto-closing it at merge would falsely resolve siblings.
