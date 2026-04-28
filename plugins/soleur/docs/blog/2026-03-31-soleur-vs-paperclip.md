---
title: "Soleur vs. Paperclip: Domain Intelligence vs. AI Company Orchestration"
seoTitle: "Soleur vs. Paperclip: Open-Source AI Company Platforms Compared"
date: 2026-03-31
description: "Soleur vs. Paperclip: both open-source AI company platforms, but from opposite directions. One provides infrastructure, the other provides intelligence."
tags:
  - comparison
  - paperclip
  - company-as-a-service
  - open-source
---

[Paperclip](https://paperclip.ing/) reached [14,600+ GitHub stars](https://github.com/paperclipai/paperclip) with a straightforward premise: give AI agents an org chart, a budget, a schedule, and governance controls, and they can run a company without humans. Zero-human company orchestration, MIT-licensed, self-hosted. The traction is real. The category framing is direct.

Soleur and Paperclip both target the same destination -- a company that operates with minimal human overhead -- but they approach it from opposite ends of the stack.

Paperclip is infrastructure. It tells agents when to run, how much to spend, who reports to whom, and what to do when something goes wrong. It does not tell agents what to know, how to reason about legal risk, or what makes a good marketing strategy. You bring your own agents and domain logic.

Soleur is intelligence. {{ stats.agents }} agents, {{ stats.skills }} skills, and a compounding knowledge base across {{ stats.departments }} departments -- engineering, marketing, legal, finance, operations, product, sales, and support. Every agent carries domain knowledge. Every session makes the system smarter. The orchestration is the workflow lifecycle: brainstorm → plan → implement → review → compound.

Neither platform is complete without what the other provides. Understanding what each actually solves is the first step to knowing which one belongs in your stack -- or whether you need both.

## What Paperclip Actually Is

Paperclip is an [open-source orchestration platform for zero-human companies](https://topaiproduct.com/2026/03/06/paperclip-ai-wants-to-run-your-entire-company-with-zero-humans-and-its-open-source/). It is agent-runtime-agnostic: connect Claude, Cursor, OpenCode, Codex, Bash, or HTTP webhooks. As of [v0.3.0](https://github.com/paperclipai/paperclip/releases/tag/v0.3.0), it supports adapters for Cursor, OpenCode, and Pi alongside the original runtime targets.

The feature set is built around governance infrastructure:

- **Org charts with reporting lines** -- tasks cascade from company mission down to individual agent objectives, following the defined hierarchy
- **Heartbeat scheduling** -- agents run on defined cadences, triggered by the platform rather than requiring user prompts
- **Per-agent monthly budgets** -- each agent has a spending ceiling; exceeding it triggers automatic pausing
- **Governance with rollback and approval gates** -- changes require approval before execution and can be rolled back afterward
- **Immutable audit logs** -- every action is recorded and cannot be altered retroactively
- **Multi-company support** -- manage multiple companies from a single instance

The upcoming Clipmart feature extends this with downloadable pre-built company templates: full org structures and agent configurations for marketing companies, e-commerce operations, software development, sales organizations, and media. The idea is to lower the setup barrier for "zero-human company" creation.

What Paperclip does not provide: agents. Domain knowledge. Opinions about what a legal agent should know, how a competitive intelligence scan should be structured, or why the brand guide the marketing agent creates should inform the content strategy the growth agent executes. Paperclip is a runtime for agents you define. It enforces constraints and routes work. The intelligence is your responsibility.

## What Soleur Actually Is

Soleur is the [Company-as-a-Service]({{ site.url }}/company-as-a-service/) platform. {{ stats.agents }} agents, {{ stats.skills }} skills, and a compounding knowledge base organized across {{ stats.departments }} business domains. Each domain has a director-level leader and specialist agents: the CMO orchestrates brand architects, SEO specialists, and growth researchers; the CLO manages legal document generation and compliance auditing; the CTO oversees engineering research, code review, architecture design, and deployment.

These agents do not operate in silos. They share a git-tracked knowledge base -- a directory of structured Markdown files -- that accumulates institutional memory with every session. The brand guide the brand-architect writes informs what the content writer generates. The competitive intelligence scan the CPO runs updates the sales battlecards the deal-architect uses. The legal compliance audit references the privacy policy the CLO previously documented. Knowledge flows across domains because every agent reads from and writes to the same base.

The orchestration model is the [compound workflow lifecycle]({{ site.url }}blog/why-most-agentic-tools-plateau/): brainstorm → plan → implement → review → compound. The compound step is what separates Soleur's approach architecturally: learnings from each session are routed back to the specific agents and workflows that were active, and critical failure patterns are promoted to mechanical enforcement hooks -- code-level guardrails that make known failure modes structurally impossible.

Soleur runs inside Claude Code. It is open-source and local-first: your knowledge base lives in your repository, your agents run in your environment, your credentials stay under your control.

## The Core Distinction: Infrastructure vs. Intelligence

Paperclip solves the governance problem: how do you control autonomous agents operating without human oversight? Budget caps, approval gates, rollback capabilities, org hierarchy, and audit trails are the answer. These are genuine problems. Autonomous agents without constraints burn money and make irreversible decisions. Paperclip's feature set directly addresses this.

Soleur solves the knowledge problem: what should agents actually know and do? A marketing agent that does not understand brand voice, competitive positioning, and SEO strategy will produce content. Whether that content is good is a different question entirely. A legal agent without knowledge of the company's regulatory context will generate documents. Whether those documents are accurate and appropriately protective depends on domain depth that cannot be scaffolded from an org chart.

The gap in Paperclip's model is real: with 14,600 GitHub stars and no pre-built domain agents, the majority of setup time goes to defining agent behavior rather than extracting value from it. Clipmart will lower this barrier with company templates, but pre-built org structures still require users to fill in the actual domain intelligence -- the reasoning, the institutional context, the quality standards.

The gap in Soleur's model is equally real: the workflow lifecycle is purpose-built for Claude Code sessions initiated by a human. It does not offer Paperclip's heartbeat scheduling (agents running on autonomous cron cadences), per-agent budget enforcement, or multi-company governance. These are problems Soleur has not solved. Paperclip has.

## The Compounding Difference

The deepest distinction between the two platforms is not which features appear in each list. It is whether the system gets smarter with use.

Paperclip tracks tasks, budgets, and audit logs. This produces valuable operational data. It does not feed back into agent behavior. An agent that exceeded its budget and was automatically paused does not learn from the experience. The governance layer enforces rules it was given; it does not discover new rules through operation.

Soleur's compound step changes this. [From the project's engineering log]({{ site.url }}blog/why-most-agentic-tools-plateau/):

> An AI agent edited files outside its designated workspace. Two hours of work disappeared. The failure triggered a four-stage response: documentation, governance rule, enforcement hook, routing. The system can never make that mistake again.

The four-stage arc -- incident → rule → code-level guard → structural prevention -- has repeated across dozens of failure classes. The project's governance document started at 26 rules. It now contains 200+, each triggered by a real incident. When an agent makes a mistake, the compound step ensures neither that agent nor any agent will make it again. The knowledge base does not just record history -- it changes behavior.

Paperclip's rollback capabilities address damage after it occurs. Soleur's compound architecture prevents the damage by making recurrence structurally impossible. Both approaches are valuable; they operate at different points in the failure lifecycle.

| What you need | Paperclip | Soleur |
|---------------|-----------|--------|
| Governance and budget controls | Yes | Partial |
| Heartbeat scheduling (autonomous cron) | Yes | No |
| Rollback and approval gates | Yes | No |
| Pre-built domain agents | No | Yes |
| Compounding cross-domain knowledge base | No | Yes |
| Self-improving rules and guardrails | No | Yes |
| Workflow lifecycle (brainstorm through ship) | No | Yes |
| Open-source and local-first | Yes | Yes |
| Multi-company support | Yes | No |

## When Paperclip Is the Right Choice

Paperclip is the right choice when you need autonomous agent governance: the ability to run agents on schedules without user prompts, with defined budget ceilings and rollback controls. If you are building a zero-human company where agents operate continuously -- marketing agents posting on cadence, data agents refreshing reports overnight, operations agents monitoring spend -- Paperclip provides the governance layer that makes continuous autonomous operation safe.

If you already have domain agents -- built on Claude, Cursor, or another runtime -- and need orchestration infrastructure around them, Paperclip's org chart model and adapter ecosystem are a faster path than building governance from scratch.

Clipmart, when it ships, will make Paperclip more accessible for founders without existing agent libraries: downloadable company templates for marketing, e-commerce, software development, and other verticals. The quality of those templates will determine how much domain intelligence comes pre-built versus how much founders still need to supply.

## When Soleur Is the Right Choice

Soleur is the right choice when the quality of what agents produce matters as much as the fact that they run.

A competitive intelligence scan that misses new entrants is worse than no scan. A legal compliance audit that cites outdated regulations creates false confidence. A content strategy that ignores brand positioning produces noise. These are not problems that governance controls solve -- they are problems that require domain depth, institutional memory, and the kind of cross-domain coherence that only compounds over time.

Solo founders building companies where legal, financial, and product strategy decisions carry real stakes cannot delegate those decisions to autonomous cycles and expect competitive-quality output. Soleur's {{ stats.departments }}-domain coverage includes the three domains Paperclip's comparable tools most commonly omit: legal, finance, and product strategy -- precisely because those domains require careful human-in-the-loop review, not autonomous execution.

If you work in Claude Code, want a full AI organization that accumulates knowledge about your specific business, and want every decision to make subsequent decisions better, Soleur's compound architecture is built for that use case.

## Using Both

The complementary case is direct: Soleur provides domain intelligence; Paperclip provides governance infrastructure. Soleur's {{ stats.agents }} agents could run within Paperclip's orchestration framework -- heartbeat-scheduled, budget-capped, with rollback controls -- while contributing to a compounding knowledge base that Paperclip's governance layer does not supply.

Paperclip's adapter model demonstrates this is architecturally feasible. [v0.3.0 added adapters](https://github.com/paperclipai/paperclip/releases/tag/v0.3.0) for Cursor, OpenCode, and Pi. A Soleur adapter would extend this pattern: Soleur's agents run as managed workers within Paperclip's org chart, governed by Paperclip's budget and scheduling controls, while the compound step continues building cross-domain institutional memory after each session.

An official Soleur adapter for Paperclip does not yet exist. The combination represents the most complete zero-human company stack either platform could offer.

## FAQ

**Q: Is Paperclip a competitor to Soleur?**

Partially. Both target the AI company category, but they operate at different layers of the stack. Paperclip is governance infrastructure: org charts, budget controls, scheduling, rollback, audit logs. Soleur is domain intelligence: purpose-built agents, compounding knowledge base, workflow lifecycle. The most accurate framing is complementary -- Paperclip governs how agents run; Soleur defines what agents know and do. Direct competition begins if Clipmart ships company templates with deep, compounding domain intelligence, or if Soleur adds autonomous scheduling and budget enforcement.

**Q: Does Paperclip include domain agents for legal, marketing, or finance?**

No. Paperclip is agent-runtime-agnostic and does not include pre-built domain agents. It supports Claude, Cursor, OpenCode, Codex, Bash, and HTTP webhooks, but you supply your own agents and domain logic. The upcoming Clipmart feature will provide org structure templates for specific verticals, but the agents and their domain intelligence remain user-defined.

**Q: What is zero-human company orchestration?**

Zero-human company orchestration describes systems designed to run business operations autonomously -- agents handling scheduling, task execution, and decision-making without human intervention between cycles. Paperclip is built explicitly for this model, with heartbeat scheduling, approval gates, and budget controls to make continuous autonomous operation safe. Soleur takes a founder-in-the-loop approach: agents execute fully, but the founder makes decisions at key workflow gates rather than receiving a summary after the fact.

**Q: Can Soleur and Paperclip be used together?**

Yes. Soleur's domain agents could run as managed workers within Paperclip's orchestration framework, gaining heartbeat scheduling, per-agent budget controls, and rollback governance while contributing to the compounding knowledge base that Paperclip does not supply. An official adapter does not yet exist, but Paperclip's v0.3.0 adapter pattern (Cursor, OpenCode, Pi) makes this architecturally straightforward. The combination would represent the most complete open-source, self-hosted zero-human company stack available.

**Q: What are the main open-source AI company platforms in 2026?**

The two most prominent open-source, self-hosted platforms for AI company operation are Paperclip (MIT license, 14,600+ GitHub stars, governance infrastructure layer) and Soleur (open-source, {{ stats.agents }} agents, domain intelligence layer). Polsia is the fastest-growing proprietary alternative -- [$1.5M ARR with 2,000+ managed companies](https://www.teamday.ai/ai/polsia-solo-founder-million-arr-self-running-companies) as of March 2026 -- but is cloud-hosted, closed-source, and fully autonomous by design.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Is Paperclip a competitor to Soleur?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Partially. Both target the AI company category, but they operate at different layers of the stack. Paperclip is governance infrastructure: org charts, budget controls, scheduling, rollback, audit logs. Soleur is domain intelligence: purpose-built agents, compounding knowledge base, workflow lifecycle. The most accurate framing is complementary — Paperclip governs how agents run; Soleur defines what agents know and do."
      }
    },
    {
      "@type": "Question",
      "name": "Does Paperclip include domain agents for legal, marketing, or finance?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. Paperclip is agent-runtime-agnostic and does not include pre-built domain agents. It supports Claude, Cursor, OpenCode, Codex, Bash, and HTTP webhooks, but you supply your own agents and domain logic. The upcoming Clipmart feature will provide org structure templates for specific verticals, but the agents and their domain intelligence remain user-defined."
      }
    },
    {
      "@type": "Question",
      "name": "What is zero-human company orchestration?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Zero-human company orchestration describes systems designed to run business operations autonomously — agents handling scheduling, task execution, and decision-making without human intervention between cycles. Paperclip is built explicitly for this model. Soleur takes a founder-in-the-loop approach: agents execute fully, but the founder makes decisions at key workflow gates."
      }
    },
    {
      "@type": "Question",
      "name": "Can Soleur and Paperclip be used together?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. Soleur's domain agents could run as managed workers within Paperclip's orchestration framework, gaining heartbeat scheduling, per-agent budget controls, and rollback governance while contributing to the compounding knowledge base that Paperclip does not supply. An official adapter does not yet exist, but Paperclip's v0.3.0 adapter pattern makes this architecturally straightforward."
      }
    },
    {
      "@type": "Question",
      "name": "What are the main open-source AI company platforms in 2026?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The two most prominent open-source, self-hosted platforms for AI company operation are Paperclip (MIT license, 14,600+ GitHub stars, governance infrastructure layer) and Soleur (open-source, purpose-built domain agents, domain intelligence layer). Polsia is the fastest-growing proprietary alternative at $1.5M ARR with 2,000+ managed companies as of March 2026, but is cloud-hosted, closed-source, and fully autonomous by design."
      }
    }
  ]
}
</script>
