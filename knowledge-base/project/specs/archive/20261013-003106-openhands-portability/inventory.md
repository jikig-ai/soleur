---
title: "OpenHands Portability Inventory"
date: 2026-04-07
issue: 1770
openhands_sdk_version: "0.x (docs.openhands.dev, accessed 2026-04-07)"
methodology: "Grep-based scan for Claude Code-specific primitives, classified against OpenHands SDK equivalents"
---

# OpenHands Portability Inventory

## Summary Statistics

| Classification | Count | Percentage | Description |
|---|---|---|---|
| GREEN | 60 | 46.5% | Ports to OpenHands as-is (tool names differ but semantics match) |
| YELLOW | 69 | 53.5% | Needs adaptation -- uses primitives with different semantics on OpenHands |
| RED | 0 | 0% | -- |
| N/A | 0 | 0% | -- |
| **Total** | **129** | **100%** | |

**By component type:**

| Type | Green | Yellow | Red | N/A | Total |
|---|---|---|---|---|---|
| Agents | 44 (69.8%) | 19 (30.2%) | 0 | 0 | 63 |
| Skills | 15 (23.8%) | 48 (76.2%) | 0 | 0 | 63 |
| Commands | 1 (33.3%) | 2 (66.7%) | 0 | 0 | 3 |

**Three-way comparison:**

| Classification | Codex CLI (2026-03-10) | Gemini CLI (2026-04-07) | OpenHands (2026-04-07) |
|---|---|---|---|
| GREEN | 47.5% (58/122) | 54.3% (70/129) | 46.5% (60/129) |
| YELLOW | 7.4% (9/122) | 45.0% (58/129) | 53.5% (69/129) |
| RED | 43.4% (53/122) | 0.8% (1/129) | 0% (0/129) |
| Blockers with no equivalent | 4 | 1 (hookSpecificOutput) | 0 |
| MCP compatibility | Partial (stdio only) | Full (stdio + HTTP) | Full (stdio + HTTP) |
| Subagent support | None | Single-level only | Multi-level + parallel |
| Skill chaining | None | Context injection (unlimited) | Context injection |
| Hook system | SessionStart only (request) | Post-hoc only (notify) | Full lifecycle (PreToolUse, PostToolUse, Stop, SessionStart, SessionEnd) |
| Plugin system | None | None | Full (plugin.json, skills/, agents/, hooks/, commands/) |

**Key insight:** OpenHands is the first target platform with ZERO red components. Every Soleur primitive has at least a partial equivalent. However, the GREEN percentage is lower than Gemini CLI (46.5% vs 54.3%) because OpenHands lacks built-in `ask_user` and `write_todos` tools that Gemini CLI provides — agents relying on AskUserQuestion shift from GREEN (on Gemini) to YELLOW (on OpenHands).

**OpenHands' unique advantage:** Multi-level parallel subagent support. Gemini CLI's critical constraint (single-level agents, sequential execution) does not exist on OpenHands. Domain leaders can spawn specialist agents that themselves spawn sub-agents — Soleur's full hierarchical delegation pattern is architecturally preserved.

## Primitive Mapping

| Claude Code Primitive | OpenHands Equivalent | Classification | Delta vs Gemini CLI |
|---|---|---|---|
| AskUserQuestion | No structured equivalent; agent outputs freeform questions | YELLOW | Worse (Gemini has `ask_user`) |
| TodoWrite / TaskCreate | No equivalent; file-based workaround | YELLOW | Worse (Gemini has `write_todos`) |
| WebSearch | MCP via `mcp-server-fetch` or custom tool | GREEN (bundled in plugin) | Same |
| WebFetch | MCP via `mcp-server-fetch` | GREEN (bundled in plugin) | Same |
| MCP tools (mcp__*) | `mcp_config` with `mcpServers` (stdio + HTTP) | GREEN | Same |
| Task / Agent tool (subagent) | DelegateTool (multi-level, parallel) | GREEN | Better (multi-level + parallel vs single-level sequential) |
| Skill tool (chaining) | No programmatic invocation; skills are context injection | YELLOW | Same |
| $ARGUMENTS | TaskTrigger `inputs` (partial, skills only) | YELLOW | Same |
| hookSpecificOutput | JSON output with `decision`/`reason`/`additionalContext` | GREEN | Better (Gemini has no equiv) |
| SessionStart / Stop hooks | SessionStart, SessionEnd, Stop hooks | GREEN | Better (Gemini has no equiv) |

---

## GREEN Agents (44)

These agents port to OpenHands `.agents/agents/*.md` format with only minor frontmatter adjustments (`model: inherit` → `model: "inherit"`, add `tools` field).

| Agent | Domain | Notes |
|---|---|---|
| cto | engineering | Pure prose assessment — no tool references in body |
| ddd-architect | engineering/design | |
| infra-security | engineering/infra | MCP references → bundled in plugin mcp_config |
| terraform-architect | engineering/infra | |
| framework-docs-researcher | engineering/research | |
| git-history-analyzer | engineering/research | |
| repo-research-analyst | engineering/research | |
| agent-native-reviewer | engineering/review | |
| architecture-strategist | engineering/review | |
| code-quality-analyst | engineering/review | |
| code-simplicity-reviewer | engineering/review | |
| data-integrity-guardian | engineering/review | |
| data-migration-expert | engineering/review | |
| deployment-verification-agent | engineering/review | |
| dhh-rails-reviewer | engineering/review | |
| kieran-rails-reviewer | engineering/review | |
| legacy-code-expert | engineering/review | |
| pattern-recognition-specialist | engineering/review | |
| performance-oracle | engineering/review | |
| security-sentinel | engineering/review | |
| semgrep-sast | engineering/review | |
| test-design-reviewer | engineering/review | |
| pr-comment-resolver | engineering/workflow | |
| budget-analyst | finance | |
| financial-reporter | finance | |
| revenue-analyst | finance | |
| legal-document-generator | legal | |
| analytics-analyst | marketing | |
| conversion-optimizer | marketing | |
| copywriter | marketing | |
| fact-checker | marketing | WebSearch → MCP (bundled in plugin) |
| growth-strategist | marketing | WebSearch → MCP (bundled in plugin) |
| paid-media-strategist | marketing | |
| pricing-strategist | marketing | |
| programmatic-seo-specialist | marketing | |
| retention-strategist | marketing | |
| seo-aeo-analyst | marketing | |
| ops-advisor | operations | |
| ops-research | operations | WebSearch + MCP → bundled in plugin |
| spec-flow-analyzer | product | |
| deal-architect | sales | |
| outbound-strategist | sales | |
| pipeline-analyst | sales | |
| ticket-triage | support | |

## YELLOW Agents (19)

| Agent | Domain | Primitives | Adaptation | Gemini CLI Status |
|---|---|---|---|---|
| agent-finder | engineering/discovery | ASK | AskUserQuestion → freeform prompts (loses structured options) | Was GREEN |
| functional-discovery | engineering/discovery | ASK | AskUserQuestion → freeform prompts | Was GREEN |
| platform-strategist | engineering/infra | TASK | Task tool reference → DelegateTool (tool name change) | Was YELLOW |
| best-practices-researcher | engineering/research | SKILL | Skill tool reference → context-based invocation | Was YELLOW |
| learnings-researcher | engineering/research | TASK | Task tool reference → DelegateTool | Was YELLOW |
| cfo | finance | TASK | Delegates to 3 specialists → DelegateTool (parallel preserved) | Was YELLOW |
| clo | legal | TASK | Delegates to 2 specialists → DelegateTool | Was YELLOW |
| legal-compliance-auditor | legal | TASK, WEB | Task + web references → DelegateTool + MCP | Was YELLOW |
| brand-architect | marketing | ASK | AskUserQuestion → freeform prompts | Was GREEN |
| cmo | marketing | TASK | Delegates to 7+ specialists → DelegateTool (parallel preserved!) | Was YELLOW |
| coo | operations | TASK | Delegates to 3 specialists → DelegateTool | Was YELLOW |
| ops-provisioner | operations | ASK, MCP | AskUserQuestion → freeform + MCP bundled | Was GREEN |
| business-validator | product | ASK, WEB | AskUserQuestion → freeform + web via MCP | Was GREEN |
| competitive-intelligence | product | TASK, ASK, WEB | Multiple primitives, all have partial equivalents | Was YELLOW |
| cpo | product | TASK | Delegates to 4 specialists → DelegateTool | Was YELLOW |
| ux-design-lead | product/design | ASK, MCP | AskUserQuestion → freeform + MCP bundled | Was GREEN |
| community-manager | support | ASK | AskUserQuestion → freeform prompts | Was GREEN |
| cro | sales | TASK | Delegates to 3 specialists → DelegateTool | Was YELLOW |
| cco | support | TASK | Delegates to 2 specialists → DelegateTool | Was YELLOW |

**Pattern change from Gemini CLI:** 7 agents that were GREEN on Gemini CLI (agent-finder, functional-discovery, brand-architect, ops-provisioner, business-validator, ux-design-lead, community-manager) shift to YELLOW on OpenHands because OpenHands lacks `ask_user`. Conversely, domain leaders that were YELLOW on Gemini CLI (losing parallelism) remain YELLOW on OpenHands but with better parity (DelegateTool preserves parallelism).

**Net: Domain leaders are BETTER on OpenHands than Gemini CLI (parallel subagents preserved), but interactive agents are WORSE (no structured prompts).**

---

## GREEN Skills (15)

| Skill | Notes |
|---|---|
| agent-browser | Pure bash CLI automation |
| archive-kb | Bash script wrapper |
| changelog | Git log analysis |
| deploy-docs | Eleventy build validation |
| docs-site | Scaffold generation |
| every-style-editor | Copy editing rules |
| frontend-design | Design generation |
| gemini-imagegen | API-based image generation |
| pencil-setup | MCP tool setup → adapt to OpenHands MCP config |
| plan-review | Agent spawning via skill description only |
| rclone | Cloud storage CLI |
| release-announce | GitHub Release via gh CLI |
| release-docs | Documentation metadata |
| user-story-writer | Story decomposition |
| kb-search | File search utility |

## YELLOW Skills (48)

| Skill | Primitives | Primary Adaptation | Gemini CLI Status |
|---|---|---|---|
| agent-native-architecture | TASK, ARGS, WEB | DelegateTool + conversation context for args | Was YELLOW |
| agent-native-audit | TASK, ARGS | DelegateTool + conversation context | Was YELLOW |
| andrew-kane-gem-writer | TASK | DelegateTool (was Gemini YELLOW, same) | Was YELLOW |
| architecture | ASK, ARGS | Freeform prompts + conversation context | Was YELLOW |
| atdd-developer | TASK | DelegateTool | Was YELLOW |
| brainstorm | TASK, SKILL, ASK, ARGS, WEB | Core orchestrator — all have partial equivalents | Was YELLOW |
| brainstorm-techniques | SKILL | Context injection (same as Gemini) | Was YELLOW |
| campaign-calendar | ARGS | Conversation context for args | Was YELLOW |
| community | ASK, ARGS | Freeform prompts + conversation context | Was YELLOW |
| competitive-analysis | TASK, ASK, ARGS | DelegateTool + freeform + context | Was YELLOW |
| compound | SKILL, ARGS, HOOK, MCP | hookSpecificOutput → JSON output (GREEN on OH!) | Was RED |
| compound-capture | SKILL, ASK, ARGS | Context injection + freeform + context | Was YELLOW |
| content-writer | TASK, ASK, ARGS, WEB | DelegateTool + freeform + context | Was YELLOW |
| deepen-plan | TASK, SKILL, ASK, ARGS, WEB, MCP | Highest primitive density — all partial | Was YELLOW |
| deploy | ASK | Freeform prompts | Was GREEN |
| dhh-rails-style | ARGS | Conversation context for args | Was YELLOW |
| discord-content | ASK | Freeform prompts | Was GREEN |
| dspy-ruby | WEB | MCP for web search | Was GREEN |
| feature-video | ARGS | Conversation context for args | Was YELLOW |
| file-todos | TASK, TODO | DelegateTool + file-based tracking | Was YELLOW |
| fix-issue | ARGS | Conversation context for args | Was YELLOW |
| git-worktree | ARGS | Conversation context for args | Was YELLOW |
| growth | TASK, WEB | DelegateTool + MCP | Was YELLOW |
| heal-skill | ARGS | Conversation context for args | Was YELLOW |
| legal-audit | TASK, ASK, ARGS | DelegateTool + freeform + context | Was YELLOW |
| legal-generate | TASK, ASK | DelegateTool + freeform | Was YELLOW |
| merge-pr | SKILL | Context injection | Was YELLOW |
| one-shot | TASK, SKILL, ARGS | Core pipeline orchestrator | Was YELLOW |
| plan | TASK, SKILL, ASK, ARGS | Core pipeline orchestrator | Was YELLOW |
| postmerge | SKILL, ARGS | Context injection + conversation context | Was YELLOW |
| preflight | ASK, ARGS | Freeform + conversation context | Was YELLOW |
| product-roadmap | TASK, SKILL, ASK, ARGS | Multi-primitive orchestrator | Was YELLOW |
| qa | SKILL, ARGS | Context injection + conversation context | Was YELLOW |
| reproduce-bug | ARGS, MCP | Conversation context + MCP | Was YELLOW |
| resolve-parallel | TASK, TODO | DelegateTool + file-based tracking | Was YELLOW |
| resolve-pr-parallel | TASK, TODO | DelegateTool + file-based tracking | Was YELLOW |
| resolve-todo-parallel | TASK, TODO | DelegateTool + file-based tracking | Was YELLOW |
| review | TASK, SKILL, ARGS | Core pipeline orchestrator | Was YELLOW |
| schedule | SKILL, ASK, ARGS, WEB | Multi-primitive | Was YELLOW |
| seo-aeo | TASK | DelegateTool | Was YELLOW |
| ship | SKILL, ASK, ARGS, TODO | Core pipeline orchestrator | Was YELLOW |
| skill-creator | TASK, SKILL, ASK, ARGS, WEB, MCP | Highest primitive density | Was YELLOW |
| social-distribute | ASK, ARGS | Freeform + conversation context | Was YELLOW |
| spec-templates | TASK | DelegateTool | Was YELLOW |
| test-browser | ASK, ARGS, MCP | Freeform + context + MCP | Was YELLOW |
| test-fix-loop | ARGS | Conversation context for args | Was YELLOW |
| triage | TODO | File-based tracking (was GREEN on Gemini) | Was GREEN |
| work | TASK, SKILL, ARGS, TODO, WEB | Core pipeline orchestrator | Was YELLOW |
| xcode-test | TASK, ASK, MCP | DelegateTool + freeform + MCP | Was YELLOW |

**Notable shifts:**

- **compound** shifts from RED (Gemini) to YELLOW (OpenHands) — hookSpecificOutput now has an equivalent
- **deploy, discord-content, dspy-ruby** shift from GREEN (Gemini) to YELLOW (OpenHands) — lost `ask_user`/`google_web_search` built-ins
- **triage** shifts from GREEN (Gemini) to YELLOW (OpenHands) — lost `write_todos`

---

## GREEN Commands (1)

| Command | Notes |
|---|---|
| help | Skill listing → can be done via directory scan in OpenHands plugin |

## YELLOW Commands (2)

| Command | Primitives | Adaptation |
|---|---|---|
| go | ASK, SKILL, ARGS | Route to skills via context injection, freeform prompts |
| sync | ASK, ARGS | Freeform prompts + conversation context |

---

## Gap Analysis by Primitive (with Codex + Gemini comparison)

### P1: AskUserQuestion — YELLOW (no OpenHands equivalent)

**Usage:** 33 files, ~60+ references
**Affected components:** 8 agents, 21 skills, 2 commands (31 total)
**OpenHands equivalent:** None. The agent can output freeform text and the user responds in the conversation. No structured multi-choice prompts, no guaranteed response format.
**Gemini CLI comparison:** Gemini CLI has `ask_user` (direct equivalent) — this is OpenHands' biggest disadvantage.
**Impact:** Skills like brainstorm, plan, and ship use AskUserQuestion for routing decisions and approval gates. On OpenHands, these become freeform conversations. The model must parse natural language responses instead of structured choices.
**Workaround viability:** HIGH. Freeform questions work for most cases. The main loss is UX quality (no dropdown menus, no guaranteed option format), not functionality.

### P2: Skill Tool / Inter-Skill Chaining — YELLOW (context injection)

**Usage:** 15 files, ~40+ references
**Affected components:** 0 agents, 13 skills, 2 commands (15 total)
**OpenHands equivalent:** Skills are context injections triggered by keywords. No programmatic mid-execution invocation.
**Gemini CLI comparison:** Same limitation (`activate_skill` is context injection, no args). Near-identical semantics.
**Impact:** The core pipeline (go → brainstorm → plan → work → review → compound → ship) depends on skill chaining. On both Gemini CLI and OpenHands, this becomes sequential context loading.

### P3: Task / Subagent Spawning — GREEN (DelegateTool + TaskToolSet)

**Usage:** 27 files, ~100+ references
**Affected components:** 8 domain leader agents, 13 skills (21 unique)
**OpenHands equivalent:** DelegateTool provides `spawn` + `delegate` commands. TaskToolSet provides sequential delegation with persistence. File-based agents are auto-registered for delegation via `register_file_agents()`.
**Gemini CLI comparison:** MUCH BETTER. Gemini CLI limits to single-level subagents (no sub-subagents) and sequential execution. OpenHands DelegateTool supports multi-level nesting and parallel threads.
**Impact:** Domain leaders can spawn specialist agents in parallel — Soleur's core hierarchical delegation pattern is fully preserved. The CMO with 7+ specialists works as designed.
**Codex/Gemini shift:** Was the #1 blocker on Codex (no equivalent). Was a significant degradation on Gemini CLI (single-level sequential). Fully resolved on OpenHands.

### P4: $ARGUMENTS — YELLOW (no skill argument interpolation)

**Usage:** 30 files, ~50+ references
**Affected components:** 28 skills, 2 commands (30 total)
**OpenHands equivalent:** TaskTrigger skills have `inputs` field for structured inputs (not runtime interpolation). Commands have no documented equivalent.
**Gemini CLI comparison:** Same limitation. Gemini commands support `{{args}}` but skills don't.
**Impact:** Skills must rely on conversation context instead of explicit argument passing. The `ask_user` fallback pattern used on Gemini CLI is less reliable on OpenHands (no structured prompt tool).

### P5: TodoWrite — YELLOW (no equivalent)

**Usage:** 7 files, ~14 references
**Affected components:** 7 skills
**OpenHands equivalent:** None documented. TaskToolSet is for agent delegation, not personal task tracking.
**Gemini CLI comparison:** WORSE. Gemini CLI has `write_todos` (direct equivalent).
**Workaround:** File-based checklists (write markdown to a file). Same workaround as Codex analysis.

### P6: hookSpecificOutput — GREEN (JSON output with additionalContext)

**Usage:** 1 file, 1 reference
**Affected components:** 1 skill (compound)
**OpenHands equivalent:** Hook JSON output with `decision`, `reason`, and `additionalContext` fields. The `additionalContext` is injected into the agent prompt, similar to `hookSpecificOutput`.
**Gemini CLI comparison:** BETTER. This was Gemini CLI's ONLY red component. Now resolved on OpenHands.
**Impact:** The compound skill's branch safety check via hooks can be implemented using OpenHands' hook JSON protocol.

### P7: MCP Tool References — GREEN (full MCP support)

**Usage:** 19 files
**Affected components:** 3 agents, 14 skills (17 unique)
**OpenHands equivalent:** Full MCP support via `mcp_config` on Agent class. Supports stdio and HTTP transports. Plugin can bundle MCP server configs.
**Gemini CLI comparison:** Same — both have full MCP support.
**Impact:** Tool name prefixes change (`mcp__plugin_*` → OpenHands MCP naming) but semantics match.

### P8: WebSearch / WebFetch — GREEN (via MCP)

**Usage:** 16 files
**Affected components:** 6 agents, 8 skills (14 unique)
**OpenHands equivalent:** Not built-in, but MCP servers like `mcp-server-fetch` and `mcp-server-web-search` provide equivalent functionality. Plugin bundles these configs.
**Gemini CLI comparison:** Gemini CLI has built-in `google_web_search` and `web_fetch`. OpenHands requires MCP config but achieves same result.
**Impact:** Minimal — MCP config is bundled in the plugin manifest.

### P9: CLAUDE_PLUGIN_ROOT — N/A

**Usage:** 1 file (git-worktree skill)
**OpenHands equivalent:** Plugin paths use different resolution. `.openhands/plugins/` directory structure.
**Impact:** Trivial — path reference change.

### P10: SessionStart / Stop Hooks — GREEN (full lifecycle hooks)

**Usage:** 1 file (git-worktree skill)
**OpenHands equivalent:** SessionStart and SessionEnd hooks with full blocking capability. Stop hook with exit code 2 blocking.
**Gemini CLI comparison:** BETTER. Gemini CLI has no SessionStart equivalent. OpenHands has the full lifecycle.
**Impact:** Welcome hook, Ralph loop continuation, and session initialization can port directly.

---

## Inter-Component Dependencies

### Core Workflow Pipeline (all YELLOW — same as Gemini CLI)

```text
go ──→ brainstorm ──→ plan ──→ work ──→ review ──→ compound ──→ ship
  ├──→ one-shot (chains all above + deepen-plan, test-browser, feature-video)
  ├──→ review (standalone)
  └──→ work (standalone)
```

Every node is YELLOW (was RED on Codex, YELLOW on Gemini CLI). The pipeline works via sequential context injection on both Gemini CLI and OpenHands. The shared constraint is no skill argument passing.

### Domain Leader → Specialist Pattern (IMPROVED vs Gemini CLI)

| Leader (YELLOW) | Specialists (mostly GREEN) | Gemini CLI | OpenHands |
|---|---|---|---|
| cmo | 11 marketing agents | Sequential skills (degraded) | **Parallel DelegateTool (preserved!)** |
| cfo | 3 finance agents | Sequential skills | Parallel DelegateTool |
| clo | 2 legal agents | Sequential skills | Parallel DelegateTool |
| coo | 3 operations agents | Sequential skills | Parallel DelegateTool |
| cpo | 4 product agents | Sequential skills | Parallel DelegateTool |
| cro | 3 sales agents | Sequential skills | Parallel DelegateTool |
| cco | 2 support agents | Sequential skills | Parallel DelegateTool |
| cto | N/A (prose only, GREEN) | N/A | N/A |

**Critical improvement:** On Gemini CLI, specialists had to be restructured from agents to skills (losing parallelism, context isolation, and independent tool scoping). On OpenHands, specialists STAY as agents and are spawned via DelegateTool in parallel — the original architecture is preserved.

---

## CI/Infrastructure (Not Counted in 129)

| Component | Type | OpenHands Equivalent | Status |
|---|---|---|---|
| hooks/hooks.json | Plugin hook manifest | `.plugin/hooks/hooks.json` (same format concept) | GREEN |
| hooks/welcome-hook.sh | SessionStart hook | SessionStart hook in `.openhands/hooks.json` | GREEN |
| hooks/stop-hook.sh | Stop hook | Stop hook with exit code 2 blocking | GREEN |
| .claude/hooks/guardrails.sh | PreToolUse hook | PreToolUse hook with exit code 2 blocking + JSON output | GREEN |
| .claude/hooks/pre-merge-rebase.sh | PreToolUse hook | PreToolUse hook | GREEN |
| .claude/hooks/worktree-write-guard.sh | PreToolUse hook | PreToolUse hook | GREEN |
| .claude-plugin/plugin.json | Plugin manifest | `.plugin/plugin.json` (same concept, different schema) | YELLOW |
| .claude-plugin/marketplace.json | Distribution manifest | No marketplace equivalent | N/A |
| .claude/settings.json | Project settings | `.openhands/` config directory | YELLOW |
| GitHub Actions workflows | CI/CD | Platform-agnostic | GREEN |

**Infrastructure is largely GREEN** — OpenHands' hook system covers all 6 hook types Claude Code uses. This is a dramatic improvement over both Codex (no hooks) and Gemini CLI (post-hoc only).

---

## Platform-Specific Considerations

### Agent Directory Structure

OpenHands discovers agents from these directories (priority order):

1. `{project}/.agents/agents/*.md` (project-level, primary)
2. `{project}/.openhands/agents/*.md` (project-level, secondary)

Like Gemini CLI, **only top-level `.md` files load** — no subdirectory recursion. Soleur's `agents/marketing/cmo.md`, `agents/engineering/design/ddd-architect.md` etc. must be flattened. This is cosmetic (name prefixes) not functional.

### Plugin Distribution

OpenHands has a plugin system with `install_plugin()`, `enable_plugin()`, `disable_plugin()`, `uninstall_plugin()`. Plugins install from local paths, GitHub repos, or Git URLs. This maps well to Soleur's distribution model.

### Docker Sandbox

OpenHands runs agents in Docker sandboxes by default. Soleur's `execute_bash` operations would run inside the sandbox. This is more isolated than Claude Code's direct shell access but may affect operations that need host-level access (e.g., SSH deployments, Terraform).

### Python SDK Requirement

OpenHands custom agents and tools can be defined in Python (the SDK is Python-based). File-based agents use markdown (same as Soleur), but custom tool creation requires Python. Soleur's bash-based tooling (worktree-manager, deploy scripts) would run via `execute_bash` — no Python needed for those.
