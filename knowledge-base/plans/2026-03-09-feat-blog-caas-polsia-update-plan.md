---
title: Update CaaS Blog Post for Competitive Landscape Changes
type: feat
date: 2026-03-09
---

# Update CaaS Blog Post for Competitive Landscape Changes

Surgical edits to `plugins/soleur/docs/blog/what-is-company-as-a-service.md` addressing positioning gaps revealed by the Polsia competitive intelligence update. No competitor names, no structural changes, no new sections.

## Acceptance Criteria

- [ ] **FR1: Intro "first" claim softened** (line 13) — reword "the first platform built on this model" to remove chronological claim. Preserve the sentence's role as an intro to Soleur.
- [ ] **FR2: FAQ answer updated** (line 159) — change "Soleur is the first company-as-a-service platform" to use "a pioneering" framing. Update both the HTML `<details>` answer AND the JSON-LD `acceptedAnswer` text (line 205).
- [ ] **FR3: Philosophical split added** — insert 1-2 sentences after the "How Company-as-a-Service Works" intro paragraph (after line 33) distinguishing autonomous CaaS from founder-in-the-loop CaaS. Frame as a category observation, not a competitive callout. No competitor names.
- [ ] **FR4: Category validation acknowledged** — insert 1-2 sentences in "The Future of Company-as-a-Service" section, after the WhatsApp/Instagram precedent paragraph (after line 122) and before the closing rhetorical paragraph. Note that multiple platforms now building on CaaS validates the category thesis.
- [ ] **FR5: Comparison table updated** (line 66) — modify the CaaS "Provides" column to hint at philosophical variants. Keep it terse to match other rows. Example: "A full AI organization — autonomous or founder-directed"
- [ ] **FR6: FAQ question updated** (lines 157 + 202) — change "What is the first CaaS platform?" to match the softened answer. Both the HTML `<summary>` tag and JSON-LD `name` field must change in sync. Suggested: "What CaaS platform should I try?"
- [ ] **TR1: Frontmatter untouched** — do not modify title, description, date, or tags
- [ ] **TR2: No naked numbers** — any new factual claims must be verifiable without cited sources (since no competitor names, new sentences should be observational, not statistical)
- [ ] **TR3: JSON-LD synced** — every change to FAQ HTML text is mirrored in the JSON-LD `<script>` block. Maintain existing pattern: JSON-LD is plain-text simplified version of HTML answer.
- [ ] **TR4: Keyword density preserved** — current baseline is ~20 mentions of "company-as-a-service" in ~2,400 words (~0.83%). Do not significantly change this ratio. Count after edits.

## Test Scenarios

- Given the updated article, when a reader searches for "What is company-as-a-service", then no sentence claims Soleur is the "first" or "only" CaaS platform.
- Given the FAQ section, when rendered as a rich snippet via JSON-LD, then the question text and answer text are semantically consistent (no Q asking "first" while A says "pioneering").
- Given the comparison table, when a reader scans the CaaS row, then they understand CaaS has philosophical variants without needing to read the full article.
- Given the Future section, when a reader finishes the article, then they come away believing CaaS is a validated category with multiple participants, not a single company's marketing term.
- Given the Eleventy build, when `npx @11ty/eleventy --input=plugins/soleur/docs` runs, then the article builds without template errors.

## Context

**File:** `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
**Single file edit.** All changes are in one markdown file.

**Constraints from brainstorm:**
- No competitor names (Polsia, SoloCEO, Tanka) in article body
- No new FAQ entries — philosophical split covered in article body only
- No new H2/H3 headings or structural changes
- Approach: "Minimal insertion, maximum signal"

**SpecFlow findings incorporated:**
- FAQ question text (lines 157, 202) must change alongside the answer — added as FR6
- TR4 corrected from wrong baseline (0.3-0.4%) to actual baseline (~0.83%)
- Line 124 ("who defines the category") left as-is — aspirational framing, not exclusionary
- JSON-LD and HTML FAQ text diverge intentionally (plain text vs. markdown) — maintain existing pattern

## MVP

### `plugins/soleur/docs/blog/what-is-company-as-a-service.md`

**FR1 (line 13):** Replace intro sentence's "first" claim.

```markdown
<!-- Before -->
[Soleur]({{ site.url }}) is the first platform built on this model.

<!-- After (suggested) -->
[Soleur]({{ site.url }}) is built on this model.
```

**FR3 (after line 33):** Add philosophical split observation.

```markdown
<!-- Insert after "Each pillar addresses a different failure mode..." paragraph -->
Not all CaaS platforms make the same trade-offs. Some run fully autonomously — the AI
decides priorities, executes tasks, and reports results. Others keep the founder as
decision-maker — the AI executes, but the human sets direction. The autonomous model
optimizes for speed. The founder-in-the-loop model optimizes for judgment.
```

**FR4 (after line 122):** Add category validation.

```markdown
<!-- Insert after WhatsApp/Instagram paragraph, before "The question is not..." -->
The category is already taking shape. Multiple platforms are building on the
company-as-a-service model, each with different assumptions about how much autonomy the
AI should have. The diversity of approaches validates the thesis — this is not one
company's marketing term but an emerging infrastructure category.
```

**FR5 (line 66):** Update comparison table CaaS row.

```markdown
<!-- Before -->
| **CaaS** | A full AI organization across every department | Compounding institutional memory you own |

<!-- After -->
| **CaaS** | A full AI organization — autonomous or founder-directed | Compounding institutional memory you own |
```

**FR2 + FR6 (lines 157-159 + 202-206):** Update FAQ question and answer.

```markdown
<!-- HTML: Before -->
<summary>What is the first CaaS platform?</summary>
[Soleur]({{ site.url }}pages/getting-started.html) is the first company-as-a-service platform.

<!-- HTML: After -->
<summary>What CaaS platform should I try?</summary>
[Soleur]({{ site.url }}pages/getting-started.html) is a pioneering company-as-a-service platform.
```

```json
// JSON-LD: Before
"name": "What is the first CaaS platform?",
"text": "Soleur is the first company-as-a-service platform. ..."

// JSON-LD: After
"name": "What CaaS platform should I try?",
"text": "Soleur is a pioneering company-as-a-service platform. ..."
```

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-09-blog-caas-polsia-update-brainstorm.md`
- Spec: `knowledge-base/specs/feat-blog-caas-polsia-update/spec.md`
- Competitive intelligence: `knowledge-base/overview/competitive-intelligence.md`
- Citation verification learning: `knowledge-base/learnings/2026-03-06-blog-citation-verification-before-publish.md`
- Eleventy frontmatter learning: `knowledge-base/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md`
- Issue: #468
- Draft PR: #467
