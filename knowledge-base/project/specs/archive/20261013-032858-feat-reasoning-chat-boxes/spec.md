---
title: Reasoning Narration — Live Status Line + Persisted Turn Summary
feature: feat-reasoning-chat-boxes
date: 2026-06-15
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
gdpr_gate_required: true
brainstorm: knowledge-base/project/brainstorms/2026-06-15-reasoning-narration-brainstorm.md
closes: [5370]
---

# Spec: Reasoning Narration — Live Status Line + Persisted Turn Summary

## Problem Statement

Non-technical Soleur users have no sense of *what the agent is doing* during a turn, nor a
durable record of *what it did*. The agent's reasoning today surfaces only in the team-only,
dev-cohort-gated, ephemeral "Debug stream" panel (`debug-stream-panel.tsx`, marked "not saved ·
visible only to the Soleur team"). Raw reasoning is operator jargon ("Issue … → routing to
`soleur:one-shot`"), hedged and unfinished — promoting it verbatim into the main chat would be
expensive (persistence + replay rework), legally heavy (DSAR/retention/cross-tenant-breach on a
dev-calibrated redaction posture), and poor UX (noise + false certainty).

## Goals

- Give users a **live, plain-language sense of progress** during a turn ("Looking into the
  navigation issue…", "Fixing it now…").
- Leave a **durable plain-language summary** of each completed turn in the chat history.
- Source the user-facing text from a **deliberate agent emission** — never the raw internal
  reasoning monologue — so no unredacted internal text reaches a persisted, user-visible record.
- Keep the existing team **debug stream untouched** (ephemeral, dev-cohort, live-only).

## Non-Goals

- Persisting or surfacing raw internal reasoning verbatim (explicitly rejected by the triad).
- Promoting / reusing the `debug_event` WS frame for the user-facing path (breaks #5240 + #5290).
- Per-reasoning-event boxes (frequency flood; the agent paces narration at milestones instead).
- Customer-facing exposure of skill names, issue numbers, file paths, or tool jargon.
- Changing the debug-mode flag, debug panel, or its redaction posture.

## Functional Requirements

- **FR1 — Deliberate narration emission.** The harness/agent emits a plain-language, user-facing
  narration string as a first-class output, distinct from internal reasoning. → wireframe 05.
- **FR2 — Live narration surface (transient).** Render the latest narration line near the
  "Soleur Concierge / Working…" badge (above the tool-use chip). It updates in place as the turn
  progresses. → wireframe 05.
- **FR3 — Teardown on turn-end.** The live line is removed when the turn ends — success, abort,
  or error — and is **never** written to history. → wireframe 06.
- **FR4 — Persisted turn summary.** On `stream_end` / `workflow_ended` for a successful turn,
  create exactly one persisted summary message ("✓ Fixed the side panel…"), visually distinct
  (emerald checkmark + left-accent rail, confident type). → wireframes 06, 07.
- **FR5 — No false "Done".** The summary's completed/checkmark treatment must **not** render for
  aborted or errored turns, which retain their existing honest markers (`[stopped by user]`,
  "Agent stopped responding…").
- **FR6 — Durable on reload.** Persisted summaries rehydrate from history on reload; the live
  line never reappears (it was never persisted). → wireframe 07.
- **FR7 — Plain-language scrub.** Both surfaces pass the existing `formatAssistantText` scrub
  (strips `/workspaces/`, `/tmp/claude-`, path/jargon shapes) before display and before persist.

## Technical Requirements

- **TR1 — Distinct persisted message type.** Add a new `ChatMessage` variant (e.g.
  `turn_summary`) as a sibling of the persisted text message — **not** by extending
  `ChatDebugEventMessage`. New reducer case in `chat-state-machine.ts` mirrors the persisted-text
  path, and `chat-surface.tsx` renders it in the **main** message map (not the `DebugStreamPanel`
  filter).
- **TR2 — Live-only invariants preserved.** Do **not** add `debug_event` to `BufferedWSMessage` /
  `BUFFERED_FRAME_TYPE_MAP`. The new live-narration frame may be live-only (transient) and the new
  summary frame is buffered/persisted — neither touches the `debug_event` family. Preserve the
  #5240 leader-liveness heartbeat and #5290 replay-completeness assumptions.
- **TR3 — Persistence path.** New migration for the summary message (mirror migration 040
  status/usage discriminator pattern); history-hydrate in `server/api-messages.ts` returns it;
  insert via the `server/messages/insert-draft-card.ts` template.
- **TR4 — Buffered frame plumbing.** The persisted summary frame follows the 4 lockstep edits in
  `stream-replay-buffer.ts` (type map, seq, schema) so it survives reconnect + history refetch.
- **TR5 — Wire + schema.** New `WSMessage` member(s) in `lib/types.ts` + Zod schema in
  `lib/ws-zod-schemas.ts`. Union-widening gates apply (`cq-union-widening-grep-three-patterns`,
  `hr-type-widening-cross-consumer-grep`).
- **TR6 — Redact-before-persist.** Run the summary through `redactCommandForDisplay` +
  `debugRedactionProbeTrips` before persistence as defense-in-depth, even though agent-authored.
- **TR7 — Compliance.** DSAR export + erasure enumeration must include the new summary table/rows;
  update Privacy Policy + Data Protection Disclosure + GDPR processing register; CLO-attestation
  before ship (`gdpr_gate_required: true`).

## Open Questions (carry-forward to plan)

- Summary content: agent-authored at turn-end vs. assembled from milestone lines (lean: authored).
- Soft cap on live-line updates per turn to bound render churn (CTO frequency flag).
- Live line vs existing `tool_use_chip`: replace or coexist (wireframe coexists).
- Multi-leader (`/soleur:go`) turns: one whole-turn summary vs per-leader (default: one).
- Trivial/no-op turns: suppress the summary box vs always emit.

## Visual Design

- `knowledge-base/product/design/chat/reasoning-narration.pen`
  - Frame 05 — live narration (mid-turn): FR1, FR2.
  - Frame 06 — after completion (live line gone, summary persisted): FR3, FR4, FR5.
  - Frame 07 — on reload (durable summaries, no live line): FR6.

## Domain Review (carry-forward)

- **Product (CPO):** transient narration + single persisted summary; extend existing surfaces;
  avoid verbatim/false-certainty boxes.
- **Legal (CLO):** permitted-with-guardrails; legal weight only on the persisted summary
  (DSAR/retention/breach); agent-emits-it removes the redaction-posture-inversion risk; privacy
  docs + processing register + CLO-attestation required.
- **Engineering (CTO):** distinct persisted message type; never promote `debug_event`; medium
  build; union-widening gates apply.
