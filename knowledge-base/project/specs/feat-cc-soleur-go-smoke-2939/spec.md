---
title: cc-soleur-go Stage 6 — post-cutover regression net
date: 2026-05-13
issue: 2939
brainstorm: knowledge-base/project/brainstorms/2026-05-13-cc-soleur-go-stage-6-smoke-brainstorm.md
parent_plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
status: spec-complete
---

# Spec: cc-soleur-go Stage 6 — post-cutover regression net

## Problem Statement

cc-soleur-go has been the unconditional production routing path for every conversation since PR #3270 retired `FLAG_CC_SOLEUR_GO`. The chat-UI bubble components shipped in Stage 4 (#2886, PR #2925) carry only unit-test coverage; the routing/cost/UX flows defined in plan §369-386 (tasks 6.1-6.11) are uncovered end-to-end; and security smoke (prompt-injection drain, bash review-gate, cross-user prompt-response, rate-limit) has no automated assertion. Every cc-soleur-go-adjacent PR after Stage 4 (#2954, #3270, #3603, #3608, #3639-42, #3648, #3670, #3720) has ridden on the unit suite alone.

This spec ships the regression net — Playwright e2e coverage of the 4 chat-UI bubbles + plan-§369-386 routing/cost/UX/security smoke + a one-time visual-QA rubric for pre-merge sign-off. It also fixes the `DEV_ORIGINS` port-hardcoding (`localhost:3000` only) in `apps/web-platform/server/validate-origin.ts` that blocks future e2e POST flows on Playwright ports 3099/3100.

This unblocks #3722 (Phase 2 MCP tool promotion) — Stage 6 closure is the gate per the #3722 blocked-by list.

## Goals

1. Pin the 4 Stage 4 chat-UI bubbles (subagent-group, interactive-prompt-card, workflow-lifecycle-bar, tool-use-chip) with Playwright e2e assertions that catch the realistic regression class (silent drop, stuck state, expand-boundary, chip-removal contract).
2. Automate plan §369-386 tasks 6.1-6.11 as Playwright tests at the WS-message boundary (no real Anthropic SDK in CI).
3. Fix `DEV_ORIGINS` port hardcoding so future e2e POST flows are unblocked.
4. Ship a one-time manual visual-QA rubric covering: avatar render, markdown render post `stream_end`, document/PDF context-aware reply, AC11 Continue-Thread tab reload.
5. Land the work as 3 layered PRs (~250-300 LoC each) closing slices of #2939.
6. Unblock #3722 (Phase 2 MCP promotion) by closing #2939.

## Non-Goals

- **`toHaveScreenshot()` visual-regression baselines.** Theme-PR churn (#3308, #3585, #3587, #3656) would degrade reviewer signal. Promote later only if a regression actually slips. (Spec NG1)
- **Real-SDK CI coverage.** Quota burn + flake. A nightly real-SDK canary is a follow-up issue, not part of #2939. (Spec NG2)
- **MCP allowlist seeding.** The empty allowlist is the actually-shipping behavior; smoke certifies the degraded UX explicitly. Allowlist seeding is #3722's job. (Spec NG3)
- **Folding empirical-demand telemetry into smoke.** Smoke must NOT exercise denied tools — that would mask the Sentry signal #3722 needs. (Spec NG4)
- **Mobile-viewport coverage, a11y audit, RTL layout tests.** Separate domains, not in #2939 scope. (Spec NG5)
- **A standing CI job that re-runs the smoke on every cc-router-adjacent PR.** Open Q5; deferred to a follow-up issue. (Spec NG6)

## Functional Requirements

### FR1 — Per-bubble Playwright assertions (PR-A)

For each of `subagent-group`, `interactive-prompt-card`, `workflow-lifecycle-bar`, `tool-use-chip`, ship one Playwright e2e test that:

- **FR1.1 subagent-group**: After injecting N `subagent_spawn` events via WS, assert `[data-parent-spawn-id]` exists, `[data-child-spawn-id]` count = N, and `[data-expanded="true"]` when N ≤ 2 (the auto-expand boundary).
- **FR1.2 interactive-prompt-card**: After `interactive_prompt(kind=ask_user)`, assert `[data-prompt-id]` rendered; after `selectedResponse`, assert multi-select checkboxes show `aria-checked="true"` for prior picks (F17 regression).
- **FR1.3 workflow-lifecycle-bar**: After `workflow_started` → `workflow_ended`, assert the in-list summary message exists AND all `[data-leader-id="cc_router"][data-chip]` elements are gone (chip-removal contract; regression class from 2026-05-04 learning).
- **FR1.4 tool-use-chip**: Assert chip appears on `tool_use(cc_router|system)` and ZERO chips after `tool_progress`. Additionally assert the **"unregistered" affordance** renders correctly for any `mcp__soleur_platform__*` tool name (degraded UX is the actually-shipping path per Spec NG3).

### FR2 — Routing/cost/UX smoke (PR-B)

Plan §369-386 tasks 6.1-6.7 + 6.5.2-6.5.4, each as one Playwright assertion at the WS-message boundary:

- **FR2.1** (6.1) Workflow routing: a fresh conversation routes to `cc-router` (asserts `[data-active-workflow="cc-router"]` after first turn).
- **FR2.2** (6.2) Sticky workflow: a conversation with `active_workflow="cc-router"` stays sticky on subsequent turns (no re-route, no router stickiness invariant violation per `router-stickiness-invariant.test.ts`).
- **FR2.3** (6.3) Mid-workflow leader switch: `@CTO` invocation mid-conversation produces a `subagent_spawn` for the CTO leader and threads its output into the transcript.
- **FR2.4** (6.4) Cost circuit breaker: when synthesized cost crosses the per-conversation threshold, the lifecycle bar shows the circuit-breaker state and refuses further turns.
- **FR2.5** (6.5.1) CFO gate: cost-circuit-breaker fires CFO leader spawn at the threshold; assert CFO leader-id appears in the subagent group.
- **FR2.6** (6.5.2) Chip-render-in-8s: from `tool_use` event to chip DOM render < 8s (Playwright timeout assertion).
- **FR2.7** (6.5.3) Narration-before-Skill: assert a narration text block precedes any `tool_use(skill_*)` event in the bubble sequence.
- **FR2.8** (6.5.4) Subprocess-reuse: two consecutive turns invoking the same Skill share a single subagent_spawn (assert `[data-spawn-id]` matches).
- **FR2.9** (6.6) Ended-state UX: a conversation with `workflow_ended_at` set shows the "Start new conversation" button and disables the input field.
- **FR2.10** (6.7) Container-restart pending-prompts drop: a `start_session` after a simulated container restart MUST clear `pendingPrompts` (asserts no orphaned interactive-prompt-card on reload).

### FR3 — Security smoke (PR-C)

Plan §369-386 tasks 6.8-6.11, automated to Playwright:

- **FR3.1** (6.8) Prompt-injection drain: inject a synthesized prompt-injection payload into a user message; assert the SDK-returned response does NOT execute the injected directive (assertion form: response does not contain the canary string the injection asked for, AND no tool_use block for the injection's named tool fires).
- **FR3.2** (6.9) Bash review-gate: any `tool_use(bash)` block surfaces an interactive-prompt-card with `kind=bash_approval` BEFORE execution; assert the card resolved-state grammar matches existing `interactive-prompt-card.test.tsx:bash_approval` cases.
- **FR3.3** (6.10) Cross-user prompt-response: a prompt sent by user A cannot have its response visible in user B's session. Mock-Supabase harness seeds two distinct test users; assert the second user's WS stream contains zero turns from the first user's conversation_id.
- **FR3.4** (6.11) 11-conversation rate limit: the 11th conversation creation by the same user in the rate-window MUST be refused with a structured error rendered in the chat UI (asserts `[data-rate-limit-exceeded]` element).

### FR4 — DEV_ORIGINS portability fix (PR-A)

In `apps/web-platform/server/validate-origin.ts`, replace the hardcoded `"http://localhost:3000"` in `DEV_ORIGINS` with a value that honors `NEXT_PUBLIC_APP_URL` (or equivalent env), falling back to `localhost:3000` for legacy dev. Verify by running the existing Playwright suite under both port 3099 (chromium) and port 3100 (authenticated) without 403s on POST routes.

### FR5 — Manual visual-QA rubric (PR-C)

A single `knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/visual-qa-rubric.md` document committed in PR-C. Rubric covers:

- **FR5.1** Avatar renders correctly for `cc_router` + each leader (no yellow-square fallback).
- **FR5.2** Markdown renders post `stream_end` (no stuck "loading" state).
- **FR5.3** Document/PDF context-aware reply: "ask about this document" returns a context-aware answer, not a generic one.
- **FR5.4** AC11 Continue-Thread tab reload: after tab reload, both user bubble + assistant bubble re-render on a cc-router or KB-Concierge conversation.
- **FR5.5** Light theme + dark theme spot-check (one screenshot per theme per bubble; 4 bubbles × 2 themes = 8 screenshots in PR description).
- **FR5.6** Screenshots committed to PR or repo: redact test-user identifiers (email, name, avatar URL) — per CLO ask.

The rubric is a one-time pre-merge gate, retired after PR-C lands.

### FR6 — Issue #2939 reconciliation

Edit #2939 body in-place with a **Reconciliation** block:

- Note that `FLAG_CC_SOLEUR_GO` was retired by #3270; cc-soleur-go is the unconditional production path.
- Reframe scope as "post-cutover regression net" not "pre-flag-flip gate."
- Link to this spec + brainstorm + 3 layered PRs (PR-A, PR-B, PR-C) as they land.

## Technical Requirements

- **TR1** Mock at the WebSocket message boundary using `page.evaluate()` to push frames into the chat client. Pattern source: `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` (replay recorded WS events through `applyStreamEvent`). Inject helper lives at `apps/web-platform/e2e/cc-soleur-go-ws-injector.ts` (~30 LoC).
- **TR2** New e2e tests use `.e2e.ts` extension (Bun picks up `.spec.ts`/`.test.ts` per 2026-03-29 learning).
- **TR3** Run from `apps/web-platform/` cwd; use `tsx` dev mode (NOT esbuild prod build — breaks on `@anthropic-ai/claude-agent-sdk` ESM/CJS per 2026-03-29 learning).
- **TR4** Supply URL-shaped dummy Supabase env vars to the spawned dev server (per 2026-03-29 learning). Reuse the `e2e/mock-supabase.ts` harness on port 54399.
- **TR5** All Playwright MCP screenshot paths absolute, worktree-rooted (per 2026-02-17 learning). If any test captures a screenshot, use `$(pwd)/tmp/screenshots/...`.
- **TR6** Any new Sentry mirror introduced by Stage 6 (e.g., "smoke detected unexpected leader-id") uses `mirrorWithDebounce` with a globally-unique `errorClass` slug registered in `apps/web-platform/server/observability.ts:223-237` (per 2026-05-13 learning).
- **TR7** Reuse the `start-fresh-*.e2e.ts` authenticated-test pattern: `page.addInitScript` injects fake `sb-localhost-auth-token` BEFORE `page.route()` mocks fire (the Supabase JS client short-circuit trap per `start-fresh-onboarding.e2e.ts:62-71`).
- **TR8** PostgREST `.single()` mocks MUST return an object (not array) — `Accept: application/vnd.pgrst.object+json` (per `start-fresh-conversations-rail.e2e.ts:137-153` PR #3021 phantom-failure note).
- **TR9** Smoke MUST NOT exercise any `mcp__soleur_platform__*` tool name that resolves to a denied tool (per Spec NG4 — would mask the #3720 Sentry signal #3722 depends on).
- **TR10** Auth-gate enumeration: if Stage 6 adds a new auth primitive, extend the canonical-list enumeration in the same PR (per 2026-04-18 learning).
- **TR11** Cross-user smoke (FR3.3) uses two distinct mock-Supabase users seeded in `e2e/mock-supabase.ts`; assertion form is "user B's WS stream contains zero conversation_ids from user A's set."

## Acceptance Criteria

- [ ] PR-A merges with: DEV_ORIGINS fix + WS-injector helper + 4 per-bubble assertions (FR1.1-FR1.4). New e2e tests green on CI.
- [ ] PR-B merges with: FR2.1-FR2.10 routing/cost/UX smoke. New e2e tests green on CI.
- [ ] PR-C merges with: FR3.1-FR3.4 security smoke + visual-QA rubric doc (FR5). Manual QA screenshots attached to PR-C description with test-user identifiers redacted (FR5.6).
- [ ] Issue #2939 body updated with Reconciliation block citing #3270 (FR6).
- [ ] #3722 unblocked: Stage 6 closure is one of its 3 blockers; CLO DPA-row status and #3720 merge are the other two.
- [ ] No `toHaveScreenshot()` baselines committed (Spec NG1).
- [ ] No real-SDK calls from CI (Spec NG2).
- [ ] No MCP allowlist non-empty default (Spec NG3, NG4).
- [ ] Smoke does not exercise denied MCP tools (TR9).

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Mock-WS injector drift from real cc-soleur-go protocol | M | TR1 pins the source pattern (`cc-soleur-go-end-to-end-render.test.tsx`); if WS protocol changes, that file is the canonical source and is already covered by unit tests |
| Theme PRs break manual-rubric screenshots | M | Rubric is one-time pre-merge (PR-C only); not re-run on each theme PR. Spec NG1 keeps `toHaveScreenshot()` out |
| Brittleness of security smoke (FR3.1 prompt-injection) | M | Use a synthesized injection payload with a canary string; assert canary absence not response content |
| DEV_ORIGINS fix breaks legacy local dev | L | FR4 fallback to `localhost:3000` when env var absent |
| Cross-user smoke (FR3.3) false-negative on slow CI | L | Use deterministic WS-injection, not real session-establishment timing |
| Phase 2 (#3722) blocked indefinitely if Stage 6 PRs are large | M | 3-PR layering (~250-300 LoC each); each closes a slice of #2939 |

## Domain Review (carry-forward)

Per brainstorm Domain Assessments. **All three triad leaders convergent on GO**; details:

- **CPO:** Kill-switch threshold (not graded rollout). Degraded-UX assertion is the right shape for the empty-allowlist reality. Manual rubric is one-time. → **GO**
- **CLO:** Synthesized fixtures + screenshot-redaction AC cover the PA 2 risk. No DPA delta. → **GO** with FR5.6 added.
- **CTO:** Mock-WS-boundary + no-`toHaveScreenshot()` + 3-PR layering. Surface the FLAG_CC_SOLEUR_GO retirement (#3270) explicitly. → **GO**

`requires_cpo_signoff: true` and `requires_clo_signoff: true` set in frontmatter because operator endorsed both `trust breach` AND `data loss / corruption` vectors at `single-user incident` threshold.
