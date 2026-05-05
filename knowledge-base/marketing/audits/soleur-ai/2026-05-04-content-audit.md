---
audit_date: 2026-05-04
audit_type: content
scope: soleur.ai (homepage + key landing pages)
brand_guide: knowledge-base/marketing/brand-guide.md (read and applied)
owner: CMO
---

# Soleur.ai Content Audit — 2026-05-04

**Scope:** Homepage, /pricing/, /about/, /vision/. This is a representative sample of the most-visited surfaces; remaining pages (Agents, Skills, Blog, Changelog) are not audited here.

**Brand guide status:** Present at `knowledge-base/marketing/brand-guide.md`. Voice (ambitious-inspiring, declarative, no hedging), tone profiles (general register for website), and value-proposition framings (primary: "Stop hiring. Start delegating." pain-point; recommended A/B: memory-first) were used to evaluate alignment.

---

## Summary

| Page | Detected target keywords | Keyword alignment | Search-intent match | Readability | Critical issues | Improvements |
|------|--------------------------|-------------------|---------------------|-------------|-----------------|--------------|
| Homepage `/` | "AI agents for solo founders", "company-as-a-service", "AI organization" | Strong on brand terms, weak on high-volume search terms | Mixed (informational hero, transactional CTAs, no commercial-investigation bridge) | Strong (declarative, short sentences, scannable) | 1 | 4 |
| `/pricing/` | "AI agents pricing", "solo founder AI tools pricing" | Weak — primary keyword is brand-led ("Every department. One price.") | Strong (transactional) | Strong | 1 | 3 |
| `/about/` | "Jean Deruelle", "Soleur founder", "what is Soleur" | Adequate for brand-nav intent | Strong (navigational) | Adequate; H1 is bare ("About") | 1 | 2 |
| `/vision/` | "company-as-a-service", "billion-dollar solo company", "AI organization platform" | Strong on owned terms; thin on entry-level informational queries | Informational, but reads like internal strategy doc | Weak — dense, abstract, low scannability | 2 | 3 |

---

## Per-Page Analysis

### Homepage (`/`)

**Page title:** "Soleur — AI Agents for Solo Founders | Every Department, One Platform"
**Meta description:** Not detected in fetched HTML (flag for SEO-AEO analyst).

**Detected target keywords:**
- "AI agents for solo founders" (title)
- "company-as-a-service platform" (H1 sub, H2)
- "stop hiring start delegating" (H1, repeats in lower CTA)
- "AI organization" (H2)

**Keyword alignment assessment:**
- The title hits the highest-value head term ("AI agents for solo founders") — good.
- Hero H1 is the brand pain-point framing ("Stop hiring. Start delegating.") which matches brand guide §Value Proposition Framings (primary). On-brand, but the phrase has near-zero existing search volume; it is a positioning line, not a keyword target. The H1 sub-line "The Company-as-a-Service platform for solo founders" recovers the keyword target, so the dual-headline pattern works.
- "AI organization" is owned-brand language and consistent across the page.
- Missed opportunities: "AI for solo founders," "AI tools for solopreneurs," "delegate to AI agents," and "AI assistant for founders" do not appear in any H2/H3 even though competitors rank for them.

**Search-intent match:**
- Hero serves informational/commercial-investigation users; primary CTA is transactional ("Join the Waitlist") and works for high-intent visitors.
- Gap: the secondary CTA "Or try the open-source version →" addresses transactional self-serve, but there is no commercial-investigation bridge (no "Compare," "How it works in 3 minutes," or "See an example day"). Visitors who arrived from informational queries have nowhere to convert before being asked for an email.

**Readability assessment:**
- Strong. Sentences are short. Department blocks follow a consistent micro-pattern (label → outcome). Aligns with brand guide voice rules (declarative, no hedging, "Trust the reader's intelligence").

**Issues found:**

| Severity | Issue |
|----------|-------|
| Critical | "Or try the open-source version →" violates brand guide §Don't ("Call it a 'plugin' or 'tool' in public-facing content"). "Open-source version" is acceptable but the sibling pricing-page CTA "Or start with the free open source version →" is also borderline. Bigger problem: the page says "open-source company-as-a-service platform that deploys 66 AI agents" — the count "66" is a hard number duplicated in prose, violating brand guide §Numbers ("never duplicate the exact count in prose, where it will drift"). FAQ block repeats "66 AI agents" twice more. |
| Improvement | Hero subhead does not surface a memory-first hook. Brand guide §Value Proposition Framings recommends A/B testing the memory-first variant ("The AI that already knows your business"). The page already uses the memory framing in body copy ("An organization that remembers") — promote it into a deck-line under the H1. |
| Improvement | Departments H2 ("8 departments. One knowledge base. Your expertise, amplified.") buries the keyword-strong phrase. "Your AI Organization" H2 above it could be retitled to capture "AI organization for solo founders." |
| Improvement | FAQ answers are good but lack concrete proof points required for AEO citation. "Soleur deploys 66 AI agents across 8 business departments" is repeated three times; switch to "60+ agents" (soft floor per brand guide) and add one statistic per answer (e.g., 67 skills, 420+ merged PRs, 8 departments named inline). |
| Improvement | "I would not be surprised if the first single-person billion-dollar company … happens in the next couple of years." — Dario Amodei quote is excellent for AEO/citation but lacks a source link. Link to the original Anthropic interview/podcast for citation-friendliness. |

**Rewrite suggestions:**

1. **Open-source mention (homepage opener)**
   - Current: "Soleur is an open-source company-as-a-service platform that deploys 66 AI agents across 8 business departments — engineering, marketing, legal, finance, operations, product, sales, and support — giving a single founder the operational capacity of a full organization."
   - Suggested: "Soleur is the open-source Company-as-a-Service platform: 60+ AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, and support — giving one founder the operational capacity of a full organization."
   - Rationale: Restores soft-floor count per brand guide; capitalizes "Company-as-a-Service" consistently; tightens "single founder ... operational capacity of a full organization" → "one founder ... full organization." Voice match: declarative, concrete, no hedging.

2. **Hero deck-line (add memory-first hook)**
   - Current (sub of H1): "The Company-as-a-Service platform for solo founders. Build a billion-dollar company — alone."
   - Suggested: "The Company-as-a-Service platform that already knows your business. Build a billion-dollar company — alone."
   - Rationale: Surfaces the memory differentiation called out in brand guide as the strongest unprompted pull in synthetic research, while preserving the closing punch line.

3. **Departments H2**
   - Current: "Your AI Organization" / "8 departments. One knowledge base. Your expertise, amplified."
   - Suggested: "Your AI organization for solo founders" / "8 departments. One compounding knowledge base. Your expertise, amplified."
   - Rationale: Captures keyword "AI organization for solo founders." Adds "compounding" — the differentiator term per brand guide glossary — without bloating the line.

4. **FAQ answer (What is Soleur?)**
   - Current: "Soleur deploys 66 AI agents across 8 business departments — engineering, marketing, legal, finance, operations, product, sales, and support — giving a single founder the capacity of a full organization."
   - Suggested: "Soleur is the Company-as-a-Service platform for solo founders. It deploys 60+ AI agents and 60+ skills across 8 departments — engineering, marketing, legal, finance, operations, product, sales, and support — so one founder runs the operational capacity of a full company."
   - Rationale: Adds the head keyword "Company-as-a-Service platform for solo founders," uses soft floors, surfaces "skills" as a second proof point. AEO-friendly: self-contained, definition-shaped, quotable in 1 sentence.

---

### `/pricing/`

**Detected target keywords:** "AI agents pricing," "solo founder AI tools pricing," "Soleur pricing"
**Keyword alignment:** Brand-led headline ("Every department. One price.") is on-voice but does not surface "pricing" as a keyword in any H1/H2 above the table. Page is found by users who already know the brand; it does not capture commercial-investigation traffic searching "AI agents for founders pricing" or "company-as-a-service cost."
**Search-intent match:** Strong transactional. Plan table is clear. Concurrent-conversation labelling is unusual jargon for the general register and may confuse non-technical visitors.
**Readability:** Strong overall.

**Issues found:**

| Severity | Issue |
|----------|-------|
| Critical | "Concurrent Conversations" is undefined on the page. Brand guide §General register requires inline definition on first use of jargon. Non-technical buyers will not know whether "2 concurrent conversations" is a hard cap, a soft cap, or per-day. |
| Improvement | H1 "Every department. One price." is great as a brand line but should be paired with a keyword-bearing subhead. |
| Improvement | "What You Replace" section header is strong copy but does not target the high-intent comparison query "AI vs hire contractor" / "replace contractors with AI." |
| Improvement | No FAQ answer is reproduced in the audit input that addresses "Is there a free trial?" / "Can I switch plans?" — both common pre-purchase queries. |

**Rewrite suggestions:**

1. **Pricing H1 subhead**
   - Current: "The team you need. Without the headcount."
   - Suggested keep H1 + add deck: "The team you need. Without the headcount. Pricing for the Company-as-a-Service platform — every department, one subscription."
   - Rationale: Adds "pricing" + "Company-as-a-Service platform" + "subscription" to the above-the-fold area. Preserves the brand line. Voice match: declarative, no hedging.

2. **Concurrent Conversations definition (inline)**
   - Current: column header "Concurrent Conversations" with values 2 / 5 / 50 / Custom.
   - Suggested: Add a one-line note above the table: "A concurrent conversation is one active session with your AI organization. Two conversations means two agents working in parallel — for example, your marketing agent drafting a launch announcement while your legal agent reviews a contract."
   - Rationale: Brand guide §General register: "no jargon without immediate definition in the same sentence." Voice match: concrete, business-outcome example.

---

### `/about/`

**Detected target keywords:** "Jean Deruelle," "Soleur founder," "who founded Soleur," "what is Soleur"
**Keyword alignment:** Adequate. The four FAQ H3s are essentially crawler-bait for AI engines and serve AEO well. Founder name appears prominently.
**Search-intent match:** Navigational/informational. Works.
**Readability:** Adequate. The bare H1 "About" is a missed opportunity.

**Issues found:**

| Severity | Issue |
|----------|-------|
| Critical | H1 is just "About". Should be either "About Soleur" or "About the founder of Soleur" to anchor a clear topical entity per AEO. Title tag already says "About Jean Deruelle - Soleur" which conflicts with H1. |
| Improvement | "Jean is a software engineer with over 15 years of experience building distributed systems and developer tools." — adequate but lacks specificity. Brand guide §Authority/E-E-A-T calls for first-hand experience signals. Add one or two concrete proof points (companies, OSS projects, scale numbers). |
| Improvement | FAQ answer "What is MCP?" is included but no FAQ answers are reproduced in the audit input — verify whether the answer is self-contained and quotable, and ensure it links to the official MCP spec for citation authority. |

**Rewrite suggestions:**

1. **H1**
   - Current: "About"
   - Suggested: "About Soleur and its founder, Jean Deruelle"
   - Rationale: Establishes both entities (organization + person) on a single page — strongest AEO entity-clarity signal. Title-tag and H1 stop conflicting.

2. **Founder credibility paragraph**
   - Current: "Jean is a software engineer with over 15 years of experience building distributed systems and developer tools."
   - Suggested: "Jean Deruelle is a software engineer with 15+ years building distributed systems and developer tools. Before Soleur he led engineering on telecom and real-time communications platforms used at carrier scale, and contributed to multiple open-source projects in the JVM and signaling-protocol ecosystems."
   - Rationale: Adds specificity. Voice match: declarative, concrete. (CMO note — verify the second sentence against Jean's bio before publishing; do not invent facts.)

---

### `/vision/`

**Detected target keywords:** "Soleur vision," "company-as-a-service," "billion-dollar solo company"
**Keyword alignment:** Strong on owned-brand language; thin on entry-level informational queries. The page assumes the reader already knows what CaaS is.
**Search-intent match:** Informational, but the page reads like an internal strategy memo rather than a public-facing vision page. Headings like "Strategic Architecture," "Master Plan," "Methodology," "Orchestration" are abstract and hard to skim.
**Readability:** Weak. Section labels are nouns-as-categories ("Leverage," "Governance," "Methodology," "Intelligence," "Orchestration," "Control," "Coordination," "Validation") with no narrative throughline visible from the heading map. This violates brand guide §Don't: "Over-explain — trust the reader's intelligence" cuts both ways: the page also under-narrates what each abstract noun means.

**Issues found:**

| Severity | Issue |
|----------|-------|
| Critical | Heading hierarchy reads as a strategy slide deck, not a public page. A first-time visitor scanning H2/H3 cannot extract "what does Soleur believe" without reading every section. |
| Critical | "The world is moving toward infinite leverage. When code and AI can replicate labor at near-zero marginal cost, the only remaining bottlenecks are Judgment and Taste." — strong thesis statement, but it is not the H1 deck-line. Move it up. |
| Improvement | No source citations on macro claims ("infinite leverage," "near-zero marginal cost"). Brand guide §Authority calls for source citations to support AI-engine citations. Link to Dario Amodei interview, Sam Altman essay, or equivalent. |
| Improvement | "Soleur is built by Soleur" line is the most quotable proof on the entire page and is buried in body copy. Promote to a dedicated callout. |
| Improvement | FAQ section exists per the heading map but the H3s are listed as "Individual FAQ questions" — verify each Q is a real search query (e.g., "What is company-as-a-service?", "How is Soleur different from Cursor?"). |

**Rewrite suggestions:**

1. **Hero deck-line (under the H1)**
   - Current: H1 "The Soleur Vision: Company-as-a-Service for the Solo Founder" with no deck-line evident in the fetched content.
   - Suggested deck-line: "The world is moving toward infinite leverage. When code and AI replicate labor at near-zero marginal cost, the only bottlenecks left are judgment and taste. Soleur is the platform built for that world."
   - Rationale: Surfaces the thesis above the fold. Voice match: declarative, future-already-here ("is moving," "is the platform"). On-brand per §Voice (Vercel-like conviction).

2. **Section H2 retitling**
   - Current: "Strategic Architecture" → H3 set "Intelligence / Orchestration / Control"
   - Suggested: "How Soleur is built" → "Intelligence: agents that specialize / Orchestration: skills that coordinate / Control: the founder's judgment, always."
   - Rationale: Replaces abstract nouns with phrase-headings that AEO engines and human scanners can quote. Captures the keyword "how Soleur is built" / "how Soleur works" which appear in informational queries.

3. **"Soleur is built by Soleur" callout**
   - Current: Buried in prose: "Soleur is built by Soleur. The platform's own growth, marketing, and code maintenance are handled by its own agents."
   - Suggested callout block: "**Soleur is built by Soleur.** Our growth, marketing, content, and code maintenance are run by the same agents we ship to founders. We dogfood every department."
   - Rationale: This is the single strongest credibility signal on the page. Brand guide §Authority/E-E-A-T explicitly values first-hand experience claims. Voice match: matches the "Designed, built, and shipped by Soleur — using Soleur" footer line.

---

## Cross-Page Issues

| Severity | Issue | Affected pages |
|----------|-------|----------------|
| Critical | Hard agent count "66" duplicated in prose violates brand guide §Numbers (use "60+" soft floor in static prose). | Homepage, Pricing, About FAQ |
| Improvement | Meta descriptions are absent from all four fetched pages. (Confirm with seo-aeo-analyst — descriptions may exist in `<head>` but were not surfaced by WebFetch's HTML→Markdown conversion.) | All |
| Improvement | No internal pillar/cluster signaling: the homepage department list links to per-department detail pages but those are not visible from the audit. If they don't exist, the homepage is doing pillar work without cluster support. Recommend follow-up content plan. | Homepage |
| Improvement | "Stop hiring. Start delegating." appears twice on the homepage (hero + lower CTA). Brand guide §execution-constraints note: "avoid repetition within 200 words of the same keyword." This is a positioning line so the repetition is more forgivable than a keyword stuff, but the lower CTA could vary to "Your AI organization is ready. Are you?" (already the documented closing CTA pattern). | Homepage |

---

## Brand Voice Alignment Notes

**What is on-brand and should be preserved:**

- Declarative hero copy ("Stop hiring. Start delegating.") — exemplary §Voice match.
- Workflow section H3s (Think / Plan / Build / Review / Ship / Compound) — verbs, declarative, no hedging.
- "Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, remembers, and self-improves." — verbatim brand-guide approved phrase, used correctly.
- Trust scaffolding present: "Soleur is human-in-the-loop by design" addresses the "what if the AI is wrong" objection per brand guide §2026-03-26 research note.
- Concrete numbers used throughout (8 departments, agents count, 67 skills) — §Voice "use concrete numbers when available."

**Drift from brand voice:**

- Hard agent count "66" duplicated in prose violates §Numbers soft-floor rule. Use `{{ stats.agents }}` in templates and `60+` in static prose.
- "Or try the open-source version →" / "Or start with the free open source version →" — phrase is acceptable but borders on framing Soleur as a "tool" rather than a platform. Prefer "Self-host Soleur free" or "Run Soleur on your own infrastructure" — keeps the platform framing per §Don't.
- `/vision/` page H2/H3 vocabulary ("Methodology," "Orchestration," "Coordination," "Validation") is closer to consulting-deck language than the brand's punchy declarative voice. Brand guide §Voice tone for Marketing/Hero is "Maximum ambition, declarative" — vision page should match.
- About-page bare H1 "About" is voiceless — every other H1 across the site carries brand energy.

**Voice traps avoided (good):**

- No instances of "AI-powered," "leverage AI," "just," "simply," "assistant," "copilot" used in the wrong context (the only "copilot" mention is in the FAQ comparison "Cursor and Copilot help you write code" — correct usage as a competitor reference).
- No "excited to announce" / startup jargon detected.
- No emojis in marketing copy.

---

## Priority Fix List (next action)

| Priority | Fix | Page | Effort |
|----------|-----|------|--------|
| P1 | Replace all hard agent counts ("66 AI agents") in prose with the `60+` soft floor (or template variable) | Homepage, Pricing, About FAQ | XS |
| P1 | Define "Concurrent Conversations" inline on the pricing page | Pricing | XS |
| P1 | Replace bare H1 "About" with "About Soleur and its founder, Jean Deruelle" | About | XS |
| P1 | Add memory-first deck-line under homepage H1 | Homepage | XS |
| P2 | Retitle vision-page abstract-noun H2/H3s to phrase headings; promote thesis line above the fold | Vision | M |
| P2 | Add inline source links to Dario Amodei quote (homepage) and infinite-leverage thesis (vision) | Homepage, Vision | S |
| P2 | Promote "Soleur is built by Soleur" to a dedicated callout block | Vision | S |
| P3 | Audit /agents/, /skills/, /blog/ for keyword alignment in a follow-up pass | — | M |

---

## Out of Scope (route to other agents)

- Meta description presence/length, JSON-LD, sitemap, llms.txt, robots.txt, schema.org markup → seo-aeo-analyst.
- Full SAP/AEO scorecard → run the GEO/AEO content audit mode in a follow-up pass.
- Competitor keyword gap analysis → run the content-plan workflow with competitor URLs supplied.
