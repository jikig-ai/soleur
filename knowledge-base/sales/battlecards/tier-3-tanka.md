---
last_updated: 2026-11-01
last_reviewed: 2026-06-02
review_cadence: monthly
owner: CRO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
competitor: Tanka
tier: 3
convergence_risk: Medium
---

# Battlecard: Tanka

> **[2026-11-01 Cascade sync, index alignment only, no new web facts]** Corrected this card where it contradicted the current CI index (Tanka data as of the 2026-06-08 scan):
> 1. **Pricing is Free (<50 members) / Plus $29 / Pro $199.** The "$299/month for teams 50+" figure is superseded, and the objection and talk tracks that relied on it were rewritten.
> 2. **EverMemOS is now fully open source.** The index reads this as commoditizing the memory-engine layer. Soleur's edge is the git-tracked, founder-readable, lifecycle-tied KB, not memory technology.
> 3. **The Fundraising Agent tracks founder interactions across Slack, Gmail and Notion** to build an institutional KB.
>
> SOC 2 / ISO 27001 and the Agent Store status come from the 2026-03-12 intake and are **not in the current index**; verify before citing. Tanka facts were **not re-verified on 2026-11-01** (scan web tools blocked).
>
> **Soleur-side caution:** the repo `LICENSE` is **Business Source License 1.1** (Soleur v3.1.0 and later; each version converts to Apache-2.0 four years after publication). Lines below that call Soleur "open source, Apache-2.0" are out of date. Say "source-available" until CRO/CLO reconcile the wording. For a three-way "memory-native" comparison, see the [Cofounder battlecard](tier-3-cofounder.md).

## Quick Facts

| Field | Value |
|-------|-------|
| **Product** | Tanka -- "AI Co-Founder" / memory-native OS. CEO Kisson Lin, Redwood City. #5 Product Hunt 2025 (1,433 upvotes). |
| **Pricing** | **Free (<50 members) / Plus $29 / Pro $199** (per CI index, 2026-06-08). |
| **Domain Coverage** | Communication-centric: messaging (Slack, WhatsApp, Gmail, Telegram), calendar, content, sales, product, data. **Fundraising Agent** tracks founder interactions across Slack/Gmail/Notion to build an institutional KB. |
| **Key Features** | **EverMemOS** (launched Sept 29 2025; structured long-term memory, agentic multi-round recall, hybrid retrieval BM25+embedding+RRF, Milvus+ES+Mongo+Redis), **now fully open source**. Multi-agent collaboration. Agent Store (planned, per 2026-03-12 intake). SOC 2 Type II and ISO 27001 certified (2026-03-12 intake; not in current index). |
| **Knowledge Persistence** | Core differentiator. EverMemOS creates persistent knowledge graphs from conversations and interactions. Memory compounding is their explicit moat claim. |
| **Architecture** | Cloud-hosted. Communication-first. Memory-native. Integrates with messaging and workspace tools. |

## When You Will Encounter This

- A founder asks "What about Tanka? They also do memory compounding."
- Discussions about persistent AI memory and knowledge graphs
- Comparisons of "AI co-founder" platforms
- Evaluations of which memory architecture is more robust

## Differentiator Table

| Dimension | Tanka | Soleur | Advantage |
|-----------|-------|--------|-----------|
| **Memory architecture** | EverMemOS -- persistent knowledge graphs built from conversations and interactions | Structured knowledge base -- brand guide, competitive intel, legal docs, learnings, decision records, cross-domain references | Different approaches. Tanka: conversation-derived. Soleur: structured business documents. |
| **Engineering depth** | No engineering agents. No code review, architecture, or deployment. | 31+ engineering agents. Full code lifecycle. | Soleur |
| **Domain scope** | Communication-centric: messaging, calendar, content, sales. Fundraising agent. | 8 structured business domains including engineering and legal. | Soleur (breadth + engineering) |
| **Memory scope** | Conversations and interactions. Communication-derived intelligence. | Business operations across all domains. Cross-domain references (brand guide informs marketing, competitive intel informs pricing). | Soleur (business-scoped vs. communication-scoped) |
| **Workflow orchestration** | Agent collaboration on communication tasks. No business lifecycle management. | Brainstorm-plan-implement-review-compound lifecycle across all domains. | Soleur |
| **Compliance** | SOC 2 Type II, ISO 27001 | Open source (Apache-2.0). Self-hosted. Data stays on your machine. | Depends on need (enterprise compliance vs. local-first control) |
| **Pricing** | Free (<50 members) / Plus $29 / Pro $199. | Plugin free (source-available). Hosted Solo $49 / Startup $149 / Scale $499 (`pricing-strategy.md`). | Tanka at entry (Free, $29). Compare on scope, not price. |
| **Platform** | Cloud-hosted. Web and mobile integrations. | Terminal-first via Claude Code. Local-first. | Depends on preference |
| **Agent Store** | Planned. Vertical agents for GTM, hiring, product development. | 61 built-in agents. No marketplace needed -- the organization ships complete. | Soleur (integrated vs. marketplace) |

## Talk Tracks

### "Tanka does memory compounding too."

**Response:** "Tanka and Soleur both believe memory compounding is the fundamental moat. The difference is scope. Tanka builds knowledge graphs from conversations -- Slack messages, WhatsApp threads, emails. That is communication intelligence. Soleur builds structured business knowledge -- brand guides, competitive analyses, legal documents, architectural decisions, product roadmaps -- with explicit cross-domain references. When Soleur's marketing agents write content, they pull from the brand guide, the competitive landscape, and the product specs simultaneously. Tanka's memory is deep on what was said. Soleur's memory is deep on what was decided and why."

### "Tanka has an Agent Store with specialized agents."

**Response:** "Agent Store is planned but not shipped. When it launches, it will likely follow a marketplace model: individual agents built by different teams, each with their own context and conventions. Soleur's 63 agents ship as an integrated organization. They share institutional memory, follow consistent conventions, and orchestrate across domains. The difference between a marketplace of agents and an organization of agents is the same as the difference between a freelancer marketplace and a company. One assembles. The other compounds."

### "Tanka has SOC 2 and ISO 27001 certification."

**Response:** "For enterprise compliance requirements, those certifications matter. Soleur takes a different approach to trust: open source. Apache-2.0 license. Every agent, every skill, every line of code is inspectable. Your data stays on your machine -- local-first, not cloud-hosted. For solo founders, the question is whether you trust a certification or whether you trust code you can read. Both are valid answers for different contexts."

### "Tanka integrates with Slack, WhatsApp, Gmail, Telegram."

**Response:** "Tanka is built around communication channels. That makes sense for their thesis -- memory compounding from conversations. Soleur is built around the terminal and the codebase. That makes sense for our thesis -- an AI organization that runs alongside the founder's work. Different starting points, different architectures, different strengths. If your primary need is communication intelligence, Tanka is purpose-built for it. If your need is a full AI organization with engineering depth and cross-domain business operations, Soleur covers more ground."

## Objection Handling

| Objection | Response |
|-----------|----------|
| "Tanka's memory is more natural -- it learns from conversations automatically." | "Automatic learning from conversations is powerful for communication patterns. Soleur's knowledge base requires more intentional input -- brainstorms produce structured documents, reviews capture learnings, compound sessions formalize patterns. The trade-off: Soleur's knowledge is structured and cross-referenced, which enables explicit cross-domain reasoning. Tanka's knowledge is implicit and derived. Both compound. They compound different things." |
| "Tanka is building fundraising agents. That is business operations." | "The fundraising agent validates that Tanka is moving toward business operations beyond communication. Monitor this closely. Today, Tanka's business agents (fundraising, content, sales) are communication-anchored -- they work through messaging interfaces. Soleur's agents are workflow-anchored -- they produce documents, review code, analyze competitors, and generate artifacts. If Tanka adds engineering agents and structured knowledge, the overlap increases significantly." |
| "Tanka is free. Why pay for Soleur?" *(rewritten 2026-11-01: Tanka pricing is now Free / Plus $29 / Pro $199)* | "Tanka's free tier and $29 Plus are cheaper than Soleur's $49 Solo plan, and that's a fair point. The question is what you're paying for. Tanka is built around your conversations: Slack, Gmail, WhatsApp. Soleur runs the company across 8 departments, including engineering you actually ship, legal and finance. Its knowledge base is the work itself, kept verbatim in your own git repo. If you mainly need communication memory, Tanka is good value. If you need the work done and a record of what you decided, Soleur covers more ground." |
| "Tanka open-sourced EverMemOS. Their memory tech is better and free." *(added 2026-11-01 from index Tier 3 takeaway 5)* | "Open-sourcing EverMemOS is a real contribution, and it means the memory engine itself is becoming a commodity. That's why Soleur doesn't compete on memory technology. We compete on what the memory *is*: plain, founder-readable files in your own git repo, tied to every stage of the brainstorm → plan → work → review → compound lifecycle, and shared across every department. A retrieval engine over your conversations is different from a reviewed, versioned record of your company's decisions." |

## Convergence Watch

Review monthly. Tanka is the closest analog to Soleur's compounding knowledge thesis.

| Trigger | Current Status (2026-03-12) | Action if Triggered |
|---------|---------------------------|-------------------|
| Tanka adds engineering agents | No signal. Agent Store planned. | Major escalation. Tanka + engineering = direct CaaS competitor. Publish comparison content. Emphasize engineering depth and structured knowledge architecture. |
| Tanka launches pricing | **Launched (index 2026-06-08):** Free (<50 members) / Plus $29 / Pro $199. | Compare on scope, not price; Tanka is cheaper at entry. Monitor for tier changes. |
| Tanka's open-source memory engine is adopted by other CaaS players | EverMemOS fully open source (index 2026-06-08). | Memory engine is commoditized. Keep Soleur's memory claims about git-tracked, founder-readable, lifecycle-tied KB, not retrieval tech. |
| Tanka's Agent Store goes live | Planned, not shipped. | Evaluate agent breadth and quality. Monitor whether marketplace agents achieve cross-domain coherence or remain siloed. |
| Tanka claims "Company-as-a-Service" or similar framing | Not detected. Current framing: "AI co-founder platform", "memory-native OS." | Accelerate CaaS category content. Establish Soleur as the category definer. |
| Tanka adds structured business document management | Communication-only. No brand guides, competitive intel, or structured business knowledge. | Re-evaluate memory architecture comparison. If Tanka adds structured business knowledge, the differentiation narrows to engineering depth and workflow orchestration. |

---

_Updated: 2026-11-01 (downstream-sync cascade: pricing, EverMemOS open-source, Fundraising Agent aligned to index; no new web facts). Previously 2026-03-12. Source: competitive-intelligence.md (2026-11-01 index; Tanka data as of 2026-06-08)._
