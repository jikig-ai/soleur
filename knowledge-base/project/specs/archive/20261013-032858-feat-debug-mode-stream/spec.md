---
title: Debug Mode — Workspace-Scoped Harness Instruction Stream
feature: feat-debug-mode-stream
date: 2026-06-08
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
gdpr_gate_required: true
brainstorm: knowledge-base/project/brainstorms/2026-06-08-debug-mode-stream-brainstorm.md
closes: [5045]
---

# Spec: Debug Mode — Workspace-Scoped Harness Instruction Stream

## Problem Statement

When dogfooding the Soleur web-platform, operators cannot see what the harness is
doing in the backend. The web harness is the Claude Agent SDK `query()` loop
(`agent-runner.ts:1842`, `cc-dispatcher.ts`); it down-selects the SDK message stream
into a few curated, redacted frames and **drops the rest in-process** — there is no
on-disk transcript a web operator can read. This makes it slow and guess-heavy to
understand and improve harness behaviour, which the Phase-4 dogfooding loop depends on.

## Goals

- Give Soleur-internal operators a **live, redacted view of the uncurated SDK message
  stream** (tool_use + input, assistant reasoning, tool_progress, result) in the web UI.
- Reuse the existing `command_stream` + `bash_autonomous` + redaction precedents rather
  than building new transport, gating, or redaction primitives.
- Keep the feature **fail-closed and brand-safe**: ephemeral, server-side-gated,
  secret-redacted, scoped to the Soleur org.

## Non-Goals

- True CLI-parity (system-reminders, sub-agent internal transcripts) — not captured by
  the web harness today; deferred to a follow-up.
- Persisting / saving debug transcripts — separate plan + mandatory DPIA.
- Any customer-facing debug surface.
- Changing the #2138 invariant outside the debug toggle.
- Agent-native get/set tool pair for `debug_mode` (mirroring `workspace_*_autonomous`) —
  deferred. `debug_mode` is dev-only/render-only, and the Concierge surface exposes no
  platform MCP tools until #3722 (`CC_MCP_ALLOWLIST` promotion), so even the existing
  autonomous parity tools are unreachable from the user-facing router today. Fold a
  `debug_mode` tool pair into that promotion if/when wanted; the RPCs + server helpers are
  already tool-ready (owner-write enforced in the SECURITY DEFINER RPC).

## Functional Requirements

- **FR1** — When debug mode is ON for a workspace, the conversation surface renders a
  **separate collapsed debug panel** (never inline with user-facing messages) that
  streams: raw `tool_use` name + redacted `tool_input`, full assistant reasoning text,
  `tool_progress`, and `result`/usage, in arrival order. *Wireframe: `knowledge-base/product/design/debug-mode/debug-mode-stream.pen`.*
- **FR2** — A **workspace settings toggle** flips `workspaces.debug_mode`. The toggle is
  **visible only to the Soleur internal (`dev`) cohort**; hidden otherwise. *Wireframe: `knowledge-base/product/design/debug-mode/debug-mode-stream.pen`.*
- **FR3** — The debug panel has collapsed, expanded, empty, and "secrets redacted"
  states, and communicates that the stream is **not persisted**.
- **FR4** — Debug events are visually distinguishable by kind (tool_use vs reasoning vs
  result) reusing existing chat component patterns/tokens.

## Technical Requirements

- **TR1** — New `debug_event` WS frame in `lib/types.ts` WSMessage union + zod schema in
  `lib/ws-zod-schemas.ts`; registered in `KNOWN_WS_MESSAGE_TYPES`; declares
  cumulative-vs-delta semantics and emits a terminal event. New `case` in
  `chat-surface.tsx` render switch (exhaustiveness rail).
- **TR2** — Emit `debug_event` from the SDK-iterator loop (`agent-runner.ts:1842` +
  `cc-dispatcher.ts` tool-block callbacks) — the only correct tap point. This is a
  **scoped, gated exception to the #2138 invariant** (raw tool name/input on the wire),
  mirroring `command_stream`.
- **TR3** — **Gating (server-side, fail-closed):** availability via a Flagsmith
  `debug-mode` flag targeted at the `dev` cohort; per-workspace state via a new
  `workspaces.debug_mode` column + member/owner SECURITY-DEFINER RPCs
  (`get_workspace_debug_mode` / `set_workspace_debug_mode`) modelled on migration 097.
  Resolved once at WS handshake and cached on `ClientSession` (no per-message DB query).
  Emission is gated server-side; a flipped client flag can never unlock the stream.
  Membership enforced in app code (the runner uses the service client, which bypasses RLS).
- **TR4** — **Redaction (dual-gate, fail-closed):** every `debug_event` payload routes
  through a hardened `redactCommandForDisplay` + `probeRedactionFallthrough` +
  sandbox-path scrub at the **construction site**, and is re-redacted at render.
  Redaction must be extended beyond command-shaped tokens to cover interpolated Doppler
  values, signed URLs, and arbitrary token shapes in prose; content-level,
  case-insensitive, Unicode-separator-aware (U+2028/U+2029/NBSP); per-call random
  sentinels if tokenizing. `probeRedactionFallthrough` **drops the frame** on a
  suspected-secret match (not best-effort). Sweep ALL sinks, not just the new path.
- **TR5** — **Ephemeral-only:** `debug_event` frames are never written to `messages`,
  server logs, or Sentry (including `captureException` *value*, not just `extra`). A
  write-boundary sentinel sweep enumerates debug-event types as never-persist.
- **TR6** — Byte/volume caps mirroring `COMMAND_STREAM_*_CAP_BYTES`; client debug panel
  imports no `@/server/*` modules (pino bundle trap).

## Gates (must run before ship)

- `soleur:gdpr-gate` on the diff (`hr-gdpr-gate-on-regulated-data-surfaces`).
- `user-impact-reviewer` at PR review.
- Security review of the redaction-filter expansion.
- `soleur:preflight` Check 6 (sensitive-path) — touches `server/`, `supabase/`, `lib/safety`.

## Acceptance Criteria

- Debug panel streams redacted SDK events live, only when `workspaces.debug_mode` is ON
  AND the viewer is in the `dev` cohort; nothing streams otherwise (verified server-side).
- A planted secret-shaped fixture in a tool input is redacted in the stream AND would be
  dropped by `probeRedactionFallthrough`; proven by tests at the construction site.
- No `debug_event` is ever persisted to `messages`, logs, or Sentry (test asserts).
- Toggle is invisible to non-`dev` cohort users.
