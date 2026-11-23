---
last_updated: 2026-11-01
last_reviewed: 2026-06-02
review_cadence: monthly
owner: CRO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
competitor: Notion AI (Custom Agents)
tier: 3
convergence_risk: High
---

# Battlecard: Notion AI (Custom Agents)

> **[2026-11-01 Cascade sync, index alignment only, no new web facts]** Corrected this card where it contradicted the current CI index (Notion data as of the 2026-06-08 scan):
> 1. **`convergence_risk` raised Medium-High to High** to match the index Tier 3 row.
> 2. **Notion is no longer "the highest convergence risk in Tier 3."** Cofounder (cofounder.co) is now rated Critical, the closest product match. See the [Cofounder battlecard](tier-3-cofounder.md).
> 3. The pricing row now reflects the index: **Custom Agents are Business/Enterprise-only**, with Free and Plus excluded. They run on credits at $10 per 1,000 from May 4. The index frames this paywall as **an acquisition window**, because it removes the free/Plus solo-founder long tail, which is Soleur's exact ICP.
>
> Notion facts were **not re-verified on 2026-11-01** (scan web tools blocked). The index's open item for the next scan is "Notion Custom Agents paywall changes."
>
> **Soleur-side caution:** the repo `LICENSE` is **Business Source License 1.1** (Soleur v3.1.0 and later; each version converts to Apache-2.0 four years after publication). Lines below that call Soleur "Apache-2.0" or "open source" are out of date. Say "source-available" until CRO/CLO reconcile the wording.

> **[2026-06-02 Review note]** Pricing status advanced past the beta window (per `knowledge-base/product/competitive-intelligence.md`, 2026-05-30 scan): the free Custom Agents beta **ended May 3, 2026**, and **credit-based pricing has been live since May 4**. Figures restated to past/active tense; the May-4 paywall transition is now an acquisition-monitoring window (watch whether agent seats drop post-paywall).

## Quick Facts

| Field | Value |
|-------|-------|
| **Product** | Notion 3.3 -- workspace tool with Custom Agents (launched Feb 24, 2026) |
| **Pricing** | $10/mo AI add-on per user. Custom Agents: free beta **ended May 3, 2026**; **credit-based pricing live since May 4** at $10/1,000 credits (variable per task complexity). Business and Enterprise plans only. |
| **User Base** | 35M+ users |
| **Domain Coverage** | Multi-domain workspace agents: docs, databases, projects, cross-app MCP integrations (Slack, Figma, Linear, HubSpot) |
| **Key Features** | Custom Agents (autonomous, scheduled, team-oriented). Multi-model (GPT-5.2, Claude Opus 4.5, Gemini 3). **NEW (Mar 3):** MiniMax M2.5 support (10x cheaper for basic tasks). 21,000+ agents built in early testing. 20-minute autonomous sessions. Cross-app MCP integrations now include Asana. |
| **Knowledge Persistence** | Workspace context (Notion pages, databases). Not structured for cross-domain business operations. |
| **Architecture** | Workspace-scoped agents. Cross-app via MCP. Team collaboration built in. |

## When You Will Encounter This

- A founder says "Notion already has Custom Agents for business tasks."
- Discussions about multi-domain AI agent platforms
- Comparisons of who is "closest to CaaS"
- Questions about Notion's distribution advantage (35M+ users)

## Differentiator Table

| Dimension | Notion AI | Soleur | Advantage |
|-----------|-----------|--------|-----------|
| **Domain scope** | Workspace-scoped: docs, databases, projects. Cross-app via MCP integrations. | 8 structured business domains: engineering, marketing, legal, operations, product, finance, sales, support | Soleur (structured business domains vs. generic workspace) |
| **Engineering depth** | No engineering workflow. No code review, architecture, or deployment agents. | 31+ engineering agents. Code review, architecture, security, infrastructure, DevOps. | Soleur |
| **Knowledge architecture** | Workspace pages and databases. Unstructured. | Structured knowledge base: brand guide, competitive intelligence, legal documents, business validation, learnings, decision records. Cross-domain references. | Soleur |
| **Workflow orchestration** | 20-minute autonomous sessions. Individual agent tasks. | Full business lifecycle: brainstorm-plan-implement-review-compound. Each stage has full domain context. | Soleur |
| **Distribution** | 35M+ users. Built into Notion. | Early stage. Requires Claude Code installation. | Notion |
| **Pricing** | $10/mo AI add-on; **Custom Agents Business/Enterprise-only**, $10/1,000 credits (from May 4, 2026) | Plugin free (source-available). Hosted Solo $49/mo (`pricing-strategy.md`). | Soleur for solo founders priced out of Notion agents |
| **Team collaboration** | Built in. Multi-user, shared workspace. | Solo-founder focused. Team features planned for paid tier. | Notion |
| **Multi-model** | GPT-5.2, Claude Opus 4.5, Gemini 3 | Claude models (via Claude Code) | Notion (flexibility) |
| **Autonomy** | Scheduled agents. 20-minute autonomous sessions. | Human-in-the-loop. Founder decides, agents execute. | Depends on preference |
| **Open source** | Proprietary | Apache-2.0 | Soleur |

## Talk Tracks

### "Notion Custom Agents do business tasks across domains."

**Response:** "Notion agents operate on your workspace -- pages, databases, and tasks. Soleur agents operate on your business. The difference is structure. Notion does not have a concept of 'brand guide that informs marketing content' or 'competitive intelligence that shapes pricing strategy' or 'legal audit that references the privacy policy.' Soleur's knowledge base creates these cross-domain connections by design. Notion agents work inside a workspace. Soleur agents run a company."

### "Notion has 35 million users. You have... one."

**Response:** "Notion has distribution. Soleur has depth. When Notion launched Custom Agents, 21,000 agents were built in early testing -- mostly for workspace automation (summarize this doc, update that database, post to Slack). That is valuable, but it is not Company-as-a-Service. Soleur's 63 agents are built for specific business functions -- not generic tasks but structured workflows for brand identity, competitive analysis, contract review, pricing strategy, and code architecture. Distribution wins eventually. But depth wins the early adopters who define the category."

### "Notion has MCP integrations with Slack, Figma, Linear, HubSpot."

**Response:** "Integrations connect to external data sources. That is plumbing, not intelligence. Soleur's value is not in connecting to HubSpot -- it is in having the competitive analysis inform the sales battlecards, the brand guide shape the marketing content, and the legal review catch compliance issues before they ship. Cross-app data access is useful. Cross-domain business intelligence is transformative. Notion has the first. Soleur has the second."

### "Won't Notion add engineering features?"

**Response:** "Notion's business is the workspace -- docs, databases, wikis, project management. Adding engineering agents (code review, architecture, deployment, CI/CD) would require building an entirely new product surface. Notion's product velocity is high, but their direction is workspace automation and team collaboration, not terminal-first engineering workflows. Even if they add basic code generation, they are unlikely to build the depth of engineering review that solo founders need -- 13+ specialized reviewers, architecture agents, security scanners, infrastructure planning."

## Objection Handling

| Objection | Response |
|-----------|----------|
| "I already use Notion for everything." | "Soleur is not replacing Notion. Notion is your workspace -- docs, projects, notes. Soleur is your AI organization -- agents that run your business. Use Notion for collaboration. Use Soleur for execution. They serve different functions." |
| "Notion has scheduled agents. Soleur requires manual invocation." | "Scheduled agents are useful for routine tasks. Soleur's human-in-the-loop design is intentional: the founder decides, agents execute. For high-stakes decisions (legal review, pricing strategy, competitive positioning), you want oversight, not automation. The brainstorm-plan-implement-review-compound lifecycle keeps the founder in control at every stage." |
| "I was using Notion agents on my Plus plan and lost access." *(added 2026-11-01 from index Tier 3 takeaway 4)* | "You're not alone. Since May 4, Custom Agents are Business/Enterprise-only and run on credits, so the solo-founder tier was priced out. Soleur is built for exactly that founder: agents across 8 departments working from a knowledge base you own in your own repo, on a flat Solo plan. You can keep Notion for docs and use Soleur to do the work." |
| "Notion is $10/month. Soleur will cost more." | "Soleur's core is free and open source -- 63 agents, 62 skills, Apache-2.0. The planned paid tier ($49/month) covers hosted infrastructure and cloud-synced knowledge base. Compare $49/month for an AI organization running 8 business departments against the $790-2,790/month a solo founder typically spends on separate tools and services." |

## Convergence Watch

Review monthly. Notion is a High convergence risk in Tier 3. *(Corrected 2026-11-01: an earlier version called Notion the highest; Cofounder is now rated Critical.)* Monitor closely.

| Trigger | Current Status (2026-06-02) | Action if Triggered |
|---------|---------------------------|-------------------|
| Notion adds engineering agents | No signal | Major escalation. Publish comparison immediately. Emphasize engineering depth (13+ review agents, architecture, security) vs. Notion's likely shallow offering. |
| Notion positions for solo founders | Currently team-focused (Business/Enterprise plans only) | Update positioning. Emphasize terminal-first workflow, open source, and compounding knowledge base designed for one-person operations. |
| Notion adds persistent business-scoped memory | Workspace context only | Evaluate whether Notion's memory architecture compounds across domains like Soleur's. If yes, differentiate on engineering depth and open source. |
| Notion hits 50,000+ custom agents | 21,000+ in early testing | Category is validated. Lean into CaaS category definition to differentiate agent-for-tasks (Notion) from agent-as-organization (Soleur). |
| Notion post-beta pricing makes autonomous agents cheap | **Beta ended May 3; credit pricing live since May 4** at $10/1,000 credits. MiniMax M2.5 at 10x cheaper for basic tasks. | If credit costs are low enough for heavy autonomous use, Notion becomes a cost-competitive multi-domain option. Emphasize engineering depth, structured business knowledge, and open source. Monitor post-paywall seat retention. |
| Notion acquires engineering AI company | No signal | Assess acquisition. Update battlecard and comparison content immediately. |

---

_Updated: 2026-11-01 (downstream-sync cascade: convergence risk, Tier 3 ranking, paywall framing aligned to index; no new web facts). Previously 2026-06-02. Source: competitive-intelligence.md (2026-11-01 index; Notion data as of 2026-06-08)._
