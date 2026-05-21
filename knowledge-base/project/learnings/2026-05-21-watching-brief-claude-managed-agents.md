---
category: strategic-watching-brief
module: backend-agent-infra
date: 2026-05-21
status: defer
revisit_when: a-productized-claude-api-backend-agent-lands-on-the-roadmap
---

# Watching Brief: Claude Managed Agents for Soleur Backend Agents

Source: https://claude.com/blog/claude-managed-agents-updates

## Question

Should Soleur leverage Claude Code's Managed Agents feature to run backend agents on Hetzner or Cloudflare?

## Decision

**Defer.** Not a fit today; revisit when a productized Claude-API backend agent lands on the roadmap. When it does, default to **Cloudflare sandbox**, not Hetzner.

## Why Defer

1. **No Claude-API backend agents exist to migrate.** `grep -rE '@anthropic-ai/sdk|Anthropic\(' apps/ packages/` returns zero. Soleur's current "backend agents" are Inngest workflow functions (deterministic JS, not LLM-driven). Managed Agents only pays off for productized Claude-API agentic loops — turning a `/soleur:*` skill chain into a SaaS-facing agent that runs without an operator's Claude Code session driving it.

2. **The agent loop never moves off Anthropic.** Per the blog: *"the agent loop that handles orchestration, context management, and error recovery stays on Anthropic's infrastructure, while tool execution moves to your own configured environment."* The framing "run our agents on our own cluster" is misleading — only the tool-execution sandbox moves. Model calls + prompt traces still flow through Anthropic. Data-residency win is real but partial: shrinks the sub-processor surface, doesn't eliminate it.

## Why Cloudflare over Hetzner (when the time comes)

- **Cloudflare is in Anthropic's named provider list** (Daytona, Modal, Vercel, Cloudflare). Hetzner is not — going Hetzner means self-hosting the sandbox primitive: provisioning, scaling, isolation, hardened-runner story, plus AGENTS.md `hr-all-infrastructure-provisioning-servers` overhead.
- Cloudflare is already in Soleur's stack (Workers, DNS, WAF). Wire-up is meant to be turn-key.
- Hetzner becomes interesting only as a *later* cost optimization once steady-state agent-hours justify the self-host burden. The orchestration-on-Anthropic split bounds the savings — you're optimizing the tool-execution slice, not the LLM slice.

## Re-Evaluation Criteria (ALL must hold)

- [ ] A Claude-API-driven backend agent product is committed to the roadmap (not just exploratory).
- [ ] The agent has identifiable per-tool execution work (sandboxed code execution, browser automation, file I/O) that benefits from a custom runtime.
- [ ] Expected steady-state usage exceeds the threshold where Cloudflare's pricing becomes non-trivial vs. self-host.

If all three hold, run a proper brainstorm with CTO + CPO + CLO triad (likely `USER_BRAND_CRITICAL=true` due to data residency and sub-processor surface).

## Tags

category: strategic-watching-brief
module: backend-agent-infra
