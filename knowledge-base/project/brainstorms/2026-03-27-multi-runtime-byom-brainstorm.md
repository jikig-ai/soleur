# Multi-Runtime and BYOM (Bring Your Own Model) Brainstorm

**Date:** 2026-03-27
**Trigger:** User feedback: "Trying to test but Claude install is a show stopper for me. I don't want to be tied to a commercial provider."
**Related:** #109 (closed, not reopened)

## What We're Building

A BYOM (Bring Your Own Model) documentation guide for CLI users who want to run Soleur with open-source models via Ollama, without writing any new Soleur code.

The web platform (app.soleur.ai) is the primary answer for users who don't want to install Claude Code CLI. BYOM documentation is a secondary path for CLI power users.

## Why This Approach

### The user's objection has two layers

1. **Install friction** -- "I don't want to install Claude Code" -- the cloud platform solves this entirely (no CLI needed)
2. **Vendor lock-in** -- "I don't want to be tied to a commercial provider" -- this is about Anthropic/Claude as a closed-source dependency

### Why not reopen #109

Issue #109 conflates CLI runtime portability (porting to Codex CLI, Gemini CLI, Kilo CLI) with model portability. The cloud platform pivot made CLI runtime portability less relevant. The user's actual concern is about closed-source model dependency, not which CLI tool runs the agents.

### Why not build multi-runtime now

- **P1 has 6 unstarted items.** Multi-turn conversation is broken. The cloud platform doesn't work end-to-end yet.
- **Coupling is structural.** 200+ tool name references, 95 skill-tool refs, 43k lines of instructional prose across 6 coupling layers. CTO assessment: "You'd be building your own coding assistant framework."
- **Competing runtimes lack primitives.** No other CLI tool has sub-agent spawning, skill invocation, or hook systems equivalent to Claude Code.
- **n=1.** One user blocked is signal, not a pattern. The 5+ founder interviews didn't surface vendor lock-in as a concern.

### The existing path (zero code changes)

Claude Code supports `ANTHROPIC_BASE_URL` override. Combined with `claude-code-proxy` (community project), Soleur can run on Ollama/open-source models today:

```
Ollama (local) --> claude-code-proxy --> Claude Code CLI --> Soleur plugin
```

Quality will degrade on non-Claude models (agents are prompt-engineered for Opus), but the path exists.

## Key Decisions

1. **Don't reopen #109.** Wrong scope. The cloud platform is the answer for install friction; BYOM docs address model portability.
2. **Document the Ollama proxy path.** Add a BYOM guide to documentation showing how to run Soleur with open-source models via claude-code-proxy. Include honest quality disclaimers.
3. **Keep focus on P1 cloud platform.** The web platform inherently removes the "install Claude Code" barrier for all users.
4. **Park in Post-MVP/Later.** Revisit if 3+ users in the target segment express the same concern.
5. **Model strategy: Claude-optimized, others documented.** Best experience on Claude, but document the open-source model path with quality caveats.

## Open Questions

1. What does the user respond when asked about their specific needs? (Already contacted, awaiting reply)
2. How badly does Soleur degrade on Llama 3.1 70B through the proxy? (Worth testing before documenting)
3. Should the cloud platform eventually support BYOM at the cloud layer? (Deferred to post-P4)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Don't reopen #109 -- create a new narrower issue. n=1 is signal, not pattern. P1 has 6 unstarted items including broken multi-turn. Recommended Option B: new issue scoped to "web platform runtime abstraction" parked in Post-MVP/Later with the user's quote as evidence.

### Engineering (CTO)

**Summary:** Coupling is pervasive and structural across 6 layers. Competing runtimes lack sub-agent orchestration primitives. Recommended: check if Claude Code supports Ollama via model config (confirmed via claude-code-proxy), extract portable knowledge as fallback, do not build abstraction layer. "An abstraction layer would be inner platform effect."

### Marketing (CMO)

**Summary:** Vendor lock-in is "the canonical objection of the next 100 users." Addressable market ceiling with Claude-only positioning. Immediate actions: (1) respond to user with portability angle ("your knowledge base is portable markdown"), (2) enforce "don't say plugin" brand rule, (3) write portability-focused blog post. These cost zero engineering time and partially neutralize the objection.

## Evidence Base

- User feedback: "Trying to test but Claude install is a show stopper for me. I don't want to be tied to a commercial provider."
- Business validation (2026-03-22): "Plugin delivery rejected," "Claude Code not in their stack," "Standalone product expected."
- Codex portability inventory (2026-03-10): 47.5% green, 43.4% red. Agents 67.7% portable, skills 57.9% non-portable.
- Platform risk learning (2026-02-25): Cross-platform presence identified as strategic moat.
- Claude Code Proxy: Community project enabling Ollama/OpenAI-compatible providers via `ANTHROPIC_BASE_URL` override.
