---
date: 2026-10-05
status: brainstorm
lane: cross-domain
source: operator report + screenshot of live Concierge session hitting the cap
---

# Concierge cost-cap: no hard-kill on managed sessions, raise-and-resume affordance

## What We're Building

Change the cc runner's per-conversation cost cap from a **conversation-killer** into an **actionable, resumable** gate — and stop enforcing it entirely on managed sessions.

Observed behavior (operator screenshot, ~$4.28 estimated spend): the runner emits
`WorkflowEnd{status:"cost_ceiling"}` → `cc-dispatcher.ts` routes it through
`TERMINAL_WORKFLOW_END_STATUSES` → `session_ended` frame → the client tears down
streams and disables input with: *"This conversation reached the per-workflow cost
cap. Start a new conversation to continue."* The conversation's accumulated context
is unrecoverable, and the advice is hollow — the same long-running task re-trips the
same cap in the new conversation.

Desired behavior:

1. **Managed sessions** (founder pays Soleur, not Anthropic directly): do not
   hard-enforce the per-conversation cap. The user pays for the work; a $2/$5 wall
   that destroys context mid-task is hostile UX.
2. **BYOK sessions** (founder's own Anthropic key): keep a cap — it guards the
   founder's own bill — but make cap-hit an **in-chat "raise cap and continue"**
   affordance, not a terminal `session_ended`. Conversation survives; context intact.

## Why This Approach

Approach A (chosen by operator over dedicated-banner B and settings-only C):
**reuse the existing `interactive_prompt` machinery** for the cap-hit prompt.

- `interactive_prompt` / `interactive_prompt_response` already exist end-to-end:
  runner → `pending-prompt-registry.ts` → WS → client renders question + options →
  response resolves the pending prompt. A `cost_cap` kind (or reuse of `ask_user`)
  gets resume UX for near-zero new wire surface.
- `cost_ceiling` comes out of `TERMINAL_WORKFLOW_END_STATUSES` — the code comment at
  `cc-dispatcher.ts` already anticipated this ("Emitting it for RECOVERABLE runner
  states (cost_ceiling, runner_runaway) would break 'user retries on next turn' UX").
- A per-conversation cap override lives in runner `state.costCaps` (raised on
  prompt response) and must persist (e.g. a `conversations` column or the existing
  workflow-state row) so a reload/reconnect doesn't silently re-trip at the old cap.
- Managed-vs-BYOK is knowable at dispatch time (`resolveKeyOwnerThenLease` in
  `cc-dispatcher.ts`) — the dispatcher passes enforcement mode into the runner.

Rejected:

- **B (dedicated `cost_cap_hit` wire event + custom banner):** better polish, but
  duplicates prompt machinery; a follow-up can upgrade the visuals later.
- **C (settings-only cap):** doesn't resume mid-conversation — the core complaint.

## Key Decisions

- **Managed sessions: no enforced per-conversation cap** — operator correction on
  the billing model: managed users still pay (Soleur subscription/usage), so the
  cap is paternalistic, not protective. Hard kill removed for managed.
- **BYOK keeps a cap** (founder's Anthropic bill protection) but it becomes
  **resumable** via the in-chat raise affordance.
- **Resume UX: in-chat "continue" affordance** (operator pick) — not auto-resume,
  not settings-only.
- **Cap override is per-conversation** and persists across reload.
- Noted for plan: the stale comment on `cost_ceiling` recoverability in
  `cc-dispatcher.ts` (Architecture-F4 block) becomes the actual behavior.

## Open Questions

- Does raising the conversation cap interact with the **BYOK cumulative
  kill-switch** (`record_byok_use_and_check_cap`, ADR-041, `byok_cap_exceeded`)?
  That layer guards founder-wide cumulative spend; if it trips, the raise affordance
  alone can't resume the conversation — plan must define what the prompt shows then
  (likely: different copy pointing at the BYOK spend cap). Possibly out of scope.
- Managed sessions: keep a very high **soft** ceiling (e.g. warn-only Sentry
  breadcrumb at $N) as runaway telemetry, or literally no check? Recommend a
  telemetry-only threshold — the operator still wants to see a $200 runaway.
- Raise semantics: fixed increments ("raise to $5 / $10 / $25") vs. "continue
  without a cap this conversation"? Prefer preset increments — keeps a nudge point.
- `.pen` wireframe gate (`wg-ui-feature-requires-pen-wireframe`): the affordance
  reuses the existing `ask_user` prompt surface. If the plan adds a dedicated
  `cost_cap` prompt kind with new visuals, the gate fires — assess at plan Phase 2.5.

## User-Brand Impact

- **Artifact:** the Concierge conversation runner's cost-cap gate
  (`soleur-go-runner.ts` `cost_ceiling` path + the raise affordance).
- **Vector:** worst case, a silent cap bypass (managed) lets a runaway agent spend
  unboundedly on a user's bill, OR a stuck prompt strands paying users
  mid-conversation — both are trust breaches on a paid surface.
- **Threshold:** `single-user incident`.

## Domain Assessments

Not spawned — the Devin CLI harness exposes only generic subagent profiles
(`subagent_explore`, `subagent_general`); the named domain leaders
(`soleur:product:cpo` et al.) are not invocable via `run_subagent` here.
The always-on user-brand-critical posture is captured above and carries forward to
plan Phase 2.6 / preflight Check 6; `soleur:engineering:review:user-impact-reviewer`
remains the load-bearing gate at PR review.
