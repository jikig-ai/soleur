---
title: "Gemini CLI Portability Inventory"
date: 2026-04-07
issue: 1738
gemini_cli_version: 0.36.0
methodology: "Grep-based scan for Claude Code-specific primitives, classified against Gemini CLI equivalents"
---

# Gemini CLI Portability Inventory

## Summary Statistics

| Classification | Count | Percentage | Description |
|---|---|---|---|
| GREEN | 70 | 54.3% | Ports to Gemini CLI as-is (tool names differ but semantics match) |
| YELLOW | 58 | 45.0% | Needs adaptation -- uses primitives with different semantics on Gemini CLI |
| RED | 1 | 0.8% | Requires rewrite -- uses hookSpecificOutput with no Gemini CLI equivalent |
| N/A | 0 | 0% | -- |
| **Total** | **129** | **100%** | |

**By component type:**

| Type | Green | Yellow | Red | N/A | Total |
|---|---|---|---|---|---|
| Agents | 51 (81.0%) | 12 (19.0%) | 0 | 0 | 63 |
| Skills | 18 (28.6%) | 44 (69.8%) | 1 (1.6%) | 0 | 63 |
| Commands | 1 (33.3%) | 2 (66.7%) | 0 | 0 | 3 |

**Comparison with Codex CLI scan (2026-03-10, 122 components):**

| Classification | Codex CLI | Gemini CLI | Change |
|---|---|---|---|
| GREEN | 47.5% (58) | 54.3% (70) | +6.8pp |
| YELLOW | 7.4% (9) | 45.0% (58) | +37.6pp |
| RED | 43.4% (53) | 0.8% (1) | -42.6pp |

**Key shift:** RED dropped from 43.4% to 0.8%. The 4 Codex blockers (Task/subagent, Skill chaining, AskUserQuestion, $ARGUMENTS) all have Gemini CLI equivalents, moving 52 components from RED to YELLOW.

## Primitive Mapping

| Claude Code Primitive | Gemini CLI Equivalent | Impact |
|---|---|---|
| AskUserQuestion | `ask_user` | GREEN -- direct equivalent |
| TodoWrite / TaskCreate | `write_todos` | GREEN -- direct equivalent |
| WebSearch | `google_web_search` | GREEN -- direct equivalent |
| WebFetch | `web_fetch` | GREEN -- direct equivalent |
| MCP tools (mcp__*) | `mcpServers` (stdio + HTTP) | GREEN -- native support |
| Task / Agent tool (subagent) | `.gemini/agents/*.md` | YELLOW -- single-level only, no sub-subagents |
| Skill tool (chaining) | `activate_skill` | YELLOW -- context injection, no args, no isolation |
| $ARGUMENTS | Not supported in skills | YELLOW -- workaround via conversation context |
| hookSpecificOutput | No equivalent | RED -- different hook protocol |

---

## GREEN Agents (51)

These agents port to Gemini CLI's `.gemini/agents/*.md` format with only tool name changes.

| Agent | Domain | Notes |
|---|---|---|
| cto | engineering | Pure prose assessment |
| ddd-architect | engineering/design | |
| infra-security | engineering/infra | |
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
| paid-media-strategist | marketing | |
| pricing-strategist | marketing | |
| programmatic-seo-specialist | marketing | |
| retention-strategist | marketing | |
| seo-aeo-analyst | marketing | |
| ops-advisor | operations | |
| spec-flow-analyzer | product | |
| deal-architect | sales | |
| outbound-strategist | sales | |
| pipeline-analyst | sales | |
| ticket-triage | support | |
| agent-finder | engineering/discovery | Uses AskUserQuestion -> ask_user |
| functional-discovery | engineering/discovery | Uses AskUserQuestion -> ask_user |
| brand-architect | marketing | Uses AskUserQuestion -> ask_user |
| ops-provisioner | operations | Uses AskUserQuestion -> ask_user |
| business-validator | product | Uses AskUserQuestion + WebSearch -> ask_user + google_web_search |
| community-manager | support | Uses AskUserQuestion -> ask_user |
| fact-checker | marketing | Uses WebSearch -> google_web_search |
| growth-strategist | marketing | Uses WebSearch -> google_web_search |
| ops-research | operations | Uses WebSearch -> google_web_search |
| ux-design-lead | product/design | Uses AskUserQuestion + MCP -> ask_user + mcpServers |

## YELLOW Agents (12)

These agents use Task/subagent spawning or Skill chaining. On Gemini CLI, the leader-specialist pattern restructures: leaders remain as agents, specialists become skills activated within the leader's subagent context.

| Agent | Domain | Primitives | Adaptation |
|---|---|---|---|
| platform-strategist | engineering/infra | TASK | Specialist invocation → skill activation |
| best-practices-researcher | engineering/research | SKILL | Skill invocation → activate_skill (no args) |
| learnings-researcher | engineering/research | TASK | Invoked as subagent, works as `.gemini/agents/` |
| cfo | finance | TASK | Delegates to 3 specialists → skill activation |
| clo | legal | TASK | Delegates to 2 specialists → skill activation |
| legal-compliance-auditor | legal | TASK, WEB | Specialist delegation + web (web is GREEN) |
| cmo | marketing | TASK | Delegates to 7+ specialists → skill activation (sequential, no parallelism) |
| coo | operations | TASK | Delegates to 3 specialists → skill activation |
| competitive-intelligence | product | TASK, ASK, WEB | Multiple primitives, TASK is the blocker |
| cpo | product | TASK | Delegates to 4 specialists → skill activation |
| cro | sales | TASK | Delegates to 3 specialists → skill activation |
| cco | support | TASK | Delegates to 2 specialists → skill activation |

**Pattern:** All 8 domain leaders are YELLOW (were RED on Codex). The subagent → skill activation workaround is viable but loses parallelism.

---

## GREEN Skills (18)

| Skill | Notes |
|---|---|
| agent-browser | Pure bash CLI automation |
| archive-kb | Bash script wrapper |
| changelog | Git log analysis |
| deploy-docs | Eleventy build validation |
| docs-site | Scaffold generation |
| every-style-editor | Copy editing rules |
| frontend-design | Design generation |
| gemini-imagegen | API-based (ironically, already Gemini) |
| pencil-setup | MCP tool setup |
| plan-review | Agent spawning via skill description only |
| rclone | Cloud storage CLI |
| release-announce | GitHub Release via gh CLI |
| release-docs | Documentation metadata |
| user-story-writer | Story decomposition |
| deploy | Uses AskUserQuestion -> ask_user |
| discord-content | Uses AskUserQuestion -> ask_user |
| dspy-ruby | Uses WebSearch -> google_web_search |
| triage | Uses TodoWrite -> write_todos |

## YELLOW Skills (44)

These skills use $ARGUMENTS (no skill arg interpolation), Skill tool (activate_skill works but no args), or Task tool (subagent works but single-level).

| Skill | Primitives | Primary Adaptation |
|---|---|---|
| agent-native-architecture | TASK, ARGS, WEB | Subagent + arg passing |
| agent-native-audit | TASK, ARGS | Subagent + arg passing |
| andrew-kane-gem-writer | TASK | Subagent spawn |
| architecture | ASK, ARGS | Arg passing (ask_user workaround) |
| atdd-developer | TASK | Subagent spawn |
| brainstorm | TASK, SKILL, ASK, ARGS, WEB | Core orchestrator -- all primitives have equivalents |
| brainstorm-techniques | SKILL | activate_skill (no args) |
| campaign-calendar | ARGS | Arg passing |
| community | ASK, ARGS | Arg passing |
| competitive-analysis | TASK, ASK, ARGS | Subagent + arg passing |
| compound-capture | SKILL, ASK, ARGS | Skill chaining + arg passing |
| content-writer | TASK, ASK, ARGS, WEB | Subagent + arg passing |
| deepen-plan | TASK, SKILL, ASK, ARGS, WEB, MCP | Highest primitive density -- all have equivalents |
| dhh-rails-style | ARGS | Arg passing only |
| feature-video | ARGS | Arg passing only |
| file-todos | TASK, TODO | Subagent + todo (todo is GREEN) |
| fix-issue | ARGS | Arg passing only |
| git-worktree | ARGS | Arg passing only |
| growth | TASK, WEB | Subagent (web is GREEN) |
| heal-skill | ARGS | Arg passing only |
| legal-audit | TASK, ASK, ARGS | Subagent + arg passing |
| legal-generate | TASK, ASK | Subagent (ask is GREEN) |
| merge-pr | SKILL | activate_skill |
| one-shot | TASK, SKILL, ARGS | Core pipeline orchestrator |
| plan | TASK, SKILL, ASK, ARGS | Core pipeline orchestrator |
| postmerge | SKILL, ARGS | Skill chaining + arg passing |
| preflight | ASK, ARGS | Arg passing (ask is GREEN) |
| product-roadmap | TASK, SKILL, ASK, ARGS | Multi-primitive orchestrator |
| qa | SKILL, ARGS | Skill chaining + arg passing |
| reproduce-bug | ARGS, MCP | Arg passing (MCP is GREEN) |
| resolve-parallel | TASK, TODO | Subagent fan-out (todo is GREEN) |
| resolve-pr-parallel | TASK, TODO | Subagent fan-out |
| resolve-todo-parallel | TASK, TODO | Subagent fan-out |
| review | TASK, SKILL, ARGS | Core pipeline orchestrator |
| schedule | SKILL, ASK, ARGS, WEB | Multi-primitive |
| seo-aeo | TASK | Subagent spawn |
| ship | SKILL, ASK, ARGS, TODO | Core pipeline orchestrator |
| skill-creator | TASK, SKILL, ASK, ARGS, WEB, MCP | Highest primitive density |
| social-distribute | ASK, ARGS | Arg passing (ask is GREEN) |
| spec-templates | TASK | Subagent spawn |
| test-browser | ASK, ARGS, MCP | Arg passing (ask + MCP are GREEN) |
| test-fix-loop | ARGS | Arg passing only |
| work | TASK, SKILL, ARGS, TODO, WEB | Core pipeline orchestrator |
| xcode-test | TASK, ASK, MCP | Subagent (ask + MCP are GREEN) |

## RED Skills (1)

| Skill | Primitives | Blocker |
|---|---|---|
| compound | SKILL, ARGS, HOOK, MCP | hookSpecificOutput -- Gemini CLI hooks use a different protocol (stdin/stdout JSON vs Claude Code hookSpecificOutput). Adaptable but requires rewrite of hook interaction pattern. |

---

## GREEN Commands (1)

| Command | Notes |
|---|---|
| sync | Uses ASK + ARGS, both have Gemini equivalents (ask_user, {{args}} in TOML) |

## YELLOW Commands (2)

| Command | Primitives | Adaptation |
|---|---|---|
| go | ASK, SKILL, ARGS | Route to skills via activate_skill |
| help | SKILL | List skills via activate_skill or shell command |

---

## Gap Analysis Summary

### Resolved Gaps (vs Codex)

| Gap | Codex Status | Gemini CLI Status | Resolution |
|---|---|---|---|
| AskUserQuestion | No equivalent (27 components blocked) | `ask_user` -- direct equivalent | Fully resolved |
| Task/subagent spawning | No equivalent (28 components blocked) | `.gemini/agents/*.md` -- single-level | Partially resolved (single-level limit) |
| Skill tool chaining | No equivalent (17 components blocked) | `activate_skill` -- context injection | Partially resolved (no args, no isolation) |
| $ARGUMENTS | No equivalent (20 components blocked) | Not in skills, `{{args}}` in commands | Partially resolved (commands only) |
| TodoWrite | No equivalent (6 components blocked) | `write_todos` -- direct equivalent | Fully resolved |
| WebSearch/WebFetch | Partial equivalent (11 components) | `google_web_search`/`web_fetch` | Fully resolved |

### Remaining Gaps

| Gap | Impact | Components | Workaround |
|---|---|---|---|
| Single-level subagent nesting | No parallel specialist execution within domain leaders | 12 agents (all domain leaders) | Leaders activate specialist skills sequentially instead of spawning subagents |
| No skill argument interpolation | Skills must use conversation context instead of explicit args | 44 skills | Skills use ask_user to request missing args, or rely on conversation context |
| hookSpecificOutput | Different hook protocol | 1 skill (compound) | Rewrite to use Gemini CLI hook stdin/stdout JSON protocol |
| Flat agent directory | No subdirectory organization | 63 agents | Flatten to single directory with name prefixes (e.g., `marketing-cmo.md`) |
| No skill isolation | Skills share conversation context | 44 skills | Architectural difference -- no workaround, but functional for sequential workflows |
