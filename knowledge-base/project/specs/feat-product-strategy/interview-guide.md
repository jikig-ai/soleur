# Interview Guide: Product Strategy Validation

## 1. Purpose

This guide exists to run 10 structured problem interviews with solo founders. The interviews validate one question: **do solo founders independently describe multi-domain pain that a CaaS platform can solve, and will they pay for it?**

This is not a sales call. There is no product demo. The interviewer does not describe Soleur, show features, or pitch. The goal is to listen to founders describe their own pain in their own words, then measure whether that pain converges on domains Soleur serves.

If a founder asks about the product, defer: "I'm happy to share after the interview -- right now I want to understand your experience."

## 2. Screening Criteria

Recruit founders who match all four criteria:

| Criterion | Requirement |
|-----------|-------------|
| Role | Solo technical founder or technical co-founder |
| Team size | 3 or fewer people |
| AI usage | Currently uses AI tools for work |
| Activity | Building a product (not freelancing, consulting, or agency work) |

**Screening question (required before scheduling):**

> "Have you ever used an AI tool for something other than writing code? What?"

Pass if they describe a specific non-coding use case (writing docs, drafting emails, research, planning). Fail if the answer is "no" or limited to code completion and debugging. The screening question filters for founders who have already crossed the mental barrier of applying AI beyond engineering -- these are the founders most likely to experience multi-domain pain.

## 3. Interview Questions (30 minutes)

Read each section aloud as written. Do not paraphrase, reorder, or skip questions. The sequence is designed so that open-ended pain discovery happens before the structured domain list -- this distinction is the foundation of the "independent pain" metric (see Section 4).

---

### Context (5 minutes)

> 1. What are you building?
> 2. How far along are you? (idea, MVP, launched, revenue)
> 3. How many people are on the team?

**Interviewer note:** These are warm-up questions. Let the founder talk. Capture their stage and team size for the response table. If they mention non-coding work unprompted here, note it -- it counts as independent pain.

---

### Pain Discovery (15 minutes)

> 4. Walk me through what you did last week that wasn't coding.

Let them talk. Do not prompt with examples. If they say "nothing" or struggle, follow up with: "What about emails, docs, planning, anything administrative?" but do not name specific domains.

> 5. Which of those tasks do you feel least qualified to do? Where is the gap between what you're doing and what an expert would do the widest? _[Rewritten 2026-03-26: original "distraction" framing failed when pain IS core work or manifests as avoidance]_
>
> 6. What business tasks do you know you should be doing but aren't? What's stopping you? _[Added 2026-03-26: surfaces avoidance pain -- 3/10 personas had pain that manifests as zero time spent, not excess time]_
>
> 7. Which of these tasks keeps you up at night — not the time-consuming ones, the scary ones? _[Added 2026-03-26: emotional weight is often a stronger buying signal than time cost]_
>
> 8. Have you tried using AI for any of those non-coding tasks? What happened?

If yes, probe: "What worked? What didn't? Did you keep using it?" If no, ask: "Why not?"

> 8a. What have you already tried to solve this — AI or otherwise? What worked, what didn't, and why? _[Added 2026-03-26: many founders tried non-AI alternatives (lawyers, freelancers, templates) — understanding why those failed reveals what the new solution must do differently]_
>
> 9. What would change for you if those tasks were handled automatically?

Listen for intensity signals: time saved, stress reduced, things they'd build instead, emotional relief. This is where willingness-to-pay seeds are planted -- note exact phrases.

---

### Domain Probing (5 minutes)

> 10. I'm going to read a list of business domains. Tell me which ones you've spent time on in the last month.
>
> **[Read aloud, slowly:]** Legal. Marketing. Operations. Finance. Sales. Support. HR/People. Product Strategy. _[Expanded 2026-03-26: added HR/People and Product Strategy — personas revealed secondary pain in these domains when prompted]_

Check off each one they confirm. Then:

> 11. Which ones are you ignoring that you probably shouldn't be?

**Interviewer note:** Responses to questions 10 and 11 are coded as "prompted" domains, not "independent." See Section 4.

---

### Willingness Signal (5 minutes)

Identify their top pain domain from the conversation so far (usually the one with the most emotional energy in questions 4-7, or the strongest response in questions 8-9). Then:

> 12. If a tool existed that handled **[their top pain domain]** for you, what would it need to do?

Let them describe the ideal. Note specific capabilities they mention.

> 12a. If that was handled for you, how would you know if it was done wrong? _[Added 2026-03-26: tests whether the founder can evaluate quality — critical for AI trust model design]_
>
> 13. What's this costing you right now — in money, in deals you're losing, in launch delays, or in risk you're carrying? _[Rewritten 2026-03-26: original "how much time per week" failed for anxiety, zero-baseline, and effectiveness pain — multi-dimensional cost framing lets founders pick the unit that matches their pain]_

Record the exact answer in whatever unit they use (dollars, hours, deals, risk). This answer becomes the anchor for the next question.

> 14. You mentioned [their stated cost from Q13]. How much of that would a tool need to cover before you'd pay for it? What would the budget look like? _[Rewritten 2026-03-26: original "what would you pay" produced flat responses from pre-revenue founders with no price anchor — anchoring on THEIR stated cost produces reliable WTP signals]_

**Establish the anchor first.** If Q13 produced a concrete cost (lawyer fees, hours lost, deals missed), reference it directly. If the founder couldn't quantify, provide the anchor: "You said you're losing enterprise deals / launching late / worried about lawsuits. If we put a dollar figure on that risk, what's the range?" Then ask about budget.

> 15. What would need to happen for you to solve this in the next 30 days? _[Added 2026-03-26: separates chronic pain from acute buying triggers — some founders have pain they'll tolerate indefinitely, others have acute triggers]_

---

## 4. "Independent Pain" Definition

This is the most important analytical distinction in the study.

**Independent pain:** A business domain the founder mentions during questions 4-7 (the open-ended Pain Discovery section) BEFORE seeing the structured domain list in question 8. The founder surfaced this pain without prompting.

**Prompted pain:** A domain the founder confirms or mentions only in response to questions 8-9 (after hearing the list read aloud). The founder recognized the pain when prompted but did not surface it independently.

**Why this matters:** Gate G1 requires that "5/10 founders independently describe multi-domain pain at intensity >= 3." Independent pain is a stronger signal than prompted pain. A founder who says "I spent all last week writing a privacy policy" (independent) is a different signal than one who says "yeah, legal, I guess I should deal with that" (prompted).

**Coding rule:** If a domain appears in a founder's answers to questions 4-7, it is independent. If it first appears in questions 8-9, it is prompted. If a domain appears in both, it is independent (first mention wins).

## 5. Response Recording Table

Complete one row per founder immediately after each interview. Do not batch these.

| Founder | Stage | Team Size | Domains (independent) | Domains (prompted) | Pain Intensity (1-5) | Top Pain Domain | WTP Signal | Key Quote |
|---------|-------|-----------|----------------------|-------------------|--------------------|----------------|-----------|-----------|
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |

**Column definitions:**

- **Founder:** First name or pseudonym. No full names in this document.
- **Stage:** idea / MVP / launched / revenue
- **Team Size:** Number (1-3)
- **Domains (independent):** Comma-separated list of domains mentioned in questions 4-7
- **Domains (prompted):** Comma-separated list of domains confirmed in questions 8-9 that were NOT already mentioned independently
- **Pain Intensity (1-5):** Overall score across all domains (see Section 6 for scale)
- **Top Pain Domain:** The single domain with highest intensity for this founder
- **WTP Signal:** Exact dollar amount and period (e.g., "$30/month", "$0", "wouldn't pay")
- **Key Quote:** The single most revealing verbatim quote from the interview

## 6. Post-Interview Coding Instructions

### When to Code

Code each interview immediately after it ends. Do not wait until all 10 are complete. Fresh recall produces more accurate coding. Spend 10-15 minutes on coding per interview.

### Pain Intensity Scale (1-5)

| Score | Label | Definition | Example Signal |
|-------|-------|------------|---------------|
| 1 | Aware | Founder acknowledges the domain exists but has not acted on it | "Yeah, I should probably look into that someday" |
| 2 | Annoyed | Founder has spent some time on it and found it unpleasant | "I wasted a couple hours on that last month" |
| 3 | Frustrated | Founder actively loses time to this domain and resents it | "Every week I spend half a day on stuff that isn't building product" |
| 4 | Blocked | The domain is preventing the founder from making progress | "I can't launch until I figure out the legal stuff and it's paralyzing" |
| 5 | Desperate | Founder has tried multiple solutions and none work; actively seeking help | "I've tried three tools, hired a freelancer, and I'm still stuck" |

For gate G1, a score of 3 or higher counts as validated pain.

### Independent vs. Prompted Classification

1. Review your notes for questions 4-7. List every business domain the founder mentioned, even in passing.
2. Review your notes for questions 8-9. List every domain the founder confirmed or raised.
3. Any domain that appears in step 1 is "independent." Any domain that appears only in step 2 is "prompted."
4. If a domain appears in both, classify it as "independent" (first mention wins).

### Handling Ambiguous Responses

- **Founder describes a task but doesn't name a domain:** Map it yourself. "I spent two hours writing an email to a potential customer" = sales. "I was trying to figure out pricing" = finance or product (use your best judgment, note the ambiguity).
- **Founder mentions a domain outside the six:** Record it in the "independent" column with the exact label they used. Do not force-fit it into the six predefined domains.
- **Founder gives a WTP range instead of a number:** Record the range, then note which end they seemed to anchor toward. For gate assessment, use the lower bound.
- **Founder says "I'd pay but I don't know how much":** Record as "WTP positive, amount unspecified." This does NOT count toward the G3 gate ($25/month minimum).
- **Founder contradicts themselves:** Record both statements. Flag with "[contradictory]" and use the more conservative interpretation for gate scoring.

### Second Coder Review

After all 10 interviews are coded, have a second person independently review 3 randomly selected interview notes and produce their own coding. Compare. If pain intensity scores diverge by more than 1 point on any founder, discuss and reconcile. This mitigates creator bias.

## 7. Interviewer Notes

Read these before every interview session.

**No product demo.** The entire interview must complete before any discussion of Soleur. If a founder asks "so what's your product?" during the interview, say: "I'll walk you through it right after -- I want to hear your experience first without that context coloring it."

**Don't lead with domain suggestions.** Questions 4-7 are deliberately open-ended. If a founder stalls, use neutral probes ("What else?" or "Tell me more about that") rather than "Did you do any marketing?" or "What about legal stuff?"

**Let silence work.** After asking a question, wait at least 5 seconds before speaking again. Founders will fill the gap. The discomfort of silence produces more honest answers than a rapid follow-up question.

**Record exact dollar amounts for WTP.** Not "around $30" or "in the $20-50 range." If the founder says "$30 a month," write "$30/month." If they say "maybe $50," write "$50/month (hedged)." Precision matters for gate G3.

**Bias acknowledgment.** The creator is conducting interviews about their own product category. This inflates positive signals. Mitigations:

1. Standardized script -- no improvisation, no enthusiasm about responses.
2. No product demo or description during the interview.
3. Second coder reviews 3/10 interview codings independently.
4. Intent-to-treat denominator -- dropouts count as non-pass, not excluded.
5. WTP threshold is $25/month, not $0 -- vague positivity does not count.

These mitigations reduce but do not eliminate creator bias. The results are directional signals, not statistically rigorous findings. That is appropriate for this stage.

**Practical logistics:**

- Audio record if the founder consents (ask at the start). If not, take detailed notes.
- Use the exact question wording. Read from this guide, not from memory.
- If the interview runs over 30 minutes, wrap up the current question and skip to question 12 (WTP). The willingness signal is more important than exhaustive domain probing.

## 8. Recruitment Message Templates

### Discord Post

```
Looking for solo founders to talk to (not selling anything)

I'm researching how solo founders handle the non-coding parts of building
a product -- legal, marketing, ops, finance, all the work that isn't
writing code.

If you're a technical founder (team of 1-3) who uses AI tools and is
building a product, I'd like to hear about your experience. 30-minute
call, no pitch, no demo. I want to learn what's actually painful.

Drop a comment or DM if you're open to a conversation.
```

### IndieHackers Post

```
Title: Researching non-coding pain points for solo founders -- looking for people to interview

I'm studying how solo founders deal with the business tasks that pull them
away from building. Legal docs, marketing, operations, finance -- the
work that doesn't feel like your core job but keeps demanding attention.

Looking for: technical founders, team of 3 or fewer, currently building a
product, using AI tools for at least some of your work.

Format: 30-minute call. No sales pitch. No product demo. I'm genuinely
trying to understand what's painful and what solutions (if any) actually
work.

If this sounds like you, comment below or message me. I'll share what I
learn with the community afterward.
```

### Twitter/X Post

```
Researching how solo founders handle non-coding work -- legal, marketing,
ops, finance.

Looking for technical founders (team <= 3) who use AI tools and are
building a product. 30 min call, no pitch, no demo.

If that's you, DM me. I'll share what I learn.
```

### Direct Outreach Message

```
Hey [name] -- I came across [their project/post/product] and it caught
my attention.

I'm doing research on how solo founders manage the non-coding parts of
building a product -- the legal, marketing, ops work that competes with
actual building time. Not selling anything; trying to understand what's
genuinely painful and what (if anything) helps.

Would you be open to a 30-minute call? I'm talking to about 10 founders
and I'd value your perspective. Happy to share what I learn from the
research afterward.

No worries if the timing doesn't work.
```

---

**File location:** `knowledge-base/project/specs/feat-product-strategy/interview-guide.md`
**Created:** 2026-03-03
**Source:** Brainstorm (2026-03-03), Validation Plan (2026-03-03)
**Gate dependency:** G1 (multi-domain pain), G3 (WTP signal)
