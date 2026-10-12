---
title: "Gemini CLI Critical Unknowns — Empirical Findings"
date: 2026-04-07
issue: 1738
---

# Critical Unknowns Verification

Verified from Gemini CLI v0.36.0 source code analysis (google-gemini/gemini-cli).

## 1. Skill Chaining Depth: UNLIMITED

**Source:** `packages/core/src/tools/activate-skill.ts`, `packages/core/src/skills/skillManager.ts`

`activate_skill` performs sequential context injection — it loads the skill body into the current conversation context. There is no recursion check, isolation boundary, or depth limit. Skill A can instruct the model to call `activate_skill` for Skill B, which can instruct the model to call `activate_skill` for Skill C.

**Key difference from Claude Code:** In Claude Code, the Skill tool spawns isolated execution contexts. In Gemini CLI, skills are injected as context within the same conversation loop. This means:

- No parallel skill execution (sequential only)
- No isolated tool scope per skill
- No skill-level argument passing (`activate_skill` takes only `name`, no args)
- Effectively unlimited depth (bounded only by context window)

**Impact on Soleur:** The `go` → `brainstorm` → `plan` → `work` chain would work as sequential context injection. However, each skill's full body is loaded into the conversation, consuming context window. With 63 skills averaging 2-5KB each, deep chains risk context exhaustion.

## 2. Agent Subdirectory Nesting: FLAT ONLY

**Source:** `packages/core/src/agents/agentLoader.ts` (line ~540)

`loadAgentsFromDirectory()` uses `fs.readdir(dir, { withFileTypes: true })` and filters to `entry.isFile()` only. No recursive directory traversal. Agent files must be directly in `.gemini/agents/`, not in subdirectories.

**Impact on Soleur:** All 62 agents currently organized in `agents/marketing/`, `agents/engineering/design/`, etc. must be flattened to a single directory. Name collisions need resolution — current naming is `cmo.md` (unique per domain), but with flattening, all 62 files coexist in one directory. This is cosmetic, not functional.

## 3. Agent Description Token Budget: NONE

**Source:** `packages/core/src/agents/registry.ts`, `packages/core/src/skills/skillManager.ts`

No hard limit on agent count or cumulative description size. All discovered agents are registered; all agent names and descriptions are injected into the system prompt for routing. The practical limit is the model's context window.

**Impact on Soleur:** 62 agents at ~40 words/description = ~2,500 words (~3.3K tokens). This is within Claude Code's 15K threshold. Gemini models (Gemini 2.5 Pro: 1M context) have ample headroom. No agent count is a concern.

## 4. Skill Argument Interpolation: NOT SUPPORTED

**Source:** `packages/core/src/tools/activate-skill.ts`

The `activate_skill` tool accepts only one parameter: `name` (an enum of available skill names). There is no `args` parameter. No `{{args}}`, `${args}`, or template interpolation is performed on skill bodies.

**Contrast with commands:** Command TOML files support `{{args}}` interpolation for user input. Skills do not.

**Impact on Soleur:** Skills like `brainstorm`, `plan`, and `work` receive feature descriptions via `args` from the Skill tool. On Gemini CLI, the user would need to include the feature description in the conversation context before activating the skill, or the skill would need to use `ask_user` to request it. This is a workflow difference, not a blocker.

**Workaround:** Skills can check for context in the conversation and use `ask_user` if missing. This mirrors the pattern many Soleur skills already have ("If feature description is empty, ask the user").

## 5. MCP Server Compatibility: FULL

**Source:** `gemini mcp add --help`, `packages/core/` MCP integration

Gemini CLI supports three MCP transports: `stdio`, `sse`, and `http`. Soleur's MCP servers use HTTP transport (Context7, Cloudflare, Vercel at `type: "http"`) and stdio (Playwright via `npx`). Both transports are natively supported.

**Migration path:** Run `gemini mcp add` for each server:

```bash
gemini mcp add context7 https://mcp.context7.com/mcp -t http
gemini mcp add cloudflare https://mcp.cloudflare.com/mcp -t http
gemini mcp add vercel https://mcp.vercel.com -t http
gemini mcp add playwright npx @playwright/mcp@latest --isolated
```

Or include in `gemini-extension.json` manifest for bundled distribution.

## Gate Decision

**All 5 unknowns have acceptable answers.** No fundamental architectural blocker found. Proceed with full portability scan (Phase 1.3).

| Unknown | Result | Blocker? |
|---|---|---|
| Skill chaining depth | Unlimited (context injection) | No — different semantics but functional |
| Agent subdirectory nesting | Flat only | No — cosmetic restructuring |
| Agent description budget | No limit | No |
| Skill argument interpolation | Not supported | No — workaround via conversation context |
| MCP compatibility | Full (stdio + HTTP) | No |

**Critical constraint remains:** Subagents cannot call other subagents (single-level). But subagents CAN activate skills. This means the domain-leader-to-specialist pattern can be restructured: leaders as agents, specialists as skills activated by leaders.
