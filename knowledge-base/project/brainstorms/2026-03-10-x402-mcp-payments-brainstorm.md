# x402 / MCP Agent-Native Payments Brainstorm

**Date:** 2026-03-10
**Status:** Parked (revisit post-MVP)
**Branch:** feat-x402-mcp-payments
**Participants:** CTO, CPO, CRO + repo research + learnings research

## What We're Exploring

Expose Soleur capabilities via MCP servers that accept payments through the x402 protocol, enabling other AI agents to discover and pay for specialized capabilities (code review, legal docs, marketing strategy, etc.) on a per-request basis.

## Context

- jean.deruelle discussed x402 agent-native payments in Discord #ai-news (2026-03-09)
- x402 has real momentum: Coinbase, Cloudflare backing, 35M+ transactions on Solana, TypeScript SDK available
- Soleur has 61 agents, 56 skills, organized across 8 business domains
- BUSL-1.1 license protects this use case (only Jikigai can host commercially)

## Domain Leader Assessments

### CTO Assessment

- **Capability inversion risk**: Agents are markdown prompts, not functions. Each MCP call requires spinning up LLM inference ($0.01-$0.50+ per call).
- **Stateless execution kills the moat**: Knowledge base doesn't transfer through stateless endpoints.
- **Three options proposed**: (A) Thin proxy with 5-10 curated stateless tools, (B) Full agent gateway with session state, (C) Defer and build subscription first.
- **Recommended**: Option C first, Option A as parallel experiment.
- **Capability gaps identified**: Crypto treasury management, MCP server provisioning skill, API rate limiting/metering, prompt-extraction defense.

### CPO Assessment

- **PIVOT directive conflict**: Product is in validation phase (0/5 pricing gates passed, zero external users). Building new features contradicts the directive.
- **Wrong buyer**: Solo founders (current ICP) vs. agent developers are different markets.
- **Commoditization exposure**: Agents are prompt files. Stateless endpoints strip the compounding knowledge moat.
- **Recommended**: Option A (validate first with 10 founders, include "would you pay for agent services?" in interviews).

### CRO Assessment

- **Zero switching costs**: Agent-native GTM has no brand loyalty, no relationships. Every request is a price/quality competition.
- **Unit economics unmodeled**: LLM cost per request vs. willingness-to-pay gap unknown.
- **Cannibalization risk**: If best capabilities are available a la carte via MCP, why pay $49/month subscription?
- **One interesting reframe**: Use MCP/x402 as a demand signal mechanism, not a revenue channel. Expose capabilities to learn what agents actually request.

### Learnings Research

- 9 relevant past learnings found, including MCP bundling constraints, HTTP 402 handling patterns, and platform risk analysis.
- MCP bundling checklist: (1) tools exist, (2) auth model compatible, (3) transport is HTTP.
- Platform risk learning: horizontal features get absorbed by platform owners. Only compounding knowledge, cross-domain coherence, and orchestration depth survive.
- No existing learnings about x402 protocol or agent-native service architecture.

### Repo Research

- Zero existing MCP server code exposing Soleur capabilities (all 3 MCP servers are inbound/consuming).
- `agent-native-architecture` skill has MCP tool design patterns ready.
- `apps/telegram-bridge` establishes the separate service pattern (Bun/TypeScript, Docker, Terraform).
- Constitution says "Plugin infrastructure is intentionally static." MCP server is runtime infrastructure -- tension with current architecture.

## Key Decision

**User intent**: Revenue channel (not just experiment or positioning play).

**Parked reason**: Brainstorm aborted before resolving the value gap question -- what makes Soleur's output worth more than a raw Claude API call to the buyer agent? This is the core question to answer post-MVP.

## Open Questions

1. **Value proposition**: Why would an agent pay Soleur instead of calling Claude directly? Cross-domain coherence? Institutional templates? BYOKB (bring your own knowledge base)?
2. **Unit economics**: What's the actual LLM cost per agent capability invocation? What margin is viable?
3. **Which capabilities are exposable?**: Many agents need repo/context access that external callers don't have.
4. **x402 timing**: Is adoption sufficient in 2026-2027 for meaningful revenue?
5. **Cannibalization**: Does per-request MCP access undermine the subscription model?
6. **Buyer identity**: Agent platforms? Developers? Companies? Each has different GTM.

## Next Steps

- Revisit post-MVP after founder validation (10+ conversations)
- Include "would you pay for agent-consumable services?" in validation interviews
- Monitor x402 ecosystem maturity (deferred payment scheme, fiat compatibility)
- Model LLM cost per agent invocation before pricing
