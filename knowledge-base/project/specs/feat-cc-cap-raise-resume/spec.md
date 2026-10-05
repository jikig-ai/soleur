---
feature: cc-cap-raise-resume
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-05-cc-cap-raise-resume-brainstorm.md
status: draft
created: 2026-10-05
---

# Spec — cc-cap-raise-resume: resumable cost cap for Concierge conversations

## Problem Statement

The cc runner's per-conversation cost cap is a **conversation-killer**. When
`state.totalCostUsd >= capFor(...)` in `soleur-go-runner.ts`, the runner emits
`WorkflowEnd{status:"cost_ceiling"}` → `cc-dispatcher.ts` routes it through
`TERMINAL_WORKFLOW_END_STATUSES` → a terminal `session_ended` frame → the client
disables input with *"This conversation reached the per-workflow cost cap. Start a
new conversation to continue."*

Two distinct defects:

1. **Managed sessions hard-stop.** Operator correction on the billing model: managed
   users still pay for the work (Soleur subscription/usage billing) — a $2/$5 wall
   that destroys the conversation's accumulated context mid-task is paternalistic,
   not protective. There is no billing rationale for a hard kill on managed.
2. **BYOK sessions get non-actionable copy.** "Start a new conversation" discards
   the working context and the same long-running task re-trips the same cap in the
   new conversation. The cap exists to guard the founder's Anthropic bill — it
   should pause and offer a raise, not kill.

## Goals

- G1 — Managed sessions: the per-conversation cap is **not enforced** (no hard
  `cost_ceiling` kill). Optional telemetry-only soft threshold for runaway
  visibility.
- G2 — BYOK sessions: cap-hit becomes an **in-chat raise-and-continue affordance**
  (interactive prompt), not a terminal `session_ended`. Conversation and context
  survive.
- G3 — The raised cap **persists per conversation** across reload/reconnect.
- G4 — No new wire-protocol machinery beyond what's needed — reuse
  `interactive_prompt` / `interactive_prompt_response` where possible.

## Non-Goals

- NG1 — The BYOK cumulative kill-switch (`record_byok_use_and_check_cap`, ADR-041,
  `byok_cap_exceeded`) is a separate layer guarding founder-wide spend. Changing
  its trip semantics or making it in-chat-raisable is out of scope; the plan must
  define the copy shown when that layer is the blocker.
- NG2 — Dedicated `cost_cap_hit` wire event + custom banner UI (Approach B —
  deferred visual polish; a follow-up can upgrade the affordance surface).
- NG3 — Per-user cap preferences in dashboard settings (Approach C — deprioritized).
- NG4 — Changing the cap VALUES themselves (`$5`/`$2` defaults, `CC_MAX_COST_USD_*`
  env contract with Doppler) — defaults stay; only enforcement mode and
  resumability change.

## Functional Requirements

- **FR1 — Managed sessions skip enforcement.** The dispatcher knows key provenance
  at dispatch time (`resolveKeyOwnerThenLease`, `cc-dispatcher.ts`). When the
  conversation's credential is managed (not a user-leased BYOK key), the runner
  does not emit `cost_ceiling` for the per-conversation cap.
- **FR2 — Cap-hit becomes a non-terminal interactive prompt.** For enforced
  (BYOK) sessions, reaching the cap emits an `interactive_prompt` (new `cost_cap`
  kind or reused `ask_user`) offering preset raises (e.g. raise to $5 / $10 /
  $25) instead of `session_ended`. `cost_ceiling` leaves
  `TERMINAL_WORKFLOW_END_STATUSES`.
- **FR3 — Raise applies per-conversation and persists.** On a raise response the
  runner bumps `state.costCaps` for that conversation and the value persists
  (e.g. on the `conversations` row / workflow-state row) so reload or reconnect
  does not re-trip at the old cap.
- **FR4 — Decline path is honest.** Dismissing the prompt leaves the cap in place
  and keeps the conversation open for non-agent messages; a subsequent agent send
  re-prompts rather than silently erroring.
- **FR5 — Copy is truthful in both states.** `WORKFLOW_END_USER_MESSAGES` /
  `SESSION_ENDED_COPY` `cost_ceiling` entries are replaced by copy that matches
  the new behavior (raise affordance pending / declined), with the parity test
  (`cc-workflow-end-messages.test.ts`, `session-ended-copy.test.tsx`) updated.

## Technical Requirements

- **TR1 — Wire-schema discipline.** If a new `cost_cap` `InteractivePromptKind` is
  added, widen `INTERACTIVE_PROMPT_KINDS`, `InteractivePromptPayload`,
  `InteractivePromptResponsePayload`, and the registry-side kind union together —
  bidirectional `_AssertKindsMatch` / `_AssertResponseKindsMatch` rails exist and
  will fail compilation on drift. Reusing `ask_user` avoids all of it.
- **TR2 — Per-conversation cap override.** `state.costCaps` is currently a single
  injected `CostCaps` (`defaultCostCaps` at `getSoleurGoRunner`). The raise path
  needs a per-`conversationId` override applied at `capFor` time and threaded
  through `agent-runner-query-options` (or the runner state row) so it survives
  process restart.
- **TR3 — Exhaustiveness rails.** Any `WorkflowEndStatus` or wire-reason change
  trips `Record<WorkflowEndStatus, string>` rails in
  `cc-workflow-end-messages.ts` / `session-ended-copy.ts` and the
  `TERMINAL_WORKFLOW_END_STATUSES` tests — update in the same change.
- **TR4 — User-impact gate.** Touches a billing-adjacent guardrail; the plan must
  carry the `## Observability` block (5 fields, `discoverability_test.command`
  non-SSH) and answer the worst-user-impact question per
  `hr-weigh-every-decision-against-target-user-impact`.
- **TR5 — `.pen` wireframe gate.** Reusing `ask_user` verbatim adds no new UI
  surface; if the plan introduces a dedicated `cost_cap` prompt visual,
  `wg-ui-feature-requires-pen-wireframe` fires and the plan must produce a
  committed `.pen` wireframe or hard-block.
