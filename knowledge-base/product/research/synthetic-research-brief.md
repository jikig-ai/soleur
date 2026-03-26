---
last_updated: 2026-03-26
last_reviewed: 2026-03-26
review_cadence: quarterly
owner: CPO
depends_on:
  - knowledge-base/product/business-validation.md
  - knowledge-base/marketing/validation-outreach-template.md
  - knowledge-base/project/specs/feat-product-strategy/interview-guide.md
  - knowledge-base/product/pricing-strategy.md
---

# Synthetic Research Brief: Findings for the Next 8 Founder Interviews

## Executive Summary

10 synthetic founder personas were run through Soleur's interview guides, three value proposition framings, and three pricing models. Five findings should change how the next 8 real interviews are conducted:

**1. Three pain archetypes exist, but the interview guides only surface one well.** Burden pain (too much time on wrong tasks) is captured. Avoidance pain (not doing critical work at all) and anxiety pain (worry without action) are missed. Add the avoidance question ("What business tasks do you know you should be doing but aren't?") and the emotional weight question ("Which tasks keep you up at night?") to both guides.

**2. "Stop hiring, start delegating" is the lead framing.** Pain-point framing won for 7/10 personas. CaaS requires market education a bootstrapped company can't afford. Tool-replacement fails for pre-revenue founders (6/10 of the cohort) who don't have tool spend to replace. But the "handles 7 of them" claim needs softening to "helps you tackle 7" for pragmatists.

**3. The "memory" differentiator is the buried lead.** Persistent, compounding context across departments generated the strongest unprompted positive reactions. Four personas independently identified it as the feature that separates Soleur from "just use ChatGPT." Yet it's a subordinate clause in all three framings. Test leading with it: "The AI that already knows your business."

**4. Outcome-based pricing functions as an on-ramp, not a business model.** Every persona who preferred outcome-based pricing described switching to flat pricing once trust was established. No persona wanted to stay on outcome-based long-term. It could replace the free trial, but not the subscription.

**5. The $49/month price is correctly positioned but needs zero-risk trial scaffolding.** No revenue-stage founder called $49 too expensive. Pre-revenue founders called it "too much commitment without proof" — a trial problem, not a price problem.

---

## Interview Guide Improvements

### Questions to Rewrite

| Original | Problem | Rewrite |
|----------|---------|---------|
| 15-min Q5: "If you had AI agents handling [pain] — would you trust the output?" | "AI agents" is jargon. Binary trust question primes for "no." | "If [pain] was handled for you automatically, what's the first thing you'd check before using the output?" |
| 15-min Q6: "What would 'good enough' look like?" | Domain-unfamiliar founders can't define quality for domains they don't understand. | "If you got a [legal doc / marketing plan / financial report] tomorrow, what would make you confident enough to use it?" |
| 30-min Q5: "Which tasks felt like a distraction?" | "Distraction" fails when pain IS core work or manifests as avoidance. | "Which of those did you resent doing? And which should you be doing but aren't?" |
| 30-min Q11: "How much time per week would that save?" | Time is the wrong unit for anxiety, zero-baseline, and effectiveness pain. | "What would change for you if that was handled? What would you do with that space?" |
| 30-min Q12: "What would you pay for that?" | Pre-revenue founders have no price anchor. Silence makes them guess low. | First establish the alternative cost ("What has this cost you so far — in money, delays, or missed opportunities?"), THEN ask what they'd pay. |

### Questions to Add

| New Question | Why It's Missing | Where to Place |
|-------------|-----------------|----------------|
| "What business tasks do you know you should be doing but aren't? What's stopping you?" | 3/10 personas have avoidance pain that current guides miss entirely | After Q1 in both guides |
| "What happens if you keep doing things this way for the next 6 months?" | Surfaces trajectory and compounding cost, not just current pain | After Q4 in 30-min, after Q2 in 15-min |
| "What have you already tried to solve this? What worked, what didn't?" | Many tried non-AI alternatives (lawyers, freelancers, templates). Understanding why those failed reveals what the new solution must do differently. | After Q3 in 15-min, after Q6 in 30-min |
| "What would need to happen for you to solve this in the next 30 days?" | Separates chronic pain from acute buying triggers | End of 30-min guide, before pricing question |
| "If this task was handled for you, how would you know if it was done wrong?" | Tests whether the founder can evaluate quality — critical for AI trust model | After trust question in both guides |
| "Which of these tasks keeps you up at night — not the time-consuming ones, the scary ones?" | Emotional weight is often a stronger buying signal than time cost | After Q2 in 15-min, after Q5 in 30-min |

### Interview Technique Changes

- **Establish alternative costs BEFORE asking WTP.** Revenue founders anchor on alternatives (Priya: $800/30min lawyer; Derek: $15K consultant). Pre-revenue founders have no anchor. Ask "what has this cost you?" first.
- **Expand the domain checklist.** Add "HR/People" and "Product Strategy" to the 30-min Q8 domain list. Several personas revealed secondary pain when prompted that they didn't mention unprompted.
- **Reframe trust questions around outcomes, not mechanisms.** "Would you trust AI?" triggers identity-level skepticism. "What would you check before using the output?" triggers practical evaluation.

---

## Value Prop Recommendation

### Lead Framing: Pain-Point (modified)

**Primary headline:** "Stop hiring, start delegating"
**Modified pitch:** "You're doing 8 jobs. Soleur helps you tackle 7 of them — marketing campaigns, legal contracts, competitive analysis, financial planning — delegated to AI agents that remember everything about your business."

Key change: "handles 7" softened to "helps you tackle 7" for pragmatist credibility.

### Memory-First Variant (recommended for A/B test)

**Headline:** "The AI that already knows your business"
**Pitch:** "Every time you use Soleur, it learns more about your company. Your marketing agent knows your brand guide. Your legal agent knows your compliance requirements. Your product agent knows your competitive landscape. One compounding knowledge base across 8 departments."

This was not one of the three tested framings, but it emerged from the strongest unprompted positive reactions across multiple personas. Test it.

### Segment-Specific Variations

| Segment | Lead With |
|---------|-----------|
| $10K-50K MRR (highest intent) | "Stop hiring, start delegating" — they're at the hire/don't-hire fork |
| $1K-10K MRR (pragmatists) | "Helps you tackle the 7 jobs that aren't coding" — softened claim |
| Pre-revenue (enthusiasts) | "The AI that already knows your business" — memory/compounding hook |
| Skeptics | Don't lead with framing — lead with a case study or demo output |

### Retire Tool-Replacement Framing

Tool-replacement ("One platform, 8 departments, replace $765-3,190/month") should be retired as a primary framing. It failed for 6/10 personas. It may work as a secondary proof point on the pricing page for later-stage founders, but not as a headline.

---

## Pricing Signals

### Model Preference by Revenue Stage

| Revenue | Preferred Model | Why |
|---------|----------------|-----|
| $0 MRR | Outcome-based | Zero risk — only pay if it works |
| $1-5K MRR | Flat or hybrid | Want access assurance, can justify $29-49/month |
| $5K+ MRR | Flat ($49/month) | Cognitive simplicity, price is trivial |

### Key Objection Themes

1. **Quality, not price, is the dominant objection.** "What if the legal document is wrong?" outweighed every pricing concern across all 10 personas and all 3 models.

2. **Outcome-based = on-ramp, not model.** Every persona who preferred outcome-based described switching to flat once trust was established. Use it as a first-month trial mechanism, not a permanent tier.

3. **Hybrid triggers "paying twice" perception.** Three personas independently described the $29 base + per-outcome bonuses as double-charging. The two-component structure contradicts "simplify the founder's life."

4. **Per-outcome creates perverse incentives.** Users ration usage and avoid exploration — directly undermining the cross-domain compounding that is Soleur's moat.

5. **The Replit backlash transfers, differently shaped.** Outcome-based shifts unpredictability from "paid for nothing" to "paid more because I succeeded." For budget-planning founders, the effect on their spreadsheets is identical.

### Actionable Pricing Interview Changes

- Ask real founders: "If you could try this at zero risk for the first month — paying only for completed outcomes — and then switch to $49/month flat, would you prefer that over a 14-day free trial?"
- Separate the pricing conversation into two phases: (a) "what would you pay monthly?" and (b) "would you prefer paying per outcome during a trial period?"

---

## Confidence Notes

### High Confidence (consistent across 7+ personas)

- Pain-point framing resonates more than CaaS or tool-replacement
- $49/month flat is correctly positioned for revenue-stage founders
- Quality/trust is the #1 objection regardless of pricing model
- Pre-revenue founders resist any fixed monthly commitment
- "Memory" / persistent context generates strong positive reactions
- Interview Q4 ("when did you think 'I need to hire'") is the strongest question

### Low Confidence (split or contradictory)

- Whether outcome-based pricing is distinguished from usage-based (5 distinguish, 3 partially, 2 don't)
- Whether the CaaS framing has any viable segment (only 1 persona responded, possibly an outlier)
- Specific dollar amounts / budget ranges (synthetic personas can't provide reliable WTP data)
- Whether the hire-vs-AI trigger is the right ICP filter (strong signal from Derek at $30K MRR, but n=1 in that revenue band)

---

## Limitations

These findings are **hypotheses, not validation evidence.** They inform how to conduct real interviews — they do not pass any validation gate.

**Specific limitations:**

1. **Novel category risk.** CaaS is a novel category. Synthetic personas reasoned about known pain points (hiring costs, tool sprawl) but may not accurately simulate reactions to a category they've never encountered.

2. **No real emotional data.** Synthetic personas simulate rational responses. Real founders have emotional reactions (excitement, skepticism, frustration) that change the conversation trajectory in ways simulation cannot capture.

3. **Pricing signals are directional only.** The dollar amounts, budget ranges, and model preferences are the model's predictions about its own predictions. Treat objection themes as reliable; treat specific numbers as unreliable.

4. **Persona diversity is designed, not discovered.** The 10 personas were constructed to cover the ICP matrix. Real interview cohorts will have clustering and gaps that can't be predicted.

5. **Confirmation risk.** These personas were designed with knowledge of Soleur's value proposition. Real founders who have never heard of CaaS may react in fundamentally different ways.

---

_Synthetic research conducted 2026-03-26. Source: 10 personas x 3 research gates (interview prep, value prop, pricing). All findings are hypotheses to be tested against real founder conversations._
