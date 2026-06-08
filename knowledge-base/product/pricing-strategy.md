---
last_updated: 2026-06-08
last_reviewed: 2026-06-08
review_cadence: quarterly
owner: CPO
depends_on:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/marketing/marketing-strategy.md
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/product/business-validation.md
---

# Soleur Pricing Strategy

> **[2026-06-08 Cascade refresh from full six-tier CI scan]** Competitive pricing matrix updated against `competitive-intelligence.md` (2026-06-08). Key changes: (1) **The entire Tier 0 IDE/agent layer moved to metered/credit billing simultaneously** — GitHub Copilot "AI Credits" (1 credit = $0.01) live June 1 with model-fallback removed and 10–50x agentic-bill spikes + public backlash; OpenAI Codex Pro 2x promo expired May 31 (effective capacity halved June 1 at $100/mo); Notion Custom Agents now Business/Enterprise-only at $10/1,000 credits. (2) **Polsia raised $30M at a $250M valuation** (May 2026) — the autonomous-CaaS thesis is venture-validated, not fading; the prior "$450K ARR / shrinking" note is reversed. (3) **NanoCorp** ($30/mo + 20% withdrawal fee, Phospho/YC) added as a second revenue-share CaaS data point. The metered-billing backlash strengthens the case for Soleur's predictable, git-native cost story — but Soleur's own hosted pricing will live in the same metered-COGS reality.

## Status

**Pricing structure is canonical.** The 4-tier model (Solo $49 / Startup $149 / Scale $499 / Enterprise custom) is encoded in `apps/web-platform/lib/stripe-price-tier-map.ts` and shipped on the live `/pricing` page. Live-mode activation (tracked by issue PR #1444) still depends on the pricing-gate criteria below — the structure is fixed but the flip from test-mode to live-mode Stripe prices gates on those signals. This document is the strategic rationale; the code and `/pricing` are the source of truth for prices and concurrency numbers.

### Business Validation Update (2026-03-22)

5+ founder conversations confirmed the CaaS thesis but rejected CLI/plugin delivery. Founders expect a standalone web/mobile product. This changes the pricing strategy in three ways:

1. **The open-core model inverts.** The current model assumes the free plugin is the distribution mechanism and the paid platform is the monetization layer. User research reveals that most target customers do not use the free plugin's host (Claude Code). The platform is the distribution mechanism AND the monetization layer. The plugin becomes an optional power-user interface, not the funnel. The "Open Source" free tier in the tier structure below may need redefinition -- it currently assumes terminal-first usage as the free experience.

2. **Cost structure escalates.** A platform-first product requires cloud infrastructure, API costs per user, frontend engineering, mobile development, and user authentication as table stakes. These costs were previously categorized as "hosted-platform infrastructure" -- optional, built after validation. Under the delivery pivot, they are pre-revenue requirements. The infrastructure cost gate (Gate 4) becomes more urgent: per-user costs must be modeled before beta, not after. (Cost model now lives in [finance/cost-model.md](../finance/cost-model.md).)

3. **Competitive framing shifts.** The replacement-stack comparison (Soleur at $49/mo vs. $765-3,190/mo in separate tools) remains valid, but the comparison set now includes web-native competitors: Polsia ($29-59/mo, web dashboard), Notion AI ($10/mo + credits, web/mobile), and Tanka ($0 for small teams, mobile apps). Founders will compare Soleur's platform against these surfaces, not against terminal tools. The "you keep 100% of revenue" argument against Polsia's revenue share and the cross-domain knowledge compounding argument remain the strongest differentiators.

---

## Competitive Pricing Matrix

### Tier 0: Platform Threats

| Competitor | Pricing | Model | Engineering | Multi-Domain | Knowledge Persistence | Notes |
|------------|---------|-------|-------------|-------------|----------------------|-------|
| **Anthropic Cowork** | Included with Claude Pro ($20/mo) / Team ($25/seat/mo) / Enterprise (custom) | Bundled | Yes (as of Feb 2026) | Yes (11+ plugins across 6+ domains) | No (stateless per session) | Cowork plugins are free with subscription. Enterprise has private marketplace. |
| **Claude Code** | Included with Claude Pro ($20/mo) / Max ($100-200/mo) | Bundled | Yes (native + 9,000+ plugins) | Limited (plugins are siloed) | Limited (auto-memory, project memory) | Claude Code itself is a bundled feature. Plugins are mostly free. |
| **Microsoft Copilot Cowork** | Part of M365 E7 Frontier Suite (pricing TBD, Research Preview) | Bundled | No | Yes (Outlook, Teams, Excel workflow automation) | No (session-scoped) | NEW (Mar 9, 2026). Anthropic Claude-powered. Enterprise-targeted. Background task execution across M365. |
| **Cursor** | Hobby $0 / Pro $20 / Pro+ $60 / Ultra $200 / Teams $40 (Premium seat $120) / Enterprise | Subscription + dollar-bucket usage | Yes (deep) | Partial (marketplace plugins) | Yes (project rules, automation memory) | **Composer 2.5 (May 18)**: 79.8% SWE-Bench Multilingual at ~1/10 cost/token ($0.50/M in, $2.50/M out) — frontier quality at low per-token cost pressures everyone's economics. |
| **GitHub Copilot** | $0 Free / $10 Pro / $39 Pro+ / $19 Business / $39 Enterprise (per user). **Usage-based "AI Credits" (1 credit = $0.01) live June 1, 2026; model fallback removed.** | Subscription + metered credits | Yes (deep) | No | Yes (CLI memory, Spaces) | **Pricing-model shift:** agentic sessions now drain a real credit pool and stop when exhausted. Power users report 10–50x bill increases; public backlash. Promo credits ($30/user Business, $70/user Enterprise) through Aug 2026. |
| **OpenAI Codex** | Free / Go / Plus / **Pro 5x $100** / Pro 20x / Business / Enterprise. April 2 → API-token-based billing. **Pro 2x promo expired May 31 — effective capacity halved June 1 at the same $100/mo.** | Token-metered + subscription | Yes (deep) | Partial (multi-agent, memory, Sites) | Yes (memory preview) | $100/mo Pro 5x matches Claude Code's $100/mo. **Sites** preview (deploy websites/apps hosted by OpenAI) + Amazon Bedrock support added this window. |
| **Windsurf** | $0 Free / **$20 Pro (was $15, +33%, Mar 19)** / $200 Max / Teams | Subscription (daily/weekly quotas, credits retired) | Yes (deep) | No | Yes (Memories system) | Windsurf 2.0 (April) embedded Cognition's Devin agent into the IDE. SWE-1.6 (950 tok/s, zero-quota) included. |
| **Google Gemini Code Assist** | Free (6,000 req/day), $299/year Premium | Freemium | Yes | No | No | Gemini 3 support. Finish Changes + Outlines GA. Enterprise/GCP focused. |

### Tier 3: CaaS / Business Platforms

| Competitor | Pricing | Model | Engineering | Multi-Domain | Knowledge Persistence | Notes |
|------------|---------|-------|-------------|-------------|----------------------|-------|
| **Devin 2.0** | $20/mo Core, custom Enterprise | Usage-based (ACU credits) | Yes (autonomous) | No | Limited (session context) | Dropped from $500 to $20/mo. Engineering-only. |
| **Lovable.dev** | $0 Free, $25/mo Pro, $50/mo Teams | Freemium | Yes (web apps) | No | No | $300M+ ARR, $6.6B valuation. Claude Opus 4.5 upgrade (20% fewer errors). |
| **Bolt.new** | $0 Free, $25/mo Pro, $109/mo Enterprise | Freemium | Yes (web apps) | No | No | Browser-based. $40M+ ARR. Open-source bolt.diy option. |
| **v0.app** | $0 Free, $20/mo Premium, $30/mo Team | Freemium | Yes (frontend) | No | No | Rebranded from v0.dev. Agentic architecture, custom MCP server support (Mar 6). |
| **Replit Agent** | $20/mo Core, $100/mo Pro | Usage-based (effort) | Yes (cloud) | No | Limited | **Agent 4** (10x faster, multi-output). **$400M Series D at $9B valuation (Mar 2026)**, ~$1B run-rate target end-2026. |
| **Notion AI** | $10/mo add-on per user; **Custom Agents now Business/Enterprise-only, $10/1,000 credits (free beta ended May 3)** | Add-on + credits | No | Yes (workspace agents, 21,000+ built) | Yes (workspace context) | 35M+ users. **Paywall evicts free/Plus solo-founder long tail (Soleur's exact ICP) — acquisition window.** |
| **Polsia** | $49/mo base + 20% revenue share | Hybrid (subscription + revenue share) | Yes (autonomous) | Yes (~5 domains) | No (no structured cross-domain knowledge base) | Most direct CaaS competitor. **Raised $30M at $250M valuation (May 2026).** ARR claims contradictory (~$10M / ~$689K / unverified) — funding is the verifiable signal. |
| **NanoCorp** | Free $0 (3 lifetime credits) / Founder $30/mo (credit-based); **both + 20% revenue-withdrawal fee** | Hybrid (credits + revenue share) | No (GTM only) | Narrow GTM engine (naming, copy, content ops, outreach) | No (cloud proprietary state) | Phospho Inc. / YC. **Ads "Coming Soon" (not live).** ARR claims contradictory/unverified ($740k/33d vs $193k/3d vs ~$264 leaderboard). Second 20%-rev-share CaaS data point. |
| **Paperclip** | Free (MIT, self-hosted) | Open source | No (agent-agnostic orchestration) | Yes (org charts, budgets, governance for any domain) | No (no knowledge layer) | **53k+ GitHub stars in first 6 weeks** (~15% fork ratio = real deployment). Built on Claude Code. Orchestration infra, not domain intelligence. Complementary to Soleur. |
| **Tanka** | $0/user/mo (<50 users), $29 Plus, $199/mo Pro | Freemium | No | Partial (communication-centric) | Yes (EverMemOS, **now open source**) | Closest memory architecture to Soleur. **Open-sourcing EverMemOS commoditizes the memory-engine layer** — Soleur's edge is the git-tracked, founder-readable, lifecycle-tied KB, not memory tech. |
| **Lindy AI** (Tier 2) | Free 400 credits / Starter $19.99 / Pro $49.99 / Business $299 / Max $199.99 | Usage-based credits | No | Partial (ops/sales workflows) | Limited | No-code agent builder. Voice $0.19/min + $10/number. Closest pricing analog at the $49 anchor. |
| **Relevance AI** (Tier 2) | Free (200 actions) / Pro $29 / Team $349 / Enterprise | Actions + Vendor Credits (BYO-key) | No | Partial (sales/support/research) | Limited | **$37.2M total funding ($24M Series B, Bessemer).** Enterprise/sales-heavy AI workforce. |
| **SoloCEO** | Unknown (previously $2,000 diagnostic) | Unknown | No | Yes (advisory) | No | Advisory-only. **No 2026 update surfaced; verify still active before next citation.** |
| **Systeme.io** | $0 Free, $17/mo Startup, $97/mo Unlimited | Freemium | No | Marketing/sales only | No | Traditional SaaS. No AI agents. Startup plan dropped from $27 to $17. |

---

## Pricing Analysis

### Market Price Anchors

The competitive landscape establishes clear price anchors:

| Category | Price Range | What Founders Expect |
|----------|------------|---------------------|
| AI coding tool (IDE) | $15-40/month | Per-seat subscription, engineering-only |
| AI coding agent (autonomous) | $20-100/month | Usage-based credits, engineering-only |
| AI web app builder | $0-50/month | Freemium, engineering-only |
| AI workspace agent | $10/month + credits | Bundled with existing workspace tool. Notion: $10/1,000 credits post-May 2026. |
| AI agent platform (engineering) | $20-40/month + marketplace plugins | Cursor: subscription + free/paid plugins. Event-driven automations included. |
| Autonomous AI company operator | $30-59/month + ~20% revenue share | Polsia ($49 base + 20% share, $30M raised @ $250M) and NanoCorp ($30/mo + 20% withdrawal fee). The 20%-revenue-cut model is now a 2-player pattern, not a Polsia outlier. |
| AI company orchestration (OSS) | Free (self-hosted) | Paperclip: MIT-licensed, no recurring cost. Infrastructure-only. |
| Multi-domain AI platform (human-in-loop) | No established anchor | Soleur would be first in this segment |

**Key insight (updated 2026-06-08):** **Two shifts reframe the pricing landscape.** First, the **20%-revenue-cut model is now a pattern, not an outlier**: both Polsia ($49 base + 20% share, freshly funded at $250M) and NanoCorp ($30/mo + 20% withdrawal fee) tax customer revenue. This sharpens — not weakens — Soleur's strongest pricing differentiator: **"$49 flat, you keep 100% of what you earn, and your institutional memory lives in your own git repo."** A founder earning $10k/mo pays $2k/mo to Polsia or NanoCorp; Soleur stays $49. Second, **the Tier 0 layer repriced to metered/credit billing in one window** (Copilot AI Credits with 10–50x bill spikes + backlash, Codex token-billing + promo expiry, Notion credits, Cursor dollar-buckets). The Copilot backlash is a gift: predictable, non-metered pricing is now a felt pain point. Soleur's framing should lean into **predictability + ownership**, not "cheaper" — Soleur's own hosted COGS lives in the same metered-compute reality (~$81/mo modeled). The justification for $49 still centers on what competitors lack: (1) cross-domain compounding knowledge the founder owns, (2) legal/finance/product-strategy domains, (3) founder-as-decision-maker orchestration — now plus (4) **predictable flat pricing in a market that just made agentic billing visibly painful.**

### Replacement Stack Cost Analysis

What a solo founder currently pays for the capabilities Soleur provides:

| Function | Current Solution | Monthly Cost |
|----------|-----------------|-------------|
| Engineering (code review, architecture) | Cursor or Copilot | $20-40 |
| Marketing (brand, content, SEO) | Agency or freelancer | $500-2,000 (amortized) |
| Legal (contracts, privacy, compliance) | Lawyer consultations | $300-500/hour, ~$200-500/month amortized |
| Operations (project management, process) | Notion + Linear + custom | $20-50 |
| Product (specs, validation, research) | Manual + scattered tools | $0-50 |
| Finance (tracking, planning) | QuickBooks + spreadsheets | $25-50 |
| Sales (battlecards, competitive intel) | Manual research | $0 (time cost) |
| Support (docs, community) | Manual | $0 (time cost) |
| **Total replacement stack** | | **$765-3,190/month** |

Even at 10% of replacement value, the justified price is $75-320/month.

### Price Sensitivity Considerations

1. **Solo founders are price-sensitive on individual tools** but spend significantly on the aggregate stack. The framing matters: $49/month for "another coding tool" feels expensive. $49/month for "every department of your company" feels like a bargain.

2. **Devin's price collapse** ($500 to $20/month) signals that autonomous coding agents are commoditizing rapidly. Any pricing anchored to engineering value alone will face downward pressure.

3. **Cowork plugins are bundled free** with Claude subscriptions that founders already pay. Soleur must provide value beyond what Cowork offers to justify a separate price.

4. **Open-source core creates a floor problem.** If the free plugin provides 80% of the value, the paid tier must offer something the open-source version cannot: cloud sync, managed infrastructure, team features, or premium agents.

---

## Recommended Pricing Model

### Model: Open Core with Hosted Platform

**Rationale:** The open-source plugin is the distribution mechanism. The paid tier is the compounding mechanism -- cloud-synced knowledge base, managed agent execution, and features that require infrastructure the solo founder does not want to maintain.

### Tier Structure

| Tier | Price | Target | Includes |
|------|-------|--------|----------|
| **Open Source** | Free (Apache-2.0) | All users | Full plugin: 63 agents, 62 skills, 3 commands. Local knowledge base. Terminal-first workflow. Self-hosted. **[2026-03-22 note: User research shows most target customers do not use the CLI host. This tier's value as a distribution mechanism is weaker than assumed. Consider whether a free web tier (limited conversations/domains) is needed as the new top-of-funnel.]** |
| **Solo** | $49/month | Solo founders building alone | 2 concurrent conversations. All 8 departments and full agent roster. Compounding knowledge base. Email support. |
| **Startup** | $149/month | Founding teams moving fast | 5 concurrent conversations. Priority execution queue. Shared knowledge base. |
| **Scale** | $499/month | Companies that never wait | Up to 50 concurrent conversations. Dedicated infrastructure. Custom agent configuration. |

_Enterprise is custom-priced with negotiated concurrency, sliding revenue share (10% → 5% as you grow), dedicated account management, and custom integrations/SLA. Contact sales (<hello@soleur.ai>) -- no self-serve checkout._

### Why $49/month

1. **Above the coding-tool anchor** ($15-40/month) -- signals that this is a different category
2. **Below the SaaS-tool-stack anchor** ($100-200/month combined) -- feels like consolidation savings
3. **Matches Lindy.ai's entry price** ($49/month) -- the closest pricing analog in the AI agent platform category
4. **Justified by replacement-stack math** -- $49 vs. $765-3,190 in separate tools and services
5. **Sustainable for one founder** -- even 100 Pro subscribers at $49/month = $4,900 MRR, enough to cover infrastructure and sustain development

### Why $149 / $499 (Startup / Scale)

Startup and Scale are not new market anchors -- they are concurrency/team-size cohorts layered on top of the $49 Solo anchor. The hypothesis is that once a founding team has 5+ agents running in parallel (code review, CFO forecast, CMO draft, legal redline simultaneously), the per-user value flips from "another AI tool" to "shared team infrastructure," and per-user pricing can scale without repricing the anchor. Startup ($149 / 5 concurrent) targets the 2-4 person founding team cohort where serialized execution becomes the bottleneck. Scale ($499 / 50 concurrent) targets companies running cross-domain workflows continuously, where concurrency is the product. Enterprise custom pricing replaces subscription with negotiated revenue share at the size where flat-fee economics no longer align vendor and customer incentives.

### Value Metric: Knowledge Base Growth

The primary value metric should be **compounding knowledge** -- the more a founder uses Soleur, the more valuable it becomes. This creates natural retention and justifies recurring pricing.

**Anti-churn mechanism:** The knowledge base is the moat. A founder with 6 months of compounding institutional memory faces a real switching cost -- not because of lock-in, but because the accumulated context cannot be replicated in a new tool.

---

## What Must Be True Before Launching Pricing

These gates prevent premature monetization:

| Gate | Criteria | Status |
|------|----------|--------|
| Demand validation | 10+ solo founders have used Soleur on real projects for 2+ weeks | Not started |
| Multi-domain validation | 5+ users engage with agents from 2+ non-engineering domains | Not started |
| Willingness-to-pay signal | 3+ founders express they would pay $49/month or identify what would justify it | Not started |
| Infrastructure ready | Cloud sync, hosted execution, and analytics dashboard are buildable (not necessarily built) | Partial — affordability documented in [finance/cost-model.md](../finance/cost-model.md) (~$81/mo COGS, break-even 2 users, ~80% gross margin all-in at 50 users). Buildability pending CPO/CTO assessment. |
| Cowork differentiation clear | Users can articulate why Soleur is worth paying for when Cowork plugins are free | Not started |

**Do not launch pricing until at least 4 of 5 gates pass.**

---

## Pricing Page Messaging Framework

When pricing launches, the page must frame the value correctly. Draft messaging:

**Headline:** "Every department. One price."

**Subheadline:** "Stop paying for 8 separate tools. Soleur replaces your engineering workflow, marketing agency, legal advisor, and operations team -- all for less than a single contractor."

**Comparison framing:**

| What You Replace | Typical Cost | With Soleur |
|-----------------|-------------|-------------|
| AI coding tool | $20-40/month | Included |
| Brand agency (amortized) | $500-2,000/month | Included |
| Legal consultations (amortized) | $200-500/month | Included |
| Marketing tools | $50-200/month | Included |
| Ops + project management | $20-50/month | Included |
| **Total** | **$790-2,790/month** | **$49/month** |

**Proof point:** "Designed, built, and shipped by Soleur -- using Soleur. 420+ PRs across all 8 domains."

---

## Pricing Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Founders anchor against $15-25/month coding tools | High | Medium | Frame as team replacement, not tool replacement. Lead with non-engineering value. |
| Cowork plugins commoditize domain breadth for free | High | High | Differentiate on compounding knowledge and workflow orchestration. Price the persistence, not the breadth. |
| Open-source version provides 80%+ of value | Medium | High | Ensure Solo tier has clear infrastructure value (cloud sync, hosted execution) that cannot be self-hosted easily. |
| Price compression forces below $49/month | Medium | Medium | $29/month floor still works at scale. The value metric (knowledge compounding) creates retention regardless of price point. |
| Polsia / NanoCorp revenue-share pricing competes with Soleur's $49 flat | High | Medium | Both now tax revenue: Polsia $49 base + 20% share (freshly funded $30M @ $250M), NanoCorp $30/mo + 20% withdrawal fee. Their base prices look cheap but the rev-share dominates at any real revenue. Position Soleur's flat $49 as "premium, you keep 100%, your memory is yours in git" and emphasize domains both lack (legal, finance, product strategy). The 20% cut is the shared vulnerability at scale. |
| Cursor's $20/month agent platform makes engineering-only pricing look cheap | Medium | Medium | Cursor at $20/month now includes automations, marketplace, cloud agents, and built-in memory. Solo founders may feel $49 for Soleur is expensive when Cursor handles engineering + some automation for less. Soleur must justify the $29 delta with non-engineering domain value. |
| Paperclip at $0 sets orchestration floor to free | Medium | Low | Paperclip provides free, self-hosted company orchestration. If Clipmart ships pre-built company templates, founders may assemble a "Soleur-like" experience from Paperclip + free agents. Soleur's moat is curated domain intelligence and compounding knowledge, not orchestration infrastructure. |
| Enterprise demand emerges before solo-founder validation | Low | Low | Good problem to have. Enterprise tier at custom pricing. Do not pivot to enterprise until solo-founder thesis is validated. |

---

## Alternative Models Considered

| Model | Pros | Cons | Verdict |
|-------|------|------|---------|
| **Usage-based (per agent execution)** | Scales with value. Low entry barrier. | Unpredictable costs frustrate solo founders. Replit's backlash is a cautionary tale. | Reject |
| **Success tax (% of revenue)** | Aligns incentives. Mentioned on vision page. Polsia validates model at $50/mo + 20% share ($1M ARR). | Requires revenue tracking integration. Trust barrier. 20% share creates friction at scale (a company earning $10k/month pays $2k to Polsia). Polsia's model works because they provision all infrastructure. | Defer -- Polsia proves this works for fully autonomous operation. For human-in-loop, pure subscription may be more compelling. Founders who choose Soleur likely want control, which correlates with not wanting revenue share. |
| **Freemium with domain gating** | Free engineering, paid non-engineering domains. | Fragments the experience. Violates the "integration IS the product" thesis. | Reject |
| **One-time license** | Simple. No recurring obligation. | Does not fund ongoing development. Knowledge compounding needs ongoing infrastructure. | Reject |
| **Donation / sponsorship** | Community goodwill. Open-source aligned. | Does not build a business. Incompatible with "billion-dollar company" thesis. | Reject |
| **Outcome-based (per result)** | Aligns vendor/customer incentives -- vendor wins when customer wins. No CaaS competitor uses it, potential positioning wedge against Polsia. Matches investor demand for measurable value in the 2026 SaaS correction ($300B value destroyed, 3.6x multiples). Could function as a zero-risk trial mechanism for pre-revenue founders. | Soleur's value is cross-domain compounding knowledge, not discrete tasks -- Intercom's 99¢/resolved-chat model doesn't map. Most domains (finance, product, ops) produce advisory output where value accrues over time, not per execution. "Negative outcomes" (kill criteria that save 3 months of wasted work) have enormous value but no natural pricing unit. Synthetic research (2026-03-26) found: per-outcome pricing creates perverse incentives -- users ration usage and avoid cross-domain exploration, directly undermining the compounding moat. Unpredictability concern may trigger same Replit backlash as usage-based (shifts from "paid for nothing" to "paid more because I succeeded"). Hybrid variant ($29 base + per-outcome) triggers "paying twice" perception. BYOK model creates double-pay perception. 0/5 pricing gates passed -- no real data to validate. | Defer -- conceptually compelling but structurally mismatched with compounding knowledge value. Synthetic personas universally described outcome-based as a trial mechanism they'd abandon once they trusted the tool. Re-evaluate after P4 validation when real usage data reveals which outcomes are discrete and attributable. Consider outcome-based as a first-month trial alternative (replacing 14-day free trial) rather than a permanent tier. Hybrid model (base + outcome bonus) deserves separate evaluation at that time. See `knowledge-base/product/research/synthetic-research-brief.md` for full analysis. |

---

## Next Steps

1. **Complete PIVOT validation** (10 founders, problem interviews, guided onboarding)
2. **Track which domains users engage with** -- confirms or refutes the multi-domain value hypothesis
3. **Ask willingness-to-pay question** in post-onboarding interviews: "Would you pay $49/month for this? What would it need to deliver?" Use the synthetic research brief (`knowledge-base/product/research/synthetic-research-brief.md`) to inform question framing -- establish alternative costs before asking WTP, and test the outcome-based trial concept ("pay only for completed outcomes in month 1, then switch to $49/month flat").
4. **Assess infrastructure requirements** for Solo tier (cloud sync complexity, hosting costs, security)
5. **Revisit this document** when 4 of 5 pricing gates pass

---

_Updated: 2026-06-08 (cascade from full six-tier CI scan: metered-billing shift across Tier 0, Polsia $30M/$250M funding reversal, NanoCorp added, Notion paywall, Tier 2 funding context). Prior: 2026-03-26 (added outcome-based pricing as 6th alternative). Sources: competitive-intelligence.md (2026-06-08), business-validation.md (2026-03-22), brand-guide.md (2026-06-01), synthetic-research-brief.md (2026-03-26)._
