---
title: "Loop Engineering for Your Whole Company, Not Just Your Codebase"
seoTitle: "Loop Engineering Beyond Code: Run a Whole Company on Agent Loops"
date: 2026-06-12
description: "Addy Osmani coined loop engineering for code. Soleur applies the same architecture — automations, skills, connectors, memory — across every department."
tags:
  - loop-engineering
  - agentic-engineering
  - solo-founder
  - company-as-a-service
---

In June 2026, Addy Osmani — a director on Google's Cloud AI team — gave a name to a shift that was already underway. He called it **[loop engineering](https://addyo.substack.com/p/loop-engineering)**, and his one-line definition is the clearest framing of the idea anyone has written:

> "Loop engineering is replacing yourself as the person who prompts the agent. You design the system that does it instead."

The leverage has moved. The skill that mattered last year was writing a good prompt. The skill that matters now is designing the system that prompts the agent for you — on a schedule, in isolation, with memory that survives between runs and a second agent that checks the first one's work.

This post does two things. First, it credits Osmani's framework and the engineers who shaped it. Then it extends the idea past the boundary Osmani drew around it — because loop engineering does not stop at code.

## What Osmani named

Osmani's essay lays out five building blocks for systems that prompt agents on their own, plus a sixth element that ties them together:

1. **Automations** — scheduled tasks that discover and triage work on a cadence, without a human kicking them off.
2. **Worktrees** — isolated working directories that let several agents run in parallel without colliding on the same files.
3. **Skills** — documented procedural knowledge, captured once so the agent never has to be re-taught the same task.
4. **Connectors** — integrations, over the [Model Context Protocol](https://modelcontextprotocol.io/), that give agents access to real tools and systems.
5. **Sub-agents** — a separate agent that verifies the work, so the maker never grades its own homework.

The sixth is **external memory** — markdown files, issue boards, a knowledge base — because models forget everything between sessions, and the loop only compounds if state outlives the run.

He is not alone in seeing the shift. Boris Cherny, who leads Claude Code, describes his own working day this way (as quoted in Osmani's essay):

> "I don't prompt Claude anymore. I have loops running that prompt Claude and figuring out what to do. My job is to write loops"

Peter Steinberger puts the same idea as a directive (also quoted in the essay):

> "You shouldn't be prompting coding agents anymore. You should be designing loops that prompt your agents."

Osmani closes by keeping the human in frame: **"Build the loop. But build it like someone who intends to stay the engineer, not just the person who presses go."** That instinct — automate the prompting, keep the judgment — is exactly right, and it is the spirit this post extends.

## The boundary Osmani drew

Read the essay closely and you will notice it lives entirely inside software engineering. Every example is a coding agent: fixing a failing test, triaging a pull request, refactoring a module. That is the natural place for loop engineering to start, because engineers built the substrate — worktrees, skills files, the Model Context Protocol — for their own work first.

But nothing in the architecture is specific to code. A scheduled automation does not care whether it triages a bug or a churn signal. A skill file is as happy documenting a refund policy as a migration. External memory is as useful to a legal review as to a release. The six blocks are domain-neutral; only the examples were not.

## Loop engineering for the whole company

Soleur is what loop engineering looks like when you stop scoping it to the codebase. It runs the same six pieces Osmani named — across marketing, sales, legal, finance, operations, support, and product, not just engineering.

Four of the six already span every department:

- **External memory** is the foundation, and it is the strongest piece. A single git-committed knowledge base holds the state of the whole company — brand guides, deal notes, compliance posture, plans, learnings — and every agent in every department reads and writes it. State outlives the run by default, because it is version-controlled, auditable, and yours.
- **Skills** number more than 80 documented procedures, spanning eight departments. A legal-document generator, a competitive-intelligence scan, a campaign calendar, a budget analysis — each one captured once.
- **Connectors** reach real systems over MCP. Cloudflare, Stripe, and Vercel ship in the box, with more available — so an agent can read live revenue or change a DNS record, not just talk about it.
- **Worktrees** give every agent an isolated place to work in parallel, the same substrate Osmani describes, available to any department's work.

The remaining two — scheduled automations that dispatch agents on their own, and the maker/checker split where a separate agent verifies the work — run today in engineering, and Soleur is extending them outward across the company. That is the honest shape of it: the memory, skills, and connectors are company-wide now; the autonomous dispatch and verification are proven where they started and generalizing from there.

This is the difference worth naming. Osmani's loop replaces *you, the engineer who prompts the coding agent*. Soleur's loop replaces *you, the founder who prompts every department* — the one person doing marketing on Monday, finance on Tuesday, and legal review whenever the contract lands. Same architecture. Wider blast radius.

If you want the ground underneath this — why the leverage moved from prompting to system design in the first place — that is the larger story of [agentic engineering](/agentic-engineering/).

## Build the loop. Run the company.

Osmani's instinct is the right one to keep: build the loop, but stay the engineer who presses go on purpose, not by reflex. The judgment stays human; the prompting becomes a system you design. Soleur takes that instinct and points it at the whole org chart — an AI organization where the loops run the departments and you run the loops.

The leverage point Osmani identified for code is the same leverage point for a company. The question is no longer how to prompt your agents. It is which loops to build first.

---

*Soleur is not affiliated with or endorsed by Addy Osmani, Boris Cherny, Peter Steinberger, Google, or Anthropic. "Loop engineering" was coined by Addy Osmani; the quotes above appear in his essay and are reproduced here with attribution. Source: [Addy Osmani, "Loop Engineering" (June 2026)](https://addyo.substack.com/p/loop-engineering).*

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is loop engineering?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Loop engineering, a term coined by Addy Osmani in June 2026, is the practice of designing systems that prompt AI agents autonomously instead of prompting them yourself by hand. Its building blocks are scheduled automations, isolated worktrees, documented skills, MCP connectors, verifier sub-agents, and external memory that persists state across sessions."
      }
    },
    {
      "@type": "Question",
      "name": "Can loop engineering work outside of code?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. Osmani's essay scopes loop engineering to software engineering, but the six building blocks are domain-neutral. Soleur applies the same architecture across marketing, sales, legal, finance, operations, support, and product. External memory, skills, and MCP connectors span every department today; autonomous scheduling and maker/checker verification run in engineering and are extending across the company."
      }
    },
    {
      "@type": "Question",
      "name": "Is Soleur affiliated with Addy Osmani, Google, or Anthropic?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. Soleur is not affiliated with or endorsed by Addy Osmani, Boris Cherny, Peter Steinberger, Google, or Anthropic. The term loop engineering was coined by Addy Osmani, and the quotes from Boris Cherny and Peter Steinberger appear in Osmani's essay, reproduced here with attribution."
      }
    }
  ]
}
</script>
