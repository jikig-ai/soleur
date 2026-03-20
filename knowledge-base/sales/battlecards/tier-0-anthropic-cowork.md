---
last_updated: 2026-03-12
last_reviewed: 2026-03-12
review_cadence: monthly
competitor: Anthropic Cowork Plugins
tier: 0
convergence_risk: Critical
---

# Battlecard: Anthropic Cowork Plugins

## Quick Facts

| Field | Value |
|-------|-------|
| **Product** | Cowork -- Anthropic's AI work product (web/desktop), with 10 department-specific plugin categories. **NEW (March 9, 2026):** Cowork technology now powers Microsoft Copilot Cowork in M365. |
| **Pricing** | Included with Claude Pro ($20/mo), Team ($25/seat/mo), Enterprise (custom). Microsoft Copilot Cowork: part of M365 E7 Frontier Suite (pricing TBD). |
| **Domain Coverage** | HR, Design, Engineering, Operations, Financial Analysis, Investment Banking, Equity Research, Private Equity, Wealth Management, Brand Voice. 15+ enterprise connectors. |
| **Distribution** | Bundled with every Claude subscription. Private marketplace for Enterprise. **NEW:** Dual distribution via Anthropic direct + Microsoft 365 (400M+ users). |
| **Key Feature** | Plugin Create for custom agents. Enterprise connectors (Google Workspace, DocuSign, Apollo, Clay, FactSet, LegalZoom, Harvey, S&P Global, LSEG, Common Room, Slack). Microsoft Copilot Cowork: background task execution across Outlook, Teams, Excel. |
| **Knowledge Persistence** | None. Stateless per session. No compounding memory across conversations. |
| **Architecture** | Individual plugins execute isolated tasks. No cross-plugin orchestration or shared context. Microsoft Copilot Cowork adds multi-step plan execution but still no persistent cross-domain memory. |

## When You Will Encounter This

- A founder says "Cowork already has marketing/legal/ops plugins -- why do I need Soleur?"
- A founder evaluates whether the free bundled option is good enough
- Enterprise buyers compare Soleur's capabilities against Anthropic's first-party offering
- Discussions about platform dependency risk ("Anthropic could build everything you do")

## Differentiator Table

| Dimension | Anthropic Cowork | Soleur | Advantage |
|-----------|-----------------|--------|-----------|
| **Knowledge persistence** | Stateless. Each session starts fresh. | Compounding. Knowledge base grows across every session. The 100th session is dramatically more productive than the 1st. | Soleur |
| **Cross-domain coherence** | Plugins are siloed. Marketing plugin does not know what legal plugin produced. | 61 agents share context across 8 domains. Brand guide informs marketing content. Competitive analysis shapes pricing. | Soleur |
| **Workflow orchestration** | Individual task execution. No lifecycle management. | Brainstorm-plan-implement-review-compound lifecycle with full domain context at each stage. | Soleur |
| **Pricing** | Free with Claude subscription ($20-25/mo) | Free (open source). Paid tier planned for hosted features. | Cowork (free bundled) |
| **Distribution** | Built into Anthropic's platform. Discoverable by every Claude user. | Claude Code plugin. Requires explicit installation. | Cowork (bundled) |
| **Enterprise connectors** | Google Workspace, DocuSign, Apollo, Clay, FactSet, LegalZoom | Terminal-first. Integrates through Claude Code MCP ecosystem. | Cowork (enterprise) |
| **Customization** | Plugin Create for custom single-purpose agents | 61 pre-built agents with opinionated workflows, configurable through AGENTS.md | Depends on use case |
| **Engineering depth** | Engineering plugins added Feb 2026. Breadth unknown. | 31+ engineering agents covering code review, architecture, security, infrastructure, DevOps, and more. | Soleur |
| **Open source** | Proprietary. Plugin templates on GitHub but core is closed. | Apache-2.0. Full source code. Inspect every agent and skill. | Soleur |

## Talk Tracks

### "Cowork has plugins for all those domains."

**Response:** "Cowork plugins execute individual tasks. Soleur orchestrates workflows across domains with compounding memory. Here is the difference: when you ask Cowork's marketing plugin to write launch content, it starts from scratch every time. When Soleur's marketing agents write launch content, they pull from the brand guide, reference the competitive landscape, align with the product roadmap, and improve based on what worked last time. That cross-domain context flow -- where every department informs every other department -- does not exist in Cowork's architecture. Plugins are nouns. Soleur's workflows are verbs."

### "It's free with my Claude subscription. Why would I pay for Soleur?"

**Response:** "Soleur's core is also free -- Apache-2.0, open source. The question is not about price. It is about whether you want a collection of independent tools or an integrated organization. A solo founder using Cowork plugins is still manually connecting the dots between domains -- 'remember that brand guide when you write this marketing content' and 'look at the competitive analysis before pricing.' Soleur's knowledge base does that automatically. If you are building a real company, the compounding memory alone justifies the difference."

### "Anthropic controls the model. Won't they make Soleur obsolete?"

**Response:** "Anthropic controls the model and the distribution surface. They can build domain-specific plugins faster than anyone. What they have not built -- and what their architecture does not support -- is cross-domain institutional memory. Cowork plugins are stateless by design. Each conversation starts fresh. Soleur's knowledge base compounds across every session, every domain, every decision. That architectural difference is not a feature gap Anthropic can close with a plugin update. It requires a different design philosophy. Could they build it? Absolutely. Have they? No. And the compounding advantage grows every day they do not."

### "What if Anthropic adds persistent memory to Cowork?"

**Response:** "Then the competitive landscape changes materially and we adjust. But persistent memory across a plugin marketplace is an architectural challenge, not a feature toggle. Each plugin would need to read and write to a shared knowledge graph with conflict resolution, access control, and cross-domain coherence. Soleur has been building this architecture from day one with a single integrated system. A plugin marketplace adding memory retroactively faces a fundamentally harder problem. If Anthropic ships it, Soleur's response is to emphasize workflow orchestration depth, open-source transparency, and the local-first model. The knowledge you build is yours, on your machine, not locked in Anthropic's cloud."

## Objection Handling

| Objection | Response |
|-----------|----------|
| "Cowork has enterprise connectors I need (Google Workspace, DocuSign)." | "Soleur integrates through Claude Code's MCP ecosystem, which supports custom tool connections. For enterprise data sources, Cowork has a head start. For solo founders building companies, the question is whether you need DocuSign integration or whether you need your legal review to reference your brand guide and competitive position. Different needs." |
| "Plugin Create lets me build custom agents." | "Plugin Create builds single-purpose agents. Soleur provides 61 agents that share institutional memory across 8 domains. The question is whether you want to build your own AI organization from scratch or deploy one that already works." |
| "I trust Anthropic more than a solo developer." | "Fair. Soleur is open source -- Apache-2.0. Every agent, every skill, every line of code is inspectable. The platform is designed, built, and shipped using itself: 420+ merged PRs across all 8 domains. Trust the code, not the brand." |

## Convergence Watch

Review monthly. If any of these triggers fire, escalate to marketing strategy review.

| Trigger | Current Status (2026-03-12) | Action if Triggered |
|---------|---------------------------|-------------------|
| Anthropic adds persistent memory to Cowork | No signal | Update battlecard. Publish comparison article. Shift positioning to workflow orchestration + open source. |
| Anthropic uses "Company-as-a-Service" framing | No signal | Accelerate CaaS category content. Establish Soleur as the originator of the term. |
| Cowork plugins gain cross-plugin orchestration | No signal | Update battlecard. Evaluate whether Soleur's orchestration depth still differentiates. |
| Anthropic launches private plugin marketplace widely | Available for Enterprise tier | Monitor adoption. If Cowork marketplace threatens plugin distribution, evaluate riding Cowork distribution. |
| Claude Code native features absorb Soleur engineering agents | Partial -- auto-memory, Plan subagent, MCP deduplication | Track feature parity. Differentiate on non-engineering domains and cross-domain coherence. |
| Microsoft Copilot Cowork expands beyond M365 workflow tasks | Research Preview (Mar 2026). Broader rollout late March. Enterprise-targeted. | Monitor scope expansion. If Copilot Cowork adds engineering or solo-founder features, the dual distribution surface (Anthropic + Microsoft) becomes a direct threat. |
| Copilot Cowork adds persistent memory | No signal. Session-scoped task execution. | Would represent Anthropic enabling memory through a partner surface before their own. Major escalation. |

---

_Updated: 2026-03-12. Source: competitive-intelligence.md (2026-03-12)._
