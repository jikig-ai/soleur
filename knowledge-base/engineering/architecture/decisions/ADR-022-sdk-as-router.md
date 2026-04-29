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

## 2026-04-29 follow-up — Command Center QA fixes (PR #3020)

Three QA findings from the V1 dogfood drove this amendment. See plan `knowledge-base/project/plans/2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md`.

### Decision 1 — Safe-Bash auto-approve allowlist (NOT `bypassPermissions`)

**Context:** users were prompted to Approve/Deny trivial inspection commands (`pwd`, `ls`, `git status`) on every turn; the user-suggested fix was the SDK's `--dangerously-skip-permissions` flag (i.e. `permissionMode: "bypassPermissions"`).

**Rejected:** `bypassPermissions` is an SDK-level kill-switch for the entire `canUseTool` chain. Per `@anthropic-ai/claude-agent-sdk/sdk.d.ts:1101-1111`, it bypasses (a) `BLOCKED_BASH_PATTERNS` deny (`curl|wget|nc|sudo|sh -c|/dev/tcp|base64 -d|eval`), (b) `FILE_TOOLS` sandbox-path check, (c) tier-blocked platform tools, (d) the plugin MCP allowlist. In a multi-tenant web app where the LLM consumes prompt-injection-vulnerable user input, any successful injection becomes immediate code execution within the user's sandbox — with BYOK key + service tokens reachable in env.

Two SDK-side alternatives also considered and rejected:

- `permissionMode: "acceptEdits"` — auto-approves file edits; doesn't help (`pwd` is Bash, not a file edit) and would auto-approve `Edit`/`Write`. Strict regression.
- `permissionMode: "dontAsk"` — denies anything not pre-approved. Would re-engineer the entire permission model. Scope creep.

**Accepted:** narrow `SAFE_BASH_PATTERNS` allowlist in `permission-callback.ts` (read-only file/git/cwd inspection: `pwd`, `ls`, `cat`, `head`, `tail`, `wc`, `file`, `stat`, `which`, `whoami`, `id`, `date`, `uname`, `hostname`, `echo`, `git status|log|diff|show|branch|rev-parse`, `git config --get`). Each pattern is a leading-token regex with strict argument shape. The check runs AFTER `BLOCKED_BASH_PATTERNS` (defense in depth) and BEFORE the review-gate. Compound commands, shell metacharacters (`;`, `&`, `|`, backtick, `<`, `>`, `$`, U+2028, U+2029, `\n`, `\r`, `\\`), and inputs over 4096 chars fall through to the gate.

**Threat model surface that remains in force:** `BLOCKED_BASH_PATTERNS` deny, `FILE_TOOLS` sandbox-path check, plugin MCP allowlist, and the per-(user, conversation) review-gate. Notably excluded from the allowlist: `printenv` (env-dump risk for BYOK key + service tokens), `find` and `grep` (`-exec` could shell out).

### Decision 2 — Awaiting-user pause hook for the runaway timer

**Context:** the wall-clock runaway timer (`soleur-go-runner.ts`, default 30s) armed on first `tool_use` and only cleared on `SDKResultMessage`. While a Bash review-gate awaited the user's click, no result arrived → timer fired with `Workflow ended (runner_runaway)`. The product became unusable for any non-trivial Bash-touching prompt.

**Decision:** add `notifyAwaitingUser(conversationId, awaiting: boolean)` to `SoleurGoRunner`. While `awaiting === true`, `armRunaway` is a no-op and the timer callback re-checks the flag (race-window guard). On `awaiting === false`, the runner re-arms with a fresh `state.firstToolUseAt = now()` if no `SDKResultMessage` has cleared it.

**Wall-clock contract change (RUNNER PUBLIC API):** the wall-clock budget now measures **agent compute time only**, not human read time. A user who pauses indefinitely no longer triggers `runner_runaway`; the upstream safety net is `abortableReviewGate`'s 5-minute timeout (`review-gate.ts`), which rejects → `consumeStream` catches → `internal_error` fires once. Safety-net hierarchy: `abortableReviewGate` (5 min) > `runaway` (30 s agent compute).

**Wired via:** `cc-dispatcher.ts updateConversationStatus` calls `notifyAwaitingUser(true)` on `"waiting_for_user"` and `(false)` on `"active"`. When the runner has no active query for the conversation (reaped or container-restarted), `notifyAwaitingUser` mirrors via `reportSilentFallback` and returns; the conversation status write proceeds and the abandoned canUseTool subprocess hits the 5-min safety net cleanly.

**Known limitations** (filed as follow-ups): rapid `waiting_for_user` ↔ `active` flap can extend the budget across pauses; the idle reaper does not consult `awaitingUser` and may reap a conversation in the middle of a >10-min user pause.

### Decision 3 — `WORKFLOW_END_USER_MESSAGES` typed map

`cc-dispatcher.ts onWorkflowEnded` previously emitted `Workflow ended (${status}) — retry to continue.` — a status-enum leak with hostile copy. Replaced with `WORKFLOW_END_USER_MESSAGES: Record<WorkflowEndStatus, string>`. Adding a new variant to `WorkflowEnd["status"]` produces a TS error at the map declaration; runtime test in `cc-dispatcher.test.ts` snapshots all keys.

### Decision 4 — Phantom approval cards (resolved-card UX)

Two related fixes:

- `interactive-prompt-card.tsx` resolved state across all 6 variants (`ask_user`, `plan_preview`, `diff`, `bash_approval`, `todo_write`, `notebook_edit`) renders a compact `<ResolvedCardRow>` matching `ReviewGateCard:40-49` instead of disabled buttons + footer.
- `soleur-go-runner.ts classifyInteractiveTool` returns `null` for Bash when `isBashCommandSafe(command)` matches — auto-approved commands no longer emit phantom `bash_approval` `interactive_prompt` events that would land orphan cards in `pendingPrompts`.

### Decision 5 — Agent rename

`cc_router.title` → "Soleur Concierge", `name` → "Concierge". Internal id `cc_router` unchanged across all consumers (test files, state-machine narrowing, leader-colors map, tool-use chip).
