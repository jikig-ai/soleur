---
title: Consolidated Working-Status Box + Session-Only Activity Trail
feature: feat-concierge-activity-trail
date: 2026-10-05
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
gdpr_gate_required: false
brainstorm: knowledge-base/project/brainstorms/2026-10-05-concierge-activity-trail-brainstorm.md
closes: [9515]
---

# Spec: Consolidated Working-Status Box + Session-Only Activity Trail

## Problem Statement

The Concierge session chat shows three redundant in-turn indicators — the boxed
"Soleur Concierge / Working…" badge, a standalone "Still working…" line, and on
return-from-navigation a second "Working…" box — while the status text itself is
generic and overwritten in place, leaving no visible record of what the agent did
during a turn. Root cause found in research: `KNOWN_WS_MESSAGE_TYPES`
(`apps/web-platform/lib/ws-known-types.ts`) is missing 11 union members on `main`,
so `ws-client.ts` drops `reasoning_narration`, `turn_summary`, `command_stream`,
`stream_replay`, `autonomous_disclosure`, `resume_stream`, `abort_turn`,
`membership_revoked`, `revocation_notice`, `autonomous_posture`,
`autonomous_disclosure_response` frames before Zod parse — narration can never
reach `liveNarration`, and the `_Exhaustive` compile-time proof is vacuous so CI
cannot catch the drift.

## Goals

- **PR1 (hotfix):** sync `KNOWN_WS_MESSAGE_TYPES` to the union; replace the
  vacuous exhaustiveness proof with a real guard; fix the guard test that pins
  the stale list.
- **PR2 (consolidation):** exactly one in-turn working-status surface — the box.
  It carries the live status line plus a bounded, session-only activity trail of
  plain-language steps, torn down at turn end into the persisted `turn_summary`.

## Non-Goals

- Persisting the activity trail (operator chose session-only; CTO Option B is the
  documented fallback if durability is later required).
- Raw commands/paths/tool names/reasoning monologue user-facing; `debug_event`
  stays team-only; debug panel untouched.
- `narrate`/`summarize` tool contract changes; leaders-responding footer; cost
  footer; turn-summary card design.

## Functional Requirements

- **FR1 — Allowlist repair (PR1).** `KNOWN_WS_MESSAGE_TYPES` contains every
  `WSMessage["type"]` and `ClosePreamble["type"]` member. Drift fails loudly:
  the guard derives the expected set from the union at test/typecheck time
  rather than a hand-maintained literal.
- **FR2 — Single status surface (PR2).** Delete the standalone `live-narration`
  slot (`chat-surface.tsx`); render narration inside the active `MessageBubble`.
  Exactly one working box is visible at any time, including after navigation —
  diagnose and fix the duplicate-box case (routing chip vs. stale transitional
  bubble).
- **FR3 — Activity trail (PR2).** The box lists plain-language steps appended on
  `tool_use`/`reasoning_narration` events: latest highlighted, ≤5 prior entries
  dimmed, consecutive-identical dedup, "…and N more steps" overflow.
  `tool_progress` updates the current step's elapsed time in place, never
  appends.
- **FR4 — Teardown (PR2).** The trail dies on every turn-end arm the same way
  `liveNarration` does today (clear_streams, enter_stopping, connection_change,
  turn-ending stream_event/timeout); the `turn_summary` card is the only durable
  record.
- **FR5 — Suppression preserved (PR2).** `awaitingUserInput` suppression,
  `aria-live="polite"`, and honest abort/error markers behave exactly as today —
  never show "working" while parked on a review gate.

## Technical Requirements

- **TR1 — No union widening for the trail.** Trail entries live on the tip
  `ChatTextMessage` (e.g., an `activity[]` field, `commandBlocks` precedent) —
  no new `ChatMessage`/`WSMessage` variants, so
  `cq-union-widening-grep-three-patterns` largely does not trigger.
- **TR2 — Live-only invariants preserved.** Do not add `debug_event` or
  `reasoning_narration` to `BufferedWSMessage`/`BUFFERED_FRAME_TYPE_MAP`
  (#5240 heartbeat + #5290 replay-completeness).
- **TR3 — Label sources.** Steps come from `tool_use.label`
  (`buildToolLabel` output — already plain-language, #2138-safe) and
  `reasoning_narration.message` (deliberate agent emission). Never
  `debug_event.body`, never raw tool names.
- **TR4 — `tool_progress` correlation (decided at plan 2026-10-05).** No
  `tool_use` widening: cc forwards `tool_progress` since #5214, sequential
  tool execution means the latest trail entry is the running step, and
  `messages[]` must not mutate on the heartbeat hot path (memo churn) —
  store `startedAt` on the trail entry and compute elapsed at render.
- **TR5 — Tests.** PR1: update `ws-known-types-guard.test.ts` to derive expected
  membership from the union (or a parse of types.ts) — a test adding a union
  member must fail without a set entry. PR2: update
  `chat-surface-awaiting-input.test.tsx` (slot removal + suppression),
  `message-bubble` tests (trail render/dedup/cap/teardown), reducer tests for
  append + teardown arms.
- **TR6 — Observability.** Keep the `ws-unknown-event` Sentry fallback — after
  PR1 a firing breadcrumb is genuine skew signal; assert zero new occurrences
  in the post-merge window.

## Observability

- **surface:** Sentry `reportSilentFallback` breadcrumbs (`op: ws-unknown-event`,
  `tool-label-fallback`) + existing chat RTL/e2e suite.
- **failure_mode → layer:** allowlist drift → vitest union-derived guard;
  narration drop → `ws-unknown-event` breadcrumb; trail never tearing down →
  reducer tests over every turn-end arm; duplicated box → RTL + QA screenshot.
- **discoverability_test.command:** `gh api 'repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?branch=main&per_page=3'` + Sentry `ws-unknown-event` query post-merge.

## Domain Review (carry-forward)

- **CPO:** bounded live trail (≤5, dimmed), torn down at turn end; "Working…"
  dominance may be label-fallback rate — measure via Sentry at plan time.
- **CLO:** ephemeral trail has no new legal surface; persistence (if ever) needs
  privacy-policy amendment first + gdpr-gate.
- **CTO:** Option C confirmed — zero buffer/schema/DSAR changes; reject
  per-event persistence; preserve #5240/#5290 invariants.
- **CMO:** copy contract — verb-first gerund + business noun, no
  `soleur:*`/paths/`#NNNN`; dedup noise; "Working…" stays honest fallback.

## Visual Design

- Wireframe: `knowledge-base/product/design/app-ui/concierge-activity-trail.pen`
  (4 states: in-turn trail, capped trail, post-turn collapse, empty-trail start).
