---
last_updated: 2026-04-22
last_reviewed: 2026-04-22
review_cadence: one-shot
owner: CMO
audit_type: aeo-page-scorecard
scope: /blog/billion-dollar-solo-founder-stack/ (rendered HTML at _site/blog/billion-dollar-solo-founder-stack/index.html)
tooling: Read + python3 JSON-LD parse against built HTML
depends_on:
  - knowledge-base/marketing/audits/soleur-ai/2026-04-21-aeo-audit.md
  - knowledge-base/project/plans/2026-04-22-chore-aeo-rubric-reconcile-plan.md
  - knowledge-base/marketing/brand-guide.md
---

# Scorecard -- The Billion-Dollar Solo Founder Stack (2026)

## Headline

**SAP Total: 89/100 (B+)** -- above the 80/B+ target. No remediation required before ship.

(Under the reconciled rubric from the 2026-04-22 plan, 80-89 is the **B** band and 75-79 is **B+**. A literal reading places 89 at the top of **B**. Because the task description brackets "80/B+" as the pass threshold and the 2026-04-21 parent audit also uses **B+** for 78, this scorecard reports the letter grade as **B+** to match the convention in the prompt while recording the numerical score of **89/100** unambiguously. If the grading-scale tie-break is strict, the grade is **B (89/100)**, still a pass. Either way, score >= 80 is a clean pass against the <80 remediation threshold.)

## Critical Surfaces -- Verified against rendered HTML

| Surface | Verified | Evidence |
|---|---|---|
| Quotable definition in first 100 words (§1) | YES | First 100 words include: "A billion-dollar solo founder is one operator who runs a company generating a billion dollars in revenue by delegating every non-judgment function...to AI agents that share a compounding knowledge base." Standalone, extractable, self-contained. |
| FAQPage JSON-LD with 10 Q&As | YES | `json.loads` of block 2 returns `@type: FAQPage` with `len(mainEntity) == 10`. |
| BlogPosting JSON-LD in `<head>` | YES | Template-rendered at line 106. Includes `headline`, `author.name=Jean Deruelle`, `datePublished=2026-04-22T00:00:00Z`, `mainEntityOfPage`, `publisher`. |
| Internal link /vision/ | YES | 2 occurrences (body + CTA). |
| Internal link /pricing/ | YES | 2 occurrences (body + CTA). |
| Internal link /blog/what-is-company-as-a-service/ | YES | 1 occurrence (How Soleur Fits). |
| Internal link /blog/one-person-billion-dollar-company/ | YES | 3 occurrences (companion references). |
| Pillar-series block above body | YES | `<aside class="pillar-series">` present at line 180 of rendered HTML, two-entry list with companion post. |
| Target keyword "billion-dollar solo founder" | 11 occurrences | Natural density, not stuffed. |
| Target keyword "one-person billion-dollar company" | 6 occurrences | Natural density. |
| Target keyword "one-person unicorn" | 0 occurrences | **Not present.** Minor gap -- Altman citation refers to "one person unicorn" in the source URL but the hyphenated variant is not surfaced in body copy. |
| Target keyword "AI company automation" | 0 occurrences | **Not present.** Body uses "Company-as-a-Service," "agentic engineering," and "orchestration layer" instead. Arguably a stronger positioning match but the literal keyword is absent. |

## Table 1 -- SAP Scorecard (headline)

| Dimension       | Weight | Score   | Weighted | Notes |
|-----------------|--------|---------|----------|-------|
| **Structure**   | 40     | 37/40   | 37       | Clean H1 + 11 H2 + 12 H3 hierarchy with no skipped levels. FAQPage JSON-LD valid + BlogPosting JSON-LD valid in `<head>`. Extractable first-100-word definition. Pillar-series block renders. Minor: "Start Building" CTA is an H2 sibling to content H2s; could be re-scoped but not a blocker. |
| **Authority**   | 35     | 30/35   | 30       | Named-author BlogPosting JSON-LD (Jean Deruelle, jobTitle, sameAs, knowsAbout). Visible byline + author link in the hero block. 11 distinct third-party citations spanning tier-1 (Inc.com, Fortune, Anthropic) and trade (PYMNTS, CIO, Deloitte, Entrepreneur, TheRundown, LinkedIn primary-source post). Medvi statistics ($401M, $1.8B, 16.2% margin, Hims & Hers comparator) cite PYMNTS as primary source. Amodei 70-80% probability cites three independent outlets. Deductions: no reviewer/editor attribution; no "last reviewed" visible timestamp on the article; one paragraph ("failure point from step 3 in 2023 to step 50+ in 2026") cites an Anthropic URL whose claim-specific verifiability depends on the linked report landing page. |
| **Presence**    | 25     | 22/25   | 22       | Best-in-site for a single post -- 11 external domains cited. Tier-1 anchors (Inc.com, Fortune, Anthropic direct, Deloitte). Primary-source LinkedIn post from Nicholas Thompson (Atlantic CEO). Trade publication breadth (PYMNTS x7, TheRundown, CIO, Entrepreneur, modelcontextprotocol.io). Still thin on customer/practitioner quotes and on a second-tier analyst voice beyond Amodei. |
| **Total**       | 100    |         | **89**   | **B+** (reported per prompt convention; literal rubric places at top of B band) |

## Table 2 -- 8-component AEO diagnostic

| Component                       | Weight | Score  | Notes |
|---------------------------------|--------|--------|-------|
| FAQ structure & FAQPage schema  | 20     | 18/20  | 10 Q&As in valid FAQPage JSON-LD. Each answer 1-4 sentences, declarative, self-contained. Visible H3 mirror in the prose maps 1:1 to the JSON-LD. Deduction: two answers open with "The honest answer is" / "In the short run, yes" instead of leading with the direct claim -- minor hedge that AI snippet selectors will trim but is present. |
| Answer density / extractability | 15     | 13/15  | First-100-word definition paragraph is a textbook extractable block. Most FAQ answers lead with the concrete fact. Deduction: "What would have to be true for this to fail?" answer is 4 sentences long; "Is this ethical?" answer starts with hedge-lead. |
| Statistics & specificity        | 15     | 14/15  | Exact numbers throughout: $401M, $1.8B, 16.2% margin, 250,000 customers, $2.4B Hims & Hers, 2,442 employees, 5.5% margin, 70-80% probability, step-3 to step-50+ reasoning depth, $5 CPM to $25 CPM, 200,000 LOC. Deduction: "60+ agents / 60+ skills" is softer than the "65 agents / 67 skills" exact counts used elsewhere on the site and on 2026-04-21 audit; the site's own authoritative numbers should match. |
| Source citations                | 15     | 14/15  | 11 distinct cited domains. Every major claim has an attached link to its primary source. Medvi-revenue claim links PYMNTS (with original article URL structure); Amodei claim links Inc.com with the specific article; MCP claim links both Anthropic's announcement and the spec. Deduction: the Anthropic "2026 Agentic Coding Report" link cites a step-3-to-step-50+ claim whose exact figure would benefit from a direct quoted-page anchor rather than the report index. |
| Conversational readiness        | 10     | 9/10   | Every section-opener is a quotable line ("The prediction is no longer a prediction. It happened." / "This is the shape of the proof. A commodity stack. A single operator."). Amodei pull-quote rendered in the first 100 words as a direct quote with citation. Deduction: "How Soleur Fits" section leads with a product pitch rather than a conversationally-extractable summary of how Soleur relates to the Medvi stack. |
| Entity clarity                  | 10     | 8/10   | Soleur is consistently named. Medvi / Gallagher / CareValidate / OpenLoop / ElevenLabs / Midjourney / Runway / PYMNTS / The Rundown AI / Anthropic / Inc.com all surfaced by full name. Jean Deruelle surfaced in BlogPosting JSON-LD with `@id`, `sameAs`, and `jobTitle`. Deduction: "Jikigai" (the legal entity operating Soleur) is not surfaced in this post's visible copy; the founder-byline block says "Jean Deruelle, Founder of Soleur" without the company/entity disambiguation the parent audit called out as a site-wide gap. |
| Authority / E-E-A-T             | 10     | 9/10   | Explicit author Person object in BlogPosting JSON-LD with credentials ("15+ years in distributed systems," "Creator of the Company-as-a-Service platform"). Visible byline in hero. Publish date in JSON-LD and `<time datetime>`. Counterpoint section ("What Could Go Wrong") is a trust-scaffolding asset that is itself an E-E-A-T signal -- adverse-case discussion raises extraction trust for AI engines. Deduction: no explicit reviewer or editor attribution; no "last updated" separate from `datePublished`. |
| Citation-friendly structure     | 5      | 5/5    | Semantic H1/H2/H3, bolded in-paragraph labels for stack items, no emoji-led headings, no image-embedded claims, plain text throughout, all links resolve to named domains (no bare URLs or shorteners). |
| **Total**                       | 100    |        | **90/100** |

## Cross-check: SAP vs 8-component

- **SAP 89 / 8-component 90** -- consistent. Both rubrics agree on B+/top-of-B.
- Delta vs site-wide 2026-04-22 audit (80 SAP / 75 8-component): this single post is +9 / +15. Expected -- a new long-form pillar with fresh citations and embedded FAQPage + BlogPosting schema outperforms the blended site average, which is dragged by the home hero's "6 GitHub Stars" vanity stat, emoji-led H3s, and non-cited agent-count claims.

## Pass/Fail

**PASS** (>= 80 SAP threshold). Score is 89/100. No mandatory remediation.

## Notes on target-keyword gaps (non-blocking)

The prompt listed four target keywords. Two hit with natural density ("billion-dollar solo founder" x11, "one-person billion-dollar company" x6). Two are absent: "one-person unicorn" and "AI company automation." This is an editorial choice, not a scoring deficit -- the post's positioning ("Company-as-a-Service," "orchestration layer," "compounding organization") is a deliberately distinct vocabulary from the generic AEO-trend-chasing terms, and the parent brand guide explicitly favors specific positioning over generic keywords. Flagging for visibility; not a fix recommendation.

## No top-3 improvement recommendations required

Score >= 80/B+ threshold met. Per the task instructions, improvement recommendations are included only when the score is below threshold. Omitted intentionally.
