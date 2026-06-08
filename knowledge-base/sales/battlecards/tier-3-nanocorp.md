---
last_updated: 2026-06-08
last_reviewed: 2026-06-08
review_cadence: monthly
owner: CRO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
competitor: NanoCorp
tier: 3
convergence_risk: High
---

# Battlecard: NanoCorp

> **[2026-06-08 Created via cascade]** New battlecard from the full six-tier scan. **Data-reconciliation warning for reps:** NanoCorp's metrics are marketing-only and mutually contradictory — do NOT quote a specific ARR. The marketing site lists Google Search Ads as "**Coming Soon**," so any pitch deck or comparison that says NanoCorp "runs your ads" is overstating shipped capability. Source: `knowledge-base/product/competitive-intelligence.md` (2026-06-08).

## Quick Facts

| Field | Value |
|-------|-------|
| **Product** | NanoCorp -- "Autonomous Companies Run by AI Making Money While You Sleep." One-prompt autonomous company creation. |
| **Parent / Backing** | **Phospho Inc.** (Wilmington, DE), YC company. Founder: Pierre-Louis Biojout. Domain: `nanocorp.so` (NOT the unrelated `nanocorp.ai` Paris network-security company). |
| **Pricing** | Free $0 (3 lifetime credits, 1 company, `nanocorp.app` subdomain) / Founder $30/mo (credit-based, scalable, rollover, unlimited companies, custom domains). **Both carry a 20% revenue-withdrawal fee.** |
| **ARR / Traction** | **Contradictory and unverified.** Founder claims span "$740k ARR in 33 days" and "$193k ARR in 3 days"; a user-revenue leaderboard showed ~$264 across 29 transactions. Quote none as fact. |
| **What ships today** | Per NanoCorp's own blog: content operations (research, draft, schedule, track) and lead-gen/outreach (find prospects, enrich, draft first-touch, log replies). Agents run on schedules and report to a dashboard. |
| **What is "Coming Soon" / not reliable** | **Google Search Ads = "Coming Soon" on the marketing site** (not live). Their blog states what does NOT work: legal accountability (contracts, hiring real humans), fine-motor desktop manipulation, anything where a single mistake is catastrophic. |
| **Domain Coverage** | Narrow go-to-market revenue engine: naming, ICP, copy, content ops, outreach. Missing: engineering code-review/deploy, legal, finance, product strategy, support. |
| **Knowledge Persistence** | Cloud-hosted proprietary state. No git-tracked compounding knowledge base. |
| **Operating model** | Fully autonomous, no human in the loop ("no babysitting required"). |

## When You Will Encounter This

- A founder asks "NanoCorp spins up a whole company from one prompt for $30/month. Why use Soleur?"
- Comparisons against Polsia (NanoCorp's closest analog) and the broader autonomous-CaaS pack
- A prospect cites NanoCorp's viral ARR claims as proof the category works
- Discussions about "set it and forget it" autonomous company creation

## Differentiator Table

| Dimension | NanoCorp | Soleur | Advantage |
|-----------|----------|--------|-----------|
| **Operating philosophy** | Fully autonomous, no human in the loop. | Founder-as-decision-maker. AI executes, human decides. | Depends on philosophy. Soleur for founders who want control + judgment compounding. |
| **Domain scope** | Narrow GTM revenue engine (naming, ICP, copy, content ops, outreach). | 8 domains incl. engineering, legal, finance, product, support. | Soleur (NanoCorp has no engineering/legal/finance/product/support depth). |
| **Shipped capability** | Content ops + lead-gen live; **ads "Coming Soon"**; no legal/high-stakes tasks. | Full lifecycle across 8 domains, dogfooded on soleur.ai (420+ PRs). | Soleur (breadth + proven execution). |
| **Knowledge persistence** | Cloud-hosted proprietary state. | Git-tracked compounding knowledge base the founder owns and can read/edit. | Soleur. |
| **Pricing model** | $30/mo (credit-based) + **20% revenue-withdrawal fee**. | Free OSS core; paid tier planned $49/mo flat, no revenue cut. | Soleur at any meaningful revenue (you keep 100%). |
| **Workflow** | One-prompt autonomous spin-up + scheduled runs. | Brainstorm → plan → implement → review → compound, founder-approved per stage. | Soleur (transparency + control). |
| **Backing** | Phospho Inc. / YC. | Independent, bootstrapped, dogfooded. | Neutral. |

## Talk Tracks

### "NanoCorp builds a whole company from one prompt. Soleur sounds like more work."

**Response:** "NanoCorp is a fast way to stand up a go-to-market revenue engine -- naming, copy, content, outreach -- and run it on autopilot. If that's all you need, it's well-built for it. Two things to know: their ads product is still 'Coming Soon,' and they explicitly say the system doesn't handle anything with legal accountability or where a single mistake is catastrophic. Soleur covers the other 70% of a real company -- engineering you actually ship, legal documents, finance, product strategy, support -- with you in the decision seat. NanoCorp spins up a storefront; Soleur runs a company."

### "NanoCorp is only $30/month."

**Response:** "Look at the full cost. NanoCorp adds a 20% revenue-withdrawal fee on top of the $30 base -- so the more you make, the more you pay, indefinitely. Soleur's planned $49/month is flat: you keep 100% of your revenue. At any meaningful revenue, Soleur is dramatically cheaper, and your institutional memory lives in your own git repo, not a vendor's database."

### "NanoCorp hit hundreds of thousands in ARR in days. That's traction."

**Response:** "Those numbers are worth a careful look -- the public claims range from '$740k ARR in 33 days' to '$193k in 3 days,' and the actual user-revenue leaderboard showed a couple hundred dollars across a few dozen transactions. The category is real -- Polsia just raised $30M at a $250M valuation -- but headline ARR claims in this space are marketing, not audited. Soleur competes on what the product actually does across eight domains with the founder in control, not on a viral launch number."

## Objection Handling

| Objection | Response |
|-----------|----------|
| "Autonomous, no babysitting -- that's the dream." | "For a single-channel revenue experiment, autonomy is great. For a company you intend to scale, the high-stakes calls -- pricing, legal exposure, product direction -- are exactly where you don't want a black box. NanoCorp itself fences those off as 'not reliable yet.' Soleur keeps you in the loop on the decisions that can kill a company and automates everything underneath." |
| "It already deploys landing pages and Stripe and runs ads." | "Landing page and Stripe, yes. Ads are listed as 'Coming Soon' on their own site as of this scan -- worth verifying before you count on it. Soleur's focus isn't one funnel; it's the full company, including the engineering, legal, and finance work NanoCorp doesn't touch." |
| "Phospho/YC backing makes it safer." | "Backing is a credibility signal, not a capability one. The question is coverage and control: NanoCorp is a narrow GTM engine; Soleur is an 8-domain organization where your knowledge compounds in a repo you own." |

## Convergence Watch

Review monthly. NanoCorp's closest analog is Polsia; watch both together.

| Trigger | Current Status (2026-06-08) | Action if Triggered |
|---------|---------------------------|-------------------|
| NanoCorp ships Google Search Ads (currently "Coming Soon") | Not live. | Update the "ads not live" talk tracks; the GTM engine becomes more complete. |
| NanoCorp adds engineering/legal/finance/product domains | Narrow GTM engine only. | Domain-coverage gap narrows; emphasize founder-in-the-loop + git-native owned memory. |
| NanoCorp publishes audited or third-party-verified ARR | Only contradictory self-reported claims. | Re-baseline the traction talk track against the verified figure. |
| NanoCorp drops or lowers the 20% revenue-withdrawal fee | $30/mo + 20% withdrawal fee. | Update pricing analysis; the "you keep 100%" wedge weakens. |

---

_Created: 2026-06-08 (cascade from full six-tier scan). Source: competitive-intelligence.md (2026-06-08)._
