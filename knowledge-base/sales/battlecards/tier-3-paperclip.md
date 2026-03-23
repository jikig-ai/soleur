---
last_updated: 2026-03-12
last_reviewed: 2026-03-12
review_cadence: monthly
owner: CRO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
competitor: Paperclip
tier: 3
convergence_risk: Medium
---

# Battlecard: Paperclip

## Quick Facts

| Field | Value |
|-------|-------|
| **Product** | Paperclip -- open-source orchestration platform for zero-human companies. MIT-licensed. Self-hosted. |
| **Pricing** | Free (MIT license, self-hosted). No paid tier. |
| **GitHub Stars** | 14.6k (March 2026). 1.7k forks. Rapid growth from 4.3k to 14.6k in one week. |
| **Latest Version** | v0.3.0 (March 9, 2026). New adapters for Cursor, OpenCode, Pi. |
| **Domain Coverage** | Agent-runtime-agnostic. Does not provide domain-specific agents. Users bring their own agents (Claude, OpenClaw, Cursor, Codex, Bash, HTTP webhooks). Target domains: marketing, crypto, e-commerce, software development, sales, media. |
| **Key Features** | Org charts with reporting lines, cascading goals (company mission to individual tasks), heartbeat scheduling, per-agent monthly budgets with auto-pause, governance with rollback and approval gates, immutable audit logs, atomic task checkout, multi-company support. Upcoming: Clipmart (pre-built company templates). |
| **Knowledge Persistence** | None. No knowledge layer. Orchestration infrastructure only. |
| **Architecture** | Node.js + React. Embedded PostgreSQL (local) or external Postgres. Self-hosted. API-driven. |

## When You Will Encounter This

- A founder asks "Paperclip orchestrates agent companies. How is Soleur different?"
- Discussions about open-source alternatives for running AI companies
- Comparisons of orchestration frameworks vs. integrated AI organizations
- Questions about using Paperclip + individual agents as a Soleur alternative
- When Clipmart launches, questions about whether pre-built templates replace Soleur

## Differentiator Table

| Dimension | Paperclip | Soleur | Advantage |
|-----------|-----------|--------|-----------|
| **Layer** | Infrastructure orchestration (org charts, budgets, governance, scheduling) | Domain intelligence (60+ specialized agents, skills, compounding knowledge base) | Different layers. Potentially complementary. |
| **Agents** | None provided. Users bring their own (Claude, Cursor, Codex, Bash, webhooks). | 60+ pre-built agents across 8 business domains with shared institutional memory. | Soleur (integrated, opinionated, curated) |
| **Knowledge persistence** | None. No knowledge layer. | Compounding knowledge base across all domains. Cross-domain references. | Soleur |
| **Workflow orchestration** | Heartbeat scheduling, ticket system, governance, approval gates. Task-oriented. | Brainstorm-plan-implement-review-compound lifecycle. Business-operation-oriented. | Different approaches. Paperclip: task execution. Soleur: business lifecycle. |
| **Cross-domain coherence** | None. Agents are orchestrated but do not share knowledge or context. | All agents share institutional memory. Brand guide informs marketing. Competitive analysis shapes pricing. | Soleur |
| **Pricing** | Free (MIT) | Free (Apache-2.0). Paid tier planned at $49/month. | Both free at core. |
| **Self-hosted** | Yes (Node.js + Postgres) | Yes (Claude Code plugin, local-first) | Both self-hosted. |
| **Agent flexibility** | Any agent runtime (Claude, Cursor, Codex, scripts, webhooks) | Claude Code native. Anthropic model dependency. | Paperclip (runtime-agnostic) |
| **GitHub traction** | 14.6k stars (rapid growth) | Early stage. | Paperclip |
| **Company templates** | Clipmart (upcoming): pre-built company templates with org structures and agent configs | 60+ agents ship as integrated organization. No assembly required. | Soleur (ready-made) vs. Paperclip (assembly from templates) |

## Talk Tracks

### "Paperclip lets me orchestrate any agents I want. Why lock into Soleur?"

**Response:** "Paperclip is excellent infrastructure. It gives you the org chart, the budgets, the governance. What it does not give you is the agents or the knowledge. Paperclip is the scaffolding. Soleur is the organization that fills it. You can use Paperclip to orchestrate Claude sessions and Python scripts, but those agents do not share institutional memory, do not reference each other's work, and do not compound across domains. Soleur's 60+ agents share a knowledge base where the brand guide informs marketing, the competitive analysis shapes pricing, and the legal audit references the privacy policy. Paperclip orchestrates tasks. Soleur compounds intelligence."

### "Paperclip is MIT-licensed and has 14.6k stars. It's more popular."

**Response:** "Paperclip's growth is impressive and validates the demand for AI company orchestration. GitHub stars measure developer interest in the infrastructure problem. Soleur solves a different problem: domain-specific intelligence with compounding knowledge. A founder using Paperclip still needs to source, configure, and connect agents for each business function. A founder using Soleur gets 60+ agents that work together out of the box. The projects could be complementary -- Soleur's agents running within Paperclip's orchestration framework."

### "What about Clipmart? Pre-built company templates sound like Soleur in a box."

**Response:** "Clipmart is not shipped yet, so we are evaluating a roadmap, not a product. When it launches, the question will be: do templates include domain intelligence, or just org charts and agent configs? A template that says 'hire a marketing agent' is not the same as an agent that pulls from your brand guide, competitive landscape, and content strategy to write launch content. If Clipmart ships with curated, knowledge-aware agents, the competitive overlap increases. If it ships with skeleton configs that users must populate, it remains orchestration infrastructure."

## Objection Handling

| Objection | Response |
|-----------|----------|
| "Paperclip is agent-runtime-agnostic. Soleur is locked to Claude." | "Agent flexibility is a real advantage for Paperclip. Soleur's Claude Code integration is a deliberate trade-off: deep integration with one model enables the compounding knowledge base, cross-domain agent context, and workflow lifecycle that runtime-agnostic orchestration cannot provide. The question is whether you want to assemble agents from multiple runtimes or deploy an integrated organization." |
| "Paperclip has budgets and governance. Soleur doesn't." | "Paperclip's per-agent budgets and governance layers are strong infrastructure features. Soleur provides operational governance through its workflow lifecycle (brainstorm-plan-implement-review-compound) and human-in-the-loop design. Different approaches to the same need: ensuring AI actions are controlled and accountable." |
| "I'll use Paperclip + Claude Code agents and skip Soleur." | "You can. Paperclip + Claude Code gives you orchestration + general-purpose AI. What you miss is the 60+ specialized agents with curated business domain expertise, the compounding knowledge base that connects decisions across domains, and the brainstorm-plan-implement-review-compound workflow lifecycle. The gap is domain intelligence and cross-domain coherence, not orchestration or raw AI capability." |

## Convergence Watch

Review monthly. Paperclip is complementary today but could converge.

| Trigger | Current Status (2026-03-12) | Action if Triggered |
|---------|---------------------------|-------------------|
| Clipmart launches with curated, knowledge-aware company templates | Upcoming feature. Not shipped. | Evaluate template quality and domain coverage. If templates include domain-specific intelligence, convergence risk escalates. Consider publishing a Soleur template for Paperclip's Clipmart. |
| Paperclip adds a knowledge layer | No knowledge persistence. Infrastructure-only. | Major escalation. If Paperclip adds cross-agent shared knowledge, the "orchestration vs. intelligence" differentiation weakens. |
| Paperclip ships a Claude Code adapter | v0.3.0 added Cursor, OpenCode, Pi adapters. No Claude Code adapter yet. | Evaluate integration quality. Consider building a Soleur-Paperclip integration before Paperclip builds a generic Claude Code adapter. |
| Paperclip GitHub stars exceed 30k | 14.6k stars (March 2026). Growing rapidly. | Community traction validated. Evaluate whether Soleur should publish a Paperclip adapter to ride distribution. |
| Paperclip raises funding or announces commercial tier | MIT-licensed, no commercial model. | Monitor pricing relative to Soleur. If Paperclip charges for hosted orchestration, the "free OSS orchestration + Soleur domain intelligence" stack becomes more expensive. |

---

_Updated: 2026-03-12. Source: competitive-intelligence.md (2026-03-12)._
