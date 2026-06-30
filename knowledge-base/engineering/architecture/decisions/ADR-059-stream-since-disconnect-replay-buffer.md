# ADR-059: Stream-since-disconnect in-memory replay buffer for backend agent sessions

- **Status:** Accepted — **RE-OPENED by [ADR-068](./ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md) (2026-06-30).** The "no multi-instance requirement exists" premise that grounded the Redis rejection (Decision § Buffer tier (b)) no longer holds: ADR-068 (multi-host `/workspaces`, #5274) creates exactly that requirement. The in-memory buffer stays correct through ADR-068 Phase 3 (affinity routes a reconnect back to the lease-holding host → still same-process); it migrates to a self-hosted EU session-Redis in **Phase 4a**, where a host *death* can send a reconnect to a *different* host. The migration MUST preserve every invariant below — most critically **`seq` counter-outlives-`clear`** (§ `seq` authority) — and add per-`workspace_id` key namespacing + an app-layer read scope-check + TTL ≤ conversation retention (replay frames carry user content, not low-sensitivity routing metadata).
- **Date:** 2026-06-14
- **Issue:** #5273 (follow-up of umbrella #5240; gated on v1 PR #5256, MERGED 2026-06-14)
- **Lineage:** **AP-013 "Process-local state for runner sessions" → ADR-027** (`principles-register.md:21`; `ADR-027-process-local-state-for-runners.md`) is the governing tier principle. This ADR extends it and mirrors the lifecycle discipline of `TtlDedupMap` (`apps/web-platform/server/observability.ts:413-458`). It does NOT extend ADR-042 (Anthropic-SDK-in-Inngest) or ADR-046 (Inngest one-shot scheduler) — an earlier draft mis-cited those as in-process-state precedents; they are unrelated.

## Context

When a SOLEUR backend agent session loses its WebSocket mid-turn, the client today re-fetches only **persisted** history on reconnect (`lib/ws-client.ts` history path). Stream events emitted **during** the gap — `stream`/`stream_start`/`stream_end` text deltas, `tool_use` labels, `tool_progress` heartbeats, `usage_update` cost ticks, a terminal `session_ended` — are never persisted until turn-end, so they are **lost**. The reconnecting user sees a frozen bubble that silently jumps to the final state (or stalls behind the misleading "Retrying…" watchdog) instead of resuming the live stream.

v1 (#5256) made reconnect **honest** — a verified workspace rebind plus an accurate status when work genuinely ended. This ADR makes the common brief-drop case **seamless**: the in-flight turn keeps running through the 30 s disconnect grace window (`DISCONNECT_GRACE_MS = 30_000`, `ws-handler.ts:195`), and on reconnect within that window the client re-attaches and the gap's frames are replayed before live streaming resumes.

The deployment topology makes an in-process buffer sound: a **single** `hcloud_server.web` backend instance, no horizontal scaling (v1 brainstorm headline finding — the "ephemeral per-container filesystem" hypothesis was false; `/workspaces` is a persistent Hetzner block volume). A reconnect therefore always lands on the same process that buffered the frames.

## Decision

Add a **server-side, in-memory, per-conversation ring buffer** (`apps/web-platform/server/stream-replay-buffer.ts`) that captures every server→client WS frame in the buffered family as it is emitted, tagged with a monotonic per-conversation `seq`. On reconnect the client sends the last `seq` it rendered (an **ack cursor**) via a new `resume_stream` control frame; the server replays every buffered frame with `seq > ackSeq`, then live streaming resumes from the still-running agent. No DB schema change.

### Buffer tier

In-memory, per-conversation, on the single backend instance. **Extends AP-013 → ADR-027** and **mirrors `TtlDedupMap`** for lifecycle discipline: bounded (`maxSize`), TTL-swept (amortized sweep-on-write, no new timer), oldest-eviction, class-based, process-local, with a `reset()` test seam.

**Alternatives considered:**
- **(a) Persist to Supabase** — rejected. Adds an Art. 30 surface (CLO), TTL management, and write amplification on the hot per-frame stream path. YAGNI at single-instance topology.
- **(b) Redis** — rejected *at this ADR's time*. A new infra dependency versus the established in-process pattern of AP-013/ADR-027, with **no multi-instance requirement to justify it** at single-host topology. **Re-opened by ADR-068 (2026-06-30):** the multi-host move IS that requirement. The buffer migrates to a self-hosted EU session-Redis in ADR-068 Phase 4a (TLS + `requirepass`/ACL + private-subnet firewall + per-`workspace_id` namespacing), preserving the counter-outlives-`clear` semantics below. Phases 1–3 keep the in-process buffer (affinity makes it host-local-sufficient).

### Reattach seam — NOT `resume_session`

Replay attaches at the **`pendingDisconnects`-cancel branch** (`ws-handler.ts:2500-2506`), where a reconnecting socket re-binds WITHOUT aborting the still-running agent, via a new **non-destructive `resume_stream` control frame**. It must NOT route through `resume_session`, which calls `abortActiveSession(userId, session)` at its **first line** (`ws-handler.ts:1588`) — that kills the live agent and marks the conversation `completed`, re-introducing exactly the abort the 30 s grace window exists to avoid. The acceptance invariant is therefore phrased as "a frame emitted by the still-running agent AFTER reconnect is rendered," not the proxy "replayFrom returned frames."

### Binding authority — the frame's `conversationId`

`sendToClient(userId, msg)` (`ws-handler.ts:583`) is **`userId`-keyed** (one socket per user); the buffer is **`conversationId`-keyed**. A backgrounded run on conversation A can emit while the socket is bound to conversation B. The write hook therefore keys the buffer on the **frame's** `conversationId` when present, falling back to `session.conversationId` ONLY when the frame lacks one — never blindly `session.conversationId`. This closes same-user cross-conversation contamination.

### `seq` authority — counter outlives `clear`

A server-stamped monotonic counter per `conversationId`, stored in a **separate `Map<conversationId, nextSeq>` that outlives `clear`**. `resetTurn` (turn-start) clears the frame ring but keeps the counter; `clear` (abort/grace/turn-end/close) clears frames and `lastActivity` but **NOT** the counter. Rationale: if `clear` rewound `nextSeq` to 0, a resumed conversation whose client holds `lastRenderedSeq = 5` would replay new `seq 0..N` frames as already-unseen. The monotonic counter must never rewind for a conversation that may be resumed.

### Ack-cursor contract

Client supplies `ackSeq` on `resume_stream`; the server replays `seq > ackSeq`. The client additionally dedups defensively by dropping any replayed frame with `seq <= lastRenderedSeq` — so no replay-window/bracket frames (`begin`/`end`) are needed, and the dangling-window race they would introduce is removed. `ackSeq` is a `z.number().int().nonnegative()`, clamped server-side, treated as a lower bound only.

### Caps / TTL

- Per-conversation ring cap `STREAM_REPLAY_BUFFER_MAX_FRAMES` (default 2000) + a per-buffer byte cap (a `stream` frame is a large cumulative snapshot).
- **Global Map-cardinality cap `STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS`** (default 500) — LRU-evict the oldest whole buffer; its next reconnect gets `incomplete`. The per-conversation ring alone does not bound the OOM-all-conversations failure mode under a burst of distinct short conversations.
- `STREAM_REPLAY_BUFFER_TTL_MS` (default = `DISCONNECT_GRACE_MS` + margin) as a leak **backstop** via amortized sweep-on-write (mirrors `TtlDedupMap`; no new timer family). The primary memory bound is the `clear` paths + the ring cap; the TTL is the backstop.

### Failure mode on cap overflow / cursor-too-old / map-evicted

The server signals `stream_replay { status: "incomplete" }`; the client falls back to the v1 honest resume (persisted-history refetch). Replay is best-effort; the correctness floor is **"never lie"** — never duplicate, never stale-render. Ownership/repo-scope mismatch at the `resume_stream` handler emits no frames and mirrors to Sentry; cursor-evicted emits `warnSilentFallback(op: "cursor-evicted")` (expected/informational); a ring/byte-cap eviction during an active turn mirrors `reportSilentFallback(op: "buffer-overflow")`.

**Severity-by-cause for the ownership/repo-scope guards (revised by the #5290 false-positive remediation; superseding the original blanket-P1 mirror above).** The first revision mirrored *every* `resume_stream` ownership/repo-scope guard miss as `reportSilentFallback(op: "ownership-mismatch")` (P1). In production this fired error-level for benign reconnect races (a deferred-creation conversation whose row had not yet materialized, and a transient `getCurrentRepoUrl` null on a tenant-mint blip), flooding the alert stream. Calibration is now **by cause** (two stable op slugs + `level` + an `extra.cause` discriminator — no IaC alert keys on the op, so `level` de-noises):

- **Genuine, page-worthy (error / `reportSilentFallback`):** a real DB error or RLS denial 42501 on the owner-scoped lookup → `op: "ownership-mismatch", cause: "db-error"` (the `pg_code` tag carries SQLSTATE); a genuine cross-repo stale cursor (both URLs non-null and differ) → `op: "repo-scope-mismatch", cause: "url-differs"`.
- **Benign but observable (warning / `warnSilentFallback`):** the row is absent (`.maybeSingle()` → `{data:null,error:null}`) → `op: "ownership-mismatch", cause: "not-materialized"`. The conversation lookup uses `.maybeSingle()` (NOT `.single()`) precisely so a zero-row result is distinguishable from a DB error by severity. This branch also covers a genuine owned-by-another row (indistinguishable here without a privileged query), so it stays observable, not silenced; the owned-by-another enumeration is deferred behind a warning-volume-drop criterion.
- **Transient, handled upstream (no handler re-mirror):** when `getCurrentRepoUrl` returns `null` (tenant-mint blip), the handler does NOT mirror — `getCurrentRepoUrl` already emits `feature: "repo-scope"` upstream (downgraded to `warnSilentFallback(op: "read-current-repo-url.tenant-mint")` as the highest-volume transient contributor); re-mirroring would double-count, and a null is not a repo-scope mismatch.

A client-side gate (`resume_stream` is sent on reconnect only for a `sessionKind === "resumed"` session) removes the dominant benign source — a `"fresh"` deferred conversation never requests replay of a row that does not exist yet. The emit slugs are kept STABLE (no rename) so no consumer darks.

## Consequences

- **No DB schema change.** The buffer is transient; the only wire change is an optional server-stamped `seq?: number` on the buffered family plus the new `resume_stream` (client→server) and `stream_replay` (server→client) variants. `seq?` is optional on the wire for back-compat with already-rendered clients during a rolling deploy.
- **Three new env vars** (`STREAM_REPLAY_BUFFER_MAX_FRAMES`, `STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS`, `STREAM_REPLAY_BUFFER_TTL_MS`) with safe in-code defaults — documented in `.env.example`, no Doppler provisioning required unless an operator overrides.
- **Legal/CLO (carry-forward from v1):** the buffer is a transient replay cache of already-retained, already-redacted conversation-class data on the same EU substrate (Hetzner hel1) → no new Art. 30 entry **provided** the effective lifetime (sweep cadence + TTL) ≤ conversation retention. The re-evaluation trigger is unchanged from v1: the first arms-length GitHub-App install where a third party's regulated-data repo lands here.
- **Brand-survival threshold:** single-user incident. The headline risk is unbounded memory on the single backend instance OOMing ALL conversations — bounded by the three caps + the `clear` teardown paths + the TTL backstop.
- **`error` frames are NOT buffered** — `sendToClient` does a bare `JSON.stringify` and sanitization is a per-call-site contract; durably buffering + replaying an `error` would widen the blast radius of any unsanitized diagnostic field (e.g. `runnerRunaway*`). Kept out of the buffered set.
- **Agent/MCP transport parity** (the same replay-on-reconnect for a backend agent consuming the WS stream) is deferred to a V2 tracking issue; the web client is the shipping surface.
