---
date: 2026-04-23
issue: 2853
branch: feat-cc-single-leader-routing
pr: 2858
status: brainstorm-complete
---

# Command Center: route via `/soleur:go` (single-leader default + on-demand escalation)

## What We're Building

Replace the Command Center's bespoke web-side domain router (`apps/web-platform/server/domain-router.ts`) with **literal invocation of the `/soleur:go` skill** via `@anthropic-ai/claude-agent-sdk`. New conversations route through `/soleur:go`, which classifies intent (`fix` / `drain` / `review` / `default`) and dispatches to the matching workflow skill (`one-shot`, `drain-labeled-backlog`, `review`, `brainstorm`). Subsequent turns stay inside the chosen workflow (sticky workflow). Multi-leader spawn remains the brainstorm-mode behaviour (it is what brainstorming is FOR); routine execution gets a single primary leader voice.

The original AC #3 (`@mention` escalation UI) is **already implemented** in `apps/web-platform/components/chat/at-mention-dropdown.tsx` (139 lines) and `parseAtMentions` in `domain-router.ts`. It carries forward unchanged into the new architecture.

## Why This Approach

The double-routing observed in PR #2843 ($0.44/turn for parallel CPO + CTO on a single-domain "resume issue 2831" message) was caused by treating an **execution intent** as if it were **exploration**. The web router has no concept of intent — it just asks "which domains match this string?" and spawns every match.

`/soleur:go` already classifies intent correctly: `fix → one-shot` (single leader), `default → brainstorm` (multi-leader assessment is desired here). Porting the logic again in the web platform creates two places to keep in sync; **invoking the actual skill** unifies the routing semantics across CLI and web. Skill changes propagate to the Command Center for free.

Trade-offs accepted (chosen over Approach B / Approach C in Phase 2):

- **Largest rewrite.** Touches WebSocket protocol, agent runner, interactive-tool → chat-UI mapping, and the embedded sandbox model.
- **5-30s first-token latency** on cold starts (vs ~200ms today for Haiku classifier).
- **Sandbox question is unsolved.** Skills use `Bash`, `Read`, `Edit`, `Write`. PR #2843 already hit this with `gh` ENOENT in the agent runner. This brainstorm acknowledges the question; the plan must answer it.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Routing mechanism | Embed `@anthropic-ai/claude-agent-sdk` in `apps/web-platform/server/`. New conversation → spawn SDK runner with soleur plugin loaded → invoke `/soleur:go <user-message>`. | Single source of truth; skill changes auto-propagate. |
| Turn lifecycle | Sticky workflow. Turn 1 = `/soleur:go` dispatch. Turn 2+ stay inside chosen workflow until it ends. New conversation = new dispatch. | Matches CLI mental model. Avoids per-turn cost of `/soleur:go` re-execution. |
| Multi-leader spawn in brainstorm | Unchanged. Brainstorm Phase 0.5 keeps spawning multiple leaders when relevant — that is what brainstorming is FOR. | The cost problem was misclassified execution intents, not brainstorm itself. |
| Single-primary in classifier | The web's Haiku classifier is replaced (not modified). Routing decisions move into `/soleur:go` and the workflow skills' own logic. | No need to update `domain-router.ts`'s prompt; the file goes away (or shrinks dramatically). |
| `pdr-when-a-user-message-contains-a-clear` rule update | Reword to clarify "orthogonal vs overlapping" semantics, *and* note that the Command Center now routes via `/soleur:go` (so the rule applies to CLI agent passive routing, not to the Command Center directly). | Rule still governs CLI behaviour; web behaviour is now defined by `/soleur:go` invocation. |
| `@mention` escalation UI | Keep as-is. Already implemented (`AtMentionDropdown` + `parseAtMentions`). Works inside any workflow as override. | AC #3 of #2853 is largely already done; verify discoverability during QA. |

## Open Questions (resolve in `/soleur:plan`)

1. **Sandbox model.** What filesystem and tool access does the embedded SDK runner have inside the web server? Options: (a) full Docker-volume access matching the dev environment, (b) virtual fs over Supabase + GitHub MCP tools (agent-native, no shell), (c) per-conversation ephemeral worktree. PR #2843's `gh` ENOENT pushed toward (b); skill execution may force (c).
2. **Interactive tool → chat UI mapping.** How does the chat render `AskUserQuestion` (chips), `ExitPlanMode` (preview + accept), `Edit`/`Write` (diff viewer?), `Bash` (terminal panel?)? Each interactive tool needs a chat-UI surface or a "this happens silently in the background" decision.
3. **Subagent visualisation.** When brainstorm Phase 0.5 spawns CPO + CTO, do they render as today's parallel-leader bubbles, or as nested children inside one `/soleur:go` thread? Affects WebSocket protocol shape.
4. **Conversation lifecycle / "ended" state.** When a workflow exits (e.g., brainstorm completes), what happens to the chat? Auto-close? Allow free-chat fallthrough? New `/soleur:go` re-dispatch on next user input?
5. **Agent SDK availability and stability.** Verify `@anthropic-ai/claude-agent-sdk` exists, supports plugin loading, supports programmatic streaming, and is stable enough for production. Use the `claude-code-guide` agent or context7 MCP to confirm.
6. **Cost ceiling.** First-token latency 5-30s and per-turn skill execution cost. Define an SLO (e.g., "P95 first token < 10s, P95 conversation cost < $1") and a fallback if exceeded.
7. **Migration strategy.** Big-bang cutover or feature-flag rollout? Existing in-flight conversations on the old router need a story.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Per `pdr-do-not-route-on-trivial-messages-yes` exception ("do not route when the domain signal IS the current task's topic"), the assessment for Engineering and Product was performed inline rather than spawning subagents — this brainstorm IS about routing/leader architecture. Marketing, Legal, Sales, Support, Finance, and Operations have no signal (internal operator tooling, no external surface, no procurement, no compliance). The minimum-CPO/CMO requirement of `hr-new-skills-agents-or-user-facing` is satisfied by inline assessment of an existing capability modification (not a new user-facing capability).

### Engineering (CTO, inline)

**Summary:** Largest impact area. Embedding `@anthropic-ai/claude-agent-sdk` server-side reshapes `agent-runner.ts`, the WebSocket protocol, and the sandbox model. Sandbox unknowns are the single biggest planning risk — see Open Question #1. Prefer the agent-native (Supabase + GitHub MCP) route over giving the SDK shell access in the web container.

### Product (CPO, inline)

**Summary:** UX shift is real but mostly invisible: routine "do this thing" messages get a single voice (today's stuck-bubble UX disappears for those). Brainstorm-mode conversations look the same as today. Discoverability of the `@mention` escalation chip should be QA'd — the rule change makes it more important.

## Capability Gaps

- **No verified Agent SDK integration pattern in `apps/web-platform`.** The closest precedent is `agent-runner.ts`'s `fetch`-based parallel API calls — different beast. Plan must include a spike: a minimal SDK runner that invokes `/soleur:go` and streams output to stdout, before any web integration.
- **No chat-UI primitives for `AskUserQuestion`, `ExitPlanMode`, `Edit`/`Write`, `Bash`.** New chat bubble variants needed; needs `ux-design-lead` artifact before implementation per `wg-for-user-facing-pages-with-a-product-ux`.
- **No sandbox model documented for skill execution in the web platform.** Open Question #1 has to land before implementation can start.
