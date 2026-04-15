---
title: "Soleur vs. Paperclip: Domain Intelligence vs. AI Company Orchestration"
type: comparison
publish_date: "2026-04-15"
channels: discord, x, bluesky, linkedin-company
status: published
---

## Discord

Two open-source AI company platforms. Different layers of the stack.

Paperclip: org charts, budget controls, heartbeat scheduling, governance. 14.6k GitHub stars. You bring your own agents.

Soleur: 63 agents, 62 skills, 9 departments, compounding knowledge base. You bring your own orchestration.

The comparison breaks down what each actually solves -- and whether you need both.

https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=discord&utm_medium=community&utm_campaign=soleur-vs-paperclip

---

## X/Twitter Thread

Paperclip hit 14.6k GitHub stars building "zero-human company" infrastructure. Soleur runs 63 agents across 9 departments with a compounding knowledge base. Both are open-source. They're solving opposite halves of the same problem.

2/ Paperclip is governance infrastructure: org charts, heartbeat scheduling, per-agent budget caps, rollback controls. It does not include agents or domain knowledge. You bring your own.

3/ Soleur is domain intelligence: legal, marketing, finance, engineering, product, ops, sales, support. 63 purpose-built agents. A knowledge base that compounds with every session. No autonomous scheduling.

4/ The gap is mutual. Paperclip governs how agents run. Soleur defines what agents know and do. Neither is complete without what the other provides.

5/ The deeper difference: Paperclip tracks what agents do. Soleur changes agent behavior based on what agents learn. Rollback vs. prevention. Governance vs. compounding.

6/ Full breakdown of where they overlap, where they differ, and when to use both:

https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=x&utm_medium=social&utm_campaign=soleur-vs-paperclip

#solofounder

---

## IndieHackers

**Title:** Comparing two open-source AI company platforms: Paperclip (14.6k stars, governance infra) vs. Soleur (63 agents, compounding knowledge base)

**Body:**

Building in public, so documenting how Soleur stacks up against Paperclip -- the other major open-source platform in the "AI runs your company" space.

The comparison surprised me. They're not direct competitors. They're solving opposite halves of the same problem.

Paperclip is infrastructure: org charts, heartbeat scheduling, per-agent monthly budgets, rollback controls, audit logs. 14,600+ GitHub stars. MIT license. Agent-runtime-agnostic -- you connect Claude, Cursor, OpenCode, Bash, or HTTP webhooks. Upcoming Clipmart feature will add pre-built company templates for marketing, e-commerce, software dev, and sales verticals.

What Paperclip does not include: agents. Domain knowledge. Any built-in understanding of what a legal compliance audit should cover or how a competitive intelligence scan should be structured.

Soleur is the intelligence layer: 63 agents across 9 departments (engineering, marketing, legal, finance, ops, product, sales, support, and more). Every agent carries domain knowledge. Every session compounds into a git-tracked knowledge base. The brand guide the marketing agent creates informs the content the growth agent writes. The legal audit references the privacy policy the CLO previously documented.

What Soleur does not include: autonomous scheduling, per-agent budget enforcement, rollback governance. These are real gaps.

The combination case is direct: run Soleur's agents as managed workers inside Paperclip's governance framework. No official adapter exists yet, but Paperclip's v0.3.0 added Cursor and OpenCode adapters, so the pattern is there.

Full breakdown here: https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=indiehackers&utm_medium=community&utm_campaign=soleur-vs-paperclip

---

## Reddit

**Subreddit:** r/SaaS, r/solopreneur, r/artificial
**Title:** Comparing two open-source "AI runs your company" platforms -- one does governance, one does domain intelligence

**Body:**

There are now two serious open-source platforms positioning as AI company infrastructure for solo founders:

**Paperclip** (14.6k GitHub stars, MIT): Org charts with reporting lines, heartbeat scheduling, per-agent monthly budgets with auto-pause, rollback and approval gates, immutable audit logs. Agent-runtime-agnostic -- you connect whatever LLM runtime you want. Upcoming "Clipmart" feature will offer pre-built company templates for marketing/e-commerce/software dev verticals. Does not include agents or domain knowledge -- you supply those.

**Soleur** (open-source, Apache 2.0): 63 agents across 9 departments including legal, finance, and product strategy. Compounding knowledge base where every session writes back to a shared git-tracked directory. The brand guide the marketing agent creates is what the content agent reads from. Legal agents reference compliance decisions made in prior sessions. No autonomous heartbeat scheduling or per-agent budget controls.

The interesting thing: they're more complementary than competitive. Paperclip governs how agents run. Soleur defines what agents know and do. The combination case is obvious -- Soleur agents running inside Paperclip's governance framework.

Wrote a full breakdown with a feature comparison table:
https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=reddit

---

## Hacker News

**Title:** Soleur vs. Paperclip: AI company governance vs. domain intelligence compared
**URL:** https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=hackernews&utm_medium=community&utm_campaign=soleur-vs-paperclip

---

## LinkedIn Personal

Two open-source AI company platforms both claim to run a company with minimal humans. I compared them. The conclusion surprised me.

Paperclip (14.6k GitHub stars): org charts, heartbeat scheduling, per-agent budget caps, rollback controls. Governance infrastructure. No agents included -- you bring your own domain logic.

Soleur (what I've been building): 63 agents across 9 departments, compounding knowledge base. Every session writes back to a shared knowledge base that every agent reads from. Legal decisions reference prior compliance work. Brand strategy informs content. No autonomous scheduling or budget enforcement.

The interesting finding: they're not competing for the same problem. Paperclip governs how agents run. Soleur defines what agents know and do.

The deeper difference is whether the system gets smarter over time. Paperclip tracks what agents do -- budget, audit logs, task history. Valuable operational data. It does not change agent behavior based on that data.

Soleur's compound step does. Failures get captured, routed back to the specific agents that were active, and in critical cases promoted to mechanical enforcement hooks. The governance document started at 26 rules. It's at 200+ now. Each rule is a scar from a real incident. The system can't make those mistakes again -- not because agents are reminded not to, but because the behavior is structurally prevented.

Rollback (Paperclip) vs. prevention (Soleur). Both are valid. They operate at different points in the failure lifecycle.

The combination case is the honest recommendation: run Soleur's domain agents inside Paperclip's governance framework. No official adapter yet, but Paperclip's v0.3.0 adapter model makes it feasible.

Full comparison with feature table: https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=soleur-vs-paperclip

#solofounder #buildinpublic

---

## LinkedIn Company Page

Soleur published a detailed comparison with Paperclip -- the other major open-source AI company platform targeting solo founders.

The two platforms operate at different layers of the stack. Paperclip provides governance infrastructure: org charts, heartbeat scheduling, per-agent budget controls, rollback capabilities, and audit logs. It is agent-runtime-agnostic -- users bring their own agents and domain logic. Soleur provides domain intelligence: 63 purpose-built agents across 9 departments with a compounding knowledge base that accumulates institutional memory across every session and every domain.

The core distinction: Paperclip governs how agents run. Soleur defines what agents know and do.

The article covers where each platform's model has gaps, the case for using both together, and a full feature comparison table.

https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=linkedin-company&utm_medium=social&utm_campaign=soleur-vs-paperclip

#AIagents #solofounder

---

## Bluesky

Paperclip: org charts, budgets, heartbeat scheduling for autonomous agents. 14.6k stars. MIT. You bring your own agents.

Soleur: 63 agents, 9 departments, compounding knowledge base. You bring your own governance.

Neither is complete. The combination case is the honest answer.

https://soleur.ai/blog/soleur-vs-paperclip/?utm_source=bluesky&utm_medium=social&utm_campaign=soleur-vs-paperclip
