---
title: Prefill-guard context-reset signal (model + user)
date: 2026-05-07
status: complete
issue: "#3269"
parent_pr: "#3263"
brand_survival_threshold: single-user incident
---

# Prefill-guard context-reset signal — Brainstorm

## What We're Building

When the prefill-guard in `apps/web-platform/server/agent-prefill-guard.ts` fires (persisted SDK session ends with `assistant`, runner drops `resume:` to avoid HTTP 400), surface the reset to **both** the model and the user:

- **(a) System-prompt notice** — `applyPrefillGuard` returns a `contextResetNotice` string when the guard fires; both call sites (`cc-dispatcher.ts:479` and `agent-runner.ts:1157`) append it to `args.systemPrompt` for that single turn. Stronger directive when the trailing message had a `tool_use` content block (Symptom 2 — tool_use orphan).
- **(b) WS `context_reset` event** — runner-side `sendToClient` emit of `{ type: "context_reset"; reason: "prefill-guard" | "tool_use_orphan"; conversationId }` when the guard fires. Client renders an inline notice ("Context was reset — Soleur may not remember earlier turns. Please re-state if needed.").

Defer **(c) MCP `get_session_state`** — no `apps/web-platform/server/mcp/` exists yet; (c) is greenfield and belongs in a dedicated agent-native-observability roadmap initiative.

## Why This Approach

**(a) alone is insufficient.** CPO + CLO both flagged that asymmetric notification (model knows, user doesn't) fails the single-user incident brand threshold. The model may proactively ask "could you remind me?" but Claude's helpfulness prior makes silent hallucinated continuation likely. The user attributes the resulting tone shift to product brokenness, not a known constraint.

**(b) is cheap given the existing taxonomy.** `WSMessage` in `apps/web-platform/lib/types.ts:189` is already a discriminated union with 27+ variants and Zod drift gates (`fanout_truncated`, `tier_changed`, `session_resumed` are direct precedents). Adding `context_reset` is one variant + parser + client renderer. No new architectural category — this is a lifecycle notice in an established taxonomy.

**Tool_use orphan ships in the same PR.** The trailing `tool_use` case is the same call site, same test fixture, same emit point — splitting it doubles review cost and leaves a known-named correctness gap (Symptom 2) open after merge.

**(c) deferred** behind the issue's existing Sentry trigger (>10 prefill-guard fires in 7d on `feature:cc-concierge OR feature:agent-runner`). If the guard rarely fires, building MCP self-observability is over-engineering. (a)+(b) protect the user even at low fire-rate; (c) protects the model's autonomous self-correction at high fire-rate.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Fix shape | (a) + (b), tool_use-orphan branch in same PR | Single-user-incident threshold demands user-visible signal; CLO confirms model-only is insufficient floor for an autonomous-agent product with destructive tools |
| (c) MCP self-observability | Defer behind Sentry signal | No native MCP server exists; greenfield 1-week+ effort. Issue's >10/7d trigger is the right gate. |
| CLO re-confirmation modal | Defer to separate issue | Larger surface (touches tool-approval flow). Brand-survival posture honored by (a)+(b); modal is a hardening layer for the next iteration. |
| CLO privacy-policy clarification | Defer to separate legal issue | On-disk JSONL persistence vs. model memory drop — disclosure update is legal-document scope, not engineering. CLO domain. |
| WS event reason discriminator | `"prefill-guard"` and `"tool_use_orphan"` from day one | Future extensions (idle-reaper, cost-cap-abort) follow the same shape. Documented in ADR. |
| ADR for lifecycle-notice family | Create now via `/soleur:architecture` | Operator chose proactive ADR over wait-and-see. Establishes pattern before second variant lands. |
| WS emit site | Runner-side via `sendToClient` (precedent in `agent-runner.ts`) | Closer to fire, no relay-layer added. Same pattern as existing variants. |
| User-facing copy | Pull `copywriter` agent at plan-time | Model-facing notice and user-facing notice have different copy registers. |

## Sharp Edges

- **System-prompt accumulation safety** — `agent-runner.ts:883-1047` builds `systemPrompt` via `+=` from many sources. Notice append must land at the documented position (after services list) to avoid being overwritten. Test scenario covers no-accumulation across simulated multi-turn.
- **WS event idempotency** — emit exactly once per guard fire, not on every retry of the SDK call. Test scenario asserts single emission per fire.
- **Negative test** — when guard does NOT fire, neither system-prompt mutation nor WS event happens. Regression-protective.
- **Probe-failure path** — when `getSessionMessages` throws, the existing guard passes `resume:` through unchanged. Do NOT emit context_reset in that branch (the user's session is intact); the existing `prefill-guard-probe-failed` Sentry op is sufficient.

## User-Brand Impact

**Artifact:** Concierge / agent-runner conversation continuity.

**Vector:** Silent context loss — user types follow-up referencing prior turns or "yes, do that" referencing a proposed tool action; model executes wrong action, no action, or hallucinates plausible continuation.

**Threshold:** `single-user incident`. CPO + user-impact-reviewer sign-off required at plan and review time. CPO assessed and confirmed threshold (push-back-resistant: "model loses memory" sounds cosmetic, but consequence is the user acting on hallucinated continuations or missed tool actions — paid-trust product, "degraded UX" framing under-weights the trust contract).

**Worst outcome if shipped silent:** Trust breach. User says "yes, send the email" referencing a tool_use the new session never proposed; bot does nothing or sends a different email. User does not retry — they churn or escalate.

## Open Questions

- **User-facing copy** — exact wording delegated to `copywriter` at plan-time. Working draft: "Context was reset — Soleur may not remember earlier turns. Please re-state your request if it referenced earlier in this conversation." May need shorter form for inline render.
- **Future lifecycle-notice variants** — does the team anticipate `idle_reaper`, `cost_cap_abort`, `container_restart` notices? ADR scope.

## Domain Assessments

**Assessed:** Product (CPO), Engineering (CTO), Legal (CLO). Marketing/Sales/Finance/Operations/Support not engaged — internal correctness fix with no positioning, deal, expense, infra, or ticket-routing surface.

### Product (CPO)

**Summary:** (a) alone insufficient at single-user incident threshold; asymmetric notification fails the brand contract. Recommend (a) tool-aware + (b), defer (c) behind Sentry signal as the issue specifies. Threshold push-back-resistant: paid-trust product, hallucinated continuation = single-user incident even when no data leaks.

### Engineering (CTO)

**Summary:** WS taxonomy precedent solid (`fanout_truncated`, `tier_changed`); (b) cost negligible. System-prompt mutation safe per-turn (SDK `system` field is per-request, never persisted to JSONL). Tool_use orphan branches off same call site — include in same PR. (c) is greenfield (no native MCP server in `apps/web-platform/server/mcp/`); 1-week+ effort, defer correctly. Soft-architectural decision (lifecycle-notice category) — ADR recommended.

### Legal (CLO)

**Summary:** WS event + UI badge is the **floor** for an autonomous-agent product with destructive tools — model-only signal does not discharge the platform's authorization-audit-trail duty. Recommends (separate scope, deferred per operator) re-confirmation gate before first tool execution post-reset, plus privacy-policy clarification on on-disk JSONL persistence vs. dropped model memory (GDPR Art. 5(1)(a) / CCPA implication).

## Capability Gaps

None reported by the leaders. `copywriter` is needed at plan-time for user-facing string review; not blocking the brainstorm.

## Deferred Items (tracking issues to create)

1. **Re-confirmation gate before first post-reset tool execution** — CLO floor for autonomous-agent product. Modal/inline confirm before any tool call lands in the first turn after a context reset. Re-evaluate when (a)+(b) ship and the first real fire is observed in production, or when the `Closes #3269` PR exposes the tool-approval flow as the natural next surface.

2. **Privacy-policy disclosure update for on-disk session persistence** — CLO scope. Disclose that session JSONL transcripts persist on disk independent of model memory state, with retention period and deletion mechanism documented. GDPR Art. 5(1)(a) / CCPA exposure. Owner: legal-document-generator agent or CLO.
