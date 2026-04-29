---
adr: ADR-022
title: SDK as Router for the Command Center
status: active
date: 2026-04-24
---

# ADR-022: SDK as Router for the Command Center

## Context

The Command Center web app (`apps/web-platform`) today routes a user's first
message through a bespoke server-side classifier in `domain-router.ts`, which
dispatches to one or more domain-leader agents (CTO/CPO/CMO/etc.). Each leader
runs its own SDK `query()` session with the Soleur plugin loaded. Two pain
points motivated this decision:

1. **Multi-leader spawning costs.** On messages where the classifier saw
   overlapping domain signals (e.g., "help me fix issue 2831" → CPO + CTO), the
   legacy router spawned every matching leader in parallel. Measured cost:
   ~$0.44/turn for duplicated upstream work (plugin load × N leaders, the
   same issue look-up × N, ...). Issue #2853 captured the cost and the
   double-bubble UX confusion.
2. **CLI / Command Center workflow divergence.** The CLI dispatches intent
   through `/soleur:go` (a slash command that classifies then routes to a
   workflow skill). The web app had no equivalent — leaders each own their
   own behavior and the workflow pipeline (brainstorm → plan → work → review
   → ship → compound) is not first-class in web UX.

The ~2026-04-23 brainstorm (see
`knowledge-base/project/brainstorms/2026-04-23-cc-single-leader-routing-brainstorm.md`)
pivoted from a minimal "single primary leader" patch to a more ambitious
"SDK as router" approach: route web turns through the SAME `/soleur:go`
command that the CLI uses, so web and CLI converge on identical workflow
semantics.

Stage 0 of plan
`knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md`
spiked the pattern. The 2026-04-24 rerun under streaming-input mode
(`prompt: AsyncIterable`) produced the data the decision is based on:

- H1 CONFIRMED: `prompt: "/soleur:go <msg>"` with `plugins: [soleur]` +
  `settingSources: []` actually dispatches the command (100% routing across
  70 runs total).
- H3 CONFIRMED: `canUseTool` intercepts non-pre-approved tools (Bash, Glob,
  Read, AskUserQuestion, Edit, Agent, ToolSearch) under the production
  threat model.
- Steady-state first-tool-use P95 = 6.1s (well under the revised 8s SLO);
  first-message P50 = 5ms, proving the SDK subprocess stays alive across
  turns when `streamInput()` is used instead of one-shot string prompts.

## Decision

Adopt `/soleur:go` as the Command Center's router for new conversations.
Build a dedicated `soleur-go-runner.ts` that:

- Maintains ONE long-lived `Query` per conversation (streaming-input mode;
  the CLI subprocess stays alive across turns, amortizing ~30s plugin-load
  cold-start over the conversation lifetime).
- Consumes `stream_event` partial messages to render `tool_use` status chips
  at ~5-6s after message send — the load-bearing early-ack for perceived
  latency.
- Instructs the model via systemPrompt to emit a one-line narration BEFORE
  calling `Skill`, so the user sees text at first-tool-use time (~6s) rather
  than silence until the dispatched skill produces its first output (~10-17s).
- Enforces per-workflow cost circuit breakers and a secondary 30s-no-result
  wall-clock runaway trigger.
- Persists the chosen workflow on `conversations.active_workflow` (migration
  032) for sticky routing on turn 2+.

Legacy `domain-router.ts` / `agent-runner.ts` / `dispatchToLeaders` remain
behind `FLAG_CC_SOLEUR_GO=false` until a 14-day dev soak confirms the new
path, then Stage 8 (separate PR) removes them.

## AP-004 deviation (intentional, for V1)

The original architecture principle AP-004 held that the CLI and Command
Center should share a routing model. This ADR intentionally diverges for
V1:

- **CLI** continues to use the human-in-the-loop `/soleur:go` pattern:
  operator types a slash command, Claude Code expands it in-process, the
  existing conversation-scoped plugin context answers in one shot.
- **Command Center** uses `/soleur:go` **as the first SDK instruction** on
  every new web conversation's turn 1. Turn 2+ stays sticky inside the
  chosen workflow via `conversations.active_workflow` rather than
  re-classifying.

Both invocation paths end up dispatching to the same workflow skills, which
is the CLI/web parity that matters for the user experience. The surface
divergence (slash-command vs. system-prompt injection) is an implementation
detail of how each surface reaches the same skill.

**Convergence path:** V2-11 tracks unifying both routes through a shared
"workflow dispatcher" module so the surface becomes a presentation layer
over a common routing core. Scope excluded from this PR because it depends
on the streaming-input runner proven out first (`soleur-go-runner.ts`
ships here; the dispatcher abstraction lifts above it later).

## Cross-references

- ADR-010 — Brainstorm Default Routing (the "brainstorm is the default
  workflow" decision that `/soleur:go` preserves).
- ADR-018 — Passive Domain Routing (the CLI-side policy that this ADR's
  AGENTS.md rule edit amends to distinguish overlapping from orthogonal
  signals).
- V2-11 in the plan's Stage 5 list — CLI + CC routing unification.

## Consequences

**Positive:**

- Web conversations gain access to the same workflow pipeline the CLI uses
  (plan → work → review → ship → compound), not just leader chat. Delivers
  the "CLI UX in the browser" goal originally scoped to #2853.
- Eliminates the duplicate-leader spawning cost class from #2853 (single
  primary workflow; `@mention` escalation UI already shipped separately).
- Streaming-input refactor side-effect: fixes production's ~30s/turn
  subprocess-spawn cost that `agent-runner.ts:778` pays today with its
  `prompt: string` one-shot pattern.

**Negative / risks:**

- Per-turn model cost is higher than the legacy direct-leader pattern
  because `/soleur:go` adds a classify step before skill dispatch. Spike
  data shows $0.24-$4.21 per successful run (P95 $0.52 excluding the
  brainstorm-dispatching outlier). Cost circuit breakers and recalibrated
  Doppler caps manage the blast radius.
- Per-conversation subprocess lifetime adds container-memory pressure as
  conversations accumulate. The runner idle-reaps after 10 minutes and
  force-closes on terminal `workflow_ended` statuses.
- Security posture depends on `settingSources: []` + restricted
  `mcpServers` whitelist. The spike confirmed `canUseTool` fires correctly
  under this config. Any future relaxation (allowing more MCP tools, or
  allowing `settingSources: ["project"]`) needs a threat-model re-review
  (V2-13 tracks per-tool tier classification for safe whitelist expansion).

**Neutral:**

- Legacy router coexists behind the flag during soak. Rollback = flip flag
  off; no data migration needed (the two code paths branch on
  `conversations.active_workflow IS NULL`).

## Status signals

- Stage 0 spike script: `apps/web-platform/scripts/spike-soleur-go-invocation.ts`
  (deleted pre-merge per plan task 0.7).
- Raw rerun data (gitignored): `knowledge-base/project/plans/spike-raw-stream-input.json`.
- Production runner arrives in Stage 2 of the plan.

## 2026-04-29 follow-up

- **Safe-Bash auto-approve allowlist** added in `permission-callback.ts` — read-only file/git inspection commands (e.g., `pwd`, `ls`, `git status`) bypass the user gate. Compound commands and shell-metacharacter inputs still flow through the existing review-gate. The SDK `bypassPermissions` mode was rejected as unsafe in the multi-tenant web app.
- **Awaiting-user pause hook** in the runner — the wall-clock runaway timer pauses while a user gate is awaiting response. Wired via `cc-dispatcher.ts updateConversationStatus`. Wall-clock now counts agent compute time only, not human read time.
- **Agent rename** — `cc_router.title` → "Soleur Concierge" (internal id unchanged).
- **User-facing workflow-end copy** moved to a typed `WORKFLOW_END_USER_MESSAGES` map.
