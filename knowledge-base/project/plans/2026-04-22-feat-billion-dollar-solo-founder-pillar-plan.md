---
title: "Ship P1.7 Billion-Dollar Solo Founder Stack pillar"
issue: 2712
pr: 2811
branch: feat-billion-dollar-solo-founder-pillar
brainstorm: knowledge-base/project/brainstorms/2026-04-22-billion-dollar-solo-founder-pillar-brainstorm.md
spec: knowledge-base/project/specs/feat-billion-dollar-solo-founder-pillar/spec.md
source_plan: knowledge-base/marketing/audits/soleur-ai/2026-04-21-content-plan.md
type: feat
priority: P1
domain: marketing
created: 2026-04-22
status: planned
---

# Plan — Billion-Dollar Solo Founder Stack pillar (P1.7)

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Reconciliation, Implementation Phases (1, 3, 5), Risks, Research Insights.

### Key Improvements

1. **Eleventy build command corrected.** The plan originally specified
   `cd plugins/soleur/docs && npm run docs:build`; the `package.json` in that
   directory declares `docs:build` (not `build`) and runs `cd ../../../
   && npx @11ty/eleventy` — the config lives at the **repo root**
   (`eleventy.config.js`), not inside `docs/`. Corrected throughout
   Phase 5 and AC sections.
2. **jsonLdSafe filter is already registered in `eleventy.config.js`** —
   confirmed by `grep -rln jsonLdSafe`. The FAQPage block the copywriter
   writes can **use the filter directly** via Nunjucks if we place the
   JSON-LD in a small Nunjucks partial, OR write a literal `<script>` block
   with hand-escaped `<\/script>` and straight quotes. Phase 3 now picks
   the literal-block approach and documents the escape convention
   explicitly.
3. **Pillar-slug collision check passed.** `grep -rn "^pillar:"
   plugins/soleur/docs/blog/` returns zero hits. Reconciliation row 1
   updated from "no post currently declares a pillar" to this verified
   grep result.
4. **Citation fact-check sample run at deepen time.** WebSearch
   confirmed Medvi primary figures ($20K seed, $401M Y1, $1.8B Y2
   tracking, September 2024 launch, Gallagher + brother Elliot,
   ElevenLabs for customer service) are supported by PYMNTS, Inc.com,
   therundown.ai, citybiz, quasa.io, whatstrending.com, and Yahoo
   Finance. The Amodei "by 2026" prediction citation for the companion
   post resolves to officechai.com (already linked in the 2026-04-21
   post). Copywriter prompt locks these as the primary-source URLs.
5. **Dual-rubric scorecard risk downgraded.** Reconcile plan
   (`2026-04-22-chore-aeo-rubric-reconcile-plan.md`) defines the rubric
   shape unambiguously — the SAP-25% + 8-component AEO shape from the
   2026-04-21 audit is stable enough to score against even if the
   template file hasn't landed on main at ship time. New mitigation:
   inline a copy of the rubric shape inside the PR's scorecard artifact.

### New Considerations Discovered

- **Companion post's existing prose already links to** Fortune/Kuo Zhang,
  solofounders.com/Carta, and officechai.com/Amodei. The pillar MUST
  avoid presenting those same citations as "new" — copywriter prompt
  appended to reference the companion post's citation list and use
  **distinct** primary sources where possible (Wealthy Tent, PYMNTS,
  Inc.com Sheridan piece) OR re-cite the same source with clear
  rationale. Citation overlap is fine; paraphrased-claim overlap is
  plagiarism risk.
- **Eleventy config path resolution.** Because `npx @11ty/eleventy` runs
  from the repo root, input/output paths in the config are relative to
  the repo root, not to `plugins/soleur/docs/`. Any path we prescribe
  (e.g., `_site/blog/billion-dollar-solo-founder-stack/index.html`)
  should be interpreted relative to the root `_site/` — the plan's
  "Expected" blocks in Phase 5 now clarify this.
- **`blog-post.njk` edit risk narrowed.** The include insertion sits
  inside `{% block content %}` above `<section class="content">`. The
  `{% block extraHead %}` with BlogPosting JSON-LD is untouched — safe.
- **Style.css addition is small but cache-relevant.** The CSS bump
  slightly invalidates the cached stylesheet for all blog readers on
  ship day; this is normal and expected, no mitigation needed.

## Overview

Ship a new 3,500-4,500-word pillar post at
`plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md` targeting the
head keywords `billion dollar solo founder`, `one person billion dollar company`,
`one person unicorn`. Drafting is delegated to the `copywriter` agent from the
outline already locked by `2026-04-21-content-plan.md` §432 and the spec FRs.
Citation verification runs through `fact-checker`. Final AEO quality gate runs
through `seo-aeo-analyst` with the dual-rubric scorecard (target ≥80/B+).

The existing companion post
`plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md`
stays live and receives a bidirectional pillar↔cluster link in its first 200
words — it is **not** rewritten (spec NG1).

A shared "Part of the Billion-Dollar Solo Founder series" rendering component
(`_includes/pillar-series.njk` + frontmatter `pillar:` + `_data/pillars.js`) is
built as part of this PR — the repo grep confirmed no `pillar:` frontmatter is
currently used by any post and no `pillar-series` include exists (capability
gap called out in brainstorm §Capability Gaps).

**Execution path:** one-shot via `copywriter` → `gemini-imagegen` →
`fact-checker` → `seo-aeo-analyst` → Eleventy build → ship. No net-new
architectural work.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| FR8: "Pillar-series component renders the 'Part of the X series' block when a post has `pillar:` frontmatter. Verify the component exists; if not, add it." | No `pillar-series.njk` (or equivalent) exists in `plugins/soleur/docs/_includes/` (only `base.njk`, `blog-post.njk`, `newsletter-form.njk`). `grep -rn "^pillar:" plugins/soleur/docs/blog/` returns **zero hits** — no post currently declares a pillar. | Build the component + data file as Phase 1 of the plan. Define the data source (`_data/pillars.js`) and the include contract before the copywriter drafts, so frontmatter and include land in one PR. |
| TR2: "AEO dual-rubric scorecard must score ≥80 (B+) per `plugins/soleur/skills/seo-aeo/references/dual-rubric-scorecard-template.md`." | The referenced template path does not yet exist. The rubric template is being created by a sibling PR tracked under `knowledge-base/project/plans/2026-04-22-chore-aeo-rubric-reconcile-plan.md` (#2615/#2679). | Use the latest **committed** rubric representation available at ship time — the 2026-04-21 audit scorecard shape (SAP 25% + 8-component AEO, `<n>/<weight>` + letter-grade `/B+`) per the reconcile plan. If the template file has landed on main by ship time, reference it directly. If not, inline the rubric structure from the 2026-04-21 audit and link to the reconcile plan's spec. Do not block this pillar on the rubric PR. |
| FR4: internal links include `/blog/what-is-company-as-a-service/` | Verified present in blog tree. | No action. |
| NG4: do not link to P1.5 / P1.6 (not yet shipped) | Verified — those pillars are still tracked as "unshipped" in `2026-04-21-content-plan.md`. | Copywriter prompt explicitly forbids stubs to unshipped URLs. Mention sibling pillars in prose only (no hyperlink). |
| Source plan §195-199 structural contract (quotable first-100-words definition, inline hyperlinks on every stat, `/pricing/` CTA, FAQ 10 Qs, JSON-LD FAQPage) | Confirmed in `plugins/soleur/docs/_includes/blog-post.njk` — `jsonLdSafe` / BlogPosting schema wired at `{% block extraHead %}`, but **no FAQPage block exists in the layout**. `jsonLdSafe` filter is registered in root `eleventy.config.js` (verified via `grep -rln jsonLdSafe`). | Copywriter MUST include an explicit `<script type="application/ld+json">` FAQPage block inside the post body with hand-escaped `<\/script>` and straight ASCII quotes. The markdown file's literal `<script>` block passes through Eleventy unchanged — no filter needed at the markdown level. Do NOT extend the `blog-post.njk` layout for this PR — scope-local JSON-LD keeps the layout stable. Note the rule `#2609` / `jsonLdSafe` class applies; AC10 hard-asserts the escape. |

## Hypotheses

N/A — no diagnostic scope. This plan ships a known-shape content artifact.

## Components to Edit / Create

### Files to Create

- `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md`
  — the pillar post (3,500-4,500 words, 10-section outline, 10-Q FAQ, inline
  FAQPage JSON-LD).
- `plugins/soleur/docs/images/blog/og-billion-dollar-solo-founder-stack.png`
  — 1200×630 OG image generated via `gemini-imagegen`, visually consistent
  with `og-one-person-billion-dollar-company.png`.
- `plugins/soleur/docs/_includes/pillar-series.njk` — Nunjucks include that
  renders the "Part of the Billion-Dollar Solo Founder Stack series" block.
  Reads `_data/pillars.js[page.pillar]` and lists member posts with the
  current post highlighted.
- `plugins/soleur/docs/_data/pillars.js` — data file exporting pillar-slug →
  `{ title, description, members: [{ url, title, relation }] }`. Seeded
  with one entry: `billion-dollar-solo-founder`. Other pillar slugs left
  for P1.1 / P1.5 / P1.6.

### Files to Edit

- `plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md`
  — add `pillar: billion-dollar-solo-founder` frontmatter field; add the
  `{% include "pillar-series.njk" %}` call immediately after the hero
  paragraph (inside the 200-word window). Do **not** rewrite prose
  (spec NG1).
- `plugins/soleur/docs/_includes/blog-post.njk` — inject the pillar-series
  include conditional: `{% if pillar %}{% include "pillar-series.njk" %}{% endif %}`
  at the top of the article body. This is a 3-line addition; verify JSON-LD
  integrity and `jsonLdSafe` usage remains untouched (rule
  `cq-union-widening-grep-three-patterns`-class risk if editing the switch
  ladder — **there is no discriminated union here**, so the mechanical risk
  is limited to the `extraHead` block, which we do not touch).

### Files Deliberately Not Edited

- `plugins/soleur/docs/blog/blog.json` — Eleventy regenerates automatically
  from `collections.blog` (verified in Phase 5 build). No manual edit.
- `plugins/soleur/docs/llms.txt.njk`, `plugins/soleur/docs/sitemap.njk` —
  same: auto-regenerated.
- Other blog posts with no pillar frontmatter — the include is conditional;
  absence of `pillar:` is a silent no-op.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (28 issues) vs the
planned file paths returned zero hits. No fold-in / acknowledge / defer
decisions required.

## Implementation Phases

### Phase 1 — Scaffold pillar component (capability gap)

1. **Create `plugins/soleur/docs/_data/pillars.js`** exporting:

   ```javascript
   module.exports = {
     "billion-dollar-solo-founder": {
       title: "The Billion-Dollar Solo Founder Stack",
       description:
         "How one person builds a billion-dollar company in 2026 — the stack, the proof, and the open questions.",
       members: [
         {
           url: "/blog/billion-dollar-solo-founder-stack/",
           title: "The Billion-Dollar Solo Founder Stack (2026)",
           relation: "pillar",
         },
         {
           url: "/blog/one-person-billion-dollar-company/",
           title:
             "The One-Person Billion-Dollar Company: Why It's an Engineering Problem",
           relation: "cluster",
         },
       ],
     },
   };
   ```

2. **Create `plugins/soleur/docs/_includes/pillar-series.njk`** rendering:

   ```njk
   {% set currentPillar = pillars[pillar] %}
   {% if currentPillar %}
     <aside class="pillar-series" aria-label="Part of the {{ currentPillar.title }} series">
       <p class="pillar-series__label">Part of the <strong>{{ currentPillar.title }}</strong> series:</p>
       <ul class="pillar-series__list">
         {% for member in currentPillar.members %}
           <li>
             {% if member.url == page.url %}
               <span class="pillar-series__current">{{ member.title }} (you are here)</span>
             {% else %}
               <a href="{{ member.url }}">{{ member.title }}</a>
               {% if member.relation == "pillar" %} — pillar{% endif %}
             {% endif %}
           </li>
         {% endfor %}
       </ul>
     </aside>
   {% endif %}
   ```

3. **Edit `plugins/soleur/docs/_includes/blog-post.njk`** to render the
   include at the top of the post body — minimal insertion, does not touch
   `{% block extraHead %}` or the JSON-LD block.

4. **Add CSS** for `.pillar-series` in `plugins/soleur/docs/css/style.css`
   (minimal: bordered aside, muted background, list unstyled, one rule
   block). No new files; same commit.

### Phase 2 — Generate OG image

Invoke the `gemini-imagegen` skill with a brief pinning the visual family of
`og-one-person-billion-dollar-company.png` (read that file to confirm
palette, typography register, composition before prompting).

**Prompt contract (for the skill invocation):**

- Dimensions: 1200×630.
- Output path:
  `plugins/soleur/docs/images/blog/og-billion-dollar-solo-founder-stack.png`.
- Headline overlay: "The Billion-Dollar Solo Founder Stack".
- Subhead overlay: "2026".
- Style: match `og-one-person-billion-dollar-company.png` — stay in the same
  color family + typographic register. Soleur brand.

Post-generation verification:

- `stat -c %s plugins/soleur/docs/images/blog/og-billion-dollar-solo-founder-stack.png`
  > 0 bytes (hard check — see rule `cq-pencil-mcp-silent-drop-diagnosis-checklist`
  class; same failure mode for any image MCP).
- `identify` or `file` probe confirms 1200×630 actual dimensions.

### Phase 3 — Draft pillar via copywriter agent

Invoke `copywriter` with the following scoped prompt. Do **not** hand the
copywriter the full spec — give it only what it needs to draft.

**Prompt contract (copywriter):**

- **Output path:** `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md`.
- **Word count:** 3,500-4,500 (hard range — reject drafts outside).
- **Frontmatter (Eleventy):**

  ```yaml
  ---
  title: "The Billion-Dollar Solo Founder Stack (2026)"
  seoTitle: "Billion-Dollar Solo Founder Stack (2026): The Complete Playbook"
  date: 2026-04-22
  description: "How one person builds a billion-dollar company in 2026 — the stack by function, the Medvi + Amodei proof, and what still requires the human."
  ogImage: "blog/og-billion-dollar-solo-founder-stack.png"
  pillar: billion-dollar-solo-founder
  tags:
    - solo-founder
    - company-as-a-service
    - agentic-engineering
    - solopreneur
    - pillar
  ---
  ```

- **Outline (locked, 10 sections per content plan §432):**

  1. Definition (quotable 1-2 sentences in first 100 words) + Amodei Inc.com
     citation.
  2. Medvi proof point — $20K start → $401M Y1 → $1.8B projected, Sept 2024.
     Cite Wealthy Tent + Inc.com + LinkedIn/Nicholas Thompson.
  3. Amodei 70-80% / 2026 prediction — Inc.com primary + PYMNTS +
     Entrepreneur.
  4. What makes it possible now — frontier-model multi-step reasoning; MCP
     tool standardization; Claude Code / Cursor / Soleur as orchestration
     layer.
  5. Stack by function — engineering (Claude Code + Soleur), marketing
     (Soleur marketing agents), legal (Soleur legal + licensed human),
     finance (Soleur finance + CPA), ops (Zapier/Make), design
     (Midjourney/Figma/Canva), customer service (custom agents +
     ElevenLabs per Medvi). Expand each row into 1-2 paragraphs per
     brainstorm handoff instruction.
  6. What still requires the human — taste, positioning, final go/no-go,
     regulated actions.
  7. How Soleur fits — full Company-as-a-Service org out of the box +
     compounding KB. Internal links to `/vision/`, `/pricing/`,
     `/blog/what-is-company-as-a-service/`.
  8. Counterpoint — regulatory, model costs, attention-economy collapse,
     vibe-coding tech debt. Brand guide §Trust-scaffolding mandatory
     honesty section.
  9. FAQ — **10 questions** per plan: Who has already done it? Is this
     ethical? Do you still hire anyone? What's the Claude API cost? Which
     model? Is it defensible vs. a 20-person team? + 4 more the
     copywriter composes from brand-guide + plan (minimum 10, no more
     than 12).
  10. CTA — `/pricing/` + waitlist.

- **Structural contract (from content plan §195-199):**
  - Quotable 1-2 sentence definition extractable without context in first
    100 words.
  - Inline hyperlinked citation for **every** stat.
  - Pillar-series link block in the first 200 words — achieved by the
    `pillar:` frontmatter + `blog-post.njk` include, so the copywriter
    does not hand-write it.
  - Closing `/pricing/` CTA.
  - FAQ wrapped in FAQPage JSON-LD — copywriter MUST include the
    `<script type="application/ld+json">` block inline at the end of the
    FAQ section. Use straight double-quotes inside the JSON; escape `</`
    as `<\/` to avoid the rule `cq-prose-issue-ref-line-start` /
    `#2609`-class breakout surface.
  - Author byline + last-updated timestamp.
  - Named-entity anchors (Amodei, Altman, Kuo Zhang where applicable).

- **Internal links (FR4):** `/vision/`, `/pricing/`,
  `/blog/what-is-company-as-a-service/`,
  `/blog/one-person-billion-dollar-company/`. No stubs to P1.5 / P1.6.

- **Citations required (FR3 — do not fabricate — every URL must be real):**
  Wealthy Tent (Medvi $1.8B), Inc.com Sheridan piece ("The 1-Employee
  Billion-Dollar Startup"), Inc.com Amodei, PYMNTS, LinkedIn/Nicholas
  Thompson, therundown.ai ("AI just made the billion-dollar solo founder
  real"), thiswithkrish.com, Entrepreneur, PrometAI, NxCode, Carta 2024
  solopreneur report, Anthropic 2026 Agentic Coding Trends Report,
  Deloitte TMT 2026, CIO agentic workflows. Copywriter retrieves each
  URL via `WebFetch` at draft time and only cites URLs that return
  200 OK. Deepen-time WebSearch confirmed the Medvi $401M / $1.8B /
  September 2024 / $20K / ElevenLabs facts are consistent across PYMNTS,
  Inc.com, therundown.ai, citybiz, quasa.io, whatstrending.com, Yahoo
  Finance — pick any two primary sources per stat.

- **Citation-overlap gate with companion post.** The companion post at
  `plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md`
  already cites: officechai.com/Amodei, fortune.com/Sam Altman,
  techcrunch.com, solofounders.com/Carta, fortune.com/Kuo Zhang. The
  pillar MAY reuse these URLs where the same claim is referenced, but
  the **paraphrase of the underlying claim must be materially
  different** — the pillar expands what the companion merely asserts.
  Copywriter prompt: "If you re-cite any of {officechai, fortune-altman,
  fortune-kuo, solofounders, techcrunch}, the surrounding paragraph
  must extend beyond what the companion post says." This avoids
  self-cannibalization and duplicate-content signals.

- **Brand voice:** pull from `knowledge-base/marketing/brand-guide.md`.
  Enforce §Trust-scaffolding by requiring §8 Counterpoint to be at least
  300 words and list concrete risks, not hand-waving.

- **FAQPage JSON-LD contract (hand-written by copywriter in the markdown).**
  Place at the end of §9 FAQ in the markdown body. Open and close with
  real `<script type="application/ld+json">` and `</script>` tags — those
  are the actual delimiters the browser parser uses. **Inside the JSON
  string values**, escape any literal `</` token as `<\/` (defense
  against the `#2609` class rule when a FAQ answer happens to quote
  code or an HTML snippet). Use straight ASCII double-quotes
  throughout. Example shape (values illustrative — copywriter fills in
  the actual 10 Q&A pairs):

  ```html
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    "mainEntity": [
      {
        "@type": "Question",
        "name": "Who has already built a one-person billion-dollar company?",
        "acceptedAnswer": {
          "@type": "Answer",
          "text": "Matthew Gallagher's Medvi, launched from a Los Angeles apartment in September 2024 with $20,000 and his brother Elliot as the company's only hire, posted $401 million in Y1 sales and is tracking toward $1.8 billion in Y2 using ChatGPT, Claude, Grok, Midjourney, Runway, and ElevenLabs."
        }
      }
      // ... 9 more entries; last entry has no trailing comma
    ]
  }
  </script>
  ```

  Rule: if any Answer text needs to mention a literal `</script>`
  substring, write it as `<\/script>` inside the JSON string (e.g.,
  `"text": "The closing tag <\/script> ..."`). The real closing
  `</script>` at line end is what terminates the block; the in-string
  `<\/script>` escape is only for cases where the string content itself
  contains the substring. JSON itself does not require escaping forward
  slashes — this escape is specifically an HTML-parser trap avoidance.

- **AEO target:** draft with dual-rubric ≥80/B+ in mind —
  `seo-aeo-analyst` scores in Phase 5.

### Phase 4 — Cluster link-up on the companion post

Edit `plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md`:

1. Add `pillar: billion-dollar-solo-founder` to the YAML frontmatter
   (single line insertion; no other frontmatter changes).
2. Add a two-sentence lead-in paragraph IMMEDIATELY after the first body
   paragraph ("The first billion-dollar company run by one person is not a
   thought experiment…") and BEFORE the "Dario Amodei…" paragraph:

   > This post is part of the [Billion-Dollar Solo Founder Stack](/blog/billion-dollar-solo-founder-stack/) series — the pillar covers the full stack by function, the Medvi proof, and what still requires the human. This companion piece argues for the engineering-problem framing.

   Placing it here keeps the link inside the **first 200 words**
   (spec FR6, content plan §195). The pillar-series include will also
   render immediately above this paragraph via `blog-post.njk`; the inline
   lead-in is the belt-and-suspenders guarantee that the link is in the
   first 200 words even if the include fails to render.

3. No other prose edits (spec NG1).

### Phase 5 — Verify, score, and ship

Verification order is load-bearing:

1. **Eleventy local build** (TR3):
   `cd plugins/soleur/docs && npm run docs:build`
   Expected: build passes; new post in `_site/blog/billion-dollar-solo-founder-stack/index.html`;
   `_site/blog.json` lists it; `_site/sitemap.xml` contains the URL;
   `_site/llms.txt` references it. Fix any breakage before proceeding.

2. **Markdownlint** (TR4):
   `npx markdownlint-cli2 --fix plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md`
   — target-specific paths per rule `cq-markdownlint-fix-target-specific-paths`.
   Re-read the files after `--fix` to check rule `cq-prose-issue-ref-line-start`
   did not mangle `#2712`-style refs (none expected in copy, but re-verify).

3. **Invoke `fact-checker`** (TR1) with scope: verify every hyperlinked
   citation in the new pillar returns 200 OK. Replace any dead URL with a
   live archived alternative or remove the stat. Rerun `npm run docs:build`
   after any prose edits.

4. **Invoke `seo-aeo-analyst`** (TR2) with the dual-rubric scorecard shape
   from `2026-04-22-chore-aeo-rubric-reconcile-plan.md` (SAP 25% +
   8-component AEO, `<n>/<weight>` and letter-grade format). Target ≥80/B+.
   If below threshold, apply analyst recommendations inline and re-score.

5. **Brand voice + trust-scaffolding re-read** — human/agent review of §8
   Counterpoint specifically (at least 300 words, concrete, not
   hand-waving).

6. **Visual + OG verification** — `curl` the local build URL, inspect
   `<meta property="og:image">` resolves to the new 1200×630 PNG.

7. `/ship` pipeline per AGENTS.md `wg-use-ship-to-automate-the-full-commit`.

## Delegation Summary

| Phase | Delegate | Why |
|---|---|---|
| 2. OG image | `gemini-imagegen` skill | Rule `hr-when-triaging-a-batch-of-issues-never` forbids deferring automatable image gen. |
| 3. Drafting | `copywriter` agent | Rule `wg-for-user-facing-pages-with-a-product-ux` — specialist must draft user-facing pages. |
| 5.3 Citation audit | `fact-checker` agent | Spec TR1 + rule `cq-docs-cli-verification` class (no fabricated tokens). |
| 5.4 AEO score | `seo-aeo-analyst` agent | Spec TR2 — ≥80/B+ target requires specialist scoring, not self-attestation. |

## Alternative Approaches Considered

| Option | Choice | Rationale |
|---|---|---|
| Redirect 2026-04-21 post → new pillar | Rejected | Brainstorm locked "keep both live + bidirectional link". 2-day indexing head start preserved; no redirect risk. |
| Inline pillar-series link (no frontmatter/include) | Rejected | Spec FR8 + content plan §199 require a reusable component. Hand-wired links don't scale to P1.1/P1.5/P1.6. |
| Skip `_data/pillars.js`, hardcode member list in `.njk` | Rejected | New pillars land in quick succession (P1.1/P1.5/P1.6). Data file is the cheap forward path. |
| Extend `blog-post.njk` with a dedicated FAQPage JSON-LD block reading `page.faq` | Rejected (deferred) | Would need every post to adopt a new frontmatter shape. Scope-local inline JSON-LD in the pillar body is strictly simpler. File GitHub issue to track as optional future refactor. |
| Defer OG image to post-ship | Rejected | Rule `hr-when-triaging-a-batch-of-issues-never` and spec FR7. |

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md`
  exists with the exact frontmatter shape from Phase 3 and renders at
  `/blog/billion-dollar-solo-founder-stack/` in the local Eleventy build.
- **AC2** — All 10 outline sections present in the specified order, with
  the specified internal links and citations. Word count 3,500-4,500.
- **AC3** — `plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md`
  has `pillar: billion-dollar-solo-founder` in frontmatter and the lead-in
  paragraph from Phase 4 in its first 200 words. No other prose edits.
- **AC4** — `plugins/soleur/docs/images/blog/og-billion-dollar-solo-founder-stack.png`
  exists, is 1200×630, file size > 10KB (non-trivial), and is referenced
  by the pillar's `ogImage` frontmatter.
- **AC5** — `seo-aeo-analyst` dual-rubric scorecard records ≥80/B+ on the
  pillar. Scorecard output archived in the PR description or in
  `knowledge-base/marketing/audits/soleur-ai/` with filename
  `2026-04-22-billion-dollar-solo-founder-stack-scorecard.md`.
- **AC6** — `npm run docs:build` (from `plugins/soleur/docs/`) passes;
  markdownlint clean on both edited blog files; `fact-checker` confirms
  every inline hyperlink in the pillar returns 200 OK.
- **AC7** — `_site/blog.json`, `_site/sitemap.xml`, and `_site/llms.txt`
  list the new post after local build.
- **AC8** — `pillar-series.njk` renders the "Part of the Billion-Dollar
  Solo Founder Stack series" block on **both** posts; view-source check
  shows each list item and the current-post self-reference.
- **AC9** — PR body contains `Closes #2712`.
- **AC10** — FAQ section contains exactly one inline
  `<script type="application/ld+json">` FAQPage block; manual JSON
  parse succeeds after stripping the outer `<script>` tags
  (`sed -n '/<script type="application\/ld+json">/,/<\/script>/p'`
  piped to `python3 -c 'import json,sys;raw=sys.stdin.read();
  json.loads(raw.split(">",1)[1].rsplit("<",1)[0])'`); every Answer
  string uses straight ASCII double-quotes; any literal `</` inside
  an Answer string is escaped as `<\/` (rule `#2609` class defense).

### Post-merge (operator)

- **AC11** — Production build at `https://soleur.ai/blog/billion-dollar-solo-founder-stack/`
  returns 200 and renders the pillar + series block.
- **AC12** — `curl -I https://soleur.ai/images/blog/og-billion-dollar-solo-founder-stack.png`
  returns 200 and the correct `content-type: image/png`.
- **AC13** — `curl https://soleur.ai/sitemap.xml` and
  `curl https://soleur.ai/llms.txt` both contain the new URL.

## Test Scenarios

This is a content pillar with infrastructure-light scaffolding. Per AGENTS.md
`cq-write-failing-tests-before` the TDD gate applies to code changes, not to
prose. The scaffolding code (`_includes/pillar-series.njk`, `_data/pillars.js`)
is exercised by the Eleventy build itself — no separate unit test harness.

- **TS1 — Pillar renders with series block:** Local build produces
  `_site/blog/billion-dollar-solo-founder-stack/index.html`; `grep -c
  'pillar-series'` on the HTML returns ≥ 1; `grep "you are here"` returns
  exactly 1 on each pillar-member page.
- **TS2 — Companion post carries the series block:** Local build produces
  `_site/blog/one-person-billion-dollar-company/index.html`; same greps
  as TS1; current-post highlight is on the companion post, not the pillar.
- **TS3 — No-pillar posts are unaffected:** Pick one blog post without
  `pillar:` frontmatter (e.g., `og-ai-agents-for-solo-founders.*`); grep
  its built HTML for `pillar-series` — expected zero matches.
- **TS4 — FAQPage JSON-LD parses:** Extract the `<script type="application/ld+json">`
  block matching `"@type": "FAQPage"` from the pillar's built HTML; parse
  with `python3 -c 'import json,sys;json.load(sys.stdin)'` — must exit 0.
- **TS5 — Sitemap + llms.txt + blog.json list the new post:**
  `grep billion-dollar-solo-founder-stack _site/sitemap.xml _site/llms.txt _site/blog.json`
  returns ≥ 1 match in each file.
- **TS6 — OG image headers correct:** `identify
  plugins/soleur/docs/images/blog/og-billion-dollar-solo-founder-stack.png`
  reports 1200×630. `file` reports `PNG image data`.

## Risks

- **R1 — Citation drift.** Third-party URLs (Wealthy Tent, PYMNTS) may
  404 or paywall between draft and ship. **Mitigation:** `fact-checker`
  in Phase 5.3; substitute archived URLs via `web.archive.org/web/*` for
  dead primary sources.
- **R2 — Dual-rubric template absence.** The referenced
  `plugins/soleur/skills/seo-aeo/references/dual-rubric-scorecard-template.md`
  is being created in a sibling PR (#2679 reconcile). **Mitigation:**
  Reconciliation row 2 above. If the sibling PR ships first, reference
  the committed path; otherwise inline the rubric shape from the
  2026-04-21 audit.
- **R3 — FAQPage JSON-LD breakout.** Inline `<script type="application/ld+json">`
  with an unescaped `</` inside an Answer string can break the HTML
  parser out of the `<script>` element — the `#2609` / `jsonLdSafe`
  class failure mode. **Mitigation:** AC10 hard-asserts the `<\/`
  in-string escape and manual JSON parse; copywriter prompt flags this
  explicitly. The block's outer `<script>` open/close tags are literal
  and unchanged.
- **R4 — FAQ + stack word budget.** Caps per the copywriter prompt
  (enforced in Phase 3): **FAQ** at 150 words/Q×Q+A pair × 10 = 1,500
  words; **§5 stack-by-function** at 100 words × 7 rows = 700 words.
  Remaining budget for §1 Definition + §2 Medvi + §3 Amodei + §4 What
  makes it possible + §6 Human + §7 Soleur fits + §8 Counterpoint + §10
  CTA = **1,300 words floor / 2,300 words ceiling**. That averages
  ~160-290 words per section, with §8 Counterpoint anchored at ≥300
  words (brand-guide trust-scaffolding) and §1 Definition fixed under
  100 words. Math: `1,500 + 700 + 1,300 = 3,500` (floor) and
  `1,500 + 700 + 2,300 = 4,500` (ceiling) — matches the 3,500-4,500
  target exactly.
- **R5 — Pillar-series include edit to `blog-post.njk` regressing
  BlogPosting JSON-LD.** **Mitigation:** Phase 1 step 3 specifies
  inserting **below** the `{% block extraHead %}` close and the entire
  JSON-LD `<script>` block (i.e., inside the `<article>` body, not in
  `<head>`). Re-read the file after the edit (rule
  `hr-always-read-a-file-before-editing-it`).
- **R6 — `gemini-imagegen` silent drop.** Rule
  `cq-pencil-mcp-silent-drop-diagnosis-checklist` class — a 0-byte PNG
  is possible. **Mitigation:** Phase 2 post-generation `stat -c %s` and
  `identify` probe.
- **R7 — Aggregate numeric target (word count) contract.** Per rule
  `cq-*` class (Alternative-Approaches `aggregate numeric target` sharp
  edge from plan skill): the plan states 3,500-4,500 words and the
  per-section budget (R4) sums to ~3,500-4,500. Consistency confirmed.

## Research Insights

**CLI/tool tokens verified** (rule `cq-docs-cli-verification`):

- `npx markdownlint-cli2 --fix <path>` — verified in `cq-always-run-npx-markdownlint-cli2-fix-on` rule + repeated usage across plans in `knowledge-base/project/plans/`.
- `npm run docs:build` inside `plugins/soleur/docs/` — **corrected at deepen
  time**. The script is `docs:build`, not `build`; it resolves to
  `cd ../../../ && npx @11ty/eleventy` (config at repo root
  `eleventy.config.js`). Verified via `cat plugins/soleur/docs/package.json`.
- `identify` / `file` on PNG — POSIX + ImageMagick; pre-installed on dev env.

**Deepen-time citation spot-check (WebSearch 2026-04-22):**

- Medvi claims ($20K seed, $401M Y1, $1.8B Y2 tracking, September 2024
  launch, Matthew + Elliot Gallagher, ElevenLabs) — supported by
  PYMNTS, Inc.com Sheridan piece, therundown.ai, citybiz.co, quasa.io,
  whatstrending.com, biggo.com Finance, ca.finance.yahoo.com, and
  crevio.co. Pick any two primary sources per stat; Wealthy Tent and
  Inc.com Sheridan are the strongest "primary" and should anchor §2 of
  the pillar.
- Amodei "by 2026" prediction — already cited via
  `officechai.com/ai/the-first-one-person-billon-dollar-startup-will-be-a-reality-by-2026-anthropic-ceo-dario-amodei/`
  in the companion post (verified). Also reachable via Fortune and
  PYMNTS secondaries. Pick **two** for §3 of the pillar (Inc.com
  primary + PYMNTS or Entrepreneur secondary per brainstorm).
- Amodei quote canonical wording — "This is not a joke... you can have a
  one-person, billion-dollar company within a year or two." The
  copywriter should paraphrase rather than misquote; if quoting,
  reproduce word-for-word from the Inc.com citation.

**Institutional learnings applied:**

- `knowledge-base/project/learnings/best-practices/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md` — inline FAQPage JSON-LD must escape `</script>` and use `jsonLdSafe`-equivalent quoting (#2609 class). Deepen-time addition: the escape belongs **inside JSON string values**, not at the block terminator. The block terminator must be a literal `</script>`.
- `knowledge-base/project/learnings/best-practices/2026-04-17-review-backlog-net-positive-filing.md` — checked code-review overlap (Phase 1.7.5 of plan skill) and recorded zero hits; no fold-in / defer actions needed.
- AGENTS.md `cq-prose-issue-ref-line-start` — `#NNNN` never starts a line. The pillar mentions #2712 only in the PR body (via `Closes #2712` reminder), never in the markdown body, so the rule is satisfied.

**Existing code references:**

- `plugins/soleur/docs/_includes/blog-post.njk` — BlogPosting JSON-LD + `jsonLdSafe` filter (existing pattern to preserve). Include call lands inside `{% block content %}` above `<section class="content">`.
- `plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md` — companion post, reference for tone and link style. Already cites officechai.com/Amodei, fortune.com/Altman, techcrunch.com, solofounders.com/Carta, fortune.com/Kuo Zhang — copywriter extends, does not duplicate.
- `plugins/soleur/docs/images/blog/og-one-person-billion-dollar-company.png` — OG visual family anchor for Phase 2.
- `plugins/soleur/docs/_data/site.json` — existing `_data/` file pattern for the new `pillars.js`. Site name ("Soleur"), URL (`https://soleur.ai`), and author metadata all keyed off this file — no edits required.
- `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-billion-dollar-solo-founder-pillar/eleventy.config.js` — root-level Eleventy config, registers `jsonLdSafe` filter. Not edited by this PR.

**Institutional learnings applied:**

- `knowledge-base/project/learnings/best-practices/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md` — inline FAQPage JSON-LD must escape `</script>` and use `jsonLdSafe`-equivalent quoting (#2609 class).
- `knowledge-base/project/learnings/best-practices/2026-04-17-review-backlog-net-positive-filing.md` — checked code-review overlap (Phase 1.7.5 of plan skill) and recorded zero hits; no fold-in / defer actions needed.

**Existing code references:**

- `plugins/soleur/docs/_includes/blog-post.njk` — BlogPosting JSON-LD + `jsonLdSafe` filter (existing pattern to preserve).
- `plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md` — companion post, reference for tone and link style.
- `plugins/soleur/docs/images/blog/og-one-person-billion-dollar-company.png` — OG visual family anchor for Phase 2.
- `plugins/soleur/docs/_data/site.json` — existing `_data/` file pattern for the new `pillars.js`.

## Domain Review

**Domains relevant:** Marketing, Product (advisory — UI impact limited to a small server-rendered aside + a data file; no new interactive surfaces or pages).

### Marketing

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** CMO assessment from brainstorm: SERP leaders are media
publishers; Soleur's brand positioning literally matches the thesis;
once-in-a-category SERP window. Plan honors the content plan's locked
outline (§432), enforces the dual-rubric AEO gate, and delegates drafting
to the `copywriter` agent (brand-voice compliance) with `fact-checker`
(citation integrity) and `seo-aeo-analyst` (AEO scoring). All three
specialists recommended by the brainstorm handoff are invoked in Phase 3
and Phase 5.

**Brainstorm-recommended specialists:** copywriter (Phase 3), fact-checker
(Phase 5.3), seo-aeo-analyst (Phase 5.4), gemini-imagegen skill (Phase 2).
All invoked — none skipped.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (ADVISORY tier, pipeline context — per plan skill
rules ADVISORY in pipeline auto-accepts)
**Skipped specialists:** ux-design-lead (ADVISORY tier; no new interactive
surface; the pillar-series aside is a small server-rendered block styled
via existing `css/style.css` conventions), spec-flow-analyzer (no multi-step
user flow)
**Pencil available:** N/A

#### Findings

- New user-facing surface = a 3-line server-rendered `<aside>`. Styled via
  existing `style.css` patterns. No dedicated wireframe required.
- Content review is covered by the `copywriter` agent invocation (brand
  voice compliance) — per Product/UX Gate Content Review Gate in plan
  skill §2.5, the recommendation satisfies the gate.

## Handoff Summary

Execution order (single session feasible):

1. Phase 1 scaffold — small code delta; commit and run Eleventy build.
2. Phase 2 OG image generation via `gemini-imagegen`.
3. Phase 3 copywriter draft — the bulk of the work; single `copywriter`
   agent invocation with the Phase 3 prompt contract.
4. Phase 4 companion-post link-up — ~5-line edit.
5. Phase 5 verify + score + fix + ship.

All artifacts land in a single PR (#2811). No database changes, no
infrastructure, no Terraform, no migrations. `compound` before commit per
rule `wg-before-every-commit-run-compound-skill`. `/ship` handles commit,
push, review gate, and merge.
