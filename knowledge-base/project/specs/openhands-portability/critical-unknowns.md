---
title: "OpenHands Critical Unknowns"
date: 2026-04-07
issue: 1770
---

# Critical Unknowns

Identified from OpenHands SDK documentation analysis (docs.openhands.dev, accessed 2026-04-07). Unlike the Gemini CLI analysis, these have NOT been verified against source code — OpenHands is a rapidly evolving open-source project and docs may lag implementation.

## 1. DelegateTool Nesting Depth: BELIEVED UNLIMITED

**Source:** SDK docs `sdk/guides/agent-delegation.md`

DelegateTool documentation describes spawning sub-agents that "operate in the same workspace as the main agent" with "independent conversation contexts." No depth limit is documented. The `max_children` parameter controls concurrency, not nesting depth.

**Risk:** If an undocumented nesting limit exists, the domain-leader → specialist → sub-specialist pattern would break. The Codex analysis identified `max_depth=1` as a critical blocker.

**Verification needed:** Create a test agent that spawns a sub-agent which spawns a sub-sub-agent. Confirm 3-level nesting works.

**Impact if wrong:** Domain leaders shift from YELLOW to YELLOW (same classification, but specialists must become skills like on Gemini CLI — loses parallelism architecture advantage).

## 2. File-Based Agent DelegateTool Integration: BELIEVED WORKING

**Source:** SDK docs `sdk/guides/agent-file-based.md`

Documentation states `register_file_agents()` auto-registers all discovered agents for delegation via DelegateTool. But the docs don't show an end-to-end example of a file-based agent spawning another file-based agent via DelegateTool.

**Risk:** DelegateTool might only work for Python-defined agents, not markdown file-based agents.

**Verification needed:** Create two file-based agents (`.agents/agents/parent.md` and `.agents/agents/child.md`). Parent instructs DelegateTool to delegate to child. Confirm child executes.

**Impact if wrong:** All 19 YELLOW agents (domain leaders) would need Python wrappers instead of pure markdown — shifts from "tool name adaptation" to "code rewrite."

## 3. AskUserQuestion Workaround Quality: UNKNOWN

**Source:** No OpenHands docs address structured user prompts.

When an agent outputs text with options (e.g., "Choose: A, B, or C"), the user responds in freeform. There's no guarantee the model will parse the response correctly.

**Risk:** For critical routing decisions (brainstorm Phase 0: "skip to one-shot?" or "brainstorm anyway?"), freeform parsing may produce incorrect routing.

**Verification needed:** Test 10 structured prompt scenarios with freeform user responses. Measure routing accuracy vs. Claude Code's AskUserQuestion.

**Impact if wrong:** Skills relying on multi-option routing (brainstorm, go, plan) may need UX redesign — not a portability issue but a quality issue.

## 4. Skill Loading Model: CONTEXT INJECTION (CONFIRMED)

**Source:** SDK docs `sdk/arch/skill.md`, `overview/skills.md`

Skills inject content into agent context. Repository skills load every step. Keyword/task skills load on trigger. This is confirmed identical to Gemini CLI's `activate_skill`.

**No risk.** This is a known semantic difference, not an unknown.

## 5. Plugin System Maturity: EARLY

**Source:** SDK docs `sdk/guides/plugins.md`

The plugin system includes install/enable/disable/uninstall functions and a `plugin.json` manifest. But the ecosystem is young — there's no public plugin registry comparable to Claude Code's marketplace or VS Code's extension store.

**Risk:** Plugin discovery and distribution may be limited. Soleur's value proposition on OpenHands depends on discoverability.

**Verification needed:** Install a test plugin from a GitHub repo URL. Confirm agents, skills, hooks, and MCP configs all load correctly.

**Impact if wrong:** Plugin bundling may not work as documented — Soleur would need to distribute as a manual install (copy files into `.agents/`).

## 6. Hook JSON Protocol Compatibility: BELIEVED COMPATIBLE

**Source:** SDK docs `sdk/guides/hooks.md`, `openhands/usage/customization/hooks.md`

OpenHands hooks support JSON output with `decision` (allow/deny), `reason`, and `additionalContext` fields. This maps to Claude Code's `hookSpecificOutput` protocol.

**Risk:** The JSON schema may differ in subtle ways (field names, required fields, error handling).

**Verification needed:** Port `guardrails.sh` to OpenHands hook format. Confirm PreToolUse blocking with JSON output injects `additionalContext` into agent prompt.

**Impact if wrong:** The compound skill's branch safety check needs rewriting (minor — 1 skill affected).

## Gate Decision

**Cannot proceed to PoC without OpenHands SDK access.** Unlike Gemini CLI (installed via `npm install -g @anthropic-ai/gemini-cli`), OpenHands requires:

1. Docker (for sandbox execution)
2. An LLM API key (supports Claude, GPT, or other providers)
3. `pip install openhands-ai` for the SDK

All unknowns have ACCEPTABLE documented answers. The risk is that documentation lags implementation. A PoC phase should verify unknowns #1, #2, #5, and #6 before committing to a full port.

| Unknown | Documented Answer | Confidence | Blocker if Wrong? |
|---|---|---|---|
| DelegateTool nesting depth | Unlimited | MEDIUM | Yes — shifts domain leader strategy |
| File-based agent delegation | Works via register_file_agents() | MEDIUM | Yes — requires Python wrappers |
| AskUserQuestion workaround | Freeform questions | HIGH | No — quality issue, not blocker |
| Skill loading model | Context injection | HIGH | No — known |
| Plugin system maturity | Full lifecycle (install/enable/disable) | LOW | No — fallback to manual install |
| Hook JSON protocol | Compatible schema | MEDIUM | No — 1 skill affected |
