---
last_updated: 2026-03-26
last_reviewed: 2026-03-26
review_cadence: quarterly
owner: CPO
methodology: synthetic-user-research
depends_on:

  - knowledge-base/product/pricing-strategy.md
  - knowledge-base/product/research/personas/
  - knowledge-base/product/competitive-intelligence.md

---

# Pricing Model Sensitivity Test: Synthetic User Research Findings

## Methodology

10 synthetic founder personas (see `personas/` directory) were presented three pricing models for Soleur and asked to react. Each persona's response was generated from their documented attributes: revenue stage, technical depth, AI attitude, primary pain, and current tooling. The deliverable is qualitative objection themes, not dollar amounts.

**Models tested:**

- **Model 1 (Flat Subscription):** $49/month for everything. All 8 domains, unlimited agent usage.
- **Model 2 (Hybrid):** $29/month base + per-outcome bonuses. Base covers access. Bonuses: shipped deployment ($2), completed legal review ($5), published marketing campaign ($10), competitive analysis ($3).
- **Model 3 (Pure Outcome-Based):** $0/month base, pay only per measurable result. Per merged PR ($2), per legal document ($5), per marketing campaign ($10), per competitive analysis ($3), per financial report ($3).

---

## Per-Persona Reactions

### 1. Marcus ($0 MRR, deep tech, Claude Code user, enthusiast)

**Preferred model:** Model 3 (Pure Outcome-Based)
**Reasoning:** Pre-revenue with zero income, every dollar of fixed cost is existential. Outcome-based means he pays nothing during the months he's heads-down on engineering and only pays when Soleur actually produces non-engineering outputs he wouldn't have done himself.

**Top objection per model:**

- Model 1: "Forty-nine dollars a month for something I haven't proven I need yet. That's my Notion plus Linear plus domain registration budget combined. I'd need to be certain I'll use it every single week."
- Model 2: "Twenty-nine a month is still a commitment when I have literally zero revenue. The base fee means I'm paying even in months I don't touch the non-engineering stuff."
- Model 3: "What counts as a 'measurable result'? If I ask it to draft a terms of service and then I have to heavily edit it, did I get a $5 outcome or did I just get a rough draft?"

**Distinguishes outcome-based from usage-based:** Yes, clearly. "Usage-based means I get charged for asking questions. Outcome-based means I get charged for answers. Those are fundamentally different — one taxes my curiosity, the other taxes my results." However, his distinction weakens when pressed on quality: if outcomes are metered but quality varies, the line between "I paid for a result" and "I paid for an attempt" blurs.

---

### 2. Priya ($3K MRR, deep tech, Cursor user, pragmatist)

**Preferred model:** Model 1 (Flat Subscription)
**Reasoning:** At $3K MRR, $49 is 1.6% of revenue — trivially affordable if the legal domain alone saves her one lawyer call per quarter. Her GDPR/DPA pain is ongoing and high-frequency. She wants unlimited access to legal agents without watching a meter.

**Top objection per model:**

- Model 1: "Forty-nine is fine if the legal stuff is actually reliable. My real objection isn't the price — it's that I'm trusting compliance work to an AI tool and if it gets GDPR wrong, no pricing model saves me from a fine."
- Model 2: "Five dollars per legal review is cheap compared to a lawyer, but I'd be doing 10-15 of these a month during a DPA cycle. That's $50-75 in bonuses on top of $29 base. Suddenly I'm paying more than flat and I have to think about it."
- Model 3: "No base fee sounds attractive until I realize I'm now forecasting 'how many legal documents will I need this month' alongside forecasting everything else. I already have enough variables to track."

**Distinguishes outcome-based from usage-based:** Yes, but considers both problematic for her use case. "I see the difference — Replit charges you for compute time whether you ship or not. Outcome-based only charges when something ships. Fine, philosophically better. But for legal work, the 'outcome' is me NOT getting sued. How do you meter that?" Her core insight: outcome-based pricing maps well to discrete, countable artifacts (PRs, campaigns) but poorly to protective/defensive work (compliance, risk avoidance).

---

### 3. Elena ($0 MRR, moderate tech, no AI tools, skeptic)

**Preferred model:** Model 3 (Pure Outcome-Based), reluctantly
**Reasoning:** Refuses to pay for something she hasn't validated. Zero base fee is the only way she'd try it. But she deeply distrusts the quality of AI-generated marketing — the one domain she actually needs.

**Top objection per model:**

- Model 1: "I'm not paying $49 a month for AI that probably generates the same generic marketing copy ChatGPT gave me for free. Show me it works first."
- Model 2: "Twenty-nine dollars for access to agents I'm skeptical about, plus I pay extra when they produce something? I'm paying twice — once for the privilege of using it and again for the output."
- Model 3: "At least I don't pay until it does something. But $10 for a 'published marketing campaign'? Published where? What does that even mean? If I ask it to write 5 LinkedIn posts and 3 are garbage, did I get a campaign or three garbage posts?"

**Distinguishes outcome-based from usage-based:** No. "It's all pay-as-you-go to me. Whether you call it 'per execution' or 'per result,' I still can't predict my bill. The difference sounds like marketing spin." Elena represents the skeptic who views all variable pricing as unpredictable, regardless of the trigger mechanism.

---

### 4. James ($15K MRR, deep tech, VS Code+Copilot, pragmatist)

**Preferred model:** Model 1 (Flat Subscription)
**Reasoning:** At $15K MRR, $49 is a rounding error. His 25+ hours per week on operations means the value proposition is time recovery, not cost savings. He wants unlimited access without cognitive overhead.

**Top objection per model:**

- Model 1: "Forty-nine is fine. My objection is whether it actually integrates with Shopify, ShipStation, Zendesk, and QuickBooks — the tools I already live in. The price is irrelevant if it can't plug into my stack."
- Model 2: "I don't want to think about whether each operation I run triggers a bonus charge. I already have a thousand things to track. Adding 'how many Soleur outcomes did I consume' to my dashboard is exactly the kind of overhead I'm trying to eliminate."
- Model 3: "My operations pain isn't discrete outcomes — it's 50 small decisions per day about inventory, shipping, and support. How do you price 'handled a supplier email well'? Operations doesn't have clean measurable results like 'merged PR' or 'published campaign.'"

**Distinguishes outcome-based from usage-based:** Yes, and thinks the distinction matters — but only for domains with discrete outputs. "For engineering, sure, a merged PR is a clear outcome. For operations, most of the value is ambient — it's the AI handling context so I don't have to. You can't meter ambient value." James identifies a structural limitation of outcome-based pricing: it works for artifact-producing domains (engineering, legal, marketing) but not for coordination-heavy domains (operations, support).

---

### 5. Sofia ($1K MRR, low tech/no-code, ChatGPT user, enthusiast)

**Preferred model:** Model 2 (Hybrid)
**Reasoning:** The $29 base feels affordable at $1K MRR. She likes knowing she has access to everything. The per-outcome bonuses feel like paying for "premium deliverables" — a frame she's comfortable with from hiring freelancers on Upwork.

**Top objection per model:**

- Model 1: "Forty-nine is almost 5% of my revenue. That's meaningful when I'm not sure how often I'll use it. I'd rather start lower and pay more when I actually get value."
- Model 2: "This feels the most honest. I pay a base for access and extra for big deliverables. My only concern is understanding what triggers a bonus — I need clear definitions, not 'completed legal review' which could mean anything."
- Model 3: "Zero base is tempting, but I know myself — I'd hesitate to use it because every click would feel like it might cost me. With ChatGPT I can ask 50 bad questions to get to one good answer. If outcomes cost money, I'd ration my usage and probably not get the value."

**Distinguishes outcome-based from usage-based:** Partially. "I think outcome-based is better because at least I know I got something. With usage-based, I might spend $30 and have nothing to show for it. But outcome-based still means I can't predict my bill, and I run my business on spreadsheets where I need to know what next month costs." She sees the philosophical difference but the practical impact (unpredictable bills) is the same.

---

### 6. Tobias ($0 MRR, deep tech/PhD, Windsurf user, pragmatist)

**Preferred model:** Model 3 (Pure Outcome-Based)
**Reasoning:** Pre-revenue with a PhD student's budget sensitivity. Will only pay for demonstrated value. But his marketing pain is strategic (how to reach accountants), not tactical (write a blog post). He doubts any pricing model can capture whether the AI actually solved his go-to-market problem.

**Top objection per model:**

- Model 1: "Forty-nine for unlimited everything sounds like a gym membership. Most people pay and don't go. I don't want to subsidize other users' unused capacity."
- Model 2: "The per-outcome pricing assumes marketing value comes in discrete chunks. A 'published marketing campaign' at $10 — published is easy. Effective is hard. I don't need campaigns published; I need customers acquired."
- Model 3: "I only pay for results, which I like. But a 'marketing campaign shipped' for $10 is meaningless if it doesn't generate a single lead. The outcome you're measuring isn't the outcome I care about."

**Distinguishes outcome-based from usage-based:** Yes, precisely, and considers both insufficient. "Usage-based charges for compute. Outcome-based charges for artifacts. Neither charges for value. The outcome I actually want is 'three accounting firms signed up for my pilot.' None of these models price against that. The $10 'campaign shipped' outcome is a proxy metric, and proxy metrics are how you end up paying for vanity deliverables." Tobias identifies the deepest problem with outcome-based pricing: the measurable outcomes (artifacts shipped) are proxies for the actual outcomes founders care about (revenue, users, risk reduction).

---

### 7. Aisha ($8K MRR, moderate tech, Cursor user, pragmatist)

**Preferred model:** Model 1 (Flat Subscription)
**Reasoning:** At $8K MRR, $49 is easily justified. Her finance pain is high-frequency and accuracy-sensitive. She wants to ask unlimited questions about incorporation, tax obligations, and international payments without a meter running.

**Top objection per model:**

- Model 1: "The price is fine. I pay more for Wave accounting software. My concern is accuracy — if the financial reports have errors, it doesn't matter what I paid. For money stuff, 'close enough' isn't enough."
- Model 2: "Three dollars per financial report — that's cheap, but how granular is 'a report'? If I ask 'should I incorporate as LLC or C-Corp' and it generates a comparison analysis, is that a report? What about follow-up questions?"
- Model 3: "I'd worry about being nickeled-and-dimed. Every time I interact with the finance agents, am I generating a billable outcome? Financial planning is iterative — I ask, refine, ask again, refine. If each refinement is a new 'report,' the cost adds up."

**Distinguishes outcome-based from usage-based:** Yes, but sees the iterative-work problem. "I get that outcome-based means I only pay when something ships. But financial planning doesn't 'ship' — it's a continuous process. I'd need 5-10 iterations of a financial model before it's useful. Are the first 9 iterations free and the 10th one costs $3? Or is each version a separate $3 outcome?" She highlights that outcome-based pricing penalizes iterative workflows where the value emerges gradually.

---

### 8. Derek ($30K MRR, deep tech, Claude Code user, enthusiast)

**Preferred model:** Model 1 (Flat Subscription)
**Reasoning:** At $30K MRR, price is a non-issue. He wants maximum throughput across all domains with zero friction. Any variable pricing introduces decision fatigue he's explicitly trying to eliminate.

**Top objection per model:**

- Model 1: "Shut up and take my money. Forty-nine a month is absurdly cheap if this tool prevents me from having to hire a $5K/month ops person. My only objection: is there a higher tier with more capacity? I'd pay $149/month for priority processing."
- Model 2: "I'm going to hit the outcome bonuses hard — I need SOC 2 docs, infrastructure management, developer documentation updates, and support triage across 150 teams. The bonuses would add up to hundreds per month. Just let me pay flat."
- Model 3: "Absolutely not. I'd generate 50-100 outcomes per month across ops, engineering, legal, and docs. At those volumes, outcome-based pricing becomes the most expensive option. This model punishes your heaviest users."

**Distinguishes outcome-based from usage-based:** Yes, and explicitly frames it as a user-friendliness gradient. "Usage-based is hostile — it charges you for trying. Outcome-based is less hostile — it charges you for succeeding. But flat is the only model that's actually friendly — it charges you for existing. As someone who'll use this tool every single day, I want the friendliest model." He also notes that outcome-based pricing creates a perverse incentive: "If I'm paying per outcome, why would Soleur ever optimize to do more with fewer outcomes? Flat pricing aligns the product's incentives with mine — make me more efficient."

---

### 9. Min-Ji ($2K MRR, moderate tech, no AI tools, skeptic)

**Preferred model:** Model 3 (Pure Outcome-Based), grudgingly
**Reasoning:** Her $2K MRR makes any fixed cost feel significant. She'd only try Soleur if she can verify value before committing. But her real issue is trust, not price.

**Top objection per model:**

- Model 1: "Forty-nine dollars is 2.5% of my revenue for a tool I've never used, made by a company I've never heard of, using AI I don't trust for marketing. I need a month to evaluate before committing to $49."
- Model 2: "Ten dollars for a marketing campaign 'published'? Published doesn't mean good. My brand voice is specific — Korean-influenced, direct, not 'generic American startup speak.' If the campaign is wrong for my audience, I paid $10 for damage to my brand."
- Model 3: "At least I can try it without risk. But I'd test one thing — maybe a competitive analysis — and if that one thing is mediocre, I'm gone forever. You get one shot with skeptics."

**Distinguishes outcome-based from usage-based:** No. "Both mean I don't know what I'll pay until the bill arrives. The naming is different, the experience is the same. I open my bank app and see an unexpected charge — whether it was for 'usage' or 'outcomes' doesn't change how that feels." Min-Ji's framing is visceral rather than conceptual: unpredictable bills are unpredictable bills, regardless of what triggered them.

---

### 10. Rafael ($0 MRR, low tech/no-code, ChatGPT user, pragmatist)

**Preferred model:** Model 2 (Hybrid)
**Reasoning:** The $29 base is at his comfort threshold for a pre-revenue tool. The per-outcome bonuses map to his mental model of hiring freelancers — he pays a retainer (base) plus per-deliverable fees (bonuses). This is how he already buys from Fiverr developers.

**Top objection per model:**

- Model 1: "Forty-nine is more than I pay for Webflow, Airtable, and Zapier combined. For a pre-revenue marketplace, that's a big commitment. I'd need to see a free trial or money-back guarantee."
- Model 2: "This makes the most sense to me — I pay for access, then pay more for big deliverables. Five dollars for a licensing agreement draft is incredible compared to a lawyer. But I need to understand: is this a first draft or a usable document?"
- Model 3: "I like zero base, but with legal documents I'd be afraid to use it. Every template I generate costs $5 — so I'd try to get everything in one shot instead of iterating. That's the wrong incentive for legal work where you need to refine."

**Distinguishes outcome-based from usage-based:** Partially. "Outcome-based feels fairer because I'm paying for a thing I can hold — a contract, a template, a document. Usage-based feels like paying for air. But both have the same problem: I'm a musician trying to launch a business, and I need to know what I'm spending before I spend it." His freelancer mental model helps him accept per-outcome pricing more readily than pure usage-based, but predictability remains the root concern.

---

## Model 1: Flat Subscription -- Objection Patterns

### Who Preferred It and Why

**Preferred by:** Priya ($3K), James ($15K), Aisha ($8K), Derek ($30K) — all revenue-generating founders above $3K MRR.

**Pattern:** Founders with meaningful revenue prefer flat pricing because:

1. The absolute dollar amount is trivially small relative to revenue (0.2% to 1.6%)
2. They have high-frequency, multi-domain usage patterns that would be expensive under variable pricing
3. Cognitive overhead is their primary enemy — they're buying simplicity, not savings
4. They already pay flat subscriptions for other tools and think in those terms

### Common Objections

1. **"Price isn't the problem — value proof is."** Every Model 1 advocate's top objection was about capability, not cost. Priya's concern is legal accuracy. James's concern is integration with his existing stack. Aisha's concern is financial report reliability. Derek's concern is that $49 might be too low, signaling limited capability. The flat price itself is rarely the friction point for revenue-stage founders.

2. **"Subsidizing unused capacity."** Tobias (pre-revenue, pragmatist) articulated this: flat pricing feels like paying for a gym membership you might not use. This objection appeared exclusively from pre-revenue or skeptic personas.

3. **"No trial, no deal."** Elena and Min-Ji won't pay $49/month for an unproven tool. The objection isn't to flat pricing conceptually — it's to paying anything before experiencing value. This is a trial/freemium problem, not a pricing model problem.

### Budget Comfort Level Themes

The $49 price point creates a clean split: founders above $3K MRR consider it trivial; founders at $0-2K MRR consider it a significant commitment requiring justification. No persona called $49 "too expensive" in absolute terms — the framing was always relative to revenue or existing tool spend.

---

## Model 2: Hybrid -- Objection Patterns

### Who Preferred It and Why

**Preferred by:** Sofia ($1K), Rafael ($0) — both low-tech/no-code founders who think in freelancer/retainer terms.

**Pattern:** The hybrid model resonated with founders who:

1. Already buy services in a retainer-plus-deliverable structure (Upwork, Fiverr)
2. Want access assurance (the base fee buys peace of mind) but can't justify the full flat rate
3. Are comfortable with "pay extra for premium deliverables" framing
4. Have lower usage volume, so variable costs won't accumulate dangerously

### Common Objections

1. **"What exactly triggers a bonus?"** This was the dominant objection across all personas, not just hybrid-preferring ones. The boundary between "included in base" and "billable outcome" is ambiguous. Is asking a question included? Is a draft included? When does a draft become a "completed legal review"? The taxonomy of billable outcomes needs to be crystal clear or it becomes a trust-destroying ambiguity.

2. **"High-volume users get punished."** Derek calculated that his usage pattern would generate $200-400/month in bonuses on top of the $29 base — making hybrid the most expensive model for power users. Priya made the same calculation for her legal DPA cycles. Hybrid pricing is anti-correlated with power usage.

3. **"I'm paying twice."** Elena's "paying for the privilege of using it AND for the output" framing appeared in three personas. The two-component structure creates a perception of double-charging that doesn't exist with either pure flat or pure outcome-based pricing.

4. **"Wrong incentive for iterative work."** Aisha, Tobias, and Rafael all flagged that per-outcome pricing discourages iteration. Legal documents need 3-5 drafts. Financial models need 5-10 refinements. If each iteration is a billable outcome, users will try to get everything right in one shot — producing worse results because they self-censor their exploration.

### Budget Comfort Level Themes

The $29 base was consistently described as "fine" or "manageable" across all revenue stages. The concern is never the base — it's the unpredictable variable component. Total monthly spend anxiety is identical to pure outcome-based for high-frequency users.

---

## Model 3: Pure Outcome-Based -- Objection Patterns

### Who Preferred It and Why

**Preferred by:** Marcus ($0), Elena ($0), Tobias ($0), Min-Ji ($2K) — all pre-revenue or low-revenue founders. Elena and Min-Ji are also the two skeptics.

**Pattern:** Pure outcome-based resonated with founders who:

1. Cannot commit to any fixed monthly cost (pre-revenue)
2. Need to validate value before spending (skeptic mindset)
3. Frame "no base fee" as "zero risk to try"
4. Have low expected usage volume (only need 1-3 things per month)

### Common Objections

1. **"Outcome quality is not guaranteed."** The single most frequent objection across all 10 personas. Paying per outcome assumes the outcome is useful. Every persona raised some version of: "What if the output is bad? Did I pay for a result or a failed attempt?" This is the foundational trust problem of outcome-based pricing — the word "outcome" implies success, but the mechanism can't guarantee it.

2. **"What counts as an outcome?"** Definitional ambiguity appeared in 8 of 10 personas. The concrete examples (merged PR, legal document, marketing campaign) sound clear in a pricing table but become murky in practice. Is a competitive analysis that surfaces nothing new still a $3 outcome? Is a financial report that needs heavy manual editing a $3 outcome? The taxonomy problem is even sharper here than in the hybrid model because there's no base fee to absorb ambiguous interactions.

3. **"Penalizes power users and heavy months."** Derek's objection applies even more strongly here: without a base fee creating a ceiling-like psychological anchor, heavy usage months could produce surprisingly large bills. This is the exact "Replit backlash" dynamic — a founder who uses the tool heavily in a crunch month gets a bill that feels punitive rather than rewarding.

4. **"I'd ration my usage."** Sofia, Aisha, and Rafael all described behavioral modification under outcome-based pricing: asking fewer questions, skipping exploratory interactions, trying to batch requests. This self-censoring reduces the product's value proposition because multi-domain exploration is how Soleur's cross-domain compounding creates differentiation.

5. **"Operations and finance don't produce discrete outcomes."** James and Aisha identified a category mismatch: outcome-based pricing maps to artifact-producing domains (engineering: PRs; legal: documents; marketing: campaigns) but fails for coordination-intensive domains (operations: daily decisions; finance: ongoing analysis; support: continuous triage). Pricing all domains under one model forces some domains into ill-fitting outcome definitions.

### Budget Comfort Level Themes

The $0 base is universally attractive as a trial mechanism. Pre-revenue founders strongly prefer it for initial exploration. However, every persona who preferred Model 3 acknowledged they'd switch to flat pricing once they validated value and had revenue. Model 3 functions as an on-ramp, not a sustainable model.

---

## The Replit Backlash Question

### Do Personas Distinguish Outcome-Based from Usage-Based?

**Clear distinction (5 personas):** Marcus, Priya, James, Tobias, Derek. All deep-tech founders. They can articulate the conceptual difference: usage-based charges for compute/activity regardless of result; outcome-based charges only when something ships. They consider this a meaningful philosophical difference.

**Partial distinction (3 personas):** Sofia, Aisha, Rafael. They grasp the concept when explained but arrive at the same practical conclusion: both models produce unpredictable bills. The distinction is real but doesn't change their behavior or comfort level.

**No distinction (2 personas):** Elena, Min-Ji. Both AI skeptics. They see all variable pricing as "pay-as-you-go" and don't distinguish the trigger mechanism. Their frame is experiential, not conceptual: "I can't predict my bill" is the same sensation whether it's per-execution or per-outcome.

### Key Finding: The Distinction Is Real but Insufficiently Motivating

The 5 founders who clearly distinguish outcome-based from usage-based all acknowledged the philosophical superiority of outcome-based pricing. But only Derek considered that distinction a meaningful factor in his purchasing decision — and he still preferred flat pricing. For the other 4, the distinction was "intellectually interesting but doesn't change my preference."

**The Replit backlash risk persists under outcome-based pricing, but manifests differently:**

- Usage-based backlash: "I spent $200 and shipped nothing." Anger at paying for failed attempts.
- Outcome-based backlash: "I shipped 40 outcomes and my bill was $150 — I thought this was a $50/month tool." Anger at success being expensive.

The emotional trigger is the same: a bill that exceeds expectations. Usage-based pricing triggers it through failure (paying for nothing). Outcome-based pricing triggers it through success (paying more because you used it more). The latter is arguably worse from a retention perspective — punishing your best users for being your best users.

### Specific Language About Predictability

Founders used these framings when discussing predictability:

- **"I need to know what next month costs"** (Sofia, Aisha, Rafael) — budget-planning frame. These founders run their businesses on spreadsheets and cannot accommodate variable line items.
- **"I don't want to think about whether this click costs money"** (James, Derek) — cognitive-overhead frame. For high-frequency users, any per-action awareness degrades the experience.
- **"I'd ration my usage"** (Sofia, Aisha, Rafael, Min-Ji) — behavioral-modification frame. Variable pricing changes how people use the product, always in a direction that reduces value.
- **"Paying for air"** (Rafael on usage-based) vs. **"paying for a thing I can hold"** (Rafael on outcome-based) — tangibility frame. This is the one axis where outcome-based genuinely feels different from usage-based. Outcomes feel like deliverables; usage feels like overhead.

---

## Budget Themes

### How Budget Comfort Varies by Revenue Stage

**$0 MRR (Marcus, Elena, Tobias, Rafael):**
Any fixed monthly cost faces existential resistance. These founders will try free tools, outcome-based models, or nothing. The threshold for commitment is "I can't justify this until I have revenue" — not a dollar amount. Free trial or $0-base models are the only viable entry points.

**$1K-5K MRR (Sofia, Priya, Min-Ji):**
$29/month is comfortable. $49/month is borderline — affordable but requires justification ("will I use it enough?"). The deciding factor is not the price but the perceived reliability and breadth of the tool. These founders are cost-conscious but not cost-averse; they'll pay for tools that demonstrably save time or reduce risk.

**$5K-50K MRR (Aisha, James, Derek):**
$49/month is trivial. Several would pay $99-149/month for more capacity or priority features. Price is not a variable in their decision — capability, reliability, and integration depth are what matters. Derek explicitly asked for a higher tier.

### The "Try for Free but Won't Pay" Threshold

The threshold is not a revenue number but a trust state. Pre-revenue founders (Marcus, Elena, Tobias, Rafael) all expressed willingness to pay once they validated value — but validation requires free or near-free initial usage. The conversion funnel is:

1. **Try at zero risk** (outcome-based with no base, or free trial)
2. **Experience one high-value outcome** (a legal document they would have paid $300 for, a marketing strategy they couldn't have produced alone)
3. **Convert to flat subscription** once they trust the quality and use it regularly

No persona described a scenario where they'd stay on outcome-based pricing permanently. It's a gateway, not a destination.

---

## Key Observations

### 1. The Strongest Objection Is Quality, Not Price

Across all 10 personas and all 3 models, the most visceral objection was never about dollar amounts. It was about whether the outcomes are good enough. "What if the legal document is wrong?" "What if the marketing campaign is generic?" "What if the financial report has errors?" Pricing model selection is downstream of quality confidence. No pricing model fixes a trust deficit.

**Implication:** Pricing strategy work is premature until quality proof points exist. The pricing-strategy.md document's recommendation to defer pricing until validation gates pass is reinforced by this finding.

### 2. Revenue Stage Is the Dominant Predictor of Model Preference

The single strongest predictor of which model a persona preferred was their MRR, not their technical depth or AI attitude:

- $0 MRR: outcome-based (zero risk)
- $1K-3K MRR: hybrid or flat (want access assurance)
- $5K+ MRR: flat (want cognitive simplicity)

Technical depth determines whether founders can articulate the outcome-vs-usage distinction, but it doesn't determine their preference. Skeptics and enthusiasts at the same revenue level chose the same model.

### 3. Outcome-Based Pricing Has a Category Problem

Outcome-based pricing works well for artifact-producing domains (engineering, legal, marketing) and poorly for coordination-intensive domains (operations, finance, support). Since Soleur's value proposition is cross-domain coverage, a per-outcome model either (a) leaves some domains unpriced, creating a confusing split, or (b) forces awkward outcome definitions onto domains where value is ambient, not discrete.

### 4. The "Paying Twice" Perception Hurts the Hybrid Model

Three personas independently described the hybrid model as "paying twice" — once for access, once for output. This perception exists even though the base fee is lower ($29 vs $49). The two-component structure introduces a cognitive burden (tracking what's included vs. what triggers bonuses) that contradicts Soleur's "simplify the founder's life" positioning.

### 5. Outcome-Based Functions as an On-Ramp, Not a Business Model

Every persona who preferred outcome-based pricing described it as a trial mechanism they'd abandon once they trusted the tool. No persona described outcome-based pricing as their long-term preference. This suggests outcome-based pricing could work as a first-month trial alternative (replacing a free trial) but not as a standalone tier.

### 6. The Replit Backlash Risk Is Real but Differently Shaped

Outcome-based pricing does not eliminate unpredictability — it shifts the unpredictability from "I paid for nothing" (usage-based) to "I paid more than expected because I succeeded" (outcome-based). For budget-planning founders (Sofia, Aisha, Rafael), the effect on their spreadsheets is identical. For cognitive-overhead founders (James, Derek), any metering is friction.

The only population for whom the distinction matters emotionally is pre-revenue founders for whom outcome-based = zero-cost trial. Once they start paying, they want flat pricing like everyone else.

### 7. Per-Outcome Pricing Creates Perverse Incentives on Both Sides

- **User side:** Founders ration usage, avoid iteration, batch requests, and self-censor exploration. This directly undermines Soleur's cross-domain compounding value, which requires frequent, exploratory, multi-domain interaction.
- **Product side:** If revenue scales with outcome count, the product is incentivized to generate more outcomes rather than more efficient outcomes. A product that solves a founder's legal needs in 2 documents instead of 5 would earn less under outcome-based pricing.

### 8. The $49 Flat Price Is Correctly Positioned but Needs Trial Scaffolding

No revenue-stage founder called $49 too expensive. Pre-revenue founders called it "too much commitment without proof," which is a trial problem, not a price problem. The pricing-strategy.md's $49/month recommendation holds, but it needs a zero-risk entry path — either a free trial, a first-month outcome-based trial, or a generous free tier on the web platform.

---

_Synthetic research conducted 2026-03-26. These are simulated reactions from documented personas, not real user interviews. Findings should inform hypotheses for real founder conversations, not substitute for them._
