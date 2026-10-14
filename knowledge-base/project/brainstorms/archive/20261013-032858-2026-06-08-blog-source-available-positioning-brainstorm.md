---
date: 2026-06-08
topic: blog-source-available-positioning
issue: 5043
status: decided
lane: single-domain
brand_survival_threshold: brand-positioning-consistency
---

# Brainstorm: Soleur-subject "open source" → "source-available" in dated blog bodies (#5043)

## What We're Building

A scoped copy sweep across the ~11 dated blog comparison posts in `plugins/soleur/docs/blog/*.md`,
rewriting **Soleur-subject** "open source" / "open-source" positioning to **"source-available
(BSL 1.1)"**, plus an extension to the `marketing-content-drift.test.ts` blog guard (Test 2c) to
ban Soleur-subject "open source" phrasings going forward.

Deferred from #5038 per CPO sign-off (APPROVE-WITH-CONDITIONS). The license-correction PR (#5036,
merged 2026-06-08) already swept every explicit Apache claim and every Soleur-subject "open source"
claim on **evergreen** pages to "source-available (BSL 1.1)", and fixed explicit Apache claims in
blog bodies. It did NOT rewrite the generic **"open source" positioning in the body** of the dated
blog comparison posts — that was held as a CMO positioning call. This brainstorm resolves it.

## Why This Approach

**Decision: Sweep → source-available (Soleur-subject only).** Selected by the operator (brand owner)
over "tables + JSON-LD only", "qualify on first use", and "leave as period-accurate".

Rationale:

- **The "period-accurate" defense does not hold.** Soleur has been BSL 1.1 the entire time these
  posts were authored (Mar–May 2026). "Open source" was never accurate — it is *old*, not
  *period-accurate*. You cannot defend a claim that was false on its publish date as historical
  framing.
- **The brand asset is auditability, not the label.** The brand guide treats "open-source
  credibility" as a positioning asset, but the *substantive* claim in the prose is transparency
  ("every agent prompt, every skill, every knowledge-base schema is readable — you can read every
  line"). That claim is fully TRUE under BSL 1.1: the source IS available and auditable.
  "Source-available" preserves the credibility claim honestly; it is the defensible version of the
  same asset.
- **Highest risk is in structured/decision-grade surfaces.** Comparison-table rows
  (`Open source: Yes` for Soleur) are buying-decision artifacts, and JSON-LD blocks are machine-read
  by search/AI engines (AEO surface). A false "open source" claim there is graded and propagated,
  not just narrative.
- **Consistency with swept evergreen pages.** A reader clicking blog → homepage currently sees
  "open source" (blog) contradict "source-available (BSL 1.1)" (homepage). The inconsistency
  undermines trust more than either choice alone.

## Key Decisions

| Decision | Choice |
|----------|--------|
| Positioning | Soleur-subject "open source" → "source-available (BSL 1.1)" |
| Scope discriminator | **Soleur-subject only**. Competitor/ecosystem references stay verbatim. |
| Surfaces covered | Comparison-table rows, narrative prose, AND JSON-LD structured data |
| Test guard | Extend `marketing-content-drift.test.ts` Test 2c to ban Soleur-subject "open source" in blog |
| Out of scope | Generic ecosystem "open source" (CrewAI MIT, Paperclip MIT, Spec Kit, GitHub spec-kit, Cowork's own free/open-source tier) — these are accurate |

### Critical discriminator (NOT a blanket find-replace)

The edit MUST distinguish the *subject* of each "open source" mention:

- **Change** when the subject is Soleur ("Soleur is open-source", "Live (open source)" in Soleur's
  comparison column, "open-source transparency" describing Soleur, the Soleur side of JSON-LD).
- **Keep verbatim** when the subject is a competitor or the ecosystem:
  - CrewAI ("open-source Python framework", "open-source framework (MIT license)", the CrewAI
    comparison-table column).
  - Paperclip ("open-source orchestration platform", MIT license, the Paperclip table column).
  - Cowork's own "Free (open source)" / "Live (open source)" tier cells (competitor column).
  - Spec Kit / GitHub spec-kit / OpenSpec references in `why-most-agentic-tools-plateau.md`.

The trickiest post is `2026-03-31-soleur-vs-paperclip.md`: its `seoTitle`
("Open-Source AI Company Platforms Compared"), `description` ("both open-source AI company
platforms"), `tags: [open-source]`, and Q&A prose lump Soleur and Paperclip together as "both
open-source". Those must be reworded to *separate* the two — Paperclip stays open-source (MIT),
Soleur becomes source-available (BSL 1.1) — rather than blanket-replaced.

## Affected files (Soleur-subject hits — verified via grep on main)

1. `2026-03-16-soleur-vs-anthropic-cowork.md` — L25, L88 (Soleur col), L112, L135 (keep Cowork's "open source" cells)
2. `2026-03-17-soleur-vs-notion-custom-agents.md` — L24, L91, L111, L129
3. `2026-03-19-soleur-vs-cursor.md` — L72, L106, L142 (JSON-LD)
4. `2026-03-26-soleur-vs-polsia.md` — L80, L122, L124, L157, L160 (JSON-LD)
5. `2026-03-29-your-ai-team-works-from-your-actual-codebase.md` — L70
6. `2026-03-31-soleur-vs-paperclip.md` — seoTitle, description, tags, L49, L84 (Soleur col), L129, L133, L174, L177 (keep all Paperclip/MIT refs)
7. `2026-04-21-soleur-vs-devin.md` — L72, L74, L117 (Soleur col)
8. `2026-04-23-agents-that-use-apis-not-browsers.md` — description, L14, L67
9. `2026-05-05-soleur-vs-tanka.md` — L82, L115 (Soleur col)
10. `2026-05-07-soleur-vs-crewai.md` — L76, L108 (Soleur col), L127, L163 (JSON-LD) (keep all CrewAI/MIT refs)
11. `2026-05-12-company-as-a-service-platform.md` — L66

Plus: `plugins/soleur/test/marketing-content-drift.test.ts` (extend Test 2c + update the #5043
deferral comments at L160-161 / L190 to "resolved").

## Open Questions

- **Phrasing of "source-available" in table headers.** Options: `Source-available (BSL 1.1)` (full,
  matches evergreen) vs. `Source-available` (compact, fits narrow table columns). Recommend full
  form in prose/JSON-LD, compact form in table rows where width matters — implementer's call at
  edit time, both honest.
- **`tags: [open-source]` frontmatter on the paperclip post.** Drives the blog tag taxonomy. Keep
  (the post still discusses open-source platforms generically) vs. drop. Recommend keep — the tag is
  topical, not a Soleur self-claim.

## Domain Assessments

**Assessed:** Marketing, Legal

### Marketing

**Summary:** Honest "source-available" preserves the real positioning asset (auditability/
transparency), which is true under BSL; the label "open source" was never the asset. Fixing
structured surfaces (tables, JSON-LD) matters most for AEO and buying decisions, and resolves the
blog↔evergreen inconsistency that actively erodes trust.

### Legal

**Summary:** BSL 1.1 is not OSI-approved; a Soleur-subject "open source" claim is a
misrepresentation (the same basis on which #5038 swept evergreen pages). Low individual reliance
(no license grant a visitor forks against — those were the Apache claims, already fixed in #5036),
but comparison-table feature claims are factual claims and should be corrected for accuracy and
internal consistency.
