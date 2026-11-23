---
last_updated: 2026-11-01
last_reviewed: 2026-06-02
review_cadence: monthly
owner: CRO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
competitor: Paperclip
tier: 3
convergence_risk: High
---

# Battlecard: Paperclip

> **[2026-11-01 Cascade sync, index alignment only, no new web facts]** Corrected this card where it contradicted the current CI index:
> 1. **Canonical repo resolved: `paperclipai/paperclip`.** `agencyenterprise/paperclip-ai` has 6 stars and is not the project.
> 2. **Stars: 74,282, verified 2026-07-20 via the GitHub API.** The 30,000+ figure is superseded.
> 3. **`convergence_risk` raised Medium to High** to match the index Tier 3 row. The index calls Paperclip "complementary at the product level, substitutable at the narrative level."
> 4. Releases are now date-versioned (e.g. `v2026.416.0`). v0.3.0 is historical.
> 5. Added the index's "free stack" objection: Paperclip + BYO agents + `alirezarezvani/claude-skills`.
>
> Paperclip facts were **not re-verified on 2026-11-01**; the scheduled scan's web tools were blocked. Star count is as of 2026-07-20; the rest is as of 2026-06-08.
>
> **Soleur-side caution:** the repo `LICENSE` and `plugins/soleur/LICENSE` are **Business Source License 1.1** (Soleur v3.1.0 and later; each version converts to Apache-2.0 four years after publication). Lines below that call Soleur "Apache-2.0" are out of date. Say "source-available" until CRO/CLO reconcile the wording.

> **[2026-06-02 Review note]** Traction updated against `knowledge-base/product/competitive-intelligence.md` (2026-05-30 scan): Paperclip **crossed 30,000+ GitHub stars in three weeks** (roughly double the 14.6k March figure) and is now **explicitly built on Anthropic's Claude Code**. The "stars exceed 30k" convergence trigger below has effectively fired — category validation is confirmed; treat the open-source-orchestration narrative as a live competitive surface, not a hypothetical.

## Quick Facts

| Field | Value |
|-------|-------|
| **Product** | Paperclip -- open-source orchestration platform for zero-human companies. MIT-licensed. Self-hosted. |
| **Pricing** | Free (MIT license, self-hosted). No paid tier. |
| **Canonical repo** | [`paperclipai/paperclip`](https://github.com/paperclipai/paperclip) (resolved per CI index; `agencyenterprise/paperclip-ai` is not the project). |
| **GitHub Stars** | **74,282 (verified 2026-07-20 via GitHub API).** Path: ~14.6k (March) → 30k (April) → 42k+ → 53k+ in the first 6 weeks after creation in early March 2026. The index reads a ~15% fork ratio as a sign of real deployment, not just starring. Launched by pseudonymous `@dotta`. |
| **Latest Version** | Active date-versioned releases (e.g. [`v2026.416.0`](https://github.com/paperclipai/paperclip/releases/tag/v2026.416.0), per 2026-06-08 index). Earlier v0.3.0 (March 9, 2026) added Cursor, OpenCode and Pi adapters. **Built on Anthropic's Claude Code.** |
| **Domain Coverage** | Agent-runtime-agnostic. Does not provide domain-specific agents. BYO agents: Claude, Codex, Gemini and OpenClaw per the index, plus Cursor, Bash and HTTP webhooks from earlier intake. Target domains: marketing, crypto, e-commerce, software development, sales, media. |
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
| **GitHub traction** | 74,282 stars (verified 2026-07-20) | Early stage. | Paperclip |
| **Company templates** | Clipmart (upcoming): pre-built company templates with org structures and agent configs | 60+ agents ship as integrated organization. No assembly required. | Soleur (ready-made) vs. Paperclip (assembly from templates) |

## Talk Tracks

### "Paperclip lets me orchestrate any agents I want. Why lock into Soleur?"

**Response:** "Paperclip is excellent infrastructure. It gives you the org chart, the budgets, the governance. What it does not give you is the agents or the knowledge. Paperclip is the scaffolding. Soleur is the organization that fills it. You can use Paperclip to orchestrate Claude sessions and Python scripts, but those agents do not share institutional memory, do not reference each other's work, and do not compound across domains. Soleur's 60+ agents share a knowledge base where the brand guide informs marketing, the competitive analysis shapes pricing, and the legal audit references the privacy policy. Paperclip orchestrates tasks. Soleur compounds intelligence."

### "Paperclip is MIT-licensed and has 70,000+ stars. It's more popular."

**Response:** "Paperclip's growth is impressive and validates the demand for AI company orchestration. GitHub stars measure developer interest in the infrastructure problem. Soleur solves a different problem: domain-specific intelligence with compounding knowledge. A founder using Paperclip still needs to source, configure, and connect agents for each business function. A founder using Soleur gets 60+ agents that work together out of the box. The projects could be complementary -- Soleur's agents running within Paperclip's orchestration framework."

### "What about Clipmart? Pre-built company templates sound like Soleur in a box."

**Response:** "Clipmart is not shipped yet, so we are evaluating a roadmap, not a product. When it launches, the question will be: do templates include domain intelligence, or just org charts and agent configs? A template that says 'hire a marketing agent' is not the same as an agent that pulls from your brand guide, competitive landscape, and content strategy to write launch content. If Clipmart ships with curated, knowledge-aware agents, the competitive overlap increases. If it ships with skeleton configs that users must populate, it remains orchestration infrastructure."

## Objection Handling

| Objection | Response |
|-----------|----------|
| "Paperclip is agent-runtime-agnostic. Soleur is locked to Claude." | "Agent flexibility is a real advantage for Paperclip. Soleur's Claude Code integration is a deliberate trade-off: deep integration with one model enables the compounding knowledge base, cross-domain agent context, and workflow lifecycle that runtime-agnostic orchestration cannot provide. The question is whether you want to assemble agents from multiple runtimes or deploy an integrated organization." |
| "Paperclip has budgets and governance. Soleur doesn't." | "Paperclip's per-agent budgets and governance layers are strong infrastructure features. Soleur provides operational governance through its workflow lifecycle (brainstorm-plan-implement-review-compound) and human-in-the-loop design. Different approaches to the same need: ensuring AI actions are controlled and accountable." |
| "I'll use Paperclip + Claude Code agents and skip Soleur." | "You can. Paperclip + Claude Code gives you orchestration + general-purpose AI. What you miss is the 60+ specialized agents with curated business domain expertise, the compounding knowledge base that connects decisions across domains, and the brainstorm-plan-implement-review-compound workflow lifecycle. The gap is domain intelligence and cross-domain coherence, not orchestration or raw AI capability." |
| "Paperclip + `alirezarezvani/claude-skills` + my own API key is basically Soleur for the cost of tokens." *(added 2026-11-01 from index Tier 3 takeaway 3)* | "That's an honest comparison, and it's the stack we have to beat. You get orchestration and a large skill library for the cost of your API usage. What you don't get is the assembled product: an enforced brainstorm → plan → work → review → compound lifecycle where each stage hands off to the next, a git-tracked knowledge base that every agent reads and writes, and a hosted platform you don't have to wire together and maintain. If you enjoy assembling and maintaining the stack, it's a reasonable choice. If you want to run the company instead of the tooling, that's what Soleur is for." |

## Convergence Watch

Review monthly. Paperclip is complementary today but could converge.

| Trigger | Current Status (2026-06-02) | Action if Triggered |
|---------|---------------------------|-------------------|
| Clipmart launches with curated, knowledge-aware company templates | Upcoming feature. Not shipped. | Evaluate template quality and domain coverage. If templates include domain-specific intelligence, convergence risk escalates. Consider publishing a Soleur template for Paperclip's Clipmart. |
| Paperclip adds a knowledge layer | No knowledge persistence. Infrastructure-only. | Major escalation. If Paperclip adds cross-agent shared knowledge, the "orchestration vs. intelligence" differentiation weakens. |
| Paperclip ships a Claude Code adapter | **Effectively TRIGGERED (2026-11-01 sync).** The CI index (2026-06-08) describes Paperclip as built on Claude Code with BYO Claude agents. The earlier "no Claude Code adapter yet" status is superseded. Adapter quality has not been evaluated. | Evaluate integration quality. Consider a Soleur-Paperclip integration. |
| Paperclip GitHub stars exceed 30k | **TRIGGERED.** 74,282 stars verified 2026-07-20 (`paperclipai/paperclip`). | Community traction validated. Evaluate whether Soleur should publish a Paperclip adapter to ride distribution. Next escalation threshold: 100k stars. Re-check on the next unblocked scan. |
| Paperclip raises funding or announces commercial tier | MIT-licensed, no commercial model. | Monitor pricing relative to Soleur. If Paperclip charges for hosted orchestration, the "free OSS orchestration + Soleur domain intelligence" stack becomes more expensive. |

---

_Updated: 2026-11-01 (downstream-sync cascade: stars/canonical repo/convergence risk aligned to index; no new web facts). Previously 2026-06-02. Source: competitive-intelligence.md (2026-11-01 index; Paperclip stars as of 2026-07-20)._
