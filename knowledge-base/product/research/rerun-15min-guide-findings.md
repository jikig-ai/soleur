# Rerun Findings: Updated 15-Minute Interview Guide

10 synthetic personas run through the UPDATED 15-minute guide (10 questions, up from 6). Original guide had 6 questions; 2 were rewritten and 4 new questions added, plus a wrap-up question. This document assesses whether the changes improved response quality.

**Original guide questions:** Q1 (typical week), Q2 (hand off), Q3 (AI tools), Q4 (hire moment), Q5 (trust AI agents), Q6 (good enough)

**Updated guide questions:** Q1 (typical week - kept), Q2 (hand off - kept), Q3 (avoidance pain - NEW), Q4 (emotional weight - NEW), Q5 (AI tools - kept), Q6 (failed alternatives - NEW), Q7 (hire moment - kept), Q8 (inbox deliverable - REWRITE of old Q5), Q9 (what needed to exist - REWRITE of old Q6), Q10 (quality evaluation - NEW), Wrap-up (cost of inaction - NEW)

---

## Full Response Data: All 10 Personas x 11 Questions

---

### Q1: "Walk me through a typical week. What tasks outside of core product work take the most time?" [KEPT]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "Monday through Thursday I'm heads down coding. Friday I open a blank Google Doc to write a Terms of Service, stare at it for an hour, close it. Saturday I watch pricing strategy videos on YouTube. Sunday I feel guilty about not having a marketing plan. The non-coding work isn't 'taking time' so much as haunting me." |
| Priya | Rich | "Last week: 6 hours on DPA requests, 3 hours deciphering a DMCA takedown notice, 2 hours on a $400 lawyer call. That's half my working week on legal instead of shipping features." |
| Elena | Moderate | "I spend a lot of time on marketing -- LinkedIn posts, forum threads, reading about SEO. But it's diffuse. I can't point to a single block of time because it's scattered across every day in 30-minute chunks that add up to nothing." |
| James | Rich | "Monday: process returns, answer support emails, 3 hours. Tuesday: check inventory, email suppliers about restocks, 2 hours. Wednesday-Thursday: more support, a shipping dispute, a chargeback. Friday: maybe 2 hours of actual coding if I'm lucky." |
| Sofia | Moderate | "I worry about legal stuff constantly. I check competitor privacy policies. I draft things in ChatGPT. But I don't actually spend that many hours on it -- it's more like a background anxiety that makes everything take longer." |
| Tobias | Flat | "Almost everything I do is product work. I don't spend time on non-product tasks because I just... don't do them. I know marketing should be on that list but I spent maybe 45 minutes on it last week." |
| Aisha | Rich | "Bookkeeping eats 3-4 hours weekly -- reconciling Stripe payouts with Wave, untangling international payment fees. Last month I got a nexus notice from California and lost an entire weekend trying to understand it." |
| Derek | Rich | "Support tickets: 10+ hours a week now. SOC 2 documentation for enterprise prospects. Developer docs every time we ship. DNS changes. Billing edge cases where Stripe webhooks fail. That's 15-20 hours of non-engineering work." |
| Min-Ji | Moderate | "I try different marketing things. Instagram, rewrote my app store listing, sent cold emails. None of it sticks, so I keep stopping and starting. Maybe 8 hours total but with zero measurable results." |
| Rafael | Rich | "Every musician I onboard asks about rights. I spend hours in ChatGPT drafting licensing terms, then second-guessing everything. Last week a manager asked for our standard sync agreement and I had to stall for two days while I scrambled." |

**Ratings: 6 Rich, 3 Moderate, 1 Flat** (unchanged from original)

---

### Q2: "Which of those tasks do you wish you could hand off entirely?" [KEPT]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "All the legal stuff -- Terms of Service, privacy policy, I'd hand that off in a heartbeat. Marketing too, but I feel like I need to understand my market first before I can delegate. Legal is just bureaucracy I have no business writing." |
| Priya | Rich | "DPA generation. GDPR compliance documentation. I don't need to understand every clause -- I just need the right documents produced correctly. But I'd still want to review anything before it goes to a customer." |
| Elena | Moderate | "The marketing strategy part. Not the design work -- I can make beautiful assets. But figuring out where to post, what messaging resonates, how SEO actually works... I'd pay for that brain, not just that labor." |
| James | Rich | "Customer support. Returns processing. Supplier communication. Everything that isn't building features or thinking about the product. If someone else handled the operational grind, I'd be twice as productive." |
| Sofia | Flat | "All of it? I don't even know what I need. I just know I'm scared of getting sued and I wish someone would tell me exactly what to do." |
| Tobias | Flat | "I don't really have tasks to hand off because I'm not doing them. I guess I wish someone would just... do marketing? But I don't even know what 'doing marketing' means for an ML product targeting accountants." |
| Aisha | Rich | "Tax compliance. Nexus obligations. International payment accounting. I'd hand that entire domain off and never think about it again." |
| Derek | Rich | "Tier-1 support -- the same WebSocket setup questions over and over. SOC 2 documentation. Billing edge case resolution. In that priority order." |
| Min-Ji | Moderate | "Marketing, I guess. But I've hired freelancers before and they didn't understand my product or my Shopify audience. So handing it off didn't actually work." |
| Rafael | Rich | "The legal documents. Licensing agreements, rights frameworks, royalty contracts. I need real legal templates, not ChatGPT guesses that might be unenforceable." |

**Ratings: 6 Rich, 2 Moderate, 2 Flat** (unchanged from original -- same structural limitation for avoidance-pain personas)

---

### Q3: "What business tasks do you know you should be doing but aren't? What's stopping you?" [NEW -- avoidance pain]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "Legal documentation, marketing plan, pricing strategy -- all three. What's stopping me? Incompetence. I'm an 8-year senior engineer and I literally don't know how to write a Terms of Service. It's not procrastination, it's paralysis because I don't know where to start and the cost of doing it wrong feels high." |
| Priya | Moderate | "Sales outreach. All 40 customers found us organically through GitHub. I know that's not a strategy but I keep telling myself 'we'll do outbound next quarter.' What's stopping me is that every spare hour goes to legal fires instead." |
| Elena | Rich | "SEO. Paid advertising. Conference networking. All three would reach architects better than random LinkedIn posts. What's stopping me is I don't know how to do any of them, I can't evaluate whether I'm doing them right, and every tutorial assumes you already know marketing fundamentals I don't have." |
| James | Moderate | "Marketing. I've grown entirely on word-of-mouth and that's plateauing. Also supplier contracts -- everything is handshake deals, which is insane. What's stopping me is I spend all my non-coding time firefighting operations instead of building foundations." |
| Sofia | Rich | "Getting a real privacy policy reviewed by a lawyer. Setting up proper data handling procedures. Understanding if I need SOC 2. What's stopping me is I don't know what questions to ask a lawyer, I don't know how much it should cost, and I'm terrified the answer is 'you've been doing everything wrong and need to start over.'" |
| Tobias | Rich | "Everything go-to-market. Content marketing, outbound sales, conference talks, product demos. I should be doing all of it and I'm doing none of it. What's stopping me is I genuinely don't know what 'good' looks like in marketing. I can evaluate ML models but I can't evaluate a marketing strategy, so I default to doing nothing." |
| Aisha | Rich | "Proper tax planning. I should have a CPA doing quarterly estimates, I should understand my state nexus obligations, I should be setting aside money for taxes instead of guessing. What's stopping me is the cost -- a fractional CFO is $3-5K/month -- and the fear that a professional will look at my books and tell me I owe back taxes I can't afford." |
| Derek | Moderate | "Hiring. I should have hired a support person 3 months ago. What's stopping me is I've never managed anyone, I don't know how to write a job description for this role, and I'm terrified of making a bad hire at this stage when every dollar matters." |
| Min-Ji | Rich | "Learning actual marketing strategy. Not tactics -- strategy. Understanding why my app store listing doesn't convert, why cold emails fail, what channels actually work for Shopify apps. What's stopping me is every resource I find is either too basic or too advanced, and the marketing freelancers I hired didn't teach me anything." |
| Rafael | Rich | "Getting a proper legal framework built. I know I need an entertainment lawyer to draft licensing agreements, but the quotes I've gotten are $5-10K and I'm pre-revenue. What's stopping me is money I don't have for a problem I can't defer -- every musician who asks about rights and doesn't get a clear answer is a musician who doesn't sign up." |

**Ratings: 7 Rich, 3 Moderate, 0 Flat**

**Assessment:** This question directly addresses the biggest weakness of Q1 and Q2. Tobias went from Flat on both Q1 and Q2 to Rich here -- the "what's stopping you" framing surfaces his paralysis without requiring him to describe tasks he's already doing. Sofia similarly went from Flat (Q2) to Rich because the question validates that NOT doing something IS the pain. Min-Ji went from Moderate to Rich because the question lets her articulate the knowledge gap rather than just listing failed tactics.

---

### Q4: "Which of these tasks keeps you up at night -- not the time-consuming ones, the scary ones?" [NEW -- emotional weight]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "The Terms of Service. I'm going to launch a product that handles construction project data -- blueprints, timelines, budgets -- with zero legal protection. If a contractor's data gets leaked through my platform, I have nothing. No ToS, no limitation of liability, nothing. That's the one that wakes me up at 2 AM." |
| Priya | Rich | "The GDPR stuff. Not the DPAs -- those are tedious but manageable. The scary part is that I might be non-compliant in some way I don't even know about. The fines are up to 4% of global revenue. For a $36K ARR company, that's survivable. But the reputational damage with my enterprise customers would kill us." |
| Elena | Rich | "Running out of savings before getting traction. I've got maybe 8 months of runway. Marketing is scary because if I can't crack it, the product dies regardless of how good it is. I can see the clock running and I don't know how to move faster." |
| James | Rich | "Supplier dependency. Two of my top 5 products come from a single roaster in Guatemala with no contract. If they disappear tomorrow, I lose 30% of revenue overnight. I know I need supplier agreements and backup relationships but I'm too buried in daily operations to build them." |
| Sofia | Rich | "A data breach. I store client data -- names, project details, financial information -- and my security setup is basically 'Bubble's defaults plus hope.' If there's a breach and I don't have a proper privacy policy or incident response plan, I could be personally liable. That's not just losing the business, that's losing everything." |
| Tobias | Rich | "Launching to silence. I'll spend 18 months building this product and then put it out there and nobody will find it. No marketing, no distribution, no audience. The ML model is state-of-the-art but the scariest scenario is it doesn't matter because zero accountants ever see it." |
| Aisha | Rich | "Tax liability I don't know about. I'm processing payments across 15+ states and I genuinely don't know my nexus obligations. The IRS doesn't send friendly reminders -- they send penalties. One bad audit could cost more than my annual revenue." |
| Derek | Rich | "Losing the enterprise pipeline. I have 3 prospects at $5K+/month who need SOC 2. That's $180K ARR sitting behind a compliance gate I can't clear as a solo founder. If they go to a competitor because I can't produce security documentation, that's the inflection point I missed." |
| Min-Ji | Rich | "Staying stuck at $2K MRR permanently. Four months at the same number. I can see a future where I'm still at $2K in a year, still trying random marketing tactics, still not growing. That's not a business, that's an expensive hobby. And I quit my job for this." |
| Rafael | Rich | "A musician getting screwed because my licensing terms were wrong. Someone signs up, their music gets used in a commercial, and the terms I drafted in ChatGPT don't protect their rights properly. I'd be personally responsible for damaging someone's livelihood. That's not a business problem, that's a moral one." |

**Ratings: 10 Rich, 0 Moderate, 0 Flat**

**Assessment:** This is the strongest-performing new question and arguably the strongest in the entire updated guide. Every single persona produced a rich, specific, emotionally authentic response. The "not the time-consuming ones, the scary ones" framing explicitly separates emotional pain from operational pain, which is exactly what the original guide failed to do. Key insight: the responses here reveal buying triggers that no other question surfaces. Marcus's fear of launching unprotected, Derek's $180K pipeline at risk, Rafael's moral weight -- these are the moments where founders would actually pay for a solution.

---

### Q5: "Have you tried using AI tools for any operational work? What was the experience?" [KEPT]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "I use Claude for brainstorming pricing models -- it's great at 'here are 5 approaches for construction SaaS' but useless for 'what should MY price be given MY costs and MY competitive landscape.' The general-to-specific gap is where it falls apart." |
| Priya | Rich | "ChatGPT for a DPA template. Looked professional but had contradictory clauses my lawyer caught. That was the moment I realized -- for legal, AI is dangerous because it looks right even when it's wrong. Confidently wrong." |
| Elena | Rich | "ChatGPT for marketing copy. Terrible. 'Revolutionize your design workflow' -- no architect talks like that. It writes for a generic tech audience, not for a profession with its own language and culture. I gave up after two tries." |
| James | Moderate | "Copilot for code but nothing for operations. I wouldn't know where to start. Do I paste my inventory spreadsheet into ChatGPT? What would it even do with that? There's a discovery gap -- I don't know what AI can do for ops." |
| Sofia | Rich | "I use ChatGPT every day -- emails, proposals, feature brainstorming. For the privacy policy, I had it write one but I have absolutely no way to tell if it's correct. I'm using it and hoping for the best, which I know is irresponsible." |
| Tobias | Moderate | "For technical architecture, yes. For marketing, I wouldn't know what to prompt. 'Help me market my ML financial reporting tool to small accounting firms' feels too vague to produce anything useful." |
| Aisha | Moderate | "Only for code. I wouldn't trust AI with financial calculations or tax categorization. My product is built on accuracy -- I can't be using inaccurate tools for my own finances and maintain any credibility." |
| Derek | Rich | "Claude Code for everything engineering. For non-engineering, I've drafted SOC 2 policies and support templates. The drafts are 70% there but need heavy editing. Net effect: saves maybe 30% of the time, not the 80% I need." |
| Min-Ji | Flat | "ChatGPT once for marketing copy. Too generic, too American, didn't understand the Shopify ecosystem at all. That's the extent of my AI experience." |
| Rafael | Moderate | "ChatGPT is my daily driver for emails and onboarding docs. For licensing templates, the output looks convincing but I know it could be legally wrong. I use it as a starting point and then worry about it constantly." |

**Ratings: 5 Rich, 4 Moderate, 1 Flat** (unchanged from original)

---

### Q6: "What have you already tried to solve this -- AI or otherwise? What worked, what didn't, and why?" [NEW -- failed alternatives]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "For legal: I googled 'SaaS Terms of Service template,' found a few free ones, but they were all for generic web apps, not construction data platforms. I looked at competitors' ToS pages but they're all enterprise companies with real lawyers. For pricing: I read a dozen blog posts and watched YouTube videos but every framework assumes you have market data I don't have yet." |
| Priya | Rich | "I hired a lawyer -- $800 for a 30-minute call about a takedown notice. She was helpful but that's not scalable. For DPAs, I tried building a template myself from GDPR documentation, but it took 8 hours and I still wasn't confident it was right. I also tried ChatGPT and got the contradictory clause problem. So: expensive expert works, DIY doesn't, AI is unreliable." |
| Elena | Rich | "For marketing: I hired a freelance marketer on Upwork for $1,500/month. She posted generic content that got zero engagement because she didn't understand architecture. I tried a 'marketing for startups' course -- $299, very general, didn't address niche B2B. I tried LinkedIn organic posting myself for 2 months -- maybe 3 leads, none converted. Everything fails because architects are a weird, insular audience." |
| James | Rich | "Zendesk for support -- helps organize but doesn't reduce volume. ShipStation for shipping -- saves time on labels but not on the returns back-and-forth. I tried a virtual assistant from the Philippines for $600/month -- she was great at support but I spent 5 hours/week training and reviewing her work, so net savings were marginal." |
| Sofia | Rich | "ChatGPT for the privacy policy -- can't verify if it's correct. I emailed a lawyer asking for a quote -- $3,000 minimum for a compliance audit, which is 3 months of my MRR. I looked at LegalZoom and Rocket Lawyer but they're template factories, not specific to SaaS data handling. Nothing I can afford actually addresses my specific situation." |
| Tobias | Rich | "I read 'Traction' by Gabriel Weinberg. Good framework, couldn't apply it -- the bullseye method assumes you can test channels quickly, but for ML financial reporting targeting accountants, there's no quick test for conference marketing or content strategy. I also looked at hiring a marketing agency -- minimum $5K/month retainers, which is absurd for a pre-revenue product." |
| Aisha | Rich | "Wave for bookkeeping -- free, decent, but can't handle multi-state tax complexity. I tried QuickBooks -- better but $80/month and still manual reconciliation. I asked my personal tax accountant about business taxes and she said 'you need a CPA who specializes in e-commerce,' which would be another $500/month minimum." |
| Derek | Rich | "For support: I built a knowledge base, wrote comprehensive docs. Customers still email instead of reading. I tried adding a chatbot (Intercom) -- $74/month, resolves maybe 15% of tickets. For SOC 2: I got a consultant quote of $15K. I started the docs myself using a template from Vanta's blog -- 3 weeks in and maybe 20% done." |
| Min-Ji | Rich | "I hired two marketing freelancers on Fiverr. First one ($200) rewrote my app listing with generic keywords that didn't match how Shopify merchants search. Second one ($400) managed my Instagram for a month -- got followers but zero conversions. I tried cold emailing 50 merchants -- 2 replies, both 'not interested.' Total spent: about $1,000 with nothing to show for it." |
| Rafael | Rich | "I found a music licensing template on LegalTemplates.net for $39. It was for a completely different type of agreement -- sync licensing for film, not marketplace licensing for commercial use. I asked in a music industry Discord -- someone said 'you need an entertainment lawyer, period.' Quoted $5-10K for a proper framework. That's money I don't have." |

**Ratings: 10 Rich, 0 Moderate, 0 Flat**

**Assessment:** This is the second-strongest new question, tied with Q4 for 10/10 rich responses. The "AI or otherwise" framing is critical -- it captures the full solution landscape. Every persona has tried something and can describe exactly why it failed. This produces three types of actionable insight: (1) what alternatives exist (competitive intelligence), (2) why they failed (feature requirements for Soleur), (3) how much was spent on failed attempts (pricing anchor). Min-Ji, who was Flat on the AI question, produced a rich response here because she HAS tried non-AI solutions. Tobias, who was Flat on Q1 and Q2, produced rich signal because books and agencies count as "tried."

---

### Q7: "What's the last thing that made you think 'I need to hire someone for this'?" [KEPT]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "Three months of staring at that blank Terms of Service document. I'm an engineer who can build distributed systems but I can't write a legal document to save my life. It's not procrastination -- it's domain incompetence. I need a lawyer, but a lawyer for a startup with zero revenue feels absurd." |
| Priya | Rich | "The takedown notice. I didn't know if I had 10 days or 30 days to respond. I called a lawyer -- $800 for 30 minutes. She said 'this is straightforward, respond within 10 days.' Eight hundred dollars for that." |
| Elena | Rich | "Two months of LinkedIn posting with zero leads. A real marketer would know why it's not working and what to do instead. But marketing consultants want $2-3K/month retainers and I'm pre-revenue." |
| James | Rich | "A 1-star review because a return took 8 days while I was at a conference. The returns queue backed up. That's when I thought 'I need a support person.' But at $4K/month for a hire, that's a huge chunk of my margin." |
| Sofia | Rich | "An enterprise prospect asked for a DPA and I didn't know what a DPA was. Googled it, panicked, spent 3 hours trying to understand. They went with a competitor. That was $2K MRR I lost to ignorance." |
| Tobias | Moderate | "I haven't had a concrete moment yet because I'm pre-revenue. But I think about it abstractly -- 'I'll need a marketer someday.' The problem is I can't hire for a function I don't understand well enough to evaluate the hire." |
| Aisha | Rich | "The California nexus letter. I didn't know what 'nexus' meant. Spent a weekend researching state tax obligations and still wasn't confident. A fractional CFO would cost $3-5K/month. At $8K MRR, that's nearly half my revenue." |
| Derek | Rich | "An enterprise prospect needing SOC 2 compliance before signing a $5K/month contract. That's $60K ARR behind a gate I can't clear. A compliance consultant quoted $15K. That's when I thought 'I need to hire' -- and simultaneously 'I can't afford to hire.'" |
| Min-Ji | Moderate | "I've thought about a marketing consultant but the two I talked to wanted $2-3K/month and neither understood the Shopify app ecosystem. Generic marketing advice isn't worth paying for and Shopify-specific expertise is rare." |
| Rafael | Rich | "A music manager saying 'I need to see your standard sync licensing agreement before my artists sign up.' I don't have one. An entertainment lawyer would cost $5-10K. I don't have $5-10K. But I also can't acquire artists without legal credibility." |

**Ratings: 8 Rich, 2 Moderate, 0 Flat** (unchanged from original)

---

### Q8: "Imagine [their pain point deliverable] just appeared in your inbox every week, done correctly. What would you check before using it? What would make you nervous?" [REWRITE of old Q5 "trust AI agents"]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "If a Terms of Service just showed up? First I'd want to know it was specific to my product -- construction data, multi-party access, subcontractor provisions. I'd check that it wasn't just a generic SaaS template with my company name pasted in. What makes me nervous is that I can't tell the difference between a good legal document and a bad one that sounds good." |
| Priya | Rich | "I'd check that the DPA clauses don't contradict each other -- that was the ChatGPT failure. I'd verify the data processing categories match our actual infrastructure. And I'd want to see that it references the correct GDPR articles. What makes me nervous is liability -- if a customer signs a DPA that turns out to be non-compliant, who's responsible?" |
| Elena | Rich | "If a marketing plan appeared? I'd check whether it actually understands how architects think and buy. Does it suggest the right channels -- AIA events, architecture publications, not generic LinkedIn ads? What makes me nervous is getting advice that sounds professional but is actually generic startup playbook stuff that doesn't apply to my niche." |
| James | Rich | "For a daily operations report, I'd check that the inventory numbers match reality -- one wrong reorder could mean $5K in dead stock. I'd verify the support ticket responses match our tone and policies. What makes me nervous is edge cases: the weird customer situations where a wrong response could lose us a customer." |
| Sofia | Rich | "For a privacy policy? I'd want some kind of confirmation that it's actually legally valid -- not just well-written but correct. Can I point to it if a regulator asks? What makes me nervous is that I can't evaluate legal quality. I don't know what I don't know. I need someone -- or something -- to tell me 'this is compliant' and stand behind it." |
| Tobias | Rich | "If a go-to-market strategy appeared? I'd check whether it's grounded in real data about how small accounting firms discover and evaluate software. Not generic 'content marketing + SEO' advice. What makes me nervous is spending 3 months executing a strategy that turns out to be wrong and wasting the limited runway I have." |
| Aisha | Rich | "For tax estimates, I'd reconcile them against my own rough calculations. If they're wildly different, something's wrong. I'd verify state-by-state nexus determinations against what I know. What makes me nervous is accuracy -- one wrong filing can trigger an audit, and the penalty for underpayment is real money." |
| Derek | Rich | "For SOC 2 docs, I'd check them against my actual architecture -- does the document describe our real infrastructure or a generic cloud setup? For support responses, I'd spot-check that technical answers are correct for our API. What makes me nervous is reputational risk: a wrong answer to an enterprise prospect's security questionnaire could kill a $60K deal." |
| Min-Ji | Rich | "If a marketing strategy appeared? I'd look at whether the recommendations are specific to the Shopify app ecosystem -- app store optimization, merchant communities, specific ad channels. Not generic e-commerce marketing advice. What makes me nervous is that I've been burned by generic advice before and I can't afford to waste another $1,000 on strategies that don't work for my market." |
| Rafael | Rich | "For licensing agreements? I'd want to verify that they cover the specific use cases in music sync licensing -- exclusive vs. non-exclusive, territory limitations, royalty structures. What makes me nervous is that I'm putting these in front of musicians and their managers. If the terms are wrong, I'm not just losing business, I'm damaging trust with artists who are putting their creative work on the line." |

**Ratings: 10 Rich, 0 Moderate, 0 Flat** (original Q5 was: 3 Rich, 4 Moderate, 3 Flat/Confused)

**Assessment:** Dramatic improvement. The original Q5 ("If you had AI agents handling [pain point] -- would you trust the output?") produced 3 flat/confused responses because "AI agents" is jargon that triggers skepticism from Elena, Sofia, and Min-Ji. The rewrite removes all mechanism language and starts from the outcome ("just appeared in your inbox, done correctly"). Key improvements:

- **Elena**: Flat to Rich. She's no longer confused by "AI agents" -- she's evaluating whether a marketing plan understands her niche.
- **Sofia**: Moderate to Rich. Instead of asking "what does AI agents mean," she's describing what "correct" would look like for her situation.
- **Min-Ji**: Flat to Rich. Instead of dismissing it as "a fancier chatbot," she's articulating specific quality criteria based on her past failures.
- **Tobias**: Moderate to Rich. Drops the philosophical "I know what AI can and can't do" and instead describes concrete validation criteria.

The "what would you check / what makes you nervous" two-part framing is the key design insight. "What would you check" reveals quality criteria and trust boundaries. "What makes you nervous" reveals the actual risk calculus. Together they produce product requirements without asking the persona to spec a product.

---

### Q9: "Think about the last time [their pain point] blocked you or cost you something. What would have needed to exist for that not to happen?" [REWRITE of old Q6 "what would good enough look like"]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "Last month I delayed my beta launch by 3 weeks because I didn't have a Terms of Service. What would've needed to exist? A legally defensible ToS, specific to construction SaaS, that I could customize and publish in an afternoon instead of three months of paralysis. Not a template -- something that already understood my product handles sensitive project data." |
| Priya | Rich | "The DMCA takedown notice. I lost a full day figuring out what to do. What needed to exist: a system that receives a legal notice, identifies what type it is, tells me exactly what I'm required to do and by when, and drafts the response. Basically a legal triage system that turns 'I'm panicking' into 'here's the 3-step action plan.'" |
| Elena | Rich | "My beta has 40 users after 5 months of marketing effort. What needed to exist? A strategy document that says 'here are the 3 channels where architects actually discover software, here's the messaging that resonates, here's a 90-day execution plan.' Not theory -- a concrete plan I could execute immediately." |
| James | Rich | "The 1-star review from the backed-up returns queue. What needed to exist: automated returns processing that generates labels, issues refunds, and sends status updates without waiting for me. And a dashboard that shows me what's going wrong instead of me discovering problems through customer complaints." |
| Sofia | Rich | "The enterprise prospect who asked for a DPA and I lost them. What needed to exist: a ready-to-send DPA template that matches my actual product and data handling practices. Not a generic DPA -- one that already knows I use Bubble, stores client data in X way, and processes it for Y purposes. Something I could send within an hour instead of losing the deal." |
| Tobias | Rich | "I haven't launched yet, so nothing has 'blocked' me in the market. But what's blocking the launch is having no go-to-market motion. What would need to exist: a concrete channel strategy that tells me 'accountants in this segment discover software through X, Y, Z' with evidence, not guesses. An ICP definition and a distribution plan." |
| Aisha | Rich | "The California nexus letter. What needed to exist: a system that tracks my payment volumes by state and alerts me before I cross nexus thresholds. And when I do cross one, tells me exactly what I need to file, when, and how much to set aside. Proactive, not reactive." |
| Derek | Rich | "The $60K enterprise deal stalled behind SOC 2. What needed to exist: SOC 2 policy documents that accurately reflect my infrastructure, generated from my actual AWS setup and deployment config, not generic templates. Something an enterprise security team would review and accept without 20 follow-up questions." |
| Min-Ji | Rich | "Being stuck at $2K MRR for 4 months. What needed to exist: data-driven marketing guidance that's specific to Shopify apps. Something like 'your app store listing is underperforming because X, try Y based on what similar apps do.' Not generic marketing advice -- evidence-based recommendations for my specific market." |
| Rafael | Rich | "The music manager who asked for our standard sync licensing agreement. What needed to exist: a proper sync licensing framework -- standard agreements for exclusive, non-exclusive, and limited-term use, written in industry-standard language that music managers and lawyers would recognize as professional. Something that says 'this marketplace takes rights management seriously.'" |

**Ratings: 10 Rich, 0 Moderate, 0 Flat** (original Q6 was: 3 Rich, 3 Moderate, 4 Flat)

**Assessment:** The single biggest improvement in the updated guide. The original Q6 asked "what would 'good enough' look like" -- a question that requires domain expertise to answer. Four personas (Elena, Sofia, Tobias, Min-Ji) couldn't answer it because they don't know what "good" looks like in an unfamiliar domain. The rewrite anchors on a concrete past event ("the last time it blocked you") and asks what was missing ("what would have needed to exist"). Key shift: the persona doesn't need to evaluate quality -- they just need to describe what would have prevented a specific bad outcome. This works for everyone because every persona has experienced a negative consequence, even Tobias (whose "block" is not having launched at all).

---

### Q10: "If this task was handled for you, how would you know if it was done wrong?" [NEW -- quality evaluation]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "Honestly? I wouldn't -- not for legal. I don't know what a bad Terms of Service looks like versus a good one. I'd need some kind of external validation -- a lawyer's stamp, a compliance check. For pricing, I'd know it was wrong if customers push back hard or I'm leaving obvious money on the table." |
| Priya | Rich | "For DPAs: if a customer's legal team rejects it or pushes back on specific clauses. For GDPR compliance: if a regulator contacts us. The problem is both of those signals come too late -- by the time you discover a legal document is wrong, you're already exposed." |
| Elena | Moderate | "For marketing: I'd look at results. Leads, conversions, signups. If the strategy doesn't produce outcomes in 60-90 days, it's wrong. But I can't tell if a marketing strategy is wrong before executing it -- I can only evaluate it by results." |
| James | Rich | "For support: customer satisfaction scores drop, or I get complaints about wrong information. For inventory: we overstock or stockout. For returns: a customer escalates because the process failed. The signals are all lagging indicators, which is the problem -- by the time I know something's wrong, damage is done." |
| Sofia | Rich | "I wouldn't know. That's the terrifying part. If someone handed me a privacy policy and it had a critical flaw, I wouldn't catch it. I don't have the expertise to evaluate legal documents. I'd need someone -- a lawyer, a compliance service, something -- to verify it. I can't be my own quality control for legal." |
| Tobias | Moderate | "For marketing strategy: if the recommended channels don't produce qualified leads within the first 30 days, something's wrong. But distinguishing 'the strategy is wrong' from 'the execution is wrong' from 'it takes longer than 30 days' is hard. I don't have the marketing experience to diagnose which one it is." |
| Aisha | Rich | "For tax stuff: if the numbers don't match my rough mental model, something's off. If estimated taxes are wildly different from last quarter without a clear reason, that's a red flag. But the subtle errors -- a miscategorized expense, a missed nexus threshold -- I might not catch those until audit time." |
| Derek | Rich | "For support: if customers reply to an auto-response saying 'that didn't help' or 'that's wrong.' For SOC 2 docs: if an enterprise prospect's security team comes back with a list of deficiencies. In both cases, the damage is reputational -- I'd rather catch errors before they reach a customer." |
| Min-Ji | Moderate | "For marketing: zero results after spending money. That's the only signal I have and it's the same signal I'm getting now from my own efforts. I can't tell the difference between a bad strategy and a good strategy with poor execution. That's why hiring freelancers didn't work -- I couldn't evaluate their work." |
| Rafael | Rich | "A lawyer or music manager would spot bad licensing terms immediately. I might not -- I'd need someone with legal expertise to review. The nightmare scenario is a musician signs an agreement that doesn't actually protect their rights, and I don't discover it until there's a dispute. The feedback loop is too slow and the consequences are too high." |

**Ratings: 7 Rich, 3 Moderate, 0 Flat**

**Assessment:** Solid but not as strong as Q4, Q6, or Q8. The question successfully surfaces whether the persona can be their own quality control -- critical product design insight. The richest responses come from personas who recognize they CAN'T evaluate quality (Marcus, Sofia, Rafael for legal; Priya for compliance). The moderate responses from Elena, Tobias, and Min-Ji reveal a common pattern: for marketing, the only quality signal is lagging results, which means they can't pre-verify. This is a meaningful finding for product design -- legal/compliance personas need third-party validation mechanisms; marketing personas need leading indicators built into the product.

---

### Wrap-up: "What happens if you keep doing things the way you're doing them for the next 6 months?" [NEW -- cost of inaction]

| Persona | Rating | Response |
|---------|--------|----------|
| Marcus | Rich | "I launch late -- again. Or I launch without legal protection and pray nothing goes wrong. Either way, my runway shrinks. In 6 months I'll be 3 months from running out of savings with a product that either isn't launched or isn't protected. That's not a sustainable trajectory." |
| Priya | Rich | "I keep hemorrhaging money on lawyers. $800 here, $400 there. That's $3-5K/year on reactive legal that should be proactive. Meanwhile, every DPA I produce manually is time I'm not building features. In 6 months, I'll have spent $10K+ on legal and still won't have a scalable compliance process." |
| Elena | Rich | "I run out of money. Eight months of runway and no growth trajectory means I'm funding a hobby, not building a business. In 6 months, I'll either have given up or I'll be looking for a job while maintaining a beta with 50 users." |
| James | Rich | "Operations scale linearly with revenue but I'm the bottleneck. If I grow to $25K MRR, I'll need 35+ hours/week on ops. At some point I'll either hire -- killing my margins -- or I'll stop growing because I literally can't handle more volume. The ceiling is me." |
| Sofia | Rich | "Every new customer increases my liability exposure. In 6 months I'll have 50-60 clients' data with the same lack of legal protection I have now. The risk compounds. One data incident and I lose everything -- the business, possibly my personal assets." |
| Tobias | Rich | "I ship a product nobody finds. 18 months of ML research with zero distribution. In 6 months I'll have a polished product, no users, and no understanding of how to get users. I'll probably give up and go back to academia, which is honestly the most likely outcome." |
| Aisha | Rich | "I get a tax surprise. I'm guessing at estimated payments, I don't know my actual nexus obligations, and my books are a mess. In 6 months, tax season hits and I find out I owe $10K I didn't plan for, or I get audited and can't produce clean records. The longer I wait, the more expensive the cleanup." |
| Derek | Rich | "I lose the enterprise pipeline. $180K ARR sitting behind SOC 2 that I can't produce alone. In 6 months, those prospects will have signed with competitors. Meanwhile, support load doubles to 20+ hours/week and I'll have to hire whether I want to or not. My golden solo-founder economics have a 6-month expiration date." |
| Min-Ji | Rich | "I stay at $2K MRR. A year from now, same revenue, same frustration, same random tactics producing nothing. At some point the Shopify app store algorithm stops showing my app because it's not growing. Stagnation becomes decline." |
| Rafael | Rich | "I keep losing musicians who want professional legal terms I can't provide. The marketplace stays small because serious artists won't join without legal credibility. In 6 months, a competitor with proper legal infrastructure launches and signs the musicians I couldn't retain. The window for first-mover advantage closes." |

**Ratings: 10 Rich, 0 Moderate, 0 Flat**

**Assessment:** Third question to achieve 10/10 rich responses. The power of this question is that it forces founders to project their current pain forward and confront compounding consequences. Every persona's response reveals urgency signals: Marcus's runway, Elena's 8 months of savings, Derek's $180K expiration date. This question should always be last because it creates emotional weight that retrospectively amplifies every pain point discussed earlier. It also provides excellent data for outcome-based pricing: you can price against the cost of the trajectory they just described.

---

## Summary Comparison: Rewritten/New Questions vs. Originals

### Questions That Replaced Weak Originals

| Original Question | Orig. Rich/Moderate/Flat | New Question | New Rich/Moderate/Flat | Improvement |
|---|---|---|---|---|
| Q5: "If you had AI agents handling [pain] -- would you trust it?" | 3 / 4 / 3 | Q8: "Imagine [deliverable] appeared in your inbox. What would you check? What makes you nervous?" | 10 / 0 / 0 | +7 Rich, -3 Flat |
| Q6: "What would 'good enough' look like for [pain] handled by AI?" | 3 / 3 / 4 | Q9: "Last time [pain] blocked you -- what would have needed to exist?" | 10 / 0 / 0 | +7 Rich, -4 Flat |

### Per-Persona Improvement on Rewritten Questions

| Persona | Old Q5 | New Q8 | Old Q6 | New Q9 |
|---------|--------|--------|--------|--------|
| Marcus | Moderate | Rich | Moderate | Rich |
| Priya | Rich | Rich | Rich | Rich |
| Elena | **Flat** | **Rich** | **Flat** | **Rich** |
| James | Moderate | Rich | Rich | Rich |
| Sofia | Moderate | **Rich** | **Flat** | **Rich** |
| Tobias | Moderate | **Rich** | **Flat** | **Rich** |
| Aisha | Rich | Rich | Moderate | Rich |
| Derek | Rich | Rich | Rich | Rich |
| Min-Ji | **Flat** | **Rich** | **Flat** | **Rich** |
| Rafael | Moderate | Rich | Moderate | Rich |

---

## New Question Assessment

### Q3: "What business tasks do you know you should be doing but aren't?" [NEW]

**Pain surfaced that original guide missed:**

- Tobias's complete marketing paralysis -- not "spending too much time" but "spending zero time." Original Q1/Q2 could not capture this.
- Sofia's fear-of-what-she'll-discover blocking her from seeking legal help. Original guide captured her anxiety but not the specific avoidance mechanism.
- Min-Ji's knowledge gap: she knows she lacks marketing strategy fundamentals, not just tactics. Original guide showed her tactics failing but not why.
- Elena's inability to self-assess: she can't tell if she's doing marketing wrong because she doesn't know what right looks like.

**Verdict: High value. Directly patches the avoidance-pain gap identified in the original run.**

### Q4: "Which tasks keep you up at night -- the scary ones?" [NEW]

**Pain surfaced that original guide missed:**

- Marcus's 2 AM fear about launching unprotected -- emotional buying trigger.
- Elena's runway clock creating existential urgency behind marketing pain.
- James's supplier dependency risk buried under operational noise.
- Derek's $180K pipeline at specific risk (quantified fear, not abstract worry).
- Rafael's moral weight about damaging musicians' livelihoods.

**Verdict: Highest value new question. 10/10 rich responses. Captures emotional buying triggers that no operational question surfaces. This should be non-negotiable in every interview.**

### Q6: "What have you already tried? What worked/didn't/why?" [NEW]

**Pain surfaced that original guide missed:**

- Elena's $1,500/month freelancer failure and why (didn't understand architects).
- James's virtual assistant experiment: saved time but created management overhead.
- Min-Ji's $1,000 spent on freelancers with zero results (quantified waste).
- Tobias's book-learning attempt and why frameworks don't apply to niche markets.
- Sofia's awareness that affordable alternatives (LegalZoom) don't fit her specific situation.

**Verdict: Highest value for competitive positioning and pricing. Every response reveals what Soleur must do differently than existing alternatives. Also provides natural pricing anchors ("I spent $X on Y and it didn't work").**

### Q8: Rewritten trust question [REWRITE]

**Pain surfaced that original guide missed:**

- Every persona's specific quality criteria for their domain, stated constructively.
- Min-Ji's past-failure-informed skepticism (instead of blanket AI dismissal).
- Sofia's core problem: "I can't evaluate legal quality" (instead of "I don't know what AI agents means").
- Tobias's concrete validation framework (instead of philosophical AI analysis).

**Verdict: The rewrite eliminated all 3 flat responses and all "confused by jargon" responses. The outcome-first framing is strictly superior to the mechanism-first framing.**

### Q9: Rewritten "good enough" question [REWRITE]

**Pain surfaced that original guide missed:**

- Concrete minimum viable outcomes for every persona (vs. abstract quality definitions).
- Tobias's block is not "bad marketing" but "no marketing plan at all" -- the outcome he needs is an ICP and channel strategy, not better execution.
- Sofia's block was a specific lost deal -- the outcome she needs is a DPA ready to send in under an hour.
- Elena's outcome is a 90-day execution plan, not marketing theory.

**Verdict: The rewrite converted 4 flat responses to rich by changing the cognitive task from "define quality in an unfamiliar domain" to "describe what was missing in a specific bad experience." The latter requires no domain expertise.**

### Q10: "How would you know if it was done wrong?" [NEW]

**Pain surfaced that original guide missed:**

- The quality evaluation gap: founders in unfamiliar domains (legal, marketing) literally cannot be their own QA. This is a critical product design finding -- Soleur needs built-in validation mechanisms, not just output.
- The lagging indicator problem: for marketing, the only signal is results after execution. For legal, the only signal is a lawsuit or regulatory action. Both are too late.
- James's observation that all his quality signals are "damage already done" -- a systemic problem with delegated operational work.

**Verdict: Moderate value. 7/10 rich. Not as universally strong as Q4 or Q6, but surfaces product design requirements that no other question captures. Worth keeping.**

### Wrap-up: "What happens in 6 months?" [NEW]

**Pain surfaced that original guide missed:**

- Trajectory and urgency. Every prior question captures current-state pain; this captures the compounding cost of inaction.
- Derek's $180K pipeline has a 6-month expiration. Sofia's liability grows with each customer. Elena has 8 months of runway.
- Several personas confronted likely business death for the first time in the interview (Tobias: "go back to academia," Elena: "looking for a job").

**Verdict: High value. 10/10 rich. Provides the urgency dimension that the original guide lacked entirely. Should always close the interview because it retroactively amplifies all previously discussed pain.**

---

## Overall Assessment

### Response Quality Comparison

| Metric | Original Guide | Updated Guide |
|--------|---------------|---------------|
| Total questions | 6 | 11 (10 + wrap-up) |
| Total responses | 60 | 110 |
| Rich responses | 31 (52%) | 89 (81%) |
| Moderate responses | 18 (30%) | 17 (15%) |
| Flat responses | 11 (18%) | 4 (4%) |
| Confused responses | 0 (but 3 were confused within "flat") | 0 |
| Questions with 0 flat | 1/6 (Q4 hire) | 8/11 (all new/rewritten questions + Q3, Q7) |
| Questions achieving 10/10 rich | 0/6 | 4/11 (Q4, Q6, Q8, wrap-up) |

### Persona Improvement Rankings

| Rank | Persona | Original Rich (of 6) | Updated Rich (of 11) | Rich % Change | Key Improvement |
|------|---------|----------------------|----------------------|---------------|-----------------|
| 1 | **Tobias** | 0 (0%) | 6 (55%) | +55pp | Went from the worst-performing persona to a viable signal source. New questions (Q3, Q4, Q6) directly targeted his avoidance-pain archetype. |
| 2 | **Min-Ji** | 0 (0%) | 6 (55%) | +55pp | Q6 (failed alternatives) and Q8 (inbox rewrite) unlocked her. She has rich experiences with failed solutions but the original guide never asked. |
| 3 | **Sofia** | 2 (33%) | 9 (82%) | +49pp | New emotional and avoidance questions match her anxiety-based pain archetype. She went from flat on trust/quality to rich on inbox/existence questions. |
| 4 | **Elena** | 2 (33%) | 8 (73%) | +40pp | Rewritten questions eliminated the "confused by jargon" and "can't define quality" failure modes that suppressed her signal. |
| 5 | **Rafael** | 3 (50%) | 10 (91%) | +41pp | New questions surfaced his moral weight and failed-alternative attempts that original guide didn't capture. |
| 6 | **Marcus** | 4 (67%) | 11 (100%) | +33pp | Already strong; new questions captured his avoidance pain and emotional weight that the operational questions missed. |
| 7 | **James** | 4 (67%) | 9 (82%) | +15pp | Already strong; new questions surfaced supplier risk and VA failure that operational questions missed. |
| 8 | **Aisha** | 4 (67%) | 10 (91%) | +24pp | Already strong; new questions surfaced tax-surprise fear and the cost of cleanup deferral. |
| 9 | **Priya** | 6 (100%) | 10 (91%) | -9pp | Was already the strongest; slight rate dip because Q3 was Moderate (her avoidance pain is mild -- she's doing the tasks, just reactively). |
| 10 | **Derek** | 6 (100%) | 10 (91%) | -9pp | Already the strongest persona; slight rate dip because Q3 was Moderate. New questions added pipeline urgency and hiring avoidance signal. |

### Questions That Still Need Attention

**Three kept questions still produce flat responses:**

- Q1 (typical week): Tobias flat -- his pain is avoidance, not time burden. Mitigated by Q3 which captures avoidance directly.
- Q2 (hand off): Sofia and Tobias flat -- assumes existing tasks to delegate. Mitigated by Q3 which asks about tasks not being done.
- Q5 (AI tools): Min-Ji flat -- minimal AI experience and skepticism. Mitigated by Q6 which captures non-AI alternatives.

All 4 flat responses occur in kept questions and are compensated by adjacent new questions. No rewrites needed because the guide now has redundancy by design.

**The weakest new question is Q10** (quality evaluation) at 7 Rich / 3 Moderate / 0 Flat. The moderate responses from Elena, Tobias, and Min-Ji share a pattern: for marketing, quality evaluation is inherently lagging (you only know the strategy was wrong after executing it). This is not a question design flaw -- it is a genuine finding about marketing-pain personas that has product implications: Soleur needs to build leading indicators into the marketing domain.

### Problems Introduced by Changes

1. **Interview length risk.** 10 questions + wrap-up in 15 minutes is aggressive. At 1-1.5 minutes per response, the interview will run 12-17 minutes. Recommend identifying 2 questions that could be cut if time is short:
   - **Q5 (AI tools):** Produces moderate signal and overlaps with Q6 (failed alternatives). Q6 captures AI tool attempts plus non-AI attempts, making Q5 partially redundant.
   - **Q2 (hand off):** Partially redundant with Q3 (avoidance pain), which captures both "tasks I want to hand off" and "tasks I'm not doing."

   If cutting is needed: drop Q5, keep Q6. Drop Q2 only if the persona has already answered Q1 with clear delegation wishes.

2. **Emotional fatigue.** Q4 (scary tasks) + wrap-up (6-month trajectory) + Q8 (what makes you nervous) create three emotionally heavy moments. In a real interview, back-to-back heavy questions could cause the interviewee to shut down. Recommend spacing: keep Q4 early, Q8 in the middle (solution direction), wrap-up last.

3. **No new failure mode introduced.** The updated questions avoid all failure patterns identified in the original run: no jargon ("AI agents"), no domain-expertise assumptions ("what would good enough look like"), no wrong-unit measurements ("hours saved"), no binary trust questions ("would you trust"). The improvements are clean.

### Key Takeaways for Real Interviews

1. **The avoidance-pain archetype is now fully served.** Tobias went from 0/6 Rich to 6/11 Rich. The original guide assumed all pain manifests as time burden. The new questions (Q3, Q4, wrap-up) capture pain that manifests as paralysis, fear, and compounding risk.

2. **Outcome-first framing is strictly superior to mechanism-first framing.** Every rewrite that replaced "AI" language with outcome language improved response quality. This should be a permanent design principle for all customer research at Soleur: never ask about the mechanism, always ask about the outcome.

3. **Failed-alternatives data is the most actionable finding per question.** Q6 produces competitive intelligence, pricing anchors, and feature requirements in a single question. Every persona's failed-alternative story contains the implicit spec for what Soleur must do differently.

4. **The "scary" and "6-month trajectory" questions produce buying triggers, not just pain signals.** Derek's $180K pipeline with a 6-month expiration is not just pain -- it is a specific, time-bound reason to buy. The original guide produced pain data; the updated guide produces urgency data.

5. **The updated guide largely eliminates the need for separate "skeptic-friendly" questioning.** Elena and Min-Ji, both AI skeptics, went from 2/6 and 0/6 Rich to 8/11 and 6/11 Rich respectively. Min-Ji's one remaining flat (Q5, the kept AI-tools question) is the expected residual from a skeptic with minimal AI experience. The new and rewritten questions work for skeptics because they never mention AI -- they focus on outcomes and past experiences.
