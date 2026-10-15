---
title: "deepagents Portability Inventory"
date: 2026-06-08
issue: 5034
deepagents_version: "deepagents 0.6.8 (PyPI, 2026-06-03); deepagents-code / dcode CLI; docs.langchain.com/oss/python/deepagents, accessed 2026-06-08"
methodology: "Grep-based scan for Claude Code-specific primitives across the live repo (152 components), classified against deepagents/LangGraph equivalents. Reclassification rule: agents flip to YELLOW because deepagents subagents are Python dicts (no markdown-agent loader); skills stay GREEN unless they depend on a degraded primitive (ASK, SKILL-chaining, ARGS, HOOK)."
---

# deepagents Portability Inventory

## Framing correction (vs the original assumption)

The prior three targets (Codex CLI, Gemini CLI, OpenHands) were framed as interactive harnesses and deepagents as "just a LangChain library, different category." **That framing is outdated as of 2026.** deepagents v0.6.8 ships `deepagents-code` (command `dcode`) — an interactive terminal coding agent the README self-describes as *"similar to Claude Code or Cursor,"* and the repo tagline is now *"the batteries-included agent harness."* deepagents is therefore a genuine OpenHands-class peer: a Python SDK **and** an operator-facing harness, explicitly inspired by Claude Code's architecture and generalizing it across model providers.

This inventory treats deepagents as a harness candidate and classifies against both the SDK and the `dcode` CLI.

## Summary Statistics

| Classification | Count | Percentage | Description |
|---|---|---|---|
| GREEN | 30 | 19.7% | Ports as-is (skill `SKILL.md` format identical; tool names differ but semantics match) |
| YELLOW | 122 | 80.3% | Needs adaptation — agents rewrite from markdown to Python `SubAgent` dicts; skills using degraded primitives (ASK/SKILL-chain/ARGS) lose fidelity |
| RED | 0 | 0% | — (no component is unportable; every primitive has an equivalent) |
| **Total** | **152** | **100%** | |

**By component type:**

| Type | Green | Yellow | Red | Total |
|---|---|---|---|---|
| Agents | 0 (0%) | 67 (100%) | 0 | 67 |
| Skills | 29 (35.4%) | 53 (64.6%) | 0 | 82 |
| Commands | 1 (33.3%) | 2 (66.7%) | 0 | 3 |

**Four-way comparison:**

| Classification | Codex CLI (2026-03-10) | Gemini CLI (2026-04-07) | OpenHands (2026-04-07) | deepagents (2026-06-08) |
|---|---|---|---|---|
| GREEN | 47.5% (58/122) | 54.3% (70/129) | 46.5% (60/129) | **19.7% (30/152)** |
| YELLOW | 7.4% (9/122) | 45.0% (58/129) | 53.5% (69/129) | **80.3% (122/152)** |
| RED | 43.4% (53/122) | 0.8% (1/129) | 0% (0/129) | **0% (0/152)** |
| Blockers with no equivalent | 4 | 1 | 0 | 0 |
| Subagent support | None | Single-level only | Multi-level + parallel | Multi-level (untested) + parallel |
| Agent authoring format | Config YAML | Markdown (flat) | Markdown (flat) | **Python `SubAgent` dict** |
| Skill authoring format | SKILL.md | SKILL.md | SKILL.md | **SKILL.md (identical, progressive disclosure)** |
| Plugin/distribution system | None | None | Full (install/enable/disable) | **None (skills dir only)** |

**Key insight — the pattern inverts OpenHands.** deepagents is the *second* zero-RED target (every Soleur primitive has at least a partial equivalent) yet has the **lowest GREEN% of any platform analyzed** (19.7%). The reason is a single architectural fact: deepagents subagents are **Python `SubAgent` TypedDicts**, and there is no markdown-agent loader. So all 67 of Soleur's markdown agents — including the entire domain-leader hierarchy — flip from GREEN (markdown→markdown on OpenHands) to YELLOW (markdown→Python rewrite). Conversely, deepagents `SkillsMiddleware` reads the **identical** `SKILL.md` + YAML-frontmatter + 3-level progressive-disclosure format, so skills port *better* than on OpenHands (where they were context-injection YELLOW).

**Net:** OpenHands = cheap-port-friendly (agents stay markdown, full plugin system). deepagents = expensive-port (agent rewrite + no plugin distribution) but **strongest strategic upside** (model-agnostic, durable persistence, MIT, 24k★ LangChain-backed).

## Primitive Mapping

| Claude Code Primitive | deepagents Equivalent | Classification | Delta vs OpenHands |
|---|---|---|---|
| AskUserQuestion | `HumanInTheLoopMiddleware` via `interrupt_on={tool: ...}` — decisions: approve / edit / reject / **respond** (free text). No structured multi-choice option set. Requires a checkpointer. | YELLOW | Same (both lack structured prompts) |
| TodoWrite / TaskCreate | `write_todos` tool via `TodoListMiddleware` — **built-in, default, 1:1** | GREEN | **Better** (OH had no equivalent → was YELLOW) |
| WebSearch | BYO tool (`tools=[tavily_tool]` etc.) — not built-in | YELLOW (GREEN-with-config) | Slightly worse (OH bundled via MCP) |
| WebFetch | BYO tool — not built-in | YELLOW (GREEN-with-config) | Slightly worse |
| MCP tools (mcp__*) | `langchain-mcp-adapters` `MultiServerMCPClient` — stdio + HTTP + SSE + WebSocket; `tools=client.get_tools()`. Explicit Python wiring (no `.mcp.json` auto-load). | GREEN | Same capability; worse ergonomics (no zero-config) |
| Task / Agent (subagent) | `task` tool via `SubAgentMiddleware` — parallel, context-isolated (`messages`/`todos`/`structured_response` filtered out of subagent state). Subagents defined as **Python `SubAgent` dicts**. | GREEN (capability) | Same parallelism; **worse authoring** (Python vs markdown) |
| Skill tool (chaining) | `SkillsMiddleware` — markdown `SKILL.md` + frontmatter, 3-level progressive disclosure. Model-driven activation; no programmatic mid-run invocation. | YELLOW | **Better format** (identical SKILL.md) but same chaining limit |
| $ARGUMENTS | `dcode` `/skill:<name> [args]` (CLI only). No SDK-level string interpolation into SKILL.md body. | YELLOW | Same |
| hookSpecificOutput | LangGraph middleware (`wrap_tool_call`, `before/after_model`) — inject context via state. **Python classes, not declarative shell hooks.** | GREEN (Python) | Same/better capability; worse for shell-based hooks |
| SessionStart / Stop hooks | `before_agent` / `after_agent` (run-scoped) + **durable checkpointers** (Postgres/Redis) for cross-session recall | GREEN | **Better** (durable persistence > CC + OH) |
| **Agent authoring format** (new dimension) | Python `SubAgent` TypedDict (`name`/`description`/`system_prompt`/`tools`/`model`/`middleware`). **No markdown-agent loader.** | YELLOW (drives all 67 agents) | **Worse** (OH read markdown agents) |

---

## Agents (67) — all YELLOW

deepagents has no markdown-agent loader; agents are Python `SubAgent` dicts. Every agent requires a carrier rewrite (markdown → `SubAgent(name=…, description=…, system_prompt=…)`). The **prose body ports verbatim** into `system_prompt`, so the conversion is mechanical for prose-only agents and scriptable in bulk. Agents that additionally reference ASK/TASK/MCP/WEB need primitive-level adaptation on top.

### YELLOW-mechanical (43) — prose-only, pure carrier rewrite (scriptable in bulk)

| Agent | Domain | Adaptation |
|---|---|---|
| cto | engineering | wrap body in SubAgent dict |
| ddd-architect | engineering/design | wrap |
| infra-security | engineering/infra | wrap (MCP refs → client wiring if any) |
| platform-strategist | engineering/infra | wrap |
| terraform-architect | engineering/infra | wrap |
| best-practices-researcher | engineering/research | wrap |
| framework-docs-researcher | engineering/research | wrap |
| git-history-analyzer | engineering/research | wrap |
| learnings-researcher | engineering/research | wrap |
| repo-research-analyst | engineering/research | wrap |
| architecture-strategist | engineering/review | wrap |
| code-quality-analyst | engineering/review | wrap |
| code-simplicity-reviewer | engineering/review | wrap |
| data-integrity-guardian | engineering/review | wrap |
| data-migration-expert | engineering/review | wrap |
| deployment-verification-agent | engineering/review | wrap |
| dhh-rails-reviewer | engineering/review | wrap |
| kieran-rails-reviewer | engineering/review | wrap |
| legacy-code-expert | engineering/review | wrap |
| observability-coverage-reviewer | engineering/review | wrap |
| pattern-recognition-specialist | engineering/review | wrap |
| performance-oracle | engineering/review | wrap |
| security-sentinel | engineering/review | wrap |
| test-design-reviewer | engineering/review | wrap |
| user-impact-reviewer | engineering/review | wrap |
| pr-comment-resolver | engineering/workflow | wrap |
| budget-analyst | finance | wrap |
| financial-reporter | finance | wrap |
| revenue-analyst | finance | wrap |
| legal-document-generator | legal | wrap |
| analytics-analyst | marketing | wrap |
| conversion-optimizer | marketing | wrap |
| paid-media-strategist | marketing | wrap |
| pricing-strategist | marketing | wrap |
| programmatic-seo-specialist | marketing | wrap |
| retention-strategist | marketing | wrap |
| seo-aeo-analyst | marketing | wrap |
| ops-advisor | operations | wrap |
| spec-flow-analyzer | product | wrap |
| deal-architect | sales | wrap |
| outbound-strategist | sales | wrap |
| pipeline-analyst | sales | wrap |
| ticket-triage | support | wrap |

### YELLOW-primitive (24) — carrier rewrite + primitive adaptation

| Agent | Domain | Primitives | Adaptation |
|---|---|---|---|
| agent-finder | engineering/discovery | ASK | HITL `respond` (loses structured options) |
| functional-discovery | engineering/discovery | ASK | HITL `respond` |
| agent-native-reviewer | engineering/review | TASK | `task` tool + Python subagent refs |
| semgrep-sast | engineering/review | TASK | `task` tool |
| cfo | finance | TASK | delegates to 3 specialists → `task` (parallel preserved) |
| clo | legal | TASK | delegates to 2 specialists → `task` |
| legal-compliance-auditor | legal | WEB | BYO web tool |
| brand-architect | marketing | ASK | HITL `respond` |
| cmo | marketing | TASK | delegates to 11 specialists → `task` (parallel preserved) |
| copywriter | marketing | WEB | BYO web tool |
| fact-checker | marketing | WEB | BYO web tool |
| growth-strategist | marketing | WEB | BYO web tool |
| coo | operations | TASK | delegates to 3 specialists → `task` |
| ops-provisioner | operations | ASK | HITL `respond` |
| ops-research | operations | WEB | BYO web tool |
| service-deep-links | operations | ASK | HITL `respond` |
| service-automator | operations | ASK, MCP | HITL + MCP client wiring |
| business-validator | product | ASK, WEB | HITL + BYO web tool |
| competitive-intelligence | product | ASK, TASK, WEB | all three primitives adapted |
| cpo | product | TASK | delegates to 4 specialists → `task` |
| ux-design-lead | product/design | ASK, MCP | HITL + MCP (Pencil) client wiring |
| cro | sales | TASK | delegates to 3 specialists → `task` |
| cco | support | TASK | delegates to 2 specialists → `task` |
| community-manager | support | ASK | HITL `respond` |

**Domain-leader pattern preserved at the capability level:** `SubAgentMiddleware`'s `task` tool supports parallel, context-isolated subagents, so cmo/cfo/clo/coo/cpo/cro/cco still fan out to their specialists. But each leader AND specialist must be authored as a Python dict — the markdown hierarchy does not survive as-is.

---

## Skills (82) — 29 GREEN, 53 YELLOW

`SkillsMiddleware` reads `SKILL.md` + YAML frontmatter with 3-level progressive disclosure — the **same format Soleur already uses**. A skill is GREEN when it ports as-is with no degraded primitive. Degraded primitives: **ASK** (no structured prompts), **SKILL-chaining** (model-driven only), **ARGS** ($ARGUMENTS interpolation absent in SDK). **TODO** (`write_todos`) and **MCP** now have equivalents, so skills YELLOW-only-for-TODO/MCP on OpenHands become GREEN here.

### GREEN Skills (29)

| Skill | Signature | Notes |
|---|---|---|
| agent-browser | prose | bash CLI automation |
| andrew-kane-gem-writer | prose | authoring rules |
| archive-kb | prose | bash wrapper |
| brainstorm-techniques | prose | context injection (reference skill) |
| changelog | prose | git log analysis |
| code-to-prd | prose | file walk + redaction |
| deploy-docs | prose | Eleventy build validation |
| dhh-rails-style | prose | style rules |
| docs-site | prose | scaffold generation |
| dspy-ruby | WEB | BYO web tool (config) |
| every-style-editor | prose | copy editing rules |
| frontend-design | prose | design generation |
| gemini-imagegen | prose | API image generation |
| git-worktree | prose | worktree CLI |
| incident | prose | PIR scaffold |
| merge-pr | prose | git merge automation |
| pencil-setup | prose | MCP setup → deepagents MCP client |
| provision-cloudflare | prose | provisioning script |
| provision-doppler | prose | provisioning script |
| provision-github | prose | provisioning script |
| provision-hetzner | prose | provisioning script |
| rclone | prose | cloud storage CLI |
| release-announce | prose | gh CLI release |
| release-docs | prose | docs metadata |
| resolve-debt | prose | debt ledger triage |
| skill-security-scan | prose | advisory scanner |
| spec-templates | prose | template generation |
| trigger-cron | prose | cron trigger |
| user-story-writer | prose | story decomposition |

### YELLOW Skills (53)

| Skill | Signature | Primary degraded primitive(s) |
|---|---|---|
| admin-ip-refresh | ARGS | args via context |
| agent-native-architecture | TASK | `task` tool |
| agent-native-audit | TASK ARGS | `task` + args |
| architecture | ASK ARGS | HITL + args |
| atdd-developer | TASK | `task` tool |
| brainstorm | ASK TASK SKILL ARGS WEB MCP | core orchestrator — highest density |
| campaign-calendar | ARGS | args via context |
| community | ASK TASK ARGS | HITL + `task` + args |
| competitive-analysis | ASK TASK | HITL + `task` |
| compound-capture | ASK ARGS | HITL + args |
| compound | TASK ARGS MCP HOOK | hook → middleware; `task` + args |
| content-writer | ASK TASK ARGS WEB | multi-primitive |
| deepen-plan | ASK TASK ARGS WEB MCP | multi-primitive |
| deploy | ASK | HITL |
| discord-content | ASK | HITL |
| drain-labeled-backlog | TASK SKILL ARGS | `task` + chaining + args |
| feature-video | ARGS | args via context |
| file-todos | TASK ARGS TODO | `task` + args (TODO=GREEN) |
| fix-issue | ARGS | args via context |
| flag-create | ARGS | args via context |
| flag-set-role | ASK ARGS | HITL + args |
| frontend-anti-slop | SKILL ARGS | chaining + args |
| gdpr-gate | TASK ARGS | `task` + args |
| growth | TASK WEB | `task` + BYO web |
| heal-skill | ARGS | args via context |
| kb-search | ARGS | args via context |
| legal-audit | ASK TASK | HITL + `task` |
| legal-generate | ASK TASK | HITL + `task` |
| linear-fetch | ASK ARGS MCP | HITL + args + MCP |
| one-shot | ASK TASK SKILL ARGS | core pipeline orchestrator |
| plan-review | TASK ARGS | `task` + args |
| plan | ASK TASK ARGS WEB MCP | core pipeline orchestrator |
| postmerge | ARGS | args via context |
| preflight | ASK ARGS | HITL + args |
| product-roadmap | ASK TASK ARGS | multi-primitive |
| qa | ARGS | args via context |
| reproduce-bug | ARGS MCP | args + MCP |
| resolve-parallel | TASK ARGS TODO | `task` + args (TODO=GREEN) |
| resolve-pr-parallel | TASK ARGS TODO | `task` + args |
| resolve-todo-parallel | TASK ARGS TODO | `task` + args |
| review | TASK ARGS WEB | core pipeline orchestrator |
| schedule | ASK TASK ARGS WEB | multi-primitive |
| seo-aeo | TASK | `task` tool |
| ship | ASK TASK SKILL ARGS TODO | core pipeline orchestrator |
| skill-creator | TASK | `task` tool |
| social-distribute | ASK ARGS | HITL + args |
| test-browser | ASK ARGS MCP | HITL + args + MCP |
| test-fix-loop | ARGS | args via context |
| triage | ARGS TODO | args (TODO=GREEN) |
| user-set-role | ARGS | args via context |
| ux-audit | TASK SKILL ARGS | `task` + chaining + args |
| work | TASK ARGS MCP TODO | core pipeline orchestrator |
| xcode-test | ASK TASK MCP | HITL + `task` + MCP |

**Shift vs OpenHands:** skills YELLOW *only* for TodoWrite on OpenHands (e.g., bare `triage`/`file-todos` TODO use) gain a built-in `write_todos`. They remain YELLOW here only because they *also* carry ARGS/TASK. No skill is GREEN-er on OpenHands than on deepagents; several are GREEN-er on deepagents.

---

## Commands (3) — 1 GREEN, 2 YELLOW

| Command | Signature | Classification | Notes |
|---|---|---|---|
| help | SKILL | GREEN | skill listing → directory scan / dcode `/help` |
| go | ASK TASK SKILL ARGS | YELLOW | router — HITL + `task` + chaining + args |
| sync | ASK TASK ARGS | YELLOW | HITL + `task` + args |

deepagents has no command/slash system in the SDK; `dcode` provides built-in slash commands (`/model`, `/skill`, `/remember`, `/threads`, etc.) but no user-defined command registry. `go`/`sync` would be re-expressed as skills or dcode-level routing.

---

## Gap Analysis by Primitive (with four-platform comparison)

### P1: Agent authoring format — YELLOW (drives the whole result)
**The defining gap.** Soleur's 67 agents are markdown files; deepagents subagents are Python `SubAgent` dicts. No markdown-agent loader exists. Prose system prompts port verbatim into `system_prompt`, so a bulk script (`for f in agents/**/*.md: SubAgent(name=…, system_prompt=read(f))`) handles the 43 prose-only agents. The 24 primitive-bearing agents need additional adaptation. **No agent is unportable (RED), but none is free (GREEN).** This single fact moves GREEN% from ~46% (OpenHands) to 19.7%.

### P2: AskUserQuestion — YELLOW (no structured multi-choice)
**Usage:** 31 components (8 agents, 21 skills, 2 commands). deepagents `HumanInTheLoopMiddleware` offers approve/edit/reject/**respond**; `respond` returns free text (the AskUserQuestion analogue) but there is no options-list schema. Requires a checkpointer. **Workaround viability: HIGH** (freeform), same constraint as OpenHands.

### P3: Skill format & chaining — YELLOW format-GREEN, chaining-YELLOW
**Usage:** ~15 chaining sites. `SkillsMiddleware` reads identical `SKILL.md` (format GREEN) but activation is model-driven; no programmatic mid-run `Skill()` call. The core pipeline (go→brainstorm→plan→work→review→compound→ship) becomes sequential context loading, same as OpenHands and Gemini CLI.

### P4: $ARGUMENTS — YELLOW
**Usage:** 30+ skills/commands. SDK has no SKILL.md arg interpolation. `dcode` `/skill:<name> [args]` passes args at the CLI but the substitution semantics are unverified (see critical-unknowns). Skills rely on conversation context.

### P5: Task / subagent — GREEN (capability), YELLOW (authoring)
**Usage:** 27 files. `task` tool via `SubAgentMiddleware`: parallel, context-isolated, prebuilt general-purpose template. Multi-level nesting "not prevented" but unverified. Capability matches OpenHands; authoring is Python.

### P6: TodoWrite — GREEN
**Usage:** 7 skills. `write_todos` / `TodoListMiddleware`, built-in and default. **The clearest deepagents win over OpenHands** (which had no equivalent).

### P7: MCP — GREEN (worse ergonomics)
**Usage:** 17 files. `langchain-mcp-adapters` `MultiServerMCPClient` (stdio/HTTP/SSE/WS). Requires explicit Python wiring per server — no `.mcp.json` auto-load. Capability matches; operational overhead is higher.

### P8: WebSearch / WebFetch — YELLOW (BYO, GREEN-with-config)
**Usage:** 14 files. Not built-in (unlike Gemini CLI, and unlike OpenHands' MCP-bundle framing). Wire a search tool (Tavily etc.) via `tools=[…]`. Minimal but explicit.

### P9: hookSpecificOutput / hooks — GREEN (Python), shell-hooks YELLOW
**Usage:** 1 skill (compound) for hookSpecificOutput; plus the infra shell hooks. LangGraph middleware (`wrap_tool_call`) gives full before/after tool interception with state injection — *more* powerful than Claude Code hooks. But Soleur's hooks are **bash** (`guardrails.sh`, `worktree-write-guard.sh`, `pre-merge-rebase.sh`, `welcome-hook.sh`, `stop-hook.sh`); each must be rewritten as a Python middleware subclass. Capability GREEN, implementation YELLOW.

### P10: SessionStart / Stop — GREEN (stronger)
`before_agent`/`after_agent` (run-scoped) plus durable checkpointers (Postgres/Redis) for cross-session recall — stronger than both Claude Code and OpenHands. Welcome hook and Ralph-loop continuation port to middleware + checkpointer.

### P11: Plugin / distribution system — RED at the infra level (no component counted)
**deepagents has no plugin marketplace, manifest, or enable/disable/uninstall system.** The only drop-in distributable unit is a **skills directory** (`SKILL.md` packages). There is no equivalent to Soleur's `.claude-plugin/plugin.json` + `marketplace.json`. This is the one place deepagents is *worse than OpenHands* (which has a full plugin system) — and it shapes the recommendation: there is no clean way to ship Soleur's 152 components as one installable harness extension. Agents/middleware ship as a **Python package**, skills as a directory.

---

## CI / Infrastructure (Not Counted in 152)

| Component | Type | deepagents Equivalent | Status |
|---|---|---|---|
| hooks/welcome-hook.sh | SessionStart hook | `before_agent` middleware (Python rewrite) | YELLOW |
| hooks/stop-hook.sh | Stop hook | `after_agent` middleware (Python rewrite) | YELLOW |
| .claude/hooks/guardrails.sh | PreToolUse hook | `wrap_tool_call` middleware (Python rewrite) | YELLOW |
| .claude/hooks/pre-merge-rebase.sh | PreToolUse hook | `wrap_tool_call` middleware | YELLOW |
| .claude/hooks/worktree-write-guard.sh | PreToolUse hook | `wrap_tool_call` middleware | YELLOW |
| .claude-plugin/plugin.json | Plugin manifest | No equivalent → Python package metadata | RED |
| .claude-plugin/marketplace.json | Distribution manifest | No equivalent | RED |
| .mcp.json | MCP auto-load | `MultiServerMCPClient` Python wiring | YELLOW |
| .claude/settings.json | Project settings | `create_deep_agent(...)` kwargs / dcode config | YELLOW |
| GitHub Actions workflows | CI/CD | platform-agnostic | GREEN |

**Infrastructure is mostly YELLOW/RED** — the inverse of OpenHands, whose hook system covered all 6 Claude Code hook types as GREEN. deepagents' middleware is more powerful but requires Python rewrites of every bash hook, and there is no distribution manifest.

---

## Platform-Specific Considerations

### Two surfaces: SDK vs dcode
- **SDK** (`from deepagents import create_deep_agent`): the programmatic path; you build the operator UX yourself (custom CLI, web app, or LangGraph Studio).
- **dcode** (`deepagents-code`): the batteries-included terminal harness. Young — packaging churn (the REPL was split out of `deepagents-cli` into `deepagents-code`, CLI at v0.1.0). Maturity for running Soleur's long multi-step pipelines is **unverified** (see critical-unknowns).

### Model-agnostic
Any LangChain chat model (`"provider:model"` strings: `anthropic:…`, `openai:…`, `google:…`, Ollama, vLLM). This is the headline strategic advantage over Claude Code and the main investment trigger.

### Durable persistence
LangGraph checkpointers (MemorySaver dev; Postgres/Redis prod) checkpoint state every superstep, keyed by `thread_id`. deepagents adds `StateBackend`/`FilesystemBackend`/`CompositeBackend` + `MemoryMiddleware` for cross-session recall. Stronger than Claude Code's session model — a strong fit for a server-side runtime.

### Python requirement
Subagents, tools, and hooks are Python. Bash tooling (worktree-manager, deploy scripts) runs via a shell/`execute` tool. The 67 agents and 5 bash hooks are the Python-rewrite surface; the 29 GREEN skills and bash scripts are not.

### Maturity
~24.2k★, `deepagents 0.6.8` (2026-06-03), MIT, Python ≥3.11, maintained by LangChain Inc., frequent releases, JS port available. LangSmith observability, remote sandbox backends (AWS AgentCore, Daytona, Modal, Runloop).
