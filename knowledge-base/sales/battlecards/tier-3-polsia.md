---
last_updated: 2026-06-08
last_reviewed: 2026-06-08
review_cadence: monthly
owner: CRO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
competitor: Polsia
tier: 3
convergence_risk: High
---

# Battlecard: Polsia

> **[2026-06-08 Cascade update]** **Trajectory reversed.** The 2026-05-30 read ("ARR fell to $450K, ambiguous trajectory") is superseded: per the 2026-06-08 full-tier scan, Polsia **raised $30M at a $250M valuation (Sound Ventures lead, True Ventures participating, May 2026)**, and newer third-party reports cite ~$10M ARR / 7,600 customers / 85% month-two retention. Figures across sources remain contradictory (a Feb 2026 Mixergy interview implied ~$689K run-rate), so **treat all revenue/customer counts as marketing/unverified — the funding round is the verifiable signal.** The "growing slower / churning out" framing from the prior note no longer holds; reps must NOT claim Polsia is shrinking. Pricing unchanged: $49/mo base + 20% revenue share.

> **[2026-06-02 Review note — superseded above]** Prior note read ARR **fell** from $1.5M to $450K+ with ambiguous trajectory. Retained for institutional history; do not use the "ARR fell / rapid-growth framing no longer holds" talk track — it is reversed by the $30M round.

## Quick Facts

| Field | Value |
|-------|-------|
| **Product** | Polsia -- autonomous AI company-operating platform. "AI that runs your company while you sleep." |
| **Pricing** | $49/mo base (one nightly autonomous task + 5 on-demand credits; 10 bonus first month) **plus 20% revenue share**. |
| **ARR** | Contradictory across sources: newer reports cite ~$10M ARR; a Feb 2026 Mixergy interview implied ~$689K run-rate; prior scans cited $1.5M then $450K. **All unverified — do not quote a single ARR figure as fact.** |
| **Funding** | **$30M raised at $250M valuation (Sound Ventures lead, True Ventures participating, May 2026).** This is the verifiable traction signal. |
| **Managed Companies** | ~7,600 business customers claimed (newer reports), with 85% month-two retention claimed; prior scans cited 500+ / 2,000+. Unverified. |
| **Founder** | Ben Broca (solo founder). Philosophy: "80% AI, 20% taste." |
| **Domain Coverage** | Engineering, marketing, cold outreach, social media, Meta ads. Missing: legal, finance, product strategy. |
| **Key Features** | Role-based agents (CEO, Engineer, Growth Manager). Nightly autonomous cycles: evaluate company state, decide priorities, execute tasks, send founder morning summary. Polsia provisions all infrastructure (email, servers, databases, Stripe, GitHub). |
| **Knowledge Persistence** | No structured cross-domain knowledge base. No compounding institutional memory. |
| **Architecture** | Cloud-hosted, proprietary. Built on Claude Agent SDK (Claude Opus 4.6). Fully autonomous -- zero human-in-the-loop. |

## When You Will Encounter This

- A founder asks "Polsia runs companies automatically from $49/month. Why would I use Soleur?"
- Discussions about autonomous vs. human-in-the-loop AI company operation
- Questions about whether CaaS means "no humans needed"
- Price comparisons -- Polsia's $49 base matches Soleur's planned $49/month, but Polsia layers a 20% revenue share on top
- Discussions about Polsia's traction; Polsia just raised **$30M at a $250M valuation** (May 2026) — a well-capitalized, venture-validated competitor. Lead with quality/control/coherence differentiation, not "they're shrinking" (they are not)

## Differentiator Table

| Dimension | Polsia | Soleur | Advantage |
|-----------|--------|--------|-----------|
| **Operating philosophy** | Fully autonomous. CEO agent decides priorities. Founder receives morning summary. Zero human-in-the-loop. | Founder-as-decision-maker. AI executes, human decides. Human judgment at every stage. | Depends on philosophy. Soleur: human judgment compounds better than autonomous execution. |
| **Domain scope** | 5 domains: engineering, marketing, cold outreach, social media, Meta ads | 8 domains: engineering, marketing, legal, operations, product, finance, sales, support | Soleur (legal, finance, product strategy absent from Polsia) |
| **Knowledge persistence** | No structured cross-domain knowledge base. Each cycle starts from company state, not accumulated wisdom. | Compounding knowledge base across all domains. Brand guide informs marketing. Competitive analysis shapes pricing. Legal audit references privacy policy. | Soleur |
| **Workflow orchestration** | Nightly autonomous cycles: evaluate, decide, execute. Black-box decision-making. | Brainstorm-plan-implement-review-compound lifecycle. Founder sees and approves each stage. | Soleur (transparency + founder control) |
| **Pricing** | $49/month base + 20% revenue share | Free (open source). Paid tier planned at $49/month flat rate. No revenue share. | Soleur at scale (same base, no revenue share). |
| **Infrastructure** | Polsia provisions everything: email, servers, databases, Stripe, GitHub | Terminal-first via Claude Code. Founder controls infrastructure. | Polsia (convenience) vs. Soleur (control) |
| **Output quality** | Reportedly basic. Autonomous execution without human review. | Human-reviewed. Founder validates before publishing/shipping. | Soleur (quality) |
| **Open source** | Proprietary, closed-source | Apache-2.0. Full source code. | Soleur |
| **Platform dependency** | Claude Agent SDK (Anthropic). Cloud-locked. | Claude Code (Anthropic). Local-first. | Both share Anthropic dependency. Soleur is local-first. |
| **Traction** | $30M raised at $250M valuation (May 2026); ARR claims contradictory (~$10M / ~$689K / unverified). | Early stage. Dogfooded on soleur.ai. | Polsia (well-capitalized; compete on quality/control, not size) |

## Talk Tracks

### "Polsia runs my company for $49/month while I sleep. Why complicate things?"

**Response:** "Polsia proved solo founders want autonomous company operation. The question is what quality of operation you want. Polsia's CEO agent decides priorities, writes code, sends emails, and posts to social media autonomously. You get a morning summary. Soleur keeps you in the decision seat -- AI executes, you decide. The difference matters when the stakes are high: a legal misstep, a brand-damaging social media post, or a pricing decision that leaves money on the table. If you want hands-off automation, Polsia is built for that. If you want an AI organization that amplifies your judgment rather than replacing it, Soleur is the architecture."

### "Polsia is cheaper."

**Response:** "Look at the full cost. Polsia's base is now $49/month -- the same as Soleur's planned flat rate -- but it layers a **20% revenue share** on top. A founder earning $10k/month would pay $2,000/month in revenue share alone. Soleur's $49/month flat rate means you keep 100% of what you earn. At any meaningful revenue, Soleur is dramatically cheaper. Polsia's base price is effectively subsidized by the revenue share."

### "Polsia has hundreds of companies running. That's real traction."

**Response:** "Polsia validates the CaaS thesis -- solo founders will pay for automated company operation, and investors agree: they just raised $30M at a $250M valuation. That is good for the entire category, including Soleur. The question is what those companies produce. Polsia's autonomous output is reportedly basic -- nightly cycles with no human review. Soleur's bet is that the first billion-dollar solo company will not be built by an AI running on autopilot. It will be built by a founder whose judgment is amplified by AI across every domain. Companies running on autopilot are different from companies where the founder makes every strategic decision with full-context AI support."

### "Polsia covers engineering, marketing, outreach, social media, and ads. That's close to Soleur."

**Response:** "Polsia covers 5 domains. Soleur covers 8. The 3 domains Polsia lacks -- legal, finance, and product strategy -- are the highest-stakes decisions a solo founder makes. A privacy policy violation, a pricing miscalculation, or a product roadmap that ignores competitive shifts can kill a company. Beyond domain count, the difference is coherence. Polsia's agents operate independently in nightly cycles. Soleur's agents share a compounding knowledge base where the brand guide informs marketing, the competitive analysis shapes pricing, and the legal audit references the privacy policy. Polsia has breadth. Soleur has coherence."

## Objection Handling

| Objection | Response |
|-----------|----------|
| "Polsia provisions all infrastructure -- servers, email, Stripe, GitHub. Soleur doesn't." | "Polsia's infrastructure provisioning is part of the fully autonomous model -- you give up control in exchange for convenience. Soleur assumes you control your own infrastructure. For serious founders building real companies, infrastructure ownership matters. You choose your hosting, your payment processor, your email provider. The AI organization runs on top of infrastructure you own." |
| "80% AI, 20% taste is the right balance." | "If that ratio works for you, Polsia is well-designed for it. Soleur's philosophy is different: AI handles 100% of execution, but the founder provides 100% of judgment. The compound skill doesn't just execute -- it captures what you decided and why, building institutional memory that makes every future decision better informed. The 20% taste model treats human input as a filter. The founder-as-decision-maker model treats human judgment as the compounding asset." |
| "Polsia is growing faster. Why back the smaller player?" | "Polsia is well-funded -- $30M at a $250M valuation -- and validates the market. We're not competing on size; we're competing on operating model. Polsia's revenue share model creates friction at scale (a founder earning $10k/month pays $2k to Polsia). Their fully autonomous output quality is a bet that 'good enough' automation beats 'excellent' human-guided execution. We believe the premium end of the CaaS market -- founders who care about quality, control, and compounding knowledge they own in git -- is where the long-term value lives." |

## Convergence Watch

Review monthly. Polsia is the most direct CaaS competitor.

| Trigger | Current Status (2026-06-02) | Action if Triggered |
|---------|---------------------------|-------------------|
| Polsia adds legal, finance, or product strategy domains | 5 domains only. No signal of expansion into legal/finance/product. | Major escalation. The domain coverage gap narrows. Emphasize cross-domain knowledge compounding and workflow orchestration. |
| Polsia implements cross-domain knowledge base | No structured knowledge base. No compounding memory. | Critical escalation. The strongest Soleur differentiator is neutralized. Shift to open source, local-first, and founder-in-the-loop as primary differentiators. |
| Polsia drops revenue share model | Currently $49/month base + 20% revenue share. | Update pricing analysis. If Polsia goes flat-rate, Soleur's pricing must justify the delta with domain depth and knowledge compounding. |
| Polsia crosses $5M ARR or 10,000 companies | Newer reports already claim ~$10M ARR / 7,600 customers (unverified). $30M raised at $250M valuation (May 2026). | Category is validated at scale and venture-backed. Accelerate CaaS category-definition content and lean into the differentiated axis (founder-in-the-loop, 8 domains, git-native owned memory, no revenue share). |
| Polsia output quality improves materially | Reportedly basic autonomous output. | Reassess the "quality vs. automation" positioning. If autonomous output quality reaches "good enough" for most founders, the human-in-the-loop argument weakens. |

---

_Updated: 2026-06-08 (cascade from full six-tier scan). Source: competitive-intelligence.md (2026-06-08)._
