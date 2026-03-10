---
last_updated: 2026-03-09
last_reviewed: 2026-03-09
review_cadence: quarterly
depends_on:
  - knowledge-base/overview/brand-guide.md
  - knowledge-base/overview/marketing-strategy.md
  - knowledge-base/overview/competitive-intelligence.md
  - knowledge-base/overview/business-validation.md
---

# Soleur Pricing Strategy

## Status

**Pricing is undecided.** This document provides the analysis framework and recommendation for when the founder is ready to commit. Per the business validation verdict (PIVOT), pricing should follow validated adoption, not precede it. Commit to a model after 50+ active users, informed by observed behavior.

---

## Competitive Pricing Matrix

### Tier 0: Platform Threats

| Competitor | Pricing | Model | Engineering | Multi-Domain | Knowledge Persistence | Notes |
|------------|---------|-------|-------------|-------------|----------------------|-------|
| **Anthropic Cowork** | Included with Claude Pro ($20/mo) / Team ($25/seat/mo) / Enterprise (custom) | Bundled | Yes (as of Feb 2026) | Yes (11+ plugins across 6+ domains) | No (stateless per session) | Cowork plugins are free with subscription. Enterprise has private marketplace. |
| **Claude Code** | Included with Claude Pro ($20/mo) / Max ($100-200/mo) | Bundled | Yes (native + 9,000+ plugins) | Limited (plugins are siloed) | Limited (auto-memory, project memory) | Claude Code itself is a bundled feature. Plugins are mostly free. |
| **Cursor** | $20/mo Pro, $40/mo Business | Subscription | Yes (deep) | No | Yes (project rules, .cursorrules) | $1B ARR, $29.3B valuation. Engineering-only. |
| **GitHub Copilot** | $10/mo Individual, $19/mo Business, $39/mo Enterprise | Subscription | Yes (deep) | No | Yes (CLI memory, Spaces) | Bundled with GitHub. Coding agent GA for all paid tiers. |
| **Windsurf** | $15/mo | Subscription | Yes (deep) | No | Yes (Memories system) | Cheapest IDE-native option. Acquired by Cognition (Devin). |
| **Google Gemini Code Assist** | Free (6,000 req/day), $299/year Premium | Freemium | Yes | No | No | Enterprise/GCP focused. Aggressive free tier. |

### Tier 3: CaaS / Business Platforms

| Competitor | Pricing | Model | Engineering | Multi-Domain | Knowledge Persistence | Notes |
|------------|---------|-------|-------------|-------------|----------------------|-------|
| **Devin 2.0** | $20/mo Core, custom Enterprise | Usage-based (ACU credits) | Yes (autonomous) | No | Limited (session context) | Dropped from $500 to $20/mo. Engineering-only. |
| **Lovable.dev** | $0 Free, $25/mo Pro, $50/mo Teams | Freemium | Yes (web apps) | No | No | $200M ARR, $6.6B valuation. Web apps only. |
| **Bolt.new** | $0 Free, $25/mo Pro, $109/mo Enterprise | Freemium | Yes (web apps) | No | No | Browser-based. Open-source bolt.diy option. |
| **v0.dev** | $0 Free, $20/mo Premium, $30/mo Team | Freemium | Yes (frontend) | No | No | Vercel ecosystem. Next.js focused. |
| **Replit Agent** | $20/mo Core, $95/mo Pro | Usage-based (effort) | Yes (cloud) | No | Limited | Pricing backlash from effort-based model. |
| **Notion AI** | $10/mo add-on per user | Add-on | No | Yes (workspace agents) | Yes (workspace context) | 35M+ users. Custom Agents launched Feb 2026. |
| **Polsia** | $50/mo + 20% revenue share + 20% ad spend share | Hybrid (subscription + revenue share) | Yes (autonomous) | Yes (engineering, marketing, ops, sales outreach, social media) | No (no structured cross-domain knowledge base) | Most direct CaaS competitor. $1M ARR in 1 month. 1,100+ managed companies. $50 "roughly breaks even on AI costs" -- real revenue is the 20% cuts. |
| **Tanka** | $0/user/mo (<50 users), $299/mo (50+ users) | Freemium | No | Partial (communication-centric) | Yes (EverMemOS memory graphs) | Closest memory architecture to Soleur. Free for solo founders. |
| **SoloCEO** | Unknown (previously $2,000 diagnostic) | Unknown | No | Yes (advisory) | No | Advisory-only. Limited public information. |
| **Systeme.io** | $0 Free, $17/mo Startup, $97/mo Unlimited | Freemium | No | Marketing/sales only | No | Traditional SaaS. No AI agents. Startup plan dropped from $27 to $17. |

---

## Pricing Analysis

### Market Price Anchors

The competitive landscape establishes clear price anchors:

| Category | Price Range | What Founders Expect |
|----------|------------|---------------------|
| AI coding tool (IDE) | $15-40/month | Per-seat subscription, engineering-only |
| AI coding agent (autonomous) | $20-95/month | Usage-based credits, engineering-only |
| AI web app builder | $0-50/month | Freemium, engineering-only |
| AI workspace agent | $10/month add-on | Bundled with existing workspace tool |
| Autonomous AI company operator | $50/month + 20% revenue share | Polsia: subscription breaks even on AI costs, revenue share is profit |
| Multi-domain AI platform (human-in-loop) | No established anchor | Soleur would be first in this segment |

**Key insight:** Polsia has established the first CaaS price anchor at $50/month + 20% revenue share. This validates that solo founders will pay $50/month for autonomous company operation. However, Polsia's real revenue comes from the 20% cuts (revenue + ad spend), not the subscription. Soleur's $49/month flat-rate model avoids revenue share friction -- founders keep 100% of what they earn. The risk shifts from "being anchored against $15-40 engineering tools" to "being compared against Polsia's $50 + 20% model." The framing must emphasize: Soleur costs the same monthly but takes no cut of your revenue.

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
| **Open Source** | Free (Apache-2.0) | All users | Full plugin: 61 agents, 56 skills, 3 commands. Local knowledge base. Terminal-first workflow. Self-hosted. |
| **Pro** | $49/month | Solo founders with active products | Cloud-synced knowledge base (access from any machine). Hosted agent execution (background tasks). Priority model access. Analytics dashboard. Email support. |
| **Team** | $99/month (up to 3 seats) | Small founding teams | Everything in Pro + shared knowledge base across team members. Role-based agent permissions. Collaboration features. |

### Why $49/month

1. **Above the coding-tool anchor** ($15-40/month) -- signals that this is a different category
2. **Below the SaaS-tool-stack anchor** ($100-200/month combined) -- feels like consolidation savings
3. **Matches Lindy.ai's entry price** ($49/month) -- the closest pricing analog in the AI agent platform category
4. **Justified by replacement-stack math** -- $49 vs. $765-3,190 in separate tools and services
5. **Sustainable for one founder** -- even 100 Pro subscribers at $49/month = $4,900 MRR, enough to cover infrastructure and sustain development

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
| Infrastructure ready | Cloud sync, hosted execution, and analytics dashboard are buildable (not necessarily built) | Not assessed |
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
| Open-source version provides 80%+ of value | Medium | High | Ensure Pro tier has clear infrastructure value (cloud sync, hosted execution) that cannot be self-hosted easily. |
| Price compression forces below $49/month | Medium | Medium | $29/month floor still works at scale. The value metric (knowledge compounding) creates retention regardless of price point. |
| Polsia's $50 + 20% share anchors CaaS pricing expectations | Medium | Medium | Founders may expect CaaS platforms to cost ~$50/month. Soleur's $49 flat rate is competitive and avoids the 20% revenue share. Position as "same price, you keep 100%." The revenue share is a vulnerability for Polsia at scale -- a founder earning $50k/month pays $10k to Polsia. |
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

---

## Next Steps

1. **Complete PIVOT validation** (10 founders, problem interviews, guided onboarding)
2. **Track which domains users engage with** -- confirms or refutes the multi-domain value hypothesis
3. **Ask willingness-to-pay question** in post-onboarding interviews: "Would you pay $49/month for this? What would it need to deliver?"
4. **Assess infrastructure requirements** for Pro tier (cloud sync complexity, hosting costs, security)
5. **Revisit this document** when 4 of 5 pricing gates pass

---

_Updated: 2026-03-09. Sources: competitive-intelligence.md (2026-03-09), business-validation.md (2026-03-09), brand-guide.md (2026-02-21)._
