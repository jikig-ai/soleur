---
title: "deepagents Portability — Critical Unknowns"
date: 2026-06-08
issue: 5034
confidence: "docs-only — items below require a PoC to verify before any investment decision"
---

# deepagents Critical Unknowns

These are flagged **docs-only confidence**. The inventory and recommendation are sound on the architecture-level facts (Python subagents, identical SKILL.md, built-in write_todos, checkpointers, no plugin system — all source-verified). The items below could each shift the effort estimate or the verdict and must be resolved by a proof-of-concept before committing.

## U1 — dcode harness maturity (HIGH impact)

**Unknown:** Can `deepagents-code` / `dcode` reliably run Soleur's long, multi-step pipelines (go→brainstorm→plan→work→review→ship, 10+ tool turns, parallel subagent fan-out)?

**Why it matters:** The CLI is at v0.1.0 with documented packaging churn (the REPL was split out of `deepagents-cli` into `deepagents-code`). The recommendation's "now a real harness" framing depends on this. If dcode can't sustain long pipelines, the only viable surface is the SDK with a self-built operator UX — raising effort.

**PoC:** Run a 5-turn skill chain + a 2-level subagent fan-out under `dcode` and observe stability, context handling, and HITL behavior.

## U2 — Subagent nesting depth (MEDIUM impact)

**Unknown:** Does `SubAgentMiddleware` support multi-level nesting (domain leader → specialist → sub-specialist) in practice, or only one level?

**Why it matters:** Research found nesting is "not prevented in code" but "theoretically possible / unverified." Soleur's domain leaders (cmo with 11 specialists) assume at least 2 levels. If nesting is unsupported/unstable, the hierarchy flattens (closer to the Gemini CLI degradation).

**PoC:** Spawn a subagent that itself spawns a subagent via `task`; confirm isolation and result propagation.

## U3 — Structured-prompt absence — real impact on gates (MEDIUM impact)

**Unknown:** Is there *any* options-list schema in `HumanInTheLoopMiddleware`, or strictly approve/edit/reject/respond + free text?

**Why it matters:** 31 components use AskUserQuestion. If only freeform `respond` exists, Soleur's routing/approval gates (go, brainstorm, plan, ship) degrade to natural-language parsing. Workaround viability was rated HIGH for OpenHands under the same constraint, but it should be confirmed for deepagents' resume/`Command(resume=...)` flow.

**PoC:** Implement one brainstorm-style multi-option gate via `respond` and measure routing reliability.

## U4 — Skill argument injection semantics (MEDIUM impact)

**Unknown:** Does `dcode` `/skill:<name> [args]` perform `$ARGUMENTS`-style substitution into the SKILL.md body, or merely prepend the args as a user message?

**Why it matters:** 30+ skills/commands pass arguments. The substitution model determines whether arg-dependent skills (fix-issue, drain-labeled-backlog, flag-set-role) port cleanly or need rework.

**PoC:** Invoke a skill that references a positional arg in its body and inspect how args reach the model.

## U5 — Shell-hook → middleware parity for deny-with-feedback (MEDIUM impact)

**Unknown:** Does `wrap_tool_call` middleware reproduce Soleur's hook pattern of *blocking a tool call with exit code 2 and surfacing a reason to the model* (guardrails.sh, worktree-write-guard.sh)?

**Why it matters:** Soleur's safety rails (never-git-stash, worktree-write-guard, pre-merge-rebase) are PreToolUse bash hooks that deny + explain. The middleware must support raising/short-circuiting a tool call AND returning a model-visible reason, not just observing.

**PoC:** Port `worktree-write-guard.sh` to a `wrap_tool_call` middleware that blocks a write and returns a correction message; confirm the model sees and acts on it.

## U6 — Plugin/distribution packaging story (MEDIUM impact)

**Unknown:** What is the canonical way to ship a large bundle (67 agents + 82 skills + middleware) as an installable, versioned unit a third party can `enable`/`disable`?

**Why it matters:** deepagents has no plugin manifest. Best current guess: a Python package (agents/middleware) + a `skills/` directory. There is no enable/disable/uninstall lifecycle. This affects how Soleur would distribute — and whether a "Soleur on deepagents" product is even shippable as one artifact.

**PoC:** Package the 29 GREEN skills as a pip-installable `skills/` provider and consume it from a fresh deepagents project.

## U7 — MCP wiring at scale (LOW impact)

**Unknown:** Operational overhead of replacing `.mcp.json` auto-load with explicit `MultiServerMCPClient` wiring for Soleur's MCP servers (Context7, Cloudflare, Stripe, Supabase, Pencil, Playwright, Linear).

**Why it matters:** Capability is GREEN, but per-server Python wiring + auth handling for ~8 servers adds boilerplate and an auth-refresh story (some servers are interactively authenticated).

**PoC:** Wire 2 MCP servers (one stdio, one HTTP) via `MultiServerMCPClient` and confirm tool availability inside a subagent.

## U8 — Cost / token profile of durable checkpointing (LOW impact)

**Unknown:** Token/latency/storage cost of checkpointing state every superstep over Soleur's long pipelines.

**Why it matters:** Durable persistence is a strength, but checkpoint-every-superstep on 10+ turn pipelines with large context could be expensive. Needs measurement before a server-side runtime commit.

**PoC:** Run a representative pipeline with a Postgres checkpointer and measure storage growth + latency overhead.

---

## Resolution gate

Do not advance past the **skills-only** scope (1–2 wk, lowest risk) until U1, U3, and U6 are resolved — they gate whether a fuller migration is viable at all. U2/U4/U5 gate the agent-and-pipeline scope. U7/U8 gate the server-side-runtime scope.
