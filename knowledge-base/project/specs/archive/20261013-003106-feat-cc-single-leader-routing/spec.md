# Feature: Command Center routes via `/soleur:go` (single-leader default + on-demand escalation)

**Issue:** #2853
**Branch:** feat-cc-single-leader-routing
**Draft PR:** #2858
**Brainstorm:** [knowledge-base/project/brainstorms/2026-04-23-cc-single-leader-routing-brainstorm.md](../../brainstorms/2026-04-23-cc-single-leader-routing-brainstorm.md)

## Problem Statement

The Command Center's web-side router (`apps/web-platform/server/domain-router.ts`) auto-routes user messages to multiple domain leaders in parallel by string-matching domain assessment questions. For routine execution intents (e.g., "resume work on issue 2831"), this produces:

- **~$0.44 per turn cost** for parallel CPO + CTO doing duplicated upstream work (issue lookup, GitHub tool calls).
- **Confusing two-column bubble UX** with separate per-leader streams when one task only needed one voice.
- **Compounded risk** of the stuck-"Working" bubble lifecycle bug observed in PR #2843.

The root mistake is that the web router has no concept of **intent** — it treats every message as if it were exploration. The CLI's `/soleur:go` skill already classifies intent correctly (`fix → one-shot` single-leader, `default → brainstorm` multi-leader-when-relevant) and could replace the bespoke router entirely.

## Goals

- Eliminate parallel multi-leader spawn for routine execution intents (target: ~50% per-turn cost reduction on single-domain operator messages).
- Unify routing logic between CLI and web platform: `/soleur:go` becomes the single source of truth for "which workflow + which leader(s)?".
- Preserve multi-leader spawn for genuine exploration (brainstorm-mode) — that is the intended brainstorm behaviour, not a bug.
- Keep the existing `@mention` escalation path for explicit per-turn override.

## Non-Goals

- **Modifying brainstorm Phase 0.5's multi-leader spawn semantics.** Brainstorm IS the surface where multi-leader is desired; cost reduction comes from routing fewer messages into brainstorm, not from changing brainstorm itself.
- **Building a new intent classifier on the web side.** The whole point is to delete the duplicate.
- **Changing the AGENTS.md `pdr-when-a-user-message-contains-a-clear` rule's CLI semantics.** The rule still governs CLI passive routing; only the wording is updated to clarify orthogonal-vs-overlapping (since the rule no longer governs Command Center routing — that moves to `/soleur:go`).
- **Per-message `/soleur:go` re-execution.** Sticky workflow: turn 1 dispatches, turn 2+ stay inside the chosen workflow.

## Functional Requirements

### FR1: New conversations route via `/soleur:go`

Each new conversation in the Command Center invokes the actual `/soleur:go` skill on the user's first message via `@anthropic-ai/claude-agent-sdk`. The skill classifies intent and dispatches to the appropriate workflow skill (`one-shot` / `drain-labeled-backlog` / `review` / `brainstorm`). Routing decisions move out of `apps/web-platform/server/domain-router.ts` entirely.

### FR2: Sticky workflow for turn 2+

Once `/soleur:go` has dispatched to a workflow, subsequent user messages in the same conversation continue inside that workflow (its dialogue, its skill instructions, its leader-spawn rules). The conversation ends when the workflow ends or when the user starts a new conversation.

### FR3: Multi-leader spawn preserved inside brainstorm

When `/soleur:go` routes to `brainstorm`, brainstorm Phase 0.5 retains its current behaviour of spawning multiple domain leaders when multiple are relevant. No semantic changes to `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`.

### FR4: `@mention` escalation works inside any workflow

The existing `AtMentionDropdown` (`apps/web-platform/components/chat/at-mention-dropdown.tsx`) and `parseAtMentions` (`apps/web-platform/server/domain-router.ts`) continue to work as an explicit per-turn override. `@CTO`, `@CPO`, etc. force a specific leader voice regardless of the active workflow.

### FR5: Interactive tool surfaces in the chat UI

When the embedded `/soleur:go` invocation triggers interactive tools (`AskUserQuestion`, `ExitPlanMode`, file `Edit`/`Write`, `Bash`), they render as appropriate chat-bubble variants. Mapping per tool to be specified in `/soleur:plan` (Open Question #2 in brainstorm).

### FR6: Subagent spawns visible to the operator

When a workflow (e.g., brainstorm Phase 0.5) spawns parallel subagents (e.g., CPO + CTO assessments), the operator sees the spawn structure in the chat — either as today's parallel-leader bubbles or as nested children. Choice deferred to plan.

### FR7: Cost telemetry

Each conversation logs total Claude API cost (prompt + completion + tool spend) to enable measuring the ~50% reduction target. Surface in admin telemetry, not in the operator UI.

## Technical Requirements

### TR1: Embed `@anthropic-ai/claude-agent-sdk` in `apps/web-platform/server/`

Replace the `fetch`-based parallel API calls in `agent-runner.ts` with an Agent SDK runner that loads the soleur plugin (skills + agents). One runner instance per active conversation. Lifecycle managed alongside the existing WebSocket session.

### TR2: Sandbox model

The embedded SDK runner needs filesystem and tool access for skill execution (`Bash`, `Read`, `Edit`, `Write`). PR #2843's `gh` ENOENT precedent argues against full shell access in the web container. Three candidate models (decide in plan):

- **(a) Full Docker-volume access** matching the dev environment.
- **(b) Agent-native virtual fs** over Supabase + GitHub MCP tools (no shell).
- **(c) Per-conversation ephemeral worktree** scoped to the runner.

### TR3: WebSocket protocol extension

The SDK runner emits structured events (text deltas, tool calls, subagent spawns, interactive prompts). The current `stream_start` / `stream` / `stream_end` / `tool_use` protocol needs new event types or a re-shape to carry skill-execution state. Backward compatibility for in-flight conversations on the old router required during rollout.

### TR4: Cold-start latency budget

P95 first-token latency must not exceed 10 seconds. SDK runner cold start, plugin load, and `/soleur:go` classification all happen before the first user-visible token. If exceeded, the plan must specify a warm-pool or pre-load strategy.

### TR5: Per-conversation cost ceiling

P95 per-conversation total cost must not exceed $1. If exceeded, a circuit breaker downgrades the conversation to a single-leader chat without skill execution.

### TR6: Update `pdr-when-a-user-message-contains-a-clear` rule

Reword the rule to clarify orthogonal-vs-overlapping semantics for **CLI passive domain routing only**. Add a note that Command Center routing is governed by `/soleur:go` invocation, not by this rule. Preserve the rule ID (`pdr-when-a-user-message-contains-a-clear`) per `cq-rule-ids-are-immutable`.

### TR7: Verify Agent SDK feasibility before commit

Spike `@anthropic-ai/claude-agent-sdk` in isolation: load the soleur plugin, invoke `/soleur:go`, verify programmatic streaming, verify `AskUserQuestion` is surfaceable as structured output. Documented spike result attached to the plan before any web-platform integration begins.

### TR8: Migration / rollout

Behind a feature flag. Existing in-flight conversations stay on the old router; new conversations route via `/soleur:go` once flag is on. Metrics dashboard tracks cost and latency before flag goes to 100%.

## Acceptance Criteria (carried from #2853, updated against current code state)

- [x] **AC #3 (`@mention` escalation UI)** is already implemented in `at-mention-dropdown.tsx`. Verified during brainstorm. Carries forward unchanged.
- [ ] **AC #1** Update `pdr-when-a-user-message-contains-a-clear` rule wording — see TR6.
- [ ] **AC #2** Single-primary-leader selection — addressed *not* by modifying the web router but by replacing it with `/soleur:go` invocation (FR1).
- [ ] **AC #4** Document the multi-leader fallback — captured in this spec (FR3) and in the brainstorm doc.
- [ ] **AC #5** Measure cost impact — see FR7 + TR5.

## Open Questions (resolve in plan)

See [brainstorm doc Open Questions section](../../brainstorms/2026-04-23-cc-single-leader-routing-brainstorm.md#open-questions-resolve-in-soleurplan).
