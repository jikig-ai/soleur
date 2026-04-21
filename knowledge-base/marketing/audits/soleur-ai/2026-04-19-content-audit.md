---
date: 2026-04-19
auditor: growth skill (content-strategy agent)
scope: soleur.ai public site -- content audit (keyword alignment, search intent, readability)
brand_guide: knowledge-base/marketing/brand-guide.md (read and applied)
sample: 10 top-level pages + 5 pillar blog posts (sitemap has 36 URLs; sampled by nav + traffic-weight)
---

# Soleur.ai Content Audit -- 2026-04-19

## Executive Summary

Soleur.ai has strong positioning ("Stop hiring. Start delegating."), a
consistent numeric spine (65 agents / 8 departments / 66 skills), and
well-structured FAQ blocks on most pages -- which is unusually good for AEO
(AI engine citeability). The site is voice-aligned with the brand guide's
ambitious-inspiring register and correctly avoids banned phrases ("AI-powered,"
"copilot," "just/simply," "terminal-first" in user-facing copy).

Three problem clusters dominate:

1. **Search-intent mismatch on the homepage.** The homepage targets branded
   + informational intent well but does not capture the highest-value
   commercial query cluster -- "AI agents for solo founders," "AI team for
   startups," "company as a service" -- in `<h1>`/`<h2>` anchors. The
   pillar-keyword "Company-as-a-Service" appears in title and body but NOT
   in H1 or H2, weakening topical authority.
2. **Pillar/cluster structure is inverted.** The strongest pillar candidate
   (`/blog/what-is-company-as-a-service/`) is a blog post, not a pillar
   page; comparison posts (`soleur-vs-cursor`, `soleur-vs-notion-custom-agents`,
   `soleur-vs-paperclip`) exist as a cluster but lack a shared hub and
   sibling cross-links. `/vision/` competes with the CaaS pillar for the
   same keyword.
3. **Numeric drift across pages.** Homepage says "65 agents" and "66 skills";
   pricing says "65 specialists"; brand guide says "63 agents / 62 skills";
   header stat blocks say "60+ agents." Inconsistent numbers weaken E-E-A-T
   and give AI engines conflicting facts to cite. Pick canonical numbers
   and update everywhere in lockstep, or switch to `60+` / `65+` floors.

No critical readability blockers found. Sentences are short and declarative
(matches "Keep sentences short and punchy"). Jargon management is good --
technical register on `/getting-started/`, general register on `/`, `/pricing/`,
`/about/`.

**Top 5 fixes, in priority order:**

1. Add "Company-as-a-Service" to homepage H1 or H2 eyebrow (currently only
   in body prose). Target intent: informational + commercial.
2. Resolve agent/skill count drift. Canonical counts, applied everywhere in
   one commit.
3. Convert `/blog/what-is-company-as-a-service/` into (or cross-link to) a
   `/company-as-a-service/` pillar page; make comparison posts cluster back
   to it.
4. Add missing target-intent meta descriptions on `/agents/`, `/skills/`,
   `/community/` (currently generic; include the primary keyword + outcome).
5. Rewrite `/vision/` subheads to target "AI agent orchestration platform"
   rather than internal-vocabulary headings like "The Global Brain" and
   "The Decision Ledger" (these are poetic but zero search signal).

---

## Methodology

- Fetched 15 URLs via curl (WebFetch blocked by 403 bot guard; flagged as
  separate SEO issue).
- Extracted `<title>`, meta description, H1/H2/H3, body word count, and
  visible FAQ text.
- Checked keyword alignment (page target keyword vs. headings vs. body vs.
  meta).
- Checked search-intent match (informational / navigational / commercial /
  transactional) against URL + user expectation.
- Applied readability heuristics (sentence length, jargon, paragraph
  density, lede clarity).
- Cross-referenced brand guide Voice section, Do/Don't list, and audience
  register rules (general vs. technical).

---

## Per-Page Analysis

| URL | Target intent | Primary keyword | Keyword alignment | Readability | Top issues |
|---|---|---|---|---|---|
| `/` | Commercial + branded | "AI agents for solo founders," "Company-as-a-Service" | Partial -- title and meta strong; H1 misses pillar keyword; CaaS mentioned in body only | Strong -- short declaratives, concrete numbers, clear CTA | Pillar keyword absent from H1/H2; two CTAs ("Join the Waitlist," "See Pricing & Join Waitlist") compete; count drift (65 agents / 66 skills vs. 60+ stat block) |
| `/about/` | Navigational (brand/founder) | "Jean Deruelle Soleur founder" | Strong -- title, meta, H1 all on-intent; founder bio has concrete years and stack | Strong -- bio reads clean | Missing backlinks/citations for "15+ years" claim; no author schema markup visible in prose (handled by seo-aeo if JSON-LD) |
| `/pricing/` | Commercial / transactional | "AI team pricing," "founder AI pricing" | Strong -- title, meta, H1 aligned; cost-replacement table is a citeable asset | Strong -- scannable table, short rationale | "From $49/mo" without tier detail on this page preview; "Enterprise prospect needs a DPA?" section reads well but the $95K/mo total needs a dated-source footnote for AEO trust |
| `/getting-started/` | Transactional (install) + informational | "get started Soleur," "install Soleur Claude Code" | Partial -- meta leads with memory hook rather than installation intent; title generic | Strong -- code blocks for install, numbered workflow | Hybrid page: mixes waitlist CTA and OSS install CTA, splits intent; "Takes 30 seconds" claim unverifiable -- either substantiate or soften |
| `/vision/` | Informational (founder/investor) | "AI agent orchestration," "billion-dollar solo company" | Weak -- H2s are internal vocabulary ("The Global Brain," "The Decision Ledger") with no search volume; "Company-as-a-Service" repeats the blog pillar | Medium -- heavier prose, longer sentences than brand average ("collapse the friction between a startup idea...") | Competes with CaaS blog pillar; H2s not SEO-extractable; 689 words -- either expand to true pillar or compress to positioning summary |
| `/agents/` | Commercial + informational | "AI agents for [department]" | Weak -- meta is a flat list, not an outcome | Strong -- 8 department sections | Meta description is a comma-separated list ("engineering, marketing, legal, finance...") -- replace with benefit-led sentence; missing per-agent deep links would help cluster architecture |
| `/skills/` | Informational / technical | "AI workflow skills," "agentic engineering workflows" | Partial -- meta good ("Multi-step workflow skills..."); H1 "Agentic Engineering Skills" narrows the keyword from broader "AI skills" | Strong | Category naming ("Uncategorized" as a visible H2) breaks professionalism; consolidate or rename |
| `/blog/` | Informational (index) | "agentic engineering blog," "company as a service blog" | Strong -- title + meta on-intent | Strong | No visible author bylines or dates on the index view (per extraction); add for E-E-A-T |
| `/changelog/` | Navigational (product) | "Soleur changelog," "Soleur releases" | Strong -- title/meta/H1 all aligned; semantic versioning explicitly noted | Medium -- 60+ H2 version entries on one page is heavy; consider pagination or a summary-of-week at the top | Frequency-of-release signal is strong; convert top 3 releases into "What's new this week" intro paragraph so AI engines can quote "Soleur ships multiple releases per day" |
| `/community/` | Navigational | "Soleur Discord," "Soleur GitHub" | Strong -- title, meta, H2s aligned | Strong | Live counters ("6 GitHub Stars, 8 Discord Members") read small for an "active community" framing -- either grow before foregrounding, or reframe as "early community" honestly |
| `/blog/what-is-company-as-a-service/` | Informational (pillar candidate) | "Company-as-a-Service," "CaaS platform" | Strong -- title, meta, H1 fully aligned; H2s cover problem/how/comparison/tech/audience/future | Strong -- 2,665 words with clean subsections | Should be promoted to pillar URL (`/company-as-a-service/`) or cross-linked as the canonical hub from `/vision/` and `/`; comparison blog posts should link here |
| `/blog/ai-agents-for-solo-founders/` | Informational (pillar candidate) | "AI agents for solo founders" | Strong -- 2,871 words, H2 structure covers definition/domains/failure-modes/selection/outcome | Strong | Same as above -- pillar material living on `/blog/`; sibling cluster posts don't back-link explicitly in extracted text |
| `/blog/soleur-vs-cursor/` | Commercial comparison | "Soleur vs Cursor," "AI coding tool vs agent platform" | Strong -- title, meta, H1, H2 all on-intent; dated claim ("Cursor shipped Automations in March 2026") is citeable | Strong | No cross-links to `/blog/soleur-vs-notion-custom-agents/` or other vs. posts -- each comparison post is an island |
| `/blog/why-most-agentic-tools-plateau/` | Informational opinion | "why AI tools plateau," "compound knowledge AI" | Strong | Strong | "Compound knowledge" is a differentiating term -- worth a dedicated glossary entry page to own the keyword |
| `/blog/vibe-coding-vs-agentic-engineering/` | Informational comparison | "vibe coding vs agentic engineering" | Strong -- title/H1/H2 all aligned, rides trending term | Strong -- 1,751 words, clean structure | Good shareable content (opinion + novel framing); make sure it back-links to the agentic-engineering pillar (`/skills/`) and the CaaS pillar |

---

## Issues Found (Prioritized)

### Critical -- Block discoverability or create factual conflict

| # | Issue | Page(s) | Why it matters |
|---|---|---|---|
| C1 | Numeric drift: 65/66 agents-skills vs. 60+ stat blocks vs. 63/62 in brand guide | `/`, `/pricing/`, `/about/`, `/agents/`, brand-guide.md | AI engines citing Soleur will surface conflicting numbers. E-E-A-T red flag. Pick canonical values OR switch to soft floors ("60+") everywhere. |
| C2 | Pillar keyword "Company-as-a-Service" missing from homepage H1/H2 | `/` | Homepage does not rank for its own category-defining term. H1 is the pain-point framing only. |
| C3 | Pillar page is a blog post, not a hub | `/blog/what-is-company-as-a-service/` vs. missing `/company-as-a-service/` | The defining category page for the brand lives in `/blog/`, which carries less authority than a top-level pillar and depth-of-path hurts AI citation weight. |
| C4 | `/vision/` H2s are internal vocabulary with zero search signal | `/vision/` | "The Global Brain," "The Decision Ledger," "The Coordination Engine" are brand-proprietary; AI engines have no way to match these to user queries. |
| C5 | Homepage FAQ answer to "Is Soleur free?" references a tier name ("Spark") not defined on the page | `/` | Breaks the AEO rule "answers must be self-contained." AI models quoting this will surface an ambiguous tier. |

### Improvement -- Enhance ranking and AI citeability

| # | Issue | Page(s) | Why it matters |
|---|---|---|---|
| I1 | Meta description on `/agents/` is a flat comma list, no benefit | `/agents/` | Low CTR from SERP; no keyword-anchored hook. |
| I2 | `/getting-started/` splits intent between waitlist and OSS install | `/getting-started/` | Single-intent pages convert better and rank cleaner. Consider split or clearer above/below-fold sectioning. |
| I3 | Comparison blog cluster has no shared hub and no visible sibling links | `/blog/soleur-vs-*` | Cluster-pillar model requires each cluster page link to pillar + at least one sibling. |
| I4 | "Takes 30 seconds" claim on `/getting-started/` is unverifiable | `/getting-started/` | Soft claim without proof erodes trust; either instrument or rephrase. |
| I5 | Header stat "6 GitHub Stars" foregrounded on home + community | `/`, `/community/` | At this scale, lead with velocity ("3.53 releases, shipping daily") rather than star counts. |
| I6 | "Uncategorized" visible as an H2 on `/skills/` | `/skills/` | Breaks professional presentation; recategorize or rename to something intentional ("Utilities" etc.). |
| I7 | Two CTAs competing on homepage: "Join the Waitlist" and "See Pricing & Join Waitlist" | `/` | A/B test to one primary action; the duplicate reduces clarity. |
| I8 | `/changelog/` has 60+ H2 entries on one view | `/changelog/` | Intro summary ("What shipped this week: 18 releases") would give AI engines one quotable line. |
| I9 | `/community/` currently overclaims "active community" vs. live counters | `/community/` | Honesty compounds trust -- either reframe as "early community, builder-heavy" or delay the copy until numbers catch up. |
| I10 | `$95,000/mo` replacement-cost table on `/pricing/` lacks a dated source footnote | `/pricing/` | Dated citations dramatically improve AEO citation rate. Add "US market median, 2025-2026 (source: BLS / levels.fyi)". |
| I11 | `/about/` missing inline authority links for "15+ years" and "Java, Ruby, Go, TypeScript" claims | `/about/` | Link to GitHub, LinkedIn, or prior talks; lifts E-E-A-T. |
| I12 | `/vision/` lede uses "collapse the friction between a startup idea and a billion-dollar outcome" -- long and abstract | `/vision/` | Brand voice says "keep sentences short and punchy." Compress. |
| I13 | 403 response on default WebFetch user-agent | infra | Bot-hostile headers block legitimate AI crawlers (Perplexity, Claude, GPTBot) depending on rule set. Review allow-list. (Flag to seo-aeo-analyst; out of scope here.) |

---

## Rewrite Suggestions (Brand-Voice Aligned)

Voice check: every rewrite below has been vetted against the brand guide --
short declaratives, no "just/simply," no "AI-powered," no "copilot," no
"terminal-first," human-in-the-loop trust scaffold preserved, "we/you"
conventions followed.

### RW-1: Homepage -- add CaaS anchor to H2 eyebrow

- **Page:** `/`
- **Current:** `H1: Stop hiring. Start delegating.` / `H2: The AI that already knows your business.`
- **Suggested:** Keep H1 unchanged. Change the existing eyebrow/badge above H1 to read `COMPANY-AS-A-SERVICE` (ALL CAPS, gold, per brand guide hero pattern). Add a new H2 earlier in the page: `Company-as-a-Service for solo founders.`
- **Rationale:** Captures the pillar keyword in a scannable anchor without
  sacrificing the pain-point headline. Matches the brand guide's prescribed
  hero pattern: "Badge (ALL CAPS, gold) > Headline > Subheadline."

### RW-2: Homepage FAQ -- self-contained answer to "Is Soleur free?"

- **Current:** "Soleur offers two paths. The cloud platform (coming soon) provides managed infrastructure, a web dashboard, and priority support -- pricing starts at the Spark tier. The self-hosted version is open source and free..."
- **Suggested:** "Soleur offers two paths. The self-hosted version is open source and free (Apache 2.0). The cloud platform starts at $49/month and includes managed infrastructure, a web dashboard, and priority support. Both run on Anthropic's Claude models, so your AI costs depend on your Claude usage."
- **Rationale:** Self-contained (AEO rule: answers must quote cleanly in
  isolation). Removes the undefined "Spark tier" dependency. Preserves the
  human-in-the-loop trust scaffold by giving concrete options.

### RW-3: `/vision/` -- rewrite internal-vocabulary H2s for search intent

- **Current H2/H3s:** "The Global Brain," "The Decision Ledger," "The Coordination Engine," "Bring Your Own Intelligence"
- **Suggested:** "Model routing: the right model for each task" (was: The Global Brain). "Decision memory that compounds across sessions" (was: The Decision Ledger). "Cross-department coordination" (was: The Coordination Engine). "Bring your own API keys" (was: Bring Your Own Intelligence).
- **Rationale:** Search-extractable; matches language founders actually
  type. Brand voice preserved -- still declarative, still precise. Internal
  poetic names can live in body copy as the narrative thread, not as
  headings.

### RW-4: `/vision/` lede compression

- **Current:** "Soleur is a Company-as-a-Service platform designed to collapse the friction between a startup idea and a billion-dollar outcome -- a future Anthropic's CEO assigns 70-80% probability."
- **Suggested:** "Soleur is the Company-as-a-Service platform for solo founders. One person. Every department. Billion-dollar outcomes -- a future Anthropic's CEO gives 70-80% probability."
- **Rationale:** Three short sentences instead of one long one (brand voice
  rule: "Keep sentences short and punchy"). Retains the dated, citeable
  Amodei stat. Drops "collapse the friction" (jargon-adjacent).

### RW-5: `/agents/` meta description

- **Current:** "AI agents for every business department -- engineering, marketing, legal, finance, operations, product, sales, and support. The full Soleur agent roster."
- **Suggested:** "65 AI agents that run every department of your company -- engineering, marketing, legal, finance, operations, product, sales, and support. Your expertise, amplified. Human-in-the-loop."
- **Rationale:** Leads with the concrete number (brand guide: "Use concrete
  numbers when available"). Adds the memory-first / trust scaffolding
  phrase. Still inside 160 chars.

### RW-6: `/getting-started/` intent split

- **Current:** Single page mixes "Reserve access" (waitlist) and "Run it yourself" (OSS install).
- **Suggested:** Keep one page, but make the split explicit: "Two ways to start" as an H2, then two parallel cards with their own H3s: "Run it yourself today (open source)" and "Reserve hosted access (waitlist)". Move the OSS install commands into the first card, the waitlist form into the second.
- **Rationale:** Each card is a self-contained unit; AI engines can cite
  either path without ambiguity. Preserves the primary CTA strength.

### RW-7: `/pricing/` replacement-cost footnote

- **Current:** "Based on US market median fully-loaded compensation, 2025-2026."
- **Suggested:** "Based on US market median fully-loaded compensation, 2025-2026. Sources: BLS Occupational Employment Statistics; levels.fyi; Glassdoor self-reported salaries."
- **Rationale:** Dated + sourced claims are the highest-signal AEO asset
  per the SAP framework. This single line turns the $95,000/mo claim from
  uncited to citeable.

### RW-8: `/community/` honest-reframe

- **Current:** "Soleur is an open-source Claude Code plugin with an active community across Discord, GitHub, and X."
- **Suggested:** "Soleur is an open-source Claude Code plugin with an early builder community across Discord, GitHub, and X. Small by design -- every contributor ships."
- **Rationale:** "Early builder community" is honest at current scale and
  actually stronger than "active" for founder audience (signals
  high-leverage peers). Brand voice preserved: declarative, no hedging.

### RW-9: `/skills/` -- rename "Uncategorized"

- **Current:** H2 `Uncategorized`
- **Suggested:** Either fold those items into one of the other four categories, or rename to `Utilities & Operations`.
- **Rationale:** "Uncategorized" reads like a staging leak; removes a
  professionalism hit at zero content cost.

### RW-10: Comparison cluster back-links

- **Pages:** `/blog/soleur-vs-cursor/`, `/blog/soleur-vs-notion-custom-agents/`, `/blog/soleur-vs-anthropic-cowork/`, `/blog/soleur-vs-polsia/`, `/blog/soleur-vs-paperclip/`
- **Suggested:** Add a common closing block on each comparison post: "Also read: [2 sibling comparisons] | Pillar: What is Company-as-a-Service?"
- **Rationale:** Cluster-pillar model requirement. Each cluster page must
  link to pillar + at least one sibling. Low implementation cost, high
  topical-authority lift.

### RW-11: `/changelog/` -- "This week in Soleur" lede

- **Current:** Page opens directly into v3.53.1.
- **Suggested:** Add an H2 at the top: "This week: [N] releases, [highlights]. Shipping on a daily cadence since launch." Refresh weekly.
- **Rationale:** Gives AI engines one quotable line summarizing release
  velocity. Converts a raw list into a narrative asset.

---

## Content-Architecture Recommendation (Pillar / Cluster)

Current state: pillar content exists but lives inside `/blog/`, and the
comparison cluster has no shared hub.

Recommended structure:

```
/company-as-a-service/                    [PILLAR -- promote blog post to top-level]
  ├─ /blog/soleur-vs-cursor/              [cluster -- link back to pillar + 1 sibling]
  ├─ /blog/soleur-vs-notion-custom-agents/
  ├─ /blog/soleur-vs-anthropic-cowork/
  ├─ /blog/soleur-vs-polsia/
  └─ /blog/soleur-vs-paperclip/

/ai-agents-for-solo-founders/             [PILLAR -- promote from /blog/]
  ├─ /blog/case-study-brand-guide-creation/
  ├─ /blog/case-study-business-validation/
  ├─ /blog/case-study-competitive-intelligence/
  ├─ /blog/case-study-legal-document-generation/
  └─ /blog/case-study-operations-management/

/agentic-engineering/                     [PILLAR -- new or from /skills/]
  ├─ /blog/why-most-agentic-tools-plateau/
  ├─ /blog/vibe-coding-vs-agentic-engineering/
  └─ /blog/your-ai-team-works-from-your-actual-codebase/
```

Searchable vs. shareable mix (current sample):

| Bucket | Count | Examples |
|---|---|---|
| Searchable (SEO-targeted) | 12 | all `soleur-vs-*`, case studies, `ai-agents-for-solo-founders`, `what-is-company-as-a-service` |
| Shareable (opinion/novelty) | 3 | `vibe-coding-vs-agentic-engineering`, `why-most-agentic-tools-plateau`, `credential-helper-isolation-sandboxed-environments` |

Mix is acceptable but shareable-side is light. For every two searchable
pieces, plan one shareable (founder POV, contrarian take, original data).

---

## Not Audited (Out of Scope for This Skill)

The following were observed but belong to the seo-aeo-analyst agent:

- JSON-LD validity (FAQPage, BlogPosting, Organization schemas all present in extracted HTML; schema validation not performed here).
- `llms.txt` or `robots.txt` presence.
- 403 response to default WebFetch user-agent -- crawler allow-list concern.
- Author schema / E-E-A-T structured data.
- Sitemap lastmod cadence (all top-level pages updated same day -- verify this is intentional).

---

## Next Actions

1. **Critical fixes (C1-C5)** are narrow-scope edits, applicable in a single PR. Recommend `/soleur:growth fix --apply` targeting homepage, `/vision/`, `/agents/` meta, and homepage FAQ rewrite.
2. **Pillar promotion (C3)** requires a routing decision: either a 301 from `/blog/what-is-company-as-a-service/` to a new `/company-as-a-service/` URL, or canonical-tag promotion keeping the blog URL. Treat as its own ticket with seo-aeo-analyst consulted on the redirect.
3. **Cluster back-linking (RW-10)** can be scripted -- add a shared include at the bottom of every `soleur-vs-*` post.
4. **Numeric drift (C1)** requires a canonical-source decision (pick: 63 / 65 / 60+) then a repo-wide find-replace across `apps/web-platform/src/content/*.md` and the brand guide.
