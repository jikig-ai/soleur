---
title: "Pluggable web agent engines bind execution before dispatch"
status: accepted
date: 2026-09-13
issue: none
supersedes: null
---

# ADR-217: Pluggable web agent engines bind execution before dispatch

## Context

Soleur Web currently has Claude-specific streaming and tool behavior, while the
product needs to add Codex and later engines without allowing a client payload
to select a provider. Conversations and routines also need retries to remain on
the engine selected when the execution started.

## Decision

The workspace default is mutable settings state. Each conversation or routine
run gets one immutable `agent_engine_runs` binding before provider dispatch. The
trusted bind RPC resolves the workspace default and enforces tenant membership;
authenticated user calls must use their own `created_by` identity. Reads use RLS
workspace membership, while owner writes use a security-definer RPC with a pinned
`public, pg_temp` search path.

Adapters implement the neutral lifecycle contract: start, continue, cancel,
reconcile, cursor resume, approval response, erasure, and disposal. Dispatch
reloads the persisted binding, verifies adapter identity, persists emitted events
before yielding them, and fails closed on missing bindings, mismatches, or event
ledger errors. Provider SDK types remain inside adapters and transport seams.

The Claude extraction uses a provider-facing SDK message source wrapped by a
translator and neutral transport bridge. The source retains permission,
session, approval, and cancellation behavior; only validated text, progress,
usage, and terminal result payloads cross into the shared event contract.

The Codex boundary follows the same shape for App Server events. Its thread
resume handle (`thread.id`) and live session identity (`thread.sessionId`) are
normalized as separate opaque fields; streamed message deltas, approvals,
usage, and terminal states are translated to contiguous neutral events. Missing
or malformed provider identities fail closed before persistence.
An injectable App Server source owns credentials and lifecycle side effects;
the transport bridge only translates its event stream.
Protocol request builders keep initialize, thread, turn, and approval envelopes
server-owned and map neutral approval decisions to the provider vocabulary.
The stdio seam uses a bounded JSONL codec so chunking and framing are handled
before protocol messages reach lifecycle translation.
An RPC correlation client bounds in-flight requests, routes server notifications
and approval requests separately, and rejects pending work on close or provider
errors without exposing native error details.
It also sends provider-request responses through a separate bounded path, so
approval decisions never masquerade as new client requests.
Handshake notifications use the same framed channel through a distinct
notification method and never consume request IDs.
The handshake helper enforces initialize completion before sending
`initialized`, so a failed negotiation cannot enter lifecycle dispatch.
The session coordinator owns that negotiated channel's thread start/resume and
turn-start ordering, returning only neutral thread and turn identities while
approval decisions use the RPC response path.
Inbound notifications hand off through a bounded ordered buffer; overflow
closes the source with an explicit backpressure error instead of growing the
server heap without limit.
The RPC client exposes channel-close callbacks so the bridge terminates
consumers when the provider process exits, preserving the source error.
The stdio process wrapper owns JSONL decoding, process exit/disposal, and the
credential-bearing launch callback; tests inject the process so no live binary
or network is needed for protocol verification.
The lifecycle source composes that connection with the neutral start and
continuation operations, reuses the negotiated session, and returns an
explicit unsupported error for protocol operations that are not yet qualified
instead of silently simulating parity.
Cancellation uses `turn/interrupt` and requires an exact empty acknowledgement;
reconciliation uses `thread/read` and maps only recognized turn/thread states,
falling back to `queued` when the provider state is incomplete.
The negotiated session also owns a bounded `thread/turns/list` history request
with opaque cursor validation, capped page size, and explicit sort/item-view
options. This is a provider seam only: neutral cursor replay remains
unsupported until persisted turn/item responses have a complete translator.
Remote erasure uses the documented `thread/delete` request and returns
`confirmed` only for an exact empty acknowledgement; malformed acknowledgements
fail closed and an erased active thread is removed from the runtime cache.
The session also exposes the experimental `thread/items/list` seam with an
optional validated turn filter, allowing a later replay translator to fetch
persisted items without resuming a thread or accepting provider envelopes at
the neutral boundary.
The replay translator now admits only persisted `agentMessage` text,
approval-waiting `commandExecution` items, and recognized turn status/usage
records. It drops unsupported item kinds and malformed identities, preserving
the same bounded payload rules as live notifications.
Persisted `plan` items are also reduced to bounded neutral progress messages;
their provider metadata and raw plan structure remain outside the contract.
Persisted `fileChange` items are reduced to a count-only progress event; paths,
diffs, and provider change metadata remain replay metadata until a dedicated
artifact store and egress policy are qualified.
Persisted command executions emit only completed/failed status progress;
commands and aggregated output remain excluded from replay payloads.
Persisted MCP tool calls follow the same status-only rule; connector identity,
arguments, results, and provider errors remain excluded until redaction is
qualified per connector.
Persisted dynamic tool calls likewise emit only completed/failed status
progress, excluding tool payloads and result content.
Persisted collaboration tool calls emit only completed/failed status progress;
cross-thread prompts and identities remain excluded until their isolation model
is qualified.
Persisted review-mode items emit only review-started/review-completed progress;
review targets and findings remain excluded from replay payloads.
Persisted context-compaction items emit a fixed `Context compacted` progress
message keyed by their bounded item identity; compaction summaries, reasoning,
and source context remain excluded from replay payloads.
Persisted `webSearch` items emit a fixed `Web search recorded` progress message
keyed by their bounded item identity; queries, URLs, and action details remain
excluded from replay payloads.
Persisted `imageView` items emit a fixed `Image view recorded` progress message
keyed by their bounded item identity; filesystem paths and image content remain
excluded from replay payloads.
Persisted `functionCallOutput` items emit a fixed `Function output recorded`
progress message keyed by their bounded item identity; function names,
namespaces, and output values remain excluded from replay payloads.
Persisted `userMessage` items emit a fixed `User input recorded` progress message
keyed by their bounded item identity; user content and attachment metadata remain
excluded because the neutral event contract has no message-role field.
When a persisted item has no qualified neutral mapping, the lifecycle source may
emit `engine_replay_item_dropped` with only the bounded engine/item type and a
reason; provider payloads and identities are never included in this telemetry.
Cursor replay now fetches full turn pages through the negotiated session and
wraps those translated events in a private replay envelope consumed by the
existing neutral transport. A missing runtime thread, malformed page, or
malformed recognized item fails closed before dispatch receives an event.

The reviewed registry controls which engines may appear in settings and which
engine/auth/workflow/capability combinations are qualified for execution. A
settings metadata lookup never grants execution authorization.

Factory and dispatch entry points accept an explicit reviewed registry when a
deployment or deterministic test catalog needs additional engines. When a
dispatch supplies a trusted egress selection, factory creation passes that
selection through registry qualification; a registry without `resolve` fails
closed rather than treating metadata lookup as authorization. The built-in
catalog remains the default, so future providers can be added through reviewed
definitions and additive factories without changing provider control flow.
The factory also requires the selection operation to match the dispatch
operation, preventing new-run qualification from authorizing an existing-run
adapter invocation.

## Consequences

Adding an engine requires a reviewed definition, adapter transport, lifecycle
tests, credential and qualification evidence, and settings/catalog wiring. A
workspace default change affects new runs only; existing runs retain their
binding. Registry injection keeps future engine wiring additive but does not
bypass enablement, binding identity, event validation, or egress policy. System-
triggered routines still require a dedicated service identity before they can
participate in the same binding path.
