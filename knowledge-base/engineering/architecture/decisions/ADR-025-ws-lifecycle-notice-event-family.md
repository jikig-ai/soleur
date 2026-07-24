---
title: WS lifecycle-notice event family
status: active
date: 2026-05-07
---

# ADR-025: WS lifecycle-notice event family

## Context

The `WSMessage` discriminated union in `apps/web-platform/lib/types.ts` carries 27+ variants today, broadly grouped into three implicit categories: **stream** (`stream`, `stream_end`, `tool_use`), **session lifecycle / state-mutation** (`session_resumed`, `session_ended`, `usage_update`, `tier_changed`), and **error / interactive** (`error`, `interactive_prompt`, `subagent_spawn`).

Issue #3269 introduces a need for a new variant — `context_reset` — that does not fit cleanly into any of the three implicit categories. It is a **server-emitted, single-shot, single-turn notice** about a server-side state transition the client renders as inline UX (badge, toast, system-style message). It is neither a stream chunk nor an error nor a state-mutation reflection.

Prefill-guard fires (#3263) are unlikely to be the only such notice. Plausible future variants in the same shape: `idle_reaper` (session reaped after idle TTL), `cost_cap_abort` (run halted at the cost ceiling), `container_restart` (workspace replaced mid-conversation), `byok_lease_expired` (BYOK key revoked or rotated mid-stream). All share the lifecycle-notice shape: server fires once, client renders once, single-turn signal, no follow-up state synchronization required.

Without an established pattern, each future variant risks bespoke handling (different reason discriminator key, different idempotency assumptions, different render-site). Anchoring the family now — while we have one variant landing and a clear forward list — keeps the union coherent.

## Decision

Establish a `lifecycle-notice` WS event family with the following invariants:

1. **Server-emit-only.** The client never sends a lifecycle-notice variant. (Existing `WSMessage` variants like `interactive_prompt` are bidirectional; lifecycle-notice is one-way.)
2. **Idempotent per fire.** Exactly one emission per server-side trigger; never re-emitted on SDK retry, reconnection replay, or message-bus deduplication.
3. **Single-turn signal.** The client renders the notice inline in the active conversation thread; no notification persists into the next turn's UI state. Equivalent to a toast in temporal scope.
4. **`reason` discriminator.** Every lifecycle-notice variant carries a `reason: <string-literal-union>` field that names the specific trigger. The variant `type:` names the **category of effect on the conversation** (e.g., `context_reset`); the `reason:` names the **specific cause** (e.g., `prefill-guard`, `tool_use_orphan`, future `idle_reaper`). Consumers switch on `type:` to decide rendering; switch on `reason:` only if differentiated copy is needed.
5. **No paired client-state change required.** Unlike `session_resumed` (which re-hydrates UI state) or `usage_update` (which mutates a counter), a lifecycle-notice does not mutate persisted client state. It is informational only.
6. **Zod-parsed and `_SchemaCovers`-proven.** Like every other `WSMessage` variant, lifecycle-notice variants must pass `apps/web-platform/lib/ws-zod-schemas.ts` and `apps/web-platform/test/ws-known-types-guard.test.ts`.

The first variant in this family is `context_reset` (#3269), with `reason: "prefill-guard" | "tool_use_orphan"`.

## Consequences

**Positive:**

- Future lifecycle-notice variants (`idle_reaper`, `cost_cap_abort`, `container_restart`, `byok_lease_expired`) follow a known shape — consistent reason discriminator, consistent invariants, consistent test coverage. New variants are additive, not bespoke.
- The client gets a uniform render-site (inline conversation notice) for a clearly-bounded category. UI work for the next variant is mostly copy + reason mapping.
- The `_SchemaCovers` / Zod gate already in place catches drift; no new infrastructure required.
- Establishing the family now makes (c) MCP `get_session_state` from #3269 an obvious extension when its threshold trips: the MCP tool reads the same lifecycle-notice history that the WS surface emits.

**Negative:**

- Adds a fourth implicit category to `WSMessage` documentation. Future contributors must understand all four (stream, lifecycle-notice, state-mutation, error/interactive) before adding variants.
- The `reason:` discriminator pattern is one more thing to remember; bare `type:`-only variants in other categories may feel inconsistent. We accept this — `reason:` is load-bearing only inside the lifecycle-notice family.
- The "single-turn signal" invariant is enforced by convention, not by type-system. A lazy contributor could emit a lifecycle-notice and also mutate persisted state in the same handler. The `_SchemaCovers` gate cannot detect this; only code review and the family doc will. Acceptable risk given the small surface.
